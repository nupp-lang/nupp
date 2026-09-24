//! A stand-in for the Nupp host on the consuming side of the AOT cache. It
//! links no LLVM. On a miss it starts the component (`nupp-llvm`) and waits
//! for the cache entry; on a hit it never touches the component. Either way
//! it loads the entry with the platform loader and calls into it.
//!
//! `run`    one miss-or-hit and a first call; prints the timeline as JSON.
//! `bench`  `run` in fresh processes, cold (entry removed) or warm.
//! `check`  every correctness check through the cached library, and the
//!          no-unwind-tables negative control.
//! `time`   run time against the C backend, one library per `--isel`.

mod harness;
mod sys;

use serde_json::{Value as J, json};
use sha2::{Digest, Sha256};
use std::path::{Path, PathBuf};
use std::process::Command;
use sys::{Lib, now_ns};

/// What the key must change with besides the inputs: the component's
/// compiler (LLVM, the lowering) and its version.
const COMPONENT_ID: &str = "nupp-llvm/llvm-23.1.1/lowering-1";

struct Config {
    args: Vec<String>,
}

impl Config {
    fn value(&self, flag: &str) -> Option<String> {
        self.args.iter().position(|a| a == flag).map(|i| self.args[i + 1].clone())
    }
    fn values(&self, flag: &str) -> Vec<String> {
        self.args.iter().enumerate().filter(|(_, a)| *a == flag).map(|(i, _)| self.args[i + 1].clone()).collect()
    }
    fn need(&self, flag: &str) -> String {
        self.value(flag).unwrap_or_else(|| panic!("missing {flag}"))
    }
    fn has(&self, flag: &str) -> bool {
        self.args.iter().any(|a| a == flag)
    }
    fn target(&self) -> String {
        self.value("--target").unwrap_or_else(|| {
            if cfg!(target_os = "macos") {
                "arm64-apple-macosx11.0.0".into()
            } else if cfg!(windows) {
                "x86_64-w64-windows-gnu".into()
            } else {
                "x86_64-unknown-linux-gnu".into()
            }
        })
    }
    fn library_name(&self) -> &'static str {
        if cfg!(target_os = "macos") {
            "module.dylib"
        } else if cfg!(windows) {
            "module.dll"
        } else {
            "module.so"
        }
    }
}

/// What the host has before any AOT code: LuaJIT and its runtime.
fn load_runtime(cfg: &Config) -> u32 {
    Lib::open(&cfg.need("--luajit"), true).unwrap();
    Lib::open(&cfg.need("--runtime"), true).unwrap();
    let size: unsafe extern "C" fn() -> usize = unsafe { std::mem::transmute(sys::global("ks_rt_builder_size")) };
    unsafe { size() as u32 }
}

/// The content key: every input byte and every setting the output depends on.
fn key(cfg: &Config, isel: &str, tables: bool, builder_size: u32) -> String {
    let mut h = Sha256::new();
    for part in [COMPONENT_ID, &cfg.target(), isel, if tables { "tables" } else { "no-tables" }, &builder_size.to_string()] {
        h.update(part.as_bytes());
        h.update([0]);
    }
    for rule in cfg.values("--import") {
        h.update(rule.as_bytes());
        h.update([0]);
    }
    for f in ["--kernels", "--builders"] {
        h.update(std::fs::read(cfg.need(f)).unwrap());
        h.update([0]);
    }
    h.finalize().iter().map(|b| format!("{b:02x}")).collect()
}

struct Entry {
    lib: Lib,
    path: PathBuf,
    hit: bool,
    component: J,
    keyed: u64,
    compiled: u64,
    opened: u64,
}

