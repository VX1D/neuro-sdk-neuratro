use super::*;

pub(crate) const INVALID_ACTION_NAME: &str = "\0neuro-invalid-action-name";
pub(crate) const MAX_ACTION_ID_BYTES: usize = 1024 * 1024;
pub(crate) const MAX_TRACKED_ACTIONS: usize = 4096;

pub(crate) fn encoded_action_id_bytes(id: &str) -> Option<usize> {
    serde_json::to_string(id).ok().map(|encoded| encoded.len())
}

pub(crate) fn action_id_fits_bounds(id: &str) -> bool {
    !id.is_empty() && encoded_action_id_bytes(id).is_some_and(|bytes| bytes <= MAX_ACTION_ID_BYTES)
}

pub(crate) fn redacted_action_id(id: &str) -> String {
    let mut hash = FNV_OFFSET;
    fingerprint_update(&mut hash, id.as_bytes());
    let encoded = encoded_action_id_bytes(id).unwrap_or(usize::MAX);
    format!("id bytes={encoded}, fnv64={hash:016x}")
}

pub(crate) fn game_name_fits_bounds(name: &str) -> bool {
    name.bytes().any(|byte| !byte.is_ascii_whitespace())
}

pub(crate) fn registrable_action_name(value: &str) -> bool {
    !value.is_empty()
        && value
            .bytes()
            .all(|b| matches!(b, b'a'..=b'z' | b'0'..=b'9' | b'_' | b'-'))
}
pub(crate) const MAX_ACTION_NAMES: usize = 256;

pub(crate) fn valid_action_names(value: &Value) -> bool {
    let Some(names) = value.as_array() else {
        return false;
    };
    if names.len() > MAX_ACTION_NAMES {
        return false;
    }
    names
        .iter()
        .all(|name| name.as_str().is_some_and(|name| !name.is_empty()))
}

pub(crate) fn parse_json_line(line: &str) -> Option<Value> {
    if line.len() > MAX_COMMAND_BYTES {
        eprintln!("[Warning] Skipping oversized line ({} bytes)", line.len());
        return None;
    }
    serde_json::from_str(line).ok()
}

pub(crate) struct ParsedLine {
    value: Option<Value>,
}

impl ParsedLine {
    pub(crate) fn parse(line: &str) -> Self {
        Self {
            value: parse_json_line(line),
        }
    }

    fn field(&self, key: &str) -> Option<&Value> {
        self.value.as_ref()?.as_object()?.get(key)
    }

    pub(crate) fn command(&self) -> Option<&str> {
        self.field("command")?.as_str()
    }

    pub(crate) fn game(&self) -> Option<&str> {
        game_of(self.value.as_ref()?)
    }

    pub(crate) fn result_id(&self) -> Option<String> {
        if self.command()? != "action/result" {
            return None;
        }
        let id = self.field("data")?.get("id")?.as_str()?;
        action_id_fits_bounds(id).then(|| id.to_string())
    }

    pub(crate) fn answer_session(&self) -> Option<u64> {
        startup_answer_session_of(self.value.as_ref()?)
    }

    pub(crate) fn wire_frame(&self, line: &str) -> Option<WireFrame> {
        sanitize_value(self.value.clone(), line)
    }

    pub(crate) fn take_wire_frame(&mut self, line: &str) -> Option<WireFrame> {
        sanitize_value(self.value.take(), line)
    }
}

pub(crate) struct WireFrame {
    pub(crate) text: String,
    pub(crate) value: Value,
}

impl WireFrame {
    pub(crate) fn game(&self) -> Option<&str> {
        game_of(&self.value)
    }
}

fn game_of(value: &Value) -> Option<&str> {
    value.get("game")?.as_str().filter(|name| !name.is_empty())
}

pub(crate) const SUPPORTED_C2S_COMMANDS: &[&str] = &[
    "startup",
    "context",
    "actions/register",
    "actions/unregister",
    "actions/force",
    "action/result",
];

fn data_keys(command: &str) -> &'static [&'static str] {
    match command {
        "context" => &["message", "silent"],
        "actions/register" => &["actions"],
        "actions/unregister" => &["action_names"],
        "actions/force" => &[
            "state",
            "query",
            "ephemeral_context",
            "priority",
            "action_names",
        ],
        "action/result" => &["id", "success", "message"],
        _ => &[],
    }
}

pub(crate) fn redacted_payload_detail(line: &str) -> String {
    let mut hash = FNV_OFFSET;
    fingerprint_update(&mut hash, line.as_bytes());
    format!("{} bytes, fnv64={hash:016x}", line.len())
}

pub(crate) fn drop_from_wire<T>(reason: &str, line: &str) -> Option<T> {
    eprintln!(
        "[Error] Dropping outbox line ({}; {})",
        reason,
        redacted_payload_detail(line)
    );
    None
}

