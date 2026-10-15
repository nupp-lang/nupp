//! LPeg 1.1.0, native: `require("lpeg")` on the VM without a C module.
//!
//! A port of the reference implementation (lptree.c, lpcode.c, lpvm.c and
//! lpcap.c, MIT licensed, Roberto Ierusalimschy). Patterns are userdata
//! whose data is the tree of node records LPeg builds, and whose user value
//! is the pattern's `ktable`, the Lua values its nodes name by index. A
//! pattern compiles on first match to LPeg's instruction set, run by the
//! same backtracking machine with the same bounded stack (`setmaxstack`),
//! so neither matching nor deep subjects recurse on the Rust stack. Capture
//! values are produced exactly as lpcap.c produces them, with the VM's
//! handle stack standing in for the Lua stack: every value LPeg would keep
//! on the Lua stack stays rooted there.
//!
//! Instructions take one slot each and jumps hold absolute targets, and a
//! charset is a full 256-bit set rather than LPeg's compacted one; neither
//! changes what a pattern matches or captures.

use std::sync::Arc;

use crate::builtins::{LuaError, Outs};
use crate::heap::{KIND_CLOSURE, KIND_ITER, KIND_RECORD, KIND_TABLE, KIND_USERDATA};
use crate::interp::Interp;
use crate::value::Value;

/// The builtins behind the library and the pattern metatable.
pub const BUILTINS: &[&str] = &[
    "lpeg.ptree", "lpeg.pcode", "lpeg.match", "lpeg.B", "lpeg.V", "lpeg.C", "lpeg.Cc", "lpeg.Cmt", "lpeg.Cb", "lpeg.Carg", "lpeg.Cp", "lpeg.Cs", "lpeg.Ct", "lpeg.Cf", "lpeg.Cg",
    "lpeg.P", "lpeg.S", "lpeg.R", "lpeg.utfR", "lpeg.locale", "lpeg.setmaxstack", "lpeg.type",
    "lpeg.__mul", "lpeg.__add", "lpeg.__pow", "lpeg.__len", "lpeg.__div", "lpeg.__mod", "lpeg.__unm", "lpeg.__sub",
];

const VERSION: &str = "LPeg 1.1.0";
const MAXBACK: usize = 400;
const MAXRULES: usize = 1000;
const MAXBEHIND: i32 = 255;
const MAXOFF: i32 = 0xF;
const MAXLOP: usize = 20;
const MAXRECLEVEL: usize = 200;
const MAXSTRCAPS: usize = 10;
const FIXEDARGS: usize = 3;
const USHRT_MAX: usize = 65535;
const SHRT_MAX: i64 = 32767;
const MAXLIM: i64 = i32::MAX as i64 / 100;

// ---- trees (lptree.h) ------------------------------------------------------

const TCHAR: u8 = 0;
const TSET: u8 = 1;
const TANY: u8 = 2;
const TTRUE: u8 = 3;
const TFALSE: u8 = 4;
const TUTFR: u8 = 5;
const TREP: u8 = 6;
const TSEQ: u8 = 7;
const TCHOICE: u8 = 8;
const TNOT: u8 = 9;
const TAND: u8 = 10;
const TCALL: u8 = 11;
const TOPENCALL: u8 = 12;
const TRULE: u8 = 13;
const TXINFO: u8 = 14;
const TGRAMMAR: u8 = 15;
const TBEHIND: u8 = 16;
const TCAPTURE: u8 = 17;
const TRUNTIME: u8 = 18;

const NUMSIBLINGS: [u8; 19] = [0, 0, 0, 0, 0, 0, 1, 2, 2, 1, 1, 0, 0, 2, 1, 1, 1, 1, 1];

// Capture kinds (lpcap.h).
const CCLOSE: u8 = 0;
const CPOSITION: u8 = 1;
const CCONST: u8 = 2;
const CBACKREF: u8 = 3;
const CARG: u8 = 4;
const CSIMPLE: u8 = 5;
const CTABLE: u8 = 6;
const CFUNCTION: u8 = 7;
const CACC: u8 = 8;
const CQUERY: u8 = 9;
const CSTRING: u8 = 10;
const CNUM: u8 = 11;
const CSUBST: u8 = 12;
const CFOLD: u8 = 13;
const CRUNTIME: u8 = 14;
const CGROUP: u8 = 15;

/// One tree node: `n` is the second child's offset, a counter or a
/// character, as LPeg's union is. A `TSet` node is followed by four nodes
/// that carry its 32-byte set.
#[derive(Clone, Copy, Default, PartialEq, Eq, Debug)]
struct T { tag: u8, cap: u8, key: u16, n: i32 }

const SETSLOTS: usize = 4;
type Cs = [u8; 32];
const FULLSET: Cs = [0xFF; 32];

#[inline] fn sib1(i: usize) -> usize { i + 1 }
#[inline] fn sib2(t: &[T], i: usize) -> usize { (i as i64 + t[i].n as i64) as usize }

fn set_read(t: &[T], i: usize) -> Cs {
    let mut cs = [0u8; 32];
    for k in 0..SETSLOTS {
        let d = t[i + 1 + k];
        let w = d.tag as u64 | (d.cap as u64) << 8 | (d.key as u64) << 16 | (d.n as u32 as u64) << 32;
        cs[8 * k..8 * k + 8].copy_from_slice(&w.to_le_bytes());
    }
    cs
}
fn set_tree(cs: &Cs) -> Vec<T> {
    let mut v = vec![T { tag: TSET, ..T::default() }];
    for k in 0..SETSLOTS {
        let w = u64::from_le_bytes(cs[8 * k..8 * k + 8].try_into().unwrap());
        v.push(T { tag: w as u8, cap: (w >> 8) as u8, key: (w >> 16) as u16, n: (w >> 32) as u32 as i32 });
    }
    v
}
#[inline] fn setchar(cs: &mut Cs, c: usize) { cs[c >> 3] |= 1 << (c & 7); }
#[inline] fn testchar(cs: &Cs, c: u8) -> bool { (cs[(c >> 3) as usize] >> (c & 7)) & 1 != 0 }

// ---- charsets (lpcset.c) ---------------------------------------------------

enum CsType { Fail, Any, Char(u8), Set }

fn charsettype(cs: &Cs) -> CsType {
    let count: u32 = cs.iter().map(|b| b.count_ones()).sum();
    if count == 0 { return CsType::Fail; }
    if count == 256 { return CsType::Any; }
    if count == 1 {
        let i = cs.iter().position(|&b| b != 0).unwrap();
        return CsType::Char((i * 8 + cs[i].trailing_zeros() as usize) as u8);
    }
    CsType::Set
}

fn tocharset(t: &[T], i: usize) -> Option<Cs> {
    match t[i].tag {
        TCHAR => { let mut cs = [0u8; 32]; setchar(&mut cs, t[i].n as usize); Some(cs) }
        TANY => Some(FULLSET),
        TFALSE => Some([0u8; 32]),
        TSET => Some(set_read(t, i)),
        _ => None,
    }
}

fn newcharset(cs: &Cs) -> Vec<T> {
    match charsettype(cs) {
        CsType::Fail => vec![T { tag: TFALSE, ..T::default() }],
        CsType::Any => vec![T { tag: TANY, ..T::default() }],
        CsType::Char(c) => vec![T { tag: TCHAR, n: c as i32, ..T::default() }],
        CsType::Set => set_tree(cs),
    }
}

// ---- errors and Lua values -------------------------------------------------

fn raise(it: &mut Interp, msg: &[u8]) -> ! {
    let s = it.new_string_bytes(msg);
    std::panic::panic_any(LuaError(s.0))
}
fn raise_str(it: &mut Interp, msg: &str) -> ! { raise(it, msg.as_bytes()) }
fn argerror(it: &mut Interp, arg: usize, fname: &str, msg: &str) -> ! {
    raise_str(it, &format!("bad argument #{arg} to '{fname}' ({msg})"))
}
fn typename(it: &Interp, v: Value) -> &'static str { crate::builtins::type_name(it, v) }
fn typeerror(it: &mut Interp, args: &[Value], arg: usize, fname: &str, expected: &str) -> ! {
    let got = if arg > args.len() { "no value" } else { typename(it, args[arg - 1]) };
    argerror(it, arg, fname, &format!("{expected} expected, got {got}"))
}

fn arg(args: &[Value], i: usize) -> Value { args.get(i).copied().unwrap_or(Value::NIL) }
fn is_number(v: Value) -> bool { crate::numeric::is_numeric(v) }
fn is_table(it: &Interp, v: Value) -> bool { matches!(it.kind_of(v), Some(KIND_TABLE | KIND_RECORD)) && !crate::storage::is_native(v) }
fn is_function(it: &Interp, v: Value) -> bool { v.as_func_in().is_some() || matches!(it.kind_of(v), Some(KIND_CLOSURE | KIND_ITER)) }
fn number_of(it: &Interp, v: Value) -> Option<f64> {
    if v.is_num() { return Some(v.as_num()); }
    if let Some(i) = crate::numeric::integer(v) { return Some(if i.unsigned { i.bits as f64 } else { i.bits as i64 as f64 }); }
    if it.is_stringish(v) { return parse_number(it.bytes_of(v)); }
    None
}
fn parse_number(b: &[u8]) -> Option<f64> {
    let s = std::str::from_utf8(b).ok()?.trim();
    if let Some(h) = s.strip_prefix("0x").or_else(|| s.strip_prefix("0X")) { return u64::from_str_radix(h, 16).ok().map(|n| n as f64); }
    if s.is_empty() || !s.bytes().all(|c| c.is_ascii_digit() || matches!(c, b'.' | b'e' | b'E' | b'+' | b'-')) { return None; }
    s.parse::<f64>().ok()
}
fn tointeger(it: &Interp, v: Value) -> Option<i64> {
    if let Some(i) = crate::numeric::integer(v) { return Some(i.bits as i64); }
    number_of(it, v).map(|n| if n.is_nan() { 0 } else { n as i64 })
}
fn checkinteger(it: &mut Interp, args: &[Value], i: usize, fname: &str) -> i64 {
    match tointeger(it, arg(args, i - 1)) { Some(n) => n, None => typeerror(it, args, i, fname, "number") }
}
/// `lua_tostring` for messages: strings and numbers, else None.
fn tostring_opt(it: &mut Interp, v: Value) -> Option<Vec<u8>> {
    if it.is_stringish(v) || is_number(v) { Some(crate::builtins::tostring(it, v)) } else { None }
}
/// LPeg's `val2str`: a name for a rule key in messages.
fn val2str(it: &mut Interp, v: Value) -> Vec<u8> {
    match tostring_opt(it, v) { Some(b) => b, None => format!("(a {})", typename(it, v)).into_bytes() }
}
fn msg_with(prefix: &str, name: &[u8], suffix: &str) -> Vec<u8> {
    let mut m = prefix.as_bytes().to_vec(); m.extend_from_slice(name); m.extend_from_slice(suffix.as_bytes()); m
}

fn push(it: &mut Interp, v: Value) -> Value { it.handles.push(v); v }
fn new_table(it: &mut Interp) -> Value { let t = it.new_table(); push(it, t) }
fn rawgeti(it: &Interp, t: Value, i: usize) -> Value { if t == Value::NIL { Value::NIL } else { it.get_index(t, Value::num(i as f64)) } }

// ---- pattern objects -------------------------------------------------------

/// A pattern's native data: its tree and, once matched, its code.
pub struct Pattern { tree: Vec<T>, code: Option<Arc<Code>> }

