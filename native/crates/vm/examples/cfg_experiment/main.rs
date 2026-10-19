mod adapter;
mod graph;
mod native;
mod reference;
use native::Input::{Number, Text};
use nupp_vm::interp::Interp;
use std::{path::Path, time::Instant};

fn equal(a: &[f64], b: &[f64]) {
    assert_eq!(a.len(), b.len(), "trace length");
    for (a, b) in a.iter().zip(b) {
        assert!(
            a.to_bits() == b.to_bits() || a.is_nan() && b.is_nan(),
            "{a:?} != {b:?}"
        );
    }
}
fn us(start: Instant) -> f64 {
    start.elapsed().as_secs_f64() * 1e6
}
fn median(mut values: Vec<f64>) -> f64 {
    values.sort_by(f64::total_cmp);
    values[values.len() / 2]
}

fn malformed_tests(bytes: &[u8], graphs: &[graph::Graph]) {
    for len in 0..bytes.len() {
        assert!(
            graph::decode(&bytes[..len]).is_err(),
            "accepted truncated image"
        );
    }
    let mut extra = bytes.to_vec();
    extra.push(0);
    assert!(graph::decode(&extra).is_err());
    let mut bad = graphs.to_vec();
    bad[0].nodes[0][0] = 999;
    assert!(graph::decode(&graph::encode(&bad)).is_err());
    let mut bad = graphs.to_vec();
    bad[0].nodes[0][1] = u32::MAX;
    assert!(graph::decode(&graph::encode(&bad)).is_err());
    let mut bad = graphs.to_vec();
    bad[0].nodes[1][2] = bad[0].nodes[1][1];
    assert!(graph::decode(&graph::encode(&bad)).is_err());
    let mut bad = graphs.to_vec();
    bad[0].edges[0].target = u32::MAX;
    assert!(graph::decode(&graph::encode(&bad)).is_err());
    let mut bad = graphs.to_vec();
    bad[0].edges[0].args.len -= 1;
    assert!(graph::decode(&graph::encode(&bad)).is_err());
    let mut large_pool = graphs[0].clone();
    large_pool.constants.resize(u16::MAX as usize, 0.);
    assert!(adapter::lower(&large_pool).is_err());
    let mut bad = graphs.to_vec();
    bad[0].types[0] = graph::TEXT;
    assert!(graph::decode(&graph::encode(&bad)).is_err());
    let mut bad = graphs.to_vec();
    bad[0].nodes[1][1] = bad[0].nodes[0][1];
    assert!(graph::decode(&graph::encode(&bad)).is_err());
    // Decode hostile words without indexing or allocating from unchecked counts.
    for offset in (8..bytes.len().saturating_sub(4)).step_by(13) {
        let mut bad = bytes.to_vec();
        bad[offset..offset + 4].fill(255);
        let _ = graph::decode(&bad);
    }
}

