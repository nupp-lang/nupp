//! The native core's contract (contracts 5.2): the instruction encoding it
//! reads, the per-function table it walks, the context it runs in, and the
//! Rust helpers it calls for anything it does not do itself. The handlers are
//! Nupp (`src/nupp/runtime/vm`), linked by the `native-runtime` feature and
//! driven by `dispatch`; a build without the object, and `NO_THREADED=1`, run
//! `Interp::run_rust`, the reference the core's results are checked against.
#![cfg_attr(not(feature = "native-runtime"), allow(dead_code, unused_imports))]

use crate::interp::{Function, Interp, Op, Outcome, State, Step};
use crate::value::Value;

/// One instruction as the core reads it: four bytes of small operands, an
/// immediate, and a wide constant (an integer, float bits or a function id).
#[repr(C)]
#[derive(Clone, Copy, Default)]
pub struct Ins { pub op: u8, pub a: u8, pub b: u8, pub c: u8, pub imm: i32, pub k: i64 }

#[repr(C)]
/// `calls` counts the entries and taken back edges of a function the JIT has
/// not decided on, toward the frame threshold that compiles it.
/// `typed` marks a function with a float parameter, which a dynamic call
/// unboxes on entry and the core leaves to Rust; `native` one with vector
/// instructions, which runs only compiled or by the interpreter's policy.
pub struct FuncInfo { pub code: *const Ins, pub consts: *const u64, pub frame_words: u32, pub nregs: u32, pub nparams: u32, pub off_i: u32, pub off_f: u32, pub off_v: u32, pub vararg: u32, pub ncode: u32, pub calls: u32, pub typed: u32, pub native: u32 }

#[repr(C)]
pub struct ShapeInfo { pub names: *const u64, pub n: u64, pub table: *const u64, pub mask: u64 }

#[repr(C)]
/// The core runs every task as the frame driver: `guard` is the highest
/// frame whose return the Rust path must take (a registered cleanup or a
/// protected call at or above it, or every frame while an unwind is in
/// progress; `NO_GUARD` when none), `slow_calls` the builtins it hands to
/// Rust whole, `frame_entries` the compiled frame entry per function,
/// entered through `rt_enter_frame`, and `frame_threshold` the heat at which
/// a function without one is compiled while `jit_frames` says the JIT may.
/// `budget` is how many more calls and taken back edges the core may take
/// before handing the instruction to Rust, which parks or raises there (an
/// instruction budget's slice, a source chunk's limit); `u64::MAX` is none.
/// `budget_mark` is what `sync` set it to, so the Rust side can charge the
/// difference before it reads the budgets itself. `cleanups` and
/// `ncleanups` are the task's cleanup records (contracts 6.5b), which the
/// core reads and rewrites in place and Rust alone pushes and pops.
pub struct Ctx { pub interp: *mut std::ffi::c_void, pub tid: u64, pub stack: *mut u64, pub cap: u64, pub cur: u64, pub funcs: *const FuncInfo, pub nfuncs: u64, pub status: u32, pub pc: u32, pub result: u64, pub last_nres: u64, pub shapes: *const ShapeInfo, pub nshapes: u64, pub marking: *const u8, pub feedback: u32, pub guard: u64, pub slow_calls: *const u8, pub nslow_calls: u64, pub frame_entries: *const u64, pub nframe_entries: u64, pub unavailable_fid: u32, pub jit_frames: u32, pub frame_threshold: u32, pub budget: u64, pub budget_mark: u64, pub cleanups: *mut crate::interp::Cleanup, pub ncleanups: u64 }

pub const NO_GUARD: u64 = u64::MAX;
/// Every return goes to Rust: an unwind is driving the task's cleanups.
const GUARD_ALL: u64 = u64::MAX - 1;

/// Builtins a dynamic call must hand to Rust: the protected calls, which the
/// frame driver runs as frames a task can suspend in, and the task API, which
/// parks.
fn slow_calls() -> &'static [u8] {
    static SLOW: std::sync::OnceLock<Vec<u8>> = std::sync::OnceLock::new();
    SLOW.get_or_init(|| crate::builtins::NAMES.iter().enumerate().map(|(id, name)| {
        (id as u32 == crate::builtins::PCALL || id as u32 == crate::builtins::XPCALL || name.starts_with("tasks.")) as u8
    }).collect())
}

pub const ST_REENTER: u32 = 0xffff_ffff;
pub const ST_DONE: u32 = 0xffff_fffe;
pub const ST_PARKED: u32 = 0xffff_fffd;
/// A raise is propagating: `Interp::pending_error` holds the value.
pub const ST_ERROR: u32 = 0xffff_fffc;

