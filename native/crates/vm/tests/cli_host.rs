use nupp_vm::{interp::Interp, value::Value};
use std::io::IsTerminal;

#[test]
fn cli_host_modules_are_available_before_loading_an_image() {
    let mut vm = Interp::new();
    vm.install_globals();

    let io = vm.require("io");
    let stdin = vm.intern("stdin");
    assert_ne!(vm.get_index(io, stdin), Value::NIL);

    let terminal = vm.require("nupp.cli.internal.terminalhost");
    let is_terminal = vm.intern("isTerminal");
    let is_terminal = vm.get_index(terminal, is_terminal);
    let answer = vm.call_value(is_terminal, &[Value::num(1.0)]);
    assert_eq!(answer, vec![Value::boolean(std::io::stdout().is_terminal())]);

    let clock = vm.require("nupp.tools.build.clockhost");
    let now = vm.intern("now");
    let now = vm.get_index(clock, now);
    let before = vm.call_value(now, &[])[0].as_num();
    let after = vm.call_value(now, &[])[0].as_num();
    assert!(before > 1_400_000_000_000.0 && after >= before);
}

#[test]
fn executable_entry_preserves_argv_stdout_and_status() {
    use std::process::Command;
    let nonce = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_nanos();
    let path = std::env::temp_dir().join(format!("nupp-vm-cli-{}-{nonce}.image", std::process::id()));
    let source = r#"function main 0 1 28 2 v:v
const 0 builtin assert
const 1 num 1
const 2 str "123"
const 3 num 2
const 4 str "@does-not-exist"
const 5 num 3
const 6 str "--repeat"
const 7 num 4
const 8 str "--host"
const 9 builtin io.write
const 10 str "{\034ok\034:true}\010"
const 11 num 37
const 12 str "_G"
const 13 str "arg"
K 10 0
K 2 1
GetIdx 3 1 2
K 4 2
Eq 12 3 4
CallDyn 10 11 1
K 2 3
GetIdx 3 1 2
K 4 4
Eq 12 3 4
CallDyn 10 11 1
K 2 5
GetIdx 3 1 2
K 4 6
Eq 12 3 4
CallDyn 10 11 1
K 2 7
GetIdx 3 1 2
K 4 8
Eq 12 3 4
CallDyn 10 11 1
Require 2 12
GetField 3 2 13
Eq 12 1 3
CallDyn 10 11 1
K 10 9
K 12 10
CallDyn 10 11 1
K 2 11
Ret 2
end
function module:cli 1 0 12 2 :v
const 0 func 0
const 1 str "main"
NewTableN 1 0 1
NewClosure 2 0 3 0
SetField 1 1 2
Ret 1
end
module cli 1
entry 1
"#;
    std::fs::write(&path, source).unwrap();
    for interpreted in [true, false] {
        let mut command = Command::new(env!("CARGO_BIN_EXE_nupp-vm"));
        command.args(["exec", path.to_str().unwrap(), "cli", "123", "@does-not-exist", "--repeat", "--host"]);
        if interpreted { command.env("NO_JIT", "1"); } else { command.env_remove("NO_JIT"); }
        let output = command.output().unwrap();
        assert_eq!(output.status.code(), Some(37), "{}", String::from_utf8_lossy(&output.stderr));
        assert_eq!(output.stdout, b"{\"ok\":true}\n");
        assert!(output.stderr.is_empty(), "{}", String::from_utf8_lossy(&output.stderr));
    }
    std::fs::remove_file(path).unwrap();
}

