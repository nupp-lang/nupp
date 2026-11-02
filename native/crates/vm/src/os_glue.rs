//! The operating-system edges native code reaches by C ABI: pages, a clock,
//! and standard input and output for standalone harnesses. A member
//! `name` of `nupp.runtime.vm.os` (`src/nupp/runtime/vm/os.d.nupp`) is the
//! symbol `nupp_os_<name in snake case>` here; the declaration gives it its
//! types and the lowering reads them from there. Nothing here knows what the
//! pages hold: the runtime's arenas and heap are written in Nupp over them.
#[cfg(windows)]
mod win {
    use std::ffi::c_void;
    pub const MEM_COMMIT: u32 = 0x1000;
    pub const MEM_RESERVE: u32 = 0x2000;
    pub const MEM_RELEASE: u32 = 0x8000;
    pub const MEM_RESET: u32 = 0x8_0000;
    pub const PAGE_READWRITE: u32 = 0x04;
    #[repr(C)]
    pub struct SystemInfo {
        pub processor_architecture: u16,
        pub reserved: u16,
        pub page_size: u32,
        pub minimum_application_address: *mut c_void,
        pub maximum_application_address: *mut c_void,
        pub active_processor_mask: usize,
        pub number_of_processors: u32,
        pub processor_type: u32,
        pub allocation_granularity: u32,
        pub processor_level: u16,
        pub processor_revision: u16,
    }
    unsafe extern "system" {
        pub fn VirtualAlloc(address: *mut c_void, size: usize, kind: u32, protect: u32) -> *mut c_void;
        pub fn VirtualFree(address: *mut c_void, size: usize, kind: u32) -> i32;
        pub fn GetSystemInfo(info: *mut SystemInfo);
    }
}

/// Maps `bytes` of zeroed, readable and writable, page-aligned memory, or
/// answers null when the system refuses. The size is rounded up to whole
/// pages by the system; the caller unmaps with the same size.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn nupp_os_map_pages(bytes: u64) -> *mut u8 {
    if bytes == 0 {
        return std::ptr::null_mut();
    }
    #[cfg(unix)]
    unsafe {
        let mapped = libc::mmap(
            std::ptr::null_mut(),
            bytes as usize,
            libc::PROT_READ | libc::PROT_WRITE,
            libc::MAP_PRIVATE | libc::MAP_ANONYMOUS,
            -1,
            0,
        );
        if mapped == libc::MAP_FAILED { std::ptr::null_mut() } else { mapped as *mut u8 }
    }
    #[cfg(windows)]
    unsafe {
        win::VirtualAlloc(
            std::ptr::null_mut(),
            bytes as usize,
            win::MEM_COMMIT | win::MEM_RESERVE,
            win::PAGE_READWRITE,
        ) as *mut u8
    }
}

/// Unmaps what `nupp_os_map_pages` mapped at `base` for `bytes`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn nupp_os_unmap_pages(base: *mut u8, bytes: u64) {
    if base.is_null() {
        return;
    }
    #[cfg(unix)]
    unsafe {
        libc::munmap(base as *mut libc::c_void, bytes as usize);
    }
    #[cfg(windows)]
    unsafe {
        let _ = bytes;
        win::VirtualFree(base as *mut std::ffi::c_void, 0, win::MEM_RELEASE);
    }
}

/// Advises the system about the pages at `base`: `0` says their contents are
/// no longer needed and may be dropped (they read back as zero or as they
/// were; the mapping stays), `1` says they are about to be used.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn nupp_os_advise_pages(base: *mut u8, bytes: u64, advice: i64) {
    if base.is_null() || bytes == 0 {
        return;
    }
    #[cfg(unix)]
    unsafe {
        let advice = match advice {
            0 => libc::MADV_DONTNEED,
            _ => libc::MADV_WILLNEED,
        };
        libc::madvise(base as *mut libc::c_void, bytes as usize, advice);
    }
    #[cfg(windows)]
    unsafe {
        if advice == 0 {
            win::VirtualAlloc(base as *mut std::ffi::c_void, bytes as usize, win::MEM_RESET, win::PAGE_READWRITE);
        }
    }
}

/// The system's page size in bytes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn nupp_os_page_size() -> u64 {
    #[cfg(unix)]
    unsafe {
        libc::sysconf(libc::_SC_PAGESIZE) as u64
    }
    #[cfg(windows)]
    unsafe {
        let mut info: win::SystemInfo = std::mem::zeroed();
        win::GetSystemInfo(&mut info);
        info.page_size as u64
    }
}

/// A monotonic clock in nanoseconds, for measurements written in the profile.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn nupp_os_monotonic_nanos() -> u64 {
    use std::sync::OnceLock;
    static START: OnceLock<std::time::Instant> = OnceLock::new();
    START.get_or_init(std::time::Instant::now).elapsed().as_nanos() as u64
}