// The core's opcode numbers: one handler each in `dispatch`, in this order.
// The same list names them, so a native handler source resolves its opcode
// by name without a second table.
macro_rules! codes {
    ($first:ident $(, $rest:ident)* $(,)?) => {
        #[allow(dead_code)]
        #[repr(u8)]
        #[derive(Clone, Copy, Debug)]
        pub(crate) enum Code { $first = 0, $($rest,)* }
        /// Every opcode name, indexed by its number.
        pub const CODE_NAMES: &[&str] = &[stringify!($first), $(stringify!($rest),)*];
    };
}
codes! {
    Slow, Move, K, Nil, Add, Sub, Mul, Lt, Le, Eq, Ne, Not, Neg,
    Jmp, JmpIf, JmpIfNot, JmpIfIZero,
    IK, IAdd, ISub, IAnd, IOr, IShl, IShrU, ICmpSLt, ICmpSLe, ICmpEq, ICmpNe, ICmpLt, ICmpLe,
    IMov, IAddK, IMaskU32, IUnbox, IToF, FToI, Truthy, BoolFromI,
    FK, FMov, FAdd, FSub, FMul, FDiv, FMod, FNeg, FUnbox, FBox, FCmpEq, FCmpNe, FCmpLe, FCmpLt,
    GetUpval, GetCell, GetSlot, GetSlotF, SetSlotF, Len, LenF, StrByte,
    Call, CallK, CallDyn, Ret, RetNil, RetN,
    GetField, GetIdxI, SetIdxI, SetCell, SetSlot, TagCheckNum, NewRecord, GetIdx,
    PadResults, IBox, GetIdxF, SetIdxF, SetIdx, Mod,
    Concat,
    NewTable, NewTableN, SetField,
    NewClosure, NewCell,
    VarargN,
    CallMethod,
    PCall, Raise, Defer, DeferMethod, DisarmAt, RearmAt, CleanupLive, Unwind,
    Switch, IXor, INot, IBswap32, TagCheckRec, IsRec, GetPhys, GetPhysF, GetPhysI, GetPhysU, SetPhys, SetPhysF, SetPhysI,
    Simd, SpanLen, SpanBounds, SpanLoad, SpanStore, VOp, VSplatN, VExtractN, VAny, VPrefix,
    VAdd, VMul, VLoadM, VStoreM, LoopFact, GuardLenLe, VMov, FFma,
    StorageLen, FLoad, FStore, VSplat, VLoad, VStore, VFma, VLane,
    Require, RequireV, SetMethod,
    UUnbox, UBox, Div, Pow, IDiv, TagCheckInt, TagCheckStr, Scalar, IJmpIfUle, IJmpIfUlt,
}

/// The opcode number of a core handler name, if it is one.
pub fn code_by_name(name: &str) -> Option<u8> {
    CODE_NAMES.iter().position(|n| *n == name).map(|i| i as u8)
}

