//! Objects, shapes, the allocator and the collector (contracts 2 and 4).
//!
//! Every object is a fixed 32-byte header followed by its payload, allocated
//! in place from size-classed chunks that never move, or on its own when it
//! is large. The header mirrors a pointer to the payload and its length at
//! fixed offsets, so compiled code reads a string's bytes, a record's slots
//! or a table's array part with two loads and no call (2.1). Growable
//! payloads (a table's parts, storage, byte buffers) own a separate buffer
//! and re-mirror it whenever it moves.
//!
//! The collector is a precise, incremental, non-moving tri-colour mark-sweep
//! with an insertion barrier, paced by allocation debt at safepoints, with
//! the four verification modes of 4.11 built in: stress, interleaved,
//! quarantine and the oracle.

use std::collections::{HashMap, HashSet};
use std::hash::BuildHasherDefault;
use std::ptr::NonNull;

use crate::value::{StrHasher, Value, fnv1a};

// Object kinds, as the header byte compiled code reads.
pub const KIND_FREED: u8 = 0;
pub const KIND_STR: u8 = 1;
pub const KIND_TABLE: u8 = 2;
pub const KIND_RECORD: u8 = 3;
pub const KIND_STORAGE: u8 = 4;
pub const KIND_CLOSURE: u8 = 5;
pub const KIND_CELL: u8 = 6;
pub const KIND_BYTES: u8 = 7;
pub const KIND_ITER: u8 = 8;
pub const KIND_SLICE: u8 = 9;
pub const KIND_INTEGER: u8 = 12;
pub const KIND_NAMES: [&str; 13] = ["freed", "string", "table", "record", "storage", "closure", "cell", "bytes", "iterator", "slice", "reserved", "reserved", "integer"];

pub const COLOR_WHITE: u8 = 0;
pub const COLOR_GRAY: u8 = 1;
pub const COLOR_BLACK: u8 = 2;

/// Header flags.
pub const F_INTERNED: u8 = 1;
/// A freed object kept as a tombstone: never reused, so a dangling reference
/// reaches a freed header rather than a new object (4.11, quarantine).
pub const F_TOMBSTONE: u8 = 2;
/// An optimized table carries a per-object metatable.
pub const F_METATABLE: u8 = 4;

/// The size class byte of an object allocated on its own.
pub const CLASS_LARGE: u8 = 0xff;

/// The fixed header (2.1). `aux` is kind-specific: a record's shape, a
/// closure's function id, an iterator's kind.
#[repr(C)]
pub struct Header {
    pub kind: u8,
    pub color: u8,
    pub class: u8,
    pub flags: u8,
    /// The cycle that last whitened or allocated this object: a white object
    /// from an earlier cycle is dead once marking has ended (4.12).
    pub epoch: u32,
    /// Bytes of the object: header and inline payload, before rounding.
    pub size: u32,
    pub aux: u32,
    pub aux_ptr: *mut u8,
    pub aux_len: u64,
}

pub const HEADER: usize = std::mem::size_of::<Header>();
pub static NEW_TABLES: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);
pub const OFF_KIND: i32 = std::mem::offset_of!(Header, kind) as i32;
pub const OFF_AUX: i32 = std::mem::offset_of!(Header, aux) as i32;
pub const OFF_AUX_PTR: i32 = std::mem::offset_of!(Header, aux_ptr) as i32;
pub const OFF_AUX_LEN: i32 = std::mem::offset_of!(Header, aux_len) as i32;
const _: () = assert!(HEADER == 32);

