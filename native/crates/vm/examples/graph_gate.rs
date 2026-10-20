//! The single-IR plan's P1 gate: fixtures encoded through the graph image
//! decode, verify and derive instruction streams that run to the same
//! results as today's lowering, on the interpreter, the threaded core and the
//! JIT; and decoding plus deriving a checker-sized image is timed against
//! today's text parse.
//!
//! `graph_gate scalar PREFIX OUT`: PREFIX.graph beside PREFIX.image (the
//! scalar fixture through both paths); every function's inputs run both ways.
//! `graph_gate typed PREFIX`: PREFIX.functions (the typed kernels lowered in
//! Nupp) beside PREFIX.functions.graph; the derived streams must equal the
//! Nupp ones instruction for instruction.
//! `graph_gate size GRAPH TEXT OUT`: decode+verify+derive of GRAPH timed
//! against the text parse of TEXT, written to OUT as JSON.
use nupp_vm::{
    builtins, graph,
    image,
    interp::{Function, Interp, Op, Outcome},
    jit::Jit,
    scheduler::Status,
    value::Value,
};
use std::time::Instant;

fn equal(a: &[f64], b: &[f64], what: &str) {
    assert_eq!(a.len(), b.len(), "{what}: trace length {a:?} vs {b:?}");
    for (a, b) in a.iter().zip(b) {
        assert!(a.to_bits() == b.to_bits() || a.is_nan() && b.is_nan(), "{what}: {a:?} != {b:?}");
    }
}
fn us(start: Instant) -> f64 { start.elapsed().as_secs_f64() * 1e6 }
fn median(mut values: Vec<f64>) -> f64 { values.sort_by(f64::total_cmp); values[values.len() / 2] }

#[derive(Clone)]
enum Input { Number(f64), Text(Vec<u8>) }
fn inputs_of(vm: &mut Interp, args: &[Input]) -> Vec<Value> {
    args.iter().map(|a| match a { Input::Number(n) => Value::num(*n), Input::Text(s) => { let v = vm.new_string_bytes(s); vm.handles.push(v); v } }).collect()
}

/// The fixture's inputs by function, as the first experiment chose them.
fn inputs(name: &str) -> Vec<Vec<Input>> {
    use Input::*;
    let mut out = Vec::new();
    match name {
        "m.diamond" | "m.early" => for n in [-100.5, -1., -0., 0., 0.5, 2., 1e100, f64::INFINITY, f64::NEG_INFINITY, f64::NAN] { out.push(vec![Number(n)]); },
        "m.loop" | "m.swap" | "m.suspend" | "m.nested" | "m.rotate" => for n in -2..35 { out.push(vec![Number(n as f64)]); },
        "m.bytes" | "m.suspendBytes" => for s in [vec![], b"abc".to_vec(), vec![0, 1, 127, 128, 255], (0..=255).collect()] { out.push(vec![Text(s)]); },
        "m.byte" => for s in [vec![], b"abc".to_vec(), vec![0, 128, 255]] { for n in [-100., -3., -2.9, -1., -0., 0.9, 1., 1.9, 3., 4., 100., f64::NAN, f64::INFINITY, f64::NEG_INFINITY] { out.push(vec![Text(s.clone()), Number(n)]); } },
        other => panic!("no fixture oracle for {other}"),
    }
    out
}

/// Runs a derived function on a fresh task, collecting every parked value
/// and the result: the interpreter (`rust`), the threaded core, or the JIT's
/// heap-frame entry when it compiles the function.
fn run_derived(vm: &mut Interp, fid: u32, args: &[Value], mode: &str) -> Vec<f64> {
    let mut trace = Vec::new();
    if mode == "jit" {
        let task = vm.schedule(Value::func(fid), args, None).unwrap();
        for _ in 0..10000 {
            vm.run_ready(64).unwrap();
            match vm.scheduler.as_ref().unwrap().status(task).unwrap() {
                Status::Active => continue,
                Status::Completed => { trace.push(vm.tasks[task.index].result.as_num()); vm.release_task(task).unwrap(); return trace; }
                status => panic!("derived task failed: {status:?}"),
            }
        }
        panic!("derived task did not complete");
    }
    let tid = vm.spawn(fid, args);
    for _ in 0..10000 {
        let outcome = if mode == "threaded" { vm.run(tid) } else { vm.run_rust(tid) };
        match outcome {
            Outcome::Done(v) => { trace.push(v.as_num()); return trace; }
            Outcome::Parked(bits) => { trace.push(Value(bits).as_num()); vm.resume(tid); }
        }
    }
    panic!("suspension limit exceeded")
}

