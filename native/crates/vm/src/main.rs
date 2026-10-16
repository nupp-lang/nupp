//! `nupp-vm run IMAGE MODULE FUNCTION [ARG...]`: loads an image, requires a
//! module, calls one of its functions on a task and prints the results.
//! An argument `@path` is that file's text, a number is a number, anything
//! else is a string. `--repeat N` times the call N times and reports the
//! median; `--host` starts the host services. The collector's verification
//! modes come from the environment: GC_STRESS, GC_INTERLEAVE, GC_ORACLE,
//! GC_QUARANTINE.

mod executable_allocator;

use nupp_vm::builtins;
use nupp_vm::heap::KIND_NAMES;
use nupp_vm::host::Host;
use nupp_vm::image;
use nupp_vm::interp::{Interp, Outcome, State};
use nupp_vm::value::Value;
#[cfg(feature = "aot")]
use sha2::Digest;

#[cfg(feature = "aot-linked")]
mod aot_link { include!(concat!(env!("OUT_DIR"), "/aot_entries.rs")); }
#[cfg(feature = "aot-linked")]
const _: () = assert!(aot_link::ABI_VERSION == nupp_vm::compiled::AOT_ABI);

#[cfg(feature = "aot")]
fn emit_object(image_path: &str, output_path: &str, frames: bool) {
    let text = std::fs::read_to_string(image_path).unwrap();
    let mut it = Interp::new();
    image::load(&mut it, &text).unwrap();
    let mut compiler = nupp_vm::jit::Compiler::<cranelift_object::ObjectModule>::new_object();
    compiler.callee_info = it.funcs.iter().map(|f| (f.nparams, f.sig.iter().all(|&c| c == b'v') && f.ret != b'f' && !f.vararg)).collect();
    let (mut compiled, mut refused) = (Vec::new(), Vec::new());
    for (fid, f) in it.funcs.iter().enumerate() {
        if !frames && f.name.starts_with("module:") { continue; }
        match compiler.try_compile_object_mode(f, fid as u32, frames) {
            Ok(()) => compiled.push(fid),
            Err(e) => refused.push(format!("{fid}\t{}\t{e}", f.name)),
        }
        if fid != 0 && fid % 250 == 0 { eprintln!("aot: lowered {fid}/{} functions", it.funcs.len()); }
    }
    // A no-JIT runtime runs vector code only through this object, so every
    // function holding it must compile now, not fail at its first call.
    let missing: Vec<String> = it.funcs.iter().enumerate()
        .filter(|(fid, f)| image::needs_native(f) && (!frames || !compiled.contains(fid)))
        .map(|(fid, f)| format!("{fid}\t{}\t{}", f.name, f.module)).collect();
    if !missing.is_empty() {
        for r in &refused { eprintln!("aot: refused {r}"); }
        eprintln!("aot: {} function{} with vector instructions did not compile{}; a no-JIT runtime cannot run them:", missing.len(), if missing.len() == 1 { "" } else { "s" }, if frames { "" } else { " (vector code needs --frames)" });
        for m in &missing { eprintln!("aot: uncompiled {m}"); }
        std::process::exit(1);
    }
    let hash: [u8; 32] = sha2::Sha256::digest(text.as_bytes()).into();
    let mut linked = format!("pub const ABI_VERSION: u32 = {};\nunsafe extern \"C\" {{\n", nupp_vm::compiled::AOT_ABI);
    for fid in &compiled {
        linked.push_str(&format!("    fn nupp_aot_{fid}();\n"));
        let f = &it.funcs[*fid];
        if !frames && (f.ret == b'f' || f.sig.iter().any(|&c| c == b'f')) {
            linked.push_str(&format!("    fn nupp_aot_{fid}_boxed();\n"));
        }
    }
    linked.push_str(&format!("}}\npub fn image_hash() -> [u8; 32] {{ {hash:?} }}\npub fn entries() -> Vec<(usize, u64)> {{ vec![\n"));
    for fid in &compiled {
        let f = &it.funcs[*fid];
        let suffix = if !frames && (f.ret == b'f' || f.sig.iter().any(|&c| c == b'f')) { "_boxed" } else { "" };
        linked.push_str(&format!("    ({fid}, nupp_aot_{fid}{suffix} as *const () as usize as u64),\n"));
    }
    if frames { linked = linked.replace("pub fn entries()", "pub fn frame_entries()"); linked.push_str("] }\npub fn entries() -> Vec<(usize, u64)> { vec![] }\n"); }
    else { linked.push_str("] }\npub fn frame_entries() -> Vec<(usize, u64)> { vec![] }\n"); }
    linked.push_str("pub fn maps() -> Vec<(usize, usize, Vec<(u32, u32, Vec<u32>)>)> {\n");
    linked.push_str("    let starts: std::collections::HashMap<u32, usize> = [\n");
    for (fid, _, _) in &compiler.object_maps {
        linked.push_str(&format!("        ({fid}, nupp_aot_{fid} as *const () as usize),\n"));
    }
    linked.push_str("    ].into_iter().collect();\n");
    let map_path = std::path::absolute(format!("{output_path}.maps")).unwrap();
    linked.push_str(&format!("    let data = include_bytes!({:?});\n", map_path));
    linked.push_str("    let mut pos = 0usize;\n    let mut next = || { let n = u32::from_le_bytes(data[pos..pos + 4].try_into().unwrap()); pos += 4; n };\n    let count = next();\n    let mut out = Vec::with_capacity(count as usize);\n    for _ in 0..count {\n        let fid = next(); let len = next() as usize; let nmap = next();\n        let mut maps = Vec::with_capacity(nmap as usize);\n        for _ in 0..nmap { let off = next(); let span = next(); let nslots = next(); let slots = (0..nslots).map(|_| next()).collect(); maps.push((off, span, slots)); }\n        out.push((starts[&fid], len, maps));\n    }\n    out\n}\n");
    let mut map_bytes = Vec::new();
    let mut push = |n: u32| map_bytes.extend_from_slice(&n.to_le_bytes());
    push(compiler.object_maps.len() as u32);
    for (fid, len, maps) in &compiler.object_maps {
        push(*fid); push(*len as u32); push(maps.len() as u32);
        for (off, span, slots) in maps {
            push(*off); push(*span); push(slots.len() as u32);
            for slot in slots { push(*slot); }
        }
    }
    eprintln!("aot: writing object");
    let bytes = compiler.emit();
    std::fs::write(output_path, &bytes).unwrap();
    std::fs::write(format!("{output_path}.rs"), linked).unwrap();
    std::fs::write(format!("{output_path}.maps"), map_bytes).unwrap();
    let symbols: Vec<String> = compiled.iter().map(|fid| {
        let f = &it.funcs[*fid];
        let suffix = if !frames && (f.ret == b'f' || f.sig.iter().any(|&c| c == b'f')) { "_boxed" } else { "" };
        format!("{fid}\tnupp_aot_{fid}{suffix}")
    }).collect();
    let hex: String = hash.iter().map(|b| format!("{b:02x}")).collect();
    let abi = nupp_vm::compiled::AOT_ABI;
    let manifest = format!("runtime-abi\t{abi}\nimage-sha256\t{hex}\nfunctions\t{}\n{}\n", it.funcs.len(), symbols.join("\n"));
    std::fs::write(format!("{output_path}.manifest"), manifest).unwrap();
    eprintln!("aot: emitted {} functions ({} bytes), refused {}", compiled.len(), bytes.len(), refused.len());
    for r in refused { eprintln!("aot: refused {r}"); }
}

