//! The LLVM artifact component: everything that needs LLVM, in an executable
//! of its own that the host starts only on an AOT cache miss.
//!
//! `nupp-llvm compile` lowers the IR of the five `simd11` kernels, `waves` and
//! the three Lua builders into one LLVM module, optimizes it at
//! `default<O3>`, generates one object, and links it with lld (in process)
//! into a shared library: a `.dylib`, `.so` or `.dll` for the target. That
//! directory is the cache entry; it appears under its key by one rename.
//!
//! `nupp-llvm exe` links a cached object with the runtime's prebuilt objects
//! into a standalone executable, again with the bundled lld only.
#![allow(dead_code)]

#[path = "../../../direct-backend/src/lir.rs"]
mod lir;
#[path = "../../../direct-backend/src/llvm.rs"]
mod llvm;
#[path = "../../../direct-backend/src/sem.rs"]
mod sem;

use llvm::{Level, Shape, Tier};
use serde_json::Value as J;
use std::ffi::{CString, c_char};
use std::path::{Path, PathBuf};
use std::time::Instant;

unsafe extern "C" {
    fn nupp_lld(argc: i32, argv: *const *const c_char) -> i32;
    fn nupp_import_library(dll: *const c_char, path: *const c_char, names: *const *const c_char, n: i32) -> i32;
}

const KERNELS: &[&str] = &["map", "refine", "explicitMap", "explicitRefine", "explicitAlgebraic"];
const BUILDERS: &[&str] = &["rows", "object", "stream"];

/// A clock every process on the machine shares, so the host can place the
/// component's phases on its own timeline.
pub fn now_ns() -> u64 {
    #[cfg(target_os = "macos")]
    unsafe {
        unsafe extern "C" {
            fn clock_gettime_nsec_np(clock: u32) -> u64;
        }
        clock_gettime_nsec_np(8) // CLOCK_UPTIME_RAW
    }
    #[cfg(target_os = "linux")]
    unsafe {
        #[repr(C)]
        struct Ts {
            s: i64,
            ns: i64,
        }
        unsafe extern "C" {
            fn clock_gettime(clock: i32, ts: *mut Ts) -> i32;
        }
        let mut t = Ts { s: 0, ns: 0 };
        clock_gettime(1, &mut t); // CLOCK_MONOTONIC
        t.s as u64 * 1_000_000_000 + t.ns as u64
    }
    #[cfg(windows)]
    unsafe {
        unsafe extern "system" {
            fn QueryPerformanceCounter(c: *mut i64) -> i32;
            fn QueryPerformanceFrequency(f: *mut i64) -> i32;
        }
        let (mut c, mut f) = (0i64, 0i64);
        QueryPerformanceCounter(&mut c);
        QueryPerformanceFrequency(&mut f);
        (c as i128 * 1_000_000_000 / f as i128) as u64
    }
}

fn us(t: Instant) -> f64 {
    t.elapsed().as_secs_f64() * 1e6
}

fn lld(args: &[String]) -> Result<(), String> {
    let cargs: Vec<CString> = args.iter().map(|a| CString::new(a.as_str()).unwrap()).collect();
    let ptrs: Vec<*const c_char> = cargs.iter().map(|a| a.as_ptr()).collect();
    match unsafe { nupp_lld(ptrs.len() as i32, ptrs.as_ptr()) } {
        0 => Ok(()),
        code => Err(format!("lld exited {code}: {}", args.join(" "))),
    }
}

struct Args {
    rest: Vec<String>,
}

impl Args {
    fn value(&self, flag: &str) -> Option<String> {
        self.rest.iter().position(|a| a == flag).map(|i| self.rest[i + 1].clone())
    }
    fn values(&self, flag: &str) -> Vec<String> {
        self.rest.iter().enumerate().filter(|(_, a)| *a == flag).map(|(i, _)| self.rest[i + 1].clone()).collect()
    }
    fn has(&self, flag: &str) -> bool {
        self.rest.iter().any(|a| a == flag)
    }
    fn need(&self, flag: &str) -> String {
        self.value(flag).unwrap_or_else(|| panic!("missing {flag}"))
    }
}

