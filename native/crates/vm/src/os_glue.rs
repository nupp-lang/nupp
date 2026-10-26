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
        _ => return None,
    })
}
