//! The public names for the file provider, forwarding into the C that implements
//! it.
//!
//! Nothing here is an implementation. `c/files.c` and the two files beside it are
//! the provider; these are the names the ABI promises, defined on this side
//! because Cargo builds a shared library with an export list naming this crate's
//! symbols and nothing else. A C symbol linked into that library is not on the
//! list and is dropped, exported by neither the library nor anything reading it.
//!
//! Every one of these goes when the Rust half does, and the C entry points below
//! take the public names directly.

use std::ffi::{c_char, c_void};

forward! {
    nuppFilesInfo = nuppcFilesInfo(
        data: *const u8, length: usize, follow: bool, out: *mut c_void
    ) -> bool;
    nuppFilesReadLink = nuppcFilesReadLink(data: *const u8, length: usize) -> *mut c_void;
    nuppFilesGlob = nuppcFilesGlob(data: *const u8, length: usize) -> *mut c_void;
    nuppFilesCreateSymlink = nuppcFilesCreateSymlink(
        target: *const u8, target_length: usize,
        link: *const u8, link_length: usize,
        directory: bool,
    ) -> bool;
    nuppFilesSetReadOnly = nuppcFilesSetReadOnly(
        data: *const u8, length: usize, read_only: bool
    ) -> bool;
    nuppFilesCreateDirectory = nuppcFilesCreateDirectory(
        data: *const u8, length: usize
    ) -> bool;
    nuppFilesRemove = nuppcFilesRemove(
        data: *const u8, length: usize, recursive: bool
    ) -> bool;
    nuppFilesRename = nuppcFilesRename(
        from: *const u8, from_length: usize, to: *const u8, to_length: usize
    ) -> bool;
    nuppFilesList = nuppcFilesList(data: *const u8, length: usize) -> *mut c_void;
    nuppFilesCreateTemporary = nuppcFilesCreateTemporary(
        directory: *const u8, directory_length: usize,
        prefix: *const u8, prefix_length: usize,
        suffix: *const u8, suffix_length: usize,
        as_directory: bool,
    ) -> *mut c_void;
    nuppFilesCurrentDirectory = nuppcFilesCurrentDirectory() -> *mut c_void;
    nuppFilesUserFolder = nuppcFilesUserFolder(which: u32) -> *mut c_void;

    nuppFileOpen = nuppcFileOpen(data: *const u8, length: usize, mode: u32) -> *mut c_void;
    nuppFileRead = nuppcFileRead(file: *mut c_void, into: *mut u8, length: usize) -> i64;
    nuppFileWrite = nuppcFileWrite(
        file: *mut c_void, from: *const u8, length: usize
    ) -> i64;
    nuppFileSeek = nuppcFileSeek(file: *mut c_void, offset: i64, whence: u32) -> i64;
    nuppFileSize = nuppcFileSize(file: *mut c_void) -> i64;
    nuppFileFlush = nuppcFileFlush(file: *mut c_void) -> bool;
    nuppFileClose = nuppcFileClose(file: *mut c_void) -> bool;

    nuppFsSubmitRead = nuppcFsSubmitRead(data: *const u8, length: usize) -> *mut c_void;
    nuppFsSubmitWrite = nuppcFsSubmitWrite(
        data: *const u8, length: usize,
        bytes: *const u8, bytes_length: usize,
        mode: u32,
    ) -> *mut c_void;
    nuppFsSubmitCopy = nuppcFsSubmitCopy(
        from: *const u8, from_length: usize, to: *const u8, to_length: usize
    ) -> *mut c_void;
    nuppFsStatus = nuppcFsStatus(request: *const c_void) -> i32;
    nuppFsData = nuppcFsData(request: *const c_void) -> *const u8;
    nuppFsLength = nuppcFsLength(request: *const c_void) -> usize;
    nuppFsError = nuppcFsError(request: *const c_void) -> *const c_char;
    nuppFsCancel = nuppcFsCancel(request: *mut c_void) -> bool;
    nuppFsDestroy = nuppcFsDestroy(request: *mut c_void) -> ();
    nuppFsPoll = nuppcFsPoll() -> usize;
    nuppFsWait = nuppcFsWait(milliseconds: u64) -> usize;
    nuppFsPending = nuppcFsPending() -> usize;
}
