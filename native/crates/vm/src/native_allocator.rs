//! Ownership transport for the Nupp allocator. All layout, allocation and
//! reclamation decisions remain in the linked Nupp heap implementation.

use std::ffi::c_void;
use std::ptr::NonNull;

use crate::heap::Header;
use crate::value::Value;

#[cfg(feature = "native-runtime")]
unsafe extern "C" {
    fn nupp_weak_string_peek(heap: *mut c_void, bytes: *const u8, count: u64) -> *mut Header;
    fn nupp_weak_integer_peek(heap: *mut c_void, bits: u64, unsigned: u64) -> *mut Header;
    fn nupp_weak_string_lookup(
        heap: *mut c_void,
        bytes: *const u8,
        count: u64,
        phase: i64,
        cycle: u64,
    ) -> *mut Header;
    fn nupp_weak_integer_lookup(
        heap: *mut c_void,
        bits: u64,
        unsigned: u64,
        phase: i64,
        cycle: u64,
    ) -> *mut Header;
    fn nupp_weak_insert(heap: *mut c_void, header: *mut Header) -> u64;
    fn nupp_weak_erase(heap: *mut c_void, header: *mut Header);
    fn nupp_object_next(heap: *mut c_void, cursor: *mut ObjectCursor) -> u64;
    fn nupp_sweep_begin(heap: *mut c_void, cycle: u64);
    fn nupp_sweep_next(heap: *mut c_void, result: *mut ObjectCursor) -> u64;
    fn nupp_sweep_finished(heap: *mut c_void) -> u64;
    fn nupp_allocator_arena_open(bytes: u64) -> *mut c_void;
    fn nupp_allocator_arena_close(arena: *mut c_void);
    fn nupp_allocator_create(arena: *mut c_void) -> *mut c_void;
    fn nupp_allocator_destroy(heap: *mut c_void);
    fn nupp_allocator_allocate(
        heap: *mut c_void,
        kind: u64,
        payload: u64,
        phase: i64,
        cycle: u64,
        debt: u64,
    ) -> *mut Header;
    fn nupp_allocator_resize(heap: *mut c_void, before: u64, after: u64, debt: u64);
    fn nupp_allocator_reclaim(heap: *mut c_void, header: *mut Header, stress: u64, quarantine: u64);
    fn nupp_allocator_snapshot(heap: *mut c_void, out: *mut u64);
    fn nupp_weak_cycle_reset(heap: *mut c_void);
    fn nupp_weak_cycle_remember(heap: *mut c_void, header: *mut Header, mode: u64);
    fn nupp_weak_cycle_scan(heap: *mut c_void, header: *mut Header, mode: u64);
    fn nupp_weak_cycle_propagate(heap: *mut c_void) -> u64;
    fn nupp_weak_cycle_clear_next(heap: *mut c_void, cursor: *mut WeakClearCursor) -> u64;
    fn nupp_scan_strong(heap: *mut c_void, header: *mut Header) -> u64;
    fn nupp_allocator_shade(heap: *mut c_void, value: u64) -> u64;
    fn nupp_allocator_barrier(heap: *mut c_void, parent: *mut Header, child: u64, marking: u64);
    fn nupp_allocator_barrier_shade(heap: *mut c_void, value: u64);
    fn nupp_allocator_gray_pop(heap: *mut c_void) -> *mut Header;
    fn nupp_allocator_weak_mark(
        heap: *mut c_void,
        array: *const Value,
        length: u64,
        buckets: *const u64,
        capacity: u64,
        mode: u64,
    ) -> u64;
    fn nupp_allocator_weak_clear(
        array: *mut Value,
        length: u64,
        buckets: *mut u64,
        capacity: u64,
        mode: u64,
        out: *mut u64,
    );
    fn nupp_allocator_gray_empty(heap: *mut c_void) -> u64;
    fn nupp_allocator_chunk_count(heap: *mut c_void) -> u64;
    fn nupp_allocator_large_count(heap: *mut c_void) -> u64;
    fn nupp_allocator_compact_large(heap: *mut c_void);
    fn nupp_allocator_is_live_slot(heap: *mut c_void, header: *mut Header) -> u64;
    fn nupp_allocator_slot_bytes(class: u64) -> u64;
}

macro_rules! linked {
    ($($body:tt)*) => {{
        #[cfg(feature = "native-runtime")]
        { $($body)* }
        #[cfg(not(feature = "native-runtime"))]
        { panic!("allocation requires a linked Nupp core") }
    }};
}

#[repr(C)]
#[derive(Default)]
pub(crate) struct ObjectCursor {
    pub chunk: u64,
    pub slot: u64,
    pub large: u64,
    pub chunk_slots: u64,
    pub large_slots: u64,
    pub header: u64,
}

