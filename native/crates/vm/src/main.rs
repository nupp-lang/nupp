//! `nupp-vm run IMAGE MODULE FUNCTION [ARG...]`: loads an image, requires a
//! module, calls one of its functions on a task and prints the results.
//! An argument `@path` is that file's text, a number is a number, anything
//! else is a string. `--repeat N` times the call N times and reports the
//! median; `--host` starts the host services. The collector's verification
//! modes come from the environment: GC_STRESS, GC_INTERLEAVE, GC_ORACLE,
//! GC_QUARANTINE.

use nupp_vm::builtins;
use nupp_vm::heap::KIND_NAMES;
use nupp_vm::host::Host;
use nupp_vm::image;
use nupp_vm::interp::{Interp, Outcome, State};
use nupp_vm::value::Value;

fn cpu_now() -> f64 { std::time::Instant::now().elapsed().as_secs_f64() + START.with(|s| s.elapsed().as_secs_f64()) }
thread_local! { static START: std::time::Instant = std::time::Instant::now(); }

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

fn show(it: &Interp, v: Value) -> String {
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
    let args: Vec<String> = std::env::args().collect();
    if args.len() < 5 || args[1] != "run" { eprintln!("usage: nupp-vm run IMAGE MODULE FUNCTION [ARG...] [--repeat N] [--host] [--setup FN]"); std::process::exit(2); }
    let mut repeat = 0usize; let mut host = false; let mut setup: Option<String> = None; let mut call_args_text: Vec<String> = Vec::new();
    let mut i = 5;
    while i < args.len() {
        match args[i].as_str() { "--repeat" => { repeat = args[i + 1].parse().unwrap(); i += 2; } "--host" => { host = true; i += 1; } "--setup" => { setup = Some(args[i + 1].clone()); i += 2; } a => { call_args_text.push(a.to_string()); i += 1; } }
    }
    let text = std::fs::read_to_string(&args[2]).unwrap_or_else(|e| { eprintln!("image {}: {e}", args[2]); std::process::exit(1) });
    let mut it = Interp::new();
    if std::env::var("BUILTIN_STATS").is_ok() { builtins::STATS.store(true, std::sync::atomic::Ordering::Relaxed); }
    let t0 = cpu_now();
    image::load(&mut it, &text).unwrap_or_else(|e| { eprintln!("load: {e}"); std::process::exit(1) });
    let load_s = cpu_now() - t0;
    it.entries = vec![0u64; it.funcs.len()];
    it.prepare_threaded();
    // The typed tier: every function it accepts, callees first by id, with
    // its compile time reported apart from the run time.
    #[cfg(feature = "jit")]
    let _jit = if std::env::var("NO_JIT").is_err() {
        nupp_vm::jit::CTX.store(&mut it as *mut Interp, std::sync::atomic::Ordering::Relaxed);
        let mut j = nupp_vm::jit::Jit::new();
        j.extra_addr = &it.extra as *const [Value; 8] as i64;
        j.last_nres_addr = &it.last_nres as *const usize as i64;
        j.entries_addr = it.entries.as_ptr() as i64;
        j.callee_info = it.funcs.iter().map(|f| (f.nparams, f.sig.iter().all(|&c| c == b'v') && f.ret != b'f' && !f.vararg)).collect();
        it.calltab = j.callee_info.iter().map(|&(np, plain)| np as u64 | ((plain as u64) << 8)).collect();
        j.calltab_addr = it.calltab.as_ptr() as i64;
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
            match j.try_compile(&f, fid as u32) { Ok(ptr) => { it.entries[fid] = ptr as u64; compiled += 1; } Err(e) => refused.push(format!("{} ({e})", f.name)) }
        }
        let compile_s = cpu_now() - tj;
        if std::env::var("JIT_LIST").is_ok() { for (n, us) in &j.compile_micros { eprintln!("jit\t{n}\t{us} us"); } }
        eprintln!("jit: compiled {compiled} functions in {:.2} ms; refused {}{}", compile_s * 1e3, refused.len(), if refused.is_empty() { String::new() } else { format!(": {}", refused.join(", ")) });
        Some(j)
    } else { None };
    it.install_globals();
    if host { it.host = Some(Host::start(4)); let ht = it.host_table(); it.loaded.insert("nupp.bench.host".into(), ht); }
    let module = it.require(&args[3]);
    if let Some(name) = &setup { let k = it.intern(name); let sf = it.get_index(module, k); let t = it.spawn_closure(sf, &[]); drive(&mut it, &[t]); it.tasks.truncate(t); }
    let k = it.intern(&args[4]); let f = it.get_index(module, k);
    if f == Value::NIL { eprintln!("{}.{} is nil", args[3], args[4]); std::process::exit(1); }
    let mut call_args: Vec<Value> = Vec::new();
    for a in &call_args_text {
        let v = if let Some(p) = a.strip_prefix('@') { let s = std::fs::read_to_string(p).unwrap_or_else(|e| { eprintln!("{p}: {e}"); std::process::exit(1) }); it.heap_new_string(&s) }
            else if let Ok(n) = a.parse::<f64>() { Value::num(n) } else { it.heap_new_string(a) };
        it.registered.push(v); call_args.push(v);
    }
    let run_once = |it: &mut Interp| -> Vec<Value> {
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
    let shown: Vec<String> = outs.iter().map(|&v| show(&it, v)).collect();
    println!("{}", shown.join("\t"));
    eprintln!("load {:.2} ms\tfirst call {:.3} ms\tobjects live {} allocated {}\tcycles {}", load_s * 1e3, first_s * 1e3, it.heap.object_count(), it.heap.stats.allocated, it.heap.stats.cycles);
    if repeat > 0 {
        let mut samples = Vec::new();
        for _ in 0..repeat { let s = cpu_now(); let o = run_once(&mut it); samples.push(cpu_now() - s); assert_eq!(o.len(), outs.len()); }
        samples.sort_by(|a, b| a.partial_cmp(b).unwrap());
        let m = samples[samples.len() / 2];
        println!("median {:.3} ms over {repeat}\tmin {:.3} ms", m * 1e3, samples[0] * 1e3);
    }
    if std::env::var("BUILTIN_STATS").is_ok() { let c = builtins::CALLS.lock().unwrap(); let mut rows: Vec<(usize, u64)> = c.iter().copied().enumerate().filter(|(_, n)| *n > 0).collect(); rows.sort_by(|a, b| b.1.cmp(&a.1)); eprintln!("builtin calls:"); for (i, n) in rows.iter().take(16) { eprintln!("  {n}\t{}", builtins::NAMES[*i]); } }
    if it.ic_stats { let c: Vec<u64> = nupp_vm::jit::IC_STATS.iter().map(|a| a.load(std::sync::atomic::Ordering::Relaxed)).collect(); eprintln!("field-cache helper calls: record with empty cache {}, record after another shape (polymorphic) {}, table {}, other {}", c[0], c[1], c[2], c[3]); eprintln!("dynamic calls from compiled code: builtin {}, compiled callee {}, interpreted (spawned task) {}", c[4], c[5], c[6]);
        if let Some(m) = nupp_vm::jit::INTERP_CALLEES.lock().unwrap().as_ref() { let mut rows: Vec<(&u32, &u64)> = m.iter().collect(); rows.sort_by(|a, b| b.1.cmp(a.1)); eprintln!("interpreted callees from compiled code:"); for (fid, n) in rows.iter().take(12) { let f = it.funcs.get(**fid as usize); eprintln!("  {n}\t{} in {} ({})", f.map(|f| f.name.as_str()).unwrap_or("?"), f.map(|f| f.module.as_str()).unwrap_or("?"), f.map(|f| if f.vararg { "vararg" } else if f.nparams > 8 { ">8 params" } else if it.entries.get(**fid as usize).copied().unwrap_or(0) == 0 { "no entry" } else { "has entry" }).unwrap_or("?")); } }
        if let Some(sites) = nupp_vm::jit::IC_SITES.lock().unwrap().as_ref() { let mut hist = std::collections::BTreeMap::new(); for set in sites.values() { *hist.entry(set.len().min(9)).or_insert(0usize) += 1; } eprintln!("record field sites by distinct shapes seen: {:?}", hist); } }
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
}
