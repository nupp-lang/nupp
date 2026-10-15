//! What each module of the running image is and what it depends on, for cache
//! stamps narrower than the whole image.
//!
//! A cache stamp names the code that computed an answer. The whole image's
//! digest (`vm.imageIdentity`) is true but coarse: an edit to any command
//! makes every store start cold. This answers, per module the image carries,
//! a digest of that module's lowered code and the modules it reaches, so the
//! compiler can stamp a store with only the modules its answer came from,
//! the way it walks the module graph of a LuaJIT tree. It is read off the
//! image the VM started from, never off sources, which may have moved on.
//!
//! A module's digest covers its functions as the image spells them, with
//! every image-wide index rewritten to something that does not move when
//! another module changes: a function id becomes the owning module and the
//! function's position in it, and a shape index becomes the shape's own
//! text. Its edges are its literal requires, the modules whose functions it
//! names, the modules defining methods of the shapes it uses, and what an
//! `@requires-dynamically` marker declares.
//!
//! A require this cannot name makes the module incomplete, as it does in the
//! LuaJIT graph (`nupp.compiler.project.fingerprint`), whose accounting this
//! follows: a call to `require` whose argument is a string literal is that
//! module; one whose argument is a concatenation starting with a literal
//! counts as that literal, which is how a token reader sees
//! `require("nupp.compiler." .. name)`; any other argument, or `require`
//! used as a value, is incomplete unless the module carries a marker. A
//! literal naming a module the image does not carry is no edge: that code is
//! no more covered by the whole image's digest than by this.

use crate::interp::{Interp, Op};
use crate::value::Value;
use crate::verify::C;
use std::collections::{BTreeMap, BTreeSet, HashMap};

/// One module of the image.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ImageModule {
    pub name: String,
    /// The cache digest of the module's normalized lowered code.
    pub digest: String,
    /// The image modules it reaches, sorted.
    pub deps: Vec<String>,
    /// Whether it may load something its edges do not name.
    pub unknown: bool,
}

struct TextFunction<'a> {
    module: &'a str,
    header: &'a str,
    body: Vec<&'a str>,
}

struct TextImage<'a> {
    shapes: Vec<&'a str>,
    functions: Vec<TextFunction<'a>>,
    /// (name, entry function id, path)
    modules: Vec<(&'a str, usize, &'a str)>,
}

fn parse(text: &str) -> Option<TextImage<'_>> {
    let mut image = TextImage { shapes: Vec::new(), functions: Vec::new(), modules: Vec::new() };
    let mut open = false;
    for raw in text.lines() {
        let line = raw.trim();
        if line.is_empty() { continue; }
        let word = line.split_whitespace().next().unwrap_or("");
        match word {
            "shape" if !open => image.shapes.push(line),
            "function" => { open = true; image.functions.push(TextFunction { module: "", header: line, body: Vec::new() }); }
            "end" if open => open = false,
            "source" if open => { image.functions.last_mut()?.module = line.split_whitespace().nth(1).unwrap_or(""); }
            "module" if !open => {
                let mut parts = line.split_whitespace();
                parts.next();
                let name = parts.next()?;
                let fid = parts.next()?.parse().ok()?;
                image.modules.push((name, fid, parts.next().unwrap_or("")));
            }
            _ if open => image.functions.last_mut()?.body.push(line),
            _ => {}
        }
    }
    Some(image)
}

