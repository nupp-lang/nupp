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
//! The collector is a precise, incremental, non-moving tri-color mark-sweep
//! with an insertion barrier, paced by allocation debt at safepoints, with
//! the four verification modes of 4.11 built in: stress, interleaved,
//! quarantine and the oracle.

use std::collections::{HashMap, HashSet};
use std::hash::BuildHasherDefault;
use std::ptr::NonNull;

use crate::value::{StrHasher, Value, fnv1a};
use crate::native_allocator::NativeAllocator;

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
/// A host object: a metatable, one Lua value, and Rust data the runtime
/// owns and drops with it (string buffers, compiled regular expressions).
pub const KIND_USERDATA: u8 = 10;
pub const KIND_INTEGER: u8 = 12;
pub const KIND_NAMES: [&str; 13] = ["freed", "string", "table", "record", "storage", "closure", "cell", "bytes", "iterator", "slice", "userdata", "reserved", "integer"];

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
/// A validated native storage descriptor, value, or declaration witness.
pub const F_NATIVE_STORAGE: u8 = 8;
/// A top-level native value allocation, as opposed to a borrowed subview.
pub const F_NATIVE_OWNED: u8 = 16;
/// Mutable tables participating in a validated physical layout.
pub const F_STORAGE_SCHEMA: u8 = 32;
/// A table some record shape names as its declaration: a store to it may
/// replace a method the shape dispatches (`Heap::declarations`).
pub const F_DECLARATION: u8 = 64;
/// A table some `__index` lookup walked as a metatable or an `__index`
/// target: a store to it may change what a cached lookup answered, so it
/// bumps `Heap::proto_epoch`, and the core's raw store fast paths refuse it.
pub const F_PROTO: u8 = 128;

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
// Hash descriptors and all storage policy live in Nupp. Rust borrows entries.
pub use crate::native_value_table::ValueTable;
pub const VT_EMPTY: u64 = Value::NIL.0;
#[repr(C)]
pub struct RecordExtra { pub fields: ValueTable, pub meta: Value }
pub use crate::native_record_tail::RecordTail;
impl std::ops::Deref for RecordExtra { type Target = ValueTable; fn deref(&self) -> &ValueTable { &self.fields } }
impl std::ops::DerefMut for RecordExtra { fn deref_mut(&mut self) -> &mut ValueTable { &mut self.fields } }
#[repr(C)]
pub struct TablePayload { pub array: crate::native_value_array::ValueArray, pub hash: ValueTable, pub meta: Value }
pub const OFF_T_HASH_PTR: i32 = (HEADER + std::mem::offset_of!(TablePayload, hash) + std::mem::offset_of!(ValueTable, ptr)) as i32;
pub const OFF_T_HASH_MASK: i32 = (HEADER + std::mem::offset_of!(TablePayload, hash) + std::mem::offset_of!(ValueTable, mask)) as i32;
pub const OFF_T_META: i32 = (HEADER + std::mem::offset_of!(TablePayload, meta)) as i32;
#[repr(C)]
pub struct StoragePayload { pub data: Vec<f64> }
#[repr(C)]
// Ordinary buffers retain Vec storage; native aggregates request an explicit
// allocation alignment. The header still exposes only a logical byte span.
// A shared block is an immutable allocation several VMs hold by reference
// (`crate::sharing`); a moved buffer is the husk an allocation left behind
// when its ownership went to another VM.
pub enum ByteBuffer { Bytes(Vec<u8>), Aligned(AlignedBytes), Shared(std::sync::Arc<crate::sharing::Block>), Moved }
pub struct AlignedBytes { pointer: NonNull<u8>, length: usize, layout: std::alloc::Layout }
// One owner at a time: the bytes are reached only through the owning object,
// so handing the allocation to another thread hands all access with it.
unsafe impl Send for AlignedBytes {}
impl AlignedBytes {
    /// The allocation's parts, which the caller now owns and must free with
    /// `layout`.
    pub(crate) fn into_raw(self) -> (NonNull<u8>, usize, std::alloc::Layout) {
        let parts = (self.pointer, self.length, self.layout);
        std::mem::forget(self);
        parts
    }
    pub(crate) fn len(&self) -> usize { self.length }
    pub(crate) fn alignment(&self) -> usize { self.layout.align() }
    pub(crate) fn bytes(&self) -> &[u8] { unsafe { std::slice::from_raw_parts(self.pointer.as_ptr(), self.length) } }
}
impl Drop for AlignedBytes {
    fn drop(&mut self) { unsafe { std::alloc::dealloc(self.pointer.as_ptr(), self.layout); } }
}
impl Default for ByteBuffer { fn default() -> Self { Self::Bytes(Vec::new()) } }
impl ByteBuffer {
    pub const MAX_ALIGNMENT: usize = 4096;
    pub fn aligned(length: usize, alignment: usize) -> Self {
        assert!(alignment.is_power_of_two() && alignment <= Self::MAX_ALIGNMENT);
        let layout = std::alloc::Layout::from_size_align(length.max(1), alignment).expect("aligned byte extent");
        let pointer = NonNull::new(unsafe { std::alloc::alloc_zeroed(layout) })
            .unwrap_or_else(|| std::alloc::handle_alloc_error(layout));
        Self::Aligned(AlignedBytes { pointer, length, layout })
    }
    pub fn is_fixed(&self) -> bool { !matches!(self, Self::Bytes(_)) }
    pub fn alignment(&self) -> usize { match self { Self::Bytes(_) | Self::Moved => 1, Self::Aligned(b) => b.layout.align(), Self::Shared(b) => b.alignment() } }
    pub fn capacity(&self) -> usize { match self { Self::Bytes(b) => b.capacity(), Self::Aligned(b) => b.layout.size(), Self::Shared(b) => b.capacity(), Self::Moved => 0 } }
    pub fn extend_from_slice(&mut self, bytes: &[u8]) {
        match self {
            Self::Bytes(b) => b.extend_from_slice(bytes),
            _ => panic!("fixed native allocation cannot grow"),
        }
    }
}
impl std::ops::Deref for ByteBuffer {
    type Target = [u8];
    fn deref(&self) -> &[u8] { match self { Self::Bytes(b) => b, Self::Aligned(b) => unsafe { std::slice::from_raw_parts(b.pointer.as_ptr(), b.length) }, Self::Shared(b) => b.bytes(), Self::Moved => &[] } }
}
// A shared block's bytes are never written: every storage view over one is
// read-only (`crate::sharing::is_shared`), so the mutable slice only mirrors
// the pointer into the header.
impl std::ops::DerefMut for ByteBuffer {
    fn deref_mut(&mut self) -> &mut [u8] { match self { Self::Bytes(b) => b, Self::Aligned(b) => unsafe { std::slice::from_raw_parts_mut(b.pointer.as_ptr(), b.length) }, Self::Shared(b) => unsafe { std::slice::from_raw_parts_mut(b.pointer(), b.len()) }, Self::Moved => &mut [] } }
}
pub struct BytesPayload { pub data: ByteBuffer }
/// Iteration state for `pairs` (1, over a key snapshot), `ipairs` (2) and
/// `gmatch` (3, `pattern` holds the pattern string).
#[repr(C)]
/// A userdata's payload: its metatable, its user value (traced) and the
/// native data behind it (dropped when the object is freed). `external`
/// is what the data owns outside the heap, fixed at creation.
pub struct UserdataPayload { pub meta: Value, pub uservalue: Value, pub data: Box<dyn std::any::Any>, pub external: usize }
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
    pub fn userdata(&self) -> &UserdataPayload { debug_assert!(self.kind == KIND_USERDATA); unsafe { &*(self.payload() as *const UserdataPayload) } }
    #[inline]
    pub fn userdata_mut(&mut self) -> &mut UserdataPayload { debug_assert!(self.kind == KIND_USERDATA); unsafe { &mut *(self.payload() as *mut UserdataPayload) } }
    #[inline]
    pub fn iter(&mut self) -> &mut IterPayload { debug_assert!(self.kind == KIND_ITER); unsafe { &mut *(self.payload() as *mut IterPayload) } }
    #[inline]
    pub fn slice(&self) -> &SlicePayload { debug_assert!(self.kind == KIND_SLICE); unsafe { &*(self.payload() as *const SlicePayload) } }
    #[inline]
    pub fn shape(&self) -> u32 { debug_assert!(self.kind == KIND_RECORD); self.aux }
    /// A record's ordered children: the array part a record type declares
    /// (`{cst.Node | lexer.Token}` inside the record), after its slots.
    #[inline]
    pub fn record_tail(&mut self) -> &mut RecordTail { debug_assert!(self.kind == KIND_RECORD); unsafe { &mut *(self.payload().add(8 * self.aux_len as usize) as *mut RecordTail) } }
    pub fn record_tail_ref(&self) -> &RecordTail { debug_assert!(self.kind == KIND_RECORD); unsafe { &*(self.payload().add(8 * self.aux_len as usize) as *const RecordTail) } }
    pub fn record_array(&mut self) -> &mut crate::native_value_array::ValueArray { &mut self.record_tail().array }
    pub fn record_array_ref(&self) -> &crate::native_value_array::ValueArray { &self.record_tail_ref().array }
    pub fn record_extra(&mut self) -> Option<&mut RecordExtra> { self.record_tail().extra_mut() }
    pub fn record_extra_ref(&self) -> Option<&RecordExtra> { self.record_tail_ref().extra() }
    pub fn ensure_record_extra(&mut self) -> &mut RecordExtra { self.record_tail().ensure_extra() }

    #[inline]
    pub fn fid(&self) -> u32 { debug_assert!(self.kind == KIND_CLOSURE); self.aux }
    /// Whether this object reads as a string: a string or a slice.
    #[inline]
    pub fn is_stringish(&self) -> bool { self.kind == KIND_STR || self.kind == KIND_SLICE }

    /// Bytes owned outside the inline allocation. A host mutating these raw
    /// payloads must report capacity changes through Heap::account_resize.
    pub fn external_bytes(&self) -> usize {
        #[cfg(feature = "allocation-metrics")]
        crate::allocation_metrics::observe(self);
        match self.kind {
            KIND_TABLE => { let t = self.table_ref(); 8 * t.array.capacity() + t.hash.backing_bytes() },
            KIND_RECORD => 8 * self.record_array_ref().capacity() + self.record_extra_ref().as_ref().map(|m| std::mem::size_of::<RecordExtra>() + m.backing_bytes()).unwrap_or(0),
            KIND_STORAGE => unsafe { 8 * (*(self.payload() as *const StoragePayload)).data.capacity() },
            KIND_BYTES => unsafe { (*(self.payload() as *const BytesPayload)).data.capacity() },
            KIND_ITER => unsafe { 8 * (*(self.payload() as *const IterPayload)).keys.capacity() },
            KIND_USERDATA => self.userdata().external,
            _ => 0,
        }
    }

    /// Re-mirrors the payload pointer and length after a growable payload
    /// changed (2.1: the runtime keeps them current whenever a payload moves).
    pub fn refresh(&mut self) {
        #[cfg(feature = "allocation-metrics")]
        crate::allocation_metrics::observe(self);
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
/// Nupp owns the hash; compiled object code calls the same leaf bridge.
#[inline] pub fn slot_hash(bits: u64) -> u64 {
    #[cfg(feature = "native-runtime")]
    { unsafe { nupp_object_slot_hash(bits) } }
    #[cfg(not(feature = "native-runtime"))]
    { let _ = bits; panic!("object hashing requires a linked Nupp core") }
}
#[cfg(feature = "native-runtime")]
unsafe extern "C" {
    fn nupp_object_slot_hash(bits: u64) -> u64;
    fn nupp_object_constructor_payload(kind: u64, count: u64) -> u64;
    fn nupp_object_record_initialize(header: *mut Header, owner: *mut std::ffi::c_void, shape: u64, count: u64) -> u64;
    fn nupp_object_string_initialize(header: *mut Header, count: u64) -> u64;
    fn nupp_object_slice_initialize(header: *mut Header, source: u64, offset: u64, count: u64) -> u64;
    fn nupp_object_cell_initialize(header: *mut Header, value: u64) -> u64;
    fn nupp_object_closure_initialize(header: *mut Header, function_id: u64, captures: *const Value, count: u64) -> u64;
    fn nupp_object_weak_lookup_action(phase: u64, color: u64, epoch: u64, cycle: u64, white: u64, marking: u64, sweeping: u64) -> u64;
    fn nupp_object_shape_capacity(count: u64) -> u64;
    fn nupp_object_shape_fill(names: *const Value, count: u64, table: *mut [u64; 2], capacity: u64) -> u64;
    fn nupp_object_shape_find(table: *const [u64; 2], capacity: u64, mask: u64, name: u64) -> u64;
}
#[cfg(feature = "native-runtime")]
const _: () = {
    assert!(crate::dispatch::OBJECT_ABI == 14);
    assert!(std::mem::size_of::<Value>() == 8);
    assert!(std::mem::size_of::<RecordTail>() == 40);
    assert!(std::mem::size_of::<RecordExtra>() == 64);
    assert!(std::mem::size_of::<[u64; 2]>() == 16);
    assert!(std::mem::align_of::<[u64; 2]>() == 8);
};
// Inline payload dimensions and initialization belong to the Nupp constructors.
fn constructor_payload(kind: u8, count: usize) -> usize {
    #[cfg(feature = "native-runtime")]
    {
        let bytes = unsafe { nupp_object_constructor_payload(kind as u64, count as u64) };
        assert_ne!(bytes, u64::MAX, "object constructor extent overflow");
        usize::try_from(bytes).expect("object constructor extent")
    }
    #[cfg(not(feature = "native-runtime"))]
    { let _ = (kind, count); panic!("object construction requires a linked Nupp core"); }
}
macro_rules! initialize_object {
    ($name:ident($($argument:expr),* $(,)?)) => {{
        #[cfg(feature = "native-runtime")]
        assert_eq!(unsafe { $name($($argument),*) }, 0, "invalid object constructor input");
        #[cfg(not(feature = "native-runtime"))]
        panic!("object construction requires a linked Nupp core");
    }};
}

