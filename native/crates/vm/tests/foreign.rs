#![cfg(all(feature = "native-ffi", not(target_family = "wasm")))]

use nupp_vm::{builtins, interp::Interp, numeric, persist, value::Value};
use std::{path::PathBuf, process::Command};

struct Fixture(PathBuf);
impl Fixture {
    fn build() -> Self {
        static NEXT: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);
        let sequence = NEXT.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
        let nonce = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let directory = std::env::temp_dir().join(format!(
            "nupp-foreign-{}-{nonce}-{sequence}",
            std::process::id()
        ));
        std::fs::create_dir(&directory).unwrap();
        let file = if cfg!(windows) {
            "fixture.dll"
        } else if cfg!(target_os = "macos") {
            "libfixture.dylib"
        } else {
            "libfixture.so"
        };
        let library = directory.join(file);
        let source = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/ffi/fixture.c");
        let compiler = std::env::var("CC").unwrap_or_else(|_| "cc".into());
        let mut command = Command::new(&compiler);
        command.current_dir(&directory);
        if PathBuf::from(&compiler)
            .file_stem()
            .and_then(|s| s.to_str())
            == Some("cl")
        {
            command
                .args(["/LD", "/std:c11", "/O2"])
                .arg(&source)
                .arg(format!("/Fe:{}", library.display()));
        } else {
            command.args(["-std=c11", "-O2"]);
            if cfg!(target_os = "macos") {
                command.arg("-dynamiclib");
            } else {
                command.args(["-shared", "-fPIC"]);
            }
            command.arg(&source).arg("-o").arg(&library);
        }
        let output = command
            .output()
            .expect("independent C compiler is required for native FFI acceptance");
        assert!(
            output.status.success(),
            "{}",
            String::from_utf8_lossy(&output.stderr)
        );
        Self(library)
    }
}
impl Drop for Fixture {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(self.0.parent().unwrap());
    }
}
fn integer(value: i64) -> Value {
    Value::inline_integer(value).unwrap()
}