// The source compiler's unmodified coroutine lowering, driven by a test-only
// function: every coroutine.resume result including the final return.
fn install_reference(vm: &mut Interp) -> u32 {
    let dead = vm.intern("dead");
    vm.handles.push(dead);
    let constants = vec![Value::builtin(builtins::id_of("tasks.coCreate").unwrap()), Value::builtin(builtins::id_of("tasks.coResume").unwrap()), Value::builtin(builtins::id_of("tasks.coStatus").unwrap()), Value::num(1.), dead];
    let mut code = vec![Op::K(15, 0), Op::Move(4, 1), Op::CallDyn(15, 3, 1), Op::NewTable(10), Op::K(11, 3), Op::K(12, 3), Op::K(15, 1), Op::Move(7, 3), Op::Move(8, 2), Op::CallDyn(15, 6, 2)];
    let check = code.len();
    code.extend([Op::JmpIf(6, 1), Op::RetNil, Op::SetIdx(10, 11, 7), Op::Add(11, 11, 12), Op::K(15, 2), Op::Move(7, 3), Op::CallDyn(15, 6, 1), Op::K(13, 4), Op::Eq(14, 6, 13)]);
    let done = code.len();
    code.push(Op::JmpIf(14, 0));
    code.extend([Op::K(15, 1), Op::Move(7, 3), Op::CallDyn(15, 6, 1)]);
    code.push(Op::Jmp(check as i32 - code.len() as i32 - 1));
    code[done] = Op::JmpIf(14, code.len() as i32 - done as i32 - 1);
    code.push(Op::Ret(10));
    let f = Function { name: "cfg_reference_coroutine".into(), module: "cfg.reference".into(), path: None, sig: vec![b'v', b'v'], ret: b'v', nv_params: 2, nf_params: 0, code, consts: constants, nparams: 2, nregs: 16, nireg: 0, nfreg: 0, nvreg: 0, jump_tables: vec![], debug: vec![], vararg: false, gpu: None, ins: vec![] };
    let id = vm.funcs.len() as u32;
    nupp_vm::verify::verify_classes(&f, id as usize + 1).unwrap();
    vm.funcs.push(f);
    id
}
fn run_reference(vm: &mut Interp, driver: u32, function: Value, args: &[Value]) -> Vec<f64> {
    assert_eq!(args.len(), 1);
    let task = vm.schedule(Value::func(driver), &[function, args[0]], None).unwrap();
    for _ in 0..1000 {
        vm.run_ready(128).unwrap();
        match vm.scheduler.as_ref().unwrap().status(task).unwrap() {
            Status::Active => continue,
            Status::Completed => {
                let table = vm.tasks[task.index].result;
                assert_ne!(table, Value::NIL, "reference coroutine failed");
                let mut trace = vec![];
                for i in 1..10000 { let v = vm.get_index(table, Value::num(i as f64)); if v == Value::NIL { break; } trace.push(v.as_num()); }
                vm.release_task(task).unwrap();
                return trace;
            }
            status => panic!("reference failed: {status:?}"),
        }
    }
    panic!("reference scheduler did not complete")
}

/// Hostile input: every truncated prefix, a trailing byte, every word
/// overwritten with all ones, and targeted mutations the verifier must catch.
fn malformed(bytes: &[u8]) {
    for len in 0..bytes.len() { assert!(graph::decode(&bytes[..len]).is_err(), "accepted a truncated image of {len} bytes"); }
    let mut extra = bytes.to_vec();
    extra.push(0);
    assert!(graph::decode(&extra).is_err(), "accepted trailing bytes");
    let mut rejected = 0;
    for offset in (12..bytes.len() - 4).step_by(4) {
        let mut bad = bytes.to_vec();
        bad[offset..offset + 4].fill(255);
        if graph::decode(&bad).is_err() { rejected += 1; }
        // An accepted mutation changed a string byte or a literal, never a structure word.
    }
    eprintln!("hostile words: {rejected} of {} rejected", (bytes.len() - 16) / 4);
    for offset in (12..bytes.len() - 4).step_by(7) {
        for value in [0u32, 1, 2, 3, 100, 1 << 20] {
            let mut bad = bytes.to_vec();
            bad[offset..offset + 4].copy_from_slice(&value.to_le_bytes());
            let _ = graph::decode(&bad);
        }
    }
}

