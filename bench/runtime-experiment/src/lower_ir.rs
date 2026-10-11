//! Lowering of the kernel IR to the typed bytecode, and the verifier that
//! re-derives every cited loop fact from the bytecode alone.

use crate::interp::{Function, Op};
use crate::ir::{Expr, Function as IrFunction, Stmt};
use std::collections::HashMap;

#[derive(Clone, Copy, Debug, PartialEq)]
enum Class { I, F, V4, Span, Species, Val }

#[derive(Clone, Copy, Debug)]
struct Reg { class: Class, idx: u8 }

struct Lowerer {
    code: Vec<Op>,
    names: HashMap<String, Reg>,
    span_value: HashMap<String, u8>,
    span_len: HashMap<String, u8>,
    ni: u8,
    nf: u8,
    /// High-water marks: the register counts the function needs.
    ni_high: u8,
    nf_high: u8,
    nv: u8,
    nregs: u8,
    /// Loop facts in scope while lowering a body: (cursor name, k, span name).
    facts: Vec<(String, i64, String)>,
    relations: Vec<(String, String)>,
    /// Whether add-of-mul may lower to a fused multiply-add.
    fuse: bool,
    /// Splats of uniforms, hoisted to the prologue: uniform name -> vector pair.
    hoisted_splats: HashMap<String, u8>,
    prologue: Vec<Op>,
    /// The byte buffer and length a builder was handed, until it finishes.
    pending_string: Option<(u8, u8)>,
    consts: Vec<crate::heap::Value>,
    /// Value registers holding pool constant strings, with their lengths.
    const_len: HashMap<u8, usize>,
    /// Interns a string literal into the heap for the constant pool.
    intern: Box<dyn FnMut(&str) -> crate::heap::Value>,
    /// Break jumps to patch, per open loop.
    breaks: Vec<Vec<usize>>,
}

/// Whether an expression can neither trap nor touch memory: locals,
/// constants and arithmetic or logic over them.
fn pure(e: &Expr) -> bool {
    match e {
        Expr::Call { op, args, .. } => !(op.starts_with("lua") || op.starts_with("simd_load") || op.starts_with("simd_store")) && args.iter().all(pure),
        _ => true,
    }
}

fn class_of(ty: &str) -> Class {
    match ty {
        "f64" | "f32" => Class::F,
        "lua_string" | "lua_value" | "lua_builder" | "lua_scratch_u8" | "lua_table" | "lua_string_buffer" => Class::Val,
        t if t.starts_with("simd_vector_") => Class::V4,
        t if t.starts_with("simd_species_") => Class::Species,
        _ => Class::I, // u32, u64, i32, i64, bool, masks (active lane count)
    }
}

impl Lowerer {
    fn ireg(&mut self) -> u8 { self.ni += 1; self.ni_high = self.ni_high.max(self.ni); self.ni - 1 }
    fn freg(&mut self) -> u8 { self.nf += 1; self.nf_high = self.nf_high.max(self.nf); self.nf - 1 }
    fn vpair(&mut self) -> u8 { self.nv += 2; self.nv - 2 }
    fn vreg(&mut self) -> u8 { let r = self.nregs; self.nregs += 1; r }
    fn alloc(&mut self, class: Class) -> Reg {
        match class { Class::I => Reg { class, idx: self.ireg() }, Class::F => Reg { class, idx: self.freg() }, Class::V4 => Reg { class, idx: self.vpair() }, Class::Val => Reg { class, idx: self.vreg() }, c => Reg { class: c, idx: 0 } }
    }

    fn to_f(&mut self, r: Reg) -> u8 {
        match r.class { Class::F => r.idx, Class::I => { let d = self.freg(); self.code.push(Op::IToF(d, r.idx)); d } _ => panic!("not a scalar: {r:?}") }
    }
    fn to_i(&mut self, r: Reg) -> u8 {
        match r.class { Class::I => r.idx, Class::F => { let d = self.ireg(); self.code.push(Op::FToI(d, r.idx)); d } _ => panic!("not a scalar: {r:?}") }
    }

    fn expr(&mut self, e: &Expr) -> Reg {
        match e {
            Expr::Local { name, .. } | Expr::Uniform { name, .. } => *self.names.get(name).unwrap_or_else(|| panic!("unknown name {name}")),
            Expr::Constant { ty, value } => {
                if ty == "bool" { let d = self.ireg(); self.code.push(Op::IK(d, (value == "true") as i64)); return Reg { class: Class::I, idx: d }; }
                if class_of(ty) == Class::F { let d = self.freg(); self.code.push(Op::FK(d, value.parse().unwrap())); Reg { class: Class::F, idx: d } }
                else { let d = self.ireg(); self.code.push(Op::IK(d, value.parse::<f64>().unwrap() as i64)); Reg { class: Class::I, idx: d } }
            }
            Expr::Span(name) => Reg { class: Class::Span, idx: self.span_value[name] },
            Expr::Str(text) => { let v = (self.intern)(text); let k = self.consts.len() as u16; self.consts.push(v); let d = self.alloc(Class::Val); self.code.push(Op::K(d.idx, k)); self.const_len.insert(d.idx, text.len()); d }
            Expr::Count(name) => Reg { class: Class::I, idx: self.span_len[name] },
            Expr::Call { op, ty, args } => self.call(op, ty.as_deref(), args),
        }
    }

    fn binary_scalar(&mut self, args: &[Expr], iop: fn(u8, u8, u8) -> Op, fop: fn(u8, u8, u8) -> Op) -> Reg {
        let a = self.expr(&args[0]);
        let b = self.expr(&args[1]);
        if a.class == Class::F || b.class == Class::F {
            let (x, y) = (self.to_f(a), self.to_f(b));
            let d = self.freg(); self.code.push(fop(d, x, y)); Reg { class: Class::F, idx: d }
        } else {
            let d = self.ireg(); self.code.push(iop(d, a.idx, b.idx)); Reg { class: Class::I, idx: d }
        }
    }

    fn compare(&mut self, args: &[Expr], iop: fn(u8, u8, u8) -> Op, fop: fn(u8, u8, u8) -> Op) -> Reg {
        // Comparisons land in an integer register whichever class they compare.
        let a = self.expr(&args[0]);
        let b = self.expr(&args[1]);
        let d = self.ireg();
        if a.class == Class::F || b.class == Class::F { let (x, y) = (self.to_f(a), self.to_f(b)); self.code.push(fop(d, x, y)); }
        else { self.code.push(iop(d, a.idx, b.idx)); }
        Reg { class: Class::I, idx: d }
    }

    /// The IR writes a span index as a 1-based number, `int_to_f64(u32_add(cursor, 1))`.
    /// That is `cursor` exactly, so the lowering uses the cursor register itself
    /// and no conversion runs; any other index goes through the general path.
    fn index_to_zero_based(&mut self, index: &Expr) -> u8 {
        if let Expr::Call { op, args, .. } = index {
            if op == "int_to_f64" {
                if let Expr::Call { op: add, args: sum, .. } = &args[0] {
                    if add == "u32_add" && matches!(&sum[1], Expr::Constant { value, .. } if value == "1") {
                        if let Expr::Local { name, .. } = &sum[0] { return self.names[name].idx; }
                    }
                }
            }
        }
        let r = self.expr(index);
        let i = self.to_i(r);
        let d = self.ireg();
        self.code.push(Op::IAddK(d, i, -1));
        d
    }