// Inline payloads, each at `HEADER` bytes from the object's start.
#[repr(C)]
pub struct StrPayload { pub hash: u64 /* then the bytes */ }
#[repr(C)]
pub struct SlicePayload { pub source: Value, pub off: u32, pub len: u32 }
/// A table's hash part: open addressing over (key bits, value) pairs, the
/// key canonical (interned string or number) so bits compare as identity,
/// nil bits marking an empty entry. A key keeps its entry when its value
/// becomes nil, as Lua's does, and a rehash drops those. The layout is
/// fixed so the typed tier and the core probe it inline, with the same hash
/// the shape slot tables use.
#[repr(C)]
pub struct ValueTable { pub ptr: *mut u64, pub mask: u64, pub cap: u64, pub len: u64 }
pub const VT_EMPTY: u64 = Value::NIL.0;
/// Optional overflow for a shaped table; the field map stays first for native probes.
#[repr(C)]
pub struct RecordExtra { pub fields: ValueTable, pub meta: Value }
impl Default for RecordExtra { fn default() -> Self { Self { fields: ValueTable::new(), meta: Value::NIL } } }
impl std::ops::Deref for RecordExtra { type Target = ValueTable; fn deref(&self) -> &ValueTable { &self.fields } }
impl std::ops::DerefMut for RecordExtra { fn deref_mut(&mut self) -> &mut ValueTable { &mut self.fields } }
impl ValueTable {
    pub fn new() -> ValueTable { ValueTable { ptr: std::ptr::null_mut(), mask: 0, cap: 0, len: 0 } }
    pub fn with_capacity(m: usize) -> ValueTable { let mut t = ValueTable::new(); if m > 0 { let mut c = 8; while c * 3 < m * 4 { c *= 2; } t.alloc(c); } t }
    fn alloc(&mut self, cap: usize) { let v: Vec<u64> = (0..cap * 2).map(|i| if i % 2 == 0 { VT_EMPTY } else { 0 }).collect(); let b = v.into_boxed_slice(); self.ptr = Box::leak(b).as_mut_ptr(); self.cap = cap as u64; self.mask = (cap - 1) as u64; }
    #[inline] fn slot(&self, bits: u64) -> Option<usize> {
        // nil is never a key: its bits are the empty marker.
        if self.ptr.is_null() || bits == VT_EMPTY { return None; }
        let mut k = slot_hash(bits) & self.mask;
        loop { let b = unsafe { *self.ptr.add(2 * k as usize) }; if b == bits { return Some(k as usize); } if b == VT_EMPTY { return None; } k = (k + 1) & self.mask; }
    }
    pub fn get(&self, key: &Value) -> Option<&Value> { let k = self.slot(key.0)?; let v = unsafe { &*(self.ptr.add(2 * k + 1) as *const Value) }; if *v == Value::NIL { None } else { Some(v) } }
    pub fn insert(&mut self, key: Value, v: Value) {
        if key == Value::NIL { return; }
        if let Some(k) = self.slot(key.0) { unsafe { *self.ptr.add(2 * k + 1) = v.0; } return; }
        if v == Value::NIL { return; }
        if self.ptr.is_null() || (self.len + 1) * 4 > self.cap * 3 { self.grow(); }
        let mut k = slot_hash(key.0) & self.mask;
        loop { let b = unsafe { *self.ptr.add(2 * k as usize) }; if b == VT_EMPTY { break; } k = (k + 1) & self.mask; }
        unsafe { *self.ptr.add(2 * k as usize) = key.0; *self.ptr.add(2 * k as usize + 1) = v.0; }
        self.len += 1;
    }
    fn grow(&mut self) {
        let live: Vec<(u64, u64)> = self.iter().map(|(k, v)| (k.0, v.0)).collect();
        let want = live.len() + 1; let mut c = 8; while c * 3 < want * 4 { c *= 2; } if c <= self.cap as usize && (want * 4 > (self.cap as usize) * 3) { c = (self.cap as usize) * 2; }
        self.free(); self.alloc(c); self.len = 0;
        for (kb, vb) in live { let mut k = slot_hash(kb) & self.mask; loop { let b = unsafe { *self.ptr.add(2 * k as usize) }; if b == VT_EMPTY { break; } k = (k + 1) & self.mask; } unsafe { *self.ptr.add(2 * k as usize) = kb; *self.ptr.add(2 * k as usize + 1) = vb; } self.len += 1; }
    }
    fn free(&mut self) { if !self.ptr.is_null() { unsafe { drop(Box::from_raw(std::slice::from_raw_parts_mut(self.ptr, self.cap as usize * 2))); } self.ptr = std::ptr::null_mut(); self.cap = 0; self.mask = 0; } }
    /// Every key with a non-nil value.
    pub fn iter(&self) -> impl Iterator<Item = (&Value, &Value)> + '_ {
        let n = if self.ptr.is_null() { 0 } else { self.cap as usize };
        (0..n).filter_map(move |k| unsafe { let b = *self.ptr.add(2 * k); if b == VT_EMPTY { return None; } let v = &*(self.ptr.add(2 * k + 1) as *const Value); if *v == Value::NIL { None } else { Some((&*(self.ptr.add(2 * k) as *const Value), v)) } })
    }
    pub fn len(&self) -> usize { self.len as usize }
    pub fn capacity(&self) -> usize { self.cap as usize }
}
impl Drop for ValueTable { fn drop(&mut self) { self.free(); } }
impl Default for ValueTable { fn default() -> ValueTable { ValueTable::new() } }
impl ValueTable { pub fn keys(&self) -> impl Iterator<Item = &Value> + '_ { self.iter().map(|(k, _)| k) } }
#[repr(C)]
pub struct TablePayload { pub array: Vec<Value>, pub hash: ValueTable, pub meta: Value }
pub const OFF_T_HASH_PTR: i32 = (HEADER + std::mem::offset_of!(TablePayload, hash) + std::mem::offset_of!(ValueTable, ptr)) as i32;
pub const OFF_T_HASH_MASK: i32 = (HEADER + std::mem::offset_of!(TablePayload, hash) + std::mem::offset_of!(ValueTable, mask)) as i32;
pub const OFF_T_META: i32 = (HEADER + std::mem::offset_of!(TablePayload, meta)) as i32;
#[repr(C)]
pub struct StoragePayload { pub data: Vec<f64> }
#[repr(C)]
pub struct BytesPayload { pub data: Vec<u8> }
/// Iteration state for `pairs` (1, over a key snapshot), `ipairs` (2) and
/// `gmatch` (3, `pattern` holds the pattern string).
#[repr(C)]
pub struct IterPayload { pub obj: Value, pub pattern: Value, pub pos: usize, pub keys: Vec<Value> }

impl Header {
    #[inline]
    pub fn payload(&self) -> *mut u8 { unsafe { (self as *const Header as *mut u8).add(HEADER) } }
    #[inline]
    pub fn is_kind(&self, k: u8) -> bool { self.kind == k }
    /// The payload as bytes, for strings, slices and byte buffers.
    #[inline]
    pub fn bytes(&self) -> &[u8] { unsafe { std::slice::from_raw_parts(self.aux_ptr, self.aux_len as usize) } }
    #[inline]
    pub fn bytes_mut(&mut self) -> &mut [u8] { unsafe { std::slice::from_raw_parts_mut(self.aux_ptr, self.aux_len as usize) } }
    /// Value slots, for records (the slots), closures (the captures) and cells.
    #[inline]
    pub fn slots(&self) -> &[Value] { unsafe { std::slice::from_raw_parts(self.aux_ptr as *const Value, self.aux_len as usize) } }
    #[inline]
    pub fn slots_mut(&mut self) -> &mut [Value] { unsafe { std::slice::from_raw_parts_mut(self.aux_ptr as *mut Value, self.aux_len as usize) } }
    #[inline]
    pub fn str_hash(&self) -> u64 { debug_assert!(self.kind == KIND_STR); unsafe { (*(self.payload() as *const StrPayload)).hash } }
    #[inline]
    pub fn table(&mut self) -> &mut TablePayload { debug_assert!(self.kind == KIND_TABLE); unsafe { &mut *(self.payload() as *mut TablePayload) } }
    #[inline]
    pub fn table_ref(&self) -> &TablePayload { debug_assert!(self.kind == KIND_TABLE); unsafe { &*(self.payload() as *const TablePayload) } }
    #[inline]
    pub fn storage(&mut self) -> &mut StoragePayload { debug_assert!(self.kind == KIND_STORAGE); unsafe { &mut *(self.payload() as *mut StoragePayload) } }
    #[inline]
    pub fn byte_buffer(&mut self) -> &mut BytesPayload { debug_assert!(self.kind == KIND_BYTES); unsafe { &mut *(self.payload() as *mut BytesPayload) } }
    #[inline]
    pub fn iter(&mut self) -> &mut IterPayload { debug_assert!(self.kind == KIND_ITER); unsafe { &mut *(self.payload() as *mut IterPayload) } }
    #[inline]
    pub fn slice(&self) -> &SlicePayload { debug_assert!(self.kind == KIND_SLICE); unsafe { &*(self.payload() as *const SlicePayload) } }
    #[inline]
    pub fn shape(&self) -> u32 { debug_assert!(self.kind == KIND_RECORD); self.aux }
    /// A record's ordered children: the array part a record type declares
    /// (`{cst.Node | lexer.Token}` inside the record), after its slots.
    #[inline]
    pub fn record_array(&mut self) -> &mut Vec<Value> { debug_assert!(self.kind == KIND_RECORD); unsafe { &mut *(self.payload().add(8 * self.aux_len as usize) as *mut Vec<Value>) } }
    #[inline]
    pub fn record_array_ref(&self) -> &Vec<Value> { debug_assert!(self.kind == KIND_RECORD); unsafe { &*(self.payload().add(8 * self.aux_len as usize) as *const Vec<Value>) } }
    /// A structural object's fields beyond its shape: the overflow a closed
    /// constructor's shape does not know (an optional field of the declared
    /// type written later). Nominal records never have one (2.5).
    #[inline]
    pub fn record_extra(&mut self) -> &mut Option<Box<RecordExtra>> { debug_assert!(self.kind == KIND_RECORD); unsafe { &mut *(self.payload().add(8 * self.aux_len as usize + std::mem::size_of::<Vec<Value>>()) as *mut Option<Box<RecordExtra>>) } }
    #[inline]
    pub fn record_extra_ref(&self) -> &Option<Box<RecordExtra>> { debug_assert!(self.kind == KIND_RECORD); unsafe { &*(self.payload().add(8 * self.aux_len as usize + std::mem::size_of::<Vec<Value>>()) as *const Option<Box<RecordExtra>>) } }
    #[inline]
    pub fn fid(&self) -> u32 { debug_assert!(self.kind == KIND_CLOSURE); self.aux }
    /// Whether this object reads as a string: a string or a slice.
    #[inline]
    pub fn is_stringish(&self) -> bool { self.kind == KIND_STR || self.kind == KIND_SLICE }

