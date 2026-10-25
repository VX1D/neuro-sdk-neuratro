use super::*;

pub(crate) type WsStream =
    tokio_tungstenite::WebSocketStream<tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>>;
pub(crate) type WsWrite = futures_util::stream::SplitSink<WsStream, Message>;

struct RecordState {
    forward: bool,
    startup_forwarded: bool,
    result_id: Option<String>,
    frame: Option<WireFrame>,
}

fn classify_outbox_command(
    record: &ParsedLine,
    line: &str,
    pending: &Mutex<PendingTracker>,
    bound_game: &mut Option<String>,
) -> RecordState {
    let mut state = RecordState {
        forward: true,
        startup_forwarded: false,
        result_id: None,
        frame: None,
    };
    let matches_bound = || {
        record
            .game()
            .is_some_and(|game| bound_game.as_deref() == Some(game))
    };
    match record.command() {
        Some("startup") => {
            let frame = record.wire_frame(line);
            let game = frame.as_ref().and_then(WireFrame::game).map(str::to_string);
            match game {
                Some(game) if bound_game.as_ref().is_none_or(|bound| *bound == game) => {
                    pending.lock().unwrap().bind_game(&game);
                    *bound_game = Some(game);
                    state.startup_forwarded = true;
                    state.frame = frame;
                }
                _ => {
                    eprintln!("[Warning] Dropping startup with an invalid or different game");
                    state.forward = false;
                }
            }
        }
        Some(command) if command.starts_with(BRIDGE_CONTROL_PREFIX) => state.forward = false,
        Some("action/result") => {
            if !matches_bound() {
                eprintln!("[Warning] Dropping an action/result for an unbound or different game");
                state.forward = false;
            } else if let Some(id) = record.result_id() {
                let pending = pending.lock().unwrap();
                if pending.should_suppress_result(&id) {
                    eprintln!(
                        "[Warning] Dropping a second action/result for one id ({})",
                        redacted_action_id(&id)
                    );
                    state.forward = false;
                } else if pending.is_stale_result(&id) {
                    eprintln!(
                        "[Info] Dropping an action/result for an action of an earlier connection ({})",
                        redacted_action_id(&id)
                    );
                    state.forward = false;
                } else {
                    state.result_id = Some(id);
                }
            } else {
                eprintln!("[Warning] Dropping action/result with an invalid or over-bound id");
                state.forward = false;
            }
        }
        command => {
            if !matches_bound() {
                if command.is_none() {
                    eprintln!(
                        "[Warning] Dropping an outbox record that could not be parsed ({})",
                        redacted_payload_detail(line)
                    );
                } else {
                    eprintln!(
                        "[Warning] Dropping an outbox record for an unbound or different game"
                    );
                }
                state.forward = false;
            }
        }
    }
    state
}

pub(crate) fn replayed(
    pending: &Mutex<PendingTracker>,
    command: Option<&str>,
    mark: QueueMark,
) -> bool {
    let replayed = !pending.lock().unwrap().first_send_at(command, mark.resume);
    if replayed {
        eprintln!(
            "[Info] Dropping an already sent {} at outbox offset {}",
            command.unwrap_or_default(),
            mark.start
        );
    }
    replayed
}

pub(crate) fn note_registration_frame(registered: &mut Vec<String>, value: &Value) {
    let names_under = |key: &str| -> Vec<String> {
        value
            .get("data")
            .and_then(|data| data.get(key))
            .and_then(Value::as_array)
            .map(|items| {
                items
                    .iter()
                    .filter_map(|item| item.get("name").or(Some(item)))
                    .filter_map(Value::as_str)
                    .map(str::to_string)
                    .collect()
            })
            .unwrap_or_default()
    };
    match value.get("command").and_then(Value::as_str) {
        Some("startup") => registered.clear(),
        Some("actions/register") => {
            let added = names_under("actions");
            registered.retain(|name| !added.contains(name));
            registered.extend(added);
        }
        Some("actions/unregister") => {
            let removed = names_under("action_names");
            registered.retain(|name| !removed.contains(name));
        }
        _ => {}
    }
}