/// Reads up to `bytes` of standard input into `base`: the count read, 0 at
/// its end, -1 when the read failed. A standalone harness reads its data so.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn nupp_os_read_input(base: *mut u8, bytes: u64) -> i64 {
    use std::io::Read;
    if base.is_null() {
        return -1;
    }
    let buffer = unsafe { std::slice::from_raw_parts_mut(base, bytes as usize) };
    loop {
        match std::io::stdin().lock().read(buffer) {
            Ok(n) => return n as i64,
            Err(e) if e.kind() == std::io::ErrorKind::Interrupted => continue,
            Err(_) => return -1,
        }
    }
}

/// Writes `bytes` at `base` to standard output: the count written, -1 when
/// the write failed.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn nupp_os_write_output(base: *const u8, bytes: u64) -> i64 {
    use std::io::Write;
    if base.is_null() {
        return -1;
    }
    let buffer = unsafe { std::slice::from_raw_parts(base, bytes as usize) };
    let mut out = std::io::stdout().lock();
    match out.write_all(buffer).and_then(|()| out.flush()) {
        Ok(()) => bytes as i64,
        Err(_) => -1,
    }
}

/// Copies the environment variable named by the `name_bytes` bytes at `name`
/// into `out`, at most `room` bytes: the value's whole length, or -1 when it
/// is unset.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn nupp_os_environment(
    name: *const u8,
    name_bytes: u64,
    out: *mut u8,
    room: u64,
) -> i64 {
    if name.is_null() {
        return -1;
    }
    let key = unsafe { std::slice::from_raw_parts(name, name_bytes as usize) };
    let Some(value) = environment_value(key) else {
        return -1;
    };
    if !out.is_null() {
        let count = value.len().min(room as usize);
        unsafe { std::ptr::copy_nonoverlapping(value.as_ptr(), out, count) };
    }
    value.len() as i64
}

#[cfg(unix)]
fn environment_value(key: &[u8]) -> Option<Vec<u8>> {
    use std::os::unix::ffi::{OsStrExt, OsStringExt};
    std::env::var_os(std::ffi::OsStr::from_bytes(key)).map(OsStringExt::into_vec)
}

#[cfg(not(unix))]
fn environment_value(key: &[u8]) -> Option<Vec<u8>> {
    std::env::var(std::str::from_utf8(key).ok()?).ok().map(String::into_bytes)
}

unsafe extern "C" {
    fn snprintf(
        out: *mut std::ffi::c_char,
        room: usize,
        format: *const std::ffi::c_char,
        ...
    ) -> i32;
    fn strtod(text: *const std::ffi::c_char, end: *mut *mut std::ffi::c_char) -> f64;
}

// A float conversion string.format builds: `%`, flags from "-+ #0", at
/// most two width digits, an optional `.` and at most two precision digits,
/// and one of "aAeEfFgG", NUL-terminated within 16 bytes. Nothing else is
/// handed to snprintf.
fn float_spec(bytes: &[u8; 16]) -> bool {
    let Some(end) = bytes.iter().position(|&b| b == 0) else { return false };
    let spec = &bytes[..end];
    if spec.len() < 2 || spec[0] != b'%' {
        return false;
    }
    let mut at = 1;
    while at < spec.len() && b"-+ #0".contains(&spec[at]) {
        at += 1;
    }
    let digits = |at: &mut usize| {
        let start = *at;
        while *at < spec.len() && spec[*at].is_ascii_digit() {
            *at += 1;
        }
        *at - start <= 2
    };
    if !digits(&mut at) {
        return false;
    }
    if at < spec.len() && spec[at] == b'.' {
        at += 1;
        if !digits(&mut at) {
            return false;
        }
    }
    at + 1 == spec.len() && b"aAeEfFgG".contains(&spec[at])
}

/// The `room` bit that says `out` holds a float_spec to format with.
const FORMAT_SPEC: u64 = 1 << 63;

/// Writes the binary64 `bits` as Lua 5.5 writes a float, C's "%.15g" or,
/// when that reads back as another number, "%.17g", into `out`, at most
/// `room` bytes: the text's whole length.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn nupp_os_format_number(bits: u64, out: *mut u8, room: u64) -> i64 {
    let value = f64::from_bits(bits);
    // string.format's float conversions: the spec is in `out`.
    if room & FORMAT_SPEC != 0 {
        if out.is_null() {
            return -1;
        }
        let mut spec = [0u8; 16];
        unsafe { std::ptr::copy_nonoverlapping(out as *const u8, spec.as_mut_ptr(), 16) };
        if !float_spec(&spec) {
            return -1;
        }
        let mut text = [0u8; 512];
        let written = unsafe { snprintf(text.as_mut_ptr().cast(), text.len(), spec.as_ptr().cast(), value) };
        if written < 0 {
            return -1;
        }
        let length = (written as usize).min(text.len() - 1);
        let room = room & !FORMAT_SPEC;
        unsafe { std::ptr::copy_nonoverlapping(text.as_ptr(), out as *mut u8, length.min(room as usize)) };
        return length as i64;
    }
    let mut text = [0u8; 64];
    let mut written = unsafe { snprintf(text.as_mut_ptr().cast(), text.len(), c"%.15g".as_ptr(), value) };
    // Lua 5.5 writes 15 digits unless they read back as another number.
    if written >= 0 && unsafe { strtod(text.as_ptr().cast(), std::ptr::null_mut()) }.to_bits() != bits {
        written = unsafe { snprintf(text.as_mut_ptr().cast(), text.len(), c"%.17g".as_ptr(), value) };
    }
    if written < 0 {
        return -1;
    }
    let length = (written as usize).min(text.len() - 1);
    if !out.is_null() {
        unsafe { std::ptr::copy_nonoverlapping(text.as_ptr(), out, length.min(room as usize)) };
    }
    length as i64
}

