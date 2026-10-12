//! The interpreter (contracts 5 and 6): tasks whose frames are inline on one
//! stack of words, an untyped tier over NaN-boxed values and a typed tier
//! over unboxed integer, float and two-lane vector registers, parking as a
//! state change, and the host services on the parking surface.

use std::ptr::NonNull;

use crate::heap::{self, Header, Heap, Roots, SlotTy, KIND_BYTES, KIND_CELL, KIND_CLOSURE, KIND_ITER, KIND_RECORD, KIND_SLICE, KIND_STORAGE, KIND_STR, KIND_TABLE};
use crate::value::Value;

/// An owned argument window: callbacks may relocate the task stack. The
/// common case stays inline, but builtin calls have no eight-argument limit.
pub(crate) struct CallArgs { inline: [Value; 8], wide: Vec<Value>, len: usize }
impl CallArgs {
    fn new(len: usize) -> Self { Self { inline: [Value::NIL; 8], wide: if len > 8 { vec![Value::NIL; len] } else { Vec::new() }, len } }
    fn as_mut_slice(&mut self) -> &mut [Value] { if self.len > 8 { &mut self.wide } else { &mut self.inline[..self.len] } }
    pub(crate) fn as_slice(&self) -> &[Value] { if self.len > 8 { &self.wide } else { &self.inline[..self.len] } }
}

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
    Mod(u8, u8, u8),
    Div(u8, u8, u8),
    FMod(u8, u8, u8),
    /// Return n values from consecutive registers starting at the first.
    RetN(u8, u8),
    /// Load the module named by constant k: its export value, running its chunk once.
    Require(u8, u16),
    /// Install a method value on a shape's descriptor by name (constant).
    SetMethod(u32, u16, u8),
    /// Load the module named by a string register.
    RequireV(u8, u8),
    /// A table with room for n array items and m named fields.
    NewTableN(u8, u8, u8),
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
    /// A dynamic call whose callee the emitter knows statically: (function id,
    /// callee register, window base, argument count, results wanted). The
    /// interpreter treats it as `CallDyn`; compiled code guards the closure's
    /// id and calls the compiled entry directly.
    CallK(u16, u8, u8, u8, u8),
    /// `string.byte(s, i)` with one result: the byte as a number, or nil out
    /// of range. (destination, string register, integer index register)
    StrByte(u8, u8, u8),
    /// `a ^ b` and `a // b` on values.
    Pow(u8, u8, u8),
    IDiv(u8, u8, u8),
    IXor(u8, u8, u8),
    INot(u8, u8),
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
    /// Slot access by offset, guarded by the shape the emitter assumed:
    /// another shape reads or writes the slot's name instead.
    GetSlot(u8, u8, u16, u32),
    SetSlot(u8, u16, u8, u32),
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
    /// Whether a value is a record of the shape: `x is R`, a boolean.
    IsRec(u8, u8, u32),
    /// After a call that wanted `n` results: the registers past what it
    /// returned (`last_nres`) are nil, as Lua pads a result list.
    PadResults(u8, u8),
    /// A fixed-width scalar intrinsic (`builtins::SCALAR_OPS[kind]`) on two
    /// number registers (a unary one names its operand twice).
    Scalar(u8, u8, u8, u8),
    /// The frame's first `n` surplus arguments into `dst..`, nil-filled.
    VarargN(u8, u8),
    /// A table of the frame's surplus arguments: `{...}`.
    VarargTable(u8),
    /// New closure over function `fid` capturing n values from base..
    NewClosure(u8, u32, u8, u8),
    NewCell(u8, u8),
    GetCell(u8, u8),
    SetCell(u8, u8),
    /// Capture i of the running closure.
    GetUpval(u8, u8),
    FBox(u8, u8),
    GetSlotF(u8, u8, u16, u32),
    SetSlotF(u8, u16, u8, u32),
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
    /// interpreter ignores it.
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

#[derive(Clone)]
pub struct Function {
    pub name: String,
    /// The module the function was emitted in, for `debug.getinfo`.
    pub module: String,
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
    /// The source position of each instruction (3.8): line and column.
    pub debug: Vec<(u32, u32)>,
    /// Surplus arguments stay in the frame, just below the header (header
    /// word 3 carries their count); a trailing `...` in a call spreads them.
    pub vararg: bool,
    /// The code as the threaded core reads it, encoded by `prepare_threaded`.
    pub ins: Vec<crate::threaded::Ins>,
}

/// A frame is inline in the task's one stack of words: four header words,
/// then the value, integer, float and vector windows in that order (5.1).
/// A call places the callee's frame after the caller's whole frame and
/// copies the arguments, so no window of any class overlaps.
pub const HDR: usize = 4;
/// `TABLE_STATS=1`: index traffic by kind and key, and the hash-part size a
/// table field read met.
pub static TABLE_STATS: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);
pub static TABLE_COUNTS: [std::sync::atomic::AtomicU64; 12] = [const { std::sync::atomic::AtomicU64::new(0) }; 12];
/// Header word 0: function id in the low half, pc in the high half.
/// Word 1: caller's frame start in the low half (NONE at the entry frame), the
/// absolute index of the caller's result register in the high half.
/// Word 2: the closure this activation runs, or nil.
/// Word 3: the absolute index of the caller's float result register in the
/// low half, whether the result is a float in bit 32, the frame's own size
/// in words in bits 33..48, and in bits 49.. the count of vararg words that
/// lie just below the header (a vararg function's surplus arguments, in the
/// frame rather than in any object).
const NONE: u32 = u32::MAX;
#[inline] fn frame_words_of(h3: u64) -> usize { ((h3 >> 33) & 0xffff) as usize }
#[inline] fn nvar_of(h3: u64) -> usize { (h3 >> 49) as usize }
#[inline] fn header3(fret: usize, is_f: bool, words: usize, nvar: usize) -> u64 { fret as u64 | ((is_f as u64) << 32) | ((words as u64) << 33) | ((nvar as u64) << 49) }

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum State { Runnable, Parked(u64), Done }

pub struct Task {
    /// Every frame's header and windows, in call order.
    pub stack: Vec<u64>,
    /// The start of the top frame.
    cur: usize,
    pub state: State,
    pub result: Value,
    /// The register of the top frame a host completion is delivered to.
    pub deliver_at: usize,
    /// Every value the entry frame returned, when it returned more than one.
    pub results: Vec<Value>,
}

impl Task {
    pub fn cur(&self) -> usize { self.cur }
    pub fn set_cur(&mut self, s: usize) { self.cur = s; }
    /// Records the top frame's pc in its header, where the backtrace reads it.
    pub fn note_pc(&mut self, pc: usize) { let s = self.cur; self.stack[s] = (self.stack[s] & 0xffff_ffff) | ((pc as u64) << 32); }
}

impl Function {
    /// Words a frame of this function occupies: header, then each class window.
    #[inline] pub fn frame_words(&self) -> usize { HDR + self.nregs as usize + 1 + self.nireg as usize + self.nfreg as usize + 2 * self.nvreg as usize }
    #[inline] pub fn off_i(&self) -> usize { HDR + self.nregs as usize + 1 }
    #[inline] pub fn off_f(&self) -> usize { self.off_i() + self.nireg as usize }
    #[inline] fn off_v(&self) -> usize { self.off_f() + self.nfreg as usize }
}

pub struct Interp {
    pub heap: Heap,
    /// The host services, once started.
    pub host: Option<crate::host::Host>,
    /// Which task parked on which host request key.
    pub host_waiters: std::collections::HashMap<u64, usize>,
    pub funcs: Vec<Function>,
    pub tasks: Vec<Task>,
    /// Handle scopes (4.7): values a native caller holds are roots until the
    /// scope that pushed them closes.
    pub handles: Vec<Value>,
    /// Registered handles: roots a native caller keeps across calls and
    /// releases explicitly.
    pub registered: Vec<Value>,
    back_edges: u32,
    pub parks: u64,
    /// TRACE_CALLS=1 prints every call's callee.
    pub trace: bool,
    /// OP_STATS=1 counts executed opcodes by name.
    pub op_stats: Option<Box<std::collections::HashMap<&'static str, u64>>>,
    /// `SLOT_STATS=1` on the Rust loop: slot accesses whose object had the
    /// assumed shape, and those that did not, by site (fid, pc).
    pub slot_stats: Option<Box<std::collections::HashMap<(u32, usize, bool), u64>>>,
    /// Misses by (assumed shape, found shape or u32::MAX for a table).
    pub slot_miss_shapes: std::collections::HashMap<(u32, u32), u64>,
    /// How many values the last call or return delivered, for a `return f()`
    /// that hands on exactly what `f` returned.
    pub last_nres: usize,
    /// Module chunks by name, and the export value of each loaded one.
    /// `TRACE_OPS`: every opcode the Rust loop executes, to stderr.
    pub trace_ops: bool,
    /// Stacks of finished scratch tasks, kept for the next spawn: a dynamic
    /// call into interpreted code from a helper happens a million times a
    /// run, and a fresh zeroed vector each time was a tenth of it.
    pub stack_pool: Vec<Vec<u64>>,
    /// `IC_STATS=1`: field-cache helper calls by case (record, cache empty;
    /// record, cache held another shape; table; other).
    pub ic_stats: bool,
    pub modules: std::collections::HashMap<String, u32>,
    /// Each module's source path, as the image recorded it.
    pub module_paths: std::collections::HashMap<String, String>,
    /// The function a `loadstring("return <literal>")` closure runs: it
    /// returns its one upvalue. Registered by `install_globals`.
    pub literal_fid: u32,
    /// The compiled function a dynamic call came from (u32::MAX between
    /// such calls): what `debug.getinfo` names when no frame was pushed.
    pub jit_fid: u32,
    /// The function behind `loadstring` of anything else: loads, and raises
    /// when called, since the runtime evaluates no Lua.
    pub unavailable_fid: u32,
    pub loaded: std::collections::HashMap<String, Value>,
    /// `package.loaded`: the same registry as a table a module can read.
    pub loaded_table: Value,
    /// The threaded core's per-function and per-shape tables, and whether it runs tasks.
    pub finfo: Vec<crate::threaded::FuncInfo>,
    /// The lazy typed tier: compile a function at its `jit_threshold`th call
    /// (0: no lazy compilation; the runner compiles eagerly or not at all).
    pub jit_threshold: u32,
    #[cfg(feature = "jit")]
    pub jit: Option<Box<crate::jit::Jit>>,
    pub lazy_compiled: usize,
    pub lazy_micros: u64,
    pub shape_info: Vec<crate::threaded::ShapeInfo>,
    pub threaded: bool,
    /// The typed tier's compiled entry per function (0 when interpreted),
    /// and the buffer results past the first travel through.
    pub entries: Vec<u64>,
    /// Per function, `nparams | plain << 8`, for compiled dynamic calls.
    pub calltab: Vec<u64>,
    /// Per shape, the slot table's address and mask, for compiled field reads.
    pub shape_probe: Vec<(u64, u64)>,
    pub extra: [Value; 8],
    pub extra_n: usize,
    /// The value of a raise that is propagating as `Value::ERROR` returns.
    pub pending_error: Option<Value>,
}

struct TaskRoots<'a> { tasks: &'a [Task], funcs: &'a [Function], handles: &'a [Value], registered: &'a [Value], extra: &'a [Value; 8], extra_n: usize, pending: Option<Value> }
impl Roots for TaskRoots<'_> {
    fn each_root(&self, f: &mut dyn FnMut(Value)) {
        for t in self.tasks {
            // Each frame's value window, walked from the top frame down the
            // caller chain; the other windows hold no references.
            let mut s = t.cur;
            if t.state != State::Done && !t.stack.is_empty() {
                loop {
                    let h0 = t.stack[s]; let fid = (h0 & 0xffff_ffff) as usize;
                    let n = self.funcs[fid].nregs as usize + 1;
                    for &w in &t.stack[s + HDR..s + HDR + n] { f(Value(w)); }
                    f(Value(t.stack[s + 2]));
                    let nvar = nvar_of(t.stack[s + 3]);
                    for &w in &t.stack[s - nvar..s] { f(Value(w)); }
                    let caller = (t.stack[s + 1] & 0xffff_ffff) as u32;
                    if caller == NONE { break; }
                    s = caller as usize;
                }
            }
            f(t.result);
            for &v in &t.results { f(v); }
        }
        for fun in self.funcs { for &k in &fun.consts { f(k); } }
        for &v in self.handles { f(v); }
        for &v in self.registered { f(v); }
        for &v in &self.extra[..self.extra_n.min(8)] { f(v); }
        if let Some(e) = self.pending { f(e); }
        #[cfg(feature = "compiled-runtime")]
        {
            f(Value(crate::compiled::CUR_CLOSURE.load(std::sync::atomic::Ordering::Relaxed)));
            let fp = crate::compiled::HELPER_FP.load(std::sync::atomic::Ordering::Relaxed);
            if fp != 0 { crate::compiled::walk_compiled_roots(fp, &mut |bits| f(Value(bits))); }
        }
    }
}

#[derive(Debug)]
pub enum Outcome { Done(Value), Parked(u64) }

/// The current activation's register windows and constants, as raw pointers,
/// handed to the outlined opcode handlers.
#[derive(Clone, Copy)]
pub struct Win { pub regs: *mut Value, pub iregs: *mut i64, pub fregs: *mut f64, pub vregs: *mut [f64; 2], pub consts: *const Value, pub code: *const Op, pub base: usize, pub fbase: usize, pub fid: u32 }
/// What an outlined handler asks the dispatch loop to do next.
pub enum Flow { Next, Reenter, Return(Outcome) }
/// What one executed opcode asks of the loop: the next pc, a frame change
/// (re-derive the windows), or the task's outcome.
pub enum Step { Next(usize), Reenter, Return(Outcome) }

macro_rules! roots { ($self:ident) => { &TaskRoots { tasks: &$self.tasks, funcs: &$self.funcs, handles: &$self.handles, registered: &$self.registered, extra: &$self.extra, extra_n: $self.extra_n, pending: $self.pending_error } } }

/// The header behind an object value, or an error; the message is built
/// only on the error path.
macro_rules! hdr { ($it:expr, $v:expr, $what:expr) => { match $v.as_obj() { Some(p) => unsafe { &mut *p.as_ptr() as &mut Header }, None => $it.err(&$what) } } }

