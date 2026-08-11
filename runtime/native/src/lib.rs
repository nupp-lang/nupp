//! Feature-gated native implementation for `nupp.data` and `nupp.io`.

use std::cell::RefCell;
use std::ffi::{c_char, CString};
use std::ptr;
#[cfg(any(
    feature = "path",
    feature = "uri",
    feature = "sha256",
    feature = "files"
))]
use std::slice;
#[cfg(any(feature = "path", feature = "uri", feature = "files"))]
use std::str;

thread_local! {
    static LAST_ERROR: RefCell<CString> =
        RefCell::new(CString::new("no error").expect("static text has no NUL"));
}

#[cfg(any(
    feature = "path",
    feature = "uri",
    feature = "files",
    feature = "process"
))]
fn set_error(error: impl ToString) {
    let message = error.to_string().replace('\0', "\\0");
    LAST_ERROR.with(|slot| {
        *slot.borrow_mut() = CString::new(message).expect("NUL bytes were replaced");
    });
}

#[no_mangle]
pub extern "C" fn nuppNativeError() -> *const c_char {
    LAST_ERROR.with(|slot| slot.borrow().as_ptr())
}

pub struct NuppBytes {
    bytes: Box<[u8]>,
}

#[cfg(any(feature = "path", feature = "files"))]
fn output_bytes(bytes: Vec<u8>) -> *mut NuppBytes {
    Box::into_raw(Box::new(NuppBytes {
        bytes: bytes.into_boxed_slice(),
    }))
}

#[no_mangle]
pub unsafe extern "C" fn nuppBytesData(bytes: *const NuppBytes) -> *const u8 {
    if bytes.is_null() {
        ptr::null()
    } else {
        unsafe { &*bytes }.bytes.as_ptr()
    }
}

#[no_mangle]
pub unsafe extern "C" fn nuppBytesLength(bytes: *const NuppBytes) -> usize {
    if bytes.is_null() {
        0
    } else {
        unsafe { &*bytes }.bytes.len()
    }
}

#[no_mangle]
pub unsafe extern "C" fn nuppBytesDestroy(bytes: *mut NuppBytes) {
    if !bytes.is_null() {
        drop(unsafe { Box::from_raw(bytes) });
    }
}

#[cfg(any(feature = "path", feature = "uri", feature = "files"))]
unsafe fn text<'a>(data: *const u8, length: usize, what: &str) -> Result<&'a str, String> {
    if data.is_null() && length != 0 {
        return Err(format!("{what} is null"));
    }
    let bytes = if length == 0 {
        &[]
    } else {
        unsafe { slice::from_raw_parts(data, length) }
    };
    let value = str::from_utf8(bytes).map_err(|_| format!("{what} is not valid UTF-8"))?;
    if value.as_bytes().contains(&0) {
        return Err(format!("{what} contains a NUL byte"));
    }
    Ok(value)
}

#[cfg(feature = "path")]
mod path {
    use super::*;
    use camino::{absolute_utf8, Utf8Component, Utf8Path, Utf8PathBuf};
    use path_clean::PathClean;
    use pathdiff::diff_utf8_paths;

    #[repr(C)]
    pub struct StringView {
        data: *const u8,
        length: usize,
    }

    unsafe fn input<'a>(data: *const u8, length: usize) -> Result<&'a Utf8Path, String> {
        Ok(Utf8Path::new(unsafe { text(data, length, "path") }?))
    }
    fn output(path: impl Into<Utf8PathBuf>) -> *mut NuppBytes {
        output_bytes(path.into().into_string().into_bytes())
    }
    fn fail(error: impl ToString) -> *mut NuppBytes {
        set_error(error);
        ptr::null_mut()
    }
    fn converted(path: std::path::PathBuf) -> Result<Utf8PathBuf, String> {
        Utf8PathBuf::from_path_buf(path).map_err(|_| "path result is not valid UTF-8".to_owned())
    }

    #[no_mangle]
    pub unsafe extern "C" fn nuppPathJoin(
        parts: *const StringView,
        count: usize,
    ) -> *mut NuppBytes {
        if parts.is_null() && count != 0 {
            return fail("path parts are null");
        }
        let parts = if count == 0 {
            &[]
        } else {
            unsafe { slice::from_raw_parts(parts, count) }
        };
        let mut joined = Utf8PathBuf::new();
        for part in parts {
            match unsafe { input(part.data, part.length) } {
                Ok(part) => joined.push(part),
                Err(e) => return fail(e),
            }
        }
        output(joined)
    }
    #[no_mangle]
    pub unsafe extern "C" fn nuppPathNormalize(data: *const u8, length: usize) -> *mut NuppBytes {
        let p = match unsafe { input(data, length) } {
            Ok(v) => v,
            Err(e) => return fail(e),
        };
        match converted(p.as_std_path().clean()) {
            Ok(v) => output(v),
            Err(e) => fail(e),
        }
    }
    #[no_mangle]
    pub unsafe extern "C" fn nuppPathAbsolute(data: *const u8, length: usize) -> *mut NuppBytes {
        let p = match unsafe { input(data, length) } {
            Ok(v) => v,
            Err(e) => return fail(e),
        };
        match absolute_utf8(p) {
            Ok(v) => output(v),
            Err(e) => fail(e),
        }
    }
    #[no_mangle]
    pub unsafe extern "C" fn nuppPathCanonicalize(
        data: *const u8,
        length: usize,
    ) -> *mut NuppBytes {
        let p = match unsafe { input(data, length) } {
            Ok(v) => v,
            Err(e) => return fail(e),
        };
        match p.canonicalize_utf8() {
            Ok(v) => output(v),
            Err(e) => fail(e),
        }
    }
    #[no_mangle]
    pub unsafe extern "C" fn nuppPathRelative(
        data: *const u8,
        length: usize,
        base: *const u8,
        base_length: usize,
    ) -> *mut NuppBytes {
        let p = match unsafe { input(data, length) } {
            Ok(v) => v,
            Err(e) => return fail(e),
        };
        let b = match unsafe { input(base, base_length) } {
            Ok(v) => v,
            Err(e) => return fail(e),
        };
        match diff_utf8_paths(p, b) {
            Some(v) => output(v),
            None => fail("paths do not share a relative coordinate system"),
        }
    }
    unsafe fn optional(data: *const u8, length: usize, kind: u32) -> *mut NuppBytes {
        let p = match unsafe { input(data, length) } {
            Ok(v) => v,
            Err(e) => return fail(e),
        };
        let value = match kind {
            0 => p.parent().map(|v| v.as_str()),
            1 => p.file_name(),
            2 => p.file_stem(),
            _ => p.extension(),
        };
        value.map_or_else(ptr::null_mut, |v| output(Utf8PathBuf::from(v)))
    }
    #[no_mangle]
    pub unsafe extern "C" fn nuppPathPart(
        data: *const u8,
        length: usize,
        kind: u32,
    ) -> *mut NuppBytes {
        unsafe { optional(data, length, kind) }
    }
    fn normal(value: &Utf8Path) -> bool {
        let mut c = value.components();
        matches!(c.next(), Some(Utf8Component::Normal(_))) && c.next().is_none()
    }
    #[no_mangle]
    pub unsafe extern "C" fn nuppPathWith(
        data: *const u8,
        length: usize,
        value: *const u8,
        value_length: usize,
        extension: bool,
    ) -> *mut NuppBytes {
        let p = match unsafe { input(data, length) } {
            Ok(v) => v,
            Err(e) => return fail(e),
        };
        let v = match unsafe { input(value, value_length) } {
            Ok(v) => v,
            Err(e) => return fail(e),
        };
        if extension {
            if !v.as_str().is_empty() && !normal(v) {
                return fail("extension must be empty or one path component");
            }
            output(p.with_extension(v.as_str()))
        } else {
            if !normal(v) {
                return fail("file name must be one non-empty path component");
            }
            output(p.with_file_name(v))
        }
    }
    #[no_mangle]
    pub unsafe extern "C" fn nuppPathIsAbsolute(data: *const u8, length: usize) -> bool {
        match unsafe { input(data, length) } {
            Ok(v) => v.is_absolute(),
            Err(e) => {
                set_error(e);
                false
            }
        }
    }
}

#[cfg(feature = "uri")]
mod uri {
    use super::*;
    use url::Url;
    pub struct NuppUri {
        url: Url,
    }
    fn output(url: Url) -> *mut NuppUri {
        Box::into_raw(Box::new(NuppUri { url }))
    }
    fn fail(error: impl ToString) -> *mut NuppUri {
        set_error(error);
        ptr::null_mut()
    }
    unsafe fn clone_uri(uri: *const NuppUri) -> Result<Url, String> {
        if uri.is_null() {
            Err("URI is null".to_owned())
        } else {
            Ok(unsafe { &*uri }.url.clone())
        }
    }
    fn part(value: Option<&str>, length: *mut usize) -> *const u8 {
        match value {
            Some(v) => {
                if !length.is_null() {
                    unsafe { *length = v.len() }
                }
                v.as_ptr()
            }
            None => {
                if !length.is_null() {
                    unsafe { *length = 0 }
                }
                ptr::null()
            }
        }
    }
    fn authority(url: &Url) -> Option<&str> {
        let s = url.as_str();
        let a = url.scheme().len() + 1;
        let rest = s.get(a..)?;
        if !rest.starts_with("//") {
            return None;
        }
        let start = a + 2;
        let tail = s.get(start..)?;
        let length = tail.find(['/', '?', '#']).unwrap_or(tail.len());
        s.get(start..start + length)
    }
    #[no_mangle]
    pub unsafe extern "C" fn nuppUriParse(data: *const u8, length: usize) -> *mut NuppUri {
        let s = match unsafe { text(data, length, "URI") } {
            Ok(v) => v,
            Err(e) => return fail(e),
        };
        match Url::parse(s) {
            Ok(v) => output(v),
            Err(e) => fail(e),
        }
    }
    unsafe fn get(uri: *const NuppUri, kind: u32, length: *mut usize) -> *const u8 {
        if uri.is_null() {
            return part(None, length);
        }
        let u = &unsafe { &*uri }.url;
        match kind {
            0 => part(Some(u.as_str()), length),
            1 => part(Some(u.scheme()), length),
            2 => part(authority(u), length),
            3 => part(Some(u.username()), length),
            4 => part(u.password(), length),
            5 => part(u.host_str(), length),
            6 => part(Some(u.path()), length),
            7 => part(u.query(), length),
            _ => part(u.fragment(), length),
        }
    }
    #[no_mangle]
    pub unsafe extern "C" fn nuppUriPart(
        uri: *const NuppUri,
        kind: u32,
        length: *mut usize,
    ) -> *const u8 {
        unsafe { get(uri, kind, length) }
    }
    #[no_mangle]
    pub unsafe extern "C" fn nuppUriPort(uri: *const NuppUri, port: *mut u16) -> bool {
        if uri.is_null() {
            return false;
        }
        let Some(v) = unsafe { &*uri }.url.port() else {
            return false;
        };
        if !port.is_null() {
            unsafe { *port = v }
        }
        true
    }
    #[no_mangle]
    pub unsafe extern "C" fn nuppUriWithText(
        uri: *const NuppUri,
        kind: u32,
        value: *const u8,
        length: usize,
        present: bool,
    ) -> *mut NuppUri {
        let mut u = match unsafe { clone_uri(uri) } {
            Ok(v) => v,
            Err(e) => return fail(e),
        };
        let v = match unsafe { text(value, length, "URI component") } {
            Ok(v) => v,
            Err(e) => return fail(e),
        };
        let result = match kind {
            0 => u
                .set_scheme(v)
                .map_err(|_| "URI scheme is invalid".to_owned()),
            1 => {
                let (a, b) = if !present {
                    ("", None)
                } else if let Some((a, b)) = v.split_once(':') {
                    (a, Some(b))
                } else {
                    (v, None)
                };
                u.set_username(a)
                    .map_err(|_| "URI user information is invalid".to_owned())
                    .and_then(|_| {
                        u.set_password(b)
                            .map_err(|_| "URI user information is invalid".to_owned())
                    })
            }
            2 => u.set_host(present.then_some(v)).map_err(|e| e.to_string()),
            3 => {
                u.set_path(v);
                Ok(())
            }
            4 => {
                u.set_query(present.then_some(v));
                Ok(())
            }
            _ => {
                u.set_fragment(present.then_some(v));
                Ok(())
            }
        };
        match result {
            Ok(()) => output(u),
            Err(e) => fail(e),
        }
    }
    #[no_mangle]
    pub unsafe extern "C" fn nuppUriWithPort(uri: *const NuppUri, port: i32) -> *mut NuppUri {
        let mut u = match unsafe { clone_uri(uri) } {
            Ok(v) => v,
            Err(e) => return fail(e),
        };
        if !(-1..=u16::MAX as i32).contains(&port) {
            return fail("URI port must be from 0 through 65535, or -1 for none");
        }
        match u.set_port(if port < 0 { None } else { Some(port as u16) }) {
            Ok(()) => output(u),
            Err(()) => fail("URI port is invalid for this scheme"),
        }
    }
    #[no_mangle]
    pub unsafe extern "C" fn nuppUriConcatPath(
        uri: *const NuppUri,
        suffix: *const u8,
        length: usize,
    ) -> *mut NuppUri {
        let mut u = match unsafe { clone_uri(uri) } {
            Ok(v) => v,
            Err(e) => return fail(e),
        };
        let s = match unsafe { text(suffix, length, "URI path") } {
            Ok(v) => v,
            Err(e) => return fail(e),
        };
        let mut p = u.path().to_owned();
        if p.ends_with('/') && s.starts_with('/') {
            p.push_str(&s[1..])
        } else if !p.ends_with('/') && !s.starts_with('/') {
            p.push('/');
            p.push_str(s)
        } else {
            p.push_str(s)
        }
        u.set_path(&p);
        output(u)
    }
    #[no_mangle]
    pub unsafe extern "C" fn nuppUriResolve(
        uri: *const NuppUri,
        reference: *const u8,
        length: usize,
    ) -> *mut NuppUri {
        let u = match unsafe { clone_uri(uri) } {
            Ok(v) => v,
            Err(e) => return fail(e),
        };
        let r = match unsafe { text(reference, length, "URI reference") } {
            Ok(v) => v,
            Err(e) => return fail(e),
        };
        match u.join(r) {
            Ok(v) => output(v),
            Err(e) => fail(e),
        }
    }
    #[no_mangle]
    pub unsafe extern "C" fn nuppUriWithEndpoint(
        uri: *const NuppUri,
        endpoint: *const NuppUri,
    ) -> *mut NuppUri {
        let current = match unsafe { clone_uri(uri) } {
            Ok(v) => v,
            Err(e) => return fail(e),
        };
        let mut e = match unsafe { clone_uri(endpoint) } {
            Ok(v) => v,
            Err(e) => return fail(e),
        };
        let mut p = e.path().to_owned();
        let s = current.path();
        if p.ends_with('/') && s.starts_with('/') {
            p.push_str(&s[1..])
        } else if !p.ends_with('/') && !s.starts_with('/') {
            p.push('/');
            p.push_str(s)
        } else {
            p.push_str(s)
        }
        e.set_path(&p);
        e.set_query(current.query());
        e.set_fragment(current.fragment());
        output(e)
    }
    #[no_mangle]
    pub unsafe extern "C" fn nuppUriDestroy(uri: *mut NuppUri) {
        if !uri.is_null() {
            drop(unsafe { Box::from_raw(uri) })
        }
    }
}

#[cfg(feature = "uuid")]
fn write_uuid(value: uuid::Uuid, output: *mut c_char) -> bool {
    if output.is_null() {
        return false;
    }
    let mut buffer = uuid::Uuid::encode_buffer();
    let text = value.hyphenated().encode_lower(&mut buffer);
    unsafe {
        ptr::copy_nonoverlapping(text.as_ptr().cast(), output, 36);
        *output.add(36) = 0;
    }
    true
}
#[cfg(feature = "uuid")]
#[no_mangle]
pub extern "C" fn nuppUuid4(output: *mut c_char) -> bool {
    write_uuid(uuid::Uuid::new_v4(), output)
}
#[cfg(feature = "uuid")]
#[no_mangle]
pub extern "C" fn nuppUuid7(output: *mut c_char) -> bool {
    write_uuid(uuid::Uuid::now_v7(), output)
}

#[cfg(feature = "sha256")]
#[no_mangle]
pub unsafe extern "C" fn nuppSha256(bytes: *const u8, length: usize, output: *mut c_char) -> bool {
    use sha2::{Digest, Sha256};
    if output.is_null() || (bytes.is_null() && length != 0) {
        return false;
    }
    let input = if length == 0 {
        &[]
    } else {
        unsafe { slice::from_raw_parts(bytes, length) }
    };
    let digest = Sha256::digest(input);
    let hex = b"0123456789abcdef";
    for (i, b) in digest.iter().enumerate() {
        unsafe {
            *output.add(i * 2) = hex[(b >> 4) as usize] as c_char;
            *output.add(i * 2 + 1) = hex[(b & 15) as usize] as c_char
        }
    }
    unsafe { *output.add(64) = 0 }
    true
}