fn is_pattern(it: &Interp, v: Value) -> bool {
    match v.as_obj() { Some(p) => { let h = unsafe { p.as_ref() }; h.kind == KIND_USERDATA && h.userdata().meta == it.lpeg_meta && h.userdata().data.is::<Pattern>() } None => false }
}
/// The pattern behind `v`, which the caller has checked and keeps rooted;
/// the heap never moves it. Shared, since `p * p` reads one pattern twice.
fn pat<'a>(v: Value) -> &'a Pattern {
    unsafe { (*v.as_obj().unwrap().as_ptr()).userdata().data.downcast_ref::<Pattern>().unwrap() }
}
/// The pattern behind `v`, to compile it: no other reference to it is live.
fn pat_mut<'a>(v: Value) -> &'a mut Pattern {
    unsafe { (*v.as_obj().unwrap().as_ptr()).userdata_mut().data.downcast_mut::<Pattern>().unwrap() }
}
fn ktable_of(v: Value) -> Value { unsafe { (*v.as_obj().unwrap().as_ptr()).userdata().uservalue } }

fn new_pattern(it: &mut Interp, tree: Vec<T>, ktable: Value) -> Value {
    let external = tree.len() * std::mem::size_of::<T>();
    let meta = it.lpeg_meta;
    let p = it.new_userdata(Box::new(Pattern { tree, code: None }), meta, ktable, external);
    push(it, p)
}
fn leaf(tag: u8) -> Vec<T> { vec![T { tag, ..T::default() }] }

// ---- ktables ---------------------------------------------------------------

fn ktablelen(it: &Interp, kt: Value) -> usize { if kt == Value::NIL || !is_table(it, kt) { 0 } else { it.array_len(kt) } }

/// Appends `v` to `kt`; nil is never stored and answers 0.
fn addtoktable(it: &mut Interp, kt: Value, v: Value) -> u16 {
    if v == Value::NIL { return 0; }
    let n = ktablelen(it, kt);
    if n >= USHRT_MAX { raise_str(it, "too many Lua values in pattern"); }
    it.set_index(kt, Value::num((n + 1) as f64), v);
    (n + 1) as u16
}
/// Copies `from` after the elements of `to`; the original length of `to`,
/// or 0 when nothing was added.
fn concattable(it: &mut Interp, from: Value, to: Value) -> usize {
    let n1 = ktablelen(it, from);
    let n2 = ktablelen(it, to);
    if n1 + n2 > USHRT_MAX { raise_str(it, "too many Lua values in pattern"); }
    if n1 == 0 { return 0; }
    for i in 1..=n1 { let v = rawgeti(it, from, i); it.set_index(to, Value::num((n2 + i) as f64), v); }
    n2
}
fn correctkeys(t: &mut [T], mut i: usize, n: usize) {
    if n == 0 { return; }
    loop {
        match t[i].tag {
            TOPENCALL | TCALL | TRUNTIME | TRULE => { if t[i].key > 0 { t[i].key += n as u16; } }
            TCAPTURE => { if t[i].key > 0 && t[i].cap != CARG && t[i].cap != CNUM { t[i].key += n as u16; } }
            _ => {}
        }
        match NUMSIBLINGS[t[i].tag as usize] {
            1 => i = sib1(i),
            2 => { correctkeys(t, sib1(i), n); i = sib2(t, i); }
            _ => return,
        }
    }
}
/// The ktable for a pattern joining `p1` and `p2`, whose second subtree
/// starts at `at` in `tree`.
fn joinktables(it: &mut Interp, k1: Value, k2: Value, tree: &mut [T], at: usize) -> Value {
    let n1 = ktablelen(it, k1);
    let n2 = ktablelen(it, k2);
    if n1 == 0 && n2 == 0 { return Value::NIL; }
    if n2 == 0 || k1 == k2 { return k1; }
    if n1 == 0 { return k2; }
    let kt = new_table(it);
    concattable(it, k1, kt);
    concattable(it, k2, kt);
    correctkeys(tree, at, n1);
    kt
}
/// A fresh ktable holding `from`'s values (when given) and then `v`.
fn addtonewktable(it: &mut Interp, from: Option<Value>, v: Value) -> (Value, u16) {
    let kt = new_table(it);
    if let Some(from) = from { concattable(it, from, kt); }
    let key = addtoktable(it, kt, v);
    (kt, key)
}

// ---- tree construction -----------------------------------------------------

fn fillseq(tag: u8, n: usize, s: Option<&[u8]>) -> Vec<T> {
    let mut t = Vec::with_capacity(2 * n);
    for i in 0..n - 1 {
        t.push(T { tag: TSEQ, n: 2, ..T::default() });
        t.push(T { tag, n: s.map(|s| s[i] as i32).unwrap_or(0), ..T::default() });
    }
    t.push(T { tag, n: s.map(|s| s[n - 1] as i32).unwrap_or(0), ..T::default() });
    t
}
fn numtree(it: &mut Interp, n: i64) -> Vec<T> {
    if n == 0 { return leaf(TTRUE); }
    let m = n.unsigned_abs() as usize;
    if m > (i32::MAX as usize) / 2 { raise_str(it, "pattern too large"); }
    if n > 0 { fillseq(TANY, m, None) } else { let mut t = leaf(TNOT); t.extend(fillseq(TANY, m, None)); t }
}

/// The value `v` as a pattern: itself, or a new pattern made from a string,
/// number, boolean, grammar table or function.
fn getpatt(it: &mut Interp, v: Value, argn: usize, fname: &str) -> Value {
    if is_pattern(it, v) { return v; }
    let tree = if it.is_stringish(v) {
        let s = it.bytes_of(v).to_vec();
        if s.is_empty() { leaf(TTRUE) } else { fillseq(TCHAR, s.len(), Some(&s)) }
    } else if is_number(v) {
        let n = tointeger(it, v).unwrap_or(0);
        numtree(it, n)
    } else if v == Value::TRUE { leaf(TTRUE) }
    else if v == Value::FALSE { leaf(TFALSE) }
    else if is_table(it, v) { return newgrammar(it, v); }
    else if is_function(it, v) {
        let (kt, key) = addtonewktable(it, None, v);
        let tree = vec![T { tag: TRUNTIME, key, ..T::default() }, T { tag: TTRUE, ..T::default() }];
        return new_pattern(it, tree, kt);
    } else {
        let got = if v == Value::NIL { "nil" } else { typename(it, v) };
        argerror(it, argn, fname, &format!("lpeg-pattern expected, got {got}"))
    };
    new_pattern(it, tree, Value::NIL)
}
fn tree_of<'a>(p: Value) -> &'a [T] { &pat(p).tree }

fn newroot1sib(it: &mut Interp, tag: u8, v: Value, fname: &str) -> (Vec<T>, Value) {
    let p = getpatt(it, v, 1, fname);
    let mut tree = leaf(tag);
    tree.extend_from_slice(tree_of(p));
    (tree, ktable_of(p))
}
fn newroot2sib(it: &mut Interp, tag: u8, p1: Value, p2: Value) -> Value {
    let (t1, t2) = (tree_of(p1), tree_of(p2));
    let mut tree = Vec::with_capacity(1 + t1.len() + t2.len());
    tree.push(T { tag, n: 1 + t1.len() as i32, ..T::default() });
    tree.extend_from_slice(t1);
    tree.extend_from_slice(t2);
    let at = 1 + t1.len();
    let kt = joinktables(it, ktable_of(p1), ktable_of(p2), &mut tree, at);
    new_pattern(it, tree, kt)
}