/// The cache entry for these settings: loaded if present, built by the
/// component first if not.
fn entry(cfg: &Config, isel: &str, tables: bool, builder_size: u32) -> Entry {
    let k = key(cfg, isel, tables, builder_size);
    let keyed = now_ns();
    let dir = Path::new(&cfg.need("--cache")).join(&k);
    let path = dir.join(cfg.library_name());
    let hit = path.exists();
    let mut component = J::Null;
    if !hit {
        std::fs::create_dir_all(cfg.need("--cache")).unwrap();
        let mut cmd = Command::new(cfg.need("--component"));
        cmd.arg("compile")
            .args(["--target", &cfg.target(), "--kernels", &cfg.need("--kernels"), "--builders", &cfg.need("--builders")])
            .args(["--builder-size", &builder_size.to_string(), "--isel", isel, "--out"])
            .arg(&dir);
        if !tables {
            cmd.arg("--no-unwind-tables");
        }
        if cfg.has("--verify") {
            cmd.arg("--verify");
        }
        for rule in cfg.values("--import") {
            cmd.args(["--import", &rule]);
        }
        let spawning = now_ns();
        let out = cmd.output().expect("start the component");
        if !out.status.success() {
            panic!("component failed: {}", String::from_utf8_lossy(&out.stderr));
        }
        component = serde_json::from_slice(&out.stdout).unwrap_or(J::Null);
        component["spawning"] = J::from(spawning);
    }
    let compiled = now_ns();
    let lib = Lib::open(path.to_str().unwrap(), false).unwrap_or_else(|e| panic!("load {}: {e}", path.display()));
    let opened = now_ns();
    Entry { lib, path, hit, component, keyed, compiled, opened }
}

fn isel(cfg: &Config) -> String {
    cfg.value("--isel").unwrap_or("dag".into())
}

fn run(cfg: &Config, entered: u64) {
    let size = load_runtime(cfg);
    let runtime = now_ns();
    let e = entry(cfg, &isel(cfg), !cfg.has("--no-unwind-tables"), size);
    let x = harness::inputs(1000);
    let mut out = vec![0.0; 1004];
    unsafe { harness::call("explicitMap", e.lib.sym("nupp_aot_explicitMap"), &x, &mut out) };
    let first = now_ns();
    assert_eq!(out[999].to_bits(), (x.left[999] * 1.25 + -0.5).to_bits());
    println!(
        "{}",
        json!({"hit": e.hit, "entered": entered, "runtime": runtime, "keyed": e.keyed, "compiled": e.compiled,
               "opened": e.opened, "firstCall": first, "component": e.component, "library": e.path})
    );
}

fn median(mut v: Vec<f64>) -> f64 {
    v.sort_by(f64::total_cmp);
    v[v.len() / 2]
}

fn uptime() -> String {
    Command::new("uptime").output().map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string()).unwrap_or_default()
}

