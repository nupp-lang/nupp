//! A register interpreter with heap frame stacks, tasks that park and resume,
//! an untyped tier over NaN-boxed values and a typed tier over unboxed
//! integer, float and two-lane vector registers.

use crate::heap::{Body, Heap, Roots, SlotTy, Value};
use std::ptr::NonNull;

#[derive(Clone, Copy, Debug)]
pub enum Op {
    // Untyped tier. Operands are register indices in the frame's window.
    K(u8, u16),
    Move(u8, u8),
    Nil(u8),
    Add(u8, u8, u8),
    Sub(u8, u8, u8),
    Mul(u8, u8, u8),
    Lt(u8, u8, u8),
    Le(u8, u8, u8),
    Eq(u8, u8, u8),
    Jmp(i32),
    JmpIf(u8, i32),
    JmpIfNot(u8, i32),
    /// Call function `fid` with arguments at base+1.., result into `base`.
    Call(u32, u8, u8),
    CallDyn(u8, u8, u8),
    Ret(u8),
    RetNil,
    NewTable(u8),
    GetIdx(u8, u8, u8),
    SetIdx(u8, u8, u8),
    /// Field by name (constant index), the untyped path with the enforced write.
    GetField(u8, u8, u16),
    SetField(u8, u16, u8),
    NewRecord(u8, u32),
    /// Slot by offset, the typed path: no check on read or write.
    GetSlot(u8, u8, u16),
    SetSlot(u8, u16, u8),
    Park(u8),
    Checkpoint,
    Ne(u8, u8, u8),
    Concat(u8, u8, u8),
    Not(u8, u8),
    Neg(u8, u8),
    Len(u8, u8),
    /// Dynamic dispatch: method name (constant) looked up in the receiver's shape.
    CallMethod(u16, u8, u8),
    /// pcall: callee at base+1, arguments after; results ok at base, value at base+1.
    PCall(u8, u8),
    TagCheckRec(u8, u8, u32),
    TagCheckNum(u8, u8),
    TagCheckStr(u8, u8),
    FBox(u8, u8),
    GetSlotF(u8, u8, u16),
    SetSlotF(u8, u16, u8),
    FDiv(u8, u8, u8),
    FNeg(u8, u8),
    LenF(u8, u8),
    /// Table read with a float index into a value register.
    GetIdxF(u8, u8, u8),
    FCmpEq(u8, u8, u8),
    FCmpNe(u8, u8, u8),
    BoolFromI(u8, u8),
    // Typed tier: i = integer registers, f = float registers, v = f64x2 registers.
    IK(u8, i64),
    IAdd(u8, u8, u8),
    IAddK(u8, u8, i64),
    IJmpIfUle(u8, u8, i32),
    IJmpIfUlt(u8, u8, i32),
    FK(u8, f64),
    /// Unbox a number from a value register into a float register.
    FUnbox(u8, u8),
    ISub(u8, u8, u8),
    /// Wrap an integer register to 32 bits.
    IMaskU32(u8, u8),
    IToF(u8, u8),
    /// Truncating conversion of a float register to an integer register.
    FToI(u8, u8),
    FSub(u8, u8, u8),
    FMul(u8, u8, u8),
    /// Unsigned comparisons into an integer register holding 0 or 1.
    ICmpLe(u8, u8, u8),
    ICmpLt(u8, u8, u8),
    FCmpLe(u8, u8, u8),
    FCmpLt(u8, u8, u8),
    IAnd(u8, u8, u8),
    JmpIfIZero(u8, i32),
    VAdd(u8, u8, u8),
    VMul(u8, u8, u8),
    /// Masked two-lane load: lanes at `off + l` below `active` are loaded,
    /// the rest are zero; every loaded lane is bounds-checked.
    VLoadM(u8, u8, u8, i32, u8),
    VStoreM(u8, u8, u8, i32, u8),
    /// A cited loop fact: `cursor + k <= len` holds here, established by the
    /// branch that guards the loop body. The verifier re-derives it; the
    /// interpreter and JIT ignore it.
    LoopFact(u8, i64, u8),
    /// An entry guard: count register a <= count register b, or the call is refused.
    GuardLenLe(u8, u8),
    IMov(u8, u8),
    FMov(u8, u8),
    VMov(u8, u8),
    FAdd(u8, u8, u8),
    FFma(u8, u8, u8, u8),
    StorageLen(u8, u8),
    FLoad(u8, u8, u8),
    FStore(u8, u8, u8),
    VSplat(u8, u8),
    VLoad(u8, u8, u8, i32),
    VStore(u8, u8, u8, i32),
    VFma(u8, u8, u8, u8),
    VLane(u8, u8, u8),
    FRet(u8),
}

