//! Same functions, production ABI, proof passes and code emitter; alternate
//! mutable-variable SSA construction with explicit typed block arguments.
use nupp_vm::{
    graph, image,
    interp::{Interp, Op},
    jit::Jit,
};
use std::{
    alloc::{GlobalAlloc, Layout, System},
    sync::atomic::{AtomicBool, AtomicUsize, Ordering::Relaxed},
    time::Instant,
};

struct Meter;
static LIVE: AtomicUsize = AtomicUsize::new(0);
static PEAK: AtomicUsize = AtomicUsize::new(0);
static BYTES: AtomicUsize = AtomicUsize::new(0);
static CALLS: AtomicUsize = AtomicUsize::new(0);
static ACTIVE: AtomicBool = AtomicBool::new(false);
fn add(n: usize) {
    let live = LIVE.fetch_add(n, Relaxed) + n;
    if ACTIVE.load(Relaxed) {
        PEAK.fetch_max(live, Relaxed);
        BYTES.fetch_add(n, Relaxed);
        CALLS.fetch_add(1, Relaxed);
    }
}
unsafe impl GlobalAlloc for Meter {
    unsafe fn alloc(&self, l: Layout) -> *mut u8 {
        let p = unsafe { System.alloc(l) };
        if !p.is_null() {
            add(l.size());
        }
        p
    }
    unsafe fn alloc_zeroed(&self, l: Layout) -> *mut u8 {
        let p = unsafe { System.alloc_zeroed(l) };
        if !p.is_null() {
            add(l.size());
        }
        p
    }
    unsafe fn dealloc(&self, p: *mut u8, l: Layout) {
        LIVE.fetch_sub(l.size(), Relaxed);
        unsafe { System.dealloc(p, l) }
    }
    unsafe fn realloc(&self, p: *mut u8, l: Layout, n: usize) -> *mut u8 {
        let p = unsafe { System.realloc(p, l, n) };
        if !p.is_null() {
            LIVE.fetch_sub(l.size(), Relaxed);
            add(n);
        }
        p
    }
}
#[cfg(feature = "allocation-metrics")]
#[global_allocator]
static ALLOC: Meter = Meter;

fn main() -> Result<(), String> {
    let args: Vec<_> = std::env::args().collect();
    let bytes = std::fs::read(args.get(1).ok_or("IMAGE [memory]")?).map_err(|e| e.to_string())?;
    let memory = args.get(2).is_some_and(|x| x == "memory");
    if memory && !cfg!(feature = "allocation-metrics") {
        return Err("memory mode requires --features allocation-metrics".into());
    }
    let mut input = Interp::new();
    if bytes.starts_with(graph::MAGIC) {
        graph::load_owned(&mut input, bytes)?;
    } else {
        image::load(&mut input, std::str::from_utf8(&bytes).map_err(|e| e.to_string())?)?;
    }
    let functions: Vec<_> = input
        .funcs
        .iter()
        .enumerate()
        .filter(|(_, f)| {
            f.code
                .iter()
                .any(|op| matches!(op, Op::SpanLen(..) | Op::VOp(..)))
        })
        .collect();
    if functions.is_empty() {
        return Err("no typed kernels in image".into());
    }
    let mut rows = Vec::new();
    // Measurements use an owning Interp so executable memory is released too.
    for round in 0..if memory { 1 } else { 5 } {
        CALLS.store(0, Relaxed);
        BYTES.store(0, Relaxed);
        let base = LIVE.load(Relaxed);
        PEAK.store(base, Relaxed);
        ACTIVE.store(memory, Relaxed);
        let start = Instant::now();
        let mut owner = Interp::new();
        owner.jit = Some(Box::new(Jit::new()));
        let mut sizes = Vec::new();
        let mut recovery = Vec::new();
        for &(fid, f) in &functions {
            let jit = owner.jit.as_mut().unwrap();
            let code = jit.compile_version(f, fid as u32, true)?;
            sizes.push(code.len);
            recovery.push(format!("{:?}", jit.last_recovery));
        }
        let micros = start.elapsed().as_secs_f64() * 1e6;
        ACTIVE.store(false, Relaxed);
        let peak = PEAK.load(Relaxed).saturating_sub(base);
        let bytes = BYTES.load(Relaxed);
        let calls = CALLS.load(Relaxed);
        // Output and code release are outside the measured interval.
        if memory || round > 0 {
            rows.push(serde_json::json!({"us":micros,"peak_requested_bytes":peak,"allocated_bytes":bytes,"allocation_calls":calls,"code_bytes":sizes,"recovery":recovery}));
        }
        drop(owner);
    }
    println!(
        "{}",
        serde_json::json!({"mode":if std::env::var_os("NUPP_CFG_TYPED").is_some(){"block-arguments"}else{"variables"},"memory":memory,"functions":functions.iter().map(|(_,f)| &f.name).collect::<Vec<_>>(),"instructions":functions.iter().map(|(_,f)|f.code.len()).sum::<usize>(),"samples":rows})
    );
    Ok(())
}
