//! Values, objects, shapes and the collector.
//!
//! NaN-boxed values: a double is itself; anything else lives in the quiet-NaN
//! space with a tag in bits 48..50 and a payload below. Heap objects are raw
//! pointers in that payload. The collector is a precise, incremental,
//! non-moving tri-colour mark-sweep with an insertion barrier, driven by
//! allocation debt at safepoints, with a stress mode that runs a whole cycle at
//! every allocation and an oracle that recomputes reachability from the roots
//! and compares it with what survived.

use std::collections::HashMap;
use std::hash::{BuildHasherDefault, Hasher};

/// Keys are value bits, interned strings by pointer, so a multiply-shift mix
/// is all a table needs.
/// FNV-1a over the bytes: the intern table's hasher, cheap on short strings.
#[derive(Default)]
pub struct StrHasher(u64);
impl Hasher for StrHasher {
    fn finish(&self) -> u64 { self.0 }
    fn write(&mut self, bytes: &[u8]) { let mut h = if self.0 == 0 { 0xcbf29ce484222325 } else { self.0 }; for &b in bytes { h ^= b as u64; h = h.wrapping_mul(0x100000001b3); } self.0 = h; }
}
#[derive(Default)]
pub struct BitsHasher(u64);
impl Hasher for BitsHasher {
    fn finish(&self) -> u64 { self.0 }
    fn write(&mut self, bytes: &[u8]) { for &b in bytes { self.0 = (self.0 ^ b as u64).wrapping_mul(0x9E3779B97F4A7C15); } }
    fn write_u64(&mut self, v: u64) { let x = v.wrapping_mul(0x9E3779B97F4A7C15); self.0 = x ^ (x >> 29); }
}
pub type ValueMap = HashMap<Value, Value, BuildHasherDefault<BitsHasher>>;
use std::ptr::NonNull;

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
#[repr(transparent)]
pub struct Value(pub u64);

const QNAN: u64 = 0x7ff8_0000_0000_0000;
const TAG_SHIFT: u64 = 48;
const TAG_MASK: u64 = 0x7 << TAG_SHIFT;
const PAYLOAD: u64 = (1 << 48) - 1;
const T_NIL: u64 = 1 << TAG_SHIFT;
const T_FALSE: u64 = 2 << TAG_SHIFT;
const T_TRUE: u64 = 3 << TAG_SHIFT;
const T_FUNC: u64 = 4 << TAG_SHIFT;
const T_OBJ: u64 = 5 << TAG_SHIFT;

impl std::hash::Hash for Value { fn hash<H: Hasher>(&self, h: &mut H) { h.write_u64(self.0) } }

