use super::*;
use futures_util::FutureExt;

const STARTUP: &str = "{\"command\":\"startup\",\"game\":\"Balatro\"}\n";

type ServerWs = tokio_tungstenite::WebSocketStream<tokio::net::TcpStream>;

fn command_from_line(line: &str) -> Option<String> {
    let value = parse_json_line(line)?;
    value
        .as_object()?
        .get("command")?
        .as_str()
        .map(str::to_string)
}

fn path_id(path: &Path) -> Option<FileId> {
    open_stat(path).ok().map(|(_, _, id)| id)
}

fn never_stop() -> tokio::sync::watch::Receiver<bool> {
    tokio::sync::watch::channel(false).1
}

struct Fx {
    dir: PathBuf,
}

impl Fx {
    fn new(tag: &str) -> Self {
        let dir = scratch_dir(tag);
        std::fs::create_dir_all(&dir).unwrap();
        Self { dir }
    }

    fn config(&self) -> Config {
        Config {
            ws_url: String::new(),
            outbox: self.dir.join("neuro_outbox.jsonl"),
            inbox: self.dir.join("neuro_inbox.jsonl"),
            game_stale_after: GAME_STALE_AFTER,
        }
    }

    fn config_at(&self, addr: std::net::SocketAddr) -> Config {
        Config {
            ws_url: format!("ws://{addr}"),
            ..self.config()
        }
    }

    async fn listen(&self) -> (tokio::net::TcpListener, Config) {
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let cfg = self.config_at(listener.local_addr().unwrap());
        (listener, cfg)
    }
}

impl Drop for Fx {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.dir);
    }
}

fn new_pending() -> Arc<Mutex<PendingTracker>> {
    Arc::new(Mutex::new(PendingTracker::default()))
}

async fn run_bounded(
    secs: u64,
    cfg: &Config,
    pending: Arc<Mutex<PendingTracker>>,
) -> std::result::Result<Result<Resume>, time::error::Elapsed> {
    time::timeout(
        Duration::from_secs(secs),
        run_session(cfg, pending, never_stop()),
    )
    .await
}

fn spawn_session(
    cfg: Config,
    pending: Arc<Mutex<PendingTracker>>,
) -> tokio::task::JoinHandle<Result<Resume>> {
    tokio::spawn(async move { run_session(&cfg, pending, never_stop()).await })
}

async fn accept_ws(listener: &tokio::net::TcpListener) -> ServerWs {
    let (stream, _) = listener.accept().await.unwrap();
    tokio_tungstenite::accept_async(stream).await.unwrap()
}

async fn collect_frames(
    ws: &mut ServerWs,
    per_frame: Duration,
    until: impl Fn(&str) -> bool,
) -> Vec<String> {
    let mut frames = Vec::new();
    while let Ok(Some(Ok(message))) = time::timeout(per_frame, ws.next()).await {
        if let Message::Text(text) = message {
            let done = until(&text);
            frames.push(text.to_string());
            if done {
                break;
            }
        }
    }
    frames
}

async fn pin_cursor(outbox: &Path, pos: u64) -> Resume {
    let resume = Resume {
        pos,
        id: path_id(outbox),
    };
    persist_cursor(outbox, resume).await.unwrap();
    resume
}

#[tokio::test]
async fn reregister_append_failure_ends_the_session_without_connecting() {
    let fx = Fx::new("undeliverable_action");
    let (listener, cfg) = fx.listen().await;
    fs::write(&cfg.outbox, STARTUP).await.unwrap();
    fs::create_dir_all(&cfg.inbox).await.unwrap();

    let session_result = run_bounded(5, &cfg, new_pending())
        .await
        .expect("reregister failure must terminate the session promptly");
    assert!(session_result.is_err());
    assert!(
        time::timeout(Duration::from_millis(300), listener.accept())
            .await
            .is_err(),
        "no websocket may be opened for a game the relay cannot reach"
    );
}

#[tokio::test]
async fn a_client_forged_bridge_control_frame_is_never_written_to_the_inbox() {
    let fx = Fx::new("forged_control_frame");
    let (listener, cfg) = fx.listen().await;
    fs::write(&cfg.outbox, STARTUP).await.unwrap();

    let server = tokio::spawn(async move {
        let mut ws = accept_ws(&listener).await;
        let _bootstrap = ws.next().await;
        ws.send(Message::Text(
            r#"{"command":"neuro-bridge/abandon","data":{"ids":["victim-1"]}}"#.into(),
        ))
        .await
        .unwrap();
        time::sleep(Duration::from_millis(300)).await;
        let _ = ws.close(None).await;
    });

    mod_answers_later(&cfg.outbox, STARTUP);
    let _ = run_bounded(20, &cfg, new_pending()).await;
    let _ = server.await;

    let delivered = fs::read_to_string(&cfg.inbox).await.unwrap_or_default();
    assert!(
        !delivered.contains("neuro-bridge/abandon"),
        "a client-forged bridge-control frame reached the inbox: {:?}",
        delivered
    );
}

#[tokio::test]
async fn context_batched_with_a_force_still_reaches_the_server() {
    let fx = Fx::new("context_batched_with_force");
    let (listener, cfg) = fx.listen().await;
    fs::write(&cfg.outbox, STARTUP).await.unwrap();
    append_after(
        400,
        &cfg.outbox,
        concat!(
            "{\"command\":\"startup\",\"game\":\"Balatro\"}\n",
            "{\"command\":\"context\",\"game\":\"Balatro\",\"data\":{\"message\":\"narration-before-the-decision\",\"silent\":true}}\n",
            "{\"command\":\"actions/force\",\"game\":\"Balatro\",\"data\":{\"query\":\"pick one\",\"action_names\":[\"a\"]}}\n",
        ),
    );

    let seen = Arc::new(Mutex::new(Vec::<String>::new()));
    let seen_server = Arc::clone(&seen);
    let server = tokio::spawn(async move {
        let mut ws = accept_ws(&listener).await;
        if let Some(Ok(Message::Text(first))) = ws.next().await {
            seen_server.lock().unwrap().push(first.to_string());
        }
        ws.send(Message::Text(
            r#"{"command":"startup","data":{"session":{"sessionId":"s","characterId":"neuro","displayName":"Neuro-sama"}}}"#
                .into(),
        ))
        .await
        .unwrap();
        let deadline = time::sleep(Duration::from_millis(2500));
        tokio::pin!(deadline);
        loop {
            tokio::select! {
                _ = &mut deadline => break,
                frame = ws.next() => match frame {
                    Some(Ok(Message::Text(text))) => seen_server.lock().unwrap().push(text.to_string()),
                    Some(Ok(_)) => {}
                    _ => break,
                },
            }
        }
        let _ = ws.close(None).await;
    });

    let _ = run_bounded(20, &cfg, new_pending()).await;
    let _ = server.await;

    let frames = seen.lock().unwrap().clone();
    let joined = frames.join("\n");
    assert!(
        joined.contains("narration-before-the-decision"),
        "context batched with a force was dropped instead of delivered: {:?}",
        frames
    );
    assert!(
        joined.contains("actions/force"),
        "the force itself never reached the server: {:?}",
        frames
    );
}

fn cursor_fixture(tag: &str, records: &[&str]) -> (Fx, PathBuf, Vec<Resume>) {
    let fx = Fx::new(tag);
    let outbox = fx.dir.join("neuro_outbox.jsonl");
    std::fs::write(&outbox, records.concat()).unwrap();
    let id = path_id(&outbox);
    let mut pos = 0;
    let ends = records
        .iter()
        .map(|record| {
            pos += record.len() as u64;
            Resume { pos, id }
        })
        .collect();
    (fx, outbox, ends)
}

#[tokio::test]
async fn a_session_whose_cursor_cannot_be_written_keeps_sending_on_its_socket() {
    let fx = Fx::new("session_cursor_failure");
    let (listener, cfg) = fx.listen().await;
    block_cursor(&cfg.outbox);
    let context = |text: &str| {
        format!("{{\"command\":\"context\",\"game\":\"Balatro\",\"data\":{{\"message\":\"{text}\",\"silent\":true}}}}\n")
    };
    fs::write(&cfg.outbox, STARTUP).await.unwrap();
    mod_answers_later(&cfg.outbox, &format!("{STARTUP}{}", context("FIRST")));
    append_after(900, &cfg.outbox, &context("SECOND"));
    let session = spawn_session(cfg, new_pending());
    let mut ws = accept_ws(&listener).await;
    let mut seen = Vec::new();
    while let Ok(Some(Ok(message))) = time::timeout(Duration::from_secs(5), ws.next()).await {
        if let Message::Text(text) = message {
            seen.push((Instant::now(), text.to_string()));
            if text.contains("SECOND") {
                break;
            }
        }
    }
    let at = |needle: &str| {
        seen.iter()
            .find(|(_, f)| f.contains(needle))
            .map(|(t, _)| *t)
    };
    let (Some(first), Some(second)) = (at("FIRST"), at("SECOND")) else {
        panic!("{seen:?}");
    };
    let held = second - first;
    assert!(
        held < Duration::from_millis(1500),
        "SECOND went out {held:?} after FIRST"
    );
    time::sleep(Duration::from_secs(2)).await;
    assert!(
        !session.is_finished(),
        "the session ended over a cursor fault"
    );
    session.abort();
}

