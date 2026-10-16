//! LuaJIT's `string.buffer`: a FIFO byte buffer object and the serializer
//! `encode`/`decode` speak, byte for byte the format LuaJIT 2.1 writes
//! (lj_serialize.c), so a payload either runtime encodes the other decodes.
//!
//! A buffer is a userdata whose Rust data is the byte vector and a read
//! offset; methods come through its metatable's `__index`, as LuaJIT's do.
//! What needs the FFI (`ref`, `reserve`, `commit`, `putcdata`) and the
//! serializer's dictionary options are refused: this runtime has no FFI
//! pointers, and nothing on it builds dictionaries.
use crate::{
    builtins::{type_name, Outs},
    heap::{KIND_RECORD, KIND_TABLE, KIND_USERDATA},
    interp::Interp,
    value::Value,
};

/// Every builtin this module answers, in `NAMES` order.
pub const BUILTINS: &[&str] = &[
    "sbuf.new", "sbuf.encode", "sbuf.decode",
    "sbuf.put", "sbuf.putf", "sbuf.get", "sbuf.tostring", "sbuf.reset", "sbuf.free", "sbuf.skip", "sbuf.set",
    "sbuf.bencode", "sbuf.bdecode", "sbuf.putcdata", "sbuf.ref", "sbuf.reserve", "sbuf.commit",
    "sbuf.__len", "sbuf.__tostring", "sbuf.__concat",
];

/// Nesting LuaJIT allows a serialized value (`LJ_SERIALIZE_DEPTH`).
const DEPTH: usize = 100;

const TAG_NIL: u32 = 0;
const TAG_FALSE: u32 = 1;
const TAG_TRUE: u32 = 2;
const TAG_NULL: u32 = 3;
const TAG_INT: u32 = 6;
const TAG_NUM: u32 = 7;
const TAG_TAB: u32 = 8;
const TAG_INT64: u32 = 0x10;
const TAG_UINT64: u32 = 0x11;
const TAG_STR: u32 = 0x20;

/// The buffer's bytes; those before `read` were consumed.
pub(crate) struct StrBuf {
    data: Vec<u8>,
    read: usize,
}
impl StrBuf {
    fn bytes(&self) -> &[u8] { &self.data[self.read..] }
    fn consume(&mut self, n: usize) -> Vec<u8> {
        let n = n.min(self.data.len() - self.read);
        let out = self.data[self.read..self.read + n].to_vec();
        self.advance(n);
        out
    }
    fn advance(&mut self, n: usize) {
        self.read += n;
        if self.read == self.data.len() {
            self.data.clear();
            self.read = 0;
        } else if self.read > 4096 && self.read * 2 > self.data.len() {
            self.data.drain(..self.read);
            self.read = 0;
        }
    }
}

/// Raises `msg` as LuaJIT's library raises it: the bare message, with no
/// runtime prefix.
fn fail(_: &Interp, msg: &str) -> ! {
    std::panic::panic_any(msg.to_string())
}

fn is_buffer(it: &Interp, v: Value) -> bool {
    it.kind_of(v) == Some(KIND_USERDATA)
        && unsafe { (*v.as_obj().unwrap().as_ptr()).userdata().data.is::<StrBuf>() }
}

/// The buffer behind `v`. The reference must not outlive a call that can run
/// a program (a `__tostring`) or reach the buffer some other way.
fn buffer<'a>(it: &Interp, v: Value, method: &str) -> &'a mut StrBuf {
    if !is_buffer(it, v) { fail(it, &format!("bad argument #1 to '{method}' (buffer expected, got {})", type_name(it, v))); }
    unsafe { (*v.as_obj().unwrap().as_ptr()).userdata_mut().data.downcast_mut::<StrBuf>().unwrap() }
}

/// Re-reports the buffer's capacity to the collector's pacing after a change.
fn account(it: &mut Interp, v: Value) {
    let p = v.as_obj().unwrap();
    let u = unsafe { (*p.as_ptr()).userdata_mut() };
    let now = u.data.downcast_ref::<StrBuf>().unwrap().data.capacity();
    let before = std::mem::replace(&mut u.external, now);
    it.heap.account_resize(before, now);
}

