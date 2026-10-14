use nupp_vm::{
    builtins::{call, id_of, iter_next},
    heap::SlotTy,
    interp::Interp,
    value::Value,
};

#[test]
fn string_capture_results_survive_later_capture_allocations() {
    for operation in ["string.find", "string.match", "string.gmatch"] {
        let mut vm = Interp::new();
        vm.heap.stress = true;
        vm.heap.oracle = true;
        vm.heap.quarantine = true;
        let subject = vm.intern("first-capture/second-capture");
        vm.register(subject);
        let pattern = vm.intern("(.*)/(.*)");
        vm.register(pattern);
        let mut values = call(&mut vm, id_of(operation).unwrap(), &[subject, pattern]);
        if operation == "string.gmatch" {
            let iterator = values[0];
            vm.register(iterator);
            values = iter_next(&mut vm, iterator);
        }
        let offset = if operation == "string.find" { 2 } else { 0 };
        for value in values.iter() {
            vm.register(*value);
        }
        vm.new_table();
        assert_eq!(vm.bytes_of(values[offset]), b"first-capture");
        assert_eq!(vm.bytes_of(values[offset + 1]), b"second-capture");
    }
}
#[test]
fn record_table_iteration_omits_absent_and_deleted_values() {
    let mut vm = Interp::new();
    vm.install_globals();
    let present = vm.intern("present");
    let absent = vm.intern("absent");
    let shape = vm
        .heap
        .shape("Probe", &[present, absent], &[SlotTy::Any, SlotTy::Any]);
    let record = vm.new_record(shape);
    let root = vm.register(record);
    vm.set_index(record, present, Value::TRUE);
    vm.set_index(record, Value::num(1.0), Value::TRUE);
    vm.set_index(record, Value::num(2.0), Value::TRUE);
    vm.set_index(record, Value::num(3.0), Value::FALSE);
    vm.set_index(record, Value::num(2.0), Value::NIL);
    let keys = vm.table_keys(record);
    assert_eq!(keys.len(), 3);
    assert!(!keys.contains(&absent));
    assert!(!keys.contains(&Value::num(2.0)));
    let iterator = call(&mut vm, id_of("pairs").unwrap(), &[record])[0];
    let iterator_root = vm.register(iterator);
    vm.set_index(record, present, Value::NIL);
    assert_eq!(
        iter_next(&mut vm, iterator).as_slice(),
        &[Value::num(1.0), Value::TRUE]
    );
    assert_eq!(
        iter_next(&mut vm, iterator).as_slice(),
        &[Value::num(3.0), Value::FALSE]
    );
    assert_eq!(iter_next(&mut vm, iterator).as_slice(), &[Value::NIL]);
    vm.release(iterator_root);
    vm.release(root);
}

const META_PROGRAM: &str = r#"
shape 0 struct:answer answer:any
shape 1 MethodOwner other:any
function readslot 0 1 4 1 v:v
GetSlot 2 1 0 0
Ret 2
end
function readfield 1 1 4 1 v:v
const 0 str "answer"
GetField 2 1 0
Ret 2
end
function writeslot 2 2 4 1 vv:v
SetSlot 1 0 2 0
Ret 1
end
entry 0
"#;

#[test]
fn sparse_numeric_keys_move_into_the_array_once() {
    let mut vm = Interp::new();
    vm.install_globals();
    vm.heap.stress = true;
    vm.heap.oracle = true;
    vm.heap.quarantine = true;
    let table = vm.new_table();
    vm.register(table);
    for key in [0, 3, 6, 9, 12, 15, 18, 21, 24, 27, 30, 33, 36, 39] {
        vm.set_index(table, Value::num(key as f64), Value::TRUE);
    }
    for key in 0..32 {
        vm.set_index(table, Value::num(key as f64), Value::TRUE);
    }
    assert_eq!(vm.table_keys(table).len(), 35);
    assert_eq!(vm.array_len(table), 31);
    vm.push_array(table, Value::num(42.0));
    assert_eq!(vm.array_len(table), 33);
    assert_eq!(vm.get_index(table, Value::num(32.0)), Value::num(42.0));
    vm.set_index(table, Value::num(33.0), Value::NIL);
    assert_eq!(vm.array_len(table), 32);
    assert_eq!(vm.get_index(table, Value::num(33.0)), Value::NIL);
    assert_eq!(vm.table_keys(table).len(), 35);
    vm.full_cycle();
    vm.check_oracle();
}

