//! Runtime specialization and controlled deoptimization (runtime plan, JIT,
//! "Specialization and deoptimization"; contracts 2.7).
//!
//! Three stages share this module:
//!
//! 1. **Feedback.** A bounded record per dynamic site (`Site`): up to three
//!    observed keys (a call target's function id, a receiver's shape or
//!    metatable) with counts, and an overflow count past them. The
//!    interpreter, the threaded core and instrumented baseline code fill it.
//!    It lives beside the VM, never in its heap: the collector does not walk
//!    it, checkpoints and snapshots do not see it, and a restored VM starts
//!    with none. A key may name an object that has since died; a plan only
//!    ever uses a key after re-deriving what it means from live state.
//! 2. **Guarded specialization.** `plan` turns feedback into a `Plan` the
//!    typed tier compiles a function version from: a monomorphic call site
//!    becomes a guarded direct call, a method site guards the receiver's
//!    shape (or metatable) and calls the method the plan resolved, a field
//!    site guards shapes and reads the slot at a fixed offset. A failed guard
//!    notes the miss and takes the generic helper in place. Every guard is
//!    re-checked at every execution, and method resolution depends only on
//!    state that bumps `Heap::proto_epoch` when it changes (shape methods, any
//!    table an `__index` lookup walked, the free of such a table), which each
//!    method site compares, so no assumption outlives a mutation, a reentrant
//!    call or a suspension. Versions per function and misses per version are
//!    capped; a function past its cap settles on its generic entry.
//! 3. **Deoptimization.** On the heap-frame path (`frame.rs`), a specialized
//!    entry's guard failure leaves through a deopt exit: every live value is
//!    written to the heap frame by its recipe, and the entry returns the pc of
//!    the guarded operation, which the interpreter then executes generically.
//!    Since the guard precedes every effect of its operation, nothing is
//!    repeated; cleanups and protected calls are runtime state the frame
//!    already owns. That is what lets a specialized frame entry keep facts
//!    past a guard (a register's proven shape) instead of merging back into
//!    the generic path.
use std::collections::HashMap;

use crate::heap::{SlotTy, F_METATABLE, KIND_CLOSURE, KIND_RECORD, KIND_TABLE};
use crate::interp::{Interp, Op};
use crate::value::Value;

/// Observed keys a site keeps before counting the rest as overflow.
pub const KEYS: usize = 3;
const TAG: u64 = 0xf << 60;
/// A closure of the function id in the low bits.
pub const K_FN: u64 = 1 << 60;
/// A bare function value (no closure) of the function id.
pub const K_BARE: u64 = 2 << 60;
pub const K_BUILTIN: u64 = 3 << 60;
/// A record of the shape in the low bits, with no metatable of its own.
pub const K_SHAPE: u64 = 4 << 60;
/// A table whose metatable's address is the low bits.
pub const K_META: u64 = 5 << 60;
/// A table with no metatable.
pub const K_TABLE: u64 = 6 << 60;
/// A record with a metatable of its own (the Lua class idiom over a
/// constructor's shape): the metatable's address over 3, shifted past the
/// shape's low 16 bits. A key that does not fit only aliases: guards compare
/// the live metatable, never the key.
pub const K_RMETA: u64 = 7 << 60;
pub const K_OTHER: u64 = 8 << 60;
/// Where a record's metatable is: its `RecordExtra` box follows the slots and
/// the ordered children's `Vec`; the metatable sits after the overflow table.
pub const RECORD_EXTRA_OFFSET: usize = crate::heap::HEADER + std::mem::size_of::<Vec<Value>>();
pub const EXTRA_META_OFFSET: usize = std::mem::offset_of!(crate::heap::RecordExtra, meta);
pub const EXTRA_FIELDS_PTR_OFFSET: usize = std::mem::offset_of!(crate::heap::RecordExtra, fields) + std::mem::offset_of!(crate::heap::ValueTable, ptr);
pub const EXTRA_FIELDS_MASK_OFFSET: usize = std::mem::offset_of!(crate::heap::RecordExtra, fields) + std::mem::offset_of!(crate::heap::ValueTable, mask);

/// A metatabled record's key.
pub fn rmeta_key(meta: Value, shape: u32) -> u64 { K_RMETA | ((((meta.0 & crate::value::PAYLOAD) >> 3) << 16) & !TAG) | (shape as u64 & 0xffff) }
/// The shape a receiver key names, for a field site.
fn key_shape(key: u64) -> Option<u32> {
    match key & TAG { K_SHAPE => Some((key & !TAG) as u32), K_RMETA => Some((key & 0xffff) as u32), _ => None }
}

/// One site's feedback. The layout is read by compiled code: keys at 0,
/// counts at 24, overflow at 36.
#[repr(C)]
#[derive(Clone, Copy, Default, Debug)]
pub struct Site { pub keys: [u64; KEYS], pub counts: [u32; KEYS], pub overflow: u32 }