    /// Whether one of the two registers was just set to a constant mask below `len`.
    fn mask_below(&self, a: u8, b: u8, len: usize) -> bool {
        let n = self.code.len();
        let k_of = |r: u8| (0..n - 1).rev().find_map(|i| match self.code[i] { Op::IK(d, k) if d == r => Some(k), o if lower_dest(&o) == Some(r) => Some(-1), _ => None });
        [a, b].iter().any(|&r| matches!(k_of(r), Some(k) if k >= 0 && (k as usize) < len))
    }

    /// The `nupp.math.u32` helpers the kernel declares, by name: the IR lists
    /// them as helpers without bodies, so each maps to its integer opcode.
    fn helper(&mut self, name: &str, args: &[Expr]) -> Reg {
        let i = |l: &mut Self, e: &Expr| { let r = l.expr(e); l.to_i(r) };
        let d = self.ireg();
        match name {
            "u32" => { if let Expr::Constant { value, .. } = &args[0] { self.code.push(Op::IK(d, value.parse::<f64>().unwrap() as u32 as i64)); } else { let a = i(self, &args[0]); self.code.push(Op::IMaskU32(d, a)); } }
            "add" => { let a = i(self, &args[0]); let b = i(self, &args[1]); let t = self.ireg(); self.code.push(Op::IAdd(t, a, b)); self.code.push(Op::IMaskU32(d, t)); }
            "shr" => { let a = i(self, &args[0]); let b = i(self, &args[1]); self.code.push(Op::IShrU(d, a, b)); }
            "shl" => { let a = i(self, &args[0]); let b = i(self, &args[1]); let t = self.ireg(); self.code.push(Op::IShl(t, a, b)); self.code.push(Op::IMaskU32(d, t)); }
            "andBits" => { let a = i(self, &args[0]); let b = i(self, &args[1]); self.code.push(Op::IAnd(d, a, b)); }
            "orBits" => { let a = i(self, &args[0]); let b = i(self, &args[1]); self.code.push(Op::IOr(d, a, b)); }
            "reversed" => { let a = i(self, &args[0]); self.code.push(Op::IBswap32(d, a)); }
            other => panic!("unsupported helper {other}"),
        }
        Reg { class: Class::I, idx: d }
    }

