//! Bounded, Lua-free native lane bookkeeping.

use nupp_native_abi::Handle;
use std::collections::{HashSet, VecDeque};
use std::fmt;
use std::sync::{Condvar, Mutex, MutexGuard};
use std::time::Duration;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum Phase {
    Open,
    Closing,
    Closed,
}

struct State {
    phase: Phase,
    pending: HashSet<Handle>,
    ready: HashSet<Handle>,
    queue: VecDeque<Handle>,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum LaneError {
    ZeroCapacity,
    Capacity,
    Duplicate,
    Unknown,
    Closing,
    Pending(usize),
    Poisoned,
}

impl fmt::Display for LaneError {
    fn fmt(&self, out: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::ZeroCapacity => write!(out, "lane capacity must be positive"),
            Self::Capacity => write!(out, "lane capacity is exhausted"),
            Self::Duplicate => write!(out, "operation is already registered"),
            Self::Unknown => write!(out, "operation is not registered"),
            Self::Closing => write!(out, "lane is shutting down"),
            Self::Pending(count) => write!(out, "lane still owns {count} operations"),
            Self::Poisoned => write!(out, "lane state was poisoned"),
        }
    }
}

impl std::error::Error for LaneError {}

/// One runtime's bounded cross-thread completion lane.
pub struct NativeLane {
    capacity: usize,
    state: Mutex<State>,
    changed: Condvar,
}

impl NativeLane {
    pub fn new(capacity: usize) -> Result<Self, LaneError> {
        if capacity == 0 {
            return Err(LaneError::ZeroCapacity);
        }
        Ok(Self {
            capacity,
            state: Mutex::new(State {
                phase: Phase::Open,
                pending: HashSet::with_capacity(capacity),
                ready: HashSet::with_capacity(capacity),
                queue: VecDeque::with_capacity(capacity),
            }),
            changed: Condvar::new(),
        })
    }

    pub fn register(&self, handle: Handle) -> Result<(), LaneError> {
        let mut state = self.lock()?;
        if state.phase != Phase::Open {
            return Err(LaneError::Closing);
        }
        if !handle.is_valid() {
            return Err(LaneError::Unknown);
        }
        if state.pending.contains(&handle) {
            return Err(LaneError::Duplicate);
        }
        if state.pending.len() == self.capacity {
            return Err(LaneError::Capacity);
        }
        state.pending.insert(handle);
        Ok(())
    }

    pub fn complete(&self, handle: Handle) -> Result<(), LaneError> {
        let mut state = self.lock()?;
        if !state.pending.contains(&handle) {
            return Err(LaneError::Unknown);
        }
        if state.ready.insert(handle) {
            debug_assert!(state.queue.len() < self.capacity);
            state.queue.push_back(handle);
            self.changed.notify_all();
        }
        Ok(())
    }

    pub fn retire(&self, handle: Handle) -> Result<(), LaneError> {
        let mut state = self.lock()?;
        if !state.pending.remove(&handle) {
            return Err(LaneError::Unknown);
        }
        state.ready.remove(&handle);
        state.queue.retain(|queued| *queued != handle);
        self.changed.notify_all();
        Ok(())
    }

    pub fn poll(&self, limit: usize) -> Result<Vec<Handle>, LaneError> {
        let mut state = self.lock()?;
        Ok(take_ready(&mut state, limit))
    }

    pub fn wait(&self, limit: usize, timeout: Duration) -> Result<Vec<Handle>, LaneError> {
        let state = self.lock()?;
        let mut state = if state.ready.is_empty() && state.phase == Phase::Open {
            self.changed
                .wait_timeout(state, timeout)
                .map_err(|_| LaneError::Poisoned)?
                .0
        } else {
            state
        };
        Ok(take_ready(&mut state, limit))
    }

    pub fn begin_shutdown(&self) -> Result<Vec<Handle>, LaneError> {
        let mut state = self.lock()?;
        if state.phase == Phase::Open {
            state.phase = Phase::Closing;
            self.changed.notify_all();
        }
        Ok(state.pending.iter().copied().collect())
    }