impl Shape {
    /// The slot a name occupies, by the table.
    #[inline] pub fn slot_of(&self, name: Value) -> Option<usize> {
        #[cfg(feature = "native-runtime")]
        {
            let index = unsafe { nupp_object_shape_find(self.table.as_ptr(), self.table.len() as u64, self.mask, name.0) };
            (index != u64::MAX).then_some(index as usize)
        }
        #[cfg(not(feature = "native-runtime"))]
        { let _ = name; panic!("shape probing requires a linked Nupp core") }
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
    pub table: Vec<[u64; 2]>,
    pub mask: u64,
    /// The descriptor: method name (interned) to the function value that runs it.
    pub methods: HashMap<Value, Value, crate::value::BitsBuild>,
    /// Which metamethods the shape's declaration holds, as `metamethods::MM`
    /// bits, with `metamethods::CACHED` once computed; zero until then and
    /// after any store that may change the answer.
    pub mm_cache: u32,
}

/// Who can enumerate the roots (4.5): every task's registers, every frame's
/// closure, constant pools, handle scopes, registered handles.
pub trait Roots {
    fn each_root(&self, f: &mut dyn FnMut(Value));
    /// The roots a rescan while marking must revisit: those that can change.
    /// Immutable roots (constant pools) were marked when the cycle started,
    /// and what joins them later is allocated black or greyed on lookup.
    fn each_mutable_root(&self, f: &mut dyn FnMut(Value)) { self.each_root(f) }
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
enum Phase { Idle, Marking, Sweeping }

#[derive(Default, Debug, Clone)]
pub struct Stats { pub cycles: u64, pub freed: u64, pub allocated: u64, pub barrier_grays: u64, pub steps: u64, pub chunks: u64, pub large: u64,
    /// Kept for `GC_STATS=1`: objects scanned, slots swept, root walks and
    /// their candidates, the largest live size, and time inside collection.
    pub scanned: u64, pub swept: u64, pub root_walks: u64, pub root_candidates: u64, pub peak_live: u64, pub gc_nanos: u64 }

pub struct Heap {
    // Native queue references follow their managed endpoint's lifetime. This
    // side table does not root endpoints; sweep drops the Arc before slot reuse.
    pub(crate) channels: HashMap<Value, crate::channels::Channel, crate::value::BitsBuild>,
    allocator: NativeAllocator,
    chunk_bytes_mapped: u64,
    live_count: usize,
    /// The root walk's candidate buffer, kept between walks.
    root_candidates: Vec<NonNull<Header>>,
    /// `GC_STATS=1`: time collection and report it at exit.
    timed: bool,
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
    /// Shapes by the declaration they were emitted for, so a record type that
    /// several images name loads as one shape and keeps one method table.
    pub shape_identities: HashMap<String, u32>,
    interned: HashMap<Box<[u8]>, NonNull<Header>, BuildHasherDefault<StrHasher>>,
    integers: HashMap<(bool, u64), NonNull<Header>>,
    pub stats: Stats,
    /// Invalidates physical layout facts after schema writes or reclamation.
    /// Saturation disables the cache instead of allowing version reuse.
    pub storage_version: u64,
    pub alloc_kinds: [u64; 13],
    /// 1 while marking: the threaded core reads it to decide whether a store
    /// needs the barrier's slow path.
    pub marking: u8,
    /// Tables this cycle scanned under a weak `__mode`, with the mode's bits
    /// (`WEAK_KEYS`, `WEAK_VALUES`); their dead entries are cleared when
    /// marking ends, before the sweep frees the referents.
    weak: Vec<(NonNull<Header>, u8)>,
    /// The shapes each declaration table (`F_DECLARATION`) declares, by the
    /// table's bits. A shape keeps its declaration alive while an instance of
    /// it is, so the bits hold; an entry goes when its table dies.
    pub declarations: HashMap<u64, Vec<u32>, crate::value::BitsBuild>,
    /// The interned `"__mode"` key's bits for this cycle, or nil's bits when
    /// no such string exists (so no metatable can name a mode).
    mode_key: u64,
    /// One bit per metamethod name (`metamethods::MM`) whose string has ever
    /// been interned. A key that was never a string is in no table, so an
    /// operation whose bit is clear has no metamethod to find.
    pub mm_seen: u32,
    /// The metamethod names as interned strings, filled on first use and
    /// held as roots so the bits stay valid; `VT_EMPTY` until then.
    pub mm_keys: [u64; crate::metamethods::COUNT],
    /// Bumped by any store to an `F_PROTO` object or a shape's methods.
    pub proto_epoch: u64,
    /// `(metatable, key)` to what the `__index` chain answered and the epoch
    /// it was answered in. Cleared when a sweep starts, before anything it
    /// names can be freed and its address reused.
    pub proto_cache: HashMap<(u64, u64), (u64, u64)>,
    /// The interned `"\0nupp:recordType"` key's bits for this cycle, and the
    /// shapes an instance of which this cycle marked. A shape's declaration
    /// (its record type, the table a `local record` creates) is held through
    /// the shape only while the shape has a live instance, as an instance's
    /// metatable holds it under LuaJIT; the code that constructs one names
    /// the declaration itself. So a record type nothing uses is collected.
    record_type_key: u64,
    live_shapes: Vec<bool>,
    #[cfg(feature = "allocation-metrics")]
    metrics: Option<crate::allocation_metrics::Handle>,
}

const WEAK_KEYS: u8 = 1;
const WEAK_VALUES: u8 = 2;

thread_local! { static NEVER: bool = std::env::var("GC_NEVER").is_ok(); }

impl Heap {
    pub fn new() -> Heap {
        let env = |k: &str| std::env::var(k).is_ok();
        Heap { channels: HashMap::default(), allocator: NativeAllocator::new(), chunk_bytes_mapped: 0, live_count: 0, root_candidates: Vec::new(), timed: env("GC_STATS"), phase: Phase::Idle, sweep_chunk: 0, sweep_slot: 0, sweep_large: 0, debt: 0, threshold: 1 << 20, live_bytes: 0, automatic_collection: true, stress: env("GC_STRESS"), stress_steps: env("GC_INTERLEAVE"), oracle: env("GC_ORACLE"), quarantine: env("GC_QUARANTINE"), shapes: Vec::new(), shape_identities: HashMap::new(), interned: HashMap::default(), integers: HashMap::new(), stats: Stats::default(), storage_version: 0, alloc_kinds: [0; 13], marking: 0, weak: Vec::new(), mode_key: VT_EMPTY, record_type_key: VT_EMPTY, live_shapes: Vec::new(), declarations: HashMap::default(), mm_seen: 0, mm_keys: [VT_EMPTY; crate::metamethods::COUNT], proto_epoch: 0, proto_cache: HashMap::new(),
            #[cfg(feature = "allocation-metrics")]
            metrics: crate::allocation_metrics::new(),
        }
    }

