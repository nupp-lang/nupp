//! `lua-utf8`, the part of luautf8's API the development rocks use, natively:
//! the VM loads no C modules. Case mapping is Unicode's; invalid UTF-8 bytes
//! pass through unchanged, as luautf8's lenient functions do.
use crate::{builtins::Outs, interp::Interp, value::Value};

fn arg(args: &[Value], i: usize) -> Value { args.get(i).copied().unwrap_or(Value::NIL) }
fn one(v: Value) -> Outs { let mut o = Outs::new(); o.push(v); o }

/// Characters with their byte offsets, decoding leniently: a stray byte is a
/// one-byte "character" that maps to itself.
fn decode(bytes: &[u8]) -> Vec<(usize, Option<char>, usize)> {
    let mut out = Vec::new(); let mut i = 0;
    while i < bytes.len() {
        let width = match bytes[i] { b if b < 0x80 => 1, b if b >> 5 == 0b110 => 2, b if b >> 4 == 0b1110 => 3, b if b >> 3 == 0b11110 => 4, _ => 1 };
        let decoded = bytes.get(i..i + width).and_then(|s| std::str::from_utf8(s).ok()).and_then(|s| s.chars().next());
        let width = if decoded.is_some() { width } else { 1 };
        out.push((i, decoded, width)); i += width;
    }
    out
}
fn map_case(bytes: &[u8], upper: bool) -> Vec<u8> {
    let mut out = Vec::with_capacity(bytes.len());
    for (at, c, width) in decode(bytes) {
        match c {
            Some(c) => { let mapped: String = if upper { c.to_uppercase().collect() } else { c.to_lowercase().collect() }; out.extend_from_slice(mapped.as_bytes()); }
            None => out.extend_from_slice(&bytes[at..at + width]),
        }
    }
    out
}
/// A Lua character position (1-based, negative from the end) as an index into `n` characters.
fn position(i: f64, n: usize) -> i64 { let i = i as i64; if i < 0 { n as i64 + i + 1 } else { i } }

pub fn call(it: &mut Interp, name: &str, args: &[Value]) -> Outs {
    match name.strip_prefix("utf8.").unwrap_or(name) {
        "char" => {
            let mut text = String::new();
            for &v in args {
                let code = v.as_num() as u32;
                text.push(char::from_u32(code).unwrap_or_else(|| it.err(&format!("bad argument to 'char' (value out of range: {code})"))));
            }
            one(it.heap_new_string(&text))
        }
        "lower" | "upper" => { let bytes = it.bytes_of(arg(args, 0)).to_vec(); let mapped = map_case(&bytes, name.ends_with("upper")); one(it.new_string_bytes(&mapped)) }
        "len" => { let bytes = it.bytes_of(arg(args, 0)).to_vec(); one(Value::num(decode(&bytes).len() as f64)) }
        "codepoint" => {
            let bytes = it.bytes_of(arg(args, 0)).to_vec(); let chars = decode(&bytes);
            let first = if arg(args, 1) == Value::NIL { 1 } else { position(arg(args, 1).as_num(), bytes.len()) };
            let last = if arg(args, 2) == Value::NIL { first } else { position(arg(args, 2).as_num(), bytes.len()) };
            let mut out = Outs::new();
            for (at, c, _) in chars { let at = at as i64 + 1; if at >= first && at <= last { out.push(Value::num(c.map(|c| c as u32).unwrap_or(bytes[at as usize - 1] as u32) as f64)); } }
            out
        }
        "sub" => {
            let bytes = it.bytes_of(arg(args, 0)).to_vec(); let chars = decode(&bytes); let n = chars.len();
            let first = position(if arg(args, 1) == Value::NIL { 1.0 } else { arg(args, 1).as_num() }, n).max(1);
            let last = position(if arg(args, 2) == Value::NIL { -1.0 } else { arg(args, 2).as_num() }, n).min(n as i64);
            if first > last { return one(it.intern("")); }
            let (from, _, _) = chars[first as usize - 1]; let (to, _, width) = chars[last as usize - 1];
            one(it.new_string_bytes(&bytes[from..to + width]))
        }
        other => it.err(&format!("lua-utf8 has no function {other}")),
    }
}