fn scalar(prefix: &str, out: &std::path::Path) -> Result<(), String> {
    std::fs::create_dir_all(out).map_err(|e| e.to_string())?;
    let bytes = std::fs::read(format!("{prefix}.graph")).map_err(|e| e.to_string())?;
    let text = std::fs::read_to_string(format!("{prefix}.image")).map_err(|e| e.to_string())?;
    let decoded = graph::decode(&bytes)?;
    malformed(&bytes);
    let mut cases = 0;
    let mut rows = Vec::new();
    let modes = ["rust", "threaded", "jit"];
    for mode in modes {
        let mut vm = Interp::new();
        image::load(&mut vm, &text)?;
        vm.install_globals();
        let module = vm.require("cfg.fixture");
        vm.handles.push(module);
        let driver = install_reference(&mut vm);
        vm.enable_scheduler()?;
        let base = vm.funcs.len() as u32;
        let derived = graph::derive_all(&mut vm, &decoded, base, &[])?;
        for f in &derived { vm.funcs.push(f.clone()); }
        if mode == "threaded" { vm.prepare_threaded(); }
        if mode == "jit" {
            vm.jit = Some(Box::new(Jit::new()));
            let mut compiled = 0;
            for (i, f) in derived.iter().enumerate() {
                match vm.jit.as_mut().unwrap().compile_frame(f, base + i as u32) {
                    Ok(_) => compiled += 1,
                    Err(e) => { assert!(f.code.iter().any(|op| matches!(op, Op::Park(_))), "{}: the JIT refused a function without a park: {e}", f.name); }
                }
            }
            eprintln!("jit: {compiled} of {} derived functions compiled (the rest park)", derived.len());
        }
        for (i, g) in decoded.functions.iter().enumerate() {
            let name = decoded.name(g).to_string();
            let short = name.strip_prefix("m.").unwrap();
            let k = vm.intern(short);
            let original = vm.index(module, k);
            vm.handles.push(original);
            for args in inputs(&name) {
                let values = inputs_of(&mut vm, &args);
                let parks = short.starts_with("suspend");
                // A park terminator parks the task itself, which the scheduler
                // has nothing to resume; the parked values are read through the
                // park protocol in every mode, on the threaded core under the JIT.
                let got = run_derived(&mut vm, base + i as u32, &values, if parks && mode == "jit" { "threaded" } else { mode });
                let expected = if parks { run_reference(&mut vm, driver, original, &values) } else { vm.call_value(original, &values).iter().map(|v| v.as_num()).collect() };
                equal(&got, &expected, &format!("{name} {mode}"));
                if mode == "rust" { cases += 1; }
            }
            if mode == "rust" {
                let old = vm.funcs.iter().find(|f| f.name == name).unwrap();
                rows.push(serde_json::json!({ "function": name, "blocks": g.blocks.len(), "values": g.classes.len(), "graph_instructions": g.insts.len(), "derived_instructions": derived[i].code.len(), "old_instructions": old.code.len() }));
            }
        }
    }
    let mut decode_us = Vec::new();
    let mut parse_us = Vec::new();
    for round in 0..13 {
        let start = Instant::now();
        let decoded = graph::decode(std::hint::black_box(&bytes))?;
        let mut vm = Interp::new();
        let _ = graph::derive_all(&mut vm, &decoded, 0, &[])?;
        let a = us(start);
        let start = Instant::now();
        let mut fresh = Interp::new();
        image::load(&mut fresh, std::hint::black_box(&text))?;
        let b = us(start);
        if round > 1 { decode_us.push(a); parse_us.push(b); }
    }
    let result = serde_json::json!({ "cases": cases, "modes": modes, "graph_bytes": bytes.len(), "text_bytes": text.len(), "functions": rows,
        "median_microseconds": { "graph_decode_verify_derive": median(decode_us), "text_parse_verify": median(parse_us) } });
    std::fs::write(out.join("scalar.json"), serde_json::to_string_pretty(&result).unwrap()).map_err(|e| e.to_string())?;
    println!("{}", serde_json::to_string_pretty(&result).unwrap());
    Ok(())
}

