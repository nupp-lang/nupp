//! Direct OS loading for the frozen VM's surviving callers. No exported ABI.
//! Callers retain this owner for every symbol, returned pointer and extension
//! resource, and drop it only after calls and extension shutdown are quiescent.
use std::ffi::{CStr, OsStr, c_void};

pub(crate) struct Library(*mut c_void);

// OS loader handles may be shared across threads; symbol use remains unsafe.
unsafe impl Send for Library {}
unsafe impl Sync for Library {}

impl Library {
    /// Loading runs library constructors. The caller must trust the image.
    pub(crate) unsafe fn open(path: &OsStr, global: bool) -> Result<Self, String> {
        #[cfg(unix)]
        {
            use std::os::unix::ffi::OsStrExt;
            let path = std::ffi::CString::new(path.as_bytes()).map_err(|e| e.to_string())?;
            let flags = libc::RTLD_NOW
                | if global {
                    libc::RTLD_GLOBAL
                } else {
                    libc::RTLD_LOCAL
                };
            Self::unix_open(path.as_ptr(), flags)
        }
        #[cfg(windows)]
        {
            use std::os::windows::ffi::OsStrExt;
            let path = std::path::Path::new(path);
            // Explicit relative paths refer to the caller's directory. Bare
            // names search only configured default directories, never CWD/PATH.
            let absolute;
            let path = if path.components().count() > 1 && !path.is_absolute() {
                absolute = std::fs::canonicalize(path).map_err(|e| e.to_string())?;
                absolute.as_path()
            } else {
                path
            };
            let mut wide: Vec<u16> = path.as_os_str().encode_wide().collect();
            if wide.contains(&0) {
                return Err("a native library path contains a zero byte".into());
            }
            wide.push(0);
            const LOAD_LIBRARY_SEARCH_DEFAULT_DIRS: u32 = 0x1000;
            const LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR: u32 = 0x100;
            let flags = LOAD_LIBRARY_SEARCH_DEFAULT_DIRS
                | if path.is_absolute() {
                    LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR
                } else {
                    0
                };
            let handle = windows::LoadLibraryExW(wide.as_ptr(), std::ptr::null_mut(), flags);
            let _ = global; // Windows symbols are resolved from explicit modules.
            if handle.is_null() {
                Err(std::io::Error::last_os_error().to_string())
            } else {
                Ok(Self(handle))
            }
        }
        #[cfg(not(any(unix, windows)))]
        {
            let _ = (path, global);
            Err("this platform has no native loader".into())
        }
    }

    pub(crate) unsafe fn this() -> Result<Self, String> {
        #[cfg(unix)]
        {
            Self::unix_open(std::ptr::null(), libc::RTLD_NOW | libc::RTLD_LOCAL)
        }
        #[cfg(windows)]
        {
            let mut handle = std::ptr::null_mut();
            // Take a reference, unlike GetModuleHandleW's borrowed handle.
            if windows::GetModuleHandleExW(0, std::ptr::null(), &mut handle) == 0 {
                Err(std::io::Error::last_os_error().to_string())
            } else {
                Ok(Self(handle))
            }
        }
        #[cfg(not(any(unix, windows)))]
        {
            Err("this platform has no default native namespace".into())
        }
    }

    #[cfg(unix)]
    unsafe fn unix_open(path: *const std::ffi::c_char, flags: i32) -> Result<Self, String> {
        libc::dlerror();
        let handle = libc::dlopen(path, flags);
        if handle.is_null() {
            Err(Self::unix_error().unwrap_or_else(|| "dlopen returned null".into()))
        } else {
            Ok(Self(handle))
        }
    }

    #[cfg(unix)]
    unsafe fn unix_error() -> Option<String> {
        let message = libc::dlerror();
        (!message.is_null()).then(|| CStr::from_ptr(message).to_string_lossy().into_owned())
    }

    /// The address is borrowed from this owner. A null-valued symbol is valid
    /// for dlsym, but none of our callers can use it as code or API data.
    pub(crate) unsafe fn symbol(&self, name: &CStr) -> Result<*mut c_void, String> {
        #[cfg(unix)]
        {
            libc::dlerror();
            let address = libc::dlsym(self.0, name.as_ptr());
            if let Some(error) = Self::unix_error() {
                return Err(error);
            }
            if address.is_null() {
                Err("native symbol has a null address".into())
            } else {
                Ok(address)
            }
        }
        #[cfg(windows)]
        {
            let address = windows::GetProcAddress(self.0, name.as_ptr().cast());
            if address.is_null() {
                Err(std::io::Error::last_os_error().to_string())
            } else {
                Ok(address)
            }
        }
        #[cfg(not(any(unix, windows)))]
        {
            let _ = name;
            Err("this platform has no native loader".into())
        }
    }
}

