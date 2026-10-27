use nupp_vm::{image, interp::Interp, value::Value};

fn quoted(text: &str) -> String {
    let mut out = String::from("\"");
    for b in text.bytes() {
        out.push_str(&format!("\\{b:03}"));
    }
    out.push('"');
    out
}

#[test]
fn load_and_call_during_interpretation() {
    // Force dispatch and entry tables to grow while the caller is active.
    let mut inner = String::new();
    for i in 0..300 {
        inner.push_str(&format!("function f{i} {i} 0 12 1 :v\nconst 0 num 42\nK 1 0\nRet 1\nend\n"));
    }
    inner.push_str("entry 299\n");
    let outer = format!("function main 0 0 12 1 :v\nconst 0 builtin vm.loadImage\nconst 1 str {}\nK 1 0\nK 2 1\nCallDyn 1 1 1\nCallDyn 1 1 0\nRet 1\nend\nentry 0\n", quoted(&inner));
    for threaded in [false, true] {
        let mut it = Interp::new();
        let entry = image::load(&mut it, &outer).unwrap();
        it.install_globals();
        it.entries.resize(it.funcs.len(), 0);
        if threaded { it.prepare_threaded(); }
        let result = it.call_value(Value::func(entry), &[]);
        assert_eq!(result, vec![Value::num(42.0)]);
    }
}

#[test]
fn filesystem_builtins_do_not_enter_scalar_dispatch() {
    let mut it = Interp::new();
    it.install_globals();
    let path = it.heap_new_string(env!("CARGO_MANIFEST_DIR"));
    let root = it.register(path);
    let id = nupp_vm::builtins::id_of("files.info").unwrap();
    let info = it.call_value(Value::builtin(id), &[path])[0];
    let handle = it.register(info);
    let key = it.intern("kind");
    assert_eq!(it.bytes_of(it.get_index(info, key)), b"directory");
    it.release(handle);
    it.release(root);
}

#[test]
fn filesystem_host_creates_and_removes_without_following_links() {
    use std::path::{Path, PathBuf};
    struct Scratch(PathBuf);
    impl Drop for Scratch {
        fn drop(&mut self) { let _ = std::fs::remove_dir_all(&self.0); }
    }
    fn call(it: &mut Interp, name: &str, path: &Path, recursive: Value) -> Vec<Value> {
        let module = it.require("nupp.vm.files");
        let key = it.intern(name);
        let function = it.get_index(module, key);
        let path = it.heap_new_string(&path.to_string_lossy());
        it.call_value(function, &[path, recursive])
    }
    let nonce = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_nanos();
    let root = Scratch(std::env::temp_dir().join(format!("nupp-vm-files-{}-{nonce}", std::process::id())));
    let nested = root.0.join("tree/nested");
    let mut it = Interp::new();
    it.install_globals();
    assert_eq!(call(&mut it, "createDirectory", &nested, Value::NIL), vec![Value::TRUE]);
    assert_eq!(call(&mut it, "createDirectory", &nested, Value::NIL), vec![Value::TRUE]);
    let file = nested.join("kept.txt");
    std::fs::write(&file, "kept").unwrap();
    let failed = call(&mut it, "remove", &nested, Value::FALSE);
    assert_eq!(failed[0], Value::FALSE);
    assert!(!it.bytes_of(failed[1]).is_empty());
    assert!(file.exists());
    assert_eq!(call(&mut it, "remove", &file, Value::NIL), vec![Value::TRUE]);
    assert_eq!(call(&mut it, "remove", &nested, Value::FALSE), vec![Value::TRUE]);
    assert_eq!(call(&mut it, "remove", &file, Value::NIL)[0], Value::FALSE);
    #[cfg(unix)]
    {
        let outside = root.0.join("outside");
        std::fs::create_dir(&outside).unwrap();
        std::fs::write(outside.join("kept.txt"), "kept").unwrap();
        let link = root.0.join("tree/link");
        std::os::unix::fs::symlink(&outside, &link).unwrap();
        assert_eq!(call(&mut it, "remove", &link, Value::TRUE), vec![Value::TRUE]);
        assert!(outside.join("kept.txt").exists());
        std::os::unix::fs::symlink(&outside, &link).unwrap();
        assert_eq!(call(&mut it, "remove", &root.0.join("tree"), Value::TRUE), vec![Value::TRUE]);
        assert!(outside.join("kept.txt").exists());
    }
    assert_eq!(call(&mut it, "remove", &root.0, Value::TRUE), vec![Value::TRUE]);
    assert!(!root.0.exists());
}