fn lp_seq(it: &mut Interp, args: &[Value]) -> Value {
    let p1 = getpatt(it, arg(args, 0), 1, "__mul");
    let p2 = getpatt(it, arg(args, 1), 2, "__mul");
    let (t1, t2) = (tree_of(p1)[0].tag, tree_of(p2)[0].tag);
    if t1 == TFALSE || t2 == TTRUE { p1 } else if t1 == TTRUE { p2 } else { newroot2sib(it, TSEQ, p1, p2) }
}
fn lp_choice(it: &mut Interp, args: &[Value]) -> Value {
    let p1 = getpatt(it, arg(args, 0), 1, "__add");
    let p2 = getpatt(it, arg(args, 1), 2, "__add");
    if let (Some(mut c1), Some(c2)) = (tocharset(tree_of(p1), 0), tocharset(tree_of(p2), 0)) {
        for i in 0..32 { c1[i] |= c2[i]; }
        return new_pattern(it, newcharset(&c1), Value::NIL);
    }
    if nofail(tree_of(p1), 0) || tree_of(p2)[0].tag == TFALSE { p1 }
    else if tree_of(p1)[0].tag == TFALSE { p2 }
    else { newroot2sib(it, TCHOICE, p1, p2) }
}
fn seqaux(tree: &mut [T], at: usize, sib: &[T]) -> usize {
    tree[at] = T { tag: TSEQ, n: sib.len() as i32 + 1, ..T::default() };
    tree[at + 1..at + 1 + sib.len()].copy_from_slice(sib);
    at + sib.len() + 1
}
fn lp_star(it: &mut Interp, args: &[Value]) -> Value {
    let n = checkinteger(it, args, 2, "__pow");
    let p1 = getpatt(it, arg(args, 0), 1, "__pow");
    let t1 = tree_of(p1).to_vec();
    let size1 = t1.len();
    let tree = if n >= 0 {
        if nullable(tree_of(p1), 0) { raise_str(it, "loop body may accept empty string"); }
        let total = (n as usize + 1).checked_mul(size1 + 1).filter(|&s| s < i32::MAX as usize).unwrap_or_else(|| raise_str(it, "pattern too large"));
        let mut tree = vec![T::default(); total];
        let mut at = 0;
        for _ in 0..n { at = seqaux(&mut tree, at, &t1); }
        tree[at] = T { tag: TREP, ..T::default() };
        tree[at + 1..at + 1 + size1].copy_from_slice(&t1);
        tree.truncate(at + 1 + size1);
        tree
    } else {
        let mut n = n.unsigned_abs() as usize;
        let total = n.checked_mul(size1 + 3).filter(|&s| s < i32::MAX as usize).unwrap_or_else(|| raise_str(it, "pattern too large")) - 1;
        let mut tree = vec![T::default(); total];
        let mut at = 0;
        while n > 1 {
            tree[at] = T { tag: TCHOICE, n: (n * (size1 + 3) - 2) as i32, ..T::default() };
            let s2 = sib2(&tree, at); tree[s2] = T { tag: TTRUE, ..T::default() };
            at = seqaux(&mut tree, sib1(at), &t1);
            n -= 1;
        }
        tree[at] = T { tag: TCHOICE, n: size1 as i32 + 1, ..T::default() };
        let s2 = sib2(&tree, at); tree[s2] = T { tag: TTRUE, ..T::default() };
        tree[at + 1..at + 1 + size1].copy_from_slice(&t1);
        tree
    };
    let kt = ktable_of(p1);
    new_pattern(it, tree, kt)
}
fn lp_and(it: &mut Interp, args: &[Value]) -> Value { let (t, kt) = newroot1sib(it, TAND, arg(args, 0), "__len"); new_pattern(it, t, kt) }
fn lp_not(it: &mut Interp, args: &[Value]) -> Value { let (t, kt) = newroot1sib(it, TNOT, arg(args, 0), "__unm"); new_pattern(it, t, kt) }
fn lp_sub(it: &mut Interp, args: &[Value]) -> Value {
    let p1 = getpatt(it, arg(args, 0), 1, "__sub");
    let p2 = getpatt(it, arg(args, 1), 2, "__sub");
    if let (Some(mut c1), Some(c2)) = (tocharset(tree_of(p1), 0), tocharset(tree_of(p2), 0)) {
        for i in 0..32 { c1[i] &= !c2[i]; }
        return new_pattern(it, newcharset(&c1), Value::NIL);
    }
    let (t1, t2) = (tree_of(p1), tree_of(p2));
    let mut tree = Vec::with_capacity(2 + t1.len() + t2.len());
    tree.push(T { tag: TSEQ, n: 2 + t2.len() as i32, ..T::default() });
    tree.push(T { tag: TNOT, ..T::default() });
    tree.extend_from_slice(t2);
    tree.extend_from_slice(t1);
    let kt = joinktables(it, ktable_of(p1), ktable_of(p2), &mut tree, 1);
    new_pattern(it, tree, kt)
}
fn lp_set(it: &mut Interp, args: &[Value]) -> Value {
    let v = arg(args, 0);
    if !(it.is_stringish(v) || is_number(v)) { typeerror(it, args, 1, "S", "string"); }
    let s = crate::builtins::tostring(it, v);
    let mut cs = [0u8; 32];
    for &c in &s { setchar(&mut cs, c as usize); }
    new_pattern(it, newcharset(&cs), Value::NIL)
}
fn lp_range(it: &mut Interp, args: &[Value]) -> Value {
    let mut cs = [0u8; 32];
    for (i, &v) in args.iter().enumerate() {
        if !(it.is_stringish(v) || is_number(v)) { typeerror(it, args, i + 1, "R", "string"); }
        let r = crate::builtins::tostring(it, v);
        if r.len() != 2 { argerror(it, i + 1, "R", "range must have two characters"); }
        for c in r[0] as usize..=r[1] as usize { setchar(&mut cs, c); }
    }
    new_pattern(it, newcharset(&cs), Value::NIL)
}
fn codeutftree(it: &mut Interp, cpu: u64, argn: usize) -> T {
    let cp = cpu as i64;
    let (len, fb) = if cp <= 0x7f { (1, cp) } else if cp <= 0x7ff { (2, 0xC0 | (cp >> 6)) } else if cp <= 0xffff { (3, 0xE0 | (cp >> 12)) } else {
        if cpu > 0x10ffff { argerror(it, argn, "utfR", "invalid code point"); }
        (4, 0xF0 | (cp >> 18))
    };
    T { tag: 0, cap: len, key: fb as u16, n: cp as i32 }
}
fn lp_utfr(it: &mut Interp, args: &[Value]) -> Value {
    let from = checkinteger(it, args, 1, "utfR") as u64;
    let to = checkinteger(it, args, 2, "utfR") as u64;
    if from > to { argerror(it, 2, "utfR", "empty range"); }
    if to <= 0x7f {
        let mut cs = [0u8; 32];
        for f in from..=to { setchar(&mut cs, f as usize); }
        return new_pattern(it, newcharset(&cs), Value::NIL);
    }
    let mut a = codeutftree(it, from, 1); a.tag = TUTFR;
    let mut b = codeutftree(it, to, 2); b.tag = TXINFO;
    new_pattern(it, vec![a, b], Value::NIL)
}
fn lp_behind(it: &mut Interp, args: &[Value]) -> Value {
    let p = getpatt(it, arg(args, 0), 1, "B");
    let mut t = tree_of(p).to_vec();
    let n = fixedlen(&mut t, 0);
    if n < 0 { argerror(it, 1, "B", "pattern may not have fixed length"); }
    if hascaptures(&mut t, 0) { argerror(it, 1, "B", "pattern have captures"); }
    if n > MAXBEHIND { argerror(it, 1, "B", "pattern too long to look behind"); }
    let (mut tree, kt) = newroot1sib(it, TBEHIND, p, "B");
    tree[0].n = n;
    new_pattern(it, tree, kt)
}
fn lp_v(it: &mut Interp, args: &[Value]) -> Value {
    let v = arg(args, 0);
    if v == Value::NIL { argerror(it, 1, "V", "non-nil value expected"); }
    let (kt, key) = addtonewktable(it, None, v);
    new_pattern(it, vec![T { tag: TOPENCALL, key, ..T::default() }], kt)
}
fn capture_aux(it: &mut Interp, args: &[Value], cap: u8, label: Option<Value>, fname: &str) -> Value {
    let (mut tree, kt) = newroot1sib(it, TCAPTURE, arg(args, 0), fname);
    tree[0].cap = cap;
    match label {
        None => new_pattern(it, tree, kt),
        Some(v) => { let (nkt, key) = addtonewktable(it, Some(kt), v); tree[0].key = key; new_pattern(it, tree, nkt) }
    }
}
fn emptycap(cap: u8, key: u16) -> Vec<T> { vec![T { tag: TCAPTURE, cap, key, ..T::default() }, T { tag: TTRUE, ..T::default() }] }
fn newemptycapkey(it: &mut Interp, cap: u8, v: Value) -> Value {
    let (kt, key) = addtonewktable(it, None, v);
    new_pattern(it, emptycap(cap, key), kt)
}
fn lp_divcapture(it: &mut Interp, args: &[Value]) -> Value {
    let v = arg(args, 1);
    if is_function(it, v) { return capture_aux(it, args, CFUNCTION, Some(v), "__div"); }
    if is_table(it, v) { return capture_aux(it, args, CQUERY, Some(v), "__div"); }
    if it.is_stringish(v) { return capture_aux(it, args, CSTRING, Some(v), "__div"); }
    if is_number(v) {
        let n = tointeger(it, v).unwrap_or(0);
        let (mut tree, kt) = newroot1sib(it, TCAPTURE, arg(args, 0), "__div");
        if !(0..=SHRT_MAX).contains(&n) { argerror(it, 1, "__div", "invalid number"); }
        tree[0].cap = CNUM; tree[0].key = n as u16;
        return new_pattern(it, tree, kt);
    }
    let name = if v == Value::NIL { "nil" } else { typename(it, v) };
    raise_str(it, &format!("unexpected {name} as 2nd operand to LPeg '/'"))
}
fn lp_constcapture(it: &mut Interp, args: &[Value]) -> Value {
    let n = args.len();
    if n == 0 { return new_pattern(it, leaf(TTRUE), Value::NIL); }
    if n == 1 { return newemptycapkey(it, CCONST, args[0]); }
    let kt = new_table(it);
    let mut tree = vec![T { tag: TCAPTURE, cap: CGROUP, ..T::default() }];
    for (i, &v) in args.iter().enumerate() {
        let key = addtoktable(it, kt, v);
        if i + 1 < n { tree.push(T { tag: TSEQ, n: 3, ..T::default() }); }
        tree.extend(emptycap(CCONST, key));
    }
    new_pattern(it, tree, kt)
}
fn lp_matchtime(it: &mut Interp, args: &[Value]) -> Value {
    if !is_function(it, arg(args, 1)) { typeerror(it, args, 2, "Cmt", "function"); }
    let (mut tree, kt) = newroot1sib(it, TRUNTIME, arg(args, 0), "Cmt");
    let (nkt, key) = addtonewktable(it, Some(kt), arg(args, 1));
    tree[0].key = key;
    new_pattern(it, tree, nkt)
}

// ---- grammars --------------------------------------------------------------

fn newgrammar(it: &mut Interp, g: Value) -> Value {
    // collectrules: the initial rule first, then every other rule.
    let postab = new_table(it);
    let first = it.get_index(g, Value::num(1.0));
    let (fkey, frule) = if it.is_stringish(first) || is_number(first) { let r = it.index_any(g, first); (first, r) } else { (Value::num(1.0), first) };
    push(it, frule);
    if !is_pattern(it, frule) {
        if frule == Value::NIL { raise_str(it, "grammar has no initial rule"); }
        let name = tostring_opt(it, fkey).unwrap_or_default();
        raise(it, &msg_with("initial rule '", &name, "' is not a pattern"));
    }
    it.set_index(postab, fkey, Value::num(1.0));
    let mut rules = vec![(fkey, frule)];
    let mut size = 3 + tree_of(frule).len();
    for key in it.table_keys(g) {
        let value = it.get_index(g, key);
        if value == Value::NIL { continue; }
        if number_of(it, key) == Some(1.0) || it.values_equal(key, fkey) { continue; }
        if !is_pattern(it, value) { let name = val2str(it, key); raise(it, &msg_with("rule '", &name, "' is not a pattern")); }
        push(it, key);
        it.set_index(postab, key, Value::num(size as f64));
        size += 2 + tree_of(value).len();
        rules.push((key, value));
    }
    let total = size + 1;
    let n = rules.len();
    if n > MAXRULES { argerror(it, 1, "P", "grammar has too many rules"); }
    // buildgrammar
    let kt = new_table(it);
    let mut tree = vec![T::default(); total];
    tree[0] = T { tag: TGRAMMAR, n: n as i32, ..T::default() };
    let mut nd = 1;
    for (i, &(_, rule)) in rules.iter().enumerate() {
        let rn = tree_of(rule).to_vec();
        let pr = sib1(nd);
        tree[nd] = T { tag: TRULE, key: 0, n: rn.len() as i32 + 2, ..T::default() };
        tree[pr] = T { tag: TXINFO, n: i as i32, ..T::default() };
        tree[pr + 1..pr + 1 + rn.len()].copy_from_slice(&rn);
        let shift = concattable(it, ktable_of(rule), kt);
        correctkeys(&mut tree, sib1(nd), shift);
        nd = sib2(&tree, nd);
    }
    tree[nd] = T { tag: TTRUE, ..T::default() };
    finalfix(it, Some(postab), Some(0), &mut tree, 1, kt);
    // initialrulename
    if tree[1].key == 0 {
        let k = ktablelen(it, kt) + 1;
        it.set_index(kt, Value::num(k as f64), fkey);
        tree[1].key = k as u16;
    }
    verifygrammar(it, &mut tree, kt);
    new_pattern(it, tree, kt)
}