/// The immediate half of `nupp.io.files`: metadata, listing, and the directory
/// operations that answer before a request could have been submitted. Transfers
/// belong to the request lane, not here.
#[cfg(feature = "files")]
pub mod files {
    use super::*;
    use std::fs;
    use std::hash::{BuildHasher, Hasher, RandomState};
    use std::path::{Path, PathBuf};
    use std::time::UNIX_EPOCH;

    pub const KIND_FILE: u32 = 1;
    pub const KIND_DIRECTORY: u32 = 2;
    pub const KIND_OTHER: u32 = 3;
    pub const KIND_SYMLINK: u32 = 4;

    const ATTEMPTS: u32 = 64;

    /// What one resolved path is. Mirrored by `NuppFileInfo` in the Lua binding,
    /// so field order and widths are part of the ABI.
    #[repr(C)]
    pub struct FileInfo {
        pub kind: u32,
        pub read_only: bool,
        pub size: u64,
        pub modified: f64,
    }

    unsafe fn at<'a>(data: *const u8, length: usize) -> Result<&'a Path, String> {
        Ok(Path::new(unsafe { text(data, length, "path") }?))
    }

    fn refused(error: impl ToString) -> bool {
        set_error(error);
        false
    }

    fn missing(error: impl ToString) -> *mut NuppBytes {
        set_error(error);
        ptr::null_mut()
    }

    fn settled<T>(result: std::io::Result<T>) -> bool {
        match result {
            Ok(_) => true,
            Err(error) => refused(error),
        }
    }

    fn named(path: PathBuf) -> *mut NuppBytes {
        match path.into_os_string().into_string() {
            Ok(text) => output_bytes(text.into_bytes()),
            Err(_) => missing("path is not valid UTF-8"),
        }
    }

    /// Describes one path. `follow` resolves a symbolic link to its target, which
    /// is the difference between asking what a name refers to and asking what the
    /// name itself is.
    #[no_mangle]
    pub unsafe extern "C" fn nuppFilesInfo(
        data: *const u8,
        length: usize,
        follow: bool,
        out: *mut FileInfo,
    ) -> bool {
        if out.is_null() {
            return refused("file info output is null");
        }
        let path = match unsafe { at(data, length) } {
            Ok(value) => value,
            Err(error) => return refused(error),
        };
        let metadata = if follow {
            fs::metadata(path)
        } else {
            fs::symlink_metadata(path)
        };
        let metadata = match metadata {
            Ok(value) => value,
            Err(error) => return refused(error),
        };
        let kind = if metadata.is_symlink() {
            KIND_SYMLINK
        } else if metadata.is_file() {
            KIND_FILE
        } else if metadata.is_dir() {
            KIND_DIRECTORY
        } else {
            KIND_OTHER
        };
        let modified = metadata
            .modified()
            .ok()
            .and_then(|value| match value.duration_since(UNIX_EPOCH) {
                Ok(since) => Some(since.as_secs_f64()),
                Err(before) => Some(-before.duration().as_secs_f64()),
            })
            .unwrap_or(0.0);
        unsafe {
            *out = FileInfo {
                kind,
                read_only: metadata.permissions().readonly(),
                size: metadata.len(),
                modified,
            }
        };
        true
    }

    /// Reads a symbolic link's target without resolving it.
    #[no_mangle]
    pub unsafe extern "C" fn nuppFilesReadLink(data: *const u8, length: usize) -> *mut NuppBytes {
        let path = match unsafe { at(data, length) } {
            Ok(value) => value,
            Err(error) => return missing(error),
        };
        match fs::read_link(path) {
            Ok(target) => named(target),
            Err(error) => missing(error),
        }
    }

    /// Creates a symbolic link. `directory` selects Windows's directory link and
    /// is ignored elsewhere, because only Windows distinguishes the two.
    #[no_mangle]
    pub unsafe extern "C" fn nuppFilesCreateSymlink(
        target: *const u8,
        target_length: usize,
        link: *const u8,
        link_length: usize,
        directory: bool,
    ) -> bool {
        let target = match unsafe { at(target, target_length) } {
            Ok(value) => value,
            Err(error) => return refused(error),
        };
        let link = match unsafe { at(link, link_length) } {
            Ok(value) => value,
            Err(error) => return refused(error),
        };
        #[cfg(windows)]
        let made = if directory {
            std::os::windows::fs::symlink_dir(target, link)
        } else {
            std::os::windows::fs::symlink_file(target, link)
        };
        #[cfg(not(windows))]
        let made = {
            let _ = directory;
            std::os::unix::fs::symlink(target, link)
        };
        settled(made)
    }

    /// Sets or clears the read-only bit.
    #[no_mangle]
    pub unsafe extern "C" fn nuppFilesSetReadOnly(
        data: *const u8,
        length: usize,
        read_only: bool,
    ) -> bool {
        let path = match unsafe { at(data, length) } {
            Ok(value) => value,
            Err(error) => return refused(error),
        };
        let mut permissions = match fs::metadata(path) {
            Ok(value) => value.permissions(),
            Err(error) => return refused(error),
        };
        permissions.set_readonly(read_only);
        settled(fs::set_permissions(path, permissions))
    }

    /// Creates a directory and every missing parent. An existing directory is
    /// success, which is what a caller building a tree wants.
    #[no_mangle]
    pub unsafe extern "C" fn nuppFilesCreateDirectory(data: *const u8, length: usize) -> bool {
        let path = match unsafe { at(data, length) } {
            Ok(value) => value,
            Err(error) => return refused(error),
        };
        settled(fs::create_dir_all(path))
    }

    /// Removes a file, a symbolic link, or an empty directory. `recursive`
    /// removes a directory's contents with it.
    #[no_mangle]
    pub unsafe extern "C" fn nuppFilesRemove(
        data: *const u8,
        length: usize,
        recursive: bool,
    ) -> bool {
        let path = match unsafe { at(data, length) } {
            Ok(value) => value,
            Err(error) => return refused(error),
        };
        let metadata = match fs::symlink_metadata(path) {
            Ok(value) => value,
            Err(error) => return refused(error),
        };
        if metadata.is_dir() {
            settled(if recursive {
                fs::remove_dir_all(path)
            } else {
                fs::remove_dir(path)
            })
        } else {
            settled(fs::remove_file(path))
        }
    }

    /// Renames a path, replacing an existing destination.
    #[no_mangle]
    pub unsafe extern "C" fn nuppFilesRename(
        from: *const u8,
        from_length: usize,
        to: *const u8,
        to_length: usize,
    ) -> bool {
        let from = match unsafe { at(from, from_length) } {
            Ok(value) => value,
            Err(error) => return refused(error),
        };
        let to = match unsafe { at(to, to_length) } {
            Ok(value) => value,
            Err(error) => return refused(error),
        };
        settled(fs::rename(from, to))
    }

    /// Lists a directory's immediate children as `kind` byte, name, NUL. The kind
    /// comes from the directory entry rather than a second call per name, and
    /// describes the entry itself, so a symbolic link reads as `l`.
    #[no_mangle]
    pub unsafe extern "C" fn nuppFilesList(data: *const u8, length: usize) -> *mut NuppBytes {
        let path = match unsafe { at(data, length) } {
            Ok(value) => value,
            Err(error) => return missing(error),
        };
        let entries = match fs::read_dir(path) {
            Ok(value) => value,
            Err(error) => return missing(error),
        };
        let mut out: Vec<u8> = Vec::new();
        for entry in entries {
            let entry = match entry {
                Ok(value) => value,
                Err(error) => return missing(error),
            };
            let name = match entry.file_name().into_string() {
                Ok(value) => value,
                Err(_) => return missing("directory entry name is not valid UTF-8"),
            };
            if name.as_bytes().contains(&0) {
                return missing("directory entry name contains a NUL byte");
            }
            let kind = match entry.file_type() {
                Ok(value) if value.is_symlink() => b'l',
                Ok(value) if value.is_dir() => b'd',
                Ok(value) if value.is_file() => b'f',
                Ok(_) => b'o',
                Err(error) => return missing(error),
            };
            out.push(kind);
            out.extend_from_slice(name.as_bytes());
            out.push(0);
        }
        output_bytes(out)
    }

    /// Expands a filesystem glob. The glob crate reports a malformed pattern
    /// before it begins walking, while an error encountered during the walk is
    /// returned at the point it is found. Either is an ordinary failed query on
    /// this ABI. Sorting here makes one pattern answer independently of the
    /// platform directory order it walked through.
    #[no_mangle]
    pub unsafe extern "C" fn nuppFilesGlob(data: *const u8, length: usize) -> *mut NuppBytes {
        let pattern = match unsafe { text(data, length, "glob pattern") } {
            Ok(value) => value,
            Err(error) => return missing(error),
        };
        let paths = match glob::glob(pattern) {
            Ok(value) => value,
            Err(error) => return missing(error),
        };
        let mut matches = Vec::new();
        for path in paths {
            let path = match path {
                Ok(value) => value,
                Err(error) => return missing(error),
            };
            let path = match path.into_os_string().into_string() {
                Ok(value) => value,
                Err(_) => return missing("glob match is not valid UTF-8"),
            };
            matches.push(path);
        }
        matches.sort();
        output_bytes(matches.join("\0").into_bytes())
    }

    /// Creates a uniquely named file or directory and answers its path. The name
    /// is created rather than merely proposed, so no second caller can win the
    /// same name between the two steps.
    #[no_mangle]
    pub unsafe extern "C" fn nuppFilesCreateTemporary(
        directory: *const u8,
        directory_length: usize,
        prefix: *const u8,
        prefix_length: usize,
        suffix: *const u8,
        suffix_length: usize,
        as_directory: bool,
    ) -> *mut NuppBytes {
        let root = if directory_length == 0 {
            std::env::temp_dir()
        } else {
            match unsafe { at(directory, directory_length) } {
                Ok(value) => value.to_path_buf(),
                Err(error) => return missing(error),
            }
        };
        let prefix = match unsafe { text(prefix, prefix_length, "temporary prefix") } {
            Ok(value) => value,
            Err(error) => return missing(error),
        };
        let suffix = match unsafe { text(suffix, suffix_length, "temporary suffix") } {
            Ok(value) => value,
            Err(error) => return missing(error),
        };
        for _ in 0..ATTEMPTS {
            let stamp = RandomState::new().build_hasher().finish();
            let candidate = root.join(format!("{prefix}{stamp:016x}{suffix}"));
            let made = if as_directory {
                fs::create_dir(&candidate)
            } else {
                fs::OpenOptions::new()
                    .write(true)
                    .create_new(true)
                    .open(&candidate)
                    .map(drop)
            };
            match made {
                Ok(()) => return named(candidate),
                Err(error) if error.kind() == std::io::ErrorKind::AlreadyExists => continue,
                Err(error) => return missing(error),
            }
        }
        missing("no unused temporary name was found")
    }

    unsafe fn borrowed<'a>(data: *const u8, length: usize) -> &'a [u8] {
        if length == 0 {
            &[]
        } else {
            unsafe { slice::from_raw_parts(data, length) }
        }
    }

    /// An open file. Owned by the caller, which is what makes closing it a
    /// checked obligation rather than a habit.
    pub struct NuppFile {
        handle: fs::File,
    }

    /// Opens a file. `mode` selects read, truncating write, append, and the
    /// three update modes, in that order.
    #[no_mangle]
    pub unsafe extern "C" fn nuppFileOpen(
        data: *const u8,
        length: usize,
        mode: u32,
    ) -> *mut NuppFile {
        let path = match unsafe { at(data, length) } {
            Ok(value) => value,
            Err(error) => {
                set_error(error);
                return ptr::null_mut();
            }
        };
        let mut options = fs::OpenOptions::new();
        match mode {
            0 => options.read(true),
            1 => options.write(true).create(true).truncate(true),
            2 => options.append(true).create(true),
            3 => options.read(true).write(true),
            4 => options.read(true).write(true).create(true).truncate(true),
            5 => options.read(true).append(true).create(true),
            _ => {
                set_error("unknown file mode");
                return ptr::null_mut();
            }
        };
        match options.open(path) {
            Ok(handle) => Box::into_raw(Box::new(NuppFile { handle })),
            Err(error) => {
                set_error(error);
                ptr::null_mut()
            }
        }
    }

    /// Reads at most `length` bytes. Answers zero at the end of the file and -1
    /// on failure, so a short read is progress rather than an error.
    #[no_mangle]
    pub unsafe extern "C" fn nuppFileRead(
        file: *mut NuppFile,
        into: *mut u8,
        length: usize,
    ) -> i64 {
        use std::io::Read;
        if file.is_null() || (into.is_null() && length != 0) {
            set_error("file read has no destination");
            return -1;
        }
        let file = unsafe { &mut *file };
        let destination = if length == 0 {
            &mut [][..]
        } else {
            unsafe { slice::from_raw_parts_mut(into, length) }
        };
        match file.handle.read(destination) {
            Ok(count) => count as i64,
            Err(error) => {
                set_error(error);
                -1
            }
        }
    }

    /// Writes every byte or fails, which is what a caller counting bytes wants.
    #[no_mangle]
    pub unsafe extern "C" fn nuppFileWrite(
        file: *mut NuppFile,
        from: *const u8,
        length: usize,
    ) -> i64 {
        use std::io::Write;
        if file.is_null() || (from.is_null() && length != 0) {
            set_error("file write has no source");
            return -1;
        }
        let file = unsafe { &mut *file };
        match file.handle.write_all(unsafe { borrowed(from, length) }) {
            Ok(()) => length as i64,
            Err(error) => {
                set_error(error);
                -1
            }
        }
    }

    /// Moves the cursor. `whence` is the start, the current position, or the
    /// end, in that order. Answers the new position, or -1 on failure.
    #[no_mangle]
    pub unsafe extern "C" fn nuppFileSeek(file: *mut NuppFile, offset: i64, whence: u32) -> i64 {
        use std::io::{Seek, SeekFrom};
        if file.is_null() {
            set_error("file seek has no file");
            return -1;
        }
        let file = unsafe { &mut *file };
        let target = match whence {
            0 => SeekFrom::Start(offset.max(0) as u64),
            1 => SeekFrom::Current(offset),
            2 => SeekFrom::End(offset),
            _ => {
                set_error("unknown seek origin");
                return -1;
            }
        };
        match file.handle.seek(target) {
            Ok(position) => position as i64,
            Err(error) => {
                set_error(error);
                -1
            }
        }
    }

    /// Answers the file's byte length without moving the cursor.
    #[no_mangle]
    pub unsafe extern "C" fn nuppFileSize(file: *mut NuppFile) -> i64 {
        if file.is_null() {
            set_error("file size has no file");
            return -1;
        }
        let file = unsafe { &*file };
        match file.handle.metadata() {
            Ok(metadata) => metadata.len() as i64,
            Err(error) => {
                set_error(error);
                -1
            }
        }
    }

    /// Pushes buffered writes at the operating system.
    #[no_mangle]
    pub unsafe extern "C" fn nuppFileFlush(file: *mut NuppFile) -> bool {
        use std::io::Write;
        if file.is_null() {
            return refused("file flush has no file");
        }
        settled(unsafe { &mut *file }.handle.flush())
    }

    /// Closes and releases the file. Repeated calls are the binding's problem,
    /// not this one's: a released handle must not be passed again.
    #[no_mangle]
    pub unsafe extern "C" fn nuppFileClose(file: *mut NuppFile) -> bool {
        if file.is_null() {
            return true;
        }
        drop(unsafe { Box::from_raw(file) });
        true
    }

    /// Whole-file transfers, off the calling thread.
    ///
    /// A transfer is submitted, settles on a worker, and is observed by polling.
    /// Nothing here calls Lua and nothing here blocks the submitter, which is
    /// what lets one caller wait by sleeping and another wait by parking a task
    /// and pumping this from its frame.
    ///
    /// The lane is bounded in three directions — how many transfers may be live,
    /// how many bytes they may hold between them, and how large one may be —
    /// because a queue that grows with its callers eventually takes the process
    /// with it.
    pub mod lane {
        use super::*;
        use std::sync::atomic::{AtomicI32, AtomicUsize, Ordering};
        use std::sync::mpsc::{sync_channel, Receiver, SyncSender};
        use std::sync::{Arc, Condvar, Mutex, OnceLock};
        use std::thread;
        use std::time::Duration;

        pub const STATUS_PENDING: i32 = 0;
        pub const STATUS_READY: i32 = 1;
        pub const STATUS_FAILED: i32 = 2;
        pub const STATUS_CANCELED: i32 = 3;

