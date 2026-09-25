//! Links the pinned LLVM and lld statically when the `llvm` feature is on.
//!
//! NUPP_LLVM_PREFIX names the build tree `scripts/toolchain llvm` produced. Its
//! `llvm-config` lists the component libraries; NUPP_LLVM_LIBS lists them
//! instead for a cross-built tree whose `llvm-config` cannot run here.

use std::process::Command;

const COMPONENTS: &[&str] = &[
    "passes", "irreader", "object", "option", "lto", "bitwriter", "bitreader", "profiledata",
    "debuginfodwarf", "textapi", "objcarcopts", "cgdata", "dtlto", "debuginfocodeview",
    "debuginfomsf", "debuginfopdb", "libdriver", "windowsdriver", "windowsmanifest",
    "aarch64codegen", "aarch64asmparser", "aarch64disassembler", "x86codegen", "x86asmparser",
    "x86disassembler", "webassemblycodegen", "webassemblyasmparser", "webassemblydisassembler",
    "mcdisassembler",
];

fn main() {
    println!("cargo::rustc-check-cfg=cfg(nupp_llvm)");
    for variable in ["NUPP_LLVM_PREFIX", "NUPP_LLVM_LIBS", "NUPP_LLVM_INCLUDES", "NUPP_LLVM_SYSTEM_LIBS", "NUPP_LLD_INCLUDE"] {
        println!("cargo:rerun-if-env-changed={variable}");
    }
    println!("cargo:rerun-if-changed=src/glue.cpp");
    if std::env::var_os("CARGO_FEATURE_LLVM").is_none() {
        return;
    }
    println!("cargo:rustc-cfg=nupp_llvm");
    let prefix = std::env::var("NUPP_LLVM_PREFIX")
        .expect("the codegen crate's `llvm` feature needs NUPP_LLVM_PREFIX (scripts/toolchain llvm)");
    let target = std::env::var("TARGET").unwrap();
    let config = format!("{prefix}/bin/llvm-config");
    let run = |args: &[&str]| {
        let out = Command::new(&config).args(args).output().expect("llvm-config");
        assert!(out.status.success(), "llvm-config {args:?} failed");
        String::from_utf8(out.stdout).unwrap()
    };
    let (libdir, libs, includes, system) = match std::env::var("NUPP_LLVM_LIBS") {
        Ok(libs) => (
            format!("{prefix}/lib"),
            libs,
            std::env::var("NUPP_LLVM_INCLUDES").expect("NUPP_LLVM_INCLUDES with NUPP_LLVM_LIBS"),
            std::env::var("NUPP_LLVM_SYSTEM_LIBS").unwrap_or_default(),
        ),
        Err(_) => {
            let mut args = vec!["--link-static", "--libs"];
            args.extend(COMPONENTS);
            // lld's headers sit beside LLVM's in the source tree, which the
            // build tree's --cxxflags names as <source>/llvm/include.
            let cxxflags = run(&["--cxxflags"]);
            let lld = std::env::var("NUPP_LLD_INCLUDE").ok().or_else(|| {
                cxxflags
                    .split_whitespace()
                    .filter_map(|f| f.strip_prefix("-I"))
                    .find_map(|dir| dir.strip_suffix("/llvm/include").map(|root| format!("{root}/lld/include")))
            });
            let lld = lld.expect("cannot find lld's headers; name them with NUPP_LLD_INCLUDE");
            (
                run(&["--libdir"]).trim().to_string(),
                run(&args),
                format!("{cxxflags} -I{lld}"),
                run(&["--link-static", "--system-libs"]),
            )
        }
    };
    let mut cpp = cc::Build::new();
    cpp.cpp(true).std("c++17").flag_if_supported("-fno-exceptions").flag_if_supported("-fno-rtti").warnings(false);
    for flag in includes.split_whitespace().filter(|f| f.starts_with("-I")) {
        cpp.include(&flag[2..]);
    }
    if target.contains("apple") {
        let floor = if target.starts_with("x86_64") { "10.14" } else { "11.0" };
        cpp.flag(format!("-mmacosx-version-min={floor}"));
    }
    cpp.file("src/glue.cpp").compile("nupp_codegen_glue");
    println!("cargo:rustc-link-search=native={libdir}");
    // lld's libraries before LLVM's: they depend on it, not the reverse.
    for lib in ["lldMinGW", "lldCOFF", "lldELF", "lldMachO", "lldWasm", "lldCommon"] {
        println!("cargo:rustc-link-lib=static={lib}");
    }
    for lib in libs.split_whitespace() {
        println!("cargo:rustc-link-lib=static={}", lib.trim_start_matches("-l").trim_end_matches(".lib"));
    }
    for lib in system.split_whitespace() {
        let name = lib.trim_start_matches("-l").trim_end_matches(".lib");
        if !name.is_empty() && !["m"].contains(&name) {
            println!("cargo:rustc-link-lib={name}");
        }
    }
    if target.contains("apple") {
        println!("cargo:rustc-link-lib=c++");
    } else if target.contains("windows") {
        // MinGW's static libstdc++ sits in the compiler's own library
        // directory, which rustc does not search.
        let compiler = cpp.get_compiler();
        if let Ok(answer) = std::process::Command::new(compiler.path()).arg("-print-file-name=libstdc++.a").output() {
            let found = std::path::PathBuf::from(String::from_utf8_lossy(&answer.stdout).trim());
            if let Some(dir) = found.parent().filter(|_| found.is_absolute()) {
                println!("cargo:rustc-link-search=native={}", dir.display());
            }
        }
        println!("cargo:rustc-link-lib=static=stdc++");
    } else {
        println!("cargo:rustc-link-lib=stdc++");
    }
}