#[test]
fn record_methods_are_values_but_are_not_raw_instance_fields() {
    use nupp_vm::image;
    let program = META_PROGRAM.replace("answer:any", "other:any");
    for threaded in [false, true] {
        let mut vm = Interp::new();
        image::load(&mut vm, &program).unwrap();
        vm.install_globals();
        if threaded {
            vm.prepare_threaded();
        }
        let name = vm.intern("answer");
        let method = Value::builtin(id_of("assert").unwrap());
        vm.heap.shapes[0].methods.insert(name, method);
        let object = vm.new_record(0);
        vm.register(object);
        assert_eq!(vm.get_index(object, name), Value::NIL);
        assert_eq!(vm.index(object, name), method);
        assert_eq!(vm.call_value(Value::func(1), &[object]), vec![method]);
        vm.set_index(object, name, Value::FALSE);
        assert_eq!(vm.call_value(Value::func(1), &[object]), vec![Value::FALSE]);
        vm.set_index(object, name, Value::NIL);
        assert_eq!(vm.call_value(Value::func(1), &[object]), vec![method]);
    }
}

#[test]
fn long_named_fields_agree_with_dynamic_lookup_across_functions() {
    use nupp_vm::{
        image,
        persist::{self, Policies},
    };
    let name = "a_field_name_longer_than_the_short_string_interning_threshold";
    let program = format!(
        r#"
shape 0 LongField {name}:any
shape 1 ExtraField other:any
function write 0 2 4 1 vv:v
const 0 str "{name}"
SetField 1 0 2
Ret 1
end
function read 1 1 4 1 v:v
const 0 str "{name}"
GetField 2 1 0
Ret 2
end
function dynamic 2 2 4 1 vv:v
GetIdx 3 1 2
Ret 3
end
entry 0
"#
    );
    for threaded in [false, true] {
        let mut vm = Interp::new();
        image::load(&mut vm, &program).unwrap();
        if threaded {
            vm.prepare_threaded();
        }
        vm.heap.stress_steps = true;
        vm.heap.oracle = true;
        vm.heap.quarantine = true;
        for shape in [None, Some(0), Some(1)] {
            let object = match shape {
                Some(id) => vm.new_record(id),
                None => vm.new_table(),
            };
            vm.register(object);
            vm.call_value(Value::func(0), &[object, Value::num(42.0)]);
            vm.full_cycle();
            let data = persist::save_graph(&mut vm, &[object], &Policies::default()).unwrap();
            let restored =
                persist::load_graph(&mut vm, &data, &Policies::default(), None).unwrap()[0];
            vm.register(restored);
            for value in [object, restored] {
                assert_eq!(
                    vm.call_value(Value::func(1), &[value]),
                    vec![Value::num(42.0)]
                );
                let key = vm.string_of(name.as_bytes());
                vm.register(key);
                assert_eq!(
                    vm.call_value(Value::func(2), &[value, key]),
                    vec![Value::num(42.0)]
                );
            }
            vm.full_cycle();
            vm.check_oracle();
        }
    }
}

#[test]
fn shaped_table_metatables_survive_gc_and_persistence() {
    use nupp_vm::{
        image,
        persist::{self, Policies},
    };
    for threaded in [false, true] {
        let mut vm = Interp::new();
        image::load(&mut vm, META_PROGRAM).unwrap();
        vm.install_globals();
        if threaded {
            vm.prepare_threaded();
        }
        vm.heap.stress_steps = true;
        vm.heap.oracle = true;
        vm.heap.quarantine = true;
        let value = vm.new_record(0);
        vm.register(value);
        let parent = vm.new_record(0);
        vm.register(parent);
        let meta = vm.new_table();
        vm.register(meta);
        let answer = vm.intern("answer");
        vm.set_index(parent, answer, Value::num(42.0));
        let index = vm.intern("__index");
        vm.set_index(meta, index, parent);
        let newindex = vm.intern("__newindex");
        vm.set_index(meta, newindex, parent);
        vm.set_metatable(value, meta);
        vm.full_cycle();
        vm.check_oracle();
        for fid in [0, 1] {
            assert_eq!(
                vm.call_value(Value::func(fid), &[value]),
                vec![Value::num(42.0)]
            );
        }
        vm.call_value(Value::func(2), &[value, Value::num(43.0)]);
        assert_eq!(vm.get_index(value, answer), Value::NIL);
        assert_eq!(vm.get_index(parent, answer), Value::num(43.0));
        let data = persist::save_graph(&mut vm, &[value], &Policies::default()).unwrap();
        let restored = persist::load_graph(&mut vm, &data, &Policies::default(), None).unwrap()[0];
        vm.register(restored);
        for fid in [0, 1] {
            assert_eq!(
                vm.call_value(Value::func(fid), &[restored]),
                vec![Value::num(43.0)]
            );
        }
        vm.set_metatable(value, Value::NIL);
        vm.call_value(Value::func(2), &[value, Value::num(44.0)]);
        assert_eq!(vm.get_index(value, answer), Value::num(44.0));
        vm.full_cycle();
        vm.check_oracle();
    }
}

