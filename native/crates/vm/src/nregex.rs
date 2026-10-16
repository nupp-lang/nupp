//! Regular expressions for `nupp.text.regex`: the `regex` crate's byte-oriented
//! engine, installed as `nupp.vm.regex` (the `nregex.` builtins).
//!
//! A compiled expression is a userdata whose Rust data is the
//! `regex::bytes::Regex`; the collector drops it with the userdata. Subjects
//! are Lua strings, so matching is over bytes: Unicode classes match UTF-8
//! encoded text and never split a codepoint, and a subject that is not UTF-8
//! still matches wherever its bytes allow. Positions are 1-based and
//! inclusive, as `string.find` reports them. Matching is linear in the
//! subject; the crate has no backreferences or lookaround to make it otherwise.
use crate::{
    builtins::{type_name, Outs},
    heap::KIND_USERDATA,
    interp::Interp,
    value::Value,
};
use regex::bytes::{Regex, RegexBuilder};

/// Every builtin this module answers, in `NAMES` order.
pub const BUILTINS: &[&str] = &[
    "nregex.compile", "nregex.isMatch", "nregex.find", "nregex.captures", "nregex.groups", "nregex.replace",
    "nregex.escape", "nregex.findAll",
];

const META: &str = "nupp.vm.regexMeta";

/// The flag bits `compile` takes, as `nupp.text.regex` spells its options.
const CASE_INSENSITIVE: u32 = 1;
const MULTI_LINE: u32 = 2;
const DOT_MATCHES_NEWLINE: u32 = 4;
const IGNORE_WHITESPACE: u32 = 8;
const BYTES: u32 = 16;
const SWAP_GREED: u32 = 32;

/// What a compiled expression costs the collector's pacing beyond the
/// userdata: the crate does not report its automata's size, so this is a
/// fixed estimate scaled by the pattern.
fn estimate(pattern: &[u8]) -> usize { 4096 + pattern.len() * 64 }

struct Compiled {
    regex: Regex,
    /// Whether the expression matches characters rather than bytes.
    utf8: bool,
}

fn arg(args: &[Value], i: usize) -> Value { args.get(i).copied().unwrap_or(Value::NIL) }
fn outs(values: &[Value]) -> Outs { values.iter().copied().collect() }

/// The expression behind `v`, or a raised argument error naming `method`.
fn compiled<'a>(it: &Interp, v: Value, method: &str) -> &'a Regex {
    let ok = it.kind_of(v) == Some(KIND_USERDATA) && unsafe { (*v.as_obj().unwrap().as_ptr()).userdata().data.is::<Compiled>() };
    if !ok { it.err(&format!("bad argument #1 to '{method}' (regular expression expected, got {})", type_name(it, v))); }
    // The userdata is one of the call's arguments, which `call` roots for the
    // whole call, and the collector never moves an object.
    unsafe { &(*v.as_obj().unwrap().as_ptr()).userdata().data.downcast_ref::<Compiled>().unwrap().regex }
}

/// Whether the compiled expression `v` (already checked) matches characters.
fn characters(_: &Interp, v: Value) -> bool {
    unsafe { (*v.as_obj().unwrap().as_ptr()).userdata().data.downcast_ref::<Compiled>().unwrap().utf8 }
}

/// The bytes of string argument `i`, borrowed from the heap. The string is
/// rooted for the whole call and immutable, so the slice stays valid across
/// allocations the call makes.
fn subject<'a>(it: &Interp, args: &[Value], i: usize, method: &str) -> &'a [u8] {
    let v = arg(args, i);
    if !it.is_stringish(v) { it.err(&format!("bad argument #{} to '{method}' (string expected, got {})", i + 1, type_name(it, v))); }
    unsafe { &*(it.bytes_of(v) as *const [u8]) }
}

/// The 0-based byte offset a 1-based `init` names, with Lua's rules: absent is
/// 1, negative counts from the end, and anything past the end clamps to it.
fn start(it: &Interp, v: Value, len: usize) -> usize {
    if v == Value::NIL { return 0; }
    if !v.is_num() { it.err("bad argument #3 (number expected for init)"); }
    let init = v.as_num().floor();
    let init = if init < 0.0 { (len as f64 + init + 1.0).max(1.0) } else if init == 0.0 { 1.0 } else { init };
    ((init - 1.0) as usize).min(len)
}