    /// Bytes owned outside the inline allocation. A host mutating these raw
    /// payloads must report capacity changes through Heap::account_resize.
    pub fn external_bytes(&self) -> usize {
        match self.kind {
            KIND_TABLE => { let t = self.table_ref(); 8 * t.array.capacity() + 16 * t.hash.capacity() },
            KIND_RECORD => 8 * self.record_array_ref().capacity() + self.record_extra_ref().as_ref().map(|m| std::mem::size_of::<RecordExtra>() + 16 * m.capacity()).unwrap_or(0),
            KIND_STORAGE => unsafe { 8 * (*(self.payload() as *const StoragePayload)).data.capacity() },
            KIND_BYTES => unsafe { (*(self.payload() as *const BytesPayload)).data.capacity() },
            KIND_ITER => unsafe { 8 * (*(self.payload() as *const IterPayload)).keys.capacity() },
            _ => 0,
        }
    }

    /// Re-mirrors the payload pointer and length after a growable payload
    /// changed (2.1: the runtime keeps them current whenever a payload moves).
    pub fn refresh(&mut self) {
        match self.kind {
            KIND_TABLE => { let t = self.table(); let (p, n) = (t.array.as_mut_ptr() as *mut u8, t.array.len() as u64); self.aux_ptr = p; self.aux_len = n; }
            KIND_STORAGE => { let s = self.storage(); let (p, n) = (s.data.as_mut_ptr() as *mut u8, s.data.len() as u64); self.aux_ptr = p; self.aux_len = n; }
            KIND_BYTES => { let b = self.byte_buffer(); let (p, n) = (b.data.as_mut_ptr(), b.data.len() as u64); self.aux_ptr = p; self.aux_len = n; }
            KIND_ITER => { let i = self.iter(); let (p, n) = (i.keys.as_mut_ptr() as *mut u8, i.keys.len() as u64); self.aux_ptr = p; self.aux_len = n; }
            _ => {}
        }
    }
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum SlotTy { Any, Num, Str, Bool, Record(u32) }

/// The probe the shape tables and the core share: the interned string's
/// address bits, spread.
#[inline] pub fn slot_hash(bits: u64) -> u64 { (bits >> 4).wrapping_mul(0x9E37_79B9_7F4A_7C15) >> 32 }
impl Shape {
    /// The slot a name occupies, by the table.
    #[inline] pub fn slot_of(&self, name: Value) -> Option<usize> {
        let mut k = slot_hash(name.0) & self.mask;
        loop { let (b, i) = self.table[k as usize]; if b == name.0 { return Some(i as usize); } if b == 0 { return None; } k = (k + 1) & self.mask; }
    }
}
pub struct Shape {
    pub name: String,
    /// A structural shape (a closed constructor's field set) accepts fields
    /// beyond its slots in the record's overflow; a nominal one does not.
    pub structural: bool,
    pub names: Vec<Value>, // interned strings
    pub types: Vec<SlotTy>,
    /// Slot by name: an open-addressed table of (name bits, slot) with a
    /// power-of-two size, empty entries zero, that the core probes the same
    /// way; names are interned, so bits compare as identity.
    pub table: Vec<(u64, u32)>,
    pub mask: u64,
    /// The descriptor: method name (interned) to the function value that runs it.
    pub methods: HashMap<Value, Value>,
}

/// Who can enumerate the roots (4.5): every task's registers, every frame's
/// closure, constant pools, handle scopes, registered handles.
pub trait Roots { fn each_root(&self, f: &mut dyn FnMut(Value)); }

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
enum Phase { Idle, Marking, Sweeping }

/// Size classes: the slot size of each chunk class, in bytes.
const CLASSES: [u32; 30] = [32, 48, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 384, 448, 512, 640, 768, 1024, 1280, 1536, 2048, 2560, 3072, 4096, 6144, 8192, 12288, 16384, 24576, 32768];
/// A chunk is this many bytes, aligned to itself, so an address finds its
/// chunk by masking.
const CHUNK_BYTES: usize = 256 * 1024;
/// The chunk's own header: class, slot size, slot count and its index in
/// allocation order, which the sweep and the allocation colour use.
#[repr(C)]
struct ChunkHeader { class: u8, slot_size: u32, nslots: u32, index: u32 }
const CHUNK_HEADER: usize = 64;

#[derive(Default, Debug, Clone)]
pub struct Stats { pub cycles: u64, pub freed: u64, pub allocated: u64, pub barrier_grays: u64, pub steps: u64, pub chunks: u64, pub large: u64 }

pub struct Heap {
    // Native queue references follow their managed endpoint's lifetime. This
    // side table does not root endpoints; sweep drops the Arc before slot reuse.
    pub(crate) channels: HashMap<Value, crate::channels::Channel>,
    /// Every chunk in allocation order, as its base address.
    chunks: Vec<usize>,
    chunk_set: HashSet<usize>,
    /// Free slots per class, threaded through the freed headers' `aux_ptr`.
    free: [*mut Header; CLASSES.len()],
    /// Objects allocated on their own, in allocation order; a freed entry is
    /// null until the sweep compacts the list.
    large: Vec<*mut Header>,
    large_set: HashSet<usize>,
    live_count: usize,
    gray: Vec<NonNull<Header>>,
    phase: Phase,
    /// The sweep cursor: chunk index and slot index, then the large index.
    sweep_chunk: usize,
    sweep_slot: usize,
    sweep_large: usize,
    debt: usize,
    threshold: usize,
    pub live_bytes: usize,
    pub automatic_collection: bool,
    /// A whole cycle at every allocation.
    pub stress: bool,
    /// One small step at every allocation, the oracle at every cycle end.
    pub stress_steps: bool,
    pub oracle: bool,
    /// Freed objects stay as tombstones.
    pub quarantine: bool,
    pub shapes: Vec<Shape>,
    interned: HashMap<Box<[u8]>, NonNull<Header>, BuildHasherDefault<StrHasher>>,
    integers: HashMap<(bool, u64), NonNull<Header>>,
    pub stats: Stats,
    pub alloc_kinds: [u64; 13],
    /// 1 while marking: the threaded core reads it to decide whether a store
    /// needs the barrier's slow path.
    pub marking: u8,
}

thread_local! { static NEVER: bool = std::env::var("GC_NEVER").is_ok(); }
fn class_of(size: usize) -> Option<usize> { CLASSES.iter().position(|&c| c as usize >= size) }

impl Heap {
    pub fn new() -> Heap {
        let env = |k: &str| std::env::var(k).is_ok();
        Heap { channels: HashMap::new(), chunks: Vec::new(), chunk_set: HashSet::new(), free: [std::ptr::null_mut(); CLASSES.len()], large: Vec::new(), large_set: HashSet::new(), live_count: 0, gray: Vec::new(), phase: Phase::Idle, sweep_chunk: 0, sweep_slot: 0, sweep_large: 0, debt: 0, threshold: 1 << 20, live_bytes: 0, automatic_collection: true, stress: env("GC_STRESS"), stress_steps: env("GC_INTERLEAVE"), oracle: env("GC_ORACLE"), quarantine: env("GC_QUARANTINE"), shapes: Vec::new(), interned: HashMap::default(), integers: HashMap::new(), stats: Stats::default(), alloc_kinds: [0; 13], marking: 0 }
    }