/// The modules of the image `text`, as loaded into `it` starting at function
/// zero: `it` supplies the lowered code the require accounting reads and the
/// modules the runtime itself provides. None when `it` does not hold `text`
/// at function zero.
pub fn analyze(it: &Interp, text: &str) -> Option<Vec<ImageModule>> {
    let image = parse(text)?;
    if it.funcs.len() < image.functions.len() { return None; }
    for (fid, f) in image.functions.iter().enumerate() {
        if it.funcs[fid].module != f.module { return None; }
    }
    // A function's stable name: its module and its position among that
    // module's functions.
    let mut ordinal: HashMap<&str, usize> = HashMap::new();
    let names: Vec<String> = image.functions.iter().map(|f| {
        let n = ordinal.entry(f.module).or_insert(0);
        *n += 1;
        format!("{}#{}", f.module, *n - 1)
    }).collect();
    let fname = |token: &str| -> String {
        token.parse::<usize>().ok().and_then(|i| names.get(i)).cloned().unwrap_or_else(|| format!("?{token}"))
    };
    let owner = |token: &str| -> Option<&str> { token.parse::<usize>().ok().and_then(|i| image.functions.get(i)).map(|f| f.module) };

    // A shape's text without its index, a record slot naming the shape it holds
    // by name and identity, and a method by its function's stable name.
    let shape_key = |index: usize| -> String {
        let Some(line) = image.shapes.get(index) else { return format!("?{index}") };
        let parts: Vec<&str> = line.split_whitespace().collect();
        let identity = parts.iter().skip(3).find(|p| p.starts_with("identity="));
        format!("{}{}", parts.get(2).unwrap_or(&""), identity.map(|i| format!(" {i}")).unwrap_or_default())
    };
    let mut shapes: Vec<(String, BTreeSet<&str>)> = Vec::with_capacity(image.shapes.len());
    for line in &image.shapes {
        let parts: Vec<&str> = line.split_whitespace().collect();
        let mut text = String::from(*parts.get(2).unwrap_or(&""));
        let mut owners = BTreeSet::new();
        for p in parts.iter().skip(3) {
            text.push(' ');
            if let Some((name, fid)) = p.strip_prefix("method:").and_then(|m| m.split_once('=')) {
                text.push_str(&format!("method:{name}={}", fname(fid)));
                if let Some(m) = owner(fid) { owners.insert(m); }
            } else if let Some((slot, record)) = p.split_once(":rec:") {
                text.push_str(&format!("{slot}:rec:{}", record.parse().map(shape_key).unwrap_or_else(|_| record.to_string())));
            } else {
                text.push_str(p);
            }
        }
        shapes.push((text, owners));
    }

    let mut code: BTreeMap<&str, String> = BTreeMap::new();
    let mut edges: BTreeMap<&str, BTreeSet<String>> = BTreeMap::new();
    for &(name, fid, path) in &image.modules {
        code.entry(name).or_default().push_str(&format!("module {} {}\n", fname(&fid.to_string()), path));
        edges.entry(name).or_default();
    }
    for f in &image.functions {
        let module = f.module;
        let out = code.entry(module).or_default();
        let deps = edges.entry(module).or_default();
        // The header without the function's image-wide id, which an anonymous
        // function's name (`parent.fn<id>`) also carries.
        let header: Vec<&str> = f.header.split_whitespace().collect();
        let name = header.get(1).map(|name| name.split('.').map(|segment| match segment.strip_prefix("fn") {
            Some(id) if !id.is_empty() && id.bytes().all(|b| b.is_ascii_digit()) => format!("fn[{}]", fname(id)),
            _ => segment.to_string(),
        }).collect::<Vec<_>>().join(".")).unwrap_or_default();
        out.push_str(&name);
        for part in header.iter().skip(3) { out.push(' '); out.push_str(part); }
        out.push('\n');
        for line in &f.body {
            let word = line.split(' ').next().unwrap_or("");
            let function_at = match word {
                "const" if line.split_whitespace().nth(2) == Some("func") => Some(3),
                "Call" | "CallT" | "CallK" => Some(1),
                "NewClosure" => Some(2),
                _ => None,
            };
            let shape_at = match word {
                "NewRecord" => Some(2),
                "GetSlot" | "SetSlot" | "GetSlotF" | "SetSlotF" => Some(4),
                "TagCheckRec" | "IsRec" => Some(3),
                "SetMethod" => Some(1),
                _ => None,
            };
            if function_at.is_none() && shape_at.is_none() {
                out.push_str(line);
                out.push('\n');
                continue;
            }
            let parts: Vec<&str> = line.split_whitespace().collect();
            let mut rewritten: Vec<String> = parts.iter().map(|p| p.to_string()).collect();
            if let Some(i) = function_at.filter(|&i| i < parts.len()) {
                rewritten[i] = fname(parts[i]);
                if let Some(m) = owner(parts[i]).filter(|&m| m != module) { deps.insert(m.to_string()); }
            }
            if let Some(i) = shape_at.filter(|&i| i < parts.len()) {
                match parts[i].parse::<usize>().ok().and_then(|s| shapes.get(s)) {
                    Some((text, owners)) => {
                        rewritten[i] = format!("[{text}]");
                        for m in owners { if *m != module { deps.insert(m.to_string()); } }
                    }
                    None => rewritten[i] = format!("?{}", parts[i]),
                }
            }
            out.push_str(&rewritten.join(" "));
            out.push('\n');
        }
    }

    // Requires, read off the loaded code.
    let in_image: BTreeSet<&str> = image.modules.iter().map(|m| m.0).collect();
    let mut dynamic: BTreeSet<&str> = BTreeSet::new();
    let mut markers: BTreeMap<&str, Vec<String>> = BTreeMap::new();
    for (fid, tf) in image.functions.iter().enumerate() {
        let f = &it.funcs[fid];
        let module = tf.module;
        for &c in &f.consts {
            if it.is_stringish(c) {
                let found = declared(it.bytes_of(c));
                if !found.is_empty() { markers.entry(module).or_default().extend(found); }
            }
        }
        let literal = f.code.iter().filter_map(|op| match *op {
            Op::Require(_, k) => f.consts.get(k as usize).copied().filter(|&v| it.is_stringish(v)),
            _ => None,
        }).map(|v| Site::Named(String::from_utf8_lossy(it.bytes_of(v)).into_owned())).collect::<Vec<_>>();
        for site in literal.into_iter().chain(require_sites(it, f)) {
            match site {
                Site::Named(name) | Site::Prefix(name) if in_image.contains(name.as_str()) => { edges.entry(module).or_default().insert(name); }
                // Code the image does not carry is no more part of this stamp than
                // it is of the whole image's, and the LuaJIT graph leaves a name
                // outside its tree out the same way: a facade's browser provider,
                // an optional library.
                Site::Named(_) | Site::Prefix(_) => {}
                Site::Dynamic => { dynamic.insert(module); }
            }
        }
    }
    for (module, patterns) in &markers {
        let deps = edges.entry(module).or_default();
        for pattern in patterns {
            if pattern == "nothing" { continue; }
            if let Some(prefix) = pattern.strip_suffix(".*") {
                for m in &in_image { if m.len() > prefix.len() + 1 && m.starts_with(prefix) && m.as_bytes()[prefix.len()] == b'.' { deps.insert(m.to_string()); } }
            } else if in_image.contains(pattern.as_str()) {
                deps.insert(pattern.clone());
            }
        }
    }

    let mut out = Vec::with_capacity(in_image.len());
    for name in in_image {
        let mut deps: Vec<String> = edges.remove(name).unwrap_or_default().into_iter().filter(|d| d != name).collect();
        deps.sort();
        let digest = nupp_native_platform::cache_digest(code.get(name).map(String::as_bytes).unwrap_or_default());
        out.push(ImageModule {
            name: name.to_string(),
            digest: String::from_utf8_lossy(&digest).into_owned(),
            deps,
            unknown: dynamic.contains(name) && !markers.contains_key(name),
        });
    }
    Some(out)
}

