use super::*;

const INSTANCE_LOCK_FILE: &str = ".neuro-bridge.lease";

pub(crate) fn create_ipc_dir(path: &Path) -> std::io::Result<()> {
    let mut builder = std::fs::DirBuilder::new();
    builder.recursive(true);
    #[cfg(unix)]
    std::os::unix::fs::DirBuilderExt::mode(&mut builder, 0o700);
    builder.create(path)
}

fn ensure_ipc_path_secure(path: &Path, dir: bool, mode: u32) -> Result<()> {
    let metadata = match std::fs::symlink_metadata(path) {
        Err(error) if error.kind() == std::io::ErrorKind::NotFound && !dir => return Ok(()),
        other => other.with_context(|| format!("inspect IPC path {}", path.display()))?,
    };
    let kind_ok = if dir {
        metadata.file_type().is_dir()
    } else {
        metadata.file_type().is_file()
    };
    if !kind_ok {
        anyhow::bail!(
            "IPC path {} is not a {}; refusing IPC",
            path.display(),
            if dir { "directory" } else { "regular file" }
        );
    }
    #[cfg(unix)]
    {
        use std::os::unix::fs::{MetadataExt, PermissionsExt};
        unsafe extern "C" {
            fn geteuid() -> u32;
        }
        if metadata.uid() != unsafe { geteuid() } {
            anyhow::bail!(
                "IPC path {} is owned by another user; refusing IPC",
                path.display()
            );
        }
        if metadata.mode() & 0o777 != mode {
            std::fs::set_permissions(path, std::fs::Permissions::from_mode(mode))
                .with_context(|| format!("restrict IPC path {}", path.display()))?;
        }
    }
    #[cfg(not(unix))]
    let _ = mode;
    Ok(())
}

pub(crate) fn ensure_ipc_dir_secure(path: &Path) -> Result<()> {
    ensure_ipc_path_secure(path, true, 0o700)
}

pub(crate) fn ensure_ipc_file_secure(path: &Path) -> Result<()> {
    ensure_ipc_path_secure(path, false, 0o600)
}

/// The OS releases this lease lock when the relay exits or crashes.
pub(crate) struct InstanceLease {
    _file: std::fs::File,
}

impl InstanceLease {
    pub(crate) fn acquire(ipc_dir: &Path) -> Result<Self> {
        ensure_ipc_dir_secure(ipc_dir)?;
        for name in [
            "neuro_inbox.jsonl",
            "neuro_outbox.jsonl",
            GAME_HEARTBEAT_FILE,
            INSTANCE_LOCK_FILE,
        ] {
            ensure_ipc_file_secure(&ipc_dir.join(name))?;
        }
        let path = ipc_dir.join(INSTANCE_LOCK_FILE);
        let mut options = std::fs::OpenOptions::new();
        options.create(true).truncate(false).write(true);
        #[cfg(unix)]
        std::os::unix::fs::OpenOptionsExt::mode(&mut options, 0o600);
        let file = options
            .open(&path)
            .with_context(|| format!("open relay lease {}", path.display()))?;
        match file.try_lock() {
            Ok(()) => Ok(Self { _file: file }),
            Err(std::fs::TryLockError::WouldBlock) => Err(anyhow!(
                "IPC directory {} is already leased by a running relay",
                ipc_dir.display()
            )),
            Err(std::fs::TryLockError::Error(error)) => {
                Err(error).with_context(|| format!("lock relay lease {}", path.display()))
            }
        }
    }
}