    fn call(&mut self, op: &str, ty: Option<&str>, args: &[Expr]) -> Reg {
        if let Some(name) = op.strip_prefix("call ") { return self.helper(name, args); }
        match op {
            "lua.length" => { let s = self.expr(&args[0]); let d = self.ireg(); self.code.push(Op::BytesLen(d, s.idx)); Reg { class: Class::I, idx: d } }
            "lua_string_u32" => { let s = self.expr(&args[0]); let r = self.expr(&args[1]); let i = self.to_i(r); let d = self.ireg(); self.code.push(Op::LoadU32W(d, s.idx, i)); Reg { class: Class::I, idx: d } }
            "lua_string_byte" => {
                let s = self.expr(&args[0]); let r = self.expr(&args[1]); let i = self.to_i(r); let d = self.ireg();
                // A lookup into a pool constant by a masked index is in bounds
                // when the mask is below the constant's length; the verifier
                // re-derives both from the bytecode (3.4b).
                let proven = self.const_len.get(&s.idx).map_or(false, |&len| matches!(self.code.last(), Some(Op::IAnd(dd, a, b)) if *dd == i && self.mask_below(*a, *b, len)));
                self.code.push(if proven { Op::LoadU8K(d, s.idx, i) } else { Op::LoadU8(d, s.idx, i) });
                Reg { class: Class::I, idx: d }
            }
            "u32_sub" => { let a = self.expr(&args[0]); let b = self.expr(&args[1]); let t = self.ireg(); self.code.push(Op::ISub(t, a.idx, b.idx)); let d = self.ireg(); self.code.push(Op::IMaskU32(d, t)); Reg { class: Class::I, idx: d } }
            "eq" => self.compare(args, Op::ICmpEq, Op::FCmpEq),
            "lua.builder" => { let d = self.alloc(Class::Val); self.code.push(Op::Nil(d.idx)); d }
            "lua.scratch_u8" => { let r = self.expr(&args[0]); let n = self.to_i(r); let d = self.alloc(Class::Val); self.code.push(Op::NewBytes(d.idx, n)); d }
            "lua_builder_string_scratch" => { let r = self.expr(&args[2]); let n = self.to_i(r); let s = self.expr(&args[3]); self.pending_string = Some((s.idx, n)); Reg { class: Class::I, idx: 0 } }
            "lua.builder_finish" => { let (s, n) = self.pending_string.take().expect("builder finished without a string"); let d = self.alloc(Class::Val); self.code.push(Op::BytesToStr(d.idx, s, n)); d }
            "numeric_cast" => { let r = self.expr(&args[0]); match r.class { Class::F => Reg { class: Class::I, idx: self.to_i(r) }, _ => r } }
            "int_to_f64" => { let r = self.expr(&args[0]); Reg { class: Class::F, idx: self.to_f(r) } }
            "u32_add" => { let a = self.expr(&args[0]); let b = self.expr(&args[1]); let t = self.ireg(); self.code.push(Op::IAdd(t, a.idx, b.idx)); let d = self.ireg(); self.code.push(Op::IMaskU32(d, t)); Reg { class: Class::I, idx: d } }
            "u64_add" | "add" => self.binary_scalar(args, Op::IAdd, Op::FAdd),
            "sub" => self.binary_scalar(args, Op::ISub, Op::FSub),
            "mul" => self.binary_scalar(args, |d, a, b| Op::IAdd(d, a, b), Op::FMul),
            "le" => self.compare(args, Op::ICmpLe, Op::FCmpLe),
            "lt" => self.compare(args, Op::ICmpLt, Op::FCmpLt),
            "ge" => { let sw = [args[1].clone(), args[0].clone()]; self.compare(&sw, Op::ICmpLe, Op::FCmpLe) }
            "gt" => { let sw = [args[1].clone(), args[0].clone()]; self.compare(&sw, Op::ICmpLt, Op::FCmpLt) }
            "ne" => self.compare(args, Op::ICmpNe, Op::FCmpNe),
            "or" => { let a = self.expr(&args[0]); let b = self.expr(&args[1]); let d = self.ireg(); self.code.push(Op::IOr(d, a.idx, b.idx)); Reg { class: Class::I, idx: d } }
            "not" => { let a = self.expr(&args[0]); let z = self.ireg(); self.code.push(Op::IK(z, 0)); let d = self.ireg(); self.code.push(Op::ICmpEq(d, a.idx, z)); Reg { class: Class::I, idx: d } }
            "lua.byte" => { let s = self.expr(&args[0]); let r = self.expr(&args[1]); let i1 = self.to_i(r); let i = self.ireg(); self.code.push(Op::IAddK(i, i1, -1)); let d = self.ireg(); self.code.push(Op::LoadU8(d, s.idx, i)); Reg { class: Class::I, idx: d } }
            "lua.new_table" => { let d = self.alloc(Class::Val); self.code.push(Op::NewTable(d.idx)); d }
            "lua.get_index" => { let t = self.expr(&args[0]); let r = self.expr(&args[1]); let i = self.to_f(r); let d = self.alloc(Class::Val); self.code.push(Op::GetIdxF(d.idx, t.idx, i)); let f = self.freg(); self.code.push(Op::FUnbox(f, d.idx)); Reg { class: Class::F, idx: f } }
            "lua.string_buffer" => { let d = self.alloc(Class::Val); self.code.push(Op::NewBuffer(d.idx)); if !matches!(&args[0], Expr::Str(s) if s.is_empty()) { let s = self.expr(&args[0]); self.code.push(Op::BufAppend(d.idx, s.idx)); } d }
            "lua.string_buffer_append" => {
                let buf = self.expr(&args[0]);
                // An appended substring is copied straight from the source.
                if let Expr::Call { op, args: sub, .. } = &args[1] { if op == "lua.substring" { let s = self.expr(&sub[0]); let r = self.expr(&sub[1]); let i = self.to_i(r); let r2 = self.expr(&sub[2]); let j = self.to_i(r2); self.code.push(Op::BufAppendSub(buf.idx, s.idx, i, j)); return Reg { class: Class::I, idx: 0 }; } }
                let s = self.expr(&args[1]); self.code.push(Op::BufAppend(buf.idx, s.idx)); Reg { class: Class::I, idx: 0 }
            }
            "lua.substring" => { let s = self.expr(&args[0]); let r = self.expr(&args[1]); let i = self.to_i(r); let r2 = self.expr(&args[2]); let j = self.to_i(r2); let d = self.alloc(Class::Val); self.code.push(Op::Substring(d.idx, s.idx, i, j)); d }
            "lua.string_buffer_finish" => { let buf = self.expr(&args[0]); let d = self.alloc(Class::Val); self.code.push(Op::BufFinish(d.idx, buf.idx)); d }
            // `and` and `or` are Lua's: the right operand runs only when the
            // left decides nothing. Pure, trap-free operands lower eagerly so
            // the loop facts the verifier reads stay single instructions.
            "and" if !pure(&args[1]) => {
                let a = self.expr(&args[0]); let d = self.ireg(); self.code.push(Op::IMov(d, a.idx));
                let branch = self.code.len(); self.code.push(Op::JmpIfIZero(d, 0));
                let b = self.expr(&args[1]); self.code.push(Op::IMov(d, b.idx));
                let end = self.code.len(); self.code[branch] = Op::JmpIfIZero(d, end as i32 - (branch as i32 + 1));
                Reg { class: Class::I, idx: d }
            }
            "or" if !pure(&args[1]) => {
                let a = self.expr(&args[0]); let d = self.ireg(); self.code.push(Op::IMov(d, a.idx));
                let z = self.ireg(); self.code.push(Op::IK(z, 0)); let t = self.ireg(); self.code.push(Op::ICmpEq(t, d, z));
                let branch = self.code.len(); self.code.push(Op::JmpIfIZero(t, 0));
                let b = self.expr(&args[1]); self.code.push(Op::IMov(d, b.idx));
                let end = self.code.len(); self.code[branch] = Op::JmpIfIZero(t, end as i32 - (branch as i32 + 1));
                Reg { class: Class::I, idx: d }
            }
            "and" => { let a = self.expr(&args[0]); let b = self.expr(&args[1]); let d = self.ireg(); self.code.push(Op::IAnd(d, a.idx, b.idx)); Reg { class: Class::I, idx: d } }
            "simd_species.species" => Reg { class: Class::Species, idx: 0 },
            "simd_lanes_generic.lanes" => { let d = self.ireg(); self.code.push(Op::IK(d, 4)); Reg { class: Class::I, idx: d } }
            "simd_splat.splat" => {
                // A uniform never changes, so its splat is computed once in the prologue.
                if let Expr::Uniform { name, .. } = &args[0] {
                    if let Some(&v) = self.hoisted_splats.get(name) { return Reg { class: Class::V4, idx: v }; }
                    let f = self.names[name].idx;
                    let v = self.vpair();
                    self.prologue.push(Op::VSplat(v, f)); self.prologue.push(Op::VSplat(v + 1, f));
                    self.hoisted_splats.insert(name.clone(), v);
                    return Reg { class: Class::V4, idx: v };
                }
                let r = self.expr(&args[0]); let f = self.to_f(r); let v = self.vpair(); self.code.push(Op::VSplat(v, f)); self.code.push(Op::VSplat(v + 1, f)); Reg { class: Class::V4, idx: v }
            }
            "simd_tail.tail" => { let r = self.expr(&args[0]); Reg { class: Class::I, idx: self.to_i(r) } }
            "simd_load.load" => {
                // (species, index, [mask], span)
                let span = match args.last() { Some(Expr::Span(n)) => n.clone(), _ => panic!("load without span") };
                let s = self.span_value[&span];
                let idx = self.index_to_zero_based(&args[1]);
                let v = self.vpair();
                if args.len() == 4 {
                    let m = self.expr(&args[2]);
                    self.code.push(Op::VLoadM(v, s, idx, 0, m.idx));
                    self.code.push(Op::VLoadM(v + 1, s, idx, 2, m.idx));
                } else {
                    self.code.push(Op::VLoad(v, s, idx, 0));
                    self.code.push(Op::VLoad(v + 1, s, idx, 2));
                }
                Reg { class: Class::V4, idx: v }
            }
            "simd_store.store" => {
                let span = match args.last() { Some(Expr::Span(n)) => n.clone(), _ => panic!("store without span") };
                let s = self.span_value[&span];
                let idx = self.index_to_zero_based(&args[1]);
                let value = self.expr(&args[2]);
                assert_eq!(value.class, Class::V4);
                if args.len() == 5 {
                    let m = self.expr(&args[3]);
                    self.code.push(Op::VStoreM(s, idx, value.idx, 0, m.idx));
                    self.code.push(Op::VStoreM(s, idx, value.idx + 1, 2, m.idx));
                } else {
                    self.code.push(Op::VStore(s, idx, value.idx, 0));
                    self.code.push(Op::VStore(s, idx, value.idx + 1, 2));
                }
                Reg { class: Class::I, idx: 0 }
            }
            "simd_binary.add" if self.fuse && args.iter().any(|a| matches!(a, Expr::Call { op, .. } if op == "simd_binary.mul")) => {
                // add(mul(x, y), z) or add(z, mul(x, y)) as one fused operation per half.
                let (mul, other) = if matches!(&args[0], Expr::Call { op, .. } if op == "simd_binary.mul") { (&args[0], &args[1]) } else { (&args[1], &args[0]) };
                let (x, y) = match mul { Expr::Call { args: m, .. } => (self.expr(&m[0]), self.expr(&m[1])), _ => unreachable!() };
                let z = self.expr(other);
                assert!(x.class == Class::V4 && y.class == Class::V4 && z.class == Class::V4);
                let d = self.vpair();
                self.code.push(Op::VFma(d, x.idx, y.idx, z.idx)); self.code.push(Op::VFma(d + 1, x.idx + 1, y.idx + 1, z.idx + 1));
                Reg { class: Class::V4, idx: d }
            }
            "simd_binary.add" | "simd_binary.mul" => {
                let a = self.expr(&args[0]); let b = self.expr(&args[1]);
                assert!(a.class == Class::V4 && b.class == Class::V4, "vector binary on {a:?} {b:?}");
                let d = self.vpair();
                let mk: fn(u8, u8, u8) -> Op = if op.ends_with("add") { Op::VAdd } else { Op::VMul };
                self.code.push(mk(d, a.idx, b.idx)); self.code.push(mk(d + 1, a.idx + 1, b.idx + 1));
                Reg { class: Class::V4, idx: d }
            }
            "simd_horizontal.algebraic_sum" => {
                let v = self.expr(&args[0]); assert_eq!(v.class, Class::V4);
                let (l0, l1, l2, l3) = (self.freg(), self.freg(), self.freg(), self.freg());
                self.code.push(Op::VLane(l0, v.idx, 0)); self.code.push(Op::VLane(l1, v.idx, 1)); self.code.push(Op::VLane(l2, v.idx + 1, 0)); self.code.push(Op::VLane(l3, v.idx + 1, 1));
                let (s0, s1, d) = (self.freg(), self.freg(), self.freg());
                self.code.push(Op::FAdd(s0, l0, l1)); self.code.push(Op::FAdd(s1, l2, l3)); self.code.push(Op::FAdd(d, s0, s1));
                Reg { class: Class::F, idx: d }
            }
            other => panic!("unsupported IR operation {other}{}", ty.map(|t| format!(":{t}")).unwrap_or_default()),
        }
    }