pub struct Function {
    pub name: &'static str,
    pub code: Vec<Op>,
    pub consts: Vec<Value>,
    pub nparams: u8,
    pub nregs: u8,
    pub nireg: u8,
    pub nfreg: u8,
    pub nvreg: u8,
}

#[derive(Clone, Copy)]
struct Frame { func: u32, pc: u32, base: u32, ibase: u32, fbase: u32, vbase: u32, ret: u32 }

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum State { Runnable, Parked(u64), Done }

pub struct Task {
    pub regs: Vec<Value>,
    iregs: Vec<i64>,
    fregs: Vec<f64>,
    vregs: Vec<[f64; 2]>,
    frames: Vec<Frame>,
    pub state: State,
    pub result: Value,
}

pub struct Interp {
    pub heap: Heap,
    pub funcs: Vec<Function>,
    pub tasks: Vec<Task>,
    pub handles: Vec<Value>,
    back_edges: u32,
    pub parks: u64,
    pub trace: bool,
    /// Compiled entry per function id, when the JIT has one.
    pub compiled: Vec<Option<*const u8>>,
    pub entry2: Option<u32>,
}

struct TaskRoots<'a> { tasks: &'a [Task], funcs: &'a [Function], handles: &'a [Value] }
impl Roots for TaskRoots<'_> {
    fn each_root(&self, f: &mut dyn FnMut(Value)) {
        for t in self.tasks { for &v in &t.regs { f(v); } f(t.result); }
        for fun in self.funcs { for &k in &fun.consts { f(k); } }
        for &v in self.handles { f(v); }
    }
}

#[derive(Debug)]
pub enum Outcome { Done(Value), Parked(u64) }

macro_rules! roots { ($self:ident) => { &TaskRoots { tasks: &$self.tasks, funcs: &$self.funcs, handles: &$self.handles } } }

impl Interp {
    pub fn new() -> Interp { Interp { heap: Heap::new(), funcs: Vec::new(), tasks: Vec::new(), handles: Vec::new(), back_edges: 0, parks: 0, trace: std::env::var("TRACE_OPS").is_ok(), compiled: Vec::new(), entry2: None } }

    pub fn intern(&mut self, s: &str) -> Value { let r = TaskRoots { tasks: &self.tasks, funcs: &self.funcs, handles: &self.handles }; self.heap.intern(s, &r) }

    pub fn spawn(&mut self, fid: u32, args: &[Value]) -> usize {
        let f = &self.funcs[fid as usize];
        let mut t = Task { regs: vec![Value::NIL; f.nregs as usize + 1], iregs: vec![0; f.nireg as usize], fregs: vec![0.0; f.nfreg as usize], vregs: vec![[0.0; 2]; f.nvreg as usize], frames: Vec::new(), state: State::Runnable, result: Value::NIL };
        for (i, &a) in args.iter().enumerate() { t.regs[i + 1] = a; }
        t.frames.push(Frame { func: fid, pc: 0, base: 0, ibase: 0, fbase: 0, vbase: 0, ret: 0 });
        self.tasks.push(t);
        self.tasks.len() - 1
    }

    pub fn resume(&mut self, tid: usize) { self.tasks[tid].state = State::Runnable; }
    pub fn new_record(&mut self, shape: u32) -> Value { self.heap.new_record(shape, roots!(self)) }
    pub fn new_storage(&mut self, n: usize) -> Value { self.heap.new_storage(n, roots!(self)) }
    pub fn full_cycle(&mut self) { self.heap.full_cycle(roots!(self)) }
    pub fn new_table(&mut self) -> Value { self.heap.new_table(roots!(self)) }
    pub fn set_slot(&mut self, rec: Value, i: usize, v: Value) { let p = rec.as_obj().unwrap(); self.heap.barrier(p, v); unsafe { if let Body::Record { slots, .. } = &mut (*p.as_ptr()).body { slots[i] = v } } }
    pub fn get_slot(&self, rec: Value, i: usize) -> Value { let p = rec.as_obj().unwrap(); unsafe { match &(*p.as_ptr()).body { Body::Record { slots, .. } => slots[i], _ => panic!("use after free or not a record") } } }
    pub fn push_array(&mut self, t: Value, v: Value) { let p = t.as_obj().unwrap(); self.heap.barrier(p, v); unsafe { if let Body::Table { array, .. } = &mut (*p.as_ptr()).body { array.push(v) } (*p.as_ptr()).refresh(); } }
    pub fn array_get(&self, t: Value, i: usize) -> Value { let p = t.as_obj().unwrap(); unsafe { match &(*p.as_ptr()).body { Body::Table { array, .. } => array[i], _ => panic!("not a table") } } }
    pub fn check_oracle(&self) { self.heap.check_oracle(roots!(self)) }