/// The core's encoding of one opcode; anything it does not handle is `Slow`,
/// which hands the instruction to the Rust interpreter.
pub fn encode(op: &Op) -> Ins {
    let i = |op: Code, a: u8, b: u8, c: u8| Ins { op: op as u8, a, b, c, imm: 0, k: 0 };
    match *op {
        Op::UUnbox(d, a) => i(Code::UUnbox, d, a, 0),
        Op::UBox(d, a) => i(Code::UBox, d, a, 0),
        Op::TagCheckStr(d, a) => i(Code::TagCheckStr, d, a, 0),
        Op::Div(d, a, b) => i(Code::Div, d, a, b),
        Op::Pow(d, a, b) => i(Code::Pow, d, a, b),
        Op::IDiv(d, a, b) => i(Code::IDiv, d, a, b),
        Op::TagCheckInt(d, a, unsigned) => i(Code::TagCheckInt, d, a, unsigned as u8),
        Op::Scalar(k, d, a, b) => Ins { imm: k as i32, ..i(Code::Scalar, d, a, b) },
        Op::IJmpIfUle(a, b, off) => Ins { imm: off, ..i(Code::IJmpIfUle, a, b, 0) },
        Op::IJmpIfUlt(a, b, off) => Ins { imm: off, ..i(Code::IJmpIfUlt, a, b, 0) },
        Op::Move(d, s) => i(Code::Move, d, s, 0),
        Op::K(d, k) => Ins { imm: k as i32, ..i(Code::K, d, 0, 0) },
        Op::Nil(d) => i(Code::Nil, d, 0, 0),
        Op::Add(d, a, b) => i(Code::Add, d, a, b),
        Op::Sub(d, a, b) => i(Code::Sub, d, a, b),
        Op::Mul(d, a, b) => i(Code::Mul, d, a, b),
        Op::Lt(d, a, b) => i(Code::Lt, d, a, b),
        Op::Le(d, a, b) => i(Code::Le, d, a, b),
        Op::Eq(d, a, b) => i(Code::Eq, d, a, b),
        Op::Ne(d, a, b) => i(Code::Ne, d, a, b),
        Op::Not(d, s) => i(Code::Not, d, s, 0),
        Op::Neg(d, s) => i(Code::Neg, d, s, 0),
        Op::Jmp(off) => Ins { imm: off, ..i(Code::Jmp, 0, 0, 0) },
        Op::JmpIf(c, off) => Ins { imm: off, ..i(Code::JmpIf, c, 0, 0) },
        Op::JmpIfNot(c, off) => Ins { imm: off, ..i(Code::JmpIfNot, c, 0, 0) },
        Op::JmpIfIZero(c, off) => Ins { imm: off, ..i(Code::JmpIfIZero, c, 0, 0) },
        Op::IK(d, k) => Ins { k, ..i(Code::IK, d, 0, 0) },
        Op::IAdd(d, a, b) => i(Code::IAdd, d, a, b),
        Op::ISub(d, a, b) => i(Code::ISub, d, a, b),
        Op::IXor(d, a, b) => i(Code::IXor, d, a, b),
        Op::INot(d, a) => i(Code::INot, d, a, 0),
        Op::IBswap32(d, a) => i(Code::IBswap32, d, a, 0),
        Op::IAnd(d, a, b) => i(Code::IAnd, d, a, b),
        Op::IOr(d, a, b) => i(Code::IOr, d, a, b),
        Op::IShl(d, a, b) => i(Code::IShl, d, a, b),
        Op::IShrU(d, a, b) => i(Code::IShrU, d, a, b),
        Op::ICmpSLt(d, a, b) => i(Code::ICmpSLt, d, a, b),
        Op::ICmpSLe(d, a, b) => i(Code::ICmpSLe, d, a, b),
        Op::ICmpEq(d, a, b) => i(Code::ICmpEq, d, a, b),
        Op::ICmpNe(d, a, b) => i(Code::ICmpNe, d, a, b),
        Op::ICmpLt(d, a, b) => i(Code::ICmpLt, d, a, b),
        Op::ICmpLe(d, a, b) => i(Code::ICmpLe, d, a, b),
        Op::IMov(d, a) => i(Code::IMov, d, a, 0),
        Op::IAddK(d, a, k) => Ins { k, ..i(Code::IAddK, d, a, 0) },
        Op::IMaskU32(d, a) => i(Code::IMaskU32, d, a, 0),
        Op::IUnbox(d, v) => i(Code::IUnbox, d, v, 0),
        Op::IToF(d, a) => i(Code::IToF, d, a, 0),
        Op::FToI(d, a) => i(Code::FToI, d, a, 0),
        Op::Truthy(d, v) => i(Code::Truthy, d, v, 0),
        Op::BoolFromI(d, a) => i(Code::BoolFromI, d, a, 0),
        Op::FK(d, f) => Ins { k: f.to_bits() as i64, ..i(Code::FK, d, 0, 0) },
        Op::FMov(d, a) => i(Code::FMov, d, a, 0),
        Op::FAdd(d, a, b) => i(Code::FAdd, d, a, b),
        Op::FSub(d, a, b) => i(Code::FSub, d, a, b),
        Op::FMul(d, a, b) => i(Code::FMul, d, a, b),
        Op::FDiv(d, a, b) => i(Code::FDiv, d, a, b),
        Op::FMod(d, a, b) => i(Code::FMod, d, a, b),
        Op::FNeg(d, a) => i(Code::FNeg, d, a, 0),
        Op::FUnbox(d, r) => i(Code::FUnbox, d, r, 0),
        Op::IBox(d, a) => i(Code::IBox, d, a, 0),
        Op::FBox(d, a) => i(Code::FBox, d, a, 0),
        Op::FCmpEq(d, a, b) => i(Code::FCmpEq, d, a, b),
        Op::FCmpNe(d, a, b) => i(Code::FCmpNe, d, a, b),
        Op::FCmpLe(d, a, b) => i(Code::FCmpLe, d, a, b),
        Op::FCmpLt(d, a, b) => i(Code::FCmpLt, d, a, b),
        Op::GetUpval(d, u) => i(Code::GetUpval, d, u, 0),
        Op::GetCell(d, c) => i(Code::GetCell, d, c, 0),
        Op::GetSlot(d, t, s, sh) => Ins { imm: sh as i32, k: s as i64, ..i(Code::GetSlot, d, t, s as u8) },
        Op::GetSlotF(d, t, s, sh) => Ins { imm: sh as i32, k: s as i64, ..i(Code::GetSlotF, d, t, s as u8) },
        Op::SetSlotF(t, s, a, sh) => Ins { imm: sh as i32, k: s as i64, ..i(Code::SetSlotF, t, s as u8, a) },
        Op::Len(d, a) => i(Code::Len, d, a, 0),
        Op::LenF(d, a) => i(Code::LenF, d, a, 0),
        Op::StrByte(d, s, ix) => i(Code::StrByte, d, s, ix),
        Op::Call(fid, base, nargs) => Ins { k: fid as i64, ..i(Code::Call, base, nargs, 0) },
        Op::CallK(fid, fr, base, nargs, nres) => Ins { imm: nres as i32, k: fid as i64, ..i(Code::CallK, fr, base, nargs) },
        Op::CallDyn(fr, base, nargs) => i(Code::CallDyn, fr, base, nargs),
        Op::Ret(s) => i(Code::Ret, s, 0, 0),
        Op::RetNil => i(Code::RetNil, 0, 0, 0),
        Op::RetN(start, n) => i(Code::RetN, start, n, 0),
        Op::GetField(d, t, k) => Ins { imm: k as i32, ..i(Code::GetField, d, t, 0) },
        Op::GetIdxI(d, t, ix) => i(Code::GetIdxI, d, t, ix),
        Op::SetIdxI(t, ix, v) => i(Code::SetIdxI, t, ix, v),
        Op::SetCell(c, v) => i(Code::SetCell, c, v, 0),
        Op::SetSlot(t, s, v, sh) => Ins { imm: sh as i32, k: s as i64, ..i(Code::SetSlot, t, s as u8, v) },
        Op::PadResults(base, n) => i(Code::PadResults, base, n, 0),
        Op::TagCheckNum(d, a) => i(Code::TagCheckNum, d, a, 0),
        Op::NewRecord(d, shape) => Ins { k: shape as i64, ..i(Code::NewRecord, d, 0, 0) },
        Op::GetIdx(d, t, key) => i(Code::GetIdx, d, t, key),
        Op::GetIdxF(d, t, k) => i(Code::GetIdxF, d, t, k),
        Op::SetIdxF(t, k, v) => i(Code::SetIdxF, t, k, v),
        Op::SetIdx(t, k, v) => i(Code::SetIdx, t, k, v),
        Op::Mod(d, a, b) => i(Code::Mod, d, a, b),
        Op::Concat(d, a, b) => i(Code::Concat, d, a, b),
        Op::NewTable(d) => i(Code::NewTable, d, 0, 0),
        Op::NewTableN(d, n, m) => i(Code::NewTableN, d, n, m),
        Op::SetField(t, k, s) => Ins { imm: k as i32, ..i(Code::SetField, t, s, 0) },
        Op::NewClosure(d, f, b, n) => Ins { k: f as i64, ..i(Code::NewClosure, d, b, n) },
        Op::NewCell(d, a) => i(Code::NewCell, d, a, 0),
        Op::VarargN(d, n) => i(Code::VarargN, d, n, 0),
        Op::CallMethod(k, b, n) => Ins { imm: k as i32, ..i(Code::CallMethod, 0, b, n) },
        Op::PCall(b, n) => i(Code::PCall, b, n, 0),
        Op::Raise(k) => Ins { imm: k as i32, ..i(Code::Raise, 0, 0, 0) },
        Op::Defer(v, c) => i(Code::Defer, v, c, 0),
        Op::DeferMethod(v, k) => Ins { imm: k as i32, ..i(Code::DeferMethod, v, 0, 0) },
        Op::DisarmAt(depth) => Ins { imm: depth as i32, ..i(Code::DisarmAt, 0, 0, 0) },
        Op::RearmAt(depth, v, c) => Ins { imm: depth as i32, ..i(Code::RearmAt, v, c, 0) },
        Op::CleanupLive(d, depth) => Ins { imm: depth as i32, ..i(Code::CleanupLive, d, 0, 0) },
        Op::Unwind(depth) => Ins { imm: depth as i32, ..i(Code::Unwind, 0, 0, 0) },
        Op::Switch(r, t) => Ins { imm: t as i32, ..i(Code::Switch, r, 0, 0) },
        Op::TagCheckRec(d, a, shape) => Ins { imm: shape as i32, ..i(Code::TagCheckRec, d, a, 0) },
        Op::IsRec(d, a, shape) => Ins { imm: shape as i32, ..i(Code::IsRec, d, a, 0) },
        Op::GetPhys(a, b, p) => Ins { imm: (p.identity as u32 | ((p.name as u32) << 16)) as i32, k: p.packed(false) as i64, ..i(Code::GetPhys, a, b, 0) },
        Op::GetPhysF(a, b, p) => Ins { imm: (p.identity as u32 | ((p.name as u32) << 16)) as i32, k: p.packed(false) as i64, ..i(Code::GetPhysF, a, b, 0) },
        Op::GetPhysI(a, b, p) => Ins { imm: (p.identity as u32 | ((p.name as u32) << 16)) as i32, k: p.packed(false) as i64, ..i(Code::GetPhysI, a, b, 0) },
        Op::GetPhysU(a, b, p) => Ins { imm: (p.identity as u32 | ((p.name as u32) << 16)) as i32, k: p.packed(false) as i64, ..i(Code::GetPhysU, a, b, 0) },
        Op::SetPhys(a, p, b) => Ins { imm: (p.identity as u32 | ((p.name as u32) << 16)) as i32, k: p.packed(true) as i64, ..i(Code::SetPhys, a, b, 0) },
        Op::SetPhysF(a, p, b) => Ins { imm: (p.identity as u32 | ((p.name as u32) << 16)) as i32, k: p.packed(true) as i64, ..i(Code::SetPhysF, a, b, 0) },
        Op::SetPhysI(a, p, b) => Ins { imm: (p.identity as u32 | ((p.name as u32) << 16)) as i32, k: p.packed(true) as i64, ..i(Code::SetPhysI, a, b, 0) },
        Op::VAdd(a,b,c) => i(Code::VAdd, a,b,c),
        Op::VMul(a,b,c) => i(Code::VMul, a,b,c),
        Op::FLoad(a,b,c) => i(Code::FLoad, a,b,c),
        Op::FStore(a,b,c) => i(Code::FStore, a,b,c),
        Op::StorageLen(a,b) => i(Code::StorageLen, a,b,0),
        Op::VSplat(a,b) => i(Code::VSplat, a,b,0),
        Op::VMov(a,b) => i(Code::VMov, a,b,0),
        Op::GuardLenLe(a,b) => i(Code::GuardLenLe, a,b,0),
        Op::VAny(a,b) => i(Code::VAny, a,b,0),
        Op::LoopFact(..) => i(Code::LoopFact,0,0,0),
        Op::FFma(a,b,c,d) => Ins { imm:d as i32, ..i(Code::FFma,a,b,c) },
        Op::VFma(a,b,c,d) => Ins { imm:d as i32, ..i(Code::VFma,a,b,c) },
        Op::VLoad(a,b,c,d) => Ins { imm:d, ..i(Code::VLoad,a,b,c) },
        Op::VStore(a,b,c,d) => Ins { imm:d, ..i(Code::VStore,a,b,c) },
        Op::VLoadM(a,b,c,d,e) => Ins { imm:d, k:e as i64, ..i(Code::VLoadM,a,b,c) },
        Op::VStoreM(a,b,c,d,e) => Ins { imm:d, k:e as i64, ..i(Code::VStoreM,a,b,c) },
        Op::VLane(a,b,c) | Op::VSplatN(a,b,c) => i(if matches!(*op, Op::VLane(..)) { Code::VLane } else { Code::VSplatN },a,b,c),
        Op::VExtractN(a,b,c,d) => Ins { imm:d as i32, ..i(Code::VExtractN,a,b,c) },
        Op::VPrefix(a,b,c,d,e) => Ins { imm:d as i32 | ((e as i32)<<8), ..i(Code::VPrefix,a,b,c) },
        Op::SpanLen(a,b,c) => i(Code::SpanLen,a,b,c),
        Op::SpanBounds(a,b,c,d,e) => Ins { imm:d as i32 | ((e as i32)<<8), ..i(Code::SpanBounds,a,b,c) },
        Op::SpanLoad(a,b,c,d,e,f,g) => Ins { imm:d as i32 | ((e as i32)<<8) | ((f as i32)<<16) | ((g as i32)<<24), ..i(Code::SpanLoad,a,b,c) },
        Op::SpanStore(a,b,c,d,e,f,g) => Ins { imm:d as i32 | ((e as i32)<<8) | ((f as i32)<<16) | ((g as i32)<<24), ..i(Code::SpanStore,a,b,c) },
        Op::VOp(a,b,c,d,e,f) => Ins { imm:a as i32 | ((b as i32)<<8) | ((f as i32)<<16), ..i(Code::VOp,c,d,e) },
        Op::Simd(a,b,c,d,e) => Ins { imm:c as i32 | ((e as i32)<<8), ..i(Code::Simd,a,b,d) },
        Op::Require(d, k) => Ins { imm: k as i32, ..i(Code::Require, d, 0, 0) },
        Op::RequireV(d, source) => i(Code::RequireV, d, source, 0),
        Op::SetMethod(shape, k, value) => Ins { imm: shape as i32, k: k as i64, ..i(Code::SetMethod, value, 0, 0) },
        _ => i(Code::Slow, 0, 0, 0),
    }
}

