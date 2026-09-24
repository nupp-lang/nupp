//! Size probe for the LLVM backend: what a product would carry (no driver,
//! no oracle, no harness), fed IR JSON so nothing is optimized away. Every
//! build compiles for arm64 and loads through LLJIT; features add x86
//! objects (AVX2, AVX-512), Wasm objects, and lld linking them in process.
#![allow(dead_code, unused_imports)]
#[path = "../../direct-backend/src/lir.rs"]
mod lir;
#[path = "../../direct-backend/src/llvm.rs"]
mod llvm;
#[path = "../../direct-backend/src/sem.rs"]
mod sem;

use llvm::{Level, Shape, Tier};
use serde_json::Value as J;

#[cfg(feature = "lld")]
unsafe extern "C" {
    fn nupp_wasm_ld(argc: i32, argv: *const *const std::ffi::c_char) -> i32;
}

const SUPPORTED: &[&str] = &["map", "refine", "explicitMap", "explicitRefine", "explicitAlgebraic", "rows", "object", "stream", "waves"];

fn main() {
    // Startup only: exec, dyld, and LLVM's static initializers.
    if std::env::var_os("NUPP_PROBE_EXIT").is_some() {
        return;
    }
    let mut total = 0usize;
    let jit = llvm::Jit::new(Tier::Arm64Neon, Level::O3, true);
    let arm = llvm::target_machine(Tier::Arm64Neon, Level::O3);
    let mut wasm_objects: Vec<Vec<u8>> = Vec::new();
    for path in std::env::args().skip(1) {
        let doc: J = serde_json::from_str(&std::fs::read_to_string(&path).unwrap_or("{}".into())).unwrap_or_default();
        let c = doc["c"].as_str().unwrap_or("");
        for f in doc["functions"].as_array().cloned().unwrap_or_default() {
            let name = f["name"].as_str().unwrap_or("");
            if !SUPPORTED.contains(&name) {
                continue;
            }
            let builder = f["entryMode"] == "lua-builder";
            let sig = if builder { sem::Signature { symbol: String::new(), params: vec![], ret: sem::Ret::Void } } else { sem::signature(c, f["symbol"].as_str().unwrap_or("")) };
            let func = if builder { lir::builder(&f["tree"], 64, llvm::LANES) } else { lir::kernel(&f["tree"], &sig, llvm::LANES) };
            let shape = if builder { Shape::LuaBuilder } else { Shape::Kernel { sig: &sig, noalias: llvm::exclusive_params(&f["tree"], &sig) } };
            let m = llvm::build(&func, name, &shape, Tier::Arm64Neon);
            m.optimize(arm, Level::O3);
            let object = m.object(arm);
            total += object.len();
            jit.add_object(&object, name);
            // Builders import the Lua C API, absent from this process: linked
            // only when looked up, so only kernels are.
            if !builder {
                total += jit.lookup(name) as usize % 2;
            }
            #[cfg(feature = "x86")]
            for tier in [Tier::X86Avx2, Tier::X86Avx512] {
                let tm = llvm::target_machine(tier, Level::O3);
                let m = llvm::build(&func, name, &shape, tier);
                m.optimize(tm, Level::O3);
                total += m.object(tm).len();
            }
            #[cfg(feature = "wasm")]
            if !builder && name != "waves" {
                let tm = llvm::target_machine(Tier::Wasm32Simd, Level::O3);
                let m = llvm::build(&func, name, &shape, Tier::Wasm32Simd);
                m.optimize(tm, Level::O3);
                wasm_objects.push(m.object(tm));
            }
        }
    }
    total += wasm_objects.iter().map(Vec::len).sum::<usize>();
    #[cfg(feature = "lld")]
    if !wasm_objects.is_empty() {
        let dir = std::env::temp_dir().join(format!("llvm-size-probe-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let mut args: Vec<String> = ["wasm-ld", "--no-entry", "--export-all", "-o"].iter().map(|s| s.to_string()).collect();
        args.push(dir.join("out.wasm").display().to_string());
        for (k, o) in wasm_objects.iter().enumerate() {
            let p = dir.join(format!("{k}.o"));
            std::fs::write(&p, o).unwrap();
            args.push(p.display().to_string());
        }
        let cargs: Vec<std::ffi::CString> = args.iter().map(|a| std::ffi::CString::new(a.as_str()).unwrap()).collect();
        let ptrs: Vec<*const std::ffi::c_char> = cargs.iter().map(|a| a.as_ptr()).collect();
        let t = std::time::Instant::now();
        let status = unsafe { nupp_wasm_ld(ptrs.len() as i32, ptrs.as_ptr()) };
        let linked = t.elapsed().as_secs_f64() * 1e6;
        let module = std::fs::read(dir.join("out.wasm")).unwrap_or_default();
        eprintln!("in-process wasm-ld: status {status}, {} B module, {linked:.0}us", module.len());
        total += module.len();
    }
    println!("{total}");
}
