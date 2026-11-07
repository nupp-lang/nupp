use nupp_vm::{image, interp::Interp, value::Value};

fn vm(source: &str) -> Box<Interp> {
    let mut vm = Box::new(Interp::new());
    image::load(&mut vm, source).unwrap();
    vm.install_globals();
    vm.entries.resize(vm.funcs.len(), 0);
    vm.prepare_threaded();
    vm.heap.oracle = true;
    vm.heap.quarantine = true;
    vm
}

#[test]
fn fusion_keeps_the_second_instruction_as_a_valid_branch_target() {
    let mut vm = vm(r#"
function choose 0 1 8 3 v:v
const 0 num 7
const 1 num 9
FK 0 2
FK 1 3
IK 2 0
JmpIf 1 1
FCmpLe 2 0 1
JmpIfIZero 2 2
K 3 1
Ret 3
K 3 0
Ret 3
end
entry 0
"#);
    for threaded in [true, false] {
        vm.threaded = threaded;
        assert_eq!(
            vm.call_value(Value::func(0), &[Value::FALSE]),
            vec![Value::num(9.0)]
        );
        assert_eq!(
            vm.call_value(Value::func(0), &[Value::TRUE]),
            vec![Value::num(7.0)]
        );
    }
}

#[test]
fn field_cache_rechecks_shape_and_resolves_empty_slots_after_collection() {
    let mut vm = vm(r#"
shape 0 A x:any y:any
shape 1 B y:any x:any
function read 0 1 8 0 v:v
const 0 str "x"
GetField 2 1 0
Ret 2
end
function index 1 2 8 0 vv:v
const 0 num 99
K 3 0
Ret 3
end
entry 0
"#);
    let a = vm.new_record(0);
    vm.register(a);
    let b = vm.new_record(1);
    vm.register(b);
    let x = vm.intern("x");
    vm.set_index(a, x, Value::FALSE);
    vm.set_index(b, x, Value::TRUE);
    for t in [a, b, a, b] {
        let wanted = if t == a { Value::FALSE } else { Value::TRUE };
        assert_eq!(vm.call_value(Value::func(0), &[t]), vec![wanted]);
        vm.full_cycle();
        vm.check_oracle();
    }
    let meta = vm.new_table();
    vm.register(meta);
    let index = vm.intern("__index");
    vm.set_index(meta, index, Value::func(1));
    vm.set_metatable(a, meta);
    vm.set_index(a, x, Value::NIL);
    assert_eq!(vm.call_value(Value::func(0), &[a]), vec![Value::num(99.0)]);
    vm.full_cycle();
    vm.check_oracle();
    vm.set_index(a, x, Value::num(42.0));
    assert_eq!(vm.call_value(Value::func(0), &[a]), vec![Value::num(42.0)]);
}

const RECORD_METHODS: &str = include_str!("record-method-overrides.image");

#[test]
fn record_method_overrides_match_property_reads() {
    for threaded in [false, true] {
        let mut vm = vm(RECORD_METHODS);
        vm.threaded = threaded;
        vm.call_value(Value::func(4), &[]);
        let name = vm.intern("action");
        for shape in [0, 1] {
            let receiver = vm.new_record(shape);
            vm.register(receiver);
            let other = vm.new_record(shape);
            vm.register(other);
            assert_eq!(
                vm.call_value(Value::func(0), &[receiver]),
                vec![Value::num(1.0)]
            );
            for (method, expected) in [
                (Value::func(2), 2.0),
                (Value::func(3), 3.0),
                (Value::NIL, 1.0),
            ] {
                vm.set_index(receiver, name, method);
                let expected_method = if method == Value::NIL {
                    Value::func(1)
                } else {
                    method
                };
                assert_eq!(
                    vm.call_value(Value::func(5), &[receiver]),
                    vec![expected_method]
                );
                assert_eq!(vm.resolve_method(receiver, name), expected_method);
                assert_eq!(
                    vm.call_value(Value::func(0), &[receiver]),
                    vec![Value::num(expected)]
                );
                assert_eq!(
                    vm.call_value(Value::func(0), &[other]),
                    vec![Value::num(1.0)]
                );
                vm.full_cycle();
                vm.check_oracle();
            }
            for value in [Value::FALSE, Value::num(9.0)] {
                vm.set_index(receiver, name, value);
                assert_eq!(vm.call_value(Value::func(5), &[receiver]), vec![value]);
                assert_eq!(vm.resolve_method(receiver, name), value);
                let result = vm.pcall_values(Value::func(0), &[receiver]);
                assert_eq!(result[0], Value::FALSE);
                let error = String::from_utf8_lossy(vm.bytes_of(result[1]));
                assert!(error.contains("method 'action'"), "{error}");
            }
        }
    }
}

#[test]
fn record_method_lookup_keeps_own_index_and_missing_method_context() {
    for threaded in [false, true] {
        let mut vm = vm(RECORD_METHODS);
        vm.threaded = threaded;
        let receiver = vm.new_record(2);
        vm.register(receiver);
        let prototype = vm.new_table();
        vm.register(prototype);
        let meta = vm.new_table();
        vm.register(meta);
        let name = vm.intern("action");
        let index = vm.intern("__index");
        vm.set_index(prototype, name, Value::func(2));
        vm.set_index(meta, index, prototype);
        vm.set_metatable(receiver, meta);
        assert_eq!(
            vm.call_value(Value::func(0), &[receiver]),
            vec![Value::num(2.0)]
        );
        vm.set_index(receiver, name, Value::func(3));
        assert_eq!(
            vm.call_value(Value::func(0), &[receiver]),
            vec![Value::num(3.0)]
        );
        vm.set_index(receiver, name, Value::NIL);
        assert_eq!(
            vm.call_value(Value::func(0), &[receiver]),
            vec![Value::num(2.0)]
        );
        vm.set_index(prototype, name, Value::NIL);
        let result = vm.pcall_values(Value::func(0), &[receiver]);
        assert_eq!(result[0], Value::FALSE);
        let error = String::from_utf8_lossy(vm.bytes_of(result[1]));
        assert!(error.contains("method 'action'"), "{error}");
    }
}