    pub fn finish_shutdown(&self) -> Result<(), LaneError> {
        let mut state = self.lock()?;
        if !state.pending.is_empty() {
            return Err(LaneError::Pending(state.pending.len()));
        }
        state.phase = Phase::Closed;
        state.ready.clear();
        state.queue.clear();
        self.changed.notify_all();
        Ok(())
    }

    pub fn pending(&self) -> Result<usize, LaneError> {
        Ok(self.lock()?.pending.len())
    }

    pub fn is_shutting_down(&self) -> bool {
        self.state
            .lock()
            .map_or(true, |state| state.phase != Phase::Open)
    }

    fn lock(&self) -> Result<MutexGuard<'_, State>, LaneError> {
        self.state.lock().map_err(|_| LaneError::Poisoned)
    }
}

fn take_ready(state: &mut State, limit: usize) -> Vec<Handle> {
    let mut out = Vec::with_capacity(limit.min(state.ready.len()));
    while out.len() < limit {
        let Some(handle) = state.queue.pop_front() else {
            break;
        };
        if state.ready.remove(&handle) {
            out.push(handle);
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn handle(value: u64) -> Handle {
        Handle::from_raw((1_u64 << 32) | value)
    }

    #[test]
    fn pending_and_ready_work_share_one_bound() {
        let lane = NativeLane::new(2).unwrap();
        lane.register(handle(1)).unwrap();
        lane.register(handle(2)).unwrap();
        assert_eq!(lane.register(handle(3)), Err(LaneError::Capacity));
        lane.complete(handle(1)).unwrap();
        lane.complete(handle(1)).unwrap();
        lane.complete(handle(2)).unwrap();
        assert_eq!(lane.poll(8).unwrap(), vec![handle(1), handle(2)]);
    }

    #[test]
    fn retirement_discards_queued_readiness() {
        let lane = NativeLane::new(1).unwrap();
        lane.register(handle(1)).unwrap();
        lane.complete(handle(1)).unwrap();
        lane.retire(handle(1)).unwrap();
        assert!(lane.poll(1).unwrap().is_empty());
        assert_eq!(lane.pending(), Ok(0));
    }

    #[test]
    fn repeated_retirement_cannot_grow_the_ready_queue() {
        let lane = NativeLane::new(1).unwrap();
        for value in 1..=128 {
            let operation = Handle::from_raw((value << 32) | 1);
            lane.register(operation).unwrap();
            lane.complete(operation).unwrap();
            lane.retire(operation).unwrap();
        }
        let final_operation = Handle::from_raw((129_u64 << 32) | 1);
        lane.register(final_operation).unwrap();
        lane.complete(final_operation).unwrap();
        assert_eq!(lane.poll(1).unwrap(), vec![final_operation]);
    }

    #[test]
    fn invalid_handles_are_rejected() {
        let lane = NativeLane::new(1).unwrap();
        assert_eq!(lane.register(Handle::INVALID), Err(LaneError::Unknown));
    }

    #[test]
    fn shutdown_names_and_drains_every_operation() {
        let lane = NativeLane::new(2).unwrap();
        lane.register(handle(1)).unwrap();
        lane.register(handle(2)).unwrap();
        let mut cancelled = lane.begin_shutdown().unwrap();
        cancelled.sort_by_key(|handle| handle.raw());
        assert_eq!(cancelled, vec![handle(1), handle(2)]);
        assert_eq!(lane.register(handle(3)), Err(LaneError::Closing));
        assert_eq!(lane.finish_shutdown(), Err(LaneError::Pending(2)));
        for handle in cancelled {
            lane.retire(handle).unwrap();
        }
        lane.finish_shutdown().unwrap();
        assert!(lane.is_shutting_down());
    }

    #[test]
    fn poisoned_state_is_never_reported_as_drained() {
        let lane = std::sync::Arc::new(NativeLane::new(1).unwrap());
        let poison = std::sync::Arc::clone(&lane);
        let _ = std::thread::spawn(move || {
            let _guard = poison.state.lock().unwrap();
            panic!("poison lane state");
        })
        .join();
        assert_eq!(lane.begin_shutdown(), Err(LaneError::Poisoned));
        assert_eq!(lane.pending(), Err(LaneError::Poisoned));
        assert_eq!(lane.finish_shutdown(), Err(LaneError::Poisoned));
    }
}
