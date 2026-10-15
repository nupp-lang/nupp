//! Development hot reload: body patches by function id (runtime plan, "Hot
//! reload", item 1).
//!
//! Functions are ids. A closure, a method table entry, a `func` constant and a
//! direct call all name the id, never the body, so replacing the body stored
//! at an id is what every caller sees on its next call; nothing is rebound.
//!
//! A patch is the changed module's whole image, lowered again, behind two
//! header lines:
//!
//! ```text
//! patch MODULE
//! map OLD OLD - OLD ...
//! <image text>
//! ```
//!
//! `map` names, for each function of the new image in order, its position in
//! the running module's function list (the identity the compiler matched it
//! to), or `-` for a function the running module never had: an anonymous
//! closure a new body introduced. A matched function keeps its id; a new one
//! is appended. The running module's list after a commit is the new image's,
//! so the next patch maps against it.
//!
//! What a patch refuses, before anything changes: a module that was never
//! loaded; a function whose calling convention changed (parameters, typed
//! signature, result class, varargs), since callers were lowered against it;
//! a capture count that differs from the closures already made; a record
//! layout the running module did not have; a function the linked compiler
//! object carries native code for; and a VM whose lazy typed tier calls
//! compiled entries directly, which `vm.loadImage` refuses for the same reason.
//!
//! Frames mid-change follow the "finish on the old version" policy (item 2):
//! an activation already running a changed body keeps running that body. Its
//! old code moves to a fresh id the frame is retargeted to, and stays alive as
//! long as anything can reach it. The Vec holding the old code is moved, never
//! reallocated, so an interpreter window cached over it stays valid; every
//! later call, recursive ones included, enters the new body.

use crate::interp::{Function, Interp, Op};
use crate::value::Value;
use std::collections::HashMap;

/// A loaded module's code, in the order its newest image listed it.
#[derive(Default, Clone)]
pub struct ModuleCode {
    pub fids: Vec<u32>,
    /// The image's shapes when it held this module alone; a patch's shapes
    /// must resolve to these by position or by identity.
    pub shapes: Vec<u32>,
}

#[derive(Default)]
pub struct State {
    pub modules: HashMap<String, ModuleCode>,
    /// Commits so far; part of the code recipe, so of the checkpoint identity.
    pub generation: u64,
}

/// What a validated or committed patch did.
#[derive(Debug, Default, PartialEq, Eq)]
pub struct Report {
    /// Functions whose body changed.
    pub changed: usize,
    /// Functions whose code is the same and only source lines moved.
    pub moved: usize,
    /// Functions the running module never had.
    pub added: usize,
    /// Activations left running an old body.
    pub retained: usize,
    pub generation: u64,
}

/// Remembers which functions an image loaded for each of its modules.
pub(crate) fn record(it: &mut Interp, base: u32, funcs: &[Function], shapes: &[u32], modules: &[(String, u32, Option<String>)]) {
    if let [(name, _, _)] = modules {
        // A module compiled alone: every function its image holds is its own,
        // the instantiations it lowered from other modules included, in the
        // order a patch lowered the same way lists them.
        let fids = (base..base + funcs.len() as u32).collect();
        it.hot.modules.insert(name.clone(), ModuleCode { fids, shapes: shapes.to_vec() });
        return;
    }
    let mut by_module: HashMap<&str, Vec<u32>> = HashMap::new();
    for (i, f) in funcs.iter().enumerate() { by_module.entry(f.module.as_str()).or_default().push(base + i as u32); }
    for (name, _, _) in modules {
        let fids = by_module.remove(name.as_str()).unwrap_or_default();
        it.hot.modules.insert(name.clone(), ModuleCode { fids, shapes: Vec::new() });
    }
}

struct Header<'a> { module: &'a str, map: Vec<Option<usize>>, image: &'a str }

fn header(text: &str) -> Result<Header<'_>, String> {
    let mut lines = text.splitn(3, '\n');
    let first = lines.next().unwrap_or("");
    let module = first.trim().strip_prefix("patch ").map(str::trim).filter(|m| !m.is_empty()).ok_or("a patch starts with `patch MODULE`")?;
    let second = lines.next().unwrap_or("").trim();
    let map = second.strip_prefix("map").ok_or("a patch's second line is `map`")?;
    let map = map.split_whitespace().map(|s| if s == "-" { Ok(None) } else { s.parse::<usize>().map(Some).map_err(|_| format!("invalid map entry {s}")) }).collect::<Result<Vec<_>, _>>()?;
    Ok(Header { module, map, image: lines.next().unwrap_or("") })
}