pub(crate) struct NativeAllocator {
    arena: NonNull<c_void>,
    heap: NonNull<c_void>,
}

#[allow(unused_variables)]
impl NativeAllocator {
    pub(crate) fn new() -> Self {
        linked! {
            let arena = NonNull::new(unsafe { nupp_allocator_arena_open(64 * 1024) }).expect("allocator arena allocation failed");
            let Some(heap) = NonNull::new(unsafe { nupp_allocator_create(arena.as_ptr()) }) else {
                unsafe { nupp_allocator_arena_close(arena.as_ptr()); }
                panic!("allocator metadata allocation failed");
            };
            Self { arena, heap }
        }
    }

    pub(crate) fn heap_pointer(&self) -> *mut c_void {
        self.heap.as_ptr()
    }

    pub(crate) fn byte_array(&self, length: usize, capacity: usize) -> crate::native_byte_array::ByteArray {
        unsafe { crate::native_byte_array::ByteArray::new(self.heap.as_ptr(), length, capacity) }
    }

    pub(crate) fn shape_methods(&self) -> crate::native_shape_methods::ShapeMethods {
        unsafe { crate::native_shape_methods::ShapeMethods::new(self.heap.as_ptr()) }
    }

    pub(crate) fn shape_backing(&self, names: &[Value]) -> (crate::native_value_array::ValueArray, crate::native_shape::ShapeTable, u64) {
        unsafe { crate::native_shape::initialize(self.heap.as_ptr(), names) }
    }

    pub(crate) fn value_array(&self, capacity: usize) -> crate::native_value_array::ValueArray {
        unsafe { crate::native_value_array::ValueArray::new(self.heap.as_ptr(), capacity) }
    }

    pub(crate) fn value_table(&self, capacity: usize) -> crate::heap::ValueTable {
        unsafe { crate::heap::ValueTable::new(self.heap.as_ptr(), capacity) }
    }

    pub(crate) fn weak_string_peek(&self, bytes: &[u8]) -> Option<NonNull<Header>> {
        linked! { NonNull::new(unsafe { nupp_weak_string_peek(self.heap.as_ptr(), bytes.as_ptr(), bytes.len() as u64) }) }
    }
    pub(crate) fn weak_integer_peek(&self, bits: u64, unsigned: bool) -> Option<NonNull<Header>> {
        linked! { NonNull::new(unsafe { nupp_weak_integer_peek(self.heap.as_ptr(), bits, unsigned as u64) }) }
    }
    pub(crate) fn weak_string_lookup(
        &mut self,
        bytes: &[u8],
        phase: i64,
        cycle: u64,
    ) -> Option<NonNull<Header>> {
        linked! { NonNull::new(unsafe { nupp_weak_string_lookup(self.heap.as_ptr(), bytes.as_ptr(), bytes.len() as u64, phase, cycle) }) }
    }
    pub(crate) fn weak_integer_lookup(
        &mut self,
        bits: u64,
        unsigned: bool,
        phase: i64,
        cycle: u64,
    ) -> Option<NonNull<Header>> {
        linked! { NonNull::new(unsafe { nupp_weak_integer_lookup(self.heap.as_ptr(), bits, unsigned as u64, phase, cycle) }) }
    }
    pub(crate) fn weak_insert(&mut self, header: NonNull<Header>) {
        linked! { assert_eq!(unsafe { nupp_weak_insert(self.heap.as_ptr(), header.as_ptr()) }, 0, "weak index insertion refused"); }
    }
    pub(crate) fn weak_erase(&mut self, header: NonNull<Header>) {
        linked! { unsafe { nupp_weak_erase(self.heap.as_ptr(), header.as_ptr()); } }
    }

    pub(crate) fn allocate(
        &mut self,
        kind: u8,
        payload: usize,
        phase: i64,
        cycle: u64,
        debt: usize,
    ) -> NonNull<Header> {
        linked! {
            NonNull::new(unsafe { nupp_allocator_allocate(self.heap.as_ptr(), kind as u64, payload as u64, phase, cycle, debt as u64) }).expect("object allocation failed")
        }
    }

    pub(crate) fn resize(&mut self, before: usize, after: usize, debt: usize) {
        linked! { unsafe { nupp_allocator_resize(self.heap.as_ptr(), before as u64, after as u64, debt as u64); } }
    }

    pub(crate) fn reclaim(&mut self, header: NonNull<Header>, stress: bool, quarantine: bool) {
        linked! { unsafe { nupp_allocator_reclaim(self.heap.as_ptr(), header.as_ptr(), stress as u64, quarantine as u64); } }
    }

    pub(crate) fn snapshot(&self) -> [u64; 9] {
        linked! {
            let mut words = [0; 9];
            unsafe { nupp_allocator_snapshot(self.heap.as_ptr(), words.as_mut_ptr()); }
            words
        }
    }

