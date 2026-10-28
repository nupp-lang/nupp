use nupp_vm::{
    heap::{COLOR_BLACK, COLOR_GRAY, COLOR_WHITE, Header, KIND_CELL, KIND_STR},
    value::{QNAN, T_OBJ, Value},
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
    fn nupp_allocator_reclaim(heap: *mut c_void, header: *mut Header, stress: u64, quarantine: u64);
    fn nupp_allocator_gray_pop(heap: *mut c_void) -> *mut Header;
    fn nupp_root_candidate(heap: *mut c_void, value: u64) -> u64;
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
    fn alloc(&self, payload: u64) -> *mut Header {
        unsafe {
            let h = nupp_allocator_allocate(
                self.heap,
                if payload == 8 { KIND_CELL } else { KIND_STR } as u64,
                payload,
                0,
                1,
                0,
            );
            assert!(!h.is_null());
            h
        }
    }
    fn candidate(&self, value: Value) -> u64 {
        unsafe { nupp_root_candidate(self.heap, value.0) }
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
fn nonnull_candidates_count_before_safe_live_slot_validation() {
    unsafe {
        let h = Heap::new();
        let live = h.alloc(8);
        let large = h.alloc(50000);
        let freed = h.alloc(8);
        nupp_allocator_reclaim(h.heap, freed, 0, 1);
        let mut outside = Box::new(Header {
            kind: KIND_CELL,
            color: COLOR_WHITE,
            class: 0,
            flags: 0,
            epoch: 0,
            size: 40,
            aux: 0,
            aux_ptr: std::ptr::null_mut(),
            aux_len: 0,
        });
        for value in [
            Value::NIL,
            Value::FALSE,
            Value::TRUE,
            Value::num(f64::NAN),
            Value::num(-0.0),
            Value::inline_integer(7).unwrap(),
            Value(QNAN | T_OBJ),
            Value(T_OBJ | 1),
        ] {
            assert_eq!(h.candidate(value), 0);
        }
        for pointer in [
            1usize as *mut Header,
            live.cast::<u8>().add(1).cast(),
            live.cast::<u8>().sub(1).cast(),
            large.cast::<u8>().add(32).cast(),
            &mut *outside,
            freed,
        ] {
            assert_eq!(h.candidate(object(pointer)), 1);
        }
        assert!(nupp_allocator_gray_pop(h.heap).is_null());
        assert_eq!(outside.color, COLOR_WHITE);
        assert_eq!((*live).color, COLOR_WHITE);
        assert_eq!(h.candidate(object(live)), 1);
        assert_eq!(h.candidate(object(live)), 1);
        assert_eq!(h.candidate(object(large)), 1);
        assert_eq!(nupp_allocator_gray_pop(h.heap), large);
        assert_eq!(nupp_allocator_gray_pop(h.heap), live);
        assert!(nupp_allocator_gray_pop(h.heap).is_null());
    }
}
#[test]
fn gray_growth_preserves_root_order_and_counts_duplicates_and_black_objects() {
    unsafe {
        let h = Heap::new();
        let roots: Vec<_> = (0..8193).map(|_| h.alloc(8)).collect();
        let black = h.alloc(8);
        (*black).color = COLOR_BLACK;
        let mut count = 0;
        for &root in &roots {
            count += h.candidate(object(root));
        }
        count += h.candidate(object(roots[0]));
        count += h.candidate(object(black));
        assert_eq!(count, 8195);
        for &root in roots.iter().rev() {
            assert_eq!(nupp_allocator_gray_pop(h.heap), root);
            assert_eq!((*root).color, COLOR_GRAY);
        }
        assert!(nupp_allocator_gray_pop(h.heap).is_null());
        assert_eq!((*black).color, COLOR_BLACK);
    }
}
#[cfg(feature = "compiled-runtime")]
#[test]
fn compiled_map_borrow_allows_gray_pool_growth_without_reentry() {
    unsafe {
        let h = Heap::new();
        let roots: Vec<_> = (0..8193).map(|_| h.alloc(8)).collect();
        let mut slots: Vec<u64> = roots.iter().map(|&root| object(root).0).collect();
        slots.extend([0, 0]);
        let caller = slots.as_ptr().add(roots.len()) as usize;
        let code_identity = Box::new(0u8);
        let ret = (&*code_identity) as *const u8 as usize;
        let frame = [caller, ret];
        nupp_vm::compiled::CODE_MAPS.lock().unwrap().push((
            ret,
            ret + 1,
            vec![(
                0,
                (roots.len() * 8) as u32,
                (0..roots.len()).map(|i| (i * 8) as u32).collect(),
            )],
        ));
        let mut candidates = 0;
        nupp_vm::compiled::walk_compiled_roots(frame.as_ptr() as usize, &mut |word| {
            candidates += h.candidate(Value(word));
        });
        nupp_vm::compiled::CODE_MAPS
            .lock()
            .unwrap()
            .retain(|(start, _, _)| *start != ret);
        assert_eq!(candidates, 8193);
        for &root in roots.iter().rev() {
            assert_eq!(nupp_allocator_gray_pop(h.heap), root);
        }
        assert!(nupp_allocator_gray_pop(h.heap).is_null());
    }
}
