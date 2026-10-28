//! Measurement control only. The candidate backend is written in Nupp.
mod execute;
use cranelift_codegen::Context;
use cranelift_codegen::ir::{ExternalName, UserExternalName};
use cranelift_codegen::settings::{self, Configurable};
use sha2::{Digest, Sha256};
use std::collections::HashMap;
use std::time::Instant;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args: Vec<String> = std::env::args().collect();
    if args.get(1).map(String::as_str) == Some("execute") {
        return execute::run(&args[2..]);
    }
    if args.len() != 5 {
        return Err("usage: control CORPUS.clif default|single_pass none|speed REPEATS".into());
    }
    let repeats: usize = args[4].parse()?;
    if repeats == 0 || repeats > 100 {
        return Err("repeats must be in 1..100".into());
    }
    let text = std::fs::read_to_string(&args[1])?;
    let start = Instant::now();
    let mut functions = cranelift_reader::parse_functions(&text)?;
    let parse_ns = start.elapsed().as_nanos() as u64;
    if functions.is_empty() {
        return Err("empty corpus".into());
    }
    let mut flags = settings::builder();
    flags.set("opt_level", &args[3])?;
    flags.set("is_pic", "true")?;
    flags.set("enable_verifier", "false")?;
    match args[2].as_str() {
        "default" => (),
        "single_pass" => flags.set("regalloc_algorithm", "single_pass")?,
        _ => return Err("allocator must be default or single_pass".into()),
    }
    let isa = cranelift_native::builder()?.finish(settings::Flags::new(flags))?;
    let names: HashMap<String, u32> = functions
        .iter()
        .enumerate()
        .map(|(index, function)| {
            (
                function
                    .name
                    .to_string()
                    .trim_start_matches('%')
                    .to_string(),
                index as u32,
            )
        })
        .collect();
    let mut imports: HashMap<String, u32> = HashMap::new();
    for function in &mut functions {
        let references: Vec<_> = function
            .dfg
            .ext_funcs
            .iter()
            .filter_map(|(reference, data)| match &data.name {
                ExternalName::TestCase(name) => Some((reference, name.to_string())),
                _ => None,
            })
            .collect();
        for (reference, name) in references {
            let name = name.trim_start_matches('%');
            let internal = names.contains_key(name);
            let index = if internal {
                names[name]
            } else {
                let next = imports.len() as u32;
                *imports.entry(name.to_string()).or_insert(next)
            };
            if !internal {
                let signature = function.dfg.ext_funcs[reference].signature;
                let mut host_signature = function.dfg.signatures[signature].clone();
                host_signature.call_conv = isa.default_call_conv();
                let host_signature = function.import_signature(host_signature);
                function.dfg.ext_funcs[reference].signature = host_signature;
            }
            let id = function.declare_imported_user_function(UserExternalName {
                namespace: if internal { 0 } else { 1 },
                index,
            });
            let data = &mut function.dfg.ext_funcs[reference];
            data.name = ExternalName::user(id);
            data.colocated = internal;
        }
    }
    let mut rows = Vec::new();
    for repeat in 0..repeats {
        for function in &functions {
            let input_instructions: usize = function
                .layout
                .blocks()
                .map(|block| function.layout.block_insts(block).count())
                .sum();
            let mut context = Context::for_function(function.clone());
            let start = Instant::now();
            let compiled = context
                .compile(isa.as_ref(), &mut Default::default())
                .map_err(|error| format!("{}: {error:?}", function.name))?;
            let compile_ns = start.elapsed().as_nanos() as u64;
            let bytes = std::hint::black_box(compiled.code_buffer()).len();
            rows.push(serde_json::json!({
                "repeat": repeat, "name": function.name.to_string(),
                "inputInstructions": input_instructions, "compileNs": compile_ns,
                "codeBytes": bytes,
                "nsPerInputInstruction": compile_ns as f64 / input_instructions.max(1) as f64,
                "nsPerCodeWord": compile_ns as f64 / (bytes / 4).max(1) as f64,
            }));
        }
    }
    println!(
        "{}",
        serde_json::to_string_pretty(&serde_json::json!({
            "scope": "Cranelift machine-code control; parsing and function cloning excluded from compileNs; code is not linked or executed",
            "corpusSha256": format!("{:x}", Sha256::digest(text.as_bytes())),
            "architecture": std::env::consts::ARCH, "allocator": args[2],
            "optLevel": args[3], "flags": isa.flags().to_string(),
            "functions": functions.len(), "parseNs": parse_ns, "results": rows,
        }))?
    );
    Ok(())
}
