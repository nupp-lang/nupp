//! Emit the opt-in leaf-handler slice against the actual VM ABI.
use cranelift_codegen::{
    ir::{AbiParam, InstBuilder, MemFlagsData, Signature, types},
    isa::CallConv,
    settings::{self, Configurable},
};
use cranelift_frontend::{FunctionBuilder, FunctionBuilderContext};
use cranelift_module::{DataDescription, Linkage, Module};
use cranelift_object::{ObjectBuilder, ObjectModule};
use nupp_vm::{
    interp::Op,
    threaded::{Ctx, encode},
};
use std::{mem::offset_of, path::Path};

#[path = "support/runtime_ir.rs"]
mod runtime_ir;

fn signature(cc: CallConv) -> Signature {
    let mut sig = Signature::new(cc);
    sig.params = vec![AbiParam::new(types::I64); 6];
    sig.returns.push(AbiParam::new(types::I64));
    sig
}

fn opcode(name: &str) -> u8 {
    encode(&match name {
        "Move" => Op::Move(0, 0),
        "Nil" => Op::Nil(0),
        "IK" => Op::IK(0, 0),
        "IMov" => Op::IMov(0, 0),
        "IAddK" => Op::IAddK(0, 0, 0),
        "IMaskU32" => Op::IMaskU32(0, 0),
        "IAdd" => Op::IAdd(0, 0, 0),
        "ISub" => Op::ISub(0, 0, 0),
        "IAnd" => Op::IAnd(0, 0, 0),
        "IOr" => Op::IOr(0, 0, 0),
        "IShl" => Op::IShl(0, 0, 0),
        "IShrU" => Op::IShrU(0, 0, 0),
        "ICmpSLt" => Op::ICmpSLt(0, 0, 0),
        "ICmpSLe" => Op::ICmpSLe(0, 0, 0),
        "ICmpEq" => Op::ICmpEq(0, 0, 0),
        "ICmpNe" => Op::ICmpNe(0, 0, 0),
        "ICmpLt" => Op::ICmpLt(0, 0, 0),
        "ICmpLe" => Op::ICmpLe(0, 0, 0),
        "Jmp" => Op::Jmp(0),
        "JmpIfIZero" => Op::JmpIfIZero(0, 0),
        _ => panic!("unsupported leaf handler {name}"),
    })
    .op
}