/// `run` in fresh processes. Cold removes the whole cache before each one.
fn bench(cfg: &Config) {
    let runs: usize = cfg.value("--runs").map(|r| r.parse().unwrap()).unwrap_or(21);
    let cold = cfg.has("--cold");
    let me = std::env::current_exe().unwrap();
    let mut pass: Vec<String> = Vec::new();
    let mut i = 0;
    while i < cfg.args.len() {
        match cfg.args[i].as_str() {
            "--runs" => i += 2,
            "--cold" | "--warm" => i += 1,
            a => {
                pass.push(a.to_string());
                i += 1;
            }
        }
    }
    let before = uptime();
    let mut rows: Vec<J> = Vec::new();
    // Warm: one run fills the entry first, and is not counted.
    if !cold {
        Command::new(&me).arg("run").args(&pass).output().unwrap();
    }
    for _ in 0..runs {
        if cold {
            let _ = std::fs::remove_dir_all(cfg.need("--cache"));
        }
        let spawned = now_ns();
        let out = Command::new(&me).arg("run").args(&pass).output().unwrap();
        let exited = now_ns();
        assert!(out.status.success(), "{}", String::from_utf8_lossy(&out.stderr));
        let mut r: J = serde_json::from_slice(&out.stdout).unwrap();
        assert_eq!(r["hit"].as_bool().unwrap(), !cold);
        r["spawned"] = J::from(spawned);
        r["exited"] = J::from(exited);
        rows.push(r);
    }
    let ms = |r: &J, from: &str, to: &str| (r[to].as_u64().unwrap() as f64 - r[from].as_u64().unwrap() as f64) / 1e6;
    let col = |f: &dyn Fn(&J) -> f64| median(rows.iter().map(f).collect());
    let spread = |f: &dyn Fn(&J) -> f64| {
        let mut v: Vec<f64> = rows.iter().map(f).collect();
        v.sort_by(f64::total_cmp);
        (v[0], v[v.len() - 1])
    };
    let total = |r: &J| ms(r, "spawned", "firstCall");
    let (lo, hi) = spread(&total);
    let mut report = json!({
        "mode": if cold { "cold miss" } else { "warm hit" }, "runs": runs, "isel": isel(cfg),
        "uptimeBefore": before, "uptimeAfter": uptime(),
        "spawnToFirstCallMs": {"median": col(&total), "min": lo, "max": hi},
        "spawnToExitMs": col(&|r| ms(r, "spawned", "exited")),
        "phasesMs": {
            "spawnToMain": col(&|r| ms(r, "spawned", "entered")),
            "loadLuaJITAndRuntime": col(&|r| ms(r, "entered", "runtime")),
            "key": col(&|r| ms(r, "runtime", "keyed")),
            "missHandled": col(&|r| ms(r, "keyed", "compiled")),
            "loadEntry": col(&|r| ms(r, "compiled", "opened")),
            "firstCall": col(&|r| ms(r, "opened", "firstCall")),
        },
    });
    if cold {
        let c = |f: &str| median(rows.iter().map(|r| r["component"]["timing"][f].as_f64().unwrap() / 1e3).collect());
        report["componentMs"] = json!({
            "spawnToMain": col(&|r| (r["component"]["timing"]["entered"].as_u64().unwrap() as f64 - r["component"]["spawning"].as_u64().unwrap() as f64) / 1e6),
            "readInputs": c("readInputs"), "targetMachine": c("targetMachine"), "irgen": c("irgen"),
            "optimize": c("optimize"), "codegen": c("codegen"), "writeObject": c("writeObject"),
            "link": c("link"), "rename": c("rename"),
            "exitToHost": col(&|r| (r["compiled"].as_u64().unwrap() as f64 - r["component"]["timing"]["exited"].as_u64().unwrap() as f64) / 1e6),
        });
        report["libraryBytes"] = rows[0]["component"]["timing"]["libraryBytes"].clone();
        report["objectBytes"] = rows[0]["component"]["timing"]["objectBytes"].clone();
    }
    println!("{}", serde_json::to_string_pretty(&report).unwrap());
}

fn registrar(builders: &J) -> String {
    let c = builders["c"].as_str().unwrap();
    c.lines().find(|l| l.starts_with("KS_API int ks_register_")).map(|l| l["KS_API int ".len()..l.find('(').unwrap()].to_string()).unwrap()
}

/// Fused multiply-adds in the loaded library's code, decoded without LLVM.
fn fused_in(path: &Path) -> (usize, Vec<String>) {
    use object::{Object, ObjectSection};
    let bytes = std::fs::read(path).unwrap();
    let file = object::File::parse(&*bytes).unwrap();
    let mut n = 0;
    let mut fused = Vec::new();
    for s in file.sections().filter(|s| s.kind() == object::SectionKind::Text) {
        let code = s.data().unwrap();
        if file.architecture() == object::Architecture::Aarch64 {
            use yaxpeax_arch::{Decoder, U8Reader};
            let d = yaxpeax_arm::armv8::a64::InstDecoder::default();
            for w in code.chunks(4) {
                if let Ok(i) = d.decode(&mut U8Reader::new(w)) {
                    n += 1;
                    let t = i.to_string();
                    let op = t.split_whitespace().next().unwrap_or("");
                    if ["fmadd", "fmsub", "fnmadd", "fnmsub", "fmla", "fmls"].contains(&op) {
                        fused.push(t);
                    }
                }
            }
        } else {
            use iced_x86::{Decoder, DecoderOptions, Formatter, IntelFormatter};
            let mut f = IntelFormatter::new();
            for i in Decoder::with_ip(64, code, 0, DecoderOptions::NONE) {
                n += 1;
                let mut t = String::new();
                f.format(&i, &mut t);
                if t.starts_with("vfmadd") || t.starts_with("vfnmadd") || t.starts_with("vfmsub") || t.starts_with("vfnmsub") {
                    fused.push(t);
                }
            }
        }
    }
    (n, fused)
}