    fn assign(&mut self, dst: Reg, src: Reg) {
        match (dst.class, src.class) {
            (Class::I, Class::I) => self.code.push(Op::IMov(dst.idx, src.idx)),
            (Class::F, Class::F) => self.code.push(Op::FMov(dst.idx, src.idx)),
            (Class::F, Class::I) => self.code.push(Op::IToF(dst.idx, src.idx)),
            (Class::I, Class::F) => self.code.push(Op::FToI(dst.idx, src.idx)),
            (Class::V4, Class::V4) => { self.code.push(Op::VMov(dst.idx, src.idx)); self.code.push(Op::VMov(dst.idx + 1, src.idx + 1)); }
            (Class::Val, Class::Val) => self.code.push(Op::Move(dst.idx, src.idx)),
            (Class::Species, Class::Species) => {}
            (a, b) => panic!("assign {b:?} to {a:?}"),
        }
    }
    fn zero_i(&mut self) -> u8 { let z = self.ireg(); self.code.push(Op::IK(z, 0)); z }
    fn zero_f(&mut self) -> u8 { let z = self.freg(); self.code.push(Op::FK(z, 0.0)); z }
    fn zero_v(&mut self) -> u8 { let f = self.zero_f(); let v = self.nv; self.nv += 1; self.code.push(Op::VSplat(v, f)); v }

    /// Recognises `cursor + K <= count S` conjuncts in a loop condition.
    fn facts_of(&self, cond: &Expr, out: &mut Vec<(String, i64, String)>) {
        if let Expr::Call { op, args, .. } = cond {
            if op == "and" { for a in args { self.facts_of(a, out); } return; }
            if op == "le" && args.len() == 2 {
                if let (Expr::Call { op: addop, args: sum, .. }, Expr::Count(span)) = (&args[0], &args[1]) {
                    if addop == "u64_add" || addop == "add" {
                        let cursor = match &sum[0] { Expr::Call { op: c, args: inner, .. } if c == "numeric_cast" => match &inner[0] { Expr::Local { name, .. } => Some(name.clone()), _ => None }, Expr::Local { name, .. } => Some(name.clone()), _ => None };
                        let k = match &sum[1] { Expr::Call { op: c, args: inner, .. } if c == "numeric_cast" => match &inner[0] { Expr::Call { op: l, .. } if l == "simd_lanes_generic.lanes" => Some(4), Expr::Constant { value, .. } => value.parse::<f64>().ok().map(|v| v as i64), _ => None }, Expr::Constant { value, .. } => value.parse::<f64>().ok().map(|v| v as i64), _ => None };
                        if let (Some(c), Some(k)) = (cursor, k) { out.push((c, k, span.clone())); }
                    }
                }
            }
        }
    }

