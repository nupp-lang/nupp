use nupp_vm::heap::ValueTable;
use nupp_vm::value::Value;
use std::collections::HashMap;

fn key(i: u64) -> Value { Value::num((i as f64) * 1.5 + 3.0) }

#[test]
fn matches_a_map() {
    let mut t = ValueTable::new();
    let mut m: HashMap<u64, Value> = HashMap::new();
    let mut x: u64 = 0x9E3779B97F4A7C15;
    for step in 0..200_000u64 {
        x ^= x << 13; x ^= x >> 7; x ^= x << 17;
        let k = key(x % 5000);
        let op = (x >> 20) % 10;
        if op < 6 { let v = Value::num(step as f64); t.insert(k, v); m.insert(k.0, v); }
        else if op < 8 { t.insert(k, Value::NIL); m.remove(&k.0); }
        else { let got = t.get(&k).copied(); let want = m.get(&k.0).copied(); assert_eq!(got, want, "step {step}"); }
    }
    let mut seen: HashMap<u64, Value> = HashMap::new();
    for (k, v) in t.iter() { seen.insert(k.0, *v); }
    assert_eq!(seen, m);
    for (k, v) in &m { assert_eq!(t.get(&Value(*k)).copied(), Some(*v)); }
}

#[test]
fn small_and_empty() {
    let t = ValueTable::new();
    assert!(t.get(&key(1)).is_none()); assert_eq!(t.iter().count(), 0);
    let mut t = ValueTable::with_capacity(3);
    t.insert(key(1), Value::num(1.0)); t.insert(key(2), Value::num(2.0)); t.insert(key(1), Value::NIL);
    assert!(t.get(&key(1)).is_none()); assert_eq!(t.get(&key(2)).map(|v| v.as_num()), Some(2.0));
    assert_eq!(t.iter().count(), 1);
}

#[test]
fn nil_is_never_a_key() {
    let mut t = ValueTable::new();
    t.insert(key(1), Value::num(1.0));
    assert!(t.get(&Value::NIL).is_none());
    t.insert(Value::NIL, Value::num(5.0));
    assert!(t.get(&Value::NIL).is_none()); assert_eq!(t.iter().count(), 1);
}

#[test]
fn churn_stays_bounded() {
    // Distinct keys stored and then set to nil, a million times: a nil value
    // keeps its entry until the next rehash, which drops it, so the capacity
    // follows the live count rather than the history.
    let mut t = ValueTable::new();
    let mut max_cap = 0;
    for i in 0..1_000_000u64 {
        let k = key(i);
        t.insert(k, Value::num(1.0));
        if i >= 8 { t.insert(key(i - 8), Value::NIL); }
        max_cap = max_cap.max(t.capacity());
    }
    assert!(max_cap <= 64, "capacity reached {max_cap}");
    assert_eq!(t.iter().count(), 8);
}