#[tokio::test]
async fn a_cursor_write_failure_holds_the_socket_and_resumes_once_writable() {
    let fx = Fx::new("session_cursor_recovers");
    let mut cfg = fx.config();
    let blocked = cursor_path(&cfg.outbox);
    std::fs::create_dir_all(&blocked).unwrap();
    std::fs::write(blocked.join("keep"), b"x").unwrap();
    let context = |text: &str| {
        format!("{{\"command\":\"context\",\"game\":\"Balatro\",\"data\":{{\"message\":\"{text}\",\"silent\":true}}}}\n")
    };
    fs::write(&cfg.outbox, STARTUP).await.unwrap();
    mod_answers_later(&cfg.outbox, &format!("{STARTUP}{}", context("FIRST")));
    let (later, second) = (cfg.outbox.clone(), context("SECOND"));
    tokio::spawn(async move {
        time::sleep(Duration::from_millis(700)).await;
        std::fs::remove_dir_all(&blocked).unwrap();
        time::sleep(Duration::from_millis(200)).await;
        append_outbox(&later, &second);
    });
    let frames = wire_of_session(&mut cfg, "SECOND").await;
    assert_eq!(
        wire_commands(&frames),
        ["startup", "context", "context"],
        "{frames:?}"
    );
    assert!(frames[2].contains("SECOND"), "{frames:?}");
}

#[tokio::test]
async fn a_reread_result_goes_out_once_per_connection() {
    let fx = Fx::new("session_result_reread");
    let (listener, cfg) = fx.listen().await;
    fs::write(&cfg.outbox, STARTUP).await.unwrap();
    let resume = pin_cursor(&cfg.outbox, STARTUP.len() as u64).await;
    let stuck_cursor = fs::read(cursor_path(&cfg.outbox)).await.unwrap();
    let result = "{\"command\":\"action/result\",\"game\":\"Balatro\",\"data\":{\"id\":\"once\",\"success\":true}}\n";
    append_outbox(&cfg.outbox, &format!("{STARTUP}{result}"));

    let server = tokio::spawn(async move {
        let mut sessions = Vec::new();
        for _ in 0..3 {
            let mut ws = accept_ws(&listener).await;
            let frames = collect_frames(&mut ws, Duration::from_secs(1), |_| false).await;
            let _ = ws.close(None).await;
            sessions.push(frames);
        }
        sessions
    });
    let pending = new_pending();
    for _ in 0..3 {
        fs::write(cursor_path(&cfg.outbox), &stuck_cursor)
            .await
            .unwrap();
        assert_eq!(load_cursor(&cfg.outbox).await, Some(resume));
        run_bounded(20, &cfg, pending.clone())
            .await
            .expect("session timed out")
            .expect("session failed");
    }
    let sessions = server.await.unwrap();
    let results: Vec<usize> = sessions
        .iter()
        .map(|frames| {
            frames
                .iter()
                .filter(|f| f.contains("action/result"))
                .count()
        })
        .collect();
    assert_eq!(results, [1, 1, 1], "{sessions:?}");
}

#[tokio::test]
async fn a_force_reread_from_a_stuck_cursor_goes_out_once() {
    let fx = Fx::new("session_force_reread");
    let (listener, cfg) = fx.listen().await;
    fs::write(&cfg.outbox, STARTUP).await.unwrap();
    let resume = pin_cursor(&cfg.outbox, STARTUP.len() as u64).await;
    let stuck_cursor = fs::read(cursor_path(&cfg.outbox)).await.unwrap();
    let force = "{\"command\":\"actions/force\",\"game\":\"Balatro\",\"data\":{\"query\":\"FORCE-ONCE\",\"action_names\":[\"play_hand\"]}}\n";
    append_outbox(&cfg.outbox, &format!("{STARTUP}{force}"));

    let server = tokio::spawn(async move {
        let mut sessions = Vec::new();
        for _ in 0..2 {
            let mut ws = accept_ws(&listener).await;
            let frames = collect_frames(&mut ws, Duration::from_secs(1), |_| false).await;
            let _ = ws.close(None).await;
            sessions.push(wire_commands(&frames));
        }
        sessions
    });
    let pending = new_pending();
    for _ in 0..2 {
        fs::write(cursor_path(&cfg.outbox), &stuck_cursor)
            .await
            .unwrap();
        assert_eq!(load_cursor(&cfg.outbox).await, Some(resume));
        run_bounded(20, &cfg, pending.clone())
            .await
            .expect("session timed out")
            .expect("session failed");
    }
    let sessions = server.await.unwrap();
    assert_eq!(
        sessions,
        [vec!["startup", "actions/force"], vec!["startup"]],
        "{sessions:?}"
    );
}

#[tokio::test]
async fn a_result_written_twice_on_one_connection_goes_out_once() {
    let fx = Fx::new("session_result_twice");
    let (listener, cfg) = fx.listen().await;
    fs::write(&cfg.outbox, "").await.unwrap();
    let (outbox, inbox) = (cfg.outbox.clone(), cfg.inbox.clone());
    let session = spawn_session(cfg, new_pending());
    let mut ws = accept_live_game(&listener, &outbox).await;
    inbox_holds(&inbox, "lost-1").await;
    let marker = "{\"command\":\"context\",\"game\":\"Balatro\",\"data\":{\"message\":\"AFTER-RESULTS\",\"silent\":true}}\n";
    append_outbox(&outbox, &action_result_line("lost-1"));
    let first = collect_frames(&mut ws, Duration::from_secs(3), |text| {
        text.contains("action/result")
    })
    .await;
    append_outbox(
        &outbox,
        &format!("{}{marker}", action_result_line("lost-1")),
    );
    let rest = collect_frames(&mut ws, Duration::from_secs(3), |text| {
        text.contains("AFTER-RESULTS")
    })
    .await;
    let frames = [first, rest].concat();
    assert_eq!(
        wire_commands(&frames),
        ["startup", "actions/register", "action/result", "context"],
        "{frames:#?}"
    );
    session.abort();
}

fn scratch_dir(tag: &str) -> PathBuf {
    std::env::temp_dir().join(format!(
        "neuro_bridge_{}_{}_{}",
        tag,
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    ))
}

#[tokio::test]
async fn cancelling_run_session_closes_the_server_connection() {
    let fx = Fx::new("cancel_session");
    let (listener, cfg) = fx.listen().await;
    fs::write(&cfg.outbox, STARTUP).await.unwrap();

    let (bootstrap_tx, bootstrap_rx) = tokio::sync::oneshot::channel();
    let server = tokio::spawn(async move {
        let mut ws = accept_ws(&listener).await;
        let first = ws.next().await;
        bootstrap_tx.send(first).ok();
        matches!(
            time::timeout(Duration::from_secs(2), ws.next()).await,
            Ok(None) | Ok(Some(Err(_))) | Ok(Some(Ok(Message::Close(_))))
        )
    });

    mod_answers_later(&cfg.outbox, STARTUP);
    let mut session = Box::pin(run_session(&cfg, new_pending(), never_stop()));
    let first = tokio::select! {
        first = bootstrap_rx => first.unwrap(),
        result = session.as_mut() => panic!("run_session exited before cancellation: {:?}", result),
    };
    assert!(matches!(first, Some(Ok(Message::Text(_)))));
    // Poll once to avoid racing client/server timers under executor starvation.
    assert!(session.as_mut().now_or_never().is_none());
    drop(session);
    assert!(
        server.await.unwrap(),
        "server did not observe the websocket closing after run_session cancellation"
    );
}
#[tokio::test]
async fn a_second_session_in_one_process_repeats_startup_before_tailing() {
    let fx = Fx::new("session_second_startup");
    let (listener, cfg) = fx.listen().await;
    fs::write(
        &cfg.outbox,
        "{\"command\":\"startup\",\"game\":\"Balatro\"}\n{\"command\":\"actions/register\",\"game\":\"Balatro\",\"data\":{\"actions\":[{\"name\":\"play_hand\",\"description\":\"d\"}]}}\n",
    )
    .await
    .unwrap();

    let server = tokio::spawn(async move {
        let mut sessions = Vec::new();
        for session in 0..2 {
            let mut ws = accept_ws(&listener).await;
            let frames = collect_frames(&mut ws, Duration::from_secs(3), |text| {
                session == 0 || text.contains("reconnect gap fact")
            })
            .await;
            sessions.push(frames);
            let _ = ws.close(None).await;
        }
        sessions
    });

    mod_answers_later(&cfg.outbox, STARTUP);
    let pending = new_pending();
    run_bounded(20, &cfg, pending.clone())
        .await
        .expect("first session timed out")
        .expect("first session failed");
    append_outbox(
        &cfg.outbox,
        "{\"command\":\"startup\",\"game\":\"Balatro\"}\n{\"command\":\"context\",\"game\":\"Balatro\",\"data\":{\"message\":\"reconnect gap fact\",\"silent\":true}}\n",
    );
    run_bounded(20, &cfg, pending)
        .await
        .expect("second session timed out")
        .expect("second session failed");

    let sessions = server.await.unwrap();
    assert_eq!(sessions.len(), 2);
    let first: Value = serde_json::from_str(&sessions[0][0]).unwrap();
    let second: Value = serde_json::from_str(&sessions[1][0]).unwrap();
    assert_eq!(first["command"], "startup");
    assert_eq!(
        sessions[1].len(),
        2,
        "append-only outbox growth must resume at the saved cursor rather than replaying history"
    );
    assert_eq!(second["command"], "startup");
    assert!(
        sessions[1]
            .iter()
            .any(|line| line.contains("reconnect gap fact")),
        "a line appended after disconnect must be tailed from the saved byte mark"
    );
}

#[tokio::test]
async fn cursor_fingerprint_matches_the_mod_fixture() {
    let fx = Fx::new("cursor_fingerprint_fixture");
    for (len, pos, words) in [
        (4096u64, 1000u64, 0x175b_c90c_14ff_821d_u64),
        (200_000, 150_000, 0x71a2_04fd_616e_5a6d),
    ] {
        let path = fx.dir.join(format!("fixture_{len}"));
        fs::write(&path, fence_fixture(len)).await.unwrap();
        let file = std::fs::File::open(&path).unwrap();
        assert_eq!(fingerprint(&file, pos, len).unwrap(), words);
    }
}

