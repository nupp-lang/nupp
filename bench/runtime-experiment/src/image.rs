//! Loader for the emitter's text image: shapes, functions with constants and
//! opcodes named after the runtime's `Op` variants, and the entry.

use crate::heap::SlotTy;
use crate::interp::{Function, Interp, Op};

pub fn load(it: &mut Interp, text: &str) -> Result<u32, String> {
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
                let mut names = Vec::new(); let mut types = Vec::new();
                for p in &parts[3..] {
                    if let Some(m) = p.strip_prefix("method:") { let (n, f) = m.split_once('=').unwrap(); pending_methods.push((shape_ids.len() as u32, n.to_string(), f.parse().unwrap())); continue; }
                    let (n, t) = p.split_once(':').ok_or(format!("line {ln}: slot"))?;
                    names.push(it.intern(n));
                    types.push(match t { "num" => SlotTy::Num, "str" => SlotTy::Str, "bool" => SlotTy::Bool, t if t.starts_with("rec:") => SlotTy::Record(shape_ids[t[4..].parse::<usize>().unwrap()]), _ => SlotTy::Any });
                }
                let id = it.heap.shape(&names, &types);
                shape_ids.push(id);
            }
            "function" => {
                let name: &'static str = Box::leak(parts[1].to_string().into_boxed_str());
                let nf: u8 = parts.get(5).and_then(|s| s.parse().ok()).unwrap_or(1);
                let (sig, ret) = parts.get(6).and_then(|s| s.split_once(':')).map(|(a, b)| (a.bytes().collect::<Vec<u8>>(), b.as_bytes()[0])).unwrap_or((Vec::new(), b'v'));
                let nfp = sig.iter().filter(|&&c| c == b'f').count() as u8;
                let nvp = sig.len() as u8 - nfp;
                cur = Some(Function { name, code: Vec::new(), consts: Vec::new(), nparams: parts[3].parse().unwrap(), nregs: parts[4].parse().unwrap(), nireg: nf, nfreg: nf, nvreg: 2, sig, ret, nv_params: nvp, nf_params: nfp, jump_tables: Vec::new() });
            }
            "const" => {
                let f = cur.as_mut().unwrap();
                let v = match parts[2] {
                    "num" => crate::heap::Value::num(parts[3].parse().unwrap()),
                    "str" => { let s = unquote(&line[line.find('"').unwrap()..]); it.intern(&s) }
                    "nil" => crate::heap::Value::NIL,
                    "builtin" => crate::heap::Value::builtin(crate::builtins::id_of(parts[3]).ok_or_else(|| format!("line {ln}: unknown builtin {}", parts[3]))?),
                    "true" => crate::heap::Value::TRUE,
                    "false" => crate::heap::Value::FALSE,
                    "func" => crate::heap::Value::func(base + parts[3].parse::<u32>().unwrap()),
                    k => return Err(format!("line {ln}: constant kind {k}")),
                };
                f.consts.push(v);
            }
            "end" => { funcs.push(cur.take().unwrap()); }
            "entry" => { entry = base + parts[1].parse::<u32>().unwrap(); }
            "table" => {
                let f = cur.as_mut().ok_or(format!("line {ln}: table outside a function"))?;
                let def: i32 = parts[2].parse().map_err(|_| format!("line {ln}: table default"))?;
                let offs: Vec<i32> = parts[3..].iter().map(|s| s.parse().unwrap()).collect();
                f.jump_tables.push((def, offs));
            }
            "module" => { it.modules.insert(parts[1].to_string(), base + parts[2].parse::<u32>().unwrap()); }
            "entry2" => { it.entry2 = Some(base + parts[1].parse::<u32>().unwrap()); }
            name => {
                let f = cur.as_mut().ok_or(format!("line {ln}: op outside a function"))?;
                let a = |i: usize| -> i64 { parts.get(i).and_then(|s| s.parse().ok()).unwrap_or(0) };
                let op = match name {
                    "K" => Op::K(a(1) as u8, a(2) as u16), "Move" => Op::Move(a(1) as u8, a(2) as u8), "Nil" => Op::Nil(a(1) as u8),
                    "Add" => Op::Add(a(1) as u8, a(2) as u8, a(3) as u8), "Sub" => Op::Sub(a(1) as u8, a(2) as u8, a(3) as u8), "Mul" => Op::Mul(a(1) as u8, a(2) as u8, a(3) as u8),
                    "Lt" => Op::Lt(a(1) as u8, a(2) as u8, a(3) as u8), "Le" => Op::Le(a(1) as u8, a(2) as u8, a(3) as u8), "Eq" => Op::Eq(a(1) as u8, a(2) as u8, a(3) as u8), "Ne" => Op::Ne(a(1) as u8, a(2) as u8, a(3) as u8),
                    "Concat" => Op::Concat(a(1) as u8, a(2) as u8, a(3) as u8), "Not" => Op::Not(a(1) as u8, a(2) as u8), "Neg" => Op::Neg(a(1) as u8, a(2) as u8), "Len" => Op::Len(a(1) as u8, a(2) as u8),
                    "Jmp" => Op::Jmp(a(1) as i32), "JmpIf" => Op::JmpIf(a(1) as u8, a(2) as i32), "JmpIfNot" => Op::JmpIfNot(a(1) as u8, a(2) as i32),
                    "Call" => Op::Call(base + a(1) as u32, a(2) as u8, a(3) as u8), "CallT" => Op::CallT(base + a(1) as u32, a(2) as u8, a(3) as u8, a(4) as u8), "CallDyn" => Op::CallDyn(a(1) as u8, a(2) as u8, a(3) as u8), "CallMethod" => Op::CallMethod(a(1) as u16, a(2) as u8, a(3) as u8), "PCall" => Op::PCall(a(1) as u8, a(2) as u8),
                    "Ret" => Op::Ret(a(1) as u8), "RetNil" => Op::RetNil,
                    "NewTable" => Op::NewTable(a(1) as u8), "GetIdx" => Op::GetIdx(a(1) as u8, a(2) as u8, a(3) as u8), "SetIdx" => Op::SetIdx(a(1) as u8, a(2) as u8, a(3) as u8),
                    "GetField" => Op::GetField(a(1) as u8, a(2) as u8, a(3) as u16), "SetField" => Op::SetField(a(1) as u8, a(2) as u16, a(3) as u8),
                    "NewRecord" => Op::NewRecord(a(1) as u8, shape_ids[a(2) as usize]), "GetSlot" => Op::GetSlot(a(1) as u8, a(2) as u8, a(3) as u16), "SetSlot" => Op::SetSlot(a(1) as u8, a(2) as u16, a(3) as u8),
                    "TagCheckRec" => Op::TagCheckRec(a(1) as u8, a(2) as u8, shape_ids[a(3) as usize]), "TagCheckNum" => Op::TagCheckNum(a(1) as u8, a(2) as u8), "TagCheckStr" => Op::TagCheckStr(a(1) as u8, a(2) as u8),
                    "FK" => Op::FK(a(1) as u8, parts[2].parse().unwrap()), "FMov" => Op::FMov(a(1) as u8, a(2) as u8), "FUnbox" => Op::FUnbox(a(1) as u8, a(2) as u8), "FBox" => Op::FBox(a(1) as u8, a(2) as u8),
                    "FAdd" => Op::FAdd(a(1) as u8, a(2) as u8, a(3) as u8), "FSub" => Op::FSub(a(1) as u8, a(2) as u8, a(3) as u8), "FMul" => Op::FMul(a(1) as u8, a(2) as u8, a(3) as u8), "FDiv" => Op::FDiv(a(1) as u8, a(2) as u8, a(3) as u8), "FNeg" => Op::FNeg(a(1) as u8, a(2) as u8),
                    "FCmpLt" => Op::FCmpLt(a(1) as u8, a(2) as u8, a(3) as u8), "FCmpLe" => Op::FCmpLe(a(1) as u8, a(2) as u8, a(3) as u8), "FCmpEq" => Op::FCmpEq(a(1) as u8, a(2) as u8, a(3) as u8), "FCmpNe" => Op::FCmpNe(a(1) as u8, a(2) as u8, a(3) as u8),
                    "JmpIfIZero" => Op::JmpIfIZero(a(1) as u8, a(2) as i32), "FToI" => Op::FToI(a(1) as u8, a(2) as u8), "IK" => Op::IK(a(1) as u8, a(2)), "IAdd" => Op::IAdd(a(1) as u8, a(2) as u8, a(3) as u8), "ISub" => Op::ISub(a(1) as u8, a(2) as u8, a(3) as u8), "IAddK" => Op::IAddK(a(1) as u8, a(2) as u8, a(3)), "IMov" => Op::IMov(a(1) as u8, a(2) as u8), "IToF" => Op::IToF(a(1) as u8, a(2) as u8), "IUnbox" => Op::IUnbox(a(1) as u8, a(2) as u8), "ICmpSLt" => Op::ICmpSLt(a(1) as u8, a(2) as u8, a(3) as u8), "ICmpSLe" => Op::ICmpSLe(a(1) as u8, a(2) as u8, a(3) as u8), "GetIdxI" => Op::GetIdxI(a(1) as u8, a(2) as u8, a(3) as u8), "SetIdxI" => Op::SetIdxI(a(1) as u8, a(2) as u8, a(3) as u8), "Switch" => Op::Switch(a(1) as u8, a(2) as u16), "Mod" => Op::Mod(a(1) as u8, a(2) as u8, a(3) as u8), "Div" => Op::Div(a(1) as u8, a(2) as u8, a(3) as u8), "FMod" => Op::FMod(a(1) as u8, a(2) as u8, a(3) as u8), "RetN" => Op::RetN(a(1) as u8, a(2) as u8), "Require" => Op::Require(a(1) as u8, a(2) as u16), "RequireV" => Op::RequireV(a(1) as u8, a(2) as u8), "NewTableN" => Op::NewTableN(a(1) as u8, a(2) as u8, a(3) as u8), "SetMethod" => Op::SetMethod(shape_ids[a(1) as usize], a(2) as u16, a(3) as u8), "BoolFromI" => Op::BoolFromI(a(1) as u8, a(2) as u8), "FRet" => Op::FRet(a(1) as u8),
                    "GetSlotF" => Op::GetSlotF(a(1) as u8, a(2) as u8, a(3) as u16), "SetSlotF" => Op::SetSlotF(a(1) as u8, a(2) as u16, a(3) as u8), "LenF" => Op::LenF(a(1) as u8, a(2) as u8), "GetIdxF" => Op::GetIdxF(a(1) as u8, a(2) as u8, a(3) as u8), "SetIdxF" => Op::SetIdxF(a(1) as u8, a(2) as u8, a(3) as u8),
                    "NewClosure" => Op::NewClosure(a(1) as u8, base + a(2) as u32, a(3) as u8, a(4) as u8), "NewCell" => Op::NewCell(a(1) as u8, a(2) as u8), "GetCell" => Op::GetCell(a(1) as u8, a(2) as u8), "SetCell" => Op::SetCell(a(1) as u8, a(2) as u8), "GetUpval" => Op::GetUpval(a(1) as u8, a(2) as u8),
                    other => return Err(format!("line {ln}: unknown opcode {other}")),
                };
                f.code.push(op);
            }
        }
    }
    let total = it.funcs.len() + funcs.len();
    for (i, f) in funcs.iter().enumerate() { crate::lower_ir::verify_classes(f, total).map_err(|e| format!("function {} ({}): {e}", f.name, base as usize + i))?; }
    for f in funcs { it.funcs.push(f); }
    for (shape, name, fid) in pending_methods { let n = it.intern(&name); it.heap.shapes[shape_ids[shape as usize] as usize].methods.insert(n, crate::heap::Value::func(base + fid)); }
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

fn unquote(s: &str) -> String {
    let inner = &s[1..s.rfind('"').unwrap()];
    let mut out = String::new();
    let b = inner.as_bytes();
    let mut i = 0;
    while i < b.len() { if b[i] == b'\\' && i + 3 < b.len() + 1 { let code: u8 = std::str::from_utf8(&b[i + 1..i + 4]).unwrap().parse().unwrap(); out.push(code as char); i += 4; } else { out.push(b[i] as char); i += 1; } }
    out
}