fn cpu_now() -> f64 { std::time::Instant::now().elapsed().as_secs_f64() + START.with(|s| s.elapsed().as_secs_f64()) }
thread_local! { static START: std::time::Instant = std::time::Instant::now(); }

fn emit_allocator_metrics(reason: &str) {
    #[cfg(feature = "allocation-metrics")]
    if executable_allocator::enabled() {
        let snapshot = executable_allocator::snapshot();
        use std::io::Write;
        let _ = writeln!(std::io::stderr().lock(), "global_allocation_stats {}", serde_json::json!({"reason": reason, "stats": snapshot}));
    }
    #[cfg(not(feature = "allocation-metrics"))]
    let _ = reason;
}

/// Runs the tasks to completion, delivering host completions as they arrive.
fn drive(it: &mut Interp, ts: &[usize]) {
    loop {
        let mut progressed = false;
        for &t in ts { if it.tasks[t].state == State::Runnable { it.run(t); progressed = true; } }
        loop { let next = match it.host.as_mut() { Some(h) => h.poll(), None => None }; match next { Some((k, d)) => { it.complete(k, d); progressed = true; } None => break } }
        if ts.iter().all(|&t| it.tasks[t].state == State::Done) { break; }
        if !progressed {
            let next = match it.host.as_mut() { Some(h) => h.wait(), None => None };
            match next { Some((k, d)) => it.complete(k, d), None => panic!("every task is parked and nothing is outstanding") }
        }
    }
}

/// Native extension resources save and restore through their types' hooks;
/// a restore reloads each extension's library before its resources.
fn extension_codecs() -> nupp_vm::persist::ResourceCodecs {
    let mut codecs = nupp_vm::persist::ResourceCodecs::new();
    codecs.insert(nupp_vm::extension::RESOURCE_KIND.into(), Box::new(nupp_vm::extension::Codec::default()));
    codecs
}

fn show(it: &Interp, v: Value) -> String {
    if let Some(i) = nupp_vm::numeric::integer(v) { return i.magnitude().to_string(); }
    if v.is_num() { return builtins::num_text(v.as_num()); }
    if v == Value::NIL { return "nil".into(); }
    if v == Value::TRUE { return "true".into(); }
    if v == Value::FALSE { return "false".into(); }
    if it.is_stringish(v) { return format!("{:?}", String::from_utf8_lossy(it.bytes_of(v))); }
    match it.kind_of(v) { Some(k) => KIND_NAMES[k as usize].to_string(), None => format!("{:#x}", v.0) }
}