impl Site {
    #[inline]
    pub fn record(&mut self, key: u64) {
        for i in 0..KEYS {
            if self.keys[i] == key { self.counts[i] = self.counts[i].saturating_add(1); return; }
            if self.keys[i] == 0 { self.keys[i] = key; self.counts[i] = 1; return; }
        }
        self.overflow = self.overflow.saturating_add(1);
    }
    /// The keys seen, when no more than `KEYS` were.
    pub fn seen(&self) -> Option<Vec<u64>> {
        if self.overflow != 0 || self.keys[0] == 0 { return None; }
        Some(self.keys.iter().copied().take_while(|&k| k != 0).collect())
    }
    pub fn mono(&self) -> Option<u64> { self.seen().filter(|k| k.len() == 1).map(|k| k[0]) }
}

/// The operations feedback is kept for.
pub fn is_site(op: &Op) -> bool { matches!(op, Op::CallDyn(..) | Op::CallK(..) | Op::CallMethod(..) | Op::GetField(..) | Op::SetField(..)) }

/// A function's feedback and specialization record. `calls` and `misses` are
/// at fixed offsets compiled code increments.
#[repr(C)]
pub struct FuncFeedback {
    /// Entries counted by instrumented baseline code, or frame entries.
    pub calls: u32,
    /// Guard failures in the current specialized version.
    pub misses: u32,
    /// Deopt exits taken by the current specialized frame entry.
    pub deopts: u32,
    /// The direct entry's versions (`DIRECT`) and the heap-frame entry's
    /// (`FRAME`): a function may run both ways in one VM, and each settles on
    /// its own.
    pub kinds: [Versions; 2],
    pub site_of: Box<[u32]>,
    pub sites: Box<[Site]>,
}

pub const DIRECT: usize = 0;
pub const FRAME: usize = 1;

/// One entry kind's versions of a function.
#[derive(Clone, Copy, Debug, Default)]
pub struct Versions {
    /// Entries counted by the driver (heap-frame entries only; direct
    /// entries count in `FuncFeedback::calls`).
    pub entries: u32,
    /// Specialized versions compiled; capped by `Limits::max_versions`.
    pub specialized: u8,
    /// Past its caps: the generic entry from now on.
    pub settled: bool,
    /// The installed entry is a specialized one.
    pub active: bool,
    /// The generic entry, kept to return to.
    pub baseline: u64,
}

impl FuncFeedback {
    pub fn kind(&self, frame: bool) -> &Versions { &self.kinds[frame as usize] }
    pub fn kind_mut(&mut self, frame: bool) -> &mut Versions { &mut self.kinds[frame as usize] }
}

pub const NO_SITE: u32 = u32::MAX;

#[derive(Clone, Copy, Debug)]
pub struct Limits {
    /// Calls (or frame entries) before a function is specialized.
    pub tier_calls: u32,
    /// Specialized versions a function may have over its life.
    pub max_versions: u8,
    /// Guard misses a specialized version tolerates before it is replaced.
    pub miss_limit: u32,
    /// Deopt exits a specialized frame entry tolerates before it is replaced.
    pub deopt_limit: u32,
    /// Bytes of feedback across the VM (records, sites and pc maps); past
    /// it, functions get no feedback.
    pub max_bytes: usize,
    /// `JIT_SPEC_CHAOS`: every n-th specialized site execution fails its
    /// guard on purpose; 0 is off.
    pub chaos: u64,
}

impl Default for Limits {
    fn default() -> Self {
        let n = |k: &str, d: u64| std::env::var(k).ok().and_then(|s| s.parse().ok()).unwrap_or(d);
        Limits { tier_calls: n("JIT_SPEC_CALLS", 1000) as u32, max_versions: n("JIT_SPEC_VERSIONS", 3) as u8, miss_limit: n("JIT_SPEC_MISSES", 1000) as u32, deopt_limit: n("JIT_SPEC_DEOPTS", 100) as u32, max_bytes: n("JIT_SPEC_BYTES", 8 << 20) as usize, chaos: n("JIT_SPEC_CHAOS", 0) }
    }
}

#[derive(Clone, Copy, Debug, Default)]
pub struct Stats {
    pub tier_ups: u64,
    pub versions: u64,
    pub sites: u64,
    pub misses: u64,
    pub deopts: u64,
    pub settled: u64,
    pub invalidated: u64,
}

/// The VM's specialization state. Transient: never saved, never traced.
pub struct State {
    /// Collect feedback on the interpreter and in instrumented code.
    pub feedback: bool,
    /// Compile specialized versions from it.
    pub specialize: bool,
    pub limits: Limits,
    pub funcs: Vec<Option<Box<FuncFeedback>>>,
    /// Functions the byte budget refused: never retried.
    pub refused: Vec<bool>,
    pub sites: usize,
    /// Bytes the records, their sites and pc maps hold.
    pub bytes: usize,
    /// Versions compiled so far: each one's symbol suffix, unique for the
    /// VM's life even when a function's record is dropped and remade.
    pub symbols: u32,
    pub stats: Stats,
    /// The chaos counter (`Plan::chaos_addr`), when the mode is on.
    pub chaos: Option<Box<u64>>,
}

