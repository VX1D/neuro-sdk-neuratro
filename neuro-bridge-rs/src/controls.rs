use super::*;

pub(crate) const TRANSPORT_SESSION_MARKER_PREFIX: &str = ".neuro-bridge-transport-session-";

fn transport_session_markers(parent: &Path) -> Result<Vec<(u64, PathBuf)>> {
    let mut markers = Vec::new();
    for entry in std::fs::read_dir(parent).context("scan transport-session markers")? {
        let entry = entry.context("read transport-session marker entry")?;
        let name = entry.file_name();
        let value = name
            .to_str()
            .and_then(|name| name.strip_prefix(TRANSPORT_SESSION_MARKER_PREFIX))
            .and_then(|raw| raw.parse::<u64>().ok());
        if let Some(value) = value {
            markers.push((value, entry.path()));
        }
    }
    Ok(markers)
}

pub(crate) fn next_transport_session(inbox: &Path) -> Result<u64> {
    let parent = inbox
        .parent()
        .filter(|path| !path.as_os_str().is_empty())
        .unwrap_or_else(|| Path::new("."));
    std::fs::create_dir_all(parent).context("create transport-session marker directory")?;
    ensure_ipc_dir_secure(parent)?;

    loop {
        let markers = transport_session_markers(parent)?;
        let high_water = markers.iter().map(|(value, _)| *value).max().unwrap_or(0);
        let next = high_water
            .checked_add(1)
            .context("transport-session marker sequence exhausted")?;
        let marker = parent.join(format!("{TRANSPORT_SESSION_MARKER_PREFIX}{next}"));
        match std::fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&marker)
        {
            Ok(mut file) => {
                if let Err(error) = ensure_ipc_file_secure(&marker) {
                    drop(file);
                    let _ = std::fs::remove_file(&marker);
                    return Err(error).with_context(|| {
                        format!("secure transport-session marker {}", marker.display())
                    });
                }
                std::io::Write::write_all(&mut file, next.to_string().as_bytes())?;
                file.sync_all()?;
                for (value, path) in transport_session_markers(parent).unwrap_or_default() {
                    if value < next {
                        let _ = std::fs::remove_file(path);
                    }
                }
                sync_parent_directory(&marker)?;
                return Ok(next);
            }
            Err(error) if error.kind() == std::io::ErrorKind::AlreadyExists => continue,
            Err(error) => {
                return Err(error).with_context(|| {
                    format!("reserve transport-session marker {}", marker.display())
                });
            }
        }
    }
}

pub(crate) const STARTUP_ANSWER_COMMAND: &str = "neuro-bridge/startup_answer";

pub(crate) fn startup_answer_session_of(value: &Value) -> Option<u64> {
    let object = value.as_object()?;
    if object.get("command")?.as_str()? != STARTUP_ANSWER_COMMAND {
        return None;
    }
    if !object.keys().all(|key| {
        matches!(
            key.as_str(),
            "command" | "game" | "transport_session" | "ts"
        )
    }) {
        return None;
    }
    object.get("transport_session")?.as_str()?.parse().ok()
}
pub(crate) const MAX_REREGISTER_APPEND_ATTEMPTS: u32 = 3;

pub(crate) async fn request_action_reregistration(inbox: &Path, session: u64) -> bool {
    let line =
        json!({"command": "neuro-bridge/reregister_all", "transport_session": session}).to_string();
    append_retrying(
        inbox,
        &line,
        MAX_REREGISTER_APPEND_ATTEMPTS,
        |attempt, error| {
            eprintln!(
                "[Warning] Reregister append failed (attempt {}/{}): {error:#}",
                attempt, MAX_REREGISTER_APPEND_ATTEMPTS
            );
            attempt < MAX_REREGISTER_APPEND_ATTEMPTS
        },
    )
    .await
}

pub(crate) fn command_of(value: &Value) -> Option<&str> {
    value.as_object()?.get("command")?.as_str()
}

pub(crate) fn canonical_action(value: &Value) -> Option<(String, String)> {
    if command_of(value)? != "action" {
        return None;
    }
    let data = value.get("data")?.as_object()?;
    let id = match data.get("id")? {
        Value::String(text) => text.clone(),
        Value::Number(number) => number.to_string(),
        Value::Bool(flag) => if *flag { "True" } else { "False" }.to_string(),
        _ => return None,
    };
    if !action_id_fits_bounds(&id) {
        return None;
    }

    let name = data
        .get("name")
        .and_then(Value::as_str)
        .filter(|name| !name.is_empty())
        .unwrap_or(INVALID_ACTION_NAME);
    let mut inner = json!({"id": id, "name": name});
    if let Some(action_data) = data.get("data") {
        inner["data"] = action_data.clone();
    }
    let encoded = json!({"command": "action", "data": inner}).to_string();
    (encoded.len() <= MAX_COMMAND_BYTES).then_some((encoded, id))
}

pub(crate) fn startup_ack_is_valid(value: &Value) -> bool {
    command_of(value) == Some("startup")
        && value
            .get("data")
            .and_then(|data| data.get("session"))
            .and_then(|session| session.get("characterId"))
            .and_then(Value::as_str)
            .is_some_and(|character_id| !character_id.is_empty())
}

pub(crate) fn speech_finished_is_valid(value: &Value) -> bool {
    if command_of(value) != Some("speech_finished") {
        return false;
    }
    let Some(data) = value.get("data").and_then(Value::as_object) else {
        return false;
    };
    if !data.get("isFinal").is_some_and(Value::is_boolean) {
        return false;
    }
    data.get("cancelled").is_none_or(Value::is_boolean)
        && data.get("reason").is_none_or(Value::is_string)
}

pub(crate) const BRIDGE_CONTROL_PREFIX: &str = "neuro-bridge/";