fn fence_fixture(len: u64) -> Vec<u8> {
    (0..len).map(|i| ((i * 131 + 17) % 256) as u8).collect()
}

fn hex(bytes: &[u8]) -> String {
    bytes.iter().map(|byte| format!("{byte:02x}")).collect()
}

#[tokio::test]
async fn the_cursor_layout_matches_the_mod_fixture() {
    let fx = Fx::new("cursor_fixture");
    let path = fx.dir.join("fixture");
    fs::write(&path, fence_fixture(200_000)).await.unwrap();
    let file = std::fs::File::open(&path).unwrap();
    let cursor = Cursor {
        pos: 120_000,
        len: 200_000,
        id: (1, 2),
        fingerprint: fingerprint(&file, 120_000, 200_000).unwrap(),
    };
    assert_eq!(
        format!("{}\n", hex(&cursor.encode())),
        include_str!("cursor_fixture.hex")
    );
}

#[tokio::test]
async fn missing_cursor_drops_stale_non_bootstrap_lines() {
    let fx = Fx::new("session_stale_tail");
    let (listener, cfg) = fx.listen().await;
    fs::write(
        &cfg.outbox,
        "{\"command\":\"startup\",\"game\":\"Balatro\"}\n{\"command\":\"context\",\"game\":\"Balatro\",\"data\":{\"message\":\"stale facts\",\"silent\":true}}\n{\"command\":\"actions/force\",\"game\":\"Balatro\",\"data\":{\"query\":\"stale decision\",\"action_names\":[\"play_hand\"]}}\n",
    )
    .await
    .unwrap();

    let server = tokio::spawn(async move {
        let mut ws = accept_ws(&listener).await;
        let frames = collect_frames(&mut ws, Duration::from_secs(3), |_| false).await;
        let _ = ws.close(None).await;
        frames
    });

    mod_answers_later(&cfg.outbox, STARTUP);
    let session = spawn_session(cfg, new_pending());

    let frames = time::timeout(Duration::from_secs(20), server)
        .await
        .expect("server timed out")
        .unwrap();
    session.abort();

    let commands: Vec<String> = frames
        .iter()
        .map(|f| {
            serde_json::from_str::<Value>(f).unwrap()["command"]
                .as_str()
                .unwrap()
                .to_string()
        })
        .collect();
    assert!(
        commands.contains(&"startup".to_string()),
        "bootstrap must still deliver startup, got {:?}",
        commands
    );
    assert!(
        !commands.contains(&"context".to_string()),
        "stale context must not cross the fresh startup reset: {:?}",
        commands
    );
    assert!(
        !commands.contains(&"actions/force".to_string()),
        "stale force must not cross the fresh startup reset: {:?}",
        commands
    );
}

#[tokio::test]
async fn a_result_for_an_id_the_relay_never_saw_is_still_forwarded() {
    let fx = Fx::new("late_result_forwarded");
    let (listener, cfg) = fx.listen().await;
    fs::write(&cfg.outbox, STARTUP).await.unwrap();

    let outbox_for_server = cfg.outbox.clone();
    let server = tokio::spawn(async move {
        let mut ws = accept_ws(&listener).await;
        append_outbox(
            &outbox_for_server,
            "{\"command\":\"action/result\",\"game\":\"Balatro\",\"data\":{\"id\":\"deadbeef\",\"success\":true,\"message\":\"late\"}}\n",
        );
        let frames = collect_frames(&mut ws, Duration::from_secs(3), |text| {
            command_from_line(text).as_deref() == Some("action/result")
        })
        .await;
        let _ = ws.close(None).await;
        frames
    });

    mod_answers_later(&cfg.outbox, STARTUP);
    let _ = run_bounded(20, &cfg, new_pending()).await;

    let frames = server.await.unwrap();
    let forwarded: Vec<&String> = frames
        .iter()
        .filter(|frame| command_from_line(frame).as_deref() == Some("action/result"))
        .collect();
    assert_eq!(
        forwarded.len(),
        1,
        "an id the ledger never held must still answer the SDK: {:?}",
        frames
    );
    assert!(forwarded[0].contains("deadbeef"), "{}", forwarded[0]);
}

#[tokio::test]
async fn run_session_rebuilds_bootstrap_after_outbox_replacement() {
    let fx = Fx::new("session_replace");
    let (listener, cfg) = fx.listen().await;
    fs::write(&cfg.outbox, STARTUP).await.unwrap();

    let server = tokio::spawn(async move {
        let mut first_frames = Vec::new();
        for _ in 0..2 {
            let mut ws = accept_ws(&listener).await;
            first_frames.push(ws.next().await);
            let _ = ws.close(None).await;
        }
        first_frames
    });

    mod_answers_later(&cfg.outbox, STARTUP);
    let pending = new_pending();
    run_bounded(20, &cfg, pending.clone())
        .await
        .expect("first run_session timed out")
        .expect("first run_session failed");

    let replacement = fx.dir.join("replacement.jsonl");
    fs::write(
        &replacement,
        "{\"command\":\"startup\",\"game\":\"Replaced\"}\n",
    )
    .await
    .unwrap();
    fs::rename(&replacement, &cfg.outbox).await.unwrap();
    mod_answers_later(
        &cfg.outbox,
        "{\"command\":\"startup\",\"game\":\"Replaced\"}\n",
    );

    run_bounded(20, &cfg, pending)
        .await
        .expect("second run_session timed out")
        .expect("second run_session failed");

    let frames = server.await.unwrap();
    assert_eq!(frames.len(), 2);
    let first = match &frames[0] {
        Some(Ok(Message::Text(text))) => serde_json::from_str::<Value>(text).unwrap(),
        other => panic!("expected first startup frame, got {:?}", other),
    };
    let second = match &frames[1] {
        Some(Ok(Message::Text(text))) => serde_json::from_str::<Value>(text).unwrap(),
        other => panic!("expected replacement startup frame, got {:?}", other),
    };
    assert_eq!(first["command"], "startup");
    assert_eq!(first["game"], "Balatro");
    assert_eq!(second["command"], "startup");
    assert_eq!(second["game"], "Replaced");
}

#[tokio::test]
async fn a_new_websocket_session_asks_the_mod_to_reregister() {
    let fx = Fx::new("reregister_session");
    let (listener, cfg) = fx.listen().await;
    fs::write(&cfg.outbox, STARTUP).await.unwrap();

    let server = tokio::spawn(async move {
        let mut ws = accept_ws(&listener).await;
        let first = ws.next().await;
        let _ = ws.close(None).await;
        first
    });

    mod_answers_later(&cfg.outbox, STARTUP);
    let _ = run_bounded(20, &cfg, new_pending()).await;

    let delivered = fs::read_to_string(&cfg.inbox).await.unwrap_or_default();
    assert!(
        delivered
            .lines()
            .any(|l| command_from_line(l).as_deref() == Some("neuro-bridge/reregister_all")),
        "a fresh websocket session left the mod without a reregister request: {:?}",
        delivered
    );
    let bootstrapped = server.await.unwrap();
    match bootstrapped {
        Some(Ok(Message::Text(text))) => {
            assert_eq!(command_from_line(&text).as_deref(), Some("startup"))
        }
        other => panic!("expected the startup bootstrap frame, got {:?}", other),
    }
}

#[tokio::test]
async fn a_fresh_session_never_replays_an_old_force_from_the_outbox() {
    let fx = Fx::new("stale_force_fence");
    let (listener, cfg) = fx.listen().await;
    let history = [
        r#"{"command":"startup","game":"Balatro"}"#,
        r#"{"command":"actions/register","game":"Balatro","data":{"actions":[{"name":"play_hand","description":"Play.","schema":{"type":"object"}}]}}"#,
        r#"{"command":"actions/force","game":"Balatro","data":{"query":"STALE-FORCE-FROM-LAST-GAME","action_names":["play_hand"]}}"#,
    ];
    fs::write(&cfg.outbox, history.join("\n") + "\n")
        .await
        .unwrap();
    mod_answers_later(&cfg.outbox, &(history[..2].join("\n") + "\n"));

    let server = tokio::spawn(async move {
        let mut ws = accept_ws(&listener).await;
        let frames = collect_frames(&mut ws, Duration::from_secs(4), |_| false).await;
        let _ = ws.close(None).await;
        frames
    });

    let _ = run_bounded(20, &cfg, new_pending()).await;
    let frames = server.await.unwrap();
    let commands: Vec<Option<String>> = frames.iter().map(|f| command_from_line(f)).collect();
    assert_eq!(
        commands,
        [
            Some("startup".to_string()),
            Some("actions/register".to_string())
        ],
        "frames were {frames:?}"
    );
    assert!(
        !frames
            .iter()
            .any(|f| f.contains("STALE-FORCE-FROM-LAST-GAME")),
        "a force from the previous game reached the SDK; frames were {:?}",
        commands
    );
}