pub(crate) fn quit_unregister_frame(game: &str, registered: &[String]) -> Option<String> {
    let frame = json!({
        "command": "actions/unregister",
        "game": game,
        "data": { "action_names": registered }
    });
    let text = frame.to_string();
    sanitize_value(Some(frame), &text).map(|frame| frame.text)
}

async fn open_transport_session(cfg: &Config) -> Result<u64> {
    reopen_inbox(&cfg.inbox).await;
    let inbox = cfg.inbox.clone();
    let transport_session = blocking(move || next_transport_session(&inbox)).await??;
    if !request_action_reregistration(&cfg.inbox, transport_session).await {
        return Err(anyhow!(
            "could not append action reregistration request after {} attempts",
            MAX_REREGISTER_APPEND_ATTEMPTS
        ));
    }
    Ok(transport_session)
}

#[derive(Clone, Copy)]
pub(crate) struct AnswerTag {
    end: Resume,
    session: u64,
}

impl AnswerTag {
    pub(crate) fn read(record: &ParsedLine, end: Resume) -> Option<Self> {
        record.answer_session().map(|session| Self { end, session })
    }
}

pub(crate) fn startup_is_live(
    tag: Option<AnswerTag>,
    start: u64,
    id: Option<FileId>,
    session: u64,
) -> bool {
    match tag {
        Some(tag) if tag.end.pos == start && tag.end.id == id => tag.session == session,
        _ => true,
    }
}

pub(crate) struct ConsumerState {
    pub(crate) tail: Resume,
    pub(crate) game: Option<String>,
    pub(crate) startup_on_wire: bool,
    /// Retain a hoisted startup until the ordered reader reaches its queued copy.
    pub(crate) hoisted: Option<QueueMark>,
    pub(crate) answer_tag: Option<AnswerTag>,
    pub(crate) registered: Vec<String>,
    pub(crate) pending: Arc<Mutex<PendingTracker>>,
}

impl ConsumerState {
    pub(crate) fn new(tail: Resume, pending: Arc<Mutex<PendingTracker>>) -> Self {
        Self {
            tail,
            game: None,
            startup_on_wire: false,
            hoisted: None,
            answer_tag: None,
            registered: Vec::new(),
            pending,
        }
    }
}

/// Skip the hoisted startup and superseded records so they cannot enter the new session.
fn superseded(
    st: &mut ConsumerState,
    outgoing: &Outgoing,
    command: Option<&str>,
    mark: QueueMark,
) -> bool {
    let Some(hoisted) = st.hoisted else {
        return false;
    };
    let clears = matches!(outgoing, Outgoing::Outbox(..))
        && matches!(
            command,
            Some(
                "startup"
                    | "actions/register"
                    | "actions/unregister"
                    | "actions/force"
                    | "action/result"
            )
        );
    if mark.resume.id != hoisted.resume.id {
        return clears;
    }
    if mark.start > hoisted.start {
        eprintln!("[Warning] The ordered read passed the startup it sent ahead without meeting it");
    }
    if mark.start >= hoisted.start {
        st.hoisted = None;
    }
    mark.start == hoisted.start || mark.start < hoisted.start && clears
}

/// Dropped detached or superseded records still advance the durable cursor.
async fn fence_record(
    cfg: &Config,
    st: &mut ConsumerState,
    cursor: &mut Checkpointer,
    rx_generation: &AtomicU64,
    outgoing: &Outgoing,
    command: Option<&str>,
) -> bool {
    let mark = outgoing.mark();
    if mark.generation != rx_generation.load(Ordering::Acquire)
        || !outbox_holds(&cfg.outbox, mark.resume).await
    {
        eprintln!("[Info] Discarding detached outbox record from an older generation");
        return false;
    }
    let skip = match outgoing {
        Outgoing::Hoisted(..) => false,
        Outgoing::Dropped(_) => {
            superseded(st, outgoing, command, mark);
            true
        }
        Outgoing::Outbox(..) => superseded(st, outgoing, command, mark),
    };
    if skip {
        st.tail = mark.resume;
        cursor.advance(mark.resume, false).await;
    }
    !skip
}