impl Value {
    pub const NIL: Value = Value(QNAN | T_NIL);
    pub const FALSE: Value = Value(QNAN | T_FALSE);
    pub const TRUE: Value = Value(QNAN | T_TRUE);
    /// What a resumable compiled entry returns when the activation parked:
    /// its registers are in the frame record and its pc in the header.
    pub const PARKED: Value = Value(QNAN | (6 << TAG_SHIFT));
    /// A library function by id (`builtins::NAMES`).
    pub fn builtin(id: u32) -> Value { Value(QNAN | (7 << TAG_SHIFT) | id as u64) }
    pub fn as_builtin(self) -> Option<u32> { if !self.is_num() && self.0 & TAG_MASK == (7 << TAG_SHIFT) { Some((self.0 & PAYLOAD) as u32) } else { None } }
    pub fn num(x: f64) -> Value {
        let b = x.to_bits();
        // A real NaN is canonicalised so it never aliases a tag.
        if b & QNAN == QNAN { Value(QNAN) } else { Value(b) }
    }
    pub fn boolean(b: bool) -> Value { if b { Value::TRUE } else { Value::FALSE } }
    pub fn func(id: u32) -> Value { Value(QNAN | T_FUNC | id as u64) }
    pub fn obj(p: NonNull<Object>) -> Value { Value(QNAN | T_OBJ | (p.as_ptr() as u64 & PAYLOAD)) }
    pub fn is_num(self) -> bool { self.0 & QNAN != QNAN || self.0 == QNAN }
    pub fn as_num(self) -> f64 { f64::from_bits(self.0) }
    pub fn is_nil(self) -> bool { self == Value::NIL }
    pub fn truthy(self) -> bool { self != Value::NIL && self != Value::FALSE }
    pub fn as_func(self) -> Option<u32> { if !self.is_num() && self.0 & TAG_MASK == T_FUNC { Some((self.0 & PAYLOAD) as u32) } else { None } }
    pub fn as_obj(self) -> Option<NonNull<Object>> {
        if !self.is_num() && self.0 & TAG_MASK == T_OBJ { NonNull::new((self.0 & PAYLOAD) as *mut Object) } else { None }
    }
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
#[repr(u8)]
pub enum Color { White, Gray, Black }

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum SlotTy { Any, Num, Str, Bool, Record(u32) }

pub struct Shape {
    pub names: Vec<Value>, // interned strings
    pub types: Vec<SlotTy>,
    /// The descriptor: method name (interned) to function id.
    /// The descriptor: method name (interned) to the function value that runs it.
    pub methods: HashMap<Value, Value>,
}

pub enum Body {
    Str { text: Box<str>, hash: u64 },
    Table { array: Vec<Value>, hash: ValueMap },
    Record { shape: u32, slots: Vec<Value> },
    /// Owned numeric storage a typed span borrows: the non-moving space.
    Storage { data: Vec<f64> },
    /// Owned byte storage: a scratch buffer or a byte string under construction.
    Bytes { data: Vec<u8> },
    /// A closure: a function id and its captures, each a cell or a value.
    Closure { fid: u32, captures: Vec<Value> },
    /// A shared mutable location a captured local lives in.
    Cell { value: Value },
    /// Iteration state for `pairs` (1, over a key snapshot), `ipairs` (2) and
    /// `gmatch` (3, `pattern` holds the pattern string).
    Iter { kind: u8, obj: Value, pattern: Value, pos: usize, keys: Vec<Value> },
    Freed(String),
}

/// Object kinds as the header byte compiled code reads.
pub const KIND_STR: u8 = 1;
pub const KIND_TABLE: u8 = 2;
pub const KIND_RECORD: u8 = 3;
pub const KIND_STORAGE: u8 = 4;
pub const KIND_FREED: u8 = 0;
pub const KIND_CLOSURE: u8 = 5;
pub const KIND_CELL: u8 = 6;
pub const KIND_BYTES: u8 = 7;
pub const KIND_ITER: u8 = 8;
/// Objects per allocation chunk.
pub const CHUNK: usize = 1024;
pub static ALLOC_KINDS: std::sync::Mutex<[u64; 9]> = std::sync::Mutex::new([0; 9]);

/// The header has a fixed layout so compiled code reads an object's kind, the
/// pointer to its payload (slots, array part, storage, bytes) and that
/// payload's length at known offsets, with no runtime call.
#[repr(C)]
pub struct Object {
    pub kind: u8,
    pub color: Color,
    /// The cycle that last whitened or allocated this object: a white object
    /// from an earlier cycle is dead once marking has ended.
    pub epoch: u64,
    pub aux_ptr: *mut u8,
    pub aux_len: u64,
    pub bytes: usize,
    /// Whether the slot holds an object; a freed slot's body is dropped and
    /// the slot waits on the free list.
    pub used: bool,
    /// The slot's index in allocation order, for the free list and the sweep.
    pub slot: u32,
    pub body: Body,
}

pub const OFF_KIND: i32 = std::mem::offset_of!(Object, kind) as i32;
pub const OFF_AUX_PTR: i32 = std::mem::offset_of!(Object, aux_ptr) as i32;
pub const OFF_AUX_LEN: i32 = std::mem::offset_of!(Object, aux_len) as i32;

impl Object {
    /// Re-mirrors the payload pointer and length after the body changed.
    pub fn refresh(&mut self) {
        match &mut self.body {
            Body::Str { text, .. } => { self.kind = KIND_STR; self.aux_ptr = text.as_ptr() as *mut u8; self.aux_len = text.len() as u64; }
            Body::Table { array, .. } => { self.kind = KIND_TABLE; self.aux_ptr = array.as_mut_ptr() as *mut u8; self.aux_len = array.len() as u64; }
            Body::Record { shape, slots } => { self.kind = KIND_RECORD; self.aux_ptr = slots.as_mut_ptr() as *mut u8; self.aux_len = slots.len() as u64 | ((*shape as u64) << 32); }
            Body::Storage { data } => { self.kind = KIND_STORAGE; self.aux_ptr = data.as_mut_ptr() as *mut u8; self.aux_len = data.len() as u64; }
            Body::Bytes { data } => { self.kind = KIND_BYTES; self.aux_ptr = data.as_mut_ptr() as *mut u8; self.aux_len = data.len() as u64; }
            Body::Iter { keys, .. } => { self.kind = KIND_ITER; self.aux_ptr = keys.as_mut_ptr() as *mut u8; self.aux_len = keys.len() as u64; }
            Body::Closure { fid, captures } => { self.kind = KIND_CLOSURE; self.aux_ptr = captures.as_mut_ptr() as *mut u8; self.aux_len = captures.len() as u64 | ((*fid as u64) << 32); }
            Body::Cell { value } => { self.kind = KIND_CELL; self.aux_ptr = value as *mut Value as *mut u8; self.aux_len = 1; }
            Body::Freed(_) => { self.kind = KIND_FREED; self.aux_ptr = std::ptr::null_mut(); self.aux_len = 0; }
        }
    }
}

impl Object {
    pub fn str_text(&self) -> &str { if let Body::Str { text, .. } = &self.body { text } else { panic!("not a string") } }
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
enum Phase { Idle, Marking, Sweeping }

pub struct Heap {
    /// Object slots in fixed chunks that never move: the sweep walks them in
    /// order, a freed slot goes on the free list, allocation takes the free
    /// list first and bumps into the newest chunk otherwise.
    chunks: Vec<Box<[std::mem::MaybeUninit<Object>; CHUNK]>>,
    bump: usize,
    free: Vec<usize>,
    live_count: usize,
    gray: Vec<NonNull<Object>>,
    phase: Phase,
    sweep_index: usize,
    debt: usize,
    threshold: usize,
    pub live_bytes: usize,
    pub stress: bool,
    /// One small collector step at every allocation, so the mutator interleaves
    /// with marking at the finest grain; the oracle runs at every cycle end.
    pub stress_steps: bool,
    pub oracle: bool,
    pub quarantine: bool,
    pub shapes: Vec<Shape>,
    interned: HashMap<Box<str>, NonNull<Object>, BuildHasherDefault<StrHasher>>,
    pub stats: Stats,
}

#[derive(Default, Debug, Clone)]
pub struct Stats { pub cycles: u64, pub freed: u64, pub allocated: u64, pub barrier_grays: u64, pub steps: u64 }

/// Who can enumerate the roots: every task's registers, globals, handle scopes.
pub trait Roots { fn each_root(&self, f: &mut dyn FnMut(Value)); }

impl Heap {
    pub fn new() -> Heap {
        Heap { chunks: Vec::new(), bump: CHUNK, free: Vec::new(), live_count: 0, gray: Vec::new(), phase: Phase::Idle, sweep_index: 0, debt: 0, threshold: 1 << 20, live_bytes: 0, stress: false, stress_steps: false, oracle: false, quarantine: std::env::var("GC_QUARANTINE").is_ok(), shapes: Vec::new(), interned: HashMap::default(), stats: Stats::default() }
    }