fn append(it: &mut Interp, v: Value, bytes: &[u8]) {
    buffer(it, v, "put").data.extend_from_slice(bytes);
    account(it, v);
}

fn new_buffer(it: &mut Interp, bytes: Vec<u8>) -> Value {
    let meta = it.loaded[META];
    let external = bytes.capacity();
    it.new_userdata(Box::new(StrBuf { data: bytes, read: 0 }), meta, Value::NIL, external)
}

const META: &str = "nupp.vm.stringBufferMeta";

/// The text `put` appends for one argument: a string, a number, a buffer's
/// contents or what `__tostring` answers.
fn text_of(it: &mut Interp, v: Value, position: usize) -> Vec<u8> {
    if it.is_stringish(v) { return it.bytes_of(v).to_vec(); }
    if crate::numeric::is_numeric(v) { return crate::builtins::tostring(it, v); }
    if is_buffer(it, v) { return buffer(it, v, "put").bytes().to_vec(); }
    if it.metamethod(v, crate::metamethods::MM::ToString) != Value::NIL { return crate::builtins::tostring(it, v); }
    fail(it, &format!("bad argument #{position} to 'put' (string/number/__tostring expected, got {})", type_name(it, v)))
}

fn wu124(out: &mut Vec<u8>, v: u32) {
    if v < 0xe0 {
        out.push(v as u8);
    } else if v < 0x1fe0 {
        let v = v - 0xe0;
        out.push(((v >> 8) | 0xe0) as u8);
        out.push(v as u8);
    } else {
        out.push(0xff);
        out.extend_from_slice(&v.to_le_bytes());
    }
}

/// Appends the serialization of `v`.
pub(crate) fn serialize(it: &Interp, v: Value, out: &mut Vec<u8>, depth: usize) {
    if v == Value::NIL { return out.push(TAG_NIL as u8); }
    if v == Value::FALSE { return out.push(TAG_FALSE as u8); }
    if v == Value::TRUE { return out.push(TAG_TRUE as u8); }
    if v.is_num() {
        let f = v.as_num();
        if f.fract() == 0.0 && f >= i32::MIN as f64 && f <= i32::MAX as f64 && !(f == 0.0 && f.is_sign_negative()) {
            out.push(TAG_INT as u8);
            out.extend_from_slice(&(f as i32).to_le_bytes());
        } else {
            out.push(TAG_NUM as u8);
            out.extend_from_slice(&f.to_bits().to_le_bytes());
        }
        return;
    }
    if let Some(i) = crate::numeric::integer(v) {
        out.push(if i.unsigned { TAG_UINT64 } else { TAG_INT64 } as u8);
        out.extend_from_slice(&i.bits.to_le_bytes());
        return;
    }
    if it.is_stringish(v) {
        let bytes = it.bytes_of(v);
        if bytes.len() > (u32::MAX - TAG_STR) as usize { fail(it, "buffer too large"); }
        wu124(out, TAG_STR + bytes.len() as u32);
        out.extend_from_slice(bytes);
        return;
    }
    match it.kind_of(v) {
        Some(KIND_TABLE) if !crate::coroutines::is_coroutine(it, v) => {
            if depth == 0 { fail(it, "too deep to serialize"); }
            let t = unsafe { (*v.as_obj().unwrap().as_ptr()).table_ref() };
            let narray = t.array.iter().rposition(|x| *x != Value::NIL).map_or(0, |i| i + 2);
            let nhash = t.hash.iter().count();
            // Index 0 is never in the array part here, so the array is always
            // written from 1, as LuaJIT writes an array whose slot 0 is nil.
            out.push((TAG_TAB + if nhash > 0 { 1 } else { 0 } + if narray > 0 { 4 } else { 0 }) as u8);
            if narray > 0 { wu124(out, narray as u32); }
            if nhash > 0 { wu124(out, nhash as u32); }
            if narray > 0 { for &x in &t.array[..narray - 1] { serialize(it, x, out, depth - 1); } }
            for (k, x) in t.hash.iter() {
                serialize(it, *k, out, depth - 1);
                serialize(it, *x, out, depth - 1);
            }
        }
        Some(KIND_RECORD) => {
            if depth == 0 { fail(it, "too deep to serialize"); }
            let keys = it.table_keys(v);
            let pairs: Vec<(Value, Value)> = keys.into_iter().map(|k| (k, it.get_index(v, k))).filter(|(_, x)| *x != Value::NIL).collect();
            out.push((TAG_TAB + if pairs.is_empty() { 0 } else { 1 }) as u8);
            if !pairs.is_empty() { wu124(out, pairs.len() as u32); }
            for (k, x) in pairs {
                serialize(it, k, out, depth - 1);
                serialize(it, x, out, depth - 1);
            }
        }
        _ => fail(it, &format!("cannot serialize '{}'", type_name(it, v))),
    }
}

