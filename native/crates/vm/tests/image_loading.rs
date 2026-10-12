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
        let module = it.require("nupp.io.files");
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
    assert_eq!(it.call_value(get, &[]), vec![Value::num(std::process::id() as f64)]);
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