fn compile(it: &mut Interp, args: &[Value]) -> Outs {
    let pattern = subject(it, args, 0, "compile");
    let flags = match arg(args, 1) { v if v.is_num() => v.as_num() as u32, _ => 0 };
    let Ok(text) = std::str::from_utf8(pattern) else {
        let reason = it.heap_new_string("the pattern is not valid UTF-8");
        return outs(&[Value::NIL, reason]);
    };
    let built = RegexBuilder::new(text)
        .case_insensitive(flags & CASE_INSENSITIVE != 0)
        .multi_line(flags & MULTI_LINE != 0)
        .dot_matches_new_line(flags & DOT_MATCHES_NEWLINE != 0)
        .ignore_whitespace(flags & IGNORE_WHITESPACE != 0)
        .unicode(flags & BYTES == 0)
        .swap_greed(flags & SWAP_GREED != 0)
        .build();
    match built {
        Ok(regex) => {
            let meta = it.loaded[META];
            let utf8 = flags & BYTES == 0;
            let value = it.new_userdata(Box::new(Compiled { regex, utf8 }), meta, Value::NIL, estimate(pattern));
            outs(&[value])
        }
        Err(error) => {
            let reason = it.heap_new_string(&error.to_string());
            outs(&[Value::NIL, reason])
        }
    }
}

/// `captures(re, subject, init)`: nil, or a table holding each group's
/// 1-based first and last byte in pairs, group 0 (the whole match) first. A
/// group that did not take part holds 0 and 0; an empty one holds `first` and
/// `first - 1`.
fn captures(it: &mut Interp, args: &[Value]) -> Outs {
    let regex = compiled(it, arg(args, 0), "captures");
    let text = subject(it, args, 1, "captures");
    let from = start(it, arg(args, 2), text.len());
    let mut locations = regex.capture_locations();
    if regex.captures_read_at(&mut locations, text, from).is_none() { return outs(&[Value::NIL]); }
    let table = it.new_table();
    let mark = it.open_scope();
    it.handles.push(table);
    for group in 0..locations.len() {
        let (first, last) = match locations.get(group) { Some((s, e)) => (s + 1, e), None => (0, 0) };
        it.set_index(table, Value::num((2 * group + 1) as f64), Value::num(first as f64));
        it.set_index(table, Value::num((2 * group + 2) as f64), Value::num(last as f64));
    }
    it.close_scope(mark);
    outs(&[table])
}

/// `groups(re)`: how many groups the expression has past the whole match, and
/// a table from each named group's name to its number.
fn groups(it: &mut Interp, args: &[Value]) -> Outs {
    let regex = compiled(it, arg(args, 0), "groups");
    let count = regex.captures_len() - 1;
    let table = it.new_table();
    let mark = it.open_scope();
    it.handles.push(table);
    for (index, name) in regex.capture_names().enumerate() {
        let Some(name) = name else { continue };
        let key = it.string_of(name.as_bytes());
        it.set_index(table, key, Value::num(index as f64));
    }
    it.close_scope(mark);
    outs(&[Value::num(count as f64), table])
}

/// `replace(re, subject, replacement, limit)`: the subject with its first
/// `limit` matches (every one when `limit` is 0) replaced, `$1` and `${name}`
/// expanded, and the number replaced.
fn replace(it: &mut Interp, args: &[Value]) -> Outs {
    let regex = compiled(it, arg(args, 0), "replace");
    let text = subject(it, args, 1, "replace");
    let replacement = subject(it, args, 2, "replace");
    let limit = match arg(args, 3) { v if v.is_num() && v.as_num() > 0.0 => v.as_num() as usize, _ => usize::MAX };
    let mut out = Vec::with_capacity(text.len());
    let mut last = 0;
    let mut count = 0;
    for found in regex.captures_iter(text).take(limit) {
        let whole = found.get(0).unwrap();
        out.extend_from_slice(&text[last..whole.start()]);
        found.expand(replacement, &mut out);
        last = whole.end();
        count += 1;
    }
    if count == 0 { return outs(&[arg(args, 1), Value::num(0.0)]); }
    out.extend_from_slice(&text[last..]);
    let result = it.string_of(&out);
    outs(&[result, Value::num(count as f64)])
}

/// A pattern matching exactly `text`. A byte that is not part of valid UTF-8
/// cannot be written literally in a pattern, so it is spelled `(?-u:\xHH)`.
fn escape(mut text: &[u8]) -> String {
    let mut out = String::with_capacity(text.len());
    while !text.is_empty() {
        match std::str::from_utf8(text) {
            Ok(valid) => { out.push_str(&regex::escape(valid)); break; }
            Err(error) => {
                let (valid, rest) = text.split_at(error.valid_up_to());
                out.push_str(&regex::escape(std::str::from_utf8(valid).unwrap()));
                let invalid = error.error_len().unwrap_or(rest.len());
                for byte in &rest[..invalid] { out.push_str(&format!("(?-u:\\x{byte:02X})")); }
                text = &rest[invalid..];
            }
        }
    }
    out
}

