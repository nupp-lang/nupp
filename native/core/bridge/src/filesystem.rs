// Raw filesystem calls. Path walking, transfer loops, temporary ownership,
// glob matching and application-directory policy belong to Nupp.
use std::ffi::OsStr;
use std::io;
use std::mem::ManuallyDrop;
use std::os::fd::FromRawFd;
use std::os::unix::ffi::OsStrExt;
use std::os::unix::fs::{DirBuilderExt, MetadataExt, PermissionsExt};
use std::path::{Path, PathBuf};

const INVALID: i32 = 22;
const BAD_ADDRESS: i32 = 14;
const BAD_DESCRIPTOR: i32 = 9;
const METADATA_BYTES: usize = 40;
const PERMISSIONS: u64 = 0o7777;
const FILE: u64 = 1;
const DIRECTORY: u64 = 2;
const SYMLINK: u64 = 3;
const OTHER: u64 = 4;
const WORKING_DIRECTORY: u64 = 0;
const CANONICAL_PATH: u64 = 1;
const EXECUTABLE_PATH: u64 = 2;

fn failed(error: io::Error) -> i64 {
    -i64::from(error.raw_os_error().unwrap_or(INVALID))
}

fn invalid() -> i64 {
    -i64::from(INVALID)
}

unsafe fn path<'a>(address: u64, bytes: u64) -> Result<&'a Path, i64> {
    let length = usize::try_from(bytes).map_err(|_| invalid())?;
    if length > isize::MAX as usize || address.checked_add(bytes).is_none() {
        return Err(invalid());
    }
    if address == 0 && length != 0 {
        return Err(-i64::from(BAD_ADDRESS));
    }
    let text = if length == 0 {
        &[][..]
    } else {
        unsafe { std::slice::from_raw_parts(address as *const u8, length) }
    };
    if text.contains(&0) {
        return Err(invalid());
    }
    Ok(Path::new(OsStr::from_bytes(text)))
}

// Five little-endian words: kind, byte length, Unix seconds, nanoseconds,
// permission mode. A failed metadata lookup publishes no output bytes.
unsafe fn metadata(result: io::Result<std::fs::Metadata>, out: u64) -> i64 {
    if out == 0 || out.checked_add(METADATA_BYTES as u64).is_none() {
        return -i64::from(BAD_ADDRESS);
    }
    let value = match result {
        Ok(value) => value,
        Err(error) => return failed(error),
    };
    let ty = value.file_type();
    let kind = if ty.is_symlink() {
        SYMLINK
    } else if ty.is_file() {
        FILE
    } else if ty.is_dir() {
        DIRECTORY
    } else {
        OTHER
    };
    let words = [
        kind,
        value.len(),
        value.mtime() as u64,
        value.mtime_nsec() as u64,
        u64::from(value.mode()),
    ];
    for (index, word) in words.into_iter().enumerate() {
        unsafe {
            std::ptr::copy_nonoverlapping(
                word.to_le_bytes().as_ptr(),
                (out as *mut u8).add(index * 8),
                8,
            )
        };
    }
    0
}

pub unsafe extern "C" fn file_info(base: u64, bytes: u64, follow: u64, out: u64) -> i64 {
    let path = match unsafe { path(base, bytes) } {
        Ok(value) => value,
        Err(code) => return code,
    };
    let result = match follow {
        0 => std::fs::symlink_metadata(path),
        1 => std::fs::metadata(path),
        _ => return invalid(),
    };
    unsafe { metadata(result, out) }
}

pub unsafe extern "C" fn file_status(fd: u64, out: u64) -> i64 {
    let descriptor = match i32::try_from(fd) {
        Ok(value) => value,
        Err(_) => return -i64::from(BAD_DESCRIPTOR),
    };
    let file = ManuallyDrop::new(unsafe { std::fs::File::from_raw_fd(descriptor) });
    unsafe { metadata(file.metadata(), out) }
}

// Zero range sizes; a short range writes nothing and returns the required
// byte count, allowing the Nupp caller to bound/retry a changing path.
unsafe fn text(result: io::Result<PathBuf>, out: u64, room: u64) -> i64 {
    let value = match result {
        Ok(value) => value,
        Err(error) => return failed(error),
    };
    let bytes = value.as_os_str().as_bytes();
    let length = match i64::try_from(bytes.len()) {
        Ok(value) => value,
        Err(_) => return invalid(),
    };
    if out == 0 {
        return if room == 0 {
            length
        } else {
            -i64::from(BAD_ADDRESS)
        };
    }
    if out.checked_add(room).is_none() {
        return -i64::from(BAD_ADDRESS);
    }
    if bytes.len() as u64 <= room {
        unsafe { std::ptr::copy_nonoverlapping(bytes.as_ptr(), out as *mut u8, bytes.len()) };
    }
    length
}

pub unsafe extern "C" fn read_link(base: u64, bytes: u64, out: u64, room: u64) -> i64 {
    let path = match unsafe { path(base, bytes) } {
        Ok(value) => value,
        Err(code) => return code,
    };
    unsafe { text(std::fs::read_link(path), out, room) }
}

