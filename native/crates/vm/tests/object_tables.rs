#![cfg(feature = "native-runtime")]

#[path = "support/value_table.rs"]
mod value_table;
use value_table::TableFixture;

use nupp_vm::{
    heap::slot_hash,
    value::Value,
};

unsafe extern "C" {
    fn nupp_object_table_probe(table: *const u64, capacity: u64, mask: u64, key: u64) -> u64;
}

#[test]
fn raw_table_probe_distinguishes_nil_zero_tombstones_and_bounded_failure() {
    let mut words = [Value::NIL.0; 20];
    words[0] = 0x1122334455667788;
    words[19] = 0x8877665544332211;
    let keys: Vec<u64> = (0..10000)
        .filter(|&key| slot_hash(key) & 7 == 0)
        .take(4)
        .collect();
    assert_eq!(keys[0], 0);
    for (slot, &key) in keys[..3].iter().enumerate() {
        words[2 + slot * 2] = key;
        words[3 + slot * 2] = if slot == 0 {
            Value::NIL.0
        } else {
            Value::TRUE.0
        };
    }
    let before = words;
    let ptr = unsafe { words.as_ptr().add(2) };
    for (slot, &key) in keys.iter().enumerate() {
        assert_eq!(
            unsafe { nupp_object_table_probe(ptr, 8, 7, key) },
            slot as u64
        );
    }
    assert_eq!(
        unsafe { nupp_object_table_probe(ptr, 8, 7, Value::NIL.0) },
        u64::MAX
    );
    for (capacity, mask) in [(0, 0), (4, 3), (8, 15), (12, 11), (1 << 33, (1 << 33) - 1)] {
        assert_eq!(
            unsafe { nupp_object_table_probe(ptr, capacity, mask, keys[0]) },
            u64::MAX
        );
    }
    assert_eq!(
        unsafe { nupp_object_table_probe(std::ptr::null(), 8, 7, 0) },
        u64::MAX
    );
    let full: Vec<u64> = (0..8).flat_map(|_| [keys[0], Value::NIL.0]).collect();
    assert_eq!(
        unsafe { nupp_object_table_probe(full.as_ptr(), 8, 7, keys[1]) },
        u64::MAX
    );
    assert_eq!(
        words, before,
        "probe cannot mutate borrowed buckets or guard words"
    );
}

#[test]
fn colliding_value_tables_keep_tombstone_ranks_and_live_order_through_rehash() {
    let keys: Vec<Value> = (0..100_000)
        .filter(|&key| slot_hash(key) & 127 == 0)
        .take(40)
        .map(Value)
        .collect();
    assert_eq!(keys.len(), 40);
    let mut table = TableFixture::new(0);
    table.insert(Value::NIL, Value::TRUE);
    table.insert(keys[0], Value::NIL);
    assert_eq!(table.capacity(), 0);
    for &key in &keys[..6] {
        table.insert(key, Value::TRUE);
    }
    assert_eq!(table.capacity(), 8);
    table.insert(keys[1], Value::NIL);
    table.insert(keys[3], Value::NIL);
    assert_eq!(table.position_of(keys[1]), Some(1));
    assert_eq!(table.next_after(keys[1]).map(|pair| pair.0), Some(keys[2]));
    table.insert(keys[1], Value::FALSE);
    assert_eq!(table.position_of(keys[1]), Some(1));
    assert_eq!(
        table.iter().map(|pair| *pair.0).collect::<Vec<_>>(),
        vec![keys[0], keys[1], keys[2], keys[4], keys[5]]
    );
    for &key in &keys[6..] {
        table.insert(key, Value::TRUE);
    }
    assert!(table.capacity() > 8);
    assert_eq!(
        table.position_of(keys[3]),
        None,
        "growth drops a deleted key"
    );
    table.insert(keys[3], Value::FALSE);
    let mut expected = keys
        .iter()
        .copied()
        .filter(|&key| key != keys[3])
        .collect::<Vec<_>>();
    expected.push(keys[3]);
    assert_eq!(
        table.iter().map(|pair| *pair.0).collect::<Vec<_>>(),
        expected
    );
    for (rank, &key) in expected.iter().enumerate() {
        assert_eq!(table.position_of(key), Some(rank));
    }
    let mut walked = Vec::new();
    let mut cursor = Value::NIL;
    while let Some((key, _)) = table.next_after(cursor) {
        walked.push(key);
        cursor = key;
    }
    assert_eq!(walked, expected);
    assert_eq!(
        table.get(&keys[0]),
        Some(&Value::TRUE),
        "zero is a live key"
    );
}