impl Default for State {
    fn default() -> Self {
        let specialize = std::env::var_os("JIT_SPECIALIZE").is_some_and(|v| v != "0");
        let feedback = specialize || std::env::var_os("JIT_FEEDBACK").is_some_and(|v| v != "0");
        State { feedback, specialize, limits: Limits::default(), funcs: Vec::new(), refused: Vec::new(), sites: 0, bytes: 0, symbols: 0, stats: Stats::default(), chaos: None }
    }
}

impl State {
    /// The function's record, made on first use while the site budget lasts.
    pub fn func(&mut self, fid: u32, code: &[Op]) -> Option<&mut FuncFeedback> {
        let i = fid as usize;
        if self.funcs.len() <= i { self.funcs.resize_with(i + 1, || None); self.refused.resize(i + 1, false); }
        if self.funcs[i].is_none() {
            if self.refused[i] { return None; }
            // The whole cost is known from the code before anything is made.
            let n = code.iter().filter(|op| is_site(op)).count();
            let bytes = Self::cost(code.len(), n);
            if self.bytes + bytes > self.limits.max_bytes { self.refused[i] = true; return None; }
            let mut site_of = vec![NO_SITE; code.len()].into_boxed_slice();
            let mut k = 0u32;
            for (pc, op) in code.iter().enumerate() { if is_site(op) { site_of[pc] = k; k += 1; } }
            self.sites += n;
            self.bytes += bytes;
            self.funcs[i] = Some(Box::new(FuncFeedback { calls: 0, misses: 0, deopts: 0, kinds: [Versions::default(); 2], site_of, sites: vec![Site::default(); n as usize].into_boxed_slice() }));
        }
        self.funcs[i].as_deref_mut()
    }
    /// What a function's record costs: itself, its sites and its pc map.
    pub fn cost(code_len: usize, sites: usize) -> usize { std::mem::size_of::<FuncFeedback>() + sites * std::mem::size_of::<Site>() + code_len * std::mem::size_of::<u32>() }
    pub fn get(&self, fid: u32) -> Option<&FuncFeedback> { self.funcs.get(fid as usize).and_then(|f| f.as_deref()) }
    /// The site record at a pc, if the function has feedback there.
    pub fn site(&self, fid: u32, pc: usize) -> Option<&Site> {
        let f = self.get(fid)?;
        let s = *f.site_of.get(pc)?;
        (s != NO_SITE).then(|| &f.sites[s as usize])
    }
}

// ---- keys -----------------------------------------------------------------

/// What a call site called.
pub fn target_key(v: Value) -> u64 {
    if let Some(f) = v.as_func() { return K_BARE | f as u64; }
    if let Some(b) = v.as_builtin() { return K_BUILTIN | b as u64; }
    match v.as_obj() {
        Some(p) => { let h = unsafe { p.as_ref() }; if h.kind == KIND_CLOSURE { K_FN | h.fid() as u64 } else { K_OTHER | h.kind as u64 } }
        None => K_OTHER,
    }
}

/// What a method or field site's receiver was.
pub fn receiver_key(v: Value) -> u64 {
    match v.as_obj() {
        Some(p) => {
            let h = unsafe { p.as_ref() };
            match h.kind {
                KIND_RECORD if h.flags & F_METATABLE != 0 => match h.record_extra_ref() { Some(extra) => rmeta_key(extra.meta, h.shape()), None => K_SHAPE | h.shape() as u64 },
                KIND_RECORD => K_SHAPE | h.shape() as u64,
                KIND_TABLE => { let m = h.table_ref().meta; if m == Value::NIL { K_TABLE } else { K_META | (m.0 & crate::value::PAYLOAD) } }
                k => K_OTHER | k as u64,
            }
        }
        None => K_OTHER,
    }
}

// ---- collection -----------------------------------------------------------

/// Records the key at (fid, pc).
pub fn note(it: &mut Interp, fid: u32, pc: usize, key: u64) {
    let Some(code) = it.funcs.get(fid as usize).map(|f| &f.code) else { return };
    if let Some(ff) = it.spec.func(fid, code) {
        if let Some(&s) = ff.site_of.get(pc) { if s != NO_SITE { ff.sites[s as usize].record(key); } }
    }
}

/// The interpreter's hook, called before `op` at `pc` executes with the
/// frame's value window at `regs`.
#[inline(never)]
pub fn observe(it: &mut Interp, fid: u32, pc: usize, op: Op, regs: *const Value) {
    let r = |i: u8| unsafe { *regs.add(i as usize) };
    let key = match op {
        Op::CallDyn(fr, ..) | Op::CallK(_, fr, ..) => target_key(r(fr)),
        Op::CallMethod(_, b, _) => receiver_key(r(b + 1)),
        Op::GetField(_, t, _) | Op::SetField(t, _, _) => receiver_key(r(t)),
        _ => return,
    };
    note(it, fid, pc, key)
}

