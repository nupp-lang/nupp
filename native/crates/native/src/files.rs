//! ABI-v2 translation for the Rust filesystem provider.

use nupp_native_abi::{Arena, Handle, Status};
use nupp_native_files as filesystem;
use std::path::PathBuf;
#[cfg(feature = "files")]
use std::ptr;
use std::sync::{Arc, Mutex, OnceLock};
#[cfg(feature = "files")]
use std::time::Duration;
use std::time::{SystemTime, UNIX_EPOCH};

#[repr(C)]
#[derive(Clone, Copy)]
pub struct FilesSlice {
    pub data: *const u8,
    pub length: usize,
}

#[repr(C)]
pub struct FilesInfo {
    pub kind: u32,
    pub read_only: i32,
    pub size: u64,
    pub modified: f64,
}

enum Resource {
    File(Arc<filesystem::OpenFile>),
    #[cfg(feature = "files")]
    Transfer(Arc<filesystem::Transfer>),
}

fn resources() -> &'static Mutex<Arena<Resource>> {
    static RESOURCES: OnceLock<Mutex<Arena<Resource>>> = OnceLock::new();
    RESOURCES.get_or_init(|| Mutex::new(Arena::new()))
}

unsafe fn bytes<'a>(slice: FilesSlice, what: &str) -> Result<&'a [u8], i32> {
    super::input(slice.data, slice.length).map_err(|_| super::failed(Status::InvalidArgument, what))
}

unsafe fn text<'a>(slice: FilesSlice, what: &str) -> Result<&'a str, i32> {
    let value = unsafe { bytes(slice, what) }?;
    if value.contains(&0) {
        return Err(super::failed(
            Status::InvalidArgument,
            &format!("{what} contains an embedded NUL"),
        ));
    }
    std::str::from_utf8(value).map_err(|_| {
        super::failed(
            Status::InvalidArgument,
            &format!("{what} is not valid UTF-8"),
        )
    })
}

unsafe fn path(slice: FilesSlice, what: &str) -> Result<PathBuf, i32> {
    unsafe { text(slice, what) }.map(PathBuf::from)
}

fn io_failed(error: std::io::Error) -> i32 {
    super::failed(Status::Internal, &error.to_string())
}

fn store(value: Vec<u8>, output: *mut u64, what: &str) -> i32 {
    if output.is_null() {
        return super::failed(Status::InvalidArgument, what);
    }
    let handle = match super::store_bytes(value) {
        Ok(handle) => handle,
        Err(status) => return status,
    };
    // SAFETY: output was checked above.
    unsafe { output.write(handle) };
    Status::Ok.code()
}

fn file(raw: u64) -> Result<(Handle, Arc<filesystem::OpenFile>), i32> {
    let handle = Handle::from_raw(raw);
    let arena = resources()
        .lock()
        .map_err(|_| super::failed(Status::Internal, "file resource store is poisoned"))?;
    match arena.get(handle) {
        Ok(Resource::File(value)) => Ok((handle, Arc::clone(value))),
        #[cfg(feature = "files")]
        Ok(Resource::Transfer(_)) => Err(super::failed(
            Status::InvalidArgument,
            "file handle names a transfer",
        )),
        Err(status) => Err(super::failed(status, "file handle is stale")),
    }
}

#[cfg(feature = "files")]
fn transfer(raw: u64) -> Result<(Handle, Arc<filesystem::Transfer>), i32> {
    let handle = Handle::from_raw(raw);
    let arena = resources()
        .lock()
        .map_err(|_| super::failed(Status::Internal, "file resource store is poisoned"))?;
    match arena.get(handle) {
        Ok(Resource::Transfer(value)) => Ok((handle, Arc::clone(value))),
        Ok(Resource::File(_)) => Err(super::failed(
            Status::InvalidArgument,
            "file transfer handle names an open file",
        )),
        Err(status) => Err(super::failed(status, "file transfer handle is stale")),
    }
}

