//! OS memory primitives, the environment and C's number text; no runtime
//! object or frame policy.
use std::ffi::c_void;

unsafe extern "C" {
    fn mmap(
        address: *mut c_void,
        length: usize,
        protection: i32,
        flags: i32,
        fd: i32,
        offset: i64,
    ) -> *mut c_void;
    fn munmap(address: *mut c_void, length: usize) -> i32;
    fn mprotect(address: *mut c_void, length: usize, protection: i32) -> i32;
    fn getpagesize() -> i32;
    #[cfg(target_os = "macos")]
    fn sys_icache_invalidate(address: *mut c_void, length: usize);
}

pub fn supported() -> bool {
    cfg!(all(
        target_arch = "aarch64",
        target_endian = "little",
        any(target_os = "macos", target_os = "linux")
    ))
}

pub extern "C" fn page_size() -> u64 {
    unsafe { getpagesize() as u64 }
}

fn rounded(bytes: u64) -> Option<usize> {
    let page = page_size();
    if bytes == 0 || page == 0 || !page.is_power_of_two() {
        return None;
    }
    let size = bytes.checked_add(page - 1)? & !(page - 1);
    (size <= isize::MAX as u64).then_some(size as usize)
}

pub extern "C" fn map_pages(bytes: u64) -> u64 {
    let Some(size) = rounded(bytes) else {
        return 0;
    };
    let anonymous = if cfg!(target_os = "macos") {
        0x1000
    } else {
        0x20
    };
    let address = unsafe { mmap(std::ptr::null_mut(), size, 3, 2 | anonymous, -1, 0) };
    if address as isize == -1 {
        0
    } else {
        address as u64
    }
}

// The caller owns the mapping and must have finished all access before unmapping.
pub unsafe extern "C" fn unmap_pages(address: u64, bytes: u64) -> u64 {
    let Some(size) = rounded(bytes) else {
        return 1;
    };
    if address == 0 || address % page_size() != 0 {
        return 1;
    }
    u64::from(unsafe { munmap(address as *mut c_void, size) } != 0)
}

pub struct Mapping {
    pub address: *mut u8,
    size: usize,
}

impl Mapping {
    pub fn new(bytes: usize) -> Result<Self, String> {
        if bytes == 0 {
            return Ok(Self {
                address: std::ptr::null_mut(),
                size: 0,
            });
        }
        let address = map_pages(bytes as u64) as *mut u8;
        if address.is_null() {
            return Err(format!("map failed: {}", std::io::Error::last_os_error()));
        }
        Ok(Self {
            address,
            size: bytes,
        })
    }

    pub fn copy(&mut self, bytes: &[u8]) {
        assert!(bytes.len() <= self.size);
        if !bytes.is_empty() {
            unsafe {
                std::ptr::copy_nonoverlapping(bytes.as_ptr(), self.address, bytes.len());
            }
        }
    }

    pub fn executable(&mut self) -> Result<(), String> {
        if unsafe { mprotect(self.address.cast(), self.size, 5) } != 0 {
            return Err(format!("seal failed: {}", std::io::Error::last_os_error()));
        }
        unsafe {
            flush(self.address, self.size);
        }
        Ok(())
    }
}

impl Drop for Mapping {
    fn drop(&mut self) {
        if self.size != 0 {
            unsafe {
                unmap_pages(self.address as u64, self.size as u64);
            }
        }
    }
}

unsafe fn flush(address: *mut u8, size: usize) {
    #[cfg(target_os = "macos")]
    unsafe {
        sys_icache_invalidate(address.cast(), size);
    }
    #[cfg(all(target_os = "linux", target_arch = "aarch64"))]
    unsafe {
        // ARM's required data-to-instruction coherency sequence for this thread.
        // No generated entry can escape the scoped invocation to another thread.
        let ctr: u64;
        std::arch::asm!("mrs {ctr}, ctr_el0", ctr = out(reg) ctr, options(nostack, preserves_flags));
        let data_line = 4usize << ((ctr >> 16) & 15);
        let instruction_line = 4usize << (ctr & 15);
        let end = address as usize + size;
        let mut at = address as usize & !(data_line - 1);
        while at < end {
            std::arch::asm!("dc cvau, {at}", at = in(reg) at, options(nostack, preserves_flags));
            at += data_line;
        }
        std::arch::asm!("dsb ish", options(nostack, preserves_flags));
        at = address as usize & !(instruction_line - 1);
        while at < end {
            std::arch::asm!("ic ivau, {at}", at = in(reg) at, options(nostack, preserves_flags));
            at += instruction_line;
        }
        std::arch::asm!("dsb ish", "isb", options(nostack, preserves_flags));
    }
    #[cfg(not(any(target_os = "macos", all(target_os = "linux", target_arch = "aarch64"))))]
    let _ = (address, size);
}

