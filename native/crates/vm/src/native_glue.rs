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
pub const LAYOUT_FIELDS: [&str; 79] = [
    "funcs", "FuncInfo.size", "FuncInfo.consts", "jit_frames", "nframe_entries", "single_step",
    "frame_entries", "stack", "cap", "cur", "nfuncs", "result", "last_nres",
    "feedback", "guard", "unavailable_fid", "FuncInfo.code",
    "FuncInfo.frame_words", "FuncInfo.nparams", "FuncInfo.off_i", "FuncInfo.off_f",
    "FuncInfo.vararg", "FuncInfo.calls", "FuncInfo.typed", "FuncInfo.native", "Header.aux_len",
    "Header.aux", "Header.flags", "Table.meta", "Header.kind", "Header.aux_ptr", "Ins.op",
    "Ins.a", "Ins.b", "Ins.c", "Ins.imm", "Ins.k", "pc", "status", "marking", "shapes",
    "ShapeInfo.size", "ShapeInfo.table", "ShapeInfo.mask", "Table.hash_ptr", "Table.hash_mask",
    "slow_calls", "nslow_calls", "frame_threshold", "budget", "Code.PadResults", "Code.CallT",
    "Table.hash_cap", "Table.hash_len", "Table.hash_order", "Table.hash_rank",
    "cleanups", "ncleanups", "Cleanup.size", "Cleanup.frame", "Cleanup.value", "Cleanup.callback",
    "FuncInfo.ncode", "ShapeInfo.names", "FuncInfo.off_v",
    "FuncInfo.nv_params", "FuncInfo.nf_params", "FuncInfo.float_return",
    "Code.SetField", "Code.SetIdx",
    "Packet.size", "Packet.a", "Packet.b", "Packet.c", "Packet.out", "Packet.lanes", "Packet.kind", "Packet.operation", "Packet.mask",
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
        "single_step" => offset_of!(Ctx, single_step),
        "guard" => offset_of!(Ctx, guard),
        "unavailable_fid" => offset_of!(Ctx, unavailable_fid),
        "FuncInfo.code" => offset_of!(FuncInfo, code),
        "FuncInfo.frame_words" => offset_of!(FuncInfo, frame_words),
        "FuncInfo.nparams" => offset_of!(FuncInfo, nparams),
        "FuncInfo.off_i" => offset_of!(FuncInfo, off_i),
        "FuncInfo.off_f" => offset_of!(FuncInfo, off_f),
        "FuncInfo.off_v" => offset_of!(FuncInfo, off_v),
        "FuncInfo.vararg" => offset_of!(FuncInfo, vararg),
        "FuncInfo.calls" => offset_of!(FuncInfo, calls),
        "FuncInfo.typed" => offset_of!(FuncInfo, typed),
        "FuncInfo.native" => offset_of!(FuncInfo, native),
        "FuncInfo.nv_params" => offset_of!(FuncInfo, nv_params),
        "FuncInfo.nf_params" => offset_of!(FuncInfo, nf_params),
        "FuncInfo.float_return" => offset_of!(FuncInfo, float_return),
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
        "ShapeInfo.names" => offset_of!(ShapeInfo, names),
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
        "Code.CallT" => crate::threaded::Code::CallT as usize,
        "Code.SetField" => crate::threaded::Code::SetField as usize,
        "Code.SetIdx" => crate::threaded::Code::SetIdx as usize,
        "Table.hash_cap" => hash_part(offset_of!(crate::heap::ValueTable, cap)),
        "Table.hash_len" => hash_part(offset_of!(crate::heap::ValueTable, len)),
        "Table.hash_order" => hash_part(offset_of!(crate::heap::ValueTable, order)),
        "Table.hash_rank" => hash_part(offset_of!(crate::heap::ValueTable, rank)),
        // The task's cleanup records (contracts 6.5b), read and rewritten in
        // place by the core.
        "cleanups" => offset_of!(Ctx, cleanups),
        "ncleanups" => offset_of!(Ctx, ncleanups),
        "Cleanup.size" => std::mem::size_of::<crate::interp::Cleanup>(),
        "Cleanup.frame" => offset_of!(crate::interp::Cleanup, frame),
        "Cleanup.value" => offset_of!(crate::interp::Cleanup, value),
        "Cleanup.callback" => offset_of!(crate::interp::Cleanup, callback),
        // Where a function's jump tables begin, past its code.
        "FuncInfo.ncode" => offset_of!(FuncInfo, ncode),
        "Packet.a" => offset_of!(crate::simd::Packet, a),
        "Packet.b" => offset_of!(crate::simd::Packet, b),
        "Packet.c" => offset_of!(crate::simd::Packet, c),
        "Packet.out" => offset_of!(crate::simd::Packet, out),
        "Packet.lanes" => offset_of!(crate::simd::Packet, lanes),
        "Packet.kind" => offset_of!(crate::simd::Packet, kind),
        "Packet.operation" => offset_of!(crate::simd::Packet, operation),
        "Packet.mask" => offset_of!(crate::simd::Packet, mask),
        "Packet.size" => std::mem::size_of::<crate::simd::Packet>(),
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

/// Checks only ABI identity transported by jump/branch block arguments.
/// No machine IR is rewritten and no computation is treated as identity.
fn transports_context(f: &Function, value: cranelift_codegen::ir::Value, original: cranelift_codegen::ir::Value) -> bool {
    let Some(entry) = f.layout.entry_block() else { return false; };
    let mut pending = vec![value];
    let mut visited = BTreeSet::new();
    let mut users: BTreeMap<cranelift_codegen::ir::Value, Vec<cranelift_codegen::ir::Value>> = BTreeMap::new();
    while let Some(value) = pending.pop() {
        if !visited.insert(value) || value == original { continue; }
        let ValueDef::Param(block, index) = f.dfg.value_def(value) else { return false; };
        if block == entry { return false; }
        let mut inputs = 0;
        for pred in f.layout.blocks() {
            let Some(inst) = f.layout.last_inst(pred) else { continue; };
            let data = &f.dfg.insts[inst];
            for edge in data.branch_destination(&f.dfg.jump_tables, &f.dfg.exception_tables) {
                if edge.block(&f.dfg.value_lists) != block { continue; }
                if !matches!(data.opcode(), Opcode::Jump | Opcode::Brif) { return false; }
                let Some(input) = edge.args(&f.dfg.value_lists).nth(index).and_then(|arg| arg.as_value()) else { return false; };
                inputs += 1;
                users.entry(input).or_default().push(value);
                pending.push(input);
            }
        }
        if inputs == 0 { return false; }
    }
    // Every component must be rooted, including a disconnected cycle feeding
    // a join that also has a direct original-context input.
    let mut rooted = BTreeSet::new();
    let mut pending = vec![original];
    while let Some(value) = pending.pop() {
        if !rooted.insert(value) { continue; }
        if let Some(values) = users.get(&value) { pending.extend(values.iter().copied()); }
    }
    visited.iter().all(|value| rooted.contains(value))
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
    if !f.global_values.is_empty() || !f.dynamic_stack_slots.is_empty() || handler && !f.sized_stack_slots.is_empty() {
        return Err(format!("{}: handlers reference no symbols or stack", f.name));
    }
    let mut scratch = 0u64;
    for slot in f.sized_stack_slots.values() {
        scratch += slot.size as u64;
        if slot.size == 0 || slot.size > 4096 || slot.align_shift > 4 || scratch > 4096 {
            return Err(format!("{}: support scratch must be bounded by 4096 bytes and 16-byte alignment", f.name));
        }
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
                    if args.len() != 7 || !transports_context(f, args[5], params[context]) {
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

// These are raw, non-reentrant Nupp object-library entries. The C wrappers
// below transport their word arguments without reconstructing VM state.
fn object_leaf(name: &str) -> Option<(&'static str, usize)> {
    match name {
        "slotHash" => Some(("nupp_object_slot_hash", 1)),
        "stringHash" => Some(("nupp_object_string_hash", 3)),
        "weakLookupAction" => Some(("nupp_object_weak_lookup_action", 7)),
        "tableProbe" => Some(("nupp_object_table_probe", 4)),
        "tableCapacity" => Some(("nupp_object_table_capacity", 1)),
        "tableNeedsGrowth" => Some(("nupp_object_table_needs_growth", 2)),
        "tableInitialize" => Some(("nupp_object_table_initialize", 2)),
        "tableLiveCount" => Some(("nupp_object_table_live_count", 4)),
        "tableRehash" => Some(("nupp_object_table_rehash", 8)),
        "shapeCapacity" => Some(("nupp_object_shape_capacity", 1)),
        "shapeFill" => Some(("nupp_object_shape_fill", 4)),
        "shapeFind" => Some(("nupp_object_shape_find", 4)),
        _ => None,
    }
}

fn require_object_leaf(f: &Function, arity: usize) -> Result<(), String> {
    if f.signature.call_conv != CallConv::Tail
        || f.signature.params.len() != arity
        || f.signature.params.iter().any(|p| p.value_type != types::I64)
        || f.signature.returns.len() != 1
        || f.signature.returns[0].value_type != types::I64
    {
        return Err(format!("{}: object leaf word signature required", f.name));
    }
    let name = name_of(f);
    let hash_call = matches!(name.as_str(), "shapeFill" | "shapeFind" | "tableProbe");
    let rehash = name == "tableRehash";
    let calls = hash_call || rehash;
    let memory = hash_call || matches!(name.as_str(), "stringHash" | "tableInitialize" | "tableLiveCount" | "tableRehash");
    let write = matches!(name.as_str(), "shapeFill" | "tableInitialize" | "tableRehash");
    if !f.global_values.is_empty() || !f.sized_stack_slots.is_empty()
        || !f.dynamic_stack_slots.is_empty() || !calls && !f.dfg.ext_funcs.is_empty()
    {
        return Err(format!("{}: object leaf references no symbols, stack or calls", f.name));
    }
    for (_, declaration) in f.dfg.ext_funcs.iter() {
        let ExternalName::TestCase(target) = &declaration.name else {
            return Err(format!("{}: object leaf requires a local scalar callee", f.name));
        };
        let target = target.to_string();
        let target = target.trim_start_matches('%');
        let arity = if hash_call && target == "slotHash" { 1 }
            else if rehash && matches!(target, "tableProbe" | "tableLiveCount") { 4 }
            else if rehash && target == "tableCapacity" { 1 }
            else { return Err(format!("{}: object leaf callee is not approved", f.name)); };
        let expected = Signature {
            params: vec![AbiParam::new(types::I64); arity],
            returns: vec![AbiParam::new(types::I64)],
            call_conv: CallConv::Tail,
        };
        if f.dfg.signatures[declaration.signature] != expected {
            return Err(format!("{}: object leaf callee signature changed", f.name));
        }
    }
    for block in f.layout.blocks() {
        for inst in f.layout.block_insts(block) {
            let opcode = f.dfg.insts[inst].opcode();
            if opcode.is_call() && (!calls || opcode != Opcode::Call) {
                return Err(format!("{}: object leaf cannot call or dispatch", f.name));
            }
            if opcode.can_load() && !memory || opcode.can_store() && !write {
                return Err(format!("{}: object leaf cannot access memory with this capability", f.name));
            }
        }
    }
    Ok(())
}

// This label transports checked source selection and ABI names. It grants
// no semantic facts to the machine IR and never changes an instruction.
fn allocator_support_names(
    text: &str,
    definitions: &BTreeMap<String, Signature>,
) -> Result<BTreeSet<String>, String> {
    const PREFIX: &str = "; Nupp allocator support: ";
    let mut labels = text.lines().filter_map(|line| line.strip_prefix(PREFIX));
    let Some(label) = labels.next() else {
        return Ok(BTreeSet::new());
    };
    if labels.next().is_some()
        || !text
            .lines()
            .next()
            .is_some_and(|line| line.starts_with(PREFIX))
    {
        return Err("allocator support selection must appear once on the first line".into());
    }
    let mut names = BTreeSet::new();
    for name in label.split(',') {
        if name.is_empty()
            || !name.bytes().all(|c| c.is_ascii_alphanumeric() || c == b'_')
            || name.as_bytes()[0].is_ascii_digit()
            || !names.insert(name.to_owned())
        {
            return Err("allocator support names must be unique source names".into());
        }
        if !definitions.contains_key(name)
            || object_leaf(name).is_some()
            || code_by_name(name).is_some()
        {
            return Err(format!(
                "{name}: allocator support must name an ordinary local definition"
            ));
        }
    }
    Ok(names)
}

fn allocator_entry(name: &str) -> Option<(&'static str, usize, bool)> {
    Some(match name {
        "allocatorArenaOpen" => ("nupp_allocator_arena_open", 1, true),
        "allocatorArenaClose" => ("nupp_allocator_arena_close", 1, false),
        "allocatorCreate" => ("nupp_allocator_create", 1, true),
        "allocatorDestroy" => ("nupp_allocator_destroy", 1, false),
        "allocatorAllocate" => ("nupp_allocator_allocate", 8, true),
        "allocatorResize" => ("nupp_allocator_resize", 4, false),
        "allocatorReclaim" => ("nupp_allocator_reclaim", 4, false),
        "allocatorSnapshot" => ("nupp_allocator_snapshot", 2, false),
        "allocatorShade" => ("nupp_allocator_shade", 2, true),
        "allocatorBarrier" => ("nupp_allocator_barrier", 4, false),
        "allocatorBarrierShade" => ("nupp_allocator_barrier_shade", 2, false),
        "allocatorGrayPop" => ("nupp_allocator_gray_pop", 1, true),
        "allocatorGrayEmpty" => ("nupp_allocator_gray_empty", 1, true),
        "allocatorChunkCount" => ("nupp_allocator_chunk_count", 1, true),
        "allocatorChunk" => ("nupp_allocator_chunk", 3, false),
        "allocatorLargeCount" => ("nupp_allocator_large_count", 1, true),
        "allocatorLarge" => ("nupp_allocator_large", 2, true),
        "allocatorCompactLarge" => ("nupp_allocator_compact_large", 1, false),
        "allocatorIsLiveSlot" => ("nupp_allocator_is_live_slot", 2, true),
        "allocatorSlotBytes" => ("nupp_allocator_slot_bytes", 1, true),
        _ => return None,
    })
}

fn allocator_os_signature(name: &str, call_conv: CallConv) -> Option<Signature> {
    let (arity, result) = match name {
        "nupp_os_map_pages" => (1, true),
        "nupp_os_unmap_pages" => (2, false),
        "nupp_os_advise_pages" => (3, false),
        "nupp_os_page_size" | "nupp_os_monotonic_nanos" => (0, true),
        "nupp_os_read_input" | "nupp_os_write_output" => (2, true),
        _ => return None,
    };
    let mut signature = Signature::new(call_conv);
    signature.params = vec![AbiParam::new(types::I64); arity];
    if result {
        signature.returns.push(AbiParam::new(types::I64));
    }
    Some(signature)
}

fn require_allocator_support(
    f: &Function,
    support: &BTreeSet<String>,
    definitions: &BTreeMap<String, Signature>,
    platform: CallConv,
) -> Result<(), String> {
    let scalar = |ty| {
        matches!(
            ty,
            types::I8 | types::I16 | types::I32 | types::I64 | types::F32 | types::F64
        )
    };
    if !support.contains(&name_of(f))
        || f.signature.call_conv != CallConv::Tail
        || f.signature.params.len() > 8
        || f.signature.returns.len() > 1
        || f.signature
            .params
            .iter()
            .chain(&f.signature.returns)
            .any(|p| {
                !scalar(p.value_type) || p.purpose != cranelift_codegen::ir::ArgumentPurpose::Normal
            })
    {
        return Err(format!(
            "{}: allocator support requires its exact scalar Tail signature",
            f.name
        ));
    }
    if let Some((_, arity, result)) = allocator_entry(&name_of(f)) {
        if f.signature.params.len() != arity
            || f.signature
                .params
                .iter()
                .any(|p| p.value_type != types::I64)
            || f.signature.returns.len() != usize::from(result)
            || f.signature
                .returns
                .iter()
                .any(|p| p.value_type != types::I64)
        {
            return Err(format!(
                "{}: allocator entry signature differs from its C transport",
                f.name
            ));
        }
    }
    if !f.global_values.is_empty() || !f.dynamic_stack_slots.is_empty() {
        return Err(format!(
            "{}: allocator support has no global symbols or dynamic stack",
            f.name
        ));
    }
    let mut scratch = 0u64;
    for slot in f.sized_stack_slots.values() {
        if slot.kind != cranelift_codegen::ir::StackSlotKind::ExplicitSlot
            || slot.size == 0
            || slot.size > 4096
            || slot.align_shift > 4
        {
            return Err(format!(
                "{}: allocator scratch must be fixed and bounded by 4096 bytes and 16-byte alignment",
                f.name
            ));
        }
        let alignment = 1u64 << slot.align_shift;
        scratch += (slot.size as u64 + alignment - 1) & !(alignment - 1);
        if scratch > 4096 {
            return Err(format!(
                "{}: allocator scratch including alignment exceeds 4096 bytes",
                f.name
            ));
        }
    }
    for (_, declaration) in f.dfg.ext_funcs.iter() {
        let ExternalName::TestCase(target) = &declaration.name else {
            return Err(format!(
                "{}: allocator support needs named checked callees",
                f.name
            ));
        };
        let target = target.to_string();
        let target = target.trim_start_matches('%');
        let signature = &f.dfg.signatures[declaration.signature];
        if support.contains(target) || object_leaf(target).is_some() {
            let expected = definitions
                .get(target)
                .ok_or_else(|| format!("{target}: allocator callee has no local definition"))?;
            if signature != expected || signature.call_conv != CallConv::Tail {
                return Err(format!(
                    "{target}: allocator local callee signature differs from its definition"
                ));
            }
        } else {
            // An unspecified CLIF convention is Fast until import transport
            // selects the host C convention. It must never request Tail here.
            if signature.call_conv != CallConv::Fast && signature.call_conv != platform
                || allocator_os_signature(target, signature.call_conv).as_ref() != Some(signature)
            {
                return Err(format!(
                    "{target}: allocator support may import only exact OS edges or selected local helpers"
                ));
            }
        }
    }
    for block in f.layout.blocks() {
        for inst in f.layout.block_insts(block) {
            let data = &f.dfg.insts[inst];
            if data.opcode().is_call() {
                if !matches!(data.opcode(), Opcode::Call | Opcode::ReturnCall) {
                    return Err(format!(
                        "{}: allocator support cannot dispatch or call indirectly",
                        f.name
                    ));
                }
                if data.opcode() == Opcode::ReturnCall {
                    let InstructionData::Call { func_ref, .. } = data else {
                        return Err("allocator tail call must name a local function".into());
                    };
                    let ExternalName::TestCase(name) = &f.dfg.ext_funcs[*func_ref].name else {
                        return Err("allocator tail call must name a local function".into());
                    };
                    if name
                        .to_string()
                        .trim_start_matches('%')
                        .starts_with("nupp_os_")
                    {
                        return Err(
                            "allocator support cannot tail-transfer to the C OS boundary".into(),
                        );
                    }
                }
            }
            if data.opcode() == Opcode::FuncAddr {
                return Err(format!(
                    "{}: allocator support cannot expose code addresses",
                    f.name
                ));
            }
        }
    }
    Ok(())
}

/// The build-time sidecar: every layout the handlers were compiled against,
/// and every opcode number they handle, asserted where the object is linked.
fn metadata_header() -> String {
    let mut metadata = String::from("// Generated with the native object. Private ABI.\n");
    metadata.push_str("pub(crate) const OBJECT_ABI: u32 = 8;\n");
    metadata.push_str(
        "const _: () = { assert!(HDR == 4); assert!(std::mem::size_of::<Ins>() == 16); assert!(crate::interp::MAX_RESULTS == 128);\n",
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
        ("single_step", offset_of!(Ctx, single_step)),
        ("guard", offset_of!(Ctx, guard)),
        ("unavailable_fid", offset_of!(Ctx, unavailable_fid)),
        ("frame_threshold", offset_of!(Ctx, frame_threshold)),
        ("budget", offset_of!(Ctx, budget)),
        ("cleanups", offset_of!(Ctx, cleanups)),
        ("ncleanups", offset_of!(Ctx, ncleanups)),
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
    for field in ["size", "a", "b", "c", "out", "lanes", "kind", "operation", "mask"] {
        let key = format!("Packet.{field}");
        let value = layout(&key).unwrap();
        let expr = if field == "size" { "std::mem::size_of::<crate::simd::Packet>()".to_owned() }
            else { format!("std::mem::offset_of!(crate::simd::Packet, {field})") };
        metadata.push_str(&format!("assert!({expr} == {value});\n"));
    }
    metadata.push_str(&format!("assert!(crate::simd::native_abi_hash() == {});\n", crate::simd::native_abi_hash()));
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
        ("off_v", offset_of!(FuncInfo, off_v)),
        ("vararg", offset_of!(FuncInfo, vararg)),
        ("calls", offset_of!(FuncInfo, calls)),
        ("typed", offset_of!(FuncInfo, typed)),
        ("native", offset_of!(FuncInfo, native)),
        ("ncode", offset_of!(FuncInfo, ncode)),
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
    metadata.push_str(&format!(
        "assert!(std::mem::size_of::<crate::interp::Cleanup>() == {} && std::mem::offset_of!(crate::interp::Cleanup, frame) == {} && std::mem::offset_of!(crate::interp::Cleanup, value) == {} && std::mem::offset_of!(crate::interp::Cleanup, callback) == {});\n",
        std::mem::size_of::<crate::interp::Cleanup>(),
        offset_of!(crate::interp::Cleanup, frame),
        offset_of!(crate::interp::Cleanup, value),
        offset_of!(crate::interp::Cleanup, callback)
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
    metadata.push_str("assert!(crate::value::T_INTEGER == 0x0007_0000_0000_0000);\n");
    metadata
}

/// `nupp-vm native object IN.clif OUT.o`: compiles the handler file into the
/// object the `native-runtime` feature links, beside its `.rs` sidecar and
/// `.txt` listings. A function named like a core opcode is that opcode's
/// handler. Object-library leaves have C word entry points; the remaining
/// functions support the handlers through tail calls. The entry derives the
/// frame from the register window and
/// dispatches through the 256-entry table, which handlers receive as their
/// sixth argument. `resumeSlow`, the frame driver's entry for the frame on
/// top, is exported beside it as `nupp_native_runtime_resume(ctx)`.
pub fn write_object(input: &str, output: &str) -> Result<(), String> {
    let text = std::fs::read_to_string(input).map_err(|e| e.to_string())?;
    let simd_abi = text.lines().find_map(|line| line.strip_prefix("; Nupp SIMD ABI: "));
    if let Some(abi) = simd_abi {
        let abi = abi.trim();
        let abi = abi.strip_prefix("0x").and_then(|s| u64::from_str_radix(s, 16).ok())
            .or_else(|| abi.parse::<u64>().ok()).ok_or("invalid Nupp SIMD descriptor ABI")?;
        if abi != crate::simd::native_abi_hash() { return Err("Nupp SIMD descriptor ABI differs from the runtime".into()); }
    }
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
    let mut definitions = BTreeMap::new();
    for function in &sources {
        if definitions.insert(name_of(function), function.signature.clone()).is_some() {
            return Err(format!("{}: duplicate native definition", function.name));
        }
    }
    let allocator_support = allocator_support_names(&text, &definitions)?;
    let locals: BTreeSet<String> = names.iter().cloned().collect();
    let mut handled: Vec<(u8, FuncId)> = Vec::new();
    let mut function_ids = Vec::new();
    for function in &sources {
        let name = name_of(function);
        let opcode = code_by_name(&name);
        if name == "Simd" && simd_abi.is_none() { return Err("Simd handler requires its descriptor ABI".into()); }
        if allocator_support.contains(&name) {
            require_allocator_support(function, &allocator_support, &definitions, conv)?;
        } else if let Some((_, arity)) = object_leaf(&name) {
            require_object_leaf(function, arity)?;
        } else {
            require_handler_clif(function, &tail, opcode.is_some(), &locals)?;
        }
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
    let handler_codes = handled.iter().map(|(code, _)| code.to_string()).collect::<Vec<_>>().join(", ");
    metadata.push_str(&format!("#[cfg(test)] const NATIVE_RUNTIME_HANDLER_CODES: &[u8] = &[{handler_codes}];\n"));
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
    // Object-library leaves have ordinary C entry points and exact Tail
    // implementations. Only this mechanical ABI transport is generated here.
    for (index, name) in names.iter().enumerate() {
        let symbol = if let Some((symbol, _)) = object_leaf(name) { symbol }
            else if allocator_support.contains(name) {
                let Some((symbol, _, _)) = allocator_entry(name) else { continue; };
                symbol
            } else { continue; };
        let mut signature = sources[index].signature.clone();
        signature.call_conv = conv;
        let wrapper = module.declare_function(symbol, Linkage::Export, &signature)
            .map_err(|e| e.to_string())?;
        ctx.func.signature = signature;
        {
            let mut fbc = FunctionBuilderContext::new();
            let mut b = FunctionBuilder::new(&mut ctx.func, &mut fbc);
            let entry = b.create_block();
            b.append_block_params_for_function_params(entry);
            b.switch_to_block(entry);
            let args = b.block_params(entry).to_vec();
            let target = module.declare_func_in_func(function_ids[index], b.func);
            let call = b.ins().call(target, &args);
            let results = b.inst_results(call).to_vec();
            b.ins().return_(&results);
            b.seal_all_blocks();
            b.finalize(module.target_config());
        }
        module.define_function(wrapper, &mut ctx).map_err(|e| e.to_string())?;
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
    // `leave`: an explicit stop boundary, also used by the one-step table.
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
    module.clear_context(&mut ctx);
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
    // answering the next instruction's address. A same-PC result is a guest
    // self-loop. Compiled boundaries use these same handlers.
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

#[cfg(test)]
mod scratch_contract_tests {
    use super::*;

    fn check(declaration: &str, handler: bool) -> Result<(), String> {
        let params = if handler { "i64, i64, i64, i64, i64, i64" } else { "i64, i64, i64" };
        let block = if handler { "v0: i64, v1: i64, v2: i64, v3: i64, v4: i64, v5: i64" } else { "v0: i64, v1: i64, v2: i64" };
        let text = format!("function %scratchSlow({params}) -> i64 tail {{\n{declaration}\nblock0({block}):\n return v0\n}}\n");
        let functions = cranelift_reader::parse_functions(&text).unwrap();
        require_handler_clif(&functions[0], &signature(CallConv::Tail), handler, &BTreeSet::new())
    }

    #[test]
    fn native_support_scratch_is_fixed_bounded_and_never_in_handlers() {
        check("ss0 = explicit_slot 2080, align = 16", false).unwrap();
        assert!(check("ss0 = explicit_slot 16, align = 16", true).unwrap_err().contains("no symbols or stack"));
        for declaration in [
            "ss0 = explicit_slot 0, align = 16",
            "ss0 = explicit_slot 4097, align = 16",
            "ss0 = explicit_slot 16, align = 32",
            "ss0 = explicit_slot 4096, align = 16\nss1 = explicit_slot 1, align = 1",
        ] {
            assert!(check(declaration, false).unwrap_err().contains("support scratch"), "{declaration}");
        }
        assert!(check("dss0 = explicit_dynamic_slot dt0", false).unwrap_err().contains("no symbols or stack"));
    }
}

#[cfg(test)]
mod context_transport_tests {
    use super::*;
    fn check(body: &str) -> Result<(), String> {
        let text = format!("function %Move(i64,i64,i64,i64,i64,i64) -> i64 tail {{\nsig0 = (i64,i64,i64,i64,i64,i64) -> i64 tail\nblock0(v0:i64,v1:i64,v2:i64,v3:i64,v4:i64,v5:i64):\n{body}\n}}\n");
        let f = cranelift_reader::parse_functions(&text).unwrap().remove(0);
        require_handler_clif(&f, &signature(CallConv::Tail), true, &BTreeSet::new())
    }
    #[test]
    fn native_context_identity_accepts_rooted_loop_transport_only() {
        let body = "jump block1(v4)\nblock1(v6:i64):\n v7=iconst.i8 1\n brif v7, block2(v6), block3(v6)\nblock2(v8:i64):\n jump block1(v8)\nblock3(v9:i64):\n return_call_indirect sig0, v5(v0,v1,v2,v3,v9,v5)";
        check(body).unwrap();
        assert!(check(&body.replace("block2(v6)", "block2(v3)")).is_err());
        assert!(check(&body.replace("jump block1(v8)", "v11=iconst.i64 0\n v10=iadd v8, v11\n jump block1(v10)")).is_err());
        // Two independent transported parameters must not be confused.
        let two = "jump block1(v3,v4)\nblock1(v6:i64,v7:i64):\n return_call_indirect sig0, v5(v0,v1,v2,v3,v7,v5)";
        check(two).unwrap();
        assert!(check(&two.replace("v3,v7,v5)", "v3,v6,v5)")).is_err());
    }
    #[test]
    fn native_context_identity_rejects_unrooted_and_missing_feeders() {
        let mixed = "jump block2(v4)\nblock1:\n v6=iconst.i32 0\n br_table v6, block2(v3), [block2(v4)]\nblock2(v7:i64):\n return_call_indirect sig0, v5(v0,v1,v2,v3,v7,v5)";
        assert!(check(mixed).is_err(), "unsupported branch feeder must not be ignored");
        for body in [
            "jump block2(v4)\nblock1(v6:i64):\n jump block1(v6)\nblock2(v7:i64):\n return_call_indirect sig0, v5(v0,v1,v2,v3,v6,v5)",
            "jump block2(v4)\nblock1(v6:i64):\n v8=iconst.i8 1\n brif v8, block1(v6), block2(v6)\nblock2(v7:i64):\n return_call_indirect sig0, v5(v0,v1,v2,v3,v7,v5)",
            "jump block1()\nblock1(v6:i64):\n return_call_indirect sig0, v5(v0,v1,v2,v3,v6,v5)",
            "jump block2()\nblock1(v6:i64):\n return_call_indirect sig0, v5(v0,v1,v2,v3,v6,v5)\nblock2:\n return v0",
        ] { assert!(check(body).is_err(), "{body}"); }
    }
}

#[cfg(test)]
mod object_leaf_tests {
    use super::*;
    fn parse(text: &str) -> Function {
        cranelift_reader::parse_functions(text).unwrap().remove(0)
    }
    #[test]
    fn object_leaves_keep_exact_word_abi_without_vm_context_or_calls() {
        let valid = "function %slotHash(i64) -> i64 tail { block0(v0:i64): return v0 }";
        require_object_leaf(&parse(valid), 1).unwrap();
        assert!(require_object_leaf(&parse(valid), 2).unwrap_err().contains("word signature"));
        for invalid in [
            "function %slotHash(f64) -> i64 tail { block0(v0:f64): v1 = iconst.i64 0 return v1 }",
            "function %slotHash(i64) -> f64 tail { block0(v0:i64): v1 = f64const 0.0 return v1 }",
            "function %slotHash(i64) -> i64 system_v { block0(v0:i64): return v0 }",
        ] {
            assert!(require_object_leaf(&parse(invalid), 1).unwrap_err().contains("word signature"));
        }
        let stack = "function %slotHash(i64) -> i64 tail { ss0 = explicit_slot 8 block0(v0:i64): return v0 }";
        assert!(require_object_leaf(&parse(stack), 1).unwrap_err().contains("symbols, stack or calls"));
        let call = "function %slotHash(i64) -> i64 tail { sig0 = (i64) -> i64 fn0 = %nupp_rt_any sig0 block0(v0:i64): v1 = call fn0(v0) return v1 }";
        assert!(require_object_leaf(&parse(call), 1).unwrap_err().contains("symbols, stack or calls"));
        let indirect = "function %slotHash(i64) -> i64 tail { sig0 = (i64) -> i64 tail block0(v0:i64): try_call_indirect v0(v0), sig0, block1(ret0), [] block1(v1:i64): return v1 }";
        assert!(require_object_leaf(&parse(indirect), 1).unwrap_err().contains("cannot call or dispatch"));
        let load = "function %slotHash(i64) -> i64 tail { block0(v0:i64): v1 = load.i64 v0 return v1 }";
        assert!(require_object_leaf(&parse(load), 1).unwrap_err().contains("cannot access memory"));
    }
    #[test]
    fn string_hash_leaf_reads_bytes_without_stores_or_callees() {
        let valid = "function %stringHash(i64, i64, i64) -> i64 tail { block0(v0:i64, v1:i64, v2:i64): v3 = uload8.i64 v0 return v3 }";
        require_object_leaf(&parse(valid), 3).unwrap();
        let store = valid.replace("return v3", "istore8 v3, v0 return v3");
        assert!(require_object_leaf(&parse(&store), 3).is_err());
        let call = "function %stringHash(i64, i64, i64) -> i64 tail { sig0 = (i64) -> i64 tail fn0 = %slotHash sig0 block0(v0:i64, v1:i64, v2:i64): v3 = call fn0(v2) return v3 }";
        assert!(require_object_leaf(&parse(call), 3).is_err());
    }
    #[test]
    fn weak_lookup_leaf_accepts_scalar_state_without_memory_or_calls() {
        let valid = "function %weakLookupAction(i64,i64,i64,i64,i64,i64,i64) -> i64 tail { block0(v0:i64,v1:i64,v2:i64,v3:i64,v4:i64,v5:i64,v6:i64): return v3 }";
        require_object_leaf(&parse(valid), 7).unwrap();
        let load = valid.replace("return v3", "v7 = load.i64 v0 return v7");
        assert!(require_object_leaf(&parse(&load), 7).is_err());
        let store = valid.replace("return v3", "store v3,v0 return v3");
        assert!(require_object_leaf(&parse(&store), 7).is_err());
    }
    #[test]
    fn rehash_leaf_accepts_only_its_checked_raw_helpers() {
        let valid = "function %tableRehash(i64,i64,i64,i64,i64,i64,i64,i64) -> i64 tail { sig0 = (i64,i64,i64,i64) -> i64 tail fn0 = %tableProbe sig0 block0(v0:i64,v1:i64,v2:i64,v3:i64,v4:i64,v5:i64,v6:i64,v7:i64): v8 = call fn0(v4,v7,v3,v2) store v8,v4 return v8 }";
        require_object_leaf(&parse(valid), 8).unwrap();
        assert!(require_object_leaf(&parse(&valid.replace("%tableProbe", "%slotHash")), 8).is_err());
        assert!(require_object_leaf(&parse(&valid.replace("tail fn0", "system_v fn0")), 8).is_err());
        let readonly = "function %tableLiveCount(i64,i64,i64,i64) -> i64 tail { block0(v0:i64,v1:i64,v2:i64,v3:i64): v4 = load.i64 v0 return v4 }";
        require_object_leaf(&parse(readonly), 4).unwrap();
        assert!(require_object_leaf(&parse(&readonly.replace("return v4", "store v4,v0 return v4")), 4).is_err());
    }
    #[test]
    fn shape_leaves_use_borrowed_memory_and_only_the_exact_hash_callee() {
        let fill = "function %shapeFill(i64, i64, i64, i64) -> i64 tail { sig0 = (i64) -> i64 tail fn0 = %slotHash sig0 block0(v0:i64, v1:i64, v2:i64, v3:i64): v4 = load.i64 v0 v5 = call fn0(v4) store v5, v2 return v3 }";
        require_object_leaf(&parse(fill), 4).unwrap();
        let find = fill.replace("%shapeFill", "%shapeFind").replace(" store v5, v2", "");
        require_object_leaf(&parse(&find), 4).unwrap();
        require_object_leaf(&parse(&find.replace("%shapeFind", "%tableProbe")), 4).unwrap();
        assert!(require_object_leaf(&parse(&fill.replace("%shapeFill", "%tableProbe")), 4).is_err());
        assert!(require_object_leaf(&parse(&fill.replace("%shapeFill", "%shapeFind")), 4).is_err());
        assert!(require_object_leaf(&parse(&fill.replace("%slotHash", "%nupp_rt_new_table")), 4).is_err());
        assert!(require_object_leaf(&parse(&fill.replace("(i64) -> i64 tail", "(i64) -> i64 system_v")), 4).is_err());
        let indirect = "function %shapeFind(i64, i64, i64, i64) -> i64 tail { sig0 = (i64) -> i64 tail block0(v0:i64, v1:i64, v2:i64, v3:i64): v4 = call_indirect sig0, v0(v1) return v4 }";
        assert!(require_object_leaf(&parse(indirect), 4).is_err());
    }

}

#[cfg(test)]
mod allocator_support_tests {
    use super::*;

    fn check(text: &str, name: &str) -> Result<(), String> {
        let sources = cranelift_reader::parse_functions(text).unwrap();
        let definitions = sources
            .iter()
            .map(|f| (name_of(f), f.signature.clone()))
            .collect();
        let support = allocator_support_names(text, &definitions)?;
        let function = sources.iter().find(|f| name_of(f) == name).unwrap();
        require_allocator_support(function, &support, &definitions, CallConv::SystemV)
    }

    #[test]
    fn allocator_selection_requires_unique_local_ordinary_source_names() {
        let valid = "; Nupp allocator support: allocatorCreate\nfunction %allocatorCreate(i64) -> i64 tail { block0(v0:i64): return v0 }";
        check(valid, "allocatorCreate").unwrap();
        for invalid in [
            valid.replace(
                "allocator support: allocatorCreate",
                "allocator support: allocatorCreate,allocatorCreate",
            ),
            valid.replace(
                "allocator support: allocatorCreate",
                "allocator support: absent",
            ),
            valid.replace(
                "allocator support: allocatorCreate",
                "allocator support: allocatorCreate,",
            ),
            format!("; another comment\n{valid}"),
            format!("{valid}\n; Nupp allocator support: allocatorCreate"),
            valid.replace("allocatorCreate", "slotHash"),
        ] {
            assert!(
                check(
                    &invalid,
                    if invalid.contains("%slotHash") {
                        "slotHash"
                    } else {
                        "allocatorCreate"
                    }
                )
                .is_err(),
                "{invalid}"
            );
        }
    }

    #[test]
    fn allocator_support_preserves_scalar_widths_zero_arguments_and_nil_results() {
        let valid = "; Nupp allocator support: allocatorDestroy,ready\nfunction %ready() -> i8 tail { block0: v0=iconst.i8 1 return v0 }\nfunction %allocatorDestroy(i64) tail { sig0=() -> i8 tail fn0=%ready sig0 block0(v0:i64): v1=call fn0() return }";
        check(valid, "allocatorDestroy").unwrap();
        check(valid, "ready").unwrap();
        assert!(
            check(
                &valid.replace("sig0=() -> i8 tail", "sig0=() -> i32 tail"),
                "allocatorDestroy"
            )
            .is_err()
        );
        assert!(
            check(
                &valid
                    .replace(
                        "%allocatorDestroy(i64) tail",
                        "%allocatorDestroy(i64) -> i8 tail"
                    )
                    .replace("v1=call fn0() return", "v1=call fn0() return v1"),
                "allocatorDestroy"
            )
            .is_err()
        );
        let narrow = "; Nupp allocator support: narrow\nfunction %narrow(i32,i16,i8) -> i32 tail { block0(v0:i32,v1:i16,v2:i8): return v0 }";
        check(narrow, "narrow").unwrap();
        assert!(check(&narrow.replace("tail", "system_v"), "narrow").is_err());
    }

    #[test]
    fn allocator_calls_match_selected_local_definitions_and_known_os_signatures() {
        let local = "; Nupp allocator support: caller,helper\nfunction %helper(i64) -> i64 tail { block0(v0:i64): return v0 }\nfunction %caller(i64) -> i64 tail { sig0=(i64) -> i64 tail fn0=%helper sig0 block0(v0:i64): v1=call fn0(v0) return v1 }";
        check(local, "caller").unwrap();
        assert!(
            check(
                &local.replace("support: caller,helper", "support: caller"),
                "caller"
            )
            .is_err()
        );
        assert!(
            check(
                &local.replace("sig0=(i64) -> i64 tail", "sig0=(i64) -> i32 tail"),
                "caller"
            )
            .is_err()
        );
        for name in ["nupp_rt_alloc", "nupp_rt_any", "nupp_os_unknown"] {
            assert!(
                check(
                    &local.replace("fn0=%helper", &format!("fn0=%{name}")),
                    "caller"
                )
                .is_err()
            );
        }
        let os = "; Nupp allocator support: caller\nfunction %caller(i64) -> i64 tail { sig0=(i64) -> i64 fn0=%nupp_os_map_pages sig0 block0(v0:i64): v1=call fn0(v0) return v1 }";
        check(os, "caller").unwrap();
        assert!(
            check(
                &os.replace("sig0=(i64) -> i64", "sig0=(i32) -> i64"),
                "caller"
            )
            .is_err()
        );
        assert!(
            check(
                &os.replace("sig0=(i64) -> i64", "sig0=(i64) -> i64 tail"),
                "caller"
            )
            .is_err()
        );
        let leaf = local
            .replace("caller,helper", "caller")
            .replace("%helper", "%slotHash");
        check(&leaf, "caller").unwrap();
    }

    #[test]
    fn allocator_scratch_is_bounded_and_globals_are_refused() {
        let base = "; Nupp allocator support: caller\nfunction %caller(i64) -> i64 tail { DECL block0(v0:i64): return v0 }";
        check(
            &base.replace("DECL", "ss0=explicit_slot 4096, align=16"),
            "caller",
        )
        .unwrap();
        for declaration in [
            "ss0=explicit_slot 0",
            "ss0=explicit_slot 4097",
            "ss0=explicit_slot 16, align=32",
            "ss0=explicit_slot 4096 ss1=explicit_slot 1",
            "ss0=explicit_slot 4095, align=16 ss1=explicit_slot 1, align=16",
            "dss0=explicit_dynamic_slot dt0",
            "gv0=symbol %external",
        ] {
            assert!(
                check(&base.replace("DECL", declaration), "caller").is_err(),
                "{declaration}"
            );
        }
    }

    #[test]
    fn allocator_support_refuses_indirect_and_exception_calls() {
        let indirect = "; Nupp allocator support: caller\nfunction %caller(i64) -> i64 tail { sig0=(i64) -> i64 tail block0(v0:i64): v1=call_indirect sig0,v0(v0) return v1 }";
        assert!(check(indirect, "caller").is_err());
        let exceptional = "; Nupp allocator support: caller\nfunction %caller(i64) -> i64 tail { sig0=(i64) -> i64 tail block0(v0:i64): try_call_indirect v0(v0),sig0,block1(ret0),[] block1(v1:i64): return v1 }";
        assert!(check(exceptional, "caller").is_err());
    }

    #[test]
    fn allocator_c_wrappers_compile_actual_word_and_void_results() {
        let text = "; Nupp allocator support: allocatorCreate,allocatorDestroy,zeroArguments\nfunction %allocatorCreate(i64) -> i64 tail { block0(v0:i64): return v0 }\nfunction %allocatorDestroy(i64) tail { block0(v0:i64): return }\nfunction %zeroArguments() -> i8 tail { block0: v0=iconst.i8 1 return v0 }\nfunction %resumeSlow(i64,i64,i64) -> i64 tail { block0(v0:i64,v1:i64,v2:i64): return v0 }";
        let directory =
            std::env::temp_dir().join(format!("nupp-allocator-wrappers-{}", std::process::id()));
        std::fs::create_dir_all(&directory).unwrap();
        let input = directory.join("source.clif");
        let output = directory.join("allocator.o");
        std::fs::write(&input, text).unwrap();
        write_object(input.to_str().unwrap(), output.to_str().unwrap()).unwrap();
        let object = std::fs::read(&output).unwrap();
        for name in [
            b"nupp_allocator_create".as_slice(),
            b"nupp_allocator_destroy".as_slice(),
        ] {
            assert!(object.windows(name.len()).any(|part| part == name));
        }
        std::fs::remove_dir_all(directory).unwrap();
    }
}