    pub fn shape(&mut self, name: &str, names: &[Value], types: &[SlotTy]) -> u32 {
        #[cfg(feature = "native-runtime")]
        {
            let size = unsafe { nupp_object_shape_capacity(names.len() as u64) };
            assert!(size != 0, "shape exceeds the slot index range");
            let mut table = vec![[0u64; 2]; usize::try_from(size).expect("shape capacity")];
            let mask = unsafe { nupp_object_shape_fill(names.as_ptr(), names.len() as u64, table.as_mut_ptr(), size) };
            self.shapes.push(Shape { name: name.to_string(), structural: name.starts_with("struct:"), names: names.to_vec(), types: types.to_vec(), methods: HashMap::default(), table, mask, mm_cache: 0 });
            (self.shapes.len() - 1) as u32
        }
        #[cfg(not(feature = "native-runtime"))]
        { let _ = (name, names, types); panic!("shape construction requires a linked Nupp core") }
    }

    /// Keep GC pacing and retained-byte accounting consistent with native
    /// payload capacities, including relocation into freshly restored objects.
    pub fn account_resize(&mut self, before: usize, after: usize) {
        #[cfg(feature = "allocation-metrics")]
        if let Some(m) = &self.metrics { m.borrow_mut().external_capacity_added += after.saturating_sub(before) as u64; }
        self.allocator.resize(before, after, self.debt);
        self.sync_allocator();
    }

    // The Nupp allocator owns these counters. Rust retains mirrors for the
    // collector's pacing and public diagnostics, never a second calculation.
    fn sync_allocator(&mut self) {
        let [count, bytes, debt, allocated, freed, chunks, large, mapped, barrier_grays] = self.allocator.snapshot();
        self.stats.barrier_grays = barrier_grays;
        self.live_count = usize::try_from(count).expect("live object count");
        self.live_bytes = usize::try_from(bytes).expect("live byte count");
        self.debt = usize::try_from(debt).expect("allocation debt");
        self.stats.allocated = allocated;
        self.stats.freed = freed;
        self.stats.chunks = chunks;
        self.stats.large = large;
        #[cfg(feature = "allocation-metrics")]
        if let Some(m) = &self.metrics { m.borrow_mut().chunk_bytes_requested += mapped - self.chunk_bytes_mapped; }
        self.chunk_bytes_mapped = mapped;
    }

    fn clear_debt(&mut self) {
        self.allocator.resize(0, 0, 0);
        self.sync_allocator();
    }

    // ---- allocation -----------------------------------------------------

    /// Allocation cannot collect. The caller ran its safepoint and published
    /// roots before entering the Nupp allocator.
    fn alloc_raw(&mut self, kind: u8, inline_bytes: usize) -> NonNull<Header> {
        HEADER.checked_add(inline_bytes).filter(|&size| size <= u32::MAX as usize).expect("object extent overflow");
        let p = self.allocator.allocate(kind, inline_bytes, self.phase as i64, self.stats.cycles, self.sweep_chunk, self.sweep_slot, self.debt);
        self.sync_allocator();
        let h = unsafe { p.as_ref() };
        crate::heap_trace::allocated(p.as_ptr(), kind, h.size as usize);
        self.alloc_kinds[kind as usize] += 1;
        #[cfg(feature = "allocation-metrics")]
        if let Some(m) = &self.metrics { m.borrow_mut().allocate_inline(kind, h.size as usize, if h.class == CLASS_LARGE { h.size as usize } else { NativeAllocator::slot_bytes(h.class) }, h.class == CLASS_LARGE); }
        p
    }

    /// Allocation is a safepoint: the collector may run here, so every value
    /// the caller still needs must be reachable from the roots at this point.
    fn alloc(&mut self, kind: u8, inline_bytes: usize, roots: &dyn Roots) -> NonNull<Header> {
        self.safepoint(roots);
        self.alloc_raw(kind, inline_bytes)
    }

    /// A fresh, uninterned string of `n` bytes (hash 0 until needed) whose
    /// bytes the caller writes before anything reads them: the native core
    /// fills a concatenation or a substring in place. Only the terminator is
    /// written here.
    pub fn new_string_blank(&mut self, n: usize, roots: &dyn Roots) -> Value {
        let p = self.alloc(KIND_STR, constructor_payload(KIND_STR, n), roots);
        initialize_object!(nupp_object_string_initialize(p.as_ptr(), n as u64));
        #[cfg(feature = "allocation-metrics")]
        crate::allocation_metrics::register(&self.metrics, unsafe { p.as_ref() });
        Value::obj(p)
    }
    /// A fresh, uninterned string with these bytes.
    pub fn new_string_bytes(&mut self, bytes: &[u8], roots: &dyn Roots) -> Value {
        let v = self.new_string_blank(bytes.len(), roots);
        unsafe { std::ptr::copy_nonoverlapping(bytes.as_ptr(), (*v.as_obj().unwrap().as_ptr()).aux_ptr, bytes.len()); }
        v
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
        self.mark_interned(v);
        v
    }
    /// Interns a fresh string in place (1.3): the live interned string with
    /// its bytes when there is one, else this string, now interned. Allocates
    /// nothing; the native core calls it on a string it has just filled.
    pub fn intern_string(&mut self, v: Value) -> Value {
        let bytes: &[u8] = unsafe { (*v.as_obj().expect("intern of a non-object").as_ptr()).bytes() };
        if let Some(found) = self.intern_lookup_bytes(bytes) { return found; }
        self.mark_interned(v);
        v
    }
    /// Enters a fresh string into the intern table: the one insertion routine.
    fn mark_interned(&mut self, v: Value) {
        let p = v.as_obj().unwrap();
        let s: &[u8] = unsafe { let h = &mut *p.as_ptr(); h.flags |= F_INTERNED; (*(h.payload() as *mut StrPayload)).hash = fnv1a(h.bytes()); h.bytes() };
        if s.starts_with(b"__") { self.mm_seen |= crate::metamethods::bit_of(s); }
        self.interned.insert(s.into(), p);
    }
    /// The interned string with these bytes, if one is alive, allocating nothing.
    // For immediate table lookup only: this does not root or resurrect a key.
    pub(crate) fn interned_key(&self, s: &str) -> Option<Value> { self.interned.get(s.as_bytes()).map(|p| Value::obj(*p)) }
    pub fn intern_lookup(&mut self, s: &str) -> Option<Value> { self.intern_lookup_bytes(s.as_bytes()) }
    pub fn intern_lookup_bytes(&mut self, s: &[u8]) -> Option<Value> {
        let p = *self.interned.get(s)?;
        if !self.weak_lookup_hit(p) { self.interned.remove(s); return None; }
        Some(Value::obj(p))
    }
    // The map/header stay owned throughout this scalar call. Gray queue
    // allocation is host backing only; no guest callback or collection runs.
    fn weak_lookup_hit(&mut self, p: NonNull<Header>) -> bool {
        #[cfg(feature = "native-runtime")]
        unsafe {
            let h = &mut *p.as_ptr();
            let action = nupp_object_weak_lookup_action(self.phase as u64, h.color as u64, h.epoch as u64, self.stats.cycles, COLOR_WHITE as u64, Phase::Marking as u64, Phase::Sweeping as u64);
            match action {
                0 => true,
                1 => { self.allocator.barrier_shade(Value::obj(p)); self.sync_allocator(); true }
                2 => false,
                _ => panic!("invalid Nupp weak lookup action"),
            }
        }
        #[cfg(not(feature = "native-runtime"))]
        { let _ = p; panic!("weak lookup policy requires a linked Nupp core") }
    }

    pub fn integer_key(&self, bits: u64) -> Option<Value> { self.integers.get(&(false, bits)).map(|p| Value::obj(*p)) }
    pub fn integer_value(&self, value: crate::numeric::Integer) -> Option<Value> { self.integers.get(&(value.unsigned, value.bits)).map(|p| Value::obj(*p)) }
    pub fn integer_lookup(&mut self, value: crate::numeric::Integer) -> Option<Value> {
        let key = (value.unsigned, value.bits);
        let p = *self.integers.get(&key)?;
        if !self.weak_lookup_hit(p) { self.integers.remove(&key); return None; }
        Some(Value::obj(p))
    }
    pub fn box_integer(&mut self, value: crate::numeric::Integer, roots: &dyn Roots) -> Value {
        let value = crate::numeric::Integer { bits: value.bits, unsigned: false };
        if let Some(v) = value.immediate().or_else(|| self.integer_lookup(value)) { return v; }
        let p = self.alloc(KIND_INTEGER, 0, roots);
        unsafe { let h = &mut *p.as_ptr(); h.aux = value.unsigned as u32; h.aux_len = value.bits; }
        self.integers.insert((value.unsigned, value.bits), p);
        #[cfg(feature = "allocation-metrics")]
        crate::allocation_metrics::register(&self.metrics, unsafe { p.as_ref() });
        Value::obj(p)
    }

