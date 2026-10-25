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