fn insert(resource: Resource, output: *mut u64, what: &str) -> i32 {
    if output.is_null() {
        return super::failed(Status::InvalidArgument, what);
    }
    let handle = match resources().lock() {
        Ok(mut arena) => match arena.insert(resource) {
            Ok(handle) => handle,
            Err(status) => return super::failed(status, "file handle capacity is exhausted"),
        },
        Err(_) => return super::failed(Status::Internal, "file resource store is poisoned"),
    };
    // SAFETY: output was checked above.
    unsafe { output.write(handle.raw()) };
    Status::Ok.code()
}

fn modified(value: Option<SystemTime>) -> f64 {
    let Some(value) = value else {
        return 0.0;
    };
    match value.duration_since(UNIX_EPOCH) {
        Ok(duration) => duration.as_secs_f64(),
        Err(error) => -error.duration().as_secs_f64(),
    }
}

#[unsafe(no_mangle)]
/// Describes a path.
///
/// # Safety
/// The path must remain readable and output must be writable for this call.
pub unsafe extern "C" fn nuppNativeV2FilesInfo(
    input: FilesSlice,
    follow: i32,
    output: *mut FilesInfo,
) -> i32 {
    if output.is_null() {
        return super::failed(Status::InvalidArgument, "file info output is null");
    }
    let path = match unsafe { path(input, "path") } {
        Ok(value) => value,
        Err(status) => return status,
    };
    let info = match filesystem::info(&path, follow != 0) {
        Ok(value) => value,
        Err(error) => return io_failed(error),
    };
    let kind = match info.kind {
        filesystem::FileKind::File => 1,
        filesystem::FileKind::Directory => 2,
        filesystem::FileKind::Other => 3,
        filesystem::FileKind::Symlink => 4,
    };
    // SAFETY: output was checked above.
    unsafe {
        output.write(FilesInfo {
            kind,
            read_only: i32::from(info.read_only),
            size: info.size,
            modified: modified(info.modified),
        })
    };
    Status::Ok.code()
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nuppNativeV2FilesReadLink(input: FilesSlice, output: *mut u64) -> i32 {
    let path = match unsafe { path(input, "path") } {
        Ok(value) => value,
        Err(status) => return status,
    };
    match filesystem::read_link(&path) {
        Ok(value) => store(value.into_bytes(), output, "link output is null"),
        Err(error) => io_failed(error),
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nuppNativeV2FilesCreateSymlink(
    target: FilesSlice,
    link: FilesSlice,
    directory: i32,
) -> i32 {
    let target = match unsafe { path(target, "symlink target") } {
        Ok(value) => value,
        Err(status) => return status,
    };
    let link = match unsafe { path(link, "symlink path") } {
        Ok(value) => value,
        Err(status) => return status,
    };
    filesystem::create_symlink(&target, &link, directory != 0)
        .map_or_else(io_failed, |()| Status::Ok.code())
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nuppNativeV2FilesSetReadOnly(input: FilesSlice, read_only: i32) -> i32 {
    let path = match unsafe { path(input, "path") } {
        Ok(value) => value,
        Err(status) => return status,
    };
    filesystem::set_read_only(&path, read_only != 0).map_or_else(io_failed, |()| Status::Ok.code())
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nuppNativeV2FilesCreateDirectory(input: FilesSlice) -> i32 {
    let path = match unsafe { path(input, "path") } {
        Ok(value) => value,
        Err(status) => return status,
    };
    filesystem::create_directory(&path).map_or_else(io_failed, |()| Status::Ok.code())
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nuppNativeV2FilesRemove(input: FilesSlice, recursive: i32) -> i32 {
    let path = match unsafe { path(input, "path") } {
        Ok(value) => value,
        Err(status) => return status,
    };
    filesystem::remove(&path, recursive != 0).map_or_else(io_failed, |()| Status::Ok.code())
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nuppNativeV2FilesRename(from: FilesSlice, to: FilesSlice) -> i32 {
    let from = match unsafe { path(from, "source path") } {
        Ok(value) => value,
        Err(status) => return status,
    };
    let to = match unsafe { path(to, "destination path") } {
        Ok(value) => value,
        Err(status) => return status,
    };
    filesystem::rename(&from, &to).map_or_else(io_failed, |()| Status::Ok.code())
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nuppNativeV2FilesList(input: FilesSlice, output: *mut u64) -> i32 {
    let path = match unsafe { path(input, "path") } {
        Ok(value) => value,
        Err(status) => return status,
    };
    let entries = match filesystem::list(&path) {
        Ok(value) => value,
        Err(error) => return io_failed(error),
    };
    let mut encoded = Vec::new();
    for entry in entries {
        encoded.push(match entry.kind {
            filesystem::FileKind::File => b'f',
            filesystem::FileKind::Directory => b'd',
            filesystem::FileKind::Symlink => b'l',
            filesystem::FileKind::Other => b'o',
        });
        encoded.extend_from_slice(entry.name.as_bytes());
        encoded.push(0);
    }
    store(encoded, output, "directory listing output is null")
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nuppNativeV2FilesGlob(input: FilesSlice, output: *mut u64) -> i32 {
    let pattern = match unsafe { text(input, "glob pattern") } {
        Ok(value) => value,
        Err(status) => return status,
    };
    let matches = match filesystem::glob(pattern) {
        Ok(value) => value,
        Err(error) => return io_failed(error),
    };
    let mut encoded = Vec::new();
    for value in matches {
        encoded.extend_from_slice(value.as_bytes());
        encoded.push(0);
    }
    store(encoded, output, "glob output is null")
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nuppNativeV2FilesCreateTemporary(
    directory: FilesSlice,
    prefix: FilesSlice,
    suffix: FilesSlice,
    as_directory: i32,
    output: *mut u64,
) -> i32 {
    let directory = match unsafe { text(directory, "temporary directory") } {
        Ok("") => None,
        Ok(value) => Some(PathBuf::from(value)),
        Err(status) => return status,
    };
    let prefix = match unsafe { text(prefix, "temporary prefix") } {
        Ok(value) => value,
        Err(status) => return status,
    };
    let suffix = match unsafe { text(suffix, "temporary suffix") } {
        Ok(value) => value,
        Err(status) => return status,
    };
    let kind = if as_directory != 0 {
        filesystem::TemporaryKind::Directory
    } else {
        filesystem::TemporaryKind::File
    };
    match filesystem::create_temporary(directory.as_deref(), prefix, suffix, kind) {
        Ok(value) => store(value.into_bytes(), output, "temporary path output is null"),
        Err(error) => io_failed(error),
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nuppNativeV2FilesCurrentDirectory(output: *mut u64) -> i32 {
    match filesystem::current_directory() {
        Ok(value) => store(
            value.into_bytes(),
            output,
            "working directory output is null",
        ),
        Err(error) => io_failed(error),
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nuppNativeV2FilesCanonicalize(input: FilesSlice, output: *mut u64) -> i32 {
    let path = match unsafe { path(input, "path") } {
        Ok(value) => value,
        Err(status) => return status,
    };
    match filesystem::canonicalize(&path) {
        Ok(value) => store(value.into_bytes(), output, "canonical path output is null"),
        Err(error) => io_failed(error),
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nuppNativeV2FilesUserFolder(which: u32, output: *mut u64) -> i32 {
    match filesystem::user_folder(which) {
        Ok(value) => store(value.into_bytes(), output, "user folder output is null"),
        Err(error) => io_failed(error),
    }
}

fn open_mode(value: u32) -> Result<filesystem::OpenMode, i32> {
    match value {
        0 => Ok(filesystem::OpenMode::Read),
        1 => Ok(filesystem::OpenMode::Write),
        2 => Ok(filesystem::OpenMode::Append),
        3 => Ok(filesystem::OpenMode::ReadWrite),
        4 => Ok(filesystem::OpenMode::ReadWriteTruncate),
        5 => Ok(filesystem::OpenMode::ReadAppend),
        _ => Err(super::failed(Status::InvalidArgument, "unknown file mode")),
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nuppNativeV2FileOpen(
    input: FilesSlice,
    mode: u32,
    output: *mut u64,
) -> i32 {
    let path = match unsafe { path(input, "path") } {
        Ok(value) => value,
        Err(status) => return status,
    };
    let mode = match open_mode(mode) {
        Ok(value) => value,
        Err(status) => return status,
    };
    let file = match filesystem::OpenFile::open(&path, mode) {
        Ok(value) => value,
        Err(error) => return io_failed(error),
    };
    insert(
        Resource::File(Arc::new(file)),
        output,
        "file handle output is null",
    )
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nuppNativeV2FileRead(
    raw: u64,
    output: *mut u8,
    capacity: usize,
    length: *mut usize,
) -> i32 {
    if length.is_null() || (capacity != 0 && output.is_null()) {
        return super::failed(Status::InvalidArgument, "file read output is null");
    }
    let (_, file) = match file(raw) {
        Ok(value) => value,
        Err(status) => return status,
    };
    // SAFETY: a zero-length slice may use a dangling pointer; otherwise output
    // was checked and the caller promises capacity writable bytes.
    let output = if capacity == 0 {
        &mut []
    } else {
        unsafe { std::slice::from_raw_parts_mut(output, capacity) }
    };
    let count = match file.read(output) {
        Ok(value) => value,
        Err(error) => return io_failed(error),
    };
    // SAFETY: length was checked above.
    unsafe { length.write(count) };
    Status::Ok.code()
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nuppNativeV2FileWrite(
    raw: u64,
    input_data: *const u8,
    input_length: usize,
    written: *mut usize,
) -> i32 {
    if written.is_null() {
        return super::failed(Status::InvalidArgument, "file write output is null");
    }
    let input = match super::input(input_data, input_length) {
        Ok(value) => value,
        Err(status) => return status,
    };
    let (_, file) = match file(raw) {
        Ok(value) => value,
        Err(status) => return status,
    };
    let count = match file.write(input) {
        Ok(value) => value,
        Err(error) => return io_failed(error),
    };
    // SAFETY: written was checked above.
    unsafe { written.write(count) };
    Status::Ok.code()
}

fn seek_origin(value: u32) -> Result<filesystem::SeekOrigin, i32> {
    match value {
        0 => Ok(filesystem::SeekOrigin::Start),
        1 => Ok(filesystem::SeekOrigin::Current),
        2 => Ok(filesystem::SeekOrigin::End),
        _ => Err(super::failed(
            Status::InvalidArgument,
            "unknown seek origin",
        )),
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nuppNativeV2FileSeek(
    raw: u64,
    offset: i64,
    origin: u32,
    output: *mut i64,
) -> i32 {
    if output.is_null() {
        return super::failed(Status::InvalidArgument, "file seek output is null");
    }
    let origin = match seek_origin(origin) {
        Ok(value) => value,
        Err(status) => return status,
    };
    let (_, file) = match file(raw) {
        Ok(value) => value,
        Err(status) => return status,
    };
    let position = match file.seek(offset, origin) {
        Ok(value) => match i64::try_from(value) {
            Ok(value) => value,
            Err(_) => return super::failed(Status::Capacity, "file position exceeds int64"),
        },
        Err(error) => return io_failed(error),
    };
    // SAFETY: output was checked above.
    unsafe { output.write(position) };
    Status::Ok.code()
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nuppNativeV2FileSize(raw: u64, output: *mut i64) -> i32 {
    if output.is_null() {
        return super::failed(Status::InvalidArgument, "file size output is null");
    }
    let (_, file) = match file(raw) {
        Ok(value) => value,
        Err(status) => return status,
    };
    let size = match file.size() {
        Ok(value) => match i64::try_from(value) {
            Ok(value) => value,
            Err(_) => return super::failed(Status::Capacity, "file size exceeds int64"),
        },
        Err(error) => return io_failed(error),
    };
    // SAFETY: output was checked above.
    unsafe { output.write(size) };
    Status::Ok.code()
}

#[unsafe(no_mangle)]
pub extern "C" fn nuppNativeV2FileFlush(raw: u64) -> i32 {
    let (_, file) = match file(raw) {
        Ok(value) => value,
        Err(status) => return status,
    };
    file.flush().map_or_else(io_failed, |()| Status::Ok.code())
}

#[unsafe(no_mangle)]
pub extern "C" fn nuppNativeV2FileRelease(raw: u64) -> i32 {
    let (handle, _) = match file(raw) {
        Ok(value) => value,
        Err(status) => return status,
    };
    match resources().lock() {
        Ok(mut arena) => match arena.remove(handle) {
            Ok(Resource::File(_)) => Status::Ok.code(),
            #[cfg(feature = "files")]
            Ok(Resource::Transfer(_)) => {
                super::failed(Status::InvalidArgument, "file handle names a transfer")
            }
            Err(status) => super::failed(status, "file handle is stale"),
        },
        Err(_) => super::failed(Status::Internal, "file resource store is poisoned"),
    }
}

#[cfg(feature = "files")]
fn write_mode(value: u32) -> Result<filesystem::WriteMode, i32> {
    match value {
        0 => Ok(filesystem::WriteMode::Replace),
        1 => Ok(filesystem::WriteMode::Append),
        2 => Ok(filesystem::WriteMode::Atomic),
        _ => Err(super::failed(
            Status::InvalidArgument,
            "unknown whole-file write mode",
        )),
    }
}

#[cfg(feature = "files")]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn nuppNativeV2FilesTransferSubmitRead(
    input: FilesSlice,
    output: *mut u64,
) -> i32 {
    let path = match unsafe { path(input, "path") } {
        Ok(value) => value,
        Err(status) => return status,
    };
    let transfer = match filesystem::submit_read(path) {
        Ok(value) => value,
        Err(error) => return io_failed(error),
    };
    insert(
        Resource::Transfer(transfer),
        output,
        "file transfer output is null",
    )
}

#[cfg(feature = "files")]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn nuppNativeV2FilesTransferSubmitWrite(
    path_input: FilesSlice,
    contents: FilesSlice,
    mode: u32,
    output: *mut u64,
) -> i32 {
    let path = match unsafe { path(path_input, "path") } {
        Ok(value) => value,
        Err(status) => return status,
    };
    let contents = match unsafe { bytes(contents, "file contents") } {
        Ok(value) => value.to_vec(),
        Err(status) => return status,
    };
    let mode = match write_mode(mode) {
        Ok(value) => value,
        Err(status) => return status,
    };
    let transfer = match filesystem::submit_write(path, contents, mode) {
        Ok(value) => value,
        Err(error) => return io_failed(error),
    };
    insert(
        Resource::Transfer(transfer),
        output,
        "file transfer output is null",
    )
}

#[cfg(feature = "files")]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn nuppNativeV2FilesTransferSubmitCopy(
    from: FilesSlice,
    to: FilesSlice,
    output: *mut u64,
) -> i32 {
    let from = match unsafe { path(from, "source path") } {
        Ok(value) => value,
        Err(status) => return status,
    };
    let to = match unsafe { path(to, "destination path") } {
        Ok(value) => value,
        Err(status) => return status,
    };
    let transfer = match filesystem::submit_copy(from, to) {
        Ok(value) => value,
        Err(error) => return io_failed(error),
    };
    insert(
        Resource::Transfer(transfer),
        output,
        "file transfer output is null",
    )
}

#[cfg(feature = "files")]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn nuppNativeV2FilesTransferStatus(raw: u64, output: *mut u32) -> i32 {
    if output.is_null() {
        return super::failed(
            Status::InvalidArgument,
            "file transfer status output is null",
        );
    }
    let (_, transfer) = match transfer(raw) {
        Ok(value) => value,
        Err(status) => return status,
    };
    let status = match transfer.status() {
        filesystem::TransferStatus::Pending => 0,
        filesystem::TransferStatus::Ready => 1,
        filesystem::TransferStatus::Failed => {
            if let Some(error) = transfer.error() {
                super::remember_error(&error);
            }
            2
        }
        filesystem::TransferStatus::Canceled => 3,
    };
    // SAFETY: output was checked above.
    unsafe { output.write(status) };
    Status::Ok.code()
}

#[cfg(feature = "files")]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn nuppNativeV2FilesTransferTakeBytes(raw: u64, output: *mut u64) -> i32 {
    if output.is_null() {
        return super::failed(
            Status::InvalidArgument,
            "file transfer bytes output is null",
        );
    }
    let (_, transfer) = match transfer(raw) {
        Ok(value) => value,
        Err(status) => return status,
    };
    let value = match transfer.take_bytes() {
        Ok(Some(value)) => value.into_vec(),
        Ok(None) => {
            return super::failed(Status::InvalidArgument, "file transfer has no byte result");
        }
        Err(error) => return io_failed(error),
    };
    store(value, output, "file transfer bytes output is null")
}

#[cfg(feature = "files")]
#[unsafe(no_mangle)]
pub extern "C" fn nuppNativeV2FilesTransferCancel(raw: u64) -> i32 {
    let (_, transfer) = match transfer(raw) {
        Ok(value) => value,
        Err(status) => return status,
    };
    transfer.cancel();
    Status::Ok.code()
}

#[cfg(feature = "files")]
#[unsafe(no_mangle)]
pub extern "C" fn nuppNativeV2FilesTransferRelease(raw: u64) -> i32 {
    let (handle, _) = match transfer(raw) {
        Ok(value) => value,
        Err(status) => return status,
    };
    match resources().lock() {
        Ok(mut arena) => match arena.remove(handle) {
            Ok(Resource::Transfer(_)) => Status::Ok.code(),
            Ok(Resource::File(_)) => super::failed(
                Status::InvalidArgument,
                "file transfer handle names an open file",
            ),
            Err(status) => super::failed(status, "file transfer handle is stale"),
        },
        Err(_) => super::failed(Status::Internal, "file resource store is poisoned"),
    }
}

#[cfg(feature = "files")]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn nuppNativeV2FilesTransferPoll(output: *mut usize) -> i32 {
    if output.is_null() {
        return super::failed(Status::InvalidArgument, "file transfer poll output is null");
    }
    // SAFETY: output was checked above.
    unsafe { ptr::write(output, filesystem::transfer_poll()) };
    Status::Ok.code()
}

#[cfg(feature = "files")]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn nuppNativeV2FilesTransferWait(timeout_ms: u64, output: *mut usize) -> i32 {
    if output.is_null() {
        return super::failed(Status::InvalidArgument, "file transfer wait output is null");
    }
    let count = filesystem::transfer_wait(Duration::from_millis(timeout_ms));
    // SAFETY: output was checked above.
    unsafe { ptr::write(output, count) };
    Status::Ok.code()
}

#[cfg(feature = "files")]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn nuppNativeV2FilesTransferPending(output: *mut usize) -> i32 {
    if output.is_null() {
        return super::failed(
            Status::InvalidArgument,
            "file transfer pending output is null",
        );
    }
    // SAFETY: output was checked above.
    unsafe { ptr::write(output, filesystem::transfer_pending()) };
    Status::Ok.code()
}

#[cfg(all(test, feature = "files"))]
mod tests {
    use super::*;

    #[test]
    fn arena_rejects_wrong_kind_and_stale_handles() {
        let root = std::env::temp_dir().join(format!("nupp-files-facade-{}", std::process::id()));
        std::fs::write(&root, b"value").unwrap();
        let value =
            Arc::new(filesystem::OpenFile::open(&root, filesystem::OpenMode::Read).unwrap());
        let handle = resources()
            .lock()
            .unwrap()
            .insert(Resource::File(value))
            .unwrap();
        assert!(transfer(handle.raw()).is_err());
        let _ = resources().lock().unwrap().remove(handle).unwrap();
        assert!(file(handle.raw()).is_err());
        std::fs::remove_file(root).unwrap();
    }
}
