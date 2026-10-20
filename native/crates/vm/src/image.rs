//! Loader for the emitter's text image: shapes, functions with constants and
//! opcodes named after the runtime's `Op` variants, and the entry.

use crate::heap::SlotTy;
use crate::interp::{Function, Interp, Op};
use crate::value::Value;

pub fn load(it: &mut Interp, text: &str) -> Result<u32, String> { load_with(it, text, false) }

/// Loads an image and also returns the heap shape ids its `shape` lines
/// resolved to, in line order: what a graph image of the same functions
/// names by index.
pub fn load_with_shapes(it: &mut Interp, text: &str) -> Result<(u32, Vec<u32>), String> {
    let scope = it.open_scope();
    let r = parse(it, text, None).map(|parsed| { let shapes = parsed.shape_ids.clone(); (install(it, parsed), shapes) });
    it.close_scope(scope);
    if r.is_ok() { it.code_events.push(crate::persist::CodeEvent::Image(text.to_owned())); }
    r
}

/// Loads a dynamic image only when this host can execute its instructions.
pub fn load_plugin(it: &mut Interp, text: &str) -> Result<u32, String> {
    load_with(it, text, !it.simd_interpret)
}

fn load_with(it: &mut Interp, text: &str, refuse_native: bool) -> Result<u32, String> {
    let scope = it.open_scope();
    let r = parse(it, text, None).and_then(|parsed| {
        if refuse_native {
            if let Some(f) = parsed.funcs.iter().find(|f| needs_native(f)) {
                return Err(uncompiled_native_message("image refused", &f.name, &f.module));
            }
        }
        Ok(install(it, parsed))
    });
    it.close_scope(scope);
    if r.is_ok() { it.code_events.push(crate::persist::CodeEvent::Image(text.to_owned())); }
    r
}

/// Whether a function holds instructions requiring native execution.
pub fn needs_native(f: &Function) -> bool { f.code.iter().any(crate::native_simd::required) }

pub fn uncompiled_native_message(what: &str, function: &str, module: &str) -> String {
    let module = if module.is_empty() { String::new() } else { format!(" in module {module}") };
    format!("{what}: function {function}{module} has vector instructions, which require native compilation, and this runtime has no code generator and no compiled implementation linked for it (SIMD_INTERPRET=1 runs it interpreted)")
}

/// An image read and verified but not yet part of the VM: its functions refer
/// to each other as `base + index`, where `base` is where they would land.
pub(crate) struct Parsed {
    pub base: u32,
    pub entry: u32,
    pub funcs: Vec<Function>,
    pub shape_ids: Vec<u32>,
    pending_methods: Vec<(u32, String, u32)>,
    /// Each `module` line: name, the index of its chunk, and its source path.
    pub modules: Vec<(String, u32, Option<String>)>,
}

/// Publishes a parsed image: modules, functions, and shape methods.
fn install(it: &mut Interp, parsed: Parsed) -> u32 {
    let Parsed { base, entry, funcs, shape_ids, pending_methods, modules } = parsed;
    for (name, chunk, path) in &modules {
        it.modules.insert(name.clone(), base + chunk);
        if let Some(p) = path { it.module_paths.insert(name.clone(), p.clone()); }
    }
    crate::hotpatch::record(it, base, &funcs, &shape_ids, &modules);
    for f in funcs { it.frame_required |= f.code.iter().any(|op| matches!(op, Op::Defer(..) | Op::DeferMethod(..) | Op::AffineEnter) || crate::native_simd::required(op)); it.funcs.push(f); }
    for (shape, name, fid) in pending_methods { let n = it.intern(&name); it.heap.shapes[shape_ids[shape as usize] as usize].methods.insert(n, Value::func(base + fid)); }
    // A method an image installs may replace one compiled code resolved.
    it.heap.proto_epoch += 1;
    entry
}