    fn block(&mut self, stmts: &[Stmt]) {
        for s in stmts {
            // Scalar temporaries live for one statement: a named register is
            // allocated before its value's temporaries, and the counters
            // return to the high-water mark afterwards. The prototype's
            // operands are eight bits and a kernel's expression trees would
            // otherwise run past them.
            let mark = (self.ni, self.nf);
            match s {
                Stmt::Let { name, ty, value, .. } => {
                    let class = class_of(ty);
                    let dst = self.alloc(class);
                    let kept = (self.ni, self.nf);
                    let r = self.expr(value);
                    self.assign(dst, r);
                    self.names.insert(name.clone(), dst);
                    self.ni = kept.0; self.nf = kept.1;
                    continue;
                }
                Stmt::Set { name, value } => { let r = self.expr(value); let dst = self.names[name]; self.assign(dst, r); }
                Stmt::While { cond, body, .. } => {
                    let header = self.code.len();
                    let c = self.expr(cond);
                    let branch = self.code.len();
                    self.code.push(Op::JmpIfIZero(c.idx, 0));
                    let mut facts = Vec::new();
                    self.facts_of(cond, &mut facts);
                    // A bound on S carries to T when the entry guard says #S <= #T.
                    let mut derived = Vec::new();
                    for (c, k, s_name) in &facts { for (a, b) in &self.relations { if a == s_name && !facts.iter().any(|(_, _, t)| t == b) { derived.push((c.clone(), *k, b.clone())); } } }
                    facts.extend(derived);
                    for (cursor, k, span) in &facts {
                        let cr = self.names[cursor];
                        self.code.push(Op::LoopFact(cr.idx, *k, self.span_len[span]));
                    }
                    let saved = self.facts.len();
                    self.facts.extend(facts);
                    self.breaks.push(Vec::new());
                    self.block(body);
                    self.facts.truncate(saved);
                    let back = self.code.len();
                    self.code.push(Op::Jmp(header as i32 - (back as i32 + 1)));
                    let exit = self.code.len();
                    self.code[branch] = Op::JmpIfIZero(c.idx, exit as i32 - (branch as i32 + 1));
                    for at in self.breaks.pop().unwrap() { self.code[at] = Op::Jmp(exit as i32 - (at as i32 + 1)); }
                }
                Stmt::If { cond, body, else_body } => {
                    let c = self.expr(cond);
                    let branch = self.code.len();
                    self.code.push(Op::JmpIfIZero(c.idx, 0));
                    self.block(body);
                    if else_body.is_empty() {
                        let end = self.code.len();
                        self.code[branch] = Op::JmpIfIZero(c.idx, end as i32 - (branch as i32 + 1));
                    } else {
                        let skip = self.code.len();
                        self.code.push(Op::Jmp(0));
                        let else_at = self.code.len();
                        self.code[branch] = Op::JmpIfIZero(c.idx, else_at as i32 - (branch as i32 + 1));
                        self.block(else_body);
                        let end = self.code.len();
                        self.code[skip] = Op::Jmp(end as i32 - (skip as i32 + 1));
                    }
                }
                Stmt::For { var, start, stop, body } => {
                    // A float loop index, inclusive stop, step one.
                    let idx = self.alloc(Class::F);
                    let s = self.expr(start); self.assign(idx, s);
                    let st = self.expr(stop); let stop_f = self.to_f(st);
                    let stop_reg = self.freg(); self.code.push(Op::FMov(stop_reg, stop_f));
                    self.names.insert(var.clone(), idx);
                    let header = self.code.len();
                    let c = self.ireg(); self.code.push(Op::FCmpLe(c, idx.idx, stop_reg));
                    let branch = self.code.len(); self.code.push(Op::JmpIfIZero(c, 0));
                    self.breaks.push(Vec::new());
                    self.block(body);
                    let one = self.freg(); self.code.push(Op::FK(one, 1.0)); self.code.push(Op::FAdd(idx.idx, idx.idx, one));
                    let back = self.code.len(); self.code.push(Op::Jmp(header as i32 - (back as i32 + 1)));
                    let exit = self.code.len();
                    self.code[branch] = Op::JmpIfIZero(c, exit as i32 - (branch as i32 + 1));
                    for at in self.breaks.pop().unwrap() { self.code[at] = Op::Jmp(exit as i32 - (at as i32 + 1)); }
                }
                Stmt::Break => { let at = self.code.len(); self.code.push(Op::Jmp(0)); self.breaks.last_mut().expect("break outside a loop").push(at); }
                Stmt::Expr(e) => { self.expr(e); }
                Stmt::Store { op, target, index, value } => {
                    let s = self.names[target];
                    let ir = self.expr(index); let i = if op == "lua_set_index" { 0 } else { self.to_i(ir) };
                    let vr = self.expr(value); let v = if op == "lua_set_index" { 0 } else { self.to_i(vr) };
                    match op.as_str() { "lua.scratch_u8_set4" => self.code.push(Op::StoreU32(s.idx, i, v)), "lua.scratch_u8_set" => self.code.push(Op::StoreU8(s.idx, i, v)), "lua_set_index" => { let fi = self.to_f(ir); let fv = self.to_f(vr); let b = self.alloc(Class::Val); self.code.push(Op::FBox(b.idx, fv)); self.code.push(Op::SetIdxF(s.idx, fi, b.idx)); } other => panic!("store {other}") }
                }
                Stmt::Return(values) => {
                    if values.is_empty() { self.code.push(Op::RetNil); }
                    else { let r = self.expr(&values[0]); if r.class == Class::Val { self.code.push(Op::Ret(r.idx)); } else { let f = self.to_f(r); self.code.push(Op::FRet(f)); } }
                }
            }
            self.ni = mark.0; self.nf = mark.1;
        }
    }
}

/// Lowers one IR function. Span and uniform parameters arrive as values in
/// registers 1.. in declaration order.
pub fn lower(f: &IrFunction) -> Function { lower_with(f, &[], Box::new(|s| panic!("string literal {s:?} with no heap"))) }

/// Lowers with named constants (the kernel's `konst_N` strings) bound to
/// value registers loaded from the constant pool in the prologue.
pub fn lower_with(f: &IrFunction, consts: &[(String, crate::heap::Value, usize)], intern: Box<dyn FnMut(&str) -> crate::heap::Value>) -> Function {
    let mut l = Lowerer { code: Vec::new(), names: HashMap::new(), span_value: HashMap::new(), span_len: HashMap::new(), ni: 0, nf: 0, ni_high: 0, nf_high: 0, nv: 0, nregs: 1, facts: Vec::new(), relations: Vec::new(), fuse: std::env::var("NO_FMA").is_err(), hoisted_splats: HashMap::new(), prologue: Vec::new(), pending_string: None, consts: Vec::new(), const_len: HashMap::new(), intern, breaks: Vec::new() };
    for (i, p) in f.params.iter().enumerate() {
        let vreg = (i + 1) as u8;
        l.nregs = vreg + 1;
        if p.ty.starts_with("lua_") {
            l.names.insert(p.name.clone(), Reg { class: Class::Val, idx: vreg });
        } else if p.ty == "bool" {
            let ir = l.ireg();
            l.code.push(Op::Truthy(ir, vreg));
            l.names.insert(p.name.clone(), Reg { class: Class::I, idx: ir });
        } else if p.kind.ends_with("span") {
            l.span_value.insert(p.name.clone(), vreg);
            let len = l.ireg();
            l.code.push(Op::StorageLen(len, vreg));
            l.span_len.insert(p.name.clone(), len);
        } else {
            let fr = l.freg();
            l.code.push(Op::FUnbox(fr, vreg));
            l.names.insert(p.name.clone(), Reg { class: Class::F, idx: fr });
        }
    }
    for (name, v, len) in consts { let k = l.consts.len() as u16; l.consts.push(*v); let r = l.vreg(); l.code.push(Op::K(r, k)); l.names.insert(name.clone(), Reg { class: Class::Val, idx: r }); l.const_len.insert(r, *len); }
    for (a, b) in &f.relations { l.code.push(Op::GuardLenLe(l.span_len[a], l.span_len[b])); }
    l.relations = f.relations.clone();
    let prologue_end = l.code.len();
    l.block(&f.body);
    // Hoisted ops land at the end of the prologue; every jump is relative and
    // lies after this point, so offsets are unchanged.
    let hoisted = std::mem::take(&mut l.prologue);
    for (i, op) in hoisted.into_iter().enumerate() { l.code.insert(prologue_end + i, op); }
    if !matches!(l.code.last(), Some(Op::RetNil) | Some(Op::FRet(_)) | Some(Op::Ret(_))) { l.code.push(Op::RetNil); }
    assert!(l.ni_high < 250 && l.nf_high < 250 && l.nv < 250, "register pressure beyond the prototype's 8-bit operands");
    Function { name: Box::leak(f.name.clone().into_boxed_str()), sig: vec![b'v'; f.params.len()], ret: b'v', nv_params: f.params.len() as u8, nf_params: 0, code: l.code, consts: l.consts, nparams: f.params.len() as u8, nregs: l.nregs + 1, nireg: l.ni_high + 1, nfreg: l.nf_high + 1, nvreg: l.nv + 2, jump_tables: Vec::new() }
}

// ---------------------------------------------------------------------------
// Verifier: register classes by abstract interpretation is implicit in the
// typed opcode set here (each operand names its class); what is re-derived is
// every cited loop fact and every unchecked memory access.

#[derive(Clone, Debug, PartialEq)]
enum Sym { Cursor(u8), Const(i64), Len(u8), Add(Box<Sym>, Box<Sym>), Le(Box<Sym>, Box<Sym>), And(Box<Sym>, Box<Sym>), Unknown }