fn main() -> Result<(), String> {
    let args: Vec<_> = std::env::args().collect();
    let prefix = args
        .get(1)
        .ok_or("usage: cfg_experiment PREFIX [OUTPUT_DIRECTORY]")?;
    let out = Path::new(
        args.get(2)
            .map(String::as_str)
            .unwrap_or("/private/tmp/nupp-cfg-results"),
    );
    std::fs::create_dir_all(out).map_err(|e| e.to_string())?;
    let bytes = std::fs::read(format!("{prefix}.cfg")).map_err(|e| e.to_string())?;
    let text = std::fs::read_to_string(format!("{prefix}.image")).map_err(|e| e.to_string())?;
    let raw = graph::decode(&bytes)?;
    malformed_tests(&bytes, &raw);
    let graphs: Vec<_> = raw.iter().map(graph::Graph::prune).collect();
    for g in &graphs {
        g.verify()?;
    }
    let packed = graph::encode(&graphs);
    assert_eq!(graphs, graph::decode(&packed)?);
    std::fs::write(out.join("optimized.cfg"), &packed).map_err(|e| e.to_string())?;
    let native = native::Native::compile(&graphs, false, true)?;
    let optimized = native::Native::compile(&graphs, true, false)?;
    let mut vm = Interp::new();
    nupp_vm::image::load(&mut vm, &text)?;
    vm.install_globals();
    let module = vm.require("cfg.fixture");
    vm.handles.push(module);
    let driver = reference::install(&mut vm);
    vm.enable_scheduler()?;
    let mut cases = 0;
    for (i, g) in graphs.iter().enumerate() {
        let k = vm.intern(&g.name);
        let function = vm.index(module, k);
        vm.handles.push(function);
        let mut inputs: Vec<Vec<native::Input>> = Vec::new();
        match g.name.as_str() {
            "diamond" | "early" => {
                for n in [
                    -100.5,
                    -1.,
                    -0.,
                    0.,
                    0.5,
                    2.,
                    1e100,
                    f64::INFINITY,
                    f64::NEG_INFINITY,
                    f64::NAN,
                ] {
                    inputs.push(vec![Number(n)]);
                }
            }
            "loop" | "swap" | "suspend" | "nested" | "rotate" => {
                for n in -2..35 {
                    inputs.push(vec![Number(n as f64)]);
                }
            }
            "bytes" | "suspendBytes" => {
                for s in [
                    vec![],
                    b"abc".to_vec(),
                    vec![0, 1, 127, 128, 255],
                    (0..=255).collect(),
                ] {
                    inputs.push(vec![Text(s)]);
                }
            }
            "byte" => {
                for s in [vec![], b"abc".to_vec(), vec![0, 128, 255]] {
                    for n in [
                        -100.,
                        -3.,
                        -2.9,
                        -1.,
                        -0.,
                        0.9,
                        1.,
                        1.9,
                        3.,
                        4.,
                        100.,
                        f64::NAN,
                        f64::INFINITY,
                        f64::NEG_INFINITY,
                    ] {
                        inputs.push(vec![Text(s.clone()), Number(n)]);
                    }
                }
            }
            name => return Err(format!("no fixture oracle for {name}")),
        }
        for args in inputs {
            let direct = native.run(i, g, &args);
            equal(&direct, &optimized.run(i, g, &args));
            equal(&direct, &adapter::run(g, &args, false));
            equal(&direct, &adapter::run(g, &args, true));
            if g.name == "suspend" {
                let Number(n) = args[0] else { unreachable!() };
                let mut trace = vec![];
                let mut sum = 0.;
                for i in 0..(n.max(0.) as usize) {
                    sum += i as f64;
                    trace.push(sum);
                }
                trace.push(sum);
                equal(&direct, &trace);
                let values = adapter::inputs(&mut vm, &args);
                equal(&direct, &reference::run(&mut vm, driver, function, &values));
            } else if g.name == "suspendBytes" {
                let values = adapter::inputs(&mut vm, &args);
                equal(&direct, &reference::run(&mut vm, driver, function, &values));
            } else {
                let values = adapter::inputs(&mut vm, &args);
                let expected = vm.call_value(function, &values);
                equal(
                    &direct,
                    &expected.iter().map(|v| v.as_num()).collect::<Vec<_>>(),
                );
            }
            cases += 1;
        }
        std::fs::write(
            out.join(format!("{}.clif", g.name)),
            &native.functions[i].clif,
        )
        .map_err(|e| e.to_string())?;
    }
    let old_functions: Vec<_> = graphs
        .iter()
        .map(|g| {
            vm.funcs
                .iter()
                .find(|f| f.name == format!("m.{}", g.name))
                .unwrap()
                .clone()
        })
        .collect();
    let mut load_cfg = vec![];
    let mut load_image = vec![];
    let mut prune = vec![];
    let mut compile_cfg = vec![];
    let mut compile_image = vec![];
    let mut adapt = vec![];
    for round in 0..13 {
        let start = Instant::now();
        let loaded = graph::decode(std::hint::black_box(&bytes))?;
        let a = us(start);
        let start = Instant::now();
        let _ = loaded.iter().map(graph::Graph::prune).collect::<Vec<_>>();
        let b = us(start);
        let start = Instant::now();
        let mut fresh = Interp::new();
        nupp_vm::image::load(&mut fresh, std::hint::black_box(&text))?;
        let c = us(start);
        let start = Instant::now();
        let _ = graphs
            .iter()
            .map(adapter::lower)
            .collect::<Result<Vec<_>, _>>()?;
        let d = us(start);
        let graph_compile = || -> Result<f64, String> {
            let start = Instant::now();
            let code = native::Native::compile(&graphs, false, false)?;
            let elapsed = us(start);
            std::hint::black_box(&code);
            Ok(elapsed)
        };
        let old_compile = || -> Result<f64, String> {
            let start = Instant::now();
            let mut jit = nupp_vm::jit::Jit::new();
            for (fid, f) in old_functions.iter().enumerate() {
                jit.compile_frame(f, fid as u32)?;
            }
            let elapsed = us(start);
            std::hint::black_box(&jit);
            Ok(elapsed)
        };
        let (e, f) = if round % 2 == 0 {
            (graph_compile()?, old_compile()?)
        } else {
            let f = old_compile()?;
            (graph_compile()?, f)
        };
        if round > 1 {
            load_cfg.push(a);
            prune.push(b);
            load_image.push(c);
            adapt.push(d);
            compile_cfg.push(e);
            compile_image.push(f);
        }
    }
    let rows:Vec<_>=graphs.iter().zip(&raw).zip(&native.functions).zip(&old_functions).map(|(((g,r),c),f)|serde_json::json!({
        "function":g.name,"blocks":g.blocks.len(),"ssa_values_before":r.types.len(),"ssa_values_after":g.types.len(),
        "graph_payload_bytes":g.size(),"graph_nodes":g.nodes.len(),"old_instructions":f.code.len(),"adapter_instructions":adapter::lower(g).unwrap().code.len(),
        "resume_parameters":g.blocks.iter().filter(|b|b.term==3).map(|b|g.successors(b)[0].args.len).collect::<Vec<_>>(),"native_code_bytes":c.code_bytes
    })).collect();
    let result = serde_json::json!({"cases":cases,"raw_graph_bytes":bytes.len(),"pruned_graph_bytes":packed.len(),"old_text_image_bytes":text.len(),"functions":rows,
        "settings":{"arch":std::env::consts::ARCH,"os":std::env::consts::OS,"jit_opt":std::env::var("JIT_OPT").unwrap_or("none".into()),"old_jit_verifier":std::env::var("JIT_VERIFY").is_ok(),"graph_jit_verifier":true},
        "median_microseconds":{"graph_decode_verify":median(load_cfg),"graph_prune":median(prune),"old_image_load_verify":median(load_image),"graph_to_vm_verify":median(adapt),"graph_to_native":median(compile_cfg.clone()),"old_to_native_frame":median(compile_image.clone())},
        "graph_compile_samples_us":compile_cfg,"old_compile_samples_us":compile_image,
        "limits":"Closed scalar subset; native resume ABI uses rooted host strings and has no production GC, deopt, patching, errors or scheduler integration. Compile times compare different runtime obligations, not equivalent production backends. All outputs and yield traces checked against original CST lowering; graph execution uses a private resume ABI and the Park adapter."});
    std::fs::write(
        out.join("results.json"),
        serde_json::to_string_pretty(&result).unwrap(),
    )
    .map_err(|e| e.to_string())?;
    println!("{}", serde_json::to_string_pretty(&result).unwrap());
    Ok(())
}