    pub fn shape(&mut self, name: &str, names: &[Value], types: &[SlotTy]) -> u32 {
        let mut size = 8usize; while size < names.len() * 2 { size *= 2; }
        let mask = (size - 1) as u64;
        let mut table = vec![(0u64, 0u32); size];
        for (i, n) in names.iter().enumerate() { let mut k = slot_hash(n.0) & mask; while table[k as usize].0 != 0 { k = (k + 1) & mask; } table[k as usize] = (n.0, i as u32); }
        self.shapes.push(Shape { name: name.to_string(), structural: name.starts_with("struct:"), names: names.to_vec(), types: types.to_vec(), methods: HashMap::new(), table, mask });
        (self.shapes.len() - 1) as u32
    }

    /// Keep GC pacing and retained-byte accounting consistent with native
    /// payload capacities, including relocation into freshly restored objects.
    pub fn account_resize(&mut self, before: usize, after: usize) {
        if after >= before { self.live_bytes += after - before; self.debt += after - before; }
        else { self.live_bytes -= before - after; }
    }

    // ---- allocation -----------------------------------------------------

    fn new_chunk(&mut self, class: usize) -> *mut u8 {
        let layout = std::alloc::Layout::from_size_align(CHUNK_BYTES, CHUNK_BYTES).unwrap();
        let base = unsafe { std::alloc::alloc_zeroed(layout) };
        assert!(!base.is_null(), "chunk allocation failed");
        let slot_size = CLASSES[class] as usize;
        let nslots = (CHUNK_BYTES - CHUNK_HEADER) / slot_size;
        let index = self.chunks.len() as u32;
        unsafe { (base as *mut ChunkHeader).write(ChunkHeader { class: class as u8, slot_size: slot_size as u32, nslots: nslots as u32, index }); }
        // Thread every slot onto the class's free list, last slot first so
        // allocation walks the chunk forwards.
        let mut next = self.free[class];
        for i in (0..nslots).rev() {
            let h = unsafe { base.add(CHUNK_HEADER + i * slot_size) as *mut Header };
            unsafe { (*h).kind = KIND_FREED; (*h).class = class as u8; (*h).flags = 0; (*h).aux_ptr = next as *mut u8; }
            next = h;
        }
        self.free[class] = next;
        self.chunks.push(base as usize);
        self.chunk_set.insert(base as usize);
        self.stats.chunks += 1;
        base
    }

    #[inline]
    fn chunk_of(addr: usize) -> usize { addr & !(CHUNK_BYTES - 1) }

    /// Allocates an object of `kind` with `inline_bytes` of payload, its
    /// payload uninitialised beyond zero. The colour follows 4.3: white when
    /// idle, black while marking, and during the sweep black ahead of the
    /// cursor and white behind it.
    fn alloc_raw(&mut self, kind: u8, inline_bytes: usize) -> NonNull<Header> {
        let size = HEADER + inline_bytes;
        let (h, class, behind_sweep) = match class_of(size) {
            Some(class) => {
                if self.free[class].is_null() { self.new_chunk(class); }
                let h = self.free[class];
                self.free[class] = unsafe { (*h).aux_ptr as *mut Header };
                let chunk = unsafe { &*(Self::chunk_of(h as usize) as *const ChunkHeader) };
                let slot = (h as usize - Self::chunk_of(h as usize) - CHUNK_HEADER) / chunk.slot_size as usize;
                let behind = (chunk.index as usize) < self.sweep_chunk || (chunk.index as usize == self.sweep_chunk && slot < self.sweep_slot);
                (h, class as u8, behind)
            }
            None => {
                let layout = std::alloc::Layout::from_size_align(size, 16).unwrap();
                let h = unsafe { std::alloc::alloc_zeroed(layout) } as *mut Header;
                assert!(!h.is_null(), "large allocation failed");
                self.large.push(h);
                self.large_set.insert(h as usize);
                self.stats.large += 1;
                (h, CLASS_LARGE, false)
            }
        };
        let color = match self.phase { Phase::Idle => COLOR_WHITE, Phase::Marking => COLOR_BLACK, Phase::Sweeping => if behind_sweep { COLOR_WHITE } else { COLOR_BLACK } };
        unsafe { h.write(Header { kind, color, class, flags: 0, epoch: self.stats.cycles as u32, size: size as u32, aux: 0, aux_ptr: (h as *mut u8).add(HEADER), aux_len: 0 }); }
        self.live_count += 1;
        self.live_bytes += size;
        self.debt += size;
        self.stats.allocated += 1;
        self.alloc_kinds[kind as usize] += 1;
        NonNull::new(h).unwrap()
    }

    /// Allocation is a safepoint: the collector may run here, so every value
    /// the caller still needs must be reachable from the roots at this point.
    fn alloc(&mut self, kind: u8, inline_bytes: usize, roots: &dyn Roots) -> NonNull<Header> {
        self.safepoint(roots);
        self.alloc_raw(kind, inline_bytes)
    }

    /// A fresh, uninterned string with these bytes (hash 0 until needed).
    pub fn new_string_bytes(&mut self, bytes: &[u8], roots: &dyn Roots) -> Value {
        let p = self.alloc(KIND_STR, 8 + bytes.len(), roots);
        unsafe {
            let h = &mut *p.as_ptr();
            (h.payload() as *mut StrPayload).write(StrPayload { hash: 0 });
            let dst = h.payload().add(8);
            std::ptr::copy_nonoverlapping(bytes.as_ptr(), dst, bytes.len());
            h.aux_ptr = dst; h.aux_len = bytes.len() as u64;
        }
        Value::obj(p)
    }
    pub fn new_string(&mut self, text: &str, roots: &dyn Roots) -> Value { self.new_string_bytes(text.as_bytes(), roots) }

