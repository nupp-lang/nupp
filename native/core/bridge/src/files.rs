//! The system calls under the guest's file layer: open, read, write, seek and
//! close on descriptors, and the system's text for an error number. Each
//! answers a count, descriptor or position, or the negated error number; the
//! buffering, modes and Lua's results are the guest's.
use std::ffi::{c_char, c_int, c_void};

unsafe extern "C" {
    fn read(fd: c_int, buffer: *mut c_void, count: usize) -> isize;
    fn write(fd: c_int, buffer: *const c_void, count: usize) -> isize;
    fn lseek(fd: c_int, offset: i64, whence: c_int) -> i64;
    fn close(fd: c_int) -> c_int;
    fn strerror(code: c_int) -> *const c_char;
}

/// The access an open asks for, as the guest encodes it.
const READ: u64 = 1;
const WRITE: u64 = 2;
const CREATE: u64 = 4;
const TRUNCATE: u64 = 8;
const APPEND: u64 = 16;

fn failed(error: std::io::Error) -> u64 {
    // An error with no number (a name holding a NUL) is C's EINVAL.
    (-i64::from(error.raw_os_error().unwrap_or(22))) as u64
}

fn last() -> u64 {
    failed(std::io::Error::last_os_error())
}

fn interrupted() -> bool {
    std::io::Error::last_os_error().kind() == std::io::ErrorKind::Interrupted
}

/// Opens the file named by the `bytes` bytes at `path`, up to a NUL as C's
/// open reads it, with the access `flags` encodes; a file it creates gets
/// mode 0666 less the umask, as fopen's do. The descriptor, or the negated
/// error number.
pub unsafe extern "C" fn file_open(path: u64, bytes: u64, flags: u64) -> u64 {
    use std::os::fd::IntoRawFd;
    use std::os::unix::ffi::OsStrExt;
    use std::os::unix::fs::OpenOptionsExt;
    if path == 0 && bytes != 0 {
        return failed(std::io::Error::from_raw_os_error(14));
    }
    let name = if bytes == 0 { &[][..] } else { unsafe { std::slice::from_raw_parts(path as *const u8, bytes as usize) } };
    let name = name.split(|byte| *byte == 0).next().unwrap_or(&[]);
    let mut options = std::fs::OpenOptions::new();
    options
        .read(flags & READ != 0)
        .write(flags & WRITE != 0 && flags & APPEND == 0)
        .append(flags & APPEND != 0)
        .create(flags & CREATE != 0)
        .truncate(flags & TRUNCATE != 0)
        .mode(0o666);
    match options.open(std::ffi::OsStr::from_bytes(name)) {
        Ok(file) => file.into_raw_fd() as u64,
        Err(error) => failed(error),
    }
}

/// Reads at most `room` bytes from `fd` into `out`: the count read, zero at
/// the end, or the negated error number.
pub unsafe extern "C" fn file_read(fd: u64, out: u64, room: u64) -> u64 {
    loop {
        let count = unsafe { read(fd as c_int, out as *mut c_void, room as usize) };
        if count >= 0 {
            return count as u64;
        }
        if !interrupted() {
            return last();
        }
    }
}

/// Writes at most `bytes` bytes at `base` to `fd`: the count written, which
/// may be fewer, or the negated error number.
pub unsafe extern "C" fn file_write(fd: u64, base: u64, bytes: u64) -> u64 {
    loop {
        let count = unsafe { write(fd as c_int, base as *const c_void, bytes as usize) };
        if count >= 0 {
            return count as u64;
        }
        if !interrupted() {
            return last();
        }
    }
}

/// Moves `fd`'s position to `offset` from its start (0), its current
/// position (1) or its end (2): the new position, or the negated error number.
pub unsafe extern "C" fn file_seek(fd: u64, offset: u64, whence: u64) -> u64 {
    if whence > 2 {
        return failed(std::io::Error::from_raw_os_error(22));
    }
    // SEEK_SET, SEEK_CUR and SEEK_END are 0, 1 and 2 on macOS and Linux.
    let position = unsafe { lseek(fd as c_int, offset as i64, whence as c_int) };
    if position < 0 { last() } else { position as u64 }
}

/// Closes `fd`: zero, or the negated error number. The descriptor is gone
/// either way, so it is never retried.
pub unsafe extern "C" fn file_close(fd: u64) -> u64 {
    if unsafe { close(fd as c_int) } == 0 { 0 } else { last() }
}

/// Copies the system's text for the error number `code`, C's strerror, into
/// `out`, at most `room` bytes: its whole length.
pub unsafe extern "C" fn error_text(code: u64, out: u64, room: u64) -> u64 {
    let text = unsafe { std::ffi::CStr::from_ptr(strerror(code as c_int)) }.to_bytes();
    if out != 0 {
        let count = text.len().min(room as usize);
        unsafe { std::ptr::copy_nonoverlapping(text.as_ptr(), out as *mut u8, count) };
    }
    text.len() as u64
}

unsafe extern "C" {
    fn remove(path: *const c_char) -> c_int;
    fn rename(from: *const c_char, to: *const c_char) -> c_int;
    fn mkstemp(template: *mut c_char) -> c_int;
}

/// The name in the `bytes` bytes at `path`, up to a NUL as C reads it, as a
/// C string.
fn cname(path: u64, bytes: u64) -> std::ffi::CString {
    let name = if bytes == 0 { &[][..] } else { unsafe { std::slice::from_raw_parts(path as *const u8, bytes as usize) } };
    let name = name.split(|byte| *byte == 0).next().unwrap_or(&[]);
    std::ffi::CString::new(name).unwrap_or_default()
}

/// Removes the file or empty directory named by the `bytes` bytes at `path`,
/// as C's remove: zero, or the negated error number.
pub unsafe extern "C" fn file_remove(path: u64, bytes: u64) -> u64 {
    let name = cname(path, bytes);
    if unsafe { remove(name.as_ptr()) } == 0 { 0 } else { last() }
}

/// Renames the file named by the `from_bytes` bytes at `from` to the name in
/// the `to_bytes` bytes at `to`, as C's rename: zero, or the negated error
/// number.
pub unsafe extern "C" fn file_rename(from: u64, from_bytes: u64, to: u64, to_bytes: u64) -> u64 {
    let (from, to) = (cname(from, from_bytes), cname(to, to_bytes));
    if unsafe { rename(from.as_ptr(), to.as_ptr()) } == 0 { 0 } else { last() }
}

/// Where a temporary file is made, as Lua's LUA_TMPNAMTEMPLATE.
const TEMPORARY: &[u8] = b"/tmp/lua_XXXXXX\0";

/// Makes a new empty file with a unique name, as Lua's os.tmpname does with
/// mkstemp, and closes it; copies its name into `out`, at most `room` bytes:
/// the name's length, or the negated error number.
pub unsafe extern "C" fn file_temporary(out: u64, room: u64) -> u64 {
    let mut name = TEMPORARY.to_vec();
    let fd = unsafe { mkstemp(name.as_mut_ptr() as *mut c_char) };
    if fd < 0 {
        return last();
    }
    unsafe { close(fd) };
    let length = name.len() - 1;
    let count = length.min(room as usize);
    unsafe { std::ptr::copy_nonoverlapping(name.as_ptr(), out as *mut u8, count) };
    length as u64
}
