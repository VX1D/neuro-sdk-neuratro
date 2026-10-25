use super::*;

const BOOTSTRAP_SCAN_CHUNK: u64 = 64 * 1024;

/// Start at the last complete record before any trailing answer tag, so startup is still observed.
pub(crate) async fn bootstrap_boundary(path: &Path) -> Result<Resume> {
    let path = path.to_path_buf();
    blocking(move || {
        let (file, len, id) = match open_stat(&path) {
            Ok(opened) => opened,
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
                return Ok(Resume::default())
            }
            Err(error) => return Err(error).context("open outbox for bootstrap"),
        };
        let complete = line_start(&file, len, len)?.unwrap_or(0);
        let last = match complete {
            0 => None,
            _ => line_start(&file, complete - 1, MAX_COMMAND_BYTES as u64)?,
        };
        let pos = match last {
            Some(last) => {
                let line = read_span(&file, last, complete - last)?;
                let tag = std::str::from_utf8(&line).is_ok_and(|line| {
                    ParsedLine::parse(line.trim_end())
                        .answer_session()
                        .is_some()
                });
                if tag {
                    last
                } else {
                    complete
                }
            }
            None => complete,
        };
        Ok(Resume { pos, id: Some(id) })
    })
    .await?
}

fn line_start(file: &std::fs::File, end: u64, limit: u64) -> Result<Option<u64>> {
    let floor = end.saturating_sub(limit);
    let mut high = end;
    while high > floor {
        let low = high.saturating_sub(BOOTSTRAP_SCAN_CHUNK).max(floor);
        let bytes = read_span(file, low, high - low).context("read outbox for bootstrap")?;
        if let Some(newline) = bytes.iter().rposition(|byte| *byte == b'\n') {
            return Ok(Some(low + newline as u64 + 1));
        }
        high = low;
    }
    Ok((floor == 0).then_some(0))
}