/// Flush an automatically queued Pong during idle, when no outbox event would trigger a write.
async fn session_idle(tasks: &SessionTasks, ws_write: &mut Option<WsWrite>) -> bool {
    if tasks.tx_is_finished() || tasks.rx_is_finished() {
        return false;
    }
    match ws_write.as_mut() {
        Some(ws) => websocket_flush(ws).await.is_ok(),
        None => true,
    }
}

pub(crate) struct Lanes {
    pub(crate) startup: mpsc::Receiver<QueuedOutgoing>,
    pub(crate) outbox: mpsc::Receiver<QueuedOutgoing>,
    pub(crate) released: Arc<tokio::sync::Notify>,
}

impl Lanes {
    pub(crate) async fn next(
        &mut self,
        st: &ConsumerState,
        wait: Duration,
    ) -> std::result::Result<Option<QueuedOutgoing>, time::error::Elapsed> {
        self.released.notify_one();
        let lane = if st.startup_on_wire {
            &mut self.outbox
        } else {
            &mut self.startup
        };
        time::timeout(wait, lane.recv()).await
    }
}

/// Ignore read-only tailer events so its own reads cannot keep it awake.
pub(crate) fn wakes_tailer(kind: &notify::EventKind) -> bool {
    use notify::event::{AccessKind, AccessMode};
    match kind {
        notify::EventKind::Access(AccessKind::Close(AccessMode::Write)) => true,
        notify::EventKind::Access(_) => false,
        _ => true,
    }
}

pub(crate) struct OutboxWatcher {
    _watcher: notify::RecommendedWatcher,
    healthy: Arc<AtomicBool>,
}

impl OutboxWatcher {
    pub(crate) fn healthy(&self) -> bool {
        self.healthy.load(Ordering::Relaxed)
    }
}

pub(crate) fn outbox_watcher(outbox: &Path, tx: mpsc::Sender<()>) -> Option<OutboxWatcher> {
    let parent = outbox.parent()?;
    let dir = std::path::absolute(parent).ok()?;
    let want = outbox.file_name().map(|n| n.to_os_string());
    let healthy = Arc::new(AtomicBool::new(true));
    let flag = Arc::clone(&healthy);
    let mut watcher =
        notify::recommended_watcher(move |res: Result<notify::Event, notify::Error>| {
            let ev = match res {
                Ok(ev) => ev,
                Err(error) => {
                    if flag.swap(false, Ordering::Relaxed) {
                        eprintln!("[Warning] Outbox watch failed ({error}); polling instead");
                    }
                    return;
                }
            };
            let gone = matches!(
                ev.kind,
                notify::EventKind::Remove(_)
                    | notify::EventKind::Modify(notify::event::ModifyKind::Name(_))
            ) && ev.paths.contains(&dir);
            let hit = gone
                || ev.need_rescan()
                || wakes_tailer(&ev.kind)
                    && match &want {
                        Some(name) => ev
                            .paths
                            .iter()
                            .any(|p| p.file_name() == Some(name.as_os_str())),
                        None => true,
                    };
            if hit {
                tx.try_send(()).ok();
            }
            if gone && flag.swap(false, Ordering::Relaxed) {
                eprintln!("[Warning] Outbox watch ended; polling instead");
            }
        })
        .ok()?;
    watcher.watch(parent, RecursiveMode::NonRecursive).ok()?;
    Some(OutboxWatcher {
        _watcher: watcher,
        healthy,
    })
}

pub(crate) async fn stop_requested(stop: &mut tokio::sync::watch::Receiver<bool>) {
    if stop.wait_for(|stopped| *stopped).await.is_err() {
        std::future::pending::<()>().await;
    }
}

async fn connect_for_startup(
    cfg: &Config,
    stop: &mut tokio::sync::watch::Receiver<bool>,
) -> Option<WsStream> {
    loop {
        match connect_websocket(&cfg.ws_url).await {
            Ok(stream) => return Some(stream),
            Err(error) => {
                eprintln!(
                    "[Warning] Could not connect websocket: {error:#} (retry in {RECONNECT_INTERVAL_SECS}s)"
                );
            }
        }
        tokio::select! {
            _ = time::sleep(Duration::from_secs(RECONNECT_INTERVAL_SECS)) => {}
            _ = stop_requested(stop) => return None,
        }
    }
}

