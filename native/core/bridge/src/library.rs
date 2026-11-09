//! The dynamic loader for the guest's foreign calls, as the C library has
//! it: `dlopen`, `dlsym`, `dlclose` and the thread's error number, passed
//! as they are. Nupp resolves each foreign symbol once and caches it in the
//! table this passes beside them; what to load and when is Nupp's.
use std::ffi::{c_char, c_int, c_void};
use std::sync::atomic::AtomicU64;

unsafe extern "C" {
    fn dlopen(path: *const c_char, mode: c_int) -> *mut c_void;
    fn dlsym(handle: *mut c_void, name: *const c_char) -> *mut c_void;
    fn dlclose(handle: *mut c_void) -> c_int;
    #[cfg_attr(target_os = "macos", link_name = "__error")]
    #[cfg_attr(target_os = "linux", link_name = "__errno_location")]
    fn errno_location() -> *mut c_int;
}

/// How many symbols and libraries one program's foreign calls resolve:
/// `os.foreignSlots()` in src/nupp/compiler/vm/nativeos.nupp.
const SLOTS: usize = 1024;

/// Zero until the guest stores what a slot resolved to.
static TABLE: [AtomicU64; SLOTS] = [const { AtomicU64::new(0) }; SLOTS];

/// The loader's entry points, the error number's, then the table.
pub fn imports() -> [u64; 5] {
    [
        dlopen as *const () as u64,
        dlsym as *const () as u64,
        dlclose as *const () as u64,
        errno_location as *const () as u64,
        TABLE.as_ptr() as u64,
    ]
}
