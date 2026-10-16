//! The native-library loader and C callbacks, against `ffi/loader.c` built
//! independently with the system C compiler. Every foreign call goes through
//! a Nupp function, so callbacks run from interpreted, threaded, compiled and
//! compiled-frame callers alike; the collector runs in stress mode with the
//! root oracle and quarantine throughout.
#![cfg(all(feature = "native-ffi", unix))]

use nupp_vm::{builtins, image, interp::Interp, scheduler::Status, value::Value};
use std::{
    path::{Path, PathBuf},
    process::Command,
};

/// The fixture built into `<temporary>/build/lib`, as a C dependency's library
/// is, so `@lib/...` resolves from a module under `<temporary>/build`.
struct Fixture {
    root: PathBuf,
    library: PathBuf,
}
impl Fixture {
    fn build() -> Self {
        static NEXT: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);
        let sequence = NEXT.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
        let nonce = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let root = std::env::temp_dir().join(format!(
            "nupp-loader-{}-{nonce}-{sequence}",
            std::process::id()
        ));
        let lib = root.join("build/lib");
        std::fs::create_dir_all(&lib).unwrap();
        std::fs::create_dir_all(root.join("build/generated")).unwrap();
        let library = lib.join(if cfg!(target_os = "macos") {
            "libloader.dylib"
        } else {
            "libloader.so"
        });
        let source = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/ffi/loader.c");
        let compiler = std::env::var("CC").unwrap_or_else(|_| "cc".into());
        let mut command = Command::new(&compiler);
        command.args(["-std=c11", "-O2"]);
        if cfg!(target_os = "macos") {
            command.arg("-dynamiclib");
        } else {
            command.args(["-shared", "-fPIC", "-pthread"]);
        }
        let output = command
            .arg(&source)
            .arg("-o")
            .arg(&library)
            .output()
            .expect("an independent C compiler is required for native loader acceptance");
        assert!(
            output.status.success(),
            "{}",
            String::from_utf8_lossy(&output.stderr)
        );
        Self { root, library }
    }
    fn path(&self) -> &str {
        self.library.to_str().unwrap()
    }
}
impl Drop for Fixture {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.root);
    }
}

const PROGRAM: &str = r#"
function through0 0 1 12 1 v:v
CallDyn 1 2 0
Ret 2
end
function through1 1 2 12 1 vv:v
Move 4 2
CallDyn 1 3 1
Ret 3
end
function through2 2 3 12 1 vvv:v
Move 5 2
Move 6 3
CallDyn 1 4 2
Ret 4
end
function through3 3 4 12 1 vvvv:v
Move 6 2
Move 7 3
Move 8 4
CallDyn 1 5 3
Ret 5
end
function add 4 2 6 1 vv:v
Add 3 1 2
Ret 3
end
function sub 5 2 6 1 vv:v
Sub 3 1 2
Ret 3
end
function reenter 6 2 12 1 vv:v
const 0 str "_G"
const 1 str "twice"
const 2 builtin collectgarbage
Require 3 0
GetField 4 3 1
Add 6 1 2
CallDyn 4 5 1
K 7 2
CallDyn 7 8 0
NewTable 9
Ret 5
end
function fail 7 2 8 1 vv:v
const 0 builtin error
const 1 str "callback failure"
K 3 0
K 5 1
CallDyn 3 4 1
RetNil
end
function halve 8 1 6 1 v:v
const 0 num 0.5
K 2 0
Mul 3 1 2
Ret 3
end
function contextual 9 2 12 1 vv:v
const 0 str "_G"
const 1 str "read"
const 2 str "leaked"
Require 3 0
GetField 4 3 1
Move 6 1
CallDyn 4 5 1
SetField 3 2 1
Add 7 5 2
Ret 7
end
function produce 10 1 8 1 v:v
const 0 str "_G"
const 1 str "context"
Require 2 0
GetField 3 2 1
Ret 3
end
function produceManaged 11 1 6 1 v:v
NewTable 2
Ret 2
end
function bindAt 12 3 12 1 vvv:v
const 0 builtin foreign.bind
source nupp.tests.generated
K 4 0
Move 6 1
Move 7 2
Move 8 3
CallDyn 4 5 3
Ret 5
end
module nupp.tests.generated 12 MODULE_PATH
entry 0
"#;

