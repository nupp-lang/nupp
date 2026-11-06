//! The poller on Linux: an epoll set, one-shot per descriptor, and a pidfd
//! for each child whose exit is watched. Compile-checked; nothing has run it.
use super::*;
use std::collections::HashMap;
use std::ffi::c_long;
use std::sync::{LazyLock, Mutex};

#[cfg_attr(target_arch = "x86_64", repr(C, packed))]
#[cfg_attr(not(target_arch = "x86_64"), repr(C))]
struct EpollEvent {
    events: u32,
    data: u64,
}

unsafe extern "C" {
    fn epoll_create1(flags: c_int) -> c_int;
    fn epoll_ctl(epoll: c_int, op: c_int, fd: c_int, event: *mut EpollEvent) -> c_int;
    fn epoll_wait(epoll: c_int, events: *mut EpollEvent, room: c_int, millis: c_int) -> c_int;
    fn syscall(number: c_long, ...) -> c_long;
}

const EPOLL_CLOEXEC: c_int = 0o2000000;
const EPOLL_CTL_ADD: c_int = 1;
const EPOLL_CTL_DEL: c_int = 2;
const EPOLL_CTL_MOD: c_int = 3;
const EPOLLIN: u32 = 0x1;
const EPOLLOUT: u32 = 0x4;
const EPOLLERR: u32 = 0x8;
const EPOLLHUP: u32 = 0x10;
const EPOLLRDHUP: u32 = 0x2000;
const EPOLLONESHOT: u32 = 1 << 30;
const ENOENT: i32 = 2;
/// pidfd_open: one number on every architecture, as system calls added
/// since Linux 5.0 are.
const SYS_PIDFD_OPEN: c_long = 434;
/// An event's data is a descriptor, or a process id with this bit set.
const PROCESS: u64 = 1 << 63;
const NANOS_PER_MILLI: u64 = 1_000_000;

/// The pidfd of each process whose exit is watched, by process id.
static PIDFDS: LazyLock<Mutex<HashMap<u64, c_int>>> = LazyLock::new(|| Mutex::new(HashMap::new()));

fn missing() -> bool {
    std::io::Error::last_os_error().raw_os_error() == Some(ENOENT)
}

/// Sets `target`'s one-shot registration to `wanted`, adding it when the
/// set does not hold it yet.
fn register(epoll: c_int, target: c_int, wanted: &mut EpollEvent) -> u64 {
    if unsafe { epoll_ctl(epoll, EPOLL_CTL_MOD, target, wanted) } == 0 {
        return 0;
    }
    if missing() && unsafe { epoll_ctl(epoll, EPOLL_CTL_ADD, target, wanted) } == 0 {
        return 0;
    }
    last()
}

pub fn open() -> u64 {
    let epoll = unsafe { epoll_create1(EPOLL_CLOEXEC) };
    if epoll < 0 { last() } else { epoll as u64 }
}

// One-shot for the whole descriptor: the guest arms it again after each
// event with what it still wants, as it does kqueue's filters.
pub fn arm(poller: u64, fd: u64, interest: u64) -> u64 {
    let (epoll, target) = (poller as c_int, fd as c_int);
    if interest & (READABLE | WRITABLE) == 0 {
        let status = unsafe { epoll_ctl(epoll, EPOLL_CTL_DEL, target, std::ptr::null_mut()) };
        return if status == 0 || missing() { 0 } else { last() };
    }
    let mut events = EPOLLONESHOT | EPOLLRDHUP;
    if interest & READABLE != 0 {
        events |= EPOLLIN;
    }
    if interest & WRITABLE != 0 {
        events |= EPOLLOUT;
    }
    register(epoll, target, &mut EpollEvent { events, data: fd })
}

// A child's exit is its pidfd turning readable.
pub fn watch_exit(poller: u64, pid: u64) -> u64 {
    let mut table = PIDFDS.lock().unwrap();
    let pidfd = match table.get(&pid) {
        Some(&pidfd) => pidfd,
        None => {
            // A pidfd closes on exec from the start.
            let made = unsafe { syscall(SYS_PIDFD_OPEN, pid as c_int, 0 as c_int) };
            if made < 0 {
                return last();
            }
            table.insert(pid, made as c_int);
            made as c_int
        }
    };
    register(poller as c_int, pidfd, &mut EpollEvent { events: EPOLLIN | EPOLLONESHOT, data: PROCESS | pid })
}

pub fn unwatch_exit(poller: u64, pid: u64) -> u64 {
    if let Some(pidfd) = PIDFDS.lock().unwrap().remove(&pid) {
        unsafe {
            epoll_ctl(poller as c_int, EPOLL_CTL_DEL, pidfd, std::ptr::null_mut());
            close(pidfd);
        }
    }
    0
}

pub fn wait(poller: u64, nanos: u64) -> u64 {
    // Milliseconds, rounded up so a wait never ends before its deadline.
    let millis = if nanos == FOREVER { -1 } else { nanos.div_ceil(NANOS_PER_MILLI).min(i32::MAX as u64) as c_int };
    let mut out = EpollEvent { events: 0, data: 0 };
    let count = unsafe { epoll_wait(poller as c_int, &mut out, 1, millis) };
    if count < 0 {
        return if interrupted() { 0 } else { last() };
    }
    if count == 0 {
        return 0;
    }
    let (events, data) = (out.events, out.data);
    if data & PROCESS != 0 {
        return event(data & !PROCESS, EXITED);
    }
    let mut bits = 0;
    if events & EPOLLIN != 0 {
        bits |= READABLE;
    }
    if events & EPOLLOUT != 0 {
        bits |= WRITABLE;
    }
    if events & (EPOLLHUP | EPOLLRDHUP) != 0 {
        bits |= HANGUP;
    }
    if events & EPOLLERR != 0 {
        bits |= FAILED;
    }
    event(data, bits)
}