#[tokio::test]
async fn a_corrupt_outbox_line_is_stepped_over_and_the_next_force_still_goes_out() {
    let fx = Fx::new("dropped_marker_fence");
    let (listener, cfg) = fx.listen().await;
    let mut bytes = STARTUP.as_bytes().to_vec();
    bytes.extend_from_slice(
        b"{\"command\":\"context\",\"game\":\"Balatro\",\"data\":{\"message\":\"\xff\"}}\n",
    );
    bytes.extend_from_slice(b"{\"command\":\"actions/force\",\"game\":\"Balatro\",\"data\":{\"query\":\"AFTER-THE-BAD-LINE\",\"action_names\":[\"play_hand\"]}}\n");
    fs::write(&cfg.outbox, &bytes).await.unwrap();
    pin_cursor(&cfg.outbox, 0).await;

    let server = tokio::spawn(async move {
        let mut ws = accept_ws(&listener).await;
        let frames = collect_frames(&mut ws, Duration::from_secs(3), |text| {
            text.contains("AFTER-THE-BAD-LINE")
        })
        .await;
        let _ = ws.close(None).await;
        frames
    });

    let _ = run_bounded(20, &cfg, new_pending()).await;
    let frames = server.await.unwrap();
    let commands: Vec<Option<String>> = frames.iter().map(|f| command_from_line(f)).collect();
    assert!(
        frames.iter().any(|f| f.contains("AFTER-THE-BAD-LINE")),
        "the force after a corrupt line never reached the SDK; frames were {:?}",
        commands
    );
    assert!(
        !commands.iter().any(|c| c.as_deref() == Some("context")),
        "the corrupt record was forwarded; frames were {:?}",
        commands
    );
}

async fn nth_asked_session(inbox: &Path, n: usize) -> u64 {
    for _ in 0..200 {
        let text = fs::read_to_string(inbox).await.unwrap_or_default();
        let asked: Vec<u64> = text
            .lines()
            .filter_map(|line| serde_json::from_str::<Value>(line).ok())
            .filter(|value| value["command"] == "neuro-bridge/reregister_all")
            .filter_map(|value| value["transport_session"].as_u64())
            .collect();
        if let Some(session) = asked.get(n) {
            return *session;
        }
        time::sleep(Duration::from_millis(25)).await;
    }
    panic!("the relay never asked the mod to reregister");
}

#[tokio::test]
async fn contexts_reread_from_an_older_cursor_are_not_sent_again() {
    let fx = Fx::new("context_reread");
    let (listener, cfg) = fx.listen().await;
    let addr = listener.local_addr().unwrap();
    fs::write(&cfg.outbox, STARTUP).await.unwrap();
    pin_cursor(&cfg.outbox, STARTUP.len() as u64).await;
    let stale_cursor = fs::read(cursor_path(&cfg.outbox)).await.unwrap();
    let pending = new_pending();
    let mut resent = Vec::new();
    for round in 0..2 {
        let session = spawn_session(fx.config_at(addr), Arc::clone(&pending));
        let asked = nth_asked_session(&cfg.inbox, round).await;
        let mut answer = format!("{}{STARTUP}{LIVENESS_REGISTER}", answer_tag_line(asked));
        if round == 0 {
            for n in 0..10 {
                answer.push_str(&format!(
                    "{{\"command\":\"context\",\"game\":\"Balatro\",\"data\":{{\"message\":\"N{n}\",\"silent\":true}}}}\n"
                ));
            }
        }
        append_outbox(&cfg.outbox, &answer);
        let (stream, _) = time::timeout(Duration::from_secs(5), listener.accept())
            .await
            .unwrap()
            .unwrap();
        let mut ws = tokio_tungstenite::accept_async(stream).await.unwrap();
        let frames = collect_frames(&mut ws, Duration::from_millis(1500), |_| false).await;
        let _ = ws.close(None).await;
        let _ = time::timeout(Duration::from_secs(5), session).await;
        if round == 0 {
            assert_eq!(frames.iter().filter(|f| f.contains("\"N")).count(), 10);
            fs::write(cursor_path(&cfg.outbox), &stale_cursor)
                .await
                .unwrap();
        } else {
            resent = frames;
        }
    }
    assert_eq!(
        wire_commands(&resent),
        ["startup", "actions/register"],
        "{resent:?}"
    );
}

#[tokio::test]
async fn an_unsendable_register_is_dropped_without_asking_the_mod_again() {
    let fx = Fx::new("unsendable_register");
    let mut cfg = fx.config();
    let register = "{\"command\":\"actions/register\",\"game\":\"Balatro\",\"data\":{\"actions\":[{\"name\":\"bad\",\"description\":\"d\",\"schema\":{\"type\":\"array\"}}]}}\n";
    let context = "{\"command\":\"context\",\"game\":\"Balatro\",\"data\":{\"message\":\"AFTER\",\"silent\":true}}\n";
    fs::write(&cfg.outbox, STARTUP).await.unwrap();
    mod_answers_later(&cfg.outbox, &format!("{STARTUP}{register}{context}"));
    let frames = wire_of_session(&mut cfg, "AFTER").await;
    assert_eq!(
        wire_commands(&frames),
        ["startup", "context"],
        "frames were {frames:?}"
    );
    let inbox = fs::read_to_string(&cfg.inbox).await.unwrap_or_default();
    assert_eq!(
        inbox.matches("neuro-bridge/reregister_all").count(),
        1,
        "only opening the session asks for registration: {inbox}"
    );
}

#[tokio::test]
async fn a_result_behind_a_valid_cursor_still_reaches_the_sdk() {
    let fx = Fx::new("result_behind_cursor");
    let (listener, cfg) = fx.listen().await;
    let result_line = "{\"command\":\"action/result\",\"game\":\"Balatro\",\"data\":{\"id\":\"deadbeef\",\"success\":true,\"message\":\"played\"}}\n";
    fs::write(&cfg.outbox, format!("{STARTUP}{result_line}"))
        .await
        .unwrap();
    pin_cursor(&cfg.outbox, 0).await;

    let server = tokio::spawn(async move {
        let mut ws = accept_ws(&listener).await;
        let frames = collect_frames(&mut ws, Duration::from_secs(3), |text| {
            command_from_line(text).as_deref() == Some("action/result")
        })
        .await;
        let _ = ws.close(None).await;
        frames
    });

    let _ = run_bounded(20, &cfg, new_pending()).await;
    let frames = server.await.unwrap();
    let commands: Vec<Option<String>> = frames.iter().map(|f| command_from_line(f)).collect();
    assert!(
        frames.iter().any(|f| f.contains("deadbeef")),
        "the undelivered result never reached the SDK; frames were {:?}",
        commands
    );
}

fn append_after(ms: u64, outbox: &Path, text: &str) {
    let (outbox, text) = (outbox.to_path_buf(), text.to_string());
    tokio::spawn(async move {
        time::sleep(Duration::from_millis(ms)).await;
        append_outbox(&outbox, &text);
    });
}

fn mod_answers_later(outbox: &Path, text: &str) {
    append_after(200, outbox, text);
}

fn append_outbox(path: &Path, text: &str) {
    use std::io::Write as _;
    let mut file = std::fs::OpenOptions::new().append(true).open(path).unwrap();
    file.write_all(text.as_bytes()).unwrap();
}

async fn wire_of_session(cfg: &mut Config, until: &'static str) -> Vec<String> {
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    cfg.ws_url = format!("ws://{}", listener.local_addr().unwrap());
    let server = tokio::spawn(async move {
        let mut ws = accept_ws(&listener).await;
        let frames =
            collect_frames(&mut ws, Duration::from_secs(2), |text| text.contains(until)).await;
        let _ = ws.close(None).await;
        frames
    });
    let _ = run_bounded(20, cfg, new_pending()).await;
    server.await.unwrap()
}

fn wire_commands(frames: &[String]) -> Vec<String> {
    frames.iter().filter_map(|f| command_from_line(f)).collect()
}

#[tokio::test]
async fn a_context_written_before_a_force_goes_out_before_it_and_the_force_is_not_replayed() {
    let fx = Fx::new("context_force_order");
    let mut cfg = fx.config();
    let context = "{\"command\":\"context\",\"game\":\"Balatro\",\"data\":{\"message\":\"NARRATION\",\"silent\":true}}\n";
    let force = "{\"command\":\"actions/force\",\"game\":\"Balatro\",\"data\":{\"query\":\"FORCE-ONE\",\"action_names\":[\"a\"]}}\n";
    fs::write(&cfg.outbox, STARTUP).await.unwrap();
    mod_answers_later(&cfg.outbox, &format!("{STARTUP}{context}{force}"));
    let frames = wire_of_session(&mut cfg, "never").await;
    let end = (2 * STARTUP.len() + context.len() + force.len()) as u64;
    assert_eq!(load_cursor(&cfg.outbox).await.map(|c| c.pos), Some(end));
    assert_eq!(
        wire_commands(&frames),
        ["startup", "context", "actions/force"],
        "frames were {frames:?}"
    );

    append_after(300, &cfg.outbox, STARTUP);
    let frames = wire_of_session(&mut cfg, "never").await;
    assert_eq!(
        wire_commands(&frames),
        ["startup"],
        "frames were {frames:?}"
    );
}

#[tokio::test]
async fn a_backlog_force_ahead_of_the_mods_startup_is_superseded_by_it() {
    let fx = Fx::new("backlog_force_superseded");
    let mut cfg = fx.config();
    let register = "{\"command\":\"actions/register\",\"game\":\"Balatro\",\"data\":{\"actions\":[{\"name\":\"play_hand\",\"description\":\"Play.\"}]}}\n";
    let old = format!("{STARTUP}{register}");
    fs::write(&cfg.outbox, &old).await.unwrap();
    pin_cursor(&cfg.outbox, old.len() as u64).await;
    append_outbox(
        &cfg.outbox,
        "{\"command\":\"actions/force\",\"game\":\"Balatro\",\"data\":{\"query\":\"F1-BACKLOG\",\"action_names\":[\"play_hand\"]}}\n",
    );
    mod_answers_later(&cfg.outbox, &format!("{STARTUP}{register}"));
    let frames = wire_of_session(&mut cfg, "never").await;
    assert_eq!(
        wire_commands(&frames),
        ["startup", "actions/register"],
        "frames were {frames:?}"
    );
    let len = fs::metadata(&cfg.outbox).await.unwrap().len();
    assert_eq!(load_cursor(&cfg.outbox).await.map(|c| c.pos), Some(len));
}

