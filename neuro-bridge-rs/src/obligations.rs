use super::*;

/// Keep fixed-size digests for the connection lifetime to prevent duplicate results for an id.
#[derive(Default)]
pub(crate) struct IdSet {
    ids: HashSet<u128>,
}

fn id_key(id: &str) -> u128 {
    let (mut low, mut high) = (FNV_OFFSET, FNV_OFFSET ^ 0x9e37_79b9_7f4a_7c15);
    fingerprint_update(&mut low, id.as_bytes());
    fingerprint_update(&mut high, id.as_bytes());
    fingerprint_update(&mut high, &(id.len() as u64).to_le_bytes());
    (u128::from(high) << 64) | u128::from(low)
}

impl IdSet {
    pub(crate) fn contains(&self, id: &str) -> bool {
        self.ids.contains(&id_key(id))
    }

    pub(crate) fn insert(&mut self, id: &str) -> bool {
        if !action_id_fits_bounds(id) {
            return false;
        }
        self.ids.insert(id_key(id))
    }

    pub(crate) fn clear(&mut self) {
        self.ids.clear();
    }
}

#[derive(Default)]
pub(crate) struct PendingTracker {
    delivered: IdSet,
    answered: IdSet,
    earlier_sessions: IdSet,
    forces_sent: HashSet<Resume>,
    contexts_sent: HashSet<Resume>,
    bound_game: Option<String>,
}

impl PendingTracker {
    pub(crate) fn bind_game(&mut self, game: &str) {
        if self
            .bound_game
            .as_deref()
            .is_some_and(|bound| bound != game)
        {
            *self = Self::default();
        }
        self.bound_game = Some(game.to_string());
    }

    pub(crate) fn admit_action(&mut self, id: &str) -> bool {
        !self.answered.contains(id) && self.delivered.insert(id)
    }

    pub(crate) fn should_suppress_result(&self, id: &str) -> bool {
        self.answered.contains(id)
    }

    /// Results from an earlier connection do not answer actions on this connection.
    pub(crate) fn is_stale_result(&self, id: &str) -> bool {
        self.earlier_sessions.contains(id) && !self.delivered.contains(id)
    }

    pub(crate) fn observe_result(&mut self, id: &str) {
        self.answered.insert(id);
    }

    pub(crate) fn owes_result(&self) -> bool {
        self.delivered
            .ids
            .iter()
            .any(|key| !self.answered.ids.contains(key))
    }

    pub(crate) fn first_send_at(&mut self, command: Option<&str>, end: Resume) -> bool {
        let sent = match command {
            Some("actions/force") => &mut self.forces_sent,
            Some("context") => &mut self.contexts_sent,
            _ => return true,
        };
        if sent.len() >= MAX_TRACKED_ACTIONS {
            sent.clear();
        }
        sent.insert(end)
    }

    pub(crate) fn begin_session(&mut self) {
        self.earlier_sessions
            .ids
            .extend(self.delivered.ids.iter().copied());
        self.delivered.clear();
        self.answered.clear();
    }
}
