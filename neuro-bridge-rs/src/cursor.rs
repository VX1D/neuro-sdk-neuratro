use super::*;
use std::fs::File;
use std::io::{Read, Seek, SeekFrom};

pub(crate) type FileId = (u64, u64);

#[derive(Clone, Copy, Default, PartialEq, Eq, Hash, Debug)]
pub(crate) struct Resume {
    pub(crate) pos: u64,
    pub(crate) id: Option<FileId>,
}

#[cfg(unix)]
fn file_id(file: &File) -> std::io::Result<FileId> {
    use std::os::unix::fs::MetadataExt;
    let meta = file.metadata()?;
    Ok((meta.dev(), meta.ino()))
}

#[cfg(windows)]
fn file_id(file: &File) -> std::io::Result<FileId> {
    use std::os::windows::io::AsRawHandle;
    use windows_sys::Win32::Storage::FileSystem::{
        GetFileInformationByHandle, BY_HANDLE_FILE_INFORMATION,
    };
    let mut info: BY_HANDLE_FILE_INFORMATION = unsafe { std::mem::zeroed() };
    if unsafe { GetFileInformationByHandle(file.as_raw_handle(), &mut info) } == 0 {
        return Err(std::io::Error::last_os_error());
    }
    let index = (u64::from(info.nFileIndexHigh) << 32) | u64::from(info.nFileIndexLow);
    Ok((u64::from(info.dwVolumeSerialNumber), index))
}

/// Read length and identity from one handle to avoid mixing generations across a rename.
pub(crate) fn open_stat(path: &Path) -> std::io::Result<(File, u64, FileId)> {
    let file = File::open(path)?;
    let len = file.metadata()?.len();
    let id = file_id(&file)?;
    Ok((file, len, id))
}

pub(crate) fn read_exact_at(file: &File, buf: &mut [u8], offset: u64) -> std::io::Result<()> {
    let mut file = file;
    file.seek(SeekFrom::Start(offset))?;
    file.read_exact(buf)
}

pub(crate) fn read_span(file: &File, offset: u64, len: u64) -> std::io::Result<Vec<u8>> {
    let mut file = file;
    file.seek(SeekFrom::Start(offset))?;
    let mut buf = Vec::with_capacity(len as usize);
    file.take(len).read_to_end(&mut buf)?;
    Ok(buf)
}

pub(crate) fn cursor_path(outbox: &Path) -> PathBuf {
    let mut raw = outbox.as_os_str().to_os_string();
    raw.push(".cursor");
    PathBuf::from(raw)
}

pub(crate) fn rotated_path(path: &Path) -> PathBuf {
    let mut raw = path.as_os_str().to_os_string();
    raw.push(".1");
    PathBuf::from(raw)
}

pub(crate) async fn blocking<T: Send + 'static>(
    work: impl FnOnce() -> T + Send + 'static,
) -> Result<T> {
    tokio::task::spawn_blocking(work)
        .await
        .map_err(|error| anyhow!("blocking filesystem task failed: {error}"))
}

pub(crate) fn sync_parent_directory(path: &Path) -> Result<()> {
    #[cfg(unix)]
    {
        let parent = path
            .parent()
            .filter(|parent| !parent.as_os_str().is_empty())
            .unwrap_or_else(|| Path::new("."));
        File::open(parent)
            .and_then(|dir| dir.sync_all())
            .with_context(|| format!("sync parent directory {}", parent.display()))?;
    }
    // Windows has no portable directory fsync; file sync plus atomic rename is the durability boundary.
    #[cfg(not(unix))]
    let _ = path;
    Ok(())
}

/// Exclusive creation prevents writes through a stale file or planted link.
pub(crate) fn write_durable_file(tmp: &Path, dest: &Path, bytes: &[u8]) -> Result<()> {
    let _ = std::fs::remove_file(tmp);
    let mut options = std::fs::OpenOptions::new();
    options.create_new(true).write(true);
    #[cfg(unix)]
    std::os::unix::fs::OpenOptionsExt::mode(&mut options, 0o600);
    let mut file = options.open(tmp).context("create temporary file")?;
    file.write_all(bytes)?;
    file.sync_data()?;
    drop(file);
    if let Err(error) = std::fs::rename(tmp, dest) {
        let _ = std::fs::remove_file(tmp);
        return Err(error).with_context(|| format!("rename durable file {}", dest.display()));
    }
    sync_parent_directory(dest)
}