    /// The interned string with these bytes (1.3): one object per content,
    /// so equality is identity. The intern table is weak (4.12): a hit while
    /// marking greys a white string; a hit while sweeping on a string an
    /// earlier cycle whitened is a miss, never a resurrection.
    pub fn intern(&mut self, s: &str, roots: &dyn Roots) -> Value { self.intern_bytes(s.as_bytes(), roots) }
    pub fn intern_bytes(&mut self, s: &[u8], roots: &dyn Roots) -> Value {
        if let Some(v) = self.intern_lookup_bytes(s) { return v; }
        let v = self.new_string_bytes(s, roots);
        let p = v.as_obj().unwrap();
        unsafe { let h = &mut *p.as_ptr(); h.flags |= F_INTERNED; (*(h.payload() as *mut StrPayload)).hash = fnv1a(s); }
        self.interned.insert(s.into(), p);
        v
    }
    /// The interned string with these bytes, if one is alive, allocating nothing.
    // For immediate table lookup only: this does not root or resurrect a key.
    pub(crate) fn interned_key(&self, s: &str) -> Option<Value> { self.interned.get(s.as_bytes()).map(|p| Value::obj(*p)) }
    pub fn intern_lookup(&mut self, s: &str) -> Option<Value> { self.intern_lookup_bytes(s.as_bytes()) }
    pub fn intern_lookup_bytes(&mut self, s: &[u8]) -> Option<Value> {
        let p = *self.interned.get(s)?;
        unsafe {
            let h = &mut *p.as_ptr();
            match (self.phase, h.color) {
                (Phase::Marking, COLOR_WHITE) => { h.color = COLOR_GRAY; self.gray.push(p); self.stats.barrier_grays += 1; Some(Value::obj(p)) }
                (Phase::Sweeping, COLOR_WHITE) if (h.epoch as u64) < self.stats.cycles => { self.interned.remove(s); None }
                _ => Some(Value::obj(p)),
            }
        }
    }

    pub fn integer_key(&self, bits: u64) -> Option<Value> { self.integers.get(&(false, bits)).map(|p| Value::obj(*p)) }
    pub fn integer_lookup(&mut self, value: crate::numeric::Integer) -> Option<Value> {
        let key = (value.unsigned, value.bits);
        let p = *self.integers.get(&key)?;
        unsafe {
            let h = &mut *p.as_ptr();
            match (self.phase, h.color) {
                (Phase::Marking, COLOR_WHITE) => { h.color = COLOR_GRAY; self.gray.push(p); self.stats.barrier_grays += 1; }
                (Phase::Sweeping, COLOR_WHITE) if (h.epoch as u64) < self.stats.cycles => { self.integers.remove(&key); return None; }
                _ => {}
            }
        }
        Some(Value::obj(p))
    }
    pub fn box_integer(&mut self, value: crate::numeric::Integer, roots: &dyn Roots) -> Value {
        if let Some(v) = value.immediate().or_else(|| self.integer_lookup(value)) { return v; }
        let p = self.alloc(KIND_INTEGER, 0, roots);
        unsafe { let h = &mut *p.as_ptr(); h.aux = value.unsigned as u32; h.aux_len = value.bits; }
        self.integers.insert((value.unsigned, value.bits), p);
        Value::obj(p)
    }

    pub fn new_slice(&mut self, source: Value, off: u32, len: u32, roots: &dyn Roots) -> Value {
        let (base, off) = unsafe { let s = &*source.as_obj().unwrap().as_ptr(); if s.kind == KIND_SLICE { let sp = s.slice(); (sp.source, sp.off + off) } else { (source, off) } };
        let p = self.alloc(KIND_SLICE, std::mem::size_of::<SlicePayload>(), roots);
        unsafe {
            let h = &mut *p.as_ptr();
            (h.payload() as *mut SlicePayload).write(SlicePayload { source: base, off, len });
            h.aux_ptr = (*base.as_obj().unwrap().as_ptr()).aux_ptr.add(off as usize); h.aux_len = len as u64;
        }
        // Allocation is black during marking; initial references need the
        // same insertion barrier as later stores.
        if self.phase == Phase::Marking { self.scan(p); }
        Value::obj(p)
    }

    pub fn new_table_sized(&mut self, n: usize, m: usize, roots: &dyn Roots) -> Value {
        if crate::interp::TABLE_STATS.load(std::sync::atomic::Ordering::Relaxed) { crate::interp::TABLE_COUNTS[if n + m == 0 { 4 } else { 4 }].fetch_add(0, std::sync::atomic::Ordering::Relaxed); NEW_TABLES.fetch_add(1, std::sync::atomic::Ordering::Relaxed); }
        let p = self.alloc(KIND_TABLE, std::mem::size_of::<TablePayload>(), roots);
        unsafe {
            let h = &mut *p.as_ptr();
            (h.payload() as *mut TablePayload).write(TablePayload { array: Vec::with_capacity(n), hash: ValueTable::with_capacity(m), meta: Value::NIL });
            h.refresh();
        }
        self.account_resize(0, unsafe { p.as_ref().external_bytes() });
        Value::obj(p)
    }
    pub fn new_table(&mut self, roots: &dyn Roots) -> Value { self.new_table_sized(0, 0, roots) }

    pub fn new_record(&mut self, shape: u32, roots: &dyn Roots) -> Value {
        let n = self.shapes[shape as usize].names.len();
        let p = self.alloc(KIND_RECORD, 8 * n + std::mem::size_of::<Vec<Value>>() + std::mem::size_of::<Option<Box<RecordExtra>>>(), roots);
        unsafe { let h = &mut *p.as_ptr(); h.aux = shape; h.aux_len = n as u64; for s in h.slots_mut() { *s = Value::NIL; } (h.payload().add(8 * n) as *mut Vec<Value>).write(Vec::new()); (h.payload().add(8 * n + std::mem::size_of::<Vec<Value>>()) as *mut Option<Box<RecordExtra>>).write(None); }
        Value::obj(p)
    }
    pub fn new_closure(&mut self, fid: u32, captures: &[Value], roots: &dyn Roots) -> Value {
        let p = self.alloc(KIND_CLOSURE, 8 * captures.len(), roots);
        unsafe { let h = &mut *p.as_ptr(); h.aux = fid; h.aux_len = captures.len() as u64; h.slots_mut().copy_from_slice(captures); }
        // Allocation is black during marking; initial references need the
        // same insertion barrier as later stores.
        if self.phase == Phase::Marking { self.scan(p); }
        Value::obj(p)
    }
    pub fn new_cell(&mut self, value: Value, roots: &dyn Roots) -> Value {
        let p = self.alloc(KIND_CELL, 8, roots);
        unsafe { let h = &mut *p.as_ptr(); h.aux_len = 1; h.slots_mut()[0] = value; }
        // Allocation is black during marking; initial references need the
        // same insertion barrier as later stores.
        if self.phase == Phase::Marking { self.scan(p); }
        Value::obj(p)
    }
    pub fn new_iter(&mut self, kind: u8, obj: Value, pattern: Value, keys: Vec<Value>, roots: &dyn Roots) -> Value {
        let p = self.alloc(KIND_ITER, std::mem::size_of::<IterPayload>(), roots);
        unsafe { let h = &mut *p.as_ptr(); h.aux = kind as u32; (h.payload() as *mut IterPayload).write(IterPayload { obj, pattern, pos: 0, keys }); h.refresh(); }
        // Allocation is black during marking; initial references need the
        // same insertion barrier as later stores.
        if self.phase == Phase::Marking { self.scan(p); }
        self.account_resize(0, unsafe { p.as_ref().external_bytes() });
        Value::obj(p)
    }
    pub fn new_bytes(&mut self, n: usize, roots: &dyn Roots) -> Value {
        let p = self.alloc(KIND_BYTES, std::mem::size_of::<BytesPayload>(), roots);
        unsafe { let h = &mut *p.as_ptr(); (h.payload() as *mut BytesPayload).write(BytesPayload { data: vec![0u8; n] }); h.refresh(); }
        self.live_bytes += n; self.debt += n;
        Value::obj(p)
    }
    /// A growable buffer with room for a short result before it reallocates.
    pub fn new_buffer(&mut self, roots: &dyn Roots) -> Value {
        let p = self.alloc(KIND_BYTES, std::mem::size_of::<BytesPayload>(), roots);
        unsafe { let h = &mut *p.as_ptr(); (h.payload() as *mut BytesPayload).write(BytesPayload { data: Vec::with_capacity(64) }); h.refresh(); }
        self.account_resize(0, unsafe { p.as_ref().external_bytes() });
        Value::obj(p)
    }
    pub fn new_storage(&mut self, n: usize, roots: &dyn Roots) -> Value {
        let p = self.alloc(KIND_STORAGE, std::mem::size_of::<StoragePayload>(), roots);
        unsafe { let h = &mut *p.as_ptr(); (h.payload() as *mut StoragePayload).write(StoragePayload { data: vec![0.0; n] }); h.refresh(); }
        self.live_bytes += 8 * n; self.debt += 8 * n;
        Value::obj(p)
    }

