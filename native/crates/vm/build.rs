// Builds the tail-call-threaded dispatch core when the C compiler supports
// `musttail` (clang, or a gcc that accepts the attribute); otherwise the crate
// runs its Rust loop and `cfg(threaded)` is unset.
fn main() {
    let mimalloc = std::env::var_os("CARGO_FEATURE_ALLOCATOR_MIMALLOC").is_some();
    let jemalloc = std::env::var_os("CARGO_FEATURE_ALLOCATOR_JEMALLOC").is_some();
    assert!(!(mimalloc && jemalloc), "allocator-mimalloc and allocator-jemalloc are mutually exclusive");
    if mimalloc || jemalloc {
        let arch = std::env::var("CARGO_CFG_TARGET_ARCH").unwrap();
        let os = std::env::var("CARGO_CFG_TARGET_OS").unwrap();
        let env = std::env::var("CARGO_CFG_TARGET_ENV").unwrap();
        assert!(matches!(arch.as_str(), "aarch64" | "x86_64")
            && (os == "macos" || os == "linux" && env == "gnu"),
            "allocator experiments support only aarch64/x86_64 macOS and GNU Linux");
    }
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
        std::fs::write(&generated, "pub const ABI_VERSION: u32 = 4;\npub fn image_hash() -> [u8; 32] { [0; 32] }\npub fn entries() -> Vec<(usize, u64)> { vec![] }\npub fn frame_entries() -> Vec<(usize, u64)> { vec![] }\npub fn maps() -> Vec<(usize, usize, Vec<(u32, u32, Vec<u32>)>)> { vec![] }\n").unwrap();
    }
    println!("cargo:rerun-if-changed=csrc/dispatch.c");
    println!("cargo:rerun-if-env-changed=NUPP_VM_NO_THREADED");
    if std::env::var("NUPP_VM_NO_THREADED").is_ok() { return; }
    let mut build = cc::Build::new();
    build.file("csrc/dispatch.c").opt_level(3).flag("-fno-strict-aliasing").warnings(false);
    // Specialization feedback hooks, only where code is generated at run time.
    if std::env::var_os("CARGO_FEATURE_JIT").is_some() { build.define("NUPP_FEEDBACK", None); }
    let compiler = build.get_compiler();
    if !compiler.is_like_clang() && !compiler.is_like_gnu() { return; }
    // A gcc without musttail fails here; the probe keeps the build going on the Rust loop.
    let probe = std::env::var("OUT_DIR").unwrap() + "/musttail_probe.c";
    std::fs::write(&probe, "int f(int x); int g(int x) { __attribute__((musttail)) return f(x); }\n").unwrap();
    let ok = cc::Build::new().file(&probe).warnings(false).cargo_warnings(false).try_compile("musttail_probe").is_ok();
    if !ok { println!("cargo:warning=C compiler lacks musttail; nupp-vm runs its Rust dispatch loop"); return; }
    // A compiler can take the probe's musttail and still refuse one in the
    // dispatch loop: some Apple clangs fail tail call elimination in the
    // backend. The Rust loop answers the same, only slower.
    if let Err(error) = build.try_compile("nupp_vm_dispatch") {
        println!("cargo:warning=C dispatch loop did not compile ({error}); nupp-vm runs its Rust dispatch loop");
        return;
    }
    println!("cargo:rustc-cfg=threaded");
}