// Discover startup outside lane and byte limits so a large backlog cannot hide it.
#[tokio::test]
async fn a_backlog_of_any_size_does_not_hide_the_mods_startup() {
    let many: Vec<String> = (0..300)
        .map(|i| format!("{{\"command\":\"context\",\"game\":\"Balatro\",\"data\":{{\"message\":\"c{i}-\",\"silent\":true}}}}\n"))
        .collect();
    let filler = "x".repeat(3 * 1024 * 1024);
    let large: Vec<String> = (0..3)
        .map(|i| format!("{{\"command\":\"context\",\"game\":\"Balatro\",\"data\":{{\"message\":\"L{i}-{filler}\",\"silent\":true}}}}\n"))
        .collect();
    for (tag, backlog, last) in [("count", many, "c299-"), ("bytes", large, "L2-")] {
        let fx = Fx::new(&format!("backlog_hides_startup_{tag}"));
        let mut cfg = fx.config();
        fs::write(&cfg.outbox, STARTUP).await.unwrap();
        pin_cursor(&cfg.outbox, STARTUP.len() as u64).await;
        append_outbox(&cfg.outbox, &(backlog.concat() + STARTUP));
        let frames = wire_of_session(&mut cfg, last).await;
        let commands = wire_commands(&frames);
        assert_eq!(
            commands.first().map(String::as_str),
            Some("startup"),
            "{tag}"
        );
        assert_eq!(commands.len(), backlog.len() + 1, "{tag}");
        for (sent, written) in frames[1..].iter().zip(&backlog) {
            let prefix = &written[written.find("\"message\":\"").unwrap() + 11..][..4];
            assert!(sent.contains(prefix), "{tag}: out of order at {prefix}");
        }
    }
}

async fn silent_mod_outbox(fx: &Fx, startup: &str, register: &str) -> Config {
    let cfg = fx.config();
    let old = format!("{startup}\n{register}\n");
    fs::write(&cfg.outbox, &old).await.unwrap();
    pin_cursor(&cfg.outbox, old.len() as u64).await;
    cfg
}

fn block_cursor(outbox: &Path) {
    let cursor = cursor_path(outbox);
    let _ = std::fs::remove_file(&cursor);
    std::fs::create_dir_all(&cursor).unwrap();
    std::fs::write(cursor.join("keep"), b"x").unwrap();
}

#[tokio::test]
async fn a_result_reaches_the_wire_in_time_while_the_cursor_cannot_be_written() {
    let fx = Fx::new("result_in_time_cursor_failure");
    let (listener, cfg) = fx.listen().await;
    block_cursor(&cfg.outbox);
    let context = "{\"command\":\"context\",\"game\":\"Balatro\",\"data\":{\"message\":\"FIRST\",\"silent\":true}}\n";
    fs::write(&cfg.outbox, STARTUP).await.unwrap();
    mod_answers_later(&cfg.outbox, &format!("{STARTUP}{context}"));
    let (outbox, inbox) = (cfg.outbox.clone(), cfg.inbox.clone());
    let server = tokio::spawn(async move {
        let mut ws = accept_ws(&listener).await;
        let start = Instant::now();
        let mut acted = None;
        while start.elapsed() < Duration::from_secs(10) {
            if acted.is_none() && start.elapsed() > Duration::from_secs(1) {
                ws.send(Message::Text(
                    r#"{"command":"action","data":{"id":"a1","name":"play_hand"}}"#.into(),
                ))
                .await
                .unwrap();
                acted = Some(Instant::now());
                let (outbox, inbox) = (outbox.clone(), inbox.clone());
                tokio::spawn(async move {
                    while !std::fs::read_to_string(&inbox)
                        .unwrap_or_default()
                        .contains("\"a1\"")
                    {
                        time::sleep(Duration::from_millis(20)).await;
                    }
                    append_outbox(&outbox, "{\"command\":\"action/result\",\"game\":\"Balatro\",\"data\":{\"id\":\"a1\",\"success\":true}}\n");
                });
            }
            if let Ok(Some(Ok(Message::Text(text)))) =
                time::timeout(Duration::from_millis(100), ws.next()).await
            {
                if text.contains("\"a1\"") {
                    return acted.map(|at| at.elapsed());
                }
            }
        }
        None
    });
    let _ = run_bounded(11, &cfg, new_pending()).await;
    let waited = server.await.unwrap();
    assert!(
        waited.is_some_and(|waited| waited < Duration::from_secs(5)),
        "the result of an action the game ran reached the wire after {waited:?}"
    );
}

fn rotate(path: &Path, fresh: &str) {
    std::fs::rename(path, rotated_path(path)).unwrap();
    std::fs::write(path, fresh).unwrap();
}

// Drain the rotated generation first so a result racing the rename can still reach the wire.
#[tokio::test]
async fn a_result_appended_just_before_outbox_rotation_still_reaches_the_wire() {
    let fx = Fx::new("session_rotation");
    let (listener, cfg) = fx.listen().await;
    fs::write(&cfg.outbox, "").await.unwrap();
    let writer_outbox = cfg.outbox.clone();
    tokio::spawn(async move {
        time::sleep(Duration::from_millis(300)).await;
        append_outbox(&writer_outbox, STARTUP);
        time::sleep(Duration::from_millis(1500)).await;
        append_outbox(
            &writer_outbox,
            "{\"command\":\"action/result\",\"game\":\"Balatro\",\"data\":{\"id\":\"r1\",\"success\":true,\"message\":\"BEFORE-ROTATE\"}}\n",
        );
        rotate(
            &writer_outbox,
            "{\"command\":\"context\",\"game\":\"Balatro\",\"data\":{\"message\":\"AFTER-ROTATE\",\"silent\":true}}\n",
        );
    });
    let server = tokio::spawn(async move {
        let mut ws = accept_ws(&listener).await;
        let mut frames = Vec::new();
        let deadline = time::sleep(Duration::from_millis(4000));
        tokio::pin!(deadline);
        loop {
            tokio::select! {
                _ = &mut deadline => break,
                frame = ws.next() => match frame {
                    Some(Ok(Message::Text(text))) => {
                        let done = text.contains("AFTER-ROTATE");
                        frames.push(text.to_string());
                        if done {
                            break;
                        }
                    }
                    Some(Ok(_)) => {}
                    _ => break,
                },
            }
        }
        let _ = ws.close(None).await;
        frames
    });
    let _ = run_bounded(10, &cfg, new_pending()).await;
    let frames = server.await.unwrap();
    let before = frames.iter().position(|f| f.contains("BEFORE-ROTATE"));
    let after = frames.iter().position(|f| f.contains("AFTER-ROTATE"));
    assert!(
        before.is_some() && after.is_some() && before < after,
        "the rotated tail must reach the wire before the new file: {frames:?}"
    );
}

fn answer_tag_line(session: u64) -> String {
    format!("{{\"command\":\"neuro-bridge/startup_answer\",\"game\":\"Balatro\",\"transport_session\":\"{session}\"}}\n")
}

async fn asked_session(inbox: &Path) -> u64 {
    for _ in 0..200 {
        let text = fs::read_to_string(inbox).await.unwrap_or_default();
        let asked = text
            .lines()
            .filter_map(|line| serde_json::from_str::<Value>(line).ok())
            .find(|value| value["command"] == "neuro-bridge/reregister_all")
            .and_then(|value| value["transport_session"].as_u64());
        if let Some(session) = asked {
            return session;
        }
        time::sleep(Duration::from_millis(25)).await;
    }
    panic!("the relay never asked the mod to reregister");
}

#[tokio::test]
async fn a_stale_answer_and_its_force_ahead_of_this_sessions_answer_never_reach_the_sdk() {
    let startup = r#"{"command":"startup","game":"Balatro"}"#;
    let register = r#"{"command":"actions/register","game":"Balatro","data":{"actions":[{"name":"play_hand","description":"Play."}]}}"#;
    let stale_force = "{\"command\":\"actions/force\",\"game\":\"Balatro\",\"data\":{\"query\":\"F-STALE\",\"action_names\":[\"play_hand\"]}}\n";
    let live_force = "{\"command\":\"actions/force\",\"game\":\"Balatro\",\"data\":{\"query\":\"F-LIVE\",\"action_names\":[\"play_hand\"]}}\n";
    {
        let fx = Fx::new("stale_answer_ahead");
        let mut cfg = silent_mod_outbox(&fx, startup, register).await;
        std::fs::write(
            fx.dir.join(format!("{TRANSPORT_SESSION_MARKER_PREFIX}7")),
            "7",
        )
        .unwrap();
        append_outbox(
            &cfg.outbox,
            &format!("{}{startup}\n{register}\n{stale_force}", answer_tag_line(7)),
        );
        let (outbox, inbox) = (cfg.outbox.clone(), cfg.inbox.clone());
        tokio::spawn(async move {
            let session = asked_session(&inbox).await;
            assert_eq!(session, 8);
            time::sleep(Duration::from_millis(200)).await;
            append_outbox(
                &outbox,
                &format!(
                    "{}{startup}\n{register}\n{live_force}",
                    answer_tag_line(session)
                ),
            );
        });
        let frames = wire_of_session(&mut cfg, "F-LIVE").await;
        assert!(!frames.iter().any(|f| f.contains("F-STALE")), "{frames:?}");
        assert_eq!(
            wire_commands(&frames),
            ["startup", "actions/register", "actions/force"],
            "{frames:?}"
        );
        let len = fs::metadata(&cfg.outbox).await.unwrap().len();
        assert_eq!(load_cursor(&cfg.outbox).await.map(|c| c.pos), Some(len));
    }
}

