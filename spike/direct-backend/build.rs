//! Links LLVM statically, only the components the LLVM backend uses, and
//! compiles the one piece of C++ glue the C API lacks.

use std::process::Command;

fn main() {
    if std::env::var_os("CARGO_FEATURE_LLVM").is_none() {
        return;
    }
    println!("cargo:rerun-if-env-changed=LLVM_SYS_231_PREFIX");
    println!("cargo:rerun-if-env-changed=NUPP_LLVM_COMPONENTS");
    println!("cargo:rerun-if-changed=src/glue.cpp");
    let prefix = std::env::var("LLVM_SYS_231_PREFIX").expect("LLVM_SYS_231_PREFIX");
    let config = format!("{prefix}/bin/llvm-config");
    let components = std::env::var("NUPP_LLVM_COMPONENTS")
        .unwrap_or_else(|_| "orcjit passes aarch64codegen x86codegen webassemblycodegen".into());
    let run = |args: &[&str]| {
        let out = Command::new(&config).args(args).output().expect("llvm-config");
        assert!(out.status.success(), "llvm-config {args:?}");
        String::from_utf8(out.stdout).unwrap()
    };
    let mut args = vec!["--link-static", "--libs"];
    args.extend(components.split_whitespace());
    println!("cargo:rustc-link-search=native={}", run(&["--libdir"]).trim());
    for lib in run(&args).split_whitespace() {
        println!("cargo:rustc-link-lib=static={}", lib.trim_start_matches("-l"));
    }
    // What this LLVM was configured with (Homebrew's: zlib, zstd); libc++.
    println!("cargo:rustc-link-search=native=/opt/homebrew/lib");
    for lib in run(&["--link-static", "--system-libs"]).split_whitespace() {
        if let Some(name) = lib.strip_prefix("-l").filter(|n| !["xml2", "m"].contains(n)) {
            println!("cargo:rustc-link-lib={name}");
        }
    }
    println!("cargo:rustc-link-lib=c++");
    let mut cpp = cc::Build::new();
    cpp.cpp(true).std("c++17").flag("-fno-exceptions").flag("-fno-rtti").warnings(false);
    // Installed trees have one include directory; build trees also have generated ones.
    for flag in run(&["--cxxflags"]).split_whitespace().filter(|f| f.starts_with("-I")) {
        cpp.include(&flag[2..]);
    }
    cpp.file("src/glue.cpp").compile("nupp_llvm_glue");
}