unsafe extern "C" {
    fn pow(x: f64, y: f64) -> f64;
    fn exp(x: f64) -> f64;
    fn log(x: f64) -> f64;
    fn log2(x: f64) -> f64;
    fn log10(x: f64) -> f64;
    fn sin(x: f64) -> f64;
    fn cos(x: f64) -> f64;
    fn tan(x: f64) -> f64;
    fn asin(x: f64) -> f64;
    fn acos(x: f64) -> f64;
    fn atan2(y: f64, x: f64) -> f64;
    fn fmod(x: f64, y: f64) -> f64;
}

/// C's math function `op` of the binary64 `x` (and `y`, for the two-operand
/// ones), as its binary64 bits: 0 pow, 1 exp, 2 log, 3 log2, 4 log10, 5 sin,
/// 6 cos, 7 tan, 8 asin, 9 acos, 10 atan2(x, y), 11 fmod. NaN for any other.
fn math(op: u64, x: u64, y: u64) -> u64 {
    let (x, y) = (f64::from_bits(x), f64::from_bits(y));
    let value = unsafe {
        match op {
            0 => pow(x, y),
            1 => exp(x),
            2 => log(x),
            3 => log2(x),
            4 => log10(x),
            5 => sin(x),
            6 => cos(x),
            7 => tan(x),
            8 => asin(x),
            9 => acos(x),
            10 => atan2(x, y),
            11 => fmod(x, y),
            _ => f64::NAN,
        }
    };
    value.to_bits()
}

/// C's math function `op` of `x` and `y`, binary64 bits in and out (see
/// `math`).
#[unsafe(no_mangle)]
pub unsafe extern "C" fn nupp_os_math_function(op: u64, x: u64, y: u64) -> u64 {
    math(op, x, y)
}

/// A seed for the guest's random numbers: the wall clock in nanoseconds mixed
/// with an address and the process id.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn nupp_os_random_seed() -> u64 {
    let clock = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|elapsed| elapsed.as_nanos() as u64)
        .unwrap_or(0);
    let local = 0u8;
    clock ^ (&local as *const u8 as u64).rotate_left(32) ^ u64::from(std::process::id())
}

/// Reads the `bytes` at `text` as C's strtod does, the whole text but for
/// surrounding space: 1 with the binary64 bits stored at `out`, or 0 when it
/// is not one numeral.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn nupp_os_parse_number(text: *const u8, bytes: u64, out: *mut u64) -> i64 {
    if text.is_null() || out.is_null() {
        return 0;
    }
    let source = unsafe { std::slice::from_raw_parts(text, bytes as usize) };
    if source.contains(&0) {
        return 0;
    }
    let mut owned = source.to_vec();
    owned.push(0);
    let start = owned.as_ptr().cast::<std::ffi::c_char>();
    let mut end = std::ptr::null_mut();
    let value = unsafe { strtod(start, &mut end) };
    let mut at = end as usize - start as usize;
    if at == 0 {
        return 0;
    }
    while at < source.len() && matches!(source[at], b' ' | b'\t' | b'\n' | 0x0b | 0x0c | b'\r') {
        at += 1;
    }
    if at != source.len() {
        return 0;
    }
    unsafe { out.write(value.to_bits()) };
    1
}

/// The address of an operating-system edge by its symbol, for a runner that
/// links native code into this process rather than against the runtime.
pub fn symbol(name: &str) -> Option<*const u8> {
    Some(match name {
        "nupp_os_map_pages" => nupp_os_map_pages as *const u8,
        "nupp_os_unmap_pages" => nupp_os_unmap_pages as *const u8,
        "nupp_os_advise_pages" => nupp_os_advise_pages as *const u8,
        "nupp_os_page_size" => nupp_os_page_size as *const u8,
        "nupp_os_monotonic_nanos" => nupp_os_monotonic_nanos as *const u8,
        "nupp_os_read_input" => nupp_os_read_input as *const u8,
        "nupp_os_write_output" => nupp_os_write_output as *const u8,
        "nupp_os_environment" => nupp_os_environment as *const u8,
        "nupp_os_format_number" => nupp_os_format_number as *const u8,
        "nupp_os_parse_number" => nupp_os_parse_number as *const u8,
        "nupp_os_math_function" => nupp_os_math_function as *const u8,
        "nupp_os_random_seed" => nupp_os_random_seed as *const u8,
        _ => return None,
    })
}