/// The 32-bit words of a function's jump tables as `Switch` reads them past
/// its last instruction (`FuncInfo.ncode`): a start word per table, then at
/// each start the table's length, its default offset and its offsets, all
/// relative to the instruction after the `Switch`.
fn jump_words(f: &Function) -> Vec<i32> {
    let mut words: Vec<i32> = vec![0; f.jump_tables.len()];
    for (t, (default, offsets)) in f.jump_tables.iter().enumerate() {
        words[t] = words.len() as i32;
        words.push(offsets.len() as i32);
        words.push(*default);
        words.extend_from_slice(offsets);
    }
    while words.len() % 4 != 0 { words.push(0); }
    words
}

/// A function's code as the core reads it: each instruction encoded, then
/// its jump tables packed four words to an instruction slot.
pub fn encode_function(f: &Function) -> Vec<Ins> {
    let mut ins: Vec<Ins> = f.code.iter().map(encode).collect();
    for w in jump_words(f).chunks(4) {
        let b = w[0].to_le_bytes();
        ins.push(Ins { op: b[0], a: b[1], b: b[2], c: b[3], imm: w[1], k: (w[2] as u32 as i64) | ((w[3] as i64) << 32) });
    }
    ins
}

/// Whether the task's instruction budget applies: a scheduled task's.
fn budgeted(it: &Interp, tid: usize) -> bool {
    it.scheduler.as_ref().is_some_and(|s| s.controls.contains_key(&tid))
}

