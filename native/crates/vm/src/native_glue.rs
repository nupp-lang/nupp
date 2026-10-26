//! The glue between Nupp-authored native handlers, printed as CLIF, and the
//! runtime that links them: `nupp-vm native layouts` publishes the structure
//! offsets the handler sources name, `nupp-vm native object` compiles the
//! handler file into the object the `native-runtime` feature links, and
//! `nupp-vm native jit` runs one function of a CLIF file in process.
use crate::heap::Header;
use crate::threaded::{Ctx, FuncInfo, Ins, ShapeInfo, code_by_name};
use cranelift_codegen::ir::{
    AbiParam, ExternalName, Function, InstBuilder, InstructionData, MemFlagsData, Opcode,
    Signature, UserExternalName, ValueDef, condcodes::IntCC, types,
};
use cranelift_codegen::isa::CallConv;
use cranelift_codegen::settings::{self, Configurable};
use cranelift_frontend::{FunctionBuilder, FunctionBuilderContext};
use cranelift_module::{DataDescription, FuncId, Linkage, Module, default_libcall_names};
use cranelift_object::{ObjectBuilder, ObjectModule};
use std::collections::{BTreeMap, BTreeSet};
use std::mem::offset_of;

/// Every structure offset a handler may name, as the linked Rust layouts
/// measure it. The Nupp producer reads these (`nupp-vm native layouts`), and
/// the generated sidecar asserts the same values at build time.
pub const LAYOUT_FIELDS: [&str; 54] = [
    "funcs", "FuncInfo.size", "FuncInfo.consts", "jit_frames", "nframe_entries",
    "frame_entries", "stack", "cap", "cur", "nfuncs", "result", "last_nres",
    "feedback", "guard", "unavailable_fid", "FuncInfo.code",
    "FuncInfo.frame_words", "FuncInfo.nparams", "FuncInfo.off_i", "FuncInfo.off_f",
    "FuncInfo.vararg", "FuncInfo.calls", "FuncInfo.typed", "FuncInfo.native", "Header.aux_len",
    "Header.aux", "Header.flags", "Table.meta", "Header.kind", "Header.aux_ptr", "Ins.op",
    "Ins.a", "Ins.b", "Ins.c", "Ins.imm", "Ins.k", "pc", "status", "marking", "shapes",
    "ShapeInfo.size", "ShapeInfo.table", "ShapeInfo.mask", "Table.hash_ptr", "Table.hash_mask",
    "slow_calls", "nslow_calls", "frame_threshold", "budget", "Code.PadResults",
    "Table.hash_cap", "Table.hash_len", "Table.hash_order", "Table.hash_rank",
];

/// A field of a table's hash part (`ValueTable`), from the object's start.
fn hash_part(field: usize) -> usize {
    crate::heap::HEADER + offset_of!(crate::heap::TablePayload, hash) + field
}