    // ---- the collector ---------------------------------------------------

    /// The insertion barrier (4.2): storing a white child into a black parent
    /// while marking greys the child. Every heap store goes through here.
    #[inline]
    pub fn barrier(&mut self, parent: NonNull<Header>, child: Value) {
        if self.phase != Phase::Marking { return; }
        if let Some(c) = child.as_obj() {
            unsafe {
                if (*parent.as_ptr()).color == COLOR_BLACK && (*c.as_ptr()).color == COLOR_WHITE {
                    (*c.as_ptr()).color = COLOR_GRAY;
                    self.gray.push(c);
                    self.stats.barrier_grays += 1;
                }
            }
        }
    }

    /// Where collection may run (4.4). Pays allocation debt with marking or
    /// sweeping work; under stress, runs a whole cycle every time.
    pub fn safepoint(&mut self, roots: &dyn Roots) {
        if !self.automatic_collection { return; }
        if self.stress {
            self.full_cycle(roots);
            if self.oracle { self.check_oracle(roots); }
            return;
        }
        if self.stress_steps {
            if self.phase == Phase::Idle { self.start(roots); }
            self.step(2, roots);
            if self.phase == Phase::Idle && self.oracle {
                // An interleaved cycle may leave floating garbage (4.8):
                // safety is exact here, completeness after an atomic cycle.
                self.check_oracle_with(roots, false);
                self.full_cycle(roots);
                self.check_oracle_with(roots, true);
            }
            return;
        }
        if self.phase == Phase::Idle {
            if self.debt < self.threshold || NEVER.with(|n| *n) { return; }
            self.start(roots);
        }
        let budget = (self.debt / 64).max(256);
        self.step(budget, roots);
        self.debt = 0;
    }

    fn start(&mut self, roots: &dyn Roots) {
        self.phase = Phase::Marking;
        self.marking = 1;
        self.stats.cycles += 1;
        self.mark_roots(roots);
    }

    /// Whether `p` addresses a live object: a slot of a chunk on a slot
    /// boundary, or a large object, and not freed (5.1: the root walk accepts
    /// a register word only when it addresses a live slot).
    pub fn is_live_slot(&self, p: NonNull<Header>) -> bool {
        let addr = p.as_ptr() as usize;
        if self.large_set.contains(&addr) { return unsafe { (*p.as_ptr()).kind != KIND_FREED }; }
        let base = Self::chunk_of(addr);
        if !self.chunk_set.contains(&base) { return false; }
        let chunk = unsafe { &*(base as *const ChunkHeader) };
        if addr < base + CHUNK_HEADER { return false; }
        let off = addr - base - CHUNK_HEADER;
        if off % chunk.slot_size as usize != 0 || off / chunk.slot_size as usize >= chunk.nslots as usize { return false; }
        unsafe { (*p.as_ptr()).kind != KIND_FREED }
    }

    fn mark_roots(&mut self, roots: &dyn Roots) {
        let mut cands: Vec<NonNull<Header>> = Vec::new();
        roots.each_root(&mut |v| { if let Some(p) = v.as_obj() { cands.push(p); } });
        for p in cands {
            if !self.is_live_slot(p) { continue; }
            unsafe { if (*p.as_ptr()).color == COLOR_WHITE { (*p.as_ptr()).color = COLOR_GRAY; self.gray.push(p); } }
        }
        let gray = &mut self.gray;
        for s in &self.shapes { for &n in s.names.iter().chain(s.methods.keys()).chain(s.methods.values()) { if let Some(p) = n.as_obj() { unsafe { if (*p.as_ptr()).color == COLOR_WHITE { (*p.as_ptr()).color = COLOR_GRAY; gray.push(p); } } } } }
    }

    /// Every reference an object holds, by kind: the one walk the marker, the
    /// oracle and the serialiser share.
    pub fn each_child(h: &Header, f: &mut dyn FnMut(Value)) {
        match h.kind {
            KIND_TABLE => { let t = h.table_ref(); for &v in &t.array { f(v); } for (k, v) in t.hash.iter() { f(*k); f(*v); } if t.meta != Value::NIL { f(t.meta); } }
            KIND_RECORD => { for &v in h.slots() { f(v); } for &v in h.record_array_ref() { f(v); } if let Some(m) = h.record_extra_ref() { f(m.meta); for (k, v) in m.iter() { f(*k); f(*v); } } }
            KIND_CLOSURE | KIND_CELL => { for &v in h.slots() { f(v); } }
            KIND_SLICE => f(h.slice().source),
            KIND_ITER => { let i = unsafe { &*(h.payload() as *const IterPayload) }; f(i.obj); f(i.pattern); for &v in &i.keys { f(v); } }
            _ => {}
        }
    }

    fn scan(&mut self, p: NonNull<Header>) {
        let gray = &mut self.gray;
        let h = unsafe { &*p.as_ptr() };
        Self::each_child(h, &mut |v| { if let Some(c) = v.as_obj() { unsafe { if (*c.as_ptr()).color == COLOR_WHITE { (*c.as_ptr()).color = COLOR_GRAY; gray.push(c); } } } });
        unsafe { (*p.as_ptr()).color = COLOR_BLACK; }
    }