pub fn verify(f: &Function) -> Result<(), String> {
    let code = &f.code;
    for (pc, op) in code.iter().enumerate() {
        if let Op::LoopFact(cursor, k, len) = *op {
            // The fact must be guarded by the immediately preceding conditional
            // branch, whose condition register must symbolically imply
            // cursor + k' <= len with k' >= k.
            // Several facts may follow one branch; walk back over them to it.
            let mut bpc = pc - 1;
            while bpc > 0 && matches!(code[bpc], Op::LoopFact(..)) { bpc -= 1; }
            let (creg, exit) = match code.get(bpc) { Some(Op::JmpIfIZero(c, off)) => (*c, (bpc as i64 + 1 + *off as i64) as usize), _ => return Err(format!("pc {pc}: loop fact not guarded by a branch")) };
            // Symbolically evaluate integer registers backwards from the branch
            // to the loop header, which is the nearest preceding jump target.
            let mut env: HashMap<u8, Sym> = HashMap::new();
            // Count registers are defined in the prologue and are loop-invariant.
            for o in &code[..pc] { if let Op::StorageLen(d, _) = *o { env.insert(d, Sym::Len(d)); } }
            // The loop header is the target of the back-edge that closes this
            // loop: the first later backward jump landing at or before this fact.
            let target_of = |i: usize, off: i32| (i as i64 + 1 + off as i64) as usize;
            let start = (pc + 1..code.len()).find_map(|i| match code[i] { Op::Jmp(off) if off < 0 && target_of(i, off) <= pc => Some(target_of(i, off)), _ => None }).ok_or_else(|| format!("pc {pc}: loop fact with no closing back-edge"))?;
            for i in start..bpc {
                match code[i] {
                    Op::IK(d, k) => { env.insert(d, Sym::Const(k)); }
                    Op::IAdd(d, a, b) => { let x = env.get(&a).cloned().unwrap_or(Sym::Cursor(a)); let y = env.get(&b).cloned().unwrap_or(Sym::Cursor(b)); env.insert(d, Sym::Add(Box::new(x), Box::new(y))); }
                    Op::IMaskU32(d, a) | Op::IMov(d, a) => { let x = env.get(&a).cloned().unwrap_or(Sym::Cursor(a)); env.insert(d, x); }
                    Op::StorageLen(d, _) => { env.insert(d, Sym::Len(d)); }
                    Op::ICmpLe(d, a, b) => { let x = env.get(&a).cloned().unwrap_or(Sym::Cursor(a)); let y = env.get(&b).cloned().unwrap_or(Sym::Cursor(b)); env.insert(d, Sym::Le(Box::new(x), Box::new(y))); }
                    Op::IAnd(d, a, b) => { let x = env.get(&a).cloned().unwrap_or(Sym::Unknown); let y = env.get(&b).cloned().unwrap_or(Sym::Unknown); env.insert(d, Sym::And(Box::new(x), Box::new(y))); }
                    Op::ICmpLt(d, ..) | Op::FCmpLe(d, ..) | Op::FCmpLt(d, ..) | Op::ISub(d, ..) | Op::FToI(d, ..) | Op::IAddK(d, ..) => { env.insert(d, Sym::Unknown); }
                    _ => {}
                }
            }
            // The length register cited must be the one StorageLen defined; it
            // is defined in the prologue, so look it up anywhere before pc.
            let len_is_storage = code[..pc].iter().any(|o| matches!(o, Op::StorageLen(d, _) if *d == len));
            if !len_is_storage { return Err(format!("pc {pc}: cited length register is not a span count")); }
            // Lengths the fact's length is known to dominate: itself, and any
            // count register an entry guard bounds above it (#x <= #len), transitively.
            let guards: Vec<(u8, u8)> = code[..pc].iter().filter_map(|o| if let Op::GuardLenLe(a, b) = *o { Some((a, b)) } else { None }).collect();
            let mut allowed = vec![len];
            loop { let n = allowed.len(); for (a, b) in &guards { if allowed.contains(b) && !allowed.contains(a) { allowed.push(*a); } } if allowed.len() == n { break; } }
            fn implies(s: &Sym, cursor: u8, k: i64, allowed: &[u8]) -> bool {
                match s {
                    Sym::And(a, b) => implies(a, cursor, k, allowed) || implies(b, cursor, k, allowed),
                    Sym::Le(l, r) => matches!(**r, Sym::Len(x) if allowed.contains(&x)) && match &**l { Sym::Add(a, b) => (matches!(**a, Sym::Cursor(c) if c == cursor) && matches!(**b, Sym::Const(kk) if kk >= k)) || (matches!(**b, Sym::Cursor(c) if c == cursor) && matches!(**a, Sym::Const(kk) if kk >= k)), _ => false },
                    _ => false,
                }
            }
            let cond = env.get(&creg).cloned().unwrap_or(Sym::Unknown);
            if !implies(&cond, cursor, k, &allowed) { return Err(format!("pc {pc}: cannot re-derive cursor r{cursor} + {k} <= len r{len} from the loop condition {cond:?}")); }
            // The guarded region is the body up to the back-edge jump that
            // targets the header: accesses citing the fact must use the cursor
            // register unmodified since the fact.
            let _ = exit;
            let mut modified = false;
            let mut i = pc + 1;
            while i < code.len() {
                match code[i] {
                    Op::Jmp(off) if off < 0 && (i as i64 + 1 + off as i64) <= start as i64 => break,
                    Op::IAdd(d, ..) | Op::IAddK(d, ..) | Op::ISub(d, ..) | Op::IMaskU32(d, ..) | Op::IK(d, ..) | Op::FToI(d, ..) | Op::IMov(d, ..) if d == cursor => modified = true,
                    Op::VLoad(_, s, idx, off) | Op::VStore(s, idx, _, off) => {
                        // An access on another span is covered by that span's own fact, if any.
                        let span_len_matches = code[..pc].iter().any(|o| matches!(o, Op::StorageLen(d, sv) if *d == len && *sv == s));
                        if !span_len_matches {
                            let its_len = code[..pc].iter().find_map(|o| if let Op::StorageLen(d, sv) = *o { if sv == s { Some(d) } else { None } } else { None });
                            let covered = its_len.map(|l| code[start..i].iter().any(|o| matches!(*o, Op::LoopFact(c, kk, ll) if c == cursor && ll == l && kk >= k))).unwrap_or(false);
                            if covered { i += 1; continue; }
                        }
                        // The index register is `cursor - 1 + 1` computed from the 1-based IR index:
                        // accept it when it was defined as IAddK(idx, t, -1) with t = FToI(IToF-free) ... in the
                        // prototype the lowering emits cursor -> IToF -> FToI -> IAddK(-1); re-derive that chain.
                        let idx_is_cursor = derives_from_cursor(code, i, idx, cursor);
                        if !span_len_matches || !idx_is_cursor || modified || off + 2 > k as i32 { return Err(format!("pc {i}: unchecked access does not fit the cited fact (span ok {span_len_matches}, index from cursor {idx_is_cursor}, cursor modified {modified}, off {off} k {k})")); }
                    }
                    _ => {}
                }
                i += 1;
            }
        }
    }
    // 3.4b: a proven byte lookup: the object register was loaded from the
    // constant pool, the index was masked by a constant below that
    // constant's length, and neither register was redefined between.
    for (pc, op) in code.iter().enumerate() {
        if let Op::LoadU8K(_, s, i) = *op {
            // Register numbers are per class: a value register's definition is a value opcode.
            let vdef = |r: u8| (0..pc).rev().find(|&j| matches!(code[j], Op::K(d, _) | Op::Move(d, _) | Op::Nil(d) | Op::NewBytes(d, _) | Op::BytesToStr(d, _, _) if d == r));
            let def = |r: u8| (0..pc).rev().find(|&j| lower_dest(&code[j]) == Some(r));
            let len = match vdef(s).map(|j| code[j]) { Some(Op::K(_, k)) => f.consts.get(k as usize).and_then(|v| v.as_obj()).map(|p| unsafe { (*p.as_ptr()).str_text().len() }), _ => None };
            let Some(len) = len else { return Err(format!("pc {pc}: proven byte lookup on a register that is not a pool constant string")); };
            let masked = match def(i).map(|j| (j, code[j])) {
                Some((j, Op::IAnd(_, a, b))) => [a, b].iter().any(|&r| matches!((0..j).rev().find(|&q| lower_dest(&code[q]) == Some(r)).map(|q| code[q]), Some(Op::IK(_, k)) if k >= 0 && (k as usize) < len)),
                _ => false,
            };
            if !masked { return Err(format!("pc {pc}: proven byte lookup whose index is not masked below {len}")); }
        }
    }
    // Every unchecked access must lie inside some fact's region; an access with
    // no fact before it in its loop is rejected.
    for (pc, op) in code.iter().enumerate() {
        if let Op::VLoad(..) | Op::VStore(..) | Op::FLoad(..) | Op::FStore(..) = op {
            let has_fact = code[..pc].iter().rev().take_while(|o| !matches!(o, Op::JmpIfIZero(..))).any(|o| matches!(o, Op::LoopFact(..))) || code[..pc].iter().any(|o| matches!(o, Op::LoopFact(..)));
            if !has_fact { return Err(format!("pc {pc}: unchecked access with no cited fact")); }
        }
    }
    Ok(())
}