        const WORKERS: usize = 4;
        const QUEUE_DEPTH: usize = 256;
        const MAX_REQUESTS: usize = 128;
        const MAX_BYTES: usize = 256 * 1024 * 1024;
        const MAX_REQUEST_BYTES: usize = 256 * 1024 * 1024;

        static REQUESTS: AtomicUsize = AtomicUsize::new(0);
        static IN_FLIGHT: AtomicUsize = AtomicUsize::new(0);
        static SETTLED: AtomicUsize = AtomicUsize::new(0);

        fn arrivals() -> &'static (Mutex<usize>, Condvar) {
            static ARRIVALS: OnceLock<(Mutex<usize>, Condvar)> = OnceLock::new();
            ARRIVALS.get_or_init(|| (Mutex::new(0), Condvar::new()))
        }

        enum Outcome {
            Waiting,
            Ready(Vec<u8>),
            Failed(CString),
        }

        /// One transfer's shared state.
        pub struct Slot {
            status: AtomicI32,
            outcome: Mutex<Outcome>,
            charged: usize,
        }

        /// Returns a transfer's share of the budget.
        ///
        /// This is tied to the caller's handle rather than to the shared state,
        /// which is the difference between a cap on what a program is holding
        /// and a cap on what the workers have finished touching. The second
        /// cannot be observed without a race: a worker publishes `READY` from
        /// inside the state both sides share, so a caller releasing the instant
        /// it sees the result is still counted until the worker gets around to
        /// dropping its own reference.
        ///
        /// The cost is that a cancelled transfer is refunded while its worker
        /// may still be reading. Those bytes are transient and belong to work
        /// already in flight; what the cap exists to bound is what a caller can
        /// keep accumulating.
        fn refund(charge: usize) {
            REQUESTS.fetch_sub(1, Ordering::AcqRel);
            IN_FLIGHT.fetch_sub(charge, Ordering::AcqRel);
        }

        /// The caller's handle on a transfer.
        pub struct NuppRequest {
            slot: Arc<Slot>,
        }

        enum Work {
            Read(PathBuf),
            Write {
                path: PathBuf,
                contents: Vec<u8>,
                mode: u32,
            },
            Copy {
                from: PathBuf,
                to: PathBuf,
            },
        }

        struct Job {
            slot: Arc<Slot>,
            work: Work,
        }

        fn settle(slot: &Arc<Slot>, outcome: Outcome, status: i32) {
            // A canceled transfer keeps its verdict: the work finished, but
            // nobody is left who asked for it, so the bytes go nowhere.
            if slot
                .status
                .compare_exchange(
                    STATUS_PENDING,
                    status,
                    Ordering::AcqRel,
                    Ordering::Acquire,
                )
                .is_ok()
            {
                *slot.outcome.lock().expect("outcome mutex") = outcome;
            }
            SETTLED.fetch_add(1, Ordering::AcqRel);
            let (count, waiters) = arrivals();
            *count.lock().expect("arrivals mutex") += 1;
            waiters.notify_all();
        }

        fn write_atomic(path: &Path, contents: &[u8]) -> std::io::Result<()> {
            use std::io::Write;
            let directory = path.parent().unwrap_or(Path::new("."));
            let stamp = RandomState::new().build_hasher().finish();
            let temporary = directory.join(format!(".nupp-write-{stamp:016x}"));
            let written = fs::OpenOptions::new()
                .write(true)
                .create_new(true)
                .open(&temporary)
                .and_then(|mut file| {
                    file.write_all(contents)?;
                    file.sync_all()
                })
                .and_then(|()| fs::rename(&temporary, path));
            if written.is_err() {
                let _ = fs::remove_file(&temporary);
            }
            written
        }

        fn perform(work: Work) -> std::io::Result<Vec<u8>> {
            use std::io::Write;
            match work {
                Work::Read(path) => fs::read(path),
                Work::Write {
                    path,
                    contents,
                    mode,
                } => match mode {
                    2 => write_atomic(&path, &contents).map(|()| Vec::new()),
                    1 => fs::OpenOptions::new()
                        .append(true)
                        .create(true)
                        .open(&path)
                        .and_then(|mut file| file.write_all(&contents))
                        .map(|()| Vec::new()),
                    _ => fs::write(&path, &contents).map(|()| Vec::new()),
                },
                Work::Copy { from, to } => fs::copy(from, to).map(|_| Vec::new()),
            }
        }

        fn worker(jobs: Arc<Mutex<Receiver<Job>>>) {
            loop {
                let job = {
                    let queue = jobs.lock().expect("job queue mutex");
                    match queue.recv() {
                        Ok(job) => job,
                        Err(_) => return,
                    }
                };
                match perform(job.work) {
                    Ok(bytes) => settle(&job.slot, Outcome::Ready(bytes), STATUS_READY),
                    Err(error) => {
                        let text = error.to_string().replace('\0', "\\0");
                        let text = CString::new(text).expect("NUL bytes were replaced");
                        settle(&job.slot, Outcome::Failed(text), STATUS_FAILED)
                    }
                }
            }
        }

        fn queue() -> &'static SyncSender<Job> {
            static QUEUE: OnceLock<SyncSender<Job>> = OnceLock::new();
            QUEUE.get_or_init(|| {
                let (sender, receiver) = sync_channel(QUEUE_DEPTH);
                let shared = Arc::new(Mutex::new(receiver));
                for _ in 0..WORKERS {
                    let jobs = Arc::clone(&shared);
                    thread::Builder::new()
                        .name("nupp-files".to_owned())
                        .spawn(move || worker(jobs))
                        .expect("file worker thread");
                }
                sender
            })
        }

        fn admit(charge: usize) -> Result<(), String> {
            if charge > MAX_REQUEST_BYTES {
                return Err(format!(
                    "the transfer is larger than the {MAX_REQUEST_BYTES}-byte limit"
                ));
            }
            let live = REQUESTS.fetch_add(1, Ordering::AcqRel) + 1;
            if live > MAX_REQUESTS {
                REQUESTS.fetch_sub(1, Ordering::AcqRel);
                return Err(format!("more than {MAX_REQUESTS} transfers are in flight"));
            }
            let held = IN_FLIGHT.fetch_add(charge, Ordering::AcqRel) + charge;
            if held > MAX_BYTES {
                IN_FLIGHT.fetch_sub(charge, Ordering::AcqRel);
                REQUESTS.fetch_sub(1, Ordering::AcqRel);
                return Err(format!(
                    "transfers in flight would hold more than {MAX_BYTES} bytes"
                ));
            }
            Ok(())
        }

        fn submit(work: Work, charge: usize) -> *mut NuppRequest {
            if let Err(reason) = admit(charge) {
                set_error(reason);
                return ptr::null_mut();
            }
            let slot = Arc::new(Slot {
                status: AtomicI32::new(STATUS_PENDING),
                outcome: Mutex::new(Outcome::Waiting),
                charged: charge,
            });
            let job = Job {
                slot: Arc::clone(&slot),
                work,
            };
            if queue().send(job).is_err() {
                refund(charge);
                set_error("the file worker queue is gone");
                return ptr::null_mut();
            }
            Box::into_raw(Box::new(NuppRequest { slot }))
        }

        /// Submits a whole-file read. The file is sized on this thread, because
        /// a lane that cannot price a transfer cannot bound itself.
        #[no_mangle]
        pub unsafe extern "C" fn nuppFsSubmitRead(
            data: *const u8,
            length: usize,
        ) -> *mut NuppRequest {
            let path = match unsafe { at(data, length) } {
                Ok(value) => value.to_path_buf(),
                Err(error) => {
                    set_error(error);
                    return ptr::null_mut();
                }
            };
            let charge = match fs::metadata(&path) {
                Ok(metadata) => metadata.len() as usize,
                Err(error) => {
                    set_error(error);
                    return ptr::null_mut();
                }
            };
            submit(Work::Read(path), charge)
        }

        /// Submits a whole-file write. `mode` replaces, appends, or writes
        /// through a temporary beside the destination, in that order.
        #[no_mangle]
        pub unsafe extern "C" fn nuppFsSubmitWrite(
            data: *const u8,
            length: usize,
            bytes: *const u8,
            bytes_length: usize,
            mode: u32,
        ) -> *mut NuppRequest {
            let path = match unsafe { at(data, length) } {
                Ok(value) => value.to_path_buf(),
                Err(error) => {
                    set_error(error);
                    return ptr::null_mut();
                }
            };
            if bytes.is_null() && bytes_length != 0 {
                set_error("file contents are null");
                return ptr::null_mut();
            }
            if mode > 2 {
                set_error("unknown write mode");
                return ptr::null_mut();
            }
            let contents = unsafe { borrowed(bytes, bytes_length) }.to_vec();
            submit(
                Work::Write {
                    path,
                    contents,
                    mode,
                },
                bytes_length,
            )
        }

        /// Submits a copy. The bytes never reach this process, so the lane
        /// charges the transfer a slot rather than a size.
        #[no_mangle]
        pub unsafe extern "C" fn nuppFsSubmitCopy(
            from: *const u8,
            from_length: usize,
            to: *const u8,
            to_length: usize,
        ) -> *mut NuppRequest {
            let from = match unsafe { at(from, from_length) } {
                Ok(value) => value.to_path_buf(),
                Err(error) => {
                    set_error(error);
                    return ptr::null_mut();
                }
            };
            let to = match unsafe { at(to, to_length) } {
                Ok(value) => value.to_path_buf(),
                Err(error) => {
                    set_error(error);
                    return ptr::null_mut();
                }
            };
            submit(Work::Copy { from, to }, 0)
        }

        fn slot_of<'a>(request: *const NuppRequest) -> Option<&'a Arc<Slot>> {
            if request.is_null() {
                None
            } else {
                Some(&unsafe { &*request }.slot)
            }
        }

        /// Answers whether a transfer is pending, ready, failed, or canceled.
        #[no_mangle]
        pub unsafe extern "C" fn nuppFsStatus(request: *const NuppRequest) -> i32 {
            match slot_of(request) {
                Some(slot) => slot.status.load(Ordering::Acquire),
                None => STATUS_FAILED,
            }
        }

        /// Answers a settled read's bytes. Valid until the transfer is
        /// destroyed.
        #[no_mangle]
        pub unsafe extern "C" fn nuppFsData(request: *const NuppRequest) -> *const u8 {
            match slot_of(request) {
                Some(slot) => match &*slot.outcome.lock().expect("outcome mutex") {
                    Outcome::Ready(bytes) => bytes.as_ptr(),
                    _ => ptr::null(),
                },
                None => ptr::null(),
            }
        }

        /// Answers a settled read's byte count.
        #[no_mangle]
        pub unsafe extern "C" fn nuppFsLength(request: *const NuppRequest) -> usize {
            match slot_of(request) {
                Some(slot) => match &*slot.outcome.lock().expect("outcome mutex") {
                    Outcome::Ready(bytes) => bytes.len(),
                    _ => 0,
                },
                None => 0,
            }
        }

        /// Copies a failed transfer's reason into the shared error slot and
        /// answers it, so every failure is read the same way.
        #[no_mangle]
        pub unsafe extern "C" fn nuppFsError(request: *const NuppRequest) -> *const c_char {
            if let Some(slot) = slot_of(request) {
                if let Outcome::Failed(text) = &*slot.outcome.lock().expect("outcome mutex") {
                    set_error(text.to_string_lossy());
                }
            }
            nuppNativeError()
        }

        /// Abandons a pending transfer. The work still finishes; its result is
        /// dropped, because a worker already reading cannot be recalled.
        #[no_mangle]
        pub unsafe extern "C" fn nuppFsCancel(request: *mut NuppRequest) -> bool {
            match slot_of(request) {
                Some(slot) => slot
                    .status
                    .compare_exchange(
                        STATUS_PENDING,
                        STATUS_CANCELED,
                        Ordering::AcqRel,
                        Ordering::Acquire,
                    )
                    .is_ok(),
                None => false,
            }
        }

        /// Releases the caller's handle and its share of the lane's budget.
        #[no_mangle]
        pub unsafe extern "C" fn nuppFsDestroy(request: *mut NuppRequest) {
            if !request.is_null() {
                let held = unsafe { Box::from_raw(request) };
                refund(held.slot.charged);
                drop(held);
            }
        }

        /// Answers how many transfers settled since the last poll, without
        /// waiting. This is the readiness pump a scheduler drives.
        #[no_mangle]
        pub extern "C" fn nuppFsPoll() -> usize {
            let (count, _) = arrivals();
            let mut guard = count.lock().expect("arrivals mutex");
            *guard = 0;
            SETTLED.swap(0, Ordering::AcqRel)
        }

        /// The same, sleeping up to a deadline for the first settlement. This is
        /// what keeps a program with no scheduler from spinning on a status.
        ///
        /// The count is read under the same lock a worker raises it under, so a
        /// settlement that lands between the check and the sleep is seen rather
        /// than slept through.
        #[no_mangle]
        pub extern "C" fn nuppFsWait(milliseconds: u64) -> usize {
            let (count, waiters) = arrivals();
            let mut guard = count.lock().expect("arrivals mutex");
            if *guard == 0 {
                let (settled, _) = waiters
                    .wait_timeout(guard, Duration::from_millis(milliseconds))
                    .expect("arrivals condvar");
                guard = settled;
            }
            *guard = 0;
            drop(guard);
            SETTLED.swap(0, Ordering::AcqRel)
        }

        /// How many transfers the caller still holds.
        #[no_mangle]
        pub extern "C" fn nuppFsPending() -> usize {
            REQUESTS.load(Ordering::Acquire)
        }
    }

    /// Answers the process's current working directory.
    #[no_mangle]
    pub extern "C" fn nuppFilesCurrentDirectory() -> *mut NuppBytes {
        match std::env::current_dir() {
            Ok(path) => named(path),
            Err(error) => missing(error),
        }
    }

    /// Answers a well-known user folder. Resolved from the environment — the XDG
    /// variables where they are set, and the platform's conventional names under
    /// the home directory otherwise. A desktop that records its folders somewhere
    /// else is not consulted, and a folder that does not exist is a failure.
    #[no_mangle]
    pub extern "C" fn nuppFilesUserFolder(which: u32) -> *mut NuppBytes {
        let home = match std::env::var_os(if cfg!(windows) {
            "USERPROFILE"
        } else {
            "HOME"
        }) {
            Some(value) if !value.is_empty() => PathBuf::from(value),
            _ => return missing("the home directory is not set in the environment"),
        };
        if which == 0 {
            return named(home);
        }
        let (variable, macos, other) = match which {
            1 => ("XDG_DOCUMENTS_DIR", "Documents", "Documents"),
            2 => ("XDG_DOWNLOAD_DIR", "Downloads", "Downloads"),
            3 => ("XDG_DESKTOP_DIR", "Desktop", "Desktop"),
            4 => ("XDG_PICTURES_DIR", "Pictures", "Pictures"),
            5 => ("XDG_MUSIC_DIR", "Music", "Music"),
            6 => ("XDG_VIDEOS_DIR", "Movies", "Videos"),
            _ => return missing("unknown user folder"),
        };
        let resolved = if cfg!(any(windows, target_os = "macos")) {
            None
        } else {
            std::env::var_os(variable).filter(|value| !value.is_empty())
        };
        let folder = match resolved {
            Some(value) => PathBuf::from(value),
            None => home.join(if cfg!(target_os = "macos") { macos } else { other }),
        };
        if !folder.is_dir() {
            return missing("the platform has no such folder");
        }
        named(folder)
    }
}

/// Child processes: spawning them, moving bytes to and from them, and reaping them.
///
/// The platform half of the seam `nupp.io.processtypes` describes. Spawning, ordered
/// stdio wiring, environment construction, SIGPIPE containment, the nonblocking
/// operations and readiness waiting, and exit decoding live here; the lifecycle policy
/// above -- deadlines, `communicate`, suspension, cancellation, cleanup -- stays in
/// Nupp.
///
/// Spawning goes through `std::process::Command` rather than a hand-rolled
/// `posix_spawn`, and that is a deliberate departure from what `plans/suspension.md`
/// first asked for rather than a way of meeting it. `Command` promises nothing about
/// how it starts a child: it uses `posix_spawn` where it can and a fork path where it
/// cannot, and which of those it picks is a standard-library detail that may change.
///
/// What the original requirement was protecting is kept. The danger was never the word
/// `fork` -- it was our own code running between a fork and its exec, where only
/// async-signal-safe functions may be called and Lua, allocation and `setenv` are none
/// of them. Nothing of ours runs there now, and the code that does has far more testing
/// behind it than a hand-rolled equivalent would.
///
/// What std does not do is the rest: its pipes are blocking, it has no readiness wait,
/// and its `SIGPIPE` handling belongs to a Rust runtime that never starts here -- this
/// is a `cdylib` loaded into someone else's process, so the disposition is whatever the
/// host chose. Those are this module's, and they are exactly the parts the seam had
/// opinions about.
///
/// Every operation that decides ownership is `catch_unwind`-wrapped. The contract says
/// those never raise, and a panic reaching the boundary would not merely break it: a
/// panic that escapes an `extern "C"` function aborts, since the ABI does not unwind,
/// and this is a library inside somebody else's process. So the caller would not learn
/// whether the handle was still theirs, and there would be nobody left to ask.
#[cfg(all(feature = "process", windows))]
#[path = "process_windows.rs"]
pub mod process;

