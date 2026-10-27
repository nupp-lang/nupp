//! Native extensions: `demo.counter` built as a separate shared library, from
//! C against `include/nupp_extension.h` with the system compiler and from Rust
//! with the SDK in its own Cargo target, and loaded when a program requires
//! the module its image declares. The checks run before the library's own
//! code; the library stays loaded while its VM lives; a checkpoint reloads it
//! before restoring its resources. Collector stress with the root oracle and
//! quarantine throughout, on both interpreter loops.
#![cfg(all(feature = "native-ffi", unix))]

use nupp_vm::embed::{Arg, Out, Vm};
use std::path::{Path, PathBuf};
use std::process::Command;

const PROGRAM: &str = include_str!("extension/main.bytecode");
const DECLARATION: &str = include_str!("extension/counter.d.nupp");

fn temporary(label: &str) -> PathBuf {
    static NEXT: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);
    let sequence = NEXT.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
    let nonce = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_nanos();
    let root = std::env::temp_dir().join(format!("nupp-extension-{label}-{}-{nonce}-{sequence}", std::process::id()));
    std::fs::create_dir_all(root.join("lib")).unwrap();
    root
}

fn library_file() -> &'static str {
    if cfg!(target_os = "macos") { "libcounter.dylib" } else { "libcounter.so" }
}

/// `tests/extension/counter.c`, built independently into `<root>/lib`.
struct Built {
    root: PathBuf,
    library: PathBuf,
}
impl Built {
    fn c(defines: &[&str]) -> Built {
        let root = temporary("c");
        let library = root.join("lib").join(library_file());
        let crate_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
        let mut command = Command::new(std::env::var("CC").unwrap_or_else(|_| "cc".into()));
        command.args(["-std=c11", "-O2", "-Wall", "-Werror"]).arg("-I").arg(crate_dir.join("include"));
        if cfg!(target_os = "macos") {
            command.arg("-dynamiclib");
        } else {
            command.args(["-shared", "-fPIC", "-pthread"]);
        }
        for d in defines {
            command.arg(format!("-D{d}"));
        }
        let output = command
            .arg(crate_dir.join("tests/extension/counter.c"))
            .arg("-o")
            .arg(&library)
            .output()
            .expect("an independent C compiler is required for extension acceptance");
        assert!(output.status.success(), "{}", String::from_utf8_lossy(&output.stderr));
        Built { root, library }
    }
    /// The SDK example crate, built by a separate Cargo invocation into its
    /// own target directory: it links the SDK and never the VM.
    fn rust() -> Built {
        let root = temporary("rust");
        let target = PathBuf::from(env!("CARGO_TARGET_TMPDIR")).join("counter-extension");
        let manifest = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../counter-extension/Cargo.toml");
        let output = Command::new(env!("CARGO"))
            .args(["build", "--release", "--offline", "--manifest-path"])
            .arg(&manifest)
            .env("CARGO_TARGET_DIR", &target)
            .output()
            .expect("cargo is required to build the Rust extension");
        assert!(output.status.success(), "{}", String::from_utf8_lossy(&output.stderr));
        let library = root.join("lib").join(library_file());
        // Copied to a fresh name, so this test's library is its alone.
        std::fs::copy(target.join("release").join(library_file()), &library).unwrap();
        Built { root, library }
    }
    fn marker(&self, suffix: &str) -> usize {
        let mut path = self.library.clone().into_os_string();
        path.push(format!(".{suffix}"));
        std::fs::read(Path::new(&path)).map(|b| b.len()).unwrap_or(0)
    }
    /// The program image, declaring `demo.counter` as this library's module.
    fn image(&self) -> String {
        image_naming(self.library.to_str().unwrap(), DECLARATION)
    }
}
impl Drop for Built {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.root);
    }
}

/// The `extension` line an emitter writes: the declaration's bytes, with
/// every byte outside printable ASCII, a quote and a backslash as `\ddd`.
fn image_naming(library: &str, declaration: &str) -> String {
    let declaration = declaration.replace("@extension counter", &format!("@extension {library}"));
    let mut quoted = String::from("\"");
    for b in declaration.bytes() {
        if (32..127).contains(&b) && b != b'"' && b != b'\\' {
            quoted.push(b as char);
        } else {
            quoted.push_str(&format!("\\{b:03}"));
        }
    }
    quoted.push('"');
    format!("{PROGRAM}extension demo.counter {quoted}\n")
}

fn stressed(vm: &mut Vm, threaded: bool) {
    let interp = vm.interp();
    interp.heap.stress_steps = true;
    interp.heap.oracle = true;
    interp.heap.quarantine = true;
    if !threaded {
        interp.threaded = false;
    }
}

