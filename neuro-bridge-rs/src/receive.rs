use super::*;

pub(crate) struct ReceiveTask<R> {
    pub(crate) ws_read: R,
    pub(crate) inbox_path: PathBuf,
    pub(crate) pending_rx: Arc<Mutex<PendingTracker>>,
    pub(crate) shutdown_rx: Arc<AtomicBool>,
}

pub(crate) fn inbound_text(message: Message) -> Option<String> {
    match message {
        Message::Text(text) => Some(text.to_string()),
        Message::Binary(bytes) => Some(String::from_utf8_lossy(&bytes).into_owned()),
        Message::Ping(_) | Message::Pong(_) | Message::Close(_) | Message::Frame(_) => None,
    }
}

enum Inbound {
    Action(String, String),
    Notification(String),
}

fn classify_inbound(text: String) -> Option<Inbound> {
    let value = parse_json_line(&text);
    let command = value.as_ref().and_then(command_of);
    if let Some(value) = &value {
        if command == Some("action") {
            if let Some((canonical, id)) = canonical_action(value) {
                return Some(Inbound::Action(canonical, id));
            }
        } else if startup_ack_is_valid(value) {
            return Some(Inbound::Notification(value.to_string()));
        } else if speech_finished_is_valid(value) {
            return None;
        }
    }
    if command.is_some_and(|command| command.starts_with(BRIDGE_CONTROL_PREFIX)) {
        eprintln!(
            "[Warning] Dropping websocket frame claiming a bridge-internal command ({})",
            redacted_payload_detail(&text)
        );
    } else {
        eprintln!(
            "[Warning] Ignoring malformed or unknown websocket frame ({})",
            redacted_payload_detail(&text)
        );
    }
    None
}

fn admit_action(pending: &Mutex<PendingTracker>, id: &str) -> bool {
    let admitted = pending
        .lock()
        .map_or(true, |mut tracker| tracker.admit_action(id));
    if !admitted {
        eprintln!(
            "[Info] Ignoring a repeated action id ({})",
            redacted_action_id(id)
        );
    }
    admitted
}

pub(crate) fn transient(error: &anyhow::Error) -> bool {
    use std::io::ErrorKind::{Interrupted, ResourceBusy, TimedOut, WouldBlock};
    error
        .chain()
        .filter_map(|cause| cause.downcast_ref::<std::io::Error>())
        .any(|cause| {
            matches!(
                cause.kind(),
                Interrupted | ResourceBusy | TimedOut | WouldBlock
            ) || cfg!(windows) && matches!(cause.raw_os_error(), Some(32 | 33))
        })
}

async fn deliver_to_inbox(inbox_path: &Path, text: &str) -> bool {
    const MAX_APPEND_ATTEMPTS: u32 = 10;
    append_retrying(inbox_path, text, MAX_APPEND_ATTEMPTS, |attempt, e| {
        eprintln!(
            "[Error] Inbox append failed (attempt {}/{}): {}",
            attempt, MAX_APPEND_ATTEMPTS, e
        );
        transient(e)
    })
    .await
}

pub(crate) async fn append_retrying(
    path: &Path,
    line: &str,
    attempts: u32,
    retry: impl Fn(u32, &anyhow::Error) -> bool,
) -> bool {
    for attempt in 1..=attempts {
        let Err(error) = append_line(path, line).await else {
            return true;
        };
        if !retry(attempt, &error) {
            return false;
        }
        let backoff = (50u64 * 2u64.saturating_pow(attempt - 1)).min(2000);
        time::sleep(Duration::from_millis(backoff)).await;
    }
    false
}

pub(crate) async fn receive_task<R>(task: ReceiveTask<R>)
where
    R: futures_util::Stream<Item = Result<Message, tokio_tungstenite::tungstenite::Error>> + Unpin,
{
    let ReceiveTask {
        mut ws_read,
        inbox_path,
        pending_rx,
        shutdown_rx,
    } = task;
    let mut spool_budget = InboundSpoolBudget::new(Instant::now());
    while let Some(msg) = ws_read.next().await {
        let message = match msg {
            Ok(Message::Close(_)) => break,
            Ok(message) => message,
            Err(e) => {
                eprintln!("[Error] WebSocket error: {}", e);
                break;
            }
        };
        let Some(text) = inbound_text(message) else {
            continue;
        };
        if text.len() > MAX_COMMAND_BYTES {
            eprintln!(
                "[Warning] Dropping oversized websocket frame ({} bytes)",
                text.len()
            );
            continue;
        }
        let Some(inbound) = classify_inbound(text) else {
            continue;
        };
        let record = match &inbound {
            Inbound::Action(record, _) | Inbound::Notification(record) => record.as_str(),
        };
        let bytes = record.len() + 1;
        while !spool_budget.admit(bytes, Instant::now()) {
            time::sleep_until(time::Instant::from_std(spool_budget.window_end())).await;
        }
        if let Inbound::Action(_, id) = &inbound {
            if !admit_action(&pending_rx, id) {
                continue;
            }
        }
        if !deliver_to_inbox(&inbox_path, record).await {
            eprintln!(
                "[Error] Could not hand a websocket frame to the mod; closing the session ({})",
                redacted_payload_detail(record)
            );
            break;
        }
        if shutdown_rx.load(Ordering::Relaxed) {
            break;
        }
    }
}