pub unsafe extern "C" fn make_directory(base: u64, bytes: u64, mode: u64) -> i64 {
    if mode & !PERMISSIONS != 0 {
        return invalid();
    }
    let path = match unsafe { path(base, bytes) } {
        Ok(value) => value,
        Err(code) => return code,
    };
    match std::fs::DirBuilder::new().mode(mode as u32).create(path) {
        Ok(()) => 0,
        Err(error) => failed(error),
    }
}

pub unsafe extern "C" fn make_symlink(
    target: u64,
    target_bytes: u64,
    link: u64,
    link_bytes: u64,
) -> i64 {
    let target = match unsafe { path(target, target_bytes) } {
        Ok(value) => value,
        Err(code) => return code,
    };
    let link = match unsafe { path(link, link_bytes) } {
        Ok(value) => value,
        Err(code) => return code,
    };
    match std::os::unix::fs::symlink(target, link) {
        Ok(()) => 0,
        Err(error) => failed(error),
    }
}

pub unsafe extern "C" fn change_mode(base: u64, bytes: u64, mode: u64) -> i64 {
    if mode & !PERMISSIONS != 0 {
        return invalid();
    }
    let path = match unsafe { path(base, bytes) } {
        Ok(value) => value,
        Err(code) => return code,
    };
    match std::fs::set_permissions(path, std::fs::Permissions::from_mode(mode as u32)) {
        Ok(()) => 0,
        Err(error) => failed(error),
    }
}

pub unsafe extern "C" fn sync_file(fd: u64) -> i64 {
    let descriptor = match i32::try_from(fd) {
        Ok(value) => value,
        Err(_) => return -i64::from(BAD_DESCRIPTOR),
    };
    let file = ManuallyDrop::new(unsafe { std::fs::File::from_raw_fd(descriptor) });
    match file.sync_all() {
        Ok(()) => 0,
        Err(error) => failed(error),
    }
}

