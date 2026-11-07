//! Shared bounded FIFO storage for worker control and application channels.
//!
//! A send transfers ownership only on acceptance. Closing ingress drains accepted
//! messages; closing the receiver discards them. Both wake every blocked side.

use std::collections::VecDeque;
use std::sync::{Condvar, Mutex, MutexGuard};
use std::time::{Duration, Instant};

struct QueueState<T> {
    entries: VecDeque<T>,
    bytes: usize,
    closed: bool,
}

pub(crate) struct BoundedQueue<T> {
    state: Mutex<QueueState<T>>,
    arrived: Condvar,
    space: Condvar,
    message_limit: usize,
    byte_limit: usize,
    measure: fn(&T) -> usize,
}

impl<T> BoundedQueue<T> {
    pub(crate) fn new(message_limit: usize, byte_limit: usize, measure: fn(&T) -> usize) -> Self {
        assert!(message_limit > 0 && byte_limit > 0);
        Self {
            state: Mutex::new(QueueState {
                entries: VecDeque::new(),
                bytes: 0,
                closed: false,
            }),
            arrived: Condvar::new(),
            space: Condvar::new(),
            message_limit,
            byte_limit,
            measure,
        }
    }

    pub(crate) fn try_push(&self, value: T) -> Result<(), QueuePushError<T>> {
        let mut state = lock(&self.state);
        self.try_push_locked(&mut state, value)
    }

    fn try_push_locked(
        &self,
        state: &mut QueueState<T>,
        value: T,
    ) -> Result<(), QueuePushError<T>> {
        let bytes = (self.measure)(&value);
        if state.closed {
            return Err(QueuePushError::Closed(value));
        }
        if state.entries.len() >= self.message_limit
            || state
                .bytes
                .checked_add(bytes)
                .is_none_or(|sum| sum > self.byte_limit)
        {
            return Err(QueuePushError::Full(value));
        }
        state.bytes += bytes;
        state.entries.push_back(value);
        self.arrived.notify_one();
        Ok(())
    }

    pub(crate) fn pop(&self, timeout: Option<Duration>) -> Option<T> {
        let mut state = lock(&self.state);
        match timeout {
            None => {
                while state.entries.is_empty() && !state.closed {
                    state = self
                        .arrived
                        .wait(state)
                        .unwrap_or_else(std::sync::PoisonError::into_inner);
                }
            }
            Some(timeout) if !timeout.is_zero() => {
                let deadline = Instant::now() + timeout;
                while state.entries.is_empty() && !state.closed {
                    let Some(remaining) = deadline.checked_duration_since(Instant::now()) else {
                        break;
                    };
                    let waited = self
                        .arrived
                        .wait_timeout(state, remaining)
                        .unwrap_or_else(std::sync::PoisonError::into_inner);
                    state = waited.0;
                    if waited.1.timed_out() {
                        break;
                    }
                }
            }
            Some(_) => {}
        }
        let answer = state.entries.pop_front()?;
        state.bytes = state.bytes.saturating_sub((self.measure)(&answer));
        self.space.notify_one();
        Some(answer)
    }

    pub(crate) fn push_wait(&self, value: T) -> Result<(), T> {
        let bytes = (self.measure)(&value);
        if bytes > self.byte_limit {
            return Err(value);
        }
        let mut state = lock(&self.state);
        while !state.closed
            && (state.entries.len() >= self.message_limit
                || state
                    .bytes
                    .checked_add(bytes)
                    .is_none_or(|sum| sum > self.byte_limit))
        {
            state = self
                .space
                .wait(state)
                .unwrap_or_else(std::sync::PoisonError::into_inner);
        }
        if state.closed {
            return Err(value);
        }
        state.bytes += bytes;
        state.entries.push_back(value);
        self.arrived.notify_one();
        Ok(())
    }

    pub(crate) fn close(&self) {
        let mut state = lock(&self.state);
        state.closed = true;
        self.arrived.notify_all();
        self.space.notify_all();
    }

    /// Closes the queue and drops what it still held.
    pub(crate) fn close_and_discard(&self) {
        let mut state = lock(&self.state);
        state.closed = true;
        let discarded = std::mem::take(&mut state.entries);
        state.bytes = 0;
        self.arrived.notify_all();
        self.space.notify_all();
        drop(state);
        drop(discarded);
    }