/// Reads an image without changing the VM's code. Interned constants are on
/// the caller's handle scope. `patch` holds the shapes the running module was
/// loaded with: a patch may name only those layouts, and never adds a shape.
pub(crate) fn parse(it: &mut Interp, text: &str, patch: Option<&[u32]>) -> Result<Parsed, String> {
    let mut entry = 0u32;
    let mut shape_ids: Vec<u32> = Vec::new();
    let mut pending_methods: Vec<(u32, String, u32)> = Vec::new();
    let mut funcs: Vec<Function> = Vec::new();
    let mut modules: Vec<(String, u32, Option<String>)> = Vec::new();
    let base = it.funcs.len() as u32;
    let mut cur: Option<Function> = None;
    let mut parts: Vec<&str> = Vec::new();
    // The opcode table the image was emitted against, when it carries one.
    let mut opcodes: Vec<crate::opcodes::Opcode> = Vec::new();
    for (ln, raw) in text.lines().enumerate() {
        let line = raw.trim();
        if line.is_empty() { continue; }
        split(line, &mut parts);
        match parts[0] {
            "opcode" if cur.is_none() => { opcodes.push(crate::opcodes::parse_row(&parts[1..]).map_err(|e| format!("line {ln}: {e}"))?); }
            "shape" => {
                let mut names = Vec::new(); let mut types = Vec::new(); let mut identity = None;
                for p in &parts[3..] {
                    if let Some(key) = p.strip_prefix("identity=") { identity = Some(key.to_string()); continue; }
                    if let Some((n, f)) = p.strip_prefix("method:").and_then(|m| m.split_once('=')) { pending_methods.push((shape_ids.len() as u32, n.to_string(), f.parse().unwrap())); continue; }
                    let (n, t) = p.split_once(':').ok_or_else(|| format!("line {ln}: slot"))?;
                    let nv = it.intern(n); it.handles.push(nv); names.push(nv);
                    types.push(match t { "num" => SlotTy::Num, "str" => SlotTy::Str, "bool" => SlotTy::Bool, t if t.starts_with("rec:") => match shape_ids.get(t[4..].parse::<usize>().map_err(|_| format!("line {ln}: record slot"))?) { Some(&id) => SlotTy::Record(id), None => SlotTy::Any }, _ => SlotTy::Any });
                }
                let existing = identity.as_ref().and_then(|key| it.heap.shape_identities.get(key).copied()).filter(|&id| {
                    // Slot types are hints two images can infer differently;
                    // the layout is the names, in order.
                    it.heap.shapes[id as usize].names == names
                });
                if let Some(old) = patch {
                    // A patch runs against records the running code already
                    // made: a layout it names must be one of theirs.
                    let same = |id: u32| it.heap.shapes[id as usize].names == names && it.heap.shapes[id as usize].name == parts[2];
                    let id = existing.or_else(|| old.get(shape_ids.len()).copied().filter(|&id| same(id)))
                        .ok_or_else(|| format!("record layout changed or added: {}", parts[2]))?;
                    shape_ids.push(id);
                    continue;
                }
                let id = existing.unwrap_or_else(|| it.heap.shape(parts[2], &names, &types));
                if let (None, Some(key)) = (existing, identity) { it.heap.shape_identities.insert(key, id); }
                shape_ids.push(id);
            }
            "function" => {
                let name = parts[1].to_string();
                let nf: u8 = parts.get(5).and_then(|s| s.parse().ok()).unwrap_or(1);
                let (sig, ret) = parts.get(6).and_then(|s| s.split_once(':')).map(|(a, b)| (a.bytes().collect::<Vec<u8>>(), b.as_bytes()[0])).unwrap_or((Vec::new(), b'v'));
                let nfp = sig.iter().filter(|&&c| c == b'f').count() as u8;
                let nvp = sig.len() as u8 - nfp;
                cur = Some(Function { name, module: String::new(), path: None, code: Vec::new(), consts: Vec::new(), nparams: parts[3].parse().unwrap(), nregs: parts[4].parse().unwrap(), nireg: nf, nfreg: nf, nvreg: 2, sig, ret, nv_params: nvp, nf_params: nfp, jump_tables: Vec::new(), debug: Vec::new(), vararg: parts.get(7) == Some(&"vararg"), gpu: None, ins: Vec::new() });
            }
            "vectors" => { if parts.len()!=2 { return Err(format!("line {ln}: vector count")); } cur.as_mut().ok_or("vectors outside function")?.nvreg = parts.get(1).ok_or("missing vector count")?.parse().map_err(|_| "invalid vector count")?; }
            "lines" => {
                let f = cur.as_mut().ok_or("lines outside function")?;
                for run in &parts[1..] {
                    let (line, count) = run.split_once('x').unwrap_or((run, "1"));
                    let line: u32 = line.parse().map_err(|_| format!("line {ln}: invalid source line"))?;
                    let count: usize = count.parse().map_err(|_| format!("line {ln}: invalid line run"))?;
                    f.debug.extend(std::iter::repeat_n((line, 0), count));
                }
            }
            "const" => {
                let f = cur.as_mut().unwrap();
                let v = match parts[2] {
                    "num" => Value::num(parts[3].parse().unwrap()),
                    "int64" | "uint64" => {
                        let unsigned = parts[2] == "uint64";
                        let text = parts[3];
                        let negative = text.starts_with('-');
                        let text = text.strip_prefix('-').unwrap_or(text);
                        let bits = if let Some(hex) = text.strip_prefix("0x").or_else(|| text.strip_prefix("0X")) { u64::from_str_radix(hex, 16) } else { text.parse::<u64>() }.map_err(|_| format!("line {ln}: invalid wide integer"))?;
                        if negative && unsigned || negative && bits > (1u64 << 63) { return Err(format!("line {ln}: wide integer out of range")); }
                        let v = it.box_integer(crate::numeric::Integer { bits: if negative { bits.wrapping_neg() } else { bits }, unsigned });
                        it.handles.push(v); v
                    }
                    "str" => { let s = unquote(&line[line.find('"').unwrap()..]); let v = it.string_of(&s); it.handles.push(v); v }
                    "nil" => Value::NIL,
                    "builtin" => Value::builtin(crate::builtins::id_of(parts[3]).ok_or_else(|| format!("line {ln}: unknown builtin {}", parts[3]))?),
                    "true" => Value::TRUE,
                    "false" => Value::FALSE,
                    "func" => Value::func(base + parts[3].parse::<u32>().unwrap()),
                    k => return Err(format!("line {ln}: constant kind {k}")),
                };
                f.consts.push(v);
            }
            "end" => {
                let mut f = cur.take().unwrap();
                if !f.debug.is_empty() && f.debug.len() != f.code.len() { return Err(format!("line {ln}: line table covers {} of {} instructions", f.debug.len(), f.code.len())); }
                // Named operations use identity keys in every execution tier.
                // Long string literals are otherwise deliberately not interned.
                for op in &f.code {
                    let key = match *op {
                        Op::GetField(_, _, k) | Op::SetField(_, k, _) | Op::CallMethod(k, _, _)
                        | Op::SetMethod(_, k, _) | Op::DeferMethod(_, k) => k as usize,
                        _ => continue,
                    };
                    let value = *f.consts.get(key).ok_or_else(|| format!("line {ln}: field constant outside pool"))?;
                    if !it.is_stringish(value) { return Err(format!("line {ln}: field name must be a string")); }
                    let name = it.key_for_store(value);
                    it.handles.push(name);
                    f.consts[key] = name;
                }
                for op in &f.code {
                    let p=match *op { Op::GetPhys(_,_,p)|Op::GetPhysF(_,_,p)|Op::GetPhysI(_,_,p)|Op::GetPhysU(_,_,p)|Op::SetPhys(_,p,_)|Op::SetPhysF(_,p,_)|Op::SetPhysI(_,p,_)=>p,_=>continue };
                    for key in [p.identity,p.name] {
                        let v=*f.consts.get(key as usize).ok_or_else(||format!("line {ln}: physical constant outside pool"))?;
                        if !it.is_stringish(v) { return Err(format!("line {ln}: physical identity/name must be strings")); }
                        let v=it.key_for_store(v); it.handles.push(v); f.consts[key as usize]=v;
                    }
                }
                funcs.push(f);
            }
            "entry" => { entry = base + parts[1].parse::<u32>().unwrap(); }
            "table" => {
                let f = cur.as_mut().ok_or_else(|| format!("line {ln}: table outside a function"))?;
                let def: i32 = parts[2].parse().map_err(|_| format!("line {ln}: table default"))?;
                let offs: Vec<i32> = parts[3..].iter().map(|s| s.parse().unwrap()).collect();
                f.jump_tables.push((def, offs));
            }
            "module" => {
                let chunk = parts.get(2).and_then(|s| s.parse::<u32>().ok()).ok_or_else(|| format!("line {ln}: module chunk"))?;
                if let Some(p) = parts.get(3) {
                    let path: std::sync::Arc<str> = (*p).into();
                    for f in funcs.iter_mut().filter(|f| f.module == parts[1]) { f.path = Some(path.clone()); }
                }
                modules.push((parts[1].to_string(), chunk, parts.get(3).map(|p| p.to_string())));
            }
            "source" => { let f = cur.as_mut().ok_or_else(|| format!("line {ln}: source outside a function"))?; f.module = parts[1].to_string(); }
            // gpu ENTRY THREADS UNIFORM_BYTES COUNT_SPAN READONLY WRITABLE UNIFORMS "WGSL" "SPIRV":
            // the name lists are comma-separated, `-` when empty; both shaders are quoted.
            "gpu" => {
                let f = cur.as_mut().ok_or_else(|| format!("line {ln}: gpu outside a function"))?;
                if parts.len() != 10 || !parts[8].starts_with('"') || !parts[9].starts_with('"') { return Err(format!("line {ln}: gpu line shape")); }
                let names = |s: &str| if s == "-" { Vec::new() } else { s.split(',').map(str::to_string).collect::<Vec<_>>() };
                let number = |s: &str| s.parse::<u32>().map_err(|_| format!("line {ln}: gpu number"));
                f.gpu = Some(Box::new(crate::interp::GpuArtifact {
                    entrypoint: parts[1].to_string(),
                    threads: number(parts[2])?,
                    uniform_bytes: number(parts[3])?,
                    count_span: parts[4].to_string(),
                    readonly: names(parts[5]),
                    writable: names(parts[6]),
                    uniforms: names(parts[7]),
                    wgsl: String::from_utf8(unquote(parts[8])).map_err(|_| format!("line {ln}: gpu wgsl"))?,
                    spirv: unquote(parts[9]),
                }));
            }
            // The declaration of a module a native extension provides.
            "extension" if cur.is_none() => {
                if parts.len() != 3 || !parts[2].starts_with('"') { return Err(format!("line {ln}: extension NAME \"DECLARATION\"")); }
                crate::extension::declare(it, parts[1], &unquote(parts[2])).map_err(|e| format!("line {ln}: {e}"))?;
            }
            name => {
                let f = cur.as_mut().ok_or_else(|| format!("line {ln}: op outside a function"))?;
                let a = |i: usize| -> i64 { parts.get(i).and_then(|s| s.parse().ok()).unwrap_or(0) };
                let strict = match name {
                    "SpanLen" | "VSplatN" | "ICmpEq" | "ICmpNe" | "ICmpLt" | "ICmpLe" => Some(3),
                    "SpanBounds" | "VPrefix" => Some(5),
                    "SpanLoad" | "SpanStore" => Some(7),
                    "VOp" => Some(6), "VExtractN" => Some(4),
                    "IMaskU32" | "VAny" | "VMov" => Some(2), "Raise" => Some(1), _ => None,
                };
                if let Some(count) = strict {
                    if parts.len()!=count+1 { return Err(format!("line {ln}: {name} operand count")); }
                    for (i,text) in parts.iter().enumerate().skip(if name=="VOp" {2} else {1}) {
                        let value = text.parse::<u16>().map_err(|_|format!("line {ln}: invalid {name} operand"))?;
                        let max = if name=="Raise" {u16::MAX} else if name=="SpanBounds" && i==5 {1} else {u8::MAX as u16};
                        if value>max { return Err(format!("line {ln}: {name} operand out of range")); }
                    }
                }
                if name.starts_with("GetPhys") || name.starts_with("SetPhys") {
                    if parts.len()!=8 { return Err(format!("line {ln}: physical field operand count")); }
                    let store=name.starts_with("Set");
                    for i in 1..8 {
                        let max=if (!store && i<=2) || (store && (i==1 || i==7)) {255u64}
                            else if i==if store {5}else{6} {u32::MAX as u64}
                            else if i==if store {6}else{7} {10} else {65535};
                        let v=parts[i].parse::<u64>().map_err(|_|format!("line {ln}: invalid physical operand"))?;
                        if v>max { return Err(format!("line {ln}: physical operand out of range")); }
                    }
                }
                let physical=|start:usize|crate::storage::PhysicalField { identity:a(start) as u16,name:a(start+1) as u16,ordinal:a(start+2) as u16,offset:a(start+3) as u32,kind:a(start+4) as u8 };
                let op = match name {
                    "GetPhys"=>Op::GetPhys(a(1) as u8,a(2) as u8,physical(3)),
                    "GetPhysF"=>Op::GetPhysF(a(1) as u8,a(2) as u8,physical(3)),
                    "GetPhysI"=>Op::GetPhysI(a(1) as u8,a(2) as u8,physical(3)),
                    "GetPhysU"=>Op::GetPhysU(a(1) as u8,a(2) as u8,physical(3)),
                    "SetPhys"=>Op::SetPhys(a(1) as u8,physical(2),a(7) as u8),
                    "SetPhysF"=>Op::SetPhysF(a(1) as u8,physical(2),a(7) as u8),
                    "SetPhysI"=>Op::SetPhysI(a(1) as u8,physical(2),a(7) as u8),
                    "DeferMethod" => Op::DeferMethod(a(1) as u8, a(2) as u16), "Defer" => Op::Defer(a(1) as u8, a(2) as u8), "CleanupLive" => Op::CleanupLive(a(1) as u8, a(2) as u16),
                "AffineMark" => Op::AffineMark(a(1) as u8, a(2) as u8),
                "AffineEnter" => Op::AffineEnter,
                "DisarmAt" => Op::DisarmAt(a(1) as u16), "RearmAt" => Op::RearmAt(a(1) as u16, a(2) as u8, a(3) as u8), "Disarm" => Op::Disarm(a(1) as u8), "Unwind" => Op::Unwind(a(1) as u16),
                    "Park" => Op::Park(a(1) as u8), "Checkpoint" => Op::Checkpoint,
                    "Simd" => {
                        if parts.len() != 5 && parts.len() != 6 { return Err(format!("line {ln}: SIMD operand count")); }
                        let op = crate::simd::operation(parts[1]).ok_or_else(|| format!("line {ln}: unknown SIMD operation"))?;
                        let kind = crate::simd::ELEMENTS.iter().position(|k| *k == parts[2]).ok_or_else(|| format!("line {ln}: unknown SIMD element"))? as u8;
                        let base = parts[3].parse::<u8>().map_err(|_| format!("line {ln}: SIMD register"))?;
                        let nargs = parts[4].parse::<u8>().map_err(|_| format!("line {ln}: SIMD arity"))?;
                        let source = if parts.len() == 6 { crate::simd::ELEMENTS.iter().position(|k| *k == parts[5]).ok_or_else(|| format!("line {ln}: unknown SIMD source element"))? as u8 } else { kind };
                        Op::Simd(op, kind, source, base, nargs)
                    },
                    "SpanLen" => Op::SpanLen(a(1) as u8, a(2) as u8, a(3) as u8),
                    "SpanBounds" => Op::SpanBounds(a(1) as u8, a(2) as u8, a(3) as u8, a(4) as u8, a(5) != 0),
                    "SpanLoad" => Op::SpanLoad(a(1) as u8, a(2) as u8, a(3) as u8, a(4) as u8, a(5) as u8, a(6) as u8, a(7) as u8),
                    "SpanStore" => Op::SpanStore(a(1) as u8, a(2) as u8, a(3) as u8, a(4) as u8, a(5) as u8, a(6) as u8, a(7) as u8),
                    "VOp" => Op::VOp(crate::simd::operation(parts[1]).ok_or("unknown vector operation")?, a(2) as u8, a(3) as u8, a(4) as u8, a(5) as u8, a(6) as u8),
                    "VSplatN" => Op::VSplatN(a(1) as u8, a(2) as u8, a(3) as u8),
                    "VExtractN" => Op::VExtractN(a(1) as u8, a(2) as u8, a(3) as u8, a(4) as u8),
                    "IMaskU32" => Op::IMaskU32(a(1) as u8, a(2) as u8),
                    "ICmpEq" => Op::ICmpEq(a(1) as u8, a(2) as u8, a(3) as u8),
                    "ICmpNe" => Op::ICmpNe(a(1) as u8, a(2) as u8, a(3) as u8),
                    "ICmpLt" => Op::ICmpLt(a(1) as u8, a(2) as u8, a(3) as u8),
                    "ICmpLe" => Op::ICmpLe(a(1) as u8, a(2) as u8, a(3) as u8),
                    "VPrefix" => Op::VPrefix(a(1) as u8, a(2) as u8, a(3) as u8, a(4) as u8, a(5) as u8),
                    "VAny" => Op::VAny(a(1) as u8, a(2) as u8),
                    "Raise" => Op::Raise(a(1) as u16),
                    "VMov" => Op::VMov(a(1) as u8, a(2) as u8),
                    "K" => Op::K(a(1) as u8, a(2) as u16), "Move" => Op::Move(a(1) as u8, a(2) as u8), "Nil" => Op::Nil(a(1) as u8),
                    "Add" => Op::Add(a(1) as u8, a(2) as u8, a(3) as u8), "Sub" => Op::Sub(a(1) as u8, a(2) as u8, a(3) as u8), "Mul" => Op::Mul(a(1) as u8, a(2) as u8, a(3) as u8),
                    "Lt" => Op::Lt(a(1) as u8, a(2) as u8, a(3) as u8), "Le" => Op::Le(a(1) as u8, a(2) as u8, a(3) as u8), "Eq" => Op::Eq(a(1) as u8, a(2) as u8, a(3) as u8), "Ne" => Op::Ne(a(1) as u8, a(2) as u8, a(3) as u8),
                    "Concat" => Op::Concat(a(1) as u8, a(2) as u8, a(3) as u8), "Not" => Op::Not(a(1) as u8, a(2) as u8), "Neg" => Op::Neg(a(1) as u8, a(2) as u8), "Len" => Op::Len(a(1) as u8, a(2) as u8),
                    "Jmp" => Op::Jmp(a(1) as i32), "JmpIf" => Op::JmpIf(a(1) as u8, a(2) as i32), "JmpIfNot" => Op::JmpIfNot(a(1) as u8, a(2) as i32),
                    "Call" => Op::Call(base + a(1) as u32, a(2) as u8, a(3) as u8), "CallT" => Op::CallT(base + a(1) as u32, a(2) as u8, a(3) as u8, a(4) as u8), "StrByte" => Op::StrByte(a(1) as u8, a(2) as u8, a(3) as u8), "Pow" => Op::Pow(a(1) as u8, a(2) as u8, a(3) as u8), "IDiv" => Op::IDiv(a(1) as u8, a(2) as u8, a(3) as u8), "IXor" => Op::IXor(a(1) as u8, a(2) as u8, a(3) as u8), "INot" => Op::INot(a(1) as u8, a(2) as u8), "CallK" => Op::CallK((base + a(1) as u32) as u16, a(2) as u8, a(3) as u8, a(4) as u8, a(5) as u8), "CallDyn" => Op::CallDyn(a(1) as u8, a(2) as u8, a(3) as u8), "CallMethod" => Op::CallMethod(a(1) as u16, a(2) as u8, a(3) as u8), "PCall" => Op::PCall(a(1) as u8, a(2) as u8),
                    "Ret" => Op::Ret(a(1) as u8), "RetNil" => Op::RetNil,
                    "NewTable" => Op::NewTable(a(1) as u8), "GetIdx" => Op::GetIdx(a(1) as u8, a(2) as u8, a(3) as u8), "SetIdx" => Op::SetIdx(a(1) as u8, a(2) as u8, a(3) as u8),
                    "GetField" => Op::GetField(a(1) as u8, a(2) as u8, a(3) as u16), "SetField" => Op::SetField(a(1) as u8, a(2) as u16, a(3) as u8),
                    "NewRecord" => Op::NewRecord(a(1) as u8, shape_ids[a(2) as usize]), "GetSlot" => Op::GetSlot(a(1) as u8, a(2) as u8, a(3) as u16, shape_ids[a(4) as usize]), "SetSlot" => Op::SetSlot(a(1) as u8, a(2) as u16, a(3) as u8, shape_ids[a(4) as usize]),
                    "TagCheckRec" => Op::TagCheckRec(a(1) as u8, a(2) as u8, shape_ids[a(3) as usize]), "TagCheckNum" => Op::TagCheckNum(a(1) as u8, a(2) as u8), "VarargN" => Op::VarargN(a(1) as u8, a(2) as u8), "PadResults" => Op::PadResults(a(1) as u8, a(2) as u8), "Scalar" => Op::Scalar(a(1) as u8, a(2) as u8, a(3) as u8, a(4) as u8), "IAnd" => Op::IAnd(a(1) as u8, a(2) as u8, a(3) as u8), "IOr" => Op::IOr(a(1) as u8, a(2) as u8, a(3) as u8), "IShl" => Op::IShl(a(1) as u8, a(2) as u8, a(3) as u8), "IShrU" => Op::IShrU(a(1) as u8, a(2) as u8, a(3) as u8), "IsRec" => Op::IsRec(a(1) as u8, a(2) as u8, shape_ids[a(3) as usize]), "VarargTable" => Op::VarargTable(a(1) as u8), "TagCheckStr" => Op::TagCheckStr(a(1) as u8, a(2) as u8),
                    "TagCheckInt" => { let kind = a(3); if kind != 0 && kind != 1 { return Err(format!("line {ln}: invalid integer kind")); } Op::TagCheckInt(a(1) as u8, a(2) as u8, kind != 0) },
                    "IBox" => Op::IBox(a(1) as u8, a(2) as u8),
                    "UBox" => Op::UBox(a(1) as u8, a(2) as u8),
                    "UUnbox" => Op::UUnbox(a(1) as u8, a(2) as u8),
                    "FK" => Op::FK(a(1) as u8, parts[2].parse().unwrap()), "FMov" => Op::FMov(a(1) as u8, a(2) as u8), "FUnbox" => Op::FUnbox(a(1) as u8, a(2) as u8), "FBox" => Op::FBox(a(1) as u8, a(2) as u8),
                    "FAdd" => Op::FAdd(a(1) as u8, a(2) as u8, a(3) as u8), "FSub" => Op::FSub(a(1) as u8, a(2) as u8, a(3) as u8), "FMul" => Op::FMul(a(1) as u8, a(2) as u8, a(3) as u8), "FDiv" => Op::FDiv(a(1) as u8, a(2) as u8, a(3) as u8), "FNeg" => Op::FNeg(a(1) as u8, a(2) as u8),
                    "FCmpLt" => Op::FCmpLt(a(1) as u8, a(2) as u8, a(3) as u8), "FCmpLe" => Op::FCmpLe(a(1) as u8, a(2) as u8, a(3) as u8), "FCmpEq" => Op::FCmpEq(a(1) as u8, a(2) as u8, a(3) as u8), "FCmpNe" => Op::FCmpNe(a(1) as u8, a(2) as u8, a(3) as u8),
                    "JmpIfIZero" => Op::JmpIfIZero(a(1) as u8, a(2) as i32), "FToI" => Op::FToI(a(1) as u8, a(2) as u8), "IK" => Op::IK(a(1) as u8, a(2)), "IAdd" => Op::IAdd(a(1) as u8, a(2) as u8, a(3) as u8), "ISub" => Op::ISub(a(1) as u8, a(2) as u8, a(3) as u8), "IAddK" => Op::IAddK(a(1) as u8, a(2) as u8, a(3)), "IMov" => Op::IMov(a(1) as u8, a(2) as u8), "IToF" => Op::IToF(a(1) as u8, a(2) as u8), "IUnbox" => Op::IUnbox(a(1) as u8, a(2) as u8), "ICmpSLt" => Op::ICmpSLt(a(1) as u8, a(2) as u8, a(3) as u8), "ICmpSLe" => Op::ICmpSLe(a(1) as u8, a(2) as u8, a(3) as u8), "GetIdxI" => Op::GetIdxI(a(1) as u8, a(2) as u8, a(3) as u8), "SetIdxI" => Op::SetIdxI(a(1) as u8, a(2) as u8, a(3) as u8), "Switch" => Op::Switch(a(1) as u8, a(2) as u16), "Mod" => Op::Mod(a(1) as u8, a(2) as u8, a(3) as u8), "Div" => Op::Div(a(1) as u8, a(2) as u8, a(3) as u8), "FMod" => Op::FMod(a(1) as u8, a(2) as u8, a(3) as u8), "RetN" => Op::RetN(a(1) as u8, a(2) as u8), "Require" => Op::Require(a(1) as u8, a(2) as u16), "RequireV" => Op::RequireV(a(1) as u8, a(2) as u8), "NewTableN" => Op::NewTableN(a(1) as u8, a(2) as u8, a(3) as u8), "SetMethod" => Op::SetMethod(shape_ids[a(1) as usize], a(2) as u16, a(3) as u8), "BoolFromI" => Op::BoolFromI(a(1) as u8, a(2) as u8), "FRet" => Op::FRet(a(1) as u8),
                    "GetSlotF" => Op::GetSlotF(a(1) as u8, a(2) as u8, a(3) as u16, shape_ids[a(4) as usize]), "SetSlotF" => Op::SetSlotF(a(1) as u8, a(2) as u16, a(3) as u8, shape_ids[a(4) as usize]), "LenF" => Op::LenF(a(1) as u8, a(2) as u8), "GetIdxF" => Op::GetIdxF(a(1) as u8, a(2) as u8, a(3) as u8), "SetIdxF" => Op::SetIdxF(a(1) as u8, a(2) as u8, a(3) as u8),
                    "NewClosure" => Op::NewClosure(a(1) as u8, base + a(2) as u32, a(3) as u8, a(4) as u8), "NewCell" => Op::NewCell(a(1) as u8, a(2) as u8), "GetCell" => Op::GetCell(a(1) as u8, a(2) as u8), "SetCell" => Op::SetCell(a(1) as u8, a(2) as u8), "GetUpval" => Op::GetUpval(a(1) as u8, a(2) as u8),
                    other => return Err(format!("line {ln}: unknown opcode {other}")),
                };
                f.code.push(op);
            }
        }
    }
    if !opcodes.is_empty() { crate::opcodes::install(opcodes)?; }
    // A patch is verified once its function references name their targets.
    if patch.is_none() {
        let total = it.funcs.len() + funcs.len();
        for (i, f) in funcs.iter().enumerate() { crate::verify::verify_classes(f, total).map_err(|e| format!("function {} ({}): {e}", f.name, base as usize + i))?; }
    }
    Ok(Parsed { base, entry, funcs, shape_ids, pending_methods, modules })
}