#[test]
fn compiler_host_sha256_and_process_identity() {
    let mut it = Interp::new();
    it.install_globals();
    let module = it.require("nupp.digest.internal.sha256");
    let key = it.intern("sha256");
    let hash = it.get_index(module, key);
    for (source, expected) in [
        ("", "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"),
        ("abc", "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"),
        ("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq", "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1"),
    ] {
        let text = it.heap_new_string(source);
        let result = it.call_value(hash, &[text]);
        assert_eq!(it.bytes_of(result[0]), expected.as_bytes());
    }
    let module = it.require("nupp.compiler.hostpid");
    let key = it.intern("get");
    let get = it.get_index(module, key);
    assert_eq!(it.call_value(get, &[]), vec![Value::inline_integer(std::process::id() as i64).unwrap()]);
}

#[test]
fn numeric_image_precision_round_trips() {
    let mut it = Interp::new();
    it.install_globals();
    let format = Value::builtin(nupp_vm::builtins::id_of("string.format").unwrap());
    let spec = it.intern("%.17g");
    let root = it.register(spec);
    for number in [9007199254740991.0, 9007199254740992.0, f32::MAX as f64,
                   1.0e-20, f64::MIN_POSITIVE, f64::from_bits(1), -0.0, 1.2345678901234567] {
        let value = it.call_value(format, &[spec, Value::num(number)])[0];
        let text = std::str::from_utf8(it.bytes_of(value)).unwrap();
        assert_eq!(text.parse::<f64>().unwrap().to_bits(), number.to_bits(), "{text}");
    }
    it.release(root);
}

#[test]
fn quoted_control_bytes_before_digits_round_trip() {
    let mut vm = Interp::new();
    vm.heap.stress_steps = true;
    vm.heap.oracle = true;
    vm.install_globals();
    let format = Value::builtin(nupp_vm::builtins::id_of("string.format").unwrap());
    let load = Value::builtin(nupp_vm::builtins::id_of("loadstring").unwrap());
    let spec = vm.intern("%q");
    vm.register(spec);
    for original in [b"\x001".as_slice(), b"\x012", b"\x1f9\x7f0", b"a\n\r\"\\b"] {
        let mark = vm.open_scope();
        let input = vm.string_of(original);
        vm.handles.push(input);
        let quoted = vm.call_value(format, &[spec, input])[0];
        vm.handles.push(quoted);
        let mut source = b"return ".to_vec();
        source.extend_from_slice(vm.bytes_of(quoted));
        let source = vm.string_of(&source);
        vm.handles.push(source);
        let function = vm.call_value(load, &[source])[0];
        vm.handles.push(function);
        let result = vm.call_value(function, &[])[0];
        assert_eq!(vm.bytes_of(result), original);
        vm.close_scope(mark);
    }
}

