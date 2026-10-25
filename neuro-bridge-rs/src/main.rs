use anyhow::{anyhow, Context, Result};
use futures_util::{SinkExt, StreamExt};
use notify::{RecursiveMode, Watcher};
use serde_json::{json, Value};
use std::collections::HashSet;
use std::env;
use std::io::Write as _;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, AtomicU64, AtomicUsize, Ordering};
use std::sync::Arc;
use std::sync::Mutex;
use std::time::Instant;
use tokio::fs;
use tokio::sync::{mpsc, Mutex as AsyncMutex};
use tokio::time::{self, Duration};
use tokio_tungstenite::connect_async_tls_with_config;
use tokio_tungstenite::tungstenite::protocol::WebSocketConfig;
use tokio_tungstenite::tungstenite::Message;

mod bootstrap;
mod config;
mod controls;
mod cursor;
mod lease;
mod liveness;
mod obligations;
mod queue;
mod receive;
mod session;
mod socket;
mod tailer;
mod wire;

pub(crate) use bootstrap::*;
pub(crate) use config::*;
pub(crate) use controls::*;
pub(crate) use cursor::*;
pub(crate) use lease::*;
pub(crate) use liveness::*;
pub(crate) use obligations::*;
pub(crate) use queue::*;
pub(crate) use receive::*;
pub(crate) use session::*;
pub(crate) use socket::*;
pub(crate) use tailer::*;
pub(crate) use wire::*;

#[tokio::main(flavor = "multi_thread", worker_threads = 2)]
async fn main() -> Result<()> {
    let cfg = Config::from_env();
    let ipc_dir = cfg
        .outbox
        .parent()
        .context("configured IPC outbox has no parent directory")?;
    if let Err(e) = create_ipc_dir(ipc_dir) {
        eprintln!(
            "[Error] Could not create IPC dir {}: {}",
            ipc_dir.display(),
            e
        );
        return Err(e.into());
    }
    #[cfg(unix)]
    let shutdown = {
        use tokio::signal::unix::{signal, SignalKind};
        let mut term = signal(SignalKind::terminate()).context("install SIGTERM handler")?;
        let mut interrupt = signal(SignalKind::interrupt()).context("install SIGINT handler")?;
        async move {
            tokio::select! {
                _ = term.recv() => {}
                _ = interrupt.recv() => {}
            }
        }
    };
    #[cfg(windows)]
    let shutdown = {
        let mut ctrl_c = tokio::signal::windows::ctrl_c().context("install Ctrl-C handler")?;
        async move {
            ctrl_c.recv().await;
        }
    };
    tokio::pin!(shutdown);
    let _lease = InstanceLease::acquire(ipc_dir)?;
    eprintln!(
        "bridge: ws_url={} ipc_dir={}",
        redact_ws_url(&cfg.ws_url),
        ipc_dir.display()
    );
    let pending_tracker = Arc::new(Mutex::new(PendingTracker::default()));
    let (stop_tx, stop_rx) = tokio::sync::watch::channel(false);
    let serve = async {
        loop {
            let mut stop = stop_rx.clone();
            match run_session(&cfg, pending_tracker.clone(), stop.clone()).await {
                Ok(mark) => eprintln!(
                    "bridge: session ended, reconnecting in {}s (resume@{})",
                    RECONNECT_INTERVAL_SECS, mark.pos
                ),
                Err(err) => eprintln!("bridge error: {err} (retry in {RECONNECT_INTERVAL_SECS}s)"),
            }
            if *stop.borrow() {
                break;
            }
            tokio::select! {
                _ = time::sleep(Duration::from_secs(RECONNECT_INTERVAL_SECS)) => {}
                _ = stop_requested(&mut stop) => break,
            }
        }
    };
    tokio::pin!(serve);
    tokio::select! {
        _ = &mut serve => {}
        _ = &mut shutdown => {
            eprintln!("bridge: shutdown signal, unregistering and releasing the instance lease");
            let _ = stop_tx.send(true);
            let _ = time::timeout(Duration::from_secs(SHUTDOWN_GRACE_SECS), &mut serve).await;
        }
    }
    Ok(())
}

const SHUTDOWN_GRACE_SECS: u64 = WS_WRITE_TIMEOUT_SECS * 2 + WS_CLOSE_TIMEOUT_SECS;

#[cfg(test)]
mod tests;