fn split<'a>(line: &'a str, out: &mut Vec<&'a str>) {
    // Whitespace split that keeps a quoted string as one token.
    out.clear();
    let mut rest = line;
    while !rest.is_empty() {
        rest = rest.trim_start();
        if rest.starts_with('"') { let end = rest[1..].find('"').map(|i| i + 2).unwrap_or(rest.len()); out.push(&rest[..end]); rest = &rest[end..]; }
        else { let end = rest.find(char::is_whitespace).unwrap_or(rest.len()); out.push(&rest[..end]); rest = &rest[end..]; }
    }
}

/// The bytes of a quoted constant: `\ddd` escapes decode to single bytes.
fn unquote(s: &str) -> Vec<u8> {
    let inner = &s[1..s.rfind('"').unwrap()];
    let mut out = Vec::new();
    let b = inner.as_bytes();
    let mut i = 0;
    while i < b.len() { if b[i] == b'\\' && i + 3 < b.len() + 1 { let code: u8 = std::str::from_utf8(&b[i + 1..i + 4]).unwrap().parse().unwrap(); out.push(code); i += 4; } else { out.push(b[i]); i += 1; } }
    out
}

#[cfg(test)]
mod gpu_line_tests {
    #[test]
    fn a_gpu_line_lands_on_its_function() {
        let mut vm = crate::interp::Interp::new();
        let image = "function module:m 0 0 3 1 :v\nsource m\nconst 0 func 1\nK 1 0\nRet 1\nend\nfunction kernel 2 2 3 1 vv:v\nsource m\ngpu kernel_gpu 256 24 input - output - \"fn k() {}\" \"\\003\\002\\035\\007\\000\"\nRetNil\nend\nmodule m 0\nentry 0\n";
        super::load(&mut vm, image).unwrap();
        let gpu = vm.funcs[1].gpu.as_ref().expect("the kernel carries its artifacts");
        assert_eq!(gpu.entrypoint, "kernel_gpu");
        assert_eq!((gpu.threads, gpu.uniform_bytes), (256, 24));
        assert_eq!(gpu.count_span, "input");
        assert_eq!(gpu.readonly, Vec::<String>::new());
        assert_eq!(gpu.writable, vec!["output".to_string()]);
        assert_eq!(gpu.wgsl, "fn k() {}");
        assert_eq!(gpu.spirv, vec![3, 2, 35, 7, 0]);
        assert!(vm.funcs[0].gpu.is_none());
    }
}

