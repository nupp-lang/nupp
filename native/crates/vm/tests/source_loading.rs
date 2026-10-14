use nupp_vm::{builtins, image, interp::Interp, value::Value};

fn put(vm: &mut Interp, object: Value, name: &str, value: Value) {
    let key = vm.intern(name);
    vm.set_index(object, key, value);
}
fn field(vm: &mut Interp, object: Value, name: &str) -> Value {
    let key = vm.intern(name);
    vm.get_index(object, key)
}
fn constant(vm: &mut Interp, value: f64) -> Value {
    let cell = vm.new_cell(Value::num(value));
    let root = vm.register(cell);
    let closure = vm.new_closure(vm.literal_fid, &[cell]);
    vm.release(root);
    closure
}

#[test]
fn preload_precedes_image_and_cleared_modules_reload() {
    let mut vm = Interp::new();
    vm.install_globals();
    vm.heap.stress_steps = true;
    vm.heap.oracle = true;
    vm.heap.quarantine = true;
    image::load(&mut vm, "function module:fixture 0 0 2 1 :v\nconst 0 num 41\nK 1 0\nRet 1\nend\nmodule fixture 0\nentry 0\n").unwrap();
    let package = vm.require("package");
    let preload = field(&mut vm, package, "preload");
    let loaded = field(&mut vm, package, "loaded");
    let first = constant(&mut vm, 42.0);
    let first_root = vm.register(first);
    put(&mut vm, preload, "fixture", first);
    assert_eq!(vm.require("fixture"), Value::num(42.0));
    let second = constant(&mut vm, 43.0);
    let second_root = vm.register(second);
    put(&mut vm, preload, "fixture", second);
    assert_eq!(vm.require("fixture"), Value::num(42.0));
    put(&mut vm, loaded, "fixture", Value::NIL);
    assert_eq!(vm.require("fixture"), Value::num(43.0));
    put(&mut vm, loaded, "fixture", Value::NIL);
    put(&mut vm, preload, "fixture", Value::NIL);
    assert_eq!(vm.require("fixture"), Value::num(41.0));
    vm.release(first_root);
    vm.release(second_root);
}

#[test]
fn cyclic_module_errors_release_scratch_tasks_and_allow_retry() {
    let mut vm = Interp::new();
    vm.install_globals();
    image::load(&mut vm, "function module:cycle 0 0 2 1 :v\nconst 0 str \"cycle\"\nRequire 1 0\nRet 1\nend\nmodule cycle 0\nentry 0\n").unwrap();
    for _ in 0..2 {
        let count = vm.tasks.len();
        let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| vm.require("cycle")));
        assert!(result.is_err());
        assert_eq!(vm.tasks.len(), count);
    }
}

#[test]
fn bounded_source_stops_loops_and_restores_the_caller() {
    for threaded in [false, true] {
        let mut vm = Interp::new();
        vm.install_globals();
        let entry =
            image::load(&mut vm, "function loop 0 0 2 1 :v\nJmp -1\nend\nentry 0\n").unwrap();
        if threaded {
            vm.prepare_threaded();
            vm.threaded = true;
        }
        let service = Value::builtin(builtins::id_of("vm.withInstructionBudget").unwrap());
        let count = vm.tasks.len();
        let result = vm.pcall_values(service, &[Value::func(entry), Value::num(100.0)]);
        assert_eq!(result[0], Value::FALSE);
        assert!(
            String::from_utf8_lossy(vm.bytes_of(result[1])).contains("instruction limit exceeded")
        );
        assert_eq!(vm.tasks.len(), count);
        let answer = constant(&mut vm, 42.0);
        assert_eq!(vm.call_value(answer, &[]), vec![Value::num(42.0)]);
    }
}

#[test]
fn loaded_chunk_and_nested_function_share_only_their_environment() {
    let mut vm = Interp::new();
    vm.install_globals();
    vm.heap.stress = true;
    vm.heap.oracle = true;
    vm.heap.quarantine = true;
    let entry = image::load(&mut vm, include_str!("isolated-chunk.bytecode")).unwrap();
    let environment = vm.new_table();
    let environment_root = vm.register(environment);
    put(&mut vm, environment, "answer", Value::num(41.0));
    let context = vm.new_table();
    let context_root = vm.register(context);
    put(&mut vm, context, "value", environment);
    let values = vm.call_value(Value::func(entry), &[context]);
    assert_eq!(values[0], Value::num(42.0));
    let function = values[1];
    let function_root = vm.register(function);
    assert_eq!(field(&mut vm, environment, "answer"), Value::num(42.0));
    assert_eq!(
        vm.call_value(function, &[]),
        vec![Value::num(42.0), Value::NIL]
    );
    let globals = vm.require("_G");
    assert_eq!(field(&mut vm, globals, "answer"), Value::NIL);
    assert_ne!(field(&mut vm, globals, "io"), Value::NIL);
    let replacement = vm.new_table();
    let replacement_root = vm.register(replacement);
    put(&mut vm, replacement, "answer", Value::num(43.0));
    put(&mut vm, context, "value", replacement);
    assert_eq!(
        vm.call_value(function, &[]),
        vec![Value::num(43.0), Value::NIL]
    );
    vm.release(replacement_root);
    vm.release(function_root);
    vm.release(context_root);
    vm.release(environment_root);
}
