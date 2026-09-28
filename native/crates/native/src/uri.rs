//! Immutable WHATWG URLs behind the versioned native handle ABI.

use super::{failed, input};
use nupp_native_abi::{Arena, Handle, Status};
use std::ptr;
use std::sync::{Mutex, OnceLock};
use url::{Position, Url};

fn uris() -> &'static Mutex<Arena<Url>> {
    static URIS: OnceLock<Mutex<Arena<Url>>> = OnceLock::new();
    URIS.get_or_init(|| Mutex::new(Arena::new()))
}

fn text<'a>(data: *const u8, length: usize, what: &str) -> Result<&'a str, i32> {
    let bytes = input(data, length)?;
    let value = std::str::from_utf8(bytes).map_err(|_| {
        failed(
            Status::InvalidArgument,
            &format!("{what} is not valid UTF-8"),
        )
    })?;
    if value.as_bytes().contains(&0) {
        return Err(failed(
            Status::InvalidArgument,
            &format!("{what} contains a NUL byte"),
        ));
    }
    Ok(value)
}

fn cloned(raw: u64) -> Result<Url, i32> {
    let arena = uris()
        .lock()
        .map_err(|_| failed(Status::Internal, "URI handle store is poisoned"))?;
    arena
        .get(Handle::from_raw(raw))
        .cloned()
        .map_err(|_| failed(Status::StaleHandle, "URI handle is stale"))
}

fn hold(value: Url, output: *mut u64) -> i32 {
    if output.is_null() {
        return failed(Status::InvalidArgument, "URI handle output is null");
    }
    let handle = match uris().lock() {
        Ok(mut arena) => match arena.insert(value) {
            Ok(handle) => handle,
            Err(status) => return failed(status, "URI handle capacity is exhausted"),
        },
        Err(_) => return failed(Status::Internal, "URI handle store is poisoned"),
    };
    // SAFETY: the caller supplied writable storage for one u64.
    unsafe { output.write(handle.raw()) };
    Status::Ok.code()
}

/// One component, or `None` for a kind that names no component.
fn part(value: &Url, kind: u32) -> Option<Option<&str>> {
    Some(match kind {
        0 => Some(value.as_str()),
        1 => Some(value.scheme()),
        2 if value.has_authority() => Some(&value[Position::BeforeUsername..Position::BeforePath]),
        2 => None,
        3 => Some(value.username()),
        4 => value.password(),
        5 => value.host_str().filter(|host| !host.is_empty()),
        6 => Some(value.path()),
        7 => value.query(),
        8 => value.fragment(),
        _ => return None,
    })
}

#[unsafe(no_mangle)]
/// Parses absolute WHATWG URL text into a new immutable handle.
///
/// # Safety
/// When `length` is nonzero, `data` must be readable for `length` bytes.
/// `output` must be writable for one `u64`.
pub unsafe extern "C" fn nuppNativeUriParse(
    data: *const u8,
    length: usize,
    output: *mut u64,
) -> i32 {
    let source = match text(data, length, "URI") {
        Ok(value) => value,
        Err(status) => return status,
    };
    let value = match Url::parse(source) {
        Ok(value) => value,
        // The parser's own reason names the rule the text broke.
        Err(error) => return failed(Status::InvalidArgument, &error.to_string()),
    };
    hold(value, output)
}

#[unsafe(no_mangle)]
pub extern "C" fn nuppNativeUriRelease(raw: u64) -> i32 {
    match uris().lock() {
        Ok(mut arena) => match arena.remove(Handle::from_raw(raw)) {
            Ok(_) => Status::Ok.code(),
            Err(status) => failed(status, "URI handle is stale"),
        },
        Err(_) => failed(Status::Internal, "URI handle store is poisoned"),
    }
}

#[unsafe(no_mangle)]
/// Copies a URI component into caller-owned storage.
///
/// # Safety
/// `length` and `present` must be writable. A nonzero `capacity` requires
/// `output` to be writable for that many bytes.
pub unsafe extern "C" fn nuppNativeUriPart(
    raw: u64,
    kind: u32,
    output: *mut u8,
    capacity: usize,
    length: *mut usize,
    present: *mut i32,
) -> i32 {
    if length.is_null() || present.is_null() || (capacity != 0 && output.is_null()) {
        return failed(Status::InvalidArgument, "URI component output is null");
    }
    let arena = match uris().lock() {
        Ok(arena) => arena,
        Err(_) => return failed(Status::Internal, "URI handle store is poisoned"),
    };
    let value = match arena.get(Handle::from_raw(raw)) {
        Ok(value) => value,
        Err(status) => return failed(status, "URI handle is stale"),
    };
    let Some(found) = part(value, kind) else {
        return failed(Status::InvalidArgument, "URI component kind is invalid");
    };
    let bytes = found.unwrap_or_default().as_bytes();
    // SAFETY: both scalar outputs were checked above.
    unsafe {
        length.write(bytes.len());
        present.write(i32::from(found.is_some()));
    }
    if capacity == 0 || found.is_none() {
        return Status::Ok.code();
    }
    if capacity < bytes.len() {
        return failed(Status::Capacity, "URI component output is too small");
    }
    if !bytes.is_empty() {
        // SAFETY: the caller promised `capacity` writable bytes.
        unsafe { ptr::copy_nonoverlapping(bytes.as_ptr(), output, bytes.len()) };
    }
    Status::Ok.code()
}

