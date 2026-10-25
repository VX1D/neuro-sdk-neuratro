use super::*;

pub(crate) const GAME_HEARTBEAT_FILE: &str = "neuro_heartbeat.txt";
pub(crate) const GAME_STALE_AFTER: Duration = Duration::from_secs(30);
pub(crate) const GAME_STALE_OWING_AFTER: Duration = Duration::from_secs(10);
pub(crate) const GAME_LIVENESS_POLL: Duration = Duration::from_secs(1);

pub(crate) struct GameLiveness {
    last: Option<Vec<u8>>,
    changed_at: Option<Instant>,
    stale_after: Duration,
}

impl GameLiveness {
    pub(crate) fn new(stale_after: Duration) -> Self {
        Self {
            last: None,
            changed_at: None,
            stale_after,
        }
    }

    pub(crate) fn observe(&mut self, beat: Option<Vec<u8>>, now: Instant) {
        let Some(beat) = beat.filter(|beat| !beat.is_empty()) else {
            return;
        };
        if self.last.as_ref().is_some_and(|last| *last != beat) {
            self.changed_at = Some(now);
        }
        self.last = Some(beat);
    }

    pub(crate) fn dead(&self, now: Instant, owes_result: bool) -> bool {
        let stale_after = if owes_result {
            self.stale_after.min(GAME_STALE_OWING_AFTER)
        } else {
            self.stale_after
        };
        self.changed_at
            .is_some_and(|at| now.duration_since(at) >= stale_after)
    }
}