fn integer(out: &[Out]) -> i64 {
    out[0].as_integer().unwrap_or_else(|| panic!("expected an integer, got {out:?}"))
}

/// The module's behavior, the same whichever language built it.
fn exercise(vm: &mut Vm) {
    let sum = vm.export("demo.main", "sum").unwrap();
    assert_eq!(integer(&vm.call(&sum, &[Arg::Integer(2), Arg::Integer(3)]).unwrap()), 8);
    assert_eq!(integer(&vm.call(&sum, &[Arg::Integer(9007199254740993), Arg::Integer(1)]).unwrap()), 9007199254740995);
    let error = vm.call(&sum, &[Arg::from("two"), Arg::Integer(3)]).unwrap_err();
    assert!(error.0.contains("argument 1 of demo.counter.add: expected an integer, got a string"), "{error}");
    assert_eq!(integer(&vm.call(&sum, &[Arg::Integer(i64::MAX), Arg::Integer(0)]).unwrap()), i64::MAX);
    let error = vm.call(&sum, &[Arg::Integer(i64::MAX), Arg::Integer(1)]).unwrap_err();
    assert!(error.0.contains("which an integer cannot hold exactly") || error.0.contains("overflows"), "{error}");
    let failing = vm.export("demo.main", "failing").unwrap();
    assert_eq!(vm.call(&failing, &[]).unwrap_err().0, "native failure");

    // Callbacks: lent for the call, and kept past it through a retained handle.
    let apply = vm.export("demo.main", "apply_twice").unwrap();
    assert_eq!(integer(&vm.call(&apply, &[Arg::Integer(5)]).unwrap()), 11);
    let keep = vm.export("demo.main", "keep_twice").unwrap();
    let call_kept = vm.export("demo.main", "call_kept").unwrap();
    let forget = vm.export("demo.main", "forget").unwrap();
    vm.call(&keep, &[]).unwrap();
    for i in 0..20 {
        assert_eq!(integer(&vm.call(&call_kept, &[Arg::Integer(i)]).unwrap()), 2 * i);
    }
    vm.call(&forget, &[]).unwrap();
    assert!(vm.call(&call_kept, &[Arg::Integer(1)]).unwrap_err().0.contains("nothing is kept"));

    // Tasks park on requests the library completes from its own threads.
    let fetch = vm.export("demo.main", "fetch").unwrap();
    let wait = vm.export("demo.main", "fetch_wait").unwrap();
    let tasks: Vec<_> = ["one", "two"].iter().map(|t| vm.spawn(&fetch, &[Arg::from(*t)]).unwrap()).collect();
    assert!(vm.run_ready(8).unwrap().is_empty());
    let results: Vec<_> = tasks.into_iter().map(|t| vm.run(t).unwrap()).collect();
    assert_eq!(results, [vec![Out::String(b"eno".to_vec())], vec![Out::String(b"owt".to_vec())]]);
    let failed = vm.spawn(&wait, &[Arg::from("x"), Arg::Integer(-1)]).unwrap();
    assert_eq!(vm.run(failed).unwrap_err().0, "a negative delay");
    assert!(vm.call(&fetch, &[Arg::from("abc")]).unwrap_err().0.contains("cannot suspend here"));

    // Resources live in the VM; the library owns their data.
    let use_counter = vm.export("demo.main", "use_counter").unwrap();
    let out = vm.call(&use_counter, &[Arg::Integer(10)]).unwrap();
    assert_eq!(out[1].as_integer(), Some(15));
    for root in [sum, failing, apply, keep, call_kept, forget, fetch, wait, use_counter] {
        vm.release(root);
    }
}

#[test]
fn a_c_extension_loads_when_its_module_is_required() {
    let built = Built::c(&[]);
    for threaded in [false, true] {
        let mut vm = Vm::new();
        vm.load_image(&built.image()).unwrap();
        stressed(&mut vm, threaded);
        assert_eq!(built.marker("init"), if threaded { 1 } else { 0 });
        exercise(&mut vm);
        assert!(vm.interp().extensions.has_module("demo.counter"));
    }
    assert_eq!(built.marker("init"), 2);
    assert_eq!(built.marker("shutdown"), 2);
}

#[test]
fn a_rust_extension_built_apart_loads_the_same_way() {
    let built = Built::rust();
    for threaded in [false, true] {
        let mut vm = Vm::new();
        vm.load_image(&built.image()).unwrap();
        stressed(&mut vm, threaded);
        exercise(&mut vm);
    }
}

