//! Safe filesystem mechanisms for Nupp's native provider.
//!
//! Filesystem operations are expressed in Rust-owned types. Immediate calls run
//! on their caller's thread; whole-file transfers use the process-wide Tokio
//! executor's blocking pool and never enter Lua.

#![forbid(unsafe_op_in_unsafe_fn)]

mod glob;
#[cfg(feature = "lane")]
mod lane;
mod platform;

pub use glob::{MAX_WALK_DEPTH, expand as glob};
#[cfg(feature = "lane")]
pub use lane::{
    FileLane, MAX_BYTES, MAX_REQUEST_BYTES, MAX_REQUESTS, Transfer, TransferStatus, WriteMode,
    submit_copy, submit_read, submit_write, transfer_pending, transfer_poll, transfer_wait,
};

use std::ffi::OsString;
use std::fs::{self, File, OpenOptions};
use std::io::{self, Read, Seek, SeekFrom, Write};
use std::path::{Path, PathBuf};
use std::sync::Mutex;
use std::time::SystemTime;

const TEMPORARY_ATTEMPTS: usize = 64;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum FileKind {
    File,
    Directory,
    Other,
    Symlink,
}

#[derive(Clone, Debug)]
pub struct FileInfo {
    pub kind: FileKind,
    pub read_only: bool,
    pub size: u64,
    pub modified: Option<SystemTime>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct DirectoryEntry {
    pub name: String,
    pub kind: FileKind,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum TemporaryKind {
    File,
    Directory,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum OpenMode {
    Read,
    Write,
    Append,
    ReadWrite,
    ReadWriteTruncate,
    ReadAppend,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum SeekOrigin {
    Start,
    Current,
    End,
}

struct FileState {
    file: File,
    position: u64,
    appending: bool,
}

/// One serialized file cursor. ABI facades may wrap this in a generational
/// handle without exposing an operating-system descriptor or a Rust pointer.
pub struct OpenFile {
    state: Mutex<FileState>,
}

impl OpenFile {
    pub fn open(path: &Path, mode: OpenMode) -> io::Result<Self> {
        let mut options = OpenOptions::new();
        let appending = matches!(mode, OpenMode::Append | OpenMode::ReadAppend);
        match mode {
            OpenMode::Read => options.read(true),
            OpenMode::Write => options.write(true).create(true).truncate(true),
            OpenMode::Append => options.write(true).append(true).create(true),
            OpenMode::ReadWrite => options.read(true).write(true),
            OpenMode::ReadWriteTruncate => {
                options.read(true).write(true).create(true).truncate(true)
            }
            OpenMode::ReadAppend => options.read(true).append(true).create(true),
        };
        Ok(Self {
            state: Mutex::new(FileState {
                file: options.open(path)?,
                position: 0,
                appending,
            }),
        })
    }

    pub fn read(&self, output: &mut [u8]) -> io::Result<usize> {
        let mut state = self.state.lock().unwrap_or_else(|error| error.into_inner());
        let position = state.position;
        state.file.seek(SeekFrom::Start(position))?;
        let count = state.file.read(output)?;
        state.position = state.position.saturating_add(count as u64);
        Ok(count)
    }

    pub fn write(&self, input: &[u8]) -> io::Result<usize> {
        let mut state = self.state.lock().unwrap_or_else(|error| error.into_inner());
        let appending = state.appending;
        if !appending {
            let position = state.position;
            state.file.seek(SeekFrom::Start(position))?;
        }
        let mut written = 0;
        while written < input.len() {
            let count = state.file.write(&input[written..])?;
            if count == 0 {
                return Err(io::Error::new(
                    io::ErrorKind::WriteZero,
                    "failed to write the complete file buffer",
                ));
            }
            written += count;
            if !appending {
                state.position = state.position.saturating_add(count as u64);
            }
        }
        if appending {
            // Append mode chooses the then-current end whatever the logical
            // cursor said. Ask the descriptor where the write landed rather
            // than incrementing a cursor that may have started at zero.
            state.position = state.file.stream_position()?;
        }
        Ok(written)
    }

    pub fn seek(&self, offset: i64, origin: SeekOrigin) -> io::Result<u64> {
        let mut state = self.state.lock().unwrap_or_else(|error| error.into_inner());
        let base = match origin {
            SeekOrigin::Start => 0,
            SeekOrigin::Current => state.position,
            SeekOrigin::End => state.file.metadata()?.len(),
        };
        state.position = if offset < 0 {
            base.saturating_sub(offset.unsigned_abs())
        } else {
            base.saturating_add(offset as u64)
        };
        Ok(state.position)
    }

    pub fn position(&self) -> u64 {
        self.state
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .position
    }

    pub fn size(&self) -> io::Result<u64> {
        self.state
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .file
            .metadata()
            .map(|metadata| metadata.len())
    }

    /// Flushes language-side buffering. `std::fs::File` is unbuffered, so this
    /// deliberately does not turn the public flush into an fsync operation.
    pub fn flush(&self) -> io::Result<()> {
        self.state
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .file
            .flush()
    }
}

pub fn info(path: &Path, follow: bool) -> io::Result<FileInfo> {
    let metadata = if follow {
        fs::metadata(path)?
    } else {
        fs::symlink_metadata(path)?
    };
    let file_type = metadata.file_type();
    let kind = if file_type.is_symlink() {
        FileKind::Symlink
    } else if file_type.is_file() {
        FileKind::File
    } else if file_type.is_dir() {
        FileKind::Directory
    } else {
        FileKind::Other
    };
    Ok(FileInfo {
        kind,
        read_only: platform::read_only(&metadata.permissions()),
        size: metadata.len(),
        modified: metadata.modified().ok(),
    })
}

pub fn read_link(path: &Path) -> io::Result<String> {
    path_text(fs::read_link(path)?)
}

pub fn create_symlink(target: &Path, link: &Path, directory: bool) -> io::Result<()> {
    #[cfg(windows)]
    {
        if directory {
            std::os::windows::fs::symlink_dir(target, link)
        } else {
            std::os::windows::fs::symlink_file(target, link)
        }
    }
    #[cfg(not(windows))]
    {
        let _ = directory;
        std::os::unix::fs::symlink(target, link)
    }
}

pub fn set_read_only(path: &Path, read_only: bool) -> io::Result<()> {
    #[cfg(windows)]
    {
        // `File::open` requests read access, but `File::set_permissions` needs
        // FILE_WRITE_ATTRIBUTES on Windows. Set the path attribute directly
        // so both enabling and clearing read-only work through the public API.
        let permissions = fs::metadata(path)?.permissions();
        return platform::set_path_read_only(path, permissions, read_only);
    }
    #[cfg(not(windows))]
    match File::open(path) {
        Ok(file) => {
            let permissions = file.metadata()?.permissions();
            platform::set_read_only(&file, permissions, read_only)
        }
        Err(_) => {
            let permissions = fs::metadata(path)?.permissions();
            platform::set_path_read_only(path, permissions, read_only)
        }
    }
}

pub fn create_directory(path: &Path) -> io::Result<()> {
    if path.as_os_str().is_empty() {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            "the directory name is empty",
        ));
    }
    fs::create_dir_all(path)
}

pub fn list(path: &Path) -> io::Result<Vec<DirectoryEntry>> {
    fs::read_dir(path)?
        .map(|entry| {
            let entry = entry?;
            let name = entry.file_name().into_string().map_err(|_| {
                io::Error::new(
                    io::ErrorKind::InvalidData,
                    "directory entry name is not valid UTF-8",
                )
            })?;
            let file_type = entry.file_type()?;
            let kind = if file_type.is_symlink() {
                FileKind::Symlink
            } else if file_type.is_dir() {
                FileKind::Directory
            } else if file_type.is_file() {
                FileKind::File
            } else {
                FileKind::Other
            };
            Ok(DirectoryEntry { name, kind })
        })
        .collect()
}

pub fn remove(path: &Path, recursive: bool) -> io::Result<()> {
    let metadata = fs::symlink_metadata(path)?;
    if !metadata.file_type().is_dir() {
        return fs::remove_file(path);
    }
    if !recursive {
        return fs::remove_dir(path);
    }
    remove_tree(path, glob::MAX_WALK_DEPTH)
}

fn remove_tree(path: &Path, depth: usize) -> io::Result<()> {
    if depth == 0 {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            format!(
                "{}: the directory tree is deeper than {} levels",
                path.display(),
                glob::MAX_WALK_DEPTH
            ),
        ));
    }
    for entry in fs::read_dir(path)? {
        let entry = entry?;
        if entry.file_type()?.is_dir() {
            remove_tree(&entry.path(), depth - 1)?;
        } else {
            fs::remove_file(entry.path())?;
        }
    }
    fs::remove_dir(path)
}