    /// One increment of work. Marking drains grey objects; when none remain
    /// the roots are rescanned once (4.6) and, if still none, sweeping begins.
    /// Sweeping frees white objects and whitens black ones in slices.
    fn step(&mut self, budget: usize, roots: &dyn Roots) {
        self.stats.steps += 1;
        let mut budget = budget;
        loop {
            match self.phase {
                Phase::Marking => {
                    while budget > 0 { match self.gray.pop() { Some(p) => { self.scan(p); budget -= 1; } None => break } }
                    if budget == 0 { return; }
                    self.mark_roots(roots);
                    if !self.gray.is_empty() { continue; }
                    self.phase = Phase::Sweeping;
                    self.marking = 0;
                    self.sweep_chunk = 0; self.sweep_slot = 0; self.sweep_large = 0;
                }
                Phase::Sweeping => {
                    let mut work = budget * 4;
                    while self.sweep_chunk < self.chunks.len() && work > 0 {
                        let base = self.chunks[self.sweep_chunk];
                        let chunk = unsafe { &*(base as *const ChunkHeader) };
                        let (slot_size, nslots) = (chunk.slot_size as usize, chunk.nslots as usize);
                        while self.sweep_slot < nslots && work > 0 {
                            let h = (base + CHUNK_HEADER + self.sweep_slot * slot_size) as *mut Header;
                            self.sweep_slot += 1;
                            if unsafe { (*h).kind } != KIND_FREED { self.sweep_one(NonNull::new(h).unwrap()); work -= 1; }
                        }
                        if self.sweep_slot >= nslots { self.sweep_chunk += 1; self.sweep_slot = 0; }
                    }
                    if self.sweep_chunk >= self.chunks.len() {
                        while self.sweep_large < self.large.len() && work > 0 {
                            let h = self.large[self.sweep_large];
                            self.sweep_large += 1;
                            if !h.is_null() && unsafe { (*h).kind } != KIND_FREED { self.sweep_one(NonNull::new(h).unwrap()); work -= 1; }
                        }
                        if self.sweep_large >= self.large.len() {
                            self.large.retain(|h| !h.is_null());
                            self.phase = Phase::Idle;
                            self.threshold = (self.live_bytes * 2).max(1 << 20);
                        }
                    }
                    return;
                }
                Phase::Idle => return,
            }
        }
    }

    fn sweep_one(&mut self, p: NonNull<Header>) {
        unsafe {
            if (*p.as_ptr()).color == COLOR_WHITE { self.free(p); }
            else { (*p.as_ptr()).color = COLOR_WHITE; (*p.as_ptr()).epoch = self.stats.cycles as u32; }
        }
    }

    /// Drops an object's owned buffers and returns its memory: to the class's
    /// free list, or, under stress and quarantine, keeps it as a tombstone.
    fn free(&mut self, p: NonNull<Header>) {
        unsafe {
            let h = &mut *p.as_ptr();
            self.live_bytes -= h.size as usize + h.external_bytes();
            self.stats.freed += 1;
            self.live_count -= 1;
            if h.flags & F_INTERNED != 0 { self.interned.remove(h.bytes()); }
            if h.kind == KIND_INTEGER {
                let key = (h.aux != 0, h.aux_len);
                if self.integers.get(&key) == Some(&p) { self.integers.remove(&key); }
            }
            match h.kind {
                KIND_TABLE => { self.channels.remove(&Value::obj(p)); let t = h.table(); std::ptr::drop_in_place(t); }
                KIND_STORAGE => { let s = h.storage(); std::ptr::drop_in_place(s); }
                KIND_BYTES => { let b = h.byte_buffer(); std::ptr::drop_in_place(b); }
                KIND_ITER => std::ptr::drop_in_place(h.iter()),
                KIND_RECORD => { let a = h.record_array(); std::ptr::drop_in_place(a); std::ptr::drop_in_place(h.record_extra()); }
                _ => {}
            }
            let was = h.kind;
            h.kind = KIND_FREED;
            h.aux = was as u32;
            h.aux_len = 0;
            h.color = COLOR_WHITE;
            if self.stress || self.quarantine {
                h.flags = F_TOMBSTONE;
                h.aux_ptr = std::ptr::null_mut();
                return;
            }
            if h.class == CLASS_LARGE {
                let i = self.large.iter().position(|&q| q == p.as_ptr()).expect("large object in its list");
                self.large[i] = std::ptr::null_mut();
                self.large_set.remove(&(p.as_ptr() as usize));
                let layout = std::alloc::Layout::from_size_align(h.size as usize, 16).unwrap();
                std::alloc::dealloc(p.as_ptr() as *mut u8, layout);
            } else {
                let class = h.class as usize;
                h.aux_ptr = self.free[class] as *mut u8;
                self.free[class] = p.as_ptr();
            }
        }
    }

    /// Every live object, for the oracle and the serialiser.
    pub fn objects(&self) -> Vec<NonNull<Header>> {
        let mut out = Vec::new();
        for &base in &self.chunks {
            let chunk = unsafe { &*(base as *const ChunkHeader) };
            for i in 0..chunk.nslots as usize {
                let h = (base + CHUNK_HEADER + i * chunk.slot_size as usize) as *mut Header;
                if unsafe { (*h).kind } != KIND_FREED { out.push(NonNull::new(h).unwrap()); }
            }
        }
        for &h in &self.large { if !h.is_null() && unsafe { (*h).kind } != KIND_FREED { out.push(NonNull::new(h).unwrap()); } }
        out
    }

    pub fn channel_count(&self) -> usize { self.channels.len() }

    pub fn full_cycle(&mut self, roots: &dyn Roots) {
        // Finish an in-progress incremental cycle, then collect from current
        // roots so an explicit full collection also removes floating garbage.
        while self.phase != Phase::Idle { self.step(usize::MAX / 8, roots); }
        self.start(roots);
        while self.phase != Phase::Idle { self.step(usize::MAX / 8, roots); }
        self.debt = 0;
    }

    /// What an object was, for messages.
    pub fn describe(h: &Header) -> String {
        match h.kind {
            KIND_STR => format!("string {:?}", String::from_utf8_lossy(&h.bytes()[..h.bytes().len().min(40)])),
            KIND_SLICE => format!("slice {}+{}", h.slice().off, h.slice().len),
            KIND_TABLE => { let t = h.table_ref(); format!("table[{}+{}]", t.array.len(), t.hash.len()) }
            KIND_RECORD => format!("record shape {}[{}]", h.aux, h.record_array_ref().len()),
            KIND_CLOSURE => format!("closure f{}", h.aux),
            KIND_FREED => format!("freed {}", KIND_NAMES.get(h.aux as usize).copied().unwrap_or("?")),
            k => KIND_NAMES.get(k as usize).copied().unwrap_or("?").to_string(),
        }
    }

    /// Recompute reachability from the roots non-incrementally and assert that
    /// it agrees with the collector: every reachable object survived, and
    /// (when `exact`) no survivor is unreachable.
    pub fn check_oracle(&self, roots: &dyn Roots) { self.check_oracle_with(roots, true) }
    pub fn check_oracle_with(&self, roots: &dyn Roots, exact: bool) {
        let mut seen: HashSet<usize> = HashSet::new();
        let mut stack: Vec<(NonNull<Header>, String)> = Vec::new();
        let mut n = 0;
        roots.each_root(&mut |v| { n += 1; if let Some(p) = v.as_obj() { if self.is_live_slot(p) { stack.push((p, format!("root #{n}"))); } } });
        for s in &self.shapes { for &nm in s.names.iter().chain(s.methods.keys()).chain(s.methods.values()) { if let Some(p) = nm.as_obj() { stack.push((p, "shape".into())); } } }
        while let Some((p, via)) = stack.pop() {
            if !seen.insert(p.as_ptr() as usize) { continue; }
            let h = unsafe { &*p.as_ptr() };
            if h.kind == KIND_FREED { panic!("oracle: a reachable object was freed: {}, reached via {via}", Self::describe(h)); }
            let mut i = 0;
            Self::each_child(h, &mut |v| { i += 1; if let Some(c) = v.as_obj() { stack.push((c, format!("{via} > {}#{i}", KIND_NAMES[h.kind as usize]))); } });
        }
        let survivors: Vec<usize> = self.objects().iter().map(|p| p.as_ptr() as usize).collect();
        let set: HashSet<usize> = survivors.iter().copied().collect();
        for s in &seen { if !set.contains(s) { let h = unsafe { &*(*s as *const Header) }; panic!("oracle: a reachable object is missing from the heap: {} kind={} color={} epoch={} cycles={}", Self::describe(h), h.kind, h.color, h.epoch, self.stats.cycles); } }
        if exact {
            for s in &survivors { assert!(seen.contains(s), "oracle: an unreachable object survived: {}", Self::describe(unsafe { &*(*s as *const Header) })); }
            assert_eq!(seen.len(), survivors.len(), "oracle: reachable and surviving sets differ");
        }
    }

