#![cfg(feature = "native-runtime")]

use nupp_vm::{
    heap::{ValueTable, slot_hash},
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
    let mut table = ValueTable::new();
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