#[tokio::test]
async fn an_untagged_launch_behind_a_stale_answer_binds_the_session() {
    let startup = r#"{"command":"startup","game":"Balatro"}"#;
    let register = r#"{"command":"actions/register","game":"Balatro","data":{"actions":[{"name":"play_hand","description":"Play."}]}}"#;
    let fx = Fx::new("untagged_launch_binds");
    let mut cfg = silent_mod_outbox(&fx, startup, register).await;
    std::fs::write(
        fx.dir.join(format!("{TRANSPORT_SESSION_MARKER_PREFIX}7")),
        "7",
    )
    .unwrap();
    append_outbox(
        &cfg.outbox,
        &format!(
            "{}{startup}\n{register}\n{}{startup}\n{register}\n{}",
            answer_tag_line(7),
            "{\"command\":\"actions/force\",\"game\":\"Balatro\",\"data\":{\"query\":\"F-STALE\",\"action_names\":[\"play_hand\"]}}\n",
            "{\"command\":\"actions/force\",\"game\":\"Balatro\",\"data\":{\"query\":\"F-LAUNCH\",\"action_names\":[\"play_hand\"]}}\n",
        ),
    );
    let frames = wire_of_session(&mut cfg, "F-LAUNCH").await;
    assert!(!frames.iter().any(|f| f.contains("F-STALE")), "{frames:?}");
    assert_eq!(
        wire_commands(&frames),
        ["startup", "actions/register", "actions/force"],
        "{frames:?}"
    );
}

#[tokio::test]
async fn the_cursor_never_rests_between_an_answer_tag_and_its_startup() {
    let startup = r#"{"command":"startup","game":"Balatro"}"#;
    let register = r#"{"command":"actions/register","game":"Balatro","data":{"actions":[{"name":"play_hand","description":"Play."}]}}"#;
    let fx = Fx::new("cursor_before_answer_tag");
    let mut cfg = silent_mod_outbox(&fx, startup, register).await;
    append_outbox(&cfg.outbox, &format!("{startup}\n"));
    let before_tag = fs::metadata(&cfg.outbox).await.unwrap().len();
    let (outbox, inbox) = (cfg.outbox.clone(), cfg.inbox.clone());
    tokio::spawn(async move {
        let session = asked_session(&inbox).await;
        time::sleep(Duration::from_millis(300)).await;
        append_outbox(&outbox, &answer_tag_line(session));
    });
    let frames = wire_of_session(&mut cfg, "never").await;
    assert_eq!(wire_commands(&frames), ["startup"], "{frames:?}");
    assert_eq!(
        load_cursor(&cfg.outbox).await.map(|c| c.pos),
        Some(before_tag)
    );
}

#[tokio::test]
async fn a_torn_cursor_write_keeps_the_last_durable_checkpoint() {
    let (_fx, outbox, ends) = cursor_fixture(
        "cursor_torn",
        &[
            "{\"command\":\"context\"}\n",
            "{\"command\":\"action/result\"}\n",
            "{\"command\":\"context\"}\n",
        ],
    );
    let cursor = cursor_path(&outbox);
    let mut tmp = cursor.clone().into_os_string();
    tmp.push(".tmp");
    persist_cursor(&outbox, ends[0]).await.unwrap();
    persist_cursor(&outbox, ends[1]).await.unwrap();
    let durable = std::fs::read(&cursor).unwrap();
    let file = std::fs::File::open(&outbox).unwrap();
    let len = file.metadata().unwrap().len();
    let next = Cursor {
        pos: ends[2].pos,
        len,
        id: ends[2].id.unwrap(),
        fingerprint: fingerprint(&file, ends[2].pos, len).unwrap(),
    }
    .encode();
    for written in 0..next.len() {
        for filler in [None, Some(0u8), Some(0xff)] {
            let mut torn = next[..written].to_vec();
            if let Some(filler) = filler {
                torn.resize(next.len(), filler);
            }
            std::fs::write(&tmp, &torn).unwrap();
            assert_eq!(
                load_cursor(&outbox).await,
                Some(ends[1]),
                "{written} bytes, rest {filler:?}"
            );
            if torn[..] != next[..] {
                std::fs::write(&cursor, &torn).unwrap();
                assert_eq!(
                    load_cursor(&outbox).await,
                    None,
                    "{written} bytes, rest {filler:?}"
                );
                std::fs::write(&cursor, &durable).unwrap();
            }
        }
    }
    persist_cursor(&outbox, ends[2]).await.unwrap();
    assert_eq!(std::fs::read(&cursor).unwrap(), next);
    assert_eq!(load_cursor(&outbox).await, Some(ends[2]));
}

#[tokio::test]
async fn no_websocket_is_opened_before_the_game_answers_with_its_startup() {
    let fx = Fx::new("parity_connect_after_startup");
    let (listener, cfg) = fx.listen().await;
    fs::write(&cfg.outbox, STARTUP).await.unwrap();
    let outbox = cfg.outbox.clone();
    let session = spawn_session(cfg, new_pending());

    assert!(
        time::timeout(Duration::from_millis(1500), listener.accept())
            .await
            .is_err(),
        "a socket was opened for a game that has not answered"
    );
    append_outbox(&outbox, STARTUP);
    let (stream, _) = time::timeout(Duration::from_secs(5), listener.accept())
        .await
        .expect("the game's startup must open the socket")
        .unwrap();
    let mut ws = tokio_tungstenite::accept_async(stream).await.unwrap();
    let first = time::timeout(Duration::from_secs(5), ws.next())
        .await
        .unwrap();
    match first {
        Some(Ok(Message::Text(text))) => assert_eq!(text, STARTUP.trim_end()),
        other => panic!("startup must be the first frame, got {other:?}"),
    }
    let _ = ws.close(None).await;
    session.abort();
}

#[tokio::test]
async fn a_refused_connection_is_retried_on_the_reference_interval() {
    let fx = Fx::new("parity_connect_retry");
    let probe = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
    let addr = probe.local_addr().unwrap();
    drop(probe);
    let cfg = fx.config_at(addr);
    fs::write(&cfg.outbox, "").await.unwrap();
    mod_answers_later(&cfg.outbox, STARTUP);
    let started = Instant::now();
    let session = spawn_session(cfg, new_pending());

    time::sleep(Duration::from_millis(1000)).await;
    let listener = tokio::net::TcpListener::bind(addr).await.unwrap();
    let (stream, _) = time::timeout(Duration::from_secs(6), listener.accept())
        .await
        .expect("the relay must retry the refused connection")
        .unwrap();
    assert!(started.elapsed() >= Duration::from_secs(RECONNECT_INTERVAL_SECS));
    let mut ws = tokio_tungstenite::accept_async(stream).await.unwrap();
    let first = time::timeout(Duration::from_secs(5), ws.next())
        .await
        .unwrap();
    assert!(matches!(first, Some(Ok(Message::Text(text))) if text.contains("startup")));
    let _ = ws.close(None).await;
    session.abort();
}

#[tokio::test]
async fn the_relay_hands_every_action_to_the_game_and_never_answers_one_itself() {
    let fx = Fx::new("parity_no_synthetic_results");
    let (listener, cfg) = fx.listen().await;
    let inbox = cfg.inbox.clone();
    fs::write(&cfg.outbox, "").await.unwrap();
    mod_answers_later(&cfg.outbox, STARTUP);
    let session = spawn_session(cfg, new_pending());

    let mut ws = accept_ws(&listener).await;
    let _startup = ws.next().await;
    ws.send(Message::Text(
        r#"{"command":"action","data":{"id":"text-1","name":"play_hand","data":"{}"}}"#.into(),
    ))
    .await
    .unwrap();
    ws.send(Message::Binary(
        br#"{"command":"action","game":"Balatro","data":{"id":"binary-1","name":"play_hand"}}"#
            .as_slice()
            .into(),
    ))
    .await
    .unwrap();
    let answered = collect_frames(&mut ws, Duration::from_millis(2500), |_| false).await;
    assert!(
        answered.is_empty(),
        "the relay put frames on the wire the game never wrote: {answered:?}"
    );
    let delivered = fs::read_to_string(&inbox).await.unwrap_or_default();
    assert!(delivered.contains("text-1"), "{delivered}");
    assert!(delivered.contains("binary-1"), "{delivered}");
    let _ = ws.close(None).await;
    session.abort();
}

#[tokio::test]
async fn shutdown_unregisters_what_the_game_still_holds_then_closes() {
    let fx = Fx::new("parity_quit_unregister");
    let (listener, cfg) = fx.listen().await;
    fs::write(&cfg.outbox, "").await.unwrap();
    mod_answers_later(
        &cfg.outbox,
        concat!(
            "{\"command\":\"startup\",\"game\":\"Balatro\"}\n",
            "{\"command\":\"actions/register\",\"game\":\"Balatro\",\"data\":{\"actions\":[{\"name\":\"a\",\"description\":\"A\"},{\"name\":\"b\",\"description\":\"B\"}]}}\n",
            "{\"command\":\"actions/unregister\",\"game\":\"Balatro\",\"data\":{\"action_names\":[\"a\"]}}\n",
        ),
    );
    let (stop_tx, stop_rx) = tokio::sync::watch::channel(false);
    let pending = new_pending();
    let session = tokio::spawn(async move { run_session(&cfg, pending, stop_rx).await });

    let mut ws = accept_ws(&listener).await;
    let mut frames = Vec::new();
    while frames.len() < 3 {
        match time::timeout(Duration::from_secs(5), ws.next()).await {
            Ok(Some(Ok(Message::Text(text)))) => frames.push(text),
            other => panic!("expected the game's frames, got {other:?}"),
        }
    }
    stop_tx.send(true).unwrap();
    let quit = match time::timeout(Duration::from_secs(5), ws.next()).await {
        Ok(Some(Ok(Message::Text(text)))) => text,
        other => panic!("expected the quit unregister, got {other:?}"),
    };
    let quit: Value = serde_json::from_str(&quit).unwrap();
    assert_eq!(quit["command"], "actions/unregister");
    assert_eq!(quit["game"], "Balatro");
    assert_eq!(quit["data"]["action_names"], serde_json::json!(["b"]));
    assert!(matches!(
        time::timeout(Duration::from_secs(5), ws.next()).await,
        Ok(Some(Ok(Message::Close(_)))) | Ok(None)
    ));
    time::timeout(Duration::from_secs(5), session)
        .await
        .expect("a stopped session must end")
        .unwrap()
        .unwrap();
}