impl Default for Interp { fn default() -> Self { Self::new() } }

impl Interp {
    pub fn new() -> Interp { Interp { heap: Heap::new(), host: None, host_waiters: std::collections::HashMap::new(), funcs: Vec::new(), tasks: Vec::new(), handles: Vec::new(), registered: Vec::new(), back_edges: 0, parks: 0, trace: std::env::var("TRACE_CALLS").is_ok(), trace_ops: std::env::var("TRACE_OPS").is_ok(), stack_pool: Vec::new(), ic_stats: std::env::var("IC_STATS").is_ok(), slot_stats: if std::env::var("SLOT_STATS").is_ok() { Some(Box::new(std::collections::HashMap::new())) } else { None }, slot_miss_shapes: std::collections::HashMap::new(), op_stats: if std::env::var("OP_STATS").is_ok() { Some(Box::new(std::collections::HashMap::new())) } else { None }, last_nres: 0, modules: std::collections::HashMap::new(), module_paths: std::collections::HashMap::new(), literal_fid: u32::MAX, unavailable_fid: u32::MAX, jit_fid: u32::MAX, loaded: std::collections::HashMap::new(), loaded_table: Value::NIL, finfo: Vec::new(), jit_threshold: 0, #[cfg(feature = "jit")] jit: None, lazy_compiled: 0, lazy_micros: 0, shape_info: Vec::new(), threaded: false, entries: Vec::new(), calltab: Vec::new(), shape_probe: Vec::new(), extra: [Value::NIL; 8], extra_n: 0, pending_error: None } }

    pub fn intern(&mut self, s: &str) -> Value { self.heap.intern(s, roots!(self)) }
    pub fn err(&self, msg: &str) -> ! { panic!("runtime error: {msg}") }

    // ---- tasks and frames -------------------------------------------------

    pub fn spawn(&mut self, fid: u32, args: &[Value]) -> usize {
        if self.jit_threshold != 0 { self.note_call(fid); }
        let f = &self.funcs[fid as usize];
        let words = f.frame_words();
        // A vararg entry's surplus arguments lie below its header.
        let nvar = if f.vararg { args.len().saturating_sub(f.nparams as usize) } else { 0 };
        // Only the header, the registers and the varargs are written below;
        // a pooled stack's other words are stale and never read before written
        // (the root walk filters words that are not live object slots).
        let need = nvar + words + 64;
        let stack = match self.stack_pool.pop() { Some(mut s) => { if s.len() < need { s.resize(need, 0); } s } None => vec![0u64; need] };
        let mut t = Task { stack, cur: nvar, state: State::Runnable, result: Value::NIL, deliver_at: 0, results: Vec::new() };
        for i in 0..nvar { t.stack[i] = args[f.nparams as usize + i].0; }
        let s0 = nvar;
        t.stack[s0] = fid as u64;
        t.stack[s0 + 1] = NONE as u64;
        t.stack[s0 + 2] = Value::NIL.0;
        t.stack[s0 + 3] = header3(0, false, words, nvar);
        for w in &mut t.stack[s0 + HDR..s0 + HDR + f.nregs as usize + 1] { *w = Value::NIL.0; }
        // Entry arguments follow the typed convention: float parameters land in
        // the float window, the rest in value registers, each in declaration order.
        let typed = f.sig.len() == f.nparams as usize;
        let (mut vi, mut fi) = (0usize, 0usize);
        let off_f = f.off_f();
        // Arguments past the declared parameters are dropped, as Lua drops them.
        for (i, &a) in args.iter().enumerate().take(f.nparams as usize) { if typed && f.sig[i] == b'f' { t.stack[s0 + off_f + fi] = a.as_num().to_bits(); fi += 1; } else { vi += 1; t.stack[s0 + HDR + vi] = a.0; } }
        self.tasks.push(t);
        self.tasks.len() - 1
    }
    /// Spawns a task running a closure value: its function with the closure
    /// in the frame header, so upvalues resolve.
    pub fn spawn_closure(&mut self, callee: Value, args: &[Value]) -> usize {
        if let Some(f) = callee.as_func() { return self.spawn(f, args); }
        let h = hdr!(self, callee, "spawn of a non-closure");
        if h.kind != KIND_CLOSURE { self.err("spawn of a non-closure") }
        let tid = self.spawn(h.fid(), args);
        { let t = &mut self.tasks[tid]; let s0 = t.cur(); t.stack[s0 + 2] = callee.0; }
        tid
    }
    pub fn resume(&mut self, tid: usize) { self.tasks[tid].state = State::Runnable; }
    /// Resumes a task parked on a host request with the completion's values
    /// in the registers the call named.
    pub fn resume_with(&mut self, tid: usize, outs: &[Value]) {
        let t = &mut self.tasks[tid];
        let at = t.cur + HDR + t.deliver_at;
        if outs.is_empty() { t.stack[at] = Value::NIL.0; }
        for (i, v) in outs.iter().take(8).enumerate() { t.stack[at + i] = v.0; }
        self.last_nres = outs.len().min(8);
        t.state = State::Runnable;
    }
    /// The task's frame chain, innermost first: function names and pcs.
    pub fn backtrace(&self, tid: usize) -> String {
        let t = &self.tasks[tid];
        if t.stack.is_empty() { return String::new(); }
        let mut out = String::new();
        let mut s = t.cur;
        loop {
            let h0 = t.stack[s]; let (fid, pc) = ((h0 & 0xffff_ffff) as usize, (h0 >> 32) as usize);
            let f = &self.funcs[fid];
            let pos = f.debug.get(pc.saturating_sub(1)).map(|(l, c)| format!(" (line {l}:{c})")).unwrap_or_default();
            out.push_str(&format!("  {} at pc {}{}\n", f.name, pc, pos));
            let caller = (t.stack[s + 1] & 0xffff_ffff) as u32;
            if caller == NONE { break; }
            s = caller as usize;
        }
        out
    }
    /// Value register `i` of task `tid`'s top frame.
    pub fn reg(&self, tid: usize, i: usize) -> Value { let t = &self.tasks[tid]; Value(t.stack[t.cur + HDR + i]) }

    /// Pushes the callee's frame after the caller's: saves the caller's pc,
    /// places the header, copies the value arguments from `args_at + 1..`
    /// into the callee's r1.. and records `args_at` as the result slot. The
    /// stack may move, so callers re-derive their pointers.
    #[inline(always)]
    /// A call of `fid` on an interpreted path: counted, and compiled at the
    /// threshold so the next call takes the entry.
    #[inline] pub fn note_call(&mut self, fid: u32) {
        if self.jit_threshold == 0 || self.entries.get(fid as usize).copied().unwrap_or(1) != 0 { return; }
        if let Some(fi) = self.finfo.get_mut(fid as usize) { if fi.calls < self.jit_threshold { fi.calls += 1; } if fi.calls >= self.jit_threshold { self.compile_now(fid); } }
    }
    #[cfg(feature = "jit")]
    fn compile_now(&mut self, fid: u32) {
        let Some(mut j) = self.jit.take() else { return };
        let f = self.funcs[fid as usize].clone();
        if !f.name.starts_with("module:") {
            let t0 = std::time::Instant::now();
            if let Ok(p) = j.try_compile(&f, fid) { self.entries[fid as usize] = p as u64; self.lazy_compiled += 1; }
            self.lazy_micros += t0.elapsed().as_micros() as u64;
        }
        if let Some(fi) = self.finfo.get_mut(fid as usize) { fi.calls = u32::MAX; }
        self.jit = Some(j);
    }
    #[cfg(not(feature = "jit"))]
    fn compile_now(&mut self, _fid: u32) {}
    fn push_frame(&mut self, tid: usize, f: u32, args_at: usize, nargs: u8, pc: usize) {
        if self.jit_threshold != 0 { self.note_call(f); }
        let callee = unsafe { self.funcs.get_unchecked(f as usize) };
        if self.trace { eprintln!("call {} nargs {}", callee.name, nargs); }
        if nargs >= 128 || callee.vararg { return self.push_frame_cold(tid, f, args_at, nargs, pc); }
        let words = callee.frame_words();
        let t = &mut self.tasks[tid];
        let s = t.cur;
        let caller_fid = t.stack[s] & 0xffff_ffff;
        t.stack[s] = caller_fid | ((pc as u64) << 32);
        let ns = s + frame_words_of(t.stack[s + 3]);
        if t.stack.len() < ns + words { let n = (ns + words).max(t.stack.len() * 2); t.stack.resize(n, 0); }
        // No other register is cleared: the root walk filters words that are
        // not live object slots (`Heap::is_live_slot`), and a register the
        // function reads before writing is a verifier error. Parameters the
        // call did not supply are nil, as the language promises.
        let nparams = callee.nparams as usize;
        unsafe {
            let st = t.stack.as_mut_ptr();
            *st.add(ns) = f as u64;
            *st.add(ns + 1) = s as u64 | ((args_at as u64) << 32);
            *st.add(ns + 2) = Value::NIL.0;
            *st.add(ns + 3) = header3(0, false, words, 0);
            for i in 0..nargs as usize { *st.add(ns + HDR + 1 + i) = *st.add(args_at + 1 + i); }
            for i in nargs as usize..nparams { *st.add(ns + HDR + 1 + i) = Value::NIL.0; }
        }
        t.cur = ns;
    }
    /// The slow call: a spread pack after the fixed arguments (`nargs` flagged
    /// by 128), a vararg callee packing its surplus, or both.
    #[inline(never)]
    fn push_frame_cold(&mut self, tid: usize, f: u32, args_at: usize, nargs: u8, pc: usize) {
        let (spread, fixed) = (nargs >= 128, (nargs & 127) as usize);
        let t = &mut self.tasks[tid];
        let s = t.cur;
        let mut args: Vec<u64> = (0..fixed).map(|i| t.stack[args_at + 1 + i]).collect();
        // A spread appends the caller's own vararg words, which lie below its header.
        if spread { let nv = nvar_of(t.stack[s + 3]); for i in 0..nv { args.push(t.stack[s - nv + i]); } }
        let (nparams, vararg) = { let c = &self.funcs[f as usize]; (c.nparams as usize, c.vararg) };
        let nvar = if vararg { args.len().saturating_sub(nparams) } else { 0 };
        let words = self.funcs[f as usize].frame_words();
        let t = &mut self.tasks[tid];
        let caller_fid = t.stack[s] & 0xffff_ffff;
        t.stack[s] = caller_fid | ((pc as u64) << 32);
        // The callee's surplus arguments go just below its header, in the frame.
        let ns = s + frame_words_of(t.stack[s + 3]) + nvar;
        if t.stack.len() < ns + words { let m = (ns + words).max(t.stack.len() * 2); t.stack.resize(m, 0); }
        for i in 0..nvar { t.stack[ns - nvar + i] = args[nparams + i]; }
        t.stack[ns] = f as u64;
        t.stack[ns + 1] = s as u64 | ((args_at as u64) << 32);
        t.stack[ns + 2] = Value::NIL.0;
        t.stack[ns + 3] = header3(0, false, words, nvar);
        for i in 0..nparams { t.stack[ns + HDR + 1 + i] = if i < args.len() { args[i] } else { Value::NIL.0 }; }
        t.cur = ns;
    }
    /// Pops the frame, delivering `v` to the caller's result register; true when
    /// the task is finished.
    #[inline]
    fn pop_frame(&mut self, tid: usize, v: Value) -> bool {
        let t = &mut self.tasks[tid];
        let s = t.cur;
        let h1 = t.stack[s + 1];
        let caller = (h1 & 0xffff_ffff) as u32;
        if caller == NONE { t.state = State::Done; t.result = v; return true; }
        let h3 = t.stack[s + 3];
        if (h3 >> 32) & 1 != 0 { t.stack[(h3 & 0xffff_ffff) as usize] = v.as_num().to_bits(); }
        else { t.stack[(h1 >> 32) as usize] = v.0; }
        t.cur = caller as usize;
        self.last_nres = 1;
        false
    }
    /// Pops the frame delivering `n` values from the callee's window at `from`
    /// (absolute) into the caller's result slots; true when the task finished.
    fn pop_frame_n(&mut self, tid: usize, from: usize, n: usize) -> bool {
        let t = &mut self.tasks[tid];
        let s = t.cur;
        let h1 = t.stack[s + 1];
        let caller = (h1 & 0xffff_ffff) as u32;
        let vals: Vec<Value> = (0..n).map(|i| Value(t.stack[from + i])).collect();
        if caller == NONE { t.state = State::Done; t.result = vals.first().copied().unwrap_or(Value::NIL); t.results = vals; return true; }
        let ret = (h1 >> 32) as usize;
        for (i, v) in vals.iter().take(8).enumerate() { t.stack[ret + i] = v.0; }
        if n == 0 { t.stack[ret] = Value::NIL.0; }
        t.cur = caller as usize;
        self.last_nres = n.min(8);
        false
    }
    /// Writes call results into the window from `at`, nil when there are none.
    #[inline]
    /// An argument count flagged 64 appends what the last call returned: its
    /// results already sit after the fixed arguments, so the count is plain
    /// arithmetic (at most the eight the frame's slack holds).
    pub fn spread_count(&self, nargs: u8) -> u8 { if nargs & 64 != 0 && nargs < 128 { (nargs & 63) + self.last_nres.min(8) as u8 } else { nargs } }
    fn deliver(&mut self, regs: *mut Value, at: usize, outs: &[Value]) {
        self.last_nres = outs.len().min(8);
        unsafe { if outs.is_empty() { *regs.add(at) = Value::NIL; } for (i, v) in outs.iter().take(8).enumerate() { *regs.add(at + i) = *v; } }
    }

    // ---- calls from the runtime ------------------------------------------

    /// The typed tier's entry for a function, if it has one.
    #[inline]
    pub fn entry_of(&self, fid: u32) -> u64 { self.entries.get(fid as usize).copied().unwrap_or(0) }
    /// Enters a compiled function with its closure and value arguments through
    /// a per-arity trampoline; the first result returns, extras through `extra`.
    #[cfg(feature = "compiled-runtime")]
    pub fn enter_compiled(&mut self, entry: u64, closure: Value, args: &[Value], nparams: usize) -> crate::builtins::Outs {
        use std::sync::atomic::{compiler_fence, Ordering::SeqCst};
        // Exactly the callee's parameters are passed, missing ones as nil:
        // a compiled function reads its parameter registers unconditionally.
        let mut padded = [Value::NIL; 8]; let n = nparams.min(8); for (i, v) in args.iter().take(n).enumerate() { padded[i] = *v; }
        let args = &padded[..n];
        crate::compiled::CUR_CLOSURE.store(closure.0, std::sync::atomic::Ordering::Relaxed);
        unsafe { std::ptr::write_volatile(&mut self.extra_n, 0); }
        compiler_fence(SeqCst);
        let a = |i: usize| args.get(i).map(|v| v.0).unwrap_or(Value::NIL.0);
        let r = unsafe { match args.len() {
            0 => std::mem::transmute::<u64, extern "C-unwind" fn() -> u64>(entry)(),
            1 => std::mem::transmute::<u64, extern "C-unwind" fn(u64) -> u64>(entry)(a(0)),
            2 => std::mem::transmute::<u64, extern "C-unwind" fn(u64, u64) -> u64>(entry)(a(0), a(1)),
            3 => std::mem::transmute::<u64, extern "C-unwind" fn(u64, u64, u64) -> u64>(entry)(a(0), a(1), a(2)),
            4 => std::mem::transmute::<u64, extern "C-unwind" fn(u64, u64, u64, u64) -> u64>(entry)(a(0), a(1), a(2), a(3)),
            5 => std::mem::transmute::<u64, extern "C-unwind" fn(u64, u64, u64, u64, u64) -> u64>(entry)(a(0), a(1), a(2), a(3), a(4)),
            6 => std::mem::transmute::<u64, extern "C-unwind" fn(u64, u64, u64, u64, u64, u64) -> u64>(entry)(a(0), a(1), a(2), a(3), a(4), a(5)),
            7 => std::mem::transmute::<u64, extern "C-unwind" fn(u64, u64, u64, u64, u64, u64, u64) -> u64>(entry)(a(0), a(1), a(2), a(3), a(4), a(5), a(6)),
            _ => std::mem::transmute::<u64, extern "C-unwind" fn(u64, u64, u64, u64, u64, u64, u64, u64) -> u64>(entry)(a(0), a(1), a(2), a(3), a(4), a(5), a(6), a(7)),
        } };
        // The callee's helpers wrote `extra` through another alias of this
        // interpreter; it is re-read volatile so the compiler cannot assume
        // the zero stored above.
        compiler_fence(SeqCst);
        // A raise inside came back as the sentinel: it continues as a panic
        // here, where Rust frames can carry it to the catch point.
        if Value(r) == Value::ERROR { let v = self.pending_error.take().unwrap_or(Value::NIL); std::panic::panic_any(crate::builtins::LuaError(v.0)); }
        let n = unsafe { std::ptr::read_volatile(&self.extra_n) }.min(7);
        let mut outs = crate::builtins::Outs::new();
        outs.push(Value(r));
        for i in 0..n { outs.push(unsafe { std::ptr::read_volatile(&self.extra[i]) }); }
        unsafe { std::ptr::write_volatile(&mut self.extra_n, 0); }
        self.last_nres = outs.len();
        outs
    }
    #[cfg(not(feature = "compiled-runtime"))]
    pub fn enter_compiled(&mut self, _entry: u64, _closure: Value, _args: &[Value], _nparams: usize) -> crate::builtins::Outs { unreachable!("no typed tier in this build") }
    /// Calls any callable value on a scratch task and returns every result:
    /// the path for builtins that call back (gsub) and for module chunks.
    pub fn call_value(&mut self, callee: Value, args: &[Value]) -> Vec<Value> {
        if let Some(id) = callee.as_builtin() { return crate::builtins::call(self, id, args).to_vec(); }
        let (fid, closure) = if let Some(f) = callee.as_func() { (f, Value::NIL) } else {
            let h = hdr!(self, callee, &format!("call_value of a non-function {:#x}", callee.0));
            match h.kind { KIND_CLOSURE => (h.fid(), callee), KIND_ITER => return crate::builtins::iter_next(self, callee).to_vec(), KIND_TABLE => { let f = self.call_handler(callee); if f == Value::NIL { self.err("call of a table without __call") } let mut full = Vec::with_capacity(args.len() + 1); full.push(callee); full.extend_from_slice(args); return self.call_value(f, &full); } _ => self.err(&format!("call_value of a non-function object ({})", Heap::describe(h))) }
        };
        let entry = self.entry_of(fid);
        if entry != 0 && !self.funcs[fid as usize].vararg { let np = self.funcs[fid as usize].nparams as usize; return self.enter_compiled(entry, closure, args, np).to_vec(); }
        let scratch = self.spawn(fid, args);
        { let t = &mut self.tasks[scratch]; let s0 = t.cur(); t.stack[s0 + 2] = closure.0; }
        let outcome = self.run(scratch);
        let outs = match outcome { Outcome::Done(v) => { let t = &self.tasks[scratch]; if t.results.is_empty() { vec![v] } else { t.results.clone() } } Outcome::Parked(_) => self.err("a callback parked") };
        if let Some(t) = self.tasks.pop() { if self.stack_pool.len() < 64 { self.stack_pool.push(t.stack); } }
        self.tasks.truncate(scratch);
        outs
    }
    /// `call_value` without a heap allocation on the builtin path.
    pub fn call_outs(&mut self, callee: Value, args: &[Value]) -> crate::builtins::Outs {
        #[cfg(feature = "compiled-runtime")]
        if self.ic_stats { let i = if callee.as_builtin().is_some() { 4 } else { match callee.as_obj() { Some(p) => { let h = unsafe { &*p.as_ptr() }; if h.kind == KIND_CLOSURE && self.entry_of(h.fid()) != 0 && !self.funcs[h.fid() as usize].vararg { 5 } else { 6 } } None => if callee.as_func().map(|f| self.entry_of(f) != 0).unwrap_or(false) { 5 } else { 6 } } }; crate::compiled::IC_STATS[i].fetch_add(1, std::sync::atomic::Ordering::Relaxed); if i == 6 { let fid = match callee.as_obj() { Some(p) => unsafe { (*p.as_ptr()).fid() }, None => callee.as_func().unwrap_or(u32::MAX) }; let mut g = crate::compiled::INTERP_CALLEES.lock().unwrap(); *g.get_or_insert_with(Default::default).entry(fid).or_insert(0) += 1; } }
        if let Some(id) = callee.as_builtin() { return crate::builtins::call(self, id, args); }
        if let Some(f) = callee.as_func() { let e = self.entry_of(f); if e != 0 && !self.funcs[f as usize].vararg { let np = self.funcs[f as usize].nparams as usize; return self.enter_compiled(e, Value::NIL, args, np); } }
        if let Some(p) = callee.as_obj() { let h = unsafe { &*p.as_ptr() }; if h.kind == KIND_ITER { return crate::builtins::iter_next(self, callee); } if h.kind == KIND_CLOSURE { let e = self.entry_of(h.fid()); if e != 0 && !self.funcs[h.fid() as usize].vararg { let np = self.funcs[h.fid() as usize].nparams as usize; return self.enter_compiled(e, callee, args, np); } } }
        self.call_value(callee, args).into_iter().collect()
    }
    /// Copy fixed arguments and, when flagged, the current frame's varargs.
    /// Trailing-call result counts have already been resolved by the caller.
    pub(crate) fn call_args(&self, tid: usize, start: usize, nargs: u8) -> CallArgs {
        let t = &self.tasks[tid];
        let fixed = (nargs & 127) as usize;
        let nv = if nargs >= 128 { nvar_of(t.stack[t.cur + 3]) } else { 0 };
        let mut args = CallArgs::new(fixed + nv);
        let out = args.as_mut_slice();
        for i in 0..fixed { out[i] = Value(t.stack[start + i]); }
        for i in 0..nv { out[fixed + i] = Value(t.stack[t.cur - nv + i]); }
        args
    }
    /// What `recv:name(...)` calls: a record's shape method, else a field of
    /// the record or table holding a function (`{define = Registry.define}`
    /// and the Lua class idiom). Strings are handled by the callers.
    pub fn resolve_method(&mut self, recv: Value, name: Value) -> Value {
        let h = hdr!(self, recv, "method call on a non-object");
        if h.kind == KIND_RECORD { if let Some(m) = self.heap.shapes[h.shape() as usize].methods.get(&name) { return *m; } }
        if h.kind == KIND_RECORD || h.kind == KIND_TABLE { let v = self.index(recv, name); if v != Value::NIL { return v; } }
        self.err(&format!("no such method {}", String::from_utf8_lossy(self.bytes_of(name))))
    }
    pub fn call_method(&mut self, name: Value, args: &[Value]) -> Vec<Value> {
        let recv = args[0];
        let h = hdr!(self, recv, "method call on a non-object");
        if h.is_stringish() {
            let mname = String::from_utf8_lossy(self.bytes_of(name)).to_string();
            let id = crate::builtins::id_of(&format!("string.{mname}")).unwrap_or_else(|| self.err(&format!("no string method {mname}")));
            return crate::builtins::call(self, id, args).to_vec();
        }
        let method = self.resolve_method(recv, name);
        self.call_value(method, args)
    }
    /// pcall as values: ok first, then the results or the error value.
    pub fn pcall_values(&mut self, callee: Value, args: &[Value]) -> Vec<Value> {
        let hook = std::panic::take_hook(); std::panic::set_hook(Box::new(|_| {}));
        let outcome = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| self.call_value(callee, args)));
        std::panic::set_hook(hook);
        match outcome {
            Ok(mut vals) => { vals.insert(0, Value::TRUE); vals }
            Err(payload) => { let v = self.error_value(payload); vec![Value::FALSE, v] }
        }
    }
    /// Runs `body` and, when it raises, parks the value in `pending_error`
    /// and answers the sentinel: the boundary where a Rust panic becomes a
    /// VM-level raise that compiled code and the threaded core return upward.
    #[inline]
    pub fn guarded(&mut self, body: impl FnOnce(&mut Interp) -> Value) -> Value {
        let r = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| body(self)));
        match r { Ok(v) => v, Err(p) => { let v = self.error_value(p); self.pending_error = Some(v); Value::ERROR } }
    }
    /// The value an unwinding error carries: `error`'s value, or the message.
    pub fn error_value(&mut self, payload: Box<dyn std::any::Any + Send>) -> Value {
        if let Some(e) = payload.downcast_ref::<crate::builtins::LuaError>() { return Value(e.0); }
        let msg = payload.downcast_ref::<String>().cloned().or_else(|| payload.downcast_ref::<&str>().map(|s| s.to_string())).unwrap_or_default();
        self.intern(&msg)
    }
    /// The export value of a module, running its chunk the first time.
    pub fn require(&mut self, name: &str) -> Value {
        if let Some(v) = self.loaded.get(name) { return *v; }
        // Raised as Lua's `require` raises it, message and all: a module that
        // probes for an optional one reads the prefix.
        let fid = match self.modules.get(name) { Some(f) => *f, None => { let msg = self.heap_new_string(&format!("module '{name}' not found: not in the image")); std::panic::panic_any(crate::builtins::LuaError(msg.0)) } };
        let outs = self.call_value(Value::func(fid), &[]);
        let v = outs.first().copied().unwrap_or(Value::NIL);
        self.registered.push(v);
        self.loaded.insert(name.to_string(), v);
        if self.loaded_table != Value::NIL { let h = self.register(v); let k = self.heap_new_string(name); self.set_index(self.loaded_table, k, v); self.release(h); }
        v
    }

    // ---- host services on the parking surface (6.3) ----------------------

    /// A host service by id: `Ok` with the results when it answers at once,
    /// `Err(key)` when the request was submitted and the caller must park.
    pub fn host_call(&mut self, id: u32, args: &[Value]) -> Result<crate::builtins::Outs, u64> {
        use crate::host::{Req, HOST_BASE};
        let k = (id - HOST_BASE) as usize;
        let text = |it: &Interp, i: usize| -> String { args.get(i).map(|v| it.bytes_of(*v)).map(|b| String::from_utf8_lossy(b).into_owned()).unwrap_or_default() };
        let num = |i: usize| -> f64 { args.get(i).map(|v| v.as_num()).unwrap_or(0.0) };
        let mut outs = crate::builtins::Outs::new();
        match k {
            5 => { let t = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_secs_f64(); outs.push(Value::num(t)); return Ok(outs); }
            6 => { let name = text(self, 0); match std::env::var(&name) { Ok(v) => { let s = self.heap_new_string(&v); outs.push(s); } Err(_) => outs.push(Value::NIL) } return Ok(outs); }
            _ => {}
        }
        let req = match k {
            0 => Req::ReadFile(text(self, 0)),
            1 => { let data = args.get(1).map(|v| self.bytes_of(*v).to_vec()).unwrap_or_default(); Req::WriteFile(text(self, 0), data) }
            2 => Req::Sleep(num(0).max(0.0) as u64),
            3 => { let n = args.len(); let argv: Vec<String> = (1..n).map(|i| text(self, i)).collect(); Req::Run(text(self, 0), argv) }
            4 => Req::ListDir(text(self, 0)),
            _ => self.err("unknown host service"),
        };
        let host = self.host.as_mut().unwrap_or_else(|| panic!("runtime error: host services not started"));
        Err(host.submit(req))
    }
    /// Turns a completion into values and resumes the task that waited on it.
    pub fn complete(&mut self, key: u64, done: crate::host::Done) {
        use crate::host::Done;
        let tid = self.host_waiters.remove(&key).expect("completion for no waiter");
        let scope = self.open_scope();
        let mut outs: Vec<Value> = Vec::new();
        let push_err = |it: &mut Interp, outs: &mut Vec<Value>, e: String| { outs.push(Value::NIL); let s = it.heap_new_string(&e); it.handles.push(s); outs.push(s); };
        match done {
            Done::Text(Ok(t)) => { let s = self.heap_new_string(&t); self.handles.push(s); outs.push(s); }
            Done::Text(Err(e)) => push_err(self, &mut outs, e),
            Done::Unit(Ok(())) => outs.push(Value::TRUE),
            Done::Unit(Err(e)) => push_err(self, &mut outs, e),
            Done::Exit(Ok((code, out))) => { outs.push(Value::num(code as f64)); let s = self.heap_new_string(&out); self.handles.push(s); outs.push(s); }
            Done::Exit(Err(e)) => push_err(self, &mut outs, e),
            Done::List(Ok(names)) => { let t = self.new_table(); self.handles.push(t); for (i, n) in names.iter().enumerate() { let s = self.heap_new_string(n); self.handles.push(s); self.set_index(t, Value::num((i + 1) as f64), s); } outs.push(t); }
            Done::List(Err(e)) => push_err(self, &mut outs, e),
        }
        // The values are held by the scope until the task's registers hold them.
        self.resume_with(tid, &outs);
        self.close_scope(scope);
    }
    /// The global tables the compiler's modules reach for (`bit`, `os`, `io`,
    /// `package`, `_G`), served by `require` as runtime-provided modules.
    pub fn install_globals(&mut self) {
        // The stub behind `loadstring`'s closures: `return <upvalue 0>`.
        self.literal_fid = self.funcs.len() as u32;
        self.funcs.push(Function { name: "loadstring.literal".to_string(), module: String::new(), code: vec![Op::GetUpval(1, 0), Op::GetCell(2, 1), Op::Ret(2)], consts: Vec::new(), nparams: 0, nregs: 4, nireg: 1, nfreg: 1, nvreg: 2, sig: Vec::new(), ret: b'v', nv_params: 0, nf_params: 0, jump_tables: Vec::new(), debug: Vec::new(), vararg: false, ins: Vec::new() });
        self.unavailable_fid = self.funcs.len() as u32;
        let msg = self.intern("a chunk loaded from Lua source cannot run: this runtime evaluates no Lua"); self.registered.push(msg);
        let err_id = crate::builtins::id_of("error").unwrap();
        self.funcs.push(Function { name: "loadstring.unavailable".to_string(), module: String::new(), code: vec![Op::K(1, 0), Op::K(2, 1), Op::CallDyn(1, 1, 1), Op::RetNil], consts: vec![Value::builtin(err_id), msg], nparams: 0, nregs: 12, nireg: 1, nfreg: 1, nvreg: 2, sig: Vec::new(), ret: b'v', nv_params: 0, nf_params: 0, jump_tables: Vec::new(), debug: Vec::new(), vararg: false, ins: Vec::new() });
        let table_of = |it: &mut Interp, entries: &[&str]| { let t = it.new_table(); it.registered.push(t); for name in entries { let full = name.to_string(); let short = full.split('.').nth(1).unwrap_or(&full).to_string(); let k = it.intern(&short); let id = crate::builtins::id_of(&full).unwrap_or_else(|| panic!("no builtin {full}")); it.set_index(t, k, Value::builtin(id)); } t };
        let bit = table_of(self, &["bit.band", "bit.bor", "bit.bxor", "bit.bnot", "bit.lshift", "bit.rshift", "bit.arshift", "bit.tobit"]);
        let os = table_of(self, &["os.getenv", "os.clock", "os.time", "os.remove", "os.tmpname", "os.execute", "os.rename"]);
        let io = table_of(self, &["io.write", "io.open", "io.read"]);
        // The standard streams: objects whose `write` is a method.
        for (field, name) in [("stderr", "io.stderr.write"), ("stdout", "io.stdout.write")] { let stream = table_of(self, &[name]); let k = self.intern(field); self.set_index(io, k, stream); }
        let debug = table_of(self, &["debug.getinfo"]);
        // The file-system minimum behind `nupp.io.files` and `nupp.io.path`, as
        // modules: a `require` finds them before the image's.
        let files = table_of(self, &["files.info", "files.isDirectory", "files.list", "files.createDirectory", "files.exists", "files.isFile"]);
        let path = table_of(self, &["path.currentDirectory", "path.newPath"]);
        for (name, t) in [("nupp.io.files", files), ("nupp.io.path", path)] { self.loaded.insert(name.to_string(), t); }
        let package = self.new_table(); self.registered.push(package);
        { let loaded = self.new_table(); self.registered.push(loaded); self.loaded_table = loaded; let k = self.intern("loaded"); self.set_index(package, k, loaded); }
        { let preload = self.new_table(); self.registered.push(preload); let k = self.intern("preload"); self.set_index(package, k, preload); let v = self.heap_new_string("/\n;\n?\n!\n-\n"); let vh = self.register(v); let k = self.intern("config"); self.set_index(package, k, v); self.release(vh); let v = self.intern(""); let vh = self.register(v); let k = self.intern("path"); self.set_index(package, k, v); self.release(vh); }
        let g = self.new_table(); self.registered.push(g);
        for (name, t) in [("bit", bit), ("os", os), ("io", io), ("package", package), ("debug", debug)] { let k = self.intern(name); self.set_index(g, k, t); }
        for name in ["pairs", "ipairs", "next", "type", "tostring", "tonumber", "error", "assert", "select", "print", "pcall"] { let k = self.intern(name); let id = crate::builtins::id_of(name).unwrap(); self.set_index(g, k, Value::builtin(id)); }
        let k = self.intern("_G"); self.set_index(g, k, g);
        for (name, t) in [("bit", bit), ("os", os), ("io", io), ("package", package), ("debug", debug), ("_G", g)] { self.loaded.insert(name.to_string(), t); let k = self.intern(name); self.set_index(self.loaded_table, k, t); }
    }
    /// The host table a module gets from `require`: one builtin per service.
    pub fn host_table(&mut self) -> Value {
        let t = self.new_table(); self.registered.push(t);
        for (i, name) in crate::host::HOST_NAMES.iter().enumerate() { let k = self.intern(name); self.set_index(t, k, Value::builtin(crate::host::HOST_BASE + i as u32)); }
        t
    }

    // ---- roots held by native code (4.7) ---------------------------------

    /// Opens a handle scope: the mark to close it with.
    pub fn open_scope(&self) -> usize { self.handles.len() }
    /// Closes a scope, releasing every handle pushed since it opened.
    pub fn close_scope(&mut self, mark: usize) { self.handles.truncate(mark); }
    /// A root the caller keeps until it releases it.
    pub fn register(&mut self, v: Value) -> usize { self.registered.push(v); self.registered.len() - 1 }
    pub fn release(&mut self, h: usize) { self.registered[h] = Value::NIL; }
    pub fn full_cycle(&mut self) { self.heap.full_cycle(roots!(self)) }
    pub fn check_oracle(&self) { self.heap.check_oracle(roots!(self)) }

    // ---- objects ----------------------------------------------------------

    pub fn new_table(&mut self) -> Value { self.heap.new_table(roots!(self)) }
    pub fn new_table_sized(&mut self, n: usize, m: usize) -> Value { self.heap.new_table_sized(n, m, roots!(self)) }
    pub fn new_record(&mut self, shape: u32) -> Value { self.heap.new_record(shape, roots!(self)) }
    pub fn new_storage(&mut self, n: usize) -> Value { self.heap.new_storage(n, roots!(self)) }
    pub fn new_cell(&mut self, v: Value) -> Value { self.heap.new_cell(v, roots!(self)) }
    pub fn new_closure(&mut self, fid: u32, caps: &[Value]) -> Value { self.heap.new_closure(fid, caps, roots!(self)) }
    pub fn new_slice(&mut self, src: Value, off: u32, len: u32) -> Value { let scope = self.open_scope(); self.handles.push(src); let v = self.heap.new_slice(src, off, len, roots!(self)); self.close_scope(scope); v }
    pub fn new_iter(&mut self, kind: u8, obj: Value, pattern: Value) -> Value { self.heap.new_iter(kind, obj, pattern, Vec::new(), roots!(self)) }
    pub fn new_iter_keys(&mut self, kind: u8, obj: Value, keys: Vec<Value>) -> Value { self.heap.new_iter(kind, obj, Value::NIL, keys, roots!(self)) }
    pub fn heap_new_bytes(&mut self, n: usize) -> Value { self.heap.new_bytes(n, roots!(self)) }
    pub fn heap_new_buffer(&mut self) -> Value { self.heap.new_buffer(roots!(self)) }
    /// A string that is not interned: long results, as Lua 5.4 treats them.
    pub fn heap_new_string(&mut self, text: &str) -> Value { self.heap.new_string(text, roots!(self)) }
    pub fn new_string_bytes(&mut self, b: &[u8]) -> Value { self.heap.new_string_bytes(b, roots!(self)) }
    /// A string with these bytes: interned when short (1.3), fresh otherwise.
    pub fn string_of(&mut self, b: &[u8]) -> Value {
        if b.len() <= 40 { let s = unsafe { std::str::from_utf8_unchecked(b) }.to_string(); self.intern(&s) } else { self.new_string_bytes(b) }
    }

    pub fn bytes_of(&self, v: Value) -> &[u8] {
        let h = hdr!(self, v, &format!("bytes of a non-object {:#x}", v.0));
        match h.kind { KIND_STR | KIND_SLICE | KIND_BYTES => h.bytes(), _ => self.err(&format!("not bytes ({})", Heap::describe(h))) }
    }
    pub fn bytes_mut(&self, v: Value) -> &mut [u8] {
        let h = hdr!(self, v, "bytes of a non-object");
        if h.kind != KIND_BYTES { self.err("not a byte buffer") }
        h.bytes_mut()
    }
    pub fn is_stringish(&self, v: Value) -> bool { v.as_obj().map(|p| unsafe { (*p.as_ptr()).is_stringish() }).unwrap_or(false) }
    pub fn kind_of(&self, v: Value) -> Option<u8> { v.as_obj().map(|p| unsafe { (*p.as_ptr()).kind }) }
    /// Equality: identical words, or two string-like objects with the same bytes.
    pub fn values_equal(&self, x: Value, y: Value) -> bool {
        if x == y { return true; }
        if let (Some(p), Some(q)) = (x.as_obj(), y.as_obj()) {
            let (a, b) = unsafe { (&*p.as_ptr(), &*q.as_ptr()) };
            // Two interned strings with different words differ (1.3).
            if a.flags & heap::F_INTERNED != 0 && b.flags & heap::F_INTERNED != 0 { return false; }
            if a.is_stringish() && b.is_stringish() { return a.bytes() == b.bytes(); }
        }
        false
    }
    /// A table key by content: a slice or an uninterned string is looked up
    /// as the interned string with those bytes, or none, in which case the
    /// key is absent.
    fn key_of(&mut self, key: Value) -> Option<Value> {
        if let Some(h) = key.as_obj().map(|p| unsafe { &*p.as_ptr() }) {
            if h.kind == KIND_SLICE || (h.kind == KIND_STR && h.flags & heap::F_INTERNED == 0) { let s = unsafe { std::str::from_utf8_unchecked(h.bytes()) }.to_string(); return self.heap.intern_lookup(&s); }
        }
        Some(key)
    }
    /// The key as stored: interned when it is a slice or an uninterned string.
    pub fn key_for_store(&mut self, key: Value) -> Value {
        match self.key_of(key) { Some(k) => k, None => { let s = unsafe { std::str::from_utf8_unchecked(self.bytes_of(key)) }.to_string(); self.intern(&s) } }
    }

    pub fn get_index(&self, tv: Value, key: Value) -> Value {
        let h = hdr!(self, tv, "index of a non-table");
        if TABLE_STATS.load(std::sync::atomic::Ordering::Relaxed) { let i = match h.kind { KIND_TABLE => if key.is_num() { 0 } else { 1 }, KIND_RECORD => if key.is_num() { 2 } else { 3 }, _ => 4 }; TABLE_COUNTS[i].fetch_add(1, std::sync::atomic::Ordering::Relaxed); if h.kind == KIND_TABLE && !key.is_num() { let n = h.table_ref().hash.len(); let b = if n == 0 { 5 } else if n <= 4 { 6 } else if n <= 16 { 7 } else if n <= 64 { 8 } else { 9 }; TABLE_COUNTS[b].fetch_add(1, std::sync::atomic::Ordering::Relaxed); } }
        match h.kind {
            KIND_TABLE => { let t = h.table_ref(); if key.is_num() { let n = key.as_num(); if n >= 1.0 && (n as usize) <= t.array.len() && n.fract() == 0.0 { return t.array[n as usize - 1]; } } *t.hash.get(&key).unwrap_or(&Value::NIL) }
            KIND_RECORD => { if key.is_num() { let n = key.as_num(); let a = h.record_array_ref(); return if n >= 1.0 && (n as usize) <= a.len() && n.fract() == 0.0 { a[n as usize - 1] } else { Value::NIL }; } let sh = &self.heap.shapes[h.shape() as usize]; match sh.names.iter().position(|n| *n == key) { Some(i) => h.slots()[i], None => h.record_extra_ref().as_ref().and_then(|m| m.get(&key).copied()).unwrap_or(Value::NIL) } }
            _ => self.err(&format!("index of a non-table ({})", Heap::describe(h))),
        }
    }
    /// An index read whose key may be a slice: by content, then as `get_index`.
    pub fn get_index_any(&mut self, t: Value, k: Value) -> Value { match self.key_of(k) { Some(k) => self.get_index(t, k), None => Value::NIL } }
    pub fn set_index(&mut self, tv: Value, iv: Value, v: Value) {
        if TABLE_STATS.load(std::sync::atomic::Ordering::Relaxed) { TABLE_COUNTS[if iv.is_num() { 10 } else { 11 }].fetch_add(1, std::sync::atomic::Ordering::Relaxed); }
        let iv = self.key_for_store(iv);
        let p = tv.as_obj().unwrap_or_else(|| self.err("index of a non-table"));
        self.heap.barrier(p, iv);
        self.heap.barrier(p, v);
        let h = unsafe { &mut *p.as_ptr() };
        match h.kind {
            // `t[#t] = nil` shrinks the array part, as Lua's border rule reads it.
            KIND_TABLE => { let t = h.table(); if iv.is_num() && iv.as_num() >= 1.0 && iv.as_num().fract() == 0.0 && (iv.as_num() as usize) <= t.array.len() + 1 { let k = iv.as_num() as usize; if k == t.array.len() + 1 { if v != Value::NIL { t.array.push(v) } } else { t.array[k - 1] = v; if v == Value::NIL && k == t.array.len() { while t.array.last() == Some(&Value::NIL) { t.array.pop(); } } } } else { t.hash.insert(iv, v); } h.refresh(); }
            // A record written by name: the shape is closed, so an unknown name is an error.
            KIND_RECORD => {
                if iv.is_num() { let n = iv.as_num(); let a = h.record_array(); if n >= 1.0 && n.fract() == 0.0 && (n as usize) <= a.len() + 1 { let k = n as usize; if k == a.len() + 1 { if v != Value::NIL { a.push(v) } } else { a[k - 1] = v; if v == Value::NIL && k == a.len() { while a.last() == Some(&Value::NIL) { a.pop(); } } } return; } self.err("record index outside its children") }
                let sh = &self.heap.shapes[h.shape() as usize]; match sh.slot_of(iv) { Some(i) => h.slots_mut()[i] = v, None => { h.record_extra().get_or_insert_with(Default::default).insert(iv, v); } }
            }
            _ => self.err(&format!("index of a non-table ({})", Heap::describe(h))),
        }
    }
    /// A slot access whose object is not of the shape the site assumed (a
    /// struct-shaped table cast to the record, say): by the slot's name.
    pub fn slot_get_slow(&self, o: Value, shape: u32, slot: u16) -> Value { let name = self.heap.shapes[shape as usize].names[slot as usize]; self.get_index(o, name) }
    pub fn slot_set_slow(&mut self, o: Value, shape: u32, slot: u16, v: Value) { let name = self.heap.shapes[shape as usize].names[slot as usize]; self.set_index(o, name, v) }
    /// A table's metatable, or nil (records and other objects have none).
    pub fn metatable_of(&self, t: Value) -> Value { match t.as_obj() { Some(p) => { let h = unsafe { &*p.as_ptr() }; if h.kind == KIND_TABLE { h.table_ref().meta } else { Value::NIL } } None => Value::NIL } }
    fn meta_field(&mut self, t: Value, name: &str) -> Value { let m = self.metatable_of(t); if m == Value::NIL { return Value::NIL; } match self.heap.intern_lookup(name) { Some(k) => self.get_index(m, k), None => Value::NIL } }
    /// A read that follows `__index` (a function or a table) when a table
    /// lacks the key; raw for records and anything else.
    pub fn index(&mut self, t: Value, key: Value) -> Value {
        let mut t = t;
        for _ in 0..100 {
            let v = self.get_index(t, key);
            if v != Value::NIL { return v; }
            let h = self.meta_field(t, "__index");
            if h == Value::NIL { return Value::NIL; }
            if h.as_obj().map(|p| unsafe { (*p.as_ptr()).kind } == KIND_TABLE).unwrap_or(false) { t = h; continue; }
            let outs = self.call_value(h, &[t, key]);
            return outs.first().copied().unwrap_or(Value::NIL);
        }
        self.err("__index chain too long")
    }
    pub fn index_any(&mut self, t: Value, k: Value) -> Value { match self.key_of(k) { Some(k) => self.index(t, k), None => Value::NIL } }
    /// A store that calls `__newindex` when a table lacks the key and its
    /// metatable has one; raw otherwise.
    pub fn newindex(&mut self, t: Value, key: Value, v: Value) {
        if self.metatable_of(t) != Value::NIL && self.get_index(t, key) == Value::NIL {
            let h = self.meta_field(t, "__newindex");
            if h != Value::NIL {
                if h.as_obj().map(|p| unsafe { (*p.as_ptr()).kind } == KIND_TABLE).unwrap_or(false) { return self.newindex(h, key, v); }
                self.call_value(h, &[t, key, v]); return;
            }
        }
        self.set_index(t, key, v)
    }
    /// The function behind a callable table (`__call`), or nil.
    pub fn call_handler(&mut self, t: Value) -> Value { self.meta_field(t, "__call") }
    pub fn get_field(&self, t: Value, name: Value) -> Value { self.get_index(t, name) }
    pub fn set_field(&mut self, t: Value, name: Value, v: Value) { self.set_index(t, name, v) }
    pub fn get_slot(&self, rec: Value, i: usize) -> Value { hdr!(self, rec, "not a record").slots()[i] }
    pub fn set_slot(&mut self, rec: Value, i: usize, v: Value) { let p = rec.as_obj().unwrap(); self.heap.barrier(p, v); unsafe { (*p.as_ptr()).slots_mut()[i] = v; } }
    pub fn set_cell(&mut self, c: Value, v: Value) { let p = c.as_obj().unwrap_or_else(|| self.err("not a cell")); self.heap.barrier(p, v); unsafe { if (*p.as_ptr()).kind != KIND_CELL { self.err("not a cell") } (*p.as_ptr()).slots_mut()[0] = v; } }
    pub fn is_rec(&self, v: Value, shape: u32) -> bool { v.as_obj().map(|p| unsafe { let h = &*p.as_ptr(); h.kind == KIND_RECORD && h.shape() == shape }).unwrap_or(false) }
    pub fn tagcheck_rec(&self, v: Value, shape: u32) { let ok = v.as_obj().map(|p| unsafe { let h = &*p.as_ptr(); h.kind == KIND_RECORD && h.shape() == shape }).unwrap_or(false); if !ok { self.err("value is not an instance of the expected record") } }
    pub fn array_len(&self, t: Value) -> usize { let h = hdr!(self, t, "length of a non-table"); match h.kind { KIND_TABLE => h.table_ref().array.len(), KIND_RECORD => h.record_array_ref().len(), _ => self.err("length of a non-table") } }
    pub fn array_get(&self, t: Value, i: usize) -> Value { hdr!(self, t, "not a table").table_ref().array[i] }
    pub fn push_array(&mut self, t: Value, v: Value) { let p = t.as_obj().unwrap(); self.heap.barrier(p, v); unsafe { let h = &mut *p.as_ptr(); h.table().array.push(v); h.refresh(); } }
    pub fn pop_array(&mut self, t: Value) { let h = hdr!(self, t, "not a table"); let a = if h.kind == KIND_RECORD { h.record_array() } else { &mut h.table().array }; while a.last() == Some(&Value::NIL) { a.pop(); } h.refresh(); }
    /// Every key of a table, array part first, for `pairs` and `next`.
    pub fn table_keys(&self, t: Value) -> Vec<Value> {
        let h = hdr!(self, t, "pairs of a non-table");
        match h.kind {
            KIND_TABLE => { let tb = h.table_ref(); let mut keys: Vec<Value> = (1..=tb.array.len()).filter(|&i| tb.array[i - 1] != Value::NIL).map(|i| Value::num(i as f64)).collect(); keys.extend(tb.hash.iter().map(|(k, _)| *k)); keys }
            KIND_RECORD => { let a = h.record_array_ref(); let mut keys: Vec<Value> = (1..=a.len()).map(|i| Value::num(i as f64)).collect(); keys.extend(self.heap.shapes[h.shape() as usize].names.iter().copied()); if let Some(m) = h.record_extra_ref() { keys.extend(m.keys().copied()); } keys }
            _ => self.err("pairs of a non-table"),
        }
    }
    pub fn iter_state(&self, it: Value) -> (u8, Value, usize, usize) { let h = hdr!(self, it, "not an iterator"); if h.kind != KIND_ITER { self.err("not an iterator") } let kind = h.aux as u8; let i = h.iter(); (kind, i.obj, i.pos, i.keys.len()) }
    pub fn iter_key(&self, it: Value, i: usize) -> Value { hdr!(self, it, "not an iterator").iter().keys[i] }
    pub fn iter_pattern(&self, it: Value) -> Value { hdr!(self, it, "not an iterator").iter().pattern }
    pub fn iter_advance(&self, it: Value) { hdr!(self, it, "not an iterator").iter().pos += 1; }
    pub fn iter_set_pos(&self, it: Value, at: usize) { hdr!(self, it, "not an iterator").iter().pos = at; }
    /// Lua's substring clamping: 1-based inclusive, out-of-range ends clamp, an empty range is empty.
    pub fn sub_bytes(&self, v: Value, i: i64, j: i64) -> &[u8] {
        let b = self.bytes_of(v);
        let n = b.len() as i64;
        let i = if i < 1 { 1 } else { i };
        let j = if j > n { n } else { j };
        if i > j { &b[0..0] } else { &b[(i - 1) as usize..j as usize] }
    }
    /// The buffer's bytes become a string: the buffer is empty after a finish.
    pub fn buf_finish(&mut self, buf: Value) -> Value {
        let h = hdr!(self, buf, "finish of a non-buffer");
        if h.kind != KIND_BYTES { self.err("not a buffer") }
        let bytes = std::mem::take(&mut h.byte_buffer().data);
        h.refresh();
        self.string_of(&bytes)
    }
    pub fn buf_append(&mut self, buf: Value, text: &[u8]) {
        let h = hdr!(self, buf, "append to a non-buffer");
        if h.kind != KIND_BYTES { self.err("not a buffer") }
        h.byte_buffer().data.extend_from_slice(text);
        h.refresh();
    }
    pub fn concat(&mut self, x: Value, y: Value) -> Value {
        let mut joined: Vec<u8> = Vec::new();
        for v in [x, y] { if v.is_num() { joined.extend_from_slice(crate::builtins::num_text(v.as_num()).as_bytes()); } else if self.is_stringish(v) { joined.extend_from_slice(self.bytes_of(v)); } else { self.err("concatenate a non-string") } }
        self.string_of(&joined)
    }

    fn arith(&self, a: Value, b: Value, op: fn(f64, f64) -> f64) -> Value {
        if a.is_num() && b.is_num() { Value::num(op(a.as_num(), b.as_num())) } else { self.err("arithmetic on a non-number") }
    }
    fn slot_type_ok(&self, ty: SlotTy, v: Value) -> bool {
        match ty {
            SlotTy::Any => true,
            SlotTy::Num => v.is_num(),
            SlotTy::Bool => v == Value::TRUE || v == Value::FALSE,
            SlotTy::Str => self.is_stringish(v),
            SlotTy::Record(s) => v.as_obj().map(|p| unsafe { let h = &*p.as_ptr(); h.kind == KIND_RECORD && h.shape() == s }).unwrap_or(false),
        }
    }
    #[inline]
    fn back_edge(&mut self) {
        self.back_edges += 1;
        if self.back_edges & 255 == 0 { self.heap.safepoint(roots!(self)); }
    }
    /// The float storage behind a value, for the typed tier's loads and stores.
    fn storage(&self, v: Value) -> &mut Vec<f64> { let h = hdr!(self, v, "not storage"); if h.kind != KIND_STORAGE { self.err("not storage") } &mut h.storage().data }

    // ---- the dispatch loop -------------------------------------------------

    /// Run task `tid` until it finishes or parks: on the threaded core when
    /// it is built and enabled, else on the Rust loop.
    pub fn run(&mut self, tid: usize) -> Outcome { if self.threaded { self.run_threaded(tid) } else { self.run_rust(tid) } }
    /// The Rust dispatch loop: the fallback (`NO_THREADED=1`) and the
    /// reference the threaded core's results are checked against.
    pub fn run_rust(&mut self, tid: usize) -> Outcome {
        assert_eq!(self.tasks[tid].state, State::Runnable);
        loop {
            let (win, mut pc) = self.window(tid);
            loop {
                // The frame's pc, for the backtrace of an error this op raises.
                self.tasks[tid].note_pc(pc + 1);
                if self.trace_ops { let f = &self.funcs[win.fid as usize]; eprintln!("{} {} {}", f.name, pc, op_name(&f.code[pc])); }
                match self.step(tid, &win, pc) {
                    Step::Next(next) => pc = next,
                    Step::Reenter => break,
                    Step::Return(o) => return o,
                }
            }
        }
    }
    /// The top frame's windows as raw pointers, and its pc. Every op that can
    /// grow the stack (a call) ends the activation, so the pointers are
    /// re-derived after it.
    #[inline]
    pub fn window(&mut self, tid: usize) -> (Win, usize) {
        let s = self.tasks[tid].cur;
        let h0 = self.tasks[tid].stack[s];
        let (fid, pc) = ((h0 & 0xffff_ffff) as u32, (h0 >> 32) as usize);
        let func = &self.funcs[fid as usize];
        let consts: *const Value = func.consts.as_ptr();
        let code: *const Op = func.code.as_ptr();
        let (base, ibase, fbase, vbase) = (s + HDR, s + func.off_i(), s + func.off_f(), s + func.off_v());
        let sp: *mut u64 = self.tasks[tid].stack.as_mut_ptr();
        let regs: *mut Value = unsafe { sp.add(base) as *mut Value };
        let iregs: *mut i64 = unsafe { sp.add(ibase) as *mut i64 };
        let fregs: *mut f64 = unsafe { sp.add(fbase) as *mut f64 };
        let vregs: *mut [f64; 2] = unsafe { sp.add(vbase) as *mut [f64; 2] };
        (Win { regs, iregs, fregs, vregs, consts, code, base, fbase, fid }, pc)
    }
    /// Executes the opcode at `pc` of the activation `w` describes. Inlined
    /// into every caller: the Rust loop keeps its single-function shape, and
    /// the threaded core's slow path gets its own copy.
    #[inline(always)]
    pub fn step(&mut self, tid: usize, w: &Win, pc: usize) -> Step {
        let win = *w;
        let (regs, iregs, fregs, vregs, consts, code, base, fid) = (w.regs, w.iregs, w.fregs, w.vregs, w.consts, w.code, w.base, w.fid);
        let mut pc = pc;
        macro_rules! r { ($i:expr) => { (*unsafe { &mut *regs.add($i as usize) }) } }
        macro_rules! ir { ($i:expr) => { (*unsafe { &mut *iregs.add($i as usize) }) } }
        macro_rules! fr { ($i:expr) => { (*unsafe { &mut *fregs.add($i as usize) }) } }
        macro_rules! vr { ($i:expr) => { (*unsafe { &mut *vregs.add($i as usize) }) } }
        macro_rules! rec { ($i:expr, $what:expr) => {{ let h = hdr!(self, r!($i), $what); if h.kind != KIND_RECORD { self.err($what) } h }} }
        let op = unsafe { *code.add(pc) };
        pc += 1;
        #[cfg(feature = "opstats")]
        if let Some(st) = self.op_stats.as_mut() { *st.entry(op_name(&op)).or_insert(0) += 1; }
        match op {
                    Op::K(d, k) => r!(d) = unsafe { *consts.add(k as usize) },
                    Op::Move(d, s) => r!(d) = r!(s),
                    Op::Nil(d) => r!(d) = Value::NIL,
                    Op::Add(d, a, b) => { let (x, y) = (r!(a), r!(b)); r!(d) = if x.is_num() && y.is_num() { Value::num(x.as_num() + y.as_num()) } else { self.arith(x, y, |p, q| p + q) } }
                    Op::Sub(d, a, b) => { let (x, y) = (r!(a), r!(b)); r!(d) = if x.is_num() && y.is_num() { Value::num(x.as_num() - y.as_num()) } else { self.arith(x, y, |p, q| p - q) } }
                    Op::Mul(d, a, b) => { let (x, y) = (r!(a), r!(b)); r!(d) = self.arith(x, y, |p, q| p * q) }
                    Op::Lt(d, a, b) => { let (x, y) = (r!(a), r!(b)); r!(d) = if x.is_num() && y.is_num() { Value::boolean(x.as_num() < y.as_num()) } else { Value::boolean(self.bytes_of(x) < self.bytes_of(y)) } }
                    Op::Le(d, a, b) => { let (x, y) = (r!(a), r!(b)); r!(d) = if x.is_num() && y.is_num() { Value::boolean(x.as_num() <= y.as_num()) } else { Value::boolean(self.bytes_of(x) <= self.bytes_of(y)) } }
                    Op::Pow(d, a, b) => { let (x, y) = (r!(a), r!(b)); if !(x.is_num() && y.is_num()) { self.err("power of a non-number") } r!(d) = Value::num(x.as_num().powf(y.as_num())) }
                    Op::IDiv(d, a, b) => { let (x, y) = (r!(a), r!(b)); if !(x.is_num() && y.is_num()) { self.err("floor division of a non-number") } r!(d) = Value::num((x.as_num() / y.as_num()).floor()) }
                    Op::IXor(d, a, b) => ir!(d) = ir!(a) ^ ir!(b),
                    Op::INot(d, a) => ir!(d) = !ir!(a),
                    Op::Mod(d, a, b) => { let (x, y) = (r!(a), r!(b)); if !(x.is_num() && y.is_num()) { self.err("modulo of a non-number") } let (p, q) = (x.as_num(), y.as_num()); r!(d) = Value::num(p - (p / q).floor() * q) }
                    Op::Div(d, a, b) => { let (x, y) = (r!(a), r!(b)); if !(x.is_num() && y.is_num()) { self.err("divide a non-number") } r!(d) = Value::num(x.as_num() / y.as_num()) }
                    Op::FMod(d, a, b) => { let (p, q) = (fr!(a), fr!(b)); fr!(d) = p - (p / q).floor() * q }
                    Op::Eq(d, a, b) => { let (x, y) = (r!(a), r!(b)); r!(d) = Value::boolean(self.values_equal(x, y)) }
                    Op::Ne(d, a, b) => { let (x, y) = (r!(a), r!(b)); r!(d) = Value::boolean(!self.values_equal(x, y)) }
                    Op::Not(d, a) => r!(d) = Value::boolean(!r!(a).truthy()),
                    Op::Neg(d, a) => { let x = r!(a); if !x.is_num() { self.err("negate a non-number") } r!(d) = Value::num(-x.as_num()) }
                    Op::Jmp(off) => { pc = (pc as i64 + off as i64) as usize; if off < 0 { self.back_edge(); } }
                    Op::JmpIf(c, off) => if r!(c).truthy() { pc = (pc as i64 + off as i64) as usize; if off < 0 { self.back_edge(); } },
                    Op::JmpIfNot(c, off) => if !r!(c).truthy() { pc = (pc as i64 + off as i64) as usize; if off < 0 { self.back_edge(); } },
                    Op::Switch(rg, t) => {
                        let i = ir!(rg);
                        let off = { let (def, tbl) = &self.funcs[fid as usize].jump_tables[t as usize]; if i >= 0 && (i as usize) < tbl.len() { tbl[i as usize] } else { *def } };
                        pc = (pc as i64 + off as i64) as usize;
                        if off < 0 { self.back_edge(); }
                    }
                    Op::RetN(start, n) => { let n = if n >= 128 { ((n & 127) as usize + self.last_nres).min(8) } else { n as usize }; if self.pop_frame_n(tid, base + start as usize, n) { let v = self.tasks[tid].result; return Step::Return(Outcome::Done(v)); } return Step::Reenter; }
                    Op::Ret(s) => { let v = r!(s); if self.pop_frame(tid, v) { return Step::Return(Outcome::Done(v)); } return Step::Reenter; }
                    Op::RetNil => { if self.pop_frame(tid, Value::NIL) { return Step::Return(Outcome::Done(Value::NIL)); } return Step::Reenter; }
                    Op::FRet(f) => { let v = Value::num(fr!(f)); if self.pop_frame(tid, v) { return Step::Return(Outcome::Done(v)); } return Step::Reenter; }
                    Op::Require(d, k) => { let name = unsafe { *consts.add(k as usize) }; let text = self.bytes_of(name).to_vec(); let name = String::from_utf8_lossy(&text).to_string(); let v = self.require(&name); r!(d) = v; }
                    Op::RequireV(d, rg) => { let text = self.bytes_of(r!(rg)).to_vec(); let name = String::from_utf8_lossy(&text).to_string(); let v = self.require(&name); r!(d) = v; }
                    Op::SetMethod(shape, k, v) => { let name = unsafe { *consts.add(k as usize) }; let f = r!(v); self.heap.shapes[shape as usize].methods.insert(name, f); }
                    Op::Call(f, b, nargs) => { let nargs = self.spread_count(nargs); self.push_frame(tid, f, base + b as usize, nargs, pc); return Step::Reenter; }
                    Op::CallT(f, b, fb, _) => match self.op_call_typed(tid, &win, pc, f, b, fb) { Flow::Next => {} Flow::Reenter => return Step::Reenter, Flow::Return(o) => return Step::Return(o) },
                    Op::CallDyn(frg, b, nargs) | Op::CallK(_, frg, b, nargs, _) => match { let nargs = self.spread_count(nargs); self.op_call_dyn(tid, &win, pc, frg, b, nargs) } { Flow::Next => {} Flow::Reenter => return Step::Reenter, Flow::Return(o) => return Step::Return(o) },
                    Op::CallMethod(k, b, nargs) => match { let nargs = self.spread_count(nargs); self.op_call_method(tid, &win, pc, k, b, nargs) } { Flow::Next => {} Flow::Reenter => return Step::Reenter, Flow::Return(o) => return Step::Return(o) },
                    Op::PCall(b, nargs) => { let nargs = self.spread_count(nargs); self.op_pcall(&win, b, nargs) }
                    Op::Concat(d, a, b) => { let (x, y) = (r!(a), r!(b)); let v = self.concat(x, y); r!(d) = v; }
                    Op::GetIdx(d, t, i) => self.op_get_idx(&win, d, t, i),
                    Op::SetIdx(t, i, s) => { let (tv, iv, v) = (r!(t), r!(i), r!(s)); if self.metatable_of(tv) != Value::NIL { let iv = self.key_for_store(iv); self.newindex(tv, iv, v); } else { self.set_index(tv, iv, v); } }
                    Op::GetField(d, t, k) => self.op_get_field(&win, d, t, k),
                    Op::SetField(t, k, s) => self.op_set_field(&win, t, k, s),
                    Op::NewTable(d) => { let v = self.new_table(); r!(d) = v; }
                    Op::NewTableN(d, n, m) => { let v = self.new_table_sized(n as usize, m as usize); r!(d) = v; }
                    Op::NewRecord(d, shape) => { let v = self.new_record(shape); r!(d) = v; }
                    Op::GetSlot(d, t, i, sh) => { if self.slot_stats.is_some() { let ok = r!(t).as_obj().map(|p| unsafe { let h = &*p.as_ptr(); h.kind == KIND_RECORD && h.shape() == sh }).unwrap_or(false); *self.slot_stats.as_mut().unwrap().entry((fid, pc - 1, ok)).or_insert(0) += 1; if !ok { let found = r!(t).as_obj().map(|p| unsafe { let h = &*p.as_ptr(); if h.kind == KIND_RECORD { h.shape() } else { u32::MAX } }).unwrap_or(u32::MAX - 1); *self.slot_miss_shapes.entry((sh, found)).or_insert(0) += 1; } } let h = rec!(t, "slot of a non-record"); if h.shape() == sh { r!(d) = h.slots()[i as usize]; } else { let v = self.slot_get_slow(r!(t), sh, i); r!(d) = v; } }
                    Op::SetSlot(t, i, s, sh) => { if self.slot_stats.is_some() { let ok = r!(t).as_obj().map(|p| unsafe { let h = &*p.as_ptr(); h.kind == KIND_RECORD && h.shape() == sh }).unwrap_or(false); *self.slot_stats.as_mut().unwrap().entry((fid, pc - 1, ok)).or_insert(0) += 1; if !ok { let found = r!(t).as_obj().map(|p| unsafe { let h = &*p.as_ptr(); if h.kind == KIND_RECORD { h.shape() } else { u32::MAX } }).unwrap_or(u32::MAX - 1); *self.slot_miss_shapes.entry((sh, found)).or_insert(0) += 1; } } let v = r!(s); let tv = r!(t); let h = rec!(t, "slot of a non-record"); if h.shape() == sh { self.heap.barrier(tv.as_obj().unwrap(), v); h.slots_mut()[i as usize] = v; } else { self.slot_set_slow(tv, sh, i, v); } }
                    Op::GetSlotF(d, t, i, sh) => { if self.slot_stats.is_some() { let ok = r!(t).as_obj().map(|p| unsafe { let h = &*p.as_ptr(); h.kind == KIND_RECORD && h.shape() == sh }).unwrap_or(false); *self.slot_stats.as_mut().unwrap().entry((fid, pc - 1, ok)).or_insert(0) += 1; if !ok { let found = r!(t).as_obj().map(|p| unsafe { let h = &*p.as_ptr(); if h.kind == KIND_RECORD { h.shape() } else { u32::MAX } }).unwrap_or(u32::MAX - 1); *self.slot_miss_shapes.entry((sh, found)).or_insert(0) += 1; } } let h = rec!(t, "slot of a non-record"); let v = if h.shape() == sh { h.slots()[i as usize] } else { self.slot_get_slow(r!(t), sh, i) }; if !v.is_num() { self.err("slot is not a number") } fr!(d) = v.as_num(); }
                    Op::SetSlotF(t, i, a, sh) => { if self.slot_stats.is_some() { let ok = r!(t).as_obj().map(|p| unsafe { let h = &*p.as_ptr(); h.kind == KIND_RECORD && h.shape() == sh }).unwrap_or(false); *self.slot_stats.as_mut().unwrap().entry((fid, pc - 1, ok)).or_insert(0) += 1; if !ok { let found = r!(t).as_obj().map(|p| unsafe { let h = &*p.as_ptr(); if h.kind == KIND_RECORD { h.shape() } else { u32::MAX } }).unwrap_or(u32::MAX - 1); *self.slot_miss_shapes.entry((sh, found)).or_insert(0) += 1; } } let h = rec!(t, "slot of a non-record"); if h.shape() == sh { h.slots_mut()[i as usize] = Value::num(fr!(a)); } else { let v = Value::num(fr!(a)); self.slot_set_slow(r!(t), sh, i, v); } }
                    Op::Len(d, a) => { let h = hdr!(self, r!(a), "length of a non-object"); let n = match h.kind { KIND_TABLE => h.table_ref().array.len(), KIND_RECORD => h.record_array_ref().len(), KIND_STR | KIND_SLICE => h.aux_len as usize, _ => self.err("length of a non-object") }; r!(d) = Value::num(n as f64) }
                    Op::LenF(d, a) => { let h = hdr!(self, r!(a), "length of a non-object"); let n = match h.kind { KIND_TABLE => h.table_ref().array.len(), KIND_RECORD => h.record_array_ref().len(), KIND_STR | KIND_SLICE => h.aux_len as usize, _ => self.err("length of a non-object") }; fr!(d) = n as f64; }
                    Op::TagCheckRec(d, a, shape) => { let v = r!(a); let ok = v.as_obj().map(|p| unsafe { let h = &*p.as_ptr(); h.kind == KIND_RECORD && h.shape() == shape }).unwrap_or(false); if !ok { let what = match v.as_obj() { Some(p) => Heap::describe(unsafe { &*p.as_ptr() }), None => format!("{:#x}", v.0) }; self.err(&format!("value is not an instance of the expected record ({}): {what}", self.heap.shapes[shape as usize].name)) } r!(d) = v; }
                    Op::TagCheckNum(d, a) => { let v = r!(a); if !v.is_num() { self.err("value is not a number") } r!(d) = v; }
                    Op::TagCheckStr(d, a) => { let v = r!(a); if !self.is_stringish(v) { self.err("value is not a string") } r!(d) = v; }
                    Op::NewClosure(d, f, b, n) => { let caps: Vec<Value> = (0..n).map(|i| r!(b + 1 + i)).collect(); let v = self.new_closure(f, &caps); r!(d) = v; }
                    Op::NewCell(d, a) => { let v = r!(a); let c = self.new_cell(v); r!(d) = c; }
                    Op::IsRec(d, a, shape) => { r!(d) = Value::boolean(self.is_rec(r!(a), shape)); }
                    Op::Scalar(k, d, a, bb) => { let (x, y) = (r!(a), r!(bb)); if !x.is_num() || !y.is_num() { self.err("scalar intrinsic on a non-number") } r!(d) = Value::num(crate::builtins::scalar_op(k, x.as_num(), y.as_num())); }
                    Op::PadResults(base, n) => { let got = self.last_nres.min(n as usize); for i in got..n as usize { r!(base as usize + i) = Value::NIL; } }
                    Op::VarargN(d, n) => { let s = self.tasks[tid].cur; let nv = nvar_of(self.tasks[tid].stack[s + 3]); for i in 0..n as usize { r!(d as usize + i) = if i < nv { Value(self.tasks[tid].stack[s - nv + i]) } else { Value::NIL }; } }
                    Op::VarargTable(d) => { let s = self.tasks[tid].cur; let nv = nvar_of(self.tasks[tid].stack[s + 3]); let vals: Vec<Value> = (0..nv).map(|i| Value(self.tasks[tid].stack[s - nv + i])).collect(); let t = self.new_table_sized(nv, 0); for (i, v) in vals.into_iter().enumerate() { if v != Value::NIL { self.set_index(t, Value::num(i as f64 + 1.0), v); } } r!(d) = t; }
                    Op::GetCell(d, c) => { let cv = r!(c); let h = hdr!(self, cv, &format!("GetCell of a non-object {:#x} in {} at pc {} register {}", cv.0, self.funcs[fid as usize].name, pc, c)); if h.kind != KIND_CELL { self.err(&format!("GetCell of a non-cell in {} at pc {} register {}", self.funcs[fid as usize].name, pc, c)) } r!(d) = h.slots()[0]; }
                    Op::SetCell(c, a) => { let v = r!(a); let cv = r!(c); self.set_cell(cv, v); }
                    Op::GetUpval(d, i) => { let clo = { let t = &self.tasks[tid]; Value(t.stack[t.cur + 2]) }; let h = hdr!(self, clo, "upvalue outside a closure"); if h.kind != KIND_CLOSURE { self.err("not a closure") } r!(d) = h.slots()[i as usize]; }
                    Op::FBox(d, a) => r!(d) = Value::num(fr!(a)),
                    Op::FDiv(d, a, b) => fr!(d) = fr!(a) / fr!(b),
                    Op::FNeg(d, a) => fr!(d) = -fr!(a),
                    Op::GetIdxF(d, t, i) => { let k = fr!(i); let tv = r!(t); r!(d) = self.index(tv, Value::num(k)); }
                    Op::SetIdxF(t, i, sv) => { let (tv, k, v) = (r!(t), fr!(i), r!(sv)); self.set_index(tv, Value::num(k), v); }
                    Op::GetIdxI(d, t, i) => { let key = Value::num(ir!(i) as f64); let tv = r!(t); r!(d) = self.index(tv, key); }
                    Op::SetIdxI(t, i, s) => { let key = Value::num(ir!(i) as f64); let (tv, v) = (r!(t), r!(s)); if self.metatable_of(tv) != Value::NIL { self.newindex(tv, key, v); } else { self.set_index(tv, key, v); } }
                    Op::FCmpEq(d, a, b) => ir!(d) = (fr!(a) == fr!(b)) as i64,
                    Op::FCmpNe(d, a, b) => ir!(d) = (fr!(a) != fr!(b)) as i64,
                    Op::BoolFromI(d, a) => r!(d) = Value::boolean(ir!(a) != 0),
                    Op::Park(k) => { let key = r!(k).0; self.parks += 1; let t = &mut self.tasks[tid]; let s = t.cur; t.stack[s] = (t.stack[s] & 0xffff_ffff) | ((pc as u64) << 32); t.state = State::Parked(key); return Step::Return(Outcome::Parked(key)); }
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
                    Op::IUnbox(d, v) => ir!(d) = r!(v).as_num() as i64,
                    Op::ICmpSLt(d, a, b) => ir!(d) = (ir!(a) < ir!(b)) as i64,
                    Op::ICmpSLe(d, a, b) => ir!(d) = (ir!(a) <= ir!(b)) as i64,
                    Op::IShl(d, a, b) => ir!(d) = ir!(a).wrapping_shl(ir!(b) as u32),
                    Op::IShrU(d, a, b) => ir!(d) = ((ir!(a) as u64) >> (ir!(b) as u32 & 63)) as i64,
                    Op::IOr(d, a, b) => ir!(d) = ir!(a) | ir!(b),
                    Op::IBswap32(d, a) => ir!(d) = (ir!(a) as u32).swap_bytes() as i64,
                    Op::ICmpEq(d, a, b) => ir!(d) = (ir!(a) == ir!(b)) as i64,
                    Op::ICmpNe(d, a, b) => ir!(d) = (ir!(a) != ir!(b)) as i64,
                    Op::Truthy(d, v) => ir!(d) = r!(v).truthy() as i64,
                    Op::BytesLen(d, s) => ir!(d) = self.bytes_of(r!(s)).len() as i64,
                    Op::LoadU8K(d, s, i) => { let bytes = self.bytes_of(r!(s)); ir!(d) = bytes[ir!(i) as usize] as i64; }
                    Op::StrByte(d, s, i) => { let v = r!(s); if !self.is_stringish(v) { self.err("byte of a non-string") } let bytes = self.bytes_of(v); let i = ir!(i); r!(d) = if i >= 1 && (i as usize) <= bytes.len() { Value::num(bytes[i as usize - 1] as f64) } else { Value::NIL }; }
                    Op::LoadU8(d, s, i) => { let bytes = self.bytes_of(r!(s)); let i = ir!(i) as usize; if i >= bytes.len() { self.err("byte read out of range") } ir!(d) = bytes[i] as i64; }
                    Op::LoadU32W(d, s, i) => { let bytes = self.bytes_of(r!(s)); let off = ir!(i) as usize * 4; if off + 4 > bytes.len() { self.err("word read out of range") } ir!(d) = u32::from_le_bytes(bytes[off..off + 4].try_into().unwrap()) as i64; }
                    Op::StoreU8(s, i, v) => { let x = ir!(v) as u8; let bytes = self.bytes_mut(r!(s)); let i = ir!(i) as usize; if i >= bytes.len() { self.err("byte write out of range") } bytes[i] = x; }
                    Op::StoreU32(s, i, v) => { let x = ir!(v) as u32; let bytes = self.bytes_mut(r!(s)); let off = ir!(i) as usize; if off + 4 > bytes.len() { self.err("word write out of range") } bytes[off..off + 4].copy_from_slice(&x.to_le_bytes()); }
                    Op::NewBuffer(d) => { let v = self.heap_new_buffer(); r!(d) = v; }
                    Op::BufAppend(bf, s) => { let text = self.bytes_of(r!(s)).to_vec(); self.buf_append(r!(bf), &text); }
                    Op::BufAppendSub(bf, s, i, j) => { let (i, j) = (ir!(i), ir!(j)); let text = self.sub_bytes(r!(s), i, j).to_vec(); self.buf_append(r!(bf), &text); }
                    Op::Substring(d, s, i, j) => { let (i, j) = (ir!(i), ir!(j)); let text = self.sub_bytes(r!(s), i, j).to_vec(); let v = self.string_of(&text); r!(d) = v; }
                    Op::BufFinish(d, bf) => { let v = self.buf_finish(r!(bf)); r!(d) = v; }
                    Op::NewBytes(d, n) => { let n = ir!(n) as usize; let v = self.heap_new_bytes(n); r!(d) = v; }
                    Op::BytesToStr(d, s, n) => { let n = ir!(n) as usize; let text = self.bytes_of(r!(s))[..n].to_vec(); let v = self.string_of(&text); r!(d) = v; }
                    Op::VAdd(d, a, b) => { let (x, y) = (vr!(a), vr!(b)); vr!(d) = [x[0] + y[0], x[1] + y[1]]; }
                    Op::VMul(d, a, b) => { let (x, y) = (vr!(a), vr!(b)); vr!(d) = [x[0] * y[0], x[1] * y[1]]; }
                    Op::VLoadM(d, s, i, off, active) => {
                        let base = ir!(i) + off as i64; let act = ir!(active) - off as i64; let st = self.storage(r!(s));
                        let mut v = [0.0; 2];
                        for l in 0..2i64 { if l < act { let k = (base + l) as usize; if k >= st.len() { self.err("masked load out of bounds") } v[l as usize] = st[k]; } }
                        vr!(d) = v;
                    }
                    Op::VStoreM(s, i, v, off, active) => {
                        let base = ir!(i) + off as i64; let act = ir!(active) - off as i64; let x = vr!(v); let st = self.storage(r!(s));
                        for l in 0..2i64 { if l < act { let k = (base + l) as usize; if k >= st.len() { self.err("masked store out of bounds") } st[k] = x[l as usize]; } }
                    }
                    Op::LoopFact(..) => {}
                    Op::IMov(d, a) => ir!(d) = ir!(a),
                    Op::FMov(d, a) => fr!(d) = fr!(a),
                    Op::VMov(d, a) => vr!(d) = vr!(a),
                    Op::GuardLenLe(a, b) => if (ir!(a) as u64) > (ir!(b) as u64) { self.err("native spans have incompatible lengths") },
                    Op::FUnbox(d, rg) => { let v = r!(rg); if !v.is_num() { self.err("not a number") } fr!(d) = v.as_num(); }
                    Op::FAdd(d, a, b) => fr!(d) = fr!(a) + fr!(b),
                    Op::FFma(d, a, b, c) => fr!(d) = fr!(a).mul_add(fr!(b), fr!(c)),
                    Op::StorageLen(d, s) => { let n = self.storage(r!(s)).len() as i64; ir!(d) = n; }
                    Op::FLoad(d, s, i) => { let idx = ir!(i) as usize; let x = self.storage(r!(s))[idx]; fr!(d) = x; }
                    Op::FStore(s, i, f) => { let idx = ir!(i) as usize; let x = fr!(f); self.storage(r!(s))[idx] = x; }
                    Op::VSplat(d, f) => { let x = fr!(f); vr!(d) = [x, x]; }
                    Op::VLoad(d, s, i, off) => { let idx = (ir!(i) + off as i64) as usize; let st = self.storage(r!(s)); let v = [st[idx], st[idx + 1]]; vr!(d) = v; }
                    Op::VStore(s, i, v, off) => { let idx = (ir!(i) + off as i64) as usize; let x = vr!(v); let st = self.storage(r!(s)); st[idx] = x[0]; st[idx + 1] = x[1]; }
                    Op::VFma(d, a, b, c) => { let (x, y, z) = (vr!(a), vr!(b), vr!(c)); vr!(d) = [x[0].mul_add(y[0], z[0]), x[1].mul_add(y[1], z[1])]; }
                    Op::VLane(d, v, l) => fr!(d) = vr!(v)[l as usize],
        }
        Step::Next(pc)
    }

    // ---- outlined opcode handlers ----------------------------------------

    #[inline(never)]
    fn op_call_typed(&mut self, tid: usize, w: &Win, pc: usize, f: u32, b: u8, fb: u8) -> Flow {
        let (base, fbase) = (w.base, w.fbase);
        let (nv, nfp, callee_ret) = { let c = &self.funcs[f as usize]; (c.nv_params, c.nf_params, c.ret) };
        self.push_frame(tid, f, base + b as usize, nv, pc);
        let callee_off_f = self.funcs[f as usize].off_f();
        let t = &mut self.tasks[tid];
        let s = t.cur;
        t.stack[s + 3] = (t.stack[s + 3] & !0x1_ffff_ffff) | (fbase + fb as usize) as u64 | ((callee_ret == b'f') as u64) << 32;
        for i in 0..nfp as usize { t.stack[s + callee_off_f + i] = t.stack[fbase + fb as usize + i]; }
        Flow::Reenter
    }
    #[inline(never)]
    fn op_call_dyn(&mut self, tid: usize, w: &Win, pc: usize, fr: u8, b: u8, nargs: u8) -> Flow {
        let (regs, base, fid) = (w.regs, w.base, w.fid);
        macro_rules! r { ($i:expr) => { (*unsafe { &mut *regs.add($i as usize) }) } }
        let callee = r!(fr);
        if let Some(f) = callee.as_func() {
            let e = self.entry_of(f);
            if e != 0 && nargs < 128 && !self.funcs[f as usize].vararg { let mut buf = [Value::NIL; 8]; let n = (nargs as usize).min(8); for i in 0..n { buf[i] = r!(b + 1 + i as u8); } let np = self.funcs[f as usize].nparams as usize; let outs = self.enter_compiled(e, Value::NIL, &buf[..n], np); self.deliver(regs, b as usize, outs.as_slice()); return Flow::Next; }
            self.push_frame(tid, f, base + b as usize, nargs, pc); return Flow::Reenter;
        }
        if let Some(id) = callee.as_builtin() {
            let args = self.call_args(tid, base + b as usize + 1, nargs);
            if id >= crate::host::HOST_BASE {
                // A host service: an immediate one answers like a builtin; a
                // parking one submits its request, parks the task on the key
                // and is resumed with the completion at `b`.
                match self.host_call(id, args.as_slice()) {
                    Ok(outs) => { self.deliver(regs, b as usize, outs.as_slice()); return Flow::Next; }
                    Err(key) => { let t = &mut self.tasks[tid]; let s = t.cur; t.stack[s] = (t.stack[s] & 0xffff_ffff) | ((pc as u64) << 32); t.state = State::Parked(key); t.deliver_at = b as usize; self.host_waiters.insert(key, tid); self.parks += 1; return Flow::Return(Outcome::Parked(key)); }
                }
            }
            let outs = crate::builtins::call(self, id, args.as_slice());
            self.deliver(regs, b as usize, outs.as_slice());
            return Flow::Next;
        }
        let h = hdr!(self, callee, &format!("call of a non-function ({:#x}) in {} at pc {} register {}", callee.0, self.funcs[fid as usize].name, pc, fr));
        if h.kind == KIND_ITER { let outs = crate::builtins::iter_next(self, callee); self.deliver(regs, b as usize, outs.as_slice()); return Flow::Next; }
        if h.kind == KIND_TABLE {
            let n = (nargs & 127) as usize; let mut full = Vec::with_capacity(n + 1); full.push(callee); for i in 0..n { full.push(r!(b + 1 + i as u8)); }
            let outs = self.call_value(callee, &full[1..]); self.deliver(regs, b as usize, outs.as_slice()); return Flow::Next;
        }
        if h.kind != KIND_CLOSURE { self.err(&format!("call of a non-function object ({}) in {} at pc {} register {}", Heap::describe(h), self.funcs[fid as usize].name, pc, fr)) }
        let f = h.fid();
        let e = self.entry_of(f);
        if e != 0 && nargs < 128 && !self.funcs[f as usize].vararg { let mut buf = [Value::NIL; 8]; let n = (nargs as usize).min(8); for i in 0..n { buf[i] = r!(b + 1 + i as u8); } let np = self.funcs[f as usize].nparams as usize; let outs = self.enter_compiled(e, callee, &buf[..n], np); self.deliver(regs, b as usize, outs.as_slice()); return Flow::Next; }
        // A dynamic call carries every argument as a value; a typed callee's
        // float parameters are unboxed on entry.
        let (nv, n, vararg) = { let c = &self.funcs[f as usize]; (c.nv_params, c.sig.len(), c.vararg) };
        if nargs >= 128 || vararg { self.push_frame_cold(tid, f, base + b as usize, nargs, pc); let t = &mut self.tasks[tid]; let s = t.cur; t.stack[s + 2] = callee.0; return Flow::Reenter; }
        // Only the arguments the call supplied are read; the rest are nil.
        let supplied = (nargs & 127) as usize;
        let all: Vec<Value> = (0..n).map(|i| if i < supplied { r!(b + 1 + i as u8) } else { Value::NIL }).collect();
        self.push_frame(tid, f, base + b as usize, nv.min(supplied as u8), pc);
        let (off_f, sig) = { let c = &self.funcs[f as usize]; (c.off_f(), c.sig.clone()) };
        let t = &mut self.tasks[tid];
        let s = t.cur;
        let (mut vi, mut fi) = (0usize, 0usize);
        for (i, c) in sig.iter().enumerate() {
            if *c == b'f' { t.stack[s + off_f + fi] = all[i].as_num().to_bits(); fi += 1; }
            else { vi += 1; t.stack[s + HDR + vi] = all[i].0; }
        }
        t.stack[s + 2] = callee.0;
        Flow::Reenter
    }
    #[inline(never)]
    fn op_call_method(&mut self, tid: usize, w: &Win, pc: usize, k: u16, b: u8, nargs: u8) -> Flow {
        let (regs, consts, base) = (w.regs, w.consts, w.base);
        macro_rules! r { ($i:expr) => { (*unsafe { &mut *regs.add($i as usize) }) } }
        let name = unsafe { *consts.add(k as usize) };
        let recv = r!(b + 1);
        let h = hdr!(self, recv, "method call on a non-object");
        if h.is_stringish() {
            // A string's methods are the string library; `nargs` counts the receiver.
            let mname = String::from_utf8_lossy(self.bytes_of(name)).to_string();
            let id = crate::builtins::id_of(&format!("string.{mname}")).unwrap_or_else(|| self.err(&format!("no string method {mname}")));
            let args = self.call_args(tid, base + b as usize + 1, nargs);
            let outs = crate::builtins::call(self, id, args.as_slice());
            self.deliver(regs, b as usize, outs.as_slice());
            return Flow::Next;
        }
        let method = self.resolve_method(recv, name);
        if let Some(fid) = method.as_func() { self.push_frame(tid, fid, base + b as usize, nargs, pc); return Flow::Reenter; }
        if let Some(id) = method.as_builtin() {
            let args = self.call_args(tid, base + b as usize + 1, nargs);
            let outs = crate::builtins::call(self, id, args.as_slice());
            self.deliver(regs, b as usize, outs.as_slice());
            return Flow::Next;
        }
        let ch = hdr!(self, method, "method is not a function");
        if ch.kind != KIND_CLOSURE { self.err("method is not a function") }
        let e = self.entry_of(ch.fid());
        if e != 0 && !self.funcs[ch.fid() as usize].vararg { let mut buf = [Value::NIL; 8]; let n = (nargs as usize).min(8); for i in 0..n { buf[i] = r!(b + 1 + i as u8); } let np = self.funcs[ch.fid() as usize].nparams as usize; let outs = self.enter_compiled(e, method, &buf[..n], np); self.deliver(regs, b as usize, outs.as_slice()); return Flow::Next; }
        self.push_frame(tid, ch.fid(), base + b as usize, nargs, pc);
        let t = &mut self.tasks[tid]; let s = t.cur; t.stack[s + 2] = method.0;
        Flow::Reenter
    }
    #[inline(never)]
    fn op_pcall(&mut self, w: &Win, b: u8, nargs: u8) {
        let regs = w.regs;
        macro_rules! r { ($i:expr) => { (*unsafe { &mut *regs.add($i as usize) }) } }
        // The callee runs on a scratch task so an error unwinds only it.
        let callee = r!(b + 1);
        let args: Vec<Value> = (0..nargs as usize).map(|i| r!(b + 2 + i as u8)).collect();
        let hook = std::panic::take_hook();
        std::panic::set_hook(Box::new(|_| {}));
        let outcome = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| self.call_value(callee, &args)));
        std::panic::set_hook(hook);
        match outcome {
            Ok(outs) => { r!(b) = Value::TRUE; self.deliver(regs, b as usize + 1, &outs); }
            Err(payload) => { let v = self.error_value(payload); r!(b) = Value::FALSE; r!(b + 1) = v; }
        }
    }
    #[inline(never)]
    fn op_get_idx(&mut self, w: &Win, d: u8, t: u8, i: u8) {
        let regs = w.regs;
        macro_rules! r { ($i:expr) => { (*unsafe { &mut *regs.add($i as usize) }) } }
        let (tv, iv) = (r!(t), r!(i));
        let v = self.index_any(tv, iv);
        r!(d) = v;
    }
    #[inline(never)]
    fn op_get_field(&mut self, w: &Win, d: u8, t: u8, k: u16) {
        let (regs, consts) = (w.regs, w.consts);
        macro_rules! r { ($i:expr) => { (*unsafe { &mut *regs.add($i as usize) }) } }
        let name = unsafe { *consts.add(k as usize) };
        let h = hdr!(self, r!(t), &format!("field {} of a non-object", String::from_utf8_lossy(self.bytes_of(name))));
        let v = match h.kind {
            KIND_TABLE => { let v = *h.table_ref().hash.get(&name).unwrap_or(&Value::NIL); if v == Value::NIL && h.table_ref().meta != Value::NIL { self.index(r!(t), name) } else { v } }
            // An untyped read of a field the shape lacks is nil, as the
            // compiler's own `x.trivia ~= nil` tests on `any` expect (2.4 amended).
            KIND_RECORD => { let sh = &self.heap.shapes[h.shape() as usize]; match sh.slot_of(name) { Some(i) => h.slots()[i], None => h.record_extra_ref().as_ref().and_then(|m| m.get(&name).copied()).unwrap_or(Value::NIL) } }
            _ => self.err(&format!("field {} of a non-object ({})", String::from_utf8_lossy(self.bytes_of(name)), Heap::describe(h))),
        };
        r!(d) = v;
    }
    #[inline(never)]
    fn op_set_field(&mut self, w: &Win, t: u8, k: u16, s: u8) {
        let (regs, consts) = (w.regs, w.consts);
        macro_rules! r { ($i:expr) => { (*unsafe { &mut *regs.add($i as usize) }) } }
        let name = unsafe { *consts.add(k as usize) };
        let v = r!(s);
        let tv = r!(t);
        let p = tv.as_obj().unwrap_or_else(|| self.err("field of a non-object"));
        if self.metatable_of(tv) != Value::NIL { self.newindex(tv, name, v); return; }
        self.heap.barrier(p, v);
        let h = unsafe { &mut *p.as_ptr() };
        match h.kind {
            KIND_TABLE => { h.table().hash.insert(name, v); }
            KIND_RECORD => {
                // The enforced write (2.5): an untyped store into a record checks
                // the slot's declared type, so typed reads never check.
                let sh = &self.heap.shapes[h.shape() as usize];
                let i = match sh.slot_of(name) { Some(i) => i, None => { h.record_extra().get_or_insert_with(Default::default).insert(name, v); return; } };
                if !self.slot_type_ok(sh.types[i], v) { self.err(&format!("value does not match the declared type of field {} of {}", String::from_utf8_lossy(self.bytes_of(name)), sh.name)) }
                h.slots_mut()[i] = v;
            }
            _ => self.err("field of a non-object"),
        }
    }
}


