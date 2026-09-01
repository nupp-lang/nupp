//! Versioned Rust-native facade. No legacy provider symbol is defined here.

#![forbid(unsafe_op_in_unsafe_fn)]

use nupp_native_abi::{ABI_VERSION, Arena, Handle, Status, last_error_ptr, set_last_error};
use std::ffi::c_char;
use std::ptr;
use std::sync::{Mutex, OnceLock};

#[cfg(any(feature = "files", feature = "filesystem"))]
mod files;
#[cfg(feature = "gpu")]
mod gpu;
#[cfg(feature = "http")]
mod http;
#[cfg(feature = "process")]
mod process;
#[cfg(feature = "uri")]
mod uri;

const FEATURE_BASE: u64 = 1 << 0;
const FEATURE_UUID: u64 = 1 << 1;
const FEATURE_GPU: u64 = 1 << 2;
const FEATURE_URI: u64 = 1 << 3;
const FEATURE_HTTP: u64 = 1 << 4;
const FEATURE_PROCESS: u64 = 1 << 5;
const FEATURE_FILESYSTEM: u64 = 1 << 6;
const FEATURE_FILES: u64 = 1 << 7;

fn bytes() -> &'static Mutex<Arena<Box<[u8]>>> {
    static BYTES: OnceLock<Mutex<Arena<Box<[u8]>>>> = OnceLock::new();
    BYTES.get_or_init(|| Mutex::new(Arena::new()))
}

pub(crate) fn store_bytes(value: Vec<u8>) -> Result<u64, i32> {
    match bytes().lock() {
        Ok(mut arena) => arena
            .insert(value.into_boxed_slice())
            .map(Handle::raw)
            .map_err(|status| failed(status, "byte handle capacity is exhausted")),
        Err(_) => Err(failed(Status::Internal, "byte handle store is poisoned")),
    }
}

#[cfg(feature = "files")]
pub(crate) fn remember_error(message: &str) {
    set_last_error(message);
}

pub(crate) fn failed(status: Status, message: &str) -> i32 {
    set_last_error(message);
    status.code()
}

pub(crate) fn input<'a>(data: *const u8, length: usize) -> Result<&'a [u8], i32> {
    if length == 0 {
        return Ok(&[]);
    }
    if data.is_null() {
        return Err(failed(Status::InvalidArgument, "input pointer is null"));
    }
    // SAFETY: the versioned ABI requires `data` to remain readable for
    // `length` bytes for the duration of this call.
    Ok(unsafe { std::slice::from_raw_parts(data, length) })
}

#[unsafe(no_mangle)]
pub extern "C" fn nuppNativeV2AbiVersion() -> u32 {
    ABI_VERSION
}

#[unsafe(no_mangle)]
pub extern "C" fn nuppNativeV2Features() -> u64 {
    FEATURE_BASE
        | if cfg!(feature = "uuid") {
            FEATURE_UUID
        } else {
            0
        }
        | if cfg!(feature = "gpu") {
            FEATURE_GPU
        } else {
            0
        }
        | if cfg!(feature = "uri") {
            FEATURE_URI
        } else {
            0
        }
        | if cfg!(feature = "http") {
            FEATURE_HTTP
        } else {
            0
        }
        | if cfg!(feature = "process") {
            FEATURE_PROCESS
        } else {
            0
        }
        | if cfg!(feature = "filesystem") {
            FEATURE_FILESYSTEM
        } else {
            0
        }
        | if cfg!(feature = "files") {
            FEATURE_FILES
        } else {
            0
        }
}

#[unsafe(no_mangle)]
pub extern "C" fn nuppNativeV2LastError() -> *const c_char {
    last_error_ptr()
}

#[unsafe(no_mangle)]
/// Copies one caller-owned byte range into a new generational handle.
///
/// # Safety
///
/// When `length` is nonzero, `data` must be readable for `length` bytes.
/// `output` must point to writable storage for one `u64`.
pub unsafe extern "C" fn nuppNativeV2BytesCreate(
    data: *const u8,
    length: usize,
    output: *mut u64,
) -> i32 {
    if output.is_null() {
        return failed(Status::InvalidArgument, "byte handle output is null");
    }
    let value = match input(data, length) {
        Ok(value) => value.to_vec(),
        Err(status) => return status,
    };
    let handle = match store_bytes(value) {
        Ok(handle) => handle,
        Err(status) => return status,
    };
    // SAFETY: the caller supplied writable storage for one u64.
    unsafe { output.write(handle) };
    Status::Ok.code()
}

