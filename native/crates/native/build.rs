//! Compiles the AOT runtime (`c/ks_rt.c`) into every provider.
//!
//! The runtime is `ks_lua.h`, the value-stream builder, compiled once here rather
//! than into every module, and reached by LLVM-compiled builder entries through
//! the table `nuppAotRuntime` returns. Every provider carries it, because the
//! one a program is staged with is chosen by the effects its source reaches,
//! and a compiled module's registrar is not source. It calls the Lua C API,
//! which the process loading this crate provides: statically in `nupp`, and
//! through the interpreter when this is the provider library, where it binds
//! at load. It imports none of it: a host that links LuaJIT privately exports
//! no Lua API, and a Windows import has to name a module, so the runtime finds
//! the API in the process itself the first time it is asked for
//! (`ks_rt_bind`), and the provider loads wherever Lua is not exported.

fn main() {
    println!("cargo:rerun-if-changed=c/ks_rt.c");
    println!("cargo:rerun-if-changed=c/ks_prelude.h");
    println!("cargo:rerun-if-changed=c/ks_lua.h");
    println!("cargo::rustc-check-cfg=cfg(nupp_aot_runtime)");
    let target = std::env::var("TARGET").unwrap();
    println!("cargo:rustc-cfg=nupp_aot_runtime");
    let mut build = cc::Build::new();
    build
        .file("c/ks_rt.c")
        .include("c")
        .std("c11")
        .opt_level(2)
        // Lua raises unwind through the runtime's frames.
        .flag_if_supported("-fasynchronous-unwind-tables")
        .flag_if_supported("-Wno-unused-function")
        .warnings(false);
    if target.contains("apple") {
        let floor = if target.starts_with("x86_64") { "10.14" } else { "11.0" };
        build.flag(format!("-mmacosx-version-min={floor}"));
    }
    build.compile("nupp_aot_runtime");
}