#[derive(Clone, Copy, Debug)]
enum Mode {
    Rust,
    Threaded,
    Typed,
    Frame,
}

fn machine(mode: Mode, module_path: &Path) -> Box<Interp> {
    let mut vm = Box::new(Interp::new());
    let program = PROGRAM.replace("MODULE_PATH", module_path.to_str().unwrap());
    image::load(&mut vm, &program).unwrap();
    vm.install_globals();
    if matches!(mode, Mode::Threaded) {
        vm.prepare_threaded();
    }
    if matches!(mode, Mode::Typed | Mode::Frame) {
        use nupp_vm::{compiled, jit::Jit};
        vm.entries.resize(vm.funcs.len(), 0);
        let mut jit = Jit::new();
        jit.extra_addr = vm.extra.as_ptr() as i64;
        jit.last_nres_addr = &vm.last_nres as *const _ as i64;
        jit.entries_addr = vm.entries.as_ptr() as i64;
        compiled::CTX.store(&mut *vm, std::sync::atomic::Ordering::Relaxed);
        if matches!(mode, Mode::Typed) {
            // The callers and the plain callbacks must compile; the rest may stay interpreted.
            for id in 0..vm.funcs.len() {
                let entry = jit.try_compile(&vm.funcs[id], id as u32);
                if id <= 5 {
                    assert!(entry.is_ok(), "function {id} did not compile: {entry:?}");
                }
                if let Ok(entry) = entry {
                    vm.entries[id] = entry as u64;
                }
            }
        } else {
            vm.enable_scheduler().unwrap();
        }
        vm.jit = Some(Box::new(jit));
    }
    vm.heap.stress = true;
    vm.heap.stress_steps = true;
    vm.heap.oracle = true;
    vm.heap.quarantine = true;
    vm
}

fn builtin(vm: &mut Interp, name: &str, args: &[Value]) -> Vec<Value> {
    vm.call_value(Value::builtin(builtins::id_of(name).unwrap()), args)
}
fn string(vm: &mut Interp, value: &str) -> Value {
    let value = vm.string_of(value.as_bytes());
    vm.register(value);
    value
}
fn set(vm: &mut Interp, object: Value, key: &str, value: Value) {
    let key = vm.intern(key);
    vm.set_index(object, key, value);
}
fn global(vm: &mut Interp, key: &str, value: Value) {
    let globals = vm.require("_G");
    set(vm, globals, key, value);
}
fn list(vm: &mut Interp, items: &[Value]) -> Value {
    let list = vm.new_table();
    vm.register(list);
    for &item in items {
        vm.push_array(list, item);
    }
    list
}
/// `{kind = "callback", params = ..., result = ...}`, as the lowering writes
/// a C function-pointer parameter.
fn callback_type(vm: &mut Interp, params: &[&str], result: &str) -> Value {
    let kinds: Vec<Value> = params.iter().map(|kind| string(vm, kind)).collect();
    let params = list(vm, &kinds);
    let result = string(vm, result);
    let kind = string(vm, "callback");
    let signature = vm.new_table();
    vm.register(signature);
    set(vm, signature, "kind", kind);
    set(vm, signature, "params", params);
    set(vm, signature, "result", result);
    signature
}
fn signature(vm: &mut Interp, result: &str, params: &[Value]) -> Value {
    let params = list(vm, params);
    let result = string(vm, result);
    let signature = vm.new_table();
    vm.register(signature);
    set(vm, signature, "result", result);
    set(vm, signature, "params", params);
    signature
}
fn bind(vm: &mut Interp, library: Value, symbol: &str, result: &str, params: &[Value]) -> Value {
    let symbol = string(vm, symbol);
    let signature = signature(vm, result, params);
    let function = builtin(vm, "foreign.bind", &[library, symbol, signature])[0];
    vm.register(function);
    function
}
fn kinds(vm: &mut Interp, names: &[&str]) -> Vec<Value> {
    names.iter().map(|name| string(vm, name)).collect()
}

