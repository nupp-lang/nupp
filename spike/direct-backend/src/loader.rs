//! The whole loader for a relocation-free image: map, copy, protect, flush.

pub struct Image {
    base: *mut u8,
    len: usize,
}

unsafe extern "C" {
    fn sys_icache_invalidate(start: *mut libc::c_void, len: libc::size_t);
}

impl Image {
    pub fn load(code: &[u8]) -> Image {
        let len = (code.len() + 16383) & !16383;
        unsafe {
            let base = libc::mmap(
                std::ptr::null_mut(),
                len,
                libc::PROT_READ | libc::PROT_WRITE,
                libc::MAP_PRIVATE | libc::MAP_ANON,
                -1,
                0,
            );
            assert!(base != libc::MAP_FAILED);
            std::ptr::copy_nonoverlapping(code.as_ptr(), base as *mut u8, code.len());
            assert_eq!(libc::mprotect(base, len, libc::PROT_READ | libc::PROT_EXEC), 0);
            sys_icache_invalidate(base, code.len());
            Image { base: base as *mut u8, len }
        }
    }
    pub fn entry(&self) -> *const u8 {
        self.base
    }
}

impl Drop for Image {
    fn drop(&mut self) {
        unsafe {
            libc::munmap(self.base as *mut libc::c_void, self.len);
        }
    }
}