struct Reader<'a> { bytes: &'a [u8], at: usize }
impl Reader<'_> {
    fn take(&mut self, it: &Interp, n: usize) -> &[u8] {
        if self.bytes.len() - self.at < n { fail(it, "unexpected end of buffer"); }
        let s = &self.bytes[self.at..self.at + n];
        self.at += n;
        s
    }
    fn ru124(&mut self, it: &Interp) -> u32 {
        let b = self.take(it, 1)[0] as u32;
        if b < 0xe0 { return b; }
        if b != 0xff {
            let lo = self.take(it, 1)[0] as u32;
            return (((b & 0x1f) << 8) | lo) + 0xe0;
        }
        u32::from_le_bytes(self.take(it, 4).try_into().unwrap())
    }
}

/// Decodes one value. Every object it makes is pushed on the handle stack,
/// where the caller's scope keeps it until the result is rooted elsewhere.
fn deserialize(it: &mut Interp, r: &mut Reader, depth: usize) -> Value {
    let tag = r.ru124(it);
    match tag {
        TAG_NIL | TAG_NULL => Value::NIL,
        TAG_FALSE => Value::FALSE,
        TAG_TRUE => Value::TRUE,
        TAG_INT => Value::num(i32::from_le_bytes(r.take(it, 4).try_into().unwrap()) as f64),
        TAG_NUM => Value::num(f64::from_bits(u64::from_le_bytes(r.take(it, 8).try_into().unwrap()))),
        TAG_INT64 | TAG_UINT64 => {
            let bits = u64::from_le_bytes(r.take(it, 8).try_into().unwrap());
            let v = it.box_integer(crate::numeric::Integer { bits, unsigned: tag == TAG_UINT64 });
            it.handles.push(v);
            v
        }
        t if t >= TAG_STR => {
            let n = (t - TAG_STR) as usize;
            let bytes = r.take(it, n).to_vec();
            let v = it.string_of(&bytes);
            it.handles.push(v);
            v
        }
        t if (TAG_TAB..TAG_TAB + 6).contains(&t) => {
            if depth == 0 { fail(it, "too deep to serialize"); }
            let narray = if t & 6 != 0 { r.ru124(it) as usize } else { 0 };
            let nhash = if t & 1 != 0 { r.ru124(it) as usize } else { 0 };
            // Sizes are hints from untrusted input: never reserve beyond what
            // the remaining bytes could hold.
            let left = r.bytes.len() - r.at;
            let table = it.new_table_sized(narray.min(left), nhash.min(left));
            it.handles.push(table);
            let first = if t & 4 != 0 { 1 } else { 0 };
            for i in first..narray {
                let v = deserialize(it, r, depth - 1);
                if v != Value::NIL { it.set_index(table, Value::num(i as f64), v); }
            }
            for _ in 0..nhash {
                let k = deserialize(it, r, depth - 1);
                let v = deserialize(it, r, depth - 1);
                if k == Value::NIL { fail(it, "table index is nil"); }
                if k.is_num() && k.as_num().is_nan() { fail(it, "table index is NaN"); }
                if it.get_index(table, k) != Value::NIL { fail(it, "duplicate table key"); }
                if v != Value::NIL { it.set_index(table, k, v); }
            }
            table
        }
        0x0e | 0x0f => {
            // A dictionary reference; no dictionary is ever configured here.
            let index = r.ru124(it);
            fail(it, &format!("cannot deserialize dictionary index {index}"))
        }
        t => fail(it, &format!("cannot deserialize tag 0x{t:02x}")),
    }
}

