//! The readiness system calls under the guest's reactor: a poller (kqueue on
//! macOS, epoll on Linux), one-shot interest in a descriptor, a wait for one
//! event, and nonblocking pipes. The queues, the deadlines and the
//! nonblocking calls made on readiness are the guest's; each call here is
//! one system call or two, answering a value or the negated error number.
use std::ffi::c_int;

unsafe extern "C" {
    fn pipe(fds: *mut c_int) -> c_int;
    fn fcntl(fd: c_int, command: c_int, ...) -> c_int;
    fn close(fd: c_int) -> c_int;
}

/// Interest and readiness, as the guest encodes them.
const READABLE: u64 = 1;
const WRITABLE: u64 = 2;
const HANGUP: u64 = 4;
const FAILED: u64 = 8;

fn last() -> u64 {
    (-i64::from(std::io::Error::last_os_error().raw_os_error().unwrap_or(22))) as u64
}

fn interrupted() -> bool {
    std::io::Error::last_os_error().kind() == std::io::ErrorKind::Interrupted
}

/// A pipe answers its read end in the low bits and its write end from bit
/// WRITE_END.
pub const WRITE_END: u64 = 32;
pub const READ_END: u64 = 0xffff_ffff;

const F_SETFD: c_int = 2;
const FD_CLOEXEC: c_int = 1;

/// One event as the guest reads it: the descriptor above four readiness bits.
fn event(fd: u64, bits: u64) -> u64 {
    fd << 4 | bits
}

