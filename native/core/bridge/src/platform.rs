//! The memory the bridge loads a bundle into; no runtime object or frame
//! policy. The guest maps its own pages, through the C library.
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

pub fn page_size() -> u64 {
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

pub fn map_pages(bytes: u64) -> u64 {
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
pub unsafe fn unmap_pages(address: u64, bytes: u64) -> u64 {
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