fn call(vm: &mut Interp, name: &str, args: &[Value]) -> Vec<Value> {
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
fn bind(
    vm: &mut Interp,
    library: Value,
    symbol: &str,
    result: &str,
    params: &[&str],
    fixed: Option<usize>,
) -> Value {
    let symbol = string(vm, symbol);
    let signature = vm.new_table();
    vm.register(signature);
    let result = string(vm, result);
    set(vm, signature, "result", result);
    let list = vm.new_table();
    vm.register(list);
    for param in params {
        let param = string(vm, param);
        vm.push_array(list, param);
    }
    set(vm, signature, "params", list);
    if let Some(fixed) = fixed {
        set(vm, signature, "fixed", Value::num(fixed as f64));
    }
    let function = call(vm, "foreign.bind", &[library, symbol, signature])[0];
    vm.register(function);
    function
}
fn invoke(vm: &mut Interp, function: Value, args: &[Value]) -> Vec<Value> {
    let mut all = vec![function];
    all.extend_from_slice(args);
    call(vm, "foreign.call", &all)
}
fn failure(vm: &mut Interp, body: impl FnOnce(&mut Interp)) {
    let roots = vm.handles.len();
    assert!(std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| body(vm))).is_err());
    assert_eq!(
        vm.handles.len(),
        roots,
        "failed foreign operation leaked temporary roots"
    );
}
fn vm() -> Interp {
    let mut vm = Interp::new();
    vm.heap.stress_steps = true;
    vm.heap.oracle = true;
    vm.heap.quarantine = true;
    vm.install_globals();
    vm
}
#[test]
fn independent_c_scalar_calls_variadics_errno_and_closed_handles() {
    let fixture = Fixture::build();
    let mut vm = vm();
    let library = string(&mut vm, fixture.0.to_str().unwrap());
    for (suffix, kind, number) in [
        ("i8", "int8", -128.0),
        ("u8", "uint8", 255.0),
        ("i16", "int16", -32768.0),
        ("u16", "uint16", 65535.0),
        ("i32", "int32", -2147483648.0),
        ("u32", "uint32", 4294967295.0),
        ("float", "float32", 1.5),
        ("double", "float64", -2.25),
    ] {
        let function = bind(
            &mut vm,
            library,
            &format!("ffi_test_{suffix}"),
            kind,
            &[kind],
            None,
        );
        assert_eq!(
            invoke(&mut vm, function, &[Value::num(number)]),
            vec![if suffix == "float" || suffix == "double" {
                Value::num(number)
            } else {
                integer(number as i64)
            }]
        );
        call(&mut vm, "foreign.close", &[function]);
        failure(&mut vm, |vm| {
            invoke(vm, function, &[Value::num(number)]);
        });
    }
    for (name, kind, bits, unsigned) in [
        ("ffi_test_i64", "int64", (1u64 << 63) + 1, false),
        ("ffi_test_u64", "uint64", u64::MAX, true),
    ] {
        let function = bind(&mut vm, library, name, kind, &[kind], None);
        let value = vm.box_integer(numeric::Integer { bits, unsigned });
        vm.register(value);
        let result = invoke(&mut vm, function, &[value])[0];
        let exact = numeric::integer(result).unwrap();
        assert_eq!((exact.bits, exact.unsigned), (bits, false));
        call(&mut vm, "foreign.close", &[function]);
    }
    let boolean = bind(&mut vm, library, "ffi_test_bool", "bool", &["bool"], None);
    assert_eq!(invoke(&mut vm, boolean, &[Value::TRUE]), vec![Value::TRUE]);
    assert_eq!(
        invoke(&mut vm, boolean, &[Value::FALSE]),
        vec![Value::FALSE]
    );
    failure(&mut vm, |vm| {
        invoke(vm, boolean, &[Value::num(1.0)]);
    });
    let sum = bind(
        &mut vm,
        library,
        "ffi_test_varargs_double",
        "float64",
        &["int32", "float64", "float64"],
        Some(1),
    );
    assert_eq!(
        invoke(
            &mut vm,
            sum,
            &[Value::num(2.0), Value::num(1.5), Value::num(2.25)]
        ),
        vec![Value::num(3.75)]
    );
    let error = bind(
        &mut vm,
        library,
        "ffi_test_errno",
        "int32",
        &["int32"],
        None,
    );
    assert_eq!(
        invoke(&mut vm, error, &[Value::num(31.0)]),
        vec![integer(-1)]
    );
    vm.full_cycle();
    vm.check_oracle();
    assert_eq!(call(&mut vm, "foreign.errno", &[]), vec![integer(31)]);
    assert_eq!(
        call(&mut vm, "foreign.errno", &[Value::num(17.0)]),
        vec![integer(31)]
    );
    let read_error = bind(&mut vm, library, "ffi_test_read_errno", "int32", &[], None);
    assert_eq!(invoke(&mut vm, read_error, &[]), vec![integer(17)]);
    failure(&mut vm, |vm| {
        bind(vm, library, "missing_symbol", "void", &[], None);
    });
    failure(&mut vm, |vm| {
        bind(vm, library, "ffi_test_i32", "bogus", &["int32"], None);
    });
    failure(&mut vm, |vm| {
        invoke(vm, sum, &[]);
    });
    #[cfg(unix)]
    {
        let abs = bind(&mut vm, Value::NIL, "abs", "int32", &["int32"], None);
        assert_eq!(
            invoke(&mut vm, abs, &[Value::num(-42.0)]),
            vec![integer(42)]
        );
        call(&mut vm, "foreign.close", &[abs]);
    }
    for function in [boolean, sum, error, read_error] {
        call(&mut vm, "foreign.close", &[function]);
    }
}
#[test]
fn managed_pointer_arguments_survive_gc_and_external_pointers_refuse_persistence() {
    let fixture = Fixture::build();
    let mut vm = vm();
    let library = string(&mut vm, fixture.0.to_str().unwrap());
    let const_pointer = vm.new_table();
    vm.register(const_pointer);
    let pointer_kind = string(&mut vm, "pointer");
    set(&mut vm, const_pointer, "kind", pointer_kind);
    set(&mut vm, const_pointer, "readonly", Value::TRUE);
    let wide_kind = string(&mut vm, "uint64");
    let void_kind = string(&mut vm, "void");
    let copy = bind_aggregate(
        &mut vm,
        library,
        "ffi_test_copy",
        void_kind,
        &[pointer_kind, const_pointer, wide_kind],
    );
    let pointer = bind(
        &mut vm,
        library,
        "ffi_test_pointer",
        "pointer",
        &["pointer"],
        None,
    );
    assert_eq!(invoke(&mut vm, pointer, &[Value::NIL]), vec![Value::NIL]);
    let input = string(&mut vm, "nupp\0ffi");
    failure(&mut vm, |vm| {
        invoke(vm, pointer, &[input]);
    });
    let readonly = call(&mut vm, "storage.castBytes", &[input])[0];
    vm.register(readonly);
    failure(&mut vm, |vm| {
        invoke(vm, pointer, &[readonly]);
    });
    let length = bind_aggregate(
        &mut vm,
        library,
        "ffi_test_strlen",
        wide_kind,
        &[const_pointer],
    );
    assert_eq!(invoke(&mut vm, length, &[readonly]), vec![integer(4)]);
    call(&mut vm, "foreign.close", &[length]);
    let output = call(&mut vm, "storage.allocateBytes", &[Value::num(8.0)])[0];
    let output_root = vm.register(output);
    // Neither a structural dictionary nor a marked view over a growable buffer
    // is an address-stable native pointer capability.
    let fake = vm.new_table();
    vm.register(fake);
    for field in ["owner", "offset", "end", "descriptor", "readonly"] {
        let key = vm.intern(&format!("\0nupp:storage:{field}"));
        let value = vm.get_index(output, key);
        set(&mut vm, fake, field, value);
    }
    failure(&mut vm, |vm| {
        invoke(vm, pointer, &[fake]);
    });
    let growable = vm.heap_new_buffer();
    vm.register(growable);
    vm.buf_append(growable, b"12345678");
    set(&mut vm, fake, "owner", growable);
    let marked = call(&mut vm, "storage.castBytes", &[fake])[0];
    vm.register(marked);
    failure(&mut vm, |vm| {
        invoke(vm, pointer, &[marked]);
    });
    invoke(&mut vm, copy, &[output, input, Value::num(8.0)]);
    let text = call(&mut vm, "storage.string", &[output, Value::num(8.0)])[0];
    assert_eq!(vm.bytes_of(text), b"nupp\0ffi");
    let returned = invoke(&mut vm, pointer, &[output])[0];
    vm.register(returned);
    // Public table fields are not native-pointer lifetime authority.
    vm.set_index(returned, Value::num(1.0), Value::NIL);
    let owner_key = vm.intern("\0nupp:storage:owner");
    vm.set_index(output, owner_key, Value::NIL);
    vm.release(output_root);
    vm.full_cycle();
    vm.check_oracle();
    let error = persist::save_graph(&mut vm, &[returned], &Default::default()).unwrap_err();
    assert!(error.contains("resource"), "{error}");
    let destination = call(&mut vm, "storage.allocateBytes", &[Value::num(8.0)])[0];
    vm.register(destination);
    invoke(&mut vm, copy, &[destination, returned, Value::num(8.0)]);
    let text = call(&mut vm, "storage.string", &[destination, Value::num(8.0)])[0];
    assert_eq!(vm.bytes_of(text), b"nupp\0ffi");
    call(&mut vm, "foreign.close", &[returned]);
    failure(&mut vm, |vm| {
        invoke(vm, copy, &[destination, returned, Value::num(8.0)]);
    });
    for function in [copy, pointer] {
        call(&mut vm, "foreign.close", &[function]);
    }
}

