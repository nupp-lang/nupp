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
    /// Dense dispatch: integer register indexes jump table `t`; out of range takes its default.
    Switch(u8, u16),
    /// Table read and write with an integer-register index.
    GetIdxI(u8, u8, u8),
    SetIdxI(u8, u8, u8),
    /// Unbox a number from a value register into an integer register.
    IUnbox(u8, u8),
    ICmpSLt(u8, u8, u8),
    ICmpSLe(u8, u8, u8),
    IShl(u8, u8, u8),
    IShrU(u8, u8, u8),
    IOr(u8, u8, u8),
    IBswap32(u8, u8),
    ICmpEq(u8, u8, u8),
    /// Byte-level access to a string or byte buffer, every access checked.
    BytesLen(u8, u8),
    LoadU8(u8, u8, u8),
    /// A byte read the verifier proves in bounds: the object is a pool
    /// constant string of known length and the index is masked below it.
    LoadU8K(u8, u8, u8),
    /// Little-endian 32-bit word at a word index.
    LoadU32W(u8, u8, u8),
    StoreU8(u8, u8, u8),
    /// Little-endian 32-bit word at a byte offset.
    StoreU32(u8, u8, u8),
    NewBytes(u8, u8),
    /// A string from the first n bytes of a byte buffer.
    BytesToStr(u8, u8, u8),
    ICmpNe(u8, u8, u8),
    /// 1 when the value register is neither nil nor false.
    Truthy(u8, u8),
    /// A growable byte buffer and its operations; substrings are 1-based inclusive.
    NewBuffer(u8),
    BufAppend(u8, u8),
    BufAppendSub(u8, u8, u8, u8),
    Substring(u8, u8, u8, u8),
    BufFinish(u8, u8),
    /// Call function `fid` with arguments at base+1.., result into `base`.
    Call(u32, u8, u8),
    /// Typed call: value arguments at base+1.., float arguments in the float
    /// window starting at fbase; the float result returns to fbase, a value
    /// result to base.
    CallT(u32, u8, u8, u8),
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
    /// New closure over function `fid` capturing n values from base..
    NewClosure(u8, u32, u8, u8),
    NewCell(u8, u8),
    GetCell(u8, u8),
    SetCell(u8, u8),
    /// Capture i of the running closure.
    GetUpval(u8, u8),
    FBox(u8, u8),
    GetSlotF(u8, u8, u16),
    SetSlotF(u8, u16, u8),
    FDiv(u8, u8, u8),
    FNeg(u8, u8),
    LenF(u8, u8),
    /// Table read with a float index into a value register.
    GetIdxF(u8, u8, u8),
    /// Table write with a float index.
    SetIdxF(u8, u8, u8),
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
    /// Parameter classes in declaration order, b'f' or b'v', and the return class.
    pub sig: Vec<u8>,
    pub ret: u8,
    /// Value and float parameter counts, derived from `sig` at load.
    pub nv_params: u8,
    pub nf_params: u8,
    pub code: Vec<Op>,
    pub consts: Vec<Value>,
    pub nparams: u8,
    pub nregs: u8,
    pub nireg: u8,
    pub nfreg: u8,
    pub nvreg: u8,
    /// Jump tables for `Switch`: (default offset, offsets by index), relative to the next op.
    pub jump_tables: Vec<(i32, Vec<i32>)>,
}

#[derive(Clone, Copy)]
struct Frame { func: u32, pc: u32, base: u32, ibase: u32, fbase: u32, vbase: u32, ret: u32, /// The closure this activation runs, or nil for a plain function.
    closure: Value, /// Where a float result goes in the caller's float window, when the callee returns one.
    ret_f: u32, ret_is_f: bool }

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
    /// Handle scopes (contracts 4.7): values a native caller holds are roots
    /// until the scope that pushed them closes.
    pub handles: Vec<Value>,
    /// Registered handles: roots a native caller keeps across calls and
    /// releases explicitly.
    pub registered: Vec<Value>,
    back_edges: u32,
    pub parks: u64,
    pub trace: bool,
    /// Compiled entry per function id, when the JIT has one.
    pub compiled: Vec<Option<*const u8>>,
    pub entry2: Option<u32>,
    /// Loop-header transfer: back-edge counts per (function, header pc), compiled
    /// header entries, and the compiler callback the harness installs.
    pub loop_counts: std::collections::HashMap<(u32, usize), u32>,
    pub osr_entries: std::collections::HashMap<(u32, usize), Option<*const u8>>,
    pub osr_compile: Option<Box<dyn FnMut(&Function, usize) -> Option<*const u8>>>,
    pub osr_threshold: u32,
    pub osr_transfers: u64,
}

struct TaskRoots<'a> { tasks: &'a [Task], funcs: &'a [Function], handles: &'a [Value], registered: &'a [Value] }
/// The frame pointer of the runtime helper currently entered from compiled
/// code, or zero; the root set walks compiled frames from here.
pub static HELPER_FP: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(0);
impl Roots for TaskRoots<'_> {
    fn each_root(&self, f: &mut dyn FnMut(Value)) {
        for t in self.tasks {
            // Only registers below the live top are roots: the top frame's window
            // end, which also covers every frame beneath it.
            let top = t.frames.last().map(|fr| (fr.base as usize + self.funcs[fr.func as usize].nregs as usize + 1).min(t.regs.len())).unwrap_or(0);
            for &v in &t.regs[..top] { f(v); }
            f(t.result);
        }
        for fun in self.funcs { for &k in &fun.consts { f(k); } }
        for &v in self.handles { f(v); }
        for &v in self.registered { f(v); }
        let fp = HELPER_FP.load(std::sync::atomic::Ordering::Relaxed);
        if fp != 0 { crate::jit::walk_compiled_roots(fp, &mut |bits| f(Value(bits))); }
    }
}