#[cfg(feature = "jit")]
#[test]
fn compiled_slot_guards_and_field_caches_observe_metatable_changes() {
    use nupp_vm::{compiled, image, jit::Jit};
    use std::sync::atomic::Ordering;
    let mut vm = Box::new(Interp::new());
    image::load(&mut vm, META_PROGRAM).unwrap();
    vm.install_globals();
    vm.entries.resize(vm.funcs.len(), 0);
    let mut jit = Jit::new();
    jit.extra_addr = &vm.extra as *const _ as i64;
    jit.last_nres_addr = &vm.last_nres as *const _ as i64;
    jit.entries_addr = vm.entries.as_ptr() as i64;
    jit.callee_info = vm.funcs.iter().map(|f| (f.nparams, true)).collect();
    vm.calltab = jit
        .callee_info
        .iter()
        .map(|&(n, _)| n as u64 | 256)
        .collect();
    jit.calltab_addr = vm.calltab.as_ptr() as i64;
    vm.shape_probe = vm
        .heap
        .shapes
        .iter()
        .map(|s| (s.table.as_ptr() as u64, s.mask))
        .collect();
    jit.probe_addr = vm.shape_probe.as_ptr() as i64;
    compiled::CTX.store(&mut *vm, Ordering::Relaxed);
    for (id, function) in vm.funcs.iter().enumerate() {
        vm.entries[id] = jit.try_compile(function, id as u32).unwrap() as u64;
    }
    let object = vm.new_record(0);
    vm.register(object);
    let parent = vm.new_record(0);
    vm.register(parent);
    let meta = vm.new_table();
    vm.register(meta);
    let answer = vm.intern("answer");
    vm.set_index(object, answer, Value::num(1.0));
    vm.set_index(parent, answer, Value::num(42.0));
    let index = vm.intern("__index");
    vm.set_index(meta, index, parent);
    let newindex = vm.intern("__newindex");
    vm.set_index(meta, newindex, parent);
    for fid in [0, 1] {
        assert_eq!(
            vm.call_outs(Value::func(fid), &[object]).as_slice(),
            &[Value::num(1.0)]
        );
    }
    vm.set_index(object, answer, Value::NIL);
    vm.set_metatable(object, meta);
    for fid in [0, 1] {
        assert_eq!(
            vm.call_outs(Value::func(fid), &[object]).as_slice(),
            &[Value::num(42.0)]
        );
    }
    vm.call_outs(Value::func(2), &[object, Value::num(43.0)]);
    assert_eq!(vm.get_index(object, answer), Value::NIL);
    assert_eq!(vm.get_index(parent, answer), Value::num(43.0));
    vm.set_metatable(object, Value::NIL);
    for fid in [0, 1] {
        assert_eq!(
            vm.call_outs(Value::func(fid), &[object]).as_slice(),
            &[Value::NIL]
        );
    }
    let method = Value::builtin(id_of("assert").unwrap());
    vm.heap.shapes[1].methods.insert(answer, method);
    let owner = vm.new_record(1);
    vm.register(owner);
    for override_value in [None, Some(Value::FALSE), Some(Value::NIL)] {
        if let Some(value) = override_value {
            vm.set_index(owner, answer, value);
        }
        assert_eq!(
            vm.call_outs(Value::func(1), &[owner]).as_slice(),
            &[if override_value == Some(Value::FALSE) {
                Value::FALSE
            } else {
                method
            }]
        );
    }
    compiled::CTX.store(std::ptr::null_mut(), Ordering::Relaxed);
}