pub fn layout(field: &str) -> Result<usize, String> {
    Ok(match field {
        "funcs" => offset_of!(Ctx, funcs),
        "FuncInfo.size" => std::mem::size_of::<FuncInfo>(),
        "FuncInfo.consts" => offset_of!(FuncInfo, consts),
        "jit_frames" => offset_of!(Ctx, jit_frames),
        "nframe_entries" => offset_of!(Ctx, nframe_entries),
        "frame_entries" => offset_of!(Ctx, frame_entries),
        "stack" => offset_of!(Ctx, stack),
        "cap" => offset_of!(Ctx, cap),
        "cur" => offset_of!(Ctx, cur),
        "nfuncs" => offset_of!(Ctx, nfuncs),
        "result" => offset_of!(Ctx, result),
        "last_nres" => offset_of!(Ctx, last_nres),
        "feedback" => offset_of!(Ctx, feedback),
        "guard" => offset_of!(Ctx, guard),
        "unavailable_fid" => offset_of!(Ctx, unavailable_fid),
        "FuncInfo.code" => offset_of!(FuncInfo, code),
        "FuncInfo.frame_words" => offset_of!(FuncInfo, frame_words),
        "FuncInfo.nparams" => offset_of!(FuncInfo, nparams),
        "FuncInfo.off_i" => offset_of!(FuncInfo, off_i),
        "FuncInfo.off_f" => offset_of!(FuncInfo, off_f),
        "FuncInfo.vararg" => offset_of!(FuncInfo, vararg),
        "FuncInfo.calls" => offset_of!(FuncInfo, calls),
        "FuncInfo.typed" => offset_of!(FuncInfo, typed),
        "FuncInfo.native" => offset_of!(FuncInfo, native),
        "Header.aux_len" => offset_of!(Header, aux_len),
        "Header.aux" => offset_of!(Header, aux),
        "Header.flags" => offset_of!(Header, flags),
        "Table.meta" => crate::heap::OFF_T_META as usize,
        "Header.kind" => offset_of!(Header, kind),
        "Header.aux_ptr" => offset_of!(Header, aux_ptr),
        "Ins.op" => offset_of!(Ins, op),
        "Ins.a" => offset_of!(Ins, a),
        "Ins.b" => offset_of!(Ins, b),
        "Ins.c" => offset_of!(Ins, c),
        "Ins.imm" => offset_of!(Ins, imm),
        "Ins.k" => offset_of!(Ins, k),
        "pc" => offset_of!(Ctx, pc),
        "status" => offset_of!(Ctx, status),
        "marking" => offset_of!(Ctx, marking),
        "shapes" => offset_of!(Ctx, shapes),
        "ShapeInfo.size" => std::mem::size_of::<ShapeInfo>(),
        "ShapeInfo.table" => offset_of!(ShapeInfo, table),
        "ShapeInfo.mask" => offset_of!(ShapeInfo, mask),
        "Table.hash_ptr" => crate::heap::OFF_T_HASH_PTR as usize,
        "Table.hash_mask" => crate::heap::OFF_T_HASH_MASK as usize,
        "slow_calls" => offset_of!(Ctx, slow_calls),
        "nslow_calls" => offset_of!(Ctx, nslow_calls),
        "frame_threshold" => offset_of!(Ctx, frame_threshold),
        "budget" => offset_of!(Ctx, budget),
        // An opcode number a handler reads from the instruction stream: the
        // return that pads the results of the call it answers.
        "Code.PadResults" => crate::threaded::Code::PadResults as usize,
        "Table.hash_cap" => hash_part(offset_of!(crate::heap::ValueTable, cap)),
        "Table.hash_len" => hash_part(offset_of!(crate::heap::ValueTable, len)),
        "Table.hash_order" => hash_part(offset_of!(crate::heap::ValueTable, order)),
        "Table.hash_rank" => hash_part(offset_of!(crate::heap::ValueTable, rank)),
        _ => return Err("unknown context field".into()),
    })
}

/// The native chain's exit words: a pointer-aligned instruction address
/// resumes Rust at that instruction, in whatever frame the context now
/// names; zero says the chain ended and the context holds the status.
pub const EXIT_ERROR: i64 = 0;

/// Whether an imported symbol is one the runtime exports for native code: a
/// helper of `dispatch.rs` (`nupp_rt_*`, each publishing and reloading the
/// task record itself) or an operating-system edge (`nupp_os_*`). The
/// declarations the handler sources are written against name them, and a
/// symbol nothing exports fails at link time rather than here.
pub fn is_runtime_export(name: &str) -> bool {
    name.starts_with("nupp_rt_") || name.starts_with("nupp_os_")
}

/// `nupp-vm native layouts OUT.json`: the layout table as JSON.
pub fn write_layouts(path: &str) -> Result<(), String> {
    let mut text = String::from("{\n");
    for (i, field) in LAYOUT_FIELDS.iter().enumerate() {
        text.push_str(&format!(
            "  \"{field}\": {}{}\n",
            layout(field)?,
            if i + 1 < LAYOUT_FIELDS.len() { "," } else { "" }
        ));
    }
    text.push_str("}\n");
    std::fs::write(path, text).map_err(|e| e.to_string())
}

/// The platform-convention signature of the object's exported entries:
/// six words in, one out.
fn entry_sig_of(cc: CallConv) -> Signature { signature(cc) }

fn signature(cc: CallConv) -> Signature {
    let mut sig = Signature::new(cc);
    sig.params = vec![AbiParam::new(types::I64); 6];
    sig.returns.push(AbiParam::new(types::I64));
    sig
}