fn fixonecall(it: &mut Interp, postab: Value, g: usize, t: &mut [T], i: usize, kt: Value) {
    let name = rawgeti(it, kt, t[i].key as usize);
    let pos = if name == Value::NIL { Value::NIL } else { it.get_index_any(postab, name) };
    let n = number_of(it, pos).unwrap_or(0.0) as i64;
    if n == 0 { let s = val2str(it, name); raise(it, &msg_with("rule '", &s, "' undefined in given grammar")); }
    t[i].tag = TCALL;
    t[i].n = (n - (i as i64 - g as i64)) as i32;
    let s2 = sib2(t, i);
    debug_assert!(t[s2].tag == TRULE);
    t[s2].key = t[i].key;
}
fn correctassociativity(t: &mut [T], i: usize) {
    let t1 = sib1(i);
    while t[t1].tag == t[i].tag {
        let n1size = t[i].n as usize - 1;
        let n11size = t[t1].n as usize - 1;
        let n12size = n1size - n11size - 1;
        t.copy_within(sib1(t1)..sib1(t1) + n11size, sib1(i));
        t[i].n = n11size as i32 + 1;
        let s2 = sib2(t, i);
        t[s2].tag = t[i].tag;
        t[s2].n = n12size as i32 + 1;
    }
}
/// Fixes open calls (inside a grammar, against `postab`) and makes
/// sequences and choices right associative.
fn finalfix(it: &mut Interp, postab: Option<Value>, g: Option<usize>, t: &mut [T], mut i: usize, kt: Value) {
    loop {
        match t[i].tag {
            TGRAMMAR => return,
            TOPENCALL => match (postab, g) {
                (Some(postab), Some(g)) => fixonecall(it, postab, g, t, i, kt),
                _ => { let name = rawgeti(it, kt, t[i].key as usize); let s = val2str(it, name); raise(it, &msg_with("rule '", &s, "' used outside a grammar")); }
            },
            TSEQ | TCHOICE => correctassociativity(t, i),
            _ => {}
        }
        match NUMSIBLINGS[t[i].tag as usize] {
            1 => i = sib1(i),
            2 => { finalfix(it, postab, g, t, sib1(i), kt); i = sib2(t, i); }
            _ => return,
        }
    }
}
fn checkloops(t: &mut [T], mut i: usize) -> bool {
    loop {
        if t[i].tag == TREP && nullable(t, sib1(i)) { return true; }
        if t[i].tag == TGRAMMAR { return false; }
        match NUMSIBLINGS[t[i].tag as usize] {
            1 => i = sib1(i),
            2 => { if checkloops(t, sib1(i)) { return true; } i = sib2(t, i); }
            _ => return false,
        }
    }
}
fn verifyerror(it: &mut Interp, passed: &[u16], kt: Value) -> ! {
    for i in (0..passed.len()).rev() {
        for j in (0..i).rev() {
            if passed[i] == passed[j] {
                let name = rawgeti(it, kt, passed[i] as usize);
                let s = val2str(it, name);
                raise(it, &msg_with("rule '", &s, "' may be left recursive"));
            }
        }
    }
    raise_str(it, "too many left calls in grammar")
}
fn verifyrule(it: &mut Interp, t: &mut [T], mut i: usize, passed: &mut Vec<u16>, npassed: usize, mut nb: bool, kt: Value) -> bool {
    let mut npassed = npassed;
    loop {
        match t[i].tag {
            TCHAR | TSET | TANY | TFALSE | TUTFR => return nb,
            TTRUE | TBEHIND => return true,
            TNOT | TAND | TREP => { i = sib1(i); nb = true; }
            TCAPTURE | TRUNTIME | TXINFO => i = sib1(i),
            TCALL => i = sib2(t, i),
            TSEQ => { if !verifyrule(it, t, sib1(i), passed, npassed, false, kt) { return nb; } i = sib2(t, i); }
            TCHOICE => { nb = verifyrule(it, t, sib1(i), passed, npassed, nb, kt); i = sib2(t, i); }
            TRULE => {
                if npassed >= MAXRULES { passed.truncate(npassed); verifyerror(it, passed, kt); }
                passed.truncate(npassed); passed.push(t[i].key); npassed += 1;
                i = sib1(i);
            }
            TGRAMMAR => return nullable(t, i),
            _ => return false,
        }
    }
}
fn verifygrammar(it: &mut Interp, t: &mut [T], kt: Value) {
    let mut passed = Vec::with_capacity(MAXRULES);
    let mut rule = sib1(0);
    while t[rule].tag == TRULE {
        if t[rule].key != 0 { verifyrule(it, t, sib1(rule), &mut passed, 0, false, kt); }
        rule = sib2(t, rule);
    }
    let mut rule = sib1(0);
    while t[rule].tag == TRULE {
        if t[rule].key != 0 && checkloops(t, sib1(rule)) {
            let name = rawgeti(it, kt, t[rule].key as usize);
            let s = val2str(it, name);
            raise(it, &msg_with("empty loop in rule '", &s, "'"));
        }
        rule = sib2(t, rule);
    }
}

// ---- analysis (lpcode.c) ---------------------------------------------------

fn callrecursive(t: &mut [T], i: usize, f: fn(&mut [T], usize) -> i32, def: i32) -> i32 {
    let key = t[i].key;
    if key == 0 { return def; }
    t[i].key = 0;
    let s2 = sib2(t, i);
    let r = f(t, s2);
    t[i].key = key;
    r
}
fn hascaptures(t: &mut [T], i: usize) -> bool { hascaptures_aux(t, i) != 0 }
fn hascaptures_aux(t: &mut [T], mut i: usize) -> i32 {
    loop {
        match t[i].tag {
            TCAPTURE | TRUNTIME => return 1,
            TCALL => return callrecursive(t, i, hascaptures_aux, 0),
            TRULE => i = sib1(i),
            _ => match NUMSIBLINGS[t[i].tag as usize] {
                1 => i = sib1(i),
                2 => { if hascaptures_aux(t, sib1(i)) != 0 { return 1; } i = sib2(t, i); }
                _ => return 0,
            },
        }
    }
}
const PE_NULLABLE: bool = false;
const PE_NOFAIL: bool = true;
fn nullable(t: &[T], i: usize) -> bool { checkaux(t, i, PE_NULLABLE) }
fn nofail(t: &[T], i: usize) -> bool { checkaux(t, i, PE_NOFAIL) }
fn checkaux(t: &[T], mut i: usize, nofail: bool) -> bool {
    loop {
        match t[i].tag {
            TCHAR | TSET | TANY | TUTFR | TFALSE | TOPENCALL => return false,
            TREP | TTRUE => return true,
            TNOT | TBEHIND => return !nofail,
            TAND => { if !nofail { return true; } i = sib1(i); }
            TRUNTIME => { if nofail { return false; } i = sib1(i); }
            TSEQ => { if !checkaux(t, sib1(i), nofail) { return false; } i = sib2(t, i); }
            TCHOICE => { if checkaux(t, sib2(t, i), nofail) { return true; } i = sib1(i); }
            TCAPTURE | TGRAMMAR | TRULE | TXINFO => i = sib1(i),
            TCALL => i = sib2(t, i),
            _ => return false,
        }
    }
}
fn fixedlen(t: &mut [T], mut i: usize) -> i32 {
    let mut len = 0;
    loop {
        match t[i].tag {
            TCHAR | TSET | TANY => return len + 1,
            TUTFR => return if t[i].cap == t[sib1(i)].cap { len + t[i].cap as i32 } else { -1 },
            TFALSE | TTRUE | TNOT | TAND | TBEHIND => return len,
            TREP | TRUNTIME | TOPENCALL => return -1,
            TCAPTURE | TRULE | TGRAMMAR | TXINFO => i = sib1(i),
            TCALL => { let n1 = callrecursive(t, i, fixedlen, -1); return if n1 < 0 { -1 } else { len + n1 }; }
            TSEQ => { let n1 = fixedlen(t, sib1(i)); if n1 < 0 { return -1; } len += n1; i = sib2(t, i); }
            TCHOICE => { let n1 = fixedlen(t, sib1(i)); let s2 = sib2(t, i); let n2 = fixedlen(t, s2); return if n1 != n2 || n1 < 0 { -1 } else { len + n1 }; }
            _ => return 0,
        }
    }
}
/// LPeg's `getfirst`: the first set of `t[i]` given the follow set; 0 when
/// the set may guard a test, bit 1 when it accepts the empty string, bit 2
/// for a match-time capture.
fn getfirst(t: &[T], mut i: usize, follow: &Cs, first: &mut Cs) -> i32 {
    let mut follow = *follow;
    loop {
        match t[i].tag {
            TCHAR | TSET | TANY | TFALSE => { *first = tocharset(t, i).unwrap(); return 0; }
            TUTFR => { *first = [0; 32]; for c in t[i].key as usize..=t[sib1(i)].key as usize { setchar(first, c); } return 0; }
            TTRUE => { *first = follow; return 1; }
            TCHOICE => {
                let mut aux = [0u8; 32];
                let e1 = getfirst(t, sib1(i), &follow, first);
                let e2 = getfirst(t, sib2(t, i), &follow, &mut aux);
                for k in 0..32 { first[k] |= aux[k]; }
                return e1 | e2;
            }
            TSEQ => {
                if !nullable(t, sib1(i)) { i = sib1(i); follow = FULLSET; continue; }
                let mut aux = [0u8; 32];
                let e2 = getfirst(t, sib2(t, i), &follow, &mut aux);
                let e1 = getfirst(t, sib1(i), &aux, first);
                if e1 == 0 { return 0; }
                if (e1 | e2) & 2 != 0 { return 2; }
                return e2;
            }
            TREP => { getfirst(t, sib1(i), &follow, first); for k in 0..32 { first[k] |= follow[k]; } return 1; }
            TCAPTURE | TGRAMMAR | TRULE | TXINFO => i = sib1(i),
            TRUNTIME => { let e = getfirst(t, sib1(i), &FULLSET, first); return if e != 0 { 2 } else { 0 }; }
            TCALL => i = sib2(t, i),
            TAND => { let e = getfirst(t, sib1(i), &follow, first); for k in 0..32 { first[k] &= follow[k]; } return e; }
            TNOT | TBEHIND => {
                if t[i].tag == TNOT { if let Some(cs) = tocharset(t, sib1(i)) { *first = cs; for b in first.iter_mut() { *b = !*b; } return 1; } }
                let e = getfirst(t, sib1(i), &follow, first);
                *first = follow;
                return e | 1;
            }
            _ => return 0,
        }
    }
}
fn headfail(t: &[T], mut i: usize) -> bool {
    loop {
        match t[i].tag {
            TCHAR | TSET | TANY | TFALSE => return true,
            TTRUE | TREP | TRUNTIME | TNOT | TBEHIND | TUTFR => return false,
            TCAPTURE | TGRAMMAR | TRULE | TXINFO | TAND => i = sib1(i),
            TCALL => i = sib2(t, i),
            TSEQ => { if !nofail(t, sib2(t, i)) { return false; } i = sib1(i); }
            TCHOICE => { if !headfail(t, sib1(i)) { return false; } i = sib2(t, i); }
            _ => return false,
        }
    }
}
fn needfollow(t: &[T], mut i: usize) -> bool {
    loop {
        match t[i].tag {
            TCHOICE | TREP => return true,
            TCAPTURE => i = sib1(i),
            TSEQ => i = sib2(t, i),
            _ => return false,
        }
    }
}

// ---- code generation (lpcode.c) --------------------------------------------

const IANY: u8 = 0;
const ICHAR: u8 = 1;
const ISET: u8 = 2;
const ITESTANY: u8 = 3;
const ITESTCHAR: u8 = 4;
const ITESTSET: u8 = 5;
const ISPAN: u8 = 6;
const IUTFR: u8 = 7;
const IBEHIND: u8 = 8;
const IRET: u8 = 9;
const IEND: u8 = 10;
const ICHOICE: u8 = 11;
const IJMP: u8 = 12;
const ICALL: u8 = 13;
const IOPENCALL: u8 = 14;
const ICOMMIT: u8 = 15;
const IPARTIALCOMMIT: u8 = 16;
const IBACKCOMMIT: u8 = 17;
const IFAILTWICE: u8 = 18;
const IFAIL: u8 = 19;
const IFULLCAPTURE: u8 = 21;
const IOPENCAPTURE: u8 = 22;
const ICLOSECAPTURE: u8 = 23;
const ICLOSERUNTIME: u8 = 24;

const OPNAMES: [&str; 25] = ["any", "char", "set", "testany", "testchar", "testset", "span", "utf-range", "behind", "ret", "end", "choice", "jmp", "call", "open_call", "commit", "partial_commit", "back_commit", "failtwice", "fail", "giveup", "fullcapture", "opencapture", "closecapture", "closeruntime"];

/// One instruction: `aux` is a character, a set default, a look-behind
/// count or a capture's kind and size; `key` a ktable index or rule number;
/// `off` a jump target or a UTF-8 range's start; `set` an index into the
/// code's sets or a UTF-8 range's end.
#[derive(Clone, Copy, Default, Debug)]
struct Inst { op: u8, aux: u8, key: u16, off: u32, set: u32 }