pub unsafe extern "C" fn path_query(which: u64, base: u64, bytes: u64, out: u64, room: u64) -> i64 {
    let result = match which {
        WORKING_DIRECTORY if base == 0 && bytes == 0 => std::env::current_dir(),
        CANONICAL_PATH => match unsafe { path(base, bytes) } {
            Ok(path) => std::fs::canonicalize(path),
            Err(code) => return code,
        },
        EXECUTABLE_PATH if base == 0 && bytes == 0 => std::env::current_exe(),
        _ => return invalid(),
    };
    unsafe { text(result, out, room) }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::os::fd::IntoRawFd;

    struct Directory(PathBuf);
    impl Directory {
        fn new() -> Self {
            let mut stamp = [0u8; 8];
            getrandom::fill(&mut stamp).unwrap();
            let path = std::env::temp_dir()
                .join(format!("nupp-core-fs-{:016x}", u64::from_le_bytes(stamp)));
            std::fs::create_dir(&path).unwrap();
            Self(path)
        }
    }
    impl Drop for Directory {
        fn drop(&mut self) {
            std::fs::remove_dir_all(&self.0).unwrap();
        }
    }
    fn name(path: &Path) -> (u64, u64) {
        let bytes = path.as_os_str().as_bytes();
        (bytes.as_ptr() as u64, bytes.len() as u64)
    }
    fn word(bytes: &[u8], index: usize) -> u64 {
        u64::from_le_bytes(bytes[index * 8..(index + 1) * 8].try_into().unwrap())
    }

    #[test]
    fn metadata_link_and_permission_calls_retain_os_results() {
        let directory = Directory::new();
        let file = directory.0.join("data");
        std::fs::write(&file, b"a\0b").unwrap();
        let (base, length) = name(&file);
        let mut out = [0u8; METADATA_BYTES];
        assert_eq!(
            unsafe { file_info(base, length, 1, out.as_mut_ptr() as u64) },
            0
        );
        assert_eq!(word(&out, 0), FILE);
        assert_eq!(word(&out, 1), 3);
        let fd = std::fs::File::open(&file).unwrap().into_raw_fd();
        assert_eq!(
            unsafe { file_status(fd as u64, out.as_mut_ptr() as u64) },
            0
        );
        assert_eq!(word(&out, 1), 3);
        assert_eq!(unsafe { sync_file(fd as u64) }, 0);
        unsafe { crate::files::file_close(fd as u64) };
        out.fill(0xa5);
        assert!(unsafe { file_status(fd as u64, out.as_mut_ptr() as u64) } < 0);
        assert_eq!(out, [0xa5; METADATA_BYTES]);
        assert_eq!(unsafe { change_mode(base, length, 0o400) }, 0);
        assert_eq!(
            unsafe { file_info(base, length, 1, out.as_mut_ptr() as u64) },
            0
        );
        assert_eq!(word(&out, 4) & 0o777, 0o400);
        let link = directory.0.join("link");
        let (link_base, link_length) = name(&link);
        assert_eq!(
            unsafe { make_symlink(base, length, link_base, link_length) },
            0
        );
        assert_eq!(
            unsafe { file_info(link_base, link_length, 0, out.as_mut_ptr() as u64) },
            0
        );
        assert_eq!(word(&out, 0), SYMLINK);
        assert_eq!(
            unsafe { file_info(link_base, link_length, 1, out.as_mut_ptr() as u64) },
            0
        );
        assert_eq!(word(&out, 0), FILE);
        let mut text = vec![0xa5; length as usize];
        assert_eq!(
            unsafe { read_link(link_base, link_length, text.as_mut_ptr() as u64, 1) },
            length as i64
        );
        assert!(text.iter().all(|byte| *byte == 0xa5));
        assert_eq!(
            unsafe { read_link(link_base, link_length, text.as_mut_ptr() as u64, length) },
            length as i64
        );
        assert_eq!(text, file.as_os_str().as_bytes());
    }

    #[test]
    fn directory_open_follows_links_and_refuses_other_nodes_without_waiting() {
        let directory = Directory::new();
        let link = directory.0.join("directory-link");
        std::os::unix::fs::symlink(&directory.0, &link).unwrap();
        let (base, length) = name(&link);
        const READ_DIRECTORY: u64 = 1 | 128;
        let fd = unsafe { crate::files::file_open(base, length, READ_DIRECTORY) };
        assert!((fd as i64) >= 0);
        assert_eq!(unsafe { crate::files::file_close(fd) }, 0);
        let file = directory.0.join("file");
        std::fs::write(&file, b"x").unwrap();
        let (base, length) = name(&file);
        assert!((unsafe { crate::files::file_open(base, length, READ_DIRECTORY) } as i64) < 0);
        let fifo = directory.0.join("fifo");
        let fifo_bytes = std::ffi::CString::new(fifo.as_os_str().as_bytes()).unwrap();
        unsafe extern "C" {
            fn mkfifo(path: *const std::ffi::c_char, mode: u32) -> i32;
        }
        assert_eq!(unsafe { mkfifo(fifo_bytes.as_ptr(), 0o600) }, 0);
        let (base, length) = name(&fifo);
        assert!((unsafe { crate::files::file_open(base, length, READ_DIRECTORY) } as i64) < 0);
    }

    #[test]
    fn private_creation_is_exclusive_and_path_failures_publish_nothing() {
        let directory = Directory::new();
        let child = directory.0.join("private");
        let (base, length) = name(&child);
        assert_eq!(unsafe { make_directory(base, length, 0o700) }, 0);
        assert_eq!(std::fs::metadata(&child).unwrap().mode() & 0o777, 0o700);
        let file = child.join("empty");
        let (base, length) = name(&file);
        const PRIVATE_EXCLUSIVE: u64 = 2 | 4 | 32 | 64;
        let fd = unsafe { crate::files::file_open(base, length, PRIVATE_EXCLUSIVE) };
        assert!((fd as i64) >= 0);
        unsafe { crate::files::file_close(fd) };
        assert_eq!(std::fs::metadata(&file).unwrap().mode() & 0o777, 0o600);
        let ordinary = child.join("ordinary");
        let reference = child.join("reference");
        std::fs::write(&reference, b"ordinary").unwrap();
        let (ordinary_base, ordinary_length) = name(&ordinary);
        const ORDINARY_EXCLUSIVE: u64 = 2 | 4 | 32;
        let ordinary_fd =
            unsafe { crate::files::file_open(ordinary_base, ordinary_length, ORDINARY_EXCLUSIVE) };
        assert!((ordinary_fd as i64) >= 0);
        assert_eq!(unsafe { crate::files::file_close(ordinary_fd) }, 0);
        assert_eq!(
            std::fs::metadata(&ordinary).unwrap().mode() & 0o777,
            std::fs::metadata(&reference).unwrap().mode() & 0o777,
        );

        assert_eq!(
            unsafe { crate::files::file_open(base, length, PRIVATE_EXCLUSIVE) } as i64,
            -17
        );
        let mut out = [0xa5; METADATA_BYTES];
        assert_eq!(
            unsafe { file_info(b"x\0y".as_ptr() as u64, 3, 1, out.as_mut_ptr() as u64) },
            invalid()
        );
        assert_eq!(out, [0xa5; METADATA_BYTES]);
        assert_eq!(
            unsafe { path_query(99, 0, 0, out.as_mut_ptr() as u64, METADATA_BYTES as u64) },
            invalid()
        );
        assert_eq!(out, [0xa5; METADATA_BYTES]);
        let size = unsafe { path_query(CANONICAL_PATH, base, length, 0, 0) };
        assert!(size > 0);
        let mut text = vec![0xa5; size as usize];
        assert_eq!(
            unsafe { path_query(CANONICAL_PATH, base, length, text.as_mut_ptr() as u64, 1) },
            size
        );
        assert!(text.iter().all(|byte| *byte == 0xa5));
        assert_eq!(
            unsafe {
                path_query(
                    CANONICAL_PATH,
                    base,
                    length,
                    text.as_mut_ptr() as u64,
                    size as u64,
                )
            },
            size
        );
        assert_eq!(
            text,
            std::fs::canonicalize(&file).unwrap().as_os_str().as_bytes()
        );
    }
}