#[cfg(all(feature = "process", unix))]
pub mod process {
    use std::ffi::OsString;
    use std::io::{ErrorKind, Read, Write};
    use std::os::unix::ffi::OsStringExt;
    use std::os::fd::{AsRawFd, FromRawFd, OwnedFd, RawFd};
    use std::panic::{catch_unwind, AssertUnwindSafe};
    use std::process::{Child, Command, Stdio};
    use std::slice;
    use std::sync::OnceLock;
    use std::time::Instant;

    use super::set_error;

    /// How a stream was asked to be connected. Mirrors `processtypes.StreamMode`, plus
    /// stderr's option to join stdout.
    pub const MODE_PIPE: u8 = 0;
    pub const MODE_INHERIT: u8 = 1;
    pub const MODE_NULL: u8 = 2;
    pub const MODE_STDOUT: u8 = 3;

    /// What a read or a write answers when it did not move bytes. Negative, so a caller
    /// reads a count and these apart without a second result.
    pub const WOULD_BLOCK: isize = -1;
    /// The far end is finished: end of stream for a read, nobody listening for a write.
    pub const GONE: isize = -2;
    /// Something else went wrong; `nuppNativeError` says what.
    pub const FAILED: isize = -3;

    /// How a release went, in the seam's own terms.
    pub const RELEASED: u8 = 0;
    /// Released, and the platform had something to say about it.
    pub const RELEASED_WITH_REASON: u8 = 1;
    /// Still the caller's, and worth another attempt.
    pub const NOT_RELEASED: u8 = 2;

    /// Milliseconds on a process-local monotonic clock.
    ///
    /// The first call establishes an arbitrary zero. Deadlines only subtract readings,
    /// so an epoch with no wall-clock meaning is exactly what they need, and `Instant`
    /// is the standard library's platform-neutral monotonic source.
    #[no_mangle]
    pub extern "C" fn nuppProcessMonotonicMs() -> f64 {
        static EPOCH: OnceLock<Instant> = OnceLock::new();
        EPOCH.get_or_init(Instant::now).elapsed().as_secs_f64() * 1000.0
    }

    /// One end of a pipe to a child, and whether this process has given it up.
    ///
    /// Two lifetimes here, and they are not the same one. The *descriptor* is released
    /// by `nuppProcessCloseStream`, after which this handle is still perfectly alive:
    /// it may be named to a readiness wait, asked its state, or closed again. The
    /// *handle* ends only at `nuppProcessStreamDestroy`, and naming it after that reads
    /// freed memory.
    ///
    /// So "released" throughout means the descriptor, never the allocation. A caller
    /// holding one of these should keep it until the `Process` that owns it is finished
    /// -- closing early is fine and normal; destroying early is what cannot be undone.
    pub struct NuppStream {
        fd: RawFd,
        reader: Option<Box<dyn Read + Send>>,
        writer: Option<Box<dyn Write + Send>>,
        released: bool,
    }

    /// A child, and the exit it has been seen to reach.
    ///
    /// The exit is remembered because `try_wait` answers once: the platform gives a
    /// status up when it is collected, and a second ask reports no such child.
    pub struct NuppChild {
        /// Optional so the drop below can take it away. Present for a handle's whole
        /// life otherwise, and `running` is how everything else reads it.
        child: Option<Child>,
        exit: Option<(i32, bool)>,
        released: bool,
        /// The parent's end of the pipe both stdout and stderr were joined onto, when
        /// they were. One end, held once: handing the same stream back under two names
        /// would be two owners of one descriptor.
        merged: Option<std::fs::File>,
    }

    /// A spawn being described. Built up field by field because the caller is on the
    /// other side of a C boundary and cannot hand over a struct.
    pub struct NuppSpawn {
        args: Vec<OsString>,
        env: Vec<OsString>,
        cwd: Option<OsString>,
        clear_env: bool,
        modes: [u8; 3],
    }

    impl NuppChild {
        /// The child this handle owns. Absent only inside its own drop, after the
        /// child has been handed to a reaper.
        fn running(&mut self) -> Option<&mut Child> {
            self.child.as_mut()
        }
    }

    fn bytes<'a>(pointer: *const u8, length: usize) -> Option<&'a [u8]> {
        if pointer.is_null() && length != 0 {
            return None;
        }
        if length == 0 {
            return Some(&[]);
        }
        Some(unsafe { slice::from_raw_parts(pointer, length) })
    }

    /// Makes a descriptor nonblocking, and on the platforms that can, quiet about
    /// `SIGPIPE`.
    ///
    /// Only ever applied to an end this process keeps. `O_NONBLOCK` lives on the open
    /// file description, so a descriptor shared with the child would make the child's
    /// own stdin or stdout nonblocking -- and a child that gets `EAGAIN` from what it
    /// believes is a plain write usually fails. The ends a child receives are wired by
    /// `Command` and never come through here.
    /// `F_SETNOSIGPIPE`, where the platform has it.
    ///
    /// Per target, because the number is per target and nothing about it is guessable:
    /// Darwin says 73 and NetBSD says 14, and issuing one platform's number on the
    /// other does not fail harmlessly -- it performs whatever that number means there.
    #[cfg(any(target_os = "macos", target_os = "ios"))]
    const F_SETNOSIGPIPE: libc::c_int = 73;
    #[cfg(target_os = "netbsd")]
    const F_SETNOSIGPIPE: libc::c_int = 14;

    /// Whether this platform can quiet a descriptor rather than mask a signal.
    const QUIETS_PER_DESCRIPTOR: bool =
        cfg!(any(target_os = "macos", target_os = "ios", target_os = "netbsd"));

    fn prepare(fd: RawFd) -> Result<(), std::io::Error> {
        let flags = unsafe { libc::fcntl(fd, libc::F_GETFL, 0) };
        if flags < 0 {
            return Err(std::io::Error::last_os_error());
        }
        if unsafe { libc::fcntl(fd, libc::F_SETFL, flags | libc::O_NONBLOCK) } < 0 {
            return Err(std::io::Error::last_os_error());
        }
        // Where it exists, a descriptor that will not raise `SIGPIPE` is strictly better
        // than a signal mask held across every write: set once, scoped to a descriptor
        // this process owns, and it leaves the host's disposition alone.
        //
        // Its failure is reported rather than shrugged at. This is the whole of the
        // protection on these platforms -- `QUIETS_PER_DESCRIPTOR` turns the masking
        // path off -- so a quiet failure here would leave the host exposed to exactly
        // the signal all of this exists to contain.
        #[cfg(any(target_os = "macos", target_os = "ios", target_os = "netbsd"))]
        if unsafe { libc::fcntl(fd, F_SETNOSIGPIPE, 1) } < 0 {
            return Err(std::io::Error::last_os_error());
        }

        Ok(())
    }

    /// Writes without letting a broken pipe reach the host.
    ///
    /// On a platform with `F_SETNOSIGPIPE` the descriptor was quieted when it was
    /// prepared and this is an ordinary write. Everywhere else the signal is blocked
    /// for the duration, and this is the sequence that has to be got exactly right:
    ///
    /// 1. Block `SIGPIPE` on this thread, keeping the old mask.
    /// 2. Read `sigpending` -- *after* the block, because an unblocked signal is
    ///    delivered rather than left pending, so a check taken first answers "not
    ///    pending" for one about to arrive.
    /// 3. Write.
    /// 4. If the write reported `EPIPE` and `SIGPIPE` was not already pending at step
    ///    2, consume the one it raised, retrying while that fails with `EINTR`. A
    ///    consume abandoned there leaves the signal for step 5 to deliver.
    /// 5. Restore the mask, on every path out.
    ///
    /// Step 4's condition is the careful part. Standard signals are not queued, so a
    /// `SIGPIPE` already pending when the write began is indistinguishable from the one
    /// the write raised, and consuming it steals a signal the host was going to handle.
    /// When it was already there, it is left alone: `EPIPE` still comes back, which is
    /// all this needs.
    ///
    /// What this never does is install a disposition. Ignoring `SIGPIPE` process-wide
    /// would be permanent, global, and the host's choice rather than a library's.
    fn write_quietly(stream: &mut NuppStream, data: &[u8]) -> std::io::Result<usize> {
        // A stream with no writer is a readable one handed to a write, which is a
        // caller's mistake and answers as one. Not a panic: a panic reaching an
        // `extern "C"` boundary does not unwind into the caller -- the non-unwinding ABI
        // catches it and aborts -- and this is a library loaded into somebody else's
        // process, so aborting takes the host down with it. Answering is the only option
        // that leaves anyone to read the answer.
        let Some(writer) = stream.writer.as_mut() else {
            return Err(std::io::Error::other("this stream is not writable"));
        };
        if QUIETS_PER_DESCRIPTOR {
            return writer.write(data);
        }

        unsafe {
            let mut blocked: libc::sigset_t = std::mem::zeroed();
            libc::sigemptyset(&mut blocked);
            libc::sigaddset(&mut blocked, libc::SIGPIPE);
            let mut previous: libc::sigset_t = std::mem::zeroed();
            // `pthread_sigmask` reports through its return value, not `errno`.
            let blocking = libc::pthread_sigmask(libc::SIG_BLOCK, &blocked, &mut previous);
            if blocking != 0 {
                return Err(std::io::Error::from_raw_os_error(blocking));
            }

            let mut pending: libc::sigset_t = std::mem::zeroed();
            libc::sigemptyset(&mut pending);
            if libc::sigpending(&mut pending) != 0 {
                // Without knowing whether a `SIGPIPE` was already waiting, there is no
                // safe way to finish: consume afterwards and this may steal the host's,
                // decline to and a signal this write raised is delivered the moment the
                // mask comes off. So the write does not happen. Not writing is a
                // recoverable disappointment; the alternatives are losing someone
                // else's signal or killing the process.
                let failure = std::io::Error::last_os_error();
                // A failed restore takes precedence over a failed inspection. Not
                // knowing the pending state costs this one write; a mask left changed
                // costs every write the host makes afterwards, and is the one a caller
                // most needs to hear about.
                if let Err(worse) = restore(&previous) {
                    return Err(worse);
                }

                return Err(failure);
            }
            let already = libc::sigismember(&pending, libc::SIGPIPE) == 1;

            let outcome = writer.write(data);

            if !already && matches!(&outcome, Err(error) if error.kind() == ErrorKind::BrokenPipe) {
                if let Err(failure) = consume_sigpipe(&blocked) {
                    // A `SIGPIPE` this write raised, still pending, and no way to take
                    // it. Restoring the mask now delivers it, and under the default
                    // disposition that ends the process -- so the mask stays as it is
                    // and the caller is told. A thread with `SIGPIPE` blocked is a
                    // changed host, which is bad; a dead host is worse, and this way
                    // there is someone left to read the message.
                    return Err(failure);
                }
            }

            // A failed restore outranks a successful write. The bytes did go, and
            // saying so while leaving the host's mask changed would trade a fact the
            // caller can recover from for one it cannot even see.
            restore(&previous)?;

            outcome
        }
    }

    /// Puts a saved mask back.
    ///
    /// Answers the failure rather than recording it, because a write that could not put
    /// the mask back has not finished successfully whatever the write itself did:
    /// leaving `SIGPIPE` blocked changes every later write in the host as surely as
    /// ignoring it would, and a caller told "wrote 12 bytes" would never learn.
    unsafe fn restore(previous: &libc::sigset_t) -> Result<(), std::io::Error> {
        let restoring = libc::pthread_sigmask(libc::SIG_SETMASK, previous, std::ptr::null_mut());
        if restoring != 0 {
            return Err(std::io::Error::from_raw_os_error(restoring));
        }

        Ok(())
    }

    /// Takes the one `SIGPIPE` this thread just raised.
    ///
    /// Answers `Ok` when there is nothing left pending -- either because it was taken,
    /// or because `sigtimedwait` timed out, which with a zero timeout is how the kernel
    /// says the set is empty. `EINTR` is retried, since an interrupted wait consumed
    /// nothing. Any other failure means a signal may still be waiting and this cannot
    /// tell, which is the one case the caller must not treat as done.
    #[cfg(not(any(target_os = "macos", target_os = "ios", target_os = "netbsd")))]
    unsafe fn consume_sigpipe(set: &libc::sigset_t) -> Result<(), std::io::Error> {
        let timeout = libc::timespec {
            tv_sec: 0,
            tv_nsec: 0,
        };
        loop {
            if libc::sigtimedwait(set, std::ptr::null_mut(), &timeout) >= 0 {
                return Ok(());
            }
            let failure = std::io::Error::last_os_error();
            match failure.raw_os_error() {
                Some(libc::EINTR) => continue,
                // Nothing was pending after all, which is the ordinary answer when the
                // write failed for a reason other than a broken pipe reaching us.
                Some(libc::EAGAIN) => return Ok(()),
                _ => return Err(failure),
            }
        }
    }

    /// Never reached: these platforms quiet the descriptor instead, and have no
    /// `sigtimedwait` to call. Present so the masking path still compiles as one piece.
    #[cfg(any(target_os = "macos", target_os = "ios", target_os = "netbsd"))]
    unsafe fn consume_sigpipe(_set: &libc::sigset_t) -> Result<(), std::io::Error> {
        Ok(())
    }

    /// Begins describing a spawn. Answers a request the caller fills in and then runs.
    #[no_mangle]
    pub extern "C" fn nuppProcessSpawnBegin() -> *mut NuppSpawn {
        Box::into_raw(Box::new(NuppSpawn {
            args: Vec::new(),
            env: Vec::new(),
            cwd: None,
            clear_env: false,
            modes: [MODE_PIPE, MODE_PIPE, MODE_PIPE],
        }))
    }

    /// Adds one argument. The first is the program, resolved through `PATH`.
    #[no_mangle]
    pub unsafe extern "C" fn nuppProcessSpawnArg(
        request: *mut NuppSpawn,
        text: *const u8,
        length: usize,
    ) -> bool {
        let (Some(request), Some(text)) = (request.as_mut(), bytes(text, length)) else {
            return false;
        };
        request.args.push(OsString::from_vec(text.to_vec()));

        true
    }

    /// Adds one `KEY=VALUE`. The whole environment is built this way, including the
    /// inherited one: `posix_spawn` has no spelling for "inherit", so there is no
    /// shortcut worth having and every case is the same case.
    #[no_mangle]
    pub unsafe extern "C" fn nuppProcessSpawnEnv(
        request: *mut NuppSpawn,
        text: *const u8,
        length: usize,
    ) -> bool {
        let (Some(request), Some(text)) = (request.as_mut(), bytes(text, length)) else {
            return false;
        };
        request.env.push(OsString::from_vec(text.to_vec()));

        true
    }

    /// Starts the child's environment from nothing rather than from this process's.
    ///
    /// Separate from adding entries, because otherwise the two questions collapse:
    /// "cleared, with nothing in it" and "inherit" would be the same request, and one
    /// of them would be unaskable.
    #[no_mangle]
    pub unsafe extern "C" fn nuppProcessSpawnClearEnv(request: *mut NuppSpawn, clear: bool) -> bool {
        let Some(request) = request.as_mut() else {
            return false;
        };
        request.clear_env = clear;

        true
    }

    /// Where the child runs, if not here.
    #[no_mangle]
    pub unsafe extern "C" fn nuppProcessSpawnCwd(
        request: *mut NuppSpawn,
        text: *const u8,
        length: usize,
    ) -> bool {
        let (Some(request), Some(text)) = (request.as_mut(), bytes(text, length)) else {
            return false;
        };
        request.cwd = Some(OsString::from_vec(text.to_vec()));

        true
    }

    /// How one of the child's three standard streams is connected. `which` is 0, 1 or
    /// 2; `MODE_STDOUT` is stderr's alone.
    #[no_mangle]
    pub unsafe extern "C" fn nuppProcessSpawnStdio(
        request: *mut NuppSpawn,
        which: u8,
        mode: u8,
    ) -> bool {
        let Some(request) = request.as_mut() else {
            return false;
        };
        if which > 2 || mode > MODE_STDOUT || (mode == MODE_STDOUT && which != 2) {
            return false;
        }
        request.modes[which as usize] = mode;

        true
    }

    /// Abandons a request that will not be run.
    #[no_mangle]
    pub unsafe extern "C" fn nuppProcessSpawnCancel(request: *mut NuppSpawn) {
        if !request.is_null() {
            drop(Box::from_raw(request));
        }
    }