/// The calls and back edges the core may still take: the smaller of the
/// source chunk's limit and the scheduled task's slice, when either is set.
fn budget_limit(it: &Interp, tid: usize) -> u64 {
    let mut limit = u64::MAX;
    if let Some(n) = it.execution_limit { limit = limit.min(n as u64); }
    if budgeted(it, tid) { if let Some(n) = it.instruction_budget { limit = limit.min(n as u64); } }
    limit
}

/// Charges what the core took since `sync` to the budgets it was drawn from.
pub(crate) fn charge(ctx: &mut Ctx, it: &mut Interp) {
    let used = ctx.budget_mark.saturating_sub(ctx.budget);
    if used == 0 { return; }
    ctx.budget_mark = ctx.budget;
    if let Some(n) = it.execution_limit.as_mut() { *n = n.saturating_sub(used as usize); }
    if budgeted(it, ctx.tid as usize) { if let Some(n) = it.instruction_budget.as_mut() { *n = n.saturating_sub(used as usize); } }
}

#[inline]
pub(crate) fn sync(ctx: &mut Ctx, it: &mut Interp) {
    let tid = ctx.tid as usize;
    ctx.budget = budget_limit(it, tid);
    ctx.budget_mark = ctx.budget;
    let t = &mut it.tasks[tid];
    ctx.stack = t.stack.as_mut_ptr();
    ctx.cap = t.stack.len() as u64;
    ctx.cur = t.cur() as u64;
    ctx.cleanups = t.cleanups.as_mut_ptr();
    ctx.ncleanups = t.cleanups.len() as u64;
    ctx.last_nres = it.last_nres as u64;
    ctx.funcs = it.finfo.as_ptr(); ctx.nfuncs = it.finfo.len() as u64;
    ctx.shapes = it.shape_info.as_ptr(); ctx.nshapes = it.shape_info.len() as u64;
    ctx.guard = guard(it, tid);
    // Compiling a frame entry may grow (and move) the table.
    #[cfg(feature = "compiled-runtime")]
    { ctx.frame_entries = it.frame_entries.as_ptr(); ctx.nframe_entries = it.frame_entries.len() as u64; }
}