    pub(crate) fn is_closed(&self) -> bool {
        lock(&self.state).closed
    }

    #[cfg(test)]
    pub(crate) fn retained_bytes(&self) -> usize {
        lock(&self.state).bytes
    }

    pub(crate) fn len(&self) -> usize {
        lock(&self.state).entries.len()
    }
}

#[derive(Debug, Eq, PartialEq)]
pub(crate) enum QueuePushError<T> {
    Closed(T),
    Full(T),
}

fn lock<T>(mutex: &Mutex<T>) -> MutexGuard<'_, T> {
    mutex
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicUsize, Ordering};
    use std::sync::{Arc, Barrier};
    use std::thread;

    #[test]
    fn count_and_byte_bounds_preserve_the_unsent_value() {
        let queue = BoundedQueue::new(2, 5, Vec::<u8>::len);
        assert_eq!(queue.try_push(vec![1, 2, 3]), Ok(()));
        assert_eq!(queue.try_push(vec![4, 5]), Ok(()));
        assert_eq!(queue.retained_bytes(), 5);
        assert_eq!(queue.try_push(vec![]), Err(QueuePushError::Full(vec![])));
        assert_eq!(queue.pop(Some(Duration::ZERO)), Some(vec![1, 2, 3]));
        assert_eq!(
            queue.try_push(vec![6, 7, 8, 9]),
            Err(QueuePushError::Full(vec![6, 7, 8, 9]))
        );
        assert_eq!(queue.try_push(vec![6, 7, 8]), Ok(()));
        assert_eq!(queue.retained_bytes(), 5);
    }

    #[test]
    fn impossible_blocking_send_returns_without_waiting() {
        let queue = BoundedQueue::new(1, 2, Vec::<u8>::len);
        assert_eq!(queue.push_wait(vec![1, 2, 3]), Err(vec![1, 2, 3]));
        assert_eq!(queue.len(), 0);
    }

    #[test]
    fn sender_close_drains_and_wakes_empty_receives() {
        let queue = Arc::new(BoundedQueue::new(2, 8, Vec::<u8>::len));
        queue.try_push(vec![1]).unwrap();
        queue.close();
        assert_eq!(queue.pop(None), Some(vec![1]));
        assert_eq!(queue.pop(None), None);
        assert_eq!(
            queue.try_push(vec![2]),
            Err(QueuePushError::Closed(vec![2]))
        );
        let queue = Arc::new(BoundedQueue::new(1, 1, Vec::<u8>::len));
        let receiving = Arc::clone(&queue);
        let receiver = thread::spawn(move || receiving.pop(None));
        queue.close();
        assert_eq!(receiver.join().unwrap(), None);
    }

    #[test]
    fn receiver_close_wakes_capacity_waits_and_drops_every_message_once() {
        struct Payload(Arc<AtomicUsize>);
        impl Drop for Payload {
            fn drop(&mut self) {
                self.0.fetch_add(1, Ordering::SeqCst);
            }
        }
        let dropped = Arc::new(AtomicUsize::new(0));
        let queue = Arc::new(BoundedQueue::new(1, 1, |_| 1));
        assert!(queue.try_push(Payload(Arc::clone(&dropped))).is_ok());
        let sending = Arc::clone(&queue);
        let pending = Payload(Arc::clone(&dropped));
        let producer = thread::spawn(move || sending.push_wait(pending).is_err());
        queue.close_and_discard();
        assert!(producer.join().unwrap());
        assert_eq!(dropped.load(Ordering::SeqCst), 2);
        assert_eq!(queue.len(), 0);
        assert_eq!(queue.retained_bytes(), 0);
        assert!(queue.pop(None).is_none());
    }

    #[test]
    fn close_and_acceptance_have_one_owner_under_racing_schedules() {
        for _ in 0..100 {
            let queue = Arc::new(BoundedQueue::new(1, 8, Vec::<u8>::len));
            let gate = Arc::new(Barrier::new(2));
            let sending = Arc::clone(&queue);
            let start = Arc::clone(&gate);
            let producer = thread::spawn(move || {
                start.wait();
                sending.try_push(vec![42])
            });
            gate.wait();
            queue.close();
            match producer.join().unwrap() {
                Ok(()) => assert_eq!(queue.pop(None), Some(vec![42])),
                Err(QueuePushError::Closed(value)) => assert_eq!(value, vec![42]),
                other => panic!("unexpected acceptance: {other:?}"),
            }
            assert_eq!(queue.pop(None), None);
        }
    }
}