    /// One pipe whose write end the child receives twice, and whose read end stays
    /// here.
    ///
    /// Close-on-exec matters on both ends: it does not stop the child receiving the two
    /// it is given -- `dup2` clears the flag on what it creates -- but it does stop
    /// anything else in the host spawning concurrently from inheriting copies and
    /// holding the pipe open against a reader waiting for end of stream.
    ///
    /// Where `pipe2` exists the descriptors are close-on-exec from the instant they do,
    /// and there is no window. macOS has no `pipe2`, so there the flag is set just
    /// afterwards and a window really is open between the two calls: a concurrent spawn
    /// in that instant inherits them. That is a constraint on the host rather than
    /// something this can close, and it is written down instead of being papered over.
    fn joined_pipe() -> Result<(OwnedFd, OwnedFd, OwnedFd), std::io::Error> {
        let mut ends = [0 as libc::c_int; 2];

        #[cfg(any(
            target_os = "linux",
            target_os = "android",
            target_os = "freebsd",
            target_os = "netbsd",
            target_os = "openbsd"
        ))]
        let made = unsafe { libc::pipe2(ends.as_mut_ptr(), libc::O_CLOEXEC) };

        #[cfg(not(any(
            target_os = "linux",
            target_os = "android",
            target_os = "freebsd",
            target_os = "netbsd",
            target_os = "openbsd"
        )))]
        let made = unsafe { libc::pipe(ends.as_mut_ptr()) };

        if made != 0 {
            return Err(std::io::Error::last_os_error());
        }
        let read_end = unsafe { OwnedFd::from_raw_fd(ends[0]) };
        let write_end = unsafe { OwnedFd::from_raw_fd(ends[1]) };

        #[cfg(not(any(
            target_os = "linux",
            target_os = "android",
            target_os = "freebsd",
            target_os = "netbsd",
            target_os = "openbsd"
        )))]
        for end in [&read_end, &write_end] {
            if unsafe { libc::fcntl(end.as_raw_fd(), libc::F_SETFD, libc::FD_CLOEXEC) } < 0 {
                return Err(std::io::Error::last_os_error());
            }
        }

        let second = write_end.try_clone()?;

        Ok((read_end, write_end, second))
    }

    /// A close-on-exec copy of one of this process's own descriptors, for a child that
    /// should write where this one does rather than to the slot of the same number.
    fn duplicate(fd: RawFd) -> Result<OwnedFd, std::io::Error> {
        // `F_DUPFD_CLOEXEC` makes the copy and marks it in one call, so no window opens
        // in which a concurrent spawn could inherit it.
        let copy = unsafe { libc::fcntl(fd, libc::F_DUPFD_CLOEXEC, 0) };
        if copy < 0 {
            return Err(std::io::Error::last_os_error());
        }

        Ok(unsafe { OwnedFd::from_raw_fd(copy) })
    }

    fn stdio_for(mode: u8) -> Stdio {
        match mode {
            MODE_INHERIT => Stdio::inherit(),
            MODE_NULL => Stdio::null(),
            _ => Stdio::piped(),
        }
    }

    /// Runs a request, consuming it. Answers the child, or null with `nuppNativeError`
    /// saying why.
    #[no_mangle]
    pub unsafe extern "C" fn nuppProcessSpawnRun(request: *mut NuppSpawn) -> *mut NuppChild {
        if request.is_null() {
            set_error("no spawn request");

            return std::ptr::null_mut();
        }
        let request = *Box::from_raw(request);
        if request.args.is_empty() {
            set_error("a spawn needs a program to run");

            return std::ptr::null_mut();
        }

        let mut command = Command::new(&request.args[0]);
        command.args(&request.args[1..]);
        command.stdin(stdio_for(request.modes[0]));

        // Joining stderr to stdout has to be arranged before the spawn, not after: the
        // child's two descriptors must already be the same pipe when it starts, and
        // there is no merging a pipe that was made separately. So one pipe is made
        // here, its write end is handed to the child twice, and the single read end is
        // what this process keeps -- one descriptor with one owner, where returning the
        // same stream under two names would have been two owners of one.
        let mut merged = None;
        if request.modes[2] == MODE_STDOUT {
            // "Where stdout goes", which is not always a pipe. A child told to inherit
            // its stdout and join its stderr to it wants both on the terminal; forcing
            // a pipe would capture output the caller asked to be left alone, and then
            // nobody would be reading it.
            match request.modes[1] {
                MODE_PIPE => match joined_pipe() {
                    Ok((read_end, first, second)) => {
                        command.stdout(Stdio::from(first));
                        command.stderr(Stdio::from(second));
                        merged = Some(read_end);
                    }
                    Err(error) => {
                        set_error(error);

                        return std::ptr::null_mut();
                    }
                },
                MODE_NULL => {
                    // Both discarded, which really is the same destination.
                    command.stdout(Stdio::null());
                    command.stderr(Stdio::null());
                }
                mode => {
                    // Inheriting is per descriptor: `Stdio::inherit()` on stderr gives
                    // the child *this* process's descriptor 2, which is only stdout's
                    // destination when the two happen to point at the same place. A
                    // parent whose own stdout is redirected and whose stderr is not
                    // would have its child's streams land in two different places,
                    // having asked for one.
                    //
                    // So stdout is inherited and stderr is a duplicate of this
                    // process's descriptor 1 -- the destination, not the slot.
                    command.stdout(stdio_for(mode));
                    match duplicate(libc::STDOUT_FILENO) {
                        Ok(copy) => {
                            command.stderr(Stdio::from(copy));
                        }
                        Err(error) => {
                            set_error(error);

                            return std::ptr::null_mut();
                        }
                    }
                }
            }
        } else {
            command.stdout(stdio_for(request.modes[1]));
            command.stderr(stdio_for(request.modes[2]));
        }
        if let Some(cwd) = &request.cwd {
            command.current_dir(cwd);
        }
        if request.clear_env {
            command.env_clear();
        }
        {
            for entry in &request.env {
                let raw = entry.clone().into_vec();
                match raw.iter().position(|byte| *byte == b'=') {
                    Some(at) => command.env(
                        OsString::from_vec(raw[..at].to_vec()),
                        OsString::from_vec(raw[at + 1..].to_vec()),
                    ),
                    None => {
                        set_error(format!("environment entry has no '=': {:?}", entry));

                        return std::ptr::null_mut();
                    }
                };
            }
        }

        match command.spawn() {
            Ok(child) => Box::into_raw(Box::new(NuppChild {
                child: Some(child),
                exit: None,
                released: false,
                merged: merged.map(std::fs::File::from),
            })),
            Err(error) => {
                set_error(error);

                std::ptr::null_mut()
            }
        }
    }

    /// Takes one of the child's piped streams, handing over the obligation to close it.
    /// Answers null for a stream that was not piped, or one already taken.
    ///
    /// `which` is 0 for stdin, 1 for stdout, 2 for stderr.
    #[no_mangle]
    pub unsafe extern "C" fn nuppProcessTakeStream(
        child: *mut NuppChild,
        which: u8,
    ) -> *mut NuppStream {
        let Some(child) = child.as_mut() else {
            return std::ptr::null_mut();
        };
        if let Some(joined) = child.merged.take() {
            if which == 1 {
                let fd = joined.as_raw_fd();
                if let Err(error) = prepare(fd) {
                    set_error(error);

                    return std::ptr::null_mut();
                }

                return Box::into_raw(Box::new(NuppStream {
                    fd,
                    reader: Some(Box::new(joined) as Box<dyn Read + Send>),
                    writer: None,
                    released: false,
                }));
            }
            // Put it back: only stdout answers a joined pipe, and stderr answering null
            // is the honest report that it has no stream of its own.
            child.merged = Some(joined);
            if which == 2 {
                return std::ptr::null_mut();
            }
        }
        let Some(running) = child.running() else {
            return std::ptr::null_mut();
        };
        let stream = match which {
            0 => running.stdin.take().map(|end| {
                let fd = end.as_raw_fd();
                (fd, None::<Box<dyn Read + Send>>, Some(Box::new(end) as Box<dyn Write + Send>))
            }),
            1 => running.stdout.take().map(|end| {
                let fd = end.as_raw_fd();
                (fd, Some(Box::new(end) as Box<dyn Read + Send>), None)
            }),
            2 => running.stderr.take().map(|end| {
                let fd = end.as_raw_fd();
                (fd, Some(Box::new(end) as Box<dyn Read + Send>), None)
            }),
            _ => None,
        };
        let Some((fd, reader, writer)) = stream else {
            return std::ptr::null_mut();
        };
        if let Err(error) = prepare(fd) {
            set_error(error);

            return std::ptr::null_mut();
        }

        Box::into_raw(Box::new(NuppStream {
            fd,
            reader,
            writer,
            released: false,
        }))
    }

    /// Reads up to `limit` bytes without waiting.
    ///
    /// Answers how many landed, or `WOULD_BLOCK`, `GONE` at end of stream, or `FAILED`.
    /// `limit` is always one or more -- the state machine normalises what its callers
    /// ask for -- so nothing here has to decide what a zero-length read would mean.
    #[no_mangle]
    pub unsafe extern "C" fn nuppProcessTryRead(
        stream: *mut NuppStream,
        buffer: *mut u8,
        limit: usize,
    ) -> isize {
        let Some(stream) = stream.as_mut() else {
            set_error("no stream");

            return FAILED;
        };
        if buffer.is_null() || limit == 0 {
            set_error("a read needs room for at least one byte");

            return FAILED;
        }
        let Some(reader) = stream.reader.as_mut() else {
            set_error("this stream is not readable");

            return FAILED;
        };
        let destination = slice::from_raw_parts_mut(buffer, limit);
        match reader.read(destination) {
            Ok(0) => GONE,
            Ok(count) => count as isize,
            Err(error) if error.kind() == ErrorKind::WouldBlock => WOULD_BLOCK,
            Err(error) if error.kind() == ErrorKind::Interrupted => WOULD_BLOCK,
            Err(error) => {
                set_error(error);

                FAILED
            }
        }
    }

    /// Writes what the pipe will take without waiting.
    ///
    /// Answers how many bytes went, or `WOULD_BLOCK`, `GONE` when nobody is reading and
    /// nobody will, or `FAILED`. The two zeroes a naive interface conflates -- no room
    /// yet, no reader ever -- are the whole reason this answers `GONE` separately.
    #[no_mangle]
    pub unsafe extern "C" fn nuppProcessTryWrite(
        stream: *mut NuppStream,
        buffer: *const u8,
        length: usize,
    ) -> isize {
        let Some(stream) = stream.as_mut() else {
            set_error("no stream");

            return FAILED;
        };
        let Some(source) = bytes(buffer, length) else {
            set_error("a write needs bytes to send");

            return FAILED;
        };
        // Answered `FAILED` rather than `GONE`, and that is the whole point of the
        // check. `GONE` is a claim about the far end -- nobody is reading this and
        // nobody will -- which a stream this caller closed says nothing about. The
        // other way to reach the same confusion is a readable stream passed here by
        // mistake; that is caught below, in the borrow, and answers `FAILED` too.
        // Letting either arrive as a synthesised broken pipe made a caller's mistake
        // indistinguishable from news about a pipe.
        if stream.released {
            set_error("this stream has been closed");

            return FAILED;
        }
        if source.is_empty() {
            return 0;
        }
        match write_quietly(stream, source) {
            Ok(count) => count as isize,
            Err(error) if error.kind() == ErrorKind::WouldBlock => WOULD_BLOCK,
            Err(error) if error.kind() == ErrorKind::Interrupted => WOULD_BLOCK,
            Err(error) if error.kind() == ErrorKind::BrokenPipe => GONE,
            Err(error) => {
                set_error(error);

                FAILED
            }
        }
    }

    /// Closes one end. Answers `RELEASED`, `RELEASED_WITH_REASON` or `NOT_RELEASED`.
    ///
    /// What is released is the descriptor, and only that. The handle stays valid
    /// afterwards -- a readiness wait may still name it, and calling this again answers
    /// `RELEASED` without troubling the platform -- but it carries no more bytes:
    /// `nuppProcessTryRead` and `nuppProcessTryWrite` both answer `FAILED`.
    ///
    /// Neither answers `GONE`, and that matters. `GONE` is a fact about the far end --
    /// this stream is finished because nothing over there is listening or sending -- and
    /// a stream this caller closed says nothing whatever about the child's end of it.
    /// Valid to speak to, finished to move bytes through.
    ///
    /// Only `nuppProcessStreamDestroy` ends the handle.
    ///
    /// Never panics across the boundary: the caller's next move depends entirely on
    /// which of those three it is told, and an unwinding panic tells it nothing.
    #[no_mangle]
    pub unsafe extern "C" fn nuppProcessCloseStream(stream: *mut NuppStream) -> u8 {
        let Some(stream) = stream.as_mut() else {
            set_error("no stream");

            return NOT_RELEASED;
        };
        if stream.released {
            return RELEASED;
        }
        let outcome = catch_unwind(AssertUnwindSafe(|| {
            stream.reader = None;
            stream.writer = None;
        }));
        // Dropped either way: the descriptor went with the handle, whatever the drop
        // thought of it, and reporting otherwise would invite a retry to close whatever
        // has since been given that number.
        stream.released = true;
        stream.fd = -1;
        match outcome {
            Ok(()) => RELEASED,
            Err(_) => {
                set_error("closing the stream panicked");

                RELEASED_WITH_REASON
            }
        }
    }

    /// Ends the handle itself. The descriptor is closed first if it still holds one.
    ///
    /// After this the pointer is dead: naming it to a readiness wait, or passing it to
    /// anything else here, reads memory that has been freed.
    ///
    /// The two are not degrees of the same act. Closing ends the descriptor, which is
    /// as permanent as this is -- what survives it is the allocation, so the handle can
    /// still be spoken to and the answers stay sensible. Destroying ends the allocation,
    /// and there is nothing left to speak to. So this belongs at the end of the owning
    /// `Process`'s life rather than at the end of the stream's usefulness.
    #[no_mangle]
    pub unsafe extern "C" fn nuppProcessStreamDestroy(stream: *mut NuppStream) {
        if !stream.is_null() {
            drop(Box::from_raw(stream));
        }
    }

    /// Asks after the child without waiting.
    ///
    /// Answers 1 when it has ended, filling in the status and whether a signal ended
    /// it; 0 while it still runs; -1 on failure. The exit is remembered, because the
    /// platform gives a status up when it is collected and a second ask reports no such
    /// child.
    #[no_mangle]
    pub unsafe extern "C" fn nuppProcessPollExit(
        child: *mut NuppChild,
        code: *mut i32,
        killed: *mut bool,
    ) -> i32 {
        let Some(child) = child.as_mut() else {
            set_error("no child");

            return -1;
        };
        if child.exit.is_none() {
            let Some(running) = child.running() else {
                set_error("this child has been handed away");

                return -1;
            };
            match running.try_wait() {
                Ok(Some(status)) => {
                    // A signal leaves no exit code of its own. 128 plus the signal is
                    // what a shell reports, and what tecs's callers already read.
                    let ended = match status.code() {
                        Some(value) => (value, false),
                        None => (128 + signal_of(&status), true),
                    };
                    child.exit = Some(ended);
                }
                Ok(None) => return 0,
                Err(error) => {
                    set_error(error);

                    return -1;
                }
            }
        }
        if let Some((value, was_killed)) = child.exit {
            if !code.is_null() {
                *code = value;
            }
            if !killed.is_null() {
                *killed = was_killed;
            }
        }

        1
    }

    fn signal_of(status: &std::process::ExitStatus) -> i32 {
        use std::os::unix::process::ExitStatusExt;
        status.signal().unwrap_or(0)
    }

    /// How many children were still unaccounted for when their handles were let go.
    ///
    /// `Total` in the name because that is what it is: an event count that only ever
    /// rises, not a gauge of anything current. Nothing here stays around to learn that
    /// a child it signalled has since died, so a reading of twelve means twelve handles
    /// were abandoned unresolved over this process's life -- not that twelve children
    /// are running.
    ///
    /// It rises once per handle dropped without being closed whose single fallback look
    /// did not find the child ended.
    ///
    /// Which is what makes it worth having. A host watching this climb is watching its
    /// own callers leak handles, and that is the fault worth reporting; whether any
    /// particular child outlived its handle is a question nothing here stays around to
    /// answer.
    #[no_mangle]
    pub extern "C" fn nuppProcessUncollectedTotal() -> usize {
        UNCOLLECTED.load(std::sync::atomic::Ordering::Relaxed)
    }

    /// The child's process id, for a caller that has to name it to something else --
    /// a diagnostic, a process group, an unrelated tool. Answers zero for no child.
    #[no_mangle]
    pub unsafe extern "C" fn nuppProcessId(child: *mut NuppChild) -> u32 {
        match child.as_ref() {
            Some(child) => child.child.as_ref().map(|running| running.id()).unwrap_or(0),
            None => 0,
        }
    }

    /// Asks the child to end, or insists. `force` sends `SIGKILL`, otherwise `SIGTERM`.
    #[no_mangle]
    pub unsafe extern "C" fn nuppProcessKill(child: *mut NuppChild, force: bool) -> bool {
        let Some(child) = child.as_mut() else {
            set_error("no child");

            return false;
        };
        if child.exit.is_some() {
            // Already ended, so there is nothing to signal and nothing wrong. Signalling
            // anyway would reach whatever now holds that pid.
            return true;
        }
        let signal = if force { libc::SIGKILL } else { libc::SIGTERM };
        let Some(pid) = child.child.as_ref().map(|running| running.id() as libc::pid_t) else {
            set_error("this child has been handed away");

            return false;
        };
        if libc::kill(pid, signal) == 0 {
            return true;
        }
        let error = std::io::Error::last_os_error();
        // The child ended between the poll above and this signal, which is a race
        // nothing can close and not a failure: what was asked for has happened.
        if error.raw_os_error() == Some(libc::ESRCH) {
            return true;
        }
        set_error(error);

        false
    }

    /// Releases the child once it has ended. Answers on `closeStream`'s terms.
    ///
    /// A pid is reused as readily as a descriptor, so the caller has to be told whether
    /// this one is still theirs to ask about -- and told by a return, never by an
    /// unwinding panic, which would say nothing at all.
    #[no_mangle]
    pub unsafe extern "C" fn nuppProcessReap(child: *mut NuppChild) -> u8 {
        let Some(child) = child.as_mut() else {
            set_error("no child");

            return NOT_RELEASED;
        };
        if child.released {
            return RELEASED;
        }
        if child.exit.is_none() {
            set_error("the child has not ended, so there is nothing to reap");

            return NOT_RELEASED;
        }
        // `try_wait` already collected the status, so the pid is gone and this is
        // bookkeeping. It is still wrapped, because the contract is that this answers
        // rather than unwinds.
        let outcome = catch_unwind(AssertUnwindSafe(|| {
            if let Some(running) = child.child.as_mut() {
                let _ = running.try_wait();
            }
        }));
        child.released = true;
        match outcome {
            Ok(()) => RELEASED,
            Err(_) => {
                set_error("reaping the child panicked");

                RELEASED_WITH_REASON
            }
        }
    }

    /// How many children this has let go of without knowing they had ended.
    ///
    /// A count rather than a message, because a host that wants to know cannot be
    /// handed one: `LAST_ERROR` is thread-local and this is reported from whichever
    /// thread happened to be dropping. A number a caller can ask for at any time says
    /// the same thing and can actually be heard.
    static UNCOLLECTED: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(0);

    /// Whether one `try_wait` says the child is no longer ours to account for.
    ///
    /// `ECHILD` counts. A host that reaps its own children -- `SIGCHLD` set to
    /// `SIG_IGN`, or its own handler -- leaves nothing here to wait for, and reading
    /// that as "still running" would report a leak that did not happen.
    fn resolved(answer: Result<Option<std::process::ExitStatus>, std::io::Error>) -> bool {
        match answer {
            Ok(Some(_)) => true,
            Err(failure) => failure.raw_os_error() == Some(libc::ECHILD),
            Ok(None) => false,
        }
    }

    /// The last resort, for a handle dropped without being closed.
    ///
    /// `nuppProcessCloseStream` and `nuppProcessReap` are the guarantee; this runs only
    /// when a caller has already failed to use them, and its job is to make that failure
    /// cheap and visible rather than to repair it. Rust is explicit that dropping a
    /// `Child` neither kills nor waits, so without something here an abandoned handle
    /// leaves a live process or a zombie and says nothing.
    ///
    /// Signal once, look once, and count what is still unresolved. Nothing more: this
    /// runs during whatever the host was doing -- a collection, a finalizer, an unwind --
    /// and none of those may be made to wait on another process. An earlier version
    /// carried a collector thread, a bounded queue and a population count to chase the
    /// stragglers, which was a great deal of machinery guarding a path that only runs
    /// after the real contract has already been broken, and every part of it was
    /// somewhere else for a bug to be.
    ///
    /// `SIGKILL` rather than `SIGTERM`, because there is nobody left to wait politely:
    /// the handle is going away this instant and a child given the chance to clean up
    /// would simply be un-owned instead. A caller who wants the polite version calls
    /// `nuppProcessKill` and waits, which is what the state machine above does -- and
    /// that path is synchronous, because there the caller chose to wait.
    impl Drop for NuppChild {
        fn drop(&mut self) {
            if self.released {
                return;
            }
            let Some(mut stray) = self.child.take() else {
                return;
            };
            let mut unsignalled = false;
            if self.exit.is_none() {
                unsignalled = stray.kill().is_err();
            }
            account_for(stray.try_wait(), unsignalled);
        }
    }

    /// Records what one look found, and answers whether it had to be counted.
    ///
    /// Separated from the drop because the drop cannot be asked a settled question: it
    /// signals and then looks, and whether `SIGKILL` has landed by the next instruction
    /// is the kernel's business. A test driving the real thing would be asserting on
    /// that race. Here the answer is handed in.
    fn account_for(
        answer: Result<Option<std::process::ExitStatus>, std::io::Error>,
        unsignalled: bool,
    ) -> bool {
        if resolved(answer) {
            return false;
        }

        UNCOLLECTED.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
        set_error(if unsignalled {
            // The worse of the two, and worth saying apart: nothing has asked it to
            // stop, so it runs to completion rather than lingering as a zombie.
            "an abandoned child could not be signalled, so it is still running"
        } else {
            "an abandoned child was signalled but had not ended, so it was left"
        });

        true
    }

    /// The accounting decision, for a test that wants to hand it an answer rather than
    /// race the kernel for one.
    #[cfg(test)]
    pub(crate) fn account_for_test(
        answer: Result<Option<std::process::ExitStatus>, std::io::Error>,
        unsignalled: bool,
    ) -> bool {
        account_for(answer, unsignalled)
    }

    /// Whether the child has already ended, for a test that needs to know which of the
    /// two the drop is about to do.
    #[cfg(test)]
    pub(crate) fn resolved_for_test(
        answer: Result<Option<std::process::ExitStatus>, std::io::Error>,
    ) -> bool {
        resolved(answer)
    }

    /// Releases a child handle. A child not already reaped is killed and collected
    /// rather than abandoned -- see the `Drop` above.
    #[no_mangle]
    pub unsafe extern "C" fn nuppProcessDestroy(child: *mut NuppChild) {
        if !child.is_null() {
            drop(Box::from_raw(child));
        }
    }

    /// Waits until one of the named streams is ready, for at most `timeout_ms`.
    ///
    /// The streams are named by their own opaque handles, not by descriptors. A
    /// descriptor is a POSIX idea: a Win32 `HANDLE` is pointer-sized and would not fit
    /// the `int32_t` a descriptor array implies, and readiness there may be an event
    /// object rather than the pipe handle at all. Handing whole streams across lets this
    /// side wait on whatever the platform actually waits on, and keeps a caller from
    /// having to hold a platform's descriptor in order to ask a neutral question.
    ///
    /// Answers how many became ready, which may be zero, or -1 on failure. A stream
    /// already *closed* is skipped rather than refused: a drain loop naturally still
    /// names one it has finished with, and there is nothing left to wait for there.
    ///
    /// A stream already *destroyed* is a different matter, and the caller's to avoid.
    /// `nuppProcessCloseStream` releases the descriptor and leaves the handle alive and
    /// safe to name; `nuppProcessStreamDestroy` frees the handle itself, and naming one
    /// afterwards reads memory that is gone. Nothing here can detect that -- a freed
    /// pointer is not distinguishable from a live one -- so it is stated rather than
    /// checked: name closed streams freely, destroyed ones never.
    ///
    /// A null entry inside the count is refused rather than skipped. Skipping would turn
    /// a binding that built its array wrongly into a wait that quietly watched fewer
    /// things than asked and came back on the timeout, which looks exactly like a quiet
    /// child. The caller compacts; this says when they did not.
    ///
    /// With both lists empty this is a bounded sleep and nothing else, which is what
    /// waiting on the child alone amounts to: nothing here can watch a pid, so an exit
    /// is noticed by the `pollExit` its caller does on waking rather than by anything
    /// here.
    #[no_mangle]
    pub unsafe extern "C" fn nuppProcessWaitReady(
        readable: *const *mut NuppStream,
        readable_count: usize,
        writable: *const *mut NuppStream,
        writable_count: usize,
        timeout_ms: i32,
    ) -> i32 {
        let mut slots: Vec<libc::pollfd> = Vec::with_capacity(readable_count + writable_count);
        for (list, count, events) in [
            (readable, readable_count, libc::POLLIN),
            (writable, writable_count, libc::POLLOUT),
        ] {
            if count > 0 {
                if list.is_null() {
                    set_error("a readiness wait was given a count without streams");

                    return -1;
                }
                for entry in slice::from_raw_parts(list, count) {
                    let Some(stream) = entry.as_ref() else {
                        set_error("a readiness wait was given a null stream inside its count");

                        return -1;
                    };
                    if stream.released {
                        continue;
                    }
                    slots.push(libc::pollfd {
                        fd: stream.fd,
                        events: events as libc::c_short,
                        revents: 0,
                    });
                }
            }
        }

        // A negative timeout means "forever" to `poll`, which is the one thing this
        // must never do: every caller above is bounded, and the usual way to arrive
        // here negative is a deadline that has already passed -- which asks for no wait
        // at all rather than an endless one.
        let bounded = timeout_ms.max(0);
        let ready = libc::poll(slots.as_mut_ptr(), slots.len() as libc::nfds_t, bounded);
        if ready >= 0 {
            return ready;
        }
        let error = std::io::Error::last_os_error();
        // Interrupted before anything was ready, which is a wait that ended early rather
        // than one that failed: the caller re-checks and waits again.
        if error.raw_os_error() == Some(libc::EINTR) {
            return 0;
        }
        set_error(error);

        -1
    }
}