fn main() -> Result<(), String> {
    let args: Vec<_> = std::env::args().collect();
    let mut program =
        runtime_ir::Program::read(Path::new(args.get(1).ok_or("source IR required")?))?;
    if args.get(3).is_some_and(|s| s == "--integers-only") {
        program
            .functions
            .retain(|f| f.name != "Move" && f.name != "Nil");
    } else if args.len() > 3 {
        return Err("only --integers-only is supported".into());
    }
    let path = args.get(2).ok_or("output object required")?;
    let mut flags = settings::builder();
    flags.set("opt_level", "speed").unwrap();
    flags.set("is_pic", "true").unwrap();
    flags
        .set(
            "preserve_frame_pointers",
            if cfg!(target_arch = "x86_64") {
                "true"
            } else {
                "false"
            },
        )
        .unwrap();
    let isa = cranelift_native::builder()
        .unwrap()
        .finish(settings::Flags::new(flags))
        .unwrap();
    let mut module = ObjectModule::new(
        ObjectBuilder::new(
            isa,
            "nupp-native-runtime",
            cranelift_module::default_libcall_names(),
        )
        .unwrap(),
    );
    let tail = signature(CallConv::Tail);
    let entry_sig = signature(module.isa().default_call_conv());
    let entry = module
        .declare_function("nupp_native_runtime_entry", Linkage::Export, &entry_sig)
        .unwrap();
    let leave = module
        .declare_function("leave", Linkage::Local, &tail)
        .unwrap();
    let table_id = module
        .declare_data("native_runtime_table", Linkage::Local, false, false)
        .unwrap();
    // The producer rejects helper calls here; this unused declaration only
    // keeps the generic whole-function bridge's signature uniform.
    let mut helper_sig = module.make_signature();
    helper_sig.params = vec![AbiParam::new(types::I64); 5];
    let helper = module
        .declare_function("forbidden_runtime_helper", Linkage::Import, &helper_sig)
        .unwrap();
    let mut ids = Vec::new();
    let mut metadata =
        String::from("// Generated with the native object. Private experimental ABI.\n");
    metadata.push_str("const _: () = { assert!(std::mem::size_of::<Ins>() == 16);\n");
    for (field, offset) in [
        ("frame_mode", offset_of!(Ctx, frame_mode)),
        ("jit_frames", offset_of!(Ctx, jit_frames)),
        ("nframe_entries", offset_of!(Ctx, nframe_entries)),
    ] {
        metadata.push_str(&format!(
            "assert!(std::mem::offset_of!(Ctx, {field}) == {offset});\n"
        ));
    }
    metadata.push_str("};\nconst fn native_table(mut table: [Handler; Code::Mod as usize + 1]) -> [Handler; Code::Mod as usize + 1] {\n");
    for function in &program.functions {
        function.require_leaf()?;
        let op = opcode(&function.name);
        let id = module
            .declare_function(&function.name, Linkage::Local, &tail)
            .unwrap();
        ids.push((op, id));
        metadata.push_str(&format!(
            "assert!(Code::{} as u8 == {op}); table[Code::{} as usize] = native_segment;\n",
            function.name, function.name
        ));
    }
    metadata.push_str("table }\n");
    let mut listings = String::new();
    for index in 0..program.functions.len() + 2 {
        let mut ctx = module.make_context();
        ctx.want_disasm = true;
        let is_entry = index == program.functions.len();
        let is_leave = index == program.functions.len() + 1;
        ctx.func.signature = if is_entry {
            entry_sig.clone()
        } else {
            tail.clone()
        };
        let mut fbc = FunctionBuilderContext::new();
        {
            let mut b = FunctionBuilder::new(&mut ctx.func, &mut fbc);
            let start = b.create_block();
            b.append_block_params_for_function_params(start);
            b.switch_to_block(start);
            let params = b.block_params(start).to_vec();
            let sig = b.import_signature(tail.clone());
            let data = module.declare_data_in_func(table_id, b.func);
            let table = b.ins().symbol_value(types::I64, data);
            if is_leave {
                b.ins().return_(&[params[0]]);
            } else if is_entry {
                let flags = MemFlagsData::new().with_notrap();
                let op = b.ins().uload8(types::I64, flags, params[0], 0);
                let offset = b.ins().ishl_imm_u(op, 3);
                let slot = b.ins().iadd(table, offset);
                let target = b.ins().load(types::I64, flags, slot, 0);
                let call = b.ins().call_indirect(sig, target, &params);
                let value = b.inst_results(call)[0];
                b.ins().return_(&[value]);
            } else {
                let helper = module.declare_func_in_func(helper, b.func);
                runtime_ir::emit(
                    &program.functions[index],
                    &mut b,
                    &params,
                    sig,
                    helper,
                    Some(table),
                )?;
            }
            b.seal_all_blocks();
            b.finalize(module.target_config());
        }
        listings.push_str(&format!("\n{}\n", ctx.func.display()));
        module
            .define_function(
                if is_entry {
                    entry
                } else if is_leave {
                    leave
                } else {
                    ids[index].1
                },
                &mut ctx,
            )
            .map_err(|e| e.to_string())?;
        listings.push_str(ctx.compiled_code().unwrap().vcode.as_deref().unwrap_or(""));
    }
    let mut data = DataDescription::new();
    data.define(vec![0; 256 * 8].into_boxed_slice());
    data.set_align(8);
    for op in 0..256 {
        let id = ids
            .iter()
            .find(|(code, _)| *code as usize == op)
            .map(|(_, id)| *id)
            .unwrap_or(leave);
        let function = module.declare_func_in_data(id, &mut data);
        data.write_function_addr((op * 8) as u32, function);
    }
    module
        .define_data(table_id, &data)
        .map_err(|e| e.to_string())?;
    std::fs::write(path, module.finish().emit().map_err(|e| e.to_string())?)
        .map_err(|e| e.to_string())?;
    std::fs::write(format!("{path}.rs"), metadata).map_err(|e| e.to_string())?;
    std::fs::write(format!("{path}.txt"), listings).map_err(|e| e.to_string())?;
    Ok(())
}
