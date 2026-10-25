use super::*;

pub(crate) const RECONNECT_INTERVAL_SECS: u64 = 3;
pub(crate) const MAX_QUEUED_RECORDS: usize = 256;

pub(crate) struct Config {
    pub(crate) ws_url: String,
    pub(crate) outbox: PathBuf,
    pub(crate) inbox: PathBuf,
    pub(crate) game_stale_after: Duration,
}

pub(crate) fn url_host_port(after_scheme: &str) -> &str {
    let end = after_scheme
        .find(['/', '?', '#'])
        .unwrap_or(after_scheme.len());
    let authority = &after_scheme[..end];
    authority
        .rsplit_once('@')
        .map_or(authority, |(_, host)| host)
}

pub(crate) fn redact_ws_url(ws_url: &str) -> String {
    match ws_url.split_once("://") {
        Some((scheme, rest)) => format!("{scheme}://{}", url_host_port(rest)),
        None => "<invalid websocket URL>".to_string(),
    }
}

fn valid_ws_port(raw: &str) -> bool {
    let normalized = raw.trim_start_matches('0');
    let normalized = if normalized.is_empty() {
        "0"
    } else {
        normalized
    };
    normalized.parse::<u16>().is_ok_and(|port| port != 0)
}

pub(crate) fn validate_ws_url(raw: &str) -> Result<(), String> {
    if raw.is_empty() {
        return Err("URL is empty".to_string());
    }
    if raw.chars().any(|ch| ch.is_control() || ch.is_whitespace()) {
        return Err("URL contains whitespace or control characters".to_string());
    }
    let Some((scheme, remainder)) = raw.split_once("://") else {
        return Err("URL must be an absolute ws:// or wss:// URL".to_string());
    };
    if !scheme.eq_ignore_ascii_case("ws") && !scheme.eq_ignore_ascii_case("wss") {
        return Err("URL scheme must be ws or wss".to_string());
    }
    if remainder.contains('#') {
        return Err("URL must not contain a fragment".to_string());
    }
    let host_port = url_host_port(remainder);
    if host_port.is_empty() {
        return Err("URL authority must contain a host".to_string());
    }
    if host_port.starts_with('[') {
        let Some(close) = host_port.find(']') else {
            return Err("URL IPv6 host is missing ]".to_string());
        };
        let host = &host_port[1..close];
        if host.is_empty() || !host.contains(':') || host.contains(&['[', ']'][..]) {
            return Err("URL IPv6 host is invalid".to_string());
        }
        let suffix = &host_port[close + 1..];
        if !suffix.is_empty() && (!suffix.starts_with(':') || !valid_ws_port(&suffix[1..])) {
            return Err("URL port is outside 1..65535".to_string());
        }
    } else {
        if host_port.contains(&['[', ']'][..]) || host_port.matches(':').count() > 1 {
            return Err("URL host must be a name or bracketed IPv6 address".to_string());
        }
        if let Some((host, port)) = host_port.split_once(':') {
            if host.is_empty() || !valid_ws_port(port) {
                return Err("URL port is outside 1..65535".to_string());
            }
        }
    }
    Ok(())
}

fn environment_ws_url() -> Option<String> {
    env::var("NEURO_SDK_WS_URL")
        .ok()
        .filter(|raw| !raw.is_empty())
        .or_else(|| persisted_env_var(false, "NEURO_SDK_WS_URL"))
        .or_else(|| persisted_env_var(true, "NEURO_SDK_WS_URL"))
}