#[test]
fn a_signature_mismatch_is_refused_before_the_extension_initializes() {
    let built = Built::c(&["COUNTER_NUMBERS"]);
    let mut vm = Vm::new();
    vm.load_image(&built.image()).unwrap();
    let error = vm.require("demo.counter").unwrap_err();
    assert!(
        error.0.contains("demo.counter.add is declared function(integer, integer): integer, but the extension registers function(number, number): number"),
        "{error}"
    );
    assert_eq!(built.marker("init"), 0);
    // The program's own calls see the same refusal.
    let sum = vm.export("demo.main", "sum").unwrap();
    assert!(vm.call(&sum, &[Arg::Integer(1), Arg::Integer(2)]).unwrap_err().0.contains("is declared function(integer, integer): integer"));
    // Each refused load closed the library again, before any of its code ran.
    assert_eq!(built.marker("unloaded"), 2);
    assert_eq!(built.marker("init"), 0);
    drop(vm);

    // A library that is not an extension, or is missing, says which.
    let mut vm = Vm::new();
    vm.load_image(&image_naming("/nonexistent/libcounter.dylib", DECLARATION)).unwrap();
    assert!(vm.require("demo.counter").unwrap_err().0.contains("cannot load native extension"));
    let complete = Built::c(&[]);
    let mut vm = Vm::new();
    vm.load_image(&image_naming(complete.library.to_str().unwrap(), &DECLARATION.replace("fail: function(message: string)", "fail: function(message: string)\n    reset: function()")))
        .unwrap();
    let error = vm.require("demo.counter").unwrap_err();
    assert!(error.0.contains("demo.counter declares reset, which the extension does not register"), "{error}");
}

#[test]
fn the_library_stays_loaded_while_its_vm_lives() {
    let built = Built::c(&[]);
    let mut vm = Vm::new();
    vm.load_image(&built.image()).unwrap();
    stressed(&mut vm, true);
    let sum = vm.export("demo.main", "sum").unwrap();
    assert_eq!(integer(&vm.call(&sum, &[Arg::Integer(1), Arg::Integer(1)]).unwrap()), 3);
    let use_counter = vm.export("demo.main", "use_counter").unwrap();
    let counter = vm.call(&use_counter, &[Arg::Integer(1)]).unwrap();
    vm.release(sum);
    vm.release(use_counter);
    drop(counter);
    // Nothing the program holds names the library now, but its functions are
    // values any table may still hold: it stays until the VM ends.
    let collect = vm.export("demo.main", "sum").unwrap();
    for _ in 0..10 {
        vm.call(&collect, &[Arg::Integer(1), Arg::Integer(1)]).unwrap();
    }
    assert_eq!(built.marker("unloaded"), 0);
    assert_eq!(built.marker("shutdown"), 0);
    assert_eq!(vm.interp().extensions.resource_count(), 1);
    drop(vm);
    // Its resources were dropped, then the module shut down, then unloaded.
    assert_eq!(built.marker("shutdown"), 1);
    assert_eq!(built.marker("unloaded"), 1);
}

#[test]
fn a_checkpoint_reloads_the_library_before_restoring_its_resources() {
    let built = Built::c(&[]);
    for threaded in [false, true] {
        let mut vm = Vm::new();
        vm.load_image(&built.image()).unwrap();
        stressed(&mut vm, threaded);
        let use_counter = vm.export("demo.main", "use_counter").unwrap();
        let remember = vm.export("demo.main", "remember").unwrap();
        let out = vm.call(&use_counter, &[Arg::Integer(10)]).unwrap();
        let Out::Root(counter) = &out[0] else { panic!("a counter is a resource object") };
        vm.call(&remember, &[Arg::Root(counter)]).unwrap();
        let saved = vm.checkpoint().unwrap();
        drop(out);
        drop(vm);
        let unloaded = built.marker("unloaded");

        let mut restored = Vm::restore(&saved, vec![]).unwrap();
        stressed(&mut restored, threaded);
        assert!(restored.interp().extensions.has_module("demo.counter"));
        let recall = restored.export("demo.main", "recall").unwrap();
        let bump = restored.export("demo.main", "bump").unwrap();
        let counter = restored.call(&recall, &[]).unwrap().remove(0);
        let Out::Root(counter) = counter else { panic!("the counter did not survive") };
        assert_eq!(integer(&restored.call(&bump, &[Arg::Root(&counter), Arg::Integer(1)]).unwrap()), 16);
        let sum = restored.export("demo.main", "sum").unwrap();
        assert_eq!(integer(&restored.call(&sum, &[Arg::Integer(2), Arg::Integer(2)]).unwrap()), 6);
        drop(restored);
        assert_eq!(built.marker("unloaded"), unloaded + 1);
    }
}