/// Copies the environment variable named by the `name_bytes` bytes at `name`
/// into `out`, at most `room` bytes: the value's whole length, or -1 when it
/// is unset. The guest's `os.getenv`.
pub unsafe extern "C" fn environment(name: u64, name_bytes: u64, out: u64, room: u64) -> u64 {
    use std::os::unix::ffi::{OsStrExt, OsStringExt};
    if name == 0 {
        return u64::MAX;
    }
    let key = unsafe { std::slice::from_raw_parts(name as *const u8, name_bytes as usize) };
    let Some(value) = std::env::var_os(std::ffi::OsStr::from_bytes(key)).map(OsStringExt::into_vec)
    else {
        return u64::MAX;
    };
    if out != 0 {
        let count = value.len().min(room as usize);
        unsafe { std::ptr::copy_nonoverlapping(value.as_ptr(), out as *mut u8, count) };
    }
    value.len() as u64
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
/// `room` bytes: the text's whole length. The guest's float text.
pub unsafe extern "C" fn format_number(bits: u64, out: u64, room: u64) -> u64 {
    let value = f64::from_bits(bits);
    // string.format's float conversions: the spec is in `out`.
    if room & FORMAT_SPEC != 0 {
        if out == 0 {
            return u64::MAX;
        }
        let mut spec = [0u8; 16];
        unsafe { std::ptr::copy_nonoverlapping(out as *const u8, spec.as_mut_ptr(), 16) };
        if !float_spec(&spec) {
            return u64::MAX;
        }
        let mut text = [0u8; 512];
        let written = unsafe { snprintf(text.as_mut_ptr().cast(), text.len(), spec.as_ptr().cast(), value) };
        if written < 0 {
            return u64::MAX;
        }
        let length = (written as usize).min(text.len() - 1);
        let room = room & !FORMAT_SPEC;
        unsafe { std::ptr::copy_nonoverlapping(text.as_ptr(), out as *mut u8, length.min(room as usize)) };
        return length as u64;
    }
    let mut text = [0u8; 64];
    let mut written = unsafe { snprintf(text.as_mut_ptr().cast(), text.len(), c"%.15g".as_ptr(), value) };
    // Lua 5.5 writes 15 digits unless they read back as another number.
    if written >= 0 && unsafe { strtod(text.as_ptr().cast(), std::ptr::null_mut()) }.to_bits() != bits {
        written = unsafe { snprintf(text.as_mut_ptr().cast(), text.len(), c"%.17g".as_ptr(), value) };
    }
    if written < 0 {
        return u64::MAX;
    }
    let length = (written as usize).min(text.len() - 1);
    if out != 0 {
        unsafe { std::ptr::copy_nonoverlapping(text.as_ptr(), out as *mut u8, length.min(room as usize)) };
    }
    length as u64
}

/// Reads the `bytes` at `text` as C's strtod does, the whole text but for
/// surrounding space: 1 with the binary64 bits stored at `out`, or 0 when it
/// is not one numeral. The guest's tonumber of float text.
pub unsafe extern "C" fn parse_number(text: u64, bytes: u64, out: u64) -> u64 {
    if text == 0 || out == 0 {
        return 0;
    }
    let source = unsafe { std::slice::from_raw_parts(text as *const u8, bytes as usize) };
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
    unsafe { (out as *mut u64).write(value.to_bits()) };
    1
}

/// Writes the `bytes` bytes at `base` to standard output and flushes it: the
/// count written, or all ones when writing fails. The guest's print.
pub unsafe extern "C" fn write_output(base: u64, bytes: u64) -> u64 {
    use std::io::Write;
    if base == 0 && bytes != 0 {
        return u64::MAX;
    }
    let buffer: &[u8] =
        if bytes == 0 { &[] } else { unsafe { std::slice::from_raw_parts(base as *const u8, bytes as usize) } };
    let mut out = std::io::stdout().lock();
    match out.write_all(buffer).and_then(|()| out.flush()) {
        Ok(()) => bytes,
        Err(_) => u64::MAX,
    }
}