#[cfg(all(
    test,
    any(
        feature = "files",
        feature = "sha256",
        feature = "uuid",
        feature = "path",
        feature = "uri"
    )
))]
mod tests {
    use super::*;
    use std::ffi::CStr;

    #[cfg(feature = "files")]
    #[test]
    fn globs_recurse_sort_and_report_invalid_patterns() {
        use std::hash::{BuildHasher, Hasher, RandomState};

        let stamp = RandomState::new().build_hasher().finish();
        let root = std::env::temp_dir().join(format!("nupp-glob-{stamp:016x}"));
        std::fs::create_dir_all(root.join("nested/deep")).expect("test directories");
        for name in ["root.nupp", "nested/child.nupp", "nested/deep/leaf.nupp"] {
            std::fs::write(root.join(name), name).expect("test file");
        }
        std::fs::write(root.join("nested/deep/ignored.lua"), "ignored").expect("other file");

        let pattern = root.join("**/*.nupp").into_os_string().into_string().expect("UTF-8 path");
        let handle = unsafe { files::nuppFilesGlob(pattern.as_ptr(), pattern.len()) };
        assert!(!handle.is_null(), "the pattern expanded");
        let result = unsafe {
            String::from_utf8(slice::from_raw_parts(nuppBytesData(handle), nuppBytesLength(handle)).to_vec())
                .expect("UTF-8 matches")
        };
        unsafe { nuppBytesDestroy(handle) };
        let expected = [
            root.join("nested/child.nupp"),
            root.join("nested/deep/leaf.nupp"),
            root.join("root.nupp"),
        ]
        .into_iter()
        .map(|path| path.into_os_string().into_string().expect("UTF-8 path"))
        .collect::<Vec<_>>();
        assert_eq!(result.split('\0').collect::<Vec<_>>(), expected);

        let flat = root.join("*.nupp").into_os_string().into_string().expect("UTF-8 path");
        let handle = unsafe { files::nuppFilesGlob(flat.as_ptr(), flat.len()) };
        assert!(!handle.is_null(), "the flat pattern expanded");
        let result = unsafe {
            String::from_utf8(slice::from_raw_parts(nuppBytesData(handle), nuppBytesLength(handle)).to_vec())
                .expect("UTF-8 matches")
        };
        unsafe { nuppBytesDestroy(handle) };
        assert_eq!(result, root.join("root.nupp").to_string_lossy());

        let invalid = root.join("[").into_os_string().into_string().expect("UTF-8 path");
        assert!(unsafe { files::nuppFilesGlob(invalid.as_ptr(), invalid.len()) }.is_null());
        assert!(!unsafe { CStr::from_ptr(nuppNativeError()) }.to_bytes().is_empty());
        std::fs::remove_dir_all(root).expect("remove test directory");
    }

    // The lane's accounting is process-global, so its cases share one test
    // rather than racing each other for the budget they are each about.
    #[cfg(feature = "files")]
    #[test]
    fn the_lane_settles_bounds_and_refunds_transfers() {
        use files::lane::*;
        use std::hash::{BuildHasher, Hasher, RandomState};

        let stamp = RandomState::new().build_hasher().finish();
        let root = std::env::temp_dir().join(format!("nupp-lane-{stamp:016x}"));
        std::fs::create_dir_all(&root).expect("test directory");
        let submit = |name: &str, contents: &[u8], mode: u32| {
            let path = root.join(name);
            let text = path.to_str().expect("utf-8 path").to_owned();
            unsafe {
                nuppFsSubmitWrite(
                    text.as_ptr(),
                    text.len(),
                    contents.as_ptr(),
                    contents.len(),
                    mode,
                )
            }
        };
        let await_settled = |request: *mut NuppRequest| {
            while unsafe { nuppFsStatus(request) } == STATUS_PENDING {
                nuppFsWait(200);
            }
            unsafe { nuppFsStatus(request) }
        };

        // Many transfers settle concurrently, and the budget comes back.
        let before = nuppFsPending();
        let mut writes = Vec::new();
        for index in 0..32 {
            let request = submit(&format!("file-{index}.bin"), b"payload", 0);
            assert!(!request.is_null(), "the lane accepted the transfer");
            writes.push(request);
        }
        for request in &writes {
            assert_eq!(await_settled(*request), STATUS_READY);
        }
        for request in writes {
            unsafe { nuppFsDestroy(request) };
        }
        assert_eq!(nuppFsPending(), before, "settled transfers return their slot");

        // Releasing the instant the result appears returns the budget then, not
        // whenever the worker gets around to letting go of the state it shares
        // with the caller. Repeated, because the window this closes is narrow.
        for round in 0..64 {
            let request = submit(&format!("tight-{round}.bin"), b"payload", 0);
            assert!(!request.is_null());
            while unsafe { nuppFsStatus(request) } == STATUS_PENDING {
                std::thread::yield_now();
            }
            unsafe { nuppFsDestroy(request) };
            assert_eq!(
                nuppFsPending(),
                before,
                "a transfer released on sight is accounted for on sight"
            );
        }

        // A read carries the bytes the worker found.
        let path = root.join("file-0.bin");
        let text = path.to_str().expect("utf-8 path").to_owned();
        let read = unsafe { nuppFsSubmitRead(text.as_ptr(), text.len()) };
        assert!(!read.is_null());
        assert_eq!(await_settled(read), STATUS_READY);
        let bytes = unsafe {
            slice::from_raw_parts(nuppFsData(read), nuppFsLength(read))
        };
        assert_eq!(bytes, b"payload");
        unsafe { nuppFsDestroy(read) };

        // A failure carries a reason rather than an empty success.
        let missing = root.join("absent").join("deep.bin");
        let text = missing.to_str().expect("utf-8 path").to_owned();
        let failed = unsafe {
            nuppFsSubmitWrite(text.as_ptr(), text.len(), b"x".as_ptr(), 1, 0)
        };
        assert!(!failed.is_null(), "a write to a missing directory is submitted");
        assert_eq!(await_settled(failed), STATUS_FAILED);
        let reason = unsafe { CStr::from_ptr(nuppFsError(failed)) };
        assert!(!reason.to_bytes().is_empty(), "a failure names itself");
        unsafe { nuppFsDestroy(failed) };

        // A cancelled transfer stops being the caller's, and gives the slot
        // back when the handle goes.
        let cancelled = submit("cancelled.bin", b"payload", 0);
        assert!(!cancelled.is_null());
        unsafe { nuppFsCancel(cancelled) };
        while nuppFsWait(50) == 0 && unsafe { nuppFsStatus(cancelled) } == STATUS_PENDING {}
        assert_eq!(unsafe { nuppFsStatus(cancelled) }, STATUS_CANCELED);
        unsafe { nuppFsDestroy(cancelled) };
        assert_eq!(nuppFsPending(), before, "a cancelled transfer is refunded");

        // The request cap refuses rather than queueing without limit.
        let mut held = Vec::new();
        let mut refused = false;
        for index in 0..200 {
            let request = submit(&format!("held-{index}.bin"), b"x", 0);
            if request.is_null() {
                refused = true;
                break;
            }
            held.push(request);
        }
        assert!(refused, "the lane refuses past its request cap");
        for request in held {
            while unsafe { nuppFsStatus(request) } == STATUS_PENDING {
                nuppFsWait(200);
            }
            unsafe { nuppFsDestroy(request) };
        }
        assert_eq!(nuppFsPending(), before, "the refused run leaks no slots");

        std::fs::remove_dir_all(&root).expect("test cleanup");
    }