/// The highest frame of `tid` whose return the Rust path must take.
fn guard(it: &mut Interp, tid: usize) -> u64 {
    if it.scheduler.as_ref().is_some_and(|s| s.controls.contains_key(&tid)) && it.unwind_state(tid) != Value::NIL { return GUARD_ALL; }
    let t = &it.tasks[tid];
    let cleanup = t.cleanups.last().map(|c| c.frame as u64);
    let protected = t.protected.last().map(|p| p.frame as u64);
    match (cleanup, protected) { (None, None) => NO_GUARD, (a, b) => a.unwrap_or(0).max(b.unwrap_or(0)) }
}

/// Executes one opcode of the context's task in Rust and answers the next
/// pc, or a status when the frame changed or the task finished.
pub(crate) fn rt_exec_op(ctx: *mut Ctx, pc: u32) -> u32 {
    let ctx = unsafe { &mut *ctx };
    let it = unsafe { &mut *(ctx.interp as *mut Interp) };
    let tid = ctx.tid as usize;
    charge(ctx, it);
    // The core moved frames on its own; the task record learns the top first.
    it.tasks[tid].set_cur(ctx.cur as usize);
    it.last_nres = ctx.last_nres as usize;
    // The frame's pc, for the backtrace of an error this op raises.
    it.tasks[tid].note_pc(pc as usize + 1);
    let (win, _) = it.window(tid);
    #[cfg(feature = "opstats")]
    if let Some(st) = it.op_stats.as_mut() { let op = it.funcs[win.fid as usize].code[pc as usize]; *st.entry(crate::interp::op_name(&op)).or_insert(0) += 1; }
    // A raise inside the opcode becomes the error status: the core returns
    // and `run_threaded` re-raises where Rust frames can carry it.
    let mark = it.handles.len();
    let stepped = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        if crate::interp::budget_point(&it.funcs[win.fid as usize].code[pc as usize], &win)
            && !it.take_budget_point(tid, pc as usize) {
            return Step::Return(Outcome::Parked(0));
        }
        it.step(tid, &win, pc as usize)
    }));
    if stepped.is_err() { it.handles.truncate(mark); }
    let r = match stepped {
        Ok(Step::Next(np)) => np as u32,
        Ok(Step::Reenter) => ST_REENTER,
        Ok(Step::Return(Outcome::Done(v))) => { ctx.result = v.0; ST_DONE }
        Ok(Step::Return(Outcome::Parked(k))) => { ctx.result = k; ST_PARKED }
        Err(p) => { let v = it.error_value(p); it.pending_error = Some(v); ctx.status = ST_ERROR; ST_ERROR }
    };
    sync(ctx, it);
    r
}