fn struct_type(
    vm: &mut Interp,
    name: &str,
    size: usize,
    alignment: usize,
    fields: &[(&str, &str, usize)],
) -> Value {
    aggregate_type(vm, "struct", name, size, alignment, fields)
}
fn aggregate_type(
    vm: &mut Interp,
    aggregate_kind: &str,
    name: &str,
    size: usize,
    alignment: usize,
    fields: &[(&str, &str, usize)],
) -> Value {
    let layout = vm.new_table();
    vm.register(layout);
    let kind = string(vm, aggregate_kind);
    set(vm, layout, "kind", kind);
    let identity = string(vm, name);
    set(vm, layout, "identity", identity);
    set(vm, layout, "size", Value::num(size as f64));
    set(vm, layout, "alignment", Value::num(alignment as f64));
    let list = vm.new_table();
    vm.register(list);
    for (name, kind, offset) in fields {
        let field = vm.new_table();
        vm.register(field);
        let name = string(vm, name);
        set(vm, field, "name", name);
        let kind = string(vm, kind);
        set(vm, field, "kind", kind);
        set(vm, field, "offset", Value::num(*offset as f64));
        vm.push_array(list, field);
    }
    set(vm, layout, "fields", list);
    let descriptor = call(vm, "storage.structDefine", &[layout, Value::NIL])[0];
    vm.register(descriptor);
    descriptor
}

