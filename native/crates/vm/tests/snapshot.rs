//! `nupp.snapshot` under collector stress: standard-provider restoration and
//! refusal, transactional restores, and durable saves in a scratch VM.
use nupp_vm::{
    heap::SlotTy,
    image,
    interp::Interp,
    persist::{self, Policies, ResourceCodecs},
    value::Value,
};

const PROGRAM: &str = r#"
function entry 0 1 12 2 :v
const 0 num 7
K 2 0
Ret 2
end
entry 0
module demo 0
"#;

fn fixture() -> Interp {
    let mut vm = Interp::new();
    image::load(&mut vm, PROGRAM).unwrap();
    vm.install_globals();
    vm.entries.resize(vm.funcs.len(), 0);
    vm.prepare_threaded();
    stress(&mut vm);
    vm
}
fn stress(vm: &mut Interp) {
    vm.heap.stress_steps = true;
    vm.heap.oracle = true;
    vm.heap.quarantine = true;
}
fn get(vm: &mut Interp, object: Value, name: &str) -> Value {
    let key = vm.intern(name);
    vm.get_index(object, key)
}
fn put(vm: &mut Interp, object: Value, name: &str, value: Value) {
    let key = vm.intern(name);
    vm.set_index(object, key, value);
}
/// Calls a builtin by name with string, number or nil arguments, rooting each
/// argument before the next is allocated, and keeps its results rooted.
enum Arg<'a> {
    S(&'a str),
    N(f64),
    V(Value),
    Nil,
}
fn call(vm: &mut Interp, name: &str, args: &[Arg]) -> Vec<Value> {
    let (ok, values) = pcall(vm, name, args);
    if !ok {
        panic!("{name} failed: {}", String::from_utf8_lossy(vm.bytes_of(values[0])));
    }
    values
}
fn pcall(vm: &mut Interp, name: &str, args: &[Arg]) -> (bool, Vec<Value>) {
    let mut values = Vec::new();
    for a in args {
        let v = match a {
            Arg::S(s) => vm.new_string_bytes(s.as_bytes()),
            Arg::N(n) => Value::num(*n),
            Arg::V(v) => *v,
            Arg::Nil => Value::NIL,
        };
        vm.register(v);
        values.push(v);
    }
    let id = nupp_vm::builtins::id_of(name).unwrap();
    let out = vm.pcall_values(Value::builtin(id), &values);
    for &v in &out {
        vm.register(v);
    }
    (out[0] == Value::TRUE, out[1..].to_vec())
}
fn message(vm: &Interp, values: &[Value]) -> String {
    String::from_utf8_lossy(vm.bytes_of(values[0])).into_owned()
}
fn text(vm: &Interp, v: Value) -> String {
    String::from_utf8_lossy(vm.bytes_of(v)).into_owned()
}
fn checkpoint(vm: &mut Interp) -> Result<Vec<u8>, String> {
    persist::save_vm(vm, &Policies::default(), &mut ResourceCodecs::new())
}
fn restore(bytes: &[u8]) -> Result<Interp, String> {
    let mut vm = persist::load_vm(bytes, &Policies::default(), &mut ResourceCodecs::new())?;
    stress(&mut vm);
    Ok(vm)
}
fn scratch_file(name: &str, contents: &[u8]) -> std::path::PathBuf {
    let dir = std::env::temp_dir().join(format!("nupp-snapshot-test-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let path = dir.join(name);
    std::fs::write(&path, contents).unwrap();
    path
}
fn open(vm: &mut Interp, path: &std::path::Path, mode: &str) -> f64 {
    let out = call(vm, "nfiles.open", &[Arg::S(path.to_str().unwrap()), Arg::S(mode)]);
    assert!(out[0].is_num(), "open failed: {}", message(vm, &out[1..]));
    out[0].as_num()
}
fn read(vm: &mut Interp, handle: f64, count: f64) -> String {
    let out = call(vm, "nfiles.fileRead", &[Arg::N(handle), Arg::N(count)]);
    text(vm, out[0])
}

#[test]
fn read_only_files_reopen_at_their_offset_after_verification() {
    let path = scratch_file("assets.bin", b"abcdefgh");
    let mut vm = fixture();
    let handle = open(&mut vm, &path, "r");
    assert_eq!(read(&mut vm, handle, 3.0), "abc");
    let bytes = checkpoint(&mut vm).unwrap();
    // The capture's VM keeps reading on its own handle.
    assert_eq!(read(&mut vm, handle, 2.0), "de");
    let mut restored = restore(&bytes).unwrap();
    assert_eq!(read(&mut restored, handle, 3.0), "def");
    // A handle opened after the restore never reuses a restored number.
    let other = open(&mut restored, &path, "r");
    assert!(other > handle);
    restored.full_cycle();
    restored.check_oracle();

    // Changed and missing assets are refused at restore, naming the file.
    std::fs::write(&path, b"abcdefgX").unwrap();
    let error = restore(&bytes).err().unwrap();
    assert!(error.contains("contents changed") && error.contains("assets.bin"), "{error}");
    std::fs::remove_file(&path).unwrap();
    let error = restore(&bytes).err().unwrap();
    assert!(error.contains("assets.bin"), "{error}");
}

#[test]
fn writable_files_need_an_explicit_strategy_and_never_truncate() {
    let path = scratch_file("journal.txt", b"");
    let mut vm = fixture();
    let handle = open(&mut vm, &path, "w");
    call(&mut vm, "nfiles.fileWrite", &[Arg::N(handle), Arg::S("first ")]);
    let error = checkpoint(&mut vm).unwrap_err();
    assert!(error.contains("open for writing") && error.contains("journal.txt"), "{error}");

    // Reopen: whatever the file holds, at the saved offset, never truncated.
    call(&mut vm, "snapshot.fileStrategy", &[Arg::S(path.to_str().unwrap()), Arg::S("reopen")]);
    let bytes = checkpoint(&mut vm).unwrap();
    call(&mut vm, "nfiles.fileWrite", &[Arg::N(handle), Arg::S("second")]);
    let mut restored = restore(&bytes).unwrap();
    assert_eq!(std::fs::read(&path).unwrap(), b"first second");
    call(&mut restored, "nfiles.fileWrite", &[Arg::N(handle), Arg::S("again!")]);
    assert_eq!(std::fs::read(&path).unwrap(), b"first again!");
    // The strategy is VM state: the restored VM captures the file again.
    checkpoint(&mut restored).unwrap();

    // Verify: a restore after further writes is refused.
    call(&mut vm, "snapshot.fileStrategy", &[Arg::S(path.to_str().unwrap()), Arg::S("verify")]);
    let bytes = checkpoint(&mut vm).unwrap();
    restore(&bytes).unwrap();
    call(&mut vm, "nfiles.fileWrite", &[Arg::N(handle), Arg::S("more")]);
    let error = restore(&bytes).err().unwrap();
    assert!(error.contains("contents changed"), "{error}");

    // A VM-wide default covers writable files with no strategy of their own.
    let log = scratch_file("log.txt", b"");
    let appending = open(&mut vm, &log, "a");
    assert!(checkpoint(&mut vm).unwrap_err().contains("log.txt"));
    call(&mut vm, "snapshot.fileStrategy", &[Arg::Nil, Arg::S("reopen")]);
    let bytes = checkpoint(&mut vm).unwrap();
    let mut restored = restore(&bytes).unwrap();
    call(&mut restored, "nfiles.fileWrite", &[Arg::N(appending), Arg::S("tail")]);
    assert_eq!(std::fs::read(&log).unwrap(), b"tail");
    let (ok, out) = pcall(&mut vm, "snapshot.fileStrategy", &[Arg::S(path.to_str().unwrap()), Arg::S("sometimes")]);
    assert!(!ok && message(&vm, &out).contains("refuse"));
}

#[test]
fn closed_handles_retire_the_sentinel() {
    let path = scratch_file("closed.txt", b"x");
    let mut vm = fixture();
    let before = checkpoint(&mut vm).unwrap();
    let handle = open(&mut vm, &path, "r");
    call(&mut vm, "nfiles.fileClose", &[Arg::N(handle)]);
    let after = checkpoint(&mut vm).unwrap();
    let restored = restore(&after).unwrap();
    assert!(restored.resources.values().all(|k| !k.starts_with("nupp.io.files")));
    assert!(!before.is_empty());

    // A strategy is VM state even while no file it names is open.
    let save = path.with_file_name("save.dat");
    call(&mut vm, "snapshot.fileStrategy", &[Arg::S(save.to_str().unwrap()), Arg::S("reopen")]);
    let bytes = checkpoint(&mut vm).unwrap();
    let mut restored = restore(&bytes).unwrap();
    open(&mut restored, &save, "w");
    checkpoint(&mut restored).unwrap();
    open(&mut vm, &save, "w");
    call(&mut vm, "snapshot.fileStrategy", &[Arg::S(save.to_str().unwrap()), Arg::Nil]);
    assert!(checkpoint(&mut vm).unwrap_err().contains("save.dat"));
}

#[test]
fn sockets_and_native_streams_are_refused_with_counts() {
    let mut vm = fixture();
    let listener = call(&mut vm, "nnet.listen", &[Arg::S("127.0.0.1"), Arg::N(0.0), Arg::N(4.0), Arg::V(Value::FALSE)]);
    assert!(listener[0].is_num(), "listen failed");
    let error = checkpoint(&mut vm).unwrap_err();
    assert!(error.contains("1 network listener") && error.contains("nupp.net.handles"), "{error}");
    call(&mut vm, "nnet.closeListener", &[Arg::V(listener[0])]);
    checkpoint(&mut vm).unwrap();

    // A refusal that is a registered resource kind is refused by graph saves too.
    let path = scratch_file("io-open.txt", b"");
    let file = call(&mut vm, "io.open", &[Arg::S(path.to_str().unwrap()), Arg::S("w")]);
    let holder = vm.new_table();
    vm.register(holder);
    put(&mut vm, holder, "file", file[0]);
    let (ok, out) = pcall(&mut vm, "snapshot.save", &[Arg::V(holder)]);
    assert!(!ok && message(&vm, &out).contains("io.open handle"), "{}", message(&vm, &out));
    assert!(checkpoint(&mut vm).unwrap_err().contains("nupp.io.file"));
}

#[test]
fn restores_are_transactions() {
    let mut vm = fixture();
    let x = vm.intern("x");
    vm.register(x);
    let thing = vm.intern("thing");
    vm.register(thing);
    let shape = vm.heap.shape("Holder", &[x, thing], &[SlotTy::Num, SlotTy::Any]);
    let source = vm.new_record(shape);
    vm.register(source);
    vm.set_slot(source, 0, Value::num(5.0));
    let resource = vm.new_table();
    vm.register(resource);
    vm.set_slot(source, 1, resource);
    call(&mut vm, "snapshot.track", &[Arg::V(resource), Arg::S("game.thing")]);
    // Builtins stand in for Nupp callbacks: tostring captures, rawequal
    // restores without effect, error fails a restore.
    let resources = |vm: &mut Interp, restore: &str| {
        let list = vm.new_table();
        vm.register(list);
        let entry = vm.new_table();
        vm.register(entry);
        vm.set_index(list, Value::num(1.0), entry);
        let kind = vm.intern("game.thing");
        vm.register(kind);
        put(vm, entry, "kind", kind);
        put(vm, entry, "capture", Value::builtin(nupp_vm::builtins::id_of("tostring").unwrap()));
        put(vm, entry, "restore", Value::builtin(nupp_vm::builtins::id_of(restore).unwrap()));
        list
    };
    let good = resources(&mut vm, "rawequal");
    let bad = resources(&mut vm, "error");
    let saved = call(&mut vm, "snapshot.save", &[Arg::V(source), Arg::Nil, Arg::V(good)])[0];
    let described = vm.call_value(Value::builtin(nupp_vm::builtins::id_of("tostring").unwrap()), &[resource])[0];
    let descriptor = text(&vm, described);
    assert!(text(&vm, saved).len() > descriptor.len());
    // Without a registration the save names the kind.
    let (ok, out) = pcall(&mut vm, "snapshot.save", &[Arg::V(source)]);
    assert!(!ok && message(&vm, &out).contains("game.thing"));

    let tracked = |vm: &Interp| vm.resources.values().filter(|k| *k == "game.thing").count();
    let out = call(&mut vm, "snapshot.prepare", &[Arg::V(saved), Arg::Nil, Arg::Nil, Arg::V(good)]);
    let (root, staged) = (out[0], out[1]);
    assert_eq!(vm.array_len(staged), 1);
    let placeholder = vm.get_index(staged, Value::num(1.0));
    assert_eq!(vm.get_slot(root, 1), placeholder);
    assert_eq!(tracked(&vm), 2);

    // A failing restore discards what it staged and leaves the target alone.
    let target = vm.new_record(shape);
    vm.register(target);
    vm.set_slot(target, 0, Value::num(1.0));
    let before = vm.new_table();
    vm.register(before);
    vm.set_slot(target, 1, before);
    let (ok, out) = pcall(&mut vm, "snapshot.loadInto", &[Arg::V(saved), Arg::V(target), Arg::Nil, Arg::V(bad)]);
    assert!(!ok && message(&vm, &out).contains("restore of game.thing"), "{}", message(&vm, &out));
    assert_eq!(vm.get_slot(target, 0), Value::num(1.0));
    assert_eq!(vm.get_slot(target, 1), before);
    assert_eq!(tracked(&vm), 2);
    vm.full_cycle();
    vm.check_oracle();

    // The same restore with a working resource replaces the target in place.
    let out = call(&mut vm, "snapshot.loadInto", &[Arg::V(saved), Arg::V(target), Arg::Nil, Arg::V(good)]);
    assert_eq!(out[0], target);
    assert_eq!(vm.get_slot(target, 0), Value::num(5.0));
    assert_ne!(vm.get_slot(target, 1), before);
    assert_eq!(tracked(&vm), 3);
    vm.full_cycle();
    vm.check_oracle();
}

#[test]
fn durable_saves_are_plain_data_envelopes() {
    let mut vm = fixture();
    let state = vm.new_table();
    vm.register(state);
    put(&mut vm, state, "score", Value::num(42.0));
    put(&mut vm, state, "self", state);
    let options = vm.new_table();
    vm.register(options);
    let application = vm.intern("demo.game");
    vm.register(application);
    put(&mut vm, options, "application", application);
    put(&mut vm, options, "version", Value::num(3.0));
    let saved = call(&mut vm, "snapshot.durable", &[Arg::V(state), Arg::V(options)])[0];
    let bytes = vm.bytes_of(saved).to_vec();
    let envelope = persist::load_data(&mut vm, &bytes).unwrap();
    vm.register(envelope);
    let format = get(&mut vm, envelope, "format");
    assert_eq!(text(&vm, format), "nupp.snapshot.durable");
    assert_eq!(get(&mut vm, envelope, "version"), Value::num(3.0));
    let root = get(&mut vm, envelope, "root");
    let graph = vm.bytes_of(root).to_vec();
    let loaded = persist::load_graph(&mut vm, &graph, &Policies::default(), None).unwrap()[0];
    vm.register(loaded);
    assert_eq!(get(&mut vm, loaded, "score"), Value::num(42.0));
    assert_eq!(get(&mut vm, loaded, "self"), loaded);
    // The live value was copied, never touched.
    assert_eq!(get(&mut vm, state, "self"), state);

    let wide_version = nupp_vm::numeric::signed(&mut vm, 9007199254740993);
    put(&mut vm, options, "version", wide_version);
    let saved = call(&mut vm, "snapshot.durable", &[Arg::V(state), Arg::V(options)])[0];
    let bytes = vm.bytes_of(saved).to_vec();
    let envelope = persist::load_data(&mut vm, &bytes).unwrap();
    vm.register(envelope);
    let version = get(&mut vm, envelope, "version");
    assert_eq!(nupp_vm::numeric::integer(version).unwrap().bits, 9007199254740993);

    // Functions bind a save to one build; a durable save refuses them.
    put(&mut vm, state, "behavior", Value::builtin(nupp_vm::builtins::id_of("print").unwrap()));
    let closure = vm.new_closure(0, &[]);
    put(&mut vm, state, "behavior", closure);
    let (ok, out) = pcall(&mut vm, "snapshot.durable", &[Arg::V(state), Arg::V(options)]);
    assert!(!ok && message(&vm, &out).contains("functions"), "{}", message(&vm, &out));
    put(&mut vm, state, "behavior", Value::NIL);
    put(&mut vm, options, "version", Value::num(1.5));
    let (ok, out) = pcall(&mut vm, "snapshot.durable", &[Arg::V(state), Arg::V(options)]);
    assert!(!ok && message(&vm, &out).contains("whole number"));
    vm.full_cycle();
    vm.check_oracle();
}