/// Enters the compiled frame of the function on top at `pc` -- its start, or
/// a back edge -- compiling it first when the core counted it `hot`, or
/// applies the interpreter's policy for one with vector instructions and no
/// compiled entry. Answers the pc to go on interpreting at, or a status.
pub(crate) fn rt_enter_frame(ctx: *mut Ctx, pc: u32, flags: u32) -> u32 {
    let ctx = unsafe { &mut *ctx };
    let it = unsafe { &mut *(ctx.interp as *mut Interp) };
    let tid = ctx.tid as usize;
    charge(ctx, it);
    it.tasks[tid].set_cur(ctx.cur as usize);
    it.last_nres = ctx.last_nres as usize;
    let fid = (it.tasks[tid].stack[ctx.cur as usize] & 0xffff_ffff) as u32;
    let mark = it.handles.len();
    let entered = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| it.enter_frame_from_core(tid, fid, pc as usize, flags & 1 != 0, flags & 2 != 0)));
    if entered.is_err() { it.handles.truncate(mark); }
    let r = match entered {
        Ok(Ok(next)) => next as u32,
        Ok(Err(Step::Reenter)) => ST_REENTER,
        Ok(Err(Step::Return(Outcome::Done(v)))) => { ctx.result = v.0; ST_DONE }
        Ok(Err(Step::Return(Outcome::Parked(k)))) => { ctx.result = k; ST_PARKED }
        Ok(Err(Step::Next(next))) => next as u32,
        Err(p) => { let v = it.error_value(p); it.pending_error = Some(v); ctx.status = ST_ERROR; ST_ERROR }
    };
    sync(ctx, it);
    r
}

/// Brings the task record up to date with the core before Rust touches it.
#[inline]
pub(crate) fn enter_rust(ctx: &mut Ctx) -> (&'static mut Interp, usize) {
    let it = unsafe { &mut *(ctx.interp as *mut Interp) };
    let tid = ctx.tid as usize;
    charge(ctx, it);
    it.tasks[tid].set_cur(ctx.cur as usize);
    it.tasks[tid].note_pc(ctx.pc as usize + 1);
    it.last_nres = ctx.last_nres as usize;
    (it, tid)
}
/// A field read by name the core could not resolve from the shape: a table's
/// hash part, a structural record's overflow, or an absent field (nil).
pub(crate) fn rt_get_field(ctx: *mut Ctx, obj: u64, name: u64) -> u64 {
    let ctx = unsafe { &mut *ctx };
    let (it, _) = enter_rust(ctx);
    let v = it.guarded(|it| it.field(Value(obj), Value(name)));
    if v == Value::ERROR { ctx.status = ST_ERROR; }
    sync(ctx, it);
    v.0
}
/// The insertion barrier (4.2) for a store the core makes while marking.
pub(crate) fn rt_barrier(ctx: *mut Ctx, parent: u64, child: u64) {
    let (it, _) = enter_rust(unsafe { &mut *ctx });
    if let Some(p) = Value(parent).as_obj() { it.heap.barrier(p, Value(child)); }
}
/// A builtin called from the core: arguments in the window from `base + 1`,
/// results delivered from `base`. Host services, which may park, are not
/// taken here: the core hands those to `rt_exec_op`.
pub(crate) fn rt_call_builtin(ctx: *mut Ctx, id: u32, base: u64, nargs: u32) {
    let ctx = unsafe { &mut *ctx };
    let (it, tid) = enter_rust(ctx);
    let args = it.call_args(tid, base as usize + 1, nargs as u8);
    let mut outs = crate::builtins::Outs::new();
    let r = it.guarded(|it| { outs = crate::builtins::call(it, id, args.as_slice()); Value::NIL });
    if r == Value::ERROR { ctx.status = ST_ERROR; sync(ctx, it); return; }
    it.note_results(outs.as_slice());
    let t = &mut it.tasks[tid];
    if outs.is_empty() { t.stack[base as usize] = Value::NIL.0; }
    for (i, v) in outs.iter().take(8).enumerate() { t.stack[base as usize + i] = v.0; }
    sync(ctx, it);
}
/// One step of an iterator object called as a function.
pub(crate) fn rt_call_iter(ctx: *mut Ctx, iter: u64, base: u64) {
    let ctx = unsafe { &mut *ctx };
    let (it, tid) = enter_rust(ctx);
    let mut outs = crate::builtins::Outs::new();
    let r = it.guarded(|it| { outs = crate::builtins::iter_next(it, Value(iter)); Value::NIL });
    if r == Value::ERROR { ctx.status = ST_ERROR; sync(ctx, it); return; }
    it.note_results(outs.as_slice());
    let t = &mut it.tasks[tid];
    if outs.is_empty() { t.stack[base as usize] = Value::NIL.0; }
    for (i, v) in outs.iter().take(8).enumerate() { t.stack[base as usize + i] = v.0; }
    sync(ctx, it);
}
pub(crate) fn rt_new_record(ctx: *mut Ctx, shape: u32) -> u64 {
    let ctx = unsafe { &mut *ctx };
    let (it, _) = enter_rust(ctx);
    let v = it.guarded(|it| it.new_record(shape));
    if v == Value::ERROR { ctx.status = ST_ERROR; }
    sync(ctx, it);
    v.0
}
/// Equality past the word compare, including a guest metamethod callback.
pub(crate) fn rt_eq_slow(ctx: *mut Ctx, x: u64, y: u64) -> u32 {
    let ctx = unsafe { &mut *ctx };
    let (it, _) = enter_rust(ctx);
    let r = it.guarded(|it| Value::boolean(it.equals(Value(x), Value(y))));
    if r == Value::ERROR { ctx.status = ST_ERROR; }
    sync(ctx, it);
    (r == Value::TRUE) as u32
}