/// The threaded core's hook: `kind` 0 is a call target, 1 a receiver.
#[unsafe(no_mangle)]
pub extern "C" fn rt_observe(interp: *mut std::ffi::c_void, fid: u32, pc: u32, value: u64, kind: u32) {
    let it = unsafe { &mut *(interp as *mut Interp) };
    let v = Value(value);
    let key = if kind == 0 { target_key(v) } else { receiver_key(v) };
    note(it, fid, pc as usize, key)
}

// ---- plans ----------------------------------------------------------------

/// How a method site's receiver is recognized.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Guard {
    /// A record of the shape: its method comes from the shape's descriptor.
    Shape(u32),
    /// A table whose metatable is at the address and that has no field of the
    /// method's name itself: its method comes through the `__index` chain.
    Meta(u64),
    /// A record of the shape with that metatable of its own, whose slot of
    /// the method's name (if its shape has one) is nil and whose overflow
    /// lacks the name: also through the chain.
    RecordMeta { shape: u32, meta: u64, slot: Option<u16>, nslots: u32 },
}

#[derive(Clone, Copy, Debug)]
pub struct MethodCase {
    pub guard: Guard,
    /// The method value the plan resolved, live while the epoch holds.
    pub method: Value,
    /// Its function, called through its compiled entry when it has one, and
    /// that function's parameter count.
    pub fid: u32,
    pub nparams: u8,
}

#[derive(Clone, Debug)]
pub enum SiteSpec {
    /// `CallMethod`: the receiver cases, tried in order.
    Method(Vec<MethodCase>),
    /// `CallDyn`: the callee is a closure (or, `bare`, a function value) of `fid`.
    Target { fid: u32, bare: bool, nparams: u8 },
    /// `GetField`: (shape, slot) cases.
    Field(Vec<(u32, u16)>),
    /// `SetField`: one shape's slot, and whether the slot is declared a number.
    Store { shape: u32, slot: u16, number: bool },
}

/// What baseline code is instrumented with.
#[derive(Clone, Debug)]
pub struct Hooks {
    /// `&FuncFeedback`: its `calls` and `misses` are at offsets 0 and 4.
    pub func_addr: i64,
    /// `&sites[0]`.
    pub sites_addr: i64,
    pub site_of: Vec<u32>,
    pub tier_calls: u32,
}

/// The input to one compiled version of a function.
#[derive(Clone, Debug, Default)]
pub struct Plan {
    /// Keeps the version's symbols apart from the function's others.
    pub version: u32,
    pub sites: HashMap<usize, SiteSpec>,
    /// `Heap::proto_epoch` when the plan resolved its methods, and where it is.
    pub epoch: u64,
    pub epoch_addr: i64,
    /// `Heap::marking`, for the barrier a specialized store takes.
    pub marking_addr: i64,
    pub hooks: Option<Hooks>,
    /// A heap-frame entry: guard failures leave through deopt exits.
    pub deopt: bool,
    /// `JIT_SPEC_CHAOS=n`: the counter every specialized site decrements,
    /// failing its guard when it reaches zero (then reset to `chaos_period`);
    /// zero when off. A test mode: it makes every miss and exit path run.
    pub chaos_addr: i64,
    pub chaos_period: u64,
}

fn plain(f: &crate::interp::Function) -> bool { f.sig.iter().all(|&c| c == b'v') && f.ret != b'f' && !f.vararg && f.nparams <= 8 }

impl Interp {
    /// The function a method value runs, when it is one with a plain
    /// compiled calling convention.
    fn method_fid(&self, m: Value) -> Option<u32> {
        let fid = match m.as_func() { Some(f) => f, None => { let p = m.as_obj()?; let h = unsafe { p.as_ref() }; if h.kind != KIND_CLOSURE { return None; } h.fid() } };
        plain(self.funcs.get(fid as usize)?).then_some(fid)
    }
    /// The live table at a key's address, or None: a key may outlive its object.
    fn live_table(&self, addr: u64) -> Option<Value> {
        let v = Value(crate::value::QNAN | crate::value::T_OBJ | (addr & crate::value::PAYLOAD));
        let p = v.as_obj()?;
        if !self.heap.is_live_slot(p) || unsafe { p.as_ref() }.kind != KIND_TABLE { return None; }
        Some(v)
    }
    /// What `recv:name()` calls for a table whose metatable is `meta` and
    /// which has no field `name` of its own, by the same walk the interpreter
    /// caches (`index_through_metatable`), which also flags every table it
    /// walked so that a store to any of them bumps the epoch.
    fn method_through(&mut self, meta: Value, name: Value) -> Option<Value> {
        if self.kind_of(meta) != Some(KIND_TABLE) { return None; }
        let scope = self.open_scope();
        self.handles.extend_from_slice(&[meta, name]);
        let probe = self.new_table();
        self.handles.push(probe);
        unsafe { (*probe.as_obj().unwrap().as_ptr()).table().meta = meta; }
        let answer = self.index_through_metatable(probe, name);
        let weak = answer.is_some() && self.walks_weak(probe, name);
        unsafe { (*probe.as_obj().unwrap().as_ptr()).table().meta = Value::NIL; }
        self.close_scope(scope);
        if weak { return None; }
        answer.filter(|v| *v != Value::NIL)
    }
    /// Whether the `__index` walk from `object` for `name` visits a weak
    /// table (a metatable or an `__index` table whose own metatable has a
    /// `__mode`). Such chains are not specialized (design, section 4): the
    /// collector may clear the method while every guard still holds.
    fn walks_weak(&mut self, object: Value, name: Value) -> bool {
        let weak = |it: &Interp, v: Value| v.as_obj().is_some_and(|p| { let h = unsafe { p.as_ref() }; h.kind == KIND_TABLE && it.heap.weak_mode(h) != 0 });
        let mut object = object;
        for _ in 0..100 {
            let meta = self.mm_table(object);
            if weak(self, meta) { return true; }
            let handler = self.metamethod(object, crate::metamethods::MM::Index);
            if handler == Value::NIL { return false; }
            if weak(self, handler) { return true; }
            if !matches!(self.kind_of(handler), Some(KIND_TABLE | KIND_RECORD)) { return false; }
            if self.get_index(handler, name) != Value::NIL { return false; }
            object = handler;
        }
        true
    }

