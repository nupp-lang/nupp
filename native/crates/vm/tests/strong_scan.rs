use nupp_vm::{
    heap::{Header, COLOR_BLACK, COLOR_GRAY, COLOR_WHITE, KIND_CELL, KIND_CLOSURE},
    value::Value,
};
use std::{ffi::c_void, ptr::NonNull};

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
    fn nupp_object_constructor_payload(kind: u64, count: u64) -> u64;
    fn nupp_object_cell_initialize(header: *mut Header, value: u64) -> u64;
    fn nupp_object_closure_initialize(
        header: *mut Header,
        function: u64,
        values: *const Value,
        count: u64,
    ) -> u64;
    fn nupp_scan_strong(heap: *mut c_void, header: *mut Header) -> u64;
    fn nupp_allocator_gray_pop(heap: *mut c_void) -> *mut Header;
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
    fn alloc(&self, kind: u8, count: usize) -> *mut Header {
        unsafe {
            let size = nupp_object_constructor_payload(kind as u64, count as u64);
            assert_ne!(size, u64::MAX);
            let h = nupp_allocator_allocate(self.heap, kind as u64, size, 0, 1, 0);
            assert!(!h.is_null());
            h
        }
    }
    fn cell(&self, value: Value) -> *mut Header {
        unsafe {
            let h = self.alloc(KIND_CELL, 0);
            assert_eq!(nupp_object_cell_initialize(h, value.0), 0);
            h
        }
    }
    fn closure(&self, values: &[Value]) -> *mut Header {
        unsafe {
            let h = self.alloc(KIND_CLOSURE, values.len());
            assert_eq!(
                nupp_object_closure_initialize(h, 0, values.as_ptr(), values.len() as u64),
                0
            );
            h
        }
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
fn object(h: *mut Header) -> Value {
    Value::obj(NonNull::new(h).unwrap())
}

#[test]
fn scalar_and_nil_slots_count_without_queue_entries() {
    unsafe {
        let h = Heap::new();
        for values in [
            vec![],
            vec![Value::NIL],
            vec![
                Value::NIL,
                Value::FALSE,
                Value::TRUE,
                Value::inline_integer(7).unwrap(),
            ],
        ] {
            let parent = h.closure(&values);
            (*parent).color = COLOR_GRAY;
            assert_eq!(nupp_scan_strong(h.heap, parent), values.len() as u64);
            assert_eq!((*parent).color, COLOR_BLACK);
            assert!(nupp_allocator_gray_pop(h.heap).is_null());
        }
        let cell = h.cell(Value::NIL);
        (*cell).color = COLOR_GRAY;
        assert_eq!(nupp_scan_strong(h.heap, cell), 1);
        assert_eq!((*cell).color, COLOR_BLACK);
        assert!(nupp_allocator_gray_pop(h.heap).is_null());
    }
}

#[test]
fn only_white_children_are_enqueued_once_in_traversal_order() {
    unsafe {
        let h = Heap::new();
        let a = h.cell(Value::NIL);
        let b = h.cell(Value::NIL);
        let c = h.cell(Value::NIL);
        (*b).color = COLOR_GRAY;
        (*c).color = COLOR_BLACK;
        let parent = h.closure(&[
            Value::NIL,
            object(a),
            object(b),
            object(a),
            object(c),
            Value::FALSE,
        ]);
        (*parent).color = COLOR_GRAY;
        assert_eq!(nupp_scan_strong(h.heap, parent), 6);
        assert_eq!((*parent).color, COLOR_BLACK);
        assert_eq!((*a).color, COLOR_GRAY);
        assert_eq!((*b).color, COLOR_GRAY);
        assert_eq!((*c).color, COLOR_BLACK);
        assert_eq!(nupp_allocator_gray_pop(h.heap), a);
        assert!(nupp_allocator_gray_pop(h.heap).is_null());
    }
}

#[test]
fn self_edges_and_cycles_do_not_requeue_scanned_parents() {
    unsafe {
        let h = Heap::new();
        let a = h.cell(Value::NIL);
        let b = h.cell(Value::NIL);
        let parent = h.alloc(KIND_CLOSURE, 4);
        let values = [object(a), object(parent), object(b), object(a)];
        assert_eq!(
            nupp_object_closure_initialize(parent, 0, values.as_ptr(), 4),
            0
        );
        assert_eq!(nupp_object_cell_initialize(a, object(parent).0), 0);
        (*parent).color = COLOR_GRAY;
        assert_eq!(nupp_scan_strong(h.heap, parent), 4);
        assert_eq!((*parent).color, COLOR_BLACK);
        assert_eq!(nupp_allocator_gray_pop(h.heap), b);
        assert_eq!(nupp_allocator_gray_pop(h.heap), a);
        assert_eq!(nupp_scan_strong(h.heap, a), 1);
        assert_eq!((*a).color, COLOR_BLACK);
        assert!(nupp_allocator_gray_pop(h.heap).is_null());
    }
}

#[test]
fn queue_growth_keeps_all_children_and_counts_duplicate_slots() {
    unsafe {
        let h = Heap::new();
        let children: Vec<_> = (0..8193).map(|_| h.cell(Value::NIL)).collect();
        let mut values: Vec<_> = children.iter().map(|&p| object(p)).collect();
        values.extend([
            object(children[0]),
            Value::NIL,
            object(children[8192]),
            Value::FALSE,
        ]);
        let parent = h.closure(&values);
        (*parent).color = COLOR_GRAY;
        assert!(children.iter().all(|&p| (*p).color == COLOR_WHITE));
        assert_eq!(nupp_scan_strong(h.heap, parent), 8197);
        assert_eq!((*parent).color, COLOR_BLACK);
        for &child in children.iter().rev() {
            assert_eq!(nupp_allocator_gray_pop(h.heap), child);
            assert_eq!((*child).color, COLOR_GRAY);
        }
        assert!(nupp_allocator_gray_pop(h.heap).is_null());
    }
}