    pub fn shape(&mut self, names: &[Value], types: &[SlotTy]) -> u32 {
        self.shapes.push(Shape { names: names.to_vec(), types: types.to_vec(), methods: HashMap::new() });
        (self.shapes.len() - 1) as u32
    }

    fn alloc_raw(&mut self, body: Body, bytes: usize) -> NonNull<Object> {
        if crate::builtins::STATS.load(std::sync::atomic::Ordering::Relaxed) { let k = match &body { Body::Str { .. } => 0, Body::Table { .. } => 1, Body::Record { .. } => 2, Body::Storage { .. } => 3, Body::Bytes { .. } => 4, Body::Closure { .. } => 5, Body::Cell { .. } => 6, Body::Iter { .. } => 7, Body::Freed(_) => 8 }; let mut c = ALLOC_KINDS.lock().unwrap(); c[k] += 1; }
        // New objects are allocated black while a cycle is in progress, so a
        // cycle never frees what it did not scan and a sweep in progress never
        // frees what was allocated after marking ended. The sweep whitens
        // them as it passes; white otherwise, as the next cycle will see them.
        let index = match self.free.pop() {
            Some(i) => i,
            None => {
                if self.bump == CHUNK { self.chunks.push(Box::new(unsafe { std::mem::MaybeUninit::uninit().assume_init() })); self.bump = 0; }
                self.bump += 1;
                (self.chunks.len() - 1) * CHUNK + self.bump - 1
            }
        };
        let p = self.slot(index);
        // A slot the sweep has already passed will not be whitened this
        // cycle, so an object allocated there is white; one ahead of the
        // sweep, or any during marking, is black so the cycle keeps it.
        let color = match self.phase { Phase::Idle => Color::White, Phase::Marking => Color::Black, Phase::Sweeping => if index < self.sweep_index { Color::White } else { Color::Black } };
        unsafe { p.as_ptr().write(Object { kind: 0, color, epoch: self.stats.cycles, aux_ptr: std::ptr::null_mut(), aux_len: 0, bytes, used: true, slot: index as u32, body }); (*p.as_ptr()).refresh(); }
        self.live_count += 1;
        self.live_bytes += bytes;
        self.debt += bytes;
        self.stats.allocated += 1;
        p
    }