    fn plan_site(&mut self, fid: u32, pc: usize, op: Op, frame: bool) -> Option<SiteSpec> {
        let site = *self.spec.site(fid, pc)?;
        let consts = &self.funcs[fid as usize].consts;
        match op {
            Op::CallMethod(k, _, nargs) if !frame && nargs < 64 => {
                let name = consts[k as usize];
                let mut cases = Vec::new();
                for key in site.seen()? {
                    let (guard, method) = match key & TAG {
                        K_SHAPE => { let s = (key & !TAG) as u32; (Guard::Shape(s), *self.heap.shapes.get(s as usize)?.methods.get(&name)?) }
                        K_META => {
                            // The key's address is re-derived from a live object or not used.
                            let meta = self.live_table(key & !TAG)?;
                            (Guard::Meta(meta.0), self.method_through(meta, name)?)
                        }
                        K_RMETA => {
                            let s = (key & 0xffff) as u32;
                            let meta = self.live_table(((key & !TAG) >> 16) << 3)?;
                            let sh = self.heap.shapes.get(s as usize)?;
                            if sh.methods.contains_key(&name) { return None; }
                            let (slot, nslots) = (sh.slot_of(name).map(|i| i as u16), sh.names.len() as u32);
                            (Guard::RecordMeta { shape: s, meta: meta.0, slot, nslots }, self.method_through(meta, name)?)
                        }
                        _ => return None,
                    };
                    let fid = self.method_fid(method)?;
                    cases.push(MethodCase { guard, method, fid, nparams: self.funcs[fid as usize].nparams });
                }
                Some(SiteSpec::Method(cases))
            }
            Op::CallDyn(_, _, nargs) if !frame && nargs < 64 => {
                let key = site.mono()?;
                let (fid, bare) = match key & TAG { K_FN => ((key & !TAG) as u32, false), K_BARE => ((key & !TAG) as u32, true), _ => return None };
                let callee = self.funcs.get(fid as usize)?;
                plain(callee).then_some(SiteSpec::Target { fid, bare, nparams: callee.nparams })
            }
            Op::GetField(_, _, k) => {
                let name = consts[k as usize];
                let mut cases = Vec::new();
                for key in site.seen()? {
                    let s = key_shape(key)?;
                    let case = (s, self.heap.shapes.get(s as usize)?.slot_of(name)? as u16);
                    if !cases.contains(&case) { cases.push(case); }
                }
                Some(SiteSpec::Field(cases))
            }
            Op::SetField(_, k, _) => {
                let name = consts[k as usize];
                let mut shapes = site.seen()?.into_iter().map(key_shape);
                let shape = shapes.next()??;
                if !shapes.all(|s| s == Some(shape)) { return None; }
                let sh = self.heap.shapes.get(shape as usize)?;
                let slot = sh.slot_of(name)?;
                let number = match sh.types[slot] { SlotTy::Any => false, SlotTy::Num => true, _ => return None };
                Some(SiteSpec::Store { shape, slot: slot as u16, number })
            }
            _ => None,
        }
    }

