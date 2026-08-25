use anyhow::{Context, Result};
use futures_util::{SinkExt, StreamExt};
use serde_json::Value;
use std::collections::{HashMap, HashSet};
use std::env;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::sync::Mutex;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::OnceLock;
use std::time::Instant;
use std::time::{SystemTime, UNIX_EPOCH};
use tokio::fs;
use tokio::io::{AsyncReadExt, AsyncSeekExt, AsyncWriteExt};
use tokio::sync::mpsc;
use tokio::time::{self, Duration};
use tokio_tungstenite::connect_async;
use tokio_tungstenite::tungstenite::Message;
use notify::{Watcher, RecursiveMode};

const DEFAULT_ORPHAN_TIMEOUT_SECS: u64 = 30;
const RECONNECT_INTERVAL_SECS: u64 = 3;

// core/bridge.lua RESULT_DEADLINE_SECS: the mod's own owed-result sweep must always get the first
// chance to answer, so the transport orphan timeout has to stay strictly above it.
const MOD_RESULT_DEADLINE_SECS: u64 = 5;

struct Config {
    ws_url: String,
    outbox: PathBuf,
    inbox: PathBuf,
    orphan_timeout: Duration,
}

// A configured value at or under the mod's own result deadline inverts the ordering the mod's test
// suite locks to the compile-time default, so it is refused outright rather than silently clamped.
fn parse_orphan_timeout_secs(raw: &str) -> Result<u64, String> {
    let secs: u64 = raw
        .parse()
        .map_err(|_| format!("NEURO_ORPHAN_TIMEOUT_SECS={:?} is not a valid positive integer", raw))?;
    if secs == 0 {
        return Err("NEURO_ORPHAN_TIMEOUT_SECS must be greater than zero".to_string());
    }
    if secs <= MOD_RESULT_DEADLINE_SECS {
        return Err(format!(
            "NEURO_ORPHAN_TIMEOUT_SECS={} must be greater than the mod's {}s result deadline (core/bridge.lua RESULT_DEADLINE_SECS); \
             a shorter transport timeout would let the bridge answer an orphaned action before the mod ever gets the chance to",
            secs, MOD_RESULT_DEADLINE_SECS
        ));
    }
    Ok(secs)
}