    pub(crate) fn shade(&mut self, value: Value) -> bool {
        linked! { unsafe { nupp_allocator_shade(self.heap.as_ptr(), value.0) != 0 } }
    }

    pub(crate) fn barrier(&mut self, parent: NonNull<Header>, child: Value, marking: bool) {
        linked! { unsafe { nupp_allocator_barrier(self.heap.as_ptr(), parent.as_ptr(), child.0, marking as u64); } }
    }

    pub(crate) fn barrier_shade(&mut self, value: Value) {
        linked! { unsafe { nupp_allocator_barrier_shade(self.heap.as_ptr(), value.0); } }
    }

    pub(crate) fn gray_pop(&mut self) -> Option<NonNull<Header>> {
        linked! { NonNull::new(unsafe { nupp_allocator_gray_pop(self.heap.as_ptr()) }) }
    }

    pub(crate) fn gray_empty(&self) -> bool {
        linked! { unsafe { nupp_allocator_gray_empty(self.heap.as_ptr()) != 0 } }
    }

    // The caller lends valid, disjoint buffers and owned candidate headers.
    // These services only mutate borrowed words or native gray-worklist backing.
    pub(crate) unsafe fn weak_mark(
        &mut self,
        array: *const Value,
        length: usize,
        buckets: *const u64,
        capacity: u64,
        mode: u8,
    ) -> bool {
        linked! { unsafe { nupp_allocator_weak_mark(self.heap.as_ptr(), array, length as u64, buckets, capacity, mode as u64) != 0 } }
    }

    pub(crate) unsafe fn weak_clear(
        array: *mut Value,
        length: usize,
        buckets: *mut u64,
        capacity: u64,
        mode: u8,
    ) -> (usize, bool) {
        linked! {
            let mut out = [0u64; 2];
            unsafe { nupp_allocator_weak_clear(array, length as u64, buckets, capacity, mode as u64, out.as_mut_ptr()); }
            (usize::try_from(out[0]).expect("weak array length"), out[1] != 0)
        }
    }

    pub(crate) fn weak_cycle_reset(&mut self) {
        linked! { unsafe { nupp_weak_cycle_reset(self.heap.as_ptr()); } }
    }
    pub(crate) fn weak_cycle_remember(&mut self, header: NonNull<Header>, mode: u8) {
        linked! { unsafe { nupp_weak_cycle_remember(self.heap.as_ptr(), header.as_ptr(), mode as u64); } }
    }
    pub(crate) fn weak_cycle_scan(&mut self, header: NonNull<Header>, mode: u8) {
        linked! { unsafe { nupp_weak_cycle_scan(self.heap.as_ptr(), header.as_ptr(), mode as u64); } }
    }
    pub(crate) fn weak_cycle_propagate(&mut self) -> bool {
        linked! { unsafe { nupp_weak_cycle_propagate(self.heap.as_ptr()) != 0 } }
    }
    pub(crate) fn weak_cycle_clear_next(&mut self, cursor: &mut WeakClearCursor) -> Option<NonNull<Header>> {
        linked! {
            if unsafe { nupp_weak_cycle_clear_next(self.heap.as_ptr(), cursor) } == 0 { return None; }
            NonNull::new(cursor.header as *mut Header)
        }
    }

    pub(crate) fn scan_strong(&mut self, header: NonNull<Header>) -> u64 {
        linked! { unsafe { nupp_scan_strong(self.heap.as_ptr(), header.as_ptr()) } }
    }

    pub(crate) fn next_object(&self, cursor: &mut ObjectCursor) -> Option<NonNull<Header>> {
        linked! {
            let found = unsafe { nupp_object_next(self.heap.as_ptr(), cursor) };
            if found == 0 { None } else { NonNull::new(cursor.header as *mut Header) }
        }
    }

    pub(crate) fn sweep_begin(&mut self, cycle: u64) {
        linked! { unsafe { nupp_sweep_begin(self.heap.as_ptr(), cycle); } }
    }

    pub(crate) fn sweep_next(&mut self, result: &mut ObjectCursor) -> u64 {
        linked! { unsafe { nupp_sweep_next(self.heap.as_ptr(), result) } }
    }

    pub(crate) fn sweep_finished(&self) -> bool {
        linked! { unsafe { nupp_sweep_finished(self.heap.as_ptr()) != 0 } }
    }

    pub(crate) fn chunk_count(&self) -> usize {
        linked! { usize::try_from(unsafe { nupp_allocator_chunk_count(self.heap.as_ptr()) }).expect("chunk count") }
    }

    pub(crate) fn large_count(&self) -> usize {
        linked! { usize::try_from(unsafe { nupp_allocator_large_count(self.heap.as_ptr()) }).expect("large count") }
    }

