//! Emit the opt-in leaf-handler slice against the actual VM ABI.
use cranelift_codegen::{
    ir::{
        AbiParam, InstBuilder, MemFlagsData, Signature, StackSlotData, StackSlotKind,
        condcodes::IntCC, types,
    },
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

// Shared with the synthetic ABI pilot, which still lowers its private JSON IR
// through it; the slice uses only the layout table and the exit code.
#[allow(dead_code)]
#[path = "support/runtime_ir.rs"]
mod runtime_ir;

fn signature(cc: CallConv) -> Signature {
    let mut sig = Signature::new(cc);
    sig.params = vec![AbiParam::new(types::I64); 6];
    sig.returns.push(AbiParam::new(types::I64));
    sig
}

fn opcode(name: &str) -> Option<u8> {
    Some(encode(&match name {
        "FAdd" => Op::FAdd(0, 0, 0),
        "FSub" => Op::FSub(0, 0, 0),
        "FMul" => Op::FMul(0, 0, 0),
        "FDiv" => Op::FDiv(0, 0, 0),
        "FMod" => Op::FMod(0, 0, 0),
        "FK" => Op::FK(0, 0.0),
        "FMov" => Op::FMov(0, 0),
        "FNeg" => Op::FNeg(0, 0),
        "IToF" => Op::IToF(0, 0),
        "FToI" => Op::FToI(0, 0),
        "FCmpEq" => Op::FCmpEq(0, 0, 0),
        "FCmpNe" => Op::FCmpNe(0, 0, 0),
        "FCmpLt" => Op::FCmpLt(0, 0, 0),
        "FCmpLe" => Op::FCmpLe(0, 0, 0),
        "FBox" => Op::FBox(0, 0),
        "FUnbox" => Op::FUnbox(0, 0),
        "GetCell" => Op::GetCell(0, 0),
        "Add" => Op::Add(0, 0, 0),
        "Sub" => Op::Sub(0, 0, 0),
        "Mul" => Op::Mul(0, 0, 0),
        "Mod" => Op::Mod(0, 0, 0),
        "Lt" => Op::Lt(0, 0, 0),
        "Le" => Op::Le(0, 0, 0),
        "Neg" => Op::Neg(0, 0),
        "Not" => Op::Not(0, 0),
        "Truthy" => Op::Truthy(0, 0),
        "BoolFromI" => Op::BoolFromI(0, 0),
        "GetUpval" => Op::GetUpval(0, 0),
        "K" => Op::K(0, 0),
        "JmpIf" => Op::JmpIf(0, 0),
        "JmpIfNot" => Op::JmpIfNot(0, 0),
        "GetSlot" => Op::GetSlot(0, 0, 0, 0),
        "GetSlotF" => Op::GetSlotF(0, 0, 0, 0),
        "Len" => Op::Len(0, 0),
        "LenF" => Op::LenF(0, 0),
        "GetIdxF" => Op::GetIdxF(0, 0, 0),
        "GetIdxI" => Op::GetIdxI(0, 0, 0),
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
        "Call" => Op::Call(0, 0, 0),
        "CallK" => Op::CallK(0, 0, 0, 0, 0),
        "CallDyn" => Op::CallDyn(0, 0, 0),
        "Ret" => Op::Ret(0),
        "RetNil" => Op::RetNil,
        "RetN" => Op::RetN(0, 0),
        "PadResults" => Op::PadResults(0, 0),
        "GetField" => Op::GetField(0, 0, 0),
        "Eq" => Op::Eq(0, 0, 0),
        "Ne" => Op::Ne(0, 0, 0),
        "GetIdx" => Op::GetIdx(0, 0, 0),
        "SetIdxI" => Op::SetIdxI(0, 0, 0),
        "SetCell" => Op::SetCell(0, 0),
        "SetSlot" => Op::SetSlot(0, 0, 0, 0),
        "SetSlotF" => Op::SetSlotF(0, 0, 0, 0),
        "TagCheckNum" => Op::TagCheckNum(0, 0),
        "NewRecord" => Op::NewRecord(0, 0),
        "IBox" => Op::IBox(0, 0),
        "IUnbox" => Op::IUnbox(0, 0),
        "StrByte" => Op::StrByte(0, 0, 0),
        "SetIdxF" => Op::SetIdxF(0, 0, 0),
        "SetIdx" => Op::SetIdx(0, 0, 0),
        _ => return None,
    })
    .op)
}

/// The Rust helpers a handler may call: exported by `dispatch.rs` under the
/// experiment feature, each publishing and reloading the task record itself.
const HELPERS: [&str; 11] = [
    "nupp_rt_get_field",
    "nupp_rt_get_index",
    "nupp_rt_get_index_num",
    "nupp_rt_set_index_num",
    "nupp_rt_store_index",
    "nupp_rt_barrier",
    "nupp_rt_new_record",
    "nupp_rt_eq_slow",
    "nupp_rt_call_iter",
    "nupp_rt_call_builtin",
    "nupp_rt_append_plain",
];

/// Opcodes whose Rust handlers share one body (`dynamic_call!`) and whose
/// native handler is the one source function: the table points both
/// opcodes at it when the source defines the first name only.
const ALIASES: [(&str, &str); 1] = [("CallDyn", "CallK")];

/// The handler contract on a parsed function. A handler has the six-register
/// tail signature; a support function (a slow path a handler tail-calls)
/// takes the pc, the context, up to five words of its own and the dispatch
/// table, so the tail call to it fits in argument registers. Either may call
/// only the exported Rust helpers, tail-call only functions of this file, and
/// `return` only the entry pc, the reenter code or the error code; every
/// tail dispatch preserves the context.
fn require_handler_clif(
    f: &cranelift_codegen::ir::Function,
    tail: &Signature,
    handler: bool,
    locals: &std::collections::BTreeSet<String>,
) -> Result<(), String> {
    use cranelift_codegen::ir::{ExternalName, InstructionData, Opcode, ValueDef};
    if handler && f.signature != *tail {
        return Err(format!("{}: handler signature required", f.name));
    }
    if !handler
        && (f.signature.call_conv != CallConv::Tail
            || f.signature.params.len() < 3
            || f.signature.params.len() > 8
            || f.signature.returns.len() != 1
            || f.signature.params.iter().any(|p| p.value_type != types::I64))
    {
        return Err(format!("{}: support signature required (pc, context, up to five more, table)", f.name));
    }
    let context = if handler { 4 } else { 1 };
    if !f.global_values.is_empty() || !f.sized_stack_slots.is_empty() {
        return Err(format!("{}: handlers reference no symbols or stack", f.name));
    }
    let entry = f.layout.entry_block().ok_or("entry block required")?;
    let params = f.dfg.block_params(entry).to_vec();
    let callee_name = |inst| -> Option<String> {
        match &f.dfg.insts[inst] {
            InstructionData::Call { func_ref, .. } => match &f.dfg.ext_funcs[*func_ref].name {
                ExternalName::TestCase(name) => Some(name.to_string().trim_start_matches('%').to_string()),
                _ => None,
            },
            _ => None,
        }
    };
    for block in f.layout.blocks() {
        for inst in f.layout.block_insts(block) {
            let data = &f.dfg.insts[inst];
            match data.opcode() {
                Opcode::CallIndirect => {
                    return Err("VM slice may only dispatch or leave before executing a helper".into());
                }
                Opcode::Call => {
                    let name = callee_name(inst).unwrap_or_default();
                    if !HELPERS.contains(&name.as_str()) {
                        return Err(format!("{name} is not an exported helper"));
                    }
                }
                Opcode::ReturnCall => {
                    let name = callee_name(inst).unwrap_or_default();
                    if !locals.contains(&name) {
                        return Err(format!("{name} is not a function of this file"));
                    }
                }
                Opcode::ReturnCallIndirect => {
                    let args = f.dfg.inst_args(inst);
                    if args.len() != 7 || args[5] != params[context] {
                        return Err("dispatch must preserve the context".into());
                    }
                }
                Opcode::Return => {
                    let args = f.dfg.inst_args(inst);
                    let code = args.len() == 1
                        && matches!(f.dfg.value_def(args[0]), ValueDef::Result(i, 0)
                            if matches!(f.dfg.insts[i], InstructionData::UnaryImm { opcode: Opcode::Iconst, imm } if imm.bits() == runtime_ir::EXIT_REENTER || imm.bits() == 0));
                    if args.len() != 1 || (args[0] != params[0] && !code) {
                        return Err("leaf transfer must preserve its VM windows and context; slow must preserve pc".into());
                    }
                }
                _ => {}
            }
        }
    }
    Ok(())
}

fn changes_frame_clif(f: &cranelift_codegen::ir::Function) -> bool {
    use cranelift_codegen::ir::Opcode;
    let Some(entry) = f.layout.entry_block() else { return false };
    let params = f.dfg.block_params(entry).to_vec();
    f.layout.blocks().any(|block| {
        f.layout.block_insts(block).any(|inst| {
            let data = &f.dfg.insts[inst];
            match data.opcode() {
                Opcode::ReturnCallIndirect => {
                    let args = f.dfg.inst_args(inst);
                    (1..4).any(|p| args[p + 1] != params[p])
                }
                Opcode::Return => f.dfg.inst_args(inst)[0] != params[0],
                _ => false,
            }
        })
    })
}

fn main() -> Result<(), String> {
    let args: Vec<_> = std::env::args().collect();
    if args.get(1).map(String::as_str) == Some("--layouts") {
        let path = args.get(2).ok_or("layout output path required")?;
        let mut text = String::from("{\n");
        for (i, field) in runtime_ir::LAYOUT_FIELDS.iter().enumerate() {
            text.push_str(&format!("  \"{field}\": {}{}\n", runtime_ir::layout(field)?,
                if i + 1 < runtime_ir::LAYOUT_FIELDS.len() { "," } else { "" }));
        }
        text.push_str("}\n");
        std::fs::write(path, text).map_err(|e| e.to_string())?;
        return Ok(());
    }
    let input = Path::new(args.get(1).ok_or("handler CLIF required")?);
    let text = std::fs::read_to_string(input).map_err(|e| e.to_string())?;
    let mut sources: Vec<cranelift_codegen::ir::Function> =
        cranelift_reader::parse_functions(&text).map_err(|e| e.to_string())?;
    let name_of = |f: &cranelift_codegen::ir::Function| f.name.to_string().trim_start_matches('%').to_string();
    let packed_state = args
        .get(3..)
        .unwrap_or(&[])
        .iter()
        .any(|s| s == "--packed-state");
    let derived_frame = args
        .get(3..)
        .unwrap_or(&[])
        .iter()
        .any(|s| s == "--derived-frame");
    if packed_state && derived_frame {
        return Err("choose one native state layout".into());
    }
    for option in args.get(3..).unwrap_or(&[]) {
        match option.as_str() {
            "--integers-only" => sources.retain(|f| {
                let name = name_of(f);
                (name.starts_with('I') && name != "IToF" && name != "IBox" && name != "IUnbox")
                    || name == "Jmp"
                    || name == "JmpIfIZero"
            }),
            "--packed-state" | "--derived-frame" => {}
            _ if option.starts_with("--without=") => {
                let names: Vec<&str> = option["--without=".len()..].split(',').collect();
                sources.retain(|f| !names.contains(&name_of(f).as_str()));
            }
            _ => return Err(format!("unknown option {option}")),
        }
    }
    if packed_state && sources.iter().any(changes_frame_clif) {
        return Err("frame-changing handlers need the frame derived from the window".into());
    }
    if !derived_frame {
        return Err("CLIF handlers are printed for the derived-frame layout".into());
    }
    if sources.is_empty() {
        return Err("no handlers".into());
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
    let mut ids = Vec::new();
    let mut function_ids = Vec::new();
    let mut metadata =
        String::from("// Generated with the native object. Private experimental ABI.\n");
    metadata.push_str(&format!(
        "#[cfg(test)] const NATIVE_DERIVED_FRAME: bool = {derived_frame};\n"
    ));
    metadata.push_str(
        "const _: () = { assert!(HDR == 4); assert!(std::mem::size_of::<Ins>() == 16);\n",
    );
    for (field, offset) in [
        ("op", 0),
        ("a", 1),
        ("b", 2),
        ("c", 3),
        ("imm", 4),
        ("k", 8),
    ] {
        metadata.push_str(&format!(
            "assert!(std::mem::offset_of!(Ins, {field}) == {offset});\n"
        ));
    }
    for (field, offset) in [
        ("pc", offset_of!(Ctx, pc)),
        ("status", offset_of!(Ctx, status)),
        ("marking", offset_of!(Ctx, marking)),
        ("shapes", offset_of!(Ctx, shapes)),
        ("slow_calls", offset_of!(Ctx, slow_calls)),
        ("nslow_calls", offset_of!(Ctx, nslow_calls)),
        ("funcs", offset_of!(Ctx, funcs)),
        ("frame_mode", offset_of!(Ctx, frame_mode)),
        ("jit_frames", offset_of!(Ctx, jit_frames)),
        ("nframe_entries", offset_of!(Ctx, nframe_entries)),
        ("frame_entries", offset_of!(Ctx, frame_entries)),
        ("stack", offset_of!(Ctx, stack)),
        ("cap", offset_of!(Ctx, cap)),
        ("cur", offset_of!(Ctx, cur)),
        ("nfuncs", offset_of!(Ctx, nfuncs)),
        ("result", offset_of!(Ctx, result)),
        ("last_nres", offset_of!(Ctx, last_nres)),
        ("entries", offset_of!(Ctx, entries)),
        ("jit_threshold", offset_of!(Ctx, jit_threshold)),
        ("feedback", offset_of!(Ctx, feedback)),
        ("guard", offset_of!(Ctx, guard)),
        ("unavailable_fid", offset_of!(Ctx, unavailable_fid)),
    ] {
        metadata.push_str(&format!(
            "assert!(std::mem::offset_of!(Ctx, {field}) == {offset});\n"
        ));
    }
    for (field, offset) in [
        ("kind", offset_of!(nupp_vm::heap::Header, kind)),
        ("aux_len", offset_of!(nupp_vm::heap::Header, aux_len)),
        ("aux", offset_of!(nupp_vm::heap::Header, aux)),
        ("flags", offset_of!(nupp_vm::heap::Header, flags)),
        ("aux_ptr", offset_of!(nupp_vm::heap::Header, aux_ptr)),
    ] {
        metadata.push_str(&format!(
            "assert!(std::mem::offset_of!(crate::heap::Header, {field}) == {offset});\n"
        ));
    }
    metadata.push_str("assert!(crate::heap::KIND_CELL == 6);\nassert!(crate::heap::KIND_STR == 1 && crate::heap::KIND_SLICE == 9 && crate::heap::KIND_TABLE == 2 && crate::heap::KIND_RECORD == 3 && crate::heap::F_METATABLE == 4);\n");
    metadata.push_str(&format!(
        "assert!(crate::heap::OFF_T_META == {});\n",
        nupp_vm::heap::OFF_T_META
    ));
    metadata.push_str(&format!("assert!(std::mem::size_of::<FuncInfo>() == {});\nassert!(std::mem::offset_of!(FuncInfo, consts) == {});\n", std::mem::size_of::<nupp_vm::threaded::FuncInfo>(), offset_of!(nupp_vm::threaded::FuncInfo, consts)));
    for (field, offset) in [
        ("code", offset_of!(nupp_vm::threaded::FuncInfo, code)),
        ("frame_words", offset_of!(nupp_vm::threaded::FuncInfo, frame_words)),
        ("nparams", offset_of!(nupp_vm::threaded::FuncInfo, nparams)),
        ("off_i", offset_of!(nupp_vm::threaded::FuncInfo, off_i)),
        ("off_f", offset_of!(nupp_vm::threaded::FuncInfo, off_f)),
        ("vararg", offset_of!(nupp_vm::threaded::FuncInfo, vararg)),
        ("calls", offset_of!(nupp_vm::threaded::FuncInfo, calls)),
        ("typed", offset_of!(nupp_vm::threaded::FuncInfo, typed)),
        ("native", offset_of!(nupp_vm::threaded::FuncInfo, native)),
    ] {
        metadata.push_str(&format!(
            "assert!(std::mem::offset_of!(FuncInfo, {field}) == {offset});\n"
        ));
    }
    metadata.push_str(&format!(
        "assert!(crate::heap::KIND_CLOSURE == 5 && crate::value::T_FUNC == 0x0004_0000_0000_0000 && NO_GUARD == u64::MAX && EXIT_REENTER == {} && EXIT_ERROR == 0 && ST_ERROR == 0xffff_fffc);\n",
        runtime_ir::EXIT_REENTER
    ));
    metadata.push_str(&format!(
        "assert!(std::mem::size_of::<ShapeInfo>() == {} && std::mem::offset_of!(ShapeInfo, table) == {} && std::mem::offset_of!(ShapeInfo, mask) == {} && crate::heap::OFF_T_HASH_PTR == {} && crate::heap::OFF_T_HASH_MASK == {});\n",
        std::mem::size_of::<nupp_vm::threaded::ShapeInfo>(),
        offset_of!(nupp_vm::threaded::ShapeInfo, table),
        offset_of!(nupp_vm::threaded::ShapeInfo, mask),
        nupp_vm::heap::OFF_T_HASH_PTR,
        nupp_vm::heap::OFF_T_HASH_MASK
    ));
    metadata.push_str("assert!(crate::value::QNAN == 0x7ff8_0000_0000_0000 && crate::value::TAG_MASK == 0x0007_0000_0000_0000 && crate::value::T_OBJ == 0x0005_0000_0000_0000 && crate::value::PAYLOAD == 0x0000_ffff_ffff_ffff);\nassert!(Value::NIL.0 == 0x7ff9_0000_0000_0000 && Value::FALSE.0 == 0x7ffa_0000_0000_0000 && Value::TRUE.0 == 0x7ffb_0000_0000_0000);\n");
    metadata.push_str("};\nconst fn native_table(mut table: [Handler; Code::Mod as usize + 1]) -> [Handler; Code::Mod as usize + 1] {\n");
    let names: Vec<String> = sources.iter().map(name_of).collect();
    let locals: std::collections::BTreeSet<String> = names.iter().cloned().collect();
    let mut imports: std::collections::BTreeMap<String, cranelift_module::FuncId> = Default::default();
    let conv = module.isa().default_call_conv();
    for function in &mut sources {
        let name = name_of(function);
        let handler = opcode(&name).is_some();
        require_handler_clif(function, &tail, handler, &locals)?;
        let mut signature = function.signature.clone();
        if !handler {
            signature.call_conv = CallConv::Tail;
        }
        let id = module
            .declare_function(&name, Linkage::Local, &signature)
            .unwrap();
        function_ids.push(id);
        if let Some(op) = opcode(&name) {
            ids.push((op, id));
            metadata.push_str(&format!(
                "assert!(Code::{name} as u8 == {op}); table[Code::{name} as usize] = native_segment;\n"
            ));
            for (alias, target) in ALIASES {
                if name == target && !names.iter().any(|f| f == alias) {
                    let op = opcode(alias).unwrap();
                    ids.push((op, id));
                    metadata.push_str(&format!(
                        "assert!(Code::{alias} as u8 == {op}); table[Code::{alias} as usize] = native_segment;\n"
                    ));
                }
            }
        }
    }
    // Calls to the exported helpers import them; tail calls name functions of
    // this file. Imported signatures take the platform convention.
    for function in &mut sources {
        let references: Vec<_> = function
            .dfg
            .ext_funcs
            .iter()
            .filter_map(|(reference, data)| match &data.name {
                cranelift_codegen::ir::ExternalName::TestCase(callee) => {
                    Some((reference, callee.to_string().trim_start_matches('%').to_string(), data.signature))
                }
                _ => None,
            })
            .collect();
        for (reference, callee, sig_ref) in references {
            let id = if HELPERS.contains(&callee.as_str()) {
                function.dfg.signatures[sig_ref].call_conv = conv;
                let signature = function.dfg.signatures[sig_ref].clone();
                *imports.entry(callee.clone()).or_insert_with(|| {
                    module.declare_function(&callee, Linkage::Import, &signature).unwrap()
                })
            } else {
                let index = names.iter().position(|n| *n == callee).ok_or_else(|| format!("unknown function {callee}"))?;
                function.dfg.signatures[sig_ref].call_conv = CallConv::Tail;
                function_ids[index]
            };
            let user = function.declare_imported_user_function(cranelift_codegen::ir::UserExternalName {
                namespace: 0,
                index: id.as_u32(),
            });
            let data = &mut function.dfg.ext_funcs[reference];
            data.name = cranelift_codegen::ir::ExternalName::user(user);
            data.colocated = !HELPERS.contains(&callee.as_str());
        }
    }
    metadata.push_str("table }\n");
    let mut listings = String::new();
    for index in 0..sources.len() + 2 {
        let mut ctx = module.make_context();
        ctx.want_disasm = true;
        let is_entry = index == sources.len();
        let is_leave = index == sources.len() + 1;
        if let Some(function) = sources.get(index) {
            // The producer decided the IR; the shim compiles it as printed.
            ctx.func = function.clone();
            listings.push_str(&format!("\n{}\n", ctx.func.display()));
            module
                .define_function(function_ids[index], &mut ctx)
                .map_err(|e| format!("{}: {e}", function.name))?;
            listings.push_str(ctx.compiled_code().unwrap().vcode.as_deref().unwrap_or(""));
            continue;
        }
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
            let table = if (packed_state || derived_frame) && !is_entry {
                params[5]
            } else {
                b.ins().symbol_value(types::I64, data)
            };
            if is_leave {
                b.ins().return_(&[params[0]]);
            } else if is_entry {
                let flags = MemFlagsData::new().with_notrap();
                if derived_frame {
                    // A VM register window begins immediately after its four
                    // frame-header words. Check the contract before any handler
                    // executes; a foreign caller with independent windows leaves
                    // unchanged through the ordinary Rust fallback.
                    let frame = b.ins().iadd_imm_s(params[1], -32);
                    let valid = b.ins().icmp(IntCC::Equal, frame, params[5]);
                    let enter = b.create_block();
                    let reject = b.create_block();
                    b.ins().brif(valid, enter, &[], reject, &[]);
                    b.switch_to_block(reject);
                    b.ins().return_(&[params[0]]);
                    b.switch_to_block(enter);
                }
                let op = b.ins().uload8(types::I64, flags, params[0], 0);
                let offset = b.ins().ishl_imm_u(op, 3);
                let slot = b.ins().iadd(table, offset);
                let target = b.ins().load(types::I64, flags, slot, 0);
                let mut arguments = params.clone();
                if packed_state {
                    // The entry owns this nonmoving pair for the entire leaf
                    // segment. Helpers and changed windows are rejected before
                    // emission, so no managed roots are hidden here.
                    let slot = b.create_sized_stack_slot(StackSlotData::new(
                        StackSlotKind::ExplicitSlot,
                        16,
                        3,
                    ));
                    let state = b.ins().stack_addr(types::I64, slot, 0);
                    b.ins().store(flags, params[4], state, 0);
                    b.ins().store(flags, params[5], state, 8);
                    arguments[4] = state;
                    arguments[5] = table;
                }
                if derived_frame {
                    arguments[5] = table;
                }
                let call = b.ins().call_indirect(sig, target, &arguments);
                let value = b.inst_results(call)[0];
                b.ins().return_(&[value]);
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
                    function_ids[index]
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