fn main() {
    // Raises travel as panics between catch points; the default hook would
    // print each one. The runner reports the one that reaches it.
    if std::env::var("RUST_BACKTRACE").is_err() { std::panic::set_hook(Box::new(|_| {})); }
    let mut args: Vec<String> = std::env::args().collect();
    // A runtime with a program appended is that program. Every argument is the
    // program's; none is read as a runner control.
    let mut program = match std::env::current_exe().ok().map(|exe| nupp_vm::payload::read(&exe)) {
        Some(Ok(found)) => found,
        Some(Err(problem)) => { eprintln!("{}: {problem}", args.first().map(String::as_str).unwrap_or("nupp")); std::process::exit(1) }
        None => None,
    };
    let stamped = program.is_some();
    if let Some(found) = &program {
        let forwarded = args.split_off(1);
        args.extend(["exec".to_string(), "<appended>".to_string(), found.entry.clone()]);
        args.extend(forwarded);
    }
    // An executable entry receives argv as strings and returns the process
    // status. Runner controls never consume the application's arguments.
    let executable = args.get(1).map(String::as_str) == Some("exec");
    if executable {
        if args.len() < 4 { eprintln!("usage: nupp-vm exec IMAGE MODULE [ARG...]"); std::process::exit(2); }
        args[1] = "run".into();
        args.insert(4, "main".into());
    }
    #[cfg(feature = "aot")]
    if (args.len() == 4 || args.len() == 5 && args[4] == "--frames") && args[1] == "aot" { emit_object(&args[2], &args[3], args.len() == 5); return; }
    if args.len() == 3 && args[1] == "verify" {
        let text = std::fs::read_to_string(&args[2]).unwrap_or_else(|e| { eprintln!("image {}: {e}", args[2]); std::process::exit(1) });
        let mut it = Interp::new();
        image::load(&mut it, &text).unwrap_or_else(|e| { eprintln!("load: {e}"); std::process::exit(1) });
        println!("verified {} functions", it.funcs.len());
        return;
    }
    if args.len() < 5 || (args[1] != "run" && args[1] != "restore") { eprintln!("usage: nupp-vm (run IMAGE | restore CHECKPOINT) MODULE FUNCTION [ARG...] [--repeat N] [--host] [--setup FN] [--load IMAGE] [--checkpoint FILE] [--output FILE] [--tasks]"); std::process::exit(2); }
    let restoring = args[1] == "restore";
    let mut checkpoint: Option<String> = None;
    // `--output FILE`: the first result, a string, written there byte for byte
    // rather than shown quoted, which is lossy for bytes that are not UTF-8.
    let mut output: Option<String> = None;
    let mut scheduled = executable;
    let mut repeat = 0usize; let mut host = false; let mut setup: Option<String> = None; let mut call_args_text: Vec<String> = Vec::new(); let mut additional_images: Vec<String> = Vec::new();
    let mut i = 5;
    while i < args.len() {
        if executable { call_args_text.extend_from_slice(&args[i..]); break; }
        match args[i].as_str() {
            "--tasks" => { scheduled = true; i += 1; }
            "--checkpoint" if i + 1 < args.len() => { checkpoint = Some(args[i + 1].clone()); i += 2; }
            "--output" if i + 1 < args.len() => { output = Some(args[i + 1].clone()); i += 2; }
            "--load" if i + 1 < args.len() => { additional_images.push(args[i + 1].clone()); i += 2; } "--repeat" => { repeat = args[i + 1].parse().unwrap(); i += 2; } "--host" => { host = true; i += 1; } "--setup" => { setup = Some(args[i + 1].clone()); i += 2; } a => { call_args_text.push(a.to_string()); i += 1; } }
    }
    if restoring && (host || !additional_images.is_empty()) { eprintln!("restore cannot replace the saved host or load extra images before native binding"); std::process::exit(2); }
    if std::env::var("BUILTIN_STATS").is_ok() { builtins::STATS.store(true, std::sync::atomic::Ordering::Relaxed); }
    if std::env::var("TABLE_STATS").is_ok() { nupp_vm::interp::TABLE_STATS.store(true, std::sync::atomic::Ordering::Relaxed); }
    let t0 = cpu_now();
    let mut it = if restoring {
        let data = std::fs::read(&args[2]).unwrap_or_else(|e| { eprintln!("checkpoint {}: {e}", args[2]); std::process::exit(1) });
        nupp_vm::persist::load_vm(&data, &Default::default(), &mut extension_codecs()).unwrap_or_else(|e| { eprintln!("restore: {e}"); std::process::exit(1) })
    } else {
        let text = match program.take() { Some(found) => found.image, None => std::fs::read_to_string(&args[2]).unwrap_or_else(|e| { eprintln!("image {}: {e}", args[2]); std::process::exit(1) }) };
        let mut vm = Interp::new();
        image::load(&mut vm, &text).unwrap_or_else(|e| { eprintln!("load: {e}"); std::process::exit(1) });
        for path in additional_images {
            let text = std::fs::read_to_string(&path).unwrap_or_else(|e| { eprintln!("{path}: {e}"); std::process::exit(1) });
            image::load(&mut vm, &text).unwrap_or_else(|e| { eprintln!("load {path}: {e}"); std::process::exit(1) });
        }
        vm
    };
    let load_s = cpu_now() - t0;
    it.entries = vec![0u64; it.funcs.len()];
    it.prepare_threaded();
    #[cfg(feature = "aot-linked")]
    let aot_entries = if std::env::var("NO_AOT").is_ok() { Vec::new() } else { aot_link::entries() };
    #[cfg(feature = "aot-linked")]
    let aot_frames = if std::env::var("NO_AOT").is_ok() { Vec::new() } else { aot_link::frame_entries() };
    #[cfg(feature = "aot-linked")]
    let aot_consts: Vec<u64> = it.funcs.iter().map(|f| f.consts.as_ptr() as u64).collect();
    #[cfg(feature = "aot-linked")]
    if !aot_entries.is_empty() || !aot_frames.is_empty() {
        let digest = nupp_vm::persist::primary_image_hash(&it).unwrap_or_else(|e| { eprintln!("aot: {e}"); std::process::exit(1) });
        if aot_link::image_hash() != digest {
            eprintln!("aot: linked object was built for another image");
            std::process::exit(1);
        }
        for (fid, ptr) in &aot_entries { if *fid >= it.entries.len() { eprintln!("aot: linked function ID outside restored image"); std::process::exit(1); } it.entries[*fid] = *ptr; }
        it.frame_entries.resize(it.funcs.len(), 0);
        for &(fid, ptr) in &aot_frames { assert!(fid < it.frame_entries.len()); it.frame_entries[fid] = ptr; }
        if std::env::var_os("AOT_VERBOSE").is_some() { eprintln!("aot: attached {} linked entries{}", aot_entries.len() + aot_frames.len(), if restoring { " after restore" } else { "" }); }
        it.calltab = it.funcs.iter().map(|f| {
            let plain = f.sig.iter().all(|&c| c == b'v') && f.ret != b'f' && !f.vararg;
            f.nparams as u64 | ((plain as u64) << 8)
        }).collect();
        it.shape_probe = it.heap.shapes.iter().map(|s| (s.table.as_ptr() as u64, s.mask)).collect();
        it.runtime_consts = aot_consts;
        it.linked_frames = it.frame_entries.clone();
        nupp_vm::compiled::CTX.store(&mut it as *mut Interp, std::sync::atomic::Ordering::Relaxed);
        nupp_vm::compiled::CODE_MAPS.lock().unwrap().extend(aot_link::maps().into_iter().map(|(start, len, maps)| (start, start + len, maps)));
    }
    // A runtime that will not interpret vector instructions (a linked no-JIT
    // host) refuses an image holding a function its object did not compile,
    // before any module initializer runs, rather than at the function's call.
    if let Some(fid) = it.first_uncompiled_native() {
        let f = &it.funcs[fid as usize];
        eprintln!("{}", image::uncompiled_native_message("image refused", &f.name, &f.module));
        std::process::exit(1);
    }
    #[cfg(all(feature = "jit", feature = "aot-linked"))]
    let has_aot = !aot_entries.is_empty() || !aot_frames.is_empty();
    #[cfg(all(feature = "jit", not(feature = "aot-linked")))]
    let has_aot = false;
    // The typed tier: every function it accepts, callees first by id, with
    // its compile time reported apart from the run time.
    #[cfg(feature = "jit")]
    let _jit = if std::env::var("NO_JIT").is_err() && !has_aot {
        nupp_vm::compiled::CTX.store(&mut it as *mut Interp, std::sync::atomic::Ordering::Relaxed);
        let mut j = nupp_vm::jit::Jit::new();
        j.extra_addr = it.extra.as_ptr() as i64;
        j.last_nres_addr = &it.last_nres as *const usize as i64;
        j.entries_addr = it.entries.as_ptr() as i64;
        j.callee_info = it.funcs.iter().map(|f| (f.nparams, f.sig.iter().all(|&c| c == b'v') && f.ret != b'f' && !f.vararg)).collect();
        it.calltab = j.callee_info.iter().map(|&(np, plain)| np as u64 | ((plain as u64) << 8)).collect();
        j.calltab_addr = it.calltab.as_ptr() as i64;
        it.shape_probe = it.heap.shapes.iter().map(|s| (s.table.as_ptr() as u64, s.mask)).collect();
        j.probe_addr = if std::env::var("NO_PROBE").is_ok() { 0 } else { it.shape_probe.as_ptr() as i64 };
        let threshold: u32 = std::env::var("JIT_THRESHOLD").ok().and_then(|s| s.parse().ok()).unwrap_or(0);
        let frame_entries = scheduled || it.funcs.iter().any(|f| f.code.iter().any(|op| matches!(op, nupp_vm::interp::Op::Simd(..) | nupp_vm::interp::Op::AffineEnter | nupp_vm::interp::Op::Defer(..) | nupp_vm::interp::Op::DeferMethod(..))));
        // Heap-frame entries compile once a function is warm (JIT_FRAME_THRESHOLD
        // entries or interpreted steps, 0 for the first): compiling every
        // function a run reaches cost more than it saved on the compiler.
        it.frame_threshold = std::env::var("JIT_FRAME_THRESHOLD").ok().and_then(|s| s.parse().ok()).unwrap_or(200);
        if threshold > 0 || frame_entries { it.jit_threshold = threshold; it.jit = Some(Box::new(j)); if !executable { if frame_entries { eprintln!("jit: heap-frame entries on demand"); } else { eprintln!("jit: lazy, compiling at the call number {threshold}"); } } None } else {
        let tj = cpu_now();
        let (mut compiled, mut refused) = (0, Vec::new());
        // JIT_LIMIT=n compiles the first n functions by id; JIT_SKIP=a,b leaves
        // those names interpreted: the bisection controls.
        let limit: usize = std::env::var("JIT_LIMIT").ok().and_then(|s| s.parse().ok()).unwrap_or(usize::MAX);
        let skip: Vec<String> = std::env::var("JIT_SKIP").map(|s| s.split(',').map(|x| x.to_string()).collect()).unwrap_or_default();
        // JIT_ONLY=a,b compiles those names and nothing else.
        let only: Vec<String> = std::env::var("JIT_ONLY").map(|s| s.split(',').map(|x| x.to_string()).collect()).unwrap_or_default();
        for fid in 0..it.funcs.len() {
            let f = it.funcs[fid].clone();
            if f.name.starts_with("module:") || compiled >= limit || skip.iter().any(|n| *n == f.name) { continue; }
            if !only.is_empty() && !only.iter().any(|n| *n == f.name) { continue; }
            // With specialization on, an instrumented generic version, compiled
            // and installed through its version record.
            let result = match it.spec_baseline_plan(fid as u32) {
                Some(plan) => it.spec_compile_function(&mut j, fid as u32, &f, plan).and_then(|v| it.spec_install(v).map_err(|e| format!("{e:?}"))),
                None => j.try_compile(&f, fid as u32).map(|p| p as u64),
            };
            match result { Ok(entry) => { it.entries[fid] = entry; compiled += 1; } Err(e) => refused.push(format!("{} ({e})", f.name)) }
        }
        let compile_s = cpu_now() - tj;
        if std::env::var("JIT_LIST").is_ok() { for (n, us) in &j.compile_micros { eprintln!("jit\t{n}\t{us} us"); } }
        if !executable { eprintln!("jit: compiled {compiled} functions in {:.2} ms; refused {}{}", compile_s * 1e3, refused.len(), if refused.is_empty() { String::new() } else { format!(": {}", refused.join(", ")) }); }
        // Specialization compiles later versions with the same compiler.
        if it.spec.specialize { it.jit = Some(Box::new(j)); None } else { Some(j) } }
    } else { None };
    if !restoring { it.install_globals(); }
    if scheduled { it.enable_scheduler().unwrap(); }
    #[cfg(feature = "jit")]
    if scheduled && it.jit.is_some() && std::env::var_os("JIT_EAGER_FRAMES").is_some() { it.precompile_frames(); }
    let argv = if executable {
        let argv = it.new_table(); it.registered.push(argv);
        for (index, argument) in call_args_text.iter().enumerate() {
            let value = it.heap_new_string(argument);
            it.set_index(argv, Value::num((index + 1) as f64), value);
        }
        // A program's `arg[0]` is the executable, as a script's is its file.
        if stamped { let value = it.heap_new_string(&args[0]); it.set_index(argv, Value::num(0.0), value); }
        let global = it.require("_G"); let key = it.intern("arg"); it.set_index(global, key, argv);
        Some(argv)
    } else { None };
    if host { it.host = Some(Host::start(4)); let ht = it.host_table(); it.loaded.insert("nupp.bench.host".into(), ht); }
    // A program's resources ride as the `nupp.embedded` module, which a bundle
    // reaches through `package.preload` (docs/reference/distribution.md).
    if stamped {
        if let Some(&fid) = it.modules.get("nupp.embedded") {
            let package = it.require("package"); let key = it.intern("preload"); let preload = it.get_index(package, key);
            if preload != Value::NIL { let name = it.intern("nupp.embedded"); it.set_index(preload, name, Value::func(fid)); }
        }
    }
    // A program is its entry module's body, run on a task so it may suspend.
    let module = if stamped { Value::NIL } else if restoring { *it.loaded.get(&args[3]).unwrap_or_else(|| { eprintln!("restore: module {} was not initialized in the checkpoint", args[3]); std::process::exit(1) }) } else {
        match std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| it.require(&args[3]))) {
            Ok(module) => module,
            Err(payload) => {
                let value = it.error_value(payload);
                eprintln!("error loading {}: {}", args[3], show(&it, value));
                for tid in (0..it.tasks.len()).rev() { let trace = it.backtrace(tid); if !trace.is_empty() { eprintln!("{trace}"); } }
                std::process::exit(1);
            }
        }
    };
    if let Some(name) = &setup { let k = it.intern(name); let sf = it.get_index(module, k); let t = it.spawn_closure(sf, &[]); drive(&mut it, &[t]); it.tasks.truncate(t); }
    let f = if stamped {
        match it.modules.get(&args[3]) { Some(&fid) => Value::func(fid), None => { eprintln!("the program image has no module {}", args[3]); std::process::exit(1) } }
    } else { let k = it.intern(&args[4]); it.get_index(module, k) };
    if f == Value::NIL { eprintln!("{}.{} is nil", args[3], args[4]); std::process::exit(1); }
    let mut call_args: Vec<Value> = Vec::new();
    if stamped {
        for argument in &call_args_text { let value = it.heap_new_string(argument); it.registered.push(value); call_args.push(value); }
    } else if let Some(argv) = argv { call_args.push(argv); }
    for a in call_args_text.iter().filter(|_| !executable) {
        let v = if let Some(p) = a.strip_prefix('@') { let s = std::fs::read_to_string(p).unwrap_or_else(|e| { eprintln!("{p}: {e}"); std::process::exit(1) }); it.heap_new_string(&s) }
            else if let Ok(n) = a.parse::<f64>() { Value::num(n) } else { it.heap_new_string(a) };
        it.registered.push(v); call_args.push(v);
    }
    let run_once = |it: &mut Interp| -> Vec<Value> {
        if scheduled {
            it.enable_scheduler().unwrap();
            let task = it.schedule(f, &call_args, None).unwrap();
            let start = std::time::Instant::now();
            let base = it.scheduler.as_ref().unwrap().now();
            loop {
                it.advance_to(base + start.elapsed().as_millis() as u64).unwrap();
                it.run_ready(256).unwrap();
                match it.scheduler.as_ref().unwrap().status(task).unwrap() {
                    nupp_vm::scheduler::Status::Completed => break,
                    nupp_vm::scheduler::Status::Active => {},
                    nupp_vm::scheduler::Status::Failed(message) if stamped => { eprintln!("{message}"); std::process::exit(1); }
                    status => { eprintln!("task: {status:?}"); std::process::exit(1); }
                }
                if it.tasks.iter().any(|t| t.state == State::Runnable) { continue; }
                if it.scheduler.as_ref().unwrap().next_wakeup().is_none() && it.host_waiters.is_empty() && !it.has_workers() { eprintln!("task scheduler has no event source for parked tasks"); std::process::exit(1); }
                std::thread::park_timeout(std::time::Duration::from_millis(1));
            }
            let t = &it.tasks[task.index];
            let results = if t.results.is_empty() { vec![t.result] } else { t.results.clone() };
            it.release_task(task).unwrap();
            if !executable {
                eprintln!("compiled frame entries: {}", it.compiled_frame_entries);
                eprintln!("compiled frame parks: {}; continuations: {}", it.compiled_frame_parks, it.compiled_frame_continuations);
                eprintln!("worker compiled entries: {}; compile {:.3} ms", it.worker_compiled_entries, it.worker_compile_micros as f64 / 1000.0);
            }
            return results;
        }
        let t = it.spawn_closure(f, &call_args);
        // An error that unwinds to here is reported with its value and the
        // task's frame chain, then the process fails.
        let outcome = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| drive(it, &[t])));
        if let Err(payload) = outcome {
            let v = it.error_value(payload);
            eprintln!("error: {}", show(it, v));
            // A callback or module chunk runs on a task of its own, left in
            // place by the unwind: innermost first.
            for tid in (t..it.tasks.len()).rev() { let b = it.backtrace(tid); if !b.is_empty() { eprintln!("{}", b); } }
            std::process::exit(1);
        }
        let task = &it.tasks[t];
        let outs = if task.results.is_empty() { vec![task.result] } else { task.results.clone() };
        it.tasks.truncate(t);
        outs
    };
    let t1 = cpu_now();
    let outs = run_once(&mut it);
    let first_s = cpu_now() - t1;
    if executable {
        // A program that returns from its body has succeeded; `os.exit` is how one says otherwise.
        let status = if stamped { Value::num(0.0) } else { outs.first().copied().unwrap_or(Value::NIL) };
        if !status.is_num() || !status.as_num().is_finite() || status.as_num().fract() != 0.0 || !(0.0..=255.0).contains(&status.as_num()) {
            eprintln!("{}.main must return an exit status from 0 to 255", args[3]);
            it.heap.emit_allocation_metrics("cli-invalid-status");
            emit_allocator_metrics("cli-invalid-status-before-drop");
            std::process::exit(1);
        }
        it.heap.emit_allocation_metrics("cli-exit");
        emit_allocator_metrics("cli-exit-before-drop");
        std::process::exit(status.as_num() as i32);
    }
    if let Some(path) = &output {
        let first = outs.first().copied().unwrap_or(Value::NIL);
        if !it.is_stringish(first) { eprintln!("--output: {} returned {}, not a string", args[4], show(&it, first)); std::process::exit(1); }
        std::fs::write(path, it.bytes_of(first)).unwrap_or_else(|e| { eprintln!("--output {path}: {e}"); std::process::exit(1) });
        it.heap.report_stats("output");
        #[cfg(feature = "jit")]
        if std::env::var_os("JIT_SPEC_STATS").is_some() { eprintln!("{}", nupp_vm::specialize::report(&it)); }
        std::process::exit(0);
    }
    let shown: Vec<String> = outs.iter().map(|&v| show(&it, v)).collect();
    println!("{}", shown.join("\t"));
    eprintln!("load {:.2} ms\tfirst call {:.3} ms\tobjects live {} allocated {}\tcycles {}", load_s * 1e3, first_s * 1e3, it.heap.object_count(), it.heap.stats.allocated, it.heap.stats.cycles);
    if repeat > 0 {
        let mut samples = Vec::new();
        for _ in 0..repeat { let s = cpu_now(); let o = run_once(&mut it); samples.push(cpu_now() - s); assert_eq!(o.len(), outs.len()); }
        samples.sort_by(|a, b| a.partial_cmp(b).unwrap());
        let m = samples[samples.len() / 2];
        println!("median {:.6} ms over {repeat}\tmin {:.6} ms", m * 1e3, samples[0] * 1e3);
    }
    if let Some(path) = checkpoint {
        let bytes = nupp_vm::persist::save_vm(&mut it, &Default::default(), &mut extension_codecs()).unwrap_or_else(|e| { eprintln!("checkpoint: {e}"); std::process::exit(1) });
        std::fs::write(&path, &bytes).unwrap_or_else(|e| { eprintln!("checkpoint {path}: {e}"); std::process::exit(1) });
        eprintln!("checkpoint: wrote {} bytes", bytes.len());
    }
    if std::env::var("BUILTIN_STATS").is_ok() { let c = builtins::CALLS.lock().unwrap(); let mut rows: Vec<(usize, u64)> = c.iter().copied().enumerate().filter(|(_, n)| *n > 0).collect(); rows.sort_by(|a, b| b.1.cmp(&a.1)); eprintln!("builtin calls:"); for (i, n) in rows.iter().take(16) { eprintln!("  {n}\t{}", builtins::NAMES[*i]); } }
    if std::env::var("TABLE_STATS").is_ok() { let c: Vec<u64> = nupp_vm::interp::TABLE_COUNTS.iter().map(|a| a.load(std::sync::atomic::Ordering::Relaxed)).collect(); eprintln!("index reads: table by number {}, table by key {}, record by number {}, record by key {}, other {}; table key reads met hash parts of 0: {}, 1-4: {}, 5-16: {}, 17-64: {}, 65+: {}; stores by number {}, by key {}; tables made {}", c[0], c[1], c[2], c[3], c[4], c[5], c[6], c[7], c[8], c[9], c[10], c[11], nupp_vm::heap::NEW_TABLES.load(std::sync::atomic::Ordering::Relaxed)); }
    if it.jit_threshold != 0 { eprintln!("jit: compiled {} functions lazily in {:.2} ms", it.lazy_compiled, it.lazy_micros as f64 / 1e3); }
    #[cfg(feature = "jit")]
    if std::env::var_os("JIT_SPEC_STATS").is_some() { eprintln!("{}", nupp_vm::specialize::report(&it)); }
    #[cfg(feature = "compiled-runtime")]
    if it.ic_stats { let c: Vec<u64> = nupp_vm::compiled::IC_STATS.iter().map(|a| a.load(std::sync::atomic::Ordering::Relaxed)).collect(); eprintln!("field-cache helper calls: record with empty cache {}, record after another shape (polymorphic) {}, table {}, other {}", c[0], c[1], c[2], c[3]); eprintln!("dynamic calls from compiled code: builtin {}, compiled callee {}, interpreted (spawned task) {}", c[4], c[5], c[6]);
        if let Some(m) = nupp_vm::compiled::INTERP_CALLEES.lock().unwrap().as_ref() { let mut rows: Vec<(&u32, &u64)> = m.iter().collect(); rows.sort_by(|a, b| b.1.cmp(a.1)); eprintln!("interpreted callees from compiled code:"); for (fid, n) in rows.iter().take(12) { let f = it.funcs.get(**fid as usize); eprintln!("  {n}\t{} in {} ({})", f.map(|f| f.name.as_str()).unwrap_or("?"), f.map(|f| f.module.as_str()).unwrap_or("?"), f.map(|f| if f.vararg { "vararg" } else if f.nparams > 8 { ">8 params" } else if it.entries.get(**fid as usize).copied().unwrap_or(0) == 0 { "no entry" } else { "has entry" }).unwrap_or("?")); } }
        if let Some(sites) = nupp_vm::compiled::IC_SITES.lock().unwrap().as_ref() { let mut hist = std::collections::BTreeMap::new(); for set in sites.values() { *hist.entry(set.len().min(9)).or_insert(0usize) += 1; } eprintln!("record field sites by distinct shapes seen: {:?}", hist); } }
    if let Some(st) = it.slot_stats.as_ref() {
        let (mut hits, mut misses) = (0u64, 0u64); let mut miss_sites: Vec<((u32, usize), u64)> = Vec::new(); let mut hit_sites = 0usize;
        for (&(f, pc, ok), &n) in st.iter() { if ok { hits += n; hit_sites += 1; } else { misses += n; miss_sites.push(((f, pc), n)); } }
        miss_sites.sort_by(|a, b| b.1.cmp(&a.1));
        eprintln!("slot accesses: {hits} with the assumed shape at {hit_sites} sites, {misses} without at {} sites", miss_sites.len());
        for ((f, pc), n) in miss_sites.iter().take(12) { eprintln!("  miss {n}\t{} pc {pc}", it.funcs[*f as usize].name); }
        // How many accesses a verifier could prove exact: the object register's
        // last write before the site, in straight-line code with no call between,
        // is `NewRecord` of the assumed shape.
        let provable = |f: &nupp_vm::interp::Function, pc: usize| -> bool {
            use nupp_vm::interp::Op;
            let (t, sh) = match f.code[pc] { Op::GetSlot(_, t, _, sh) | Op::GetSlotF(_, t, _, sh) => (t, sh), Op::SetSlot(t, _, _, sh) | Op::SetSlotF(t, _, _, sh) => (t, sh), _ => return false };
            let targets: std::collections::HashSet<usize> = f.code.iter().enumerate().flat_map(|(i, op)| nupp_vm::verify::operands(op).1.into_iter().map(move |off| (i as i64 + 1 + off as i64) as usize)).collect();
            let mut i = pc; let mut t = t;
            while i > 0 {
                i -= 1;
                if targets.contains(&(i + 1)) { return false; }
                match f.code[i] {
                    Op::NewRecord(d, s2) if d == t => return s2 == sh,
                    // A constructor lands in a temporary and moves to its local.
                    Op::Move(d, src) if d == t => { t = src; continue; }
                    // A call delivers results at its base register and up to eight above.
                    Op::Call(_, b, _) | Op::CallDyn(_, b, _) | Op::CallK(_, _, b, _, _) | Op::CallMethod(_, b, _) | Op::PCall(b, _) => { if t >= b && t < b.saturating_add(9) { return false; } }
                    Op::CallT(_, b, _, _) => { if t >= b && t < b.saturating_add(9) { return false; } }
                    Op::Jmp(..) | Op::JmpIf(..) | Op::JmpIfNot(..) | Op::JmpIfIZero(..) | Op::Switch(..) => return false,
                    // Stores name the object first and write no register.
                    Op::SetSlot(..) | Op::SetSlotF(..) | Op::SetField(..) | Op::SetIdx(..) | Op::SetIdxI(..) | Op::SetIdxF(..) | Op::SetCell(..) | Op::SetMethod(..) => {}
                    ref op => { let (ws, _) = nupp_vm::verify::operands(op); if ws.first().map(|(_, r)| *r == t).unwrap_or(false) { return false; } }
                }
            }
            false
        };
        let (mut prov_hits, mut prov_sites) = (0u64, 0usize);
        for (&(f, pc, ok), &n) in st.iter() { if ok && provable(&it.funcs[f as usize], pc) { prov_hits += n; prov_sites += 1; } }
        eprintln!("  provable exact (the register was written by NewRecord of the shape, in straight-line code): {prov_hits} accesses at {prov_sites} sites");
        if std::env::var("SLOT_STATS_SITES").is_ok() { let mut rows: Vec<_> = st.iter().filter(|(k, _)| k.2).collect(); rows.sort_by(|a, b| b.1.cmp(a.1)); for ((f, pc, _), n) in rows.iter().take(8) { let func = &it.funcs[*f as usize]; let lo = pc.saturating_sub(3); eprintln!("  site {} pc {pc} x{n} provable={}: {}", func.name, provable(func, *pc), (lo..=*pc).map(|i| format!("{:?}", func.code[i])).collect::<Vec<_>>().join(" ; ")); } }
        let mut by_shape: Vec<(&(u32, u32), &u64)> = it.slot_miss_shapes.iter().collect(); by_shape.sort_by(|a, b| b.1.cmp(a.1));
        let name = |s: u32| -> String { if s == u32::MAX { "table".to_string() } else if s == u32::MAX - 1 { "non-object".to_string() } else { it.heap.shapes[s as usize].name.clone() } };
        for ((a, f), n) in by_shape.iter().take(15) { eprintln!("  assumed {} found {}: {n}", name(*a), name(*f)); }
    }
    if let Some(st) = it.op_stats.as_ref() { let mut rows: Vec<(&&str, &u64)> = st.iter().collect(); rows.sort_by(|a, b| b.1.cmp(a.1)); let total: u64 = st.values().sum(); eprintln!("ops executed {total}"); for (n, c) in rows.iter().take(40) { eprintln!("  {n}\t{c}\t{:.1}%", **c as f64 * 100.0 / total as f64); } }
    let _ = Outcome::Done(Value::NIL);
    drop(it);
    emit_allocator_metrics("after-vm-drop");
}