    /// Allocation is a safepoint: the collector may run here, so every value
    /// the caller still needs must be reachable from the roots at this point.
    pub fn alloc(&mut self, body: Body, bytes: usize, roots: &dyn Roots) -> NonNull<Object> {
        self.safepoint(roots);
        self.alloc_raw(body, bytes)
    }

    pub fn intern(&mut self, s: &str, roots: &dyn Roots) -> Value {
        if let Some(&p) = self.interned.get(s) {
            // The intern table is weak, so a hit is a read through a non-root
            // edge and needs a barrier: while marking, a white hit is greyed so
            // the cycle keeps it; while sweeping, a white hit is already dead by
            // decision and must not be resurrected, so it is a miss.
            unsafe {
                match (self.phase, (*p.as_ptr()).color) {
                    (Phase::Marking, Color::White) => { (*p.as_ptr()).color = Color::Gray; self.gray.push(p); self.stats.barrier_grays += 1; return Value::obj(p); }
                    (Phase::Sweeping, Color::White) if (*p.as_ptr()).epoch < self.stats.cycles => { self.interned.remove(s); }
                    _ => return Value::obj(p),
                }
            }
        }
        let hash = { let mut h: u64 = 0xcbf29ce484222325; for b in s.bytes() { h ^= b as u64; h = h.wrapping_mul(0x100000001b3); } h };
        let p = self.alloc(Body::Str { text: s.into(), hash }, 32 + s.len(), roots);
        self.interned.insert(s.into(), p);
        Value::obj(p)
    }

    pub fn new_table_sized(&mut self, n: usize, m: usize, roots: &dyn Roots) -> Value { Value::obj(self.alloc(Body::Table { array: Vec::with_capacity(n), hash: ValueMap::with_capacity_and_hasher(m, Default::default()) }, 64 + 8 * n + 24 * m, roots)) }
    pub fn new_table(&mut self, roots: &dyn Roots) -> Value { Value::obj(self.alloc(Body::Table { array: Vec::new(), hash: ValueMap::default() }, 64, roots)) }
    pub fn new_record(&mut self, shape: u32, roots: &dyn Roots) -> Value {
        let n = self.shapes[shape as usize].names.len();
        Value::obj(self.alloc(Body::Record { shape, slots: vec![Value::NIL; n] }, 24 + 8 * n, roots))
    }
    pub fn new_closure(&mut self, fid: u32, captures: Vec<Value>, roots: &dyn Roots) -> Value { let n = captures.len(); Value::obj(self.alloc(Body::Closure { fid, captures }, 32 + 8 * n, roots)) }
    pub fn new_iter(&mut self, kind: u8, obj: Value, pattern: Value, keys: Vec<Value>, roots: &dyn Roots) -> Value { let n = keys.len(); Value::obj(self.alloc(Body::Iter { kind, obj, pattern, pos: 0, keys }, 48 + 8 * n, roots)) }
    pub fn new_cell(&mut self, value: Value, roots: &dyn Roots) -> Value { Value::obj(self.alloc(Body::Cell { value }, 32, roots)) }
    /// A growable buffer with room for a short result before it reallocates.
    pub fn new_buffer(&mut self, roots: &dyn Roots) -> Value { Value::obj(self.alloc(Body::Bytes { data: Vec::with_capacity(64) }, 24 + 64, roots)) }
    pub fn new_bytes(&mut self, n: usize, roots: &dyn Roots) -> Value { Value::obj(self.alloc(Body::Bytes { data: vec![0u8; n] }, 24 + n, roots)) }
    /// A string that is not interned (hash 0): long results, as Lua 5.4 treats them.
    pub fn new_string(&mut self, text: String, roots: &dyn Roots) -> Value { let n = text.len(); Value::obj(self.alloc(Body::Str { text: text.into_boxed_str(), hash: 0 }, 32 + n, roots)) }
    pub fn new_storage(&mut self, n: usize, roots: &dyn Roots) -> Value { Value::obj(self.alloc(Body::Storage { data: vec![0.0; n] }, 24 + 8 * n, roots)) }