pub struct Code { insts: Vec<Inst>, sets: Vec<Cs> }

const NOINST: i64 = -1;

struct Comp<'a> { code: Vec<Inst>, sets: Vec<Cs>, t: &'a mut [T] }

impl Comp<'_> {
    fn here(&self) -> i64 { self.code.len() as i64 }
    fn add(&mut self, op: u8, aux: u8) -> i64 { self.code.push(Inst { op, aux, ..Inst::default() }); self.code.len() as i64 - 1 }
    fn add_offset(&mut self, op: u8) -> i64 { self.add(op, 0) }
    fn jumptothere(&mut self, inst: i64, target: i64) { if inst >= 0 { self.code[inst as usize].off = target as u32; } }
    fn jumptohere(&mut self, inst: i64) { let h = self.here(); self.jumptothere(inst, h); }
    fn add_set(&mut self, inst: i64, cs: &Cs) {
        let k = match self.sets.iter().position(|s| s == cs) { Some(k) => k, None => { self.sets.push(*cs); self.sets.len() - 1 } };
        self.code[inst as usize].set = k as u32;
    }
    fn addinstcap(&mut self, op: u8, cap: u8, key: u16, aux: i32) -> i64 { let i = self.add(op, cap | ((aux as u8) << 4)); self.code[i as usize].key = key; i }
    fn finaltarget(&self, mut i: usize) -> usize { while self.code[i].op == IJMP { i = self.code[i].off as usize; } i }
    fn finallabel(&self, i: usize) -> usize { self.finaltarget(self.code[i].off as usize) }

    fn codechar(&mut self, c: u8, tt: i64) {
        if tt >= 0 && self.code[tt as usize].op == ITESTCHAR && self.code[tt as usize].aux == c { self.add(IANY, 0); } else { self.add(ICHAR, c); }
    }
    fn codecharset(&mut self, i: usize, tt: i64) {
        let cs = set_read(self.t, i);
        if tt >= 0 && self.code[tt as usize].op == ITESTSET && self.sets[self.code[tt as usize].set as usize] == cs { self.add(IANY, 0); }
        else { let k = self.add(ISET, 0); self.add_set(k, &cs); }
    }
    fn codetestset(&mut self, cs: &Cs, e: bool) -> i64 {
        if e { return NOINST; }
        match charsettype(cs) {
            CsType::Fail => self.add_offset(IJMP),
            CsType::Any => self.add_offset(ITESTANY),
            CsType::Char(c) => { let i = self.add_offset(ITESTCHAR); self.code[i as usize].aux = c; i }
            CsType::Set => { let i = self.add_offset(ITESTSET); self.add_set(i, cs); i }
        }
    }
    fn codeutfr(&mut self, i: usize) {
        let k = self.add_offset(IUTFR) as usize;
        self.code[k].off = self.t[i].n as u32;
        self.code[k].set = self.t[sib1(i)].n as u32;
    }
    fn codebehind(&mut self, i: usize) {
        if self.t[i].n > 0 { self.add(IBEHIND, self.t[i].n as u8); }
        self.codegen(sib1(i), false, NOINST, &FULLSET);
    }
    fn codechoice(&mut self, p1: usize, p2: usize, opt: bool, fl: &Cs) {
        let emptyp2 = self.t[p2].tag == TTRUE;
        let mut cs1 = [0u8; 32];
        let e1 = getfirst(self.t, p1, &FULLSET, &mut cs1);
        let disjoint = || { let mut cs2 = [0u8; 32]; getfirst(self.t, p2, fl, &mut cs2); (0..32).all(|k| cs1[k] & cs2[k] == 0) };
        if headfail(self.t, p1) || (e1 == 0 && disjoint()) {
            let test = self.codetestset(&cs1, false);
            let mut jmp = NOINST;
            self.codegen(p1, false, test, fl);
            if !emptyp2 { jmp = self.add_offset(IJMP); }
            self.jumptohere(test);
            self.codegen(p2, opt, NOINST, fl);
            self.jumptohere(jmp);
        } else if opt && emptyp2 {
            let pc = self.add_offset(IPARTIALCOMMIT);
            self.jumptohere(pc);
            self.codegen(p1, true, NOINST, &FULLSET);
        } else {
            let test = self.codetestset(&cs1, e1 != 0);
            let pchoice = self.add_offset(ICHOICE);
            self.codegen(p1, emptyp2, test, &FULLSET);
            let pcommit = self.add_offset(ICOMMIT);
            self.jumptohere(pchoice);
            self.jumptohere(test);
            self.codegen(p2, opt, NOINST, fl);
            self.jumptohere(pcommit);
        }
    }
    fn codeand(&mut self, i: usize, tt: i64) {
        let n = fixedlen(self.t, i);
        if n >= 0 && n <= MAXBEHIND && !hascaptures(self.t, i) {
            self.codegen(i, false, tt, &FULLSET);
            if n > 0 { self.add(IBEHIND, n as u8); }
        } else {
            let pchoice = self.add_offset(ICHOICE);
            self.codegen(i, false, tt, &FULLSET);
            let pcommit = self.add_offset(IBACKCOMMIT);
            self.jumptohere(pchoice);
            self.add(IFAIL, 0);
            self.jumptohere(pcommit);
        }
    }
    fn codecapture(&mut self, i: usize, tt: i64, fl: &Cs) {
        let len = fixedlen(self.t, sib1(i));
        let (cap, key) = (self.t[i].cap, self.t[i].key);
        if len >= 0 && len <= MAXOFF && !hascaptures(self.t, sib1(i)) {
            self.codegen(sib1(i), false, tt, fl);
            self.addinstcap(IFULLCAPTURE, cap, key, len);
        } else {
            self.addinstcap(IOPENCAPTURE, cap, key, 0);
            self.codegen(sib1(i), false, tt, fl);
            self.addinstcap(ICLOSECAPTURE, CCLOSE, 0, 0);
        }
    }
    fn coderuntime(&mut self, i: usize, tt: i64) {
        let key = self.t[i].key;
        self.addinstcap(IOPENCAPTURE, CGROUP, key, 0);
        self.codegen(sib1(i), false, tt, &FULLSET);
        self.addinstcap(ICLOSERUNTIME, CCLOSE, 0, 0);
    }
    fn closeloop(&mut self, test: i64) {
        let jmp = self.add_offset(IJMP);
        self.jumptohere(test);
        self.jumptothere(jmp, test);
    }
    fn coderepcharset(&mut self, i: usize) -> bool {
        match self.t[i].tag {
            TFALSE => true,
            TANY => { let test = self.add_offset(ITESTANY); self.add(IANY, 0); self.closeloop(test); true }
            TCHAR => { let test = self.add_offset(ITESTCHAR); self.code[test as usize].aux = self.t[i].n as u8; self.add(IANY, 0); self.closeloop(test); true }
            TSET => { let k = self.add(ISPAN, 0); let cs = set_read(self.t, i); self.add_set(k, &cs); true }
            _ => false,
        }
    }
    fn coderep(&mut self, i: usize, opt: bool, fl: &Cs) {
        if self.coderepcharset(i) { return; }
        let mut st = [0u8; 32];
        let e1 = getfirst(self.t, i, &FULLSET, &mut st);
        if headfail(self.t, i) || (e1 == 0 && (0..32).all(|k| st[k] & fl[k] == 0)) {
            let test = self.codetestset(&st, false);
            self.codegen(i, false, test, &FULLSET);
            self.closeloop(test);
        } else {
            let test = self.codetestset(&st, e1 != 0);
            let mut pchoice = NOINST;
            if opt { let pc = self.add_offset(IPARTIALCOMMIT); self.jumptohere(pc); } else { pchoice = self.add_offset(ICHOICE); }
            let l2 = self.here();
            self.codegen(i, false, NOINST, &FULLSET);
            let commit = self.add_offset(IPARTIALCOMMIT);
            self.jumptothere(commit, l2);
            self.jumptohere(pchoice);
            self.jumptohere(test);
        }
    }
    fn codenot(&mut self, i: usize) {
        let mut st = [0u8; 32];
        let e = getfirst(self.t, i, &FULLSET, &mut st);
        let test = self.codetestset(&st, e != 0);
        if headfail(self.t, i) { self.add(IFAIL, 0); }
        else {
            let pchoice = self.add_offset(ICHOICE);
            self.codegen(i, false, NOINST, &FULLSET);
            self.add(IFAILTWICE, 0);
            self.jumptohere(pchoice);
        }
        self.jumptohere(test);
    }
    fn correctcalls(&mut self, positions: &[i64], from: usize, to: usize) {
        for i in from..to {
            if self.code[i].op == IOPENCALL {
                let rule = positions[self.code[i].key as usize];
                let ft = self.finaltarget(i + 1);
                self.code[i].op = if self.code[ft].op == IRET { IJMP } else { ICALL };
                self.jumptothere(i as i64, rule);
            }
        }
    }
    fn codegrammar(&mut self, g: usize) {
        let mut positions = Vec::new();
        let firstcall = self.add_offset(ICALL);
        let jumptoend = self.add_offset(IJMP);
        let start = self.here();
        self.jumptohere(firstcall);
        let mut rule = sib1(g);
        while self.t[rule].tag == TRULE {
            let r = sib1(rule);
            positions.push(self.here());
            self.codegen(sib1(r), false, NOINST, &FULLSET);
            self.add(IRET, 0);
            rule = sib2(self.t, rule);
        }
        self.jumptohere(jumptoend);
        let end = self.here();
        self.correctcalls(&positions, start as usize, end as usize);
    }
    fn codecall(&mut self, i: usize) {
        let c = self.add_offset(IOPENCALL);
        let rule = sib2(self.t, i);
        self.code[c as usize].key = self.t[sib1(rule)].n as u16;
    }
    fn codeseq1(&mut self, p1: usize, p2: usize, tt: i64, fl: &Cs) -> i64 {
        if needfollow(self.t, p1) {
            let mut fl1 = [0u8; 32];
            getfirst(self.t, p2, fl, &mut fl1);
            self.codegen(p1, false, tt, &fl1);
        } else {
            self.codegen(p1, false, tt, &FULLSET);
        }
        if fixedlen(self.t, p1) != 0 { NOINST } else { tt }
    }
    fn codegen(&mut self, mut i: usize, opt: bool, mut tt: i64, fl: &Cs) {
        loop {
            match self.t[i].tag {
                TCHAR => self.codechar(self.t[i].n as u8, tt),
                TANY => { self.add(IANY, 0); }
                TSET => self.codecharset(i, tt),
                TTRUE => {}
                TFALSE => { self.add(IFAIL, 0); }
                TUTFR => self.codeutfr(i),
                TCHOICE => { let s2 = sib2(self.t, i); self.codechoice(sib1(i), s2, opt, fl) }
                TREP => self.coderep(sib1(i), opt, fl),
                TBEHIND => self.codebehind(i),
                TNOT => self.codenot(sib1(i)),
                TAND => self.codeand(sib1(i), tt),
                TCAPTURE => self.codecapture(i, tt, fl),
                TRUNTIME => self.coderuntime(i, tt),
                TGRAMMAR => self.codegrammar(i),
                TCALL => self.codecall(i),
                TSEQ => {
                    let s2 = sib2(self.t, i);
                    tt = self.codeseq1(sib1(i), s2, tt, fl);
                    i = s2;
                    continue;
                }
                _ => {}
            }
            return;
        }
    }
    fn peephole(&mut self) {
        let mut i = 0;
        while i < self.code.len() {
            loop {
                match self.code[i].op {
                    ICHOICE | ICALL | ICOMMIT | IPARTIALCOMMIT | IBACKCOMMIT | ITESTCHAR | ITESTSET | ITESTANY => {
                        let fl = self.finallabel(i); self.code[i].off = fl as u32;
                    }
                    IJMP => {
                        let ft = self.finaltarget(i);
                        match self.code[ft].op {
                            IRET | IFAIL | IFAILTWICE | IEND => self.code[i] = self.code[ft],
                            ICOMMIT | IPARTIALCOMMIT | IBACKCOMMIT => {
                                let fft = self.finallabel(ft);
                                self.code[i] = self.code[ft];
                                self.code[i].off = fft as u32;
                                continue;
                            }
                            _ => self.code[i].off = ft as u32,
                        }
                    }
                    _ => {}
                }
                break;
            }
            i += 1;
        }
    }
}