/// What `@requires-dynamically NAME` markers in `text` declare, matched as
/// the LuaJIT graph matches them: `@requires%-dynamically%s+([%w%.%*%-_]+)`.
pub fn declared(text: &[u8]) -> Vec<String> {
    const MARK: &[u8] = b"@requires-dynamically";
    let mut found = Vec::new();
    let mut at = 0;
    while let Some(offset) = text[at..].iter().position(|&b| b == b'@') {
        if !text[at + offset..].starts_with(MARK) { at += offset + 1; continue; }
        let mut i = at + offset + MARK.len();
        let spaces = i;
        while i < text.len() && matches!(text[i], b' ' | b'\t' | b'\n' | b'\r' | 0x0b | 0x0c) { i += 1; }
        let start = i;
        while i < text.len() && (text[i].is_ascii_alphanumeric() || matches!(text[i], b'.' | b'*' | b'-' | b'_')) { i += 1; }
        if start > spaces && i > start {
            found.push(String::from_utf8_lossy(&text[start..i]).into_owned());
            at = i;
        } else {
            at = at + offset + 1;
        }
    }
    found
}

#[derive(Debug, PartialEq)]
enum Site { Named(String), Prefix(String), Dynamic }

/// What a register may hold, as far as requires are concerned.
#[derive(Clone, PartialEq, Debug)]
enum Abs { Str(Vec<u8>), Prefix(Vec<u8>), Globals, Require, MaybeRequire }