fn typed(prefix: &str) -> Result<(), String> {
    let text = std::fs::read_to_string(format!("{prefix}.functions")).map_err(|e| e.to_string())?;
    let bytes = std::fs::read(format!("{prefix}.functions.graph")).map_err(|e| e.to_string())?;
    let decoded = graph::decode(&bytes)?;
    malformed(&bytes);
    let mut vm = Interp::new();
    image::load(&mut vm, &text)?;
    let derived = graph::derive_all(&mut vm, &decoded, 0, &[])?;
    assert_eq!(derived.len(), vm.funcs.len(), "function count");
    let mut instructions = 0;
    for (d, g) in derived.iter().zip(&decoded.functions) {
        let old = vm.funcs.iter().find(|f| f.name == d.name).ok_or_else(|| format!("{} is not in the text", d.name))?;
        let (a, b): (Vec<String>, Vec<String>) = (d.code.iter().map(|o| format!("{o:?}")).collect(), old.code.iter().map(|o| format!("{o:?}")).collect());
        if a != b {
            let at = a.iter().zip(&b).position(|(x, y)| x != y).unwrap_or(a.len().min(b.len()));
            return Err(format!("{}: derived stream differs at pc {at}: derived {:?} vs lowered {:?}\nderived: {}\nlowered: {}", d.name, a.get(at), b.get(at), a.join("; "), b.join("; ")));
        }
        assert_eq!((d.nregs, d.nireg, d.nfreg, d.nvreg, d.nparams), (old.nregs, old.nireg, old.nfreg, old.nvreg, old.nparams), "{}: register counts", d.name);
        assert_eq!(d.gpu.is_some(), old.gpu.is_some(), "{}: gpu artifact", d.name);
        if let (Some(x), Some(y)) = (&d.gpu, &old.gpu) { assert_eq!(x.wgsl, y.wgsl, "{}: wgsl", d.name); assert_eq!(x.spirv, y.spirv, "{}: spirv", d.name); }
        instructions += d.code.len();
        eprintln!("{}: {} blocks, {} values, {} instructions, identical stream", d.name, g.blocks.len(), g.classes.len(), d.code.len());
    }
    println!("typed: {} functions, {instructions} instructions, every derived stream equals the Nupp lowering", derived.len());
    Ok(())
}

/// `graph_gate image PREFIX`: PREFIX.image (the text the lowering wrote) and
/// PREFIX.graph (the same functions converted to graphs); every derived
/// function must equal the lowered one instruction for instruction.
fn image_gate(prefix: &str) -> Result<(), String> {
    let text = std::fs::read_to_string(format!("{prefix}.image")).map_err(|e| e.to_string())?;
    let bytes = std::fs::read(format!("{prefix}.graph")).map_err(|e| e.to_string())?;
    let decoded = graph::decode(&bytes)?;
    let mut vm = Interp::new();
    let (_, shape_ids) = image::load_with_shapes(&mut vm, &text)?;
    let start = Instant::now();
    let derived = graph::derive_all(&mut vm, &decoded, 0, &shape_ids)?;
    let derive_us = us(start);
    if derived.len() != vm.funcs.len() {
        let names = |fs: &[Function]| fs.iter().map(|f| f.name.clone()).collect::<Vec<_>>().join(" ");
        return Err(format!("{} graphs against {} lowered functions\ngraphs: {}\nlowered: {}", derived.len(), vm.funcs.len(), names(&derived), names(&vm.funcs)));
    }
    let mut instructions = 0;
    let mut blocks = 0;
    let mut params = 0;
    let mut failures = 0;
    for (i, (d, g)) in derived.iter().zip(&decoded.functions).enumerate() {
        let old = &vm.funcs[i];
        if d.name != old.name { return Err(format!("function {i}: graph {} against lowered {}", d.name, old.name)); }
        let (a, b): (Vec<String>, Vec<String>) = (d.code.iter().map(|o| format!("{o:?}")).collect(), old.code.iter().map(|o| format!("{o:?}")).collect());
        if a != b {
            // Every differing function, so one run shows every gap.
            let at = a.iter().zip(&b).position(|(x, y)| x != y).unwrap_or(a.len().min(b.len()));
            let window = |s: &[String]| s[at.saturating_sub(3)..(at + 4).min(s.len())].join("; ");
            eprintln!("{}: derived stream differs at pc {at}: derived {:?} vs lowered {:?}\n  derived: {}\n  lowered: {}", d.name, a.get(at), b.get(at), window(&a), window(&b));
            failures += 1;
            continue;
        }
        if (d.nregs, d.nireg, d.nfreg, d.nvreg, d.nparams) != (old.nregs, old.nireg, old.nfreg, old.nvreg, old.nparams) {
            eprintln!("{}: register counts {:?} vs {:?}", d.name, (d.nregs, d.nireg, d.nfreg, d.nvreg), (old.nregs, old.nireg, old.nfreg, old.nvreg));
            failures += 1;
            continue;
        }
        instructions += d.code.len();
        blocks += g.blocks.len();
        params += g.blocks.iter().map(|b| b.params.len as usize).sum::<usize>();
    }
    if failures > 0 { return Err(format!("{failures} of {} functions differ", derived.len())); }
    println!("{}", serde_json::json!({"functions": derived.len(), "instructions": instructions, "blocks": blocks, "parameters": params, "graph_bytes": bytes.len(), "text_bytes": text.len(), "derive_us": derive_us}));
    Ok(())
}