impl Interp {
    /// Encodes every function for the core and builds its table. Called once
    /// after loading; a later load must call it again.
    pub fn prepare_threaded(&mut self) {
        if std::env::var("NO_THREADED").is_ok() { self.threaded = false; return; }
        self.shape_info = self.heap.shapes.iter().map(|s| ShapeInfo { names: s.names.as_ptr() as *const u64, n: s.names.len() as u64, table: s.table.as_ptr() as *const u64, mask: s.mask }).collect();
        for f in &mut self.funcs { if f.ins.len() != f.code.len() + jump_words(f).len() / 4 { f.ins = encode_function(f); } }
        self.finfo = self.funcs.iter().map(|f: &Function| FuncInfo { code: f.ins.as_ptr(), consts: f.consts.as_ptr() as *const u64, frame_words: f.frame_words() as u32, nregs: f.nregs as u32, nparams: f.nparams as u32, off_i: f.off_i() as u32, off_f: f.off_f() as u32, off_v: f.off_v() as u32, vararg: f.vararg as u32, ncode: f.code.len() as u32, calls: 0, typed: f.sig.contains(&b'f') as u32, native: f.code.iter().any(crate::native_simd::required) as u32 }).collect();
        self.threaded = true;
    }

    /// Runs the task on the native core until it finishes or parks.
    #[cfg(feature = "native-runtime")]
    pub fn run_threaded(&mut self, tid: usize) -> Outcome {
        let _caller = self.enter_caller(crate::interp::Caller::Task(tid));
        let _execution = crate::persist::Execution::enter(&self.execution_depth);
        assert_eq!(self.tasks[tid].state, State::Runnable);
        if self.finfo.len() != self.funcs.len() || self.shape_info.len() != self.heap.shapes.len() { self.prepare_threaded(); }
        let slow = slow_calls();
        #[cfg(feature = "compiled-runtime")]
        let (frame_entries, nframe_entries) = if !self.frame_entries.is_empty() { (self.frame_entries.as_ptr(), self.frame_entries.len() as u64) } else { (std::ptr::null(), 0) };
        #[cfg(not(feature = "compiled-runtime"))]
        let (frame_entries, nframe_entries): (*const u64, u64) = (std::ptr::null(), 0);
        #[cfg(feature = "jit")]
        let jit_frames = self.jit.is_some();
        #[cfg(not(feature = "jit"))]
        let jit_frames = false;
        #[cfg(feature = "compiled-runtime")]
        let frame_threshold = self.frame_threshold;
        #[cfg(not(feature = "compiled-runtime"))]
        let frame_threshold = 0;
        let mut ctx = Ctx { interp: self as *mut Interp as *mut std::ffi::c_void, tid: tid as u64, stack: std::ptr::null_mut(), cap: 0, cur: 0, funcs: self.finfo.as_ptr(), nfuncs: self.finfo.len() as u64, status: 0, pc: 0, result: 0, last_nres: 0, shapes: self.shape_info.as_ptr(), nshapes: self.shape_info.len() as u64, marking: &self.heap.marking as *const u8, feedback: 0, guard: NO_GUARD, slow_calls: slow.as_ptr(), nslow_calls: slow.len() as u64, frame_entries, nframe_entries, unavailable_fid: self.unavailable_fid, jit_frames: jit_frames as u32, frame_threshold, budget: u64::MAX, budget_mark: u64::MAX, cleanups: std::ptr::null_mut(), ncleanups: 0 };
        sync(&mut ctx, self);
        // The core reports call targets and receivers while feedback is on.
        #[cfg(feature = "jit")]
        { ctx.feedback = self.spec.feedback as u32; }
        // The JIT's glue reaches the context of the task the core is running
        // on this thread when a compiled frame is entered.
        #[cfg(feature = "aot")]
        let _current = crate::jit_glue::ContextGuard::enter(&mut ctx);
        let status = unsafe { crate::dispatch::run(&mut ctx) };
        // The core's pops do not touch the task record; its state, last
        // result count and what it took of the budgets are brought over here.
        charge(&mut ctx, self);
        self.last_nres = ctx.last_nres as usize;
        self.tasks[tid].set_cur(ctx.cur as usize);
        match status {
            ST_DONE => { let v = Value(ctx.result); let t = &mut self.tasks[tid]; if t.state != State::Done { t.state = State::Done; t.result = v; } Outcome::Done(t.result) }
            ST_PARKED => Outcome::Parked(ctx.result),
            ST_ERROR => { let v = self.pending_error.take().unwrap_or(Value::NIL); std::panic::panic_any(crate::builtins::LuaError(v.0)) }
            s => panic!("threaded core returned status {s:#x}"),
        }
    }
}