    pub fn new_slice(&mut self, source: Value, off: u32, len: u32, roots: &dyn Roots) -> Value {
        let p = self.alloc(KIND_SLICE, constructor_payload(KIND_SLICE, 0), roots);
        initialize_object!(nupp_object_slice_initialize(p.as_ptr(), source.0, off as u64, len as u64));
        // Allocation is black during marking; initial references need the
        // same insertion barrier as later stores.
        if self.phase == Phase::Marking { self.scan(p); }
        #[cfg(feature = "allocation-metrics")]
        crate::allocation_metrics::register(&self.metrics, unsafe { p.as_ref() });
        Value::obj(p)
    }

    pub fn new_table_sized(&mut self, n: usize, m: usize, roots: &dyn Roots) -> Value {
        if crate::interp::TABLE_STATS.load(std::sync::atomic::Ordering::Relaxed) { crate::interp::TABLE_COUNTS[if n + m == 0 { 4 } else { 4 }].fetch_add(0, std::sync::atomic::Ordering::Relaxed); NEW_TABLES.fetch_add(1, std::sync::atomic::Ordering::Relaxed); }
        // Backing reservation can fail. Finish it before publishing a live
        // header; this empty payload holds no guest edges across alloc's GC.
        let payload = TablePayload { array: self.allocator.value_array(n), hash: self.allocator.value_table(m), meta: Value::NIL };
        let p = self.alloc(KIND_TABLE, std::mem::size_of::<TablePayload>(), roots);
        unsafe {
            let h = &mut *p.as_ptr();
            (h.payload() as *mut TablePayload).write(payload);
            h.refresh();
        }
        self.account_resize(0, unsafe { p.as_ref().external_bytes() });
        #[cfg(feature = "allocation-metrics")]
        crate::allocation_metrics::register(&self.metrics, unsafe { p.as_ref() });
        Value::obj(p)
    }
    pub fn new_table(&mut self, roots: &dyn Roots) -> Value { self.new_table_sized(0, 0, roots) }

    // Borrowed-storage construction for embedding fixtures. The returned table
    // and all its entry borrows must be dropped before this Heap.
    pub unsafe fn value_table(&self, capacity: usize) -> ValueTable {
        self.allocator.value_table(capacity)
    }

    pub fn new_record(&mut self, shape: u32, roots: &dyn Roots) -> Value {
        let n = self.shapes[shape as usize].names.len();
        let p = self.alloc(KIND_RECORD, constructor_payload(KIND_RECORD, n), roots);
        initialize_object!(nupp_object_record_initialize(p.as_ptr(), self.allocator.heap_pointer(), shape as u64, n as u64));
        // Allocated black during marking, so never scanned: its shape's
        // declaration is held for it here.
        if self.phase == Phase::Marking { if let Some(live) = self.live_shapes.get_mut(shape as usize) { *live = true; } }
        #[cfg(feature = "allocation-metrics")]
        crate::allocation_metrics::register(&self.metrics, unsafe { p.as_ref() });
        Value::obj(p)
    }
    pub fn new_closure(&mut self, fid: u32, captures: &[Value], roots: &dyn Roots) -> Value {
        let p = self.alloc(KIND_CLOSURE, constructor_payload(KIND_CLOSURE, captures.len()), roots);
        initialize_object!(nupp_object_closure_initialize(p.as_ptr(), fid as u64, captures.as_ptr(), captures.len() as u64));
        // Allocation is black during marking; initial references need the
        // same insertion barrier as later stores.
        if self.phase == Phase::Marking { self.scan(p); }
        #[cfg(feature = "allocation-metrics")]
        crate::allocation_metrics::register(&self.metrics, unsafe { p.as_ref() });
        Value::obj(p)
    }
    pub fn new_cell(&mut self, value: Value, roots: &dyn Roots) -> Value {
        let p = self.alloc(KIND_CELL, constructor_payload(KIND_CELL, 0), roots);
        initialize_object!(nupp_object_cell_initialize(p.as_ptr(), value.0));
        // Allocation is black during marking; initial references need the
        // same insertion barrier as later stores.
        if self.phase == Phase::Marking { self.scan(p); }
        #[cfg(feature = "allocation-metrics")]
        crate::allocation_metrics::register(&self.metrics, unsafe { p.as_ref() });
        Value::obj(p)
    }
    pub fn new_iter(&mut self, kind: u8, obj: Value, pattern: Value, keys: Vec<Value>, roots: &dyn Roots) -> Value {
        let p = self.alloc(KIND_ITER, std::mem::size_of::<IterPayload>(), roots);
        unsafe { let h = &mut *p.as_ptr(); h.aux = kind as u32; (h.payload() as *mut IterPayload).write(IterPayload { obj, pattern, pos: 0, keys }); h.refresh(); }
        // Allocation is black during marking; initial references need the
        // same insertion barrier as later stores.
        if self.phase == Phase::Marking { self.scan(p); }
        self.account_resize(0, unsafe { p.as_ref().external_bytes() });
        #[cfg(feature = "allocation-metrics")]
        crate::allocation_metrics::register(&self.metrics, unsafe { p.as_ref() });
        Value::obj(p)
    }
    /// A userdata over `data`. The caller keeps `meta` and `uservalue`
    /// reachable: the allocation is a safepoint.
    pub fn new_userdata(&mut self, data: Box<dyn std::any::Any>, meta: Value, uservalue: Value, external: usize, roots: &dyn Roots) -> Value {
        let p = self.alloc(KIND_USERDATA, std::mem::size_of::<UserdataPayload>(), roots);
        unsafe { let h = &mut *p.as_ptr(); (h.payload() as *mut UserdataPayload).write(UserdataPayload { meta, uservalue, data, external }); h.aux_len = 0; }
        // Allocation is black during marking; initial references need the
        // same insertion barrier as later stores.
        if self.phase == Phase::Marking { self.scan(p); }
        self.account_resize(0, external);
        #[cfg(feature = "allocation-metrics")]
        crate::allocation_metrics::register(&self.metrics, unsafe { p.as_ref() });
        Value::obj(p)
    }
    pub fn new_bytes(&mut self, n: usize, roots: &dyn Roots) -> Value {
        let p = self.alloc(KIND_BYTES, std::mem::size_of::<BytesPayload>(), roots);
        unsafe { let h = &mut *p.as_ptr(); (h.payload() as *mut BytesPayload).write(BytesPayload { data: ByteBuffer::Bytes(vec![0u8; n]) }); h.refresh(); }
        self.account_resize(0, n);
        #[cfg(feature = "allocation-metrics")]
        crate::allocation_metrics::register(&self.metrics, unsafe { p.as_ref() });
        Value::obj(p)
    }
    pub fn new_aligned_bytes(&mut self, n: usize, alignment: usize, roots: &dyn Roots) -> Value {
        let data = ByteBuffer::aligned(n, alignment);
        let size = data.capacity();
        let p = self.alloc(KIND_BYTES, std::mem::size_of::<BytesPayload>(), roots);
        unsafe { let h = &mut *p.as_ptr(); (h.payload() as *mut BytesPayload).write(BytesPayload { data }); h.refresh(); }
        self.account_resize(0, size);
        #[cfg(feature = "allocation-metrics")]
        crate::allocation_metrics::register(&self.metrics, unsafe { p.as_ref() });
        Value::obj(p)
    }
    /// A growable buffer with room for a short result before it reallocates.
    pub fn new_buffer(&mut self, roots: &dyn Roots) -> Value {
        let p = self.alloc(KIND_BYTES, std::mem::size_of::<BytesPayload>(), roots);
        unsafe { let h = &mut *p.as_ptr(); (h.payload() as *mut BytesPayload).write(BytesPayload { data: ByteBuffer::Bytes(Vec::with_capacity(64)) }); h.refresh(); }
        self.account_resize(0, unsafe { p.as_ref().external_bytes() });
        #[cfg(feature = "allocation-metrics")]
        crate::allocation_metrics::register(&self.metrics, unsafe { p.as_ref() });
        Value::obj(p)
    }
    pub fn new_storage(&mut self, n: usize, roots: &dyn Roots) -> Value {
        let p = self.alloc(KIND_STORAGE, std::mem::size_of::<StoragePayload>(), roots);
        unsafe { let h = &mut *p.as_ptr(); (h.payload() as *mut StoragePayload).write(StoragePayload { data: vec![0.0; n] }); h.refresh(); }
        self.account_resize(0, 8 * n);
        #[cfg(feature = "allocation-metrics")]
        crate::allocation_metrics::register(&self.metrics, unsafe { p.as_ref() });
        Value::obj(p)
    }

    // ---- the collector ---------------------------------------------------

    #[inline]
    pub fn schema_write(&mut self, object: NonNull<Header>) {
        let flags = unsafe { object.as_ref().flags };
        if flags & (F_STORAGE_SCHEMA | F_PROTO) == 0 { return; }
        if flags & F_STORAGE_SCHEMA != 0 {
            self.storage_version = self.storage_version.saturating_add(1);
        }
        if flags & F_PROTO != 0 { self.proto_epoch += 1; }
    }

    /// The insertion barrier (4.2): storing a white child into a black parent
    /// while marking greys the child. Every heap store goes through here.
    #[inline]
    pub fn barrier(&mut self, parent: NonNull<Header>, child: Value) {
        self.schema_write(parent);
        self.allocator.barrier(parent, child, self.phase == Phase::Marking);
        self.sync_allocator();
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
        if self.timed {
            let started = std::time::Instant::now();
            self.step(budget, roots);
            self.stats.gc_nanos += started.elapsed().as_nanos() as u64;
        } else {
            self.step(budget, roots);
        }
        self.clear_debt();
    }