    #[cfg(feature = "sha256")]
    #[test]
    fn sha256_matches_a_published_vector() {
        let mut output = [0 as c_char; 65];
        assert!(unsafe { nuppSha256(b"abc".as_ptr(), 3, output.as_mut_ptr()) });
        let text = unsafe { CStr::from_ptr(output.as_ptr()) }.to_str().unwrap();
        assert_eq!(
            text,
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        );
    }

    #[cfg(feature = "uuid")]
    #[test]
    fn uuid_generators_write_the_requested_versions() {
        let mut output = [0 as c_char; 37];
        assert!(nuppUuid4(output.as_mut_ptr()));
        let text = unsafe { CStr::from_ptr(output.as_ptr()) }.to_str().unwrap();
        assert_eq!(uuid::Uuid::parse_str(text).unwrap().get_version_num(), 4);
        assert!(nuppUuid7(output.as_mut_ptr()));
        let text = unsafe { CStr::from_ptr(output.as_ptr()) }.to_str().unwrap();
        assert_eq!(uuid::Uuid::parse_str(text).unwrap().get_version_num(), 7);
    }

    #[cfg(feature = "path")]
    #[test]
    fn paths_normalize_lexically() {
        let input = b"alpha/./beta/../file.txt";
        let bytes = unsafe { path::nuppPathNormalize(input.as_ptr(), input.len()) };
        assert!(!bytes.is_null());
        let output =
            unsafe { slice::from_raw_parts(nuppBytesData(bytes), nuppBytesLength(bytes)).to_vec() };
        unsafe { nuppBytesDestroy(bytes) };
        assert_eq!(output, b"alpha/file.txt");
    }

    #[cfg(feature = "uri")]
    #[test]
    fn uris_parse_and_normalize() {
        let input = b"https://EXAMPLE.com/a/../b?q=1";
        let uri = unsafe { uri::nuppUriParse(input.as_ptr(), input.len()) };
        assert!(!uri.is_null());
        let mut length = 0;
        let data = unsafe { uri::nuppUriPart(uri, 0, &mut length) };
        let output = unsafe { slice::from_raw_parts(data, length) };
        assert_eq!(output, b"https://example.com/b?q=1");
        assert!(unsafe { uri::nuppUriWithPort(uri, 70_000) }.is_null());
        unsafe { uri::nuppUriDestroy(uri) };
    }
}

#[cfg(all(test, feature = "process", unix))]
mod process_tests {
        use crate::process::*;
        use std::os::fd::AsRawFd;

        fn arg(request: *mut NuppSpawn, text: &str) {
            assert!(unsafe { nuppProcessSpawnArg(request, text.as_ptr(), text.len()) });
        }

        /// Spawns `sh -c script` with everything piped, and every environment entry the
        /// test asks for.
        fn spawn(script: &str, env: &[&str]) -> *mut NuppChild {
            spawn_with(script, env, false, false)
        }

        fn spawn_with(
            script: &str,
            env: &[&str],
            clear: bool,
            join_stderr: bool,
        ) -> *mut NuppChild {
            let request = nuppProcessSpawnBegin();
            arg(request, "sh");
            arg(request, "-c");
            arg(request, script);
            if clear {
                assert!(unsafe { nuppProcessSpawnClearEnv(request, true) });
            }
            if join_stderr {
                assert!(unsafe { nuppProcessSpawnStdio(request, 2, MODE_STDOUT) });
            }
            for entry in env {
                assert!(unsafe {
                    nuppProcessSpawnEnv(request, entry.as_ptr(), entry.len())
                });
            }
            let child = unsafe { nuppProcessSpawnRun(request) };
            assert!(!child.is_null(), "the child did not start");

            child
        }

        /// Drains a stream to end, waiting on it rather than spinning.
        fn drain(stream: *mut NuppStream) -> String {
            let mut collected = Vec::new();
            let mut room = [0u8; 4096];
            loop {
                let got = unsafe { nuppProcessTryRead(stream, room.as_mut_ptr(), room.len()) };
                match got {
                    GONE => break,
                    WOULD_BLOCK => {
                        unsafe { nuppProcessWaitReady(&stream, 1, std::ptr::null(), 0, 250) };
                    }
                    FAILED => panic!("the read failed"),
                    count => collected.extend_from_slice(&room[..count as usize]),
                }
            }

            String::from_utf8(collected).expect("the child wrote text")
        }

        fn settle(child: *mut NuppChild) -> (i32, bool) {
            let mut code = -1;
            let mut killed = false;
            for _ in 0..2000 {
                let answer = unsafe { nuppProcessPollExit(child, &mut code, &mut killed) };
                assert!(answer >= 0, "polling the child failed");
                if answer == 1 {
                    return (code, killed);
                }
                unsafe { nuppProcessWaitReady(std::ptr::null(), 0, std::ptr::null(), 0, 5) };
            }
            panic!("the child never ended");
        }

        #[test]
        fn a_child_speaks_and_exits() {
            let child = spawn("printf 'hello from a child'; exit 3", &[]);
            let out = unsafe { nuppProcessTakeStream(child, 1) };
            assert!(!out.is_null());
            let said = drain(out);
            let (code, killed) = settle(child);
            assert_eq!(said, "hello from a child");
            assert_eq!(code, 3);
            assert!(!killed);
            assert_eq!(unsafe { nuppProcessCloseStream(out) }, RELEASED);
            assert_eq!(unsafe { nuppProcessReap(child) }, RELEASED);
            unsafe { nuppProcessStreamDestroy(out) };
            unsafe { nuppProcessDestroy(child) };
        }

        #[test]
        fn stdout_and_stderr_stay_apart() {
            let child = spawn("printf out; printf err >&2", &[]);
            let out = unsafe { nuppProcessTakeStream(child, 1) };
            let err = unsafe { nuppProcessTakeStream(child, 2) };
            assert_eq!(drain(out), "out");
            assert_eq!(drain(err), "err");
            settle(child);
            unsafe { nuppProcessCloseStream(out) };
            unsafe { nuppProcessCloseStream(err) };
            unsafe { nuppProcessReap(child) };
            unsafe { nuppProcessStreamDestroy(out) };
            unsafe { nuppProcessStreamDestroy(err) };
            unsafe { nuppProcessDestroy(child) };
        }

        /// Reports what a script printed, once the child has finished.
        fn say(child: *mut NuppChild) -> String {
            let out = unsafe { nuppProcessTakeStream(child, 1) };
            assert!(!out.is_null());
            let said = drain(out);
            settle(child);
            unsafe { nuppProcessCloseStream(out) };
            unsafe { nuppProcessReap(child) };
            unsafe { nuppProcessStreamDestroy(out) };
            unsafe { nuppProcessDestroy(child) };

            said
        }

        // The environment has three shapes and they are asked for separately, because
        // the interesting one used to be inexpressible: with clearing implied by adding
        // an entry, "cleared and empty" and "inherit" were the same request.
        //
        // The marker is a variable only this process could have supplied. `PATH` would
        // not do -- a shell inheriting no `PATH` invents one, so its presence says
        // nothing about what was passed in.

        #[test]
        fn an_untouched_environment_is_inherited() {
            std::env::set_var("NUPP_MARK_INHERIT", "from the parent");
            let said = say(spawn("printf '%s' \"$NUPP_MARK_INHERIT\"", &[]));
            assert_eq!(said, "from the parent");
        }

        #[test]
        fn entries_overlay_an_inherited_environment() {
            std::env::set_var("NUPP_MARK_OVERLAY", "from the parent");
            let said = say(spawn(
                "printf '%s %s' \"$NUPP_MARK_OVERLAY\" \"$NUPP_ADDED\"",
                &["NUPP_ADDED=added"],
            ));
            assert_eq!(said, "from the parent added", "both the inherited and the added");
        }

        #[test]
        fn a_cleared_environment_keeps_only_what_it_was_given() {
            std::env::set_var("NUPP_MARK_CLEARED", "from the parent");
            let said = say(spawn_with(
                "printf '%s' \"$NUPP_ONLY${NUPP_MARK_CLEARED:+ leaked}\"",
                &["NUPP_ONLY=set"],
                true,
                false,
            ));
            assert_eq!(said, "set", "the entry given arrived and the parent's did not");
        }

        #[test]
        fn a_cleared_environment_can_be_empty() {
            // The request that had no representation at all: with clearing implied by
            // adding an entry, asking for an empty environment was asking to inherit.
            std::env::set_var("NUPP_MARK_EMPTY", "from the parent");
            let said = say(spawn_with(
                "printf '%s' \"${NUPP_MARK_EMPTY:-none}\"",
                &[],
                true,
                false,
            ));
            assert_eq!(said, "none", "nothing was inherited and nothing was added");
        }

        #[test]
        fn stderr_can_join_stdout_on_one_pipe() {
            // Arranged before the spawn, because the child's two descriptors have to be
            // the same pipe when it starts. Ordering within the child's output is the
            // child's business; that both arrived on one stream is this module's.
            let child = spawn_with("printf out; printf err >&2", &[], false, true);
            assert!(
                unsafe { nuppProcessTakeStream(child, 2) }.is_null(),
                "stderr has no stream of its own, and says so rather than handing back a
                 second owner of stdout's"
            );
            let said = say(child);
            assert!(said.contains("out") && said.contains("err"),
                "both streams arrived on the one pipe, got: {said}");
            assert_eq!(said.len(), 6, "and nothing else did");
        }

        /// The environment variable that turns a test run into the helper below.
        const JOIN_HELPER: &str = "NUPP_JOIN_HELPER_OUTPUT";

        #[test]
        fn stderr_joins_stdout_wherever_stdout_went() {
            // Checked by where the bytes land, not by whether a pipe exists. Absence of
            // a pipe is equally true of a stderr that inherited descriptor 2 and went
            // somewhere else entirely, which is the bug this is about.
            //
            // Which means pointing this process's own stdout at a file -- and that is
            // process-wide state, in a runner that runs its tests on threads. Doing it
            // here would redirect whatever else happened to spawn at that moment, and
            // strand stdout entirely if an assertion unwound before it was put back. So
            // the scenario runs in a copy of this binary, told by an environment
            // variable to be the helper and to run this one test, where descriptor 1 is
            // nobody else's business.
            if let Ok(destination) = std::env::var(JOIN_HELPER) {
                join_helper(&destination);

                return;
            }

            let directory = std::env::temp_dir().join(format!(
                "nupp-join-{}-{}",
                std::process::id(),
                std::time::SystemTime::now()
                    .duration_since(std::time::UNIX_EPOCH)
                    .map(|since| since.as_nanos())
                    .unwrap_or(0)
            ));
            let helper = std::process::Command::new(
                std::env::current_exe().expect("this test binary"),
            )
            .args([
                "--exact",
                "process_tests::stderr_joins_stdout_wherever_stdout_went",
                "--nocapture",
            ])
            .env(JOIN_HELPER, &directory)
            .output()
            .expect("the helper ran");

            let landed = std::fs::read_to_string(&directory).unwrap_or_default();
            let _ = std::fs::remove_file(&directory);
            assert!(
                helper.status.success(),
                "the helper finished: {}",
                String::from_utf8_lossy(&helper.stderr)
            );
            // Distinctive markers, because the helper's own descriptor 1 is this file
            // and its test harness prints to it too. That output names the test being
            // run -- and this test's name has "err" in it, which made a `contains("err")`
            // check pass no matter where the child's stderr actually went.
            assert!(
                landed.contains("STDOUT-LANDED"),
                "stdout went where this process's does; got {landed:?}"
            );
            assert!(
                landed.contains("STDERR-LANDED"),
                "and so did stderr, rather than to descriptor 2's own destination; got {landed:?}"
            );
        }

        /// The scenario, in a process of its own.
        ///
        /// Points descriptor 1 at `destination`, starts a child that inherits stdout and
        /// joins stderr to it, and lets both halves land wherever descriptor 1 now goes.
        /// Nothing here is put back, because nothing else in this process cares.
        fn join_helper(destination: &str) {
            let file = std::fs::File::create(destination).expect("a scratch file");
            unsafe {
                assert!(libc::dup2(file.as_raw_fd(), libc::STDOUT_FILENO) >= 0);
            }

            let request = nuppProcessSpawnBegin();
            arg(request, "sh");
            arg(request, "-c");
            arg(request, "printf STDOUT-LANDED; printf STDERR-LANDED >&2");
            assert!(unsafe { nuppProcessSpawnStdio(request, 1, MODE_INHERIT) });
            assert!(unsafe { nuppProcessSpawnStdio(request, 2, MODE_STDOUT) });
            let child = unsafe { nuppProcessSpawnRun(request) };
            assert!(!child.is_null(), "the child started");
            assert!(
                unsafe { nuppProcessTakeStream(child, 1) }.is_null(),
                "no pipe was made, so there is nothing to take"
            );
            assert!(unsafe { nuppProcessTakeStream(child, 2) }.is_null());
            assert_eq!(settle(child).0, 0);
            unsafe { nuppProcessReap(child) };
            unsafe { nuppProcessDestroy(child) };
        }

        #[test]
        fn stderr_joined_to_a_discarded_stdout_needs_no_pipe() {
            // The other destination worth checking, and one that needs no descriptor
            // games: both really are the same place.
            let request = nuppProcessSpawnBegin();
            arg(request, "sh");
            arg(request, "-c");
            arg(request, "printf out; printf err >&2");
            assert!(unsafe { nuppProcessSpawnStdio(request, 1, MODE_NULL) });
            assert!(unsafe { nuppProcessSpawnStdio(request, 2, MODE_STDOUT) });
            let quiet = unsafe { nuppProcessSpawnRun(request) };
            assert!(!quiet.is_null());
            assert!(unsafe { nuppProcessTakeStream(quiet, 1) }.is_null());
            assert_eq!(settle(quiet).0, 0);
            unsafe { nuppProcessReap(quiet) };
            unsafe { nuppProcessDestroy(quiet) };
        }

        /// The invariant the whole masking sequence turns on, and it cannot be checked
        /// on a platform that quiets the descriptor instead: there, no mask is taken and
        /// nothing is ever consumed.
        ///
        /// Standard signals are not queued. If a `SIGPIPE` was already pending when a
        /// write began, the one waiting afterwards may be that one rather than the
        /// write's, and consuming it steals a signal the host was going to handle. So
        /// the rule is: when it was already there, leave it. This raises one, blocks it
        /// so it stays pending, provokes a broken pipe, and checks it survived.
        #[cfg(not(any(target_os = "macos", target_os = "ios", target_os = "netbsd")))]
        #[test]
        fn a_sigpipe_already_pending_is_left_alone() {
            unsafe {
                let mut blocked: libc::sigset_t = std::mem::zeroed();
                libc::sigemptyset(&mut blocked);
                libc::sigaddset(&mut blocked, libc::SIGPIPE);
                let mut previous: libc::sigset_t = std::mem::zeroed();
                assert_eq!(
                    libc::pthread_sigmask(libc::SIG_BLOCK, &blocked, &mut previous),
                    0
                );

                // Pending, and staying that way because this thread has it blocked.
                assert_eq!(libc::raise(libc::SIGPIPE), 0);
                let mut pending: libc::sigset_t = std::mem::zeroed();
                libc::sigemptyset(&mut pending);
                assert_eq!(libc::sigpending(&mut pending), 0);
                assert_eq!(
                    libc::sigismember(&pending, libc::SIGPIPE),
                    1,
                    "the host's own signal is waiting before the write"
                );

                let child = spawn("exit 0", &[]);
                let input = nuppProcessTakeStream(child, 0);
                settle(child);
                let payload = vec![b'x'; 4096];
                let mut saw_gone = false;
                for _ in 0..64 {
                    if nuppProcessTryWrite(input, payload.as_ptr(), payload.len()) == GONE {
                        saw_gone = true;
                        break;
                    }
                }
                assert!(
                    saw_gone,
                    "the write really did break a pipe -- without that this proves only
                     that a signal nobody touched stayed put"
                );

                libc::sigemptyset(&mut pending);
                assert_eq!(libc::sigpending(&mut pending), 0);
                assert_eq!(
                    libc::sigismember(&pending, libc::SIGPIPE),
                    1,
                    "and it is still waiting afterwards, rather than having been taken"
                );

                nuppProcessCloseStream(input);
                nuppProcessReap(child);
                nuppProcessStreamDestroy(input);
                nuppProcessDestroy(child);

                // Consume the one this test raised, so it does not outlive the test.
                let timeout = libc::timespec { tv_sec: 0, tv_nsec: 0 };
                libc::sigtimedwait(&blocked, std::ptr::null_mut(), &timeout);
                libc::pthread_sigmask(libc::SIG_SETMASK, &previous, std::ptr::null_mut());
            }
        }

