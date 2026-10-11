//! The library the compiler's own modules call: strings with Lua patterns,
//! tables, math, iteration, errors. Each builtin is a value with a tag and an
//! id; a dynamic call on one lands here and returns its results.

use crate::heap::{Body, Value};
use crate::interp::Interp;

pub const NAMES: &[&str] = &[
    "string.byte", "string.sub", "string.find", "string.char", "string.rep", "string.format", "string.gsub", "string.gmatch", "string.len", "string.upper", "string.lower", "string.match",
    "table.concat", "table.insert", "table.remove", "table.unpack",
    "math.floor", "math.min", "math.max", "math.abs", "math.huge",
    "pcall", "pairs", "ipairs", "next", "type", "tostring", "tonumber", "error", "assert", "select", "print", "rawequal", "rawget", "rawset", "setmetatable", "getmetatable", "unpack",
];

pub static STATS: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);
const N_0: u32 = 0; // string.byte
const N_1: u32 = 1; // string.sub
const N_2: u32 = 2; // string.find
const N_3: u32 = 3; // string.char
const N_4: u32 = 4; // string.rep
const N_5: u32 = 5; // string.format
const N_6: u32 = 6; // string.gsub
const N_7: u32 = 7; // string.gmatch
const N_8: u32 = 8; // string.len
const N_9: u32 = 9; // string.upper
const N_10: u32 = 10; // string.lower
const N_11: u32 = 11; // string.match
const N_12: u32 = 12; // table.concat
const N_13: u32 = 13; // table.insert
const N_14: u32 = 14; // table.remove
const N_15: u32 = 15; // table.unpack
const N_16: u32 = 16; // math.floor
const N_17: u32 = 17; // math.min
const N_18: u32 = 18; // math.max
const N_19: u32 = 19; // math.abs
const N_20: u32 = 20; // math.huge
const N_21: u32 = 21; // pcall
const N_22: u32 = 22; // pairs
const N_23: u32 = 23; // ipairs
const N_24: u32 = 24; // next
const N_25: u32 = 25; // type
const N_26: u32 = 26; // tostring
const N_27: u32 = 27; // tonumber
const N_28: u32 = 28; // error
const N_29: u32 = 29; // assert
const N_30: u32 = 30; // select
const N_31: u32 = 31; // print
const N_32: u32 = 32; // rawequal
const N_33: u32 = 33; // rawget
const N_34: u32 = 34; // rawset
const N_35: u32 = 35; // setmetatable
const N_36: u32 = 36; // getmetatable
const N_37: u32 = 37; // unpack

pub fn id_of(name: &str) -> Option<u32> { NAMES.iter().position(|n| *n == name).map(|i| i as u32) }

/// An error raised by `error`: the value travels as the panic payload.
pub struct LuaError(pub u64);

/// Up to eight results, on the stack: a builtin call allocates nothing for
/// its answer. More than eight are dropped, which this prototype accepts.
#[derive(Clone, Copy)]
pub struct Outs { n: u8, v: [Value; 8] }
impl Outs {
    pub fn new() -> Outs { Outs { n: 0, v: [Value::NIL; 8] } }
    pub fn push(&mut self, x: Value) { if (self.n as usize) < 8 { self.v[self.n as usize] = x; self.n += 1; } }
    pub fn len(&self) -> usize { self.n as usize }
    pub fn is_empty(&self) -> bool { self.n == 0 }
    pub fn first(&self) -> Option<&Value> { if self.n > 0 { Some(&self.v[0]) } else { None } }
    pub fn iter(&self) -> std::slice::Iter<'_, Value> { self.v[..self.n as usize].iter() }
    pub fn as_slice(&self) -> &[Value] { &self.v[..self.n as usize] }
    pub fn to_vec(&self) -> Vec<Value> { self.as_slice().to_vec() }
}
impl std::iter::FromIterator<Value> for Outs { fn from_iter<I: IntoIterator<Item = Value>>(it: I) -> Outs { let mut o = Outs::new(); for x in it { o.push(x); } o } }
impl std::ops::Index<usize> for Outs { type Output = Value; fn index(&self, i: usize) -> &Value { &self.v[i] } }
macro_rules! outs { ($($x:expr),* $(,)?) => {{ let mut o = Outs::new(); $( o.push($x); )* o }} }