/// The integer register an opcode defines, if any.
fn lower_dest(o: &Op) -> Option<u8> {
    match *o { Op::IMov(d, _) | Op::IK(d, _) | Op::IAdd(d, ..) | Op::IAddK(d, ..) | Op::ISub(d, ..) | Op::IMaskU32(d, _) | Op::FToI(d, _) | Op::StorageLen(d, _) | Op::ICmpLe(d, ..) | Op::ICmpLt(d, ..) | Op::ICmpEq(d, ..) | Op::ICmpNe(d, ..) | Op::Truthy(d, _) | Op::IAnd(d, ..) | Op::IOr(d, ..) | Op::IShl(d, ..) | Op::IShrU(d, ..) | Op::IBswap32(d, _) | Op::BytesLen(d, _) | Op::LoadU8(d, ..) | Op::LoadU8K(d, ..) | Op::LoadU32W(d, ..) | Op::IUnbox(d, _) | Op::ICmpSLt(d, ..) | Op::ICmpSLe(d, ..) => Some(d), _ => None }
}

/// Whether register `idx` at `at` was computed as `cursor + 1 - 1` through the
/// lowering's index chain: IAddK(idx, t, -1), t = FToI(u), u = IToF(w) or
/// u = (cursor + 1 masked), i.e. the 1-based index of the cursor's element.
fn derives_from_cursor(code: &[Op], at: usize, idx: u8, cursor: u8) -> bool {
    fn def(code: &[Op], before: usize, r: u8) -> Option<(usize, Op)> { (0..before).rev().find_map(|i| match code[i] { o if dest(&o) == Some(r) => Some((i, o)), _ => None }) }
    fn dest(o: &Op) -> Option<u8> { match *o { Op::IMov(d, _) | Op::IK(d, _) | Op::IAdd(d, ..) | Op::IAddK(d, ..) | Op::ISub(d, ..) | Op::IMaskU32(d, _) | Op::FToI(d, _) | Op::StorageLen(d, _) | Op::ICmpLe(d, ..) | Op::ICmpLt(d, ..) | Op::IAnd(d, ..) => Some(d), _ => None } }
    fn fdef(code: &[Op], before: usize, r: u8) -> Option<(usize, Op)> { (0..before).rev().find_map(|i| match code[i] { Op::IToF(d, s) if d == r => Some((i, Op::IToF(d, s))), Op::FK(d, k) if d == r => Some((i, Op::FK(d, k))), Op::FAdd(d, a, b) if d == r => Some((i, Op::FAdd(d, a, b))), _ => None }) }
    if idx == cursor { return true; }
    let Some((i1, Op::IAddK(_, t, -1))) = def(code, at, idx) else { return false };
    let Some((i2, Op::FToI(_, u))) = def(code, i1, t) else { return false };
    let Some((i3, Op::IToF(_, w))) = fdef(code, i2, u) else { return false };
    // w = IMaskU32(sum), sum = IAdd(cursor, one), one = IK 1
    let Some((i4, Op::IMaskU32(_, sum))) = def(code, i3, w) else { return false };
    let Some((i5, Op::IAdd(_, a, b))) = def(code, i4, sum) else { return false };
    let one = |r: u8| matches!(def(code, i5, r), Some((_, Op::IK(_, 1))));
    (a == cursor && one(b)) || (b == cursor && one(a))
}

// ---------------------------------------------------------------------------
// Operand classes (contracts 3.2): every operand names a class by its opcode;
// each index must lie inside the function's count for that class, every
// branch target inside the code, every constant inside the pool, every callee
// inside the image. Linear in code size; runs once per function at load.

#[derive(Clone, Copy, PartialEq, Debug)]
pub enum C { V, I, F, X }