// The host adapter also supplies storage and names these types in every feature
// profile, even when worker bindings are disabled.

/// A direction has one live capability generation. Moving it invalidates every
/// old wrapper, including wrappers retained by a dynamically typed caller.
struct Capability<T> {
    queue: std::sync::Arc<BoundedQueue<T>>,
    generation: std::sync::atomic::AtomicU64,
    sender: bool,
}

pub(crate) struct Endpoint<T> {
    capability: std::sync::Arc<Capability<T>>,
    generation: u64,
}

#[derive(Debug, Eq, PartialEq)]
pub(crate) enum SendError<T> {
    Invalid(T),
    Closed(T),
    Full(T),
    Oversized(T),
}

#[derive(Debug, Eq, PartialEq)]
pub(crate) enum Receive<T> {
    Value(T),
    Empty,
    Closed,
    Invalid,
}

#[repr(i32)]
#[derive(Debug, Eq, PartialEq)]
pub(crate) enum Readiness {
    Ready = 0,
    Waiting = 1,
    Closed = 2,
    Oversized = 3,
    Invalid = 4,
}

impl<T> Endpoint<T> {
    pub(crate) fn pair(
        messages: usize,
        bytes: usize,
        measure: fn(&T) -> usize,
    ) -> Option<(Self, Self)> {
        if messages == 0 || bytes == 0 {
            return None;
        }
        let queue = std::sync::Arc::new(BoundedQueue::new(messages, bytes, measure));
        let endpoint = |sender| Self {
            capability: std::sync::Arc::new(Capability {
                queue: std::sync::Arc::clone(&queue),
                generation: std::sync::atomic::AtomicU64::new(1),
                sender,
            }),
            generation: 1,
        };
        Some((endpoint(true), endpoint(false)))
    }

    pub(crate) fn is_live(&self) -> bool {
        self.capability
            .generation
            .load(std::sync::atomic::Ordering::Acquire)
            == self.generation
    }

    pub(crate) fn is_sender(&self) -> bool {
        self.capability.sender
    }

    pub(crate) fn byte_limit(&self) -> usize {
        self.capability.queue.byte_limit
    }

    pub(crate) fn transfer(&self) -> Option<Self> {
        // Generation changes and queue operations share the lock, so a stale
        // operation cannot accept or consume after the successor starts.
        let _state = lock(&self.capability.queue.state);
        let next = self.generation.checked_add(1)?;
        self.capability
            .generation
            .compare_exchange(
                self.generation,
                next,
                std::sync::atomic::Ordering::AcqRel,
                std::sync::atomic::Ordering::Acquire,
            )
            .ok()?;
        self.capability.queue.arrived.notify_all();
        self.capability.queue.space.notify_all();
        Some(Self {
            capability: std::sync::Arc::clone(&self.capability),
            generation: next,
        })
    }

    pub(crate) fn try_send(&self, value: T) -> Result<(), SendError<T>> {
        if !self.is_live() || !self.is_sender() {
            return Err(SendError::Invalid(value));
        }
        let queue = &self.capability.queue;
        if (queue.measure)(&value) > queue.byte_limit {
            return Err(SendError::Oversized(value));
        }
        let mut state = lock(&queue.state);
        if !self.is_live() {
            return Err(SendError::Invalid(value));
        }
        queue
            .try_push_locked(&mut state, value)
            .map_err(|error| match error {
                QueuePushError::Closed(value) => SendError::Closed(value),
                QueuePushError::Full(value) => SendError::Full(value),
            })
    }

    pub(crate) fn try_receive(&self) -> Receive<T> {
        if !self.is_live() || self.is_sender() {
            return Receive::Invalid;
        }
        let queue = &self.capability.queue;
        // Testing closure and taking the head share the queue lock, so a final
        // accepted message cannot be skipped in favor of end of stream.
        let mut state = lock(&queue.state);
        if !self.is_live() {
            return Receive::Invalid;
        }
        if let Some(value) = state.entries.pop_front() {
            state.bytes -= (queue.measure)(&value);
            queue.space.notify_all();
            Receive::Value(value)
        } else if state.closed {
            Receive::Closed
        } else {
            Receive::Empty
        }
    }