enum Incoming {
    Record(std::result::Result<Option<QueuedOutgoing>, time::error::Elapsed>),
    CursorRetry,
    Stop,
}

pub(crate) async fn run_session(
    cfg: &Config,
    pending: Arc<Mutex<PendingTracker>>,
    mut stop: tokio::sync::watch::Receiver<bool>,
) -> Result<Resume> {
    let (tail, bootstrapped) = match load_cursor(&cfg.outbox).await {
        Some(mark) => (mark, false),
        None => (bootstrap_boundary(&cfg.outbox).await?, true),
    };
    pending.lock().unwrap().begin_session();

    let mut cursor = Checkpointer::new(&cfg.outbox, tail);
    if bootstrapped && tail.id.is_some() {
        cursor.write(tail).await;
    }
    let transport_session = open_transport_session(cfg).await?;

    let queue_bytes = Arc::new(AtomicUsize::new(0));
    let (tx, outbox_rx) = mpsc::channel::<QueuedOutgoing>(MAX_QUEUED_RECORDS);
    let outbox_released = Arc::new(tokio::sync::Notify::new());
    let (startup_tx, startup_rx) = mpsc::channel::<QueuedOutgoing>(1);
    let generation = Arc::new(AtomicU64::new(0));
    let startup_on_wire_flag = Arc::new(AtomicBool::new(false));
    let shutdown = Arc::new(AtomicBool::new(false));

    let (watch_tx, watch_rx) = mpsc::channel::<()>(16);
    let watcher = outbox_watcher(&cfg.outbox, watch_tx.clone());
    let tailer = Tailer::new(cfg.outbox.clone(), tail);
    if watcher.is_none() {
        eprintln!(
            "[Info] File watcher unavailable, falling back to {}ms polling",
            POLL_FALLBACK_MS
        );
    }
    let lane = Lane {
        tx,
        startup_tx,
        startup_on_wire: Arc::clone(&startup_on_wire_flag),
        generation: Arc::clone(&generation),
        queue_bytes,
        released: Arc::clone(&outbox_released),
        transport_session,
    };
    let tx_task = tokio::spawn(tailer_task(tailer, watcher, watch_rx, lane));
    let mut tasks = SessionTasks {
        tx: tx_task,
        rx: None,
    };
    let mut ws_write: Option<WsWrite> = None;
    let mut st = ConsumerState::new(tail, Arc::clone(&pending));
    let mut lanes = Lanes {
        startup: startup_rx,
        outbox: outbox_rx,
        released: outbox_released,
    };
    let mut game = GameLiveness::new(cfg.game_stale_after);
    let mut next_liveness_check = Instant::now();

    loop {
        if Instant::now() >= next_liveness_check {
            game.observe(fs::read(cfg.heartbeat()).await.ok(), Instant::now());
            next_liveness_check = Instant::now() + GAME_LIVENESS_POLL;
            // A dead game cannot answer actions or unregister them on its behalf.
            let owes_result = pending.lock().unwrap().owes_result();
            if ws_write.is_some() && game.dead(Instant::now(), owes_result) {
                eprintln!("[Warning] The game's heartbeat stopped; closing the websocket");
                break;
            }
        }
        let retry_at = cursor.retry_at();
        let incoming = tokio::select! {
            biased;
            _ = stop_requested(&mut stop) => Incoming::Stop,
            _ = time::sleep_until(retry_at.unwrap_or_else(Instant::now).into()), if retry_at.is_some() => Incoming::CursorRetry,
            record = lanes.next(&st, Duration::from_secs(1)) => Incoming::Record(record),
        };
        let incoming = match incoming {
            Incoming::Record(record) => record,
            Incoming::CursorRetry => {
                cursor.write(st.tail).await;
                continue;
            }
            Incoming::Stop => {
                if let (Some(ws), Some(game), true) =
                    (ws_write.as_mut(), st.game.as_deref(), st.startup_on_wire)
                {
                    if let Some(frame) = quit_unregister_frame(game, &st.registered) {
                        let _ = websocket_send(ws, Message::Text(frame.into())).await;
                    }
                }
                break;
            }
        };
        match incoming {
            Ok(Some(queued)) => {
                let outgoing = &queued.outgoing;
                let line = match outgoing {
                    Outgoing::Outbox(line, _) | Outgoing::Hoisted(line, _) => Some(line.as_str()),
                    Outgoing::Dropped(_) => None,
                };
                let mut record = line.map(ParsedLine::parse);
                let command = record.as_ref().and_then(ParsedLine::command);
                let urgent = matches!(command, Some("actions/force" | "context"));
                let answer_tag = record
                    .as_ref()
                    .and_then(|r| AnswerTag::read(r, outgoing.mark().resume));
                if !fence_record(cfg, &mut st, &mut cursor, &generation, outgoing, command).await {
                    continue;
                }
                let (Some(line), Some(record)) = (line, record.as_mut()) else {
                    unreachable!("dropped markers are handled above");
                };
                let RecordState {
                    forward,
                    startup_forwarded,
                    result_id,
                    frame,
                } = classify_outbox_command(record, line, &pending, &mut st.game);
                // A second startup indicates relaunch; closing the old connection reports any owed result.
                let mark = outgoing.mark();
                if startup_forwarded
                    && st.startup_on_wire
                    && startup_is_live(st.answer_tag, mark.start, mark.resume.id, transport_session)
                {
                    eprintln!("[Info] The game started again; reconnecting before its startup");
                    break;
                }
                st.answer_tag = answer_tag.or(st.answer_tag);
                let forward = forward
                    && !matches!(
                        outgoing,
                        Outgoing::Outbox(_, mark) if replayed(&pending, record.command(), *mark)
                    );
                if forward {
                    // The mod rebuilds the same unsendable frame, so re-registration cannot repair it.
                    if let Some(frame) = frame.or_else(|| record.take_wire_frame(line)) {
                        if ws_write.is_none() {
                            let Some(stream) = connect_for_startup(cfg, &mut stop).await else {
                                break;
                            };
                            let (write, read) = stream.split();
                            ws_write = Some(write);
                            tasks.rx = Some(tokio::spawn(receive_task(ReceiveTask {
                                ws_read: read,
                                inbox_path: cfg.inbox.clone(),
                                pending_rx: Arc::clone(&pending),
                                shutdown_rx: Arc::clone(&shutdown),
                            })));
                        }
                        let ws = ws_write.as_mut().expect("connected above");
                        note_registration_frame(&mut st.registered, &frame.value);
                        if websocket_send(ws, Message::Text(frame.text.into()))
                            .await
                            .is_err()
                        {
                            break;
                        }
                        // Record an id as answered only after its result frame is confirmed on the socket.
                        if let Some(id) = result_id {
                            st.pending.lock().unwrap().observe_result(&id);
                        }
                        if startup_forwarded && !st.startup_on_wire {
                            st.startup_on_wire = true;
                            if let Outgoing::Hoisted(_, mark) = outgoing {
                                st.hoisted = Some(*mark);
                            }
                            startup_on_wire_flag.store(true, Ordering::Release);
                            let _ = watch_tx.try_send(());
                        }
                    }
                }
                // Do not checkpoint an answer tag alone; the next session could treat startup as untagged.
                if let Outgoing::Outbox(_, mark) = outgoing {
                    if answer_tag.is_none() {
                        st.tail = mark.resume;
                        cursor.advance(mark.resume, urgent).await;
                    }
                }
            }
            Ok(None) => break,
            Err(_) => {
                if !session_idle(&tasks, &mut ws_write).await {
                    break;
                }
            }
        }
    }

    cursor.finish(st.tail).await;
    shutdown.store(true, Ordering::Relaxed);
    if let Some(ws) = ws_write.as_mut() {
        let _ = websocket_close(ws).await;
    }
    tasks.stop().await;
    Ok(st.tail)
}
