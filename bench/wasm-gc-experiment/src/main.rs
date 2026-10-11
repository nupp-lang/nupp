//! Wasm GC as the runtime: the plan's untyped and typed workloads, the host
//! boundary and suspension, on wasmtime's collectors.
use wasmtime::*;

fn cpu_now() -> f64 { let mut ts = libc::timespec { tv_sec: 0, tv_nsec: 0 }; unsafe { libc::clock_gettime(libc::CLOCK_THREAD_CPUTIME_ID, &mut ts) }; ts.tv_sec as f64 + ts.tv_nsec as f64 * 1e-9 }

fn median(mut v: Vec<f64>) -> f64 { v.sort_by(|a, b| a.partial_cmp(b).unwrap()); v[v.len() / 2] }

fn timed<F: FnMut() -> f64>(name: &str, want: f64, mut f: F) -> f64 {
    let mut samples = Vec::new();
    for _ in 0..5 { let s = cpu_now(); let r = f(); let e = cpu_now() - s; assert_eq!(r, want, "{name}"); samples.push(e); }
    let m = median(samples);
    println!("{name}\t{:.6}", m);
    m
}

fn rss_mb() -> f64 { let mut ru: libc::rusage = unsafe { std::mem::zeroed() }; unsafe { libc::getrusage(libc::RUSAGE_SELF, &mut ru) }; ru.ru_maxrss as f64 / (1 << 20) as f64 }

