//! Direct-backend spike driver: lowers selected `bench/simd11` kernels from
//! Nupp IR to AArch64, loads them without a linker, and checks and times each
//! one against the C backend's output built by clang at -O3.

mod asm;
mod emit;
mod loader;
mod lower;
mod luaphase;
mod mir;

use regalloc2::{Algorithm, RegallocOptions};
use serde_json::Value as J;
use std::ffi::CString;
use std::process::Command;
use std::time::Instant;

const KERNELS: &[&str] = &["map", "refine", "explicitMap", "explicitRefine", "explicitAlgebraic"];

type MapFn = unsafe extern "C" fn(*mut f64, *const f64, f64, f64, usize);
type ExplicitMapFn = unsafe extern "C" fn(*mut f64, *const f64, f64, f64, usize, usize);
type RefineFn = unsafe extern "C" fn(*mut f64, *const f64, usize);
type ExplicitRefineFn = unsafe extern "C" fn(*mut f64, *const f64, usize, usize);
type DotFn = unsafe extern "C" fn(*const f64, *const f64, usize, usize) -> f64;

fn c_library(c: &str, dir: &std::path::Path) -> *mut libc::c_void {
    let src = dir.join("kernels.c");
    let lib = dir.join("kernels.dylib");
    std::fs::write(&src, c).unwrap();
    let ok = Command::new("clang")
        .args(["-std=c11", "-O3", "-ffp-contract=off", "-fno-fast-math", "-fPIC", "-dynamiclib", "-o"])
        .arg(&lib)
        .arg(&src)
        .arg("-lm")
        .status()
        .unwrap();
    assert!(ok.success());
    let path = CString::new(lib.to_str().unwrap()).unwrap();
    let handle = unsafe { libc::dlopen(path.as_ptr(), libc::RTLD_NOW) };
    assert!(!handle.is_null());
    handle
}

fn symbol(handle: *mut libc::c_void, name: &str) -> *const u8 {
    let n = CString::new(name).unwrap();
    let p = unsafe { libc::dlsym(handle, n.as_ptr()) };
    assert!(!p.is_null(), "{name}");
    p as *const u8
}

/// Disassembles generated words through the system toolchain, for reading.
pub fn disassemble(code: &[u8], dir: &std::path::Path, name: &str) -> String {
    let src = dir.join(format!("{name}.s"));
    let obj = dir.join(format!("{name}.o"));
    let words: String = code
        .chunks(4)
        .map(|c| format!("  .inst 0x{:08x}\n", u32::from_le_bytes([c[0], c[1], c[2], c[3]])))
        .collect();
    std::fs::write(&src, format!(".text\n_{name}:\n{words}")).unwrap();
    assert!(Command::new("clang").args(["-c", "-arch", "arm64", "-o"]).arg(&obj).arg(&src).status().unwrap().success());
    let out = Command::new("otool").args(["-tvV"]).arg(&obj).output().unwrap();
    String::from_utf8(out.stdout).unwrap()
}

struct Inputs {
    left: Vec<f64>,
    right: Vec<f64>,
}

fn inputs(n: usize) -> Inputs {
    Inputs {
        left: (0..n).map(|i| ((i % 97) + 1) as f64 * 0.125).collect(),
        right: (0..n).map(|i| ((i % 17) + 1) as f64 * 0.0625).collect(),
    }
}

/// Runs one kernel once into `out` and returns its scalar result, if any.
unsafe fn call(name: &str, f: *const u8, x: &Inputs, out: &mut [f64]) -> f64 {
    let n = x.left.len();
    unsafe {
        match name {
            "map" => {
                std::mem::transmute::<*const u8, MapFn>(f)(out.as_mut_ptr(), x.left.as_ptr(), 1.25, -0.5, n);
                0.0
            }
            "explicitMap" => {
                std::mem::transmute::<*const u8, ExplicitMapFn>(f)(out.as_mut_ptr(), x.left.as_ptr(), 1.25, -0.5, n, n);
                0.0
            }
            "refine" => {
                std::mem::transmute::<*const u8, RefineFn>(f)(out.as_mut_ptr(), x.left.as_ptr(), n);
                0.0
            }
            "explicitRefine" => {
                std::mem::transmute::<*const u8, ExplicitRefineFn>(f)(out.as_mut_ptr(), x.left.as_ptr(), n, n);
                0.0
            }
            "explicitAlgebraic" => {
                std::mem::transmute::<*const u8, DotFn>(f)(x.left.as_ptr(), x.right.as_ptr(), n, n)
            }
            _ => unreachable!(),
        }
    }
}