#[unsafe(no_mangle)]
/// Answers the explicit, non-default port, or -1 when absent.
///
/// # Safety
/// `output` must be writable for one `i32`.
pub unsafe extern "C" fn nuppNativeUriPort(raw: u64, output: *mut i32) -> i32 {
    if output.is_null() {
        return failed(Status::InvalidArgument, "URI port output is null");
    }
    let value = match cloned(raw) {
        Ok(value) => value,
        Err(status) => return status,
    };
    // SAFETY: the output pointer was checked above.
    unsafe { output.write(value.port().map_or(-1, i32::from)) };
    Status::Ok.code()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn parse(source: &str) -> u64 {
        let mut handle = 0;
        assert_eq!(
            unsafe { nuppNativeUriParse(source.as_ptr(), source.len(), &mut handle) },
            Status::Ok.code()
        );
        handle
    }

    fn component(handle: u64, kind: u32) -> Option<String> {
        let mut length = 0;
        let mut present = 0;
        assert_eq!(
            unsafe {
                nuppNativeUriPart(handle, kind, ptr::null_mut(), 0, &mut length, &mut present)
            },
            0
        );
        if present == 0 {
            return None;
        }
        let mut output = vec![0; length];
        assert_eq!(
            unsafe {
                nuppNativeUriPart(
                    handle,
                    kind,
                    output.as_mut_ptr(),
                    output.len(),
                    &mut length,
                    &mut present,
                )
            },
            0
        );
        Some(String::from_utf8(output).unwrap())
    }

    #[test]
    fn parse_normalizes_and_copies_every_component() {
        let handle = parse("https://user:pass@EXAMPLE.com:443/a/../b?q=1#top");
        assert_eq!(
            component(handle, 0).as_deref(),
            Some("https://user:pass@example.com/b?q=1#top")
        );
        assert_eq!(component(handle, 1).as_deref(), Some("https"));
        assert_eq!(
            component(handle, 2).as_deref(),
            Some("user:pass@example.com")
        );
        assert_eq!(component(handle, 3).as_deref(), Some("user"));
        assert_eq!(component(handle, 4).as_deref(), Some("pass"));
        assert_eq!(component(handle, 5).as_deref(), Some("example.com"));
        assert_eq!(component(handle, 6).as_deref(), Some("/b"));
        assert_eq!(component(handle, 7).as_deref(), Some("q=1"));
        assert_eq!(component(handle, 8).as_deref(), Some("top"));
        assert_eq!(nuppNativeUriRelease(handle), 0);
        assert_eq!(nuppNativeUriRelease(handle), Status::StaleHandle.code());
    }

    #[test]
    fn a_component_kind_outside_the_list_is_refused() {
        let handle = parse("https://example.com/#top");
        let mut length = 0;
        let mut present = 0;
        assert_eq!(
            unsafe { nuppNativeUriPart(handle, 9, ptr::null_mut(), 0, &mut length, &mut present) },
            Status::InvalidArgument.code()
        );
        assert_eq!(nuppNativeUriRelease(handle), 0);
    }

    #[test]
    fn opaque_and_empty_authorities_remain_distinct() {
        let opaque = parse("mailto:someone@example.com");
        assert_eq!(component(opaque, 2), None);
        assert_eq!(component(opaque, 6).as_deref(), Some("someone@example.com"));
        let file = parse("file:///tmp/x");
        assert_eq!(component(file, 2).as_deref(), Some(""));
        assert_eq!(component(file, 5), None);
        assert_eq!(nuppNativeUriRelease(opaque), 0);
        assert_eq!(nuppNativeUriRelease(file), 0);
    }

    #[test]
    fn malformed_text_keeps_the_public_reasons() {
        for (source, reason) in [
            ("", "relative URL without a base"),
            ("http://[", "invalid IPv6 address"),
            ("http:", "empty host"),
            ("http://example.com:99999/", "invalid port number"),
            ("http://exa mple.com/", "invalid international domain name"),
            ("http://999.1.1.1/", "invalid IPv4 address"),
        ] {
            let mut handle = 0;
            assert_eq!(
                unsafe { nuppNativeUriParse(source.as_ptr(), source.len(), &mut handle) },
                Status::InvalidArgument.code()
            );
            nupp_native_abi::with_last_error(|error| assert_eq!(error.to_str().unwrap(), reason));
        }
    }
}