/// The opcode's name, for statistics.
pub fn op_name(op: &Op) -> &'static str {
    match op {
        Op::K(..) => "K",
        Op::Move(..) => "Move",
        Op::Nil(..) => "Nil",
        Op::Add(..) => "Add",
        Op::Sub(..) => "Sub",
        Op::Mul(..) => "Mul",
        Op::Lt(..) => "Lt",
        Op::Le(..) => "Le",
        Op::Eq(..) => "Eq",
        Op::Jmp(..) => "Jmp",
        Op::JmpIf(..) => "JmpIf",
        Op::JmpIfNot(..) => "JmpIfNot",
        Op::Switch(..) => "Switch",
        Op::GetIdxI(..) => "GetIdxI",
        Op::SetIdxI(..) => "SetIdxI",
        Op::IUnbox(..) => "IUnbox",
        Op::ICmpSLt(..) => "ICmpSLt",
        Op::ICmpSLe(..) => "ICmpSLe",
        Op::IShl(..) => "IShl",
        Op::IShrU(..) => "IShrU",
        Op::IOr(..) => "IOr",
        Op::IBswap32(..) => "IBswap32",
        Op::ICmpEq(..) => "ICmpEq",
        Op::BytesLen(..) => "BytesLen",
        Op::LoadU8(..) => "LoadU8",
        Op::LoadU8K(..) => "LoadU8K",
        Op::LoadU32W(..) => "LoadU32W",
        Op::StoreU8(..) => "StoreU8",
        Op::StoreU32(..) => "StoreU32",
        Op::NewBytes(..) => "NewBytes",
        Op::BytesToStr(..) => "BytesToStr",
        Op::Mod(..) => "Mod",
        Op::Div(..) => "Div",
        Op::FMod(..) => "FMod",
        Op::RetN(..) => "RetN",
        Op::Require(..) => "Require",
        Op::SetMethod(..) => "SetMethod",
        Op::RequireV(..) => "RequireV",
        Op::NewTableN(..) => "NewTableN",
        Op::ICmpNe(..) => "ICmpNe",
        Op::Truthy(..) => "Truthy",
        Op::NewBuffer(..) => "NewBuffer",
        Op::BufAppend(..) => "BufAppend",
        Op::BufAppendSub(..) => "BufAppendSub",
        Op::Substring(..) => "Substring",
        Op::BufFinish(..) => "BufFinish",
        Op::Call(..) => "Call",
        Op::CallT(..) => "CallT",
        Op::CallDyn(..) => "CallDyn",
        Op::CallK(..) => "CallK",
        Op::StrByte(..) => "StrByte",
        Op::Pow(..) => "Pow",
        Op::IDiv(..) => "IDiv",
        Op::IXor(..) => "IXor",
        Op::INot(..) => "INot",
        Op::Ret(..) => "Ret",
        Op::RetNil => "RetNil",
        Op::NewTable(..) => "NewTable",
        Op::GetIdx(..) => "GetIdx",
        Op::SetIdx(..) => "SetIdx",
        Op::GetField(..) => "GetField",
        Op::SetField(..) => "SetField",
        Op::NewRecord(..) => "NewRecord",
        Op::GetSlot(..) => "GetSlot",
        Op::SetSlot(..) => "SetSlot",
        Op::Park(..) => "Park",
        Op::Checkpoint => "Checkpoint",
        Op::Ne(..) => "Ne",
        Op::Concat(..) => "Concat",
        Op::Not(..) => "Not",
        Op::Neg(..) => "Neg",
        Op::Len(..) => "Len",
        Op::CallMethod(..) => "CallMethod",
        Op::PCall(..) => "PCall",
        Op::TagCheckRec(..) => "TagCheckRec",
        Op::TagCheckNum(..) => "TagCheckNum",
        Op::TagCheckStr(..) => "TagCheckStr",
        Op::IsRec(..) => "IsRec",
        Op::PadResults(..) => "PadResults",
        Op::Scalar(..) => "Scalar",
        Op::VarargN(..) => "VarargN",
        Op::VarargTable(..) => "VarargTable",
        Op::NewClosure(..) => "NewClosure",
        Op::NewCell(..) => "NewCell",
        Op::GetCell(..) => "GetCell",
        Op::SetCell(..) => "SetCell",
        Op::GetUpval(..) => "GetUpval",
        Op::FBox(..) => "FBox",
        Op::GetSlotF(..) => "GetSlotF",
        Op::SetSlotF(..) => "SetSlotF",
        Op::FDiv(..) => "FDiv",
        Op::FNeg(..) => "FNeg",
        Op::LenF(..) => "LenF",
        Op::GetIdxF(..) => "GetIdxF",
        Op::SetIdxF(..) => "SetIdxF",
        Op::FCmpEq(..) => "FCmpEq",
        Op::FCmpNe(..) => "FCmpNe",
        Op::BoolFromI(..) => "BoolFromI",
        Op::IK(..) => "IK",
        Op::IAdd(..) => "IAdd",
        Op::IAddK(..) => "IAddK",
        Op::IJmpIfUle(..) => "IJmpIfUle",
        Op::IJmpIfUlt(..) => "IJmpIfUlt",
        Op::FK(..) => "FK",
        Op::FUnbox(..) => "FUnbox",
        Op::ISub(..) => "ISub",
        Op::IMaskU32(..) => "IMaskU32",
        Op::IToF(..) => "IToF",
        Op::FToI(..) => "FToI",
        Op::FSub(..) => "FSub",
        Op::FMul(..) => "FMul",
        Op::ICmpLe(..) => "ICmpLe",
        Op::ICmpLt(..) => "ICmpLt",
        Op::FCmpLe(..) => "FCmpLe",
        Op::FCmpLt(..) => "FCmpLt",
        Op::IAnd(..) => "IAnd",
        Op::JmpIfIZero(..) => "JmpIfIZero",
        Op::VAdd(..) => "VAdd",
        Op::VMul(..) => "VMul",
        Op::VLoadM(..) => "VLoadM",
        Op::VStoreM(..) => "VStoreM",
        Op::LoopFact(..) => "LoopFact",
        Op::GuardLenLe(..) => "GuardLenLe",
        Op::IMov(..) => "IMov",
        Op::FMov(..) => "FMov",
        Op::VMov(..) => "VMov",
        Op::FAdd(..) => "FAdd",
        Op::FFma(..) => "FFma",
        Op::StorageLen(..) => "StorageLen",
        Op::FLoad(..) => "FLoad",
        Op::FStore(..) => "FStore",
        Op::VSplat(..) => "VSplat",
        Op::VLoad(..) => "VLoad",
        Op::VStore(..) => "VStore",
        Op::VFma(..) => "VFma",
        Op::VLane(..) => "VLane",
        Op::FRet(..) => "FRet",
    }
}

pub fn storage_ptr(v: Value) -> Option<NonNull<Header>> { v.as_obj() }