#[unsafe(no_mangle)]
/// Copies the allocation behind a byte handle into caller-owned storage.
///
/// # Safety
///
/// `output_length` must be writable. When `capacity` is nonzero, `output_data`
/// must be writable for `capacity` bytes.
pub unsafe extern "C" fn nuppNativeV2BytesCopy(
    raw: u64,
    output_data: *mut u8,
    capacity: usize,
    output_length: *mut usize,
) -> i32 {
    if output_length.is_null() || (capacity != 0 && output_data.is_null()) {
        return failed(Status::InvalidArgument, "byte copy output is null");
    }
    let arena = match bytes().lock() {
        Ok(arena) => arena,
        Err(_) => return failed(Status::Internal, "byte handle store is poisoned"),
    };
    let value = match arena.get(Handle::from_raw(raw)) {
        Ok(value) => value,
        Err(status) => return failed(status, "byte handle is stale"),
    };
    // SAFETY: `output_length` was checked above.
    unsafe { output_length.write(value.len()) };
    if capacity < value.len() {
        return failed(Status::Capacity, "byte copy output is too small");
    }
    if !value.is_empty() {
        // SAFETY: the caller promised `capacity` writable bytes and the check
        // above proves the allocation fits.
        unsafe { ptr::copy_nonoverlapping(value.as_ptr(), output_data, value.len()) };
    }
    Status::Ok.code()
}