fn decode_one(it: &mut Interp, bytes: &[u8]) -> (Value, usize) {
    let mut r = Reader { bytes, at: 0 };
    let v = deserialize(it, &mut r, DEPTH);
    (v, r.at)
}

fn number_arg(it: &Interp, v: Value, position: usize, method: &str) -> f64 {
    if !v.is_num() { fail(it, &format!("bad argument #{position} to '{method}' (number expected, got {})", type_name(it, v))); }
    v.as_num()
}

fn dispatch(it: &mut Interp, name: &str, args: &[Value]) -> Outs {
    let arg = |i: usize| args.get(i).copied().unwrap_or(Value::NIL);
    let one = |v: Value| -> Outs { let mut o = Outs::new(); o.push(v); o };
    let this = arg(0);
    match name {
        "new" => {
            let options = if it.kind_of(arg(0)) == Some(KIND_TABLE) { arg(0) } else { arg(1) };
            if options != Value::NIL {
                for key in ["dict", "metatable"] {
                    let k = it.intern(key);
                    if it.get_index(options, k) != Value::NIL { fail(it, &format!("string.buffer option '{key}' is not supported on this runtime")); }
                }
            }
            one(new_buffer(it, Vec::new()))
        }
        "encode" => {
            let mut out = Vec::new();
            serialize(it, arg(0), &mut out, DEPTH);
            one(it.string_of(&out))
        }
        "decode" => {
            if !it.is_stringish(arg(0)) { fail(it, &format!("bad argument #1 to 'decode' (string expected, got {})", type_name(it, arg(0)))); }
            let bytes = it.bytes_of(arg(0)).to_vec();
            let (v, used) = decode_one(it, &bytes);
            if used != bytes.len() { fail(it, "left-over data in buffer"); }
            one(v)
        }
        "put" => {
            buffer(it, this, "put");
            for (i, &v) in args.iter().enumerate().skip(1) {
                let text = text_of(it, v, i + 1);
                append(it, this, &text);
            }
            one(this)
        }
        "putf" => {
            buffer(it, this, "putf");
            let format = crate::builtins::call(it, crate::builtins::STRING_FORMAT, &args[1.min(args.len())..]);
            let text = it.bytes_of(format.first().copied().unwrap_or(Value::NIL)).to_vec();
            append(it, this, &text);
            one(this)
        }
        "get" => {
            buffer(it, this, "get");
            let mut out = Outs::new();
            if args.len() <= 1 {
                let all = buffer(it, this, "get").consume(usize::MAX);
                out.push(it.string_of(&all));
                return out;
            }
            for (i, &n) in args.iter().enumerate().skip(1) {
                let n = if n == Value::NIL { usize::MAX } else {
                    let count = number_arg(it, n, i + 1, "get");
                    // LuaJIT refuses a negative count, after any earlier ones were taken.
                    if count < 0.0 { fail(it, &format!("bad argument #{} to '?' (number out of range)", i + 1)); }
                    count as usize
                };
                let piece = buffer(it, this, "get").consume(n);
                let s = it.string_of(&piece);
                it.handles.push(s);
                out.push(s);
            }
            out
        }
        "tostring" | "__tostring" => {
            let bytes = buffer(it, this, "tostring").bytes().to_vec();
            one(it.string_of(&bytes))
        }
        "reset" => { let b = buffer(it, this, "reset"); b.data.clear(); b.read = 0; one(this) }
        "free" => { let b = buffer(it, this, "free"); b.data = Vec::new(); b.read = 0; account(it, this); one(this) }
        "skip" => {
            buffer(it, this, "skip");
            let n = number_arg(it, arg(1), 2, "skip");
            if n < 0.0 { fail(it, "bad argument #2 to '?' (number out of range)"); }
            let n = n as usize;
            let b = buffer(it, this, "skip");
            let n = n.min(b.data.len() - b.read);
            b.advance(n);
            one(this)
        }
        "set" => {
            buffer(it, this, "set");
            if !it.is_stringish(arg(1)) { fail(it, &format!("bad argument #2 to 'set' (string expected, got {})", type_name(it, arg(1)))); }
            let bytes = it.bytes_of(arg(1)).to_vec();
            let b = buffer(it, this, "set");
            b.data = bytes;
            b.read = 0;
            account(it, this);
            one(this)
        }
        "bencode" => {
            buffer(it, this, "encode");
            let mut out = Vec::new();
            serialize(it, arg(1), &mut out, DEPTH);
            append(it, this, &out);
            one(this)
        }
        "bdecode" => {
            let bytes = buffer(it, this, "decode").bytes().to_vec();
            let (v, used) = decode_one(it, &bytes);
            buffer(it, this, "decode").advance(used);
            one(v)
        }
        "__len" => { let n = buffer(it, this, "len").bytes().len(); one(Value::num(n as f64)) }
        "__concat" => {
            let mut joined = Vec::new();
            for v in [arg(0), arg(1)] {
                if is_buffer(it, v) { joined.extend_from_slice(buffer(it, v, "concat").bytes()); }
                else if it.is_stringish(v) || crate::numeric::is_numeric(v) { joined.extend(crate::builtins::tostring(it, v)); }
                else { fail(it, &format!("attempt to concatenate a {} value", type_name(it, v))); }
            }
            one(it.string_of(&joined))
        }
        "putcdata" | "ref" | "reserve" | "commit" => fail(it, &format!("string.buffer {name} needs the FFI, which this runtime does not provide")),
        _ => fail(it, &format!("no string.buffer function {name}")),
    }
}

