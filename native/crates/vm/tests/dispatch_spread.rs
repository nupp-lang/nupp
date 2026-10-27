use nupp_vm::{image, interp::Interp, value::Value};

fn call(n: usize, pack: bool) -> (Box<Interp>, Value) {
    let mut vm = Box::new(Interp::new());
    let builtin = if pack { "string.char" } else { "select" };
    let (base, arity) = if pack { (5, 64) } else { (4, 65) };
    let constants = (1..=n)
        .map(|i| format!("const {} num {i}\n", i - 1))
        .collect::<String>();
    let loads = (1..=n)
        .map(|i| format!("K {i} {}\n", i - 1))
        .collect::<String>();
    let ret = match n {
        0 => "RetNil".to_string(),
        1 => "Ret 1".to_string(),
        _ => format!("RetN 1 {n}"),
    };
    let source = format!(
        r##"
function caller 0 0 32 0 :v
const 0 builtin {builtin}
const 1 str "#"
const 2 func 1
const 3 builtin type
K 20 3
Nil 22
CallDyn 20 21 1
K 20 2
CallDyn 20 6 0
K 15 0
K 5 1
CallDyn 15 {base} {arity}
Ret {base}
end
function produce 1 0 16 0 :v
{constants}{loads}{ret}
end
entry 0
"##
    );
    image::load(&mut vm, &source).unwrap();
    vm.install_globals();
    vm.entries.resize(vm.funcs.len(), 0);
    vm.prepare_threaded();
    vm.heap.stress = true;
    vm.heap.oracle = true;
    vm.heap.quarantine = true;
    let result = vm.call_value(Value::func(0), &[])[0];
    (vm, result)
}

#[test]
fn builtin_spread_uses_the_latest_fast_return_count_and_wide_tail() {
    for n in [0, 1, 3, 8, 10] {
        let (_, result) = call(n, false);
        assert_eq!(result, Value::inline_integer(n as i64).unwrap(), "result count {n}");
    }
}

#[test]
fn allocating_builtin_receives_the_full_result_pack() {
    for n in [0, 1, 3, 8, 10] {
        let (mut vm, result) = call(n, true);
        vm.register(result);
        vm.full_cycle();
        vm.check_oracle();
        assert_eq!(vm.bytes_of(result), (1..=n as u8).collect::<Vec<_>>());
    }
}