        /// Turns a test run into the auto-reaping helper below.
        const ECHILD_HELPER: &str = "NUPP_ECHILD_HELPER";

        #[test]
        fn a_child_the_host_reaped_is_not_reported_as_left() {
            // `SIGCHLD` set to `SIG_IGN` makes the system reap children itself, so
            // `try_wait` answers `ECHILD`: gone, and nothing here will ever see it exit.
            // Read as "still running", every abandoned handle on such a host would be
            // counted as a leak that never happened.
            //
            // The disposition is process-wide and the runner uses threads, so this runs
            // in a copy of the binary rather than changing signal handling under
            // whatever else is going on.
            let _counter = counter_lock();
            if std::env::var(ECHILD_HELPER).is_ok() {
                unsafe {
                    assert_ne!(libc::signal(libc::SIGCHLD, libc::SIG_IGN), libc::SIG_ERR);
                }
                let before = nuppProcessUncollectedTotal();
                let child = spawn("exit 0", &[]);
                let pid = unsafe { nuppProcessId(child) } as libc::pid_t;
                // Waited for rather than slept through: on a loaded runner the child may
                // not have been scheduled yet, and a fixed pause would destroy the handle
                // while it was still running -- testing the ordinary path by accident and
                // saying nothing about `ECHILD` at all.
                let mut gone = false;
                for _ in 0..500 {
                    if unsafe { libc::kill(pid, 0) } == -1 {
                        // Only "no such process" proves it. `kill` can fail for other
                        // reasons -- `EPERM` says the pid exists and belongs to somebody
                        // else -- and treating any failure as proof would let the test
                        // pass on a pid that was very much alive.
                        let failure = std::io::Error::last_os_error();
                        assert_eq!(
                            failure.raw_os_error(),
                            Some(libc::ESRCH),
                            "the pid is gone, rather than merely unsignalable: {failure}"
                        );
                        gone = true;
                        break;
                    }
                    std::thread::sleep(std::time::Duration::from_millis(10));
                }
                assert!(gone, "the host reaped the child, so its pid is no longer ours");
                unsafe { nuppProcessDestroy(child) };
                assert_eq!(
                    nuppProcessUncollectedTotal(),
                    before,
                    "a child the host reaped is gone, not left behind"
                );

                return;
            }

            let helper = std::process::Command::new(
                std::env::current_exe().expect("this test binary"),
            )
            .args([
                "--exact",
                "process_tests::a_child_the_host_reaped_is_not_reported_as_left",
                "--nocapture",
            ])
            .env(ECHILD_HELPER, "1")
            .output()
            .expect("the helper ran");
            assert!(
                helper.status.success(),
                "the helper finished: {}{}",
                String::from_utf8_lossy(&helper.stdout),
                String::from_utf8_lossy(&helper.stderr)
            );
        }

        #[test]
        fn an_ended_child_is_resolved_and_a_running_one_is_not() {
            // The one classification the fallback makes, and the only place `ECHILD`
            // can be handed to it without arranging a host that reaps its own children.
            assert!(
                !resolved_for_test(Ok(None)),
                "still running is not resolved"
            );
            assert!(
                resolved_for_test(Err(std::io::Error::from_raw_os_error(libc::ECHILD))),
                "collected by the host itself is resolved"
            );
            assert!(
                !resolved_for_test(Err(std::io::Error::from_raw_os_error(libc::EIO))),
                "an unexplained failure says nothing, so it is not resolved"
            );
        }

        #[test]
        fn a_child_dropped_without_being_closed_is_signalled_and_counted() {
            // Taken because this drop may itself increment the count, and a test
            // comparing that number before and after its own work must not have this
            // one running alongside it.
            let _counter = counter_lock();
            // Rust does not kill or wait when a `Child` is dropped, so without this the
            // handle would leave a live process behind with nobody owning it.
            //
            // What the fallback promises is narrow and deliberately so: the child is
            // signalled, it is looked at once, and if that look does not find it ended
            // the count says so. It does not wait -- this runs during whatever the host
            // was doing -- and it does not chase. Closing the handle properly is the
            // guarantee; this only makes failing to do so cheap and visible.
            let before = nuppProcessUncollectedTotal();
            let child = spawn("sleep 30", &[]);
            let pid = unsafe { nuppProcessId(child) };
            unsafe { nuppProcessDestroy(child) };

            // The signal landed, which is the part that matters: reaping it here proves
            // it ended rather than running out its thirty seconds.
            let mut status = 0;
            let mut ended = false;
            for _ in 0..200 {
                let answered =
                    unsafe { libc::waitpid(pid as libc::pid_t, &mut status, libc::WNOHANG) };
                if answered == pid as libc::pid_t {
                    ended = true;
                    break;
                }
                if answered == -1 {
                    let failure = std::io::Error::last_os_error();
                    match failure.raw_os_error() {
                        // Somebody else has it, which is as good as this needs.
                        Some(libc::ECHILD) => {
                            ended = true;
                            break;
                        }
                        Some(libc::EINTR) => continue,
                        other => panic!("waiting on the child failed: {other:?}"),
                    }
                }
                std::thread::sleep(std::time::Duration::from_millis(10));
            }
            assert!(ended, "the child was signalled rather than left to run");
            // Whether this one was *counted* is deliberately not asserted. The drop
            // signals and then looks, and `SIGKILL` landing before that look is the
            // kernel's business -- a child found already ended is correctly not counted.
            // The counting rule is tested where it can be asked a settled question.
            let _ = before;
        }

        /// Taken by the tests that read `nuppProcessUncollectedTotal`.
        ///
        /// It is one number for the whole process and the runner uses threads, so two
        /// tests comparing it before and after their own work will see each other's and
        /// fail on whichever order they happened to run in.
        static COUNTER_TESTS: std::sync::Mutex<()> = std::sync::Mutex::new(());

        fn counter_lock() -> std::sync::MutexGuard<'static, ()> {
            COUNTER_TESTS.lock().unwrap_or_else(|held| held.into_inner())
        }

        #[test]
        fn only_an_unresolved_child_is_counted() {
            let _counter = counter_lock();
            // The accounting rule, handed answers rather than racing for them.
            let before = nuppProcessUncollectedTotal();
            assert!(
                !account_for_test(Ok(Some(exited())), false),
                "a child known to have ended is not a leak"
            );
            assert!(
                !account_for_test(Err(std::io::Error::from_raw_os_error(libc::ECHILD)), false),
                "nor is one the host reaped itself"
            );
            assert_eq!(
                nuppProcessUncollectedTotal(),
                before,
                "and neither moved the count"
            );

            assert!(
                account_for_test(Ok(None), false),
                "a child still running when it was let go is counted"
            );
            assert_eq!(nuppProcessUncollectedTotal(), before + 1);
            let said = unsafe { std::ffi::CStr::from_ptr(crate::nuppNativeError()) }
                .to_string_lossy()
                .into_owned();
            assert!(
                said.contains("signalled but had not ended"),
                "and reported as signalled; got {said:?}"
            );

            assert!(account_for_test(Ok(None), true), "as is one never signalled");
            assert_eq!(nuppProcessUncollectedTotal(), before + 2);
            let worse = unsafe { std::ffi::CStr::from_ptr(crate::nuppNativeError()) }
                .to_string_lossy()
                .into_owned();
            assert!(
                worse.contains("still running"),
                "and reported apart, because nothing asked it to stop; got {worse:?}"
            );
        }

        /// A real exit status, which cannot be constructed directly.
        fn exited() -> std::process::ExitStatus {
            std::process::Command::new("sh")
                .args(["-c", "exit 0"])
                .status()
                .expect("a child that exits")
        }

        #[test]
        fn a_child_seen_to_exit_is_not_counted_when_it_is_let_go() {
            let _counter = counter_lock();
            // The ordinary resolved path, end to end: a caller that watched its child
            // finish and then dropped the handle without reaping has leaked nothing the
            // fallback can see, and must not be reported as though it had.
            let before = nuppProcessUncollectedTotal();
            let child = spawn("exit 0", &[]);
            let (code, _) = settle(child);
            assert_eq!(code, 0, "it exited on its own");
            // Destroyed without `nuppProcessReap`, which is the case being tested.
            unsafe { nuppProcessDestroy(child) };
            assert_eq!(
                nuppProcessUncollectedTotal(),
                before,
                "a child already seen to end is not a leak"
            );
        }

        #[test]
        fn a_write_to_a_child_that_stopped_reading_reports_gone() {
            // The case that kills the host when SIGPIPE is not contained: the child
            // reads nothing and exits, and this process keeps writing. Reaching the
            // assertion at all is most of the test.
            let child = spawn("exit 0", &[]);
            let input = unsafe { nuppProcessTakeStream(child, 0) };
            assert!(!input.is_null());
            settle(child);

            let payload = vec![b'x'; 4096];
            let mut saw_gone = false;
            for _ in 0..64 {
                let sent = unsafe {
                    nuppProcessTryWrite(input, payload.as_ptr(), payload.len())
                };
                if sent == GONE {
                    saw_gone = true;
                    break;
                }
                assert!(sent >= 0 || sent == WOULD_BLOCK, "unexpected write answer {sent}");
            }
            assert!(saw_gone, "the far end going was reported, and the host survived");
            unsafe { nuppProcessCloseStream(input) };
            unsafe { nuppProcessReap(child) };
            unsafe { nuppProcessStreamDestroy(input) };
            unsafe { nuppProcessDestroy(child) };
        }

        #[test]
        fn a_killed_child_says_so() {
            let child = spawn("sleep 30", &[]);
            assert!(unsafe { nuppProcessKill(child, true) });
            let (code, killed) = settle(child);
            assert!(killed, "the child was ended rather than exiting");
            assert_eq!(code, 128 + 9, "and by the signal that was sent");
            unsafe { nuppProcessReap(child) };
            unsafe { nuppProcessDestroy(child) };
        }

        #[test]
        fn a_release_is_idempotent_and_never_unwinds() {
            let child = spawn("exit 0", &[]);
            let out = unsafe { nuppProcessTakeStream(child, 1) };
            settle(child);
            assert_eq!(unsafe { nuppProcessCloseStream(out) }, RELEASED);
            assert_eq!(unsafe { nuppProcessCloseStream(out) }, RELEASED,
                "a released descriptor is released, and asking again is not an error");
            assert_eq!(unsafe { nuppProcessReap(child) }, RELEASED);
            assert_eq!(unsafe { nuppProcessReap(child) }, RELEASED);
            unsafe { nuppProcessStreamDestroy(out) };
            unsafe { nuppProcessDestroy(child) };
        }

        #[test]
        fn reaping_a_running_child_is_refused_rather_than_guessed() {
            let child = spawn("sleep 30", &[]);
            assert_eq!(unsafe { nuppProcessReap(child) }, NOT_RELEASED,
                "it has not ended, so there is nothing to release");
            unsafe { nuppProcessKill(child, true) };
            settle(child);
            assert_eq!(unsafe { nuppProcessReap(child) }, RELEASED);
            unsafe { nuppProcessDestroy(child) };
        }

        #[test]
        fn a_readiness_wait_refuses_a_null_it_was_told_to_watch() {
            // Skipping it would turn a binding that built its array wrongly into a wait
            // that watched fewer things than asked and returned on the timeout -- which
            // is indistinguishable from a quiet child, and would be chased for a long
            // time before anyone suspected the array.
            let empty: *mut NuppStream = std::ptr::null_mut();
            let answered = unsafe {
                nuppProcessWaitReady(&empty, 1, std::ptr::null(), 0, 10)
            };
            assert_eq!(answered, -1, "a null inside the count is refused");
            let said = unsafe { std::ffi::CStr::from_ptr(crate::nuppNativeError()) }
                .to_string_lossy()
                .into_owned();
            assert!(said.contains("null stream"), "and says so; got {said:?}");
        }

        #[test]
        fn a_negative_timeout_does_not_wait_forever() {
            // `poll` reads a negative timeout as "no deadline". Every caller above is
            // bounded, and the usual way to arrive here negative is a deadline already
            // passed -- which asks for no wait at all.
            let started = std::time::Instant::now();
            let answered = unsafe {
                nuppProcessWaitReady(std::ptr::null(), 0, std::ptr::null(), 0, -1)
            };
            assert_eq!(answered, 0, "nothing was ready");
            assert!(
                started.elapsed() < std::time::Duration::from_millis(500),
                "and it returned rather than waiting for an event that cannot come"
            );
        }

        #[test]
        fn a_closed_stream_answers_but_does_not_carry_bytes() {
            // What "valid but no longer usable" actually amounts to, checked rather than
            // asserted -- a binding is about to be written against this sentence.
            let child = spawn("printf done", &[]);
            let out = unsafe { nuppProcessTakeStream(child, 1) };
            let input = unsafe { nuppProcessTakeStream(child, 0) };
            let _ = drain(out);
            assert_eq!(unsafe { nuppProcessCloseStream(out) }, RELEASED);
            assert_eq!(unsafe { nuppProcessCloseStream(input) }, RELEASED);

            let mut room = [0u8; 16];
            assert_eq!(
                unsafe { nuppProcessTryRead(out, room.as_mut_ptr(), room.len()) },
                FAILED,
                "reading a closed stream is a failure, not an end of stream: there is a
                 difference between a child that finished and a caller that let go"
            );
            let payload = b"bytes";
            assert_eq!(
                unsafe { nuppProcessTryWrite(input, payload.as_ptr(), payload.len()) },
                FAILED,
                "and so is writing to one: `GONE` would claim the child's end had gone,
                 which closing this end says nothing about"
            );
            let closed_said = unsafe { std::ffi::CStr::from_ptr(crate::nuppNativeError()) }
                .to_string_lossy()
                .into_owned();
            assert!(
                closed_said.contains("has been closed"),
                "and says it was closed rather than never writable, since those are
                 different mistakes to have made; got {closed_said:?}"
            );

            // The other way to reach the same mistake: a readable stream handed to a
            // write. That is a caller bug, and used to arrive as a synthesised broken
            // pipe -- indistinguishable from the real thing.
            let second = spawn("printf again", &[]);
            let readable = unsafe { nuppProcessTakeStream(second, 1) };
            assert_eq!(
                unsafe { nuppProcessTryWrite(readable, payload.as_ptr(), payload.len()) },
                FAILED,
                "a stream that cannot be written is a failure, not a broken pipe"
            );
            let said = unsafe { std::ffi::CStr::from_ptr(crate::nuppNativeError()) }
                .to_string_lossy()
                .into_owned();
            assert!(said.contains("not writable"), "and says which; got {said:?}");
            let _ = drain(readable);
            settle(second);
            unsafe { nuppProcessCloseStream(readable) };
            unsafe { nuppProcessReap(second) };
            unsafe { nuppProcessStreamDestroy(readable) };
            unsafe { nuppProcessDestroy(second) };

            settle(child);
            unsafe { nuppProcessReap(child) };
            unsafe { nuppProcessStreamDestroy(out) };
            unsafe { nuppProcessStreamDestroy(input) };
            unsafe { nuppProcessDestroy(child) };
        }

        #[test]
        fn a_closed_stream_may_still_be_named() {
            // Closing releases the descriptor and leaves the handle alive, so a drain
            // loop that names a stream it has finished with is asking a fair question.
            // Destroying is what makes a handle unnameable, and that is the caller's to
            // avoid -- a freed pointer cannot be told from a live one here.
            let child = spawn("printf done", &[]);
            let out = unsafe { nuppProcessTakeStream(child, 1) };
            assert!(!out.is_null());
            let _ = drain(out);
            assert_eq!(unsafe { nuppProcessCloseStream(out) }, RELEASED);
            let answered = unsafe { nuppProcessWaitReady(&out, 1, std::ptr::null(), 0, 10) };
            assert_eq!(answered, 0, "a closed stream is skipped, not an error");
            settle(child);
            unsafe { nuppProcessReap(child) };
            unsafe { nuppProcessStreamDestroy(out) };
            unsafe { nuppProcessDestroy(child) };
        }

        #[test]
        fn an_empty_readiness_wait_is_a_bounded_sleep() {
            let started = std::time::Instant::now();
            let ready = unsafe {
                nuppProcessWaitReady(std::ptr::null(), 0, std::ptr::null(), 0, 40)
            };
            assert_eq!(ready, 0, "nothing became ready, because nothing was named");
            assert!(started.elapsed().as_millis() >= 30, "and it really waited");
        }

        #[test]
        fn the_process_clock_is_monotonic() {
            let first = nuppProcessMonotonicMs();
            std::thread::yield_now();
            let second = nuppProcessMonotonicMs();
            assert!(first >= 0.0);
            assert!(second >= first);
        }
    }
