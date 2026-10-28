use nupp_vm::{
    heap::{
        COLOR_BLACK, COLOR_GRAY, COLOR_WHITE, Header, KIND_CELL, KIND_FREED, KIND_INTEGER,
        KIND_SLICE, KIND_STR, KIND_TABLE,
    },
    value::Value,
};
use std::{ffi::c_void, ptr::NonNull};
#[repr(C)]
#[derive(Default)]
struct Cursor {
    index: u64,
    header: u64,
    changed: u64,
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
    fn nupp_allocator_gray_pop(heap: *mut c_void) -> *mut Header;
    fn nupp_weak_cycle_reset(heap: *mut c_void);
    fn nupp_weak_cycle_remember(heap: *mut c_void, header: *mut Header, mode: u64);
    fn nupp_weak_cycle_scan(heap: *mut c_void, header: *mut Header, mode: u64);
    fn nupp_weak_cycle_propagate(heap: *mut c_void) -> u64;
    fn nupp_weak_cycle_clear_next(heap: *mut c_void, cursor: *mut Cursor) -> u64;
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
    fn alloc(&self, kind: u8) -> *mut Header {
        unsafe {
            let h = nupp_allocator_allocate(
                self.heap,
                kind as u64,
                if kind == KIND_TABLE { 96 } else { 16 },
                0,
                1,
                0,
            );
            assert!(!h.is_null());
            h
        }
    }
    fn table(&self, array: &mut [Value], buckets: &mut [Value], meta: Value) -> *mut Header {
        unsafe {
            assert_eq!(buckets.len() % 2, 0);
            let h = self.alloc(KIND_TABLE);
            let body = h.add(1).cast::<u64>();
            std::ptr::write_bytes(body, 0, 12);
            *body.add(1) = array.as_mut_ptr() as u64;
            *body.add(2) = array.len() as u64;
            *body.add(3) = array.len() as u64;
            *body.add(4) = buckets.as_mut_ptr() as u64;
            *body.add(6) = (buckets.len() / 2) as u64;
            *body.add(11) = meta.0;
            // Deliberately stale header mirrors: the body descriptor is authoritative.
            (*h).aux_ptr = std::ptr::null_mut();
            (*h).aux_len = 0;
            h
        }
    }
    fn clear(&self) -> Vec<(*mut Header, u64)> {
        let mut cursor = Cursor::default();
        let mut out = vec![];
        unsafe {
            while nupp_weak_cycle_clear_next(self.heap, &mut cursor) != 0 {
                out.push((cursor.header as *mut Header, cursor.changed));
            }
            assert_eq!((cursor.header, cursor.changed), (0, 0));
        }
        out
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
fn value(h: *mut Header) -> Value {
    Value::obj(NonNull::new(h).unwrap())
}
#[test]
fn remembered_modes_and_authoritative_descriptors_survive_later_mode_changes() {
    unsafe {
        assert_eq!(std::mem::size_of::<Cursor>(), 24);
        assert_eq!(std::mem::offset_of!(Cursor, changed), 16);
        let h = Heap::new();
        let dead = h.alloc(KIND_CELL);
        let mut array = [value(dead), Value::NIL];
        let table = h.table(&mut array, &mut [], Value::NIL);
        nupp_weak_cycle_remember(h.heap, table, 2);
        (*table).aux = 0;
        assert_eq!(h.clear(), [(table, 1)]);
        assert_eq!(array, [Value::NIL; 2]);
        assert_eq!((*table).aux_len, 0);
        assert_eq!((*table).aux_ptr, array.as_mut_ptr().cast());
        array[0] = value(dead);
        *table.add(1).cast::<u64>().add(2) = 2;
        nupp_weak_cycle_remember(h.heap, table, (*table).aux as u64);
        (*table).aux = 2;
        assert_eq!(h.clear(), [(table, 0)]);
        assert_eq!(array[0], value(dead));
        assert_eq!((*table).aux_len, 2);
        assert!(h.clear().is_empty());
        assert_eq!((*dead).color, COLOR_WHITE);
    }
}
#[test]
fn propagation_reaches_ephemeron_fixed_point_in_scan_order() {
    unsafe {
        let h = Heap::new();
        let first = h.alloc(KIND_CELL);
        let second = h.alloc(KIND_CELL);
        let tail = h.alloc(KIND_CELL);
        let dead = h.alloc(KIND_CELL);
        let meta = h.alloc(KIND_CELL);
        let mut a = [value(second), value(tail)];
        let mut b = [value(first), value(second), value(dead), Value::TRUE];
        let ta = h.table(&mut [], &mut a, Value::NIL);
        let tb = h.table(&mut [], &mut b, value(meta));
        nupp_weak_cycle_scan(h.heap, ta, 1);
        nupp_weak_cycle_scan(h.heap, tb, 1);
        assert_eq!((*ta).color, COLOR_BLACK);
        assert_eq!((*tb).color, COLOR_BLACK);
        assert_eq!(nupp_allocator_gray_pop(h.heap), meta);
        assert!(nupp_allocator_gray_pop(h.heap).is_null());
        assert_eq!(nupp_weak_cycle_propagate(h.heap), 0);
        (*first).color = COLOR_BLACK;
        assert_eq!(nupp_weak_cycle_propagate(h.heap), 1);
        assert_eq!(nupp_allocator_gray_pop(h.heap), second);
        assert_eq!(nupp_weak_cycle_propagate(h.heap), 1);
        assert_eq!(nupp_allocator_gray_pop(h.heap), tail);
        assert_eq!(nupp_weak_cycle_propagate(h.heap), 0);
        assert_eq!((*second).color, COLOR_GRAY);
        assert_eq!((*tail).color, COLOR_GRAY);
        assert_eq!(h.clear(), [(ta, 0), (tb, 1)]);
        assert_eq!(b[3], Value::NIL);
        assert_eq!(b[2], value(dead));
    }
}
#[test]
fn scalar_and_stringlike_immunity_preserves_extent_and_hash_keys() {
    unsafe {
        let h = Heap::new();
        let mut array = vec![
            Value::FALSE,
            Value::TRUE,
            Value::inline_integer(3).unwrap(),
            Value::num(f64::NAN),
            Value::NIL,
        ];
        for kind in [KIND_STR, KIND_SLICE, KIND_INTEGER] {
            array.push(value(h.alloc(kind)));
        }
        let expected = array.clone();
        let dead = h.alloc(KIND_CELL);
        let mut buckets = [Value::FALSE, value(dead), value(dead), Value::TRUE];
        let t = h.table(&mut array, &mut buckets, Value::NIL);
        nupp_weak_cycle_remember(h.heap, t, 3);
        assert_eq!(h.clear(), [(t, 1)]);
        assert_eq!(array, expected);
        assert_eq!((*t).aux_len, expected.len() as u64);
        assert_eq!(buckets, [Value::FALSE, Value::NIL, value(dead), Value::NIL]);
    }
}
#[test]
fn remembered_backing_growth_reset_and_skipped_headers_keep_order() {
    unsafe {
        let h = Heap::new();
        let a = h.table(&mut [], &mut [], Value::NIL);
        let b = h.table(&mut [], &mut [], Value::NIL);
        let gone = h.alloc(KIND_CELL);
        (*gone).kind = KIND_FREED;
        for i in 0..8193 {
            nupp_weak_cycle_remember(h.heap, if i % 2 == 0 { a } else { b }, 2);
        }
        nupp_weak_cycle_remember(h.heap, gone, 2);
        let cleared = h.clear();
        assert_eq!(cleared.len(), 8193);
        for (i, &entry) in cleared.iter().enumerate() {
            assert_eq!(entry, (if i % 2 == 0 { a } else { b }, 0));
        }
        nupp_weak_cycle_remember(h.heap, a, 2);
        nupp_weak_cycle_reset(h.heap);
        assert!(h.clear().is_empty());
        nupp_weak_cycle_remember(h.heap, b, 2);
        assert_eq!(h.clear(), [(b, 0)]);
    }
}