unsafe extern "C" {
    fn nupp_object_table_capacity(wanted: u64) -> u64;
    fn nupp_object_table_needs_growth(length: u64, capacity: u64) -> u64;
    fn nupp_object_table_initialize(table: *mut u64, capacity: u64) -> u64;
    fn nupp_object_table_live_count(
        table: *const u64,
        order: *const u32,
        length: u64,
        capacity: u64,
    ) -> u64;
    fn nupp_object_table_rehash(
        source: *const u64,
        order: *const u32,
        length: u64,
        capacity: u64,
        target: *mut u64,
        target_order: *mut u32,
        target_rank: *mut u32,
        target_capacity: u64,
    ) -> u64;
}

#[test]
fn capacity_and_initialization_bound_overflow_without_touching_invalid_buffers() {
    for (wanted, expected) in [
        (0, 0),
        (1, 8),
        (6, 8),
        (7, 16),
        (12, 16),
        (13, 32),
        (0xc0000000, 0x100000000),
        (0xc0000001, 0),
        (u64::MAX, 0),
    ] {
        assert_eq!(unsafe { nupp_object_table_capacity(wanted) }, expected);
    }
    for (length, capacity, expected) in [
        (0, 0, 1),
        (5, 8, 0),
        (6, 8, 1),
        (0xbfffffff, 0x100000000, 0),
        (0xc0000000, 0x100000000, 1),
        (u64::MAX, 8, 1),
        (0, u64::MAX, 1),
        (0, 12, 1),
    ] {
        assert_eq!(
            unsafe { nupp_object_table_needs_growth(length, capacity) },
            expected
        );
    }
    let mut words = [0x1122334455667788; 18];
    let original = words;
    for capacity in [0, 7, 12, u64::MAX] {
        assert_eq!(
            unsafe { nupp_object_table_initialize(words.as_mut_ptr().add(1), capacity) },
            u64::MAX
        );
        assert_eq!(words, original);
    }
    assert_eq!(
        unsafe { nupp_object_table_initialize(std::ptr::null_mut(), 8) },
        u64::MAX
    );
    assert_eq!(
        unsafe { nupp_object_table_initialize(words.as_mut_ptr().add(1), 8) },
        0
    );
    assert_eq!(words[0], original[0]);
    assert_eq!(words[17], original[17]);
    for bucket in 0..8 {
        assert_eq!(&words[1 + bucket * 2..3 + bucket * 2], &[Value::NIL.0, 0]);
    }
    assert!(std::panic::catch_unwind(|| TableFixture::new(usize::MAX)).is_err());
}

#[test]
fn rehash_preflights_buffers_and_rebuilds_live_order_without_changing_source() {
    let keys: Vec<u64> = (0..10000)
        .filter(|&key| slot_hash(key) & 7 == 0)
        .take(5)
        .collect();
    let order = [3u32, 6, 1, 7, 0];
    let mut source = [Value::NIL.0; 16];
    for (index, &bucket) in order.iter().enumerate() {
        source[bucket as usize * 2] = keys[index];
        source[bucket as usize * 2 + 1] = if index == 1 || index == 3 {
            Value::NIL.0
        } else {
            Value::TRUE.0
        };
    }
    let mut target = [0u64; 18];
    target[0] = 0x1234;
    target[17] = 0x5678;
    let mut target_order = [u32::MAX; 10];
    let mut target_rank = [u32::MAX; 10];
    assert_eq!(
        unsafe { nupp_object_table_initialize(target.as_mut_ptr().add(1), 8) },
        0
    );
    let target_before = target;
    let order_before = target_order;
    let rank_before = target_rank;
    let source_before = source;
    let mut broken_order = order;
    broken_order[4] = 8;
    assert_eq!(
        unsafe { nupp_object_table_live_count(source.as_ptr(), broken_order.as_ptr(), 5, 8) },
        u64::MAX
    );
    assert_eq!(
        unsafe {
            nupp_object_table_rehash(
                source.as_ptr(),
                broken_order.as_ptr(),
                5,
                8,
                target.as_mut_ptr().add(1),
                target_order.as_mut_ptr().add(1),
                target_rank.as_mut_ptr().add(1),
                8,
            )
        },
        u64::MAX
    );
    assert_eq!(target, target_before);
    assert_eq!(target_order, order_before);
    assert_eq!(target_rank, rank_before);
    let mut dense = [Value::NIL.0; 16];
    let dense_order = [0u32, 1, 2, 3, 4, 5];
    for index in 0..6 {
        dense[index * 2] = index as u64 * 16;
        dense[index * 2 + 1] = Value::TRUE.0;
    }
    assert_eq!(
        unsafe {
            nupp_object_table_rehash(
                dense.as_ptr(),
                dense_order.as_ptr(),
                6,
                8,
                target.as_mut_ptr().add(1),
                target_order.as_mut_ptr().add(1),
                target_rank.as_mut_ptr().add(1),
                8,
            )
        },
        u64::MAX
    );
    assert_eq!(
        target, target_before,
        "capacity refusal must precede writes"
    );
    target[1] = 0;
    let dirty = target;
    assert_eq!(
        unsafe {
            nupp_object_table_rehash(
                source.as_ptr(),
                order.as_ptr(),
                5,
                8,
                target.as_mut_ptr().add(1),
                target_order.as_mut_ptr().add(1),
                target_rank.as_mut_ptr().add(1),
                8,
            )
        },
        u64::MAX
    );
    assert_eq!(target, dirty, "dirty target must fail before any write");
    target = target_before;
    assert_eq!(
        unsafe {
            nupp_object_table_rehash(
                source.as_ptr(),
                order.as_ptr(),
                5,
                8,
                source.as_mut_ptr(),
                target_order.as_mut_ptr().add(1),
                target_rank.as_mut_ptr().add(1),
                8,
            )
        },
        u64::MAX
    );
    assert_eq!(source, source_before);
    assert_eq!(
        unsafe { nupp_object_table_live_count(source.as_ptr(), order.as_ptr(), 5, 8) },
        3
    );
    assert_eq!(
        unsafe {
            nupp_object_table_rehash(
                source.as_ptr(),
                order.as_ptr(),
                5,
                8,
                target.as_mut_ptr().add(1),
                target_order.as_mut_ptr().add(1),
                target_rank.as_mut_ptr().add(1),
                8,
            )
        },
        3
    );
    assert_eq!(source, source_before);
    assert_eq!(target[0], 0x1234);
    assert_eq!(target[17], 0x5678);
    assert_eq!(target_order[0], u32::MAX);
    assert_eq!(target_order[9], u32::MAX);
    assert_eq!(target_rank[0], u32::MAX);
    assert_eq!(target_rank[9], u32::MAX);
    for (rank, &key) in [keys[0], keys[2], keys[4]].iter().enumerate() {
        let bucket = target_order[rank + 1] as usize;
        assert_eq!(target[1 + bucket * 2], key);
        assert_eq!(target[2 + bucket * 2], Value::TRUE.0);
        assert_eq!(target_rank[bucket + 1], rank as u32);
    }
    let mut empty = [0u64; 16];
    unsafe {
        nupp_object_table_initialize(empty.as_mut_ptr(), 8);
    }
    assert_eq!(
        unsafe {
            nupp_object_table_rehash(
                std::ptr::null(),
                std::ptr::null(),
                0,
                0,
                empty.as_mut_ptr(),
                target_order.as_mut_ptr().add(1),
                target_rank.as_mut_ptr().add(1),
                8,
            )
        },
        0
    );
}