fn unwind_sections(path: &Path) -> Vec<String> {
    use object::{Object, ObjectSection};
    let bytes = std::fs::read(path).unwrap();
    let file = object::File::parse(&*bytes).unwrap();
    file.sections()
        .filter_map(|s| Some((s.name().ok()?.to_string(), s.size())))
        .filter(|(n, _)| n.contains("unwind") || n.contains("eh_frame") || n == ".pdata" || n == ".xdata")
        .map(|(n, size)| format!("{n} ({size} B)"))
        .collect()
}

fn check(cfg: &Config) {
    let size = load_runtime(cfg);
    let builders: J = serde_json::from_str(&std::fs::read_to_string(cfg.need("--builders")).unwrap()).unwrap();
    let kernels: J = serde_json::from_str(&std::fs::read_to_string(cfg.need("--kernels")).unwrap()).unwrap();
    let e = entry(cfg, &isel(cfg), true, size);
    println!("library {} ({}; {} B)", e.path.display(), if e.hit { "hit" } else { "miss, compiled" }, std::fs::metadata(&e.path).unwrap().len());
    if let Some(v) = e.component.get("irContract") {
        println!("component: IR contract violations {v}; fused in assembly {}; reassoc sites {}", e.component["fusedInstructions"], e.component["reassocSites"]);
    }
    let oracle = Lib::open(&cfg.need("--oracle"), false).unwrap();
    let mut failures = 0;
    for name in harness::KERNELS {
        let symbol = kernels["functions"].as_array().unwrap().iter().find(|f| f["name"] == *name).unwrap()["symbol"].as_str().unwrap().to_string();
        let r = harness::check_kernel(name, e.lib.sym(&format!("nupp_aot_{name}")), oracle.sym(&symbol));
        println!("  {name:<18} {}", match &r {
            Ok(()) => "bit-identical to C, n = 0..17, 63, 1000, 65539".to_string(),
            Err(m) => format!("DIFFER {m}"),
        });
        failures += r.is_err() as usize;
    }
    let waves: harness::Waves = unsafe { std::mem::transmute(e.lib.sym("nupp_aot_waves")) };
    let c_waves: harness::Waves = unsafe { std::mem::transmute(sys::global("ks_waves")) };
    let r = harness::check_waves(waves, c_waves);
    println!("  {:<18} {}", "waves", r.as_ref().map(|_| "bit-identical to C, n = 0..9, 1000".to_string()).unwrap_or_else(|m| format!("DIFFER {m}")));
    failures += r.is_err() as usize;
    let (insts, fused) = fused_in(&e.path);
    println!("  fused multiply-add in the library's {insts} instructions: {}", fused.len());
    failures += !fused.is_empty() as usize;
    println!("  unwind sections: {}", unwind_sections(&e.path).join(", "));
    let entries: Vec<(&str, *const u8)> = ["rows", "object", "stream"].iter().map(|n| (*n, e.lib.sym(&format!("nupp_aot_{n}")))).collect();
    let ok = harness::run_lua(&entries, &registrar(&builders), false);
    println!("lua-builder entries match C: {ok}");
    failures += !ok as usize;

    // The negative control: the same library built without unwind tables,
    // raising in a child; and the positive one, the same child on the real
    // library.
    let me = std::env::current_exe().unwrap();
    for tables in [true, false] {
        let lib = entry(cfg, &isel(cfg), tables, size).path;
        let out = Command::new(&me).arg("lua-quick").args(&cfg.args).arg("--library").arg(&lib).output().unwrap();
        let stderr = String::from_utf8_lossy(&out.stderr);
        let panicked = stderr.contains("PANIC: unprotected error");
        println!(
            "  {}: exit {:?}{}; stdout {:?}; stderr {:?}",
            if tables { "with unwind tables   " } else { "without unwind tables" },
            out.status.code(),
            signal(&out.status),
            String::from_utf8_lossy(&out.stdout).lines().last().unwrap_or(""),
            stderr.lines().last().unwrap_or("")
        );
        failures += if tables { !out.status.success() } else { !panicked } as usize;
    }
    println!("failures: {failures}");
    std::process::exit(failures as i32);
}