pub fn rename(from: &Path, to: &Path) -> io::Result<()> {
    platform::replace(from, to)
}

pub fn create_temporary(
    directory: Option<&Path>,
    prefix: &str,
    suffix: &str,
    kind: TemporaryKind,
) -> io::Result<String> {
    let root = directory.map_or_else(std::env::temp_dir, Path::to_path_buf);
    let mut collision = None;
    for _ in 0..TEMPORARY_ATTEMPTS {
        let mut stamp = [0u8; 8];
        getrandom::fill(&mut stamp).map_err(|error| {
            io::Error::other(format!("cannot create a temporary name: {error}"))
        })?;
        let candidate = root.join(format!(
            "{prefix}{:016x}{suffix}",
            u64::from_le_bytes(stamp)
        ));
        let made = match kind {
            TemporaryKind::File => platform::create_private_file(&candidate).map(drop),
            TemporaryKind::Directory => platform::create_private_directory(&candidate),
        };
        match made {
            Ok(()) => return path_text(candidate),
            Err(error) if error.kind() == io::ErrorKind::AlreadyExists => collision = Some(error),
            Err(error) => return Err(error),
        }
    }
    Err(collision.unwrap_or_else(|| {
        io::Error::new(
            io::ErrorKind::AlreadyExists,
            "no unused temporary name was found",
        )
    }))
}