/// Calls `sbuf.<name>`. Every value it makes stays on the handle stack until
/// it returns or raises.
pub fn call(it: &mut Interp, name: &str, args: &[Value]) -> Outs {
    let mark = it.open_scope();
    it.handles.extend_from_slice(args);
    let name = name.strip_prefix("sbuf.").unwrap_or(name);
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| dispatch(it, name, args)));
    it.close_scope(mark);
    match result { Ok(out) => out, Err(e) => std::panic::resume_unwind(e) }
}

/// Builds the buffer metatable and the `string.buffer` module.
pub fn install(it: &mut Interp) {
    debug_assert!(BUILTINS.iter().all(|name| crate::builtins::id_of(name).is_some()));
    let builtin = |name: &str| Value::builtin(crate::builtins::id_of(name).unwrap_or_else(|| panic!("no builtin {name}")));
    let meta = it.new_table();
    it.registered.push(meta);
    let methods = it.new_table();
    it.registered.push(methods);
    for (method, name) in [("put", "put"), ("putf", "putf"), ("get", "get"), ("tostring", "tostring"), ("reset", "reset"), ("free", "free"),
        ("skip", "skip"), ("set", "set"), ("encode", "bencode"), ("decode", "bdecode"), ("putcdata", "putcdata"), ("ref", "ref"),
        ("reserve", "reserve"), ("commit", "commit")] {
        let k = it.intern(method);
        it.set_index(methods, k, builtin(&format!("sbuf.{name}")));
    }
    for name in ["__len", "__tostring", "__concat"] {
        let k = it.intern(name);
        it.set_index(meta, k, builtin(&format!("sbuf.{name}")));
    }
    let k = it.intern("__index");
    it.set_index(meta, k, methods);
    let lib = it.new_table();
    it.registered.push(lib);
    for name in ["new", "encode", "decode"] {
        let k = it.intern(name);
        it.set_index(lib, k, builtin(&format!("sbuf.{name}")));
    }
    it.loaded.insert(META.into(), meta);
    it.loaded.insert("string.buffer".into(), lib);
}