    /// The plan for a specialized version of `fid` from its feedback; None
    /// when no site would be specialized.
    pub fn spec_plan(&mut self, fid: u32, frame: bool) -> Option<Plan> {
        if self.spec.limits.chaos != 0 && self.spec.chaos.is_none() { self.spec.chaos = Some(Box::new(self.spec.limits.chaos)); }
        let code = self.funcs.get(fid as usize)?.code.clone();
        let mut sites = HashMap::new();
        for (pc, &op) in code.iter().enumerate() {
            if !is_site(&op) { continue; }
            if let Some(s) = self.plan_site(fid, pc, op, frame) { sites.insert(pc, s); }
        }
        if sites.is_empty() { return None; }
        self.spec.get(fid)?;
        self.spec.symbols += 1;
        Some(Plan { version: self.spec.symbols, sites, epoch: self.heap.proto_epoch, epoch_addr: &self.heap.proto_epoch as *const u64 as i64, marking_addr: &self.heap.marking as *const u8 as i64, hooks: None, deopt: frame, chaos_addr: self.spec.chaos.as_ref().map_or(0, |c| &**c as *const u64 as i64), chaos_period: self.spec.limits.chaos })
    }

    /// The plan for an instrumented generic version: feedback hooks only.
    pub fn spec_baseline_plan(&mut self, fid: u32) -> Option<Plan> {
        if !self.spec.specialize { return None; }
        let tier_calls = self.spec.limits.tier_calls;
        let code = &self.funcs.get(fid as usize)?.code;
        let ff = self.spec.func(fid, code)?;
        let hooks = Hooks { func_addr: &*ff as *const FuncFeedback as i64, sites_addr: ff.sites.as_ptr() as i64, site_of: ff.site_of.to_vec(), tier_calls };
        self.spec.symbols += 1;
        Some(Plan { version: self.spec.symbols, hooks: Some(hooks), epoch_addr: &self.heap.proto_epoch as *const u64 as i64, marking_addr: &self.heap.marking as *const u8 as i64, ..Plan::default() })
    }

    /// Records the generic entry an eager compile installed for `fid`.
    pub fn spec_installed(&mut self, fid: u32, entry: u64) {
        if let Some(ff) = self.spec.funcs.get_mut(fid as usize).and_then(|f| f.as_deref_mut()) { ff.kinds[DIRECT].baseline = entry; }
    }

    /// Drops what the VM learned about `fid` and every version specialized
    /// from it, for a body that changed (a hot patch): the next calls run its
    /// generic entry and feedback starts over.
    pub fn invalidate_specializations(&mut self, fid: u32) {
        let Some(slot) = self.spec.funcs.get_mut(fid as usize) else { return };
        let Some(ff) = slot.take() else { return };
        self.spec.sites -= ff.sites.len();
        self.spec.bytes -= State::cost(ff.site_of.len(), ff.sites.len());
        if let Some(r) = self.spec.refused.get_mut(fid as usize) { *r = false; }
        self.spec.stats.invalidated += 1;
        // A direct entry is only ever patched through its generic version
        // (hot reload refuses direct entries); a heap-frame entry is compiled
        // again from the new body on its next entry.
        if ff.kinds[DIRECT].active {
            if let Some(e) = self.entries.get_mut(fid as usize) { if ff.kinds[DIRECT].baseline != 0 { *e = ff.kinds[DIRECT].baseline; } }
        }
        #[cfg(feature = "compiled-runtime")]
        if let Some(e) = self.frame_entries.get_mut(fid as usize) { *e = 0; }
    }
}

// ---- tiering --------------------------------------------------------------

#[cfg(feature = "jit")]
impl Interp {
    fn spec_compile(&mut self, fid: u32, plan: Plan, frame: bool) -> Option<u64> {
        let mut jit = self.jit.take()?;
        jit.extra_addr = self.extra.as_ptr() as i64;
        jit.last_nres_addr = &self.last_nres as *const _ as i64;
        jit.entries_addr = self.entries.as_ptr() as i64;
        jit.calltab_addr = self.calltab.as_ptr() as i64;
        jit.probe_addr = self.shape_probe.as_ptr() as i64;
        jit.cur_closure_addr = crate::compiled::closure_address() as i64;
        jit.plan = Some(plan);
        let f = self.funcs[fid as usize].clone();
        let result = if frame { jit.compile_frame(&f, fid) } else { jit.try_compile(&f, fid) };
        jit.plan = None;
        self.jit = Some(jit);
        result.ok().map(|p| p as u64)
    }

    /// Compiles `fid`'s generic entry, instrumented when specialization is
    /// on: the lazy tier's compile.
    pub fn spec_compile_baseline(&mut self, fid: u32) -> Option<u64> {
        let plan = self.spec_baseline_plan(fid)?;
        let entry = self.spec_compile(fid, plan, false)?;
        if let Some(ff) = self.spec.funcs[fid as usize].as_deref_mut() { ff.kinds[DIRECT].baseline = entry; }
        Some(entry)
    }

