#![cfg(feature = "native-runtime")]

use std::cell::{Cell, RefCell};
use std::rc::Rc;

use nupp_vm::heap::{CLASS_LARGE, Heap, Roots};
use nupp_vm::value::Value;

#[derive(Default)]
struct Keep(RefCell<Vec<Value>>);
impl Roots for Keep {
    fn each_root(&self, f: &mut dyn FnMut(Value)) {
        for &value in self.0.borrow().iter() {
            f(value);
        }
    }
}

#[test]
fn allocator_transports_external_bytes_and_reuses_reclaimed_slots() {
    let roots = Keep::default();
    let mut heap = Heap::new();
    heap.automatic_collection = false;
    let small = heap.new_bytes(17, &roots);
    let large = heap.new_string(&"x".repeat(50_000), &roots);
    let small_header = small.as_obj().unwrap();
    let large_header = large.as_obj().unwrap();
    assert_eq!(unsafe { large_header.as_ref().class }, CLASS_LARGE);
    assert!(heap.is_live_slot(small_header));
    assert!(heap.is_live_slot(large_header));
    let expected: usize = heap
        .objects()
        .iter()
        .map(|header| unsafe {
            let h = header.as_ref();
            h.size as usize + h.external_bytes()
        })
        .sum();
    assert_eq!(heap.live_bytes, expected);
    roots.0.borrow_mut().push(large);
    heap.full_cycle(&roots);
    assert!(!heap.is_live_slot(small_header));
    assert!(heap.is_live_slot(large_header));
    let replacement = heap.new_bytes(17, &roots);
    assert_eq!(replacement.as_obj().unwrap(), small_header);
    roots.0.borrow_mut().clear();
    heap.full_cycle(&roots);
    assert!(
        !heap.is_live_slot(large_header),
        "large lookup must not dereference an unmapped header"
    );
    assert_eq!(heap.object_count(), 0);
    assert_eq!(heap.live_bytes, 0);
    assert_eq!(heap.stats.allocated, 3);
    assert_eq!(heap.stats.freed, 3);
}

#[test]
fn initial_external_capacities_stay_in_the_allocator_snapshot() {
    let roots = Keep::default();
    let mut heap = Heap::new();
    heap.automatic_collection = false;
    let table = heap.new_table_sized(8, 12, &roots);
    heap.new_buffer(&roots);
    heap.new_bytes(123, &roots);
    heap.new_aligned_bytes(257, 64, &roots);
    heap.new_storage(19, &roots);
    heap.new_iter(0, table, Value::NIL, vec![table; 23], &roots);
    heap.new_userdata(Box::new(42u64), Value::NIL, Value::NIL, 4097, &roots);
    let expected: usize = heap
        .objects()
        .iter()
        .map(|header| unsafe {
            let h = header.as_ref();
            h.size as usize + h.external_bytes()
        })
        .sum();
    assert_eq!(heap.object_count(), 7);
    assert_eq!(heap.live_bytes, expected);
    heap.full_cycle(&roots);
    assert_eq!(heap.object_count(), 0);
    assert_eq!(heap.live_bytes, 0);
    assert_eq!(heap.stats.allocated, 7);
    assert_eq!(heap.stats.freed, 7);
}

#[test]
fn payloads_drop_once_before_the_allocator_arena_closes() {
    struct Count(Rc<Cell<u32>>);
    impl Drop for Count {
        fn drop(&mut self) {
            self.0.set(self.0.get() + 1);
        }
    }
    let drops = Rc::new(Cell::new(0));
    let roots = Keep::default();
    {
        let mut heap = Heap::new();
        heap.automatic_collection = false;
        heap.new_userdata(
            Box::new(Count(drops.clone())),
            Value::NIL,
            Value::NIL,
            0,
            &roots,
        );
        heap.full_cycle(&roots);
        assert_eq!(drops.get(), 1);
        let live = heap.new_userdata(
            Box::new(Count(drops.clone())),
            Value::NIL,
            Value::NIL,
            0,
            &roots,
        );
        roots.0.borrow_mut().push(live);
        heap.full_cycle(&roots);
        assert_eq!(drops.get(), 1);
    }
    assert_eq!(drops.get(), 2);
}

#[test]
fn large_compaction_preserves_survivor_indices_across_later_reclaims() {
    let roots = Keep::default();
    let mut heap = Heap::new();
    heap.automatic_collection = false;
    let first = heap
        .new_string(&"a".repeat(50_000), &roots)
        .as_obj()
        .unwrap();
    let middle = heap.new_string(&"b".repeat(50_000), &roots);
    let last = heap.new_string(&"c".repeat(50_000), &roots);
    roots.0.borrow_mut().extend([middle, last]);
    heap.full_cycle(&roots);
    assert!(!heap.is_live_slot(first));
    assert_eq!(heap.object_count(), 2);
    roots.0.borrow_mut().remove(0);
    heap.full_cycle(&roots);
    assert!(!heap.is_live_slot(middle.as_obj().unwrap()));
    assert!(heap.is_live_slot(last.as_obj().unwrap()));
    let appended = heap.new_string(&"d".repeat(50_000), &roots);
    roots.0.borrow_mut().push(appended);
    roots.0.borrow_mut().remove(0);
    heap.full_cycle(&roots);
    assert!(!heap.is_live_slot(last.as_obj().unwrap()));
    assert!(heap.is_live_slot(appended.as_obj().unwrap()));
    assert_eq!(heap.object_count(), 1);
    roots.0.borrow_mut().clear();
    heap.full_cycle(&roots);
    assert_eq!(heap.object_count(), 0);
    assert_eq!(heap.live_bytes, 0);
    assert_eq!(heap.stats.freed, 4);
}
