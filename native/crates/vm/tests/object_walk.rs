use nupp_vm::heap::{Header, COLOR_BLACK, COLOR_WHITE, KIND_CELL, KIND_STR};
use std::ffi::c_void;

#[repr(C)]
#[derive(Default)]
struct Cursor {
    chunk: u64,
    slot: u64,
    large: u64,
    chunk_slots: u64,
    large_slots: u64,
    header: u64,
}
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
        debt: u64,
    ) -> *mut Header;
    fn nupp_allocator_reclaim(heap: *mut c_void, header: *mut Header, stress: u64, quarantine: u64);
    fn nupp_allocator_compact_large(heap: *mut c_void);
    fn nupp_object_next(heap: *mut c_void, cursor: *mut Cursor) -> u64;
    fn nupp_sweep_begin(heap: *mut c_void, cycle: u64);
    fn nupp_sweep_next(heap: *mut c_void, result: *mut Cursor) -> u64;
    fn nupp_sweep_finished(heap: *mut c_void) -> u64;
}
struct Heap {
    arena: *mut c_void,
    heap: *mut c_void,
}
impl Heap {
    fn new() -> Self {
        unsafe {
            let arena = nupp_allocator_arena_open(65536);
            assert!(!arena.is_null());
            let heap = nupp_allocator_create(arena);
            assert!(!heap.is_null());
            Self { arena, heap }
        }
    }
    fn alloc(&self, payload: u64, phase: i64, cycle: u64) -> *mut Header {
        unsafe {
            let h = nupp_allocator_allocate(
                self.heap,
                if payload == 8 { KIND_CELL } else { KIND_STR } as u64,
                payload,
                phase,
                cycle,
                0,
            );
            assert!(!h.is_null());
            h
        }
    }
    fn objects(&self) -> (Vec<*mut Header>, Cursor) {
        let mut c = Cursor::default();
        let mut out = vec![];
        while unsafe { nupp_object_next(self.heap, &mut c) } != 0 {
            out.push(c.header as *mut Header);
        }
        (out, c)
    }
}
impl Drop for Heap {
    fn drop(&mut self) {
        unsafe {
            nupp_allocator_destroy(self.heap);
            nupp_allocator_arena_close(self.arena);
        }
    }
}

#[test]
fn enumeration_layout_and_holes_preserve_chunk_then_large_order() {
    unsafe {
        assert_eq!(std::mem::size_of::<Cursor>(), 48);
        assert_eq!(std::mem::align_of::<Cursor>(), 8);
        assert_eq!(std::mem::offset_of!(Cursor, chunk_slots), 24);
        assert_eq!(std::mem::offset_of!(Cursor, header), 40);
        let h = Heap::new();
        assert!(h.objects().0.is_empty());
        let a = h.alloc(8, 0, 1);
        let b = h.alloc(8, 0, 1);
        let c = h.alloc(8, 0, 1);
        let x = h.alloc(50_000, 0, 1);
        let y = h.alloc(50_000, 0, 1);
        let z = h.alloc(50_000, 0, 1);
        nupp_allocator_reclaim(h.heap, b, 0, 0);
        nupp_allocator_reclaim(h.heap, y, 0, 0);
        let (objects, cursor) = h.objects();
        assert_eq!(objects, [a, c, x, z]);
        assert_eq!((cursor.chunk_slots, cursor.large_slots), (3, 3));
        nupp_allocator_reclaim(h.heap, a, 0, 1);
        nupp_allocator_reclaim(h.heap, c, 0, 1);
        assert_eq!(h.objects().0, [x, z]);
        nupp_allocator_compact_large(h.heap);
        assert_eq!(h.objects().0, [x, z]);
    }
}