#[cfg(target_os = "macos")]
mod backend {
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
    }

    const EVFILT_READ: i16 = -1;
    const EVFILT_WRITE: i16 = -2;
    const EV_ADD: u16 = 0x1;
    const EV_DELETE: u16 = 0x2;
    const EV_ONESHOT: u16 = 0x10;
    const EV_RECEIPT: u16 = 0x40;
    const EV_ERROR: u16 = 0x4000;
    const EV_EOF: u16 = 0x8000;
    const ENOENT: isize = 2;

    fn change(fd: u64, filter: i16, wanted: bool) -> Kevent {
        let flags = if wanted { EV_ADD | EV_ONESHOT } else { EV_DELETE };
        Kevent { ident: fd as usize, filter, flags: flags | EV_RECEIPT, fflags: 0, data: 0, udata: std::ptr::null_mut() }
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
        let mut receipts = [change(0, 0, false), change(0, 0, false)];
        let count = unsafe { kevent(poller as c_int, changes.as_ptr(), 2, receipts.as_mut_ptr(), 2, std::ptr::null()) };
        if count < 0 {
            return last();
        }
        // Removing interest the descriptor never had is not a failure.
        for receipt in &receipts[..count as usize] {
            if receipt.flags & EV_ERROR != 0 && receipt.data != 0 && receipt.data != ENOENT {
                return (-(receipt.data as i64)) as u64;
            }
        }
        0
    }

    pub fn wait(poller: u64, nanos: u64) -> u64 {
        let limit = Timespec { seconds: (nanos / 1_000_000_000) as i64, nanos: (nanos % 1_000_000_000) as i64 };
        let timeout = if nanos == u64::MAX { std::ptr::null() } else { &limit as *const Timespec };
        let mut out = change(0, 0, false);
        let count = unsafe { kevent(poller as c_int, std::ptr::null(), 0, &mut out, 1, timeout) };
        if count < 0 {
            return if interrupted() { 0 } else { last() };
        }
        if count == 0 {
            return 0;
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
}

#[cfg(target_os = "linux")]
mod backend {
    use super::*;

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

    fn missing() -> bool {
        std::io::Error::last_os_error().raw_os_error() == Some(ENOENT)
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
        let mut wanted = EpollEvent { events, data: fd };
        if unsafe { epoll_ctl(epoll, EPOLL_CTL_MOD, target, &mut wanted) } == 0 {
            return 0;
        }
        if missing() && unsafe { epoll_ctl(epoll, EPOLL_CTL_ADD, target, &mut wanted) } == 0 {
            return 0;
        }
        last()
    }

    pub fn wait(poller: u64, nanos: u64) -> u64 {
        // Milliseconds, rounded up so a wait never ends before its deadline.
        let millis = if nanos == u64::MAX { -1 } else { nanos.div_ceil(1_000_000).min(i32::MAX as u64) as c_int };
        let mut out = EpollEvent { events: 0, data: 0 };
        let count = unsafe { epoll_wait(poller as c_int, &mut out, 1, millis) };
        if count < 0 {
            return if interrupted() { 0 } else { last() };
        }
        if count == 0 {
            return 0;
        }
        let (events, fd) = (out.events, out.data);
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
        event(fd, bits)
    }
}

/// A new poller's descriptor, or the negated error number.
pub extern "C" fn poll_open() -> u64 {
    backend::open()
}

/// Sets the readiness `poller` waits for on `fd` to `interest` (1 readable,
/// 2 writable, added together; 0 none), for one event: after it the guest
/// arms the descriptor again. Zero, or the negated error number.
pub extern "C" fn poll_arm(poller: u64, fd: u64, interest: u64) -> u64 {
    backend::arm(poller, fd, interest)
}

/// Waits at most `nanos` nanoseconds (all ones: without limit) for one
/// event: its descriptor above four bits, 1 readable, 2 writable, 4 hung up
/// and 8 failed; zero when the time passed or a signal interrupted the wait;
/// or the negated error number.
pub extern "C" fn poll_wait(poller: u64, nanos: u64) -> u64 {
    backend::wait(poller, nanos)
}

/// A pipe whose ends are nonblocking and close on exec: the read end's
/// descriptor, and the write end's above it from bit 32; or the negated
/// error number.
pub extern "C" fn pipe_open() -> u64 {
    const F_GETFL: c_int = 3;
    const F_SETFL: c_int = 4;
    const NONBLOCK: c_int = if cfg!(target_os = "macos") { 0x4 } else { 0o4000 };
    let mut fds: [c_int; 2] = [-1, -1];
    if unsafe { pipe(fds.as_mut_ptr()) } != 0 {
        return last();
    }
    for fd in fds {
        let flags = unsafe { fcntl(fd, F_GETFL) };
        if flags < 0
            || unsafe { fcntl(fd, F_SETFL, flags | NONBLOCK) } != 0
            || unsafe { fcntl(fd, F_SETFD, FD_CLOEXEC) } != 0 {
            let failed = last();
            unsafe {
                close(fds[0]);
                close(fds[1]);
            }
            return failed;
        }
    }
    fds[0] as u64 | (fds[1] as u64) << WRITE_END
}

#[cfg(test)]
mod tests {
    use super::*;

    fn write_byte(fd: c_int) {
        let byte = [7u8];
        assert_eq!(unsafe { crate::files::file_write(fd as u64, byte.as_ptr() as u64, 1) }, 1);
    }

    #[test]
    fn a_pipe_reads_once_written_and_hangs_up_once_closed() {
        let poller = poll_open();
        assert!((poller as i64) >= 0);
        let ends = pipe_open();
        assert!((ends as i64) >= 0);
        let (reader, writer) = (ends & READ_END, ends >> WRITE_END);
        let mut room = [0u8; 4];
        // Nonblocking: an empty pipe answers EAGAIN rather than waiting.
        let early = unsafe { crate::files::file_read(reader, room.as_mut_ptr() as u64, 4) } as i64;
        assert!(early == -35 || early == -11, "{early}");
        assert_eq!(poll_arm(poller, reader, READABLE), 0);
        assert_eq!(poll_wait(poller, 1_000_000), 0);
        write_byte(writer as c_int);
        assert_eq!(poll_wait(poller, u64::MAX), event(reader, READABLE));
        // One-shot: nothing more until it is armed again.
        assert_eq!(poll_wait(poller, 0), 0);
        assert_eq!(poll_arm(poller, reader, READABLE), 0);
        assert_eq!(poll_wait(poller, 0) & !HANGUP, event(reader, READABLE));
        assert_eq!(unsafe { crate::files::file_read(reader, room.as_mut_ptr() as u64, 4) }, 1);
        assert_eq!(poll_arm(poller, writer, WRITABLE), 0);
        assert_eq!(poll_wait(poller, 0), event(writer, WRITABLE));
        // Disarming what was never armed is not a failure.
        assert_eq!(poll_arm(poller, writer, 0), 0);
        assert_eq!(poll_arm(poller, reader, READABLE), 0);
        unsafe { close(writer as c_int) };
        assert_eq!(poll_wait(poller, u64::MAX), event(reader, READABLE | HANGUP));
        unsafe {
            close(reader as c_int);
            close(poller as c_int);
        }
    }
}
