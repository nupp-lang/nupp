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
    let args: Vec<String> = std::env::args().collect();
    if args.len() < 5 || args[1] != "run" { eprintln!("usage: nupp-vm run IMAGE MODULE FUNCTION [ARG...] [--repeat N] [--host] [--setup FN]"); std::process::exit(2); }
    let mut repeat = 0usize; let mut host = false; let mut setup: Option<String> = None; let mut call_args_text: Vec<String> = Vec::new();
    let mut i = 5;
    while i < args.len() {
        match args[i].as_str() { "--repeat" => { repeat = args[i + 1].parse().unwrap(); i += 2; } "--host" => { host = true; i += 1; } "--setup" => { setup = Some(args[i + 1].clone()); i += 2; } a => { call_args_text.push(a.to_string()); i += 1; } }
    }
    let text = std::fs::read_to_string(&args[2]).unwrap_or_else(|e| { eprintln!("image {}: {e}", args[2]); std::process::exit(1) });
    let mut it = Interp::new();
    let t0 = cpu_now();
    image::load(&mut it, &text).unwrap_or_else(|e| { eprintln!("load: {e}"); std::process::exit(1) });
    let load_s = cpu_now() - t0;
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
            eprintln!("{}", it.backtrace(t));
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
    let (ok, outcome) = (true, Outcome::Done(Value::NIL)); let _ = (ok, outcome);
}