    /// The specialized version from current feedback, installed as the
    /// function's entry; or, past the version cap or with nothing to
    /// specialize, the function settles on its generic entry.
    pub fn respecialize(&mut self, fid: u32, frame: bool) {
        let max = self.spec.limits.max_versions;
        let Some(ff) = self.spec.funcs.get_mut(fid as usize).and_then(|f| f.as_deref_mut()) else { return };
        if ff.kind(frame).settled { return; }
        ff.misses = 0; ff.deopts = 0;
        if ff.kind(frame).specialized >= max { return self.settle(fid, frame); }
        let Some(plan) = self.spec_plan(fid, frame) else { return self.settle(fid, frame) };
        let n = plan.sites.len() as u64;
        if std::env::var_os("JIT_SPEC_TRACE").is_some() {
            let mut sites: Vec<_> = plan.sites.iter().collect(); sites.sort_by_key(|(pc, _)| **pc);
            eprintln!("spec: {} v{} {}{}", self.funcs[fid as usize].name, plan.version, if frame { "frame " } else { "" }, sites.iter().map(|(pc, s)| format!("{pc}:{s:?}")).collect::<Vec<_>>().join(" "));
        }
        let Some(entry) = self.spec_compile(fid, plan, frame) else { return self.settle(fid, frame) };
        let ff = self.spec.funcs[fid as usize].as_deref_mut().unwrap();
        let v = ff.kind_mut(frame); v.specialized += 1; v.active = true;
        self.spec.stats.versions += 1; self.spec.stats.sites += n;
        if frame {
            #[cfg(feature = "compiled-runtime")]
            { self.frame_entries.resize(self.funcs.len(), 0); self.frame_entries[fid as usize] = entry; }
        } else {
            self.entries[fid as usize] = entry;
        }
    }

    fn settle(&mut self, fid: u32, frame: bool) {
        if std::env::var_os("JIT_SPEC_TRACE").is_some() { eprintln!("spec: {} {}settles", self.funcs[fid as usize].name, if frame { "frame " } else { "" }); }
        let Some(ff) = self.spec.funcs.get_mut(fid as usize).and_then(|f| f.as_deref_mut()) else { return };
        let v = ff.kind_mut(frame);
        v.settled = true;
        self.spec.stats.settled += 1;
        if !v.active { return; }
        v.active = false;
        let baseline = v.baseline;
        if baseline == 0 { return; }
        if frame {
            #[cfg(feature = "compiled-runtime")]
            { self.frame_entries[fid as usize] = baseline; }
        } else {
            self.entries[fid as usize] = baseline;
        }
    }

    /// Before a heap-frame entry runs: the first entry compiles the generic
    /// frame code, a hot one a specialized version.
    #[cfg(feature = "compiled-runtime")]
    pub(crate) fn spec_frame_entry(&mut self, fid: u32) {
        if !self.spec.specialize || self.jit.is_none() { return; }
        let tier = self.spec.limits.tier_calls;
        let code = &self.funcs[fid as usize].code;
        let Some(ff) = self.spec.func(fid, code) else { return };
        let v = ff.kind_mut(true);
        if v.settled { return; }
        v.entries = v.entries.saturating_add(1);
        let first = v.entries == 1;
        let hot = v.entries == tier;
        if first {
            self.frame_entries.resize(self.funcs.len(), 0);
            if self.frame_entries[fid as usize] == 0 {
                if let Some(mut plan) = self.spec_baseline_plan(fid) {
                    plan.deopt = true;
                    if let Some(hooks) = plan.hooks.as_mut() { hooks.tier_calls = 0; }
                    let entry = self.spec_compile(fid, plan, true).unwrap_or(u64::MAX);
                    self.frame_entries[fid as usize] = entry;
                    if let Some(ff) = self.spec.funcs[fid as usize].as_deref_mut() { ff.kinds[FRAME].baseline = entry; }
                }
            }
        }
        if hot { self.spec.stats.tier_ups += 1; self.respecialize(fid, true); }
    }
}

// ---- helpers compiled code calls ------------------------------------------

fn vm() -> &'static mut Interp { unsafe { &mut *crate::compiled::CTX.load(std::sync::atomic::Ordering::Relaxed) } }

/// Points the collector's walk of compiled frames at this helper's caller for
/// as long as the helper runs, as `compiled`'s helpers that may allocate do: a
/// helper that compiles a version may allocate while resolving methods.
struct HelperFrame(usize);
impl Drop for HelperFrame {
    fn drop(&mut self) { crate::compiled::HELPER_FP.store(self.0, std::sync::atomic::Ordering::Relaxed); }
}
#[inline(always)]
fn enter_helper() -> HelperFrame {
    let fp: usize;
    #[cfg(target_arch = "aarch64")]
    unsafe { std::arch::asm!("mov {}, x29", out(reg) fp) };
    #[cfg(target_arch = "x86_64")]
    unsafe { std::arch::asm!("mov {}, rbp", out(reg) fp) };
    #[cfg(not(any(target_arch = "aarch64", target_arch = "x86_64")))]
    { fp = 0; }
    HelperFrame(crate::compiled::HELPER_FP.swap(fp, std::sync::atomic::Ordering::Relaxed))
}

/// Instrumented baseline code reached its tier-up count.
#[unsafe(no_mangle)]
pub extern "C" fn j_spec_tier_up(fid: u64) -> u64 {
    let _frame = enter_helper();
    #[cfg(feature = "jit")]
    {
        let it = vm();
        it.spec.stats.tier_ups += 1;
        let _ = it.guarded(|it| { it.respecialize(fid as u32, false); Value::NIL });
    }
    let _ = fid;
    0
}

