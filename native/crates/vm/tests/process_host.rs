use nupp_vm::{
    builtins::{call, id_of},
    interp::Interp,
    value::Value,
};

fn invoke(vm: &mut Interp, name: &str, args: &[Value]) -> Vec<Value> {
    call(vm, id_of(name).unwrap(), args).to_vec()
}
fn put(vm: &mut Interp, object: Value, name: &str, value: Value) {
    let root = vm.register(value);
    let key = vm.intern(name);
    vm.set_index(object, key, value);
    vm.release(root);
}

#[test]
fn file_write_preserves_binary_views_and_reports_host_failures() {
    let mut vm = Interp::new();
    vm.install_globals();
    vm.heap.stress = true;
    vm.heap.oracle = true;
    let owner = invoke(&mut vm, "files.createTemporaryDirectory", &[])[0];
    let owner_root = vm.register(owner);
    let directory = invoke(&mut vm, "temporary.toString", &[owner])[0];
    let directory = std::path::PathBuf::from(std::str::from_utf8(vm.bytes_of(directory)).unwrap());
    let destination = directory.join("binary.dat");
    let path = vm.heap_new_string(destination.to_str().unwrap());
    let path_root = vm.register(path);
    let bytes = vm.new_string_bytes(b"before\0\xfftail");
    let bytes_root = vm.register(bytes);
    assert_eq!(invoke(&mut vm, "files.write", &[path, bytes]), vec![Value::TRUE]);
    assert_eq!(std::fs::read(&destination).unwrap(), b"before\0\xfftail");

    let getter = nupp_vm::image::load(&mut vm, r#"
function view 0 1 4 1 v:v
const 0 builtin collectgarbage
const 1 str "_bytes"
K 2 0
CallDyn 2 3 0
GetField 2 1 1
Ret 2
end
entry 0
"#).unwrap();
    let view = vm.new_table();
    let view_root = vm.register(view);
    put(&mut vm, view, "getString", Value::func(getter));
    let short = vm.new_string_bytes(b"\0\x80");
    put(&mut vm, view, "_bytes", short);
    let path_object = vm.new_table();
    let object_root = vm.register(path_object);
    put(&mut vm, path_object, "_text", path);
    assert_eq!(invoke(&mut vm, "files.write", &[path_object, view]), vec![Value::TRUE]);
    assert_eq!(std::fs::read(&destination).unwrap(), b"\0\x80", "write truncates and keeps embedded bytes");

    put(&mut vm, view, "_bytes", Value::num(42.0));
    let error = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| invoke(&mut vm, "files.write", &[path, view])));
    assert!(error.is_err());
    assert_eq!(std::fs::read(&destination).unwrap(), b"\0\x80", "invalid view must not truncate the destination");
    let missing = vm.heap_new_string(directory.join("missing/child").to_str().unwrap());
    let failure = invoke(&mut vm, "files.write", &[missing, bytes]);
    assert_eq!(failure[0], Value::FALSE);
    assert!(!vm.bytes_of(failure[1]).is_empty());
    invoke(&mut vm, "temporary.close", &[owner]);
    for root in [object_root, view_root, bytes_root, path_root, owner_root] { vm.release(root); }
}

#[test]
fn temporary_owners_persist_or_remove_their_paths() {
    let mut vm = Interp::new();
    vm.install_globals();
    vm.heap.stress = true;
    vm.heap.oracle = true;
    let options = vm.new_table();
    let root = vm.register(options);
    let prefix = vm.intern("nupp-vm-owner-");
    put(&mut vm, options, "prefix", prefix);
    let owner = invoke(&mut vm, "files.createTemporaryDirectory", &[options])[0];
    assert_ne!(owner, Value::NIL);
    let path = invoke(&mut vm, "temporary.toString", &[owner])[0];
    let path = std::path::PathBuf::from(std::str::from_utf8(vm.bytes_of(path)).unwrap());
    std::fs::write(path.join("child.txt"), b"owned\0bytes").unwrap();
    let pattern = vm.heap_new_string(&format!("{}/*.txt", path.display()));
    let pattern_root = vm.register(pattern);
    let matches = invoke(&mut vm, "files.glob", &[pattern])[0];
    let matches_root = vm.register(matches);
    assert_eq!(vm.array_len(matches), 1);
    let matched = vm.get_index(matches, Value::num(1.0));
    let text = invoke(&mut vm, "path.toString", &[matched])[0];
    assert_eq!(
        vm.bytes_of(text),
        path.join("child.txt").to_str().unwrap().as_bytes()
    );
    assert!(nupp_vm::persist::save_graph(&mut vm, &[owner], &Default::default()).is_err());
    let destination = path.with_extension("persisted");
    let destination_value = vm.heap_new_string(destination.to_str().unwrap());
    let destination_root = vm.register(destination_value);
    assert_eq!(
        invoke(&mut vm, "temporary.persist", &[owner, destination_value]),
        vec![Value::TRUE]
    );
    invoke(&mut vm, "temporary.close", &[owner]);
    assert!(destination.join("child.txt").is_file() && !path.exists());
    std::fs::remove_dir_all(destination).unwrap();
    let owner = invoke(&mut vm, "files.createTemporaryDirectory", &[options])[0];
    let path = invoke(&mut vm, "temporary.toString", &[owner])[0];
    let path = std::path::PathBuf::from(std::str::from_utf8(vm.bytes_of(path)).unwrap());
    vm.release(destination_root);
    vm.release(matches_root);
    vm.release(pattern_root);
    vm.release(root);
    drop(vm);
    assert!(
        !path.exists(),
        "VM shutdown must release unclosed temporary owners"
    );
}