    fn readiness_locked(&self, state: &QueueState<T>, bytes: usize) -> Readiness {
        if !self.is_live() {
            return Readiness::Invalid;
        }
        if self.is_sender() {
            if bytes > self.byte_limit() {
                return Readiness::Oversized;
            }
            if state.closed {
                return Readiness::Closed;
            }
            if state.entries.len() < self.capability.queue.message_limit
                && state
                    .bytes
                    .checked_add(bytes)
                    .is_some_and(|sum| sum <= self.byte_limit())
            {
                Readiness::Ready
            } else {
                Readiness::Waiting
            }
        } else if !state.entries.is_empty() {
            Readiness::Ready
        } else if state.closed {
            Readiness::Closed
        } else {
            Readiness::Waiting
        }
    }

    pub(crate) fn readiness(&self, bytes: usize) -> Readiness {
        self.readiness_locked(&lock(&self.capability.queue.state), bytes)
    }

    pub(crate) fn wait_ready(&self, bytes: usize, timeout: Duration) -> Readiness {
        let queue = &self.capability.queue;
        let mut state = lock(&queue.state);
        let deadline = Instant::now() + timeout;
        while self.readiness_locked(&state, bytes) == Readiness::Waiting {
            let Some(remaining) = deadline.checked_duration_since(Instant::now()) else {
                break;
            };
            let condition = if self.is_sender() {
                &queue.space
            } else {
                &queue.arrived
            };
            let waited = condition
                .wait_timeout(state, remaining)
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            state = waited.0;
            if waited.1.timed_out() {
                break;
            }
        }
        self.readiness_locked(&state, bytes)
    }

    pub(crate) fn close(&self) {
        // Swapping the generation makes explicit close, failed transfer, and
        // finalization idempotent; an old generation cannot close its successor.
        if self
            .capability
            .generation
            .compare_exchange(
                self.generation,
                0,
                std::sync::atomic::Ordering::AcqRel,
                std::sync::atomic::Ordering::Acquire,
            )
            .is_ok()
        {
            if self.is_sender() {
                self.capability.queue.close();
            } else {
                self.capability.queue.close_and_discard();
            }
        }
    }
    /// The owning scope tears storage down after joining its children. Its
    /// authority belongs to the queue, independently of endpoint generations.
    pub(crate) fn abort_resource(&self) {
        self.capability.queue.close_and_discard();
    }
}

impl<T> Drop for Endpoint<T> {
    fn drop(&mut self) {
        self.close();
    }
}

#[cfg(test)]
mod endpoint_tests {
    use super::*;
    use std::sync::Arc;
    use std::thread;

    #[test]
    fn readiness_observes_exact_capacity_and_draining_close() {
        let (sender, receiver) = Endpoint::pair(2, 3, Vec::<u8>::len).unwrap();
        assert_eq!(receiver.readiness(0), Readiness::Waiting);
        assert_eq!(sender.readiness(4), Readiness::Oversized);
        sender.try_send(vec![1, 2]).unwrap();
        assert_eq!(sender.readiness(1), Readiness::Ready);
        assert_eq!(sender.readiness(2), Readiness::Waiting);
        sender.close();
        assert_eq!(receiver.readiness(0), Readiness::Ready);
        assert_eq!(receiver.try_receive(), Receive::Value(vec![1, 2]));
        assert_eq!(receiver.readiness(0), Readiness::Closed);
        assert_eq!(sender.readiness(0), Readiness::Invalid);
    }

    #[test]
    fn host_waits_wake_for_capacity_messages_and_peer_close() {
        let (sender, receiver) = Endpoint::pair(1, 1, Vec::<u8>::len).unwrap();
        let receiving = Arc::new(receiver);
        let parked = Arc::clone(&receiving);
        let waiting = thread::spawn(move || parked.wait_ready(0, Duration::from_secs(1)));
        sender.try_send(vec![42]).unwrap();
        assert_eq!(waiting.join().unwrap(), Readiness::Ready);
        let sender = Arc::new(sender);
        let parked = Arc::clone(&sender);
        let waiting = thread::spawn(move || parked.wait_ready(1, Duration::from_secs(1)));
        assert_eq!(receiving.try_receive(), Receive::Value(vec![42]));
        assert_eq!(waiting.join().unwrap(), Readiness::Ready);
        sender.try_send(vec![1]).unwrap();
        let parked = Arc::clone(&sender);
        let waiting = thread::spawn(move || parked.wait_ready(1, Duration::from_secs(1)));
        receiving.close();
        assert_eq!(waiting.join().unwrap(), Readiness::Closed);
    }