fn bytes_of(it: &Interp, v: Value) -> Vec<u8> {
    if v.is_num() { return num_text(v.as_num()).into_bytes(); }
    it.bytes_of(v).to_vec()
}
/// The bytes of a string value without a copy; a number is formatted.
fn bytes_ref<'a>(it: &'a Interp, v: Value, scratch: &'a mut Vec<u8>) -> &'a [u8] {
    if v.is_num() { *scratch = num_text(v.as_num()).into_bytes(); return scratch; }
    it.bytes_of(v)
}
pub fn num_text(n: f64) -> String { if n.fract() == 0.0 && n.abs() < 1e15 { format!("{}", n as i64) } else { let s = format!("{:.14}", n); let s = s.trim_end_matches('0').trim_end_matches('.').to_string(); s } }
fn str_of(it: &mut Interp, b: &[u8]) -> Value { let s = unsafe { String::from_utf8_unchecked(b.to_vec()) }; it.intern(&s) }
fn arg(args: &[Value], i: usize) -> Value { args.get(i).copied().unwrap_or(Value::NIL) }
fn int(args: &[Value], i: usize, default: i64) -> i64 { let v = arg(args, i); if v.is_num() { v.as_num() as i64 } else { default } }
fn type_name(it: &Interp, v: Value) -> &'static str {
    if v.is_num() { return "number"; }
    if v == Value::NIL { return "nil"; }
    if v == Value::TRUE || v == Value::FALSE { return "boolean"; }
    if v.as_func().is_some() || v.as_builtin().is_some() { return "function"; }
    match v.as_obj() { Some(p) => unsafe { match &(*p.as_ptr()).body { Body::Str { .. } => "string", Body::Table { .. } => "table", Body::Record { .. } => "table", Body::Closure { .. } => "function", Body::Iter { .. } => "function", Body::Bytes { .. } => "userdata", Body::Storage { .. } => "userdata", _ => "userdata" } }, None => { let _ = it; "nil" } }
}

/// Lua's `tostring`.
pub fn tostring(it: &mut Interp, v: Value) -> String {
    if v.is_num() { return num_text(v.as_num()); }
    if v == Value::NIL { return "nil".into(); }
    if v == Value::TRUE { return "true".into(); }
    if v == Value::FALSE { return "false".into(); }
    if let Some(p) = v.as_obj() { unsafe { if let Body::Str { text, .. } = &(*p.as_ptr()).body { return text.to_string(); } } }
    format!("{}: {:#x}", type_name(it, v), v.0)
}

pub static CALLS: std::sync::Mutex<Vec<u64>> = std::sync::Mutex::new(Vec::new());