    /// The insertion barrier: storing a white child into a black parent while
    /// marking greys the child. Every heap store goes through here.
    #[inline]
    pub fn barrier(&mut self, parent: NonNull<Object>, child: Value) {
        if self.phase != Phase::Marking { return; }
        if let Some(c) = child.as_obj() {
            unsafe {
                if (*parent.as_ptr()).color == Color::Black && (*c.as_ptr()).color == Color::White {
                    (*c.as_ptr()).color = Color::Gray;
                    self.gray.push(c);
                    self.stats.barrier_grays += 1;
                }
            }
        }
    }

    /// Where collection may run. Pays allocation debt with marking or sweeping
    /// work; under stress, runs a whole cycle every time.
    pub fn safepoint(&mut self, roots: &dyn Roots) {
        if self.stress {
            self.full_cycle(roots);
            if self.oracle { self.check_oracle(roots); }
            return;
        }
        if self.stress_steps {
            if self.phase == Phase::Idle { self.start(roots); }
            self.step(2, roots);
            if self.phase == Phase::Idle && self.oracle {
                // An interleaved cycle may leave floating garbage: objects
                // allocated black during the cycle that died before the sweep.
                // Safety is exact at this point; completeness is checked after
                // an atomic cycle, which nothing can float past.
                self.check_oracle_with(roots, false);
                self.full_cycle(roots);
                self.check_oracle_with(roots, true);
            }
            return;
        }
        if self.phase == Phase::Idle {
            if self.debt < self.threshold { return; }
            self.start(roots);
        }
        let budget = (self.debt / 64).max(256);
        self.step(budget, roots);
        self.debt = 0;
    }

    fn start(&mut self, roots: &dyn Roots) {
        self.phase = Phase::Marking;
        self.stats.cycles += 1;
        self.mark_roots(roots);
    }

    /// Whether `p` is a live object slot: inside a chunk, on a slot boundary,
    /// and in use. A register window a frame has not written yet can hold a
    /// word of another class from a frame that occupied the same stack
    /// region, which may decode as a pointer; the root walk is precise for
    /// written registers and this filter makes the unwritten ones harmless,
    /// at worst keeping an object alive one cycle longer.
    pub fn is_live_slot(&self, p: NonNull<Object>) -> bool {
        let addr = p.as_ptr() as usize;
        let size = std::mem::size_of::<std::mem::MaybeUninit<Object>>();
        for chunk in &self.chunks {
            let base = chunk.as_ptr() as usize;
            if addr >= base && addr < base + CHUNK * size {
                if (addr - base) % size != 0 { return false; }
                return unsafe { (*p.as_ptr()).used };
            }
        }
        false
    }

    fn mark_roots(&mut self, roots: &dyn Roots) {
        let mut cands: Vec<NonNull<Object>> = Vec::new();
        roots.each_root(&mut |v| { if let Some(p) = v.as_obj() { cands.push(p); } });
        for p in cands {
            if !self.is_live_slot(p) { continue; }
            unsafe { if (*p.as_ptr()).color == Color::White { (*p.as_ptr()).color = Color::Gray; self.gray.push(p); } }
        }
        let gray = &mut self.gray;
        // Shapes root their slot names and their method names and values.
        for s in &self.shapes { for &n in s.names.iter().chain(s.methods.keys()).chain(s.methods.values()) { if let Some(p) = n.as_obj() { unsafe { if (*p.as_ptr()).color == Color::White { (*p.as_ptr()).color = Color::Gray; gray.push(p); } } } } }
    }

