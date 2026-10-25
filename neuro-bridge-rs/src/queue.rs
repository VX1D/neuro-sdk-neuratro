use super::*;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) struct QueueMark {
    pub(crate) resume: Resume,
    pub(crate) generation: u64,
    pub(crate) start: u64,
}

pub(crate) enum Outgoing {
    Outbox(String, QueueMark),
    Dropped(QueueMark),
    Hoisted(String, QueueMark),
}

impl Outgoing {
    pub(crate) fn mark(&self) -> QueueMark {
        match self {
            Self::Outbox(_, mark) | Self::Dropped(mark) | Self::Hoisted(_, mark) => *mark,
        }
    }

    pub(crate) fn bytes(&self) -> usize {
        match self {
            Self::Outbox(line, _) | Self::Hoisted(line, _) => line.len(),
            Self::Dropped(_) => 0,
        }
    }
}

pub(crate) struct QueuedOutgoing {
    pub(crate) outgoing: Outgoing,
    pub(crate) budget: Arc<AtomicUsize>,
}

impl QueuedOutgoing {
    pub(crate) fn dropped(mark: QueueMark, budget: &Arc<AtomicUsize>) -> Self {
        Self {
            outgoing: Outgoing::Dropped(mark),
            budget: Arc::clone(budget),
        }
    }

    pub(crate) async fn admit(
        outgoing: Outgoing,
        budget: &Arc<AtomicUsize>,
        released: &tokio::sync::Notify,
    ) -> Self {
        let bytes = outgoing.bytes();
        while !reserve(budget, bytes) {
            released.notified().await;
        }
        Self {
            outgoing,
            budget: Arc::clone(budget),
        }
    }
}

fn reserve(budget: &AtomicUsize, bytes: usize) -> bool {
    let mut used = budget.load(Ordering::Acquire);
    loop {
        let Some(next) = used
            .checked_add(bytes)
            .filter(|next| *next <= MAX_QUEUED_BYTES)
        else {
            return false;
        };
        match budget.compare_exchange_weak(used, next, Ordering::AcqRel, Ordering::Acquire) {
            Ok(_) => return true,
            Err(observed) => used = observed,
        }
    }
}

impl Drop for QueuedOutgoing {
    fn drop(&mut self) {
        self.budget
            .fetch_sub(self.outgoing.bytes(), Ordering::AcqRel);
    }
}
