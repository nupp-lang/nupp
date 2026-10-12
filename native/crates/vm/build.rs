// Builds the tail-call-threaded dispatch core when the C compiler supports
// `musttail` (clang, or a gcc that accepts the attribute); otherwise the crate
// runs its Rust loop and `cfg(threaded)` is unset.
fn main() {
    println!("cargo::rustc-check-cfg=cfg(threaded)");
    println!("cargo:rerun-if-env-changed=NUPP_AOT_OBJECT");
    let generated = std::path::PathBuf::from(std::env::var("OUT_DIR").unwrap()).join("aot_entries.rs");
    if let Ok(object) = std::env::var("NUPP_AOT_OBJECT") {
        assert!(std::env::var("CARGO_FEATURE_AOT_LINKED").is_ok(), "NUPP_AOT_OBJECT requires --features aot-linked (or aot)");
        let object = std::fs::canonicalize(object).unwrap();
        let object = object.to_str().unwrap();
        println!("cargo:rerun-if-changed={object}");
        println!("cargo:rerun-if-changed={object}.rs");
        println!("cargo:rerun-if-changed={object}.maps");
        println!("cargo:rustc-link-arg-bin=nupp-vm={object}");
        std::fs::copy(format!("{object}.rs"), &generated).unwrap();
    } else {
        std::fs::write(&generated, "pub fn image_hash() -> [u8; 32] { [0; 32] }\npub fn entries() -> Vec<(usize, u64)> { vec![] }\npub fn maps() -> Vec<(usize, usize, Vec<(u32, u32, Vec<u32>)>)> { vec![] }\n").unwrap();
    }
    println!("cargo:rerun-if-changed=csrc/dispatch.c");
    println!("cargo:rerun-if-env-changed=NUPP_VM_NO_THREADED");
    if std::env::var("NUPP_VM_NO_THREADED").is_ok() { return; }
    let mut build = cc::Build::new();
    build.file("csrc/dispatch.c").opt_level(3).flag("-fno-strict-aliasing").warnings(false);
    let compiler = build.get_compiler();
    if !compiler.is_like_clang() && !compiler.is_like_gnu() { return; }
    // A gcc without musttail fails here; the probe keeps the build going on the Rust loop.
    let probe = std::env::var("OUT_DIR").unwrap() + "/musttail_probe.c";
    std::fs::write(&probe, "int f(int x); int g(int x) { __attribute__((musttail)) return f(x); }\n").unwrap();
    let ok = cc::Build::new().file(&probe).warnings(false).cargo_warnings(false).try_compile("musttail_probe").is_ok();
    if !ok { println!("cargo:warning=C compiler lacks musttail; nupp-vm runs its Rust dispatch loop"); return; }
    build.compile("nupp_vm_dispatch");
    println!("cargo:rustc-cfg=threaded");
}