#[cfg(unix)]
fn signal(s: &std::process::ExitStatus) -> String {
    use std::os::unix::process::ExitStatusExt;
    s.signal().map(|n| format!(" signal {n}")).unwrap_or_default()
}
#[cfg(windows)]
fn signal(_: &std::process::ExitStatus) -> String {
    String::new()
}

fn lua_quick(cfg: &Config) {
    load_runtime(cfg);
    let builders: J = serde_json::from_str(&std::fs::read_to_string(cfg.need("--builders")).unwrap()).unwrap();
    let lib = Lib::open(&cfg.need("--library"), false).unwrap();
    let entries: Vec<(&str, *const u8)> = ["rows", "object", "stream"].iter().map(|n| (*n, lib.sym(&format!("nupp_aot_{n}")))).collect();
    let ok = harness::run_lua(&entries, &registrar(&builders), true);
    println!("quick cases match C: {ok}");
    std::process::exit(!ok as i32);
}

fn time(cfg: &Config) {
    let size = load_runtime(cfg);
    let kernels: J = serde_json::from_str(&std::fs::read_to_string(cfg.need("--kernels")).unwrap()).unwrap();
    let variants: Vec<String> = cfg.value("--variants").unwrap_or("dag,fast,global".into()).split(',').map(str::to_string).collect();
    let libs: Vec<Entry> = variants.iter().map(|v| entry(cfg, v, true, size)).collect();
    let oracle = Lib::open(&cfg.need("--oracle"), false).unwrap();
    println!("run time, ratio to C (median of 21 rotating samples); {}", uptime());
    print!("{:<18} {:>6} {:>9}", "kernel", "n", "C ns");
    for v in &variants {
        print!(" {:>8}", format!("{v}/C"));
    }
    println!();
    for name in harness::KERNELS {
        let symbol = kernels["functions"].as_array().unwrap().iter().find(|f| f["name"] == *name).unwrap()["symbol"].as_str().unwrap().to_string();
        let mut fs: Vec<*const u8> = libs.iter().map(|e| e.lib.sym(&format!("nupp_aot_{name}"))).collect();
        for (v, f) in variants.iter().zip(&fs) {
            if let Err(m) = harness::check_kernel(name, *f, oracle.sym(&symbol)) {
                println!("{name} {v}: DIFFER {m}");
            }
        }
        fs.push(oracle.sym(&symbol));
        for n in [63usize, 1000, 65539] {
            let t = harness::time_all(name, &fs, n);
            let c = t[t.len() - 1];
            print!("{name:<18} {n:>6} {c:>9.1}");
            for x in &t[..t.len() - 1] {
                print!(" {:>8.2}", x / c);
            }
            println!();
        }
    }
}

fn main() {
    let entered = now_ns();
    let mut argv: Vec<String> = std::env::args().collect();
    let mode = argv.get(1).cloned().unwrap_or_default();
    let cfg = Config { args: argv.split_off(2.min(argv.len())) };
    match mode.as_str() {
        "run" => run(&cfg, entered),
        "bench" => bench(&cfg),
        "check" => check(&cfg),
        "time" => time(&cfg),
        "lua-quick" => lua_quick(&cfg),
        _ => {
            eprintln!("usage: nupp-artifact-host run|bench|check|time ...");
            std::process::exit(2);
        }
    }
}