pub fn call(it: &mut Interp, id: u32, args: &[Value]) -> Outs {
    // A host service reached from a frame that cannot park: compiled code
    // without a frame record, or a native caller. Contracts 6.2 and 6.4.
    if id >= crate::host::HOST_BASE { it.err("host service called from a frame that cannot park"); }
    if STATS.load(std::sync::atomic::Ordering::Relaxed) { let mut c = CALLS.lock().unwrap(); if c.len() < NAMES.len() { c.resize(NAMES.len(), 0); } c[id as usize] += 1; }
    match id {
        N_0 => {
            let mut scratch = Vec::new(); let s = bytes_ref(it, arg(args, 0), &mut scratch); let n = s.len() as i64;
            let mut i = int(args, 1, 1); let mut j = int(args, 2, i);
            if i < 0 { i += n + 1; } if j < 0 { j += n + 1; }
            if i < 1 { i = 1; } if j > n { j = n; }
            if i > j { return Outs::new(); }
            (i..=j).map(|k| Value::num(s[(k - 1) as usize] as f64)).collect()
        }
        N_1 => {
            let out = { let mut scratch = Vec::new(); let s = bytes_ref(it, arg(args, 0), &mut scratch); let n = s.len() as i64;
            let mut i = int(args, 1, 1); let mut j = int(args, 2, -1);
            if i < 0 { i += n + 1; } if j < 0 { j += n + 1; }
            if i < 1 { i = 1; } if j > n { j = n; }
            if i > j { Vec::new() } else { s[(i - 1) as usize..j as usize].to_vec() } };
            outs![str_of(it, &out)]
        }
        N_8 => { let mut scratch = Vec::new(); let n = bytes_ref(it, arg(args, 0), &mut scratch).len(); outs![Value::num(n as f64)] }
        N_3 => { let b: Vec<u8> = args.iter().map(|v| v.as_num() as i64 as u8).collect(); outs![str_of(it, &b)] }
        N_4 => { let s = bytes_of(it, arg(args, 0)); let n = int(args, 1, 0).max(0) as usize; let sep = if args.len() > 2 { bytes_of(it, arg(args, 2)) } else { Vec::new() }; let mut out = Vec::new(); for k in 0..n { if k > 0 { out.extend_from_slice(&sep); } out.extend_from_slice(&s); } outs![str_of(it, &out)] }
        N_9 => { let s = bytes_of(it, arg(args, 0)); let o: Vec<u8> = s.iter().map(|b| b.to_ascii_uppercase()).collect(); outs![str_of(it, &o)] }
        N_10 => { let s = bytes_of(it, arg(args, 0)); let o: Vec<u8> = s.iter().map(|b| b.to_ascii_lowercase()).collect(); outs![str_of(it, &o)] }
        N_2 | N_11 => {
            let find = id == N_2;
            let pat = bytes_of(it, arg(args, 1));
            let plain = arg(args, 3).truthy();
            if find && (plain || !pat.iter().any(|c| b"^$*+?.([%-".contains(c))) {
                // A plain search borrows the subject; nothing is copied.
                let mut scratch = Vec::new(); let s = bytes_ref(it, arg(args, 0), &mut scratch); let n = s.len() as i64;
                let mut init = int(args, 2, 1); if init < 0 { init += n + 1; } if init < 1 { init = 1; }
                if init > n + 1 { return outs![Value::NIL]; }
                let start = (init - 1) as usize;
                if pat.is_empty() { return outs![Value::num(init as f64), Value::num((init - 1) as f64)]; }
                let hit = if pat.len() == 1 { s[start..].iter().position(|&c| c == pat[0]) } else { s[start..].windows(pat.len()).position(|w| w == &pat[..]) };
                match hit { Some(k) => outs![Value::num((start + k + 1) as f64), Value::num((start + k + pat.len()) as f64)], None => outs![Value::NIL] }
            } else {
                let s = bytes_of(it, arg(args, 0)); let n = s.len() as i64;
                let mut init = int(args, 2, 1); if init < 0 { init += n + 1; } if init < 1 { init = 1; }
                if init > n + 1 { return outs![Value::NIL]; }
                match pattern::find(&s, &pat, (init - 1) as usize) {
                    Some((a, b, caps)) => {
                        let mut out = Outs::new();
                        if find { out.push(Value::num((a + 1) as f64)); out.push(Value::num(b as f64)); }
                        if caps.is_empty() && !find { out.push(str_of(it, &s[a..b])); }
                        for c in caps { out.push(match c { pattern::Cap::Pos(p) => Value::num((p + 1) as f64), pattern::Cap::Span(x, y) => str_of(it, &s[x..y]) }); }
                        out
                    }
                    None => outs![Value::NIL],
                }
            }
        }
        N_7 => { let s = arg(args, 0); let p = arg(args, 1); outs![it.new_iter(3, s, p)] }
        N_6 => {
            let s = bytes_of(it, arg(args, 0)); let pat = bytes_of(it, arg(args, 1)); let repl = arg(args, 2);
            let max = if args.len() > 3 && arg(args, 3).is_num() { int(args, 3, i64::MAX) } else { i64::MAX };
            let anchored = pat.first() == Some(&b'^');
            let mut out = Vec::new(); let mut pos = 0usize; let mut count = 0i64;
            while pos <= s.len() && count < max {
                match pattern::match_at(&s, &pat, pos) {
                    Some((end, caps)) => {
                        count += 1;
                        let whole = &s[pos..end];
                        let cap_values: Vec<Value> = if caps.is_empty() { vec![str_of(it, whole)] } else { caps.iter().map(|c| match c { pattern::Cap::Pos(p) => Value::num((*p + 1) as f64), pattern::Cap::Span(x, y) => str_of(it, &s[*x..*y]) }).collect() };
                        let replacement: Option<Vec<u8>> = if repl.is_num() || matches!(repl.as_obj().map(|p| unsafe { matches!(&(*p.as_ptr()).body, Body::Str { .. }) }), Some(true)) {
                            let r = bytes_of(it, repl); let mut o = Vec::new(); let mut i = 0;
                            while i < r.len() { if r[i] == b'%' && i + 1 < r.len() { let c = r[i + 1]; if c == b'%' { o.push(b'%'); } else if c.is_ascii_digit() { let k = (c - b'0') as usize; if k == 0 { o.extend_from_slice(whole); } else if let Some(v) = cap_values.get(k - 1) { o.extend_from_slice(&bytes_of(it, *v)); } } i += 2; } else { o.push(r[i]); i += 1; } }
                            Some(o)
                        } else if let Some(p) = repl.as_obj().filter(|p| unsafe { matches!(&(*p.as_ptr()).body, Body::Table { .. }) }) {
                            let v = it.get_index(Value::obj(p), cap_values[0]); if v == Value::NIL || v == Value::FALSE { None } else { Some(bytes_of(it, v)) }
                        } else {
                            let res = it.call_value(repl, &cap_values); let v = res.first().copied().unwrap_or(Value::NIL); if v == Value::NIL || v == Value::FALSE { None } else { Some(bytes_of(it, v)) }
                        };
                        match replacement { Some(r) => out.extend_from_slice(&r), None => out.extend_from_slice(whole) }
                        if end > pos { pos = end; } else { if pos < s.len() { out.push(s[pos]); } pos += 1; }
                    }
                    None => { if pos < s.len() { out.push(s[pos]); } pos += 1; }
                }
                if anchored { break; }
            }
            if pos < s.len() { out.extend_from_slice(&s[pos..]); }
            outs![str_of(it, &out), Value::num(count as f64)]
        }
        N_5 => {
            let fmt = bytes_of(it, arg(args, 0)); let mut out = Vec::new(); let mut ai = 1; let mut i = 0;
            while i < fmt.len() {
                if fmt[i] != b'%' { out.push(fmt[i]); i += 1; continue; }
                i += 1; if i >= fmt.len() { break; }
                if fmt[i] == b'%' { out.push(b'%'); i += 1; continue; }
                let start = i; while i < fmt.len() && b"-+ #0123456789.".contains(&fmt[i]) { i += 1; }
                let spec = String::from_utf8_lossy(&fmt[start..i]).to_string(); let conv = fmt[i]; i += 1;
                let v = arg(args, ai); ai += 1;
                let (width, zero, left, prec) = parse_spec(&spec);
                let body: Vec<u8> = match conv {
                    b's' => { let t = tostring(it, v).into_bytes(); match prec { Some(p) => t[..t.len().min(p)].to_vec(), None => t } }
                    b'd' | b'i' => format!("{}", v.as_num() as i64).into_bytes(),
                    b'x' => format!("{:x}", v.as_num() as i64).into_bytes(),
                    b'X' => format!("{:X}", v.as_num() as i64).into_bytes(),
                    b'f' => format!("{:.*}", prec.unwrap_or(6), v.as_num()).into_bytes(),
                    b'g' => num_text(v.as_num()).into_bytes(),
                    b'q' => { let t = bytes_of(it, v); let mut q = vec![b'"']; for &c in &t { match c { b'"' => q.extend_from_slice(b"\\\""), b'\\' => q.extend_from_slice(b"\\\\"), b'\n' => q.extend_from_slice(b"\\n"), b'\r' => q.extend_from_slice(b"\\r"), 0 => q.extend_from_slice(b"\\0"), c if c < 32 || c == 127 => q.extend_from_slice(format!("\\{}", c).as_bytes()), c => q.push(c) } } q.push(b'"'); q }
                    b'c' => vec![v.as_num() as u8],
                    other => panic!("runtime error: string.format conversion %{}", other as char),
                };
                let pad = width.saturating_sub(body.len());
                if left { out.extend_from_slice(&body); out.extend(std::iter::repeat(b' ').take(pad)); }
                else { out.extend(std::iter::repeat(if zero { b'0' } else { b' ' }).take(pad)); out.extend_from_slice(&body); }
            }
            outs![str_of(it, &out)]
        }
        N_12 => {
            let t = arg(args, 0); let sep = if args.len() > 1 && arg(args, 1) != Value::NIL { bytes_of(it, arg(args, 1)) } else { Vec::new() };
            let n = it.array_len(t) as i64; let i = int(args, 2, 1); let j = int(args, 3, n);
            let mut out = Vec::new();
            for k in i..=j { if k > i { out.extend_from_slice(&sep); } let v = it.get_index(t, Value::num(k as f64)); if !(v.is_num() || type_name(it, v) == "string") { panic!("runtime error: invalid value (at index {k}) in table for 'concat'"); } out.extend_from_slice(&bytes_of(it, v)); }
            outs![str_of(it, &out)]
        }
        N_13 => {
            let t = arg(args, 0); let n = it.array_len(t) as i64;
            if args.len() >= 3 { let pos = int(args, 1, n + 1); let v = arg(args, 2); for k in (pos..=n).rev() { let x = it.get_index(t, Value::num(k as f64)); it.set_index(t, Value::num((k + 1) as f64), x); } it.set_index(t, Value::num(pos as f64), v); }
            else { it.set_index(t, Value::num((n + 1) as f64), arg(args, 1)); }
            Outs::new()
        }
        N_14 => {
            let t = arg(args, 0); let n = it.array_len(t) as i64; if n == 0 { return outs![Value::NIL]; }
            let pos = int(args, 1, n); let v = it.get_index(t, Value::num(pos as f64));
            for k in pos..n { let x = it.get_index(t, Value::num((k + 1) as f64)); it.set_index(t, Value::num(k as f64), x); }
            it.set_index(t, Value::num(n as f64), Value::NIL); it.pop_array(t);
            outs![v]
        }
        N_15 | N_37 => { let t = arg(args, 0); let n = it.array_len(t) as i64; let i = int(args, 1, 1); let j = int(args, 2, n); (i..=j).map(|k| it.get_index(t, Value::num(k as f64))).collect() }
        N_16 => outs![Value::num(arg(args, 0).as_num().floor())],
        N_19 => outs![Value::num(arg(args, 0).as_num().abs())],
        N_17 => { let mut m = arg(args, 0).as_num(); for a in &args[1..] { m = m.min(a.as_num()); } outs![Value::num(m)] }
        N_18 => { let mut m = arg(args, 0).as_num(); for a in &args[1..] { m = m.max(a.as_num()); } outs![Value::num(m)] }
        N_20 => outs![Value::num(f64::INFINITY)],
        N_21 => {
            let callee = arg(args, 0); let rest = &args[1.min(args.len())..];
            let hook = std::panic::take_hook(); std::panic::set_hook(Box::new(|_| {}));
            let outcome = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| it.call_value(callee, rest)));
            std::panic::set_hook(hook);
            match outcome {
                Ok(vals) => { let mut o = outs![Value::TRUE]; for v in vals { o.push(v); } o }
                Err(payload) => { let v = if let Some(e) = payload.downcast_ref::<LuaError>() { Value(e.0) } else { let msg = payload.downcast_ref::<String>().cloned().or_else(|| payload.downcast_ref::<&str>().map(|s| s.to_string())).unwrap_or_default(); it.intern(&msg) }; outs![Value::FALSE, v] }
            }
        }
        N_22 => { let t = arg(args, 0); let keys = it.table_keys(t); let itv = it.new_iter_keys(1, t, keys); outs![itv, t, Value::NIL] }
        N_23 => { let t = arg(args, 0); let itv = it.new_iter(2, t, Value::NIL); outs![itv, t, Value::num(0.0)] }
        N_24 => { let t = arg(args, 0); let k = arg(args, 1); let keys = it.table_keys(t); let pos = if k == Value::NIL { 0 } else { keys.iter().position(|x| *x == k).map(|p| p + 1).unwrap_or(keys.len()) }; if pos < keys.len() { let key = keys[pos]; let v = it.get_index(t, key); outs![key, v] } else { outs![Value::NIL] } }
        N_25 => { let v = arg(args, 0); let n = type_name(it, v); outs![it.intern(n)] }
        N_26 => { let v = arg(args, 0); let s = tostring(it, v); outs![it.intern(&s)] }
        N_27 => { let v = arg(args, 0); if v.is_num() { return outs![v]; } let s = String::from_utf8_lossy(&bytes_of(it, v)).trim().to_string(); let base = int(args, 1, 10); let n = if base == 10 { if let Some(h) = s.strip_prefix("0x").or_else(|| s.strip_prefix("0X")) { i64::from_str_radix(h, 16).ok().map(|x| x as f64) } else { s.parse::<f64>().ok() } } else { i64::from_str_radix(&s, base as u32).ok().map(|x| x as f64) }; outs![n.map(Value::num).unwrap_or(Value::NIL)] }
        N_28 => { let v = arg(args, 0); std::panic::panic_any(LuaError(v.0)) }
        N_29 => { let v = arg(args, 0); if !v.truthy() { let msg = if args.len() > 1 { arg(args, 1) } else { it.intern("assertion failed!") }; std::panic::panic_any(LuaError(msg.0)); } args.iter().copied().collect() }
        N_30 => { let n = arg(args, 0); if !n.is_num() { return outs![Value::num((args.len() - 1) as f64)]; } let i = n.as_num() as i64; if i < 0 { args[(args.len() as i64 + i) as usize..].iter().copied().collect() } else { args[(i as usize).min(args.len())..].iter().copied().collect() } }
        N_31 => { let parts: Vec<String> = args.iter().map(|&v| tostring(it, v)).collect(); println!("{}", parts.join("\t")); Outs::new() }
        N_32 => outs![Value::boolean(arg(args, 0) == arg(args, 1))],
        N_33 => { let v = it.get_index(arg(args, 0), arg(args, 1)); outs![v] }
        N_34 => { it.set_index(arg(args, 0), arg(args, 1), arg(args, 2)); outs![arg(args, 0)] }
        N_35 => outs![arg(args, 0)],
        N_36 => outs![Value::NIL],
        other => panic!("runtime error: builtin {} not implemented", NAMES[other as usize]),
    }
}

