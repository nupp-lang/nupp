//! Loader for the emitter's text image: shapes, functions with constants and
//! opcodes named after the runtime's `Op` variants, and the entry.

use crate::heap::SlotTy;
use crate::interp::{Function, Interp, Op};
use crate::value::Value;

pub fn load(it: &mut Interp, text: &str) -> Result<u32, String> {
    // Everything interned while loading is rooted by a handle scope until the
    // functions and shapes that hold it are registered (4.7).
    let scope = it.open_scope();
    let r = load_in(it, text);
    it.close_scope(scope);
    if r.is_ok() { it.code_events.push(crate::persist::CodeEvent::Image(text.to_owned())); }
    r
}
fn load_in(it: &mut Interp, text: &str) -> Result<u32, String> {
    let mut entry = 0u32;
    let mut shape_ids: Vec<u32> = Vec::new();
    let mut pending_methods: Vec<(u32, String, u32)> = Vec::new();
    let mut funcs: Vec<Function> = Vec::new();
    let base = it.funcs.len() as u32;
    let mut cur: Option<Function> = None;
    for (ln, raw) in text.lines().enumerate() {
        let line = raw.trim();
        if line.is_empty() { continue; }
        let parts: Vec<&str> = split(line);
        match parts[0] {
            "shape" => {
                let mut names = Vec::new(); let mut types = Vec::new(); let mut identity = None;
                for p in &parts[3..] {
                    if let Some(key) = p.strip_prefix("identity=") { identity = Some(key.to_string()); continue; }
                    if let Some((n, f)) = p.strip_prefix("method:").and_then(|m| m.split_once('=')) { pending_methods.push((shape_ids.len() as u32, n.to_string(), f.parse().unwrap())); continue; }
                    let (n, t) = p.split_once(':').ok_or(format!("line {ln}: slot"))?;
                    let nv = it.intern(n); it.handles.push(nv); names.push(nv);
                    types.push(match t { "num" => SlotTy::Num, "str" => SlotTy::Str, "bool" => SlotTy::Bool, t if t.starts_with("rec:") => match shape_ids.get(t[4..].parse::<usize>().map_err(|_| format!("line {ln}: record slot"))?) { Some(&id) => SlotTy::Record(id), None => SlotTy::Any }, _ => SlotTy::Any });
                }
                let existing = identity.as_ref().and_then(|key| it.heap.shape_identities.get(key).copied()).filter(|&id| {
                    // Slot types are hints two images can infer differently;
                    // the layout is the names, in order.
                    it.heap.shapes[id as usize].names == names
                });
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
                cur = Some(Function { name, module: String::new(), path: None, code: Vec::new(), consts: Vec::new(), nparams: parts[3].parse().unwrap(), nregs: parts[4].parse().unwrap(), nireg: nf, nfreg: nf, nvreg: 2, sig, ret, nv_params: nvp, nf_params: nfp, jump_tables: Vec::new(), debug: Vec::new(), vararg: parts.get(7) == Some(&"vararg"), ins: Vec::new() });
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
                let f = cur.as_mut().ok_or(format!("line {ln}: table outside a function"))?;
                let def: i32 = parts[2].parse().map_err(|_| format!("line {ln}: table default"))?;
                let offs: Vec<i32> = parts[3..].iter().map(|s| s.parse().unwrap()).collect();
                f.jump_tables.push((def, offs));
            }
            "module" => {
                it.modules.insert(parts[1].to_string(), base + parts[2].parse::<u32>().unwrap());
                if let Some(p) = parts.get(3) {
                    it.module_paths.insert(parts[1].to_string(), p.to_string());
                    let path: std::sync::Arc<str> = (*p).into();
                    for f in funcs.iter_mut().filter(|f| f.module == parts[1]) { f.path = Some(path.clone()); }
                }
            }
            "source" => { let f = cur.as_mut().ok_or(format!("line {ln}: source outside a function"))?; f.module = parts[1].to_string(); }
            // The declaration of a module a native extension provides.
            "extension" if cur.is_none() => {
                if parts.len() != 3 || !parts[2].starts_with('"') { return Err(format!("line {ln}: extension NAME \"DECLARATION\"")); }
                crate::extension::declare(it, parts[1], &unquote(parts[2])).map_err(|e| format!("line {ln}: {e}"))?;
            }
            name => {
                let f = cur.as_mut().ok_or(format!("line {ln}: op outside a function"))?;
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
    let total = it.funcs.len() + funcs.len();
    for (i, f) in funcs.iter().enumerate() { crate::verify::verify_classes(f, total).map_err(|e| format!("function {} ({}): {e}", f.name, base as usize + i))?; }
    for f in funcs { it.frame_required |= f.code.iter().any(|op| matches!(op, Op::Defer(..) | Op::DeferMethod(..) | Op::AffineEnter) || crate::native_simd::required(op)); it.funcs.push(f); }
    for (shape, name, fid) in pending_methods { let n = it.intern(&name); it.heap.shapes[shape_ids[shape as usize] as usize].methods.insert(n, Value::func(base + fid)); }
    // A method an image installs may replace one compiled code resolved.
    it.heap.proto_epoch += 1;
    Ok(entry)
}

fn split(line: &str) -> Vec<&str> {
    // Whitespace split that keeps a quoted string as one token.
    let mut out = Vec::new();
    let mut rest = line;
    while !rest.is_empty() {
        rest = rest.trim_start();
        if rest.starts_with('"') { let end = rest[1..].find('"').map(|i| i + 2).unwrap_or(rest.len()); out.push(&rest[..end]); rest = &rest[end..]; }
        else { let end = rest.find(char::is_whitespace).unwrap_or(rest.len()); out.push(&rest[..end]); rest = &rest[end..]; }
    }
    out
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
