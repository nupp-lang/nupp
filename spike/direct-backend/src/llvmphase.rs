//! The LLVM backend's evidence, run beside the direct backend from the same
//! binary on the same inputs: correctness against the C backend, run time,
//! compile latency, Lua-builder entries with unwinding, x86 and Wasm.

use crate::llvm::{self, Level, Shape, Tier};
use crate::{emit, emit_x86, lir, loader, lower, luaphase, sem};
use regalloc2::{Algorithm, RegallocOptions};
use serde_json::Value as J;
use std::ffi::{CStr, CString};
use std::fmt::Write as _;
use std::os::raw::c_int;
use std::process::Command;
use std::time::Instant;

/// simd11 kernels past the five the direct spike covers, tried for coverage.
const MORE: &[&str] = &["ordered", "explicitOrdered", "pairwise", "explicitPairwise", "algebraic", "crossLane", "crossWidth"];

type DotFn = unsafe extern "C" fn(*const f64, *const f64, usize, usize) -> f64;
type WidthFn = unsafe extern "C" fn() -> u32;

fn us(t: Instant) -> f64 {
    t.elapsed().as_secs_f64() * 1e6
}

fn median(mut v: Vec<f64>) -> f64 {
    v.sort_by(f64::total_cmp);
    v[v.len() / 2]
}

unsafe fn call_any(name: &str, f: *const u8, x: &crate::Inputs, out: &mut [f64]) -> f64 {
    unsafe {
        match name {
            "ordered" | "explicitOrdered" | "pairwise" | "explicitPairwise" | "algebraic" => {
                let n = x.left.len();
                std::mem::transmute::<*const u8, DotFn>(f)(x.left.as_ptr(), x.right.as_ptr(), n, n)
            }
            "crossWidth" => std::mem::transmute::<*const u8, WidthFn>(f)() as f64,
            _ => crate::call(name, f, x, out),
        }
    }
}

/// Bit-identical to C for every n, except a reassociating sum (1e-12).
fn check_any(name: &str, ours: *const u8, theirs: *const u8) -> Result<(), String> {
    let reassociates = name.contains("lgebraic");
    for n in (0..18).chain([63, 1000, 65539]) {
        let x = crate::inputs(n);
        let mut a = vec![-777.0; n + 4];
        let mut b = vec![-777.0; n + 4];
        let (ra, rb) = unsafe { (call_any(name, ours, &x, &mut a), call_any(name, theirs, &x, &mut b)) };
        for i in 0..n + 4 {
            if a[i].to_bits() != b[i].to_bits() {
                return Err(format!("n={n} element {i}: ours {} C {}", a[i], b[i]));
            }
        }
        let same = if reassociates { (ra - rb).abs() <= 1e-12 * rb.abs().max(1.0) } else { ra.to_bits() == rb.to_bits() };
        if !same {
            return Err(format!("n={n}: ours {ra} C {rb}"));
        }
    }
    Ok(())
}

/// Median of 21 samples per function, the order rotating every sample.
fn time_all(name: &str, fs: &[*const u8], n: usize) -> Vec<f64> {
    let x = crate::inputs(n);
    let mut out = vec![0.0; n + 4];
    let repeats = (2_000_000 / n.max(1)).max(1);
    let run = |f: *const u8, out: &mut [f64]| {
        let start = Instant::now();
        let mut sink = 0.0;
        for _ in 0..repeats {
            sink += unsafe { call_any(name, std::hint::black_box(f), &x, out) };
        }
        std::hint::black_box(sink);
        start.elapsed().as_secs_f64() * 1e9 / repeats as f64
    };
    for _ in 0..3 {
        for f in fs {
            run(*f, &mut out);
        }
    }
    let mut samples = vec![Vec::new(); fs.len()];
    for s in 0..21 {
        for k in 0..fs.len() {
            let j = (s + k) % fs.len();
            samples[j].push(run(fs[j], &mut out));
        }
    }
    samples.into_iter().map(median).collect()
}

fn function<'d>(doc: &'d J, name: &str) -> &'d J {
    doc["functions"].as_array().unwrap().iter().find(|f| f["name"] == name).unwrap_or_else(|| panic!("no function {name}"))
}

fn panic_text(e: Box<dyn std::any::Any + Send>) -> String {
    e.downcast_ref::<String>().cloned().or_else(|| e.downcast_ref::<&str>().map(|s| s.to_string())).unwrap_or_default()
}

/// LIR for a kernel, or why the shared walker cannot lower it.
fn kernel_lir(doc: &J, name: &str, lanes: usize) -> Result<(lir::Func, sem::Signature), String> {
    let c = doc["c"].as_str().unwrap();
    let f = function(doc, name);
    let sig = sem::signature(c, f["symbol"].as_str().unwrap());
    let hook = std::panic::take_hook();
    std::panic::set_hook(Box::new(|_| {}));
    let r = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| lir::kernel(&f["tree"], &sig, lanes)));
    std::panic::set_hook(hook);
    r.map(|func| (func, sem::signature(c, f["symbol"].as_str().unwrap()))).map_err(panic_text)
}

#[derive(Default, Clone, Copy)]
struct Phases {
    lir: f64,
    ir: f64,
    opt: f64,
    codegen: f64,
    link: f64,
}