fn parse_spec(spec: &str) -> (usize, bool, bool, Option<usize>) {
    let left = spec.contains('-'); let zero = spec.starts_with('0') || spec.contains("-0");
    let digits: String = spec.chars().skip_while(|c| "-+ #0".contains(*c)).collect();
    let (w, p) = match digits.split_once('.') { Some((w, p)) => (w.to_string(), Some(p.parse::<usize>().unwrap_or(0))), None => (digits, None) };
    (w.parse().unwrap_or(0), zero, left, p)
}

/// One step of an iterator object: `pairs`, `ipairs` or `gmatch` state.
pub fn iter_next(it: &mut Interp, iter: Value) -> Outs {
    let (kind, obj, pos, keys_len) = it.iter_state(iter);
    match kind {
        1 => { if pos >= keys_len { return outs![Value::NIL]; } let k = it.iter_key(iter, pos); it.iter_advance(iter); let v = it.get_index(obj, k); outs![k, v] }
        2 => { let i = pos + 1; let v = it.get_index(obj, Value::num(i as f64)); if v == Value::NIL { return outs![Value::NIL]; } it.iter_advance(iter); outs![Value::num(i as f64), v] }
        3 => {
            let s = bytes_of(it, obj); let pat = bytes_of(it, it.iter_pattern(iter));
            if pos > s.len() { return outs![Value::NIL]; }
            match pattern::find(&s, &pat, pos) {
                Some((a, b, caps)) => { it.iter_set_pos(iter, if b > a { b } else { b + 1 }); if caps.is_empty() { outs![str_of(it, &s[a..b])] } else { caps.iter().map(|c| match c { pattern::Cap::Pos(p) => Value::num((*p + 1) as f64), pattern::Cap::Span(x, y) => str_of(it, &s[*x..*y]) }).collect() } }
                None => { it.iter_set_pos(iter, s.len() + 1); outs![Value::NIL] }
            }
        }
        _ => outs![Value::NIL],
    }
}