type State = BTreeMap<u8, Abs>;

fn join(a: &State, b: &State) -> State {
    let mut out = State::new();
    for (r, x) in a {
        match b.get(r) {
            Some(y) if x == y => { out.insert(*r, x.clone()); }
            other => if matches!(x, Abs::Require | Abs::MaybeRequire) || matches!(other, Some(Abs::Require | Abs::MaybeRequire)) { out.insert(*r, Abs::MaybeRequire); },
        }
    }
    for (r, y) in b {
        if !a.contains_key(r) && matches!(y, Abs::Require | Abs::MaybeRequire) { out.insert(*r, Abs::MaybeRequire); }
    }
    out
}

fn fixed_args(nargs: u8) -> u8 { if nargs >= 128 { nargs & 127 } else { nargs & 63 } }

/// Every place `f` calls `require`, and every place `require` escapes as a
/// value (`Site::Dynamic`): a forward dataflow over the function's registers.
fn require_sites(it: &Interp, f: &crate::interp::Function) -> Vec<Site> {
    let require = crate::builtins::id_of("require");
    let is_require = |v: Value| v.as_builtin().is_some() && v.as_builtin() == require;
    let text = |k: u16| -> Option<&[u8]> { f.consts.get(k as usize).copied().filter(|&v| it.is_stringish(v)).map(|v| it.bytes_of(v)) };
    let relevant = f.code.iter().any(|op| matches!(op, Op::RequireV(..)))
        || f.consts.iter().any(|&v| is_require(v))
        || f.code.iter().any(|op| matches!(op, Op::GetField(_, _, k) if text(*k) == Some(b"require")));
    if !relevant { return Vec::new(); }
    let n = f.code.len();
    let succs: Vec<Vec<usize>> = f.code.iter().enumerate().map(|(pc, op)| {
        let (_, offs) = crate::verify::operands(op);
        let mut s: Vec<usize> = offs.iter().map(|o| (pc as i64 + 1 + *o as i64) as usize).collect();
        if let Op::Switch(_, t) = op { if let Some((def, tbl)) = f.jump_tables.get(*t as usize) { for o in std::iter::once(def).chain(tbl.iter()) { s.push((pc as i64 + 1 + *o as i64) as usize); } } }
        let falls = !matches!(op, Op::Jmp(..) | Op::Ret(..) | Op::RetNil | Op::RetN(..) | Op::FRet(..) | Op::Raise(..) | Op::Switch(..));
        if falls { s.push(pc + 1); }
        s.retain(|&t| t < n);
        s
    }).collect();
    let mut states: Vec<Option<State>> = vec![None; n];
    if n > 0 { states[0] = Some(State::new()); }
    let mut sites: BTreeMap<usize, Vec<Site>> = BTreeMap::new();
    let mut work: Vec<usize> = vec![0];
    while let Some(pc) = work.pop() {
        if pc >= n { continue; }
        let Some(mut st) = states[pc].clone() else { continue };
        let op = f.code[pc];
        let requireish = |st: &State, r: u8| matches!(st.get(&r), Some(Abs::Require | Abs::MaybeRequire));
        let arg = |st: &State, r: u8| -> Site {
            match st.get(&r) {
                Some(Abs::Str(s)) => Site::Named(String::from_utf8_lossy(s).into_owned()),
                Some(Abs::Prefix(s)) => Site::Prefix(String::from_utf8_lossy(s).into_owned()),
                _ => Site::Dynamic,
            }
        };
        let mut found: Vec<Site> = Vec::new();
        // The callee register a call reads as its function rather than as a value.
        let mut callee: Option<u8> = None;
        match op {
            Op::RequireV(_, s) => found.push(arg(&st, s)),
            Op::CallDyn(fr, base, nargs) | Op::CallK(_, fr, base, nargs, _) if requireish(&st, fr) => {
                callee = Some(fr);
                found.push(if fixed_args(nargs) >= 1 { arg(&st, base.wrapping_add(1)) } else { Site::Dynamic });
            }
            Op::PCall(base, nargs) if requireish(&st, base.wrapping_add(1)) => {
                callee = Some(base.wrapping_add(1));
                found.push(if fixed_args(nargs) >= 1 { arg(&st, base.wrapping_add(2)) } else { Site::Dynamic });
            }
            _ => {}
        }
        let (defs, uses): (Vec<(C, u8)>, Vec<(C, u8)>) = match op {
            Op::CallT(fid, base, _, _) => {
                let nv = it.funcs.get(fid as usize).map(|g| g.nv_params).unwrap_or(u8::MAX);
                (vec![(C::V, base)], (1..=nv).filter_map(|i| base.checked_add(i)).map(|r| (C::V, r)).collect())
            }
            Op::PadResults(d, k) => ((0..k).filter_map(|i| d.checked_add(i)).map(|r| (C::V, r)).collect(), Vec::new()),
            _ => crate::verify::defs_uses(&op),
        };
        for (c, r) in &uses {
            if *c != C::V || Some(*r) == callee || matches!(op, Op::Move(..)) { continue; }
            if requireish(&st, *r) { found.push(Site::Dynamic); }
        }
        let value = match op {
            Op::K(_, k) => {
                let v = f.consts.get(k as usize).copied().unwrap_or(Value::NIL);
                if is_require(v) { Some(Abs::Require) } else if it.is_stringish(v) { Some(Abs::Str(it.bytes_of(v).to_vec())) } else { None }
            }
            Op::Move(_, s) => st.get(&s).cloned(),
            Op::Concat(_, a, b) => match (st.get(&a), st.get(&b)) {
                (Some(Abs::Str(x)), Some(Abs::Str(y))) => Some(Abs::Str([x.as_slice(), y.as_slice()].concat())),
                (Some(Abs::Str(x)), Some(Abs::Prefix(y))) => Some(Abs::Prefix([x.as_slice(), y.as_slice()].concat())),
                (Some(Abs::Str(x) | Abs::Prefix(x)), _) => Some(Abs::Prefix(x.clone())),
                _ => None,
            },
            Op::Require(_, k) if text(k) == Some(b"_G") => Some(Abs::Globals),
            Op::GetField(_, t, k) if st.get(&t) == Some(&Abs::Globals) && text(k) == Some(b"require") => Some(Abs::Require),
            _ => None,
        };
        for (c, r) in &defs {
            if *c == C::V { st.remove(r); }
        }
        if let (Some(v), Some((C::V, d))) = (value, defs.first()) { st.insert(*d, v); }
        sites.insert(pc, found);
        for &s in &succs[pc] {
            let merged = match &states[s] { Some(old) => join(old, &st), None => st.clone() };
            if states[s].as_ref() != Some(&merged) {
                states[s] = Some(merged);
                work.push(s);
            }
        }
    }
    sites.into_values().flatten().collect()
}

