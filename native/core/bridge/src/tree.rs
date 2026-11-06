//! The descriptor-relative calls a recursive `os.remove` walks a directory
//! tree with: opening a directory below another without following a link,
//! naming a directory's entries, and unlinking an entry relative to its
//! directory. A directory swapped for a link while the guest walks is then
//! removed as the link it has become, never followed. The walk, its depth
//! bound and its results are the guest's.
use std::ffi::{CStr, c_char, c_int};

#[repr(C)]
struct Dir {
    _private: [u8; 0],
}

unsafe extern "C" {
    fn openat(parent: c_int, path: *const c_char, flags: c_int, ...) -> c_int;
    fn unlinkat(parent: c_int, path: *const c_char, flags: c_int) -> c_int;
    fn dup(fd: c_int) -> c_int;
    fn close(fd: c_int) -> c_int;
    fn fdopendir(fd: c_int) -> *mut Dir;
    fn rewinddir(dir: *mut Dir);
    fn readdir(dir: *mut Dir) -> *const u8;
    fn closedir(dir: *mut Dir) -> c_int;
}

#[cfg(target_os = "macos")]
mod constants {
    pub const DIRECTORY: i32 = 0x0010_0000;
    pub const NOFOLLOW: i32 = 0x0100;
    pub const CLOEXEC: i32 = 0x0100_0000;
    pub const CWD: i32 = -2;
    pub const REMOVEDIR: i32 = 0x0080;
    /// Where `struct dirent`'s name starts: after d_ino, d_seekoff,
    /// d_reclen, d_namlen and d_type.
    pub const NAME: usize = 21;
    pub const ELOOP: i32 = 62;
    pub const ENOTDIR: i32 = 20;
}

#[cfg(all(target_os = "linux", target_arch = "aarch64"))]
mod constants {
    pub const DIRECTORY: i32 = 0o40000;
    pub const NOFOLLOW: i32 = 0o100000;
    pub const CLOEXEC: i32 = 0o2000000;
    pub const CWD: i32 = -100;
    pub const REMOVEDIR: i32 = 0x200;
    /// Where `struct dirent`'s name starts: after d_ino, d_off, d_reclen
    /// and d_type.
    pub const NAME: usize = 19;
    pub const ELOOP: i32 = 40;
    pub const ENOTDIR: i32 = 20;
}

#[cfg(all(target_os = "linux", not(target_arch = "aarch64")))]
mod constants {
    pub const DIRECTORY: i32 = 0o200000;
    pub const NOFOLLOW: i32 = 0o400000;
    pub const CLOEXEC: i32 = 0o2000000;
    pub const CWD: i32 = -100;
    pub const REMOVEDIR: i32 = 0x200;
    /// Where `struct dirent`'s name starts: after d_ino, d_off, d_reclen
    /// and d_type.
    pub const NAME: usize = 19;
    pub const ELOOP: i32 = 40;
    pub const ENOTDIR: i32 = 20;
}

fn last() -> u64 {
    (-i64::from(std::io::Error::last_os_error().raw_os_error().unwrap_or(22))) as u64
}

/// The guest's parent descriptor: a negative one is the working directory.
fn parent(fd: u64) -> c_int {
    if (fd as i64) < 0 { constants::CWD } else { fd as c_int }
}

/// The name in the `bytes` bytes at `path`, up to a NUL as C reads it.
fn cname(path: u64, bytes: u64) -> std::ffi::CString {
    let name = if bytes == 0 { &[][..] } else { unsafe { std::slice::from_raw_parts(path as *const u8, bytes as usize) } };
    let name = name.split(|byte| *byte == 0).next().unwrap_or(&[]);
    std::ffi::CString::new(name).unwrap_or_default()
}