impl Phases {
    fn total(&self) -> f64 {
        self.lir + self.ir + self.opt + self.codegen + self.link
    }
}

/// Words of code in an object's text section.
fn text_bytes(object: &[u8]) -> usize {
    use object::{Object, ObjectSection};
    let file = object::File::parse(object).unwrap();
    file.sections().filter(|s| s.kind() == object::SectionKind::Text).map(|s| s.size() as usize).sum()
}

/// Walker through JIT-linked code for one kernel; `symbol` must be fresh.
fn compile_kernel(doc: &J, name: &str, symbol: &str, tm: llvm_sys::target_machine::LLVMTargetMachineRef, level: Level, jit: &llvm::Jit) -> (*const u8, Phases, Vec<u8>) {
    let mut p = Phases::default();
    let t = Instant::now();
    let (f, sig) = kernel_lir(doc, name, llvm::LANES).unwrap();
    p.lir = us(t);
    let t = Instant::now();
    let noalias = llvm::exclusive_params(&function(doc, name)["tree"], &sig);
    let m = llvm::build(&f, symbol, &Shape::Kernel { sig: &sig, noalias }, Tier::Arm64Neon);
    p.ir = us(t);
    let t = Instant::now();
    m.optimize(tm, level);
    p.opt = us(t);
    let t = Instant::now();
    let object = m.object(tm);
    p.codegen = us(t);
    let t = Instant::now();
    jit.add_object(&object, symbol);
    let addr = jit.lookup(symbol);
    p.link = us(t);
    (addr, p, object)
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

pub fn run(path: &str) {
    // One-time costs first, in a process that has touched no LLVM yet.
    let t = Instant::now();
    llvm::init_targets();
    let init_us = us(t);
    let t = Instant::now();
    let tm2 = llvm::target_machine(Tier::Arm64Neon, Level::O2);
    let tm_us = us(t);
    let tm3 = llvm::target_machine(Tier::Arm64Neon, Level::O3);
    let t = Instant::now();
    let jit = llvm::Jit::new(Tier::Arm64Neon, Level::O3, true);
    let jit_us = us(t);
    let t = Instant::now();
    let jit_ir = llvm::Jit::new(Tier::Arm64Neon, Level::O3, true);
    let jit2_us = us(t);
    println!(
        "one-time: register targets {init_us:.0}us, target machine {tm_us:.0}us, LLJIT + process symbols {jit_us:.0}us (second {jit2_us:.0}us)"
    );

    let doc: J = serde_json::from_str(&std::fs::read_to_string(path).unwrap()).unwrap();
    let c = doc["c"].as_str().unwrap();
    let dir = std::env::temp_dir().join(format!("nupp-spike-llvm-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let handle = crate::c_library(c, &dir);
    let dump = std::env::var("NUPP_SPIKE_LLVM_DUMP").ok();

    // ---- correctness -------------------------------------------------------
    println!("\n{:<18} {:>6} {:>6} {:>6} {:>6}  {}", "kernel", "O2 w", "O3 w", "direct", "C w", "result");
    let env = emit::machine_env();
    let mut images = Vec::new();
    let mut timed: Vec<(&str, Vec<*const u8>)> = Vec::new();
    let mut first_link = None;
    let mut failures = 0;
    for name in crate::KERNELS.iter().chain(MORE) {
        let symbol = function(&doc, name)["symbol"].as_str().unwrap().to_string();
        let theirs = crate::symbol(handle, &symbol);
        if let Err(e) = kernel_lir(&doc, name, llvm::LANES) {
            println!("{name:<18} {:>6} {:>6} {:>6} {:>6}  shared walker cannot lower it: {e}", "-", "-", "-", "-");
            continue;
        }
        let mut words = Vec::new();
        let mut fs = Vec::new();
        let mut result = Vec::new();
        for (level, tm) in [(Level::O2, tm2), (Level::O3, tm3)] {
            let sym = format!("llvm_{name}_{level:?}");
            let (addr, p, object) = compile_kernel(&doc, name, &sym, tm, level, &jit);
            first_link.get_or_insert(p.link);
            words.push(text_bytes(&object) / 4);
            let (f, sig) = kernel_lir(&doc, name, llvm::LANES).unwrap();
            let noalias = llvm::exclusive_params(&function(&doc, name)["tree"], &sig);
            let m = llvm::build(&f, &sym, &Shape::Kernel { sig: &sig, noalias }, Tier::Arm64Neon);
            m.optimize(tm, level);
            let asm = m.assembly(tm);
            let fusedops = fused(&asm);
            if !fusedops.is_empty() {
                result.push(format!("{level:?} FUSED {fusedops:?}"));
                failures += 1;
            }
            if dump.as_deref() == Some(*name) {
                println!("---- {name} {level:?} IR ----\n{}\n---- {name} {level:?} asm ----\n{asm}", m.ir());
            }
            match check_any(name, addr, theirs) {
                Ok(()) => result.push(format!("{level:?} same")),
                Err(e) => {
                    failures += 1;
                    result.push(format!("{level:?} DIFFER {e}"));
                }
            }
            fs.push(addr);
        }
        // The IR path: LLJIT runs code generation itself.
        {
            let (f, sig) = kernel_lir(&doc, name, llvm::LANES).unwrap();
            let noalias = llvm::exclusive_params(&function(&doc, name)["tree"], &sig);
            let sym = format!("llvm_ir_{name}");
            let m = llvm::build(&f, &sym, &Shape::Kernel { sig: &sig, noalias }, Tier::Arm64Neon);
            m.optimize(tm3, Level::O3);
            jit_ir.add_ir(m);
            match check_any(name, jit_ir.lookup(&sym), theirs) {
                Ok(()) => result.push("IR-path same".into()),
                Err(e) => {
                    failures += 1;
                    result.push(format!("IR-path DIFFER {e}"));
                }
            }
        }
        let mut direct_words = "-".to_string();
        if crate::KERNELS.contains(name) {
            let sig = lower::signature(c, &symbol);
            let func = lower::lower(&function(&doc, name)["tree"], &sig);
            let options = RegallocOptions { verbose_log: false, validate_ssa: true, algorithm: Algorithm::Ion };
            let output = regalloc2::run(&func, &env, &options).unwrap();
            let (code, stats) = emit::emit(&func, &output);
            let image = loader::Image::load(&code);
            direct_words = stats.words.to_string();
            match check_any(name, image.entry(), theirs) {
                Ok(()) => result.push("direct same".into()),
                Err(e) => {
                    failures += 1;
                    result.push(format!("direct DIFFER {e}"));
                }
            }
            fs.push(image.entry());
            images.push(image);
        }
        fs.push(theirs);
        println!(
            "{:<18} {:>6} {:>6} {:>6} {:>6}  {}",
            name,
            words[0],
            words[1],
            direct_words,
            crate::c_words(&dir, &symbol),
            result.join("; ")
        );
        timed.push((name, fs));
    }
    println!("correctness failures: {failures}");
    if failures > 0 {
        return;
    }

    // ---- compile latency, warm ----------------------------------------------
    println!("\ncompile latency, warm (median of 9; first link in this process {:.0}us):", first_link.unwrap_or(0.0));
    println!("{:<18} {:>7} {:>7} {:>7} {:>8} {:>7} {:>8} | {:>8} {:>8} | {:>8}", "kernel", "lir", "irgen", "opt", "codegen", "link", "O3 total", "O2 total", "IR path", "direct");
    for name in crate::KERNELS {
        let mut o3 = Vec::new();
        let mut o2 = Vec::new();
        let mut irpath = Vec::new();
        let mut direct = Vec::new();
        for r in 0..9 {
            o3.push(compile_kernel(&doc, name, &format!("llvm_{name}_w3_{r}"), tm3, Level::O3, &jit).1);
            o2.push(compile_kernel(&doc, name, &format!("llvm_{name}_w2_{r}"), tm2, Level::O2, &jit).1.total());
            let t = Instant::now();
            let (f, sig) = kernel_lir(&doc, name, llvm::LANES).unwrap();
            let noalias = llvm::exclusive_params(&function(&doc, name)["tree"], &sig);
            let sym = format!("llvm_ir_{name}_w{r}");
            let m = llvm::build(&f, &sym, &Shape::Kernel { sig: &sig, noalias }, Tier::Arm64Neon);
            m.optimize(tm3, Level::O3);
            jit_ir.add_ir(m);
            jit_ir.lookup(&sym);
            irpath.push(us(t));
            let t = Instant::now();
            let sig = lower::signature(c, function(&doc, name)["symbol"].as_str().unwrap());
            let func = lower::lower(&function(&doc, name)["tree"], &sig);
            let options = RegallocOptions { verbose_log: false, validate_ssa: false, algorithm: Algorithm::Ion };
            let output = regalloc2::run(&func, &env, &options).unwrap();
            let (code, _) = emit::emit(&func, &output);
            let image = loader::Image::load(&code);
            std::hint::black_box(image.entry());
            direct.push(us(t));
            images.push(image);
        }
        let m = |f: fn(&Phases) -> f64| median(o3.iter().map(f).collect());
        println!(
            "{:<18} {:>5.0}us {:>5.0}us {:>5.0}us {:>6.0}us {:>5.0}us {:>6.0}us | {:>6.0}us {:>6.0}us | {:>6.0}us",
            name,
            m(|p| p.lir),
            m(|p| p.ir),
            m(|p| p.opt),
            m(|p| p.codegen),
            m(|p| p.link),
            m(|p| p.total()),
            median(o2),
            median(irpath),
            median(direct)
        );
    }

    // The whole program as one module: per-module costs are paid once.
    for (level, tm) in [(Level::O3, tm3), (Level::O2, tm2)] {
        let mut runs: Vec<Phases> = Vec::new();
        let mut direct = Vec::new();
        for r in 0..9 {
            let mut p = Phases::default();
            let t = Instant::now();
            let lirs: Vec<(lir::Func, sem::Signature)> = crate::KERNELS.iter().map(|n| kernel_lir(&doc, n, llvm::LANES).unwrap()).collect();
            p.lir = us(t);
            let t = Instant::now();
            let m = llvm::Module::empty("program", Tier::Arm64Neon);
            for (name, (f, sig)) in crate::KERNELS.iter().zip(&lirs) {
                let noalias = llvm::exclusive_params(&function(&doc, name)["tree"], sig);
                m.add(f, &format!("llvm_p{level:?}{r}_{name}"), &Shape::Kernel { sig, noalias }, Tier::Arm64Neon);
            }
            p.ir = us(t);
            let t = Instant::now();
            m.optimize(tm, level);
            p.opt = us(t);
            let t = Instant::now();
            let object = m.object(tm);
            p.codegen = us(t);
            let t = Instant::now();
            jit.add_object(&object, "program");
            for name in crate::KERNELS {
                std::hint::black_box(jit.lookup(&format!("llvm_p{level:?}{r}_{name}")));
            }
            p.link = us(t);
            runs.push(p);
            let t = Instant::now();
            for name in crate::KERNELS {
                let sig = lower::signature(c, function(&doc, name)["symbol"].as_str().unwrap());
                let func = lower::lower(&function(&doc, name)["tree"], &sig);
                let options = RegallocOptions { verbose_log: false, validate_ssa: false, algorithm: Algorithm::Ion };
                let output = regalloc2::run(&func, &env, &options).unwrap();
                let (code, _) = emit::emit(&func, &output);
                images.push(loader::Image::load(&code));
            }
            direct.push(us(t));
        }
        let m = |f: fn(&Phases) -> f64| median(runs.iter().map(f).collect());
        println!(
            "{:<18} {:>5.0}us {:>5.0}us {:>5.0}us {:>6.0}us {:>5.0}us {:>6.0}us | {:>8} {:>8} | {:>6.0}us",
            format!("all five, {level:?}"),
            m(|p| p.lir),
            m(|p| p.ir),
            m(|p| p.opt),
            m(|p| p.codegen),
            m(|p| p.link),
            m(|p| p.total()),
            "",
            "",
            median(direct)
        );
    }

    // ---- run time -----------------------------------------------------------
    let load = Command::new("uptime").output().map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string()).unwrap_or_default();
    println!("\nrun time, ratio to clang -O3 C (median of 21 rotating samples); {load}");
    println!("{:<18} {:>6} {:>9} {:>7} {:>7} {:>7}", "kernel", "n", "C ns", "O2/C", "O3/C", "direct/C");
    for (name, fs) in &timed {
        for n in [63usize, 1000, 65539] {
            let t = time_all(name, fs, n);
            let c_ns = t[t.len() - 1];
            let direct = if fs.len() == 4 { format!("{:>7.2}", t[2] / c_ns) } else { format!("{:>7}", "-") };
            println!("{:<18} {:>6} {:>9.1} {:>7.2} {:>7.2} {}", name, n, c_ns, t[0] / c_ns, t[1] / c_ns, direct);
        }
    }
    drop(images);
}

/// One-time costs in a fresh process: targets, a target machine, LLJIT, and
/// the first kernel through to a lookup.
pub fn init(path: &str) {
    let t = Instant::now();
    llvm::init_targets();
    let a = us(t);
    let t = Instant::now();
    let tm = llvm::target_machine(Tier::Arm64Neon, Level::O3);
    let b = us(t);
    let t = Instant::now();
    let jit = llvm::Jit::new(Tier::Arm64Neon, Level::O3, true);
    let c = us(t);
    let doc: J = serde_json::from_str(&std::fs::read_to_string(path).unwrap()).unwrap();
    let t = Instant::now();
    let (_, p, _) = compile_kernel(&doc, "refine", "first", tm, Level::O3, &jit);
    let d = us(t);
    println!("{a:.0} {b:.0} {c:.0} {d:.0} {:.0}", p.link);
}

/// Codegen only, repeated, for profiling: `-time-passes` prints on shutdown.
pub fn profile(path: &str, name: &str) {
    let doc: J = serde_json::from_str(&std::fs::read_to_string(path).unwrap()).unwrap();
    let tm = llvm::target_machine(Tier::Arm64Neon, Level::O3);
    let (f, sig) = kernel_lir(&doc, name, llvm::LANES).unwrap();
    let noalias = llvm::exclusive_params(&function(&doc, name)["tree"], &sig);
    let m = llvm::build(&f, name, &Shape::Kernel { sig: &sig, noalias }, Tier::Arm64Neon);
    m.optimize(tm, Level::O3);
    let mut times = Vec::new();
    let reps: usize = std::env::var("NUPP_SPIKE_REPS").ok().and_then(|r| r.parse().ok()).unwrap_or(50);
    for _ in 0..reps {
        let t = Instant::now();
        std::hint::black_box(m.object(tm));
        times.push(us(t));
    }
    println!("{name}: codegen median {:.0}us", median(times));
    unsafe { llvm_sys::core::LLVMShutdown() };
}

// ---- Lua-builder entries -------------------------------------------------------

fn level_from_env() -> Level {
    if std::env::var("NUPP_SPIKE_LLVM_LEVEL").as_deref() == Ok("O3") { Level::O3 } else { Level::O2 }
}

pub fn lua(path: &str) {
    let doc: J = serde_json::from_str(&std::fs::read_to_string(path).unwrap()).unwrap();
    let c = doc["c"].as_str().unwrap();
    let dir = std::env::temp_dir().join(format!("nupp-spike-llvm-lua-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let luajit = std::env::var("NUPP_SPIKE_LUAJIT").expect("NUPP_SPIKE_LUAJIT: path to libluajit-5.1.dylib");
    luaphase::open_global(&luajit);
    let src = dir.join("runtime.c");
    let lib = dir.join("runtime.dylib");
    std::fs::write(&src, format!("{c}\n{}", luaphase::RUNTIME_SHIMS)).unwrap();
    let ok = Command::new("clang")
        .args(["-std=c11", "-O3", "-ffp-contract=off", "-fno-fast-math", "-fPIC", "-dynamiclib", "-undefined", "dynamic_lookup", "-w", "-o"])
        .arg(&lib)
        .arg(&src)
        .status()
        .unwrap();
    assert!(ok.success());
    luaphase::open_global(lib.to_str().unwrap());
    let builder_size: unsafe extern "C" fn() -> usize = unsafe { std::mem::transmute(luaphase::sym("ks_rt_builder_size")) };
    let builder_size = unsafe { builder_size() } as u32;
    let no_cfi = std::env::var("NUPP_SPIKE_NO_CFI").is_ok();
    let level = level_from_env();
    let tm = llvm::target_machine(Tier::Arm64Neon, level);
    let jit = llvm::Jit::new(Tier::Arm64Neon, level, !no_cfi);

    if !no_cfi {
        let waves = function(&doc, "waves");
        let sig = sem::signature(c, waves["symbol"].as_str().unwrap());
        let t = Instant::now();
        let f = lir::kernel(&waves["tree"], &sig, llvm::LANES);
        let noalias = llvm::exclusive_params(&waves["tree"], &sig);
        let m = llvm::build(&f, "llvm_waves", &Shape::Kernel { sig: &sig, noalias }, Tier::Arm64Neon);
        m.optimize(tm, level);
        let object = m.object(tm);
        jit.add_object(&object, "waves");
        let entry = jit.lookup("llvm_waves");
        let compile = us(t);
        let imports = undefined_symbols(&object);
        type Waves = unsafe extern "C" fn(*mut f64, *const f64, f64, usize);
        let ours: Waves = unsafe { std::mem::transmute(entry) };
        let theirs: Waves = unsafe { std::mem::transmute(luaphase::sym(&sig.symbol)) };
        for n in (0..10).chain([1000]) {
            let input: Vec<f64> = (0..n).map(|i| (i as f64 - 400.0) * 0.0125).collect();
            let (mut a, mut b) = (vec![-7.0; n + 2], vec![-7.0; n + 2]);
            unsafe {
                ours(a.as_mut_ptr(), input.as_ptr(), 0.5, n);
                theirs(b.as_mut_ptr(), input.as_ptr(), 0.5, n);
            }
            for i in 0..n + 2 {
                assert!(a[i].to_bits() == b[i].to_bits(), "waves n={n} [{i}] ours {} C {}", a[i], b[i]);
            }
        }
        let input: Vec<f64> = (0..1000).map(|i| (i as f64 - 400.0) * 0.0125).collect();
        let mut out = vec![0.0; 1000];
        let time = |f: Waves, out: &mut Vec<f64>| {
            let mut best = f64::MAX;
            for _ in 0..15 {
                let t = Instant::now();
                for _ in 0..200 {
                    unsafe { f(out.as_mut_ptr(), std::hint::black_box(input.as_ptr()), 0.5, 1000) };
                }
                best = best.min(t.elapsed().as_secs_f64() * 1e9 / 200.0);
            }
            best
        };
        let (o, t) = (time(ours, &mut out), time(theirs, &mut out));
        println!(
            "waves {level:?} (imports: {}) words {} compile {:.0}us: bit-identical n=0..9,1000; n=1000 ours {:.0} ns C {:.0} ns ours/C {:.2}",
            imports.join(", "),
            text_bytes(&object) / 4,
            compile,
            o,
            t,
            o / t
        );
    }

    let mut entries = Vec::new();
    for name in ["rows", "object", "stream"] {
        let f = function(&doc, name);
        let t = Instant::now();
        let func = lir::builder(&f["tree"], builder_size, llvm::LANES);
        let sym = format!("llvm_{name}");
        let m = llvm::build(&func, &sym, &Shape::LuaBuilder, Tier::Arm64Neon);
        m.optimize(tm, level);
        let object = m.object(tm);
        jit.add_object(&object, name);
        let entry = jit.lookup(&sym);
        let compile = us(t);
        if !no_cfi {
            println!(
                "{name}: words {} imports {} compile {:.0}us, unwind sections: {}",
                text_bytes(&object) / 4,
                undefined_symbols(&object).len(),
                compile,
                unwind_sections(&object).join(", ")
            );
        }
        entries.push((name, entry));
    }

    let registrar = c
        .lines()
        .find(|l| l.starts_with("KS_API int ks_register_"))
        .map(|l| l["KS_API int ".len()..l.find('(').unwrap()].to_string())
        .unwrap();
    let lua = luaphase::lua_api();
    unsafe {
        let l = (lua.new_state)();
        (lua.open_libs)(l);
        let script = CString::new(luaphase::HARNESS).unwrap();
        assert_eq!((lua.load_string)(l, script.as_ptr()), 0);
        (lua.create_table)(l, 0, 3);
        for (name, entry) in &entries {
            (lua.push_cclosure)(l, std::mem::transmute::<*const u8, luaphase::CFunction>(*entry), 0);
            let n = CString::new(*name).unwrap();
            (lua.set_field)(l, -2, n.as_ptr());
        }
        let reg: luaphase::CFunction = std::mem::transmute(luaphase::sym(&registrar));
        (lua.push_cclosure)(l, reg, 0);
        assert_eq!((lua.pcall)(l, 0, 1, 0), 0);
        (lua.push_boolean)(l, no_cfi as c_int);
        let status = (lua.pcall)(l, 3, 1, 0);
        if status != 0 {
            let msg = CStr::from_ptr((lua.to_lstring)(l, -1, std::ptr::null_mut()));
            panic!("harness: {msg:?}");
        }
        let all_same = (lua.to_boolean)(l, -1) != 0;
        println!("lua-builder entries match C: {all_same}");
    }
    drop(jit);
}

fn undefined_symbols(object: &[u8]) -> Vec<String> {
    use object::{Object, ObjectSymbol};
    let file = object::File::parse(object).unwrap();
    file.symbols().filter(|s| s.is_undefined()).map(|s| s.name().unwrap().trim_start_matches('_').to_string()).collect()
}

fn unwind_sections(object: &[u8]) -> Vec<String> {
    use object::{Object, ObjectSection};
    let file = object::File::parse(object).unwrap();
    file.sections()
        .filter_map(|s| s.name().ok().map(str::to_string))
        .filter(|n| n.contains("eh_frame") || n.contains("compact_unwind"))
        .map(|n| {
            let size = file.section_by_name(&n).map(|s| s.size()).unwrap_or(0);
            format!("{n} ({size} B)")
        })
        .collect()
}

/// The error cases in a child whose JIT links without unwind registration.
pub fn lua_without_registration(path: &str) {
    use std::os::unix::process::ExitStatusExt;
    for (what, tables) in [("JITLink without LLJIT's eh-frame plugin", true), ("no unwind tables emitted", false)] {
        let exe = std::env::current_exe().unwrap();
        let mut cmd = Command::new(exe);
        cmd.arg("llvm-lua").arg(path).env("NUPP_SPIKE_NO_CFI", "1");
        if !tables {
            cmd.env("NUPP_SPIKE_NO_TABLES", "1");
        }
        let out = cmd.output().unwrap();
        println!(
            "{what}: exit {:?} signal {:?}; stdout {:?}; stderr tail {:?}",
            out.status.code(),
            out.status.signal(),
            String::from_utf8_lossy(&out.stdout).trim(),
            String::from_utf8_lossy(&out.stderr).lines().last().unwrap_or("")
        );
    }
}

// ---- x86-64 ------------------------------------------------------------------

const X86_KERNELS: &[(&str, &str)] = &[
    ("map", "void (*)(double *, const double *, double, double, size_t)"),
    ("refine", "void (*)(double *, const double *, size_t)"),
    ("explicitMap", "void (*)(double *, const double *, double, double, size_t, size_t)"),
    ("explicitRefine", "void (*)(double *, const double *, size_t, size_t)"),
    ("explicitAlgebraic", "double (*)(const double *, const double *, size_t, size_t)"),
];

/// AVX2 and AVX-512 objects from LLVM, the direct backend's AVX2 images, and
/// an x86-64 macOS test program linking the objects beside the C backend's
/// AVX2 build (the oracle). Run the program under Rosetta.
pub fn x86(path: &str, out_dir: &str) {
    let doc: J = serde_json::from_str(&std::fs::read_to_string(path).unwrap()).unwrap();
    let c = doc["c"].as_str().unwrap();
    std::fs::create_dir_all(out_dir).unwrap();
    let env = emit_x86::machine_env();
    let mut decls = String::new();
    let mut images = String::new();
    let mut table = String::from("static const struct kernel kernels[] = {\n");
    let mut objects = Vec::new();
    for (name, ty) in X86_KERNELS {
        let (f, sig) = kernel_lir(&doc, name, llvm::LANES).unwrap();
        let noalias = llvm::exclusive_params(&function(&doc, name)["tree"], &sig);
        let mut line = Vec::new();
        for tier in [Tier::X86Avx2, Tier::X86Avx512] {
            for level in [Level::O2, Level::O3] {
                let t = Instant::now();
                let tm = llvm::target_machine(tier, level);
                let tag = format!("{}_{level:?}", if tier == Tier::X86Avx2 { "avx2" } else { "avx512" });
                let sym = format!("llvm_{tag}_{name}");
                let m = llvm::build(&f, &sym, &Shape::Kernel { sig: &sig, noalias: noalias.clone() }, tier);
                m.optimize(tm, level);
                let object = m.object(tm);
                let asm = m.assembly(tm);
                let fusedops = fused(&asm);
                assert!(fusedops.is_empty(), "{name} {tag}: fused {fusedops:?}");
                line.push(format!("{tag} {} B {:.0}us", text_bytes(&object), us(t)));
                let o = format!("{out_dir}/{name}.{tag}.o");
                std::fs::write(&o, &object).unwrap();
                std::fs::write(format!("{out_dir}/{name}.{tag}.s"), asm).unwrap();
                if tier == Tier::X86Avx512 && level == Level::O3 {
                    line.push(iced_decode(&object));
                }
                if tier == Tier::X86Avx2 {
                    objects.push(o);
                    let _ = writeln!(decls, "extern char {sym}[];");
                }
                unsafe { LLVMDisposeTargetMachine(tm) };
            }
        }
        // The direct backend's AVX2 image, as x86phase builds it.
        let dsig = lower::signature(c, function(&doc, name)["symbol"].as_str().unwrap());
        let func = lower::lower_for(&function(&doc, name)["tree"], &dsig, lower::Target::X86Avx2);
        let options = RegallocOptions { verbose_log: false, validate_ssa: true, algorithm: Algorithm::Ion };
        let output = regalloc2::run(&func, &env, &options).unwrap();
        let e = emit_x86::emit(&func, &output);
        let _ = write!(images, "static const unsigned char image_{name}[] = {{");
        for (k, b) in e.bytes.iter().enumerate() {
            if k % 24 == 0 {
                images.push_str("\n   ");
            }
            let _ = write!(images, " {b},");
        }
        images.push_str("\n};\n");
        line.push(format!("direct {} B", e.bytes.len()));
        println!("{name}: {}", line.join(", "));
        let _ = writeln!(
            table,
            "    {{\"{name}\", {{(void *)llvm_avx2_O2_{name}, (void *)llvm_avx2_O3_{name}}}, image_{name}, sizeof image_{name}, (void *){}, \"{ty}\"}},",
            sig.symbol
        );
    }
    table.push_str("};\n");
    let harness = format!("{c}\n\n/* ---- LLVM spike harness ---- */\n{decls}{images}\n{X86_TYPES}{table}{X86_MAIN}");
    let src = format!("{out_dir}/x86test.c");
    std::fs::write(&src, harness).unwrap();
    let exe = format!("{out_dir}/x86test");
    let status = Command::new("clang")
        .args(["-arch", "x86_64", "-std=gnu11", "-O3", "-mavx2", "-mfma", "-ffp-contract=off", "-fno-fast-math", "-w", "-o", &exe, &src])
        .args(&objects)
        .status()
        .unwrap();
    assert!(status.success());
    println!("wrote {exe}; run it (under Rosetta) for the AVX2 results");
}

use llvm_sys::target_machine::LLVMDisposeTargetMachine;

/// Decodes an object's text with iced-x86, independently of LLVM's own
/// disassembler: instructions, invalid encodings, EVEX-encoded ones.
fn iced_decode(object: &[u8]) -> String {
    use iced_x86::{Decoder, DecoderOptions};
    use object::{Object, ObjectSection};
    let file = object::File::parse(object).unwrap();
    let (mut n, mut invalid, mut evex) = (0, 0, 0);
    for s in file.sections().filter(|s| s.kind() == object::SectionKind::Text) {
        let bytes = s.data().unwrap();
        for i in Decoder::with_ip(64, bytes, 0, DecoderOptions::NONE) {
            n += 1;
            invalid += i.is_invalid() as usize;
            // The EVEX prefix byte (LLVM emits no legacy prefix before it here).
            evex += (bytes[i.ip() as usize] == 0x62) as usize;
        }
    }
    format!("iced: {n} insts, {invalid} invalid, {evex} EVEX")
}

const X86_TYPES: &str = r#"
#include <sys/mman.h>
#include <time.h>
struct kernel { const char *name; void *llvm[2]; const unsigned char *image; size_t size; void *oracle; const char *type; };
"#;

const X86_MAIN: &str = r#"
typedef void (*map_fn)(double *, const double *, double, double, size_t);
typedef void (*xmap_fn)(double *, const double *, double, double, size_t, size_t);
typedef void (*refine_fn)(double *, const double *, size_t);
typedef void (*xrefine_fn)(double *, const double *, size_t, size_t);
typedef double (*dot_fn)(const double *, const double *, size_t, size_t);

static void *load(const unsigned char *code, size_t n) {
    size_t len = (n + 4095) & ~(size_t)4095;
    void *p = mmap(0, len, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
    if (p == MAP_FAILED) return 0;
    memcpy(p, code, n);
    if (mprotect(p, len, PROT_READ | PROT_EXEC) != 0) return 0;
    return p;
}

static double call(const char *name, void *f, double *out, const double *left, const double *right, size_t n) {
    if (!strcmp(name, "map")) { ((map_fn)f)(out, left, 1.25, -0.5, n); return 0; }
    if (!strcmp(name, "explicitMap")) { ((xmap_fn)f)(out, left, 1.25, -0.5, n, n); return 0; }
    if (!strcmp(name, "refine")) { ((refine_fn)f)(out, left, n); return 0; }
    if (!strcmp(name, "explicitRefine")) { ((xrefine_fn)f)(out, left, n, n); return 0; }
    return ((dot_fn)f)(left, right, n, n);
}

static double now_ns(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec * 1e9 + t.tv_nsec; }
static double left[65539], right[65539], a[65543], b[65543];

static int same(const char *name, const char *who, void *ours, void *oracle) {
    size_t sizes[21]; int ns = 0;
    for (size_t n = 0; n < 18; n++) sizes[ns++] = n;
    sizes[ns++] = 63; sizes[ns++] = 1000; sizes[ns++] = 65539;
    for (int s = 0; s < ns; s++) {
        size_t n = sizes[s];
        for (size_t i = 0; i < n; i++) { left[i] = (double)(i % 97 + 1) * 0.125; right[i] = (double)(i % 17 + 1) * 0.0625; }
        for (size_t i = 0; i < n + 4; i++) { a[i] = -777.0; b[i] = -777.0; }
        double ra = call(name, ours, a, left, right, n);
        double rb = call(name, oracle, b, left, right, n);
        for (size_t i = 0; i < n + 4; i++)
            if (memcmp(&a[i], &b[i], sizeof a[i]) != 0) {
                printf("FAIL %s %s n=%zu element %zu: ours %.17g C %.17g\n", name, who, n, i, a[i], b[i]);
                return 0;
            }
        double tol = 1e-12 * (fabs(rb) > 1 ? fabs(rb) : 1);
        if (fabs(ra - rb) > tol) { printf("FAIL %s %s n=%zu result ours %.17g C %.17g\n", name, who, n, ra, rb); return 0; }
    }
    return 1;
}

static int cmpd(const void *x, const void *y) { double p = *(const double *)x, q = *(const double *)y; return p < q ? -1 : p > q; }

int main(void) {
    int failures = 0;
    for (size_t k = 0; k < sizeof kernels / sizeof kernels[0]; k++) {
        const struct kernel *kn = &kernels[k];
        void *direct = load(kn->image, kn->size);
        void *fs[4] = {kn->llvm[0], kn->llvm[1], direct, kn->oracle};
        const char *who[3] = {"llvm-O2", "llvm-O3", "direct"};
        int ok = 1;
        for (int j = 0; j < 3; j++) if (!same(kn->name, who[j], fs[j], kn->oracle)) { ok = 0; failures++; }
        if (!ok) continue;
        printf("PASS %-18s llvm-O2, llvm-O3, direct bit-identical to C, n=0..17,63,1000,65539\n", kn->name);
        size_t sizes[3] = {63, 1000, 65539};
        for (int si = 0; si < 3; si++) {
            size_t n = sizes[si];
            size_t repeats = 2000000 / n; if (repeats < 1) repeats = 1;
            double samples[4][21];
            for (int w = 0; w < 3; w++) for (int j = 0; j < 4; j++) { for (size_t r = 0; r < repeats; r++) call(kn->name, fs[j], a, left, right, n); }
            for (int s = 0; s < 21; s++)
                for (int q = 0; q < 4; q++) {
                    int j = (s + q) % 4;
                    double t = now_ns();
                    for (size_t r = 0; r < repeats; r++) call(kn->name, fs[j], a, left, right, n);
                    samples[j][s] = (now_ns() - t) / repeats;
                }
            double med[4];
            for (int j = 0; j < 4; j++) { qsort(samples[j], 21, sizeof(double), cmpd); med[j] = samples[j][10]; }
            printf("TIME %-18s n=%-6zu C %9.1f ns  O2/C %.2f  O3/C %.2f  direct/C %.2f\n", kn->name, n, med[3], med[0] / med[3], med[1] / med[3], med[2] / med[3]);
            fflush(stdout);
        }
    }
    printf("DONE failures %d\n", failures);
    return failures != 0;
}
"#;

// ---- Wasm --------------------------------------------------------------------

pub fn wasm(path: &str, out_dir: &str) {
    let doc: J = serde_json::from_str(&std::fs::read_to_string(path).unwrap()).unwrap();
    std::fs::create_dir_all(out_dir).unwrap();
    let level = level_from_env();
    let tm = llvm::target_machine(Tier::Wasm32Simd, level);
    let mut objects = Vec::new();
    let mut exports = Vec::new();
    for name in crate::KERNELS {
        let t = Instant::now();
        let (f, sig) = kernel_lir(&doc, name, llvm::LANES).unwrap();
        let noalias = llvm::exclusive_params(&function(&doc, name)["tree"], &sig);
        let m = llvm::build(&f, name, &Shape::Kernel { sig: &sig, noalias }, Tier::Wasm32Simd);
        m.optimize(tm, level);
        let object = m.object(tm);
        let o = format!("{out_dir}/{name}.o");
        std::fs::write(&o, &object).unwrap();
        std::fs::write(format!("{out_dir}/{name}.s"), m.assembly(tm)).unwrap();
        println!("{name}: wasm object {} B, compile {:.0}us", object.len(), us(t));
        objects.push(o);
        exports.push(format!("--export={name}"));
    }
    let lld = std::env::var("NUPP_SPIKE_WASM_LD").unwrap_or_else(|_| "/opt/homebrew/opt/lld/bin/wasm-ld".into());
    let out = format!("{out_dir}/kernels.wasm");
    let t = Instant::now();
    // Data and stack above the test harness's arrays, which start at 0.
    let status = Command::new(&lld)
        .args(["--no-entry", "--global-base=4194304", "--initial-memory=8388608", "-o", &out])
        .args(&exports)
        .args(&objects)
        .status()
        .unwrap();
    assert!(status.success());
    println!("{out}: {} B, linked by wasm-ld in {:.0}us (a process)", std::fs::metadata(&out).unwrap().len(), us(t));
}
