use nupp_vm::{image, interp::Interp, value::Value};

const FLOAT_READ: &str = "FUnbox 0 2\nGetIdxF 3 1 0";

fn vm(read: &str) -> Box<Interp> {
    let mut vm = Box::new(Interp::new());
    let source = r#"
function read 0 2 12 1 vv:v
READ
Ret 3
end
function index 1 2 16 1 vv:v
const 0 func 2
const 1 num 64
K 10 0
K 11 1
CallDyn 10 10 1
Ret 10
end
function grow 2 1 240 1 v:v
const 0 num 1
const 1 func 2
const 2 num 99
const 3 builtin collectgarbage
K 2 0
Lt 3 1 2
JmpIf 3 6
Sub 201 1 2
K 200 1
CallDyn 200 200 1
Ret 200
RetNil
RetNil
K 200 3
CallDyn 200 200 0
K 239 2
Ret 239
end
function write 3 3 12 1 vvv:v
FUnbox 0 2
SetIdxF 1 0 3
RetNil
end
function write_any 4 3 12 1 vvv:v
SetIdx 1 2 3
RetNil
end
entry 0
"#
    .replace("READ", read);
    image::load(&mut vm, &source).unwrap();
    vm.install_globals();
    vm.entries.resize(vm.funcs.len(), 0);
    vm.prepare_threaded();
    vm.heap.oracle = true;
    vm.heap.quarantine = true;
    vm
}

fn check_index_hole(read: &str) {
    let mut vm = vm(read);
    let t = vm.new_table();
    vm.register(t);
    for i in 1..=3 {
        vm.set_index(t, Value::num(i as f64), Value::FALSE);
    }
    vm.set_index(t, Value::num(2.0), Value::NIL);
    let mt = vm.new_table();
    vm.register(mt);
    let key = vm.intern("__index");
    vm.set_index(mt, key, Value::func(1));
    vm.set_metatable(t, mt);
    assert_eq!(
        vm.call_value(Value::func(0), &[t, Value::num(1.0)]),
        vec![Value::FALSE]
    );
    assert_eq!(
        vm.call_value(Value::func(0), &[t, Value::num(2.0)]),
        vec![Value::num(99.0)]
    );
    vm.full_cycle();
    vm.check_oracle();
}

#[test]
fn dense_appends_keep_gc_roots_accounting_and_sparse_key_migration() {
    let mut vm = vm(FLOAT_READ);
    let t = vm.new_table();
    vm.register(t);
    let mut capacity_added = 0;
    for i in 1..=100 {
        let v = vm.heap_new_string(&format!("element {i}"));
        let before = vm.heap.live_bytes;
        vm.call_value(Value::func(3), &[t, Value::num(i as f64), v]);
        capacity_added += vm.heap.live_bytes - before;
    }
    assert!(capacity_added >= 100 * 8);
    // The next contiguous key already has a successor in the hash part.
    // Appending must migrate it into the array instead of hiding it.
    vm.set_index(t, Value::num(102.0), Value::TRUE);
    vm.call_value(Value::func(3), &[t, Value::num(101.0), Value::FALSE]);
    assert_eq!(vm.array_len(t), 102);
    assert_eq!(vm.get_index(t, Value::num(102.0)), Value::TRUE);
    vm.full_cycle();
    vm.check_oracle();
    for i in 1..=100 {
        let v = vm.get_index(t, Value::num(i as f64));
        assert_eq!(vm.bytes_of(v), format!("element {i}").as_bytes());
    }
    vm.call_value(Value::func(3), &[t, Value::num(102.0), Value::NIL]);
    assert_eq!(vm.array_len(t), 101);
}

#[test]
fn float_index_hole_calls_index_and_reloads_a_grown_stack() {
    check_index_hole(FLOAT_READ);
}

#[test]
fn integer_index_hole_calls_index_and_reloads_a_grown_stack() {
    check_index_hole("IUnbox 0 2\nGetIdxI 3 1 0");
}

#[test]
fn value_index_hole_calls_index_and_reloads_a_grown_stack() {
    check_index_hole("GetIdx 3 1 2");
}

#[test]
fn value_store_canonicalizes_a_long_string_before_testing_newindex() {
    let mut vm = vm(FLOAT_READ);
    let t = vm.new_table();
    vm.register(t);
    let text = "a long key which is deliberately longer than the automatic interning threshold";
    let canonical = vm.intern(text);
    vm.set_index(t, canonical, Value::FALSE);
    let mt = vm.new_table();
    vm.register(mt);
    let newindex = vm.intern("__newindex");
    vm.set_index(mt, newindex, Value::func(1));
    vm.set_metatable(t, mt);
    let key = vm.heap_new_string(text);
    assert_ne!(key, canonical);
    vm.call_value(Value::func(4), &[t, key, Value::TRUE]);
    assert_eq!(vm.get_index(t, canonical), Value::TRUE);
    vm.full_cycle();
    vm.check_oracle();
}
