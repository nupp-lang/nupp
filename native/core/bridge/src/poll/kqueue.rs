//! The poller on macOS: a kqueue, a filter per readiness and the process
//! filter for a child's exit.
use super::*;

#[repr(C)]
struct Kevent {
    ident: usize,
    filter: i16,
    flags: u16,
    fflags: u32,
    data: isize,
    udata: *mut std::ffi::c_void,
}

#[repr(C)]
struct Timespec {
    seconds: i64,
    nanos: i64,
}

unsafe extern "C" {
    fn kqueue() -> c_int;
    fn kevent(
        kq: c_int,
        changes: *const Kevent,
        count: c_int,
        events: *mut Kevent,
        room: c_int,
        timeout: *const Timespec,
    ) -> c_int;
    fn waitid(idtype: c_int, id: u32, info: *mut SigInfo, options: c_int) -> c_int;
}

/// Room for waitid's siginfo_t, which this reads nothing of.
#[repr(C, align(8))]
struct SigInfo([u8; 128]);

const P_PID: c_int = 1;
const WEXITED: c_int = 0x04;
const WNOWAIT: c_int = 0x20;

const EVFILT_READ: i16 = -1;
const EVFILT_WRITE: i16 = -2;
const EVFILT_PROC: i16 = -5;
const EV_ADD: u16 = 0x1;
const EV_DELETE: u16 = 0x2;
const EV_ONESHOT: u16 = 0x10;
const EV_RECEIPT: u16 = 0x40;
const EV_ERROR: u16 = 0x4000;
const EV_EOF: u16 = 0x8000;
const NOTE_EXIT: u32 = 0x8000_0000;
const ENOENT: isize = 2;
const ESRCH: isize = 3;
const NANOS: u64 = 1_000_000_000;

fn change(ident: u64, filter: i16, wanted: bool) -> Kevent {
    let flags = if wanted { EV_ADD | EV_ONESHOT } else { EV_DELETE };
    Kevent { ident: ident as usize, filter, flags: flags | EV_RECEIPT, fflags: 0, data: 0, udata: std::ptr::null_mut() }
}

/// Applies `changes`: 0, or the negated error number of the first that
/// failed for a reason other than one `ignored` answers true for.
fn apply(poller: u64, changes: &[Kevent], ignored: impl Fn(isize) -> bool) -> u64 {
    let mut receipts = [change(0, 0, false), change(0, 0, false)];
    let room = changes.len().min(receipts.len()) as c_int;
    let count =
        unsafe { kevent(poller as c_int, changes.as_ptr(), room, receipts.as_mut_ptr(), room, std::ptr::null()) };
    if count < 0 {
        return last();
    }
    for receipt in &receipts[..count as usize] {
        if receipt.flags & EV_ERROR != 0 && receipt.data != 0 && !ignored(receipt.data) {
            return (-(receipt.data as i64)) as u64;
        }
    }
    0
}

pub fn open() -> u64 {
    let kq = unsafe { kqueue() };
    if kq < 0 {
        return last();
    }
    // The poller is not inherited.
    unsafe { fcntl(kq, F_SETFD, FD_CLOEXEC) };
    kq as u64
}

pub fn arm(poller: u64, fd: u64, interest: u64) -> u64 {
    let changes = [change(fd, EVFILT_READ, interest & READABLE != 0), change(fd, EVFILT_WRITE, interest & WRITABLE != 0)];
    // Removing interest the descriptor never had is not a failure.
    apply(poller, &changes, |code| code == ENOENT)
}

pub fn watch_exit(poller: u64, pid: u64) -> u64 {
    let mut exit = change(pid, EVFILT_PROC, true);
    exit.fflags = NOTE_EXIT;
    let status = apply(poller, &[exit], |_| false);
    if status as i64 == -(ESRCH as i64) {
        reapable(pid);
    }
    status
}

/// Waits, without reaping it, until child `pid` can be reaped. The filter
/// refuses a child already exiting, and reports an exit, a moment before
/// waitpid can collect it: exiting is all it still does then, so this
/// returns at once, and ESRCH or an exit always means a status to collect.
fn reapable(pid: u64) {
    let mut info = SigInfo([0; 128]);
    while unsafe { waitid(P_PID, pid as u32, &mut info, WEXITED | WNOWAIT) } != 0 && interrupted() {}
}

pub fn unwatch_exit(poller: u64, pid: u64) -> u64 {
    // A watch that fired, or a process already gone, has nothing to remove.
    apply(poller, &[change(pid, EVFILT_PROC, false)], |code| code == ENOENT || code == ESRCH)
}

pub fn wait(poller: u64, nanos: u64) -> u64 {
    let limit = Timespec { seconds: (nanos / NANOS) as i64, nanos: (nanos % NANOS) as i64 };
    let timeout = if nanos == FOREVER { std::ptr::null() } else { &limit as *const Timespec };
    let mut out = change(0, 0, false);
    let count = unsafe { kevent(poller as c_int, std::ptr::null(), 0, &mut out, 1, timeout) };
    if count < 0 {
        return if interrupted() { 0 } else { last() };
    }
    if count == 0 {
        return 0;
    }
    if out.filter == EVFILT_PROC {
        reapable(out.ident as u64);
        return event(out.ident as u64, EXITED);
    }
    let mut bits = match out.filter {
        EVFILT_READ => READABLE,
        EVFILT_WRITE => WRITABLE,
        _ => 0,
    };
    if out.flags & EV_EOF != 0 {
        bits |= HANGUP;
    }
    if out.flags & EV_ERROR != 0 {
        bits |= FAILED;
    }
    event(out.ident as u64, bits)
}
