//! A C extension fixture built apart from the VM, with the system C compiler
//! against nothing but `include/nupp_extension.h`, into a directory of its own.
//! The embedding and extension tests share it.
use std::path::{Path, PathBuf};
use std::process::Command;

fn temporary(label: &str) -> PathBuf {
    static NEXT: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);
    let sequence = NEXT.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
    let nonce = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_nanos();
    let root = std::env::temp_dir().join(format!("nupp-extension-{label}-{}-{nonce}-{sequence}", std::process::id()));
    std::fs::create_dir_all(root.join("lib")).unwrap();
    root
}

fn library_file(name: &str) -> String {
    if cfg!(target_os = "macos") { format!("lib{name}.dylib") } else { format!("lib{name}.so") }
}

/// `tests/extension/<source>.c`, built into `<root>/lib`.
pub struct Built {
    root: PathBuf,
    pub library: PathBuf,
}
impl Built {
    /// `counter.c`, the `demo.counter` module, as `libcounter`.
    pub fn c(defines: &[&str]) -> Built {
        Built::source("counter", "counter", defines)
    }

    /// `tests/extension/<source>.c` as `lib<name>`, with `defines` set.
    pub fn source(source: &str, name: &str, defines: &[&str]) -> Built {
        let root = temporary(name);
        let library = root.join("lib").join(library_file(name));
        let crate_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
        let mut command = Command::new(std::env::var("CC").unwrap_or_else(|_| "cc".into()));
        command.args(["-std=c11", "-O2", "-Wall", "-Werror"]).arg("-I").arg(crate_dir.join("../../include"));
        if cfg!(target_os = "macos") {
            command.arg("-dynamiclib");
        } else {
            command.args(["-shared", "-fPIC", "-pthread"]);
        }
        for d in defines {
            command.arg(format!("-D{d}"));
        }
        let output = command
            .arg(crate_dir.join("tests/extension").join(format!("{source}.c")))
            .arg("-o")
            .arg(&library)
            .output()
            .expect("an independent C compiler is required for extension acceptance");
        assert!(output.status.success(), "{}", String::from_utf8_lossy(&output.stderr));
        Built { root, library }
    }

    /// How many times the library left the marker `<library>.<suffix>`.
    #[allow(dead_code)]
    pub fn marker(&self, suffix: &str) -> usize {
        let mut path = self.library.clone().into_os_string();
        path.push(format!(".{suffix}"));
        std::fs::read(Path::new(&path)).map(|b| b.len()).unwrap_or(0)
    }
}
impl Drop for Built {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.root);
    }
}