#[derive(Clone, Copy, PartialEq)]
enum Os {
    MacOS,
    Linux,
    Windows,
}

fn os_of(triple: &str) -> Os {
    if triple.contains("apple") {
        Os::MacOS
    } else if triple.contains("windows") || triple.contains("mingw") {
        Os::Windows
    } else {
        Os::Linux
    }
}

fn library_name(os: Os) -> &'static str {
    match os {
        Os::MacOS => "module.dylib",
        Os::Linux => "module.so",
        Os::Windows => "module.dll",
    }
}

fn main() {
    let entered = now_ns();
    let mut argv: Vec<String> = std::env::args().collect();
    let mode = argv.get(1).cloned().unwrap_or_default();
    let args = Args { rest: argv.split_off(2.min(argv.len())) };
    match mode.as_str() {
        "compile" => compile(&args, entered),
        "exe" => exe(&args),
        "version" => println!("nupp-llvm llvm-23.1.1 {}", env!("CARGO_PKG_VERSION")),
        _ => {
            eprintln!("usage: nupp-llvm compile|exe|version ...");
            std::process::exit(2);
        }
    }
}

/// Fast-math licences in the optimized IR, and fused multiply-adds. The
/// licences (`reassoc`, `contract`, `arcp`, `afn`, `fast`) are violations
/// anywhere but `algebraic_sum`'s reduction; `nnan`, `ninf` and `nsz` are
/// facts LLVM proves and records (InstCombine's FP-class analysis), which
/// change no result, so they are counted separately.
fn ir_contract(ir: &str) -> (Vec<String>, Vec<String>) {
    let licences = ["fast", "contract", "arcp", "afn", "reassoc"];
    let facts = ["nnan", "ninf", "nsz"];
    let mut function = "";
    let (mut bad, mut inferred) = (Vec::new(), Vec::new());
    for line in ir.lines() {
        if line.starts_with("define ") {
            function = line.split('@').nth(1).and_then(|r| r.split('(').next()).unwrap_or("");
            continue;
        }
        let words: Vec<&str> = line.split_whitespace().collect();
        if line.contains("llvm.fmuladd") || line.contains("llvm.fma.") {
            bad.push(format!("{function}: {}", line.trim()));
        }
        if words.iter().any(|w| facts.contains(w)) {
            inferred.push(format!("{function}: {}", line.trim()));
        }
        let marked: Vec<&str> = words.iter().copied().filter(|w| licences.contains(w)).collect();
        if marked.is_empty() {
            continue;
        }
        let algebraic = function.ends_with("explicitAlgebraic");
        let reduction = line.contains("llvm.vector.reduce.fadd") || words.iter().any(|w| *w == "fadd");
        if !(algebraic && reduction && marked.iter().all(|w| *w == "reassoc")) {
            bad.push(format!("{function}: {}", line.trim()));
        }
    }
    (bad, inferred)
}

fn fused(asm: &str) -> Vec<String> {
    asm.lines()
        .map(str::trim)
        .filter(|l| {
            let op = l.split_whitespace().next().unwrap_or("");
            ["fmadd", "fmsub", "fnmadd", "fnmsub", "fmla", "fmls"].contains(&op) || op.starts_with("vfmadd") || op.starts_with("vfnmadd") || op.starts_with("vfmsub")
        })
        .map(str::to_string)
        .collect()
}

fn undefined_symbols(object: &[u8]) -> Vec<String> {
    use object::{Object, ObjectSymbol};
    let file = object::File::parse(object).unwrap();
    file.symbols().filter(|s| s.is_undefined()).map(|s| s.name().unwrap().to_string()).collect()
}