fn compile_tree(t: &mut [T]) -> Code {
    let mut c = Comp { code: Vec::with_capacity(t.len() / 2 + 2), sets: Vec::new(), t };
    c.codegen(0, false, NOINST, &FULLSET);
    c.add(IEND, 0);
    c.peephole();
    Code { insts: c.code, sets: c.sets }
}
/// The pattern's code, compiled on first use.
fn code_of(it: &mut Interp, p: Value) -> Arc<Code> {
    if let Some(c) = &pat(p).code { return c.clone(); }
    let kt = ktable_of(p);
    let tree = &mut pat_mut(p).tree;
    finalfix(it, None, None, tree, 0, kt);
    let code = Arc::new(compile_tree(tree));
    pat_mut(p).code = Some(code.clone());
    code
}

// ---- the machine (lpvm.c) --------------------------------------------------

#[derive(Clone, Copy, Default, Debug)]
struct Capture { index: usize, idx: u16, kind: u8, siz: u8 }
const MAXINDT: usize = usize::MAX;

#[inline] fn isopencap(c: &Capture) -> bool { c.siz == 0 }
#[inline] fn isclosecap(c: &Capture) -> bool { c.kind == CCLOSE }
#[inline] fn capinside(c1: &Capture, c2: &Capture) -> bool {
    if isopencap(c1) { !isclosecap(c2) } else { c2.index < c1.index.wrapping_add(c1.siz as usize - 1) }
}

#[derive(Clone, Copy)]
struct Frame { s: usize, p: usize, caplevel: usize }
const CALLFRAME: usize = usize::MAX;
const GIVEUP: usize = usize::MAX;

fn utf8_decode(s: &[u8], at: usize) -> Option<(usize, u32)> {
    const LIMITS: [u32; 4] = [0xFF, 0x7F, 0x7FF, 0xFFFF];
    let mut c = s[at] as u32;
    if c < 0x80 { return Some((at + 1, c)); }
    let mut res = 0u32;
    let mut count = 0usize;
    while c & 0x40 != 0 {
        count += 1;
        let cc = *s.get(at + count).unwrap_or(&0) as u32;
        if cc & 0xC0 != 0x80 { return None; }
        res = (res << 6) | (cc & 0x3F);
        c <<= 1;
    }
    res |= (c & 0x7F) << (count * 5);
    if count > 3 || res > 0x10FFFF || res <= LIMITS[count] { return None; }
    Some((at + count + 1, res))
}

/// Everything a match keeps: the capture list, and where on the handle
/// stack its match-time capture values start.
struct Match<'a> {
    s: &'a [u8],
    subject: Value,
    kt: Value,
    args: &'a [Value],
    caps: Vec<Capture>,
    dyn_base: usize,
}

/// The open capture before `cap` that a close at `currindex` can turn into
/// a full capture, if any.
fn vm_findopen(caps: &[Capture], cap: usize, currindex: usize) -> Option<usize> {
    let mut c = cap - 1;
    if !isopencap(&caps[c]) && caps[c].index == currindex { return None; }
    for _ in 0..MAXLOP {
        if currindex.wrapping_sub(caps[c].index) >= 255 { return None; }
        if isopencap(&caps[c]) { return Some(c); }
        if caps[c].kind == CCLOSE { return None; }
        if c == 0 { return None; }
        c -= 1;
    }
    None
}
fn finddyncap(caps: &[Capture], from: usize, to: usize) -> usize {
    caps[from..to].iter().find(|c| c.kind == CRUNTIME).map(|c| c.idx as usize).unwrap_or(0)
}

fn vm_match(it: &mut Interp, m: &mut Match, code: &Code, init: usize) -> Option<usize> {
    let insts = &code.insts[..];
    let sets = &code.sets[..];
    let s_all = m.s;
    let e = s_all.len();
    let mut s = init;
    let mut stack: Vec<Frame> = Vec::with_capacity(32);
    let mut limit = MAXBACK;
    let mut captop = 0usize;
    let mut ndyncap = 0usize;
    let mut p = 0usize;
    stack.push(Frame { s, p: GIVEUP, caplevel: 0 });
    m.caps.clear();
    m.caps.resize(32, Capture::default());
    macro_rules! grow { ($n:expr) => { if m.caps.len() <= captop + $n { let n = (captop + $n + 1) * 3 / 2; m.caps.resize(n, Capture::default()); } } }
    macro_rules! pushframe { ($f:expr) => {{
        if stack.len() == limit {
            let max = it.lpeg_maxstack;
            if limit >= max { raise_str(it, &format!("backtrack stack overflow (current limit is {max})")); }
            limit = (2 * limit).min(max);
        }
        stack.push($f);
    }} }
    loop {
        let inst = insts[p];
        match inst.op {
            IEND => {
                grow!(1);
                m.caps[captop] = Capture { kind: CCLOSE, index: MAXINDT, idx: 0, siz: 0 };
                return Some(s);
            }
            IRET => { p = stack.pop().unwrap().p; continue; }
            IANY => { if s < e { p += 1; s += 1; continue; } }
            IUTFR => {
                if s < e { if let Some((ns, cp)) = utf8_decode(s_all, s) { if inst.off <= cp && cp <= inst.set { s = ns; p += 1; continue; } } }
            }
            ITESTANY => { p = if s < e { p + 1 } else { inst.off as usize }; continue; }
            ICHAR => { if s < e && s_all[s] == inst.aux { p += 1; s += 1; continue; } }
            ITESTCHAR => { p = if s < e && s_all[s] == inst.aux { p + 1 } else { inst.off as usize }; continue; }
            ISET => { if s < e && testchar(&sets[inst.set as usize], s_all[s]) { p += 1; s += 1; continue; } }
            ITESTSET => { p = if s < e && testchar(&sets[inst.set as usize], s_all[s]) { p + 1 } else { inst.off as usize }; continue; }
            IBEHIND => { let n = inst.aux as usize; if n <= s { s -= n; p += 1; continue; } }
            ISPAN => { let cs = &sets[inst.set as usize]; while s < e && testchar(cs, s_all[s]) { s += 1; } p += 1; continue; }
            IJMP => { p = inst.off as usize; continue; }
            ICHOICE => { pushframe!(Frame { s, p: inst.off as usize, caplevel: captop }); p += 1; continue; }
            ICALL => { pushframe!(Frame { s: CALLFRAME, p: p + 1, caplevel: 0 }); p = inst.off as usize; continue; }
            ICOMMIT => { stack.pop(); p = inst.off as usize; continue; }
            IPARTIALCOMMIT => { let top = stack.last_mut().unwrap(); top.s = s; top.caplevel = captop; p = inst.off as usize; continue; }
            IBACKCOMMIT => {
                let f = stack.pop().unwrap();
                s = f.s;
                if ndyncap > 0 { ndyncap -= removedyncap(it, m, f.caplevel, captop); }
                captop = f.caplevel;
                p = inst.off as usize;
                continue;
            }
            IFAILTWICE => { stack.pop(); }
            IFAIL => {}
            ICLOSERUNTIME => {
                grow!(1);
                let otop = it.handles.len() - m.dyn_base;
                let close = captop;
                let open = cap_findopen(&m.caps, close);
                let id = finddyncap(&m.caps, open, close);
                m.caps[close].kind = CCLOSE;
                m.caps[close].index = s;
                // runtimecap: call the function with the subject, the
                // position and the group's values.
                let fpos = it.handles.len();
                let f = rawgeti(it, m.kt, m.caps[open].idx as usize);
                push(it, f);
                push(it, m.subject);
                push(it, Value::num((s + 1) as f64));
                {
                    let mut cs = CapState { m, cap: open, reclevel: 0, firstcap: fpos + 3 };
                    cs.pushnestedvalues(it, false);
                }
                let callargs = it.handles[fpos + 1..].to_vec();
                let results = it.call_value(f, &callargs);
                it.handles.truncate(fpos);
                it.handles.extend_from_slice(&results);
                let rem = if id > 0 { it.handles.drain(m.dyn_base + id - 1..m.dyn_base + otop); otop - id + 1 } else { 0 };
                captop -= close - open - 1;
                ndyncap -= rem;
                let fr = fpos - rem;
                let first = it.handles.get(fr).copied().unwrap_or(Value::NIL);
                let res = if !first.truthy() { None } else if first == Value::TRUE { Some(s) } else {
                    let r = tointeger(it, first).unwrap_or(0) - 1;
                    if r < s as i64 || r > e as i64 { raise_str(it, "invalid position returned by match-time capture"); }
                    Some(r as usize)
                };
                match res {
                    None => { it.handles.truncate(fr); }
                    Some(r) => {
                        if fr < it.handles.len() { it.handles.remove(fr); }
                        s = r;
                        let n = it.handles.len() - fr;
                        ndyncap += n;
                        if n == 0 { captop -= 1; } else {
                            let fd = fr - m.dyn_base + 1;
                            if (fd + n) as i64 >= SHRT_MAX { raise_str(it, "too many results in match-time capture"); }
                            grow!(n + 1);
                            m.caps[captop - 1].idx = 0;
                            for k in 0..n { m.caps[captop + k] = Capture { kind: CRUNTIME, siz: 1, idx: (fd + k) as u16, index: s }; }
                            m.caps[captop + n] = Capture { kind: CCLOSE, siz: 1, idx: 0, index: s };
                            captop += n + 1;
                        }
                        p += 1;
                        continue;
                    }
                }
            }
            ICLOSECAPTURE => {
                if let Some(open) = vm_findopen(&m.caps, captop, s) {
                    m.caps[open].siz = (s - m.caps[open].index + 1) as u8;
                } else {
                    m.caps[captop] = Capture { siz: 1, index: s, idx: inst.key, kind: inst.aux & 0xF };
                    captop += 1;
                    grow!(0);
                }
                p += 1;
                continue;
            }
            IOPENCAPTURE => {
                m.caps[captop] = Capture { siz: 0, index: s, idx: inst.key, kind: inst.aux & 0xF };
                captop += 1;
                grow!(0);
                p += 1;
                continue;
            }
            IFULLCAPTURE => {
                let off = (inst.aux >> 4) as usize;
                m.caps[captop] = Capture { siz: off as u8 + 1, index: s - off, idx: inst.key, kind: inst.aux & 0xF };
                captop += 1;
                grow!(0);
                p += 1;
                continue;
            }
            op => unreachable!("lpeg: bad opcode {op}"),
        }
        // fail: pop pending calls and resume at the last choice.
        let f = loop { let f = stack.pop().unwrap(); if f.s != CALLFRAME { break f; } };
        if f.p == GIVEUP { return None; }
        s = f.s;
        if ndyncap > 0 { ndyncap -= removedyncap(it, m, f.caplevel, captop); }
        captop = f.caplevel;
        p = f.p;
    }
}
/// Drops the match-time capture values of the captures in `level..last`.
fn removedyncap(it: &mut Interp, m: &Match, level: usize, last: usize) -> usize {
    let id = finddyncap(&m.caps, level, last);
    if id == 0 { return 0; }
    let top = it.handles.len();
    let keep = m.dyn_base + id - 1;
    it.handles.truncate(keep);
    top - keep
}