    pub fn object_count(&self) -> usize { self.live_count }
    pub fn is_marking(&self) -> bool { self.phase == Phase::Marking }
}

impl Drop for Heap {
    fn drop(&mut self) {
        // Owned buffers of live objects, then the chunks and large blocks.
        for p in self.objects() {
            unsafe { let h = &mut *p.as_ptr(); match h.kind { KIND_TABLE => std::ptr::drop_in_place(h.table()), KIND_STORAGE => std::ptr::drop_in_place(h.storage()), KIND_BYTES => std::ptr::drop_in_place(h.byte_buffer()), KIND_ITER => std::ptr::drop_in_place(h.iter()), KIND_RECORD => { std::ptr::drop_in_place(h.record_array()); std::ptr::drop_in_place(h.record_extra()); } _ => {} } }
        }
        let layout = std::alloc::Layout::from_size_align(CHUNK_BYTES, CHUNK_BYTES).unwrap();
        for &base in &self.chunks { unsafe { std::alloc::dealloc(base as *mut u8, layout); } }
        for &h in &self.large { if !h.is_null() { unsafe { let size = (*h).size as usize; std::alloc::dealloc(h as *mut u8, std::alloc::Layout::from_size_align(size, 16).unwrap()); } } }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    struct R(std::cell::RefCell<Vec<Value>>);
    impl Roots for R { fn each_root(&self, f: &mut dyn FnMut(Value)) { for &v in self.0.borrow().iter() { f(v); } } }

    #[test]
    fn layout_and_slots() {
        let mut h = Heap::new();
        let r = R(std::cell::RefCell::new(Vec::new()));
        let s = h.intern("hello", &r);
        let p = s.as_obj().unwrap();
        unsafe { assert_eq!((*p.as_ptr()).bytes(), b"hello"); assert_eq!((*p.as_ptr()).kind, KIND_STR); }
        assert_eq!(h.intern("hello", &r), s);
        let shape = h.shape("P", &[s], &[SlotTy::Any]);
        let rec = h.new_record(shape, &r);
        unsafe { let hh = &mut *rec.as_obj().unwrap().as_ptr(); assert_eq!(hh.slots().len(), 1); hh.slots_mut()[0] = s; assert_eq!(hh.shape(), shape); }
        assert!(h.is_live_slot(p));
        let big = h.new_string(&"x".repeat(100_000), &r);
        assert!(h.is_live_slot(big.as_obj().unwrap()));
        assert_eq!(unsafe { (*big.as_obj().unwrap().as_ptr()).class }, CLASS_LARGE);
    }

    #[test]
    fn collects_unreachable_keeps_reachable() {
        let mut h = Heap::new();
        h.oracle = true;
        let r = R(std::cell::RefCell::new(Vec::new()));
        let keep = h.new_table(&r);
        r.0.borrow_mut().push(keep);
        for i in 0..5000 {
            let s = h.new_string(&format!("s{i}"), &r);
            if i % 10 == 0 { let kp = keep.as_obj().unwrap(); h.barrier(kp, s); unsafe { let before = (*kp.as_ptr()).external_bytes(); let t = (*kp.as_ptr()).table(); t.array.push(s); (*kp.as_ptr()).refresh(); h.account_resize(before, (*kp.as_ptr()).external_bytes()); } }
        }
        let before = h.object_count();
        h.full_cycle(&r);
        h.check_oracle(&r);
        assert!(h.object_count() < before);
        assert_eq!(h.object_count(), 501);
        let big = h.new_string(&"y".repeat(50_000), &r);
        let _ = big;
        h.full_cycle(&r); h.check_oracle(&r);
        assert_eq!(h.object_count(), 501);
    }

    #[test]
    fn initialized_black_objects_trace_their_children() {
        for kind in 0..4 {
            let mut heap = Heap::new();
            let roots = R(std::cell::RefCell::new(Vec::new()));
            let child = heap.new_string("kept", &roots);
            roots.0.borrow_mut().push(child);
            // Leave marking busy on an unrelated chain. The constructor's
            // source is reachable, but still white behind that chain.
            let mut chain = child;
            let mut source_parent = Value::NIL;
            for _ in 0..3000 {
                let cell = heap.new_cell(chain, &roots);
                if source_parent == Value::NIL { source_parent = cell; }
                roots.0.borrow_mut()[0] = cell;
                chain = cell;
            }
            heap.debt = 0;
            heap.start(&roots);
            let made = match kind {
                0 => heap.new_cell(child, &roots),
                1 => heap.new_closure(0, &[child], &roots),
                2 => heap.new_slice(child, 0, 4, &roots),
                _ => heap.new_iter(0, child, child, vec![child], &roots),
            };
            assert!(heap.phase == Phase::Marking);
            roots.0.borrow_mut()[0] = made;
            // Transfer the reference: the old gray chain no longer reaches it.
            unsafe { (*source_parent.as_obj().unwrap().as_ptr()).slots_mut()[0] = Value::NIL; }
            heap.full_cycle(&roots);
            assert!(heap.is_live_slot(child.as_obj().unwrap()), "constructor {kind}");
            heap.check_oracle_with(&roots, false);
        }
    }

    #[test]
    fn interleaved_with_barrier_and_oracle() {
        let mut h = Heap::new();
        h.stress_steps = true; h.oracle = true; h.quarantine = true;
        let r = R(std::cell::RefCell::new(Vec::new()));
        let root = h.new_table(&r);
        r.0.borrow_mut().push(root);
        let mut last = root;
        for i in 0..3000 {
            let t = h.new_table(&r);
            let lp = last.as_obj().unwrap();
            h.barrier(lp, t);
            unsafe { let before = (*lp.as_ptr()).external_bytes(); (*lp.as_ptr()).table().array.push(t); (*lp.as_ptr()).refresh(); h.account_resize(before, (*lp.as_ptr()).external_bytes()); }
            if i % 7 == 0 { let s = h.intern(&format!("k{}", i % 50), &r); let tp = t.as_obj().unwrap(); h.barrier(tp, s); unsafe { (*tp.as_ptr()).table().hash.insert(s, Value::num(i as f64)); } }
            last = t;
        }
        h.full_cycle(&r); h.check_oracle(&r);
        assert!(h.object_count() >= 3001);
    }
}