#[cfg(windows)]
fn persisted_env_var(machine: bool, name: &str) -> Option<String> {
    use std::os::windows::ffi::OsStrExt;
    use windows_sys::Win32::System::Registry::{
        RegGetValueW, HKEY_CURRENT_USER, HKEY_LOCAL_MACHINE, RRF_RT_REG_EXPAND_SZ, RRF_RT_REG_SZ,
    };
    let wide = |text: &str| -> Vec<u16> {
        std::ffi::OsStr::new(text)
            .encode_wide()
            .chain(std::iter::once(0))
            .collect()
    };
    let (root, key) = if machine {
        (
            HKEY_LOCAL_MACHINE,
            "System\\CurrentControlSet\\Control\\Session Manager\\Environment",
        )
    } else {
        (HKEY_CURRENT_USER, "Environment")
    };
    let (key, value) = (wide(key), wide(name));
    let flags = RRF_RT_REG_SZ | RRF_RT_REG_EXPAND_SZ;
    let mut bytes = 0u32;
    let status = unsafe {
        RegGetValueW(
            root,
            key.as_ptr(),
            value.as_ptr(),
            flags,
            std::ptr::null_mut(),
            std::ptr::null_mut(),
            &mut bytes,
        )
    };
    if status != 0 || bytes < 2 {
        return None;
    }
    let mut buffer = vec![0u16; (bytes as usize).div_ceil(2)];
    let status = unsafe {
        RegGetValueW(
            root,
            key.as_ptr(),
            value.as_ptr(),
            flags,
            std::ptr::null_mut(),
            buffer.as_mut_ptr().cast(),
            &mut bytes,
        )
    };
    if status != 0 {
        return None;
    }
    let len = buffer
        .iter()
        .position(|unit| *unit == 0)
        .unwrap_or(buffer.len());
    Some(String::from_utf16_lossy(&buffer[..len])).filter(|raw| !raw.is_empty())
}

#[cfg(not(windows))]
fn persisted_env_var(_machine: bool, _name: &str) -> Option<String> {
    None
}

pub(crate) const WS_URL_FILE: &str = "neuro_ws_url.txt";

pub(crate) fn file_ws_url(roots: &[PathBuf]) -> Result<Option<(PathBuf, String)>, String> {
    let conflict = format!("conflicting {WS_URL_FILE} files found");
    unique_marker(roots, WS_URL_FILE, "", &conflict, |file, raw| {
        let value = raw.trim();
        if value.is_empty() {
            return Ok(None);
        }
        validate_ws_url(value)
            .map_err(|message| format!("invalid {}: {message}", file.display()))?;
        Ok(Some(value.to_string()))
    })
}

fn configured_ws_url() -> String {
    match file_ws_url(&marker_roots()) {
        Ok(Some((file, url))) => {
            eprintln!("[Info] websocket URL read from {}", file.display());
            return url;
        }
        Ok(None) => {}
        Err(message) => {
            eprintln!("[Fatal] {message}");
            std::process::exit(1);
        }
    }
    let Some(raw) = environment_ws_url() else {
        eprintln!(
            "[Fatal] no websocket URL; put the SDK's ws:// or wss:// URL in {WS_URL_FILE} next to the mod or set NEURO_SDK_WS_URL"
        );
        std::process::exit(1);
    };
    if let Err(message) = validate_ws_url(&raw) {
        eprintln!("[Fatal] invalid NEURO_SDK_WS_URL: {message}");
        std::process::exit(1);
    }
    raw
}

fn absolute_ipc_value(raw: &str, source: &str) -> Result<Option<PathBuf>, String> {
    let value = raw.trim();
    if value.is_empty() {
        return Ok(None);
    }
    if value
        .chars()
        .any(|ch| ch.is_control() || matches!(ch, '"' | '`' | '$' | ';' | '|' | '&' | '<' | '>'))
    {
        return Err(format!(
            "{source} contains unsafe characters; refusing IPC directory"
        ));
    }
    let path = Path::new(value);
    if !path.is_absolute() {
        return Err(format!(
            "{source} must be one canonical absolute IPC directory; refusing {:?}",
            value
        ));
    }
    Ok(Some(path.to_path_buf()))
}

impl Config {
    pub(crate) fn from_env() -> Self {
        let ws_url = configured_ws_url();
        let ipc_dir = resolve_ipc_dir();
        let outbox = ipc_dir.join("neuro_outbox.jsonl");
        let inbox = ipc_dir.join("neuro_inbox.jsonl");
        Self {
            ws_url,
            outbox,
            inbox,
            game_stale_after: GAME_STALE_AFTER,
        }
    }

    pub(crate) fn heartbeat(&self) -> PathBuf {
        self.outbox.with_file_name(GAME_HEARTBEAT_FILE)
    }
}

fn marker_roots() -> Vec<PathBuf> {
    let mut roots = Vec::new();
    let mut add = |root: PathBuf| {
        if !roots.iter().any(|existing| existing == &root) {
            roots.push(root);
        }
    };
    if let Ok(raw) = env::var("APPDATA") {
        let value = raw.trim();
        if !value.is_empty() {
            let appdata = Path::new(value);
            if appdata.is_absolute() {
                let mods = appdata.join("Balatro").join("Mods");
                add(mods.join("neuro-game"));
                add(mods.join("neuro_game"));
            }
        }
    }
    if let Ok(cwd) = env::current_dir() {
        add(cwd.join("neuro-game"));
        add(cwd);
    }
    if let Ok(exe) = env::current_exe() {
        if let Some(parent) = exe.parent() {
            add(parent.join("neuro-game"));
            add(parent.to_path_buf());
        }
    }
    roots
}

