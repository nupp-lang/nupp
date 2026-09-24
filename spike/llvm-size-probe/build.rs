//! Static LLVM, only the components each target set needs.

use std::process::Command;

fn main() {
    println!("cargo:rerun-if-changed=../direct-backend/src/glue.cpp");
    println!("cargo:rerun-if-changed=src/lld.cpp");
    println!("cargo:rerun-if-env-changed=LLVM_SYS_231_PREFIX");
    println!("cargo:rerun-if-env-changed=NUPP_LLD_LIBDIR");
    let prefix = std::env::var("LLVM_SYS_231_PREFIX").expect("LLVM_SYS_231_PREFIX");
    let config = format!("{prefix}/bin/llvm-config");
    let feature = |f: &str| std::env::var_os(format!("CARGO_FEATURE_{}", f.to_uppercase())).is_some();
    let mut components = vec!["orcjit", "passes", "aarch64codegen"];
    if feature("x86") {
        components.push("x86codegen");
    }
    if feature("wasm") {
        components.push("webassemblycodegen");
    }
    if feature("lld") {
        components.extend(["lto", "bitwriter", "option", "profiledata", "debuginfodwarf", "aarch64asmparser", "x86asmparser", "webassemblyasmparser"]);
    }
    let run = |args: &[&str]| {
        let out = Command::new(&config).args(args).output().expect("llvm-config");
        assert!(out.status.success(), "llvm-config {args:?}");
        String::from_utf8(out.stdout).unwrap()
    };
    let mut args = vec!["--link-static", "--libs"];
    args.extend(&components);
    let libs = run(&args);
    std::fs::write(std::path::Path::new(&std::env::var("OUT_DIR").unwrap()).join("components.txt"), format!("{}\n{libs}", components.join(" "))).unwrap();
    println!("cargo:rustc-env=NUPP_LLVM_COMPONENTS={}", components.join(" "));
    println!("cargo:rustc-link-search=native={}", run(&["--libdir"]).trim());
    let mut cpp = cc::Build::new();
    cpp.cpp(true).std("c++17").flag("-fno-exceptions").flag("-fno-rtti").warnings(false);
    // Installed trees have one include directory; build trees also have generated ones.
    for flag in run(&["--cxxflags"]).split_whitespace().filter(|f| f.starts_with("-I")) {
        cpp.include(&flag[2..]);
    }
    cpp.file("../direct-backend/src/glue.cpp");
    if feature("lld") {
        let lld = std::fs::canonicalize(std::env::var("NUPP_LLD_LIBDIR").unwrap_or("../../build/lld-src".into())).unwrap();
        cpp.include(std::fs::canonicalize("../../build/lld-src/llvm-project-23.1.1.src/lld/include").unwrap()).file("src/lld.cpp");
        println!("cargo:rustc-link-search=native={}", lld.display());
        println!("cargo:rustc-link-lib=static=lldWasm");
        println!("cargo:rustc-link-lib=static=lldCommon");
    }
    cpp.compile("nupp_llvm_glue");
    for lib in libs.split_whitespace().filter(|l| !l.contains("Polly")) {
        println!("cargo:rustc-link-lib=static={}", lib.trim_start_matches("-l"));
    }
    // Only what this LLVM was configured with (Homebrew's: zlib, zstd, ...).
    println!("cargo:rustc-link-search=native=/opt/homebrew/lib");
    for lib in run(&["--link-static", "--system-libs"]).split_whitespace() {
        if let Some(name) = lib.strip_prefix("-l").filter(|n| !["xml2", "m"].contains(n)) {
            println!("cargo:rustc-link-lib={name}");
        }
    }
    println!("cargo:rustc-link-lib=c++");
}
