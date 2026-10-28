//! Test-only scalar execution adapter; it does not implement MIR operations.
use cranelift_codegen::ir::{AbiParam, InstBuilder, MemFlagsData, Opcode, Type, Value, types};
use cranelift_frontend::{FunctionBuilder, FunctionBuilderContext};
use cranelift_jit::{JITBuilder, JITModule};
use cranelift_module::{Linkage, Module, default_libcall_names};
use std::error::Error;

fn scalar(kind: Type) -> bool {
    matches!(
        kind,
        types::I8 | types::I16 | types::I32 | types::I64 | types::F32 | types::F64
    )
}

fn argument(b: &mut FunctionBuilder, word: Value, kind: Type) -> Value {
    match kind {
        types::I64 => word,
        types::F64 => b.ins().bitcast(types::F64, MemFlagsData::new(), word),
        types::F32 => {
            let narrow = b.ins().ireduce(types::I32, word);
            b.ins().bitcast(types::F32, MemFlagsData::new(), narrow)
        }
        _ => b.ins().ireduce(kind, word),
    }
}

fn result(b: &mut FunctionBuilder, value: Value, kind: Type) -> Value {
    match kind {
        types::I64 => value,
        types::F64 => b.ins().bitcast(types::I64, MemFlagsData::new(), value),
        types::F32 => {
            let narrow = b.ins().bitcast(types::I32, MemFlagsData::new(), value);
            b.ins().uextend(types::I64, narrow)
        }
        _ => b.ins().uextend(types::I64, value),
    }
}

pub fn run(args: &[String]) -> Result<(), Box<dyn Error>> {
    if args.len() != 3 {
        return Err("usage: control execute CASE.clif INPUT.bin OUTPUT.bin".into());
    }
    let text = std::fs::read_to_string(&args[0])?;
    let mut functions = cranelift_reader::parse_functions(&text)?;
    if functions.len() != 1 {
        return Err("execute requires exactly one self-contained function".into());
    }
    let mut function = functions.pop().unwrap();
    let signature = &function.signature;
    if signature.params.len() > 256
        || signature.returns.is_empty()
        || signature.returns.len() > 2
        || signature
            .params
            .iter()
            .chain(&signature.returns)
            .any(|p| !scalar(p.value_type))
        || !function.dfg.ext_funcs.is_empty()
        || function.layout.blocks().any(|block| {
            function.layout.block_insts(block).any(|inst| {
                matches!(
                    function.dfg.insts[inst].opcode(),
                    Opcode::Call
                        | Opcode::CallIndirect
                        | Opcode::ReturnCall
                        | Opcode::ReturnCallIndirect
                )
            })
        })
    {
        return Err("execute supports scalar leaf kernels with one or two results".into());
    }
    let input = std::fs::read(&args[1])?;
    if input.len() != signature.params.len() * 8 {
        return Err("input must contain exactly one little-endian u64 per parameter".into());
    }
    let words: Vec<u64> = input
        .chunks_exact(8)
        .map(|word| u64::from_le_bytes(word.try_into().unwrap()))
        .collect();
    let builder = JITBuilder::with_flags(
        &[("opt_level", "none"), ("enable_verifier", "true")],
        default_libcall_names(),
    )?;
    let mut module = JITModule::new(builder);
    if module.target_config().pointer_type() != types::I64 {
        return Err("execute requires a 64-bit host".into());
    }
    // Only the public boundary changes convention; the kernel's operations and
    // stack slots are the exact parsed input. There are no guest or host calls.
    function.signature.call_conv = module.isa().default_call_conv();
    let signature = function.signature.clone();
    let kernel = module.declare_function("__kernel", Linkage::Local, &signature)?;
    let mut context = module.make_context();
    context.func = function;
    module.define_function(kernel, &mut context)?;
    module.clear_context(&mut context);

    let mut wrapper_signature = module.make_signature();
    wrapper_signature
        .params
        .extend([AbiParam::new(types::I64), AbiParam::new(types::I64)]);
    let wrapper = module.declare_function("__words", Linkage::Export, &wrapper_signature)?;
    context.func.signature = wrapper_signature;
    {
        let mut builder_context = FunctionBuilderContext::new();
        let mut b = FunctionBuilder::new(&mut context.func, &mut builder_context);
        let block = b.create_block();
        b.append_block_params_for_function_params(block);
        b.switch_to_block(block);
        let input = b.block_params(block)[0];
        let output = b.block_params(block)[1];
        let memory = MemFlagsData::new().with_notrap();
        let mut arguments = Vec::new();
        for (index, param) in signature.params.iter().enumerate() {
            let word = b.ins().load(types::I64, memory, input, (index * 8) as i32);
            arguments.push(argument(&mut b, word, param.value_type));
        }
        let target = module.declare_func_in_func(kernel, b.func);
        let call = b.ins().call(target, &arguments);
        let values = b.inst_results(call).to_vec();
        for (index, value) in values.into_iter().enumerate() {
            let word = result(&mut b, value, signature.returns[index].value_type);
            b.ins()
                .store(memory, word, output, ((index + 1) * 8) as i32);
        }
        b.ins().return_(&[]);
        b.seal_all_blocks();
        b.finalize(module.target_config());
    }
    module.define_function(wrapper, &mut context)?;
    module.finalize_definitions()?;
    let invoke: unsafe extern "C" fn(*const u64, *mut u64) =
        unsafe { std::mem::transmute(module.get_finalized_function(wrapper)) };
    let mut output = [0u64; 3];
    unsafe { invoke(words.as_ptr(), output.as_mut_ptr()) };
    let bytes: Vec<u8> = output.iter().flat_map(|word| word.to_le_bytes()).collect();
    std::fs::write(&args[2], bytes)?;
    Ok(())
}