    pub(crate) fn compact_large(&mut self) {
        linked! { unsafe { nupp_allocator_compact_large(self.heap.as_ptr()); } }
    }

    pub(crate) fn is_live_slot(&self, header: NonNull<Header>) -> bool {
        linked! { unsafe { nupp_allocator_is_live_slot(self.heap.as_ptr(), header.as_ptr()) != 0 } }
    }

    pub(crate) fn slot_bytes(class: u8) -> usize {
        linked! { usize::try_from(unsafe { nupp_allocator_slot_bytes(class as u64) }).expect("slot extent") }
    }
}

impl Drop for NativeAllocator {
    fn drop(&mut self) {
        #[cfg(feature = "native-runtime")]
        unsafe {
            nupp_allocator_destroy(self.heap.as_ptr());
            nupp_allocator_arena_close(self.arena.as_ptr());
        }
    }
}

#[cfg(all(test, feature = "native-runtime"))]
mod shape_backing_tests {
    use super::*;

    // Canonical arena.Arena prefix. Constrain the real arena rather than
    // adding a production allocation-failure switch.
    #[repr(C)]
    struct ArenaPrefix {
        chunk: *mut c_void,
        cursor: u64,
        limit: u64,
        chunk_bytes: u64,
        growable: bool,
    }
    struct RestoreArena(*mut ArenaPrefix, u64, bool);
    impl Drop for RestoreArena {
        fn drop(&mut self) {
            unsafe { (*self.0).limit = self.1; (*self.0).growable = self.2; }
        }
    }

    #[test]
    fn shape_second_allocation_refusal_returns_first_backing_atomically() {
        let owner = NativeAllocator::new();
        let seed = owner.value_array(1);
        let pointer = seed.as_ptr();
        drop(seed);
        let mut names = owner.value_array(0);
        let mut probes = owner.value_array(0);
        let source = [Value::TRUE];
        let arena = owner.arena.as_ptr().cast::<ArenaPrefix>();
        let restore = unsafe {
            let guard = RestoreArena(arena, (*arena).limit, (*arena).growable);
            (*arena).limit = (*arena).cursor;
            (*arena).growable = false;
            guard
        };
        // Names can reuse the seeded free slot. The probe pool cannot allocate
        // even its metadata, so this deterministically fails the second take.
        assert_eq!(unsafe { crate::native_shape::nupp_shape_owned_initialize(&mut names, &mut probes, source.as_ptr(), 1) }, u64::MAX);
        assert_eq!((names.len(), names.capacity(), probes.len(), probes.capacity()), (0, 0, 0, 0));
        let reused = owner.value_array(1);
        assert_eq!(reused.as_ptr(), pointer, "the failed construction leaked its first allocation");
        drop(reused);
        drop(restore);
        let (names, probes, mask) = owner.shape_backing(&source);
        assert_eq!(&names[..], &source);
        assert_eq!((probes.len(), mask), (8, 7));
    }
    #[test]
    fn shape_methods_growth_refusal_keeps_entries_and_the_old_borrow() {
        let owner = NativeAllocator::new();
        let mut map = owner.shape_methods();
        for key in 0..6 { map.insert(Value(key), Value::NIL); }
        let before: Vec<_> = map.iter().map(|(&k,&v)|(k,v)).collect();
        let pointer = map.get(&Value(0)).unwrap() as *const Value;
        let arena = owner.arena.as_ptr().cast::<ArenaPrefix>();
        let restore = unsafe {
            let guard = RestoreArena(arena, (*arena).limit, (*arena).growable);
            (*arena).limit = (*arena).cursor;
            (*arena).growable = false;
            guard
        };
        let mut old = 0x123456789abcdef0;
        assert_eq!(unsafe { crate::native_shape_methods::nupp_shape_methods_insert(&mut map, 99, Value::TRUE.0, &mut old) }, 2);
        assert_eq!(old, 0x123456789abcdef0);
        assert_eq!(map.len(), 6);
        assert_eq!(map.get(&Value(0)).unwrap() as *const Value, pointer);
        assert_eq!(map.iter().map(|(&k,&v)|(k,v)).collect::<Vec<_>>(), before);
        drop(restore);
        assert_eq!(map.insert(Value(99), Value::NIL), None);
        assert_eq!(map.get(&Value(99)), Some(&Value::NIL));
    }

}

#[repr(C)]
#[derive(Default)]
pub(crate) struct WeakClearCursor { pub index: u64, pub header: u64, pub changed: u64 }
const _: () = {
    assert!(std::mem::size_of::<WeakClearCursor>() == 24);
    assert!(std::mem::offset_of!(WeakClearCursor, changed) == 16);
};