/// Opens the directory named by the `bytes` bytes at `path` below directory
/// `fd` (negative: the working directory), refusing to follow a link: its
/// descriptor, or the negated error number (ENOTDIR for anything
/// that is not a directory, a link included, as ENOTDIR).
pub unsafe extern "C" fn dir_open(fd: u64, path: u64, bytes: u64) -> u64 {
    let name = cname(path, bytes);
    let flags = constants::DIRECTORY | constants::NOFOLLOW | constants::CLOEXEC;
    let opened = unsafe { openat(parent(fd), name.as_ptr(), flags) };
    if opened >= 0 {
        return opened as u64;
    }
    // A link refused by O_NOFOLLOW is one more thing that is not a directory.
    if std::io::Error::last_os_error().raw_os_error() == Some(constants::ELOOP) {
        return (-i64::from(constants::ENOTDIR)) as u64;
    }
    last()
}

/// Copies the names of directory `fd`'s entries, "." and ".." aside, each
/// followed by a NUL, into `out`, at most `room` bytes: their whole length,
/// or the negated error number. Each call reads the directory afresh.
pub unsafe extern "C" fn dir_names(fd: u64, out: u64, room: u64) -> u64 {
    let copy = unsafe { dup(fd as c_int) };
    if copy < 0 {
        return last();
    }
    let dir = unsafe { fdopendir(copy) };
    if dir.is_null() {
        let failed = last();
        unsafe { close(copy) };
        return failed;
    }
    unsafe { rewinddir(dir) };
    let mut length = 0usize;
    loop {
        let entry = unsafe { readdir(dir) };
        if entry.is_null() {
            break;
        }
        let name = unsafe { CStr::from_ptr(entry.add(constants::NAME) as *const c_char) }.to_bytes();
        if name == b"." || name == b".." {
            continue;
        }
        for &byte in name.iter().chain(std::iter::once(&0u8)) {
            if length < room as usize {
                unsafe { *(out as *mut u8).add(length) = byte };
            }
            length += 1;
        }
    }
    unsafe { closedir(dir) };
    length as u64
}

/// Unlinks the entry named by the `bytes` bytes at `path` in directory `fd`
/// (negative: the working directory), an empty directory when `directory`
/// is 1: zero, or the negated error number.
pub unsafe extern "C" fn unlink_entry(fd: u64, path: u64, bytes: u64, directory: u64) -> u64 {
    let name = cname(path, bytes);
    let flags = if directory == 1 { constants::REMOVEDIR } else { 0 };
    if unsafe { unlinkat(parent(fd), name.as_ptr(), flags) } == 0 { 0 } else { last() }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn walks_and_removes_a_tree() {
        let root = std::env::temp_dir().join(format!("nupp-core-tree-{}", std::process::id()));
        std::fs::create_dir_all(root.join("a/b")).unwrap();
        std::fs::write(root.join("a/b/c"), b"x").unwrap();
        std::fs::write(root.join("d"), b"y").unwrap();
        std::os::unix::fs::symlink(root.join("a"), root.join("link")).unwrap();
        let path = root.to_str().unwrap();
        let fd = unsafe { dir_open(u64::MAX, path.as_ptr() as u64, path.len() as u64) };
        assert!((fd as i64) >= 0);
        let mut out = [0u8; 64];
        let length = unsafe { dir_names(fd, out.as_mut_ptr() as u64, 64) } as usize;
        let mut names: Vec<_> = out[..length].split(|b| *b == 0).filter(|n| !n.is_empty()).collect();
        names.sort();
        assert_eq!(names, vec![&b"a"[..], b"d", b"link"]);
        // A link is not opened as a directory.
        let refused = unsafe { dir_open(fd, b"link".as_ptr() as u64, 4) } as i64;
        assert_eq!(refused, -i64::from(constants::ENOTDIR));
        assert_eq!(unsafe { unlink_entry(fd, b"link".as_ptr() as u64, 4, 0) }, 0);
        // A directory with entries is not unlinked.
        assert!((unsafe { unlink_entry(fd, b"a".as_ptr() as u64, 1, 1) } as i64) < 0);
        unsafe { close(fd as c_int) };
        std::fs::remove_dir_all(&root).unwrap();
    }
}