/// Calls `function` with `args` through the image's `through<n>`, so the
/// foreign call is made from the mode's own tier.
#[track_caller]
fn through(vm: &mut Interp, mode: Mode, function: Value, args: &[Value]) -> Result<Value, String> {
    let mut all = vec![function];
    all.extend_from_slice(args);
    let fid = args.len() as u32;
    if matches!(mode, Mode::Frame) {
        let task = vm.schedule(Value::func(fid), &all, None).unwrap();
        let events = vm.run_ready(1).unwrap();
        return match &events[0].status {
            Status::Completed => Ok(vm.tasks[task.index].result),
            Status::Failed(error) => Err(error.clone()),
            status => panic!("unexpected {status:?}"),
        };
    }
    let roots = vm.handles.len();
    let result = vm.guarded(|vm| {
        let values = vm.call_value(Value::func(fid), &all);
        values.first().copied().unwrap_or(Value::NIL)
    });
    // Compiled code that calls a callable table which raises leaves the call's
    // arguments on the handle stack (any raising `__call`, not only a foreign
    // one), so the compiled tier is held to this only when the call succeeds.
    if result != Value::ERROR || !matches!(mode, Mode::Typed) {
        assert_eq!(
            vm.handles.len(),
            roots,
            "a foreign call leaked temporary roots in {mode:?}"
        );
    }
    vm.handles.truncate(roots);
    if result == Value::ERROR {
        let error = vm.pending_error.take().unwrap();
        Err(String::from_utf8_lossy(vm.bytes_of(error)).into_owned())
    } else {
        Ok(result)
    }
}
fn number(value: Value) -> f64 {
    assert!(value.is_num(), "expected a number, found {value:?}");
    value.as_num()
}
/// A `uint64` result's bits, boxed or, when it fits, a plain number.
fn bits(value: Value) -> u64 {
    nupp_vm::numeric::integer(value)
        .map(|exact| exact.bits)
        .unwrap_or_else(|| number(value) as u64)
}
fn refused(result: Result<Value, String>, expected: &str) {
    match result {
        Err(message) => assert!(
            message.contains(expected),
            "expected an error containing {expected:?}, got {message:?}"
        ),
        Ok(value) => panic!("expected an error containing {expected:?}, got {value:?}"),
    }
}
fn message(vm: &mut Interp, body: impl FnOnce(&mut Interp)) -> String {
    let roots = vm.handles.len();
    let payload = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| body(vm)))
        .expect_err("the operation should have been refused");
    assert_eq!(
        vm.handles.len(),
        roots,
        "a refused operation leaked temporary roots"
    );
    if let Some(text) = payload.downcast_ref::<String>() {
        return text.clone();
    }
    let error = vm.error_value(payload);
    String::from_utf8_lossy(vm.bytes_of(error)).into_owned()
}