// ---- captures (lpcap.c) ----------------------------------------------------

/// The open capture that the close at `cap` closes.
fn cap_findopen(caps: &[Capture], mut cap: usize) -> usize {
    let mut n = 0;
    loop {
        cap -= 1;
        if isclosecap(&caps[cap]) { n += 1; }
        else if isopencap(&caps[cap]) { if n == 0 { return cap; } n -= 1; }
    }
}

struct CapState<'m, 'a> { m: &'m Match<'a>, cap: usize, reclevel: usize, firstcap: usize }

#[derive(Clone, Copy, Default)]
struct StrAux { isstring: bool, idx: usize, siz: usize, cp: usize }

impl CapState<'_, '_> {
    fn c(&self, i: usize) -> &Capture { &self.m.caps[i] }
    fn ktval(&self, it: &Interp, idx: u16) -> Value { rawgeti(it, self.m.kt, idx as usize) }
    fn capsize(&self, cap: usize, close: usize) -> usize {
        let c = self.c(cap);
        if isopencap(c) { self.c(close).index - c.index } else { c.siz as usize - 1 }
    }
    fn closesize(&self, head: usize) -> usize { self.capsize(head, self.cap) }
    fn skipclose(&mut self, head: usize) { if isopencap(self.c(head)) { self.cap += 1; } }
    fn nextcap(&mut self) {
        let cap = self.cap;
        if isopencap(self.c(cap)) {
            let mut n = 0;
            let mut c = cap;
            loop {
                c += 1;
                if isopencap(self.c(c)) { n += 1; }
                else if isclosecap(self.c(c)) { if n == 0 { break; } n -= 1; }
            }
            self.cap = c + 1;
        } else {
            let mut next = cap + 1;
            while capinside(self.c(cap), self.c(next)) { next += 1; }
            self.cap = next;
        }
    }
    fn substring(&self, it: &mut Interp, from: usize, len: usize) -> Value {
        let s = &self.m.s[from..from + len];
        it.string_of(s)
    }
    fn pushnestedvalues(&mut self, it: &mut Interp, addextra: bool) -> usize {
        let head = self.cap;
        self.cap += 1;
        let mut n = 0;
        while capinside(self.c(head), self.c(self.cap)) { n += self.pushcapture(it); }
        if addextra || n == 0 {
            let (from, len) = (self.c(head).index, self.closesize(head));
            let v = self.substring(it, from, len);
            push(it, v);
            n += 1;
        }
        self.skipclose(head);
        n
    }
    fn pushonenestedvalue(&mut self, it: &mut Interp) {
        let n = self.pushnestedvalues(it, false);
        let len = it.handles.len();
        if n > 1 { it.handles.truncate(len - (n - 1)); }
    }
    fn capvisible(&self, grp: usize, refc: usize) -> bool {
        let mut cap = grp;
        let mut i = MAXLOP;
        while i > 0 && cap > 0 {
            i -= 1;
            cap -= 1;
            if isclosecap(self.c(cap)) { return true; }
            if self.c(grp).index.wrapping_sub(self.c(cap).index) >= 255 { return true; }
            if capinside(self.c(cap), self.c(grp)) { return capinside(self.c(cap), self.c(refc)); }
        }
        true
    }
    fn findback(&self, it: &mut Interp, name: Value, refc: usize) -> usize {
        let mut cap = refc;
        while cap > 0 {
            cap -= 1;
            if isclosecap(self.c(cap)) { cap = cap_findopen(&self.m.caps, cap); }
            else if capinside(self.c(cap), self.c(refc)) { continue; }
            if self.c(cap).kind == CGROUP && self.capvisible(cap, refc) {
                let gname = self.ktval(it, self.c(cap).idx);
                if it.values_equal(name, gname) { return cap; }
            }
        }
        let s = tostring_opt(it, name).unwrap_or_else(|| b"(null)".to_vec());
        raise(it, &msg_with("back reference '", &s, "' not found"))
    }
    fn backrefcap(&mut self, it: &mut Interp) -> usize {
        let curr = self.cap;
        let name = self.ktval(it, self.c(curr).idx);
        self.cap = self.findback(it, name, curr);
        let n = self.pushnestedvalues(it, false);
        self.cap = curr + 1;
        n
    }
    fn tablecap(&mut self, it: &mut Interp) -> usize {
        let head = self.cap;
        self.cap += 1;
        let t = new_table(it);
        let mut n = 0;
        while capinside(self.c(head), self.c(self.cap)) {
            let c = *self.c(self.cap);
            if c.kind == CGROUP && c.idx != 0 {
                let name = self.ktval(it, c.idx);
                let at = it.handles.len();
                push(it, name);
                self.pushonenestedvalue(it);
                let v = it.handles[at + 1];
                if name == Value::NIL { raise_str(it, "table index is nil"); }
                it.set_index(t, name, v);
                it.handles.truncate(at);
            } else {
                let at = it.handles.len();
                let k = self.pushcapture(it);
                for i in 0..k { let v = it.handles[at + i]; it.set_index(t, Value::num((n + i + 1) as f64), v); }
                it.handles.truncate(at);
                n += k;
            }
        }
        self.skipclose(head);
        1
    }
    fn querycap(&mut self, it: &mut Interp) -> usize {
        let idx = self.c(self.cap).idx;
        let at = it.handles.len();
        self.pushonenestedvalue(it);
        let table = self.ktval(it, idx);
        let key = it.handles[at];
        let v = it.index_any(table, key);
        it.handles.truncate(at);
        if v == Value::NIL { 0 } else { push(it, v); 1 }
    }
    fn foldcap(&mut self, it: &mut Interp) -> usize {
        let head = self.cap;
        self.cap += 1;
        let idx = self.c(head).idx;
        let at = it.handles.len();
        let n = if isclosecap(self.c(self.cap)) { 0 } else { self.pushcapture(it) };
        if n == 0 { raise_str(it, "no initial value for fold capture"); }
        it.handles.truncate(at + 1);
        while capinside(self.c(head), self.c(self.cap)) {
            let f = self.ktval(it, idx);
            self.pushcapture(it);
            let callargs = it.handles[at..].to_vec();
            let r = it.call_value(f, &callargs);
            it.handles.truncate(at);
            push(it, r.first().copied().unwrap_or(Value::NIL));
        }
        self.skipclose(head);
        1
    }
    fn functioncap(&mut self, it: &mut Interp) -> usize {
        let top = it.handles.len();
        let f = self.ktval(it, self.c(self.cap).idx);
        push(it, f);
        self.pushnestedvalues(it, false);
        let callargs = it.handles[top + 1..].to_vec();
        let r = it.call_value(f, &callargs);
        it.handles.truncate(top);
        it.handles.extend_from_slice(&r);
        r.len()
    }
    fn accumulatorcap(&mut self, it: &mut Interp) -> usize {
        if it.handles.len() <= self.firstcap { raise_str(it, "no previous value for accumulator capture"); }
        let prev = it.handles.len() - 1;
        let f = self.ktval(it, self.c(self.cap).idx);
        push(it, f);
        self.pushnestedvalues(it, false);
        let mut callargs = vec![it.handles[prev]];
        callargs.extend_from_slice(&it.handles[prev + 2..]);
        let r = it.call_value(f, &callargs);
        it.handles.truncate(prev);
        push(it, r.first().copied().unwrap_or(Value::NIL));
        0
    }
    fn numcap(&mut self, it: &mut Interp) -> usize {
        let idx = self.c(self.cap).idx as usize;
        if idx == 0 { self.nextcap(); return 0; }
        let at = it.handles.len();
        let n = self.pushnestedvalues(it, false);
        if n < idx { raise_str(it, &format!("no capture '{idx}'")); }
        let v = it.handles[at + idx - 1];
        it.handles.truncate(at);
        push(it, v);
        1
    }
    fn getstrcaps(&mut self, cps: &mut [StrAux; MAXSTRCAPS], n: usize) -> usize {
        let k = n;
        let mut n = n + 1;
        let head = self.cap;
        self.cap += 1;
        cps[k].isstring = true;
        cps[k].idx = self.c(head).index;
        while capinside(self.c(head), self.c(self.cap)) {
            if n >= MAXSTRCAPS { self.nextcap(); }
            else if self.c(self.cap).kind == CSIMPLE { n = self.getstrcaps(cps, n); }
            else { cps[n].isstring = false; cps[n].cp = self.cap; self.nextcap(); n += 1; }
        }
        cps[k].siz = self.closesize(head);
        self.skipclose(head);
        n
    }
    fn stringcap(&mut self, it: &mut Interp, b: &mut Vec<u8>) {
        let fmtv = self.ktval(it, self.c(self.cap).idx);
        let fmt = crate::builtins::tostring(it, fmtv);
        let mut cps = [StrAux::default(); MAXSTRCAPS];
        let n = self.getstrcaps(&mut cps, 0) - 1;
        let mut i = 0;
        while i < fmt.len() {
            if fmt[i] != b'%' { b.push(fmt[i]); }
            else {
                i += 1;
                let c = fmt.get(i).copied().unwrap_or(0);
                if !c.is_ascii_digit() { b.push(c); }
                else {
                    let l = (c - b'0') as usize;
                    if l > n { raise_str(it, &format!("invalid capture index ({l})")); }
                    else if cps[l].isstring { b.extend_from_slice(&self.m.s[cps[l].idx..cps[l].idx + cps[l].siz]); }
                    else {
                        let curr = self.cap;
                        self.cap = cps[l].cp;
                        if self.addonestring(it, b, "capture") == 0 { raise_str(it, &format!("no values in capture index {l}")); }
                        self.cap = curr;
                    }
                }
            }
            i += 1;
        }
    }
    fn substcap(&mut self, it: &mut Interp, b: &mut Vec<u8>) {
        let mut curr = self.c(self.cap).index;
        let head = self.cap;
        self.cap += 1;
        while capinside(self.c(head), self.c(self.cap)) {
            let cap = self.cap;
            let caps = self.c(cap).index;
            if caps > curr { b.extend_from_slice(&self.m.s[curr..caps]); }
            if self.addonestring(it, b, "replacement") != 0 { curr = caps + self.capsize(cap, self.cap - 1); } else { curr = caps; }
        }
        let end = self.c(head).index + self.closesize(head);
        if end > curr { b.extend_from_slice(&self.m.s[curr..end]); }
        self.skipclose(head);
    }
    fn addonestring(&mut self, it: &mut Interp, b: &mut Vec<u8>, what: &str) -> usize {
        match self.c(self.cap).kind {
            CSTRING => { self.stringcap(it, b); 1 }
            CSUBST => { self.substcap(it, b); 1 }
            CACC => raise_str(it, "invalid context for an accumulator capture"),
            _ => {
                let at = it.handles.len();
                let n = self.pushcapture(it);
                if n > 0 {
                    let v = it.handles[at];
                    if !(it.is_stringish(v) || is_number(v)) { let tn = typename(it, v); raise_str(it, &format!("invalid {what} value (a {tn})")); }
                    let text = crate::builtins::tostring(it, v);
                    b.extend_from_slice(&text);
                }
                it.handles.truncate(at);
                n
            }
        }
    }
    fn pushcapture(&mut self, it: &mut Interp) -> usize {
        if self.reclevel > MAXRECLEVEL { raise_str(it, "subcapture nesting too deep"); }
        self.reclevel += 1;
        let c = *self.c(self.cap);
        let res = match c.kind {
            CPOSITION => { push(it, Value::num((c.index + 1) as f64)); self.cap += 1; 1 }
            CCONST => { let v = self.ktval(it, c.idx); push(it, v); self.cap += 1; 1 }
            CARG => {
                self.cap += 1;
                let a = c.idx as usize;
                if a + FIXEDARGS > self.m.args.len() { raise_str(it, &format!("reference to absent extra argument #{a}")); }
                push(it, self.m.args[a + FIXEDARGS - 1]);
                1
            }
            CSIMPLE => {
                let at = it.handles.len();
                let k = self.pushnestedvalues(it, true);
                // The whole match goes first.
                it.handles[at..at + k].rotate_right(1);
                k
            }
            CRUNTIME => { let v = it.handles[self.m.dyn_base + c.idx as usize - 1]; push(it, v); self.cap += 1; 1 }
            CSTRING => { let mut b = Vec::new(); self.stringcap(it, &mut b); let v = it.string_of(&b); push(it, v); 1 }
            CSUBST => { let mut b = Vec::new(); self.substcap(it, &mut b); let v = it.string_of(&b); push(it, v); 1 }
            CGROUP => { if c.idx == 0 { self.pushnestedvalues(it, false) } else { self.nextcap(); 0 } }
            CBACKREF => self.backrefcap(it),
            CTABLE => self.tablecap(it),
            CFUNCTION => self.functioncap(it),
            CACC => self.accumulatorcap(it),
            CNUM => self.numcap(it),
            CQUERY => self.querycap(it),
            CFOLD => self.foldcap(it),
            _ => 0,
        };
        self.reclevel -= 1;
        res
    }
}

