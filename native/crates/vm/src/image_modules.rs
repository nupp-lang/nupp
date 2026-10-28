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
//! A module's digest covers its functions as the runtime holds them, from a
//! text image or a graph alike, with every image-wide index rewritten to
//! something that does not move when another module changes: a function id
//! becomes the owning module and the function's position in it, and a shape
//! id becomes the shape's own text. Its edges are its literal requires, the modules whose functions it
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

use crate::heap::SlotTy;
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

/// The modules of the image loaded into `it` as its first `count` functions:
/// their code as the runtime holds it, whichever format it came in. None when
/// `it` holds fewer functions.
pub fn analyze(it: &Interp, count: usize) -> Option<Vec<ImageModule>> {
    if it.funcs.len() < count { return None; }
    let funcs = &it.funcs[..count];
    let table = crate::opcodes::table();
    // A function's stable name: its module and its position among that
    // module's functions.
    let mut ordinal: HashMap<&str, usize> = HashMap::new();
    let names: Vec<String> = funcs.iter().map(|f| {
        let n = ordinal.entry(f.module.as_str()).or_insert(0);
        *n += 1;
        format!("{}#{}", f.module, *n - 1)
    }).collect();
    let fname = |id: u32| -> String { names.get(id as usize).cloned().unwrap_or_else(|| format!("?{id}")) };
    let owner = |id: u32| -> Option<&str> { funcs.get(id as usize).map(|f| f.module.as_str()) };
    let text = |v: Value| -> String { String::from_utf8_lossy(it.bytes_of(v)).into_owned() };

    // A shape's text without its heap id: its name and identity, its slots, a
    // record slot naming the shape it holds by name and identity, and its
    // methods by their functions' stable names; and the modules defining them.
    let mut identity: HashMap<u32, &str> = HashMap::new();
    for (key, &id) in &it.heap.shape_identities { identity.insert(id, key.as_str()); }
    let shallow = |id: u32| -> String {
        let shape = &it.heap.shapes[id as usize];
        format!("{}{}", shape.name, identity.get(&id).map(|k| format!(" identity={k}")).unwrap_or_default())
    };
    let mut shape_text: HashMap<u32, (String, BTreeSet<&str>)> = HashMap::new();
    let mut describe = |id: u32| -> (String, BTreeSet<&str>) {
        shape_text.entry(id).or_insert_with(|| {
            let shape = &it.heap.shapes[id as usize];
            let mut out = shallow(id);
            for (slot, ty) in shape.names.iter().zip(&shape.types) {
                let ty = match ty { SlotTy::Num => "num".to_string(), SlotTy::Str => "str".to_string(), SlotTy::Bool => "bool".to_string(), SlotTy::Record(r) => format!("rec:{}", shallow(r)), SlotTy::Any => "any".to_string() };
                out.push_str(&format!(" {}:{ty}", text(*slot)));
            }
            let mut owners = BTreeSet::new();
            let mut methods: Vec<(String, String)> = shape.methods.iter().filter_map(|(&k, &v)| v.as_func().map(|fid| {
                if let Some(m) = owner(fid) { owners.insert(m); }
                (text(k), fname(fid))
            })).collect();
            methods.sort();
            for (name, f) in methods { out.push_str(&format!(" method:{name}={f}")); }
            (out, owners)
        }).clone()
    };

    let in_image: BTreeSet<&str> = it.modules.iter().filter(|entry| (*entry.1 as usize) < count).map(|(name, _)| name.as_str()).collect();
    let mut code: BTreeMap<&str, String> = BTreeMap::new();
    let mut edges: BTreeMap<&str, BTreeSet<String>> = BTreeMap::new();
    for &name in &in_image {
        let path = it.module_paths.get(name).map(String::as_str).unwrap_or("");
        code.entry(name).or_default().push_str(&format!("module {} {}\n", fname(it.modules[name]), path));
        edges.entry(name).or_default();
    }
    for f in funcs {
        let module = f.module.as_str();
        let out = code.entry(module).or_default();
        let deps = edges.entry(module).or_default();
        // The name without the function's image-wide id, which an anonymous
        // function's name (`parent.fn<id>`) carries.
        let name = f.name.split('.').map(|segment| match segment.strip_prefix("fn") {
            Some(id) if !id.is_empty() && id.bytes().all(|b| b.is_ascii_digit()) => format!("fn[{}]", fname(id.parse().unwrap_or(u32::MAX))),
            _ => segment.to_string(),
        }).collect::<Vec<_>>().join(".");
        out.push_str(&format!("function {name} {} {:?} {} {} {} {} {} {}\n", f.nparams, f.sig, f.ret, f.vararg, f.nregs, f.nireg, f.nfreg, f.nvreg));
        for &c in &f.consts {
            if let Some(fid) = c.as_func() {
                out.push_str(&format!("const func {}\n", fname(fid)));
                if let Some(m) = owner(fid).filter(|&m| m != module) { deps.insert(m.to_string()); }
            } else if it.is_stringish(c) {
                out.push_str(&format!("const str {:?}\n", it.bytes_of(c)));
            } else {
                out.push_str(&format!("const {:#x}\n", c.0));
            }
        }
        for (pc, op) in f.code.iter().enumerate() {
            let row = table.row(op);
            out.push_str(&row.name);
            for (spec, v) in row.operands.iter().zip(op.operands()) {
                match spec.class {
                    crate::opcodes::Class::Func => {
                        out.push_str(&format!(" {}", fname(v as u32)));
                        if let Some(m) = owner(v as u32).filter(|&m| m != module) { deps.insert(m.to_string()); }
                    }
                    crate::opcodes::Class::Shape => {
                        let (described, owners) = describe(v as u32);
                        out.push_str(&format!(" [{described}]"));
                        for m in owners { if m != module { deps.insert(m.to_string()); } }
                    }
                    _ => out.push_str(&format!(" {v}")),
                }
            }
            out.push_str(&format!(" @{}\n", f.debug.get(pc).map_or(0, |d| d.0)));
        }
    }

    // Requires, read off the loaded code.
    let mut dynamic: BTreeSet<&str> = BTreeSet::new();
    let mut markers: BTreeMap<&str, Vec<String>> = BTreeMap::new();
    for f in funcs {
        let module = f.module.as_str();
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
    let succs = crate::verify::successors(f);
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
    let count = match it.code_events.first() {
        Some(crate::persist::CodeEvent::Image(text)) => text.lines().filter(|l| l.trim_start().starts_with("function ")).count(),
        Some(crate::persist::CodeEvent::Graph { functions, .. }) => *functions as usize,
        _ => return Value::NIL,
    };
    let modules = analyze(it, count);
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