#[cfg(test)]
mod token_buffer_tests {
    use super::split;

    #[test]
    fn quoted_unicode_tokens_preserve_boundaries() {
        let mut tokens = Vec::new();
        for (source, expected) in [
            (
                "const 0 str \"a b\\034c\\034 é\"",
                vec!["const", "0", "str", "\"a b\\034c\\034 é\""],
            ),
            (
                "source\u{00a0}module\u{2003}next",
                vec!["source", "module", "next"],
            ),
            (
                "const 0 str \"inside\u{2003}space\"",
                vec!["const", "0", "str", "\"inside\u{2003}space\""],
            ),
            ("\"unterminated value", vec!["\"unterminated value"]),
            ("", vec![]),
        ] {
            split(source, &mut tokens);
            assert_eq!(tokens, expected);
        }
    }

    #[test]
    fn a_shorter_line_reuses_capacity_without_stale_tokens() {
        let long = (0..2404)
            .map(|n| format!("field{n}"))
            .collect::<Vec<_>>()
            .join(" ");
        let mut tokens = Vec::new();
        split(&long, &mut tokens);
        assert_eq!(tokens.len(), 2404);
        assert_eq!(tokens[2403], "field2403");
        let capacity = tokens.capacity();
        let pointer = tokens.as_ptr();
        split("entry 0", &mut tokens);
        assert_eq!(tokens, ["entry", "0"]);
        assert_eq!(tokens.capacity(), capacity);
        assert_eq!(tokens.as_ptr(), pointer);
    }
}