pub(crate) const FNV_OFFSET: u64 = 0xcbf29ce484222325;
const FNV_PRIME: u64 = 0x100000001b3;

pub(crate) fn fingerprint_update(hash: &mut u64, bytes: &[u8]) {
    *hash ^= bytes.len() as u64;
    *hash = hash.wrapping_mul(FNV_PRIME);
    for byte in bytes {
        *hash ^= u64::from(*byte);
        *hash = hash.wrapping_mul(FNV_PRIME);
    }
}

fn mix(hash: u64, word: u64) -> u64 {
    (hash ^ word).wrapping_mul(FNV_PRIME)
}

fn mix_words(hash: u64, bytes: &[u8]) -> u64 {
    bytes
        .chunks(8)
        .fold(mix(hash, bytes.len() as u64), |hash, chunk| {
            let mut word = [0u8; 8];
            word[..chunk.len()].copy_from_slice(chunk);
            mix(hash, u64::from_le_bytes(word))
        })
}

const FENCE_CHUNK: u64 = 64 * 1024;

/// The mod fingerprints `.1` to determine whether the relay is still draining that generation.
pub(crate) fn fingerprint(file: &File, pos: u64, len: u64) -> std::io::Result<u64> {
    let samples = if len <= 2 * FENCE_CHUNK {
        vec![(0, len)]
    } else {
        vec![(0, FENCE_CHUNK), (len - FENCE_CHUNK, FENCE_CHUNK)]
    };
    let mut hash = mix(mix(FNV_OFFSET, pos), len);
    for (offset, length) in samples {
        let mut window = vec![0u8; length as usize];
        read_exact_at(file, &mut window, offset)?;
        hash = mix_words(mix(hash, offset), &window);
    }
    Ok(hash)
}

/// Lua decodes this seven-word record, so its field order and checksum must match.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) struct Cursor {
    pub(crate) pos: u64,
    pub(crate) len: u64,
    pub(crate) id: FileId,
    pub(crate) fingerprint: u64,
}

const CURSOR_MAGIC: u64 = u64::from_le_bytes(*b"NBCURSOR");
const CURSOR_WORDS: usize = 7;

fn checksum(words: &[u64]) -> u64 {
    words.iter().fold(FNV_OFFSET, |hash, word| mix(hash, *word))
}

impl Cursor {
    pub(crate) fn encode(&self) -> [u8; CURSOR_WORDS * 8] {
        let mut words = [
            CURSOR_MAGIC,
            self.pos,
            self.len,
            self.id.0,
            self.id.1,
            self.fingerprint,
            0,
        ];
        words[6] = checksum(&words[..6]);
        let mut bytes = [0u8; CURSOR_WORDS * 8];
        for (chunk, word) in bytes.chunks_exact_mut(8).zip(words) {
            chunk.copy_from_slice(&word.to_le_bytes());
        }
        bytes
    }

    fn decode(bytes: &[u8]) -> Option<Self> {
        if bytes.len() != CURSOR_WORDS * 8 {
            return None;
        }
        let words: Vec<u64> = bytes
            .chunks_exact(8)
            .map(|chunk| u64::from_le_bytes(chunk.try_into().expect("an 8-byte chunk")))
            .collect();
        (words[0] == CURSOR_MAGIC && words[6] == checksum(&words[..6])).then(|| Self {
            pos: words[1],
            len: words[2],
            id: (words[3], words[4]),
            fingerprint: words[5],
        })
    }

    /// The prefix fingerprint prevents a reused inode from validating a stale resume position.
    fn fence(path: &Path, resume: Resume, len: Option<u64>) -> Option<Self> {
        let (file, file_len, id) = open_stat(path).ok()?;
        let len = len.unwrap_or(file_len);
        if resume.id != Some(id) || resume.pos > len || len > file_len {
            return None;
        }
        Some(Self {
            pos: resume.pos,
            len,
            id,
            fingerprint: fingerprint(&file, resume.pos, len).ok()?,
        })
    }

    pub(crate) fn resume(&self) -> Resume {
        Resume {
            pos: self.pos,
            id: Some(self.id),
        }
    }
}