#[test]
fn sweep_actions_preserve_budget_boundary_epoch_and_allocation_cursor() {
    unsafe {
        let h = Heap::new();
        let a = h.alloc(8, 0, 1);
        let b = h.alloc(8, 0, 1);
        let c = h.alloc(8, 0, 1);
        (*b).color = COLOR_BLACK;
        (*c).color = COLOR_BLACK;
        nupp_sweep_begin(h.heap, 9);
        let mut result = Cursor::default();
        assert_eq!(nupp_sweep_next(h.heap, &mut result), 1);
        assert_eq!(result.header, a as u64);
        assert_eq!((result.chunk_slots, result.large_slots), (1, 0));
        nupp_allocator_reclaim(h.heap, a, 0, 0);
        let reused = h.alloc(8, 2, 9);
        assert_eq!(reused, a);
        assert_eq!((*reused).color, COLOR_WHITE);
        let ahead = h.alloc(8, 2, 9);
        assert_eq!((*ahead).color, COLOR_BLACK);
        assert_eq!(nupp_sweep_finished(h.heap), 0);
        for expected in [b, c, ahead] {
            assert_eq!(nupp_sweep_next(h.heap, &mut result), 2);
            assert_eq!(result.header, expected as u64);
            assert_eq!((*expected).color, COLOR_WHITE);
            assert_eq!((*expected).epoch, 9);
        }
        // Completion is visible on the exact final budget unit, without another next.
        assert_eq!(nupp_sweep_finished(h.heap), 1);
        assert_eq!(nupp_sweep_next(h.heap, &mut result), 0);
        assert_eq!((result.chunk_slots, result.large_slots), (0, 0));
        assert_eq!(h.objects().0, [a, b, c, ahead]);
    }
}

#[test]
fn trailing_holes_wait_for_work_and_quarantine_is_skipped() {
    unsafe {
        let h = Heap::new();
        let a = h.alloc(8, 0, 1);
        let tomb = h.alloc(8, 0, 1);
        let x = h.alloc(50_000, 0, 1);
        let hole = h.alloc(50_000, 0, 1);
        nupp_allocator_reclaim(h.heap, tomb, 0, 1);
        nupp_allocator_reclaim(h.heap, hole, 0, 0);
        (*a).color = COLOR_BLACK;
        (*x).color = COLOR_BLACK;
        nupp_sweep_begin(h.heap, 12);
        let mut r = Cursor::default();
        assert_eq!(nupp_sweep_next(h.heap, &mut r), 2);
        assert_eq!(r.header, a as u64);
        assert_eq!(nupp_sweep_finished(h.heap), 0);
        assert_eq!(nupp_sweep_next(h.heap, &mut r), 2);
        assert_eq!(r.header, x as u64);
        assert_eq!((r.chunk_slots, r.large_slots), (1, 1));
        assert_eq!(nupp_sweep_finished(h.heap), 0);
        assert_eq!(nupp_sweep_next(h.heap, &mut r), 0);
        assert_eq!((r.chunk_slots, r.large_slots), (0, 1));
        assert_eq!(nupp_sweep_finished(h.heap), 1);
        // A new cycle's epoch does not depend on allocating in that cycle.
        (*a).color = COLOR_BLACK;
        (*x).color = COLOR_BLACK;
        nupp_sweep_begin(h.heap, 13);
        assert_eq!(nupp_sweep_next(h.heap, &mut r), 2);
        assert_eq!((*a).epoch, 13);
        assert_eq!(nupp_sweep_next(h.heap, &mut r), 2);
        assert_eq!((*x).epoch, 13);
    }
}

#[test]
fn empty_chunks_and_new_large_allocations_resume_in_order() {
    unsafe {
        let h = Heap::new();
        let retired = h.alloc(8, 0, 1);
        nupp_allocator_reclaim(h.heap, retired, 0, 1);
        let first = h.alloc(50_000, 0, 1);
        (*first).color = COLOR_BLACK;
        nupp_sweep_begin(h.heap, 21);
        let mut result = Cursor::default();
        assert_eq!(nupp_sweep_next(h.heap, &mut result), 2);
        assert_eq!(result.header, first as u64);
        assert_eq!((result.chunk_slots, result.large_slots), (1, 1));
        let added = h.alloc(50_000, 2, 21);
        assert_eq!((*added).color, COLOR_BLACK);
        assert_eq!(nupp_sweep_finished(h.heap), 0);
        assert_eq!(nupp_sweep_next(h.heap, &mut result), 2);
        assert_eq!(result.header, added as u64);
        assert_eq!((*added).epoch, 21);
        assert_eq!(nupp_sweep_finished(h.heap), 1);
        assert_eq!(h.objects().0, [first, added]);
    }
}