const LIVENESS_REGISTER: &str = "{\"command\":\"actions/register\",\"game\":\"Balatro\",\"data\":{\"actions\":[{\"name\":\"play_hand\",\"description\":\"Play.\"}]}}\n";

fn liveness_config(cfg: Config) -> Config {
    Config {
        game_stale_after: Duration::from_secs(2),
        ..cfg
    }
}

fn beating_game(path: PathBuf, beating: Arc<AtomicBool>) -> tokio::task::JoinHandle<()> {
    tokio::spawn(async move {
        let mut beat = 0u64;
        while beating.load(Ordering::Relaxed) {
            beat += 1;
            let _ = fs::write(&path, format!("{beat}\n")).await;
            time::sleep(Duration::from_millis(200)).await;
        }
    })
}

async fn accept_live_game(listener: &tokio::net::TcpListener, outbox: &Path) -> ServerWs {
    asked_session(&outbox.with_file_name("neuro_inbox.jsonl")).await;
    append_outbox(outbox, &format!("{STARTUP}{LIVENESS_REGISTER}"));
    let (stream, _) = time::timeout(Duration::from_secs(5), listener.accept())
        .await
        .expect("the game's startup must open the socket")
        .unwrap();
    let mut ws = tokio_tungstenite::accept_async(stream).await.unwrap();
    ws.send(Message::Text(
        "{\"command\":\"action\",\"data\":{\"id\":\"lost-1\",\"name\":\"play_hand\"}}".into(),
    ))
    .await
    .unwrap();
    ws
}

async fn frames_until_close(ws: &mut ServerWs, within: Duration) -> Option<Vec<String>> {
    let deadline = time::Instant::now() + within;
    let mut frames = Vec::new();
    loop {
        match time::timeout_at(deadline, ws.next()).await {
            Err(_) => return None,
            Ok(Some(Ok(Message::Text(text)))) => frames.push(text.to_string()),
            Ok(Some(Ok(Message::Close(_)))) | Ok(Some(Err(_))) | Ok(None) => return Some(frames),
            Ok(Some(Ok(_))) => {}
        }
    }
}

#[tokio::test]
async fn a_game_whose_heartbeat_stops_loses_its_socket_and_nothing_is_sent_for_it() {
    let fx = Fx::new("liveness_stale");
    let (listener, cfg) = fx.listen().await;
    let cfg = liveness_config(cfg);
    fs::write(&cfg.outbox, "").await.unwrap();
    let beating = Arc::new(AtomicBool::new(true));
    let game = beating_game(cfg.heartbeat(), Arc::clone(&beating));
    let outbox = cfg.outbox.clone();
    let pending = new_pending();
    let session = tokio::spawn(async move {
        let result = run_session(&cfg, pending, never_stop()).await;
        (cfg, result)
    });

    let mut ws = accept_live_game(&listener, &outbox).await;
    time::sleep(Duration::from_millis(1500)).await;
    beating.store(false, Ordering::Relaxed);
    game.await.unwrap();
    let frames = frames_until_close(&mut ws, Duration::from_secs(8))
        .await
        .expect("a game that stopped beating must lose its socket");
    assert_eq!(
        wire_commands(&frames),
        ["startup", "actions/register"],
        "{frames:?}"
    );
    let (cfg, result) = time::timeout(Duration::from_secs(5), session)
        .await
        .expect("the session must end with the socket")
        .unwrap();
    result.unwrap();

    let next = spawn_session(cfg, new_pending());
    assert!(
        time::timeout(Duration::from_millis(2500), listener.accept())
            .await
            .is_err(),
        "a socket was reopened for a dead game"
    );
    next.abort();
}

#[tokio::test]
async fn a_beating_game_or_a_mod_that_never_beats_keeps_its_socket() {
    for beats in [true, false] {
        let fx = Fx::new("liveness_fresh");
        let (listener, cfg) = fx.listen().await;
        let cfg = liveness_config(cfg);
        fs::write(&cfg.outbox, "").await.unwrap();
        let beating = Arc::new(AtomicBool::new(beats));
        fs::write(cfg.heartbeat(), "7\n").await.unwrap();
        let game = beating_game(cfg.heartbeat(), Arc::clone(&beating));
        let outbox = cfg.outbox.clone();
        let session = spawn_session(cfg, new_pending());

        let mut ws = accept_live_game(&listener, &outbox).await;
        assert!(
            frames_until_close(&mut ws, Duration::from_secs(5))
                .await
                .is_none(),
            "the socket closed although the game {}",
            if beats { "beats" } else { "never beat" }
        );
        assert!(!session.is_finished());
        beating.store(false, Ordering::Relaxed);
        game.await.unwrap();
        session.abort();
    }
}

async fn inbox_holds(inbox: &Path, text: &str) {
    for _ in 0..200 {
        if fs::read_to_string(inbox)
            .await
            .unwrap_or_default()
            .contains(text)
        {
            return;
        }
        time::sleep(Duration::from_millis(25)).await;
    }
    panic!("the inbox never received {text}");
}

#[tokio::test]
async fn a_game_that_dies_owing_a_result_loses_its_socket_before_the_server_gives_up() {
    let fx = Fx::new("liveness_owed");
    let (listener, cfg) = fx.listen().await;
    fs::write(&cfg.outbox, "").await.unwrap();
    let beating = Arc::new(AtomicBool::new(true));
    let game = beating_game(cfg.heartbeat(), Arc::clone(&beating));
    let (outbox, inbox) = (cfg.outbox.clone(), cfg.inbox.clone());
    let session = spawn_session(cfg, new_pending());

    let mut ws = accept_live_game(&listener, &outbox).await;
    inbox_holds(&inbox, "lost-1").await;
    time::sleep(Duration::from_millis(1500)).await;
    beating.store(false, Ordering::Relaxed);
    game.await.unwrap();
    let frames = frames_until_close(&mut ws, Duration::from_secs(14))
        .await
        .expect("a dead game owing a result must lose its socket within 14 s");
    assert_eq!(
        wire_commands(&frames),
        ["startup", "actions/register"],
        "{frames:?}"
    );
    session.abort();
}

#[tokio::test]
async fn a_relaunched_games_startup_goes_out_on_a_fresh_connection() {
    for tagged in [false, true] {
        let fx = Fx::new("restart_fresh_connection");
        let (listener, cfg) = fx.listen().await;
        let addr = listener.local_addr().unwrap();
        fs::write(&cfg.outbox, "").await.unwrap();
        let (outbox, inbox) = (cfg.outbox.clone(), cfg.inbox.clone());
        let session = spawn_session(cfg, new_pending());

        let mut ws = accept_live_game(&listener, &outbox).await;
        inbox_holds(&inbox, "lost-1").await;
        let tag = if tagged {
            answer_tag_line(asked_session(&inbox).await)
        } else {
            String::new()
        };
        append_outbox(&outbox, &format!("{tag}{STARTUP}{LIVENESS_REGISTER}"));
        let frames = frames_until_close(&mut ws, Duration::from_secs(5))
            .await
            .expect("the relaunched game's startup must not share the old connection");
        assert_eq!(
            wire_commands(&frames),
            ["startup", "actions/register"],
            "{frames:?}"
        );
        time::timeout(Duration::from_secs(5), session)
            .await
            .expect("the session must end with its socket")
            .unwrap()
            .unwrap();

        let next = spawn_session(fx.config_at(addr), new_pending());
        if tagged {
            let asked = nth_asked_session(&inbox, 1).await;
            append_outbox(
                &outbox,
                &format!("{}{STARTUP}{LIVENESS_REGISTER}", answer_tag_line(asked)),
            );
        }
        let (stream, _) = time::timeout(Duration::from_secs(5), listener.accept())
            .await
            .expect("the relaunched game's startup must open a new socket")
            .unwrap();
        let mut ws = tokio_tungstenite::accept_async(stream).await.unwrap();
        let frames = collect_frames(&mut ws, Duration::from_millis(1500), |_| false).await;
        assert_eq!(
            wire_commands(&frames),
            ["startup", "actions/register"],
            "{frames:?}"
        );
        next.abort();
    }
}

#[tokio::test]
async fn a_wss_url_reaches_the_tls_handshake() {
    use tokio::io::AsyncReadExt as _;
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let url = format!("wss://localhost:{}", listener.local_addr().unwrap().port());
    let server = tokio::spawn(async move {
        let (mut stream, _) = listener.accept().await.unwrap();
        let mut record_type = [0u8; 1];
        stream.read_exact(&mut record_type).await.unwrap();
        record_type[0]
    });
    let error = connect_websocket(&url)
        .await
        .expect_err("a server that never answers the TLS hello cannot complete the handshake");
    assert!(
        !format!("{error:#}").contains("TLS support not compiled in"),
        "{error:#}"
    );
    assert_eq!(
        server.await.unwrap(),
        0x16,
        "the relay must open with a TLS handshake record"
    );
}