    /// The `GC_STATS=1` summary line, on standard error.
    pub fn report_stats(&self, reason: &str) {
        if !self.timed { return; }
        let s = &self.stats;
        eprintln!("gc[{reason}]: {:.2}s in {} cycles, {} steps; scanned {} swept {} roots {} walks/{} candidates; allocated {} freed {}; live {} MB peak {} MB; chunks {} large {}",
            s.gc_nanos as f64 / 1e9, s.cycles, s.steps, s.scanned, s.swept, s.root_walks, s.root_candidates, s.allocated, s.freed, self.live_bytes >> 20, s.peak_live >> 20, self.allocator.chunk_count(), self.allocator.large_count());
    }

    fn start(&mut self, roots: &dyn Roots) {
        self.phase = Phase::Marking;
        self.marking = 1;
        self.stats.cycles += 1;
        self.weak.clear();
        // Looked up before marking begins, so the lookup greys nothing; a
        // metatable naming `__mode` holds the string, so it stays alive and
        // keeps these bits for the cycle.
        self.mode_key = self.interned.get(&b"__mode"[..]).map_or(VT_EMPTY, |p| Value::obj(*p).0);
        self.record_type_key = self.interned.get(&b"\0nupp:recordType"[..]).map_or(VT_EMPTY, |p| Value::obj(*p).0);
        self.live_shapes.clear();
        self.live_shapes.resize(self.shapes.len(), false);
        self.mark_roots(roots, false);
    }

    /// The weak mode a table's metatable declares (Lua 5.1: `__mode` holding
    /// `k`, `v` or both), or 0.
    pub(crate) fn weak_mode(&self, h: &Header) -> u8 {
        if self.mode_key == VT_EMPTY { return 0; }
        let Some(meta) = h.table_ref().meta.as_obj() else { return 0 };
        let m = unsafe { &*meta.as_ptr() };
        let key = Value(self.mode_key);
        // A metatable built by a constructor may be a record of the shape the
        // constructor inferred, `__mode` one of its slots.
        let mode = match m.kind {
            KIND_TABLE => m.table_ref().hash.get(&key).copied(),
            KIND_RECORD => match self.shapes[m.shape() as usize].slot_of(key) {
                Some(i) => m.slots().get(i).copied(),
                None => m.record_extra_ref().as_ref().and_then(|extra| extra.get(&key).copied()),
            },
            _ => None,
        };
        let Some(mode) = mode.and_then(|v| v.as_obj()) else { return 0 };
        let mode = unsafe { &*mode.as_ptr() };
        if !mode.is_stringish() { return 0; }
        let text: &[u8] = if mode.kind == KIND_STR { mode.bytes() } else {
            let s = mode.slice();
            match s.source.as_obj() { Some(src) => { let b = unsafe { (*src.as_ptr()).bytes() }; &b[s.off as usize..(s.off + s.len) as usize] } None => return 0 }
        };
        let mut bits = 0;
        if text.contains(&b'k') { bits |= WEAK_KEYS; }
        if text.contains(&b'v') { bits |= WEAK_VALUES; }
        bits
    }

    /// Drops every weak entry whose weak side is still white. Runs once
    /// marking has finished, so white here means unreachable but for weak
    /// references; the sweep that follows frees those objects.
    fn clear_weak(&mut self) {
        for (p, mode) in std::mem::take(&mut self.weak) {
            let h = unsafe { &mut *p.as_ptr() };
            if h.kind != KIND_TABLE { continue; }
            let t = h.table();
            // Vec owns the array; Nupp borrows only its initialized words and
            // canonical buckets, without collection or callbacks across the view.
            let (length, changed) = unsafe { NativeAllocator::weak_clear(t.array.as_mut_ptr(), t.array.len(), t.hash.ptr, t.hash.cap, mode) };
            t.array.truncate(length);
            h.refresh();
            // A cleared entry of a table an `__index` lookup walked changes
            // what the lookup answers, as a store would: compiled code that
            // resolved through it must not call what is about to be freed.
            if changed && h.flags & F_PROTO != 0 { self.proto_epoch += 1; }
        }
    }

    /// Whether `p` addresses a live object: a slot of a chunk on a slot
    /// boundary, or a large object, and not freed (5.1: the root walk accepts
    /// a register word only when it addresses a live slot).
    pub fn is_live_slot(&self, p: NonNull<Header>) -> bool {
        self.allocator.is_live_slot(p)
    }

    fn mark_roots(&mut self, roots: &dyn Roots, rescan: bool) {
        let mut cands: Vec<NonNull<Header>> = std::mem::take(&mut self.root_candidates);
        cands.clear();
        #[cfg(feature = "allocation-metrics")]
        let mut root_slots = 0u64;
        let mut visit = |v: Value| {
            #[cfg(feature = "allocation-metrics")]
            { root_slots += 1; }
            if let Some(p) = v.as_obj() { cands.push(p); }
        };
        if rescan { roots.each_mutable_root(&mut visit); } else { roots.each_root(&mut visit); }
        self.stats.root_walks += 1;
        self.stats.root_candidates += cands.len() as u64;
        #[cfg(feature = "allocation-metrics")]
        if let Some(m) = &self.metrics { let mut m = m.borrow_mut(); m.root_slots += root_slots; m.root_object_candidates += cands.len() as u64; m.root_passes += 1; }
        for &p in &cands {
            if !self.is_live_slot(p) { continue; }
            self.allocator.shade(Value::obj(p));
        }
        self.root_candidates = cands;
        #[cfg(feature = "allocation-metrics")]
        if let Some(m) = &self.metrics { m.borrow_mut().shape_root_slots += self.shapes.iter().map(|s| s.names.len() + 2 * s.methods.len()).sum::<usize>() as u64; }
        let allocator = &mut self.allocator;
        let (key, declarations, live) = (self.record_type_key, &self.declarations, &self.live_shapes);
        for (id, s) in self.shapes.iter().enumerate() {
            let held = |k: &Value, v: &Value| k.0 != key || live.get(id).copied().unwrap_or(true) || !declarations.contains_key(&v.0);
            for &n in s.names.iter().chain(s.methods.keys()).chain(s.methods.iter().filter(|(k, v)| held(k, v)).map(|(_, v)| v)) { allocator.shade(n); }
        }
        for &k in &self.mm_keys { allocator.shade(Value(k)); }
    }

    /// Once marking is done: a declaration no live instance or reference
    /// kept is dropped from its shapes before the sweep frees it.
    fn clear_dead_declarations(&mut self) {
        let dead = |bits: u64| Value(bits).as_obj().is_some_and(|p| unsafe { (*p.as_ptr()).color == COLOR_WHITE });
        let key = Value(self.record_type_key);
        let gone: Vec<(u64, Vec<u32>)> = self.declarations.iter().filter(|&(&bits, _)| dead(bits)).map(|(&bits, shapes)| (bits, shapes.clone())).collect();
        for (bits, shapes) in gone {
            self.declarations.remove(&bits);
            for shape in shapes {
                let methods = &mut self.shapes[shape as usize].methods;
                if methods.get(&key).is_some_and(|v| v.0 == bits) { methods.remove(&key); self.proto_epoch += 1; }
            }
        }
    }

    /// Every reference an object holds, by kind: the one walk the marker, the
    /// oracle and the serializer share.
    pub fn each_child(h: &Header, f: &mut dyn FnMut(Value)) {
        match h.kind {
            KIND_TABLE => { let t = h.table_ref(); for &v in &t.array { f(v); } for (k, v) in t.hash.iter() { f(*k); f(*v); } if t.meta != Value::NIL { f(t.meta); } }
            KIND_RECORD => { for &v in h.slots() { f(v); } for &v in h.record_array_ref() { f(v); } if let Some(m) = h.record_extra_ref() { f(m.meta); for (k, v) in m.iter() { f(*k); f(*v); } } }
            KIND_CLOSURE | KIND_CELL => { for &v in h.slots() { f(v); } }
            KIND_SLICE => f(h.slice().source),
            KIND_ITER => { let i = unsafe { &*(h.payload() as *const IterPayload) }; f(i.obj); f(i.pattern); for &v in &i.keys { f(v); } }
            KIND_USERDATA => { let u = h.userdata(); f(u.meta); f(u.uservalue); }
            _ => {}
        }
    }

    fn scan(&mut self, p: NonNull<Header>) {
        self.stats.scanned += 1;
        let h = unsafe { &*p.as_ptr() };
        if h.kind == KIND_TABLE && h.table_ref().meta != Value::NIL {
            let mode = self.weak_mode(h);
            if mode != 0 { self.scan_weak(p, mode); return; }
        }
        if h.kind == KIND_RECORD {
            let shape = h.shape() as usize;
            if let Some(live) = self.live_shapes.get_mut(shape) { *live = true; }
        }
        let allocator = &mut self.allocator;
        #[cfg(feature = "allocation-metrics")]
        let mut children = 0u64;
        Self::each_child(h, &mut |v| {
            #[cfg(feature = "allocation-metrics")]
            { children += 1; }
            allocator.shade(v); });
        #[cfg(feature = "allocation-metrics")]
        if let Some(m) = &self.metrics { let mut m = m.borrow_mut(); m.scanned_objects += 1; m.child_slots += children; }
        unsafe { (*p.as_ptr()).color = COLOR_BLACK; }
    }

    /// A weak table's strong references: its metatable and both sides of
    /// every entry that will survive. An entry survives when each weak side
    /// is a string or boxed integer (never cleared) or already marked; until
    /// then neither side is marked, as an ephemeron, because the entry may
    /// yet be dropped and a side marked for it would outlive it unreachable.
    /// The table is remembered so `propagate_weak` can revisit entries whose
    /// weak side is marked later, and `clear_weak` can drop what dies.
    fn scan_weak(&mut self, p: NonNull<Header>, mode: u8) {
        let t = unsafe { (*p.as_ptr()).table_ref() };
        Self::mark_live_entries(&mut self.allocator, t, mode);
        self.allocator.shade(t.meta);
        self.weak.push((p, mode));
        unsafe { (*p.as_ptr()).color = COLOR_BLACK; }
    }