/// `findAll(re, subject, init, limit)`: a table holding the first and last
/// byte of each successive non-overlapping match in pairs, at most `limit`
/// of them (every one when `limit` is 0). An empty match is never reported
/// where a previous match ended, and iteration steps past it by one
/// character, so a scan always advances.
fn find_all(it: &mut Interp, args: &[Value]) -> Outs {
    let regex = compiled(it, arg(args, 0), "findAll");
    let text = subject(it, args, 1, "findAll");
    let from = start(it, arg(args, 2), text.len());
    let limit = match arg(args, 3) { v if v.is_num() && v.as_num() > 0.0 => v.as_num() as usize, _ => usize::MAX };
    let table = it.new_table();
    let mark = it.open_scope();
    it.handles.push(table);
    let mut index = 0.0;
    // Each search starts at a position in the whole subject rather than in a
    // suffix of it, so `\b` and `^` still see what comes before.
    let utf8 = characters(it, arg(args, 0));
    let mut at = from;
    let mut previous_end: Option<usize> = None;
    let mut count = 0;
    while at <= text.len() && count < limit {
        let Some(found) = regex.find_at(text, at) else { break };
        if found.start() == found.end() && previous_end == Some(found.end()) {
            // An empty match where the last one ended: try one step further.
            at = next_boundary(utf8, text, found.end());
            if at > text.len() { break; }
            continue;
        }
        index += 1.0;
        it.set_index(table, Value::num(index), Value::num((found.start() + 1) as f64));
        index += 1.0;
        it.set_index(table, Value::num(index), Value::num(found.end() as f64));
        count += 1;
        previous_end = Some(found.end());
        at = if found.start() == found.end() { next_boundary(utf8, text, found.end()) } else { found.end() };
    }
    it.close_scope(mark);
    outs(&[table])
}

/// The position after `at` an empty match steps to: one byte, or past a whole
/// UTF-8 character when the expression matches characters.
fn next_boundary(utf8: bool, text: &[u8], at: usize) -> usize {
    let mut next = at + 1;
    while utf8 && next < text.len() && (text[next] & 0xC0) == 0x80 { next += 1; }
    next
}

fn dispatch(it: &mut Interp, name: &str, args: &[Value]) -> Outs {
    match name {
        "compile" => compile(it, args),
        "isMatch" => {
            let regex = compiled(it, arg(args, 0), "isMatch");
            let text = subject(it, args, 1, "isMatch");
            let from = start(it, arg(args, 2), text.len());
            outs(&[Value::boolean(regex.is_match_at(text, from))])
        }
        "find" => {
            let regex = compiled(it, arg(args, 0), "find");
            let text = subject(it, args, 1, "find");
            let from = start(it, arg(args, 2), text.len());
            match regex.find_at(text, from) {
                Some(found) => outs(&[Value::num((found.start() + 1) as f64), Value::num(found.end() as f64)]),
                None => outs(&[Value::NIL]),
            }
        }
        "captures" => captures(it, args),
        "groups" => groups(it, args),
        "replace" => replace(it, args),
        "findAll" => find_all(it, args),
        "escape" => {
            let text = subject(it, args, 0, "escape");
            let escaped = escape(text);
            let result = it.string_of(escaped.as_bytes());
            outs(&[result])
        }
        _ => it.err(&format!("unknown regular expression operation {name}")),
    }
}

pub fn call(it: &mut Interp, name: &str, args: &[Value]) -> Outs {
    let mark = it.open_scope();
    it.handles.extend_from_slice(args);
    let name = name.strip_prefix("nregex.").unwrap_or(name);
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| dispatch(it, name, args)));
    it.close_scope(mark);
    match result { Ok(out) => out, Err(e) => std::panic::resume_unwind(e) }
}

/// Builds the metatable compiled expressions share. The primitives themselves
/// are installed as `nupp.vm.regex` with the other provider families.
pub fn install(it: &mut Interp) {
    debug_assert!(BUILTINS.iter().all(|name| crate::builtins::id_of(name).is_some()));
    let meta = it.new_table();
    it.registered.push(meta);
    let mark = it.open_scope();
    let k = it.intern("__metatable");
    it.handles.push(k);
    let v = it.intern("regular expression");
    it.set_index(meta, k, v);
    it.close_scope(mark);
    it.loaded.insert(META.into(), meta);
}