#[test]
fn failed_growth_preserves_the_old_backing_owner() {
    use std::panic::{AssertUnwindSafe, catch_unwind};
    let mut table = TableFixture::new(0);
    for key in 0..6 {
        table.insert(Value(key * 16), Value::TRUE);
    }
    let pointer = table.ptr;
    let capacity = table.cap;
    let length = table.len;
    table.len = capacity + 1;
    assert!(catch_unwind(AssertUnwindSafe(|| table.insert(Value(100000), Value::TRUE))).is_err());
    assert_eq!(table.ptr, pointer);
    assert_eq!(table.cap, capacity);
    table.len = length;
    for key in 0..6 {
        assert_eq!(table.get(&Value(key * 16)), Some(&Value::TRUE));
    }
}

#[test]
fn weak_key_value_collection_and_growth_keep_survivors_in_order() {
    use nupp_vm::interp::Interp;
    let mut vm = Box::new(Interp::new());
    vm.heap.stress = true;
    vm.heap.oracle = true;
    vm.heap.quarantine = true;
    let table = vm.new_table();
    vm.register(table);
    let meta = vm.new_table();
    let meta_root = vm.register(meta);
    let mode_key = vm.intern("__mode");
    vm.register(mode_key);
    let mode = vm.intern("kv");
    vm.register(mode);
    vm.set_index(meta, mode_key, mode);
    vm.set_metatable(table, meta);
    vm.release(meta_root);
    let mut expected = Vec::new();
    for index in 0..8 {
        let key = vm.new_table();
        let key_root = vm.register(key);
        let value = vm.new_table();
        let value_root = vm.register(value);
        vm.set_index(table, key, value);
        if index % 2 == 0 {
            vm.release(key_root);
            vm.release(value_root);
        } else {
            expected.push((key, value));
        }
    }
    vm.full_cycle();
    vm.check_oracle();
    assert_eq!(
        vm.table_keys(table),
        expected.iter().map(|pair| pair.0).collect::<Vec<_>>()
    );
    for _ in 0..32 {
        let key = vm.new_table();
        vm.register(key);
        let value = vm.new_table();
        vm.register(value);
        vm.set_index(table, key, value);
        expected.push((key, value));
        vm.full_cycle();
        vm.check_oracle();
    }
    assert_eq!(
        vm.table_keys(table),
        expected.iter().map(|pair| pair.0).collect::<Vec<_>>()
    );
    for (key, value) in expected {
        assert_eq!(vm.get_index(table, key), value);
    }
}
