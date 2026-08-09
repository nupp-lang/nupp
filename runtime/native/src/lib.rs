//! Feature-gated native implementation for `nupp.data` and `nupp.io`.

use std::cell::RefCell;
use std::ffi::{c_char, CString};
use std::ptr;
#[cfg(any(feature = "path", feature = "uri", feature = "sha256"))]
use std::slice;
#[cfg(any(feature = "path", feature = "uri"))]
use std::str;

thread_local! {
    static LAST_ERROR: RefCell<CString> =
        RefCell::new(CString::new("no error").expect("static text has no NUL"));
}

#[cfg(any(feature = "path", feature = "uri"))]
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

#[cfg(feature = "path")]
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

#[cfg(any(feature = "path", feature = "uri"))]
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

#[cfg(test)]
mod tests {
    use super::*;
    use std::ffi::CStr;

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
