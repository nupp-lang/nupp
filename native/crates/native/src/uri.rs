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

fn why_not(value: &str) -> &'static str {
    let bytes = value.as_bytes();
    let Some(first) = bytes.first() else {
        return "relative URL without a base";
    };
    if !first.is_ascii_alphabetic() {
        return "relative URL without a base";
    }
    let Some(scheme_end) = bytes.iter().position(|byte| *byte == b':') else {
        return "relative URL without a base";
    };
    if !bytes[1..scheme_end]
        .iter()
        .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'+' | b'-' | b'.'))
    {
        return "relative URL without a base";
    }

    let after = &bytes[scheme_end + 1..];
    if after.starts_with(b"//") {
        let authority = &after[2..after[2..]
            .iter()
            .position(|byte| matches!(byte, b'/' | b'?' | b'#'))
            .map_or(after.len(), |at| at + 2)];
        if authority.contains(&b'[') && !authority.contains(&b']') {
            return "invalid IPv6 address";
        }
        if authority.is_empty() {
            return "empty host";
        }
    } else {
        let scheme = &value[..scheme_end];
        if ["http", "https", "ws", "wss", "ftp", "file"]
            .iter()
            .any(|special| scheme.eq_ignore_ascii_case(special))
        {
            return "empty host";
        }
    }
    "the URI is not valid"
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

fn part(value: &Url, kind: u32) -> Option<&str> {
    match kind {
        0 => Some(value.as_str()),
        1 => Some(value.scheme()),
        2 if value.has_authority() => Some(&value[Position::BeforeUsername..Position::BeforePath]),
        2 => None,
        3 => Some(value.username()),
        4 => value.password(),
        5 => value.host_str().filter(|host| !host.is_empty()),
        6 => Some(value.path()),
        7 => value.query(),
        _ => value.fragment(),
    }
}

fn joined_path(left: &str, right: &str) -> String {
    let left_slash = left.ends_with('/');
    let right_slash = right.starts_with('/');
    let mut joined = String::with_capacity(left.len() + right.len() + 1);
    joined.push_str(left);
    match (left_slash, right_slash) {
        (true, true) => joined.push_str(&right[1..]),
        (false, false) => {
            joined.push('/');
            joined.push_str(right);
        }
        _ => joined.push_str(right),
    }
    joined
}

#[unsafe(no_mangle)]
/// Parses absolute WHATWG URL text into a new immutable handle.
///
/// # Safety
/// When `length` is nonzero, `data` must be readable for `length` bytes.
/// `output` must be writable for one `u64`.
pub unsafe extern "C" fn nuppNativeV2UriParse(
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
        Err(_) => return failed(Status::InvalidArgument, why_not(source)),
    };
    hold(value, output)
}