    fn scan(&mut self, p: NonNull<Object>) {
        let gray = &mut self.gray;
        let mut push = |v: Value| { if let Some(c) = v.as_obj() { unsafe { if (*c.as_ptr()).color == Color::White { (*c.as_ptr()).color = Color::Gray; gray.push(c); } } } };
        unsafe {
            match &(*p.as_ptr()).body {
                Body::Table { array, hash } => { for &v in array { push(v); } for (&k, &v) in hash { push(k); push(v); } }
                Body::Record { slots, .. } => { for &v in slots { push(v); } }
                Body::Closure { captures, .. } => { for &v in captures { push(v); } }
                Body::Cell { value } => push(*value),
                Body::Iter { obj, pattern, keys, .. } => { push(*obj); push(*pattern); for &v in keys { push(v); } }
                Body::Str { .. } | Body::Storage { .. } | Body::Bytes { .. } | Body::Freed(_) => {}
            }
            (*p.as_ptr()).color = Color::Black;
        }
    }

    /// One increment of work. Marking drains grey objects; when none remain the
    /// roots are rescanned once (registers are not heap objects and carry no
    /// barrier) and, if still none, sweeping begins. Sweeping frees white
    /// objects and whitens black ones in slices.
    fn step(&mut self, mut budget: usize, roots: &dyn Roots) {
        self.stats.steps += 1;
        loop {
            match self.phase {
                Phase::Marking => {
                    while budget > 0 { match self.gray.pop() { Some(p) => { self.scan(p); budget -= 1; } None => break } }
                    if budget == 0 { return; }
                    self.mark_roots(roots);
                    if !self.gray.is_empty() { continue; }
                    self.phase = Phase::Sweeping;
                    self.sweep_index = 0;
                }
                Phase::Sweeping => {
                    // Slots in allocation order; the newest chunk only up to its bump.
                    let total = self.slot_count();
                    let mut i = self.sweep_index;
                    let mut work = budget * 4;
                    while i < total && work > 0 {
                        let p = self.slot(i);
                        if unsafe { (*p.as_ptr()).used } {
                            let color = unsafe { (*p.as_ptr()).color };
                            if color == Color::White { self.free(p); }
                            else { unsafe { (*p.as_ptr()).color = Color::White; (*p.as_ptr()).epoch = self.stats.cycles; } }
                            work -= 1;
                        }
                        i += 1;
                    }
                    self.sweep_index = i;
                    if i >= total { self.phase = Phase::Idle; self.threshold = (self.live_bytes * 2).max(1 << 20); }
                    return;
                }
                Phase::Idle => return,
            }
        }
    }

    fn free(&mut self, p: NonNull<Object>) {
        unsafe {
            let o = &mut *p.as_ptr();
            self.live_bytes -= o.bytes;
            self.stats.freed += 1;
            if let Body::Str { text, hash } = &o.body { if *hash != 0 { self.interned.remove(&**text); } }
            if self.stress || self.quarantine {
                // Under stress nothing is deallocated, so a dangling pointer is
                // detectable by the oracle instead of being undefined behaviour.
                let what = match &o.body { Body::Str { text, .. } => format!("string {:?}", String::from_utf8_lossy(&text.as_bytes()[..text.len().min(40)])), Body::Bytes { data } => format!("bytes {}", data.len()), Body::Table { array, hash } => format!("table[{}+{}]", array.len(), hash.len()), Body::Record { shape, .. } => format!("record shape {shape}"), Body::Storage { data } => format!("storage[{}]", data.len()), Body::Closure { fid, .. } => format!("closure f{fid}"), Body::Cell { .. } => "cell".into(), Body::Iter { kind, .. } => format!("iterator {kind}"), Body::Freed(w) => w.clone() };
                // A tombstone: dropped from the heap's accounting and never
                // swept or reused, but its memory stays so a dangling
                // reference reaches a Freed body rather than a new object.
                o.body = Body::Freed(what);
                o.refresh();
                o.color = Color::White;
                o.used = false;
                self.live_count -= 1;
            } else {
                std::ptr::drop_in_place(&mut o.body);
                o.used = false;
                o.kind = KIND_FREED;
                self.live_count -= 1;
                self.free.push(o.slot as usize);
            }
        }
    }