#[unsafe(no_mangle)]
pub extern "C" fn nuppNativeV2BytesRelease(raw: u64) -> i32 {
    match bytes().lock() {
        Ok(mut arena) => match arena.remove(Handle::from_raw(raw)) {
            Ok(_) => Status::Ok.code(),
            Err(status) => failed(status, "byte handle is stale"),
        },
        Err(_) => failed(Status::Internal, "byte handle store is poisoned"),
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn nuppNativeV2MonotonicNs() -> u64 {
    nupp_native_platform::monotonic_ns()
}

#[unsafe(no_mangle)]
pub extern "C" fn nuppNativeV2WallMs() -> u64 {
    nupp_native_platform::wall_ms()
}

#[unsafe(no_mangle)]
pub extern "C" fn nuppNativeV2SleepMs(milliseconds: f64) -> i32 {
    match nupp_native_platform::sleep_ms(milliseconds) {
        Ok(()) => Status::Ok.code(),
        Err(message) => failed(Status::InvalidArgument, message),
    }
}

#[unsafe(no_mangle)]
/// Writes the two-seed, lowercase XXH64 cache digest.
///
/// # Safety
///
/// When `length` is nonzero, `data` must be readable for `length` bytes.
/// `output` must be writable for at least `capacity` bytes.
pub unsafe extern "C" fn nuppNativeV2Xxh64Digest(
    data: *const u8,
    length: usize,
    output: *mut u8,
    capacity: usize,
) -> i32 {
    if output.is_null() || capacity < 32 {
        return failed(Status::Capacity, "XXH64 digest output needs 32 bytes");
    }
    let value = match input(data, length) {
        Ok(value) => nupp_native_platform::cache_digest(value),
        Err(status) => return status,
    };
    // SAFETY: the output capacity was checked above.
    unsafe { ptr::copy_nonoverlapping(value.as_ptr(), output, value.len()) };
    Status::Ok.code()
}

#[unsafe(no_mangle)]
/// Writes the little-endian XXH64 prefix stored in a stamped payload trailer.
///
/// # Safety
///
/// When `length` is nonzero, `data` must be readable for `length` bytes.
/// `output` must be writable for eight bytes.
pub unsafe extern "C" fn nuppNativeV2TrailerDigest(
    data: *const u8,
    length: usize,
    output: *mut u8,
) -> i32 {
    if output.is_null() {
        return failed(Status::InvalidArgument, "trailer digest output is null");
    }
    let value = match input(data, length) {
        Ok(value) => nupp_native_platform::trailer_digest(value),
        Err(status) => return status,
    };
    // SAFETY: the ABI requires writable storage for the fixed eight-byte digest.
    unsafe { ptr::copy_nonoverlapping(value.as_ptr(), output, value.len()) };
    Status::Ok.code()
}

#[cfg(feature = "uuid")]
unsafe fn write_uuid(
    make: fn() -> Result<String, String>,
    output: *mut u8,
    capacity: usize,
) -> i32 {
    if output.is_null() || capacity < 37 {
        return failed(Status::Capacity, "UUID output needs 37 bytes");
    }
    let value = match make() {
        Ok(value) => value,
        Err(error) => return failed(Status::Internal, &error),
    };
    // SAFETY: the output capacity was checked and a canonical UUID is 36 bytes.
    unsafe {
        ptr::copy_nonoverlapping(value.as_ptr(), output, value.len());
        output.add(value.len()).write(0);
    }
    Status::Ok.code()
}

#[cfg(feature = "uuid")]
#[unsafe(no_mangle)]
/// Writes a canonical UUIDv4 followed by a NUL byte.
///
/// # Safety
///
/// `output` must be writable for at least `capacity` bytes.
pub unsafe extern "C" fn nuppNativeV2Uuid4(output: *mut u8, capacity: usize) -> i32 {
    unsafe { write_uuid(nupp_native_platform::uuid4, output, capacity) }
}

#[cfg(feature = "uuid")]
#[unsafe(no_mangle)]
/// Writes a canonical UUIDv7 followed by a NUL byte.
///
/// # Safety
///
/// `output` must be writable for at least `capacity` bytes.
pub unsafe extern "C" fn nuppNativeV2Uuid7(output: *mut u8, capacity: usize) -> i32 {
    unsafe { write_uuid(nupp_native_platform::uuid7, output, capacity) }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn bytes_are_validated_by_generation() {
        let mut handle = 0;
        assert_eq!(
            unsafe { nuppNativeV2BytesCreate(b"abc".as_ptr(), 3, &mut handle) },
            0
        );
        let mut data = [0; 3];
        let mut length = 0;
        assert_eq!(
            unsafe { nuppNativeV2BytesCopy(handle, data.as_mut_ptr(), data.len(), &mut length,) },
            0
        );
        assert_eq!(&data[..length], b"abc");
        assert_eq!(nuppNativeV2BytesRelease(handle), 0);
        assert_eq!(nuppNativeV2BytesRelease(handle), Status::StaleHandle.code());
    }

    #[test]
    fn digest_outputs_are_capacity_checked() {
        let mut short = [0; 31];
        assert_eq!(
            unsafe { nuppNativeV2Xxh64Digest(ptr::null(), 0, short.as_mut_ptr(), short.len()) },
            Status::Capacity.code()
        );
        let mut output = [0; 32];
        assert_eq!(
            unsafe { nuppNativeV2Xxh64Digest(ptr::null(), 0, output.as_mut_ptr(), output.len()) },
            0
        );
        assert_eq!(&output[..16], b"ef46db3751d8e999");
        let mut trailer = [0; 8];
        assert_eq!(
            unsafe { nuppNativeV2TrailerDigest(ptr::null(), 0, trailer.as_mut_ptr()) },
            0
        );
        assert_eq!(trailer, 0xef46_db37_51d8_e999_u64.to_le_bytes());
    }

    #[test]
    fn sleep_rejects_non_finite_and_negative_durations() {
        assert_eq!(nuppNativeV2SleepMs(0.0), 0);
        assert_eq!(nuppNativeV2SleepMs(-1.0), Status::InvalidArgument.code());
        assert_eq!(
            nuppNativeV2SleepMs(f64::NAN),
            Status::InvalidArgument.code()
        );
    }

    #[cfg(feature = "uuid")]
    #[test]
    fn uuid_outputs_are_canonical_and_checked() {
        let mut output = [0; 37];
        assert_eq!(
            unsafe { nuppNativeV2Uuid4(output.as_mut_ptr(), output.len()) },
            0
        );
        assert_eq!(output[14], b'4');
        assert_eq!(output[36], 0);
        assert_eq!(
            unsafe { nuppNativeV2Uuid7(output.as_mut_ptr(), 36) },
            Status::Capacity.code()
        );
    }
}
