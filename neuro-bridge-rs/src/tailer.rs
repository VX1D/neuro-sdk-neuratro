use super::*;
use std::fs::File;

pub(crate) const WATCHED_FALLBACK_MS: u64 = 5000;
pub(crate) const POLL_FALLBACK_MS: u64 = 150;

/// An unsendable complete record still advances the cursor.
pub(crate) struct Record {
    pub(crate) line: Option<String>,
    pub(crate) start: u64,
    pub(crate) end: Resume,
}

#[derive(Clone)]
pub(crate) struct Tailer {
    pub(crate) path: PathBuf,
    pub(crate) pos: u64,
    pub(crate) id: Option<FileId>,
    // Rewind invalidates queued records from the prior generation after replacement or truncation.
    pub(crate) generation: u64,
    discard_from: Option<u64>,
    pub(crate) caught_up: bool,
}

impl Tailer {
    pub(crate) fn new(path: PathBuf, resume: Resume) -> Self {
        Self {
            path,
            pos: resume.pos,
            id: resume.id,
            generation: 0,
            discard_from: None,
            caught_up: true,
        }
    }

    pub(crate) async fn read(&mut self) -> Result<Vec<Record>> {
        let mut tailer = self.clone();
        let (tailer, records) = blocking(move || {
            let records = tailer.read_blocking();
            (tailer, records)
        })
        .await?;
        *self = tailer;
        records
    }

    fn read_blocking(&mut self) -> Result<Vec<Record>> {
        loop {
            let current = match open_stat(&self.path) {
                Ok(current) => Some(current),
                Err(e) if e.kind() == std::io::ErrorKind::NotFound => None,
                Err(e) => return Err(e).context("open outbox"),
            };
            let ours = current.as_ref().is_some_and(|(_, len, id)| {
                *len >= self.pos && self.id.is_none_or(|own| own == *id)
            });
            if !ours {
                if let Some((file, len)) = self.own_rotated()? {
                    let before = self.pos;
                    let records = self.split(&file, len)?;
                    if self.pos != before {
                        self.caught_up = false;
                        return Ok(records);
                    }
                    if before < len {
                        eprintln!("[Warning] Rotated outbox ended inside a record; discarding its torn tail");
                    }
                    eprintln!(
                        "[Info] Rotated outbox drained; following the new outbox from its start"
                    );
                    (self.pos, self.id, self.discard_from) = (0, None, None);
                    continue;
                }
            }
            let Some((file, len, id)) = current else {
                self.caught_up = true;
                return Ok(Vec::new());
            };
            if !ours {
                eprintln!(
                    "[Warning] Outbox replaced or shrank at {}, re-reading from start",
                    self.pos
                );
                self.generation = self.generation.wrapping_add(1);
                (self.pos, self.discard_from) = (0, None);
            }
            self.id = Some(id);
            return self.split(&file, len);
        }
    }

    /// Accept rotation only when the tailer’s generation still covers its position.
    fn own_rotated(&self) -> Result<Option<(File, u64)>> {
        let Some(own) = self.id else {
            return Ok(None);
        };
        match open_stat(&rotated_path(&self.path)) {
            Ok((file, len, id)) => Ok((id == own && len >= self.pos).then_some((file, len))),
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(None),
            Err(e) => Err(e).context("open rotated outbox"),
        }
    }

    /// Read complete records only; reread a partial record from its start after its newline arrives.
    fn split(&mut self, file: &File, len: u64) -> Result<Vec<Record>> {
        let base = self.pos;
        let buf = read_span(file, base, MAX_CHUNK.min(len.saturating_sub(base)))?;
        self.caught_up = base + buf.len() as u64 >= len;
        let mut records = Vec::new();
        let mut offset = 0;
        while let Some(newline) = buf[offset..].iter().position(|byte| *byte == b'\n') {
            let start = base + offset as u64;
            let bytes = &buf[offset..offset + newline];
            offset += newline + 1;
            let end = Resume {
                pos: base + offset as u64,
                id: self.id,
            };
            let line = match (self.discard_from.take(), std::str::from_utf8(bytes)) {
                (Some(start), _) => {
                    records.push(Record {
                        line: None,
                        start,
                        end,
                    });
                    continue;
                }
                (None, Ok(text)) => text.strip_suffix('\r').unwrap_or(text),
                (None, Err(_)) => {
                    eprintln!("[Warning] Quarantining outbox record containing invalid UTF-8");
                    records.push(Record {
                        line: None,
                        start,
                        end,
                    });
                    continue;
                }
            };
            if !line.trim().is_empty() {
                let line = Some(line.to_string());
                records.push(Record { line, start, end });
            }
        }
        if self.discard_from.is_none() && offset == 0 && buf.len() as u64 == MAX_CHUNK {
            eprintln!("[Error] Outbox line exceeded {MAX_CHUNK} bytes; discarding line");
            self.discard_from = Some(base);
        }
        if self.discard_from.is_some() {
            offset = buf.len();
        }
        self.pos = base + offset as u64;
        Ok(records)
    }
}