    #[test]
    fn moving_a_direction_wakes_and_invalidates_old_waits() {
        let (sender, receiver) = Endpoint::pair(1, 1, Vec::<u8>::len).unwrap();
        sender.try_send(vec![1]).unwrap();
        let sender = Arc::new(sender);
        let parked = Arc::clone(&sender);
        let waiting = thread::spawn(move || parked.wait_ready(1, Duration::from_secs(1)));
        let moved = sender.transfer().unwrap();
        assert_eq!(waiting.join().unwrap(), Readiness::Invalid);
        assert_eq!(receiver.try_receive(), Receive::Value(vec![1]));
        assert_eq!(moved.wait_ready(1, Duration::ZERO), Readiness::Ready);
    }

    #[test]
    fn moves_invalidate_old_generations_without_closing_the_successor() {
        let (sender, receiver) = Endpoint::pair(2, 8, Vec::<u8>::len).unwrap();
        let moved = sender.transfer().unwrap();
        assert!(!sender.is_live());
        assert!(sender.transfer().is_none());
        assert_eq!(sender.try_send(vec![1]), Err(SendError::Invalid(vec![1])));
        drop(sender);
        assert_eq!(moved.try_send(vec![2]), Ok(()));
        assert_eq!(receiver.try_receive(), Receive::Value(vec![2]));
        assert_eq!(receiver.try_receive(), Receive::Empty);
        drop(moved);
        assert_eq!(receiver.try_receive(), Receive::Closed);
    }

    #[test]
    fn directions_limits_and_unsent_payloads_are_enforced() {
        let (sender, receiver) = Endpoint::pair(1, 2, Vec::<u8>::len).unwrap();
        assert_eq!(receiver.try_send(vec![1]), Err(SendError::Invalid(vec![1])));
        assert_eq!(sender.try_receive(), Receive::Invalid);
        assert_eq!(
            sender.try_send(vec![1, 2, 3]),
            Err(SendError::Oversized(vec![1, 2, 3]))
        );
        assert_eq!(sender.try_send(vec![1, 2]), Ok(()));
        assert_eq!(sender.try_send(vec![3]), Err(SendError::Full(vec![3])));
        receiver.close();
        assert_eq!(sender.try_send(vec![4]), Err(SendError::Closed(vec![4])));
        assert_eq!(sender.capability.queue.retained_bytes(), 0);
    }

    #[test]
    fn a_transfer_race_mints_exactly_one_successor() {
        for _ in 0..100 {
            let (sender, receiver) = Endpoint::pair(1, 1, Vec::<u8>::len).unwrap();
            let sender = Arc::new(sender);
            let first = Arc::clone(&sender);
            let second = Arc::clone(&sender);
            let left = thread::spawn(move || first.transfer());
            let right = thread::spawn(move || second.transfer());
            let left = left.join().unwrap();
            let right = right.join().unwrap();
            assert_ne!(left.is_some(), right.is_some());
            let successor = left.or(right).unwrap();
            drop(sender);
            assert_eq!(successor.try_send(vec![42]), Ok(()));
            assert_eq!(receiver.try_receive(), Receive::Value(vec![42]));
        }
    }

    #[test]
    fn a_failed_transfer_drops_the_direction_and_unread_storage() {
        let (sender, receiver) = Endpoint::pair(1, 8, Vec::<u8>::len).unwrap();
        sender.try_send(vec![42]).unwrap();
        let in_transit = receiver.transfer().unwrap();
        drop(in_transit);
        assert_eq!(sender.try_send(vec![1]), Err(SendError::Closed(vec![1])));
        assert_eq!(sender.capability.queue.len(), 0);
        assert_eq!(receiver.try_receive(), Receive::Invalid);
    }
}