// ---- entry points ----------------------------------------------------------

fn initposition(it: &mut Interp, args: &[Value], len: usize) -> usize {
    let v = arg(args, 2);
    let ii = if v == Value::NIL { 1 } else { match tointeger(it, v) { Some(n) => n, None => typeerror(it, args, 3, "match", "number") } };
    if ii > 0 { if (ii as u64) <= len as u64 { ii as usize - 1 } else { len } }
    else if ii.unsigned_abs() <= len as u64 { len - ii.unsigned_abs() as usize } else { 0 }
}

fn lp_match(it: &mut Interp, args: &[Value]) -> Outs {
    let p = getpatt(it, arg(args, 0), 1, "match");
    let code = code_of(it, p);
    let sv = arg(args, 1);
    let subject = if it.is_stringish(sv) { sv } else if is_number(sv) {
        let b = crate::builtins::tostring(it, sv); let v = it.string_of(&b); push(it, v)
    } else { typeerror(it, args, 2, "match", "string") };
    let bytes = it.bytes_of(subject);
    // The subject is rooted (an argument or pushed) and the heap does not
    // move objects, so its bytes stay put while callbacks run.
    let s: &[u8] = unsafe { std::slice::from_raw_parts(bytes.as_ptr(), bytes.len()) };
    let init = initposition(it, args, s.len());
    let kt = ktable_of(p);
    let dyn_base = it.handles.len();
    let mut m = Match { s, subject, kt, args, caps: Vec::new(), dyn_base };
    let r = vm_match(it, &mut m, &code, init);
    let mut out = Outs::new();
    let Some(r) = r else { out.push(Value::NIL); return out; };
    // getcaptures
    let firstcap = it.handles.len();
    let mut n = 0;
    if !isclosecap(&m.caps[0]) {
        let mut cs = CapState { m: &m, cap: 0, reclevel: 0, firstcap };
        loop { n += cs.pushcapture(it); if isclosecap(cs.c(cs.cap)) { break; } }
    }
    if n == 0 { out.push(Value::num((r + 1) as f64)); return out; }
    for &v in &it.handles[firstcap..] { out.push(v); }
    out
}

fn lp_setmax(it: &mut Interp, args: &[Value]) -> Outs {
    let lim = checkinteger(it, args, 1, "setmaxstack");
    if !(0 < lim && lim <= MAXLIM) { argerror(it, 1, "setmaxstack", "out of range"); }
    it.lpeg_maxstack = lim as usize;
    Outs::new()
}

fn lp_locale(it: &mut Interp, args: &[Value]) -> Value {
    let t = match arg(args, 0) {
        v if v == Value::NIL => new_table(it),
        v if is_table(it, v) => v,
        _ => typeerror(it, args, 1, "locale", "table"),
    };
    let cats: [(&str, fn(u8) -> bool); 11] = [
        ("alnum", |c| c.is_ascii_alphanumeric()), ("alpha", |c| c.is_ascii_alphabetic()), ("cntrl", |c| c.is_ascii_control()),
        ("digit", |c| c.is_ascii_digit()), ("graph", |c| c.is_ascii_graphic()), ("lower", |c| c.is_ascii_lowercase()),
        ("print", |c| c.is_ascii_graphic() || c == b' '), ("punct", |c| c.is_ascii_punctuation()),
        ("space", |c| matches!(c, b' ' | b'\t' | b'\n' | 0x0b | 0x0c | b'\r')), ("upper", |c| c.is_ascii_uppercase()), ("xdigit", |c| c.is_ascii_hexdigit()),
    ];
    for (name, f) in cats {
        let mut cs = [0u8; 32];
        for c in 0..=255u8 { if f(c) { setchar(&mut cs, c as usize); } }
        let p = new_pattern(it, newcharset(&cs), Value::NIL);
        let k = it.intern(name);
        it.set_index(t, k, p);
    }
    t
}

fn print_code(code: &Code) -> String {
    let mut out = String::new();
    for (i, inst) in code.insts.iter().enumerate() {
        let name = OPNAMES.get(inst.op as usize).copied().unwrap_or("?");
        let detail = match inst.op {
            ICHAR | ITESTCHAR => format!(" '{}'", inst.aux as char),
            IFULLCAPTURE | IOPENCAPTURE | ICLOSECAPTURE | ICLOSERUNTIME => format!(" kind {} n {} key {}", inst.aux & 0xF, inst.aux >> 4, inst.key),
            IBEHIND => format!(" {}", inst.aux),
            IUTFR => format!(" {}-{}", inst.off, inst.set),
            _ => String::new(),
        };
        let target = match inst.op { ITESTANY | ITESTCHAR | ITESTSET | IJMP | ICHOICE | ICALL | ICOMMIT | IPARTIALCOMMIT | IBACKCOMMIT => format!(" -> {}", inst.off), _ => String::new() };
        out.push_str(&format!("{i:4}: {name}{detail}{target}\n"));
    }
    out
}

fn dispatch(it: &mut Interp, name: &str, args: &[Value]) -> Outs {
    let one = |v: Value| { let mut o = Outs::new(); o.push(v); o };
    match name {
        "P" => { if args.is_empty() { argerror(it, 1, "P", "value expected"); } one(getpatt(it, args[0], 1, "P")) }
        "match" => lp_match(it, args),
        "S" => one(lp_set(it, args)),
        "R" => one(lp_range(it, args)),
        "utfR" => one(lp_utfr(it, args)),
        "B" => one(lp_behind(it, args)),
        "V" => one(lp_v(it, args)),
        "C" => one(capture_aux(it, args, CSIMPLE, None, "C")),
        "Cs" => one(capture_aux(it, args, CSUBST, None, "Cs")),
        "Ct" => one(capture_aux(it, args, CTABLE, None, "Ct")),
        "Cg" => { let label = arg(args, 1); one(capture_aux(it, args, CGROUP, (label != Value::NIL).then_some(label), "Cg")) }
        "Cf" => { if !is_function(it, arg(args, 1)) { typeerror(it, args, 2, "Cf", "function"); } one(capture_aux(it, args, CFOLD, Some(arg(args, 1)), "Cf")) }
        "Cc" => one(lp_constcapture(it, args)),
        "Cmt" => one(lp_matchtime(it, args)),
        "Cb" => { if args.is_empty() { argerror(it, 1, "Cb", "value expected"); } one(newemptycapkey(it, CBACKREF, args[0])) }
        "Cp" => one(new_pattern(it, emptycap(CPOSITION, 0), Value::NIL)),
        "Carg" => {
            let n = checkinteger(it, args, 1, "Carg");
            if !(0 < n && n <= SHRT_MAX) { argerror(it, 1, "Carg", "invalid argument index"); }
            one(new_pattern(it, emptycap(CARG, n as u16), Value::NIL))
        }
        "locale" => one(lp_locale(it, args)),
        "setmaxstack" => lp_setmax(it, args),
        "type" => one(if is_pattern(it, arg(args, 0)) { it.intern("pattern") } else { Value::NIL }),
        "ptree" => {
            let p = getpatt(it, arg(args, 0), 1, "ptree");
            println!("{:?}", tree_of(p));
            Outs::new()
        }
        "pcode" => {
            let p = getpatt(it, arg(args, 0), 1, "pcode");
            let code = code_of(it, p);
            print!("{}", print_code(&code));
            Outs::new()
        }
        "__mul" => one(lp_seq(it, args)),
        "__add" => one(lp_choice(it, args)),
        "__pow" => one(lp_star(it, args)),
        "__len" => one(lp_and(it, args)),
        "__div" => one(lp_divcapture(it, args)),
        "__mod" => one(capture_aux(it, args, CACC, Some(arg(args, 1)), "__mod")),
        "__unm" => one(lp_not(it, args)),
        "__sub" => one(lp_sub(it, args)),
        _ => it.err(&format!("no lpeg function {name}")),
    }
}

/// Calls `lpeg.<name>`. Every value it makes stays on the handle stack until
/// it returns or raises.
pub fn call(it: &mut Interp, name: &str, args: &[Value]) -> Outs {
    let mark = it.open_scope();
    it.handles.extend_from_slice(args);
    let name = name.strip_prefix("lpeg.").unwrap_or(name);
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| dispatch(it, name, args)));
    it.close_scope(mark);
    match result { Ok(out) => out, Err(e) => std::panic::resume_unwind(e) }
}

/// Builds the pattern metatable and the `lpeg` module.
pub fn install(it: &mut Interp) {
    let builtin = |name: &str| Value::builtin(crate::builtins::id_of(name).unwrap_or_else(|| panic!("no builtin {name}")));
    let meta = it.new_table(); it.registered.push(meta);
    it.lpeg_meta = meta;
    for name in ["__mul", "__add", "__pow", "__len", "__div", "__mod", "__unm", "__sub"] {
        let k = it.intern(name); it.set_index(meta, k, builtin(&format!("lpeg.{name}")));
    }
    let lib = it.new_table(); it.registered.push(lib);
    for name in BUILTINS.iter().filter(|n| !n.starts_with("lpeg.__")) {
        let k = it.intern(&name[5..]); it.set_index(lib, k, builtin(name));
    }
    let v = it.intern(VERSION); let root = it.register(v);
    let k = it.intern("version"); it.set_index(lib, k, v); it.release(root);
    let k = it.intern("__index"); it.set_index(meta, k, lib);
    it.loaded.insert("lpeg".into(), lib);
}