async fn inbox_after_frames(
    tag: &str,
    pending: Arc<Mutex<PendingTracker>>,
    frames: Vec<Message>,
) -> String {
    let fx = Fx::new(tag);
    let inbox = fx.dir.join("neuro_inbox.jsonl");
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    tokio::spawn(async move {
        let mut ws = accept_ws(&listener).await;
        for frame in frames {
            ws.send(frame).await.unwrap();
        }
        let _ = ws.close(None).await;
    });
    let stream = connect_websocket(&format!("ws://{addr}")).await.unwrap();
    let (_write, read) = stream.split();
    time::timeout(
        Duration::from_secs(10),
        receive_task(ReceiveTask {
            ws_read: read,
            inbox_path: inbox.clone(),
            pending_rx: pending,
            shutdown_rx: Arc::new(AtomicBool::new(false)),
        }),
    )
    .await
    .expect("receive task did not finish");
    fs::read_to_string(&inbox).await.unwrap_or_default()
}

#[tokio::test]
async fn actions_past_the_inbound_rate_are_delayed_not_dropped() {
    let count = MAX_INBOUND_SPOOL_RATE_RECORDS + 44;
    let frames = (0..count)
        .map(|i| {
            Message::Text(
                format!(r#"{{"command":"action","data":{{"id":"burst-{i}","name":"help"}}}}"#)
                    .into(),
            )
        })
        .collect();
    let delivered = inbox_after_frames("inbound_rate_burst", new_pending(), frames).await;
    for i in 0..count {
        assert!(
            delivered.contains(&format!("\"burst-{i}\"")),
            "action burst-{i} was dropped"
        );
    }
}

#[tokio::test]
async fn an_inbox_that_can_never_take_a_record_ends_the_receive_half_at_once() {
    let fx = Fx::new("inbox_not_a_file");
    let inbox = fx.dir.join("neuro_inbox.jsonl");
    fs::create_dir_all(&inbox).await.unwrap();
    let frames: Vec<Result<Message, tokio_tungstenite::tungstenite::Error>> = vec![Ok(
        Message::Text(r#"{"command":"action","data":{"id":"a1","name":"play"}}"#.into()),
    )];
    time::timeout(
        Duration::from_secs(1),
        receive_task(ReceiveTask {
            ws_read: futures_util::stream::iter(frames),
            inbox_path: inbox,
            pending_rx: new_pending(),
            shutdown_rx: Arc::new(AtomicBool::new(false)),
        }),
    )
    .await
    .expect("a deterministic inbox failure was retried");
    let busy = anyhow::Error::from(std::io::Error::from(std::io::ErrorKind::ResourceBusy));
    assert!(transient(&busy.context("open inbox")));
    let refused = anyhow::Error::from(std::io::Error::from(std::io::ErrorKind::PermissionDenied));
    assert!(!transient(&refused));
}

#[tokio::test]
async fn an_oversized_inbound_frame_is_ignored_and_the_next_action_arrives() {
    let big = format!(
        "{{\"command\":\"junk\",\"data\":{{\"x\":\"{}\"}}}}",
        "x".repeat(MAX_COMMAND_BYTES + 10)
    );
    let after = r#"{"command":"action","data":{"id":"after","name":"help"}}"#;
    let delivered = inbox_after_frames(
        "oversized_inbound",
        new_pending(),
        vec![Message::Text(big.into()), Message::Text(after.into())],
    )
    .await;
    assert!(delivered.contains("\"after\""), "{delivered:?}");
    assert!(!delivered.contains("junk"), "{delivered:?}");
}

#[tokio::test]
async fn a_pretty_printed_notification_reaches_the_mod_and_the_next_action_arrives() {
    let frames = [
        "{\n  \"command\": \"startup\",\n  \"data\": {\n    \"session\": {\"characterId\": \"neuro\"}\n  }\n}",
        "{\n\"command\":\"startup\",\"data\":{\"session\":{\"characterId\":\"neuro\"}}}",
        r#"{"command":"neuro-bridge/reregister_all","command":"startup","data":{"session":{"characterId":"neuro"}}}"#,
        r#"{"command":"speech_finished","data":{"isFinal":true}}"#,
        r#"{"command":"action","data":{"id":"after-pretty","name":"help"}}"#,
    ];
    let delivered = inbox_after_frames(
        "pretty_inbound",
        new_pending(),
        frames.map(|frame| Message::Text(frame.into())).to_vec(),
    )
    .await;
    assert_eq!(
        delivered.lines().collect::<Vec<_>>(),
        [
            r#"{"command":"startup","data":{"session":{"characterId":"neuro"}}}"#,
            r#"{"command":"startup","data":{"session":{"characterId":"neuro"}}}"#,
            r#"{"command":"startup","data":{"session":{"characterId":"neuro"}}}"#,
            r#"{"command":"action","data":{"id":"after-pretty","name":"help"}}"#,
        ]
    );
}

#[tokio::test]
async fn a_new_connection_delivers_an_id_the_last_one_answered() {
    let pending = new_pending();
    {
        let mut tracker = pending.lock().unwrap();
        tracker.bind_game("Balatro");
        tracker.begin_session();
        assert!(tracker.admit_action("0"));
        tracker.observe_result("0");
        tracker.begin_session();
    }
    let action = |id: &str| {
        Message::Text(
            format!(r#"{{"command":"action","data":{{"id":"{id}","name":"help"}}}}"#).into(),
        )
    };
    let delivered = inbox_after_frames("reused_id", pending, vec![action("0"), action("1")]).await;
    assert!(delivered.contains("\"id\":\"0\""), "{delivered:?}");
    assert!(delivered.contains("\"id\":\"1\""), "{delivered:?}");
}

fn action_result_line(id: &str) -> String {
    format!("{{\"command\":\"action/result\",\"game\":\"Balatro\",\"data\":{{\"id\":\"{id}\",\"success\":true}}}}\n")
}

#[tokio::test]
async fn a_result_for_an_action_of_the_previous_connection_never_reaches_the_new_one() {
    let fx = Fx::new("stale_result_after_reconnect");
    let (listener, cfg) = fx.listen().await;
    fs::write(&cfg.outbox, "").await.unwrap();
    let (outbox, inbox) = (cfg.outbox.clone(), cfg.inbox.clone());
    let pending = new_pending();
    let first = spawn_session(
        fx.config_at(listener.local_addr().unwrap()),
        Arc::clone(&pending),
    );
    let mut ws = accept_live_game(&listener, &outbox).await;
    ws.send(Message::Text(
        "{\"command\":\"action\",\"data\":{\"id\":\"lost-2\",\"name\":\"play_hand\"}}".into(),
    ))
    .await
    .unwrap();
    inbox_holds(&inbox, "lost-2").await;
    let _ = ws.close(None).await;
    drop(ws);
    time::timeout(Duration::from_secs(10), first)
        .await
        .expect("the first session must end with its socket")
        .unwrap()
        .unwrap();

    append_outbox(&outbox, &action_result_line("lost-1"));
    let second = spawn_session(cfg, pending);
    nth_asked_session(&inbox, 1).await;
    append_outbox(
        &outbox,
        &format!(
            "{STARTUP}{LIVENESS_REGISTER}{}",
            action_result_line("lost-2")
        ),
    );
    let (stream, _) = time::timeout(Duration::from_secs(5), listener.accept())
        .await
        .expect("the new startup must open a socket")
        .unwrap();
    let mut ws = tokio_tungstenite::accept_async(stream).await.unwrap();
    ws.send(Message::Text(
        "{\"command\":\"action\",\"data\":{\"id\":\"live-1\",\"name\":\"play_hand\"}}".into(),
    ))
    .await
    .unwrap();
    inbox_holds(&inbox, "live-1").await;
    append_outbox(&outbox, &action_result_line("live-1"));
    let frames = collect_frames(&mut ws, Duration::from_secs(3), |text| {
        text.contains("live-1")
    })
    .await;
    assert!(!frames.iter().any(|f| f.contains("lost-")), "{frames:#?}");
    assert_eq!(
        wire_commands(&frames),
        ["startup", "actions/register", "action/result"],
        "{frames:#?}"
    );
    second.abort();
}

#[tokio::test]
async fn a_restarted_relay_drops_a_result_written_before_its_startup() {
    let fx = Fx::new("stale_result_after_restart");
    let (listener, cfg) = fx.listen().await;
    fs::write(&cfg.outbox, "").await.unwrap();
    let (outbox, inbox) = (cfg.outbox.clone(), cfg.inbox.clone());
    let first = spawn_session(fx.config_at(listener.local_addr().unwrap()), new_pending());
    let ws = accept_live_game(&listener, &outbox).await;
    inbox_holds(&inbox, "lost-1").await;
    first.abort();
    let _ = first.await;
    drop(ws);
    let end = fs::metadata(&outbox).await.unwrap().len();
    pin_cursor(&outbox, end).await;

    append_outbox(&outbox, &action_result_line("lost-1"));
    let second = spawn_session(cfg, new_pending());
    let asked = nth_asked_session(&inbox, 1).await;
    append_outbox(
        &outbox,
        &format!("{}{STARTUP}{LIVENESS_REGISTER}", answer_tag_line(asked)),
    );
    let (stream, _) = time::timeout(Duration::from_secs(5), listener.accept())
        .await
        .expect("the new startup must open a socket")
        .unwrap();
    let mut ws = tokio_tungstenite::accept_async(stream).await.unwrap();
    ws.send(Message::Text(
        "{\"command\":\"action\",\"data\":{\"id\":\"live-1\",\"name\":\"play_hand\"}}".into(),
    ))
    .await
    .unwrap();
    inbox_holds(&inbox, "live-1").await;
    append_outbox(&outbox, &action_result_line("live-1"));
    let frames = collect_frames(&mut ws, Duration::from_secs(3), |text| {
        text.contains("live-1")
    })
    .await;
    assert!(!frames.iter().any(|f| f.contains("lost-1")), "{frames:#?}");
    assert_eq!(
        wire_commands(&frames),
        ["startup", "actions/register", "action/result"],
        "{frames:#?}"
    );
    second.abort();
}