/// `vm.imageModules`: `{digests = {module = digest}, edges = {module = {deps}},
/// unknown = {module = boolean}}` for the image the VM started from, or nil
/// when it did not start from one.
pub fn tables(it: &mut Interp) -> Value {
    let modules = match it.code_events.first() {
        Some(crate::persist::CodeEvent::Image(text)) => {
            let text = text.clone();
            analyze(it, &text)
        }
        _ => None,
    };
    let Some(modules) = modules else { return Value::NIL };
    let scope = it.open_scope();
    let result = it.new_table(); it.handles.push(result);
    let field = |it: &mut Interp, name: &str| -> Value {
        let t = it.new_table(); it.handles.push(t);
        let k = it.intern(name); it.handles.push(k);
        it.set_index(result, k, t);
        t
    };
    let digests = field(it, "digests");
    let edges = field(it, "edges");
    let unknown = field(it, "unknown");
    for m in &modules {
        let inner = it.open_scope();
        let name = it.intern(&m.name); it.handles.push(name);
        let digest = it.new_string_bytes(m.digest.as_bytes()); it.handles.push(digest);
        it.set_index(digests, name, digest);
        let list = it.new_table_sized(m.deps.len(), 0); it.handles.push(list);
        it.set_index(edges, name, list);
        for (i, dep) in m.deps.iter().enumerate() {
            let d = it.intern(dep); it.handles.push(d);
            it.set_index(list, Value::num((i + 1) as f64), d);
        }
        it.set_index(unknown, name, if m.unknown { Value::TRUE } else { Value::FALSE });
        it.close_scope(inner);
    }
    it.close_scope(scope);
    result
}
