#![cfg(feature = "native-runtime")]
use nupp_vm::{
    interp::Interp,
    persist::{self, Policies, ResourceCodecs},
    value::Value,
};

#[test]
fn shape_methods_root_nil_keys_and_live_values_until_remove_or_clear() {
    let mut vm = Interp::new();
    vm.heap.automatic_collection = false;
    let shape = vm.heap.shape("Methods", &[], &[]);
    let nil_method = vm.intern("nil-method");
    let method = vm.intern("live-method");
    let value = vm.heap_new_string("held only by method");
    let methods = &mut vm.heap.shapes[shape as usize].methods;
    methods.insert(nil_method, Value::NIL);
    methods.insert(method, value);
    methods.insert(Value::NIL, Value::NIL);
    vm.full_cycle();
    vm.check_oracle();
    assert_eq!(vm.heap.object_count(), 3);
    let methods = &mut vm.heap.shapes[shape as usize].methods;
    assert_eq!(methods.get(&nil_method), Some(&Value::NIL));
    assert_eq!(methods.get(&Value::NIL), Some(&Value::NIL));
    assert_eq!(methods.remove(&method), Some(value));
    vm.full_cycle();
    vm.check_oracle();
    assert_eq!(vm.heap.object_count(), 1);
    vm.heap.shapes[shape as usize].methods.clear();
    vm.full_cycle();
    vm.check_oracle();
    assert_eq!(vm.heap.object_count(), 0);
}

#[test]
fn method_checkpoints_preserve_nil_presence_and_sort_independently_of_map_order() {
    let mut source = Interp::new();
    source.heap.automatic_collection = false;
    let shape = source.heap.shape("Methods", &[], &[]);
    let a = source.intern("alpha");
    let b = source.intern("beta");
    let c = source.intern("gamma");
    let value = source.heap_new_string("method-held payload");
    let pairs = [(a, Value::NIL), (b, value), (c, Value::FALSE)];
    for (key, value) in pairs {
        source.heap.shapes[shape as usize]
            .methods
            .insert(key, value);
    }
    let first = persist::save_vm(
        &mut source,
        &Policies::default(),
        &mut ResourceCodecs::new(),
    )
    .unwrap();
    source.heap.shapes[shape as usize].methods.clear();
    for (key, value) in pairs.into_iter().rev() {
        source.heap.shapes[shape as usize]
            .methods
            .insert(key, value);
    }
    let second = persist::save_vm(
        &mut source,
        &Policies::default(),
        &mut ResourceCodecs::new(),
    )
    .unwrap();
    assert_eq!(first, second);
    drop(source);
    let mut restored =
        persist::load_vm(&first, &Policies::default(), &mut ResourceCodecs::new()).unwrap();
    restored.heap.stress = true;
    restored.full_cycle();
    restored.check_oracle();
    let a = restored.intern("alpha");
    let b = restored.intern("beta");
    let c = restored.intern("gamma");
    let methods = &restored.heap.shapes[0].methods;
    assert!(methods.contains_key(&a));
    assert_eq!(methods.get(&a), Some(&Value::NIL));
    assert_eq!(methods.get(&c), Some(&Value::FALSE));
    assert_eq!(
        restored.bytes_of(*methods.get(&b).unwrap()),
        b"method-held payload"
    );
    restored.heap.shapes[0].methods.clear();
    restored.full_cycle();
    assert_eq!(restored.heap.object_count(), 0);
}