fn remap(op: &mut Op, to: &dyn Fn(u32) -> Result<u32, String>) -> Result<(), String> {
    match op {
        Op::Call(f, ..) | Op::CallT(f, ..) | Op::NewClosure(_, f, ..) => *f = to(*f)?,
        Op::CallK(f, ..) => *f = to(*f as u32)? as u16,
        _ => {}
    }
    Ok(())
}

/// The capture count every closure of a function is made with, by function.
fn captures<'a>(funcs: impl Iterator<Item = &'a Function>) -> HashMap<u32, u8> {
    let mut out = HashMap::new();
    for f in funcs { for op in &f.code { if let Op::NewClosure(_, fid, _, n) = *op { out.insert(fid, n); } } }
    out
}

fn same_constants(it: &Interp, a: &[Value], b: &[Value]) -> bool {
    a.len() == b.len() && a.iter().zip(b).all(|(&x, &y)| x == y || it.is_stringish(x) && it.is_stringish(y) && it.bytes_of(x) == it.bytes_of(y))
}

fn same_code(it: &Interp, a: &Function, b: &Function) -> bool {
    a.nparams == b.nparams && a.nregs == b.nregs && a.nireg == b.nireg && a.nfreg == b.nfreg && a.nvreg == b.nvreg
        && a.vararg == b.vararg && a.sig == b.sig && a.ret == b.ret && a.jump_tables == b.jump_tables
        && a.code.len() == b.code.len() && format!("{:?}", a.code) == format!("{:?}", b.code)
        && same_constants(it, &a.consts, &b.consts)
}

/// Every frame running one of `fids`, in all tasks, by frame position.
fn live_frames(it: &Interp, fids: &std::collections::HashSet<u32>) -> Vec<(usize, usize, u32)> {
    let mut out = Vec::new();
    for (tid, t) in it.tasks.iter().enumerate() {
        if t.state == crate::interp::State::Done || t.stack.is_empty() { continue; }
        let mut s = t.cur();
        loop {
            let fid = (t.stack[s] & 0xffff_ffff) as u32;
            if fids.contains(&fid) { out.push((tid, s, fid)); }
            let caller = (t.stack[s + 1] & 0xffff_ffff) as u32;
            if caller == u32::MAX { break; }
            s = caller as usize;
        }
    }
    out
}

/// Validates a patch and, when `commit`, applies it. Nothing changes unless
/// the whole patch is accepted.
pub fn apply(it: &mut Interp, text: &str, commit: bool) -> Result<Report, String> {
    let scope = it.open_scope();
    let r = apply_in(it, text, commit, None);
    it.close_scope(scope);
    let (report, retired) = r?;
    if commit {
        it.code_events.push(crate::persist::CodeEvent::Patch { text: text.to_owned(), retired, added: report.added as u32 });
    }
    Ok(report)
}

/// Replays a committed patch while rebuilding a VM's code (a checkpoint
/// restore, a worker): the old bodies it retired move to the same new ids,
/// and no frame is walked, since the restored frames already name them.
pub(crate) fn replay(it: &mut Interp, text: &str, retired: &[u32]) -> Result<(), String> {
    let scope = it.open_scope();
    let r = apply_in(it, text, true, Some(retired));
    it.close_scope(scope);
    r.map(|_| ())
}