    fn err(&self, msg: &str) -> ! { panic!("runtime error: {msg}") }

    fn arith(&self, a: Value, b: Value, op: fn(f64, f64) -> f64) -> Value {
        if a.is_num() && b.is_num() { Value::num(op(a.as_num(), b.as_num())) } else { self.err("arithmetic on a non-number") }
    }

    fn slot_type_ok(&self, ty: SlotTy, v: Value) -> bool {
        match ty {
            SlotTy::Any => true,
            SlotTy::Num => v.is_num(),
            SlotTy::Bool => v == Value::TRUE || v == Value::FALSE,
            SlotTy::Str => v.as_obj().map(|p| unsafe { matches!((*p.as_ptr()).body, Body::Str { .. }) }).unwrap_or(false),
            SlotTy::Record(s) => v.as_obj().map(|p| unsafe { matches!((*p.as_ptr()).body, Body::Record { shape, .. } if shape == s) }).unwrap_or(false),
        }
    }

    /// Run task `tid` until it finishes or parks.
    pub fn run(&mut self, tid: usize) -> Outcome {
        assert_eq!(self.tasks[tid].state, State::Runnable);
        loop {
            let frame = *self.tasks[tid].frames.last().unwrap();
            let (fid, mut pc, base, ibase, fbase, vbase) = (frame.func, frame.pc as usize, frame.base as usize, frame.ibase as usize, frame.fbase as usize, frame.vbase as usize);
            let code: *const Op = self.funcs[fid as usize].code.as_ptr();
            let ncode = self.funcs[fid as usize].code.len();
            let consts: *const Value = self.funcs[fid as usize].consts.as_ptr();
            // The register windows as raw pointers for the duration of this
            // activation. Every op that can grow the register stacks (a call)
            // leaves the inner loop, so the pointers are re-derived after it.
            let regs: *mut Value = unsafe { self.tasks[tid].regs.as_mut_ptr().add(base) };
            let iregs: *mut i64 = unsafe { self.tasks[tid].iregs.as_mut_ptr().add(ibase) };
            let fregs: *mut f64 = unsafe { self.tasks[tid].fregs.as_mut_ptr().add(fbase) };
            let vregs: *mut [f64; 2] = unsafe { self.tasks[tid].vregs.as_mut_ptr().add(vbase) };
            macro_rules! r { ($i:expr) => { (*unsafe { &mut *regs.add($i as usize) }) } }
            macro_rules! ir { ($i:expr) => { (*unsafe { &mut *iregs.add($i as usize) }) } }
            macro_rules! fr { ($i:expr) => { (*unsafe { &mut *fregs.add($i as usize) }) } }
            macro_rules! vr { ($i:expr) => { (*unsafe { &mut *vregs.add($i as usize) }) } }
            macro_rules! storage { ($i:expr) => {{
                let v = r!($i);
                match v.as_obj() { Some(p) => unsafe { match &mut (*p.as_ptr()).body { Body::Storage { data } => data, _ => self.err("not storage") } }, None => self.err("not storage") }
            }} }
            loop {
                debug_assert!(pc < ncode);
                let op = unsafe { *code.add(pc) };
                if self.trace { eprintln!("  {}:{} {:?}", self.funcs[fid as usize].name, pc, op); }
                pc += 1;
                match op {
                    Op::K(d, k) => r!(d) = unsafe { *consts.add(k as usize) },
                    Op::Move(d, s) => r!(d) = r!(s),
                    Op::Nil(d) => r!(d) = Value::NIL,
                    Op::Add(d, a, b) => { let (x, y) = (r!(a), r!(b)); r!(d) = if x.is_num() && y.is_num() { Value::num(x.as_num() + y.as_num()) } else { self.arith(x, y, |p, q| p + q) } }
                    Op::Sub(d, a, b) => { let (x, y) = (r!(a), r!(b)); r!(d) = if x.is_num() && y.is_num() { Value::num(x.as_num() - y.as_num()) } else { self.arith(x, y, |p, q| p - q) } }
                    Op::Mul(d, a, b) => { let (x, y) = (r!(a), r!(b)); r!(d) = self.arith(x, y, |p, q| p * q) }
                    Op::Lt(d, a, b) => { let (x, y) = (r!(a), r!(b)); if !(x.is_num() && y.is_num()) { self.err("compare") } r!(d) = Value::boolean(x.as_num() < y.as_num()) }
                    Op::Le(d, a, b) => { let (x, y) = (r!(a), r!(b)); if !(x.is_num() && y.is_num()) { self.err("compare") } r!(d) = Value::boolean(x.as_num() <= y.as_num()) }
                    Op::Eq(d, a, b) => { let (x, y) = (r!(a), r!(b)); r!(d) = Value::boolean(x == y) }
                    Op::Jmp(off) => { pc = (pc as i64 + off as i64) as usize; if off < 0 { self.back_edge(); } }
                    Op::JmpIf(c, off) => if r!(c).truthy() { pc = (pc as i64 + off as i64) as usize; if off < 0 { self.back_edge(); } },
                    Op::JmpIfNot(c, off) => if !r!(c).truthy() { pc = (pc as i64 + off as i64) as usize; if off < 0 { self.back_edge(); } },
                    Op::Call(f, b, nargs) => {
                        if let Some(Some(entry)) = self.compiled.get(f as usize) {
                            // The handoff: arguments marshalled from the register window
                            // as values, the compiled callee called through a per-arity
                            // trampoline, the result landing where the window began.
                            let entry = *entry;
                            let args: [u64; 4] = std::array::from_fn(|i| if i < nargs as usize { r!(b + 1 + i as u8).0 } else { 0 });
                            let result = unsafe { match nargs { 0 => std::mem::transmute::<_, extern "C" fn() -> u64>(entry)(), 1 => std::mem::transmute::<_, extern "C" fn(u64) -> u64>(entry)(args[0]), 2 => std::mem::transmute::<_, extern "C" fn(u64, u64) -> u64>(entry)(args[0], args[1]), 3 => std::mem::transmute::<_, extern "C" fn(u64, u64, u64) -> u64>(entry)(args[0], args[1], args[2]), _ => std::mem::transmute::<_, extern "C" fn(u64, u64, u64, u64) -> u64>(entry)(args[0], args[1], args[2], args[3]) } };
                            r!(b) = Value(result);
                            continue;
                        }
                        self.push_frame(tid, f, base + b as usize, nargs, pc, fid, base, ibase, fbase, vbase, base + b as usize); break;
                    }
                    Op::CallDyn(fr, b, nargs) => { let f = r!(fr).as_func().unwrap_or_else(|| self.err("call of a non-function")); self.push_frame(tid, f, base + b as usize, nargs, pc, fid, base, ibase, fbase, vbase, base + b as usize); break; }
                    Op::Ret(s) => { let v = r!(s); if self.pop_frame(tid, v) { return Outcome::Done(v); } break; }
                    Op::RetNil => { if self.pop_frame(tid, Value::NIL) { return Outcome::Done(Value::NIL); } break; }
                    Op::NewTable(d) => { let v = self.heap.new_table(roots!(self)); r!(d) = v; }
                    Op::GetIdx(d, t, i) => {
                        let (tv, iv) = (r!(t), r!(i));
                        let p = tv.as_obj().unwrap_or_else(|| self.err("index of a non-table"));
                        let v = unsafe { match &(*p.as_ptr()).body {
                            Body::Table { array, hash } => { if iv.is_num() { let k = iv.as_num(); if k >= 1.0 && (k as usize) <= array.len() && k.fract() == 0.0 { array[k as usize - 1] } else { *hash.get(&iv).unwrap_or(&Value::NIL) } } else { *hash.get(&iv).unwrap_or(&Value::NIL) } }
                            _ => self.err("index of a non-table"),
                        } };
                        r!(d) = v;
                    }
                    Op::SetIdx(t, i, s) => {
                        let (tv, iv, v) = (r!(t), r!(i), r!(s));
                        let p = tv.as_obj().unwrap_or_else(|| self.err("index of a non-table"));
                        self.heap.barrier(p, iv);
                        self.heap.barrier(p, v);
                        unsafe { match &mut (*p.as_ptr()).body {
                            Body::Table { array, hash } => { if iv.is_num() && iv.as_num() >= 1.0 && iv.as_num().fract() == 0.0 && (iv.as_num() as usize) <= array.len() + 1 { let k = iv.as_num() as usize; if k == array.len() + 1 { array.push(v) } else { array[k - 1] = v } } else { hash.insert(iv, v); } }
                            _ => self.err("index of a non-table"),
                        } (*p.as_ptr()).refresh(); }
                    }
                    Op::GetField(d, t, k) => {
                        let name = unsafe { *consts.add(k as usize) };
                        let p = r!(t).as_obj().unwrap_or_else(|| self.err("field of a non-object"));
                        let v = unsafe { match &(*p.as_ptr()).body {
                            Body::Table { hash, .. } => *hash.get(&name).unwrap_or(&Value::NIL),
                            Body::Record { shape, slots } => { let sh = &self.heap.shapes[*shape as usize]; match sh.names.iter().position(|&n| n == name) { Some(i) => slots[i], None => self.err("no such field") } }
                            _ => self.err("field of a non-object"),
                        } };
                        r!(d) = v;
                    }
                    Op::SetField(t, k, s) => {
                        let name = unsafe { *consts.add(k as usize) };
                        let v = r!(s);
                        let p = r!(t).as_obj().unwrap_or_else(|| self.err("field of a non-object"));
                        self.heap.barrier(p, v);
                        unsafe { match &mut (*p.as_ptr()).body {
                            Body::Table { hash, .. } => { hash.insert(name, v); }
                            Body::Record { shape, slots } => {
                                // The enforced write: an untyped store into a record checks
                                // the slot's declared type, so typed reads never check.
                                let sh = &self.heap.shapes[*shape as usize];
                                let i = sh.names.iter().position(|&n| n == name).unwrap_or_else(|| self.err("record has no such field"));
                                if !self.slot_type_ok(sh.types[i], v) { self.err("value does not match the field's declared type") }
                                slots[i] = v;
                            }
                            _ => self.err("field of a non-object"),
                        } }
                    }
                    Op::NewRecord(d, shape) => { let v = self.heap.new_record(shape, roots!(self)); r!(d) = v; }
                    Op::GetSlot(d, t, i) => { let p = r!(t).as_obj().unwrap_or_else(|| self.err("slot of a non-record")); r!(d) = unsafe { match &(*p.as_ptr()).body { Body::Record { slots, .. } => *slots.get_unchecked(i as usize), Body::Freed(_) => self.err("use after free"), _ => self.err("slot of a non-record") } }; }
                    Op::SetSlot(t, i, s) => { let v = r!(s); let p = r!(t).as_obj().unwrap_or_else(|| self.err("slot of a non-record")); self.heap.barrier(p, v); unsafe { match &mut (*p.as_ptr()).body { Body::Record { slots, .. } => *slots.get_unchecked_mut(i as usize) = v, Body::Freed(_) => self.err("use after free"), _ => self.err("slot of a non-record") } } }
                    Op::Ne(d, a, b) => { let (x, y) = (r!(a), r!(b)); r!(d) = Value::boolean(x != y) }
                    Op::Not(d, a) => r!(d) = Value::boolean(!r!(a).truthy()),
                    Op::Neg(d, a) => { let x = r!(a); if !x.is_num() { self.err("negate a non-number") } r!(d) = Value::num(-x.as_num()) }
                    Op::Len(d, a) => { let p = r!(a).as_obj().unwrap_or_else(|| self.err("length of a non-object")); let n = unsafe { match &(*p.as_ptr()).body { Body::Table { array, .. } => array.len(), Body::Str { text, .. } => text.len(), _ => self.err("length of a non-object") } }; r!(d) = Value::num(n as f64) }
                    Op::Concat(d, a, b) => {
                        let (x, y) = (r!(a), r!(b));
                        let text = |v: Value| -> String { if v.is_num() { let n = v.as_num(); if n.fract() == 0.0 && n.abs() < 1e15 { format!("{}", n as i64) } else { format!("{}", n) } } else { match v.as_obj() { Some(p) => unsafe { (*p.as_ptr()).str_text().to_string() }, None => self.err("concatenate a non-string") } } };
                    let joined = text(x) + &text(y);
                        let v = self.heap.intern(&joined, roots!(self));
                        r!(d) = v;
                    }
                    Op::CallMethod(k, b, nargs) => {
                        let name = unsafe { *consts.add(k as usize) };
                        let recv = r!(b + 1);
                        let p = recv.as_obj().unwrap_or_else(|| self.err("method call on a non-object"));
                        let fid = unsafe { match &(*p.as_ptr()).body { Body::Record { shape, .. } => *self.heap.shapes[*shape as usize].methods.get(&name).unwrap_or_else(|| self.err("no such method")), _ => self.err("method call on a non-record") } };
                        self.push_frame(tid, fid, base + b as usize, nargs, pc, fid, base, ibase, fbase, vbase, base + b as usize); break;
                    }
                    Op::PCall(b, nargs) => {
                        // The callee runs on a scratch task so an error unwinds only it.
                        let callee = r!(b + 1).as_func().unwrap_or_else(|| self.err("pcall of a non-function"));
                        let args: Vec<Value> = (0..nargs as usize).map(|i| r!(b + 2 + i as u8)).collect();
                        let scratch = self.spawn(callee, &args);
                        let hook = std::panic::take_hook();
                        std::panic::set_hook(Box::new(|_| {}));
                        let outcome = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| self.run(scratch)));
                        std::panic::set_hook(hook);
                        self.tasks.truncate(scratch);
                        match outcome {
                            Ok(Outcome::Done(v)) => { r!(b) = Value::TRUE; r!(b + 1) = v; }
                            Ok(Outcome::Parked(_)) => self.err("pcall body parked"),
                            Err(payload) => { let msg = payload.downcast_ref::<String>().cloned().or_else(|| payload.downcast_ref::<&str>().map(|s| s.to_string())).unwrap_or_default(); let m = self.heap.intern(&msg, roots!(self)); r!(b) = Value::FALSE; r!(b + 1) = m; }
                        }
                    }
                    Op::TagCheckRec(d, a, shape) => { let v = r!(a); let ok = v.as_obj().map(|p| unsafe { matches!((*p.as_ptr()).body, Body::Record { shape: s, .. } if s == shape) }).unwrap_or(false); if !ok { self.err("value is not an instance of the expected record") } r!(d) = v; }
                    Op::TagCheckNum(d, a) => { let v = r!(a); if !v.is_num() { self.err("value is not a number") } r!(d) = v; }
                    Op::TagCheckStr(d, a) => { let v = r!(a); if !v.as_obj().map(|p| unsafe { matches!((*p.as_ptr()).body, Body::Str { .. }) }).unwrap_or(false) { self.err("value is not a string") } r!(d) = v; }
                    Op::FBox(d, a) => r!(d) = Value::num(fr!(a)),
                    Op::GetSlotF(d, t, i) => { let p = r!(t).as_obj().unwrap_or_else(|| self.err("slot of a non-record")); let v = unsafe { match &(*p.as_ptr()).body { Body::Record { slots, .. } => *slots.get_unchecked(i as usize), _ => self.err("slot of a non-record") } }; fr!(d) = v.as_num(); }
                    Op::SetSlotF(t, i, a) => { let p = r!(t).as_obj().unwrap_or_else(|| self.err("slot of a non-record")); let v = Value::num(fr!(a)); unsafe { match &mut (*p.as_ptr()).body { Body::Record { slots, .. } => *slots.get_unchecked_mut(i as usize) = v, _ => self.err("slot of a non-record") } } }
                    Op::FDiv(d, a, b) => fr!(d) = fr!(a) / fr!(b),
                    Op::FNeg(d, a) => fr!(d) = -fr!(a),
                    Op::LenF(d, a) => { let p = r!(a).as_obj().unwrap_or_else(|| self.err("length of a non-object")); let n = unsafe { match &(*p.as_ptr()).body { Body::Table { array, .. } => array.len(), Body::Str { text, .. } => text.len(), _ => self.err("length of a non-object") } }; fr!(d) = n as f64; }
                    Op::GetIdxF(d, t, i) => { let p = r!(t).as_obj().unwrap_or_else(|| self.err("index of a non-table")); let k = fr!(i); let v = unsafe { match &(*p.as_ptr()).body { Body::Table { array, hash } => { if k >= 1.0 && (k as usize) <= array.len() && k.fract() == 0.0 { array[k as usize - 1] } else { *hash.get(&Value::num(k)).unwrap_or(&Value::NIL) } } _ => self.err("index of a non-table") } }; r!(d) = v; }
                    Op::FCmpEq(d, a, b) => ir!(d) = (fr!(a) == fr!(b)) as i64,
                    Op::FCmpNe(d, a, b) => ir!(d) = (fr!(a) != fr!(b)) as i64,
                    Op::BoolFromI(d, a) => r!(d) = Value::boolean(ir!(a) != 0),
                    Op::Park(k) => { let key = r!(k).0; self.parks += 1; let t = &mut self.tasks[tid]; t.frames.last_mut().unwrap().pc = pc as u32; t.state = State::Parked(key); return Outcome::Parked(key); }
                    Op::Checkpoint => { self.back_edge(); }
                    Op::IK(d, k) => ir!(d) = k,
                    Op::IAdd(d, a, b) => ir!(d) = ir!(a).wrapping_add(ir!(b)),
                    Op::IAddK(d, a, k) => ir!(d) = ir!(a).wrapping_add(k),
                    Op::IJmpIfUle(a, b, off) => if (ir!(a) as u64) <= (ir!(b) as u64) { pc = (pc as i64 + off as i64) as usize; if off < 0 { self.back_edge(); } },
                    Op::IJmpIfUlt(a, b, off) => if (ir!(a) as u64) < (ir!(b) as u64) { pc = (pc as i64 + off as i64) as usize; if off < 0 { self.back_edge(); } },
                    Op::FK(d, k) => fr!(d) = k,
                    Op::ISub(d, a, b) => ir!(d) = ir!(a).wrapping_sub(ir!(b)),
                    Op::IMaskU32(d, a) => ir!(d) = ir!(a) & 0xffff_ffff,
                    Op::IToF(d, a) => fr!(d) = ir!(a) as f64,
                    Op::FToI(d, a) => ir!(d) = fr!(a) as i64,
                    Op::FSub(d, a, b) => fr!(d) = fr!(a) - fr!(b),
                    Op::FMul(d, a, b) => fr!(d) = fr!(a) * fr!(b),
                    Op::ICmpLe(d, a, b) => ir!(d) = ((ir!(a) as u64) <= (ir!(b) as u64)) as i64,
                    Op::ICmpLt(d, a, b) => ir!(d) = ((ir!(a) as u64) < (ir!(b) as u64)) as i64,
                    Op::FCmpLe(d, a, b) => ir!(d) = (fr!(a) <= fr!(b)) as i64,
                    Op::FCmpLt(d, a, b) => ir!(d) = (fr!(a) < fr!(b)) as i64,
                    Op::IAnd(d, a, b) => ir!(d) = ir!(a) & ir!(b),
                    Op::JmpIfIZero(c, off) => if ir!(c) == 0 { pc = (pc as i64 + off as i64) as usize; if off < 0 { self.back_edge(); } },
                    Op::VAdd(d, a, b) => { let (x, y) = (vr!(a), vr!(b)); vr!(d) = [x[0] + y[0], x[1] + y[1]]; }
                    Op::VMul(d, a, b) => { let (x, y) = (vr!(a), vr!(b)); vr!(d) = [x[0] * y[0], x[1] * y[1]]; }
                    Op::VLoadM(d, s, i, off, active) => {
                        let base = ir!(i) + off as i64; let act = ir!(active) - off as i64; let st = storage!(s);
                        let mut v = [0.0; 2];
                        for l in 0..2i64 { if l < act { let k = (base + l) as usize; if k >= st.len() { self.err("masked load out of bounds") } v[l as usize] = st[k]; } }
                        vr!(d) = v;
                    }
                    Op::VStoreM(s, i, v, off, active) => {
                        let base = ir!(i) + off as i64; let act = ir!(active) - off as i64; let x = vr!(v); let st = storage!(s);
                        for l in 0..2i64 { if l < act { let k = (base + l) as usize; if k >= st.len() { self.err("masked store out of bounds") } st[k] = x[l as usize]; } }
                    }
                    Op::LoopFact(..) => {}
                    Op::IMov(d, a) => ir!(d) = ir!(a),
                    Op::FMov(d, a) => fr!(d) = fr!(a),
                    Op::VMov(d, a) => vr!(d) = vr!(a),
                    Op::GuardLenLe(a, b) => if (ir!(a) as u64) > (ir!(b) as u64) { self.err("native spans have incompatible lengths") },
                    Op::FUnbox(d, r) => { let v = r!(r); if !v.is_num() { self.err("not a number") } fr!(d) = v.as_num(); }
                    Op::FAdd(d, a, b) => fr!(d) = fr!(a) + fr!(b),
                    Op::FFma(d, a, b, c) => fr!(d) = fr!(a).mul_add(fr!(b), fr!(c)),
                    Op::StorageLen(d, s) => { let n = storage!(s).len() as i64; ir!(d) = n; }
                    Op::FLoad(d, s, i) => { let idx = ir!(i) as usize; let x = storage!(s)[idx]; fr!(d) = x; }
                    Op::FStore(s, i, f) => { let idx = ir!(i) as usize; let x = fr!(f); storage!(s)[idx] = x; }
                    Op::VSplat(d, f) => { let x = fr!(f); vr!(d) = [x, x]; }
                    Op::VLoad(d, s, i, off) => { let idx = (ir!(i) + off as i64) as usize; let st = storage!(s); let v = [st[idx], st[idx + 1]]; vr!(d) = v; }
                    Op::VStore(s, i, v, off) => { let idx = (ir!(i) + off as i64) as usize; let x = vr!(v); let st = storage!(s); st[idx] = x[0]; st[idx + 1] = x[1]; }
                    Op::VFma(d, a, b, c) => { let (x, y, z) = (vr!(a), vr!(b), vr!(c)); vr!(d) = [x[0].mul_add(y[0], z[0]), x[1].mul_add(y[1], z[1])]; }
                    Op::VLane(d, v, l) => fr!(d) = vr!(v)[l as usize],
                    Op::FRet(f) => { let v = Value::num(fr!(f)); if self.pop_frame(tid, v) { return Outcome::Done(v); } break; }
                }
            }
        }
    }

    #[inline]
    fn back_edge(&mut self) {
        self.back_edges += 1;
        if self.back_edges & 255 == 0 { self.heap.safepoint(roots!(self)); }
    }

    #[allow(clippy::too_many_arguments)]
    fn push_frame(&mut self, tid: usize, f: u32, args_at: usize, nargs: u8, pc: usize, _caller: u32, _base: usize, ibase: usize, fbase: usize, vbase: usize, ret: usize) {
        let callee = &self.funcs[f as usize];
        assert_eq!(callee.nparams, nargs, "arity");
        let t = &mut self.tasks[tid];
        t.frames.last_mut().unwrap().pc = pc as u32;
        // The callee's window starts at the caller's result slot, so its r1 is the first argument.
        let base = args_at;
        let need = base + callee.nregs as usize + 1;
        if t.regs.len() < need { t.regs.resize(need, Value::NIL); }
        let caller = &self.funcs[t.frames.last().unwrap().func as usize];
        let (ni, nf, nv) = (ibase + caller.nireg as usize, fbase + caller.nfreg as usize, vbase + caller.nvreg as usize);
        if t.iregs.len() < ni + callee.nireg as usize { t.iregs.resize(ni + callee.nireg as usize, 0); }
        if t.fregs.len() < nf + callee.nfreg as usize { t.fregs.resize(nf + callee.nfreg as usize, 0.0); }
        if t.vregs.len() < nv + callee.nvreg as usize { t.vregs.resize(nv + callee.nvreg as usize, [0.0; 2]); }
        t.frames.push(Frame { func: f, pc: 0, base: base as u32, ibase: ni as u32, fbase: nf as u32, vbase: nv as u32, ret: ret as u32 });
    }

    /// Pops the frame, delivering `v` to the caller's result register; true when
    /// the task is finished.
    fn pop_frame(&mut self, tid: usize, v: Value) -> bool {
        let t = &mut self.tasks[tid];
        let frame = t.frames.pop().unwrap();
        // The popped frame's window is dead: clear it so it does not keep
        // garbage alive. Windows above it were cleared when they popped.
        let top = (frame.base as usize + self.funcs[frame.func as usize].nregs as usize + 1).min(t.regs.len());
        for r in &mut t.regs[frame.base as usize..top] { *r = Value::NIL; }
        if t.frames.is_empty() { t.state = State::Done; t.result = v; return true; }
        t.regs[frame.ret as usize] = v;
        false
    }
}

impl std::ops::Index<usize> for Function { type Output = Op; fn index(&self, i: usize) -> &Op { &self.code[i] } }
impl Clone for Function { fn clone(&self) -> Self { Function { name: self.name, code: self.code.clone(), consts: self.consts.clone(), nparams: self.nparams, nregs: self.nregs, nireg: self.nireg, nfreg: self.nfreg, nvreg: self.nvreg } } }
pub fn storage_ptr(v: Value) -> Option<NonNull<crate::heap::Object>> { v.as_obj() }