fn main() -> Result<()> {
    let args: Vec<String> = std::env::args().collect();
    if args.get(1).map(|s| s.as_str()) == Some("sched") { return sched_mode(); }
    if args.get(1).map(|s| s.as_str()) == Some("live") { return live_mode(); }
    let collector = match args.get(1).map(|s| s.as_str()).unwrap_or("copying") { "drc" => Collector::DeferredReferenceCounting, "null" => Collector::Null, _ => Collector::Copying };
    let mut config = Config::new();
    config.wasm_gc(true).wasm_function_references(true).wasm_exceptions(true).wasm_tail_call(true).collector(collector);
    config.cranelift_opt_level(OptLevel::Speed);
    if let Some(mb) = std::env::var("GC_HEAP_MB").ok().and_then(|s| s.parse::<u64>().ok()) { config.gc_heap_initial_size(mb << 20); config.gc_heap_reservation((mb * 2) << 20); }
    // Stack switching is tried on its own engine, so a refusal costs nothing else.
    let park_engine = { let mut c = config.clone(); c.wasm_stack_switching(true); Engine::new(&c) };
    let park_ok = park_engine.is_ok();
    let engine = Engine::new(&config)?;
    let dir = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("wat");
    let load = |engine: &Engine, name: &str| -> Result<Module> { let t = std::time::Instant::now(); let m = Module::from_file(engine, dir.join(name))?; eprintln!("compile\t{name}\t{} us", t.elapsed().as_micros()); Ok(m) };
    for (tier, file) in [("untyped-boxed", "untyped.wat"), ("untyped-i31", "i31.wat"), ("typed", "typed.wat")] {
        let module = load(&engine, file)?;
        let mut store = Store::new(&engine, ());
        let instance = Instance::new(&mut store, &module, &[])?;
        let fib = instance.get_typed_func::<f64, f64>(&mut store, "fib")?;
        let trees = instance.get_typed_func::<(f64, f64), f64>(&mut store, "trees")?;
        timed(&format!("{tier}\tfib30"), 832040.0, || fib.call(&mut store, 30.0).unwrap());
        timed(&format!("{tier}\ttrees15x10"), 10.0 * 65535.0, || trees.call(&mut store, (10.0, 15.0)).unwrap());
        let iters: f64 = std::env::var("TREES_ITERS").ok().and_then(|s| s.parse().ok()).unwrap_or(0.0);
        if iters > 0.0 { let m = timed(&format!("{tier}\ttrees15x{iters}"), iters * 65535.0, || trees.call(&mut store, (iters, 15.0)).unwrap()); println!("{tier}\tper tree of 65535 nodes\t{:.3} ms", m / iters * 1e3); }
        if tier == "typed" {
            let churn = instance.get_typed_func::<f64, f64>(&mut store, "churn")?;
            let n: f64 = std::env::var("CHURN_N").ok().and_then(|s| s.parse().ok()).unwrap_or(5_000_000.0);
            let m = timed("typed\tchurn-alloc", n, || churn.call(&mut store, n).unwrap());
            println!("typed\talloc-drop\t{:.1} ns per object", m / n * 1e9);
        }
    }
    {
        let module = load(&engine, "tables.wat")?;
        let mut store = Store::new(&engine, ());
        let instance = Instance::new(&mut store, &module, &[])?;
        let churn = instance.get_typed_func::<f64, f64>(&mut store, "churn")?;
        let n = 5_000_000.0;
        timed("tables\tchurn5m", n * (n + 1.0) / 2.0, || churn.call(&mut store, n).unwrap());
        let intern = instance.get_typed_func::<i32, i32>(&mut store, "intern")?;
        let interned = instance.get_typed_func::<(), i32>(&mut store, "interned")?;
        let n = 100_000i32;
        let s = cpu_now(); let a = intern.call(&mut store, n)?; let miss = cpu_now() - s;
        assert_eq!(interned.call(&mut store, ())?, n + 1, "distinct strings");
        let probes = instance.get_typed_func::<(), i32>(&mut store, "probes")?;
        let miss_probes = probes.call(&mut store, ())?;
        let mut hits = Vec::new();
        for _ in 0..5 { let s = cpu_now(); let b = intern.call(&mut store, n)?; hits.push(cpu_now() - s); assert_eq!(a, b); }
        let hit_probes = probes.call(&mut store, ())? / 5;
        println!("tables\tprobes per lookup\tnew {:.2}\texisting {:.2}", miss_probes as f64 / n as f64, hit_probes as f64 / n as f64);
        assert_eq!(interned.call(&mut store, ())?, n + 1, "no duplicates");
        println!("tables\tintern 100k new strings\t{:.1} ns per string", miss / n as f64 * 1e9);
        println!("tables\tintern 100k existing strings\t{:.1} ns per string", median(hits) / n as f64 * 1e9);
        { let f = instance.get_typed_func::<i32, i32>(&mut store, "churn_i31")?; let n = 20_000i32; let mut samples = Vec::new(); for _ in 0..5 { let s = cpu_now(); let r = f.call(&mut store, n)?; samples.push(cpu_now() - s); assert_eq!(r, n * (n + 1) / 2); } println!("tables\tchurn_i31 (no allocation)\t{:.2} ns per iteration", median(samples) / n as f64 * 1e9); }
        for (name, want) in [("refstore", 8), ("numstore", 9_999_999), ("alloc_store", 9_999_999)] {
            let f = instance.get_typed_func::<i32, i32>(&mut store, name)?;
            let n = 10_000_000i32;
            let mut samples = Vec::new();
            for _ in 0..5 { let s = cpu_now(); let r = f.call(&mut store, n)?; samples.push(cpu_now() - s); assert_eq!(r, want); }
            println!("tables\t{name}\t{:.2} ns per store", median(samples) / n as f64 * 1e9);
        }
    }
    {
        let module = load(&engine, "statemachine.wat")?;
        let mut store = Store::new(&engine, ());
        let instance = Instance::new(&mut store, &module, &[])?;
        for name in ["park1", "park3"] {
            let f = instance.get_typed_func::<i64, i64>(&mut store, name)?;
            let n = 10_000_000i64;
            let mut samples = Vec::new();
            for _ in 0..5 { let s = cpu_now(); let r = f.call(&mut store, n)?; samples.push(cpu_now() - s); assert_eq!(r, n * (n - 1) / 2); }
            println!("statemachine\t{name}\t{:.1} ns per park and resume", median(samples) / n as f64 * 1e9);
        }
    }
    {
        let module = load(&engine, "host.wat")?;
        let mut store = Store::new(&engine, ());
        let mut linker = Linker::new(&engine);
        linker.func_wrap("host", "nop", |x: i64| -> i64 { x.wrapping_add(1) })?;
        let instance = linker.instantiate(&mut store, &module)?;
        let callhost = instance.get_typed_func::<i64, i64>(&mut store, "callhost")?;
        let n = 10_000_000i64;
        let mut samples = Vec::new();
        for _ in 0..5 { let s = cpu_now(); let r = callhost.call(&mut store, n)?; let e = cpu_now() - s; assert_eq!(r, n); samples.push(e); }
        println!("host\tcall from wasm into rust\t{:.1} ns per call", median(samples) / n as f64 * 1e9);
        let mut samples = Vec::new();
        for _ in 0..5 { let s = cpu_now(); let mut acc = 0; for _ in 0..1_000_000 { acc = callhost.call(&mut store, 0)?; } let e = cpu_now() - s; let _ = acc; samples.push(e); }
        println!("host\tcall from rust into wasm\t{:.1} ns per call", median(samples) / 1e6 * 1e9);
    }
    if park_ok {
        let engine = park_engine.unwrap();
        match load(&engine, "park.wat") {
            Ok(module) => {
                let mut store = Store::new(&engine, ());
                let instance = Instance::new(&mut store, &module, &[])?;
                let park = instance.get_typed_func::<i64, i64>(&mut store, "park")?;
                let n = 1_000_000i64;
                let mut samples = Vec::new();
                for _ in 0..5 { let s = cpu_now(); let r = park.call(&mut store, n)?; let e = cpu_now() - s; assert_eq!(r, n); samples.push(e); }
                println!("park\tsuspend and resume\t{:.1} ns per pair", median(samples) / n as f64 * 1e9);
            }
            Err(e) => println!("park\tunavailable: {e}"),
        }
    } else { println!("park\tstack switching not supported: {}", park_engine.err().map(|e| e.to_string()).unwrap_or_default()); }
    Ok(())
}


