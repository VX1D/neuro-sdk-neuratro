use anyhow::{Context, Result};
use futures_util::{SinkExt, StreamExt};
use serde_json::Value;
use std::env;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};
use tokio::fs;
use tokio::io::{AsyncReadExt, AsyncSeekExt, AsyncWriteExt};
use tokio::sync::mpsc;
use tokio::time::{self, Duration};
use tokio_tungstenite::connect_async;
use tokio_tungstenite::tungstenite::Message;
use notify::{Watcher, RecursiveMode};

struct Config {
    ws_url: String,
    outbox: PathBuf,
    inbox: PathBuf,
}

impl Config {
    fn from_env() -> Self {
        let ws_url =
            env::var("NEURO_SDK_WS_URL").unwrap_or_else(|_| "ws://127.0.0.1:8000".to_string());
        let ipc_dir = resolve_ipc_dir();
        let outbox = ipc_dir.join("neuro_outbox.jsonl");
        let inbox = ipc_dir.join("neuro_inbox.jsonl");
        Self { ws_url, outbox, inbox }
    }
}

fn resolve_ipc_dir() -> PathBuf {
    if let Ok(dir) = env::var("NEURO_IPC_DIR") {
        if !dir.trim().is_empty() {
            return PathBuf::from(dir);
        }
    }
    if let Ok(appdata) = env::var("APPDATA") {
        let appdata_path = PathBuf::from(&appdata);
        let candidate = appdata_path.join("Balatro").join("neuro-ipc");
        if candidate.exists() {
            return candidate;
        }
        let candidate = appdata_path
            .join("Balatro")
            .join("Mods")
            .join("neuro-game")
            .join("ipc");
        if candidate.exists() {
            return candidate;
        }
    }
    if let Ok(cwd) = env::current_dir() {
        let candidate = cwd.join("ipc");
        if candidate.exists() {
            return candidate;
        }
    }
    PathBuf::from("ipc")
}

struct Tailer {
    path: PathBuf,
    pos: u64,
    buffer: String,
}

impl Tailer {
    fn new(path: PathBuf, pos: u64) -> Self {
        Self { path, pos, buffer: String::new() }
    }

    async fn read_new_lines(&mut self) -> Result<Vec<String>> {
        let meta = match fs::metadata(&self.path).await {
            Ok(m) => m,
            Err(_) => return Ok(Vec::new()),
        };
        let len = meta.len();
        if len < self.pos {
            self.pos = 0;
            self.buffer.clear();
        }
        if len == self.pos {
            if self.buffer.len() > 1024 * 1024 {
                let line = std::mem::take(&mut self.buffer);
                return Ok(vec![line]);
            }
            return Ok(Vec::new());
        }

        let mut file = fs::File::open(&self.path).await.context("open outbox")?;
        file.seek(std::io::SeekFrom::Start(self.pos)).await?;
        let mut buf = Vec::new();
        file.read_to_end(&mut buf).await?;

        let bytes_read = buf.len();

        if buf.is_empty() {
            return Ok(Vec::new());
        }

        let text = match String::from_utf8(buf) {
            Ok(s) => s,
            Err(e) => {
                eprintln!("[Warning] Invalid UTF-8 in outbox at position {}: {}", self.pos, e);
                String::from_utf8_lossy(e.as_bytes()).to_string()
            }
        };

        self.buffer.push_str(&text);
        self.pos += bytes_read as u64;

        let mut lines = Vec::new();
        while let Some(idx) = self.buffer.find('\n') {
            let mut line = self.buffer[..idx].to_string();
            if line.ends_with('\r') {
                line.pop();
            }
            if !line.trim().is_empty() {
                lines.push(line);
            }
            self.buffer.drain(..=idx);
        }

        if self.buffer.len() > 1024 * 1024 {
            let line = std::mem::take(&mut self.buffer);
            if !line.trim().is_empty() {
                lines.push(line);
            }
        }

        Ok(lines)
    }
}

async fn append_line(path: &Path, line: &str) -> Result<()> {
    if line.trim().is_empty() {
        return Ok(());
    }
    let mut file = fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(path)
        .await
        .context("open inbox")?;
    let mut buf = line.to_string();
    buf.push('\n');
    file.write_all(buf.as_bytes()).await?;
    file.sync_all().await.context("fsync inbox")?;
    Ok(())
}

async fn bootstrap_messages(path: &Path) -> Result<(u64, Vec<String>)> {
    let data = match fs::read_to_string(path).await {
        Ok(text) => text,
        Err(e) => {
            if e.kind() == std::io::ErrorKind::NotFound {
                return Ok((0, Vec::new()));
            }
            eprintln!("[Warning] Could not read outbox: {}", e);
            return Ok((0, Vec::new()));
        }
    };

    let metadata = fs::metadata(path).await.ok();
    if let Some(meta) = metadata {
        if meta.len() > 100 * 1024 * 1024 {
            eprintln!("[Warning] Outbox file too large ({} bytes), skipping bootstrap", meta.len());
            return Ok((meta.len(), Vec::new()));
        }
    }

    let mut last_startup: Option<String> = None;
    let mut last_register: Option<String> = None;
    for line in data.lines() {
        if line.trim().is_empty() {
            continue;
        }
        if let Some(cmd) = command_from_line(line) {
            if cmd == "startup" {
                last_startup = Some(line.to_string());
            } else if cmd == "actions/register" {
                last_register = Some(line.to_string());
            }
        }
    }
    let mut messages = Vec::new();
    if let Some(line) = last_startup {
        messages.push(line);
    }
    if let Some(line) = last_register {
        messages.push(line);
    }
    Ok((data.len() as u64, messages))
}