fn apply_in(it: &mut Interp, text: &str, commit: bool, replaying: Option<&[u32]>) -> Result<(Report, Vec<u32>), String> {
    let header = header(text)?;
    let running = it.hot.modules.get(header.module).cloned().ok_or_else(|| format!("module {} is not loaded", header.module))?;
    if it.jit_threshold != 0 || it.entries.iter().any(|&p| p != 0) {
        return Err("hot reload requires the interpreter or heap-frame entries, as dynamic image loading does".into());
    }
    let parsed = crate::image::parse(it, header.image, Some(&running.shapes))?;
    if parsed.modules.len() != 1 || parsed.modules[0].0 != header.module {
        return Err(format!("a patch for {} must hold that module alone", header.module));
    }
    if header.map.len() != parsed.funcs.len() {
        return Err(format!("patch map names {} functions for an image of {}", header.map.len(), parsed.funcs.len()));
    }
    // Where each new function lands: its matched id, or the next free one.
    let first_new = it.funcs.len() as u32;
    let mut seen = vec![false; running.fids.len()];
    let mut target = Vec::with_capacity(parsed.funcs.len());
    let mut added = 0u32;
    for entry in &header.map {
        match *entry {
            Some(old) => {
                let fid = *running.fids.get(old).ok_or_else(|| format!("patch maps to function {old} of {} the module never had", running.fids.len()))?;
                if std::mem::replace(&mut seen[old], true) { return Err(format!("patch maps two functions to {}", it.funcs[fid as usize].name)); }
                target.push(fid);
            }
            None => { target.push(first_new + added); added += 1; }
        }
    }
    let base = parsed.base;
    let mut funcs = parsed.funcs;
    let n = funcs.len() as u32;
    let to = |f: u32| -> Result<u32, String> {
        f.checked_sub(base).filter(|&i| i < n).map(|i| target[i as usize]).ok_or_else(|| format!("patch refers to function {f} outside itself"))
    };
    for f in &mut funcs {
        for op in &mut f.code { remap(op, &to)?; }
        for k in &mut f.consts { if let Some(fid) = k.as_func() { *k = Value::func(to(fid)?); } }
    }
    let total = it.funcs.len() + added as usize;
    for f in &funcs { crate::verify::verify_classes(f, total).map_err(|e| format!("function {}: {e}", f.name))?; }

    let old_captures = captures(running.fids.iter().map(|&fid| &it.funcs[fid as usize]));
    let new_captures = captures(funcs.iter());
    let mut report = Report { added: added as usize, ..Report::default() };
    let mut changed = Vec::new();
    for (i, f) in funcs.iter().enumerate() {
        let fid = target[i];
        if fid >= first_new { continue; }
        let old = &it.funcs[fid as usize];
        if old.nparams != f.nparams || old.sig != f.sig || old.ret != f.ret || old.vararg != f.vararg {
            return Err(format!("callable signature changed: {}", old.name));
        }
        if let (Some(a), Some(b)) = (old_captures.get(&fid), new_captures.get(&fid)) {
            if a != b { return Err(format!("captured bindings changed: {}", old.name)); }
        }
        if same_code(it, old, f) {
            if old.debug != f.debug { report.moved += 1; }
            continue;
        }
        if it.linked_frames.get(fid as usize).is_some_and(|&p| p != 0) {
            return Err(format!("{} runs linked native code and cannot be replaced", old.name));
        }
        changed.push(fid);
    }
    report.changed = changed.len();
    let changing: std::collections::HashSet<u32> = changed.iter().copied().collect();
    let frames = if replaying.is_some() { Vec::new() } else { live_frames(it, &changing) };
    let mut retired: Vec<u32> = match replaying {
        Some(list) => list.to_vec(),
        None => { let mut v: Vec<u32> = frames.iter().map(|&(_, _, fid)| fid).collect(); v.sort_unstable(); v.dedup(); v }
    };
    retired.retain(|fid| changing.contains(fid));
    report.retained = frames.len();
    if !commit {
        report.generation = it.hot.generation;
        return Ok((report, retired));
    }

    // Nothing below can fail: the patch is published whole.
    let mut new_bodies: HashMap<u32, Function> = HashMap::new();
    let mut appended = Vec::new();
    for (i, f) in funcs.into_iter().enumerate() {
        let fid = target[i];
        if fid >= first_new { appended.push(f); } else { new_bodies.insert(fid, f); }
    }
    for f in appended { it.funcs.push(f); }
    let mut moved_to: HashMap<u32, u32> = HashMap::new();
    for (&fid, f) in new_bodies.iter_mut() {
        if !changing.contains(&fid) {
            // Same code: only the source positions follow the edit.
            std::mem::swap(&mut it.funcs[fid as usize].debug, &mut f.debug);
        }
    }
    for &fid in &changed {
        let body = new_bodies.remove(&fid).expect("changed body");
        let old = std::mem::replace(&mut it.funcs[fid as usize], body);
        if retired.binary_search(&fid).is_ok() {
            moved_to.insert(fid, it.funcs.len() as u32);
            it.funcs.push(old);
        }
    }
    for &(tid, s, fid) in &frames {
        if let Some(&to) = moved_to.get(&fid) {
            let stack = &mut it.tasks[tid].stack;
            stack[s] = (stack[s] & !0xffff_ffff) | to as u64;
        }
    }
    for &fid in &changed { it.invalidate_function(fid); }
    for f in &it.funcs[first_new as usize..] {
        it.frame_required |= f.code.iter().any(|op| matches!(op, Op::Defer(..) | Op::DeferMethod(..) | Op::AffineEnter) || crate::native_simd::required(op));
    }
    for &fid in &changed {
        let f = &it.funcs[fid as usize];
        it.frame_required |= f.code.iter().any(|op| matches!(op, Op::Defer(..) | Op::DeferMethod(..) | Op::AffineEnter) || crate::native_simd::required(op));
    }
    it.entries.resize(it.funcs.len(), 0);
    if it.threaded { it.prepare_threaded(); }
    it.hot.modules.insert(header.module.to_string(), ModuleCode { fids: target, shapes: parsed.shape_ids });
    it.hot.generation += 1;
    report.generation = it.hot.generation;
    Ok((report, retired))
}
