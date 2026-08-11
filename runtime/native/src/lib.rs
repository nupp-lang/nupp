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

#[cfg(any(feature = "path", feature = "uri", feature = "files"))]
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

#[cfg(test)]
mod tests {
    use super::*;
    use std::ffi::CStr;

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
        let expected = format!("alpha{}file.txt", std::path::MAIN_SEPARATOR);
        assert_eq!(output, expected.as_bytes());
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