impl Config {
    fn from_env() -> Self {
        let ws_url =
            env::var("NEURO_SDK_WS_URL").unwrap_or_else(|_| "ws://127.0.0.1:8000".to_string());
        let ipc_dir = resolve_ipc_dir();
        let outbox = ipc_dir.join("neuro_outbox.jsonl");
        let inbox = ipc_dir.join("neuro_inbox.jsonl");
        let orphan_timeout = match env::var("NEURO_ORPHAN_TIMEOUT_SECS") {
            Ok(raw) if !raw.trim().is_empty() => match parse_orphan_timeout_secs(raw.trim()) {
                Ok(secs) => Duration::from_secs(secs),
                Err(message) => {
                    eprintln!("[Fatal] {}", message);
                    std::process::exit(1);
                }
            },
            _ => Duration::from_secs(DEFAULT_ORPHAN_TIMEOUT_SECS),
        };
        Self { ws_url, outbox, inbox, orphan_timeout }
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

type FileId = (u64, u64);

#[cfg(unix)]
fn file_identity(meta: &std::fs::Metadata) -> Option<FileId> {
    use std::os::unix::fs::MetadataExt;
    Some((meta.dev(), meta.ino()))
}

#[cfg(not(unix))]
fn file_identity(meta: &std::fs::Metadata) -> Option<FileId> {
    let created = meta.created().ok()?.duration_since(std::time::UNIX_EPOCH).ok()?;
    Some((created.as_secs(), created.subsec_nanos() as u64))
}

#[derive(Clone, Copy, Default, PartialEq, Eq, Debug)]
struct Resume {
    pos: u64,
    id: Option<FileId>,
}

struct Tailer {
    path: PathBuf,
    pos: u64,
    identity: Option<FileId>,
    buffer: String,
    discarding: bool,
}

impl Tailer {
    fn new(path: PathBuf, resume: Resume) -> Self {
        Self {
            path,
            pos: resume.pos,
            identity: resume.id,
            buffer: String::new(),
            discarding: false,
        }
    }

    fn rewind_to_start(&mut self) {
        self.pos = 0;
        self.buffer.clear();
        self.discarding = false;
    }

    async fn read_new_lines(&mut self) -> Result<Vec<(String, u64)>> {
        let meta = match fs::metadata(&self.path).await {
            Ok(m) => m,
            Err(_) => return Ok(Vec::new()),
        };
        let len = meta.len();
        let identity = file_identity(&meta);
        let replaced = match (self.identity, identity) {
            (Some(previous), Some(current)) => previous != current,
            _ => false,
        };
        self.identity = identity;
        if replaced {
            eprintln!(
                "[Warning] Outbox replaced by a new file (was at {}), re-reading from start",
                self.pos
            );
            self.rewind_to_start();
        } else if len < self.pos {
            eprintln!(
                "[Warning] Outbox shrank ({} < {}), re-reading from start",
                len, self.pos
            );
            self.rewind_to_start();
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
            if self.discarding {
                self.buffer.drain(..=idx);
                self.discarding = false;
                continue;
            }
            if idx > MAX_BUFFERED_LINE {
                eprintln!(
                    "[Error] Outbox line exceeded {} bytes; discarding line",
                    MAX_BUFFERED_LINE
                );
                self.buffer.drain(..=idx);
                continue;
            }
            let mut line = self.buffer[..idx].to_string();
            if line.ends_with('\r') {
                line.pop();
            }
            self.buffer.drain(..=idx);
            let end_pos = self.pos - self.buffer.len() as u64;
            if !line.trim().is_empty() {
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
    file.flush().await?;
    Ok(())
}

fn bootstrap_from_bytes(data: &[u8]) -> Vec<String> {
    let mut cache = BootstrapCache::default();
    for bytes in data.split(|byte| *byte == b'\n') {
        let Ok(line) = std::str::from_utf8(bytes) else {
            eprintln!("[Warning] Skipping outbox bootstrap line with invalid UTF-8");
            continue;
        };
        let line = line.strip_suffix('\r').unwrap_or(line);
        if line.trim().is_empty() {
            continue;
        }
        cache.observe(line);
    }
    cache.lines()
}

#[cfg(test)]
fn bootstrap_from_text(data: &str) -> Vec<String> {
    bootstrap_from_bytes(data.as_bytes())
}

async fn bootstrap_messages(path: &Path) -> Result<(u64, Vec<String>)> {
    if let Ok(meta) = fs::metadata(path).await {
        if meta.len() > 100 * 1024 * 1024 {
            eprintln!("[Warning] Outbox file too large ({} bytes), skipping bootstrap", meta.len());
            return Ok((meta.len(), Vec::new()));
        }
    }

    let bytes = match fs::read(path).await {
        Ok(bytes) => bytes,
        Err(e) => {
            if e.kind() == std::io::ErrorKind::NotFound {
                return Ok((0, Vec::new()));
            }
            eprintln!("[Warning] Could not read outbox: {}", e);
            let pos = fs::metadata(path).await.map(|m| m.len()).unwrap_or(0);
            return Ok((pos, Vec::new()));
        }
    };
    let complete_len = bytes
        .iter()
        .rposition(|byte| *byte == b'\n')
        .map(|index| index + 1)
        .unwrap_or(0);
    Ok((
        complete_len as u64,
        bootstrap_from_bytes(&bytes[..complete_len]),
    ))
}

#[derive(Default)]
struct BootstrapCache {
    startup: Option<String>,
    register: Option<String>,
    startup_sent: bool,
}

fn unregistered_names(line: &str) -> Vec<String> {
    let Ok(value) = serde_json::from_str::<Value>(line) else {
        return Vec::new();
    };
    value
        .get("data")
        .and_then(|d| d.get("action_names"))
        .and_then(Value::as_array)
        .map(|names| {
            names
                .iter()
                .filter_map(|n| n.as_str().map(|s| s.to_string()))
                .collect()
        })
        .unwrap_or_default()
}

enum RegisterPrune {
    Unchanged,
    Kept(String),
    Emptied,
}

fn register_without(line: &str, removed: &[String]) -> RegisterPrune {
    if removed.is_empty() {
        return RegisterPrune::Unchanged;
    }
    let Ok(mut value) = serde_json::from_str::<Value>(line) else {
        return RegisterPrune::Unchanged;
    };
    let Some(actions) = value
        .get_mut("data")
        .and_then(|data| data.get_mut("actions"))
        .and_then(Value::as_array_mut)
    else {
        return RegisterPrune::Unchanged;
    };
    let before = actions.len();
    actions.retain(|action| match action.get("name").and_then(Value::as_str) {
        Some(name) => !removed.iter().any(|dead| dead == name),
        None => true,
    });
    if actions.len() == before {
        return RegisterPrune::Unchanged;
    }
    if actions.is_empty() {
        return RegisterPrune::Emptied;
    }
    match serde_json::to_string(&value) {
        Ok(pruned) => RegisterPrune::Kept(pruned),
        Err(_) => RegisterPrune::Unchanged,
    }
}

// The mod sends actions/register as a DIFF against what it already registered (core/bridge.lua
// register_actions), announcing every removal as its own actions/unregister frame first. Overwriting
// on each register frame therefore replayed a truncated catalogue after two ordinary state changes.
fn register_merged(current: Option<&str>, line: &str) -> Option<String> {
    let current = current?;
    let (Ok(incoming), Ok(mut merged)) = (
        serde_json::from_str::<Value>(line),
        serde_json::from_str::<Value>(current),
    ) else {
        return None;
    };
    let incoming_actions = incoming
        .get("data")
        .and_then(|data| data.get("actions"))
        .and_then(Value::as_array)
        .cloned()?;
    let actions = merged
        .get_mut("data")
        .and_then(|data| data.get_mut("actions"))
        .and_then(Value::as_array_mut)?;
    for action in incoming_actions {
        let name = action
            .get("name")
            .and_then(Value::as_str)
            .map(str::to_string);
        match name.and_then(|name| {
            actions
                .iter_mut()
                .find(|held| held.get("name").and_then(Value::as_str) == Some(name.as_str()))
        }) {
            Some(slot) => *slot = action,
            None => actions.push(action),
        }
    }
    serde_json::to_string(&merged).ok()
}

impl BootstrapCache {
    fn observe(&mut self, line: &str) {
        if line.len() > 10 * 1024 * 1024
            || !(line.contains("\"startup\"")
                || line.contains("actions/register")
                || line.contains("actions/unregister"))
        {
            return;
        }
        match command_from_line(line).as_deref() {
            Some("startup") => {
                self.startup = Some(line.to_string());
                self.register = None;
            }
            Some("actions/register") => {
                self.register = register_merged(self.register.as_deref(), line)
                    .or_else(|| Some(line.to_string()))
            }
            Some("actions/unregister") => {
                let removed = unregistered_names(line);
                if let Some(current) = self.register.as_deref() {
                    match register_without(current, &removed) {
                        RegisterPrune::Kept(pruned) => self.register = Some(pruned),
                        RegisterPrune::Emptied => self.register = None,
                        RegisterPrune::Unchanged => {}
                    }
                }
            }
            _ => {}
        }
    }

    fn lines(&self) -> Vec<String> {
        self.startup
            .iter()
            .chain(self.register.iter())
            .cloned()
            .collect()
    }

    fn mark_startup_sent(&mut self) {
        self.startup_sent = true;
    }

    fn has_startup(&self) -> bool {
        self.startup.is_some()
    }

    fn replay_lines(&mut self) -> Vec<String> {
        let mut lines = Vec::new();
        if let Some(startup) = &self.startup {
            if !self.startup_sent {
                lines.push(startup.clone());
                self.startup_sent = true;
            }
        }
        lines.extend(self.register.iter().cloned());
        lines
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

const DROP_PREVIEW: usize = 200;
const SUPPORTED_C2S_COMMANDS: &[&str] = &[
    "startup",
    "context",
    "actions/register",
    "actions/unregister",
    "actions/force",
    "action/result",
];

fn drop_from_wire(reason: &str, line: &str) -> Option<String> {
    eprintln!(
        "[Error] Dropping outbox line ({}): {}",
        reason,
        line.chars().take(DROP_PREVIEW).collect::<String>()
    );
    None
}

// Keep transport metadata out of the SDK wire schema.
fn sanitize_for_wire(line: &str) -> Option<String> {
    let Ok(value) = serde_json::from_str::<Value>(line) else {
        return drop_from_wire("not valid JSON", line);
    };
    let Some(obj) = value.as_object() else {
        return drop_from_wire("not a JSON object", line);
    };
    let mut out = serde_json::Map::new();
    for key in ["command", "game", "data"] {
        if let Some(v) = obj.get(key) {
            out.insert(key.to_string(), v.clone());
        }
    }
    let Some(command) = out
        .get("command")
        .and_then(Value::as_str)
        .map(str::to_string)
    else {
        return drop_from_wire("no command field", line);
    };
    let Some(game) = out.get("game").and_then(Value::as_str) else {
        return drop_from_wire("no game field", line);
    };
    if game.trim().is_empty() {
        return drop_from_wire("empty game field", line);
    }
    if !SUPPORTED_C2S_COMMANDS.contains(&command.as_str()) {
        return drop_from_wire("unsupported command", line);
    }

    if command == "startup" {
        out.remove("data");
    }

    if command == "action/result" {
        if let Some(Value::Object(data)) = out.get_mut("data") {
            data.retain(|k, _| matches!(k.as_str(), "id" | "success" | "message"));
        }
    } else if command == "context" {
        if let Some(Value::Object(data)) = out.get_mut("data") {
            data.retain(|k, _| matches!(k.as_str(), "message" | "silent"));
        }
    } else if command == "actions/register" {
        if let Some(Value::Object(data)) = out.get_mut("data") {
            data.retain(|k, _| matches!(k.as_str(), "actions"));
            // SPECIFICATION.md:95-111 says nothing about a partly invalid batch, and no reference
            // implementation discards one: Randy/index.ts:64-67 registers every element it is
            // handed. Dropping the whole frame here cost the well-formed siblings their
            // registration while the mod's shadow still counted them as registered, so a later
            // force could name an action the SDK never received. Only the broken element goes.
            if let Some(Value::Array(actions)) = data.get_mut("actions") {
                actions.retain(|action| {
                    if valid_action_definition(action) {
                        return true;
                    }
                    eprintln!(
                        "[Error] Dropping malformed action definition from actions/register: {}",
                        action.to_string().chars().take(DROP_PREVIEW).collect::<String>()
                    );
                    false
                });
            }
        }
    } else if command == "actions/unregister" {
        if let Some(Value::Object(data)) = out.get_mut("data") {
            data.retain(|k, _| matches!(k.as_str(), "action_names"));
        }
    } else if command == "actions/force" {
        if let Some(Value::Object(data)) = out.get_mut("data") {
            data.retain(|k, _| matches!(k.as_str(), "state" | "query" | "ephemeral_context" | "priority" | "action_names"));
        }
    }

    let data = out.get("data").and_then(Value::as_object);
    let valid = match command.as_str() {
        "startup" => out.get("data").map(Value::is_object).unwrap_or(true),
        "context" => data.is_some_and(|data| {
            data.get("message").is_some_and(Value::is_string)
                && data.get("silent").is_some_and(Value::is_boolean)
        }),
        // Every surviving element was already proven valid above; an emptied batch is nothing to say.
        "actions/register" => data.is_some_and(|data| {
            data.get("actions")
                .and_then(Value::as_array)
                .is_some_and(|actions| !actions.is_empty())
        }),
        "actions/unregister" => data.is_some_and(|data| {
            data.get("action_names")
                .and_then(Value::as_array)
                .is_some_and(|names| names.iter().all(Value::is_string))
        }),
        "actions/force" => data.is_some_and(valid_action_force),
        "action/result" => data.is_some_and(|data| {
            data.get("id").is_some_and(Value::is_string)
                && data.get("success").is_some_and(Value::is_boolean)
                && data.get("message").map(Value::is_string).unwrap_or(true)
        }),
        _ => false,
    };
    if !valid {
        return drop_from_wire("invalid command data", line);
    }

    match serde_json::to_string(&Value::Object(out)) {
        Ok(text) => Some(text),
        Err(_) => drop_from_wire("not serializable", line),
    }
}

fn valid_action_definition(value: &Value) -> bool {
    let Some(action) = value.as_object() else {
        return false;
    };
    if let Some(name) = action.get("name").and_then(Value::as_str) {
        if !is_recommended_action_name(name) {
            eprintln!(
                "[Warning] action name {:?} is outside the recommended lowercase underscore/dash format",
                name
            );
        }
    }
    if !action.get("name").is_some_and(Value::is_string)
        || !action.get("description").is_some_and(Value::is_string)
    {
        return false;
    }
    action.get("schema").map_or(true, |schema| {
        schema.as_object().is_some_and(|schema| {
            schema.is_empty()
                || schema
                    .get("type")
                    .is_some_and(|kind| kind.as_str() == Some("object"))
        })
    })
}

fn is_recommended_action_name(name: &str) -> bool {
    let mut saw_word = false;
    let mut previous_separator = false;
    for character in name.chars() {
        if matches!(character, '_' | '-') {
            if !saw_word || previous_separator {
                return false;
            }
            previous_separator = true;
        } else if character.is_ascii_lowercase() || character.is_ascii_digit() {
            saw_word = true;
            previous_separator = false;
        } else {
            return false;
        }
    }
    saw_word && !previous_separator
}

fn valid_action_force(data: &serde_json::Map<String, Value>) -> bool {
    data.get("query").is_some_and(Value::is_string)
        && data
            .get("action_names")
            .and_then(Value::as_array)
            .is_some_and(|names| names.iter().all(Value::is_string))
        && data.get("state").map(Value::is_string).unwrap_or(true)
        && data
            .get("ephemeral_context")
            .map(Value::is_boolean)
            .unwrap_or(true)
        && data.get("priority").map_or(true, |priority| {
            matches!(
                priority.as_str(),
                Some("low" | "medium" | "high" | "critical")
            )
        })
}


const DEFAULT_GAME: &str = "Balatro";
const UNDELIVERED_MESSAGE: &str =
    "The game never received this action: the bridge could not hand it to the mod. Nothing happened in game.";

fn game_from_line(line: &str) -> Option<String> {
    let name = serde_json::from_str::<Value>(line).ok()?
        .get("game")?.as_str()?.to_string();
    if name.is_empty() { None } else { Some(name) }
}

fn observe_game_name(line: &str, game: &Mutex<String>) {
    let Some(name) = game_from_line(line) else {
        return;
    };
    if let Ok(mut slot) = game.lock() {
        if *slot != name {
            *slot = name;
        }
    }
}

fn undelivered_action_result(text: &str, game: &str) -> Option<String> {
    let value: Value = serde_json::from_str(text).ok()?;
    if value.get("command")?.as_str()? != "action" {
        return None;
    }
    let id = value.get("data")?.get("id")?.as_str()?;
    if id.is_empty() {
        return None;
    }
    serde_json::to_string(&serde_json::json!({
        "command": "action/result",
        "game": game,
        "data": { "id": id, "success": true, "message": UNDELIVERED_MESSAGE }
    }))
    .ok()
}

const RESTART_ORPHAN_MESSAGE: &str =
    "The game restarted before this action produced a result. It was not executed in the previous run; nothing happened in game.";
const STALLED_ORPHAN_MESSAGE: &str =
    "The game stopped responding and never produced a result for this action. It was not executed; nothing happened in game.";

fn action_id_from_line(text: &str) -> Option<String> {
    let value: Value = serde_json::from_str(text).ok()?;
    if value.get("command")?.as_str()? != "action" {
        return None;
    }
    let id = value.get("data")?.get("id")?.as_str()?;
    if id.is_empty() { None } else { Some(id.to_string()) }
}

fn action_result_id_from_line(text: &str) -> Option<String> {
    let value: Value = serde_json::from_str(text).ok()?;
    if value.get("command")?.as_str()? != "action/result" {
        return None;
    }
    let id = value.get("data")?.get("id")?.as_str()?;
    if id.is_empty() { None } else { Some(id.to_string()) }
}

// SPECIFICATION.md:184,188: success=false immediately retries the whole force.  Orphan recovery is
// terminal transport bookkeeping for an action the dead/unresponsive game did not execute, so a
// retry would only manufacture another orphan.  success=true plus the explicit message acknowledges
// the frame without claiming that any game mutation happened.
fn orphan_action_result(id: &str, game: &str, message: &str) -> String {
    serde_json::to_string(&serde_json::json!({
        "command": "action/result",
        "game": game,
        "data": { "id": id, "success": true, "message": message }
    }))
    .unwrap_or_default()
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum ModResult {
    Forward,
    Suppress,
}

// Tracks actions the bridge handed to the mod so a game that vanishes mid-action
// (crash, force-quit, restart) still gets exactly one action/result: never zero,
// never two. `answered` is permanent once set - it is the single source of truth
// for "has Neuro already been told about this id", regardless of who answered it.
#[derive(Default)]
struct PendingTracker {
    pending: HashMap<String, Instant>,
    answered: HashSet<String>,
}

impl PendingTracker {
    fn new() -> Self {
        Self::default()
    }

    fn sent(&mut self, id: &str, at: Instant) {
        if self.answered.contains(id) {
            return;
        }
        self.pending.insert(id.to_string(), at);
    }

    fn mark_answered(&mut self, id: &str) {
        self.pending.remove(id);
        self.answered.insert(id.to_string());
    }
    fn already_answered(&self, id: &str) -> bool {
        self.answered.contains(id)
    }

    // Duplicate suppression is a property of one websocket delivery session. Neuro may
    // redeliver an action id after reconnect when it did not retain the previous result; Lua then
    // deliberately replays its cached verdict. Keeping `answered` forever would accept that
    // redelivery into the inbox and then silently discard the only reply. Outstanding actions
    // remain pending across reconnects; only the per-wire-session reply memory is reset.
    fn begin_session(&mut self) {
        self.answered.clear();
    }

    fn observe_mod_result(&mut self, id: &str) -> ModResult {
        if !self.answered.insert(id.to_string()) {
            return ModResult::Suppress;
        }
        self.pending.remove(id);
        ModResult::Forward
    }

    fn drain_for_restart(&mut self) -> Vec<String> {
        let ids: Vec<String> = self.pending.keys().cloned().collect();
        for id in &ids {
            self.mark_answered(id);
        }
        ids
    }

    fn drain_stale(&mut self, now: Instant, timeout: Duration) -> Vec<String> {
        let stale: Vec<String> = self
            .pending
            .iter()
            .filter(|(_, &sent_at)| now.duration_since(sent_at) >= timeout)
            .map(|(id, _)| id.clone())
            .collect();
        for id in &stale {
            self.mark_answered(id);
        }
        stale
    }
}


const REREGISTER_ALL_LINE: &str = r#"{"command":"actions/reregister_all"}"#;

// The mod treats an unchanged stamp as "same client" and skips the non-idempotent half of its
// reconnect (core/dispatcher.lua), so the counter must never repeat a value a previous bridge
// process already sent: it starts from the process's own wall-clock start instead of from zero.
static TRANSPORT_SESSION: OnceLock<AtomicU64> = OnceLock::new();

fn next_transport_session() -> u64 {
    TRANSPORT_SESSION
        .get_or_init(|| AtomicU64::new(process_session_base()))
        .fetch_add(1, Ordering::Relaxed)
        + 1
}

fn process_session_base() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_micros() as u64)
        .unwrap_or(0)
}

fn reregister_line_for_session(session: u64) -> String {
    let mut value: Value = serde_json::from_str(REREGISTER_ALL_LINE)
        .unwrap_or_else(|_| Value::Object(serde_json::Map::new()));
    if let Some(obj) = value.as_object_mut() {
        obj.insert("transport_session".to_string(), Value::from(session));
    }
    value.to_string()
}

async fn request_action_reregistration(inbox: &Path, session: u64) {
    if let Err(e) = append_line(inbox, &reregister_line_for_session(session)).await {
        eprintln!("[Warning] Could not request action reregistration: {}", e);
    }
}

const ABANDON_COMMAND: &str = "neuro-bridge/abandon";
const BRIDGE_CONTROL_PREFIX: &str = "neuro-bridge/";

// Every neuro-bridge/* command is the bridge's own to the mod; a websocket client claiming one is a forgery.
fn is_bridge_control_command(text: &str) -> bool {
    command_from_line(text).is_some_and(|command| command.starts_with(BRIDGE_CONTROL_PREFIX))
}

fn abandon_line(ids: &[String], transport_session: u64) -> String {
    serde_json::to_string(&serde_json::json!({
        "command": ABANDON_COMMAND,
        "transport_session": transport_session,
        "data": { "ids": ids }
    }))
    .unwrap_or_default()
}

async fn request_action_abandon(inbox: &Path, ids: &[String], transport_session: u64) {
    if ids.is_empty() {
        return;
    }
    let line = abandon_line(ids, transport_session);
    if line.is_empty() {
        return;
    }
    if let Err(e) = append_line(inbox, &line).await {
        eprintln!(
            "[Warning] Could not tell the mod to abandon {} action(s) the bridge already answered: {}",
            ids.len(),
            e
        );
    }
}

enum Outgoing {
    Outbox(String, Resume),
    Local(String),
}

struct SessionTasks {
    tx: Option<tokio::task::JoinHandle<()>>,
    rx: Option<tokio::task::JoinHandle<()>>,
}

impl SessionTasks {
    fn new(tx: tokio::task::JoinHandle<()>, rx: tokio::task::JoinHandle<()>) -> Self {
        Self {
            tx: Some(tx),
            rx: Some(rx),
        }
    }

    fn tx_is_finished(&self) -> bool {
        self.tx.as_ref().is_none_or(tokio::task::JoinHandle::is_finished)
    }

    fn rx_is_finished(&self) -> bool {
        self.rx.as_ref().is_none_or(tokio::task::JoinHandle::is_finished)
    }

    fn abort(&self) {
        if let Some(task) = &self.tx {
            task.abort();
        }
        if let Some(task) = &self.rx {
            task.abort();
        }
    }

    async fn stop(mut self) {
        self.abort();
        if let Some(task) = self.tx.take() {
            let _ = task.await;
        }
        if let Some(task) = self.rx.take() {
            let _ = task.await;
        }
    }
}

impl Drop for SessionTasks {
    fn drop(&mut self) {
        self.abort();
    }
}

async fn run_session(
    cfg: &Config,
    resume: Option<Resume>,
    cache: &mut BootstrapCache,
    pending: Arc<Mutex<PendingTracker>>,
) -> Result<Resume> {
    let outbox_meta = fs::metadata(&cfg.outbox).await.ok();
    let outbox_id = outbox_meta.as_ref().and_then(file_identity);
    let resume_invalid = match resume {
        Some(mark) => match &outbox_meta {
            Some(meta) => {
                meta.len() < mark.pos || (mark.id.is_some() && outbox_id != mark.id)
            }
            None => mark.pos > 0,
        },
        None => false,
    };
    if resume_invalid {
        *cache = BootstrapCache::default();
    }
    let (start_pos, bootstrap) = match resume {
        // Resume from the last frame actually forwarded to the websocket, never current EOF.
        // Lines appended during the reconnect gap are protocol debt and must be tailed.
        Some(mark) if !resume_invalid => (mark.pos, cache.replay_lines()),
        _ => {
            let (scanned_pos, lines) = bootstrap_messages(&cfg.outbox).await?;
            for line in &lines {
                cache.observe(line);
            }
            (scanned_pos, cache.replay_lines())
        }
    };
    let start = Resume { pos: start_pos, id: outbox_id };
    let game_name = Arc::new(Mutex::new(DEFAULT_GAME.to_string()));
    let (ws_stream, _) = connect_async(&cfg.ws_url).await.context("connect websocket")?;
    let (mut ws_write, mut ws_read) = ws_stream.split();

    pending.lock().unwrap().begin_session();

    for line in bootstrap {
        observe_game_name(&line, &game_name);
        if let Some(text) = sanitize_for_wire(&line) {
            ws_write.send(Message::Text(text)).await?;
        }
    }

    let transport_session = next_transport_session();
    request_action_reregistration(&cfg.inbox, transport_session).await;

    let (tx, mut rx) = mpsc::channel::<Outgoing>(256);
    let local_tx = tx.clone();
    let outbox_path = cfg.outbox.clone();
    let inbox_path = cfg.inbox.clone();

    let shutdown = Arc::new(AtomicBool::new(false));
    let shutdown_tx = shutdown.clone();
    let shutdown_rx = shutdown.clone();
    let game_name_rx = game_name.clone();
    let pending_rx = pending.clone();

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

    let mut tail = start;
    let mut tailer = Tailer::new(outbox_path, start);
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
                    let id = tailer.identity;
                    for (line, pos) in lines {
                        if tx.send(Outgoing::Outbox(line, Resume { pos, id })).await.is_err() {
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
            let incoming = match msg {
                Ok(Message::Text(text)) => Some(text),
                Ok(Message::Binary(bytes)) => match String::from_utf8(bytes) {
                    Ok(text) => Some(text),
                    Err(e) => {
                        eprintln!("[Warning] Dropping a binary websocket frame that is not UTF-8: {}", e);
                        None
                    }
                },
                Ok(Message::Close(_)) => break,
                Ok(Message::Ping(_)) | Ok(Message::Pong(_)) | Ok(Message::Frame(_)) => None,
                Err(e) => {
                    eprintln!("[Error] WebSocket error: {}", e);
                    break;
                }
            };
            if let Some(text) = incoming {
              if is_bridge_control_command(&text) {
                eprintln!(
                    "[Warning] Dropping a websocket frame claiming a bridge-internal command: {}",
                    text.chars().take(DROP_PREVIEW).collect::<String>()
                );
              } else {
                let is_action = command_from_line(&text).as_deref() == Some("action");
                let action_id = if is_action { action_id_from_line(&text) } else { None };
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
                if delivered && is_action {
                    if let Some(id) = &action_id {
                        if let Ok(mut tracker) = pending_rx.lock() {
                            tracker.sent(id, Instant::now());
                        }
                    }
                }
                if !delivered {
                    let preview = text.chars().take(512).collect::<String>();
                    let game = game_name_rx
                        .lock()
                        .map(|name| name.clone())
                        .unwrap_or_else(|_| DEFAULT_GAME.to_string());
                    match undelivered_action_result(&text, &game) {
                        Some(frame) => {
                            eprintln!(
                                "[Error] Inbox append failed after {} attempts; answering Neuro that the action never ran: {}",
                                MAX_APPEND_ATTEMPTS, preview
                            );
                            if let Some(id) = &action_id {
                                if let Ok(mut tracker) = pending_rx.lock() {
                                    tracker.mark_answered(id);
                                }
                            }
                            if local_tx.send(Outgoing::Local(frame)).await.is_err() {
                                break;
                            }
                        }
                        None => eprintln!(
                            "[Error] DROPPING inbox message after {} attempts (no action id to answer): {}",
                            MAX_APPEND_ATTEMPTS, preview
                        ),
                    }
                }
              }
            }
            // check shutdown AFTER handling: a command received during teardown must still reach the inbox
            if shutdown_rx.load(Ordering::Relaxed) {
                break;
            }
        }
    });
    let tasks = SessionTasks::new(tx_task, rx_task);
    let mut startup_on_wire = cache.has_startup();

    loop {
        match time::timeout(Duration::from_secs(1), rx.recv()).await {
            Ok(Some(outgoing)) => {
                let mut forward = true;
                let mut startup_forwarded = false;
                let mut startup_written = false;
                let mut result_id: Option<String> = None;
                let line = match &outgoing {
                    Outgoing::Outbox(line, _) => {
                        cache.observe(line);
                        observe_game_name(line, &game_name);
                        match command_from_line(line).as_deref() {
                            Some("startup") => {
                                startup_forwarded = true;
                            }
                            Some("action/result") => {
                                if let Some(id) = action_result_id_from_line(line) {
                                    if pending.lock().unwrap().already_answered(&id) {
                                        eprintln!(
                                            "[Warning] Dropping duplicate action/result for '{}': Neuro already received one result for this id",
                                            id
                                        );
                                        forward = false;
                                    } else {
                                        result_id = Some(id);
                                    }
                                }
                            }
                            _ => {}
                        }
                        line
                    }
                    Outgoing::Local(line) => line,
                };
                if forward {
                    if let Some(text) = sanitize_for_wire(line) {
                        if ws_write.feed(Message::Text(text)).await.is_err() {
                            break;
                        }
                        if ws_write.flush().await.is_err() {
                            break;
                        }
                        // an id may be marked answered only after the frame is confirmed on the socket
                        if let Some(id) = result_id.take() {
                            pending.lock().unwrap().observe_mod_result(&id);
                        }
                        if startup_forwarded {
                            cache.mark_startup_sent();
                            startup_on_wire = true;
                            startup_written = true;
                        }
                    }
                }
                if startup_written {
                    let restart_ids = pending.lock().unwrap().drain_for_restart();
                    if !restart_ids.is_empty() {
                        request_action_abandon(&cfg.inbox, &restart_ids, transport_session).await;
                        let game = game_name.lock().map(|g| g.clone()).unwrap_or_else(|_| DEFAULT_GAME.to_string());
                        let mut ws_failed = false;
                        for id in &restart_ids {
                            eprintln!(
                                "[Warning] Game restarted with '{}' still unanswered from the previous session; answering Neuro",
                                id
                            );
                            let frame = orphan_action_result(id, &game, RESTART_ORPHAN_MESSAGE);
                            if let Some(text) = sanitize_for_wire(&frame) {
                                if ws_write.feed(Message::Text(text)).await.is_err() {
                                    ws_failed = true;
                                    break;
                                }
                            }
                        }
                        if ws_failed || ws_write.flush().await.is_err() {
                            break;
                        }
                    }
                }
                if let Outgoing::Outbox(_, mark) = outgoing {
                    tail = mark;
                }
            }
            Ok(None) => break,
            Err(_) => {
                if tasks.tx_is_finished() || tasks.rx_is_finished() {
                    break;
                }
                // Only sweep after the ordered outbox channel has been idle for a full tick. The
                // former top-of-loop sweep could send an orphan first and then discard a real
                // action/result that was already queued in `rx` as a duplicate.
                let stale_ids = if startup_on_wire {
                    pending.lock().unwrap().drain_stale(Instant::now(), cfg.orphan_timeout)
                } else {
                    Vec::new()
                };
                if !stale_ids.is_empty() {
                    request_action_abandon(&cfg.inbox, &stale_ids, transport_session).await;
                    let game = game_name.lock().map(|g| g.clone()).unwrap_or_else(|_| DEFAULT_GAME.to_string());
                    let mut ws_failed = false;
                    for id in &stale_ids {
                        eprintln!(
                            "[Warning] No action/result seen for '{}' within {:?}; the game is presumed unresponsive, answering Neuro so she isn't left waiting",
                            id, cfg.orphan_timeout
                        );
                        let frame = orphan_action_result(id, &game, STALLED_ORPHAN_MESSAGE);
                        if let Some(text) = sanitize_for_wire(&frame) {
                            if ws_write.feed(Message::Text(text)).await.is_err() {
                                ws_failed = true;
                                break;
                            }
                        }
                    }
                    if ws_failed || ws_write.flush().await.is_err() {
                        break;
                    }
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
    tasks.stop().await;

    Ok(tail)
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
    let mut resume: Option<Resume> = None;
    let mut bootstrap_cache = BootstrapCache::default();
    let pending_tracker = Arc::new(Mutex::new(PendingTracker::new()));
    loop {
        let res = run_session(&cfg, resume, &mut bootstrap_cache, pending_tracker.clone()).await;
        match res {
            Ok(mark) => {
                resume = Some(mark);
                eprintln!(
                    "bridge: session ended, reconnecting in {}s (resume@{})",
                    RECONNECT_INTERVAL_SECS, mark.pos
                );
            }
            Err(err) => {
                eprintln!("bridge error: {err} (retry in {RECONNECT_INTERVAL_SECS}s)");
            }
        }
        time::sleep(Duration::from_secs(RECONNECT_INTERVAL_SECS)).await;
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use futures_util::FutureExt;

    #[test]
    fn parse_orphan_timeout_secs_rejects_values_at_or_under_the_mod_deadline() {
        assert!(parse_orphan_timeout_secs("0").is_err());
        assert!(parse_orphan_timeout_secs("5").is_err());
        assert!(parse_orphan_timeout_secs("3").is_err());
        assert!(parse_orphan_timeout_secs("not a number").is_err());
        assert_eq!(parse_orphan_timeout_secs("6").unwrap(), 6);
        assert_eq!(parse_orphan_timeout_secs("30").unwrap(), 30);
    }

    #[test]
    fn command_from_line_extracts_command() {
        assert_eq!(command_from_line(r#"{"command":"startup"}"#).as_deref(), Some("startup"));
        assert_eq!(command_from_line(r#"{"command":"context","data":{}}"#).as_deref(), Some("context"));
        assert_eq!(command_from_line("not json"), None);
        assert_eq!(command_from_line(r#"{"no":"command"}"#), None);
    }

    #[test]
    fn sanitize_strips_reason_code_from_action_result_data() {
        let out = sanitize_for_wire(
            r#"{"command":"action/result","game":"Balatro","data":{"id":"a1","success":false,"message":"nope","reason_code":"ACTION_REJECTED"}}"#,
        ).unwrap();
        let v: Value = serde_json::from_str(&out).unwrap();
        assert_eq!(v["data"]["id"], "a1");
        assert_eq!(v["data"]["success"], false);
        assert_eq!(v["data"]["message"], "nope");
        assert!(
            v["data"].get("reason_code").is_none(),
            "reason_code must be stripped from the action/result wire frame"
        );
        let force = sanitize_for_wire(
            r#"{"command":"actions/force","game":"Balatro","data":{"query":"q","action_names":["help"],"ephemeral_context":true}}"#,
        ).unwrap();
        let f: Value = serde_json::from_str(&force).unwrap();
        assert_eq!(f["data"]["ephemeral_context"], true);
    }

    #[test]
    fn sanitize_for_wire_strips_non_spec_fields() {
        let out = sanitize_for_wire(
            r#"{"command":"context","game":"Balatro","seq":42,"session_id":1712345,"run_generation":3,"data":{"message":"hi","silent":true}}"#,
        ).unwrap();
        let v: Value = serde_json::from_str(&out).unwrap();
        let obj = v.as_object().unwrap();
        let mut keys: Vec<&str> = obj.keys().map(|k| k.as_str()).collect();
        keys.sort();
        assert_eq!(keys, vec!["command", "data", "game"]);
        assert_eq!(v["data"]["message"], "hi");
        assert_eq!(v["data"]["silent"], true);
    }

    #[test]
    fn sanitize_for_wire_accepts_every_supported_c2s_command() {
        let frames = [
            r#"{"command":"startup","game":"Balatro"}"#,
            r#"{"command":"context","game":"Balatro","data":{"message":"hi","silent":false}}"#,
            r#"{"command":"actions/register","game":"Balatro","data":{"actions":[{"name":"help","description":"Show help","schema":{"type":"object"}}]}}"#,
            r#"{"command":"actions/unregister","game":"Balatro","data":{"action_names":["help"]}}"#,
            r#"{"command":"actions/force","game":"Balatro","data":{"state":"menu","query":"Choose","ephemeral_context":true,"priority":"high","action_names":["help"]}}"#,
            r#"{"command":"action/result","game":"Balatro","data":{"id":"a-1","success":true,"message":"done"}}"#,
        ];
        assert_eq!(frames.len(), SUPPORTED_C2S_COMMANDS.len());
        for (index, line) in frames.iter().enumerate() {
            let value = serde_json::from_str::<Value>(line).unwrap();
            assert_eq!(
                value["command"].as_str().unwrap(),
                SUPPORTED_C2S_COMMANDS[index]
            );
        }
        for line in frames {
            assert!(
                sanitize_for_wire(line).is_some(),
                "supported C2S frame was rejected: {:?}",
                line
            );
        }
    }

    #[test]
    fn sanitize_for_wire_keeps_spec_only_messages_and_passthrough() {
        let clean = r#"{"command":"startup","game":"Balatro"}"#;
        let v: Value = serde_json::from_str(&sanitize_for_wire(clean).unwrap()).unwrap();
        assert_eq!(v.as_object().unwrap().len(), 2);
        let deep = r#"{"command":"actions/register","game":"Balatro","seq":7,"data":{"actions":[{"name":"a","description":"A","schema":{"type":"object"}}]}}"#;
        let v: Value = serde_json::from_str(&sanitize_for_wire(deep).unwrap()).unwrap();
        assert_eq!(v["data"]["actions"][0]["name"], "a");
        assert!(v.get("seq").is_none());
        assert_eq!(
            sanitize_for_wire("not json"),
            None,
            "an unparsable line must never reach the websocket"
        );
    }

    #[test]
    fn sanitize_for_wire_refuses_everything_outside_the_spec_envelope() {
        for line in [
            "not json",
            "",
            r#"{"command":"context","game":"Balatro","data":{"message":"tor"#,
            r#"[{"command":"startup"}]"#,
            r#""startup""#,
            r#"{"game":"Balatro","data":{"message":"hi"}}"#,
            r#"{"command":"","game":"Balatro"}"#,
            r#"{"command":42,"game":"Balatro"}"#,
            "?????",
        ] {
            assert_eq!(
                sanitize_for_wire(line),
                None,
                "line escaped the wire gate: {:?}",
                line
            );
        }
        assert!(sanitize_for_wire(r#"{"command":"startup","game":"Balatro"}"#).is_some());
    }

    #[test]
    fn sanitize_for_wire_rejects_missing_game_bad_data_and_unknown_commands() {
        for line in [
            r#"{"command":"startup"}"#,
            r#"{"command":"startup","game":"  "}"#,
            r#"{"command":"context","game":"Balatro"}"#,
            r#"{"command":"context","game":"Balatro","data":{"message":"hi"}}"#,
            r#"{"command":"context","game":"Balatro","data":{"message":7,"silent":false}}"#,
            r#"{"command":"actions/register","game":"Balatro","data":{"actions":{}}}"#,
            r#"{"command":"actions/register","game":"Balatro","data":{"actions":[{"name":"help"}]}}"#,
            r#"{"command":"actions/unregister","game":"Balatro","data":{"action_names":[7]}}"#,
            r#"{"command":"actions/force","game":"Balatro","data":{"query":"Choose"}}"#,
            r#"{"command":"actions/force","game":"Balatro","data":{"query":"Choose","action_names":[],"priority":"urgent"}}"#,
            r#"{"command":"action/result","game":"Balatro","data":{"id":"a-1","success":"yes"}}"#,
            r#"{"command":"action/result","game":"Balatro","data":{"success":true}}"#,
            r#"{"command":"action","game":"Balatro","data":{"id":"a-1","name":"help"}}"#,
            r#"{"command":"future/command","game":"Balatro","data":{}}"#,
        ] {
            assert_eq!(
                sanitize_for_wire(line),
                None,
                "structurally invalid frame escaped the wire gate: {:?}",
                line
            );
        }
    }

    #[test]
    fn sanitize_for_wire_strips_legacy_startup_data_without_dropping_startup() {
        for line in [
            r#"{"command":"startup","game":"Balatro","data":{"legacy":true}}"#,
            r#"{"command":"startup","game":"Balatro","data":["legacy"]}"#,
        ] {
            let out = sanitize_for_wire(line)
                .expect("startup must survive while legacy data is stripped");
            let value: Value = serde_json::from_str(&out).unwrap();
            assert_eq!(value["command"], "startup");
            assert_eq!(value["game"], "Balatro");
            assert!(value.get("data").is_none());
        }
    }

    #[test]
    fn sanitize_for_wire_rejects_action_schema_without_object_type() {
        let line = r#"{"command":"actions/register","game":"Balatro","data":{"actions":[{"name":"help","description":"Show help","schema":{"properties":{}}}]}}"#;
        assert_eq!(sanitize_for_wire(line), None);
    }

    #[test]
    fn sanitize_for_wire_accepts_the_sdk_empty_schema() {
        let line = r#"{"command":"actions/register","game":"Balatro","data":{"actions":[{"name":"help","description":"Show help","schema":{}}]}}"#;
        assert!(sanitize_for_wire(line).is_some(), "the SDK explicitly permits an empty schema");
    }

    #[test]
    fn sanitize_for_wire_keeps_the_valid_actions_of_a_partly_malformed_register() {
        let line = r#"{"command":"actions/register","game":"Balatro","data":{"actions":[{"name":"play_hand","description":"Play","schema":{"type":"object"}},{"name":"broken"},{"name":"discard_hand","description":"Discard"}]}}"#;
        let out = sanitize_for_wire(line)
            .expect("one malformed definition must not cost its well-formed siblings the wire");
        let value: Value = serde_json::from_str(&out).unwrap();
        let names: Vec<&str> = value["data"]["actions"]
            .as_array()
            .unwrap()
            .iter()
            .map(|a| a["name"].as_str().unwrap())
            .collect();
        assert_eq!(names, vec!["play_hand", "discard_hand"]);
    }

    #[test]
    fn sanitize_for_wire_drops_a_register_left_empty_by_pruning() {
        let line = r#"{"command":"actions/register","game":"Balatro","data":{"actions":[{"name":"broken"},{"description":"nameless"}]}}"#;
        assert_eq!(
            sanitize_for_wire(line),
            None,
            "a register with nothing left to register is not a frame"
        );
    }

    #[test]
    fn sanitize_for_wire_keeps_noncanonical_action_name() {
        let line = r#"{"command":"actions/register","game":"Balatro","data":{"actions":[{"name":"Play Hand","description":"Show help"}]}}"#;
        let out = sanitize_for_wire(line).expect("name format is a recommendation, not a wire gate");
        let value: Value = serde_json::from_str(&out).unwrap();
        assert_eq!(value["data"]["actions"][0]["name"], "Play Hand");
    }

    #[test]
    fn action_name_format_is_only_a_recommendation() {
        assert!(is_recommended_action_name("play_hand"));
        assert!(is_recommended_action_name("use-item"));
        assert!(!is_recommended_action_name("Play Hand"));
    }

    #[test]
    fn undelivered_action_result_reports_the_action_as_not_executed_without_retry() {
        let frame = undelivered_action_result(
            r#"{"command":"action","run_generation":4,"data":{"id":"a-7","name":"help","data":"{}"}}"#,
            "Balatro",
        )
        .expect("a dropped action must produce a result frame");
        let v: Value = serde_json::from_str(&frame).unwrap();
        assert_eq!(v["command"], "action/result");
        assert_eq!(v["game"], "Balatro");
        assert_eq!(v["data"]["id"], "a-7");
        assert_eq!(
            v["data"]["success"], true,
            "success=false would make Neuro retry the whole actions force into the same broken write"
        );
        assert!(v["data"]["message"].as_str().unwrap().len() > 0);
        assert!(sanitize_for_wire(&frame).is_some());

        assert!(undelivered_action_result(r#"{"command":"actions/reregister_all"}"#, "Balatro").is_none());
        assert!(undelivered_action_result(r#"{"command":"action","data":{"name":"help"}}"#, "Balatro").is_none());
        assert!(undelivered_action_result("not json", "Balatro").is_none());
    }

    #[test]
    fn game_name_is_learned_from_outbox_lines() {
        let slot = Mutex::new(DEFAULT_GAME.to_string());
        observe_game_name(r#"{"command":"startup","game":"Some Other Game"}"#, &slot);
        assert_eq!(slot.lock().unwrap().as_str(), "Some Other Game");
        observe_game_name(r#"{"command":"context","data":{"message":"hi"}}"#, &slot);
        assert_eq!(slot.lock().unwrap().as_str(), "Some Other Game");
    }

    #[tokio::test]
    async fn a_replaced_outbox_is_re_read_from_the_start() {
        let dir = scratch_dir("outbox_identity");
        fs::create_dir_all(&dir).await.unwrap();
        let outbox = dir.join("neuro_outbox.jsonl");
        let filler = "{\"command\":\"context\",\"game\":\"Balatro\",\"data\":{\"message\":\"old\"}}\n";

        let mut before = String::new();
        for _ in 0..40 {
            before.push_str(filler);
        }
        fs::write(&outbox, &before).await.unwrap();

        let mut tailer = Tailer::new(outbox.clone(), Resume::default());
        let lines = tailer.read_new_lines().await.unwrap();
        assert_eq!(lines.len(), 40);
        assert_eq!(tailer.pos, before.len() as u64);

        fs::rename(&outbox, dir.join("neuro_outbox.jsonl.prev")).await.unwrap();
        let mut after = String::from("{\"command\":\"startup\",\"game\":\"Balatro\"}\n");
        for _ in 0..80 {
            after.push_str(filler);
        }
        fs::write(&outbox, &after).await.unwrap();
        assert!(after.len() > before.len());

        let lines = tailer.read_new_lines().await.unwrap();
        assert_eq!(
            lines.first().map(|(line, _)| command_from_line(line)).flatten().as_deref(),
            Some("startup"),
            "the bridge resumed inside a replaced outbox and skipped the startup frame"
        );
        assert_eq!(lines.len(), 81);
        let _ = fs::remove_dir_all(&dir).await;
    }

    #[tokio::test]
    async fn an_undeliverable_action_is_answered_without_forcing_a_retry() {
        let dir = scratch_dir("undeliverable_action");
        fs::create_dir_all(&dir).await.unwrap();
        let outbox = dir.join("neuro_outbox.jsonl");
        let inbox = dir.join("neuro_inbox.jsonl");
        fs::write(&outbox, "{\"command\":\"startup\",\"game\":\"Balatro\"}\n").await.unwrap();
        fs::create_dir_all(&inbox).await.unwrap();

        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let server = tokio::spawn(async move {
            let (stream, _) = listener.accept().await.unwrap();
            let mut ws = tokio_tungstenite::accept_async(stream).await.unwrap();
            let _bootstrap = ws.next().await;
            ws.send(Message::Text(
                r#"{"command":"action","data":{"id":"a-7","name":"help"}}"#.to_string(),
            ))
            .await
            .unwrap();
            let mut result = None;
            let deadline = time::sleep(Duration::from_secs(45));
            tokio::pin!(deadline);
            loop {
                tokio::select! {
                    _ = &mut deadline => break,
                    incoming = ws.next() => match incoming {
                        Some(Ok(Message::Text(text))) => {
                            if command_from_line(&text).as_deref() == Some("action/result") {
                                result = Some(text);
                                break;
                            }
                        }
                        Some(Ok(_)) => {}
                        _ => break,
                    },
                }
            }
            let _ = ws.close(None).await;
            result
        });

        let cfg = Config { ws_url: format!("ws://{}", addr), outbox, inbox, orphan_timeout: Duration::from_secs(DEFAULT_ORPHAN_TIMEOUT_SECS) };
        let mut cache = BootstrapCache::default();
        let pending = Arc::new(Mutex::new(PendingTracker::new()));
        let _ = time::timeout(
            Duration::from_secs(60),
            run_session(&cfg, None, &mut cache, pending),
        )
        .await;

        let result = server
            .await
            .unwrap()
            .expect("Neuro was left waiting: no action/result for an action the mod never got");
        let v: Value = serde_json::from_str(&result).unwrap();
        let mut keys: Vec<&str> = v.as_object().unwrap().keys().map(|k| k.as_str()).collect();
        keys.sort();
        assert_eq!(keys, vec!["command", "data", "game"]);
        assert_eq!(v["game"], "Balatro");
        assert_eq!(v["data"]["id"], "a-7");
        assert_eq!(v["data"]["success"], true);
        assert!(!v["data"]["message"].as_str().unwrap().is_empty());
        let _ = fs::remove_dir_all(&dir).await;
    }

    #[test]
    fn bootstrap_cache_orders_startup_then_register_and_never_context() {
        let mut c = BootstrapCache::default();
        c.observe(r#"{"command":"startup","session_id":1}"#);
        c.observe(r#"{"command":"actions/register","data":{"actions":[]}}"#);
        c.observe(r#"{"command":"context","data":{"message":"hi"}}"#);
        let lines = c.lines();
        assert_eq!(lines.len(), 2);
        assert!(lines[0].contains("startup"));
        assert!(lines[1].contains("actions/register"));
        assert!(
            !lines.iter().any(|l| l.contains("context")),
            "a stale context must never be replayed after a reconnect"
        );
    }

    #[test]
    fn bootstrap_cache_replays_startup_only_until_it_has_been_sent() {
        let mut c = BootstrapCache::default();
        c.observe(r#"{"command":"startup","game":"Balatro"}"#);
        c.observe(r#"{"command":"actions/register","data":{"actions":[{"name":"A"}]}}"#);
        let first = c.replay_lines();
        assert_eq!(first.len(), 2);
        assert!(first[0].contains("startup"));
        assert!(first[1].contains("actions/register"));
        let second = c.replay_lines();
        assert_eq!(second.len(), 1);
        assert!(
            second[0].contains("actions/register"),
            "startup must be sent once per game process, like the reference SDKs"
        );
    }

    #[test]
    fn a_startup_already_sent_live_is_not_replayed() {
        let mut c = BootstrapCache::default();
        c.observe(r#"{"command":"startup","game":"Balatro"}"#);
        c.mark_startup_sent();
        c.observe(r#"{"command":"actions/register","data":{"actions":[{"name":"A"}]}}"#);
        let lines = c.replay_lines();
        assert_eq!(lines.len(), 1);
        assert!(lines[0].contains("actions/register"));
    }

    #[test]
    fn abandon_line_is_ipc_only_and_never_reaches_the_wire() {
        let line = abandon_line(&["a-1".to_string(), "a-2".to_string()], 5);
        let v: Value = serde_json::from_str(&line).unwrap();
        assert_eq!(v["command"], ABANDON_COMMAND);
        assert_eq!(v["transport_session"], 5);
        let ids: Vec<&str> = v["data"]["ids"]
            .as_array()
            .unwrap()
            .iter()
            .map(|id| id.as_str().unwrap())
            .collect();
        assert_eq!(ids, vec!["a-1", "a-2"]);
        assert_eq!(
            sanitize_for_wire(&line),
            None,
            "an internal IPC command must never be forwarded to the SDK"
        );
    }

    #[test]
    fn is_bridge_control_command_matches_only_the_neuro_bridge_namespace() {
        assert!(is_bridge_control_command(
            r#"{"command":"neuro-bridge/abandon","data":{"ids":["a-1"]}}"#
        ));
        assert!(!is_bridge_control_command(r#"{"command":"action","data":{"id":"a-1"}}"#));
        assert!(!is_bridge_control_command(r#"{"command":"actions/reregister_all"}"#));
        assert!(!is_bridge_control_command("not json"));
    }

    #[tokio::test]
    async fn a_client_forged_bridge_control_frame_is_never_written_to_the_inbox() {
        let dir = scratch_dir("forged_control_frame");
        fs::create_dir_all(&dir).await.unwrap();
        let outbox = dir.join("neuro_outbox.jsonl");
        let inbox = dir.join("neuro_inbox.jsonl");
        fs::write(&outbox, "{\"command\":\"startup\",\"game\":\"Balatro\"}\n").await.unwrap();

        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let server = tokio::spawn(async move {
            let (stream, _) = listener.accept().await.unwrap();
            let mut ws = tokio_tungstenite::accept_async(stream).await.unwrap();
            let _bootstrap = ws.next().await;
            ws.send(Message::Text(
                r#"{"command":"neuro-bridge/abandon","data":{"ids":["victim-1"]}}"#.to_string(),
            ))
            .await
            .unwrap();
            time::sleep(Duration::from_millis(300)).await;
            let _ = ws.close(None).await;
        });

        let cfg = Config { ws_url: format!("ws://{}", addr), outbox, inbox: inbox.clone(), orphan_timeout: Duration::from_secs(DEFAULT_ORPHAN_TIMEOUT_SECS) };
        let mut cache = BootstrapCache::default();
        let pending = Arc::new(Mutex::new(PendingTracker::new()));
        let _ = time::timeout(
            Duration::from_secs(20),
            run_session(&cfg, None, &mut cache, pending),
        )
        .await;
        let _ = server.await;

        let delivered = fs::read_to_string(&inbox).await.unwrap_or_default();
        assert!(
            !delivered.contains("neuro-bridge/abandon"),
            "a client-forged bridge-control frame reached the inbox: {:?}",
            delivered
        );
        let _ = fs::remove_dir_all(&dir).await;
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

    fn register_names(line: &str) -> Vec<String> {
        let value: Value = serde_json::from_str(line).unwrap();
        value["data"]["actions"]
            .as_array()
            .unwrap()
            .iter()
            .map(|a| a["name"].as_str().unwrap().to_string())
            .collect()
    }

    fn register(names: &[&str]) -> String {
        let actions: Vec<Value> = names
            .iter()
            .map(|n| serde_json::json!({ "name": n, "description": "d", "schema": {} }))
            .collect();
        serde_json::json!({ "command": "actions/register", "data": { "actions": actions } })
            .to_string()
    }

    // #14: the mod sends actions/register as a DIFF against what it already registered
    // (core/bridge.lua register_actions), announcing every removal as its own actions/unregister
    // frame first. Overwriting on each frame replayed a truncated catalogue to a reconnecting
    // client after two ordinary state changes, silently dropping still-valid actions.
    #[test]
    fn bootstrap_cache_accumulates_successive_register_frames() {
        let mut c = BootstrapCache::default();
        c.observe(r#"{"command":"startup","session_id":1}"#);
        c.observe(&register(&["A", "B", "C"]));
        c.observe(&register(&["D"]));
        c.observe(&register(&["E"]));
        let lines = c.lines();
        assert_eq!(lines.len(), 2);
        assert_eq!(register_names(&lines[1]), vec!["A", "B", "C", "D", "E"]);
    }

    #[test]
    fn bootstrap_cache_redefinition_replaces_the_action_it_names() {
        let mut c = BootstrapCache::default();
        c.observe(&register(&["A", "B"]));
        c.observe(
            r#"{"command":"actions/register","data":{"actions":[{"name":"B","description":"newer","schema":{}}]}}"#,
        );
        let lines = c.lines();
        assert_eq!(register_names(&lines[0]), vec!["A", "B"]);
        assert!(lines[0].contains("newer"));
        assert!(!lines[0].contains("\"description\":\"d\",\"name\":\"B\""));
    }

    #[test]
    fn bootstrap_cache_still_drops_a_name_the_mod_unregistered_earlier() {
        let mut c = BootstrapCache::default();
        c.observe(&register(&["A", "B"]));
        c.observe(r#"{"command":"actions/unregister","data":{"action_names":["A"]}}"#);
        c.observe(&register(&["C"]));
        let lines = c.lines();
        assert_eq!(register_names(&lines[0]), vec!["B", "C"]);
    }

    #[test]
    fn bootstrap_cache_startup_clears_the_accumulation() {
        let mut c = BootstrapCache::default();
        c.observe(&register(&["A"]));
        c.observe(r#"{"command":"startup","session_id":2}"#);
        c.observe(&register(&["B"]));
        let lines = c.lines();
        assert_eq!(lines.len(), 2);
        assert_eq!(register_names(&lines[1]), vec!["B"]);
    }

    #[test]
    fn bootstrap_cache_drops_unregistered_actions_from_replay() {
        let mut c = BootstrapCache::default();
        c.observe(r#"{"command":"startup","session_id":1}"#);
        c.observe(
            r#"{"command":"actions/register","data":{"actions":[{"name":"A","schema":{}},{"name":"B","schema":{}}]}}"#,
        );
        c.observe(r#"{"command":"actions/unregister","data":{"action_names":["A"]}}"#);
        let lines = c.lines();
        assert_eq!(lines.len(), 2);
        let replayed: Value = serde_json::from_str(&lines[1]).unwrap();
        let names: Vec<&str> = replayed["data"]["actions"]
            .as_array()
            .unwrap()
            .iter()
            .map(|a| a["name"].as_str().unwrap())
            .collect();
        assert_eq!(
            names,
            vec!["B"],
            "unregistered action A survived the reconnect replay"
        );
    }

    #[test]
    fn bootstrap_cache_unregister_without_register_is_inert() {
        let mut c = BootstrapCache::default();
        c.observe(r#"{"command":"actions/unregister","data":{"action_names":["A"]}}"#);
        assert!(c.lines().is_empty());
        c.observe(r#"{"command":"actions/register","data":{"actions":[{"name":"A"}]}}"#);
        assert_eq!(c.lines().len(), 1);
        assert!(c.lines()[0].contains("\"A\""));
    }

    #[test]
    fn bootstrap_cache_register_after_unregister_wins() {
        let mut c = BootstrapCache::default();
        c.observe(r#"{"command":"actions/register","data":{"actions":[{"name":"A"}]}}"#);
        c.observe(r#"{"command":"actions/unregister","data":{"action_names":["A"]}}"#);
        c.observe(r#"{"command":"actions/register","data":{"actions":[{"name":"A"},{"name":"C"}]}}"#);
        let lines = c.lines();
        assert_eq!(lines.len(), 1);
        let replayed: Value = serde_json::from_str(&lines[0]).unwrap();
        let names: Vec<&str> = replayed["data"]["actions"]
            .as_array()
            .unwrap()
            .iter()
            .map(|a| a["name"].as_str().unwrap())
            .collect();
        assert_eq!(names, vec!["A", "C"]);
    }

    #[test]
    fn bootstrap_from_text_replays_surviving_actions_only_and_no_context() {
        let data = concat!(
            r#"{"command":"startup","session_id":9}"#, "\n",
            r#"{"command":"actions/register","data":{"actions":[{"name":"A"},{"name":"B"}]}}"#, "\n",
            r#"{"command":"actions/unregister","data":{"action_names":["A"]}}"#, "\n",
            r#"{"command":"context","data":{"message":"hi"}}"#, "\n",
        );
        let lines = bootstrap_from_text(data);
        assert_eq!(lines.len(), 2);
        assert!(lines[0].contains("startup"));
        assert!(lines[1].contains("actions/register"));
        assert!(
            !lines.iter().any(|l| l.contains("context")),
            "the outbox rescan replayed a context frame"
        );
        assert!(
            !lines[1].contains("\"A\""),
            "outbox rescan replayed an action that had been unregistered"
        );
        assert!(lines[1].contains("\"B\""));
    }

    #[test]
    fn reregister_all_line_is_a_bare_spec_command() {
        let value: Value = serde_json::from_str(REREGISTER_ALL_LINE).unwrap();
        let obj = value.as_object().unwrap();
        assert_eq!(obj.len(), 1);
        assert_eq!(obj["command"], "actions/reregister_all");
        assert_eq!(command_from_line(REREGISTER_ALL_LINE).as_deref(), Some("actions/reregister_all"));
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
    async fn bootstrap_skips_only_lines_with_invalid_utf8() {
        let dir = scratch_dir("invalid_utf8_bootstrap");
        fs::create_dir_all(&dir).await.unwrap();
        let outbox = dir.join("neuro_outbox.jsonl");
        let mut bytes =
            br#"{"command":"startup","game":"Balatro"}"#.to_vec();
        bytes.push(b'\n');
        bytes.extend_from_slice(br#"{"command":"startup","game":"Poisoned"#);
        bytes.push(0xff);
        bytes.extend_from_slice(b"\"}\n");
        bytes.extend_from_slice(
            b"{\"command\":\"actions/register\",\"game\":\"Balatro\",\"data\":{\"actions\":[{\"name\":\"A\"}]}}\n",
        );
        fs::write(&outbox, &bytes).await.unwrap();

        let (pos, lines) = bootstrap_messages(&outbox).await.unwrap();
        assert_eq!(pos, bytes.len() as u64);
        assert_eq!(lines.len(), 2);
        let startup: Value = serde_json::from_str(&lines[0]).unwrap();
        assert_eq!(startup["game"], "Balatro");
        assert_eq!(command_from_line(&lines[1]).as_deref(), Some("actions/register"));
        let _ = fs::remove_dir_all(&dir).await;
    }

    #[tokio::test]
    async fn cancelling_run_session_closes_the_server_connection() {
        let dir = scratch_dir("cancel_session");
        fs::create_dir_all(&dir).await.unwrap();
        let outbox = dir.join("neuro_outbox.jsonl");
        let inbox = dir.join("neuro_inbox.jsonl");
        fs::write(&outbox, "{\"command\":\"startup\",\"game\":\"Balatro\"}\n")
            .await
            .unwrap();

        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let (bootstrap_tx, bootstrap_rx) = tokio::sync::oneshot::channel();
        let server = tokio::spawn(async move {
            let (stream, _) = listener.accept().await.unwrap();
            let mut ws = tokio_tungstenite::accept_async(stream).await.unwrap();
            let first = ws.next().await;
            bootstrap_tx.send(first).ok();
            match time::timeout(Duration::from_secs(2), ws.next()).await {
                Ok(None) | Ok(Some(Err(_))) | Ok(Some(Ok(Message::Close(_)))) => true,
                _ => false,
            }
        });

        let cfg = Config {
            ws_url: format!("ws://{}", addr),
            outbox,
            inbox,
            orphan_timeout: Duration::from_secs(DEFAULT_ORPHAN_TIMEOUT_SECS),
        };
        let mut cache = BootstrapCache::default();
        let pending = Arc::new(Mutex::new(PendingTracker::new()));
        let mut session = Box::pin(run_session(&cfg, None, &mut cache, pending));
        let first = tokio::select! {
            first = bootstrap_rx => first.unwrap(),
            result = session.as_mut() => panic!("run_session exited before cancellation: {:?}", result),
        };
        assert!(matches!(first, Some(Ok(Message::Text(_)))));
        // Poll once instead of racing a 50 ms client timer against the server's 2 s timeout. Under
        // scheduler starvation both wall-clock deadlines can mature before either task is polled,
        // making a healthy session look as though it exited before cancellation.
        assert!(session.as_mut().now_or_never().is_none());
        drop(session);
        assert!(
            server.await.unwrap(),
            "server did not observe the websocket closing after run_session cancellation"
        );
        let _ = fs::remove_dir_all(&dir).await;
    }
    #[tokio::test]
    async fn a_restarted_game_sends_startup_before_answering_an_orphaned_action() {
        let dir = scratch_dir("session_orphan_order");
        fs::create_dir_all(&dir).await.unwrap();
        let outbox = dir.join("neuro_outbox.jsonl");
        let inbox = dir.join("neuro_inbox.jsonl");
        fs::write(&outbox, "{\"command\":\"startup\",\"game\":\"Balatro\"}\n")
            .await
            .unwrap();

        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let (frame_tx, mut frame_rx) = mpsc::channel::<String>(8);
        let server = tokio::spawn(async move {
            let (stream, _) = listener.accept().await.unwrap();
            let mut ws = tokio_tungstenite::accept_async(stream).await.unwrap();
            while let Some(Ok(msg)) = ws.next().await {
                if let Message::Text(text) = msg {
                    if frame_tx.send(text).await.is_err() {
                        break;
                    }
                }
            }
        });

        let cfg = Config {
            ws_url: format!("ws://{}", addr),
            outbox: outbox.clone(),
            inbox: inbox.clone(),
            orphan_timeout: Duration::from_secs(DEFAULT_ORPHAN_TIMEOUT_SECS),
        };
        let pending = Arc::new(Mutex::new(PendingTracker::new()));
        let session = tokio::spawn({
            let pending = pending.clone();
            async move {
                let mut cache_inner = BootstrapCache::default();
                let _ = run_session(&cfg, None, &mut cache_inner, pending).await;
            }
        });

        async fn next_frame(rx: &mut mpsc::Receiver<String>) -> Value {
            let text = time::timeout(Duration::from_secs(10), rx.recv())
                .await
                .expect("no frame arrived in time")
                .expect("websocket closed early");
            serde_json::from_str::<Value>(&text).unwrap()
        }

        let bootstrap_startup = next_frame(&mut frame_rx).await;
        assert_eq!(bootstrap_startup["command"], "startup");

        pending.lock().unwrap().sent("orphan-1", Instant::now());
        append_line(&outbox, "{\"command\":\"startup\",\"game\":\"Balatro\"}")
            .await
            .unwrap();

        let restart_startup = next_frame(&mut frame_rx).await;
        assert_eq!(
            restart_startup["command"], "startup",
            "the restart startup must reach the socket before anything else"
        );
        let orphan = next_frame(&mut frame_rx).await;
        assert_eq!(orphan["command"], "action/result");
        assert_eq!(orphan["data"]["id"], "orphan-1");

        session.abort();
        server.abort();
        let _ = fs::remove_dir_all(&dir).await;
    }

    #[tokio::test]
    async fn without_a_startup_no_orphan_result_is_sent_first() {
        let dir = scratch_dir("session_orphan_nostartup");
        fs::create_dir_all(&dir).await.unwrap();
        let outbox = dir.join("neuro_outbox.jsonl");
        let inbox = dir.join("neuro_inbox.jsonl");
        fs::write(&outbox, "").await.unwrap();

        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let server = tokio::spawn(async move {
            let (stream, _) = listener.accept().await.unwrap();
            let mut ws = tokio_tungstenite::accept_async(stream).await.unwrap();
            let frame = time::timeout(Duration::from_secs(3), ws.next()).await;
            let _ = ws.close(None).await;
            frame
        });

        let cfg = Config {
            ws_url: format!("ws://{}", addr),
            outbox: outbox.clone(),
            inbox: inbox.clone(),
            orphan_timeout: Duration::from_millis(1),
        };
        let pending = Arc::new(Mutex::new(PendingTracker::new()));
        pending.lock().unwrap().sent("orphan-2", Instant::now());

        let session = tokio::spawn({
            let pending = pending.clone();
            async move {
                let mut cache_inner = BootstrapCache::default();
                let _ = run_session(&cfg, None, &mut cache_inner, pending).await;
            }
        });

        let frame = time::timeout(Duration::from_secs(20), server)
            .await
            .expect("server timed out")
            .unwrap();
        session.abort();

        assert!(
            frame.is_err(),
            "no frame may precede startup, got {:?}",
            frame
        );
        assert!(
            pending.lock().unwrap().drain_for_restart().contains(&"orphan-2".to_string()),
            "a held orphan must stay pending, not be dropped"
        );
    }

    #[test]
    fn a_register_emptied_by_unregister_is_not_replayed() {
        let mut c = BootstrapCache::default();
        c.observe("{\"command\":\"startup\",\"game\":\"Balatro\"}");
        c.observe(
            "{\"command\":\"actions/register\",\"game\":\"Balatro\",\"data\":{\"actions\":[{\"name\":\"play_hand\",\"description\":\"d\"}]}}",
        );
        c.observe(
            "{\"command\":\"actions/unregister\",\"game\":\"Balatro\",\"data\":{\"action_names\":[\"play_hand\"]}}",
        );
        let lines = c.replay_lines();
        assert_eq!(lines.len(), 1);
        assert_eq!(
            command_from_line(&lines[0]).as_deref(),
            Some("startup"),
            "an emptied register must not be replayed"
        );
    }

    #[test]
    fn sanitize_for_wire_rejects_a_register_with_no_actions() {
        assert_eq!(
            sanitize_for_wire(
                "{\"command\":\"actions/register\",\"game\":\"Balatro\",\"data\":{\"actions\":[]}}"
            ),
            None
        );
    }

    #[tokio::test]
    async fn a_second_session_in_one_process_does_not_repeat_startup() {
        let dir = scratch_dir("session_second_startup");
        fs::create_dir_all(&dir).await.unwrap();
        let outbox = dir.join("neuro_outbox.jsonl");
        let inbox = dir.join("neuro_inbox.jsonl");
        fs::write(
            &outbox,
            "{\"command\":\"startup\",\"game\":\"Balatro\"}\n{\"command\":\"actions/register\",\"game\":\"Balatro\",\"data\":{\"actions\":[{\"name\":\"play_hand\",\"description\":\"d\"}]}}\n",
        )
        .await
        .unwrap();

        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let server = tokio::spawn(async move {
            let mut sessions = Vec::new();
            for session in 0..2 {
                let (stream, _) = listener.accept().await.unwrap();
                let mut ws = tokio_tungstenite::accept_async(stream).await.unwrap();
                let mut frames = Vec::new();
                while let Ok(Some(Ok(message))) = time::timeout(Duration::from_secs(3), ws.next()).await {
                    if let Message::Text(text) = message {
                        let is_gap = text.contains("reconnect gap fact");
                        frames.push(text);
                        if session == 0 || is_gap { break; }
                    }
                }
                sessions.push(frames);
                let _ = ws.close(None).await;
            }
            sessions
        });

        let cfg = Config {
            ws_url: format!("ws://{}", addr),
            outbox: outbox.clone(),
            inbox,
            orphan_timeout: Duration::from_secs(DEFAULT_ORPHAN_TIMEOUT_SECS),
        };
        let mut cache = BootstrapCache::default();
        let pending = Arc::new(Mutex::new(PendingTracker::new()));
        let resume = time::timeout(
            Duration::from_secs(20),
            run_session(&cfg, None, &mut cache, pending.clone()),
        )
        .await
        .expect("first session timed out")
        .expect("first session failed");
        fs::OpenOptions::new()
            .append(true)
            .open(&outbox)
            .await
            .unwrap()
            .write_all(b"{\"command\":\"context\",\"game\":\"Balatro\",\"data\":{\"message\":\"reconnect gap fact\",\"silent\":true}}\n")
            .await
            .unwrap();
        time::timeout(
            Duration::from_secs(20),
            run_session(&cfg, Some(resume), &mut cache, pending),
        )
        .await
        .expect("second session timed out")
        .expect("second session failed");

        let sessions = server.await.unwrap();
        assert_eq!(sessions.len(), 2);
        let first: Value = serde_json::from_str(&sessions[0][0]).unwrap();
        let second: Value = serde_json::from_str(&sessions[1][0]).unwrap();
        assert_eq!(first["command"], "startup");
        assert_eq!(
            second["command"], "actions/register",
            "startup is sent once per process, so a reconnect opens with the cached register"
        );
        assert!(sessions[1].iter().any(|line| line.contains("reconnect gap fact")),
            "a line appended after disconnect must be tailed from the saved byte mark");
        let _ = fs::remove_dir_all(&dir).await;
    }

    #[tokio::test]
    async fn outbox_lines_before_the_tail_start_are_never_replayed() {
        let dir = scratch_dir("session_stale_tail");
        fs::create_dir_all(&dir).await.unwrap();
        let outbox = dir.join("neuro_outbox.jsonl");
        let inbox = dir.join("neuro_inbox.jsonl");
        fs::write(
            &outbox,
            "{\"command\":\"startup\",\"game\":\"Balatro\"}\n{\"command\":\"context\",\"game\":\"Balatro\",\"data\":{\"message\":\"stale facts\",\"silent\":true}}\n{\"command\":\"actions/force\",\"game\":\"Balatro\",\"data\":{\"query\":\"stale decision\",\"action_names\":[\"play_hand\"]}}\n",
        )
        .await
        .unwrap();

        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let server = tokio::spawn(async move {
            let (stream, _) = listener.accept().await.unwrap();
            let mut ws = tokio_tungstenite::accept_async(stream).await.unwrap();
            let mut frames = Vec::new();
            while let Ok(Some(Ok(msg))) = time::timeout(Duration::from_secs(3), ws.next()).await {
                if let Message::Text(text) = msg {
                    frames.push(text);
                }
            }
            let _ = ws.close(None).await;
            frames
        });

        let cfg = Config {
            ws_url: format!("ws://{}", addr),
            outbox: outbox.clone(),
            inbox,
            orphan_timeout: Duration::from_secs(DEFAULT_ORPHAN_TIMEOUT_SECS),
        };
        let session = tokio::spawn(async move {
            let mut cache = BootstrapCache::default();
            let pending = Arc::new(Mutex::new(PendingTracker::new()));
            let _ = run_session(&cfg, None, &mut cache, pending).await;
        });

        let frames = time::timeout(Duration::from_secs(20), server)
            .await
            .expect("server timed out")
            .unwrap();
        session.abort();

        let commands: Vec<String> = frames
            .iter()
            .map(|f| serde_json::from_str::<Value>(f).unwrap()["command"].as_str().unwrap().to_string())
            .collect();
        assert!(
            commands.contains(&"startup".to_string()),
            "bootstrap must still deliver startup, got {:?}",
            commands
        );
        assert!(
            !commands.contains(&"context".to_string()),
            "a context written before the tail start must not be replayed, got {:?}",
            commands
        );
        assert!(
            !commands.contains(&"actions/force".to_string()),
            "a force written before the tail start must not be replayed, got {:?}",
            commands
        );
        let _ = fs::remove_dir_all(&dir).await;
    }

    #[tokio::test]
    async fn run_session_rebuilds_bootstrap_after_outbox_replacement() {
        let dir = scratch_dir("session_replace");
        fs::create_dir_all(&dir).await.unwrap();
        let outbox = dir.join("neuro_outbox.jsonl");
        let inbox = dir.join("neuro_inbox.jsonl");
        fs::write(&outbox, "{\"command\":\"startup\",\"game\":\"Balatro\"}\n")
            .await
            .unwrap();

        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let server = tokio::spawn(async move {
            let mut first_frames = Vec::new();
            for _ in 0..2 {
                let (stream, _) = listener.accept().await.unwrap();
                let mut ws = tokio_tungstenite::accept_async(stream).await.unwrap();
                first_frames.push(ws.next().await);
                let _ = ws.close(None).await;
            }
            first_frames
        });

        let cfg = Config {
            ws_url: format!("ws://{}", addr),
            outbox: outbox.clone(),
            inbox,
            orphan_timeout: Duration::from_secs(DEFAULT_ORPHAN_TIMEOUT_SECS),
        };
        let mut cache = BootstrapCache::default();
        let pending = Arc::new(Mutex::new(PendingTracker::new()));
        let resume = time::timeout(
            Duration::from_secs(20),
            run_session(&cfg, None, &mut cache, pending.clone()),
        )
        .await
        .expect("first run_session timed out")
        .expect("first run_session failed");

        let replacement = dir.join("replacement.jsonl");
        fs::write(&replacement, "{\"command\":\"startup\",\"game\":\"Replaced\"}\n")
            .await
            .unwrap();
        fs::rename(&replacement, &outbox).await.unwrap();

        time::timeout(
            Duration::from_secs(20),
            run_session(&cfg, Some(resume), &mut cache, pending),
        )
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
        let _ = fs::remove_dir_all(&dir).await;
    }


    // A bridge restart used to re-send transport_session = 1, which the mod reads as "same client"
    // and answers by skipping the non-idempotent half of its reconnect (core/dispatcher.lua).
    #[test]
    fn a_restarted_bridge_cannot_repeat_an_earlier_process_stamp() {
        let earlier = process_session_base();
        assert!(earlier > 0, "the stamp base must not restart at zero");
        std::thread::sleep(std::time::Duration::from_millis(2));
        let later = process_session_base();
        assert!(later > earlier, "a later process must start above an earlier one: {later} !> {earlier}");
        assert!(
            later - earlier >= 1_000,
            "a process would have to open a websocket session every microsecond to reach the next base: {later} - {earlier}"
        );
    }

    #[test]
    fn successive_websocket_sessions_in_one_process_still_advance() {
        let first = next_transport_session();
        let second = next_transport_session();
        assert!(second > first, "{second} !> {first}");
        let now = process_session_base();
        assert!(
            first <= now && first + 3_600_000_000 > now,
            "the stamp is seeded from this process's start, not from zero: {first} against {now}"
        );
    }

    #[test]
    fn reregister_line_carries_only_the_ipc_session_stamp() {
        let first: Value = serde_json::from_str(&reregister_line_for_session(1)).unwrap();
        let second: Value = serde_json::from_str(&reregister_line_for_session(2)).unwrap();
        assert_eq!(first["command"], "actions/reregister_all");
        assert_ne!(first["transport_session"], second["transport_session"]);
        assert_eq!(sanitize_for_wire(&reregister_line_for_session(1)), None);
    }

    #[tokio::test]
    async fn each_websocket_session_stamps_a_new_transport_session() {
        let dir = scratch_dir("reregister_epoch");
        fs::create_dir_all(&dir).await.unwrap();
        let inbox = dir.join("neuro_inbox.jsonl");
        request_action_reregistration(&inbox, 41).await;
        request_action_reregistration(&inbox, 42).await;
        let written = fs::read_to_string(&inbox).await.unwrap();
        let stamps: Vec<u64> = written
            .lines()
            .filter(|l| !l.trim().is_empty())
            .map(|l| serde_json::from_str::<Value>(l).unwrap()["transport_session"].as_u64().unwrap())
            .collect();
        assert_eq!(stamps, vec![41, 42]);
        let _ = fs::remove_dir_all(&dir).await;
    }

    #[tokio::test]
    async fn request_action_reregistration_appends_one_bare_command() {
        let dir = scratch_dir("reregister_unit");
        fs::create_dir_all(&dir).await.unwrap();
        let inbox = dir.join("neuro_inbox.jsonl");
        request_action_reregistration(&inbox, 7).await;
        let written = fs::read_to_string(&inbox).await.unwrap();
        let value: Value = serde_json::from_str(written.trim()).unwrap();
        assert_eq!(value["command"], "actions/reregister_all");
        assert_eq!(value["transport_session"], 7);
        assert_eq!(value.as_object().unwrap().len(), 2);
        let _ = fs::remove_dir_all(&dir).await;
    }

    #[tokio::test]
    async fn a_new_websocket_session_asks_the_mod_to_reregister() {
        let dir = scratch_dir("reregister_session");
        fs::create_dir_all(&dir).await.unwrap();
        let outbox = dir.join("neuro_outbox.jsonl");
        let inbox = dir.join("neuro_inbox.jsonl");
        fs::write(&outbox, "{\"command\":\"startup\",\"game\":\"Balatro\"}\n").await.unwrap();

        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let server = tokio::spawn(async move {
            let (stream, _) = listener.accept().await.unwrap();
            let mut ws = tokio_tungstenite::accept_async(stream).await.unwrap();
            let first = ws.next().await;
            let _ = ws.close(None).await;
            first
        });

        let cfg = Config { ws_url: format!("ws://{}", addr), outbox, inbox: inbox.clone(), orphan_timeout: Duration::from_secs(DEFAULT_ORPHAN_TIMEOUT_SECS) };
        let mut cache = BootstrapCache::default();
        let pending = Arc::new(Mutex::new(PendingTracker::new()));
        let _ = time::timeout(
            Duration::from_secs(20),
            run_session(&cfg, None, &mut cache, pending),
        )
        .await;

        let delivered = fs::read_to_string(&inbox).await.unwrap_or_default();
        assert!(
            delivered.lines().any(|l| command_from_line(l).as_deref() == Some("actions/reregister_all")),
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
        let _ = fs::remove_dir_all(&dir).await;
    }

    #[test]
    fn bootstrap_cache_ignores_unrelated_lines() {
        let mut c = BootstrapCache::default();
        c.observe(r#"{"command":"action","data":{"id":"x","name":"help"}}"#);
        c.observe(r#"{"command":"action/result","data":{"id":"x","success":true}}"#);
        assert!(c.lines().is_empty(), "only startup/register should be cached");
    }

    #[test]
    fn t1_stale_after_timeout() {
        let mut pt = PendingTracker::new();
        let t0 = Instant::now();
        pt.sent("a", t0);
        let stale = pt.drain_stale(t0 + Duration::from_secs(31), Duration::from_secs(30));
        assert_eq!(stale, vec!["a"]);
    }

    #[test]
    fn t2_not_stale_before_timeout() {
        let mut pt = PendingTracker::new();
        let t0 = Instant::now();
        pt.sent("a", t0);
        let stale = pt.drain_stale(t0 + Duration::from_secs(29), Duration::from_secs(30));
        assert!(stale.is_empty());
    }

    #[test]
    fn t3_stale_then_observe_suppresses() {
        let mut pt = PendingTracker::new();
        let t0 = Instant::now();
        pt.sent("a", t0);
        let stale = pt.drain_stale(t0 + Duration::from_secs(999), Duration::from_secs(30));
        assert_eq!(stale, vec!["a"]);
        assert_eq!(pt.observe_mod_result("a"), ModResult::Suppress);
    }

    #[test]
    fn t4_observe_forward_then_suppress() {
        let mut pt = PendingTracker::new();
        let t0 = Instant::now();
        pt.sent("a", t0);
        assert_eq!(pt.observe_mod_result("a"), ModResult::Forward);
        assert_eq!(pt.observe_mod_result("a"), ModResult::Suppress);
    }

    #[test]
    fn t4c_peek_does_not_mark_answered_so_a_failed_send_can_retry() {
        let mut t = PendingTracker::new();
        let now = Instant::now();
        t.sent("z1", now);
        assert!(!t.already_answered("z1"), "peek must not mark the id as answered");
        assert!(!t.already_answered("z1"), "peek must stay side-effect free when repeated");
        assert_eq!(
            t.observe_mod_result("z1"),
            ModResult::Forward,
            "after a confirmed send the first observe must still forward"
        );
        assert!(t.already_answered("z1"), "observe marks it answered");
        assert_eq!(
            t.observe_mod_result("z1"),
            ModResult::Suppress,
            "a second observe for the same id must be suppressed"
        );
    }

    #[test]
    fn t4b_observe_clears_pending_so_never_stale() {
        let mut pt = PendingTracker::new();
        let t0 = Instant::now();
        pt.sent("a", t0);
        assert_eq!(pt.observe_mod_result("a"), ModResult::Forward);
        let stale = pt.drain_stale(t0 + Duration::from_secs(999), Duration::from_secs(30));
        assert!(stale.is_empty());
    }

    #[test]
    fn reconnect_reopens_result_forwarding_but_preserves_unanswered_work() {
        let mut pt = PendingTracker::new();
        let t0 = Instant::now();
        pt.sent("answered", t0);
        pt.sent("pending", t0);
        assert_eq!(pt.observe_mod_result("answered"), ModResult::Forward);
        assert!(pt.already_answered("answered"));

        pt.begin_session();

        assert!(!pt.already_answered("answered"));
        assert_eq!(pt.observe_mod_result("answered"), ModResult::Forward);
        let stale = pt.drain_stale(t0 + Duration::from_secs(31), Duration::from_secs(30));
        assert_eq!(stale, vec!["pending"]);
    }

    #[test]
    fn t5_restart_drains_all_then_stale_empty() {
        let mut pt = PendingTracker::new();
        let t0 = Instant::now();
        pt.sent("a", t0);
        pt.sent("b", t0);
        let drained = pt.drain_for_restart();
        assert_eq!(drained.len(), 2);
        assert!(drained.contains(&"a".to_string()));
        assert!(drained.contains(&"b".to_string()));
        let stale = pt.drain_stale(t0 + Duration::from_secs(999), Duration::from_secs(30));
        assert!(stale.is_empty());
    }

    #[test]
    fn t6_answered_never_stale() {
        let mut pt = PendingTracker::new();
        let t0 = Instant::now();
        pt.mark_answered("a");
        pt.sent("a", t0);
        let stale = pt.drain_stale(t0 + Duration::from_secs(999), Duration::from_secs(30));
        assert!(stale.is_empty());
    }

    #[test]
    fn t7_stalled_orphan_frame_has_correct_shape() {
        let frame = orphan_action_result("abc", "Balatro", STALLED_ORPHAN_MESSAGE);
        let v: Value = serde_json::from_str(&frame).unwrap();
        assert_eq!(v["command"], "action/result");
        assert_eq!(v["game"], "Balatro");
        assert_eq!(v["data"]["id"], "abc");
        assert_eq!(
            v["data"]["success"], true,
            "an orphan must be acknowledged without retrying its dead force"
        );
        assert!(v["data"]["message"].as_str().unwrap().len() > 0);
    }

    #[test]
    fn t8_stalled_orphan_survives_sanitize() {
        let frame = orphan_action_result("abc", "Balatro", STALLED_ORPHAN_MESSAGE);
        let sanitized = sanitize_for_wire(&frame).expect("orphan frame must survive sanitize");
        let v: Value = serde_json::from_str(&sanitized).unwrap();
        assert_eq!(v["data"]["id"], "abc");
        assert_eq!(v["data"]["success"], true);
        assert!(v["data"]["message"].as_str().unwrap().len() > 0);
    }

    #[test]
    fn t9_restart_orphan_survives_sanitize() {
        let frame = orphan_action_result("xyz", "Balatro", RESTART_ORPHAN_MESSAGE);
        let sanitized = sanitize_for_wire(&frame).expect("restart orphan frame must survive sanitize");
        let v: Value = serde_json::from_str(&sanitized).unwrap();
        assert_eq!(v["data"]["id"], "xyz");
        assert_eq!(v["data"]["success"], true);
        assert!(v["data"]["message"].as_str().unwrap().len() > 0);
    }

    #[test]
    fn t10_context_strips_unknown_data_fields() {
        let out = sanitize_for_wire(
            r#"{"command":"context","game":"Balatro","data":{"message":"hi","silent":true,"debug":"x"}}"#,
        ).unwrap();
        let v: Value = serde_json::from_str(&out).unwrap();
        assert_eq!(v["data"]["message"], "hi");
        assert_eq!(v["data"]["silent"], true);
        assert!(v["data"].get("debug").is_none());
    }

    #[test]
    fn t11_register_strips_unknown_data_fields() {
        let out = sanitize_for_wire(
            r#"{"command":"actions/register","game":"Balatro","data":{"actions":[{"name":"a","description":"A","schema":{"type":"object"}}],"debug":"x"}}"#,
        ).unwrap();
        let v: Value = serde_json::from_str(&out).unwrap();
        assert_eq!(v["data"]["actions"][0]["name"], "a");
        assert!(v["data"].get("debug").is_none());
    }

    #[test]
    fn t12_unregister_strips_unknown_data_fields() {
        let out = sanitize_for_wire(
            r#"{"command":"actions/unregister","game":"Balatro","data":{"action_names":["a","b"],"debug":"x"}}"#,
        ).unwrap();
        let v: Value = serde_json::from_str(&out).unwrap();
        let names: Vec<&str> = v["data"]["action_names"].as_array().unwrap().iter().map(|n| n.as_str().unwrap()).collect();
        assert_eq!(names, vec!["a", "b"]);
        assert!(v["data"].get("debug").is_none());
    }

    #[test]
    fn t13_force_with_all_optional_fields_keeps_every_spec_field() {
        let out = sanitize_for_wire(
            r#"{"command":"actions/force","game":"Balatro","data":{"state":"S","query":"Q","ephemeral_context":true,"priority":"medium","action_names":["a"],"debug":"x"}}"#,
        ).unwrap();
        let v: Value = serde_json::from_str(&out).unwrap();
        assert_eq!(v["data"]["state"], "S");
        assert_eq!(v["data"]["query"], "Q");
        assert_eq!(v["data"]["ephemeral_context"], true);
        assert_eq!(v["data"]["priority"], "medium");
        assert_eq!(v["data"]["action_names"][0], "a");
        assert!(v["data"].get("debug").is_none());
    }

    #[test]
    fn t14_force_without_optional_fields_does_not_gain_them() {
        let out = sanitize_for_wire(
            r#"{"command":"actions/force","game":"Balatro","data":{"query":"Q","action_names":["a"]}}"#,
        ).unwrap();
        let v: Value = serde_json::from_str(&out).unwrap();
        assert_eq!(v["data"]["query"], "Q");
        assert_eq!(v["data"]["action_names"][0], "a");
        assert!(v["data"].get("state").is_none());
        assert!(v["data"].get("priority").is_none());
        assert!(v["data"].get("ephemeral_context").is_none());
    }
}