/// A drained rotated generation still contains records, so resume may target `.1`.
pub(crate) async fn outbox_holds(outbox: &Path, resume: Resume) -> bool {
    let outbox = outbox.to_path_buf();
    blocking(move || {
        [outbox.clone(), rotated_path(&outbox)].iter().any(|path| {
            open_stat(path).is_ok_and(|(_, len, id)| {
                len >= resume.pos && resume.id.is_none_or(|own| own == id)
            })
        })
    })
    .await
    .unwrap_or(false)
}

/// An invalid cursor requires bootstrap; guessing a position could replay or skip records.
pub(crate) async fn load_cursor(outbox: &Path) -> Option<Resume> {
    let outbox = outbox.to_path_buf();
    blocking(move || {
        let bytes = match std::fs::read(cursor_path(&outbox)) {
            Ok(bytes) => bytes,
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => return None,
            Err(e) => {
                eprintln!("[Warning] Could not read durable outbox cursor: {e}");
                return None;
            }
        };
        let Some(cursor) = Cursor::decode(&bytes) else {
            eprintln!("[Warning] Ignoring corrupt durable outbox cursor");
            return None;
        };
        let fenced = [outbox.clone(), rotated_path(&outbox)]
            .iter()
            .any(|path| Cursor::fence(path, cursor.resume(), Some(cursor.len)) == Some(cursor));
        if !fenced {
            eprintln!("[Warning] Ignoring durable outbox cursor: the outbox it covered was replaced or rewritten");
        }
        fenced.then(|| cursor.resume())
    })
    .await
    .ok()
    .flatten()
}

pub(crate) async fn persist_cursor(outbox: &Path, resume: Resume) -> Result<()> {
    let outbox = outbox.to_path_buf();
    blocking(move || {
        let cursor = Cursor::fence(&outbox, resume, None)
            .or_else(|| Cursor::fence(&rotated_path(&outbox), resume, None))
            .context("the outbox no longer holds the cursor position")?;
        let path = cursor_path(&outbox);
        ensure_ipc_file_secure(&path)?;
        let mut tmp = path.clone().into_os_string();
        tmp.push(".tmp");
        write_durable_file(Path::new(&tmp), &path, &cursor.encode())
    })
    .await?
}

const CHECKPOINT_RECORDS: usize = 64;
const CHECKPOINT_BYTES: u64 = 1024 * 1024;
const RETRY_FIRST: Duration = Duration::from_secs(1);
const RETRY_MAX: Duration = Duration::from_secs(30);

/// Keep the socket open while retrying cursor writes; reconnecting resends startup and registrations.
pub(crate) struct Checkpointer {
    outbox: PathBuf,
    durable: Resume,
    records: usize,
    retry: Option<(Instant, Duration)>,
}

impl Checkpointer {
    pub(crate) fn new(outbox: &Path, durable: Resume) -> Self {
        Self {
            outbox: outbox.to_path_buf(),
            durable,
            records: 0,
            retry: None,
        }
    }

    pub(crate) fn retry_at(&self) -> Option<Instant> {
        self.retry.map(|(at, _)| at)
    }

    /// Checkpoint force and context records immediately to avoid replaying a force over a live one.
    pub(crate) async fn advance(&mut self, tail: Resume, urgent: bool) {
        self.records += 1;
        let due = urgent
            || tail.id != self.durable.id
            || tail.pos < self.durable.pos
            || self.records >= CHECKPOINT_RECORDS
            || tail.pos - self.durable.pos >= CHECKPOINT_BYTES;
        if due && self.retry_at().is_none_or(|at| Instant::now() >= at) {
            self.write(tail).await;
        }
    }

    pub(crate) async fn write(&mut self, tail: Resume) {
        match persist_cursor(&self.outbox, tail).await {
            Ok(()) => {
                if self.retry.take().is_some() {
                    eprintln!("[Info] Durable outbox cursor written again");
                }
                self.durable = tail;
                self.records = 0;
            }
            Err(error) => {
                let delay = self
                    .retry
                    .map_or(RETRY_FIRST, |(_, delay)| (delay * 2).min(RETRY_MAX));
                eprintln!(
                    "[Error] Could not persist durable outbox cursor: {error:#} (retry in {}s)",
                    delay.as_secs()
                );
                self.retry = Some((Instant::now() + delay, delay));
            }
        }
    }

    pub(crate) async fn finish(&mut self, tail: Resume) {
        if tail != self.durable || self.retry.is_some() {
            self.write(tail).await;
        }
    }
}