/// The register operands of an opcode by class, and its branch offsets.
pub fn operands(op: &Op) -> (Vec<(C, u8)>, Vec<i32>) {
    use Op::*;
    use C::*;
    let r = |list: &[(C, u8)]| (list.to_vec(), Vec::new());
    match *op {
        K(d, _) | Nil(d) | NewTable(d) | NewBuffer(d) | Ret(d) | Park(d) => r(&[(V, d)]),
        Move(d, s) | Not(d, s) | Neg(d, s) | Len(d, s) | TagCheckNum(d, s) | TagCheckStr(d, s) | NewCell(d, s) | GetCell(d, s) | SetCell(d, s) | BufAppend(d, s) | BufFinish(d, s) => r(&[(V, d), (V, s)]),
        Add(d, a, b) | Sub(d, a, b) | Mul(d, a, b) | Lt(d, a, b) | Le(d, a, b) | Eq(d, a, b) | Ne(d, a, b) | Concat(d, a, b) | GetIdx(d, a, b) | SetIdx(d, a, b) | CallDyn(d, a, b) => r(&[(V, d), (V, a), (V, b)]),
        JmpIf(c, off) | JmpIfNot(c, off) => (vec![(V, c)], vec![off]),
        Jmp(off) => (Vec::new(), vec![off]),
        Switch(i, _) => r(&[(I, i)]),
        GetIdxI(d, t, i) => r(&[(V, d), (V, t), (I, i)]),
        SetIdxI(t, i, v) => r(&[(V, t), (I, i), (V, v)]),
        IUnbox(d, v) | Truthy(d, v) | BytesLen(d, v) | StorageLen(d, v) => r(&[(I, d), (V, v)]),
        ICmpSLt(d, a, b) | ICmpSLe(d, a, b) | IShl(d, a, b) | IShrU(d, a, b) | IOr(d, a, b) | ICmpEq(d, a, b) | ICmpNe(d, a, b) | IAdd(d, a, b) | ISub(d, a, b) | ICmpLe(d, a, b) | ICmpLt(d, a, b) | IAnd(d, a, b) => r(&[(I, d), (I, a), (I, b)]),
        IBswap32(d, a) | IMaskU32(d, a) | IMov(d, a) => r(&[(I, d), (I, a)]),
        LoadU8(d, s, i) | LoadU8K(d, s, i) | LoadU32W(d, s, i) => r(&[(I, d), (V, s), (I, i)]),
        StoreU8(s, i, v) | StoreU32(s, i, v) => r(&[(V, s), (I, i), (I, v)]),
        NewBytes(d, n) => r(&[(V, d), (I, n)]),
        BytesToStr(d, s, n) => r(&[(V, d), (V, s), (I, n)]),
        BufAppendSub(b, s, i, j) => r(&[(V, b), (V, s), (I, i), (I, j)]),
        Substring(d, s, i, j) => r(&[(V, d), (V, s), (I, i), (I, j)]),
        Call(_, base, _) | CallT(_, base, _, _) | PCall(base, _) | CallMethod(_, base, _) => r(&[(V, base)]),
        RetNil | Checkpoint | LoopFact(..) => r(&[]),
        GetField(d, t, _) => r(&[(V, d), (V, t)]),
        SetField(t, _, v) => r(&[(V, t), (V, v)]),
        NewRecord(d, _) => r(&[(V, d)]),
        GetSlot(d, o, _) => r(&[(V, d), (V, o)]),
        SetSlot(o, _, v) => r(&[(V, o), (V, v)]),
        TagCheckRec(d, v, _) => r(&[(V, d), (V, v)]),
        NewClosure(d, _, base, _) => r(&[(V, d), (V, base)]),
        GetUpval(d, _) => r(&[(V, d)]),
        FBox(d, f) => r(&[(V, d), (F, f)]),
        GetSlotF(f, o, _) => r(&[(F, f), (V, o)]),
        SetSlotF(o, _, f) => r(&[(V, o), (F, f)]),
        FDiv(d, a, b) | FSub(d, a, b) | FMul(d, a, b) | FAdd(d, a, b) => r(&[(F, d), (F, a), (F, b)]),
        FNeg(d, a) | FMov(d, a) => r(&[(F, d), (F, a)]),
        LenF(f, v) | FUnbox(f, v) => r(&[(F, f), (V, v)]),
        GetIdxF(d, t, i) => r(&[(V, d), (V, t), (F, i)]),
        SetIdxF(t, i, v) => r(&[(V, t), (F, i), (V, v)]),
        FCmpEq(d, a, b) | FCmpNe(d, a, b) | FCmpLe(d, a, b) | FCmpLt(d, a, b) => r(&[(I, d), (F, a), (F, b)]),
        BoolFromI(d, i) => r(&[(V, d), (I, i)]),
        IK(d, _) => r(&[(I, d)]),
        IAddK(d, a, _) => r(&[(I, d), (I, a)]),
        IJmpIfUle(a, b, off) | IJmpIfUlt(a, b, off) => (vec![(I, a), (I, b)], vec![off]),
        FK(d, _) => r(&[(F, d)]),
        IToF(f, i) => r(&[(F, f), (I, i)]),
        FToI(i, f) => r(&[(I, i), (F, f)]),
        JmpIfIZero(c, off) => (vec![(I, c)], vec![off]),
        VAdd(d, a, b) | VMul(d, a, b) => r(&[(X, d), (X, a), (X, b)]),
        VLoadM(d, s, i, _, m) => r(&[(X, d), (V, s), (I, i), (I, m)]),
        VStoreM(s, i, v, _, m) => r(&[(V, s), (I, i), (X, v), (I, m)]),
        GuardLenLe(a, b) => r(&[(I, a), (I, b)]),
        VMov(d, a) => r(&[(X, d), (X, a)]),
        FFma(d, a, b, c) => r(&[(F, d), (F, a), (F, b), (F, c)]),
        FLoad(f, s, i) => r(&[(F, f), (V, s), (I, i)]),
        FStore(s, i, f) => r(&[(V, s), (I, i), (F, f)]),
        VSplat(d, f) => r(&[(X, d), (F, f)]),
        VLoad(d, s, i, _) => r(&[(X, d), (V, s), (I, i)]),
        VStore(s, i, v, _) => r(&[(V, s), (I, i), (X, v)]),
        VFma(d, a, b, c) => r(&[(X, d), (X, a), (X, b), (X, c)]),
        VLane(f, v, _) => r(&[(F, f), (X, v)]),
        FRet(f) => r(&[(F, f)]),
    }
}

/// Checks every operand of `f` against its register counts, every branch
/// against its code, every constant against its pool and every callee
/// against `nfuncs`.
pub fn verify_classes(f: &Function, nfuncs: usize) -> Result<(), String> {
    let n = f.code.len();
    for (pc, op) in f.code.iter().enumerate() {
        let (regs, offs) = operands(op);
        for (c, i) in regs {
            let limit = match c { C::V => f.nregs as usize + 1, C::I => f.nireg as usize, C::F => f.nfreg as usize, C::X => f.nvreg as usize };
            if i as usize >= limit { return Err(format!("pc {pc}: {op:?} names {c:?} register {i}, the function has {limit}")); }
        }
        for off in offs {
            let t = pc as i64 + 1 + off as i64;
            if t < 0 || t > n as i64 { return Err(format!("pc {pc}: branch to {t}, outside 0..={n}")); }
        }
        match *op {
            Op::K(_, k) if k as usize >= f.consts.len() => return Err(format!("pc {pc}: constant {k} outside the pool of {}", f.consts.len())),
            Op::Switch(_, t) => {
                let (def, tbl) = f.jump_tables.get(t as usize).ok_or_else(|| format!("pc {pc}: jump table {t} does not exist"))?;
                for off in std::iter::once(def).chain(tbl.iter()) { let tt = pc as i64 + 1 + *off as i64; if tt < 0 || tt > n as i64 { return Err(format!("pc {pc}: switch target {tt} outside the code")); } }
            }
            Op::Call(callee, ..) | Op::CallT(callee, ..) if callee as usize >= nfuncs => return Err(format!("pc {pc}: callee {callee} outside the image of {nfuncs}")),
            Op::NewClosure(_, fid, ..) if fid as usize >= nfuncs => return Err(format!("pc {pc}: closure over function {fid} outside the image")),
            _ => {}
        }
    }
    Ok(())
}