/// If rollback fails, the next append repairs the torn tail before writing.
pub(crate) fn roll_back_append(
    file: std::fs::File,
    path: &Path,
    before: u64,
    failure: anyhow::Error,
) -> anyhow::Error {
    let rolled_back = file.set_len(before).is_ok() && file.sync_data().is_ok();
    drop(file);
    if rolled_back && before == 0 {
        let _ = std::fs::remove_file(path);
    }
    failure.context(if rolled_back {
        "inbox append rolled back"
    } else {
        "inbox append left a torn tail"
    })
}

struct OpenInbox {
    path: PathBuf,
    file: std::fs::File,
    len: u64,
}

impl OpenInbox {
    /// Terminate a torn append so the mod discards it separately from the next record.
    fn open(path: &Path) -> Result<Self> {
        use std::io::{Read, Seek};
        if let Some(parent) = path
            .parent()
            .filter(|parent| !parent.as_os_str().is_empty())
        {
            ensure_ipc_dir_secure(parent).context("verify inbox IPC directory")?;
        }
        ensure_ipc_file_secure(path).context("verify inbox IPC file")?;
        let existed = path.exists();
        let mut file = std::fs::OpenOptions::new()
            .read(true)
            .create(true)
            .append(true)
            .open(path)
            .context("open inbox")?;
        ensure_ipc_file_secure(path).context("secure inbox IPC file")?;
        if !existed {
            sync_parent_directory(path).context("sync inbox directory")?;
        }
        let mut len = file.metadata().context("stat inbox")?.len();
        if len > 0 {
            let mut last = [0u8; 1];
            file.seek(std::io::SeekFrom::Start(len - 1))?;
            file.read_exact(&mut last)?;
            if last[0] != b'\n' {
                eprintln!("[Warning] Closing a torn inbox record left by a failed append");
                file.write_all(b"\n")?;
                len += 1;
            }
        }
        Ok(Self {
            path: path.to_path_buf(),
            file,
            len,
        })
    }
}

static INBOX: std::sync::LazyLock<Arc<AsyncMutex<Option<OpenInbox>>>> =
    std::sync::LazyLock::new(|| Arc::new(AsyncMutex::new(None)));

/// Reopen the inbox each session so a replaced path cannot leave a stale handle in use.
pub(crate) async fn reopen_inbox(path: &Path) {
    let mut slot = INBOX.lock().await;
    if slot.as_ref().is_some_and(|open| open.path == path) {
        *slot = None;
    }
}

fn append_record(slot: &mut Option<OpenInbox>, path: &Path, record: &[u8]) -> Result<()> {
    let grow = record.len() as u64;
    let mut inbox = match slot.take() {
        Some(open) if open.path == path => open,
        _ => OpenInbox::open(path)?,
    };
    if inbox.len.saturating_add(grow) > MAX_INBOX_BYTES {
        inbox.file.sync_data().context("sync full inbox")?;
        drop(inbox);
        std::fs::rename(path, rotated_path(path))
            .map_err(anyhow::Error::from)
            .and_then(|()| sync_parent_directory(path))
            .context("rotate full inbox")?;
        inbox = OpenInbox::open(path)?;
        if inbox.len.saturating_add(grow) > MAX_INBOX_BYTES {
            anyhow::bail!("refusing to grow inbox beyond {} bytes", MAX_INBOX_BYTES);
        }
    }
    if let Err(error) = inbox.file.write_all(record) {
        return Err(roll_back_append(inbox.file, path, inbox.len, error.into()));
    }
    inbox.len += grow;
    *slot = Some(inbox);
    Ok(())
}

pub(crate) async fn append_line(path: &Path, line: &str) -> Result<()> {
    if line.trim().is_empty() {
        return Ok(());
    }
    if line.contains('\r') || line.contains('\n') {
        anyhow::bail!("refusing to append a line containing a newline");
    }
    if line.len() > MAX_COMMAND_BYTES {
        anyhow::bail!(
            "refusing to append a line larger than {} bytes",
            MAX_COMMAND_BYTES
        );
    }
    let mut record = Vec::with_capacity(line.len() + 1);
    record.extend_from_slice(line.as_bytes());
    record.push(b'\n');
    let path = path.to_path_buf();
    let mut slot = Arc::clone(&INBOX).lock_owned().await;
    blocking(move || append_record(&mut slot, &path, &record)).await?
}