/// A specialized site's guard failed on `value`: the miss is counted and
/// recorded, and past the limit the function is specialized again (or
/// settles). The caller then takes the generic path itself.
#[unsafe(no_mangle)]
pub extern "C" fn j_spec_miss(fid: u64, pc: u64, value: u64) -> u64 {
    let _frame = enter_helper();
    let it = vm();
    it.spec.stats.misses += 1;
    let op = it.funcs[fid as usize].code[pc as usize];
    let key = match op { Op::CallDyn(..) | Op::CallK(..) => target_key(Value(value)), _ => receiver_key(Value(value)) };
    note(it, fid as u32, pc as usize, key);
    let limit = it.spec.limits.miss_limit;
    let Some(ff) = it.spec.funcs.get_mut(fid as usize).and_then(|f| f.as_deref_mut()) else { return 0 };
    ff.misses += 1;
    if ff.misses >= limit {
        #[cfg(feature = "jit")]
        { let _ = it.guarded(|it| { it.respecialize(fid as u32, false); Value::NIL }); }
    }
    0
}

/// A deopt exit: the frame holds every live value and the interpreter is
/// about to run the guarded operation at `pc`.
#[unsafe(no_mangle)]
pub extern "C" fn j_spec_deopt(fid: u64, pc: u64, value: u64) -> u64 {
    let _frame = enter_helper();
    let it = vm();
    it.spec.stats.deopts += 1;
    let key = receiver_key(Value(value));
    note(it, fid as u32, pc as usize, key);
    let limit = it.spec.limits.deopt_limit;
    let Some(ff) = it.spec.funcs.get_mut(fid as usize).and_then(|f| f.as_deref_mut()) else { return 0 };
    ff.deopts += 1;
    if ff.deopts >= limit {
        #[cfg(feature = "jit")]
        { let _ = it.guarded(|it| { it.respecialize(fid as u32, true); Value::NIL }); }
    }
    0
}

/// Instrumented `GetField` miss: the receiver noted, then the generic read.
#[unsafe(no_mangle)]
pub extern "C" fn j_spec_get_field(t: u64, name: u64, site: *mut Site) -> u64 {
    unsafe { (*site).record(receiver_key(Value(t))); }
    crate::compiled::j_get_field(t, name)
}

/// Instrumented `SetField`.
#[unsafe(no_mangle)]
pub extern "C" fn j_spec_set_field(t: u64, name: u64, v: u64, site: *mut Site) -> u64 {
    unsafe { (*site).record(receiver_key(Value(t))); }
    crate::compiled::j_set_field(t, name, v)
}

/// Instrumented `CallMethod`: the receiver is the first argument.
#[unsafe(no_mangle)]
pub extern "C" fn j_spec_call_method(name: u64, argv: *const u64, nargs: u64, site: *mut Site) -> u64 {
    if nargs & 63 > 0 { unsafe { (*site).record(receiver_key(Value(*argv))); } }
    crate::compiled::j_call_method(name, argv, nargs)
}

/// Instrumented dynamic call target, for a key the site has not seen first.
#[unsafe(no_mangle)]
pub extern "C" fn j_spec_note(site: *mut Site, key: u64) -> u64 {
    unsafe { (*site).record(key); }
    0
}

/// The store barrier a specialized slot store takes while marking.
#[unsafe(no_mangle)]
pub extern "C" fn j_spec_barrier(parent: u64, child: u64) -> u64 {
    let it = vm();
    if let Some(p) = Value(parent).as_obj() { it.heap.barrier(p, Value(child)); }
    0
}

/// The helpers this module adds to the typed tier's table.
pub fn helpers() -> Vec<(&'static str, *const u8, usize)> {
    vec![
        ("j_spec_tier_up", j_spec_tier_up as *const u8, 1),
        ("j_spec_miss", j_spec_miss as *const u8, 3),
        ("j_spec_deopt", j_spec_deopt as *const u8, 3),
        ("j_spec_get_field", j_spec_get_field as *const u8, 3),
        ("j_spec_set_field", j_spec_set_field as *const u8, 4),
        ("j_spec_call_method", j_spec_call_method as *const u8, 4),
        ("j_spec_note", j_spec_note as *const u8, 2),
        ("j_spec_barrier", j_spec_barrier as *const u8, 2),
    ]
}

/// A line for `JIT_SPEC_STATS=1`.
pub fn report(it: &Interp) -> String {
    let s = it.spec.stats;
    let functions = it.spec.funcs.iter().flatten().count();
    format!("spec: {functions} functions with feedback ({} sites, {} KiB); {} tier-ups, {} versions specializing {} sites, {} guard misses, {} deopts, {} settled, {} invalidated", it.spec.sites, it.spec.bytes / 1024, s.tier_ups, s.versions, s.sites, s.misses, s.deopts, s.settled, s.invalidated)
}