#[unsafe(no_mangle)]
pub extern "C" fn nuppNativeV2UriRelease(raw: u64) -> i32 {
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
pub unsafe extern "C" fn nuppNativeV2UriPart(
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
    let found = part(value, kind);
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
pub unsafe extern "C" fn nuppNativeV2UriPort(raw: u64, output: *mut i32) -> i32 {
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

#[unsafe(no_mangle)]
/// Derives a URI by replacing one textual component.
///
/// # Safety
/// When `length` is nonzero, `data` must be readable for `length` bytes.
/// `output` must be writable for one `u64`.
pub unsafe extern "C" fn nuppNativeV2UriWithText(
    raw: u64,
    kind: u32,
    data: *const u8,
    length: usize,
    present: i32,
    output: *mut u64,
) -> i32 {
    let replacement = match text(data, length, "URI component") {
        Ok(value) => value,
        Err(status) => return status,
    };
    let mut value = match cloned(raw) {
        Ok(value) => value,
        Err(status) => return status,
    };
    let present = present != 0;
    let result = match kind {
        0 => value
            .set_scheme(replacement)
            .map_err(|_| "URI scheme is invalid"),
        1 => {
            let (username, password) = if present {
                replacement
                    .split_once(':')
                    .map_or((replacement, None), |(name, password)| {
                        (name, Some(password))
                    })
            } else {
                ("", None)
            };
            value
                .set_username(username)
                .and_then(|()| value.set_password(password))
                .map_err(|_| "URI user information is invalid")
        }
        2 => value
            .set_host(present.then_some(replacement))
            .map_err(|_| "URI host is invalid"),
        3 => {
            value.set_path(replacement);
            Ok(())
        }
        4 => {
            value.set_query(present.then_some(replacement));
            Ok(())
        }
        _ => {
            value.set_fragment(present.then_some(replacement));
            Ok(())
        }
    };
    if let Err(reason) = result {
        return failed(Status::InvalidArgument, reason);
    }
    hold(value, output)
}

#[unsafe(no_mangle)]
/// Derives a URI with an explicit port, or no port when `port` is -1.
///
/// # Safety
/// `output` must be writable for one `u64`.
pub unsafe extern "C" fn nuppNativeV2UriWithPort(raw: u64, port: i32, output: *mut u64) -> i32 {
    if !(-1..=65535).contains(&port) {
        return failed(
            Status::InvalidArgument,
            "URI port must be from 0 through 65535, or -1 for none",
        );
    }
    let mut value = match cloned(raw) {
        Ok(value) => value,
        Err(status) => return status,
    };
    if value.set_port((port >= 0).then_some(port as u16)).is_err() {
        return failed(
            Status::InvalidArgument,
            "URI port is invalid for this scheme",
        );
    }
    hold(value, output)
}

#[unsafe(no_mangle)]
/// Appends path text with exactly one separator.
///
/// # Safety
/// When `length` is nonzero, `suffix` must be readable for `length` bytes.
/// `output` must be writable for one `u64`.
pub unsafe extern "C" fn nuppNativeV2UriConcatPath(
    raw: u64,
    suffix: *const u8,
    length: usize,
    output: *mut u64,
) -> i32 {
    let suffix = match text(suffix, length, "URI path") {
        Ok(value) => value,
        Err(status) => return status,
    };
    let mut value = match cloned(raw) {
        Ok(value) => value,
        Err(status) => return status,
    };
    let path = joined_path(value.path(), suffix);
    value.set_path(&path);
    hold(value, output)
}

#[unsafe(no_mangle)]
/// Reroots a URI at another URI while preserving its path, query and fragment.
///
/// # Safety
/// `output` must be writable for one `u64`.
pub unsafe extern "C" fn nuppNativeV2UriWithEndpoint(
    raw: u64,
    endpoint: u64,
    output: *mut u64,
) -> i32 {
    let source = match cloned(raw) {
        Ok(value) => value,
        Err(status) => return status,
    };
    let mut value = match cloned(endpoint) {
        Ok(value) => value,
        Err(status) => return status,
    };
    let path = joined_path(value.path(), source.path());
    value.set_path(&path);
    value.set_query(source.query());
    value.set_fragment(source.fragment());
    hold(value, output)
}

#[unsafe(no_mangle)]
/// Resolves a WHATWG URL reference against an existing absolute URL.
///
/// # Safety
/// When `length` is nonzero, `reference` must be readable for `length` bytes.
/// `output` must be writable for one `u64`.
pub unsafe extern "C" fn nuppNativeV2UriResolve(
    raw: u64,
    reference: *const u8,
    length: usize,
    output: *mut u64,
) -> i32 {
    let reference = match text(reference, length, "URI reference") {
        Ok(value) => value,
        Err(status) => return status,
    };
    let base = match cloned(raw) {
        Ok(value) => value,
        Err(status) => return status,
    };
    match base.join(reference) {
        Ok(value) => hold(value, output),
        Err(_) => failed(
            Status::InvalidArgument,
            "the URI reference cannot be resolved against this URI",
        ),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn parse(source: &str) -> u64 {
        let mut handle = 0;
        assert_eq!(
            unsafe { nuppNativeV2UriParse(source.as_ptr(), source.len(), &mut handle) },
            Status::Ok.code()
        );
        handle
    }

    fn component(handle: u64, kind: u32) -> Option<String> {
        let mut length = 0;
        let mut present = 0;
        assert_eq!(
            unsafe {
                nuppNativeV2UriPart(handle, kind, ptr::null_mut(), 0, &mut length, &mut present)
            },
            0
        );
        if present == 0 {
            return None;
        }
        let mut output = vec![0; length];
        assert_eq!(
            unsafe {
                nuppNativeV2UriPart(
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
        assert_eq!(nuppNativeV2UriRelease(handle), 0);
        assert_eq!(nuppNativeV2UriRelease(handle), Status::StaleHandle.code());
    }

    #[test]
    fn opaque_and_empty_authorities_remain_distinct() {
        let opaque = parse("mailto:someone@example.com");
        assert_eq!(component(opaque, 2), None);
        assert_eq!(component(opaque, 6).as_deref(), Some("someone@example.com"));
        let file = parse("file:///tmp/x");
        assert_eq!(component(file, 2).as_deref(), Some(""));
        assert_eq!(component(file, 5), None);
        assert_eq!(nuppNativeV2UriRelease(opaque), 0);
        assert_eq!(nuppNativeV2UriRelease(file), 0);
    }

    #[test]
    fn derivations_do_not_mutate_the_source() {
        let source = parse("https://example.com/api?q=1#top");
        let endpoint = parse("http://127.0.0.1:8080/prefix");
        let mut derived = 0;
        assert_eq!(
            unsafe { nuppNativeV2UriWithEndpoint(source, endpoint, &mut derived) },
            0
        );
        assert_eq!(
            component(derived, 0).as_deref(),
            Some("http://127.0.0.1:8080/prefix/api?q=1#top")
        );
        assert_eq!(
            component(source, 0).as_deref(),
            Some("https://example.com/api?q=1#top")
        );
        for handle in [source, endpoint, derived] {
            assert_eq!(nuppNativeV2UriRelease(handle), 0);
        }
    }

    #[test]
    fn malformed_text_keeps_the_public_reasons() {
        for (source, reason) in [
            ("", "relative URL without a base"),
            ("http://[", "invalid IPv6 address"),
            ("http:", "empty host"),
        ] {
            let mut handle = 0;
            assert_eq!(
                unsafe { nuppNativeV2UriParse(source.as_ptr(), source.len(), &mut handle) },
                Status::InvalidArgument.code()
            );
            nupp_native_abi::with_last_error(|error| assert_eq!(error.to_str().unwrap(), reason));
        }
    }
}
