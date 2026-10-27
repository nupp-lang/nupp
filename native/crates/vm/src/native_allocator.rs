//! Ownership transport for the Nupp allocator. All layout, allocation and
//! reclamation decisions remain in the linked Nupp heap implementation.

use std::ffi::c_void;
use std::ptr::NonNull;

use crate::heap::Header;
use crate::value::Value;

#[cfg(feature = "native-runtime")]
unsafe extern "C" {
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
        sweep_chunk: u64,
        sweep_slot: u64,
        debt: u64,
    ) -> *mut Header;
    fn nupp_allocator_resize(heap: *mut c_void, before: u64, after: u64, debt: u64);
    fn nupp_allocator_reclaim(heap: *mut c_void, header: *mut Header, stress: u64, quarantine: u64);
    fn nupp_allocator_snapshot(heap: *mut c_void, out: *mut u64);
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
    fn nupp_allocator_chunk(heap: *mut c_void, index: u64, out: *mut u64);
    fn nupp_allocator_large_count(heap: *mut c_void) -> u64;
    fn nupp_allocator_large(heap: *mut c_void, index: u64) -> *mut Header;
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

    pub(crate) fn allocate(
        &mut self,
        kind: u8,
        payload: usize,
        phase: i64,
        cycle: u64,
        sweep_chunk: usize,
        sweep_slot: usize,
        debt: usize,
    ) -> NonNull<Header> {
        linked! {
            NonNull::new(unsafe { nupp_allocator_allocate(self.heap.as_ptr(), kind as u64, payload as u64, phase, cycle, sweep_chunk as u64, sweep_slot as u64, debt as u64) }).expect("object allocation failed")
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

    pub(crate) fn chunk_count(&self) -> usize {
        linked! { usize::try_from(unsafe { nupp_allocator_chunk_count(self.heap.as_ptr()) }).expect("chunk count") }
    }

    /// The first slot address, slot extent and number of touched slots.
    pub(crate) fn chunk(&self, index: usize) -> [usize; 3] {
        linked! {
            let mut words = [0; 3];
            unsafe { nupp_allocator_chunk(self.heap.as_ptr(), index as u64, words.as_mut_ptr()); }
            words.map(|word| usize::try_from(word).expect("chunk extent"))
        }
    }

    pub(crate) fn large_count(&self) -> usize {
        linked! { usize::try_from(unsafe { nupp_allocator_large_count(self.heap.as_ptr()) }).expect("large count") }
    }

    pub(crate) fn large(&self, index: usize) -> *mut Header {
        linked! { unsafe { nupp_allocator_large(self.heap.as_ptr(), index as u64) } }
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