#[derive(Debug)]
pub enum Outcome { Done(Value), Parked(u64) }

/// The current activation's register windows and constants, as raw pointers,
/// handed to the outlined opcode handlers.
#[derive(Clone, Copy)]
pub struct Win { regs: *mut Value, iregs: *mut i64, fregs: *mut f64, consts: *const Value, base: usize, ibase: usize, fbase: usize, vbase: usize, fid: u32 }
/// What an outlined handler asks the dispatch loop to do next.
pub enum Flow { Next, Reenter, Return(Outcome) }

/// No roots: for allocations made while nothing else is live yet.
pub struct NoRoots;
impl crate::heap::Roots for NoRoots { fn each_root(&self, _f: &mut dyn FnMut(Value)) {} }
macro_rules! roots { ($self:ident) => { &TaskRoots { tasks: &$self.tasks, funcs: &$self.funcs, handles: &$self.handles, registered: &$self.registered } } }

impl Interp {
    pub fn new() -> Interp { Interp { heap: Heap::new(), funcs: Vec::new(), tasks: Vec::new(), handles: Vec::new(), registered: Vec::new(), back_edges: 0, parks: 0, trace: std::env::var("TRACE_OPS").is_ok(), compiled: Vec::new(), entry2: None, loop_counts: std::collections::HashMap::new(), osr_entries: std::collections::HashMap::new(), osr_compile: None, osr_threshold: 50, osr_transfers: 0 } }

    pub fn intern(&mut self, s: &str) -> Value { let r = TaskRoots { tasks: &self.tasks, funcs: &self.funcs, handles: &self.handles, registered: &self.registered }; self.heap.intern(s, &r) }