pub(crate) struct Lane {
    pub(crate) tx: mpsc::Sender<QueuedOutgoing>,
    pub(crate) startup_tx: mpsc::Sender<QueuedOutgoing>,
    pub(crate) startup_on_wire: Arc<AtomicBool>,
    pub(crate) generation: Arc<AtomicU64>,
    pub(crate) queue_bytes: Arc<AtomicUsize>,
    pub(crate) released: Arc<tokio::sync::Notify>,
    pub(crate) transport_session: u64,
}

pub(crate) async fn tailer_task(
    mut tailer: Tailer,
    watcher: Option<OutboxWatcher>,
    mut watch_rx: mpsc::Receiver<()>,
    lane: Lane,
) {
    let mut answer_tag = None;
    let mut probe = Some(Tailer::new(
        tailer.path.clone(),
        Resume {
            pos: tailer.pos,
            id: tailer.id,
        },
    ));
    let mut watched = watcher.is_some();
    loop {
        while watch_rx.try_recv().is_ok() {}
        let caught_up = if lane.startup_on_wire.load(Ordering::Acquire) {
            probe = None;
            let Some(records) = read_logged(&mut tailer).await else {
                return;
            };
            if forward_in_order(records, &tailer, &lane).await.is_none() {
                return;
            }
            tailer.caught_up
        } else if let Some(reader) = probe.as_mut() {
            let Some(records) = read_logged(reader).await else {
                return;
            };
            match hoist_startup(records, tailer.generation, &mut answer_tag, &lane).await {
                Some(true) => {
                    probe = None;
                    true
                }
                Some(false) => reader.caught_up,
                None => return,
            }
        } else {
            true
        };
        if !caught_up {
            continue;
        }
        if watched && !watcher.as_ref().is_some_and(OutboxWatcher::healthy) {
            watched = false;
            eprintln!("[Info] File watcher stopped, falling back to {POLL_FALLBACK_MS}ms polling");
        }
        let fallback_ms = if watched {
            WATCHED_FALLBACK_MS
        } else {
            POLL_FALLBACK_MS
        };
        tokio::select! {
            Some(()) = watch_rx.recv() => {}
            _ = time::sleep(Duration::from_millis(fallback_ms)) => {}
        }
    }
}

async fn read_logged(tailer: &mut Tailer) -> Option<Vec<Record>> {
    tailer
        .read()
        .await
        .map_err(|e| eprintln!("[Error] Failed to read outbox: {e}"))
        .ok()
}

async fn hoist_startup(
    records: Vec<Record>,
    generation: u64,
    answer_tag: &mut Option<AnswerTag>,
    lane: &Lane,
) -> Option<bool> {
    let found = records.into_iter().find_map(|Record { line, start, end }| {
        let line = line?;
        let record = ParsedLine::parse(&line);
        if let Some(tag) = AnswerTag::read(&record, end) {
            *answer_tag = Some(tag);
            return None;
        }
        let live = record.command() == Some("startup")
            && record
                .wire_frame(&line)
                .is_some_and(|frame| frame.game().is_some())
            && startup_is_live(*answer_tag, start, end.id, lane.transport_session);
        live.then_some((line, start, end))
    });
    let Some((line, start, end)) = found else {
        return Some(false);
    };
    let mark = QueueMark {
        resume: end,
        generation,
        start,
    };
    let outgoing = Outgoing::Hoisted(line, mark);
    let queued = QueuedOutgoing::admit(outgoing, &lane.queue_bytes, &lane.released).await;
    lane.startup_tx.send(queued).await.ok()?;
    Some(true)
}

async fn forward_in_order(records: Vec<Record>, tailer: &Tailer, lane: &Lane) -> Option<()> {
    lane.generation.store(tailer.generation, Ordering::Release);
    for Record { line, start, end } in records {
        let mark = QueueMark {
            resume: end,
            generation: tailer.generation,
            start,
        };
        let queued = match line {
            Some(line) => {
                let outgoing = Outgoing::Outbox(line, mark);
                QueuedOutgoing::admit(outgoing, &lane.queue_bytes, &lane.released).await
            }
            None => QueuedOutgoing::dropped(mark, &lane.queue_bytes),
        };
        lane.tx.send(queued).await.ok()?;
    }
    Some(())
}
