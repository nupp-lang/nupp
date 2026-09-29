//! The shared asynchronous executor native providers run their Lua-free work
//! on, and the one readiness generation they all advance.

pub mod activity;

#[cfg(feature = "async")]
use std::sync::OnceLock;
#[cfg(feature = "async")]
use tokio::runtime::{Builder, Runtime};

#[cfg(feature = "async")]
fn pin_anchor() {}

/// Keeps the image containing the shared executor loaded for the remainder of
/// the process.
///
/// LuaJIT owns `ffi.load` handles through garbage-collected values. A Lua state
/// may therefore release its handle while another state, or a Tokio worker,
/// still has native work in flight. Retaining the image at the operating-system
/// loader prevents those threads from returning into unmapped Rust code.
#[cfg(feature = "async")]
fn pin_current_image() -> Result<(), &'static str> {
    static PINNED: OnceLock<Result<(), String>> = OnceLock::new();
    match PINNED.get_or_init(platform_pin_current_image) {
        Ok(()) => Ok(()),
        Err(error) => Err(error.as_str()),
    }
}

#[cfg(all(feature = "async", unix))]
fn platform_pin_current_image() -> Result<(), String> {
    use std::ffi::{CStr, c_char, c_int, c_void};
    use std::mem::MaybeUninit;
    use std::os::unix::ffi::OsStrExt;
    use std::path::Path;

    #[repr(C)]
    struct DlInfo {
        filename: *const c_char,
        base: *mut c_void,
        symbol_name: *const c_char,
        symbol_address: *mut c_void,
    }

    #[cfg_attr(not(target_vendor = "apple"), link(name = "dl"))]
    unsafe extern "C" {
        fn dladdr(address: *const c_void, info: *mut DlInfo) -> c_int;
        fn dlopen(filename: *const c_char, flags: c_int) -> *mut c_void;
        fn dlerror() -> *const c_char;
    }

    const RTLD_NOW: c_int = 2;

    let mut info = MaybeUninit::<DlInfo>::uninit();
    // SAFETY: `pin_anchor` is a live address in the current image and `info`
    // points to writable storage for the loader's fixed-layout result.
    if unsafe { dladdr(pin_anchor as *const () as *const c_void, info.as_mut_ptr()) } == 0 {
        return Err("cannot identify the loaded Rust native library".to_owned());
    }
    // SAFETY: a successful `dladdr` initialized the record.
    let info = unsafe { info.assume_init() };
    if info.filename.is_null() {
        return Err("the loaded Rust native library has no loader path".to_owned());
    }

    // Code linked directly into the process executable cannot be unloaded and
    // needs no extra loader reference. This also lets crate tests exercise the
    // same initialization path without trying to dlopen their PIE executable.
    // SAFETY: `dladdr` returns a NUL-terminated path owned by the loader.
    let filename = unsafe { CStr::from_ptr(info.filename) };
    let image_path = Path::new(std::ffi::OsStr::from_bytes(filename.to_bytes()));
    if let Ok(executable) = std::env::current_exe() {
        let same_canonical_image = match (image_path.canonicalize(), executable.canonicalize()) {
            (Ok(image), Ok(executable)) => image == executable,
            _ => false,
        };
        let same_image = image_path == executable || same_canonical_image;
        if same_image {
            return Ok(());
        }
    }

    // `dlopen` increments the image's loader reference count. The returned
    // reference is intentionally never paired with `dlclose`: losing the
    // opaque value does not release it, so this is a process-lifetime pin.
    // SAFETY: `filename` remains valid for the call and names the image that
    // contains `pin_anchor`.
    let retained = unsafe { dlopen(info.filename, RTLD_NOW) };
    if retained.is_null() {
        // SAFETY: `dlerror` returns either null or a loader-owned C string.
        let detail = unsafe {
            let error = dlerror();
            if error.is_null() {
                "unknown loader error".to_owned()
            } else {
                CStr::from_ptr(error).to_string_lossy().into_owned()
            }
        };
        return Err(format!("cannot pin the Rust native library: {detail}"));
    }
    Ok(())
}

#[cfg(all(feature = "async", windows))]
fn platform_pin_current_image() -> Result<(), String> {
    use std::ffi::c_void;
    use std::ptr;

    type Module = *mut c_void;

    #[link(name = "kernel32")]
    unsafe extern "system" {
        fn GetModuleHandleExW(flags: u32, name: *const u16, module: *mut Module) -> i32;
    }

    const FROM_ADDRESS: u32 = 0x0000_0004;
    const PIN: u32 = 0x0000_0001;

    let mut module: Module = ptr::null_mut();
    // With FROM_ADDRESS, Windows interprets `name` as an address in the module
    // rather than as UTF-16. PIN makes that module non-unloadable until process
    // termination and does not require keeping the returned handle alive.
    // SAFETY: `pin_anchor` is a live address and `module` is writable output.
    let pinned = unsafe {
        GetModuleHandleExW(
            FROM_ADDRESS | PIN,
            pin_anchor as *const () as *const u16,
            &mut module,
        )
    };
    if pinned == 0 || module.is_null() {
        return Err(format!(
            "cannot pin the Rust native library: Windows error {}",
            std::io::Error::last_os_error()
        ));
    }
    Ok(())
}

#[cfg(all(feature = "async", not(any(unix, windows))))]
fn platform_pin_current_image() -> Result<(), String> {
    Err("the Rust native executor cannot pin its library on this platform".to_owned())
}

/// The process-wide executor used by asynchronous native providers.
///
/// Provider tasks may operate only on Rust-owned state and report readiness to
/// their owning lane. They never enter Lua from an executor thread.
#[cfg(feature = "async")]
pub fn executor() -> Result<&'static Runtime, &'static str> {
    static EXECUTOR: OnceLock<Result<Runtime, String>> = OnceLock::new();
    match EXECUTOR.get_or_init(|| {
        pin_current_image().map_err(str::to_owned)?;
        let workers = std::env::var("NUPP_NATIVE_WORKERS")
            .ok()
            .and_then(|value| value.parse::<usize>().ok())
            .filter(|value| *value > 0)
            .unwrap_or_else(|| {
                std::thread::available_parallelism()
                    .map(usize::from)
                    .unwrap_or(2)
                    .clamp(2, 8)
            });
        Builder::new_multi_thread()
            .worker_threads(workers)
            .enable_all()
            .thread_name("nupp-native")
            .build()
            .map_err(|error| error.to_string())
    }) {
        Ok(runtime) => Ok(runtime),
        Err(error) => Err(error.as_str()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[cfg(feature = "async")]
    use std::time::Duration;

    #[cfg(feature = "async")]
    #[test]
    fn executor_initialization_pins_its_image_once() {
        pin_current_image().expect("pin the image containing the executor");
        pin_current_image().expect("repeat the process-lifetime pin");
        let first = executor().expect("create the shared executor");
        let second = executor().expect("reuse the shared executor");
        assert!(std::ptr::eq(first, second));
    }

    #[cfg(feature = "async")]
    #[test]
    fn executor_carries_a_tokio_io_driver() {
        executor()
            .expect("create the shared executor")
            .block_on(async {
                // The connection may be refused or prohibited by a test
                // sandbox. Constructing and polling it is the assertion: a
                // Tokio runtime without an I/O driver panics before it can
                // report either operating-system result.
                let _ = tokio::time::timeout(
                    Duration::from_millis(100),
                    tokio::net::TcpStream::connect(("127.0.0.1", 1)),
                )
                .await;
            });
    }
}