    pub fn spawn(&mut self, fid: u32, args: &[Value]) -> usize {
        let f = &self.funcs[fid as usize];
        let mut t = Task { regs: vec![Value::NIL; f.nregs as usize + 1], iregs: vec![0; f.nireg as usize], fregs: vec![0.0; f.nfreg as usize], vregs: vec![[0.0; 2]; f.nvreg as usize], frames: Vec::new(), state: State::Runnable, result: Value::NIL };
        // Entry arguments follow the typed convention: float parameters land in
        // the float window, the rest in value registers, each in declaration order.
        let typed = f.sig.len() == f.nparams as usize;
        let (mut vi, mut fi) = (0usize, 0usize);
        for (i, &a) in args.iter().enumerate() { if typed && f.sig[i] == b'f' { t.fregs[fi] = a.as_num(); fi += 1; } else { vi += 1; t.regs[vi] = a; } }
        t.frames.push(Frame { func: fid, pc: 0, base: 0, ibase: 0, fbase: 0, vbase: 0, ret: 0, ret_f: 0, ret_is_f: false, closure: Value::NIL });
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
    /// Opens a handle scope: the mark to close it with.
    pub fn open_scope(&self) -> usize { self.handles.len() }
    /// Closes a scope, releasing every handle pushed since it opened.
    pub fn close_scope(&mut self, mark: usize) { self.handles.truncate(mark); }
    /// A root the caller keeps until it releases it.
    pub fn register(&mut self, v: Value) -> usize { self.registered.push(v); self.registered.len() - 1 }
    pub fn release(&mut self, h: usize) { self.registered[h] = Value::NIL; }
    pub fn heap_new_bytes(&mut self, n: usize) -> Value { self.heap.new_bytes(n, roots!(self)) }
    pub fn bytes_to_str(&mut self, s: Value, n: usize) -> Value { let text = String::from_utf8(self.bytes_of(s)[..n].to_vec()).unwrap_or_else(|_| self.err("not text")); self.heap.new_string(text, roots!(self)) }
    /// Lua's substring clamping: 1-based inclusive, out-of-range ends clamp, an empty range is empty.
    pub fn sub_bytes(&self, v: Value, i: i64, j: i64) -> &[u8] {
        let b = self.bytes_of(v);
        let n = b.len() as i64;
        let i = if i < 1 { 1 } else { i };
        let j = if j > n { n } else { j };
        if i > j { &b[0..0] } else { &b[(i - 1) as usize..j as usize] }
    }
    pub fn substring(&mut self, s: Value, i: i64, j: i64) -> Value { let text = String::from_utf8(self.sub_bytes(s, i, j).to_vec()).unwrap_or_else(|_| self.err("not text")); self.heap.new_string(text, roots!(self)) }
    pub fn buf_append(&mut self, buf: Value, text: &[u8]) {
        let p = buf.as_obj().unwrap_or_else(|| self.err("append to a non-buffer"));
        unsafe { match &mut (*p.as_ptr()).body { Body::Bytes { data } => { data.extend_from_slice(text); } _ => self.err("not a buffer") } (*p.as_ptr()).refresh(); }
    }
    pub fn bytes_of(&self, v: Value) -> &[u8] {
        let p = v.as_obj().unwrap_or_else(|| self.err("bytes of a non-object"));
        unsafe { match &(*p.as_ptr()).body { Body::Str { text, .. } => text.as_bytes(), Body::Bytes { data } => data, _ => self.err("not bytes") } }
    }
    pub fn bytes_mut(&self, v: Value) -> &mut [u8] {
        let p = v.as_obj().unwrap_or_else(|| self.err("bytes of a non-object"));
        unsafe { match &mut (*p.as_ptr()).body { Body::Bytes { data } => data, _ => self.err("not a byte buffer") } }
    }
    pub fn get_index(&self, tv: Value, key: Value) -> Value {
        let p = tv.as_obj().unwrap_or_else(|| self.err("index of a non-table"));
        unsafe { match &(*p.as_ptr()).body {
            Body::Table { array, hash } => { if key.is_num() { let n = key.as_num(); if n >= 1.0 && (n as usize) <= array.len() && n.fract() == 0.0 { return array[n as usize - 1]; } } *hash.get(&key).unwrap_or(&Value::NIL) }
            _ => self.err("index of a non-table"),
        } }
    }
    pub fn set_index(&mut self, tv: Value, iv: Value, v: Value) {
        let p = tv.as_obj().unwrap_or_else(|| self.err("index of a non-table"));
        self.heap.barrier(p, iv);
        self.heap.barrier(p, v);
        unsafe { match &mut (*p.as_ptr()).body {
            Body::Table { array, hash } => { if iv.is_num() && iv.as_num() >= 1.0 && iv.as_num().fract() == 0.0 && (iv.as_num() as usize) <= array.len() + 1 { let k = iv.as_num() as usize; if k == array.len() + 1 { array.push(v) } else { array[k - 1] = v } } else { hash.insert(iv, v); } }
            _ => self.err("index of a non-table"),
        } (*p.as_ptr()).refresh(); }
    }
    pub fn concat(&mut self, x: Value, y: Value) -> Value {
        let text = |v: Value| -> String { if v.is_num() { let n = v.as_num(); if n.fract() == 0.0 && n.abs() < 1e15 { format!("{}", n as i64) } else { format!("{}", n) } } else { match v.as_obj() { Some(p) => unsafe { (*p.as_ptr()).str_text().to_string() }, None => panic!("runtime error: concatenate a non-string") } } };
        let joined = text(x) + &text(y);
        self.heap.intern(&joined, roots!(self))
    }
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
            let win = Win { regs, iregs, fregs, consts, base, ibase, fbase, vbase, fid };
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
                #[cfg(feature = "trace")]
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
                    Op::Jmp(off) => {
                        pc = (pc as i64 + off as i64) as usize;
                        if off < 0 {
                            self.back_edge();
                            if self.osr_compile.is_some() {
                                if let Some(entry) = self.loop_trip(fid, pc) {
                                    // Transfer: the compiled header entry reads the windows,
                                    // runs the activation to its end and returns the result.
                                    let f: extern "C" fn(u64, u64, u64) -> u64 = unsafe { std::mem::transmute(entry) };
                                    self.osr_transfers += 1;
                                    let result = Value(f(regs as u64, fregs as u64, iregs as u64));
                                    if self.pop_frame(tid, result) { return Outcome::Done(result); }
                                    break;
                                }
                            }
                        }
                    }
                    Op::JmpIf(c, off) => if r!(c).truthy() { pc = (pc as i64 + off as i64) as usize; if off < 0 { self.back_edge(); } },
                    Op::JmpIfNot(c, off) => if !r!(c).truthy() { pc = (pc as i64 + off as i64) as usize; if off < 0 { self.back_edge(); } },
                    Op::CallT(f, b, fb, _) => match self.op_call_typed(tid, &win, pc, f, b, fb) { Flow::Next => {} Flow::Reenter => break, Flow::Return(o) => return o },
                    Op::CallDyn(fr, b, nargs) => match self.op_call_dyn(tid, &win, pc, fr, b, nargs) { Flow::Next => {} Flow::Reenter => break, Flow::Return(o) => return o },
                    Op::CallMethod(k, b, nargs) => match self.op_call_method(tid, &win, pc, k, b, nargs) { Flow::Next => {} Flow::Reenter => break, Flow::Return(o) => return o },
                    Op::PCall(b, nargs) => self.op_pcall(&win, b, nargs),
                    Op::Concat(d, a, b) => self.op_concat(&win, d, a, b),
                    Op::GetIdx(d, t, i) => self.op_get_idx(&win, d, t, i),
                    Op::SetIdx(t, i, s) => self.op_set_idx(&win, t, i, s),
                    Op::GetField(d, t, k) => self.op_get_field(&win, d, t, k),
                    Op::SetField(t, k, s) => self.op_set_field(&win, t, k, s),
                    Op::NewTable(d) => { let v = self.heap.new_table(roots!(self)); r!(d) = v; }
                    Op::NewRecord(d, shape) => { let v = self.heap.new_record(shape, roots!(self)); r!(d) = v; }
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
                    Op::Ret(s) => { let v = r!(s); if self.pop_frame(tid, v) { return Outcome::Done(v); } break; }
                    Op::RetNil => { if self.pop_frame(tid, Value::NIL) { return Outcome::Done(Value::NIL); } break; }
                    Op::GetSlot(d, t, i) => { let p = r!(t).as_obj().unwrap_or_else(|| self.err("slot of a non-record")); r!(d) = unsafe { match &(*p.as_ptr()).body { Body::Record { slots, .. } => *slots.get_unchecked(i as usize), Body::Freed(_) => self.err("use after free"), _ => self.err("slot of a non-record") } }; }
                    Op::SetSlot(t, i, s) => { let v = r!(s); let p = r!(t).as_obj().unwrap_or_else(|| self.err("slot of a non-record")); self.heap.barrier(p, v); unsafe { match &mut (*p.as_ptr()).body { Body::Record { slots, .. } => *slots.get_unchecked_mut(i as usize) = v, Body::Freed(_) => self.err("use after free"), _ => self.err("slot of a non-record") } } }
                    Op::Ne(d, a, b) => { let (x, y) = (r!(a), r!(b)); r!(d) = Value::boolean(x != y) }
                    Op::Not(d, a) => r!(d) = Value::boolean(!r!(a).truthy()),
                    Op::Neg(d, a) => { let x = r!(a); if !x.is_num() { self.err("negate a non-number") } r!(d) = Value::num(-x.as_num()) }
                    Op::Len(d, a) => { let p = r!(a).as_obj().unwrap_or_else(|| self.err("length of a non-object")); let n = unsafe { match &(*p.as_ptr()).body { Body::Table { array, .. } => array.len(), Body::Str { text, .. } => text.len(), _ => self.err("length of a non-object") } }; r!(d) = Value::num(n as f64) }
                    Op::TagCheckRec(d, a, shape) => { let v = r!(a); let ok = v.as_obj().map(|p| unsafe { matches!((*p.as_ptr()).body, Body::Record { shape: s, .. } if s == shape) }).unwrap_or(false); if !ok { self.err("value is not an instance of the expected record") } r!(d) = v; }
                    Op::TagCheckNum(d, a) => { let v = r!(a); if !v.is_num() { self.err("value is not a number") } r!(d) = v; }
                    Op::TagCheckStr(d, a) => { let v = r!(a); if !v.as_obj().map(|p| unsafe { matches!((*p.as_ptr()).body, Body::Str { .. }) }).unwrap_or(false) { self.err("value is not a string") } r!(d) = v; }
                    Op::NewClosure(d, f, b, n) => { let caps: Vec<Value> = (0..n).map(|i| r!(b + 1 + i)).collect(); let v = self.heap.new_closure(f, caps, roots!(self)); r!(d) = v; }
                    Op::NewCell(d, a) => { let v = r!(a); let c = self.heap.new_cell(v, roots!(self)); r!(d) = c; }
                    Op::GetCell(d, c) => { let p = r!(c).as_obj().unwrap_or_else(|| self.err("not a cell")); r!(d) = unsafe { match &(*p.as_ptr()).body { Body::Cell { value } => *value, _ => self.err("not a cell") } }; }
                    Op::SetCell(c, a) => { let v = r!(a); let p = r!(c).as_obj().unwrap_or_else(|| self.err("not a cell")); self.heap.barrier(p, v); unsafe { match &mut (*p.as_ptr()).body { Body::Cell { value } => *value = v, _ => self.err("not a cell") } } }
                    Op::GetUpval(d, i) => { let clo = self.tasks[tid].frames.last().unwrap().closure; let p = clo.as_obj().unwrap_or_else(|| self.err("upvalue outside a closure")); r!(d) = unsafe { match &(*p.as_ptr()).body { Body::Closure { captures, .. } => captures[i as usize], _ => self.err("not a closure") } }; }
                    Op::FBox(d, a) => r!(d) = Value::num(fr!(a)),
                    Op::GetSlotF(d, t, i) => { let p = r!(t).as_obj().unwrap_or_else(|| self.err("slot of a non-record")); let v = unsafe { match &(*p.as_ptr()).body { Body::Record { slots, .. } => *slots.get_unchecked(i as usize), _ => self.err("slot of a non-record") } }; fr!(d) = v.as_num(); }
                    Op::SetSlotF(t, i, a) => { let p = r!(t).as_obj().unwrap_or_else(|| self.err("slot of a non-record")); let v = Value::num(fr!(a)); unsafe { match &mut (*p.as_ptr()).body { Body::Record { slots, .. } => *slots.get_unchecked_mut(i as usize) = v, _ => self.err("slot of a non-record") } } }
                    Op::FDiv(d, a, b) => fr!(d) = fr!(a) / fr!(b),
                    Op::FNeg(d, a) => fr!(d) = -fr!(a),
                    Op::LenF(d, a) => { let p = r!(a).as_obj().unwrap_or_else(|| self.err("length of a non-object")); let n = unsafe { match &(*p.as_ptr()).body { Body::Table { array, .. } => array.len(), Body::Str { text, .. } => text.len(), _ => self.err("length of a non-object") } }; fr!(d) = n as f64; }
                    Op::GetIdxF(d, t, i) => { let p = r!(t).as_obj().unwrap_or_else(|| self.err("index of a non-table")); let k = fr!(i); let v = unsafe { match &(*p.as_ptr()).body { Body::Table { array, hash } => { if k >= 1.0 && (k as usize) <= array.len() && k.fract() == 0.0 { array[k as usize - 1] } else { *hash.get(&Value::num(k)).unwrap_or(&Value::NIL) } } _ => self.err("index of a non-table") } }; r!(d) = v; }
                    Op::SetIdxF(t, i, sv) => {
                        let (tv, k, v) = (r!(t), fr!(i), r!(sv));
                        let p = tv.as_obj().unwrap_or_else(|| self.err("index of a non-table"));
                        self.heap.barrier(p, v);
                        unsafe { match &mut (*p.as_ptr()).body {
                            Body::Table { array, hash } => { if k >= 1.0 && k.fract() == 0.0 && (k as usize) <= array.len() + 1 { let n = k as usize; if n == array.len() + 1 { array.push(v) } else { array[n - 1] = v } } else { hash.insert(Value::num(k), v); } }
                            _ => self.err("index of a non-table"),
                        } (*p.as_ptr()).refresh(); }
                    }
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
                    Op::GetIdxI(d, t, i) => { let key = Value::num(ir!(i) as f64); let tv = r!(t); r!(d) = self.get_index(tv, key); }
                    Op::SetIdxI(t, i, s) => { let key = Value::num(ir!(i) as f64); let (tv, v) = (r!(t), r!(s)); self.set_index(tv, key, v); }
                    Op::IUnbox(d, v) => ir!(d) = r!(v).as_num() as i64,
                    Op::ICmpSLt(d, a, b) => ir!(d) = (ir!(a) < ir!(b)) as i64,
                    Op::ICmpSLe(d, a, b) => ir!(d) = (ir!(a) <= ir!(b)) as i64,
                    Op::IShl(d, a, b) => ir!(d) = ir!(a).wrapping_shl(ir!(b) as u32),
                    Op::IShrU(d, a, b) => ir!(d) = ((ir!(a) as u64) >> (ir!(b) as u32 & 63)) as i64,
                    Op::IOr(d, a, b) => ir!(d) = ir!(a) | ir!(b),
                    Op::IBswap32(d, a) => ir!(d) = (ir!(a) as u32).swap_bytes() as i64,
                    Op::ICmpEq(d, a, b) => ir!(d) = (ir!(a) == ir!(b)) as i64,
                    Op::BytesLen(d, s) => ir!(d) = self.bytes_of(r!(s)).len() as i64,
                    Op::LoadU8K(d, s, i) => { let bytes = self.bytes_of(r!(s)); ir!(d) = bytes[ir!(i) as usize] as i64; }
                    Op::LoadU8(d, s, i) => { let bytes = self.bytes_of(r!(s)); let i = ir!(i) as usize; if i >= bytes.len() { self.err("byte read out of range") } ir!(d) = bytes[i] as i64; }
                    Op::LoadU32W(d, s, i) => { let bytes = self.bytes_of(r!(s)); let off = ir!(i) as usize * 4; if off + 4 > bytes.len() { self.err("word read out of range") } ir!(d) = u32::from_le_bytes(bytes[off..off + 4].try_into().unwrap()) as i64; }
                    Op::StoreU8(s, i, v) => { let x = ir!(v) as u8; let bytes = self.bytes_mut(r!(s)); let i = ir!(i) as usize; if i >= bytes.len() { self.err("byte write out of range") } bytes[i] = x; }
                    Op::StoreU32(s, i, v) => { let x = ir!(v) as u32; let bytes = self.bytes_mut(r!(s)); let off = ir!(i) as usize; if off + 4 > bytes.len() { self.err("word write out of range") } bytes[off..off + 4].copy_from_slice(&x.to_le_bytes()); }
                    Op::ICmpNe(d, a, b) => ir!(d) = (ir!(a) != ir!(b)) as i64,
                    Op::Truthy(d, v) => ir!(d) = r!(v).truthy() as i64,
                    Op::NewBuffer(d) => { let v = self.heap.new_bytes(0, roots!(self)); r!(d) = v; }
                    Op::BufAppend(bf, s) => { let text = self.bytes_of(r!(s)).to_vec(); self.buf_append(r!(bf), &text); }
                    Op::BufAppendSub(bf, s, i, j) => { let (i, j) = (ir!(i), ir!(j)); let text = self.sub_bytes(r!(s), i, j).to_vec(); self.buf_append(r!(bf), &text); }
                    Op::Substring(d, s, i, j) => { let (i, j) = (ir!(i), ir!(j)); let text = String::from_utf8(self.sub_bytes(r!(s), i, j).to_vec()).unwrap_or_else(|_| self.err("not text")); let v = self.heap.new_string(text, roots!(self)); r!(d) = v; }
                    Op::BufFinish(d, bf) => { let text = String::from_utf8(self.bytes_of(r!(bf)).to_vec()).unwrap_or_else(|_| self.err("not text")); let v = self.heap.new_string(text, roots!(self)); r!(d) = v; }
                    Op::NewBytes(d, n) => { let n = ir!(n) as usize; let v = self.heap.new_bytes(n, roots!(self)); r!(d) = v; }
                    Op::BytesToStr(d, s, n) => { let n = ir!(n) as usize; let text = String::from_utf8(self.bytes_of(r!(s))[..n].to_vec()).unwrap_or_else(|_| self.err("not text")); let v = self.heap.new_string(text, roots!(self)); r!(d) = v; }
                    Op::Switch(r, t) => {
                        let i = ir!(r);
                        let off = { let (def, tbl) = &self.funcs[fid as usize].jump_tables[t as usize]; if i >= 0 && (i as usize) < tbl.len() { tbl[i as usize] } else { *def } };
                        pc = (pc as i64 + off as i64) as usize;
                        if off < 0 { self.back_edge(); }
                    }
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


    // ---- Outlined opcode handlers. Each keeps the dispatch loop small; the
    // register macros below address the activation through the window.
    #[inline(never)]
    fn op_call_typed(&mut self, tid: usize, w: &Win, pc: usize, f: u32, b: u8, fb: u8) -> Flow {
        let (regs, iregs, fregs, consts, base, ibase, fbase, vbase, fid) = (w.regs, w.iregs, w.fregs, w.consts, w.base, w.ibase, w.fbase, w.vbase, w.fid);
        let _ = (consts, ibase, vbase, fid, base);
        macro_rules! r { ($i:expr) => { (*unsafe { &mut *regs.add($i as usize) }) } }
        macro_rules! ir { ($i:expr) => { (*unsafe { &mut *iregs.add($i as usize) }) } }
        macro_rules! fr { ($i:expr) => { (*unsafe { &mut *fregs.add($i as usize) }) } }
        let _ = (|| 0i64);
        
                        let (nv, nfp, callee_ret) = { let c = &self.funcs[f as usize]; (c.nv_params, c.nf_params, c.ret) };
                        if let Some(Some(entry)) = self.compiled.get(f as usize) {
                            let entry = *entry;
                            let mut args = [0u64; 4];
                            let (mut vi, mut fi) = (0u8, 0u8);
                            { let sig = &self.funcs[f as usize].sig; for (i, &c) in sig.iter().enumerate() { args[i] = if c == b'f' { let v = Value::num(fr!(fb + fi)).0; fi += 1; v } else { vi += 1; r!(b + vi).0 }; } }
                            let n = (nv + nfp) as usize;
                            let result = unsafe { match n { 0 => std::mem::transmute::<_, extern "C" fn() -> u64>(entry)(), 1 => std::mem::transmute::<_, extern "C" fn(u64) -> u64>(entry)(args[0]), 2 => std::mem::transmute::<_, extern "C" fn(u64, u64) -> u64>(entry)(args[0], args[1]), 3 => std::mem::transmute::<_, extern "C" fn(u64, u64, u64) -> u64>(entry)(args[0], args[1], args[2]), _ => std::mem::transmute::<_, extern "C" fn(u64, u64, u64, u64) -> u64>(entry)(args[0], args[1], args[2], args[3]) } };
                            if callee_ret == b'f' { fr!(fb) = Value(result).as_num(); } else { r!(b) = Value(result); }
                            return Flow::Next;
                        }
                        self.push_frame(tid, f, base + b as usize, nv, pc, fid, base, ibase, fbase, vbase, base + b as usize);
                        let t = &mut self.tasks[tid];
                        let frame = t.frames.last_mut().unwrap();
                        let callee_fbase = frame.fbase as usize;
                        frame.ret_f = (fbase + fb as usize) as u32;
                        frame.ret_is_f = callee_ret == b'f';
                        for i in 0..nfp as usize { t.fregs[callee_fbase + i] = t.fregs[fbase + fb as usize + i]; }
                        return Flow::Reenter;
                    
    }
    #[inline(never)]
    fn op_call_dyn(&mut self, tid: usize, w: &Win, pc: usize, fr: u8, b: u8, nargs: u8) -> Flow {
        let (regs, iregs, fregs, consts, base, ibase, fbase, vbase, fid) = (w.regs, w.iregs, w.fregs, w.consts, w.base, w.ibase, w.fbase, w.vbase, w.fid);
        let _ = (consts, ibase, vbase, fid, base);
        macro_rules! r { ($i:expr) => { (*unsafe { &mut *regs.add($i as usize) }) } }
        macro_rules! ir { ($i:expr) => { (*unsafe { &mut *iregs.add($i as usize) }) } }
        macro_rules! fr { ($i:expr) => { (*unsafe { &mut *fregs.add($i as usize) }) } }
        let _ = (|| 0i64);
        
                        let callee = r!(fr);
                        if let Some(f) = callee.as_func() { self.push_frame(tid, f, base + b as usize, nargs, pc, fid, base, ibase, fbase, vbase, base + b as usize); return Flow::Reenter; }
                        let p = callee.as_obj().unwrap_or_else(|| self.err("call of a non-function"));
                        let f = unsafe { match &(*p.as_ptr()).body { Body::Closure { fid, .. } => *fid, _ => self.err("call of a non-function") } };
                        // Dynamic calls pass values; a typed callee unboxes its float parameters on entry.
                        let (nv, nfp) = { let c = &self.funcs[f as usize]; (c.nv_params, c.nf_params) };
                        self.push_frame(tid, f, base + b as usize, nv, pc, fid, base, ibase, fbase, vbase, base + b as usize);
                        if nfp > 0 {
                            let frame = *self.tasks[tid].frames.last().unwrap();
                            let callee_base = frame.base as usize;
                            let (mut vi, mut fi) = (0usize, 0usize);
                            let n = self.funcs[f as usize].sig.len();
                            for i in 0..n {
                                let c = self.funcs[f as usize].sig[i];
                                let t = &mut self.tasks[tid];
                                if c == b'f' { let v = t.regs[callee_base + 1 + i]; t.fregs[frame.fbase as usize + fi] = v.as_num(); fi += 1; }
                                else { vi += 1; t.regs[callee_base + vi] = t.regs[callee_base + 1 + i]; }
                            }
                        }
                        let t = &mut self.tasks[tid];
                        let fr_ = t.frames.last_mut().unwrap();
                        fr_.closure = callee;
                        fr_.ret_is_f = false;
                        let _ = nargs;
                        return Flow::Reenter;
                    
    }
    #[inline(never)]
    fn op_call_method(&mut self, tid: usize, w: &Win, pc: usize, k: u16, b: u8, nargs: u8) -> Flow {
        let (regs, iregs, fregs, consts, base, ibase, fbase, vbase, fid) = (w.regs, w.iregs, w.fregs, w.consts, w.base, w.ibase, w.fbase, w.vbase, w.fid);
        let _ = (consts, ibase, vbase, fid, base);
        macro_rules! r { ($i:expr) => { (*unsafe { &mut *regs.add($i as usize) }) } }
        macro_rules! ir { ($i:expr) => { (*unsafe { &mut *iregs.add($i as usize) }) } }
        macro_rules! fr { ($i:expr) => { (*unsafe { &mut *fregs.add($i as usize) }) } }
        let _ = (|| 0i64);
        
                        let name = unsafe { *consts.add(k as usize) };
                        let recv = r!(b + 1);
                        let p = recv.as_obj().unwrap_or_else(|| self.err("method call on a non-object"));
                        let fid = unsafe { match &(*p.as_ptr()).body { Body::Record { shape, .. } => *self.heap.shapes[*shape as usize].methods.get(&name).unwrap_or_else(|| self.err("no such method")), _ => self.err("method call on a non-record") } };
                        self.push_frame(tid, fid, base + b as usize, nargs, pc, fid, base, ibase, fbase, vbase, base + b as usize); return Flow::Reenter;
                    
    }
    #[inline(never)]
    fn op_pcall(&mut self, w: &Win, b: u8, nargs: u8) {
        let (regs, iregs, fregs, consts, base, ibase, fbase, vbase, fid) = (w.regs, w.iregs, w.fregs, w.consts, w.base, w.ibase, w.fbase, w.vbase, w.fid);
        let _ = (consts, ibase, vbase, fid, base);
        macro_rules! r { ($i:expr) => { (*unsafe { &mut *regs.add($i as usize) }) } }
        macro_rules! ir { ($i:expr) => { (*unsafe { &mut *iregs.add($i as usize) }) } }
        macro_rules! fr { ($i:expr) => { (*unsafe { &mut *fregs.add($i as usize) }) } }
        let _ = (|| 0i64);
        
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
    #[inline(never)]
    fn op_concat(&mut self, w: &Win, d: u8, a: u8, b: u8) {
        let (regs, iregs, fregs, consts, base, ibase, fbase, vbase, fid) = (w.regs, w.iregs, w.fregs, w.consts, w.base, w.ibase, w.fbase, w.vbase, w.fid);
        let _ = (consts, ibase, vbase, fid, base);
        macro_rules! r { ($i:expr) => { (*unsafe { &mut *regs.add($i as usize) }) } }
        macro_rules! ir { ($i:expr) => { (*unsafe { &mut *iregs.add($i as usize) }) } }
        macro_rules! fr { ($i:expr) => { (*unsafe { &mut *fregs.add($i as usize) }) } }
        let _ = (|| 0i64);
        
                        let (x, y) = (r!(a), r!(b));
                        let text = |v: Value| -> String { if v.is_num() { let n = v.as_num(); if n.fract() == 0.0 && n.abs() < 1e15 { format!("{}", n as i64) } else { format!("{}", n) } } else { match v.as_obj() { Some(p) => unsafe { (*p.as_ptr()).str_text().to_string() }, None => self.err("concatenate a non-string") } } };
                    let joined = text(x) + &text(y);
                        let v = self.heap.intern(&joined, roots!(self));
                        r!(d) = v;
                    
    }
    #[inline(never)]
    fn op_get_idx(&mut self, w: &Win, d: u8, t: u8, i: u8) {
        let (regs, iregs, fregs, consts, base, ibase, fbase, vbase, fid) = (w.regs, w.iregs, w.fregs, w.consts, w.base, w.ibase, w.fbase, w.vbase, w.fid);
        let _ = (consts, ibase, vbase, fid, base);
        macro_rules! r { ($i:expr) => { (*unsafe { &mut *regs.add($i as usize) }) } }
        macro_rules! ir { ($i:expr) => { (*unsafe { &mut *iregs.add($i as usize) }) } }
        macro_rules! fr { ($i:expr) => { (*unsafe { &mut *fregs.add($i as usize) }) } }
        let _ = (|| 0i64);
        
                        let (tv, iv) = (r!(t), r!(i));
                        let p = tv.as_obj().unwrap_or_else(|| self.err("index of a non-table"));
                        let v = unsafe { match &(*p.as_ptr()).body {
                            Body::Table { array, hash } => { if iv.is_num() { let k = iv.as_num(); if k >= 1.0 && (k as usize) <= array.len() && k.fract() == 0.0 { array[k as usize - 1] } else { *hash.get(&iv).unwrap_or(&Value::NIL) } } else { *hash.get(&iv).unwrap_or(&Value::NIL) } }
                            _ => self.err("index of a non-table"),
                        } };
                        r!(d) = v;
                    
    }
    #[inline(never)]
    fn op_set_idx(&mut self, w: &Win, t: u8, i: u8, s: u8) {
        let (regs, iregs, fregs, consts, base, ibase, fbase, vbase, fid) = (w.regs, w.iregs, w.fregs, w.consts, w.base, w.ibase, w.fbase, w.vbase, w.fid);
        let _ = (consts, ibase, vbase, fid, base);
        macro_rules! r { ($i:expr) => { (*unsafe { &mut *regs.add($i as usize) }) } }
        macro_rules! ir { ($i:expr) => { (*unsafe { &mut *iregs.add($i as usize) }) } }
        macro_rules! fr { ($i:expr) => { (*unsafe { &mut *fregs.add($i as usize) }) } }
        let _ = (|| 0i64);
        
                        let (tv, iv, v) = (r!(t), r!(i), r!(s));
                        let p = tv.as_obj().unwrap_or_else(|| self.err("index of a non-table"));
                        self.heap.barrier(p, iv);
                        self.heap.barrier(p, v);
                        unsafe { match &mut (*p.as_ptr()).body {
                            Body::Table { array, hash } => { if iv.is_num() && iv.as_num() >= 1.0 && iv.as_num().fract() == 0.0 && (iv.as_num() as usize) <= array.len() + 1 { let k = iv.as_num() as usize; if k == array.len() + 1 { array.push(v) } else { array[k - 1] = v } } else { hash.insert(iv, v); } }
                            _ => self.err("index of a non-table"),
                        } (*p.as_ptr()).refresh(); }
                    
    }
    #[inline(never)]
    fn op_get_field(&mut self, w: &Win, d: u8, t: u8, k: u16) {
        let (regs, iregs, fregs, consts, base, ibase, fbase, vbase, fid) = (w.regs, w.iregs, w.fregs, w.consts, w.base, w.ibase, w.fbase, w.vbase, w.fid);
        let _ = (consts, ibase, vbase, fid, base);
        macro_rules! r { ($i:expr) => { (*unsafe { &mut *regs.add($i as usize) }) } }
        macro_rules! ir { ($i:expr) => { (*unsafe { &mut *iregs.add($i as usize) }) } }
        macro_rules! fr { ($i:expr) => { (*unsafe { &mut *fregs.add($i as usize) }) } }
        let _ = (|| 0i64);
        
                        let name = unsafe { *consts.add(k as usize) };
                        let p = r!(t).as_obj().unwrap_or_else(|| self.err("field of a non-object"));
                        let v = unsafe { match &(*p.as_ptr()).body {
                            Body::Table { hash, .. } => *hash.get(&name).unwrap_or(&Value::NIL),
                            Body::Record { shape, slots } => { let sh = &self.heap.shapes[*shape as usize]; match sh.names.iter().position(|&n| n == name) { Some(i) => slots[i], None => self.err("no such field") } }
                            _ => self.err("field of a non-object"),
                        } };
                        r!(d) = v;
                    
    }
    #[inline(never)]
    fn op_set_field(&mut self, w: &Win, t: u8, k: u16, s: u8) {
        let (regs, iregs, fregs, consts, base, ibase, fbase, vbase, fid) = (w.regs, w.iregs, w.fregs, w.consts, w.base, w.ibase, w.fbase, w.vbase, w.fid);
        let _ = (consts, ibase, vbase, fid, base);
        macro_rules! r { ($i:expr) => { (*unsafe { &mut *regs.add($i as usize) }) } }
        macro_rules! ir { ($i:expr) => { (*unsafe { &mut *iregs.add($i as usize) }) } }
        macro_rules! fr { ($i:expr) => { (*unsafe { &mut *fregs.add($i as usize) }) } }
        let _ = (|| 0i64);
        
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

    /// Counts a back-edge at `header` of `fid`; past the threshold, compiles a
    /// header entry once and returns it on this and every later trip.
    #[inline(never)]
    fn loop_trip(&mut self, fid: u32, header: usize) -> Option<*const u8> {
        if let Some(e) = self.osr_entries.get(&(fid, header)) { return *e; }
        let n = self.loop_counts.entry((fid, header)).or_insert(0);
        *n += 1;
        if *n < self.osr_threshold { return None; }
        let f = self.funcs[fid as usize].clone();
        let entry = self.osr_compile.as_mut().and_then(|c| c(&f, header));
        self.osr_entries.insert((fid, header), entry);
        entry
    }

    #[inline]
    fn back_edge(&mut self) {
        self.back_edges += 1;
        if self.back_edges & 255 == 0 { self.heap.safepoint(roots!(self)); }
    }

    #[allow(clippy::too_many_arguments)]
    fn push_frame(&mut self, tid: usize, f: u32, args_at: usize, nargs: u8, pc: usize, _caller: u32, _base: usize, ibase: usize, fbase: usize, vbase: usize, ret: usize) {
        let callee = &self.funcs[f as usize];
        // The value-argument count: float parameters travel in the float window.
        let expected = if callee.sig.len() == callee.nparams as usize { callee.sig.iter().filter(|&&c| c != b'f').count() as u8 } else { callee.nparams };
        assert_eq!(expected, nargs, "arity of {}", callee.name);
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
        t.frames.push(Frame { func: f, pc: 0, base: base as u32, ibase: ni as u32, fbase: nf as u32, vbase: nv as u32, ret: ret as u32, ret_f: 0, ret_is_f: false, closure: Value::NIL });
    }

    /// Pops the frame, delivering `v` to the caller's result register; true when
    /// the task is finished.
    fn pop_frame(&mut self, tid: usize, v: Value) -> bool {
        let t = &mut self.tasks[tid];
        let frame = t.frames.pop().unwrap();
        // Registers above the caller's window are not roots (see the root set),
        // so nothing is cleared on return.
        if frame.ret_is_f && !t.frames.is_empty() {
            t.fregs[frame.ret_f as usize] = v.as_num();
            return false;
        }
        if t.frames.is_empty() { t.state = State::Done; t.result = v; return true; }
        t.regs[frame.ret as usize] = v;
        false
    }
}

impl std::ops::Index<usize> for Function { type Output = Op; fn index(&self, i: usize) -> &Op { &self.code[i] } }
impl Clone for Function { fn clone(&self) -> Self { Function { name: self.name, sig: self.sig.clone(), ret: self.ret, nv_params: self.nv_params, nf_params: self.nf_params, code: self.code.clone(), consts: self.consts.clone(), nparams: self.nparams, nregs: self.nregs, nireg: self.nireg, nfreg: self.nfreg, nvreg: self.nvreg, jump_tables: self.jump_tables.clone() } } }
pub fn storage_ptr(v: Value) -> Option<NonNull<crate::heap::Object>> { v.as_obj() }