#[test]
fn compiler_writes_binary_cache_files_and_releases_handles() {
    use nupp_vm::builtins::{call, id_of};
    let nonce = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_nanos();
    let path = std::env::temp_dir().join(format!("nupp-vm-cache-{}-{nonce}", std::process::id()));
    let moved = path.with_extension("moved");
    let mut vm = Interp::new();
    vm.install_globals();
    vm.heap.stress_steps = true;
    vm.heap.oracle = true;
    let name = vm.heap_new_string(path.to_str().unwrap()); let root = vm.register(name);
    let mode = vm.intern("wb");
    let file = call(&mut vm, id_of("io.open").unwrap(), &[name, mode]).as_slice()[0];
    assert_ne!(file, Value::NIL);
    assert!(vm.resources.contains_key(&file));
    let bytes = vm.new_string_bytes(b"one\0two\n"); let bytes_root = vm.register(bytes);
    assert_eq!(call(&mut vm, id_of("file.write").unwrap(), &[file, bytes]).as_slice(), &[file]);
    assert!(nupp_vm::persist::save_graph(&mut vm, &[file], &Default::default()).is_err());
    assert_eq!(call(&mut vm, id_of("file.close").unwrap(), &[file]).as_slice(), &[Value::TRUE]);
    assert!(!vm.resources.contains_key(&file) && vm.native_files.is_empty());
    let mode = vm.intern("r+b");
    let reader = call(&mut vm, id_of("io.open").unwrap(), &[name, mode]).as_slice()[0];
    let zero = call(&mut vm, id_of("file.read").unwrap(), &[reader, Value::num(0.0)]).as_slice()[0];
    assert_eq!(vm.bytes_of(zero), b"");
    let all = vm.intern("*a");
    let contents = call(&mut vm, id_of("file.read").unwrap(), &[reader, all]).as_slice()[0];
    assert_eq!(vm.bytes_of(contents), b"one\0two\n");
    assert_eq!(call(&mut vm, id_of("file.read").unwrap(), &[reader, Value::num(0.0)]).as_slice(), &[Value::NIL]);
    assert_eq!(call(&mut vm, id_of("file.close").unwrap(), &[reader]).as_slice(), &[Value::TRUE]);
    let to = vm.heap_new_string(moved.to_str().unwrap()); let to_root = vm.register(to);
    assert_eq!(call(&mut vm, id_of("os.rename").unwrap(), &[name, to]).as_slice(), &[Value::TRUE]);
    assert_eq!(std::fs::read(&moved).unwrap(), b"one\0two\n");
    assert_eq!(call(&mut vm, id_of("os.remove").unwrap(), &[to]).as_slice(), &[Value::TRUE]);
    vm.release(to_root); vm.release(bytes_root); vm.release(root);
}

#[test]
fn compiler_hash_and_temporary_paths_are_native_services() {
    use nupp_vm::builtins::{call, id_of};
    let mut vm = Interp::new(); vm.install_globals();
    let module = vm.require("nupp.compiler.nativehash"); let key = vm.intern("digest"); let hash = vm.get_index(module, key);
    let source = vm.new_string_bytes(b"abc\0def"); let root = vm.register(source);
    let answer = vm.call_value(hash, &[source])[0];
    assert_eq!(vm.bytes_of(answer), nupp_native_platform::cache_digest(b"abc\0def"));
    let path = call(&mut vm, id_of("os.tmpname").unwrap(), &[]).as_slice()[0]; let path_root = vm.register(path);
    assert_eq!(std::fs::read(std::str::from_utf8(vm.bytes_of(path)).unwrap()).unwrap(), b"");
    assert_eq!(call(&mut vm, id_of("os.remove").unwrap(), &[path]).as_slice(), &[Value::TRUE]);
    vm.release(path_root); vm.release(root);
}

#[cfg(feature = "c-headers")]
#[test]
fn c_declaration_service_keeps_external_state_explicit() {
    let mut vm = Interp::new(); vm.install_globals();
    vm.heap.stress_steps = true; vm.heap.oracle = true;
    let module = vm.require("nupp.compiler.nativecdecl");
    let key = vm.intern("request"); let request = vm.get_index(module, key);
    let input = vm.heap_new_string(r#"{"operation":"declare","text":"int checked(int value);"}"#); let root = vm.register(input);
    let result = vm.call_value(request, &[input])[0];
    let reply: serde_json::Value = serde_json::from_slice(vm.bytes_of(result)).unwrap();
    assert_eq!(reply["ok"], true); assert_eq!(reply["value"]["checked"], true);
    assert_eq!(vm.resources[&module], "nupp.compiler.c-declarations");
    assert!(nupp_vm::persist::save_graph(&mut vm, &[module], &Default::default()).is_err());
    vm.release(root);
}
