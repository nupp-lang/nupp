//! The dynamic loader for the guest's foreign calls, as the C library has
//! it: `dlopen`, `dlsym` and `dlclose`, with artifact-relative `@` paths
//! anchored before opening. Nupp resolves
//! each foreign symbol once and caches it in the table this passes beside
//! them; what to load and when is Nupp's, and it reads `errno` through a
//! foreign call of its own.
use std::cell::RefCell;
use std::ffi::{CStr, CString, c_char, c_int, c_void};
use std::marker::PhantomData;
use std::os::unix::ffi::OsStrExt;
use std::path::{Path, PathBuf};
use std::rc::Rc;
use std::sync::atomic::AtomicU64;

unsafe extern "C" {
    fn dlopen(path: *const c_char, mode: c_int) -> *mut c_void;
    fn dlsym(handle: *mut c_void, name: *const c_char) -> *mut c_void;
    fn dlclose(handle: *mut c_void) -> c_int;
}

/// How many symbols and libraries one program's foreign calls resolve:
/// `os.foreignSlots()` in src/nupp/compiler/vm/nativeos.nupp.
const SLOTS: usize = 1024;

/// Zero until the guest stores what a slot resolved to.
static TABLE: [AtomicU64; SLOTS] = [const { AtomicU64::new(0) }; SLOTS];

thread_local! {
    static ARTIFACT_DIRECTORY: RefCell<Option<PathBuf>> = const { RefCell::new(None) };
}

/// Keeps the currently executing artifact's directory available to its loader.
/// The bridge executes guest code on this thread; pool workers run OS jobs only.
pub struct ArtifactOrigin {
    previous: Option<PathBuf>,
    thread: PhantomData<Rc<()>>,
}

pub fn for_artifact(bundle: &Path) -> Result<ArtifactOrigin, String> {
    let path = bundle
        .canonicalize()
        .map_err(|error| format!("bundle: {error}"))?;
    let directory = path
        .parent()
        .ok_or("bundle has no parent directory")?
        .to_path_buf();
    let previous = ARTIFACT_DIRECTORY.with(|current| current.replace(Some(directory)));
    Ok(ArtifactOrigin {
        previous,
        thread: PhantomData,
    })
}

impl Drop for ArtifactOrigin {
    fn drop(&mut self) {
        ARTIFACT_DIRECTORY.with(|current| current.replace(self.previous.take()));
    }
}

unsafe extern "C" fn open(path: *const c_char, mode: c_int) -> *mut c_void {
    if path.is_null() {
        return unsafe { dlopen(path, mode) };
    }
    // The import has dlopen's contract: a non-null path names a C string.
    let name = unsafe { CStr::from_ptr(path) }.to_bytes();
    let anchored = name.strip_prefix(b"@").and_then(|relative| {
        ARTIFACT_DIRECTORY.with(|current| {
            current.borrow().as_ref().map(|directory| {
                // A leading slash after `@` still names the artifact's directory,
                // as it does for the generated Lua loader's string concatenation.
                let mut relative = relative;
                while let Some(rest) = relative.strip_prefix(b"/") {
                    relative = rest;
                }
                let path = directory.join(std::ffi::OsStr::from_bytes(relative));
                CString::new(path.as_os_str().as_bytes()).expect("library path has no zero byte")
            })
        })
    });
    unsafe { dlopen(anchored.as_ref().map_or(path, |name| name.as_ptr()), mode) }
}