#[test]
fn loader_resolves_names_paths_and_module_relative_libraries_and_anchors_them() {
    let fixture = Fixture::build();
    let mut vm = machine(
        Mode::Rust,
        &fixture.root.join("build/generated/binding.nupp"),
    );
    let int32 = kinds(&mut vm, &["int32", "int32"]);

    // An explicit path, through a library object.
    let path = string(&mut vm, fixture.path());
    let library = builtin(&mut vm, "foreign.load", &[path])[0];
    vm.register(library);
    let add = bind(&mut vm, library, "loader_add", "int32", &int32);
    assert_eq!(
        number(
            through(
                &mut vm,
                Mode::Rust,
                add,
                &[Value::num(19.0), Value::num(23.0)]
            )
            .unwrap()
        ),
        42.0
    );

    // A missing symbol and a missing library name what was asked for.
    let problem = message(&mut vm, |vm| {
        bind(vm, library, "loader_missing", "int32", &[]);
    });
    assert!(
        problem.contains("native symbol \"loader_missing\" is not in native library")
            && problem.contains(fixture.path()),
        "{problem}"
    );
    let missing = string(&mut vm, "nupp_loader_missing");
    let problem = message(&mut vm, |vm| {
        builtin(vm, "foreign.load", &[missing]);
    });
    let expected = if cfg!(target_os = "macos") {
        "cannot load native library \"nupp_loader_missing\" (as libnupp_loader_missing.dylib)"
    } else {
        "cannot load native library \"nupp_loader_missing\" (as libnupp_loader_missing.so)"
    };
    assert!(problem.contains(expected), "{problem}");
    let options = vm.new_table();
    vm.register(options);
    set(&mut vm, options, "global", Value::TRUE);
    let global = builtin(&mut vm, "foreign.load", &[path, options])[0];
    vm.register(global);
    let twice = bind(&mut vm, global, "loader_twice", "int32", &int32[..1]);
    assert_eq!(
        number(through(&mut vm, Mode::Rust, twice, &[Value::num(21.0)]).unwrap()),
        42.0
    );

    // A canonical name: the platform's prefix and extension, found by the platform loader.
    #[cfg(target_os = "macos")]
    {
        let system = string(&mut vm, "System");
        let system = builtin(&mut vm, "foreign.load", &[system])[0];
        vm.register(system);
        let abs = bind(&mut vm, system, "abs", "int32", &int32[..1]);
        assert_eq!(
            number(through(&mut vm, Mode::Rust, abs, &[Value::num(-42.0)]).unwrap()),
            42.0
        );
        builtin(&mut vm, "foreign.close", &[abs]);
        builtin(&mut vm, "foreign.close", &[system]);
    }

    // `@lib/...` resolves at or above the calling module's directory, the way a
    // generated binding under build/ reaches the library built beside it.
    let relative = string(
        &mut vm,
        if cfg!(target_os = "macos") {
            "@lib/libloader.dylib"
        } else {
            "@lib/libloader.so"
        },
    );
    let symbol = string(&mut vm, "loader_add");
    let add_signature = signature(&mut vm, "int32", &int32);
    let relative_add = vm.call_value(Value::func(12), &[relative, symbol, add_signature])[0];
    vm.register(relative_add);
    assert_eq!(
        number(
            through(
                &mut vm,
                Mode::Rust,
                relative_add,
                &[Value::num(40.0), Value::num(2.0)]
            )
            .unwrap()
        ),
        42.0
    );
    let absent = string(&mut vm, "@lib/libnupp-absent.dylib");
    let problem = through(
        &mut vm,
        Mode::Rust,
        Value::func(12),
        &[absent, symbol, add_signature],
    );
    let generated = fixture.root.join("build/generated");
    refused(
        problem,
        &format!(
            "cannot find native library lib/libnupp-absent.dylib at or above {}",
            generated.display()
        ),
    );

    // Bytes at an address C returned, to the terminator or of a given length.
    let text = bind(&mut vm, library, "loader_text", "pointer", &[]);
    let pointer = through(&mut vm, Mode::Rust, text, &[]).unwrap();
    vm.register(pointer);
    let read = builtin(&mut vm, "foreign.string", &[pointer])[0];
    assert_eq!(vm.bytes_of(read), b"nupp");
    let read = builtin(&mut vm, "foreign.string", &[pointer, Value::num(11.0)])[0];
    assert_eq!(vm.bytes_of(read), b"nupp\0loader");
    builtin(&mut vm, "foreign.close", &[pointer]);
    let problem = message(&mut vm, |vm| {
        builtin(vm, "foreign.string", &[pointer]);
    });
    assert!(
        problem.contains("foreign.string expects an open foreign pointer"),
        "{problem}"
    );
    builtin(&mut vm, "foreign.close", &[text]);

    // A C function pointer a call returns is callable under its declared signature.
    let binary = callback_type(&mut vm, &["int32", "int32"], "int32");
    let adder = bind(&mut vm, library, "loader_adder", "pointer", &[]);
    builtin(&mut vm, "foreign.close", &[adder]);
    let symbol = string(&mut vm, "loader_adder");
    let returns_function = vm.new_table();
    vm.register(returns_function);
    set(&mut vm, returns_function, "result", binary);
    let no_params = list(&mut vm, &[]);
    set(&mut vm, returns_function, "params", no_params);
    let adder = builtin(
        &mut vm,
        "foreign.bind",
        &[library, symbol, returns_function],
    )[0];
    vm.register(adder);
    let returned = through(&mut vm, Mode::Rust, adder, &[]).unwrap();
    vm.register(returned);
    assert_eq!(
        number(
            through(
                &mut vm,
                Mode::Rust,
                returned,
                &[Value::num(40.0), Value::num(2.0)]
            )
            .unwrap()
        ),
        42.0
    );
    for function in [returned, adder] {
        builtin(&mut vm, "foreign.close", &[function]);
    }

    // Binding through a closed library object is refused; what it bound stays callable.
    builtin(&mut vm, "foreign.close", &[library]);
    refused(
        through(
            &mut vm,
            Mode::Rust,
            Value::func(12),
            &[library, symbol, add_signature],
        ),
        "native library is closed or invalid",
    );
    assert_eq!(
        number(
            through(
                &mut vm,
                Mode::Rust,
                add,
                &[Value::num(1.0), Value::num(2.0)]
            )
            .unwrap()
        ),
        3.0
    );
    vm.full_cycle();
    vm.check_oracle();

    // The platform unloads the library once nothing holds it.
    let unloaded = PathBuf::from(format!("{}.unloaded", fixture.path()));
    for function in [add, twice, relative_add] {
        assert!(
            !unloaded.exists(),
            "the library unloaded while a function still held it"
        );
        builtin(&mut vm, "foreign.close", &[function]);
    }
    assert!(
        !unloaded.exists(),
        "the library unloaded while a library object still held it"
    );
    builtin(&mut vm, "foreign.close", &[global]);
    assert!(
        unloaded.exists(),
        "closing every holder did not unload the library"
    );
}