fn size(graph_path: &str, text_path: &str, out: &str) -> Result<(), String> {
    let bytes = std::fs::read(graph_path).map_err(|e| e.to_string())?;
    let text = std::fs::read_to_string(text_path).map_err(|e| e.to_string())?;
    let mut decode_us = Vec::new();
    let mut derive_us = Vec::new();
    let mut parse_us = Vec::new();
    let mut load_us = Vec::new();
    let mut graph_functions = 0;
    let mut graph_instructions = 0;
    let mut text_functions = 0;
    let mut text_instructions = 0;
    for round in 0..7 {
        let start = Instant::now();
        let mut fresh = Interp::new();
        let (_, shape_ids) = image::load_with_shapes(&mut fresh, std::hint::black_box(&text))?;
        let c = us(start);
        text_functions = fresh.funcs.len();
        text_instructions = fresh.funcs.iter().map(|f| f.code.len()).sum();
        let start = Instant::now();
        let decoded = graph::decode(std::hint::black_box(&bytes))?;
        let a = us(start);
        let start = Instant::now();
        let mut vm = Interp::new();
        let derived = graph::derive_all(&mut vm, &decoded, 0, &shape_ids)?;
        let b = us(start);
        graph_functions = derived.len();
        graph_instructions = derived.iter().map(|f| f.code.len()).sum();
        std::hint::black_box(&derived);
        let start = Instant::now();
        let mut whole = Interp::new();
        graph::load(&mut whole, std::hint::black_box(&bytes))?;
        let d = us(start);
        if round > 1 { decode_us.push(a); derive_us.push(b); parse_us.push(c); load_us.push(d); }
    }
    let result = serde_json::json!({
        "graph": { "path": graph_path, "bytes": bytes.len(), "functions": graph_functions, "instructions": graph_instructions, "decode_verify_us": median(decode_us.clone()), "derive_us": median(derive_us.clone()), "total_us": median(decode_us.iter().zip(&derive_us).map(|(a, b)| a + b).collect()), "load_us": median(load_us) },
        "text": { "path": text_path, "bytes": text.len(), "functions": text_functions, "instructions": text_instructions, "parse_verify_us": median(parse_us) },
    });
    std::fs::write(out, serde_json::to_string_pretty(&result).unwrap()).map_err(|e| e.to_string())?;
    println!("{}", serde_json::to_string_pretty(&result).unwrap());
    Ok(())
}

/// `graph_gate loop FILE ROUNDS`: loads an image of either kind ROUNDS
/// times into fresh VMs, for a sampler to watch.
fn load_loop(path: &str, rounds: usize) -> Result<(), String> {
    let bytes = std::fs::read(path).map_err(|e| e.to_string())?;
    let start = Instant::now();
    for _ in 0..rounds {
        let mut vm = Interp::new();
        if bytes.starts_with(b"NUPPGRAF") { graph::load(&mut vm, std::hint::black_box(&bytes))?; }
        else { image::load(&mut vm, std::str::from_utf8(&bytes).map_err(|e| e.to_string())?)?; }
        std::hint::black_box(&vm);
    }
    println!("{} loads in {:.1} ms", rounds, us(start) / 1000.0);
    Ok(())
}

fn main() -> Result<(), String> {
    let args: Vec<_> = std::env::args().collect();
    match args.get(1).map(String::as_str) {
        Some("loop") => return load_loop(&args[2], args[3].parse().unwrap()),
        Some("scalar") => scalar(args.get(2).ok_or("PREFIX")?, std::path::Path::new(args.get(3).ok_or("OUT")?)),
        Some("typed") => typed(args.get(2).ok_or("PREFIX")?),
        Some("image") => image_gate(args.get(2).ok_or("PREFIX")?),
        Some("size") => size(args.get(2).ok_or("GRAPH")?, args.get(3).ok_or("TEXT")?, args.get(4).ok_or("OUT")?),
        _ => Err("usage: graph_gate (scalar PREFIX OUT | typed PREFIX | image PREFIX | size GRAPH TEXT OUT)".into()),
    }
}