#[cfg(unix)]
#[test]
fn shell_processes_preserve_binary_pipes_and_exit_status() {
    let mut vm = Interp::new();
    vm.install_globals();
    vm.heap.stress_steps = true;
    vm.heap.oracle = true;
    let command = vm.intern("printf 'one\\000two\\n'; exit 7");
    let pipe = invoke(&mut vm, "io.popen", &[command])[0];
    assert!(nupp_vm::persist::save_graph(&mut vm, &[pipe], &Default::default()).is_err());
    let empty = invoke(&mut vm, "process.pipeRead", &[pipe, Value::num(0.0)])[0];
    assert_eq!(vm.bytes_of(empty), b"");
    let all = vm.intern("*a");
    let result = invoke(&mut vm, "process.pipeRead", &[pipe, all])[0];
    assert_eq!(vm.bytes_of(result), b"one\0two\n");
    assert_eq!(
        invoke(&mut vm, "process.pipeRead", &[pipe, Value::num(0.0)]),
        vec![Value::NIL]
    );
    let result = invoke(&mut vm, "process.pipeClose", &[pipe]);
    assert_eq!(result[0], Value::NIL);
    assert_eq!(result[2], Value::num(7.0));
    assert_eq!(vm.bytes_of(result[1]), b"exit");
    assert!(!vm.resources.contains_key(&pipe));
    let command = vm.intern("exit 9");
    assert_eq!(
        invoke(&mut vm, "os.execute", &[command]),
        vec![Value::num(9.0 * 256.0)]
    );
    let command = vm.intern("printf 'first\\nsecond\\n'");
    let pipe = invoke(&mut vm, "io.popen", &[command])[0];
    let line = invoke(&mut vm, "process.pipeRead", &[pipe])[0];
    assert_eq!(vm.bytes_of(line), b"first");
    let line = invoke(&mut vm, "process.pipeRead", &[pipe])[0];
    assert_eq!(vm.bytes_of(line), b"second");
    assert_eq!(
        invoke(&mut vm, "process.pipeRead", &[pipe]),
        vec![Value::NIL]
    );
    assert_eq!(
        invoke(&mut vm, "process.pipeClose", &[pipe])[0],
        Value::TRUE
    );
}

#[cfg(unix)]
#[test]
fn provider_handles_separate_child_and_pipe_lifetimes() {
    let mut vm = Interp::new();
    vm.install_globals();
    vm.heap.stress_steps = true;
    vm.heap.oracle = true;
    let options = vm.new_table();
    let root = vm.register(options);
    let argv = vm.new_table();
    let argv_root = vm.register(argv);
    for (index, text) in [
        "/bin/sh",
        "-c",
        "printf '%s' \"$VM_PROCESS_TEST\"; printf err >&2; exit 3",
    ]
    .iter()
    .enumerate()
    {
        let text = vm.intern(text);
        vm.set_index(argv, Value::num((index + 1) as f64), text);
    }
    put(&mut vm, options, "args", argv);
    let env = vm.new_table();
    let env_root = vm.register(env);
    let value = vm.intern("environment reached child");
    put(&mut vm, env, "VM_PROCESS_TEST", value);
    put(&mut vm, options, "env", env);
    put(&mut vm, options, "clearEnv", Value::TRUE);
    let spawned = invoke(&mut vm, "process.spawn", &[options]);
    assert_ne!(spawned[0], Value::NIL);
    invoke(&mut vm, "process.closeStream", &[spawned[1]]);
    let mut outputs = [Vec::new(), Vec::new()];
    for (index, handle) in spawned[2..4].iter().enumerate() {
        loop {
            let value = invoke(&mut vm, "process.read", &[*handle, Value::num(4096.0)])[0];
            if value == Value::NIL {
                break;
            }
            outputs[index].extend_from_slice(vm.bytes_of(value));
            if vm.bytes_of(value).is_empty() {
                std::thread::sleep(std::time::Duration::from_millis(1));
            }
        }
        invoke(&mut vm, "process.closeStream", &[*handle]);
        invoke(&mut vm, "process.closeStream", &[*handle]);
    }
    assert_eq!(outputs[0], b"environment reached child");
    assert_eq!(outputs[1], b"err");
    loop {
        let result = invoke(&mut vm, "process.poll", &[spawned[0]]);
        if result[0] != Value::NIL {
            assert_eq!(result, vec![Value::num(3.0), Value::FALSE]);
            break;
        }
        std::thread::yield_now();
    }
    assert_eq!(
        invoke(&mut vm, "process.reap", &[spawned[0]]),
        vec![Value::TRUE]
    );
    assert_eq!(
        invoke(&mut vm, "process.reap", &[spawned[0]]),
        vec![Value::TRUE]
    );
    assert!(vm.resources.is_empty());
    vm.release(env_root);
    vm.release(argv_root);
    vm.release(root);
}