    /// Greys both sides of every entry of a weak table that survives as
    /// marking stands; answers whether anything was greyed.
    fn mark_live_entries(allocator: &mut NativeAllocator, t: &TablePayload, mode: u8) -> bool {
        // The shared policy reads initialized words, not Rust container layouts.
        unsafe { allocator.weak_mark(t.array.as_ptr(), t.array.len(), t.hash.ptr, t.hash.cap, mode) }
    }

    /// Revisits every weak table this cycle scanned once marking has drained:
    /// an entry whose weak side was marked after its table was scanned now
    /// survives, so its other side is marked too. Answers whether marking
    /// has more to do.
    fn propagate_weak(&mut self) -> bool {
        let mut greyed = false;
        for &(p, mode) in &self.weak {
            let h = unsafe { &*p.as_ptr() };
            if h.kind != KIND_TABLE { continue; }
            greyed |= Self::mark_live_entries(&mut self.allocator, h.table_ref(), mode);
        }
        greyed
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
                    while budget > 0 { match self.allocator.gray_pop() { Some(p) => { self.scan(p); budget -= 1; } None => break } }
                    if budget == 0 { return; }
                    self.mark_roots(roots, true);
                    if !self.allocator.gray_empty() || self.propagate_weak() { continue; }
                    crate::heap_trace::marked(self, roots);
                    self.clear_weak();
                    self.proto_cache.clear();
                    self.clear_dead_declarations();
                    self.phase = Phase::Sweeping;
                    self.marking = 0;
                    self.sweep_chunk = 0; self.sweep_slot = 0; self.sweep_large = 0;
                }
                Phase::Sweeping => {
                    let mut work = budget * 4;
                    while self.sweep_chunk < self.allocator.chunk_count() && work > 0 {
                        let [base, slot_size, nslots] = self.allocator.chunk(self.sweep_chunk);
                        while self.sweep_slot < nslots && work > 0 {
                            let h = (base + self.sweep_slot * slot_size) as *mut Header;
                            self.sweep_slot += 1;
                            #[cfg(feature = "allocation-metrics")]
                            if let Some(m) = &self.metrics { m.borrow_mut().sweep_chunk_slots += 1; }
                            if unsafe { (*h).kind } != KIND_FREED { self.sweep_one(NonNull::new(h).unwrap()); work -= 1; }
                        }
                        if self.sweep_slot >= nslots { self.sweep_chunk += 1; self.sweep_slot = 0; }
                    }
                    if self.sweep_chunk >= self.allocator.chunk_count() {
                        while self.sweep_large < self.allocator.large_count() && work > 0 {
                            let h = self.allocator.large(self.sweep_large);
                            self.sweep_large += 1;
                            #[cfg(feature = "allocation-metrics")]
                            if let Some(m) = &self.metrics { m.borrow_mut().sweep_large_slots += 1; }
                            if !h.is_null() && unsafe { (*h).kind } != KIND_FREED { self.sweep_one(NonNull::new(h).unwrap()); work -= 1; }
                        }
                        if self.sweep_large >= self.allocator.large_count() {
                            self.allocator.compact_large();
                            self.phase = Phase::Idle;
                            self.stats.peak_live = self.stats.peak_live.max(self.live_bytes as u64);
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
        self.stats.swept += 1;
        #[cfg(feature = "allocation-metrics")]
        if let Some(m) = &self.metrics { m.borrow_mut().sweep_live_objects += 1; }
        unsafe {
            if (*p.as_ptr()).color == COLOR_WHITE { self.free(p); }
            else { (*p.as_ptr()).color = COLOR_WHITE; (*p.as_ptr()).epoch = self.stats.cycles as u32; }
        }
    }

    /// Drops an object's owned buffers and returns its memory: to the class's
    /// free list, or, under stress and quarantine, keeps it as a tombstone.
    fn free(&mut self, p: NonNull<Header>) {
        self.schema_write(p);
        unsafe {
            let h = &mut *p.as_ptr();
            let external = h.external_bytes();
            self.allocator.resize(external, 0, self.debt);
            #[cfg(feature = "allocation-metrics")]
            crate::allocation_metrics::reclaim(h);
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
                KIND_USERDATA => std::ptr::drop_in_place(h.userdata_mut()),
                KIND_RECORD => { std::ptr::drop_in_place(h.record_tail()); }
                _ => {}
            }
            self.allocator.reclaim(p, self.stress, self.quarantine);
        }
        self.sync_allocator();
    }

    /// Every live object, for the oracle and the serializer.
    pub fn objects(&self) -> Vec<NonNull<Header>> {
        let mut out = Vec::new();
        for index in 0..self.allocator.chunk_count() {
            let [base, slot_size, used] = self.allocator.chunk(index);
            for i in 0..used {
                let h = (base + i * slot_size) as *mut Header;
                if unsafe { (*h).kind } != KIND_FREED { out.push(NonNull::new(h).unwrap()); }
            }
        }
        for index in 0..self.allocator.large_count() {
            let h = self.allocator.large(index);
            if !h.is_null() && unsafe { (*h).kind } != KIND_FREED { out.push(NonNull::new(h).unwrap()); }
        }
        out
    }

    pub fn channel_count(&self) -> usize { self.channels.len() }

    pub fn full_cycle(&mut self, roots: &dyn Roots) {
        // Finish an in-progress incremental cycle, then collect from current
        // roots so an explicit full collection also removes floating garbage.
        while self.phase != Phase::Idle { self.step(usize::MAX / 8, roots); }
        crate::heap_trace::atomic(true);
        self.start(roots);
        while self.phase != Phase::Idle { self.step(usize::MAX / 8, roots); }
        crate::heap_trace::atomic(false);
        self.clear_debt();
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
        for &k in &self.mm_keys { if let Some(p) = Value(k).as_obj() { stack.push((p, "metamethod name".into())); } }
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

    /// Emit opt-in diagnostics once, before a process exit that skips Drop.
    /// Worker heaps emit the same record automatically when they are dropped.
    pub fn emit_allocation_metrics(&self, reason: &str) {
        self.report_stats(reason);
        #[cfg(feature = "allocation-metrics")]
        if let Some(metrics) = &self.metrics {
            crate::allocation_metrics::emit(metrics, reason, self.objects(), self.live_bytes, &self.stats);
        }
        #[cfg(not(feature = "allocation-metrics"))]
        let _ = reason;
    }

    pub fn object_count(&self) -> usize { self.live_count }
    pub fn is_marking(&self) -> bool { self.phase == Phase::Marking }
}

impl Drop for Heap {
    fn drop(&mut self) {
        self.emit_allocation_metrics("heap_drop");
        // Owned buffers of live objects, then the chunks and large blocks.
        for p in self.objects() {
            #[cfg(feature = "allocation-metrics")]
            crate::allocation_metrics::unregister(unsafe { p.as_ref() });
            unsafe { let h = &mut *p.as_ptr(); match h.kind { KIND_TABLE => std::ptr::drop_in_place(h.table()), KIND_STORAGE => std::ptr::drop_in_place(h.storage()), KIND_BYTES => std::ptr::drop_in_place(h.byte_buffer()), KIND_ITER => std::ptr::drop_in_place(h.iter()), KIND_USERDATA => std::ptr::drop_in_place(h.userdata_mut()), KIND_RECORD => { std::ptr::drop_in_place(h.record_tail()); } _ => {} } }
        }
        // NativeAllocator drops after payload teardown and releases its arena.

    }
}

#[cfg(test)]
mod tests {
    use super::*;
    struct R(std::cell::RefCell<Vec<Value>>);
    impl Roots for R { fn each_root(&self, f: &mut dyn FnMut(Value)) { for &v in self.0.borrow().iter() { f(v); } } }

    #[cfg(feature = "native-runtime")]
    #[test]
    fn table_constructor_refusal_leaves_recycled_slots_dead() {
        use std::panic::{AssertUnwindSafe, catch_unwind};
        for (array, hash) in [(usize::MAX, 0), (4, usize::MAX)] {
            let mut heap = Heap::new();
            heap.automatic_collection = false;
            let roots = R(std::cell::RefCell::new(Vec::new()));
            let old = heap.new_table_sized(8, 8, &roots).as_obj().unwrap();
            heap.full_cycle(&roots);
            let before = (heap.live_count, heap.live_bytes, heap.stats.allocated);
            assert!(!heap.is_live_slot(old));
            let failed = catch_unwind(AssertUnwindSafe(|| {
                heap.new_table_sized(array, hash, &roots);
            }));
            let after = (heap.live_count, heap.live_bytes, heap.stats.allocated);
            let valid = failed.is_err() && after == before && !heap.is_live_slot(old);
            if !valid {
                // A regressed constructor may leave dangling payload owners.
                // Do not scan/drop that invalid state while reporting failure.
                std::mem::forget(heap);
                panic!("refused table published a header: {before:?} -> {after:?}");
            }
            let table = heap.new_table_sized(8, 8, &roots);
            assert_eq!(table.as_obj().unwrap(), old);
            roots.0.borrow_mut().push(table);
            heap.full_cycle(&roots);
            unsafe {
                let header = table.as_obj().unwrap().as_ref();
                let payload = header.table_ref();
                assert!(payload.array.is_empty());
                assert!(payload.array.capacity() >= 8);
                assert_eq!(payload.hash.len(), 0);
                assert_eq!(payload.meta, Value::NIL);
                assert_eq!(header.aux_ptr, payload.array.as_ptr() as *mut u8);
                assert_eq!(header.aux_len, 0);
            }
        }
    }

    #[cfg(feature = "native-runtime")]
    #[test]
    fn table_constructor_reservation_survives_its_allocation_safepoint() {
        let mut heap = Heap::new();
        let roots = R(std::cell::RefCell::new(Vec::new()));
        let child = heap.new_string("rooted across reservation", &roots);
        roots.0.borrow_mut().push(child);
        heap.stress = true;
        let cycles = heap.stats.cycles;
        let table = heap.new_table_sized(8, 8, &roots);
        assert!(heap.stats.cycles > cycles);
        assert!(heap.is_live_slot(child.as_obj().unwrap()));
        unsafe {
            let header = &mut *table.as_obj().unwrap().as_ptr();
            let payload = header.table();
            assert!(payload.array.is_empty());
            assert_eq!(payload.hash.len(), 0);
            payload.array.push(child);
            payload.hash.insert(Value::TRUE, child);
            header.refresh();
        }
        *roots.0.borrow_mut() = vec![table];
        heap.full_cycle(&roots);
        unsafe {
            let payload = table.as_obj().unwrap().as_ref().table_ref();
            assert_eq!(&*payload.array, &[child]);
            assert_eq!(payload.hash.get(&Value::TRUE), Some(&child));
        }
        assert!(heap.is_live_slot(child.as_obj().unwrap()));
    }

    #[cfg(feature = "allocation-metrics")]
    #[test]
    fn allocation_metrics_allow_tls_owned_heap_teardown() {
        thread_local! {
            static EMBEDDED_HEAP: std::cell::RefCell<Option<Heap>> = const { std::cell::RefCell::new(None) };
        }
        std::thread::spawn(|| {
            // Initialize the host's TLS first. The diagnostic registry is
            // initialized by allocation and destroyed before this heap.
            EMBEDDED_HEAP.with(|slot| {
                let mut heap = Heap::new();
                heap.automatic_collection = false;
                heap.metrics = Some(crate::allocation_metrics::for_test());
                let roots = R(std::cell::RefCell::new(Vec::new()));
                heap.new_table(&roots);
                *slot.borrow_mut() = Some(heap);
            });
        }).join().expect("TLS-owned heap drops after diagnostic TLS teardown");
    }

    #[cfg(feature = "allocation-metrics")]
    #[test]
    fn allocation_metrics_count_gc_work_and_managed_bytes() {
        let mut h = Heap::new();
        h.automatic_collection = false;
        let metrics = crate::allocation_metrics::for_test();
        h.metrics = Some(metrics.clone());
        let roots = R(std::cell::RefCell::new(Vec::new()));
        let table = h.new_table(&roots);
        let child = h.new_string("kept", &roots);
        let _dead = h.new_string("dead", &roots);
        unsafe {
            let header = &mut *table.as_obj().unwrap().as_ptr();
            header.table().array.push(child);
            header.refresh();
            h.account_resize(0, header.external_bytes());
        }
        roots.0.borrow_mut().extend([table, Value::NIL]);
        h.full_cycle(&roots);
        let m = metrics.borrow();
        assert_eq!(h.stats.allocated, 3);
        assert_eq!(h.stats.freed, 1);
        assert_eq!(m.inline_requested_bytes, (HEADER + std::mem::size_of::<TablePayload>() + 2 * (HEADER + 9 + 4)) as u64);
        assert_eq!(m.chunk_bytes_requested, h.chunk_bytes_mapped);
        assert!(m.chunk_bytes_requested >= h.stats.chunks * 256 * 1024);
        assert_eq!(m.root_passes, 2);
        assert_eq!(m.root_slots, 4);
        assert_eq!(m.root_object_candidates, 2);
        assert_eq!(m.scanned_objects, 2);
        assert_eq!(m.child_slots, 1);
        assert_eq!(m.sweep_live_objects, 3);
        assert_eq!(m.sweep_large_slots, 0);
        assert_eq!(m.sweep_chunk_slots, m.sweep_live_objects, "untouched chunk tails are not swept");
    }

    #[cfg(feature = "native-runtime")]
    #[test]
    fn weak_intern_hits_preserve_gc_actions_with_collection_stopped() {
        for integer in [false, true] {
            let mut h = Heap::new();
            h.automatic_collection = false;
            let roots = R(std::cell::RefCell::new(Vec::new()));
            let key = crate::numeric::Integer { bits: i64::MAX as u64, unsigned: false };
            let make = |heap: &mut Heap| if integer { heap.box_integer(key, &roots) } else { heap.intern("weak-barrier", &roots) };
            let lookup = |heap: &mut Heap| if integer { heap.integer_lookup(key) } else { heap.intern_lookup("weak-barrier") };
            let first = make(&mut h);
            let p = first.as_obj().unwrap();
            h.stats.cycles = 4;
            unsafe { (*p.as_ptr()).color = COLOR_WHITE; (*p.as_ptr()).epoch = 1; }
            assert_eq!(lookup(&mut h), Some(first));
            assert!(h.allocator.gray_empty());
            let barriers = h.stats.barrier_grays;
            h.phase = Phase::Marking;
            assert_eq!(lookup(&mut h), Some(first));
            assert_eq!(unsafe { (*p.as_ptr()).color }, COLOR_GRAY);
            assert_eq!(h.allocator.gray_pop(), Some(p));
            assert!(h.allocator.gray_empty());
            assert_eq!(h.stats.barrier_grays, barriers + 1);
            assert_eq!(lookup(&mut h), Some(first));
            assert!(h.allocator.gray_empty(), "already-gray hit is not queued twice");
            h.phase = Phase::Sweeping;
            unsafe { (*p.as_ptr()).color = COLOR_WHITE; (*p.as_ptr()).epoch = 4; }
            assert_eq!(lookup(&mut h), Some(first), "white survivor from this sweep stands");
            assert_eq!(h.stats.barrier_grays, barriers + 1);
            unsafe { (*p.as_ptr()).epoch = 3; }
            assert_eq!(lookup(&mut h), None, "old white hit cannot resurrect");
            assert_eq!(lookup(&mut h), None, "dead hit is removed from its weak map");
            assert_eq!(unsafe { (*p.as_ptr()).color }, COLOR_WHITE);
            assert!(h.allocator.gray_empty());
            let replacement = make(&mut h);
            assert_ne!(replacement, first);
            assert_eq!(lookup(&mut h), Some(replacement));
            let replacement_pointer = replacement.as_obj().unwrap();
            unsafe { (*replacement_pointer.as_ptr()).color = COLOR_BLACK; (*replacement_pointer.as_ptr()).epoch = 0; }
            assert_eq!(lookup(&mut h), Some(replacement), "nonwhite hit stands despite old epoch");
            h.phase = Phase::Marking;
            unsafe { (*replacement_pointer.as_ptr()).color = COLOR_WHITE; }
            assert_eq!(lookup(&mut h), Some(replacement));
            assert_eq!(h.allocator.gray_pop(), Some(replacement_pointer));
            assert!(h.allocator.gray_empty());
            assert_eq!(h.stats.barrier_grays, barriers + 2);
        }
    }

    #[cfg(feature = "native-runtime")]
    #[test]
    fn native_gray_worklist_deduplicates_and_reuses_multiple_arena_segments() {
        let mut heap = Heap::new();
        heap.automatic_collection = false;
        let roots = R(std::cell::RefCell::new(Vec::new()));
        let headers: Vec<_> = (0..8192)
            .map(|_| heap.new_cell(Value::NIL, &roots).as_obj().unwrap())
            .collect();
        for _ in 0..2 {
            for &header in &headers {
                unsafe {
                    (*header.as_ptr()).color = COLOR_WHITE;
                }
                assert!(heap.allocator.shade(Value::obj(header)));
                assert!(
                    !heap.allocator.shade(Value::obj(header)),
                    "a gray header is queued once"
                );
            }
            assert!(!heap.allocator.gray_empty());
            for &header in headers.iter().rev() {
                assert_eq!(heap.allocator.gray_pop(), Some(header));
            }
            assert!(heap.allocator.gray_empty());
            assert_eq!(heap.allocator.gray_pop(), None);
        }
        assert_eq!(heap.object_count(), headers.len());
        assert_eq!(
            heap.allocator.snapshot()[8],
            0,
            "ordinary shading is not a store barrier"
        );
    }

    #[cfg(feature = "native-runtime")]
    #[test]
    fn native_barriers_use_current_phase_with_collection_stopped() {
        let mut heap = Heap::new();
        heap.automatic_collection = false;
        let roots = R(std::cell::RefCell::new(Vec::new()));
        let parent = heap.new_cell(Value::NIL, &roots).as_obj().unwrap();
        let child = heap.new_cell(Value::NIL, &roots).as_obj().unwrap();
        let other = heap.new_cell(Value::NIL, &roots).as_obj().unwrap();
        unsafe {
            (*parent.as_ptr()).color = COLOR_BLACK;
        }
        heap.barrier(parent, Value::obj(child));
        assert!(heap.allocator.gray_empty());
        heap.phase = Phase::Marking;
        heap.barrier(parent, Value::obj(child));
        heap.barrier(parent, Value::obj(child));
        assert_eq!(heap.stats.barrier_grays, 1);
        assert_eq!(heap.allocator.gray_pop(), Some(child));
        assert_eq!(heap.allocator.gray_pop(), None);
        for value in [
            Value::NIL,
            Value::FALSE,
            Value::num(f64::NAN),
            Value::num(-0.0),
            Value::inline_integer(-1).unwrap(),
        ] {
            heap.barrier(parent, value);
        }
        assert!(heap.allocator.gray_empty());
        assert_eq!(heap.stats.barrier_grays, 1);
        unsafe {
            (*parent.as_ptr()).color = COLOR_WHITE;
        }
        heap.barrier(parent, Value::obj(other));
        assert!(heap.allocator.gray_empty());
        unsafe {
            (*parent.as_ptr()).color = COLOR_BLACK;
        }
        heap.phase = Phase::Idle;
        heap.barrier(parent, Value::obj(other));
        assert_eq!(unsafe { other.as_ref().color }, COLOR_WHITE);
        assert!(heap.allocator.gray_empty());
        heap.phase = Phase::Marking;
        heap.barrier(parent, Value::obj(other));
        assert_eq!(heap.stats.barrier_grays, 2);
        assert_eq!(heap.allocator.gray_pop(), Some(other));
        assert_eq!(heap.allocator.gray_pop(), None);
        heap.phase = Phase::Idle;
    }

    #[cfg(feature = "native-runtime")]
    #[test]
    fn native_weak_views_preserve_modes_order_and_proto_invalidation() {
        for mode in 0..=3 {
            let mut heap = Heap::new();
            heap.automatic_collection = false;
            let roots = R(std::cell::RefCell::new(Vec::new()));
            let table = heap.new_table(&roots).as_obj().unwrap();
            let dead_key = heap.new_cell(Value::NIL, &roots);
            let dead_value = heap.new_cell(Value::NIL, &roots);
            let live = heap.new_cell(Value::NIL, &roots);
            unsafe {
                (*live.as_obj().unwrap().as_ptr()).color = COLOR_BLACK;
            }
            let string = heap.new_string("weak literal", &roots);
            let slice = heap.new_slice(string, 1, 4, &roots);
            let integer = heap.box_integer(
                crate::numeric::Integer {
                    bits: 1 << 60,
                    unsigned: false,
                },
                &roots,
            );
            let preserved = [
                string,
                slice,
                integer,
                Value::NIL,
                Value::FALSE,
                Value::num(-0.0),
                Value::num(f64::NAN),
                Value::inline_integer(-1).unwrap(),
            ];
            let h = unsafe { &mut *table.as_ptr() };
            h.flags |= F_PROTO;
            let t = h.table();
            t.array.extend(preserved);
            t.array.extend([dead_value, Value::NIL]);
            t.hash.insert(dead_key, live);
            t.hash.insert(Value::FALSE, dead_value);
            t.hash.insert(Value::num(0.0), live);
            t.hash.insert(string, slice);
            t.hash.insert(integer, integer);
            let before_order: Vec<_> = (0..t.hash.len())
                .map(|i| t.hash.entry_at(i).unwrap().0)
                .collect();
            let before_ranks: Vec<_> = before_order
                .iter()
                .map(|&key| t.hash.position_of(key))
                .collect();
            h.refresh();
            heap.weak.push((table, mode));
            let epoch = heap.proto_epoch;
            heap.clear_weak();
            let t = unsafe { table.as_ref().table_ref() };
            assert_eq!(&t.array[..preserved.len()], &preserved);
            assert_eq!(
                t.array.len(),
                if mode & WEAK_VALUES != 0 {
                    preserved.len()
                } else {
                    preserved.len() + 2
                }
            );
            assert_eq!(
                t.hash.get(&dead_key).copied(),
                (mode & WEAK_KEYS == 0).then_some(live)
            );
            assert_eq!(
                t.hash.get(&Value::FALSE).copied(),
                (mode & WEAK_VALUES == 0).then_some(dead_value)
            );
            assert_eq!(
                t.hash.get(&Value::num(0.0)),
                Some(&live),
                "raw zero is a live key"
            );
            assert_eq!(t.hash.get(&string), Some(&slice));
            assert_eq!(t.hash.get(&integer), Some(&integer));
            assert_eq!(
                (0..t.hash.len())
                    .map(|i| t.hash.entry_at(i).unwrap().0)
                    .collect::<Vec<_>>(),
                before_order
            );
            assert_eq!(
                before_order
                    .iter()
                    .map(|&key| t.hash.position_of(key))
                    .collect::<Vec<_>>(),
                before_ranks
            );
            assert_eq!(heap.proto_epoch, epoch + u64::from(mode != 0));
            let t = unsafe { &mut *table.as_ptr() }.table();
            t.hash.insert(dead_key, live);
            assert_eq!(
                t.hash.next_after(Value::NIL),
                Some((dead_key, live)),
                "reinsertion retains original rank"
            );
        }
    }

    #[cfg(feature = "native-runtime")]
    #[test]
    fn native_weak_mark_views_reach_a_fixed_point_without_duplicate_shading() {
        let mut heap = Heap::new();
        heap.automatic_collection = false;
        let roots = R(std::cell::RefCell::new(Vec::new()));
        let first = heap.new_cell(Value::NIL, &roots);
        let second = heap.new_cell(Value::NIL, &roots);
        let tail = heap.new_cell(Value::NIL, &roots);
        let dead_key = heap.new_cell(Value::NIL, &roots);
        let dead_value = heap.new_cell(Value::NIL, &roots);
        let mut table = TablePayload {
            array: heap.allocator.value_array(0),
            hash: heap.allocator.value_table(0),
            meta: Value::NIL,
        };
        table.hash.insert(first, second);
        table.hash.insert(second, tail);
        table.hash.insert(dead_key, dead_value);
        assert!(!Heap::mark_live_entries(
            &mut heap.allocator,
            &table,
            WEAK_KEYS
        ));
        unsafe {
            (*first.as_obj().unwrap().as_ptr()).color = COLOR_BLACK;
        }
        let mut passes = 0;
        while Heap::mark_live_entries(&mut heap.allocator, &table, WEAK_KEYS) {
            passes += 1;
            assert!(passes <= 2, "the ephemeron chain converges");
        }
        assert!(passes > 0);
        let mut grayed = Vec::new();
        while let Some(header) = heap.allocator.gray_pop() {
            grayed.push(Value::obj(header));
        }
        grayed.sort_by_key(|v| v.0);
        let mut expected = vec![second, tail];
        expected.sort_by_key(|v| v.0);
        assert_eq!(grayed, expected);
        assert_eq!(
            unsafe { dead_key.as_obj().unwrap().as_ref().color },
            COLOR_WHITE
        );
        assert_eq!(
            unsafe { dead_value.as_obj().unwrap().as_ref().color },
            COLOR_WHITE
        );
        let mut unchanged = vec![Value::TRUE, Value::NIL];
        let (length, changed) = unsafe {
            NativeAllocator::weak_clear(
                unchanged.as_mut_ptr(),
                unchanged.len(),
                std::ptr::null_mut(),
                0,
                WEAK_VALUES,
            )
        };
        assert_eq!(
            (length, changed),
            (2, false),
            "an unchanged borrowed array retains its extent"
        );
        let (length, changed) = unsafe {
            NativeAllocator::weak_clear(std::ptr::null_mut(), 0, std::ptr::null_mut(), 0, 3)
        };
        assert_eq!(
            (length, changed),
            (0, false),
            "empty views do not dereference null"
        );
    }
    #[cfg(feature = "native-runtime")]
    #[test]
    fn native_allocator_rejects_unrepresentable_extents_before_allocation() {
        let mut heap = Heap::new();
        heap.automatic_collection = false;
        let initial = heap.allocator.snapshot();
        for payload in [u32::MAX as usize - HEADER + 1, usize::MAX] {
            let refused = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
                heap.alloc_raw(KIND_CELL, payload)
            }));
            assert!(
                refused.is_err(),
                "unrepresentable header size must fail before mapping"
            );
            assert_eq!(heap.allocator.snapshot(), initial);
            assert_eq!(heap.object_count(), 0);
            assert_eq!(heap.live_bytes, 0);
            assert_eq!(heap.debt, 0);
            assert_eq!(heap.stats.allocated, 0);
            assert_eq!(heap.stats.freed, 0);
            assert_eq!(heap.stats.chunks, 0);
            assert_eq!(heap.stats.large, 0);
            assert_eq!(heap.alloc_kinds[KIND_CELL as usize], 0);
            assert_eq!(heap.chunk_bytes_mapped, 0);
        }
        let roots = R(std::cell::RefCell::new(Vec::new()));
        let cell = heap.new_cell(Value::NIL, &roots);
        assert!(heap.is_live_slot(cell.as_obj().unwrap()));
        assert_eq!(heap.object_count(), 1);
        assert_eq!(heap.stats.allocated, 1);
        assert_eq!(heap.live_bytes, HEADER + 8);
    }