fn drop_register_element(action: &Value) {
    let name = action
        .get("name")
        .and_then(Value::as_str)
        .filter(|name| !name.is_empty() && name.len() <= 128)
        .map_or_else(|| "<unnamed>".to_string(), |name| format!("{name:?}"));
    eprintln!(
        "[Error] Dropping malformed action definition {} from actions/register ({})",
        name,
        redacted_payload_detail(&action.to_string())
    );
}

pub(crate) fn sanitize_value(value: Option<Value>, line: &str) -> Option<WireFrame> {
    let Some(value) = value else {
        return drop_from_wire(
            if line.len() > MAX_COMMAND_BYTES {
                "oversized line"
            } else {
                "not valid JSON"
            },
            line,
        );
    };
    let Value::Object(mut obj) = value else {
        return drop_from_wire("not a JSON object", line);
    };
    let mut out = serde_json::Map::new();
    for key in ["command", "game", "data"] {
        if let Some(v) = obj.remove(key) {
            out.insert(key.to_string(), v);
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
        return drop_from_wire("missing game field", line);
    };
    if !game_name_fits_bounds(game) {
        return drop_from_wire("invalid or oversized game field", line);
    }
    if !SUPPORTED_C2S_COMMANDS.contains(&command.as_str()) {
        return drop_from_wire("unsupported command", line);
    }

    if command == "startup" {
        out.remove("data");
    } else if let Some(Value::Object(data)) = out.get_mut("data") {
        data.retain(|k, _| data_keys(&command).contains(&k.as_str()));
        if let Some(actions) = data.get_mut("actions").and_then(Value::as_array_mut) {
            let mut seen = std::collections::HashSet::new();
            *actions = std::mem::take(actions)
                .into_iter()
                .filter(|action| {
                    let valid = valid_action_definition(action)
                        && seen.insert(action["name"].as_str().unwrap_or_default().to_owned());
                    if !valid {
                        drop_register_element(action);
                    }
                    valid
                })
                .map(project_action_definition)
                .collect();
        }
    }

    let data = out.get("data").and_then(Value::as_object);
    let valid = match command.as_str() {
        "startup" => true,
        "context" => data.is_some_and(|data| {
            data.get("message").is_some_and(Value::is_string)
                && data.get("silent").is_some_and(Value::is_boolean)
        }),
        "actions/register" => data.is_some_and(|data| {
            data.get("actions")
                .and_then(Value::as_array)
                .is_some_and(|actions| !actions.is_empty())
        }),
        "actions/unregister" => {
            data.is_some_and(|data| data.get("action_names").is_some_and(valid_action_names))
        }
        "actions/force" => data.is_some_and(valid_action_force),
        "action/result" => data.is_some_and(|data| {
            data.get("id")
                .and_then(Value::as_str)
                .is_some_and(action_id_fits_bounds)
                && data.get("success").is_some_and(Value::is_boolean)
                && data.get("message").is_none_or(Value::is_string)
        }),
        _ => false,
    };
    if !valid {
        return drop_from_wire("invalid command data", line);
    }
    let value = Value::Object(out);
    let text = value.to_string();
    if text.len() > MAX_COMMAND_BYTES {
        return drop_from_wire("serialized frame too large", &text);
    }
    Some(WireFrame { text, value })
}

fn valid_action_definition(value: &Value) -> bool {
    let Some(action) = value.as_object() else {
        return false;
    };
    action
        .get("name")
        .and_then(Value::as_str)
        .is_some_and(registrable_action_name)
        && action.get("description").is_some_and(Value::is_string)
        && action.get("schema").is_none_or(|schema| {
            schema.as_object().is_some_and(|schema| {
                schema.is_empty() || schema.get("type") == Some(&json!("object"))
            })
        })
}

fn project_action_definition(value: Value) -> Value {
    let mut projected = serde_json::Map::new();
    if let Value::Object(mut action) = value {
        for key in ["name", "description", "schema"] {
            if let Some(value) = action.remove(key) {
                projected.insert(key.to_string(), value);
            }
        }
    }
    Value::Object(projected)
}

pub(crate) fn valid_action_force(data: &serde_json::Map<String, Value>) -> bool {
    data.get("query").is_some_and(Value::is_string)
        && data.get("action_names").is_some_and(|names| {
            valid_action_names(names) && names.as_array().is_some_and(|names| !names.is_empty())
        })
        && data.get("state").is_none_or(Value::is_string)
        && data.get("ephemeral_context").is_none_or(Value::is_boolean)
        && data.get("priority").is_none_or(|priority| {
            matches!(
                priority.as_str(),
                Some("low" | "medium" | "high" | "critical")
            )
        })
}
