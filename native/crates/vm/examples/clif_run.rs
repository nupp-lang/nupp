//! Compiles a CLIF text file just in time and calls one of its functions:
//! the test harness for Nupp lowered to CLIF. `%name` references between the
//! file's functions resolve to each other; nothing else is linked.
use cranelift_codegen::ir::{
    AbiParam, ExternalName, InstBuilder, MemFlagsData, Signature, UserExternalName, types,
};
use cranelift_frontend::{FunctionBuilder, FunctionBuilderContext};
use cranelift_jit::{JITBuilder, JITModule};
use cranelift_module::{Linkage, Module, default_libcall_names};
use std::collections::HashMap;

fn main() -> Result<(), String> {
    let args: Vec<String> = std::env::args().collect();
    let path = args.get(1).ok_or("CLIF file required")?;
    let entry = args.get(2).ok_or("function name required")?;
    let text = std::fs::read_to_string(path).map_err(|e| e.to_string())?;
    let functions = cranelift_reader::parse_functions(&text).map_err(|e| e.to_string())?;
    let builder = JITBuilder::new(default_libcall_names()).map_err(|e| e.to_string())?;
    let mut module = JITModule::new(builder);
    let conv = module.isa().default_call_conv();
    let mut ids = HashMap::new();
    let mut signatures = HashMap::new();
    for function in &functions {
        let name = function.name.to_string().trim_start_matches('%').to_string();
        let mut signature = function.signature.clone();
        signature.call_conv = conv;
        let id = module
            .declare_function(&name, Linkage::Export, &signature)
            .map_err(|e| e.to_string())?;
        ids.insert(name.clone(), id);
        signatures.insert(name, signature);
    }
    let mut ctx = module.make_context();
    for mut function in functions {
        let name = function.name.to_string().trim_start_matches('%').to_string();
        function.signature.call_conv = conv;
        for (_, signature) in function.dfg.signatures.iter_mut() {
            signature.call_conv = conv;
        }
        let references: Vec<_> = function
            .dfg
            .ext_funcs
            .iter()
            .filter_map(|(reference, data)| match &data.name {
                ExternalName::TestCase(callee) => Some((reference, callee.to_string())),
                _ => None,
            })
            .collect();
        for (reference, callee) in references {
            let callee = callee.trim_start_matches('%');
            let id = *ids.get(callee).ok_or_else(|| format!("{name} calls unknown {callee}"))?;
            let user = function.declare_imported_user_function(UserExternalName {
                namespace: 0,
                index: id.as_u32(),
            });
            let data = &mut function.dfg.ext_funcs[reference];
            data.name = ExternalName::user(user);
            data.colocated = true;
        }
        ctx.func = function;
        module
            .define_function(ids[&name], &mut ctx)
            .map_err(|e| format!("{name}: {e}"))?;
        module.clear_context(&mut ctx);
    }
    // A trampoline with one shape: words in, a word out, so the harness calls
    // every signature through the same Rust type.
    let target = signatures.get(entry).ok_or_else(|| format!("no function {entry}"))?.clone();
    let mut tramp_sig = Signature::new(conv);
    tramp_sig.params.push(AbiParam::new(types::I64));
    tramp_sig.params.push(AbiParam::new(types::I64));
    let tramp = module
        .declare_function("__nupp_run", Linkage::Export, &tramp_sig)
        .map_err(|e| e.to_string())?;
    ctx.func.signature = tramp_sig;
    {
        let mut fbc = FunctionBuilderContext::new();
        let mut b = FunctionBuilder::new(&mut ctx.func, &mut fbc);
        let block = b.create_block();
        b.append_block_params_for_function_params(block);
        b.switch_to_block(block);
        let (words, out) = (b.block_params(block)[0], b.block_params(block)[1]);
        let flags = MemFlagsData::new().with_notrap();
        let mut call_args = Vec::new();
        for (index, param) in target.params.iter().enumerate() {
            let word = b.ins().load(types::I64, flags, words, (index * 8) as i32);
            call_args.push(match param.value_type {
                types::F64 => b.ins().bitcast(types::F64, MemFlagsData::new(), word),
                types::I8 => b.ins().ireduce(types::I8, word),
                types::I32 => b.ins().ireduce(types::I32, word),
                _ => word,
            });
        }
        let callee = module.declare_func_in_func(ids[entry], b.func);
        let call = b.ins().call(callee, &call_args);
        if let Some(result) = b.inst_results(call).first().copied() {
            let word = match target.returns[0].value_type {
                types::F64 => b.ins().bitcast(types::I64, MemFlagsData::new(), result),
                types::I8 | types::I32 => b.ins().uextend(types::I64, result),
                _ => result,
            };
            b.ins().store(flags, word, out, 0);
        }
        b.ins().return_(&[]);
        b.seal_all_blocks();
        b.finalize(module.target_config());
    }
    module.define_function(tramp, &mut ctx).map_err(|e| e.to_string())?;
    module.finalize_definitions().map_err(|e| e.to_string())?;
    let run: extern "C" fn(*const u64, *mut u64) =
        unsafe { std::mem::transmute(module.get_finalized_function(tramp)) };
    let given = &args[3..];
    if given.len() != target.params.len() {
        return Err(format!("{entry} takes {} arguments", target.params.len()));
    }
    // `buffer:N` passes the address of N zeroed bytes that live for the call.
    let mut buffers: Vec<Vec<u64>> = Vec::new();
    let words: Vec<u64> = given
        .iter()
        .zip(&target.params)
        .map(|(text, param)| match param.value_type {
            _ if text.starts_with("buffer:") => {
                let bytes: usize = text["buffer:".len()..].parse().map_err(|_| "buffer size".parse::<f64>().unwrap_err())?;
                buffers.push(vec![0u64; bytes.div_ceil(8).max(1)]);
                Ok(buffers.last().unwrap().as_ptr() as u64)
            }
            types::F64 => text.parse::<f64>().map(f64::to_bits),
            types::I8 => match text.as_str() {
                "true" => Ok(1),
                "false" => Ok(0),
                other => other.parse::<u64>(),
            }
            .map_err(|_| "boolean argument".parse::<f64>().unwrap_err()),
            _ => text.parse::<i64>().map(|v| v as u64).or_else(|_| text.parse::<u64>().map_err(|_| "integer".parse::<f64>().unwrap_err())),
        })
        .collect::<Result<_, _>>()
        .map_err(|e| format!("bad argument: {e}"))?;
    let mut out = 0u64;
    run(words.as_ptr(), &mut out);
    if let Some(result) = target.returns.first() {
        match result.value_type {
            types::F64 => println!("{}", f64::from_bits(out)),
            types::I8 => println!("{}", out & 1 != 0),
            _ => println!("{}", out as i64),
        }
    } else {
        println!("nil");
    }
    Ok(())
}