    #[cfg(feature = "native-runtime")]
    #[test]
    fn native_allocator_colors_follow_sweep_cursor_and_debt_reset() {
        let mut h = Heap::new();
        h.automatic_collection = false;
        let roots = R(std::cell::RefCell::new(Vec::new()));
        let first = h.new_cell(Value::NIL, &roots).as_obj().unwrap();
        assert_eq!(unsafe { first.as_ref().color }, COLOR_WHITE);
        h.phase = Phase::Marking;
        h.stats.cycles = 7;
        let marking = h.new_cell(Value::NIL, &roots).as_obj().unwrap();
        assert_eq!(unsafe { marking.as_ref().color }, COLOR_BLACK);
        assert_eq!(unsafe { marking.as_ref().epoch }, 7);
        h.phase = Phase::Sweeping;
        h.sweep_chunk = 0;
        h.sweep_slot = 0;
        let ahead = h.new_cell(Value::NIL, &roots).as_obj().unwrap();
        assert_eq!(unsafe { ahead.as_ref().color }, COLOR_BLACK);
        h.free(first);
        h.sweep_slot = 1;
        let behind = h.new_cell(Value::NIL, &roots).as_obj().unwrap();
        assert_eq!(behind, first);
        assert_eq!(unsafe { behind.as_ref().color }, COLOR_WHITE);
        h.clear_debt();
        assert_eq!(h.debt, 0);
        assert_eq!(h.allocator.snapshot()[2], 0);
        h.free(behind);
        assert_eq!(h.debt, 0, "reclaim cannot restore debt from before the reset");
        assert_eq!(h.object_count(), 2);
        h.phase = Phase::Idle;
    }

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