fn command_from_line(line: &str) -> Option<String> {
    if line.len() > 10 * 1024 * 1024 {
        eprintln!("[Warning] Skipping oversized line ({} bytes)", line.len());
        return None;
    }
    let value: Value = serde_json::from_str(line).ok()?;
    value.get("command")?.as_str().map(|s| s.to_string())
}

async fn run_session(cfg: &Config) -> Result<()> {
    let (start_pos, bootstrap) = bootstrap_messages(&cfg.outbox).await?;
    let (ws_stream, _) = connect_async(&cfg.ws_url).await.context("connect websocket")?;
    let (mut ws_write, mut ws_read) = ws_stream.split();

    for line in bootstrap {
        ws_write.send(Message::Text(line)).await?;
    }

    let (tx, mut rx) = mpsc::channel::<String>(256);
    let outbox_path = cfg.outbox.clone();
    let inbox_path = cfg.inbox.clone();

    let shutdown = Arc::new(AtomicBool::new(false));
    let shutdown_tx = shutdown.clone();
    let shutdown_rx = shutdown.clone();

    let (watch_tx, mut watch_rx) = tokio::sync::mpsc::channel::<()>(16);
    let watcher = outbox_path.parent().and_then(|parent| {
        let tx = watch_tx.clone();
        let mut w = notify::recommended_watcher(move |res: Result<notify::Event, notify::Error>| {
            if res.is_ok() {
                tx.try_send(()).ok();
            }
        }).ok()?;
        w.watch(parent, RecursiveMode::NonRecursive).ok()?;
        Some(w)
    });
    let fallback_ms: u64 = if watcher.is_some() { 500 } else { 20 };
    if watcher.is_none() {
        eprintln!("[Info] File watcher unavailable, falling back to {}ms polling", fallback_ms);
    }

    let mut tailer = Tailer::new(outbox_path, start_pos);
    let tx_task = tokio::spawn(async move {
        let _watcher = watcher;
        let _watch_keep = watch_tx;
        loop {
            tokio::select! {
                _ = watch_rx.recv() => {}
                _ = time::sleep(Duration::from_millis(fallback_ms)) => {}
            }

            if shutdown_tx.load(Ordering::Relaxed) {
                break;
            }

            match tailer.read_new_lines().await {
                Ok(lines) => {
                    for line in lines {
                        if tx.send(line).await.is_err() {
                            return;
                        }
                    }
                }
                Err(e) => {
                    eprintln!("[Error] Failed to read outbox: {}", e);
                }
            }
        }
    });

    let rx_task = tokio::spawn(async move {
        while let Some(msg) = ws_read.next().await {
            if shutdown_rx.load(Ordering::Relaxed) {
                break;
            }

            match msg {
                Ok(Message::Text(text)) => {
                    if let Err(e) = append_line(&inbox_path, &text).await {
                        eprintln!("[Error] Failed to append to inbox: {}", e);
                    }
                }
                Ok(Message::Binary(_)) => {}
                Ok(Message::Close(_)) => break,
                Ok(Message::Ping(_data)) => {
                }
                Ok(Message::Pong(_)) => {}
                Ok(Message::Frame(_)) => {}
                Err(e) => {
                    eprintln!("[Error] WebSocket error: {}", e);
                    break;
                }
            }
        }
    });

    loop {
        match time::timeout(Duration::from_secs(1), rx.recv()).await {
            Ok(Some(line)) => {
                if ws_write.send(Message::Text(line)).await.is_err() {
                    break;
                }
            }
            Ok(None) => break,
            Err(_) => {
                if tx_task.is_finished() || rx_task.is_finished() {
                    break;
                }
            }
        }
    }

    shutdown.store(true, Ordering::Relaxed);

    let _ = time::timeout(Duration::from_secs(5), tx_task).await;
    let _ = time::timeout(Duration::from_secs(5), rx_task).await;

    let _ = ws_write.close().await;

    Ok(())
}

#[tokio::main]
async fn main() -> Result<()> {
    let cfg = Config::from_env();
    if let Some(parent) = cfg.outbox.parent() {
        fs::create_dir_all(parent).await.ok();
    }
    eprintln!(
        "bridge: ws_url={} ipc_dir={}",
        cfg.ws_url,
        cfg.outbox
            .parent()
            .map(|p| p.display().to_string())
            .unwrap_or_else(|| "<unknown>".to_string())
    );
    let mut backoff_secs: u64 = 1;
    loop {
        let res = run_session(&cfg).await;
        match res {
            Ok(()) => {
                backoff_secs = 1;
                eprintln!("bridge: session ended, reconnecting in 1s");
            }
            Err(err) => {
                eprintln!("bridge error: {err} (retry in {backoff_secs}s)");
            }
        }
        time::sleep(Duration::from_secs(backoff_secs)).await;
        backoff_secs = (backoff_secs * 2).min(30);
    }
}
