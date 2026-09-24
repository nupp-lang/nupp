//! The platform's own loader: `dlopen` or `LoadLibrary`. Nothing here
//! relocates, binds or registers unwind information; the OS does all of it.

use std::ffi::{CString, c_void};

pub struct Lib(pub *mut c_void);

#[cfg(unix)]
mod imp {
    use super::*;
    use std::ffi::CStr;

    pub fn open(path: &str, global: bool) -> Result<*mut c_void, String> {
        let c = CString::new(path).unwrap();
        let flags = libc::RTLD_NOW | if global { libc::RTLD_GLOBAL } else { libc::RTLD_LOCAL };
        let h = unsafe { libc::dlopen(c.as_ptr(), flags) };
        if h.is_null() {
            return Err(unsafe { CStr::from_ptr(libc::dlerror()) }.to_string_lossy().into_owned());
        }
        Ok(h)
    }

    pub fn sym(h: *mut c_void, name: &str) -> *mut c_void {
        let n = CString::new(name).unwrap();
        unsafe { libc::dlsym(h, n.as_ptr()) }
    }

    pub fn global(name: &str) -> *mut c_void {
        sym(libc::RTLD_DEFAULT, name)
    }
}

#[cfg(windows)]
mod imp {
    use super::*;
    use std::sync::Mutex;

    unsafe extern "system" {
        fn LoadLibraryA(name: *const i8) -> *mut c_void;
        fn GetProcAddress(h: *mut c_void, name: *const i8) -> *mut c_void;
        fn GetLastError() -> u32;
    }

    /// Windows has no global scope: what was opened "globally" is searched in
    /// order, as `dlsym(RTLD_DEFAULT)` would search it.
    static GLOBAL: Mutex<Vec<usize>> = Mutex::new(Vec::new());

    pub fn open(path: &str, global: bool) -> Result<*mut c_void, String> {
        let c = CString::new(path).unwrap();
        let h = unsafe { LoadLibraryA(c.as_ptr()) };
        if h.is_null() {
            return Err(format!("LoadLibrary {path}: error {}", unsafe { GetLastError() }));
        }
        if global {
            GLOBAL.lock().unwrap().push(h as usize);
        }
        Ok(h)
    }

    pub fn sym(h: *mut c_void, name: &str) -> *mut c_void {
        let n = CString::new(name).unwrap();
        unsafe { GetProcAddress(h, n.as_ptr()) }
    }

    pub fn global(name: &str) -> *mut c_void {
        for h in GLOBAL.lock().unwrap().iter() {
            let p = sym(*h as *mut c_void, name);
            if !p.is_null() {
                return p;
            }
        }
        std::ptr::null_mut()
    }
}

impl Lib {
    pub fn open(path: &str, global: bool) -> Result<Lib, String> {
        imp::open(path, global).map(Lib)
    }
    pub fn sym(&self, name: &str) -> *const u8 {
        let p = imp::sym(self.0, name);
        assert!(!p.is_null(), "no symbol {name}");
        p as *const u8
    }
}

/// A symbol from anything opened globally (the Lua C API, the runtime).
pub fn global(name: &str) -> *mut c_void {
    let p = imp::global(name);
    assert!(!p.is_null(), "unresolved {name}");
    p
}

/// A clock every process on the machine shares; the component uses the same.
pub fn now_ns() -> u64 {
    #[cfg(target_os = "macos")]
    unsafe {
        unsafe extern "C" {
            fn clock_gettime_nsec_np(clock: u32) -> u64;
        }
        clock_gettime_nsec_np(8) // CLOCK_UPTIME_RAW
    }
    #[cfg(target_os = "linux")]
    unsafe {
        let mut t = libc::timespec { tv_sec: 0, tv_nsec: 0 };
        libc::clock_gettime(libc::CLOCK_MONOTONIC, &mut t);
        t.tv_sec as u64 * 1_000_000_000 + t.tv_nsec as u64
    }
    #[cfg(windows)]
    unsafe {
        unsafe extern "system" {
            fn QueryPerformanceCounter(c: *mut i64) -> i32;
            fn QueryPerformanceFrequency(f: *mut i64) -> i32;
        }
        let (mut c, mut f) = (0i64, 0i64);
        QueryPerformanceCounter(&mut c);
        QueryPerformanceFrequency(&mut f);
        (c as i128 * 1_000_000_000 / f as i128) as u64
    }
}
