//! Compiles the AOT runtime (`c/ks_rt.c`) when the `aotrt` feature is on.
//!
//! The runtime is the C lowering's own `ks_lua.h`, compiled once here rather
//! than into every module, and reached by LLVM-compiled builder entries through
//! the table `nuppAotRuntime` returns. It calls the Lua C API, which the
//! process loading this crate provides: statically in `nupp`, and through the
//! interpreter when this is the provider library, where it binds at load.

fn main() {
    println!("cargo:rerun-if-changed=c/ks_rt.c");
    println!("cargo:rerun-if-changed=../../../src/nupp/compiler/aot/include/ks_prelude.h");
    println!("cargo:rerun-if-changed=../../../src/nupp/compiler/aot/include/ks_lua.h");
    if std::env::var_os("CARGO_FEATURE_AOTRT").is_none() {
        return;
    }
    let target = std::env::var("TARGET").unwrap();
    let mut build = cc::Build::new();
    build
        .file("c/ks_rt.c")
        .include("../../../src/nupp/compiler/aot/include")
        .std("c11")
        .opt_level(2)
        // Lua raises unwind through the runtime's frames.
        .flag_if_supported("-fasynchronous-unwind-tables")
        .flag_if_supported("-Wno-unused-function")
        .warnings(false);
    if target.contains("apple") {
        let floor = if target.starts_with("x86_64") { "10.14" } else { "11.0" };
        build.flag(format!("-mmacosx-version-min={floor}"));
        // The provider library leaves the Lua API to the loading process.
        println!("cargo:rustc-cdylib-link-arg=-Wl,-undefined,dynamic_lookup");
    }
    build.compile("nupp_aot_runtime");
}
