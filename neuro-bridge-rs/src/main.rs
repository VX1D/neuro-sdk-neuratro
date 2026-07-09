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

const MAX_CHUNK: u64 = 8 * 1024 * 1024;
const MAX_BUFFERED_LINE: usize = 64 * 1024 * 1024;

struct Tailer {
    path: PathBuf,
    pos: u64,
    buffer: String,
    discarding: bool,
}

impl Tailer {
    fn new(path: PathBuf, pos: u64) -> Self {
        Self { path, pos, buffer: String::new(), discarding: false }
    }

    async fn read_new_lines(&mut self) -> Result<Vec<(String, u64)>> {
        let meta = match fs::metadata(&self.path).await {
            Ok(m) => m,
            Err(_) => return Ok(Vec::new()),
        };
        let len = meta.len();
        if len < self.pos {
            eprintln!(
                "[Warning] Outbox shrank ({} < {}), re-reading from start",
                len, self.pos
            );
            self.pos = 0;
            self.buffer.clear();
            self.discarding = false;
        }
        if len == self.pos {
            return Ok(Vec::new());
        }

        let mut file = fs::File::open(&self.path).await.context("open outbox")?;
        file.seek(std::io::SeekFrom::Start(self.pos)).await?;
        let mut buf = Vec::new();
        file.take(MAX_CHUNK).read_to_end(&mut buf).await?;

        if buf.is_empty() {
            return Ok(Vec::new());
        }

        let (text, consumed) = match String::from_utf8(buf) {
            Ok(s) => {
                let n = s.len();
                (s, n)
            }
            Err(e) => {
                let err = e.utf8_error();
                let valid = err.valid_up_to();
                let bytes = e.into_bytes();
                let mut s = std::str::from_utf8(&bytes[..valid]).unwrap_or("").to_string();
                match err.error_len() {
                    Some(bad) => {
                        eprintln!(
                            "[Warning] Substituting {} invalid UTF-8 byte(s) in outbox stream",
                            bad
                        );
                        for _ in 0..bad {
                            s.push('?');
                        }
                        (s, valid + bad)
                    }
                    None => (s, valid),
                }
            }
        };

        self.buffer.push_str(&text);
        self.pos += consumed as u64;

        let mut lines = Vec::new();
        while let Some(idx) = self.buffer.find('\n') {
            let mut line = self.buffer[..idx].to_string();
            if line.ends_with('\r') {
                line.pop();
            }
            self.buffer.drain(..=idx);
            let end_pos = self.pos - self.buffer.len() as u64;
            if self.discarding {
                self.discarding = false;
            } else if !line.trim().is_empty() {
                lines.push((line, end_pos));
            }
        }

        if self.buffer.len() > MAX_BUFFERED_LINE {
            eprintln!(
                "[Error] Outbox line exceeded {} bytes with no newline; discarding buffered data",
                MAX_BUFFERED_LINE
            );
            self.buffer.clear();
            self.discarding = true;
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
    Ok(())
}

async fn bootstrap_messages(path: &Path) -> Result<(u64, Vec<String>)> {
    if let Ok(meta) = fs::metadata(path).await {
        if meta.len() > 100 * 1024 * 1024 {
            eprintln!("[Warning] Outbox file too large ({} bytes), skipping bootstrap", meta.len());
            return Ok((meta.len(), Vec::new()));
        }
    }

    let data = match fs::read_to_string(path).await {
        Ok(text) => text,
        Err(e) => {
            if e.kind() == std::io::ErrorKind::NotFound {
                return Ok((0, Vec::new()));
            }
            eprintln!("[Warning] Could not read outbox: {}", e);
            let pos = fs::metadata(path).await.map(|m| m.len()).unwrap_or(0);
            return Ok((pos, Vec::new()));
        }
    };

    // order matters (startup -> register -> context); startup resets register/context so a reconnect
    // never replays a prior session. force is NOT replayed: the mod re-forces itself, and replaying an
    // already-answered force would emit a duplicate action.
    let mut startup: Option<String> = None;
    let mut register: Option<String> = None;
    let mut context: Option<String> = None;
    for line in data.lines() {
        if line.trim().is_empty() {
            continue;
        }
        match command_from_line(line).as_deref() {
            Some("startup") => {
                startup = Some(line.to_string());
                register = None;
                context = None;
            }
            Some("actions/register") => register = Some(line.to_string()),
            Some("context") => context = Some(line.to_string()),
            _ => {}
        }
    }
    let mut messages = Vec::new();
    if let Some(line) = startup {
        messages.push(line);
    }
    if let Some(line) = register {
        messages.push(line);
    }
    if let Some(line) = context {
        messages.push(line);
    }
    Ok((data.len() as u64, messages))
}

#[derive(Default)]
struct BootstrapCache {
    startup: Option<String>,
    register: Option<String>,
    context: Option<String>,
}

impl BootstrapCache {
    fn observe(&mut self, line: &str) {
        if line.len() > 10 * 1024 * 1024
            || !(line.contains("\"startup\"")
                || line.contains("actions/register")
                || line.contains("\"context\""))
        {
            return;
        }
        match command_from_line(line).as_deref() {
            // startup resets register/context so a reconnect never replays a prior session's set
            Some("startup") => {
                self.startup = Some(line.to_string());
                self.register = None;
                self.context = None;
            }
            Some("actions/register") => self.register = Some(line.to_string()),
            Some("context") => self.context = Some(line.to_string()),
            _ => {}
        }
    }

    fn lines(&self) -> Vec<String> {
        self.startup
            .iter()
            .chain(self.register.iter())
            .chain(self.context.iter())
            .cloned()
            .collect()
    }
}

fn command_from_line(line: &str) -> Option<String> {
    if line.len() > 10 * 1024 * 1024 {
        eprintln!("[Warning] Skipping oversized line ({} bytes)", line.len());
        return None;
    }
    let value: Value = serde_json::from_str(line).ok()?;
    value.get("command")?.as_str().map(|s| s.to_string())
}

async fn run_session(cfg: &Config, resume: Option<u64>, cache: &mut BootstrapCache) -> Result<u64> {
    let (start_pos, bootstrap) = match resume {
        Some(pos) if !cache.lines().is_empty() => (pos, cache.lines()),
        // empty cache or fresh start: rescan outbox for the bootstrap burst; keep resume pos else scanned end
        _ => {
            let (scanned_pos, lines) = bootstrap_messages(&cfg.outbox).await?;
            for line in &lines {
                cache.observe(line);
            }
            (resume.unwrap_or(scanned_pos), lines)
        }
    };
    let (ws_stream, _) = connect_async(&cfg.ws_url).await.context("connect websocket")?;
    let (mut ws_write, mut ws_read) = ws_stream.split();

    for line in bootstrap {
        ws_write.send(Message::Text(line)).await?;
    }

    let (tx, mut rx) = mpsc::channel::<(String, u64)>(256);
    let outbox_path = cfg.outbox.clone();
    let inbox_path = cfg.inbox.clone();

    let shutdown = Arc::new(AtomicBool::new(false));
    let shutdown_tx = shutdown.clone();
    let shutdown_rx = shutdown.clone();

    let (watch_tx, mut watch_rx) = mpsc::channel::<()>(16);
    let outbox_name = outbox_path.file_name().map(|n| n.to_os_string());
    let watcher = outbox_path.parent().and_then(|parent| {
        let tx = watch_tx.clone();
        let want = outbox_name.clone();
        let mut w = notify::recommended_watcher(move |res: Result<notify::Event, notify::Error>| {
            if let Ok(ev) = res {
                let hit = match &want {
                    Some(name) => ev.paths.iter().any(|p| p.file_name() == Some(name.as_os_str())),
                    None => true,
                };
                if hit {
                    tx.try_send(()).ok();
                }
            }
        }).ok()?;
        w.watch(parent, RecursiveMode::NonRecursive).ok()?;
        Some(w)
    });
    let fallback_ms: u64 = if watcher.is_some() { 1000 } else { 150 };
    if watcher.is_none() {
        eprintln!("[Info] File watcher unavailable, falling back to {}ms polling", fallback_ms);
    }

    let mut tail_pos: u64 = start_pos;
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
                    for item in lines {
                        if tx.send(item).await.is_err() {
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
            match msg {
                Ok(Message::Text(text)) => {
                    // the action already left the ws: a failed append can't be recovered by reconnect,
                    // so retry hard (backoff capped near the mod's ~12s stall watchdog) instead of dropping
                    const MAX_APPEND_ATTEMPTS: u32 = 10;
                    let mut delivered = false;
                    for attempt in 1..=MAX_APPEND_ATTEMPTS {
                        match append_line(&inbox_path, &text).await {
                            Ok(()) => {
                                delivered = true;
                                break;
                            }
                            Err(e) => {
                                eprintln!(
                                    "[Error] Inbox append failed (attempt {}/{}): {}",
                                    attempt, MAX_APPEND_ATTEMPTS, e
                                );
                                let backoff = (50u64 * 2u64.saturating_pow(attempt - 1)).min(2000);
                                time::sleep(Duration::from_millis(backoff)).await;
                            }
                        }
                    }
                    if !delivered {
                        eprintln!(
                            "[Error] DROPPING inbox message after {} attempts (mod stall watchdog will re-force): {}",
                            MAX_APPEND_ATTEMPTS,
                            text.chars().take(512).collect::<String>()
                        );
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
            // check shutdown AFTER handling: a command received during teardown must still reach the inbox
            if shutdown_rx.load(Ordering::Relaxed) {
                break;
            }
        }
    });

    loop {
        match time::timeout(Duration::from_secs(1), rx.recv()).await {
            Ok(Some((line, pos))) => {
                cache.observe(&line);
                if ws_write.feed(Message::Text(line)).await.is_err() {
                    break;
                }
                if ws_write.flush().await.is_err() {
                    break;
                }
                tail_pos = pos;
            }
            Ok(None) => break,
            Err(_) => {
                if tx_task.is_finished() || rx_task.is_finished() {
                    break;
                }
                // idle flush: pushes an auto-queued Pong out (no outbox line triggers a flush), else the server drops the idle connection
                if ws_write.flush().await.is_err() {
                    break;
                }
            }
        }
    }

    shutdown.store(true, Ordering::Relaxed);

    let _ = ws_write.close().await;
    tx_task.abort();
    rx_task.abort();
    let _ = tx_task.await;
    let _ = rx_task.await;

    Ok(tail_pos)
}

#[tokio::main]
async fn main() -> Result<()> {
    let cfg = Config::from_env();
    if let Some(parent) = cfg.outbox.parent() {
        if let Err(e) = fs::create_dir_all(parent).await {
            eprintln!(
                "[Error] Could not create IPC dir {}: {}",
                parent.display(),
                e
            );
        }
    }
    eprintln!(
        "bridge: ws_url={} ipc_dir={}",
        cfg.ws_url,
        cfg.outbox
            .parent()
            .map(|p| p.display().to_string())
            .unwrap_or_else(|| "<unknown>".to_string())
    );
    let mut resume: Option<u64> = None;
    let mut backoff_secs: u64 = 1;
    let mut bootstrap_cache = BootstrapCache::default();
    loop {
        let res = run_session(&cfg, resume, &mut bootstrap_cache).await;
        match res {
            Ok(pos) => {
                resume = Some(pos);
                backoff_secs = 1;
                eprintln!("bridge: session ended, reconnecting in 1s (resume@{pos})");
            }
            Err(err) => {
                eprintln!("bridge error: {err} (retry in {backoff_secs}s)");
            }
        }
        time::sleep(Duration::from_secs(backoff_secs)).await;
        backoff_secs = (backoff_secs * 2).min(30);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn command_from_line_extracts_command() {
        assert_eq!(command_from_line(r#"{"command":"startup"}"#).as_deref(), Some("startup"));
        assert_eq!(command_from_line(r#"{"command":"context","data":{}}"#).as_deref(), Some("context"));
        assert_eq!(command_from_line("not json"), None);
        assert_eq!(command_from_line(r#"{"no":"command"}"#), None);
    }

    #[test]
    fn bootstrap_cache_orders_startup_register_context() {
        let mut c = BootstrapCache::default();
        c.observe(r#"{"command":"startup","session_id":1}"#);
        c.observe(r#"{"command":"actions/register","data":{"actions":[]}}"#);
        c.observe(r#"{"command":"context","data":{"message":"hi"}}"#);
        let lines = c.lines();
        assert_eq!(lines.len(), 3);
        assert!(lines[0].contains("startup"));
        assert!(lines[1].contains("actions/register"));
        assert!(lines[2].contains("context"));
    }

    #[test]
    fn bootstrap_cache_resets_on_new_startup() {
        let mut c = BootstrapCache::default();
        c.observe(r#"{"command":"startup","session_id":1}"#);
        c.observe(r#"{"command":"actions/register","data":{"actions":["stale_action"]}}"#);
        c.observe(r#"{"command":"context","data":{"message":"stale"}}"#);
        c.observe(r#"{"command":"startup","session_id":2}"#);
        c.observe(r#"{"command":"actions/register","data":{"actions":["fresh_action"]}}"#);
        let lines = c.lines();
        assert_eq!(lines.len(), 2);
        assert!(lines[0].contains("startup"));
        assert!(lines[1].contains("fresh_action"));
        assert!(
            !lines.iter().any(|l| l.contains("stale")),
            "stale register/context leaked across the startup reset"
        );
    }

    #[test]
    fn bootstrap_cache_latest_wins_within_session() {
        let mut c = BootstrapCache::default();
        c.observe(r#"{"command":"actions/register","data":{"actions":["first"]}}"#);
        c.observe(r#"{"command":"actions/register","data":{"actions":["second"]}}"#);
        let lines = c.lines();
        assert_eq!(lines.len(), 1);
        assert!(lines[0].contains("second"));
        assert!(!lines[0].contains("first"));
    }

    #[test]
    fn bootstrap_cache_ignores_unrelated_lines() {
        let mut c = BootstrapCache::default();
        c.observe(r#"{"command":"action","data":{"id":"x","name":"help"}}"#);
        c.observe(r#"{"command":"action/result","data":{"id":"x","success":true}}"#);
        assert!(c.lines().is_empty(), "only startup/register/context should be cached");
    }
}