impl Drop for Library {
    fn drop(&mut self) {
        // Unload only after the last caller-owned handle has been released.
        // Drop cannot report an unload error; never retry a potentially stale handle.
        unsafe {
            #[cfg(unix)]
            {
                libc::dlclose(self.0);
            }
            #[cfg(windows)]
            {
                windows::FreeLibrary(self.0);
            }
        }
    }
}

#[cfg(windows)]
mod windows {
    use std::ffi::c_void;
    #[link(name = "kernel32")]
    unsafe extern "system" {
        pub(super) fn LoadLibraryExW(
            path: *const u16,
            file: *mut c_void,
            flags: u32,
        ) -> *mut c_void;
        pub(super) fn GetModuleHandleExW(
            flags: u32,
            name: *const u16,
            module: *mut *mut c_void,
        ) -> i32;
        pub(super) fn GetProcAddress(module: *mut c_void, name: *const u8) -> *mut c_void;
        pub(super) fn FreeLibrary(module: *mut c_void) -> i32;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[cfg(windows)]
    #[test]
    fn absolute_libraries_load_adjacent_dll_dependencies() {
        use std::path::PathBuf;
        use std::process::Command;

        if let Some(name) = std::env::var_os("NUPP_LOADER_CWD_PROBE") {
            assert!(unsafe { Library::open(&name, false) }.is_err());
            return;
        }
        struct Fixture(PathBuf);
        impl Drop for Fixture {
            fn drop(&mut self) {
                let _ = std::fs::remove_dir_all(&self.0);
            }
        }
        let nonce = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let fixture = Fixture(
            std::env::temp_dir().join(format!("nupp-vm-dll-{}-{nonce}", std::process::id())),
        );
        std::fs::create_dir_all(&fixture.0).unwrap();
        let support = format!("nupp_support_{}_{nonce}", std::process::id());
        std::fs::write(
            fixture.0.join("support.c"),
            "__declspec(dllexport) int support_value(void) { return 73; }\n",
        )
        .unwrap();
        std::fs::write(fixture.0.join("parent.c"), "__declspec(dllimport) int support_value(void);\n__declspec(dllexport) int parent_value(void) { return support_value(); }\n").unwrap();
        let compiler = std::env::var_os("CC").unwrap_or_else(|| "cc".into());
        let output = Command::new(&compiler)
            .current_dir(&fixture.0)
            .args([
                "-shared",
                "support.c",
                "-o",
                &format!("{support}.dll"),
                &format!("-Wl,--out-implib,lib{support}.a"),
            ])
            .output()
            .expect("C compiler required for adjacent DLL fixture");
        assert!(
            output.status.success(),
            "{}",
            String::from_utf8_lossy(&output.stderr)
        );
        let output = Command::new(&compiler)
            .current_dir(&fixture.0)
            .args([
                "-shared",
                "parent.c",
                &format!("lib{support}.a"),
                "-o",
                "parent.dll",
            ])
            .output()
            .unwrap();
        assert!(
            output.status.success(),
            "{}",
            String::from_utf8_lossy(&output.stderr)
        );
        let adjacent = fixture.0.join("moved library \u{e9}");
        std::fs::create_dir(&adjacent).unwrap();
        std::fs::rename(fixture.0.join("parent.dll"), adjacent.join("parent.dll")).unwrap();
        std::fs::rename(
            fixture.0.join(format!("{support}.dll")),
            adjacent.join(format!("{support}.dll")),
        )
        .unwrap();
        // A child changes CWD and PATH without racing other tests' process
        // state. A bare name must not pick up even this valid DLL there.
        let probe = Command::new(std::env::current_exe().unwrap())
            .args([
                "--exact",
                "library::tests::absolute_libraries_load_adjacent_dll_dependencies",
            ])
            .current_dir(&adjacent)
            .env("NUPP_LOADER_CWD_PROBE", format!("{support}.dll"))
            .env(
                "PATH",
                format!(
                    "{};{}",
                    adjacent.display(),
                    std::env::var("PATH").unwrap_or_default()
                ),
            )
            .output()
            .unwrap();
        assert!(
            probe.status.success(),
            "{}",
            String::from_utf8_lossy(&probe.stdout)
        );
        let path = adjacent.join("parent.dll").canonicalize().unwrap();
        assert_ne!(std::env::current_dir().unwrap(), adjacent);
        let library = unsafe { Library::open(path.as_os_str(), false) }.unwrap();
        let address = unsafe { library.symbol(c"parent_value") }.unwrap();
        let value: unsafe extern "C" fn() -> i32 = unsafe { std::mem::transmute(address) };
        assert_eq!(unsafe { value() }, 73);
    }

    #[test]
    fn unicode_path_and_last_owner_unload() {
        let directory =
            std::env::temp_dir().join(format!("nupp-loader-owner-{}", std::process::id()));
        std::fs::create_dir_all(&directory).unwrap();
        struct Fixture(std::path::PathBuf);
        impl Drop for Fixture {
            fn drop(&mut self) {
                let _ = std::fs::remove_dir_all(&self.0);
            }
        }
        let fixture = Fixture(directory);
        let source = fixture.0.join("owner.c");
        std::fs::write(
            &source,
            r#"
static int *state;
#ifdef _WIN32
#include <windows.h>
__declspec(dllexport) void watch(int *p) { state = p; }
BOOL WINAPI DllMain(HINSTANCE h, DWORD reason, LPVOID reserved) {
    if (reason == DLL_PROCESS_DETACH && state) ++*state;
    return TRUE;
}
#else
void watch(int *p) { state = p; }
__attribute__((destructor)) static void unloaded(void) { if (state) ++*state; }
#endif
"#,
        )
        .unwrap();
        let library = fixture.0.join(if cfg!(windows) {
            "owner.dll"
        } else if cfg!(target_os = "macos") {
            "owner.dylib"
        } else {
            "owner.so"
        });
        let compiler = std::env::var_os("CC").unwrap_or_else(|| "cc".into());
        let mut build = std::process::Command::new(&compiler);
        if std::path::Path::new(&compiler)
            .file_stem()
            .and_then(OsStr::to_str)
            == Some("cl")
        {
            build
                .current_dir(&fixture.0)
                .args(["/LD", "/O2"])
                .arg(&source)
                .arg(format!("/Fe:{}", library.display()));
        } else {
            build.arg(if cfg!(target_os = "macos") {
                "-dynamiclib"
            } else {
                "-shared"
            });
            if !cfg!(windows) {
                build.arg("-fPIC");
            }
            build.arg(&source).arg("-o").arg(&library);
        }
        let output = build.output().unwrap();
        assert!(
            output.status.success(),
            "{}",
            String::from_utf8_lossy(&output.stderr)
        );
        let unicode = fixture.0.join("library é 🦋");
        std::fs::create_dir(&unicode).unwrap();
        let moved = unicode.join(library.file_name().unwrap());
        std::fs::rename(&library, &moved).unwrap();
        let mut unloaded = 0;
        unsafe {
            let owner = std::sync::Arc::new(Library::open(moved.as_os_str(), false).unwrap());
            let symbol_owner = owner.clone();
            let watch: unsafe extern "C" fn(*mut i32) =
                std::mem::transmute(owner.symbol(c"watch").unwrap());
            watch(&mut unloaded);
            drop(owner);
            assert_eq!(unloaded, 0);
            // The symbol owner keeps code and its static data alive.
            watch(&mut unloaded);
            drop(symbol_owner);
            assert_eq!(unloaded, 1);
        }
    }

    #[test]
    fn missing_lookup_does_not_poison_the_next_lookup() {
        unsafe {
            #[cfg(unix)]
            let library = Library::this().unwrap();
            #[cfg(windows)]
            let library = Library::open(OsStr::new("kernel32.dll"), false).unwrap();
            assert!(library.symbol(c"nupp_missing_loader_symbol").is_err());
            #[cfg(unix)]
            let name = c"malloc";
            #[cfg(windows)]
            let name = c"GetCurrentProcessId";
            assert!(!library.symbol(name).unwrap().is_null());
            assert!(Library::open(OsStr::new("nupp-missing-library-73921"), false).is_err());
            assert!(!library.symbol(name).unwrap().is_null());
        }
    }
}