#[test]
fn union_and_nested_union_byvalue_signatures_roundtrip() {
    let fixture = Fixture::build();
    let mut vm = vm();
    let library = string(&mut vm, fixture.0.to_str().unwrap());
    let union = aggregate_type(
        &mut vm,
        "union",
        "ffi.oracle.Union",
        4,
        4,
        &[("bits", "uint32", 0), ("real", "float32", 0)],
    );
    let size_kind = if cfg!(target_pointer_width = "64") {
        "uint64"
    } else {
        "uint32"
    };
    let layout = bind(
        &mut vm,
        library,
        "ffi_test_layout",
        size_kind,
        &["uint32"],
        None,
    );
    for (query, expected) in [(14, 4), (15, 4), (16, 0), (17, 0)] {
        let result = invoke(&mut vm, layout, &[Value::num(query as f64)])[0];
        assert_eq!(numeric::bits(&vm, result, true), expected);
    }
    call(&mut vm, "foreign.close", &[layout]);
    let write = bind(
        &mut vm,
        library,
        "ffi_test_byte_union",
        "void",
        &["pointer", "uint32"],
        None,
    );
    let value = call(&mut vm, "storage.valueNew", &[union])[0];
    vm.register(value);
    invoke(&mut vm, write, &[value, Value::num(0x3f80_0000 as f64)]);
    let real = string(&mut vm, "real");
    assert_eq!(
        call(&mut vm, "storage.index", &[value, real]),
        vec![Value::num(1.0)]
    );
    call(&mut vm, "foreign.close", &[write]);
    let outer = vm.new_table();
    vm.register(outer);
    let kind = string(&mut vm, "struct");
    set(&mut vm, outer, "kind", kind);
    let identity = string(&mut vm, "ffi.oracle.NestedUnion");
    set(&mut vm, outer, "identity", identity);
    set(&mut vm, outer, "size", Value::num(4.0));
    set(&mut vm, outer, "alignment", Value::num(4.0));
    let fields = vm.new_table();
    vm.register(fields);
    let member = vm.new_table();
    vm.register(member);
    let name = string(&mut vm, "value");
    set(&mut vm, member, "name", name);
    set(&mut vm, member, "offset", Value::num(0.0));
    set(&mut vm, member, "type", union);
    vm.push_array(fields, member);
    set(&mut vm, outer, "fields", fields);
    let nested = call(&mut vm, "storage.structDefine", &[outer, Value::NIL])[0];
    vm.register(nested);
    // libffi has no unions; each passes as the struct its target classifies
    // alike, alone and nested in a struct, as an argument and as a result.
    let symbol = string(&mut vm, "ffi_test_union");
    let bits = string(&mut vm, "bits");
    let value_name = string(&mut vm, "value");
    for (descriptor, nested_value) in [(union, false), (nested, true)] {
        let signature = vm.new_table();
        vm.register(signature);
        set(&mut vm, signature, "result", descriptor);
        let params = vm.new_table();
        vm.register(params);
        vm.push_array(params, descriptor);
        set(&mut vm, signature, "params", params);
        let function = call(&mut vm, "foreign.bind", &[library, symbol, signature])[0];
        vm.register(function);
        let argument = call(&mut vm, "storage.valueNew", &[descriptor])[0];
        vm.register(argument);
        let inner = if nested_value {
            call(&mut vm, "storage.index", &[argument, value_name])[0]
        } else {
            argument
        };
        vm.register(inner);
        call(
            &mut vm,
            "storage.write",
            &[inner, bits, Value::num(0x3f80_0000 as f64)],
        );
        vm.full_cycle();
        let returned = invoke(&mut vm, function, &[argument])[0];
        vm.register(returned);
        let returned = if nested_value {
            call(&mut vm, "storage.index", &[returned, value_name])[0]
        } else {
            returned
        };
        assert_eq!(
            call(&mut vm, "storage.index", &[returned, real]),
            vec![Value::num(1.0)]
        );
        call(&mut vm, "foreign.close", &[function]);
    }
    vm.full_cycle();
    vm.check_oracle();
}
fn bind_aggregate(
    vm: &mut Interp,
    library: Value,
    symbol: &str,
    result: Value,
    params: &[Value],
) -> Value {
    let signature = vm.new_table();
    vm.register(signature);
    set(vm, signature, "result", result);
    let list = vm.new_table();
    vm.register(list);
    for &param in params {
        vm.push_array(list, param);
    }
    set(vm, signature, "params", list);
    let symbol = string(vm, symbol);
    let function = call(vm, "foreign.bind", &[library, symbol, signature])[0];
    vm.register(function);
    function
}
#[test]
fn native_aggregate_hfa_and_large_return_preserve_value_semantics() {
    let fixture = Fixture::build();
    let mut vm = vm();
    let library = string(&mut vm, fixture.0.to_str().unwrap());
    let pair = struct_type(
        &mut vm,
        "ffi.oracle.Pair",
        16,
        8,
        &[("x", "float64", 0), ("y", "float64", 8)],
    );
    let double = string(&mut vm, "float64");
    let function = bind_aggregate(&mut vm, library, "ffi_test_pair", pair, &[pair, double]);
    let input = call(
        &mut vm,
        "storage.valueOf",
        &[pair, Value::num(1.5), Value::num(2.5)],
    )[0];
    vm.register(input);
    let output = invoke(&mut vm, function, &[input, Value::num(2.0)])[0];
    vm.register(output);
    let x = string(&mut vm, "x");
    let y = string(&mut vm, "y");
    assert_eq!(
        call(&mut vm, "storage.index", &[output, x]),
        vec![Value::num(3.5)]
    );
    assert_eq!(
        call(&mut vm, "storage.index", &[output, y]),
        vec![Value::num(0.5)]
    );
    assert_eq!(
        call(&mut vm, "storage.index", &[input, x]),
        vec![Value::num(1.5)]
    );
    call(&mut vm, "foreign.close", &[function]);
    let semantic = struct_type(
        &mut vm,
        "ffi.oracle.NuppScalars",
        8,
        4,
        &[("flag", "boolean", 0), ("count", "int32", 4)],
    );
    let function = bind_aggregate(
        &mut vm,
        library,
        "ffi_test_nupp_scalars",
        semantic,
        &[semantic],
    );
    let input = call(
        &mut vm,
        "storage.valueOf",
        &[semantic, Value::TRUE, Value::num(41.0)],
    )[0];
    vm.register(input);
    let output = invoke(&mut vm, function, &[input])[0];
    vm.register(output);
    let flag = string(&mut vm, "flag");
    let count = string(&mut vm, "count");
    assert_eq!(
        call(&mut vm, "storage.index", &[output, flag]),
        vec![Value::FALSE]
    );
    assert_eq!(
        call(&mut vm, "storage.index", &[output, count]),
        vec![integer(42)]
    );
    call(&mut vm, "foreign.close", &[function]);
    let large = struct_type(
        &mut vm,
        "ffi.oracle.Large",
        32,
        8,
        &[
            ("a", "uint64", 0),
            ("b", "uint64", 8),
            ("c", "uint64", 16),
            ("d", "uint64", 24),
        ],
    );
    let function = bind_aggregate(&mut vm, library, "ffi_test_large", large, &[large]);
    let exact = vm.box_integer(numeric::Integer {
        bits: u64::MAX,
        unsigned: true,
    });
    vm.register(exact);
    let input = call(
        &mut vm,
        "storage.valueOf",
        &[
            large,
            exact,
            Value::num(2.0),
            Value::num(3.0),
            Value::num(4.0),
        ],
    )[0];
    vm.register(input);
    let output = invoke(&mut vm, function, &[input])[0];
    vm.register(output);
    vm.full_cycle();
    vm.check_oracle();
    let a = string(&mut vm, "a");
    let d = string(&mut vm, "d");
    assert_eq!(
        numeric::integer(call(&mut vm, "storage.index", &[output, a])[0])
            .unwrap()
            .bits,
        u64::MAX
    );
    let small = call(&mut vm, "storage.index", &[output, d])[0];
    assert_eq!(numeric::word(&vm, small, true), 4);
    call(&mut vm, "storage.write", &[output, a, Value::num(7.0)]);
    assert_eq!(
        numeric::integer(call(&mut vm, "storage.index", &[input, a])[0])
            .unwrap()
            .bits,
        u64::MAX
    );
    call(&mut vm, "foreign.close", &[function]);
}
