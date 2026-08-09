//! Rust regex bindings for Nupp's native feature registry.
//!
//! This keeps Tecs' byte-string semantics: patterns are UTF-8 Rust regexes,
//! while subjects are arbitrary Lua byte strings and offsets cross the ABI as
//! byte positions.

use regex::bytes::Regex;
use std::{borrow::Cow, cell::RefCell, ffi::CString, ptr, slice, str};

thread_local! { static ERROR: RefCell<CString> = RefCell::new(CString::new("").unwrap()); }

fn set_error(error: impl std::fmt::Display) {
    let text = error.to_string().replace('\0', " ");
    ERROR.with(|slot| *slot.borrow_mut() = CString::new(text).unwrap());
}

#[no_mangle]
pub extern "C" fn nuppRegexLastError() -> *const i8 {
    ERROR.with(|slot| slot.borrow().as_ptr())
}

unsafe fn bytes<'a>(value: *const u8, length: usize) -> Option<&'a [u8]> {
    if value.is_null() { return (length == 0).then_some(&[]); }
    Some(unsafe { slice::from_raw_parts(value, length) })
}

pub struct NuppRegex { regex: Regex, names: Vec<Option<Box<[u8]>>> }

#[repr(C)]
pub struct NuppRegexSpan { start: usize, end: usize, matched: bool }

pub struct NuppBytes { bytes: Box<[u8]> }

#[no_mangle]
pub unsafe extern "C" fn nuppRegexCompile(pattern: *const u8, length: usize) -> *mut NuppRegex {
    let Some(pattern) = (unsafe { bytes(pattern, length) }) else { set_error("regex pattern is null"); return ptr::null_mut(); };
    let pattern = match str::from_utf8(pattern) { Ok(value) => value, Err(_) => { set_error("regex pattern is not UTF-8"); return ptr::null_mut(); } };
    let regex = match Regex::new(pattern) { Ok(value) => value, Err(error) => { set_error(error); return ptr::null_mut(); } };
    let names = regex.capture_names().map(|name| name.map(|value| value.as_bytes().into())).collect();
    Box::into_raw(Box::new(NuppRegex { regex, names }))
}

#[no_mangle]
pub unsafe extern "C" fn nuppRegexDestroy(regex: *mut NuppRegex) {
    if !regex.is_null() { drop(unsafe { Box::from_raw(regex) }); }
}

#[no_mangle]
pub unsafe extern "C" fn nuppRegexCaptureCount(regex: *const NuppRegex) -> usize {
    if regex.is_null() { 0 } else { unsafe { &*regex }.regex.captures_len() }
}

#[no_mangle]
pub unsafe extern "C" fn nuppRegexCaptureName(regex: *const NuppRegex, index: usize, length: *mut usize) -> *const u8 {
    if !length.is_null() { unsafe { *length = 0 }; }
    if regex.is_null() { return ptr::null(); }
    let Some(Some(name)) = unsafe { &*regex }.names.get(index) else { return ptr::null(); };
    if !length.is_null() { unsafe { *length = name.len() }; }
    name.as_ptr()
}

#[no_mangle]
pub unsafe extern "C" fn nuppRegexIsMatch(regex: *const NuppRegex, subject: *const u8, length: usize) -> bool {
    let (Some(regex), Some(subject)) = ((!regex.is_null()).then(|| unsafe { &*regex }), unsafe { bytes(subject, length) }) else { return false; };
    regex.regex.is_match(subject)
}

#[no_mangle]
pub unsafe extern "C" fn nuppRegexFind(regex: *const NuppRegex, subject: *const u8, length: usize, start: usize, output: *mut NuppRegexSpan) -> bool {
    if regex.is_null() || output.is_null() || start > length { return false; }
    let Some(subject) = (unsafe { bytes(subject, length) }) else { return false; };
    let Some(found) = unsafe { &*regex }.regex.find_at(subject, start) else { return false; };
    unsafe { *output = NuppRegexSpan { start: found.start(), end: found.end(), matched: true }; }
    true
}

#[no_mangle]
pub unsafe extern "C" fn nuppRegexCaptures(regex: *const NuppRegex, subject: *const u8, length: usize, start: usize, spans: *mut NuppRegexSpan, count: usize) -> bool {
    if regex.is_null() || spans.is_null() || start > length { return false; }
    let regex = unsafe { &*regex };
    if count < regex.regex.captures_len() { return false; }
    let Some(subject) = (unsafe { bytes(subject, length) }) else { return false; };
    let Some(captures) = regex.regex.captures_at(subject, start) else { return false; };
    let spans = unsafe { slice::from_raw_parts_mut(spans, count) };
    for (index, output) in spans.iter_mut().enumerate().take(captures.len()) {
        *output = captures.get(index).map(|found| NuppRegexSpan { start: found.start(), end: found.end(), matched: true }).unwrap_or(NuppRegexSpan { start: 0, end: 0, matched: false });
    }
    true
}

#[no_mangle]
pub unsafe extern "C" fn nuppRegexReplace(regex: *const NuppRegex, subject: *const u8, length: usize, replacement: *const u8, replacement_length: usize, limit: usize) -> *mut NuppBytes {
    if regex.is_null() { return ptr::null_mut(); }
    let (Some(subject), Some(replacement)) = (unsafe { bytes(subject, length) }, unsafe { bytes(replacement, replacement_length) }) else { return ptr::null_mut(); };
    match unsafe { &*regex }.regex.replacen(subject, limit, replacement) {
        Cow::Borrowed(_) => ptr::null_mut(),
        Cow::Owned(bytes) => Box::into_raw(Box::new(NuppBytes { bytes: bytes.into_boxed_slice() })),
    }
}

#[no_mangle]
pub unsafe extern "C" fn nuppBytesLength(bytes: *const NuppBytes) -> usize {
    if bytes.is_null() { 0 } else { unsafe { &*bytes }.bytes.len() }
}

#[no_mangle]
pub unsafe extern "C" fn nuppBytesData(bytes: *const NuppBytes) -> *const u8 {
    if bytes.is_null() { ptr::null() } else { unsafe { &*bytes }.bytes.as_ptr() }
}

#[no_mangle]
pub unsafe extern "C" fn nuppBytesDestroy(bytes: *mut NuppBytes) {
    if !bytes.is_null() { drop(unsafe { Box::from_raw(bytes) }); }
}
