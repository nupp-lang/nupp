//! The process-wide readiness generation.
//!
//! Every native family advances this one counter when something a caller could
//! be waiting for changes: a socket turns readable, a file transfer settles, an
//! HTTP transfer produces an event, a child exits or a pipe moves, GPU work
//! finishes. A caller waiting on any mix of them sleeps on the counter once,
//! rather than on one family's condition at a time.
//!
//! The protocol has no lost wakeup when a caller reads [`generation`] *before*
//! it checks the resources it cares about, and then waits from that value: an
//! edge after the read has advanced the counter, so [`wait_since`] returns at
//! once. A wake says only that something changed, so every wait is followed by
//! a recheck.

use std::sync::{Condvar, Mutex, MutexGuard, OnceLock};
use std::time::Duration;

struct Activity {
    generation: Mutex<u64>,
    changed: Condvar,
}

fn activity() -> &'static Activity {
    static ACTIVITY: OnceLock<Activity> = OnceLock::new();
    ACTIVITY.get_or_init(|| Activity {
        generation: Mutex::new(0),
        changed: Condvar::new(),
    })
}

/// The counter's lock. Nothing that can panic runs under it, so a poisoned
/// lock says nothing about the value it holds.
fn locked() -> MutexGuard<'static, u64> {
    activity()
        .generation
        .lock()
        .unwrap_or_else(|error| error.into_inner())
}

/// The current generation.
pub fn generation() -> u64 {
    *locked()
}

/// Records that something changed, and wakes every waiter.
pub fn advance() {
    let mut generation = locked();
    *generation = generation.wrapping_add(1);
    activity().changed.notify_all();
}

/// Waits until the generation moves past `seen`, or until `timeout` elapses,
/// and answers the generation it found. A zero timeout never sleeps.
pub fn wait_since(seen: u64, timeout: Duration) -> u64 {
    let generation = locked();
    let generation = if *generation == seen && !timeout.is_zero() {
        activity()
            .changed
            .wait_timeout_while(generation, timeout, |current| *current == seen)
            .unwrap_or_else(|error| error.into_inner())
            .0
    } else {
        generation
    };
    *generation
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::Instant;

    #[test]
    fn a_wait_from_a_stale_generation_returns_at_once() {
        let seen = generation();
        advance();
        let started = Instant::now();
        assert_ne!(wait_since(seen, Duration::from_secs(5)), seen);
        assert!(started.elapsed() < Duration::from_secs(5));
    }

    #[test]
    fn an_advance_on_another_thread_wakes_a_waiter() {
        let seen = generation();
        let waker = std::thread::spawn(|| {
            std::thread::sleep(Duration::from_millis(20));
            advance();
        });
        let started = Instant::now();
        assert_ne!(wait_since(seen, Duration::from_secs(5)), seen);
        assert!(started.elapsed() < Duration::from_secs(5));
        waker.join().unwrap();
    }

    #[test]
    fn a_zero_timeout_never_sleeps() {
        let started = Instant::now();
        wait_since(generation(), Duration::ZERO);
        assert!(started.elapsed() < Duration::from_secs(1));
    }
}