    fn slot_count(&self) -> usize { if self.chunks.is_empty() { 0 } else { (self.chunks.len() - 1) * CHUNK + self.bump } }
    fn slot(&self, i: usize) -> NonNull<Object> { NonNull::new(self.chunks[i / CHUNK][i % CHUNK].as_ptr() as *mut Object).unwrap() }
    /// Every live slot, for the oracle.
    fn objects(&self) -> Vec<NonNull<Object>> { (0..self.slot_count()).map(|i| self.slot(i)).filter(|p| unsafe { (*p.as_ptr()).used }).collect() }

    pub fn full_cycle(&mut self, roots: &dyn Roots) {
        if self.phase == Phase::Idle { self.start(roots); }
        while self.phase != Phase::Idle { self.step(usize::MAX / 8, roots); }
        self.debt = 0;
    }

    /// Recompute reachability from the roots non-incrementally and assert that
    /// it agrees with the collector: every reachable object survived, and no
    /// survivor is unreachable.
    pub fn check_oracle(&self, roots: &dyn Roots) { self.check_oracle_with(roots, true) }

    pub fn check_oracle_with(&self, roots: &dyn Roots, exact: bool) {
        let mut seen: std::collections::HashSet<usize> = std::collections::HashSet::new();
        let mut stack: Vec<(NonNull<Object>, String)> = Vec::new();
        let mut visit = |v: Value, via: String, stack: &mut Vec<(NonNull<Object>, String)>| { if let Some(p) = v.as_obj() { stack.push((p, via)); } };
        let mut n = 0;
        roots.each_root(&mut |v| { n += 1; if let Some(p) = v.as_obj() { if !self.is_live_slot(p) { return; } } visit(v, format!("root #{n}"), &mut stack) });
        for s in &self.shapes { for &nm in s.names.iter().chain(s.methods.keys()).chain(s.methods.values()) { visit(nm, "shape".into(), &mut stack); } }
        while let Some((p, via)) = stack.pop() {
            if !seen.insert(p.as_ptr() as usize) { continue; }
            unsafe {
                match &(*p.as_ptr()).body {
                    Body::Freed(what) => panic!("oracle: a reachable object was freed: {what}, reached via {via}"),
                    Body::Table { array, hash } => { for (i, &v) in array.iter().enumerate() { visit(v, format!("{via} > table[{}]", i + 1), &mut stack); } for (&k, &v) in hash { visit(k, format!("{via} > table key"), &mut stack); visit(v, format!("{via} > table value"), &mut stack); } }
                    Body::Record { slots, shape } => { for (i, &v) in slots.iter().enumerate() { visit(v, format!("{via} > record{shape}.slot{i}"), &mut stack); } }
                    Body::Closure { captures, .. } => { for (i, &v) in captures.iter().enumerate() { visit(v, format!("{via} > closure.capture{i}"), &mut stack); } }
                    Body::Cell { value } => visit(*value, format!("{via} > cell"), &mut stack),
                    Body::Iter { obj, pattern, keys, .. } => { visit(*obj, format!("{via} > iterator"), &mut stack); visit(*pattern, format!("{via} > iterator pattern"), &mut stack); for &v in keys { visit(v, format!("{via} > iterator key"), &mut stack); } }
                    _ => {}
                }
            }
        }
        let survivors: Vec<usize> = self.objects().iter().filter(|p| unsafe { !matches!((*p.as_ptr()).body, Body::Freed(_)) }).map(|p| p.as_ptr() as usize).collect();
        let set: std::collections::HashSet<usize> = survivors.iter().copied().collect();
        for s in &seen { if !set.contains(s) { let o = unsafe { &*(*s as *const Object) }; let what = match &o.body { Body::Str { text, .. } => format!("string {:?}", String::from_utf8_lossy(&text.as_bytes()[..text.len().min(40)])), Body::Table { array, hash } => format!("table[{}+{}]", array.len(), hash.len()), Body::Record { shape, .. } => format!("record shape {shape}"), Body::Bytes { data } => format!("bytes {}", data.len()), _ => "other".into() }; panic!("oracle: a reachable object is missing from the heap: {what} used={} kind={} color={:?} epoch={} cycles={}", o.used, o.kind, o.color, o.epoch, self.stats.cycles); } }
        if exact {
            for s in &survivors { assert!(seen.contains(s), "oracle: an unreachable object survived"); }
            assert_eq!(seen.len(), survivors.len(), "oracle: reachable and surviving sets differ");
        }
    }

    pub fn object_count(&self) -> usize { self.live_count }
}