/// Lua patterns: classes, sets, captures, anchors, the four quantifiers.
pub mod pattern {
    #[derive(Clone, Copy, Debug)]
    pub enum Cap { Span(usize, usize), Pos(usize) }
    #[derive(Clone)]
    struct State<'a> { s: &'a [u8], p: &'a [u8], caps: Vec<(usize, Option<usize>)>, depth: u32 }

    fn class_matches(c: u8, cl: u8) -> bool {
        let r = match cl.to_ascii_lowercase() { b'a' => c.is_ascii_alphabetic(), b'd' => c.is_ascii_digit(), b's' => c.is_ascii_whitespace() || c == 11, b'w' => c.is_ascii_alphanumeric(), b'x' => c.is_ascii_hexdigit(), b'p' => c.is_ascii_punctuation(), b'l' => c.is_ascii_lowercase(), b'u' => c.is_ascii_uppercase(), b'c' => c.is_ascii_control(), b'g' => c.is_ascii_graphic(), other => return c == other };
        if cl.is_ascii_uppercase() { !r } else { r }
    }
    /// The end of the single-character item starting at `pi`.
    fn item_end(p: &[u8], pi: usize) -> usize {
        match p[pi] { b'%' => (pi + 2).min(p.len()), b'[' => { let mut i = pi + 1; if i < p.len() && p[i] == b'^' { i += 1; } loop { if i >= p.len() { return p.len(); } if p[i] == b']' && i > pi + 1 { return i + 1; } if p[i] == b'%' { i += 2; } else { i += 1; } } } _ => pi + 1 }
    }
    fn single(c: u8, p: &[u8], pi: usize, end: usize) -> bool {
        match p[pi] {
            b'.' => true,
            b'%' => class_matches(c, p[pi + 1]),
            b'[' => { let mut i = pi + 1; let neg = p[i] == b'^'; if neg { i += 1; } let mut found = false; while i < end - 1 { if p[i] == b'%' { if class_matches(c, p[i + 1]) { found = true; } i += 2; } else if i + 2 < end - 1 && p[i + 1] == b'-' { if c >= p[i] && c <= p[i + 2] { found = true; } i += 3; } else { if c == p[i] { found = true; } i += 1; } } found != neg }
            other => c == other,
        }
    }
    fn do_match(st: &mut State, si: usize, pi: usize) -> Option<usize> {
        st.depth += 1; if st.depth > 10_000 { panic!("runtime error: pattern too complex"); }
        let r = match_inner(st, si, pi);
        st.depth -= 1; r
    }
    fn match_inner(st: &mut State, mut si: usize, mut pi: usize) -> Option<usize> {
        let p = st.p; let s = st.s;
        loop {
            if pi >= p.len() { return Some(si); }
            match p[pi] {
                b'(' => {
                    if pi + 1 < p.len() && p[pi + 1] == b')' { st.caps.push((si, Some(si))); let idx = st.caps.len() - 1; st.caps[idx] = (si, None); let r = do_match(st, si, pi + 2); if r.is_none() { st.caps.pop(); } else { st.caps[idx].1 = Some(usize::MAX); } return r; }
                    st.caps.push((si, None)); let idx = st.caps.len() - 1;
                    let r = do_match(st, si, pi + 1); if r.is_none() { st.caps.truncate(idx); } return r;
                }
                b')' => { let idx = st.caps.iter().rposition(|c| c.1.is_none()).expect("unmatched )"); st.caps[idx].1 = Some(si); let r = do_match(st, si, pi + 1); if r.is_none() { st.caps[idx].1 = None; } return r; }
                b'$' if pi + 1 == p.len() => return if si == s.len() { Some(si) } else { None },
                _ => {
                    let end = item_end(p, pi);
                    let m = si < s.len() && single(s[si], p, pi, end);
                    let q = if end < p.len() { p[end] } else { 0 };
                    match q {
                        b'?' => { if m { if let Some(r) = do_match(st, si + 1, end + 1) { return Some(r); } } pi = end + 1; continue; }
                        b'+' => { if !m { return None; } return max_expand(st, si + 1, pi, end); }
                        b'*' => return max_expand(st, si, pi, end),
                        b'-' => { let mut i = si; loop { if let Some(r) = do_match(st, i, end + 1) { return Some(r); } if i < s.len() && single(s[i], p, pi, end) { i += 1; } else { return None; } } }
                        _ => { if !m { return None; } si += 1; pi = end; continue; }
                    }
                }
            }
        }
    }
    fn max_expand(st: &mut State, si: usize, pi: usize, end: usize) -> Option<usize> {
        let s = st.s; let p = st.p;
        let mut i = si; while i < s.len() && single(s[i], p, pi, end) { i += 1; }
        loop { if let Some(r) = do_match(st, i, end + 1) { return Some(r); } if i == si { return None; } i -= 1; }
    }
    fn captures(st: &State) -> Vec<Cap> { st.caps.iter().map(|&(a, b)| match b { Some(usize::MAX) => Cap::Pos(a), Some(e) => Cap::Span(a, e), None => Cap::Span(a, a) }).collect() }
    /// Matches anchored at `si`; returns the end and the captures.
    pub fn match_at(s: &[u8], p: &[u8], si: usize) -> Option<(usize, Vec<Cap>)> {
        let p = if p.first() == Some(&b'^') { &p[1..] } else { p };
        let mut st = State { s, p, caps: Vec::new(), depth: 0 };
        do_match(&mut st, si, 0).map(|e| (e, captures(&st)))
    }
    /// The first match at or after `init`: (start, end, captures).
    pub fn find(s: &[u8], p: &[u8], init: usize) -> Option<(usize, usize, Vec<Cap>)> {
        let anchored = p.first() == Some(&b'^');
        let body = if anchored { &p[1..] } else { p };
        let mut si = init;
        loop {
            let mut st = State { s, p: body, caps: Vec::new(), depth: 0 };
            if let Some(e) = do_match(&mut st, si, 0) { return Some((si, e, captures(&st))); }
            if anchored || si >= s.len() { return None; }
            si += 1;
        }
    }
}