#[test]
fn callbacks_lend_retain_rebind_release_and_refuse_in_every_tier() {
    let fixture = Fixture::build();
    for mode in [Mode::Rust, Mode::Threaded, Mode::Typed, Mode::Frame] {
        let mut vm = machine(mode, &fixture.root.join("build/generated/binding.nupp"));
        let path = string(&mut vm, fixture.path());
        let library = builtin(&mut vm, "foreign.load", &[path])[0];
        vm.register(library);
        let int32 = string(&mut vm, "int32");
        let number_kind = string(&mut vm, "number");
        let pointer = string(&mut vm, "pointer");
        let binary = callback_type(&mut vm, &["int32", "int32"], "int32");
        let unary_double = callback_type(&mut vm, &["number"], "number");
        let with_context = callback_type(&mut vm, &["pointer", "int32"], "int32");
        let producer = callback_type(&mut vm, &["int32"], "pointer");

        let apply = bind(
            &mut vm,
            library,
            "loader_apply",
            "int32",
            &[binary, int32, int32],
        );
        let apply_double = bind(
            &mut vm,
            library,
            "loader_apply_double",
            "number",
            &[unary_double, number_kind],
        );
        let keep = bind(&mut vm, library, "loader_keep", "void", &[binary]);
        let call_kept = bind(
            &mut vm,
            library,
            "loader_call_kept",
            "int32",
            &[int32, int32],
        );
        let kept_address = bind(&mut vm, library, "loader_kept_address", "uint64", &[]);
        let twice = bind(&mut vm, library, "loader_twice", "int32", &[int32]);
        let read = bind(&mut vm, library, "loader_read", "int32", &[pointer]);
        let context = bind(&mut vm, library, "loader_context", "pointer", &[]);
        let contextual = bind(
            &mut vm,
            library,
            "loader_with_context",
            "int32",
            &[with_context, pointer, int32],
        );
        let produce = bind(
            &mut vm,
            library,
            "loader_produce",
            "pointer",
            &[producer, int32],
        );
        let from_thread = bind(
            &mut vm,
            library,
            "loader_call_from_thread",
            "int32",
            &[binary],
        );
        global(&mut vm, "twice", twice);
        global(&mut vm, "read", read);
        let (add, sub, reenter, fail, halve) = (
            Value::func(4),
            Value::func(5),
            Value::func(6),
            Value::func(7),
            Value::func(8),
        );
        let n = Value::num;

        // A plain function is lent a trampoline for the length of one call.
        assert_eq!(
            number(through(&mut vm, mode, apply, &[add, n(19.0), n(23.0)]).unwrap()),
            42.0
        );
        assert_eq!(
            number(through(&mut vm, mode, apply, &[reenter, n(20.0), n(1.0)]).unwrap()),
            42.0
        );
        assert_eq!(
            number(through(&mut vm, mode, apply_double, &[halve, n(84.0)]).unwrap()),
            42.0
        );
        // C that keeps a lent pointer past the call is refused when it calls it.
        through(&mut vm, mode, keep, &[add]).unwrap();
        refused(
            through(&mut vm, mode, call_kept, &[n(1.0), n(2.0)]),
            "native callback invoked after the call that lent it returned",
        );
        // So is a call from a thread the VM does not run on.
        refused(
            through(&mut vm, mode, from_thread, &[add]),
            "native callback invoked from a thread other than its VM's",
        );

        // A retained callback takes its C signature from the first parameter it fills.
        let retained = builtin(&mut vm, "foreign.callback", &[Value::NIL, add])[0];
        vm.register(retained);
        through(&mut vm, mode, keep, &[retained]).unwrap();
        let address = through(&mut vm, mode, kept_address, &[]).unwrap();
        vm.register(address);
        assert_eq!(
            number(through(&mut vm, mode, call_kept, &[n(40.0), n(2.0)]).unwrap()),
            42.0
        );
        // Rebinding keeps the pointer C holds.
        builtin(&mut vm, "foreign.setCallback", &[retained, sub]);
        assert_eq!(
            number(through(&mut vm, mode, call_kept, &[n(50.0), n(8.0)]).unwrap()),
            42.0
        );
        let again = through(&mut vm, mode, kept_address, &[]).unwrap();
        assert_eq!(bits(address), bits(again), "rebinding moved the C pointer");
        // Nupp calls a retained callback as the function it holds.
        assert_eq!(number(vm.call_value(retained, &[n(50.0), n(8.0)])[0]), 42.0);
        // A callback with another C signature is refused rather than reinterpreted.
        refused(
            through(&mut vm, mode, apply_double, &[retained, n(1.0)]),
            "native callback has C signature (int32,int32):int32, but the parameter expects (number):number",
        );
        // An error raised in a callback reaches the Nupp caller, and the callback recovers.
        builtin(&mut vm, "foreign.setCallback", &[retained, fail]);
        refused(
            through(&mut vm, mode, call_kept, &[n(1.0), n(2.0)]),
            "callback failure",
        );
        builtin(&mut vm, "foreign.setCallback", &[retained, reenter]);
        assert_eq!(
            number(through(&mut vm, mode, call_kept, &[n(20.0), n(1.0)]).unwrap()),
            42.0
        );
        vm.full_cycle();
        vm.check_oracle();
        // Released, the pointer C still holds reaches a refusal, not freed code.
        builtin(&mut vm, "foreign.close", &[retained]);
        refused(
            through(&mut vm, mode, call_kept, &[n(1.0), n(2.0)]),
            "native callback invoked after it was released",
        );
        refused(
            through(&mut vm, mode, apply, &[retained, n(1.0), n(2.0)]),
            "a native callback parameter takes a function, a retained callback, or nil",
        );
        through(&mut vm, mode, keep, &[Value::NIL]).unwrap();
        assert_eq!(
            number(through(&mut vm, mode, call_kept, &[n(1.0), n(2.0)]).unwrap()),
            -1.0
        );

        // A released trampoline is reused only after 256 later releases, so the
        // trampolines a program holds stay bounded by what it keeps alive.
        let kept_bits = |vm: &mut Interp| bits(through(vm, mode, kept_address, &[]).unwrap());
        let first = builtin(&mut vm, "foreign.callback", &[Value::NIL, add])[0];
        vm.register(first);
        through(&mut vm, mode, keep, &[first]).unwrap();
        let first_address = kept_bits(&mut vm);
        builtin(&mut vm, "foreign.close", &[first]);
        for _ in 0..256 {
            let later = builtin(&mut vm, "foreign.callback", &[Value::NIL, sub])[0];
            let root = vm.register(later);
            through(&mut vm, mode, keep, &[later]).unwrap();
            assert_ne!(
                kept_bits(&mut vm),
                first_address,
                "a released trampoline was reused early"
            );
            builtin(&mut vm, "foreign.close", &[later]);
            vm.release(root);
        }
        let reused = builtin(&mut vm, "foreign.callback", &[Value::NIL, add])[0];
        vm.register(reused);
        through(&mut vm, mode, keep, &[reused]).unwrap();
        assert_eq!(
            kept_bits(&mut vm),
            first_address,
            "the oldest released trampoline was not reused"
        );
        assert_eq!(
            number(through(&mut vm, mode, call_kept, &[n(40.0), n(2.0)]).unwrap()),
            42.0
        );
        builtin(&mut vm, "foreign.close", &[reused]);
        through(&mut vm, mode, keep, &[Value::NIL]).unwrap();

        // Pointers C passes a callback are opaque handles for that invocation.
        let handle = through(&mut vm, mode, context, &[]).unwrap();
        vm.register(handle);
        global(&mut vm, "context", handle);
        assert_eq!(
            number(through(&mut vm, mode, contextual, &[Value::func(9), handle, n(2.0)]).unwrap()),
            42.0
        );
        let globals = vm.require("_G");
        let leaked_key = vm.intern("leaked");
        let leaked = vm.get_index(globals, leaked_key);
        assert!(leaked != Value::NIL);
        assert!(
            through(&mut vm, mode, read, &[leaked]).is_err(),
            "a lent pointer outlived its callback"
        );
        // A callback may return an address C owns, and nothing managed.
        let produced = through(&mut vm, mode, produce, &[Value::func(10), n(0.0)]).unwrap();
        vm.register(produced);
        assert_eq!(
            number(through(&mut vm, mode, read, &[produced]).unwrap()),
            40.0
        );
        refused(
            through(&mut vm, mode, produce, &[Value::func(11), n(0.0)]),
            "a native callback returns a foreign pointer or nil",
        );

        // Signatures a callback cannot have are refused when declared.
        let aggregate = vm.new_table();
        vm.register(aggregate);
        let kind = string(&mut vm, "struct");
        set(&mut vm, aggregate, "kind", kind);
        let unsupported = signature(&mut vm, "int32", &[aggregate]);
        let problem = message(&mut vm, |vm| {
            builtin(vm, "foreign.callback", &[unsupported, add]);
        });
        assert!(
            problem.contains("cannot be an aggregate or a function by value"),
            "{problem}"
        );
        let variadic = signature(&mut vm, "int32", &[int32]);
        set(&mut vm, variadic, "fixed", n(1.0));
        let problem = message(&mut vm, |vm| {
            builtin(vm, "foreign.callback", &[variadic, add]);
        });
        assert!(
            problem.contains("a native callback cannot be variadic"),
            "{problem}"
        );
        vm.full_cycle();
        vm.check_oracle();
        if matches!(mode, Mode::Frame) {
            assert!(
                vm.compiled_frame_entries > 0,
                "no foreign call ran from a compiled frame"
            );
        }
    }
}