/// The loader's entry points, then the table.
pub fn imports() -> [u64; 4] {
    [
        open as *const () as u64,
        dlsym as *const () as u64,
        dlclose as *const () as u64,
        TABLE.as_ptr() as u64,
    ]
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::process::Command;

    unsafe extern "C" {
        fn dlerror() -> *const c_char;
    }

    struct Fixture(PathBuf);

    impl Fixture {
        fn new() -> Self {
            let nonce = std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos();
            let root = std::env::temp_dir()
                .join(format!("nupp-core-library-{}-{nonce}", std::process::id()));
            std::fs::create_dir_all(root.join("original/lib")).unwrap();
            std::fs::create_dir(root.join("elsewhere")).unwrap();
            std::fs::write(root.join("original/program.core"), []).unwrap();
            std::fs::write(
                root.join("fixture.c"),
                "int anchor_value(void) { return 73; }\n",
            )
            .unwrap();
            let mut command = Command::new(std::env::var_os("CC").unwrap_or_else(|| "cc".into()));
            if cfg!(target_os = "macos") {
                command.arg("-dynamiclib");
            } else {
                command.args(["-shared", "-fPIC"]);
            }
            let output = command
                .arg(root.join("fixture.c"))
                .arg("-o")
                .arg(root.join("original/lib").join(filename()))
                .output()
                .expect("independent C compiler required for loader fixture");
            assert!(
                output.status.success(),
                "{}",
                String::from_utf8_lossy(&output.stderr)
            );
            std::fs::rename(root.join("original"), root.join("moved")).unwrap();
            Self(root)
        }
    }

    impl Drop for Fixture {
        fn drop(&mut self) {
            let _ = std::fs::remove_dir_all(&self.0);
        }
    }

    fn filename() -> &'static str {
        if cfg!(target_os = "macos") {
            "libanchor.dylib"
        } else {
            "libanchor.so"
        }
    }

    fn loader_error() -> String {
        let error = unsafe { dlerror() };
        assert!(!error.is_null(), "the platform loader reports the failure");
        unsafe { CStr::from_ptr(error) }
            .to_string_lossy()
            .into_owned()
    }

    #[test]
    fn loads_moved_artifact_libraries_from_an_unrelated_working_directory() {
        const CHILD: &str = "NUPP_CORE_LIBRARY_ANCHOR_FIXTURE";
        let Some(bundle) = std::env::var_os(CHILD) else {
            let fixture = Fixture::new();
            let output = Command::new(std::env::current_exe().unwrap())
                .args(["--exact", "library::tests::loads_moved_artifact_libraries_from_an_unrelated_working_directory"])
                .env(CHILD, fixture.0.join("moved/program.core"))
                .current_dir(fixture.0.join("elsewhere"))
                .output().unwrap();
            assert!(
                output.status.success(),
                "{}\n{}",
                String::from_utf8_lossy(&output.stdout),
                String::from_utf8_lossy(&output.stderr)
            );
            return;
        };

        let bundle = PathBuf::from(bundle).canonicalize().unwrap();
        let directory = bundle.parent().unwrap();
        assert_ne!(std::env::current_dir().unwrap(), directory);
        assert_ne!(
            std::env::current_exe().unwrap().parent().unwrap(),
            directory
        );
        let origin = for_artifact(&bundle).unwrap();
        let entries = imports();
        let load: unsafe extern "C" fn(*const c_char, c_int) -> *mut c_void =
            unsafe { std::mem::transmute(entries[0]) };
        let symbol: unsafe extern "C" fn(*mut c_void, *const c_char) -> *mut c_void =
            unsafe { std::mem::transmute(entries[1]) };
        let relative = CString::new(format!("@lib/{}", filename())).unwrap();
        let library = unsafe { load(relative.as_ptr(), 2) };
        assert!(!library.is_null(), "{}", loader_error());
        let address = unsafe { symbol(library, c"anchor_value".as_ptr()) };
        assert!(!address.is_null(), "{}", loader_error());
        let value: unsafe extern "C" fn() -> c_int = unsafe { std::mem::transmute(address) };
        assert_eq!(unsafe { value() }, 73);

        let absolute = CString::new(
            directory
                .join("lib")
                .join(filename())
                .as_os_str()
                .as_bytes(),
        )
        .unwrap();
        assert_eq!(
            unsafe { load(absolute.as_ptr(), 2) },
            library,
            "ordinary paths pass through"
        );
        let program = unsafe { load(std::ptr::null(), 2) };
        assert!(!program.is_null(), "the default namespace still loads");
        assert!(!unsafe { symbol(program, c"puts".as_ptr()) }.is_null());

        let missing = unsafe { load(c"@lib/not-present".as_ptr(), 2) };
        assert!(missing.is_null());
        let detail = loader_error();
        assert!(detail.contains(directory.to_str().unwrap()), "{detail}");
        assert!(detail.contains("not-present"), "{detail}");
        assert!(unsafe { symbol(library, c"anchor_missing".as_ptr()) }.is_null());
        assert!(loader_error().contains("anchor_missing"));

        drop(origin);
        assert_eq!(
            unsafe { value() },
            73,
            "leaving the artifact does not unload its library"
        );
    }

    #[test]
    fn artifact_origins_restore_the_enclosing_execution() {
        let first = for_artifact(Path::new(file!())).unwrap();
        let directory = ARTIFACT_DIRECTORY.with(|current| current.borrow().clone());
        {
            let _second = for_artifact(Path::new("Cargo.toml")).unwrap();
            assert_ne!(
                ARTIFACT_DIRECTORY.with(|current| current.borrow().clone()),
                directory
            );
        }
        assert_eq!(
            ARTIFACT_DIRECTORY.with(|current| current.borrow().clone()),
            directory
        );
        drop(first);
        assert!(ARTIFACT_DIRECTORY.with(|current| current.borrow().is_none()));
    }
}