pub fn current_directory() -> io::Result<String> {
    path_text(std::env::current_dir()?)
}

pub fn canonicalize(path: &Path) -> io::Result<String> {
    path_text(fs::canonicalize(path)?)
}

pub fn user_folder(which: u32) -> io::Result<String> {
    let home = std::env::var_os(if cfg!(windows) { "USERPROFILE" } else { "HOME" })
        .filter(|value| !value.is_empty())
        .map(PathBuf::from)
        .ok_or_else(|| io::Error::new(io::ErrorKind::NotFound, "the home directory is not set"))?;
    if which == 0 {
        return path_text(home);
    }
    let (variable, macos, other) = match which {
        1 => ("XDG_DOCUMENTS_DIR", "Documents", "Documents"),
        2 => ("XDG_DOWNLOAD_DIR", "Downloads", "Downloads"),
        3 => ("XDG_DESKTOP_DIR", "Desktop", "Desktop"),
        4 => ("XDG_PICTURES_DIR", "Pictures", "Pictures"),
        5 => ("XDG_MUSIC_DIR", "Music", "Music"),
        6 => ("XDG_VIDEOS_DIR", "Movies", "Videos"),
        _ => {
            return Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                "unknown user folder",
            ));
        }
    };
    let configured = if cfg!(any(windows, target_os = "macos")) {
        None
    } else {
        std::env::var_os(variable).filter(|value| !value.is_empty())
    };
    let folder = configured.map_or_else(
        || {
            home.join(if cfg!(target_os = "macos") {
                macos
            } else {
                other
            })
        },
        PathBuf::from,
    );
    if !folder.is_dir() {
        return Err(io::Error::new(
            io::ErrorKind::NotFound,
            "the platform has no such folder",
        ));
    }
    path_text(folder)
}

