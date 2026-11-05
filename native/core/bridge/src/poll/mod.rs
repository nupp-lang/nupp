//! The readiness system calls under the guest's reactor: a poller (kqueue on
//! macOS, epoll on Linux), one-shot interest in a descriptor or in a child's
//! exit, a wait for one event, and nonblocking pipes. The queues, the
//! deadlines and the nonblocking calls made on readiness are the guest's;
//! each call here is one system call or two, answering a value or the
//! negated error number.
use std::ffi::c_int;

#[cfg(target_os = "macos")]
#[path = "kqueue.rs"]
mod backend;

#[cfg(target_os = "linux")]
#[path = "epoll.rs"]
mod backend;

unsafe extern "C" {
    fn pipe(fds: *mut c_int) -> c_int;
    fn fcntl(fd: c_int, command: c_int, ...) -> c_int;
    fn close(fd: c_int) -> c_int;
}

/// Interest and readiness, as the guest encodes them. An exit's event
/// carries a process id where the others carry a descriptor.
pub(crate) const READABLE: u64 = 1;
const WRITABLE: u64 = 2;
const HANGUP: u64 = 4;
const FAILED: u64 = 8;
pub(crate) const EXITED: u64 = 16;
/// An event is its descriptor or process id above these bits.
pub(crate) const EVENT_BITS: u64 = 5;
/// A wait without a limit.
const FOREVER: u64 = u64::MAX;
const EINVAL: i32 = 22;

fn last() -> u64 {
    (-i64::from(std::io::Error::last_os_error().raw_os_error().unwrap_or(EINVAL))) as u64
}

fn interrupted() -> bool {
    std::io::Error::last_os_error().kind() == std::io::ErrorKind::Interrupted
}

/// A pipe answers its read end in the low bits and its write end from bit
/// WRITE_END.
pub const WRITE_END: u64 = 32;
pub const READ_END: u64 = 0xffff_ffff;

const F_GETFL: c_int = 3;
const F_SETFL: c_int = 4;
const F_SETFD: c_int = 2;
const FD_CLOEXEC: c_int = 1;
const O_NONBLOCK: c_int = if cfg!(target_os = "macos") { 0x4 } else { 0o4000 };

/// One event as the guest reads it: the descriptor or process id above the
/// readiness bits.
fn event(ident: u64, bits: u64) -> u64 {
    ident << EVENT_BITS | bits
}

/// A pipe whose ends close on exec, each nonblocking as `nonblocking` says
/// (its read end first): the read end's descriptor, and the write end's
/// above it from bit 32; or the negated error number.
pub fn pipe_with(nonblocking: [bool; 2]) -> u64 {
    let mut fds: [c_int; 2] = [-1, -1];
    if unsafe { pipe(fds.as_mut_ptr()) } != 0 {
        return last();
    }
    for (fd, wanted) in fds.into_iter().zip(nonblocking) {
        let flags = unsafe { fcntl(fd, F_GETFL) };
        if flags < 0
            || wanted && unsafe { fcntl(fd, F_SETFL, flags | O_NONBLOCK) } != 0
            || unsafe { fcntl(fd, F_SETFD, FD_CLOEXEC) } != 0
        {
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
/// event: its descriptor above five bits, 1 readable, 2 writable, 4 hung
/// up and 8 failed, or a child's process id above 16 for its exit; zero when
/// the time passed or a signal interrupted the wait; or the negated error
/// number.
pub extern "C" fn poll_wait(poller: u64, nanos: u64) -> u64 {
    backend::wait(poller, nanos)
}

/// A pipe whose ends are nonblocking and close on exec: the read end's
/// descriptor, and the write end's above it from bit 32; or the negated
/// error number.
pub extern "C" fn pipe_open() -> u64 {
    pipe_with([true, true])
}

/// Has `poller` report child `pid`'s exit once, as an event: zero, or the
/// negated error number (ESRCH when it has already exited).
pub extern "C" fn process_watch(poller: u64, pid: u64) -> u64 {
    backend::watch_exit(poller, pid)
}

/// Stops watching child `pid`'s exit, which may have been reported: zero, or
/// the negated error number.
pub extern "C" fn process_unwatch(poller: u64, pid: u64) -> u64 {
    backend::unwatch_exit(poller, pid)
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