fn engine_with(collector: Collector, heap_mb: Option<u64>) -> Result<Engine> {
    let mut config = Config::new();
    config.wasm_gc(true).wasm_function_references(true).wasm_exceptions(true).wasm_tail_call(true).collector(collector);
    config.cranelift_opt_level(OptLevel::Speed);
    if let Some(mb) = heap_mb { config.gc_heap_initial_size(mb << 20); config.gc_heap_reservation((mb * 4) << 20); }
    Engine::new(&config)
}

/// 1,000 tasks parking 1,000 times each in a three-frame chain, scheduled
/// round-robin, as the prototype's `park1000x1000`.
fn sched_mode() -> Result<()> {
    let engine = engine_with(Collector::Copying, None)?;
    let dir = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("wat");
    let module = Module::from_file(&engine, dir.join("sched.wat"))?;
    let mut store = Store::new(&engine, ());
    let instance = Instance::new(&mut store, &module, &[])?;
    let spawn = instance.get_typed_func::<(i32, i64), ()>(&mut store, "spawn")?;
    let run = instance.get_typed_func::<(), i64>(&mut store, "run")?;
    let step = instance.get_typed_func::<i32, i32>(&mut store, "step")?;
    let parks = instance.get_typed_func::<(), i64>(&mut store, "parks")?;
    let (count, n) = (1000i32, 1000i64);
    let mut samples = Vec::new();
    for _ in 0..5 { spawn.call(&mut store, (count, n))?; let s = cpu_now(); let p = run.call(&mut store, ())?; samples.push(cpu_now() - s); assert_eq!(p, count as i64 * n); }
    println!("sched\twasm scheduler, 1000 tasks x 1000 parks, 3 frames\t{:.1} ns per park and resume", median(samples) / (count as f64 * n as f64) * 1e9);
    let mut samples = Vec::new();
    for _ in 0..5 {
        spawn.call(&mut store, (count, n))?;
        let s = cpu_now();
        let mut live = count;
        while live > 0 { for i in 0..count { match step.call(&mut store, i)? { 0 => live -= 1, _ => {} } } }
        samples.push(cpu_now() - s);
        assert_eq!(parks.call(&mut store, ())?, count as i64 * n);
    }
    println!("sched\thost scheduler calling step per task\t{:.1} ns per park and resume", median(samples) / (count as f64 * n as f64) * 1e9);
    Ok(())
}

/// Boxed trees beside a large live heap, under each heap size: time per
/// tree, one explicit full collection, and the process's peak memory.
fn live_mode() -> Result<()> {
    let dir = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("wat");
    let live_n: i32 = std::env::var("LIVE_N").ok().and_then(|s| s.parse().ok()).unwrap_or(2_000_000);
    // One configuration per process when LIVE_CFG is set, so peak memory is that configuration's.
    let only_heap: Option<Option<u64>> = std::env::var("LIVE_CFG").ok().map(|c| if c == "default" { None } else { Some(c.parse().unwrap()) });
    let only_live: Option<bool> = std::env::var("LIVE_WITH").ok().map(|c| c == "1");
    for heap in [None, Some(256u64), Some(1024u64)] {
        if let Some(h) = only_heap { if h != heap { continue; } }
        for with_live in [false, true] {
            if let Some(w) = only_live { if w != with_live { continue; } }
            let engine = engine_with(Collector::Copying, heap)?;
            let module = Module::from_file(&engine, dir.join("liveheap.wat"))?;
            let mut store = Store::new(&engine, ());
            let instance = Instance::new(&mut store, &module, &[])?;
            let build = instance.get_typed_func::<i32, ()>(&mut store, "build_live")?;
            let trees = instance.get_typed_func::<(f64, f64), f64>(&mut store, "trees")?;
            let t0 = cpu_now();
            if with_live { build.call(&mut store, live_n)?; }
            let build_s = cpu_now() - t0;
            let mut samples = Vec::new();
            for _ in 0..5 { let s = cpu_now(); let r = trees.call(&mut store, (10.0, 15.0))?; samples.push(cpu_now() - s); assert_eq!(r, 655350.0); }
            let g0 = cpu_now(); store.gc(None); let gc_s = cpu_now() - g0;
            println!("live\theap {}\tlive {}\ttrees15x10 {:.1} ms\tfull collection {:.1} ms\tbuild {:.0} ms\tpeak rss {:.0} MB", heap.map(|m| format!("{m} MB")).unwrap_or("default".into()), if with_live { format!("{live_n} records") } else { "none".into() }, median(samples) * 1e3, gc_s * 1e3, build_s * 1e3, rss_mb());
        }
    }
    Ok(())
}