pub(crate) fn name_of(f: &Function) -> String {
    f.name.to_string().trim_start_matches('%').to_string()
}

/// The handler contract on a parsed function. A handler has the six-register
/// tail signature; a support function (a slow path a handler tail-calls)
/// takes the pc, the context, up to five words of its own and the dispatch
/// table, so the tail call to it fits in argument registers. Either may call
/// only the exported Rust helpers, tail-call only functions of this file, and
/// `return` only the entry pc or the error code; every tail dispatch
/// preserves the context.
fn require_handler_clif(
    f: &Function,
    tail: &Signature,
    handler: bool,
    locals: &BTreeSet<String>,
) -> Result<(), String> {
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
        return Err(format!(
            "{}: support signature required (pc, context, up to five more, table)",
            f.name
        ));
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
                ExternalName::TestCase(name) => {
                    Some(name.to_string().trim_start_matches('%').to_string())
                }
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
                    return Err(
                        "VM slice may only dispatch or leave before executing a helper".into(),
                    );
                }
                Opcode::Call => {
                    let name = callee_name(inst).unwrap_or_default();
                    if !is_runtime_export(&name) {
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
                            if matches!(f.dfg.insts[i], InstructionData::UnaryImm { opcode: Opcode::Iconst, imm }
                                if imm.bits() == EXIT_ERROR));
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

/// The build-time sidecar: every layout the handlers were compiled against,
/// and every opcode number they handle, asserted where the object is linked.
fn metadata_header() -> String {
    let mut metadata = String::from("// Generated with the native object. Private ABI.\n");
    metadata.push_str(
        "const _: () = { assert!(HDR == 4); assert!(std::mem::size_of::<Ins>() == 16);\n",
    );
    for (field, offset) in [("op", 0), ("a", 1), ("b", 2), ("c", 3), ("imm", 4), ("k", 8)] {
        metadata.push_str(&format!("assert!(std::mem::offset_of!(Ins, {field}) == {offset});\n"));
    }
    for (field, offset) in [
        ("pc", offset_of!(Ctx, pc)),
        ("status", offset_of!(Ctx, status)),
        ("marking", offset_of!(Ctx, marking)),
        ("shapes", offset_of!(Ctx, shapes)),
        ("slow_calls", offset_of!(Ctx, slow_calls)),
        ("nslow_calls", offset_of!(Ctx, nslow_calls)),
        ("funcs", offset_of!(Ctx, funcs)),
        ("jit_frames", offset_of!(Ctx, jit_frames)),
        ("nframe_entries", offset_of!(Ctx, nframe_entries)),
        ("frame_entries", offset_of!(Ctx, frame_entries)),
        ("stack", offset_of!(Ctx, stack)),
        ("cap", offset_of!(Ctx, cap)),
        ("cur", offset_of!(Ctx, cur)),
        ("nfuncs", offset_of!(Ctx, nfuncs)),
        ("result", offset_of!(Ctx, result)),
        ("last_nres", offset_of!(Ctx, last_nres)),
        ("feedback", offset_of!(Ctx, feedback)),
        ("guard", offset_of!(Ctx, guard)),
        ("unavailable_fid", offset_of!(Ctx, unavailable_fid)),
        ("frame_threshold", offset_of!(Ctx, frame_threshold)),
        ("budget", offset_of!(Ctx, budget)),
    ] {
        metadata.push_str(&format!("assert!(std::mem::offset_of!(Ctx, {field}) == {offset});\n"));
    }
    for (field, offset) in [
        ("kind", offset_of!(Header, kind)),
        ("aux_len", offset_of!(Header, aux_len)),
        ("aux", offset_of!(Header, aux)),
        ("flags", offset_of!(Header, flags)),
        ("aux_ptr", offset_of!(Header, aux_ptr)),
    ] {
        metadata.push_str(&format!(
            "assert!(std::mem::offset_of!(crate::heap::Header, {field}) == {offset});\n"
        ));
    }
    metadata.push_str("assert!(crate::heap::KIND_CELL == 6);\nassert!(crate::heap::KIND_STR == 1 && crate::heap::KIND_SLICE == 9 && crate::heap::KIND_TABLE == 2 && crate::heap::KIND_RECORD == 3 && crate::heap::F_METATABLE == 4);\n");
    metadata.push_str(&format!(
        "assert!(crate::heap::OFF_T_META == {});\n",
        crate::heap::OFF_T_META
    ));
    metadata.push_str(&format!(
        "assert!(std::mem::size_of::<FuncInfo>() == {});\nassert!(std::mem::offset_of!(FuncInfo, consts) == {});\n",
        std::mem::size_of::<FuncInfo>(),
        offset_of!(FuncInfo, consts)
    ));
    for (field, offset) in [
        ("code", offset_of!(FuncInfo, code)),
        ("frame_words", offset_of!(FuncInfo, frame_words)),
        ("nparams", offset_of!(FuncInfo, nparams)),
        ("off_i", offset_of!(FuncInfo, off_i)),
        ("off_f", offset_of!(FuncInfo, off_f)),
        ("vararg", offset_of!(FuncInfo, vararg)),
        ("calls", offset_of!(FuncInfo, calls)),
        ("typed", offset_of!(FuncInfo, typed)),
        ("native", offset_of!(FuncInfo, native)),
    ] {
        metadata.push_str(&format!(
            "assert!(std::mem::offset_of!(FuncInfo, {field}) == {offset});\n"
        ));
    }
    metadata.push_str(&format!(
        "assert!(crate::heap::KIND_CLOSURE == 5 && crate::heap::KIND_ITER == 8 && crate::value::T_FUNC == 0x0004_0000_0000_0000 && NO_GUARD == u64::MAX && EXIT_ERROR == {EXIT_ERROR} && ST_ERROR == 0xffff_fffc && ST_REENTER == 0xffff_ffff);\n"
    ));
    metadata.push_str(&format!(
        "assert!(std::mem::size_of::<ShapeInfo>() == {} && std::mem::offset_of!(ShapeInfo, table) == {} && std::mem::offset_of!(ShapeInfo, mask) == {} && crate::heap::OFF_T_HASH_PTR == {} && crate::heap::OFF_T_HASH_MASK == {});\n",
        std::mem::size_of::<ShapeInfo>(),
        offset_of!(ShapeInfo, table),
        offset_of!(ShapeInfo, mask),
        crate::heap::OFF_T_HASH_PTR,
        crate::heap::OFF_T_HASH_MASK
    ));
    metadata.push_str("assert!(crate::heap::KIND_BYTES == 7 && crate::heap::KIND_INTEGER == 12 && crate::heap::F_INTERNED == 1);\n");
    metadata.push_str("assert!((crate::heap::F_STORAGE_SCHEMA | crate::heap::F_DECLARATION | crate::heap::F_PROTO) == 224);\n");
    for (field, offset) in [
        ("cap", layout("Table.hash_cap").unwrap()),
        ("len", layout("Table.hash_len").unwrap()),
        ("order", layout("Table.hash_order").unwrap()),
        ("rank", layout("Table.hash_rank").unwrap()),
    ] {
        metadata.push_str(&format!(
            "assert!(crate::heap::HEADER + std::mem::offset_of!(crate::heap::TablePayload, hash) + std::mem::offset_of!(crate::heap::ValueTable, {field}) == {offset});\n"
        ));
    }
    metadata.push_str("assert!(crate::value::QNAN == 0x7ff8_0000_0000_0000 && crate::value::TAG_MASK == 0x0007_0000_0000_0000 && crate::value::T_OBJ == 0x0005_0000_0000_0000 && crate::value::PAYLOAD == 0x0000_ffff_ffff_ffff);\nassert!(Value::NIL.0 == 0x7ff9_0000_0000_0000 && Value::FALSE.0 == 0x7ffa_0000_0000_0000 && Value::TRUE.0 == 0x7ffb_0000_0000_0000);\n");
    metadata
}

/// `nupp-vm native object IN.clif OUT.o`: compiles the handler file into the
/// object the `native-runtime` feature links, beside its `.rs` sidecar and
/// `.txt` listings. A function named like a core opcode is that opcode's
/// handler; any other function is a support function the handlers reach by
/// tail call. The entry derives the frame from the register window and
/// dispatches through the 256-entry table, which handlers receive as their
/// sixth argument. `resumeSlow`, the frame driver's entry for the frame on
/// top, is exported beside it as `nupp_native_runtime_resume(ctx)`.
pub fn write_object(input: &str, output: &str) -> Result<(), String> {
    let text = std::fs::read_to_string(input).map_err(|e| e.to_string())?;
    let mut sources: Vec<Function> =
        cranelift_reader::parse_functions(&text).map_err(|e| e.to_string())?;
    if sources.is_empty() {
        return Err("no handlers".into());
    }
    let mut flags = settings::builder();
    flags.set("opt_level", "speed").unwrap();
    flags.set("is_pic", "true").unwrap();
    flags
        .set(
            "preserve_frame_pointers",
            if cfg!(target_arch = "x86_64") { "true" } else { "false" },
        )
        .unwrap();
    let isa = cranelift_native::builder()
        .unwrap()
        .finish(settings::Flags::new(flags))
        .unwrap();
    let mut module = ObjectModule::new(
        ObjectBuilder::new(isa, "nupp-native-runtime", default_libcall_names()).unwrap(),
    );
    let tail = signature(CallConv::Tail);
    let conv = module.isa().default_call_conv();
    let entry_sig = signature(conv);
    let entry = module
        .declare_function("nupp_native_runtime_entry", Linkage::Export, &entry_sig)
        .unwrap();
    let leave = module.declare_function("leave", Linkage::Local, &tail).unwrap();
    let table_id = module
        .declare_data("native_runtime_table", Linkage::Local, false, false)
        .unwrap();
    let mut metadata = metadata_header();
    let names: Vec<String> = sources.iter().map(name_of).collect();
    let locals: BTreeSet<String> = names.iter().cloned().collect();
    let mut handled: Vec<(u8, FuncId)> = Vec::new();
    let mut function_ids = Vec::new();
    for function in &sources {
        let name = name_of(function);
        let opcode = code_by_name(&name);
        require_handler_clif(function, &tail, opcode.is_some(), &locals)?;
        let mut signature = function.signature.clone();
        if opcode.is_none() {
            signature.call_conv = CallConv::Tail;
        }
        let id = module.declare_function(&name, Linkage::Local, &signature).unwrap();
        function_ids.push(id);
        if let Some(op) = opcode {
            handled.push((op, id));
            metadata.push_str(&format!("assert!(Code::{name} as u8 == {op});\n"));
        }
    }
    metadata.push_str("};\n");
    // Calls to the exported helpers import them; tail calls name functions of
    // this file. Imported signatures take the platform convention.
    let mut imports: BTreeMap<String, FuncId> = BTreeMap::new();
    for function in &mut sources {
        let references: Vec<_> = function
            .dfg
            .ext_funcs
            .iter()
            .filter_map(|(reference, data)| match &data.name {
                ExternalName::TestCase(callee) => Some((
                    reference,
                    callee.to_string().trim_start_matches('%').to_string(),
                    data.signature,
                )),
                _ => None,
            })
            .collect();
        for (reference, callee, sig_ref) in references {
            let helper = is_runtime_export(&callee);
            let id = if helper {
                function.dfg.signatures[sig_ref].call_conv = conv;
                let signature = function.dfg.signatures[sig_ref].clone();
                *imports.entry(callee.clone()).or_insert_with(|| {
                    module.declare_function(&callee, Linkage::Import, &signature).unwrap()
                })
            } else {
                let index = names
                    .iter()
                    .position(|n| *n == callee)
                    .ok_or_else(|| format!("unknown function {callee}"))?;
                function.dfg.signatures[sig_ref].call_conv = CallConv::Tail;
                function_ids[index]
            };
            let user = function.declare_imported_user_function(UserExternalName {
                namespace: 0,
                index: id.as_u32(),
            });
            let data = &mut function.dfg.ext_funcs[reference];
            data.name = ExternalName::user(user);
            data.colocated = !helper;
        }
    }
    let mut listings = String::new();
    let mut ctx = module.make_context();
    for (index, function) in sources.iter().enumerate() {
        // The producer decided the IR; the glue compiles it as printed.
        ctx.func = function.clone();
        ctx.want_disasm = true;
        listings.push_str(&format!("\n{}\n", ctx.func.display()));
        module
            .define_function(function_ids[index], &mut ctx)
            .map_err(|e| format!("{}: {e}", function.name))?;
        listings.push_str(ctx.compiled_code().unwrap().vcode.as_deref().unwrap_or(""));
        module.clear_context(&mut ctx);
    }
    // The entry: check the frame contract, then dispatch the first
    // instruction through the table.
    ctx.func.signature = entry_sig;
    ctx.want_disasm = true;
    {
        let mut fbc = FunctionBuilderContext::new();
        let mut b = FunctionBuilder::new(&mut ctx.func, &mut fbc);
        let start = b.create_block();
        b.append_block_params_for_function_params(start);
        b.switch_to_block(start);
        let params = b.block_params(start).to_vec();
        let sig = b.import_signature(tail.clone());
        let data = module.declare_data_in_func(table_id, b.func);
        let table = b.ins().symbol_value(types::I64, data);
        let flags = MemFlagsData::new().with_notrap();
        // A VM register window begins immediately after its four frame-header
        // words. Check the contract before any handler executes; a foreign
        // caller with independent windows leaves unchanged through the
        // ordinary Rust fallback.
        let frame = b.ins().iadd_imm_s(params[1], -32);
        let valid = b.ins().icmp(IntCC::Equal, frame, params[5]);
        let enter = b.create_block();
        let reject = b.create_block();
        b.ins().brif(valid, enter, &[], reject, &[]);
        b.switch_to_block(reject);
        b.ins().return_(&[params[0]]);
        b.switch_to_block(enter);
        let op = b.ins().uload8(types::I64, flags, params[0], 0);
        let offset = b.ins().ishl_imm_u(op, 3);
        let slot = b.ins().iadd(table, offset);
        let target = b.ins().load(types::I64, flags, slot, 0);
        let mut arguments = params.clone();
        arguments[5] = table;
        let call = b.ins().call_indirect(sig, target, &arguments);
        let value = b.inst_results(call)[0];
        b.ins().return_(&[value]);
        b.seal_all_blocks();
        b.finalize(module.target_config());
    }
    listings.push_str(&format!("\n{}\n", ctx.func.display()));
    module.define_function(entry, &mut ctx).map_err(|e| e.to_string())?;
    listings.push_str(ctx.compiled_code().unwrap().vcode.as_deref().unwrap_or(""));
    module.clear_context(&mut ctx);
    // The resume entry: the frame driver's policy for the frame the context
    // names, then the chain from there.
    let resume_index = names
        .iter()
        .position(|n| n == "resumeSlow")
        .ok_or("resumeSlow: the frame driver's entry is required")?;
    let mut resume_sig = Signature::new(conv);
    resume_sig.params.push(AbiParam::new(types::I64));
    resume_sig.returns.push(AbiParam::new(types::I64));
    let resume = module
        .declare_function("nupp_native_runtime_resume", Linkage::Export, &resume_sig)
        .unwrap();
    ctx.func.signature = resume_sig;
    ctx.want_disasm = true;
    {
        let mut fbc = FunctionBuilderContext::new();
        let mut b = FunctionBuilder::new(&mut ctx.func, &mut fbc);
        let start = b.create_block();
        b.append_block_params_for_function_params(start);
        b.switch_to_block(start);
        let context = b.block_params(start)[0];
        let data = module.declare_data_in_func(table_id, b.func);
        let table = b.ins().symbol_value(types::I64, data);
        let target = module.declare_func_in_func(function_ids[resume_index], b.func);
        let pc = b.ins().iconst(types::I64, 0);
        let call = b.ins().call(target, &[pc, context, table]);
        let value = b.inst_results(call)[0];
        b.ins().return_(&[value]);
        b.seal_all_blocks();
        b.finalize(module.target_config());
    }
    listings.push_str(&format!("\n{}\n", ctx.func.display()));
    module.define_function(resume, &mut ctx).map_err(|e| e.to_string())?;
    listings.push_str(ctx.compiled_code().unwrap().vcode.as_deref().unwrap_or(""));
    module.clear_context(&mut ctx);
    // `leave`: the table entry of every opcode without a handler, handing the
    // instruction back to Rust.
    ctx.func.signature = tail.clone();
    ctx.want_disasm = true;
    {
        let mut fbc = FunctionBuilderContext::new();
        let mut b = FunctionBuilder::new(&mut ctx.func, &mut fbc);
        let start = b.create_block();
        b.append_block_params_for_function_params(start);
        b.switch_to_block(start);
        let pc = b.block_params(start)[0];
        b.ins().return_(&[pc]);
        b.seal_all_blocks();
        b.finalize(module.target_config());
    }
    listings.push_str(&format!("\n{}\n", ctx.func.display()));
    module.define_function(leave, &mut ctx).map_err(|e| e.to_string())?;
    listings.push_str(ctx.compiled_code().unwrap().vcode.as_deref().unwrap_or(""));
    let mut data = DataDescription::new();
    data.define(vec![0; 256 * 8].into_boxed_slice());
    data.set_align(8);
    for op in 0..256 {
        let id = handled
            .iter()
            .find(|(code, _)| *code as usize == op)
            .map(|(_, id)| *id)
            .unwrap_or(leave);
        let function = module.declare_func_in_data(id, &mut data);
        data.write_function_addr((op * 8) as u32, function);
    }
    module.define_data(table_id, &data).map_err(|e| e.to_string())?;
    // The step table: `leave` for every opcode. A handler entered with it as
    // its table runs its own instruction and stops at the next dispatch,
    // answering the next instruction's address (or its own, when it hands
    // the instruction to Rust): the JIT's way to run one instruction on the
    // handlers without a second implementation of it.
    let step_table_id = module
        .declare_data("native_runtime_step_table", Linkage::Local, false, false)
        .unwrap();
    let mut data = DataDescription::new();
    data.define(vec![0; 256 * 8].into_boxed_slice());
    data.set_align(8);
    for op in 0..256 {
        let function = module.declare_func_in_data(leave, &mut data);
        data.write_function_addr((op * 8) as u32, function);
    }
    module.define_data(step_table_id, &data).map_err(|e| e.to_string())?;
    // `nupp_native_runtime_step(pc, regs, ints, floats, ctx, frame)`: the
    // instruction at `pc` through its handler, with the step table; the
    // handler's exit word comes back.
    let step = module
        .declare_function("nupp_native_runtime_step", Linkage::Export, &entry_sig_of(conv))
        .unwrap();
    ctx.func.signature = entry_sig_of(conv);
    ctx.want_disasm = true;
    {
        let mut fbc = FunctionBuilderContext::new();
        let mut b = FunctionBuilder::new(&mut ctx.func, &mut fbc);
        let start = b.create_block();
        b.append_block_params_for_function_params(start);
        b.switch_to_block(start);
        let params = b.block_params(start).to_vec();
        let sig = b.import_signature(tail.clone());
        let real = module.declare_data_in_func(table_id, b.func);
        let real = b.ins().symbol_value(types::I64, real);
        let steps = module.declare_data_in_func(step_table_id, b.func);
        let steps = b.ins().symbol_value(types::I64, steps);
        let flags = MemFlagsData::new().with_notrap();
        let op = b.ins().uload8(types::I64, flags, params[0], 0);
        let offset = b.ins().ishl_imm_u(op, 3);
        let slot = b.ins().iadd(real, offset);
        let target = b.ins().load(types::I64, flags, slot, 0);
        let mut arguments = params.clone();
        arguments[5] = steps;
        let call = b.ins().call_indirect(sig, target, &arguments);
        let value = b.inst_results(call)[0];
        b.ins().return_(&[value]);
        b.seal_all_blocks();
        b.finalize(module.target_config());
    }
    listings.push_str(&format!("\n{}\n", ctx.func.display()));
    module.define_function(step, &mut ctx).map_err(|e| e.to_string())?;
    listings.push_str(ctx.compiled_code().unwrap().vcode.as_deref().unwrap_or(""));
    module.clear_context(&mut ctx);
    let bytes = module.finish().emit().map_err(|e| e.to_string())?;
    std::fs::write(output, bytes).map_err(|e| e.to_string())?;
    std::fs::write(format!("{output}.rs"), metadata).map_err(|e| e.to_string())?;
    std::fs::write(format!("{output}.txt"), listings).map_err(|e| e.to_string())?;
    Ok(())
}