fn marker_file(root: &Path, name: &str) -> Option<PathBuf> {
    [root.join(name), root.join(format!("{name}.txt"))]
        .into_iter()
        .find(|file| file.is_file())
}

fn unique_marker<T: PartialEq>(
    roots: &[PathBuf],
    name: &str,
    label: &str,
    conflict: &str,
    parse: impl Fn(&Path, &str) -> Result<Option<T>, String>,
) -> Result<Option<(PathBuf, T)>, String> {
    let mut selected: Option<(PathBuf, T)> = None;
    for root in roots {
        let Some(file) = marker_file(root, name) else {
            continue;
        };
        let raw = std::fs::read_to_string(&file)
            .map_err(|error| format!("could not read {label}{}: {error}", file.display()))?;
        let Some(value) = parse(&file, &raw)? else {
            continue;
        };
        match &selected {
            Some((_, existing)) if *existing != value => return Err(conflict.to_string()),
            Some(_) => {}
            None => selected = Some((file, value)),
        }
    }
    Ok(selected)
}

fn configured_ipc_dir() -> Result<Option<PathBuf>, String> {
    let from_env = |name| absolute_ipc_value(&env::var(name).unwrap_or_default(), name);
    if let Some(value) = from_env("NEURO_IPC_DIR")? {
        return Ok(Some(value));
    }
    let marker = unique_marker(
        &marker_roots(),
        "neuro_ipc_dir.txt",
        "IPC marker ",
        "conflicting absolute IPC markers found; set NEURO_IPC_DIR explicitly",
        |file, raw| absolute_ipc_value(raw, &format!("IPC marker {}", file.display())),
    )?;
    if let Some((_, value)) = marker {
        return Ok(Some(value));
    }
    Ok(from_env("APPDATA")?.map(|appdata| appdata.join("Balatro").join("neuro-ipc")))
}

pub(crate) fn resolve_ipc_dir() -> PathBuf {
    match configured_ipc_dir() {
        Ok(Some(dir)) => return dir,
        Ok(None) => eprintln!(
            "[Fatal] no canonical IPC directory found; set NEURO_IPC_DIR to an absolute path \
             (required for native Linux/Proton direct invocation)"
        ),
        Err(message) => eprintln!("[Fatal] {message}"),
    }
    std::process::exit(1);
}

pub(crate) const MAX_CHUNK: u64 = 8 * 1024 * 1024;
pub(crate) const MAX_COMMAND_BYTES: usize = 8 * 1024 * 1024;
pub(crate) const MAX_INBOUND_FRAME_BYTES: usize = 8 * MAX_COMMAND_BYTES;
pub(crate) const MAX_QUEUED_BYTES: usize = 8 * 1024 * 1024;
pub(crate) const MAX_INBOX_BYTES: u64 = 64 * 1024 * 1024;
pub(crate) const INBOUND_SPOOL_RATE_WINDOW: Duration = Duration::from_secs(1);
pub(crate) const MAX_INBOUND_SPOOL_RATE_BYTES: usize = MAX_COMMAND_BYTES + 1;
pub(crate) const MAX_INBOUND_SPOOL_RATE_RECORDS: usize = 256;

pub(crate) struct InboundSpoolBudget {
    window_started: Instant,
    bytes: usize,
    records: usize,
}

impl InboundSpoolBudget {
    pub(crate) fn new(now: Instant) -> Self {
        Self {
            window_started: now,
            bytes: 0,
            records: 0,
        }
    }

    pub(crate) fn admit(&mut self, bytes: usize, now: Instant) -> bool {
        if now.duration_since(self.window_started) >= INBOUND_SPOOL_RATE_WINDOW {
            *self = Self::new(now);
        }
        let bytes = self.bytes.saturating_add(bytes);
        if bytes > MAX_INBOUND_SPOOL_RATE_BYTES || self.records >= MAX_INBOUND_SPOOL_RATE_RECORDS {
            return false;
        }
        self.bytes = bytes;
        self.records += 1;
        true
    }

    pub(crate) fn window_end(&self) -> Instant {
        self.window_started + INBOUND_SPOOL_RATE_WINDOW
    }
}