fn path_text(path: PathBuf) -> io::Result<String> {
    let mut text = path.into_os_string().into_string().map_err(|_: OsString| {
        io::Error::new(io::ErrorKind::InvalidData, "path result is not valid UTF-8")
    })?;
    if cfg!(windows) {
        text = text.replace('\\', "/");
    }
    Ok(text)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn root(name: &str) -> PathBuf {
        let mut random = [0u8; 8];
        getrandom::fill(&mut random).unwrap();
        let path = std::env::temp_dir().join(format!(
            "nupp-files-{name}-{:016x}",
            u64::from_le_bytes(random)
        ));
        fs::create_dir_all(&path).unwrap();
        path
    }

    #[test]
    fn metadata_listing_links_and_removal_keep_entry_identity() {
        let root = root("immediate");
        create_directory(&root.join("nested/deep")).unwrap();
        fs::write(root.join("nested/file.txt"), b"value").unwrap();
        create_symlink(
            &root.join("nested/file.txt"),
            &root.join("nested/link"),
            false,
        )
        .unwrap();
        assert_eq!(
            info(&root.join("nested/link"), false).unwrap().kind,
            FileKind::Symlink
        );
        assert_eq!(
            info(&root.join("nested/link"), true).unwrap().kind,
            FileKind::File
        );
        let entries = list(&root.join("nested")).unwrap();
        assert!(
            entries
                .iter()
                .any(|entry| entry.name == "link" && entry.kind == FileKind::Symlink)
        );
        remove(&root.join("nested"), true).unwrap();
        assert!(!root.join("nested").exists());
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn open_file_owns_a_clamped_serial_cursor() {
        let root = root("cursor");
        let path = root.join("value.bin");
        fs::write(&path, b"hello world").unwrap();
        let file = OpenFile::open(&path, OpenMode::ReadWrite).unwrap();
        let mut first = [0u8; 5];
        assert_eq!(file.read(&mut first).unwrap(), 5);
        assert_eq!(&first, b"hello");
        assert_eq!(file.seek(-100, SeekOrigin::Current).unwrap(), 0);
        assert_eq!(file.seek(-1, SeekOrigin::End).unwrap(), 10);
        let mut last = [0u8; 2];
        assert_eq!(file.read(&mut last).unwrap(), 1);
        assert_eq!(last[0], b'd');
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn append_cursor_reports_the_end_where_the_write_landed() {
        let root = root("append-cursor");
        let path = root.join("value.bin");
        fs::write(&path, b"prefix").unwrap();
        let file = OpenFile::open(&path, OpenMode::ReadAppend).unwrap();
        assert_eq!(file.position(), 0);
        assert_eq!(file.write(b":body").unwrap(), 5);
        assert_eq!(file.position(), 11);
        assert_eq!(file.seek(-4, SeekOrigin::Current).unwrap(), 7);
        let mut tail = [0u8; 4];
        assert_eq!(file.read(&mut tail).unwrap(), 4);
        assert_eq!(&tail, b"body");
        file.flush().unwrap();
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn temporaries_are_created_with_the_requested_shape() {
        let root = root("temporary");
        let file = create_temporary(Some(&root), "before-", ".tmp", TemporaryKind::File).unwrap();
        let directory =
            create_temporary(Some(&root), "directory-", "", TemporaryKind::Directory).unwrap();
        assert!(Path::new(&file).is_file());
        assert!(Path::new(&directory).is_dir());
        assert!(file.contains("before-") && file.ends_with(".tmp"));
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn read_only_attribute_can_be_set_and_cleared() {
        let root = root("read-only");
        let path = root.join("value.txt");
        fs::write(&path, b"value").unwrap();

        set_read_only(&path, true).unwrap();
        assert!(info(&path, true).unwrap().read_only);
        set_read_only(&path, false).unwrap();
        assert!(!info(&path, true).unwrap().read_only);

        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn path_case_follows_the_filesystem_without_losing_entry_spelling() {
        let root = root("path-case");
        let exact = root.join("MixedCase.txt");
        let alternate = root.join("mixedcase.txt");
        fs::write(&exact, b"exact").unwrap();

        let folds_case = fs::metadata(&alternate).is_ok();
        assert_eq!(info(&alternate, true).is_ok(), folds_case);
        assert!(
            list(&root)
                .unwrap()
                .iter()
                .any(|entry| entry.name == "MixedCase.txt")
        );

        if folds_case {
            assert_eq!(
                canonicalize(&exact).unwrap(),
                canonicalize(&alternate).unwrap()
            );
            assert_eq!(fs::read(&alternate).unwrap(), b"exact");
        } else {
            fs::write(&alternate, b"alternate").unwrap();
            let entries = list(&root).unwrap();
            assert!(entries.iter().any(|entry| entry.name == "MixedCase.txt"));
            assert!(entries.iter().any(|entry| entry.name == "mixedcase.txt"));
            assert_ne!(
                canonicalize(&exact).unwrap(),
                canonicalize(&alternate).unwrap()
            );
        }

        fs::remove_dir_all(root).unwrap();
    }
}