fn compile(args: &Args, entered: u64) {
    let started = Instant::now();
    let triple = args.need("--target");
    let os = os_of(&triple);
    let arm = triple.starts_with("arm64") || triple.starts_with("aarch64");
    let tier = if arm { Tier::Arm64Neon } else { Tier::X86Avx2 };
    // The settings llvm.rs reads, fixed before it reads them.
    unsafe {
        // Lane-width masks are the NEON form (LLVM.md, "Run time"); `<4 x i1>`
        // is the AVX2 one.
        if arm {
            std::env::set_var("NUPP_SPIKE_LLVM_MASKS", "wide");
        }
        if args.has("--no-unwind-tables") {
            std::env::set_var("NUPP_SPIKE_NO_TABLES", "1");
        }
        match args.value("--isel").as_deref() {
            None | Some("dag") => {}
            Some("fast") => std::env::set_var("NUPP_SPIKE_LLVM_ARGS", "-fast-isel"),
            Some("global") => std::env::set_var("NUPP_SPIKE_LLVM_ARGS", "-global-isel -global-isel-abort=2"),
            Some(other) => panic!("--isel {other}"),
        }
    }
    llvm::set_triple(&triple);
    let kernels: J = serde_json::from_str(&std::fs::read_to_string(args.need("--kernels")).unwrap()).unwrap();
    let builders: J = serde_json::from_str(&std::fs::read_to_string(args.need("--builders")).unwrap()).unwrap();
    let builder_size: u32 = args.need("--builder-size").parse().unwrap();
    let out = PathBuf::from(args.need("--out"));
    let verify = args.has("--verify");
    let read = us(started);

    let t = Instant::now();
    let tm = llvm::target_machine(tier, Level::O3);
    let setup = us(t);

    let t = Instant::now();
    let function = |doc: &J, name: &str| -> J { doc["functions"].as_array().unwrap().iter().find(|f| f["name"] == name).unwrap().clone() };
    let module = llvm::Module::empty("nupp_aot", tier);
    let mut kernel = |doc: &J, name: &str| {
        let f = function(doc, name);
        let sig = sem::signature(doc["c"].as_str().unwrap(), f["symbol"].as_str().unwrap());
        let func = lir::kernel(&f["tree"], &sig, llvm::LANES);
        let noalias = llvm::exclusive_params(&f["tree"], &sig);
        module.add(&func, &format!("nupp_aot_{name}"), &Shape::Kernel { sig: &sig, noalias }, tier);
    };
    for name in KERNELS {
        kernel(&kernels, name);
    }
    kernel(&builders, "waves");
    for name in BUILDERS {
        let f = function(&builders, name);
        let func = lir::builder(&f["tree"], builder_size, llvm::LANES);
        module.add(&func, &format!("nupp_aot_{name}"), &Shape::LuaBuilder, tier);
    }
    if os == Os::Windows {
        export_definitions(&module);
    }
    let irgen = us(t);

    let t = Instant::now();
    module.optimize(tm, Level::O3);
    let opt = us(t);

    let mut report = serde_json::Map::new();
    if verify {
        // Not part of a product miss: a second code generation, for reading.
        let ir = module.ir();
        let asm = module.assembly(tm);
        let (bad, inferred) = ir_contract(&ir);
        report.insert("irContract".into(), J::from(bad));
        report.insert("inferredFacts".into(), J::from(inferred));
        report.insert("fusedInstructions".into(), J::from(fused(&asm)));
        report.insert("reassocSites".into(), J::from(ir.lines().filter(|l| l.contains("reassoc")).count()));
    }

    let t = Instant::now();
    let object = module.object(tm);
    let codegen = us(t);

    // The entry is built beside its final name and appears by one rename.
    let t = Instant::now();
    let tmp = out.with_extension(format!("tmp-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&tmp);
    std::fs::create_dir_all(&tmp).unwrap();
    let object_path = tmp.join("module.o");
    std::fs::write(&object_path, &object).unwrap();
    if verify {
        std::fs::write(tmp.join("module.ll"), module.ir()).unwrap();
        std::fs::write(tmp.join("module.s"), module.assembly(tm)).unwrap();
    }
    let write_object = us(t);

    let t = Instant::now();
    let library = tmp.join(library_name(os));
    let link = link_library(os, &triple, &object_path, &library, &undefined_symbols(&object), args).unwrap_or_else(|e| {
        eprintln!("{e}");
        std::process::exit(1)
    });
    let linked = us(t);

    let t = Instant::now();
    let timing = serde_json::json!({
        "entered": entered,
        "readInputs": read, "targetMachine": setup, "irgen": irgen, "optimize": opt,
        "codegen": codegen, "writeObject": write_object, "link": linked,
        "objectBytes": object.len(), "libraryBytes": std::fs::metadata(&library).unwrap().len(),
        "lld": link,
    });
    report.insert("timing".into(), timing);
    std::fs::write(tmp.join("component.json"), serde_json::to_string_pretty(&J::Object(report.clone())).unwrap()).unwrap();
    if std::fs::rename(&tmp, &out).is_err() {
        // Another process filled the entry first: its bytes are the same.
        let _ = std::fs::remove_dir_all(&tmp);
    }
    report["timing"]["rename"] = J::from(us(t));
    report["timing"]["exited"] = J::from(now_ns());
    println!("{}", J::Object(report));
}

/// A DLL exports what it defines, by directives in the object.
fn export_definitions(module: &llvm::Module) {
    use llvm_sys::core::*;
    unsafe {
        let mut f = LLVMGetFirstFunction(module.m);
        while !f.is_null() {
            if LLVMIsDeclaration(f) == 0 && LLVMGetLinkage(f) == llvm_sys::LLVMLinkage::LLVMExternalLinkage {
                LLVMSetDLLStorageClass(f, llvm_sys::LLVMDLLStorageClass::LLVMDLLExportStorageClass);
            }
            f = LLVMGetNextFunction(f);
        }
    }
}

/// Links `object` into a shared library for `os`. Returns the lld command.
fn link_library(os: Os, triple: &str, object: &Path, library: &Path, undefined: &[String], args: &Args) -> Result<String, String> {
    let o = object.display().to_string();
    let l = library.display().to_string();
    let argv: Vec<String> = match os {
        // Undefined symbols (the Lua C API, the runtime, libm) bind at load
        // time against what the host process already has loaded.
        Os::MacOS => ["ld64.lld", "-arch", "arm64", "-platform_version", "macos", "11.0.0", "11.0.0", "-dylib", "-install_name", "@rpath/module.dylib", "-undefined", "dynamic_lookup", "-o", &l, &o]
            .iter()
            .map(|s| s.to_string())
            .collect(),
        // Shared objects may leave symbols undefined for the global scope;
        // `--eh-frame-hdr` gives the unwinder its PT_GNU_EH_FRAME index.
        Os::Linux => ["ld.lld", "-shared", "--eh-frame-hdr", "-z", "noexecstack", "-z", "now", "--hash-style=gnu", "-soname", "module.so", "-o", &l, &o]
            .iter()
            .map(|s| s.to_string())
            .collect(),
        // A PE image may not leave anything undefined: every import names its
        // DLL, through an import library written here for each provider.
        Os::Windows => {
            let dir = library.parent().unwrap();
            let mut libs = Vec::new();
            let mut providers: Vec<(String, Vec<String>)> = Vec::new();
            let rules: Vec<(String, String)> = args
                .values("--import")
                .iter()
                .map(|r| {
                    let (prefix, dll) = r.split_once('=').expect("--import prefix=dll");
                    (prefix.to_string(), dll.to_string())
                })
                .collect();
            for sym in undefined {
                let name = sym.trim_start_matches("__imp_");
                let dll = rules
                    .iter()
                    .find(|(p, _)| p == "*" || name.starts_with(p.as_str()))
                    .map(|(_, d)| d.clone())
                    .ok_or_else(|| format!("no provider for import {name}"))?;
                match providers.iter_mut().find(|(d, _)| *d == dll) {
                    Some((_, names)) => names.push(name.to_string()),
                    None => providers.push((dll, vec![name.to_string()])),
                }
            }
            for (dll, names) in &providers {
                let path = dir.join(format!("{}.imp.a", dll.trim_end_matches(".dll").trim_end_matches(".exe")));
                let c: Vec<CString> = names.iter().map(|n| CString::new(n.as_str()).unwrap()).collect();
                let p: Vec<*const c_char> = c.iter().map(|n| n.as_ptr()).collect();
                let (d, pth) = (CString::new(dll.as_str()).unwrap(), CString::new(path.display().to_string()).unwrap());
                if unsafe { nupp_import_library(d.as_ptr(), pth.as_ptr(), p.as_ptr(), p.len() as i32) } != 0 {
                    return Err(format!("import library for {dll}"));
                }
                libs.push(path.display().to_string());
            }
            let mut v: Vec<String> = ["lld-link", "-lldmingw", "/dll", "/noentry", "/machine:x64", "/nodefaultlib"].iter().map(|s| s.to_string()).collect();
            v.push(format!("/out:{l}"));
            v.push(o.clone());
            v.extend(libs);
            v
        }
    };
    let _ = triple;
    lld(&argv)?;
    Ok(argv.join(" "))
}

/// A standalone macOS executable: the cached object, the runtime's prebuilt
/// objects and archives, and libSystem named by a text stub written here --
/// no SDK, no system linker.
fn exe(args: &Args) {
    use object::{Object, ObjectSymbol};
    let t = Instant::now();
    let out = args.need("--out");
    let inputs: Vec<String> = args.values("--input");
    let mut defined = std::collections::BTreeSet::new();
    let mut undefined = std::collections::BTreeSet::new();
    let mut scan = |bytes: &[u8]| {
        let file = object::File::parse(bytes).unwrap();
        for s in file.symbols() {
            let n = s.name().unwrap().to_string();
            if s.is_undefined() {
                undefined.insert(n);
            } else if s.is_global() {
                defined.insert(n);
            }
        }
    };
    for path in &inputs {
        let bytes = std::fs::read(path).unwrap();
        if bytes.starts_with(b"!<arch>\n") {
            let archive = object::read::archive::ArchiveFile::parse(&*bytes).unwrap();
            for member in archive.members() {
                let m = member.unwrap();
                let data = m.data(&*bytes).unwrap();
                if object::File::parse(data).is_ok() {
                    scan(data);
                }
            }
        } else {
            scan(&bytes);
        }
    }
    let mut system: Vec<String> = undefined.difference(&defined).cloned().collect();
    // Lazy binding's helper, which lld references on the images' behalf.
    system.push("dyld_stub_binder".into());
    let dir = Path::new(&out).parent().unwrap().to_path_buf();
    let tbd = dir.join("libSystem.tbd");
    let symbols = system.iter().map(|s| format!("'{s}'")).collect::<Vec<_>>().join(", ");
    std::fs::write(
        &tbd,
        format!(
            "--- !tapi-tbd\ntbd-version: 4\ntargets: [ arm64-macos ]\ninstall-name: '/usr/lib/libSystem.B.dylib'\ncurrent-version: 1351\nexports:\n  - targets: [ arm64-macos ]\n    symbols: [ {symbols} ]\n...\n"
        ),
    )
    .unwrap();
    let mut argv: Vec<String> = ["ld64.lld", "-arch", "arm64", "-platform_version", "macos", "11.0.0", "26.0.0", "-dead_strip", "-o", &out].iter().map(|s| s.to_string()).collect();
    argv.extend(inputs.iter().cloned());
    argv.push(tbd.display().to_string());
    if let Err(e) = lld(&argv) {
        eprintln!("{e}");
        std::process::exit(1);
    }
    println!("{}", serde_json::json!({"link": us(t), "libSystemSymbols": system, "command": argv.join(" ")}));
}