fn check(name: &str, ours: *const u8, theirs: *const u8) {
    for n in (0..18).chain([63, 1000, 65539]) {
        let x = inputs(n);
        let mut a = vec![-777.0; n + 4];
        let mut b = vec![-777.0; n + 4];
        let (ra, rb) = unsafe { (call(name, ours, &x, &mut a), call(name, theirs, &x, &mut b)) };
        for i in 0..n + 4 {
            assert!(a[i].to_bits() == b[i].to_bits(), "{name} n={n} element {i}: ours {} C {}", a[i], b[i]);
        }
        let tolerance = 1e-12 * rb.abs().max(1.0);
        assert!((ra - rb).abs() <= tolerance, "{name} n={n}: ours {ra} C {rb}");
    }
}

fn time(name: &str, ours: *const u8, theirs: *const u8, n: usize) -> (f64, f64) {
    let x = inputs(n);
    let mut out = vec![0.0; n + 4];
    let repeats = (2_000_000 / n.max(1)).max(1);
    let run = |f: *const u8, out: &mut [f64]| {
        let start = Instant::now();
        let mut sink = 0.0;
        for _ in 0..repeats {
            sink += unsafe { call(name, std::hint::black_box(f), &x, out) };
        }
        std::hint::black_box(sink);
        start.elapsed().as_secs_f64() * 1e9 / repeats as f64
    };
    for _ in 0..3 {
        run(ours, &mut out);
        run(theirs, &mut out);
    }
    let (mut a, mut b) = (Vec::new(), Vec::new());
    for s in 0..21 {
        if s % 2 == 0 {
            a.push(run(ours, &mut out));
            b.push(run(theirs, &mut out));
        } else {
            b.push(run(theirs, &mut out));
            a.push(run(ours, &mut out));
        }
    }
    a.sort_by(f64::total_cmp);
    b.sort_by(f64::total_cmp);
    (a[a.len() / 2], b[b.len() / 2])
}

/// Instruction count of one function in the clang-built library.
fn c_words(dir: &std::path::Path, symbol: &str) -> usize {
    let out = Command::new("otool").args(["-tvV"]).arg(dir.join("kernels.dylib")).output().unwrap();
    let text = String::from_utf8(out.stdout).unwrap();
    let mut counting = false;
    let mut n = 0;
    for line in text.lines() {
        if line.ends_with(':') && !line.starts_with('0') {
            counting = line.trim_end_matches(':') == format!("_{symbol}");
            continue;
        }
        if counting && line.starts_with('0') {
            n += 1;
        }
    }
    n
}

fn main() {
    if std::env::args().nth(1).as_deref() == Some("lua") {
        let path = std::env::args().nth(2).expect("builders.json");
        luaphase::run(&path);
        if std::env::var("NUPP_SPIKE_NO_CFI").is_err() {
            luaphase::without_cfi(&path);
        }
        return;
    }
    let path = std::env::args().nth(1).expect("kernels.json");
    let dump = std::env::args().nth(2);
    let doc: J = serde_json::from_str(&std::fs::read_to_string(&path).unwrap()).unwrap();
    let c = doc["c"].as_str().unwrap();
    let dir = std::env::temp_dir().join(format!("nupp-spike-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let handle = c_library(c, &dir);
    let env = emit::machine_env();

    println!(
        "{:<18} {:>6} {:>6} {:>5} {:>5} {:>8} {:>6} {:>10} {:>10} {:>7}",
        "kernel", "words", "Cwords", "spill", "moves", "compile", "n", "ours ns", "C ns", "ours/C"
    );
    for name in KERNELS {
        let function = doc["functions"].as_array().unwrap().iter().find(|f| f["name"] == *name).unwrap();
        let program = &function["tree"];
        let sig = lower::signature(c, function["symbol"].as_str().unwrap());
        let started = Instant::now();
        let func = lower::lower(program, &sig);
        let options = RegallocOptions { verbose_log: false, validate_ssa: true, algorithm: Algorithm::Ion };
        let output = regalloc2::run(&func, &env, &options).unwrap_or_else(|e| panic!("{name}: {e:?}"));
        let (code, stats) = emit::emit(&func, &output);
        let compile_us = started.elapsed().as_secs_f64() * 1e6;
        let image = loader::Image::load(&code);
        let theirs = symbol(handle, &sig.symbol);
        if dump.as_deref() == Some(*name) {
            println!("{}", disassemble(&code, &dir, name));
        }
        check(name, image.entry(), theirs);
        let c_count = c_words(&dir, &sig.symbol);
        for n in [63usize, 1000, 65539] {
            let (ours, theirs_ns) = time(name, image.entry(), theirs, n);
            println!(
                "{:<18} {:>6} {:>6} {:>5} {:>5} {:>6.0}us {:>6} {:>10.1} {:>10.1} {:>7.2}",
                name, stats.words, c_count, stats.spill_slots, stats.moves, compile_us, n, ours, theirs_ns,
                ours / theirs_ns
            );
        }
        let _ = stats.saved;
    }
}
