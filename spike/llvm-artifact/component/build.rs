//! Static LLVM (only the components the component uses) and lld's drivers,
//! chosen by feature. `LLVM_SYS_231_PREFIX` names an LLVM build or install
//! tree; its `llvm-config` lists the libraries, unless `NUPP_LLVM_LIBS` does
//! (a cross-built tree whose `llvm-config` cannot run here).

use std::process::Command;

fn main() {
    for f in ["src/glue.cpp", "../../direct-backend/src/glue.cpp"] {
        println!("cargo:rerun-if-changed={f}");
    }
    for v in ["LLVM_SYS_231_PREFIX", "NUPP_LLVM_LIBS", "NUPP_LLVM_INCLUDES", "NUPP_LLD_INCLUDE", "NUPP_LLVM_SYSTEM_LIBS"] {
        println!("cargo:rerun-if-env-changed={v}");
    }
    // The LLVM backend's loading section (ORC) is compiled out: the component
    // never loads what it compiles.
    println!("cargo:rustc-cfg=feature=\"no-jit\"");
    let feature = |f: &str| std::env::var_os(format!("CARGO_FEATURE_{}", f.to_uppercase())).is_some();
    let prefix = std::env::var("LLVM_SYS_231_PREFIX").expect("LLVM_SYS_231_PREFIX");
    let target = std::env::var("TARGET").unwrap();
    let windows = target.contains("windows");
    let drivers: Vec<&str> = ["macho", "elf", "coff", "wasm"].into_iter().filter(|d| feature(d)).collect();
    let mut components = vec!["passes", "aarch64codegen", "x86codegen", "webassemblycodegen", "object"];
    if !drivers.is_empty() {
        components.extend(["lto", "bitwriter", "bitreader", "option", "profiledata", "debuginfodwarf", "aarch64asmparser", "x86asmparser", "webassemblyasmparser"]);
    }
    if feature("macho") {
        components.extend(["textapi", "objcarcopts", "cgdata"]);
    }
    if feature("elf") || feature("coff") {
        components.push("dtlto");
    }
    if feature("coff") {
        components.extend(["debuginfocodeview", "debuginfomsf", "debuginfopdb", "libdriver", "windowsdriver", "windowsmanifest"]);
    }
    let config = format!("{prefix}/bin/llvm-config");
    let run = |args: &[&str]| {
        let out = Command::new(&config).args(args).output().expect("llvm-config");
        assert!(out.status.success(), "llvm-config {args:?}");
        String::from_utf8(out.stdout).unwrap()
    };
    let (libdir, libs, includes) = match std::env::var("NUPP_LLVM_LIBS") {
        Ok(libs) => (format!("{prefix}/lib"), libs, std::env::var("NUPP_LLVM_INCLUDES").unwrap()),
        Err(_) => {
            let mut args = vec!["--link-static", "--libs"];
            args.extend(&components);
            (run(&["--libdir"]).trim().to_string(), run(&args), run(&["--cxxflags"]))
        }
    };
    println!("cargo:rustc-link-search=native={libdir}");
    let mut cpp = cc::Build::new();
    cpp.cpp(true).std("c++17").flag("-fno-exceptions").flag("-fno-rtti").warnings(false);
    for flag in includes.split_whitespace().filter(|f| f.starts_with("-I")) {
        cpp.include(&flag[2..]);
    }
    let lld_include = std::env::var("NUPP_LLD_INCLUDE")
        .unwrap_or_else(|_| format!("{prefix}/../llvm-project-23.1.1.src/lld/include"));
    cpp.include(lld_include);
    for d in &drivers {
        cpp.define(&format!("NUPP_LLD_{}", d.to_uppercase()), None);
    }
    cpp.file("../../direct-backend/src/glue.cpp").file("src/glue.cpp");
    cpp.compile("nupp_llvm_glue");
    // lld's libraries before LLVM's: they depend on it, not the reverse.
    for d in &drivers {
        match *d {
            "macho" => println!("cargo:rustc-link-lib=static=lldMachO"),
            "elf" => println!("cargo:rustc-link-lib=static=lldELF"),
            "coff" => {
                println!("cargo:rustc-link-lib=static=lldMinGW");
                println!("cargo:rustc-link-lib=static=lldCOFF");
            }
            "wasm" => println!("cargo:rustc-link-lib=static=lldWasm"),
            _ => unreachable!(),
        }
    }
    if !drivers.is_empty() {
        println!("cargo:rustc-link-lib=static=lldCommon");
    }
    for lib in libs.split_whitespace() {
        println!("cargo:rustc-link-lib=static={}", lib.trim_start_matches("-l").trim_end_matches(".lib"));
    }
    std::fs::write(std::path::Path::new(&std::env::var("OUT_DIR").unwrap()).join("components.txt"), format!("{}\n{libs}", components.join(" "))).unwrap();
    if windows {
        // MinGW: libstdc++ and the Win32 libraries LLVM Support uses, static.
        let sys = std::env::var("NUPP_LLVM_SYSTEM_LIBS").unwrap_or("psapi shell32 ole32 uuid advapi32 ws2_32 ntdll".into());
        println!("cargo:rustc-link-lib=static=stdc++");
        for l in sys.split_whitespace() {
            println!("cargo:rustc-link-lib={l}");
        }
        println!("cargo:rustc-link-arg=-static");
    } else if target.contains("apple") {
        println!("cargo:rustc-link-lib=c++");
    } else {
        println!("cargo:rustc-link-lib=stdc++");
    }
}