/// A module an image loaded at run time declared answers `require` from that
/// image once. After `require` loaded it and `package.loaded` forgot it, the
/// image loader stands aside so the loaders behind it load the module again;
/// loading a new image that declares it makes that image current. The running
/// image's own modules keep answering.
#[test]
fn image_loader_stands_aside_for_a_spent_runtime_module() {
    let base = "function basemod 0 0 12 1 :v\nNewTableN 1 0 0\nRet 1\nend\nmodule basemod 0\nentry 0\n";
    let dynamic = "function dyn 0 0 12 1 :v\nNewTableN 1 0 0\nRet 1\nend\nmodule dyn 0\nentry 0\n";
    let mut it = Interp::new();
    image::load(&mut it, base).unwrap();
    it.install_globals();
    it.entries.resize(it.funcs.len(), 0);
    let load_image = Value::builtin(nupp_vm::builtins::id_of("vm.loadImage").unwrap());
    let image_loader = Value::builtin(nupp_vm::builtins::id_of("package.imageLoader").unwrap());
    let ask = |it: &mut Interp, name: &str| -> Value {
        let key = it.intern(name);
        let root = it.register(key);
        let answer = it.call_value(image_loader, &[key])[0];
        it.release(root);
        answer
    };
    let forget = |it: &mut Interp, name: &str| {
        let key = it.intern(name);
        let root = it.register(key);
        it.set_index(it.loaded_table, key, Value::NIL);
        it.release(root);
    };
    let text = it.heap_new_string(dynamic);
    let root = it.register(text);
    it.call_value(load_image, &[text]);
    assert!(ask(&mut it, "dyn").as_func().is_some(), "a freshly loaded image answers for its module");
    let first = it.require("dyn");
    let first_root = it.register(first);
    forget(&mut it, "dyn");
    assert_eq!(ask(&mut it, "dyn"), Value::NIL, "a spent runtime module is left to the other loaders");
    it.call_value(load_image, &[text]);
    assert!(ask(&mut it, "dyn").as_func().is_some(), "a newer image is current for the name again");
    let second = it.require("dyn");
    assert_ne!(first, second, "requiring after a clear runs the newer image's chunk");
    it.release(first_root);
    it.release(root);
    it.require("basemod");
    forget(&mut it, "basemod");
    assert!(ask(&mut it, "basemod").as_func().is_some(), "the running image keeps answering for its own modules");
}

#[test]
fn image_quotes_unicode_whitespace_and_buffer_reuse_survive_gc() {
    let text = "\u{2003}shape\u{00a0}0 Box x:str\n\
                function value 0 0 4 1 :v\r\n\
                source\u{2003}fixture\n\
                const 0 str \"space\\034quote\\034 é\u{2003}end\"\n\
                K 1 0\nRet 1\nend\nmodule fixture 0 fixture.nupp\nentry 0\n";
    let mut vm = Interp::new();
    vm.heap.stress = true;
    vm.heap.stress_steps = true;
    vm.heap.oracle = true;
    vm.heap.quarantine = true;
    let entry = image::load(&mut vm, text).unwrap();
    assert_eq!(vm.funcs.len(), 1);
    assert_eq!(vm.funcs[0].module, "fixture");
    assert_eq!(vm.modules["fixture"], entry);
    assert_eq!(vm.heap.shapes[0].names.len(), 1);
    vm.full_cycle();
    let result = vm.call_value(Value::func(entry), &[])[0];
    assert_eq!(
        vm.bytes_of(result),
        "space\"quote\" é\u{2003}end".as_bytes()
    );
    vm.check_oracle();
}

#[test]
fn malformed_image_messages_keep_their_original_lines() {
    for (text, expected) in [
        ("shape 0 Bad broken\n", "line 0: slot"),
        ("table 0 0\n", "line 0: table outside a function"),
        ("module missing nope\n", "line 0: module chunk"),
        ("source orphan\n", "line 0: source outside a function"),
        ("Ret 0\n", "line 0: op outside a function"),
        (
            "function f 0 0 2 1 :v\nBogus\n",
            "line 1: unknown opcode Bogus",
        ),
        ("\n\nsource orphan\n", "line 2: source outside a function"),
    ] {
        let mut vm = Interp::new();
        assert_eq!(image::load(&mut vm, text).unwrap_err(), expected);
        assert!(vm.funcs.is_empty());
    }
}
