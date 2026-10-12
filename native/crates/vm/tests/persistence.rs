use nupp_vm::{
    heap::SlotTy,
    image,
    interp::{Interp, Outcome, State},
    persist::{self, Policies, ResourceCodec, ResourceCodecs, ShapePolicy},
    value::Value,
};
use std::collections::{HashMap, HashSet};

fn field(vm: &mut Interp, object: Value, name: &str, value: Value) {
    let key = vm.intern(name);
    vm.set_index(object, key, value);
}
fn get(vm: &mut Interp, object: Value, name: &str) -> Value {
    let key = vm.intern(name);
    vm.get_index(object, key)
}
fn record(vm: &mut Interp, name: &str) -> u32 {
    let x = vm.intern("x");
    let h = vm.register(x);
    let cache = vm.intern("cache");
    let id = vm
        .heap
        .shape(name, &[x, cache], &[SlotTy::Num, SlotTy::Any]);
    vm.release(h);
    id
}
fn fixture() -> Interp {
    let mut vm = Interp::new();
    image::load(&mut vm, PROGRAM).unwrap();
    vm.install_globals();
    vm.entries.resize(vm.funcs.len(), 0);
    vm.prepare_threaded();
    vm
}
const PROGRAM: &str = r#"
function entry 0 1 12 2 :v
const 0 num 7
K 2 0
Park 2
GetField 3 1 1
Ret 3
const 1 str "count"
end
function readcapture 1 0 8 2 :v
GetUpval 1 0
GetCell 2 1
Ret 2
end
entry 0
module demo 0
"#;

#[test]
fn graphs_preserve_all_kinds_cycles_identity_and_typed_spans() {
    let mut vm = fixture();
    vm.heap.stress_steps = true;
    vm.heap.oracle = true;
    vm.heap.quarantine = true;
    let table = vm.new_table();
    let handle = vm.register(table);
    field(&mut vm, table, "self", table);
    let text = vm.intern("slice source");
    let text_handle = vm.register(text);
    let slice = vm.new_slice(text, 6, 6);
    field(&mut vm, table, "slice", slice);
    let bytes = vm.heap_new_bytes(6);
    vm.bytes_mut(bytes).copy_from_slice(b"\0\xffGAME");
    field(&mut vm, table, "bytes", bytes);
    let storage = vm.new_storage(4);
    unsafe {
        (*storage.as_obj().unwrap().as_ptr())
            .storage()
            .data
            .copy_from_slice(&[1.0, -0.0, f64::INFINITY, 42.0]);
    }
    field(&mut vm, table, "storage", storage);
    let cell = vm.new_cell(table);
    let ch = vm.register(cell);
    let closure = vm.new_closure(1, &[cell]);
    field(&mut vm, table, "closure", closure);
    let key = vm.intern("self");
    let it = vm.new_iter_keys(1, table, vec![key]);
    field(&mut vm, table, "iterator", it);
    field(&mut vm, table, "alias", bytes);
    let meta = vm.new_table();
    field(&mut vm, table, "meta", meta);
    unsafe {
        (*table.as_obj().unwrap().as_ptr()).table().meta = meta;
    }
    vm.heap.barrier(table.as_obj().unwrap(), meta);
    let data = persist::save_graph(&mut vm, &[table], &Policies::default()).unwrap();
    let restored = persist::load_graph(&mut vm, &data, &Policies::default(), None).unwrap()[0];
    let rh = vm.register(restored);
    assert_ne!(table, restored);
    assert_eq!(get(&mut vm, restored, "self"), restored);
    assert_eq!(
        get(&mut vm, restored, "bytes"),
        get(&mut vm, restored, "alias")
    );
    let s = get(&mut vm, restored, "slice");
    assert_eq!(vm.bytes_of(s), b"source");
    let b = get(&mut vm, restored, "bytes");
    assert_eq!(vm.bytes_of(b), b"\0\xffGAME");
    let c = get(&mut vm, restored, "closure");
    assert_eq!(vm.call_value(c, &[]), vec![restored]);
    let i = get(&mut vm, restored, "iterator");
    assert_eq!(vm.call_value(i, &[])[1], restored);
    let st = get(&mut vm, restored, "storage");
    let numbers = unsafe { &(*st.as_obj().unwrap().as_ptr()).storage().data };
    assert_eq!(numbers[1].to_bits(), (-0.0f64).to_bits());
    assert_eq!(numbers[3], 42.0);
    vm.full_cycle();
    vm.check_oracle();
    for h in [rh, ch, text_handle, handle] {
        vm.release(h);
    }
}

fn rebuild_cache(vm: &mut Interp, v: Value) -> persist::Result<()> {
    field(vm, v, "cache", Value::num(99.0));
    Ok(())
}
#[test]
fn durable_shapes_transients_hooks_and_in_place_identity() {
    let mut source = Interp::new();
    let shape = record(&mut source, "old.Position");
    let v = source.new_record(shape);
    source.register(v);
    field(&mut source, v, "x", Value::num(12.0));
    field(&mut source, v, "cache", v);
    let mut policies = Policies::default();
    policies.shapes.insert(
        "old.Position".into(),
        ShapePolicy {
            name: Some("game.Position.v1".into()),
            transient: HashSet::from(["cache".into()]),
            ..Default::default()
        },
    );
    let data = persist::save_graph(&mut source, &[v], &policies).unwrap();
    let mut target = Interp::new();
    let sid = record(&mut target, "new.Position");
    let existing = target.new_record(sid);
    target.register(existing);
    let mut policies = Policies::default();
    policies.shapes.insert(
        "new.Position".into(),
        ShapePolicy {
            name: Some("game.Position.v1".into()),
            after_load: Some(rebuild_cache),
            ..Default::default()
        },
    );
    assert_eq!(
        persist::load_into(&mut target, &data, existing, &policies).unwrap(),
        existing
    );
    assert_eq!(get(&mut target, existing, "x"), Value::num(12.0));
    assert_eq!(get(&mut target, existing, "cache"), Value::num(99.0));
    target.heap.shapes[sid as usize].types[0] = SlotTy::Bool;
    assert!(
        persist::load_graph(&mut target, &data, &policies, None)
            .unwrap_err()
            .contains("schema changed")
    );
}

#[test]
fn reject_corruption_wrong_types_and_changed_code() {
    let mut vm = fixture();
    let value = vm.new_closure(1, &[Value::num(1.0)]);
    vm.register(value);
    let bytes = persist::save_graph(&mut vm, &[value], &Policies::default()).unwrap();
    for n in 0..bytes.len() {
        assert!(persist::load_graph(&mut vm, &bytes[..n], &Policies::default(), None).is_err());
    }
    let mut corrupt = bytes.clone();
    let last = corrupt.len() - 1;
    corrupt[last] ^= 1;
    assert!(
        persist::load_graph(&mut vm, &corrupt, &Policies::default(), None)
            .unwrap_err()
            .contains("checksum")
    );
    vm.funcs[1].name = "changed".into();
    assert!(
        persist::load_graph(&mut vm, &bytes, &Policies::default(), None)
            .unwrap_err()
            .contains("digest")
    );
    let mut vm = Interp::new();
    let sid = record(&mut vm, "Position");
    let r = vm.new_record(sid);
    vm.register(r);
    unsafe {
        (*r.as_obj().unwrap().as_ptr()).slots_mut()[0] = Value::FALSE;
    }
    let bytes = persist::save_graph(&mut vm, &[r], &Policies::default()).unwrap();
    assert!(
        persist::load_graph(
            &mut vm,
            &bytes,
            &Policies::default(),
            Some(SlotTy::Record(sid))
        )
        .unwrap_err()
        .contains("typed field")
    );
}

#[test]
fn checkpoint_parked_and_runnable_tasks_globals_and_handle_roots() {
    for threaded in [false, true] {
        let mut vm = fixture();
        vm.threaded = threaded;
        let shared = vm.new_table();
        vm.register(shared);
        field(&mut vm, shared, "count", Value::num(42.0));
        vm.loaded.insert("state".into(), shared);
        let a = vm.spawn(0, &[shared]);
        let b = vm.spawn(0, &[shared]);
        assert!(matches!(vm.run(a), Outcome::Parked(_)));
        let data =
            persist::save_vm(&mut vm, &Policies::default(), &mut ResourceCodecs::new()).unwrap();
        drop(vm);
        let mut vm =
            persist::load_vm(&data, &Policies::default(), &mut ResourceCodecs::new()).unwrap();
        vm.threaded = threaded;
        assert!(matches!(vm.tasks[a].state, State::Parked(_)));
        assert_eq!(vm.tasks[b].state, State::Runnable);
        assert!(vm.entries.iter().all(|&e| e == 0));
        let shared = vm.loaded["state"];
        field(&mut vm, shared, "count", Value::num(81.0));
        vm.resume(a);
        assert!(matches!(vm.run(a),Outcome::Done(v) if v==Value::num(81.0)));
        assert!(matches!(vm.run(b), Outcome::Parked(_)));
        vm.resume(b);
        assert!(matches!(vm.run(b),Outcome::Done(v) if v==Value::num(81.0)));
        vm.full_cycle();
        vm.check_oracle();
        // Completed tasks and all graph roots remain restorable too.
        let again =
            persist::save_vm(&mut vm, &Policies::default(), &mut ResourceCodecs::new()).unwrap();
        let restored =
            persist::load_vm(&again, &Policies::default(), &mut ResourceCodecs::new()).unwrap();
        assert_eq!(restored.tasks[a].result, Value::num(81.0));
    }
}

struct CounterCodec(std::sync::Arc<std::sync::Mutex<u64>>);
impl ResourceCodec for CounterCodec {
    fn save(&mut self, _: &Interp, _: Value) -> persist::Result<Vec<u8>> {
        Ok(self.0.lock().unwrap().to_le_bytes().to_vec())
    }
    fn restore(&mut self, _: &mut Interp, _: Value, data: &[u8]) -> persist::Result<()> {
        *self.0.lock().unwrap() =
            u64::from_le_bytes(data.try_into().map_err(|_| "counter length")?);
        Ok(())
    }
}
#[test]
fn extension_state_requires_and_uses_explicit_hooks() {
    let mut vm = fixture();
    let value = vm.new_table();
    vm.resources.insert(value, "game.counter.v1".into());
    vm.loaded.insert("counter".into(), value);
    assert!(
        persist::save_graph(&mut vm, &[value], &Policies::default())
            .unwrap_err()
            .contains("no save codec")
    );
    assert!(
        persist::save_vm(&mut vm, &Policies::default(), &mut ResourceCodecs::new())
            .unwrap_err()
            .contains("game.counter.v1")
    );
    let counter = std::sync::Arc::new(std::sync::Mutex::new(77));
    let mut codecs: ResourceCodecs = HashMap::from([(
        "game.counter.v1".into(),
        Box::new(CounterCodec(counter.clone())) as Box<dyn ResourceCodec>,
    )]);
    let bytes = persist::save_vm(&mut vm, &Policies::default(), &mut codecs).unwrap();
    *counter.lock().unwrap() = 0;
    drop(vm);
    let vm = persist::load_vm(&bytes, &Policies::default(), &mut codecs).unwrap();
    assert_eq!(*counter.lock().unwrap(), 77);
    assert_eq!(vm.resources[&vm.loaded["counter"]], "game.counter.v1");
    assert!(
        persist::load_vm(&bytes, &Policies::default(), &mut ResourceCodecs::new())
            .err()
            .unwrap()
            .contains("no restore codec")
    );
}

#[test]
fn pending_requests_are_not_silently_lost() {
    let mut vm = fixture();
    vm.host_waiters.insert(42, 0);
    assert!(
        persist::save_vm(&mut vm, &Policies::default(), &mut ResourceCodecs::new())
            .unwrap_err()
            .contains("pending host")
    );
}

// The child restores without access to the saving process's heap or native code.
#[test]
fn fresh_process_restore() {
    if let Ok(path) = std::env::var("NUPP_CHECKPOINT_CHILD") {
        let bytes = std::fs::read(path).unwrap();
        let mut vm =
            persist::load_vm(&bytes, &Policies::default(), &mut ResourceCodecs::new()).unwrap();
        vm.resume(0);
        assert!(matches!(vm.run(0),Outcome::Done(v) if v==Value::num(42.0)));
        return;
    }
    if let Ok(path) = std::env::var("NUPP_CHECKPOINT_WRITER") {
        let mut vm = fixture();
        let table = vm.new_table();
        vm.register(table);
        field(&mut vm, table, "count", Value::num(42.0));
        let tid = vm.spawn(0, &[table]);
        assert!(matches!(vm.run(tid), Outcome::Parked(_)));
        let data =
            persist::save_vm(&mut vm, &Policies::default(), &mut ResourceCodecs::new()).unwrap();
        std::fs::write(path, data).unwrap();
        return;
    }
    let path = std::env::temp_dir().join(format!("nupp-checkpoint-{}.bin", std::process::id()));
    // Wait for the saving process to exit before starting the restoring one.
    for stage in ["NUPP_CHECKPOINT_WRITER", "NUPP_CHECKPOINT_CHILD"] {
        assert!(
            std::process::Command::new(std::env::current_exe().unwrap())
                .args(["--exact", "fresh_process_restore", "--nocapture"])
                .env(stage, &path)
                .status()
                .unwrap()
                .success()
        );
    }
    std::fs::remove_file(path).unwrap();
}

struct Files(std::sync::Arc<std::sync::Mutex<HashMap<Value, (String, std::fs::File)>>>);
impl ResourceCodec for Files {
    fn save(&mut self, _: &Interp, object: Value) -> persist::Result<Vec<u8>> {
        use std::io::Seek;
        let mut files = self.0.lock().unwrap();
        let (path, file) = files.get_mut(&object).ok_or("unregistered file")?;
        let mut data = file
            .stream_position()
            .map_err(|e| e.to_string())?
            .to_le_bytes()
            .to_vec();
        data.extend(path.as_bytes());
        Ok(data)
    }
    fn restore(&mut self, _: &mut Interp, object: Value, data: &[u8]) -> persist::Result<()> {
        use std::io::{Seek, SeekFrom};
        let pos = u64::from_le_bytes(
            data.get(..8)
                .ok_or("file state truncated")?
                .try_into()
                .unwrap(),
        );
        let path = std::str::from_utf8(&data[8..])
            .map_err(|e| e.to_string())?
            .to_string();
        let mut file = std::fs::File::open(&path).map_err(|e| e.to_string())?;
        file.seek(SeekFrom::Start(pos)).map_err(|e| e.to_string())?;
        self.0.lock().unwrap().insert(object, (path, file));
        Ok(())
    }
}
#[test]
fn fresh_process_reopens_file_with_position_and_identity() {
    use std::io::{Read, Seek, SeekFrom};
    let files = std::sync::Arc::new(std::sync::Mutex::new(HashMap::new()));
    let mut codecs: ResourceCodecs = HashMap::from([(
        "test.file.v1".into(),
        Box::new(Files(files.clone())) as Box<dyn ResourceCodec>,
    )]);
    if let Ok(path) = std::env::var("NUPP_FILE_CHECKPOINT_CHILD") {
        let mut vm = persist::load_vm(
            &std::fs::read(path).unwrap(),
            &Policies::default(),
            &mut codecs,
        )
        .unwrap();
        let value = vm.loaded["file"];
        let mut remaining = String::new();
        files
            .lock()
            .unwrap()
            .get_mut(&value)
            .unwrap()
            .1
            .read_to_string(&mut remaining)
            .unwrap();
        assert_eq!(remaining, "remaining");
        vm.resume(0);
        assert!(matches!(vm.run(0),Outcome::Done(v) if v==value));
        return;
    }
    if let Ok(base) = std::env::var("NUPP_FILE_CHECKPOINT_WRITER") {
        let base = std::path::PathBuf::from(base);
        let mut vm = fixture();
        let file_value = vm.new_table();
        vm.resources.insert(file_value, "test.file.v1".into());
        vm.loaded.insert("file".into(), file_value);
        let source = base.with_extension("txt");
        let snapshot = base.with_extension("bin");
        std::fs::write(&source, "read remaining").unwrap();
        let mut file = std::fs::File::open(&source).unwrap();
        file.seek(SeekFrom::Start(5)).unwrap();
        files
            .lock()
            .unwrap()
            .insert(file_value, (source.to_string_lossy().into_owned(), file));
        let table = vm.new_table();
        vm.register(table);
        field(&mut vm, table, "count", file_value);
        let tid = vm.spawn(0, &[table]);
        assert!(matches!(vm.run(tid), Outcome::Parked(_)));
        std::fs::write(
            &snapshot,
            persist::save_vm(&mut vm, &Policies::default(), &mut codecs).unwrap(),
        )
        .unwrap();
        return;
    }
    let base = std::env::temp_dir().join(format!("nupp-file-checkpoint-{}", std::process::id()));
    for (stage, path) in [
        ("NUPP_FILE_CHECKPOINT_WRITER", base.clone()),
        ("NUPP_FILE_CHECKPOINT_CHILD", base.with_extension("bin")),
    ] {
        assert!(
            std::process::Command::new(std::env::current_exe().unwrap())
                .args([
                    "--exact",
                    "fresh_process_reopens_file_with_position_and_identity",
                    "--nocapture"
                ])
                .env(stage, path)
                .status()
                .unwrap()
                .success()
        );
    }
    std::fs::remove_file(base.with_extension("txt")).unwrap();
    std::fs::remove_file(base.with_extension("bin")).unwrap();
}

#[test]
fn nested_typed_frames_varargs_and_cycles_restore() {
    let source = r#"
function outer 0 1 16 2 :v
const 0 num 99
K 2 0
Call 1 0 2
Ret 0
end
function inner 1 1 16 2 :v vararg
const 0 num 1
K 2 0
FUnbox 0 2
IK 0 17
Park 2
VarargN 3 1
FBox 4 0
Add 3 3 4
Ret 3
end
entry 0
"#;
    for threaded in [false, true] {
        let mut vm = Interp::new();
        image::load(&mut vm, source).unwrap();
        vm.entries.resize(vm.funcs.len(), 0);
        if threaded {
            vm.prepare_threaded();
        }
        let t = vm.spawn(0, &[Value::num(7.0)]);
        assert!(matches!(vm.run(t), Outcome::Parked(_)));
        let bytes =
            persist::save_vm(&mut vm, &Policies::default(), &mut ResourceCodecs::new()).unwrap();
        let mut restored =
            persist::load_vm(&bytes, &Policies::default(), &mut ResourceCodecs::new()).unwrap();
        restored.threaded = threaded;
        restored.resume(t);
        assert!(matches!(restored.run(t),Outcome::Done(v) if v==Value::num(100.0)));
    }
}

#[test]
fn structurally_corrupt_graphs_never_panic() {
    let mut vm = Interp::new();
    let table = vm.new_table();
    vm.register(table);
    let data = vm.intern("abcdef");
    field(&mut vm, table, "text", data);
    field(&mut vm, table, "self", table);
    let valid = persist::save_graph(&mut vm, &[table], &Policies::default()).unwrap();
    for at in 21..valid.len() {
        let mut bytes = valid.clone();
        bytes[at] ^= 0xff;
        let hash = crc32fast::hash(&bytes[21..]);
        bytes[17..21].copy_from_slice(&hash.to_le_bytes());
        let answer = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            persist::load_graph(&mut vm, &bytes, &Policies::default(), None)
        }));
        assert!(answer.is_ok(), "panicked at byte {at}");
        vm.full_cycle();
    }
}

#[test]
fn runtime_module_saves_and_loads_values() {
    let mut vm = fixture();
    let module = vm.require("nupp.vm.persist");
    let save = get(&mut vm, module, "save");
    let load = get(&mut vm, module, "load");
    let source = vm.new_table();
    vm.register(source);
    field(&mut vm, source, "same", source);
    let bytes = vm.call_value(save, &[source])[0];
    vm.register(bytes);
    let restored = vm.call_value(load, &[bytes])[0];
    vm.register(restored);
    assert_eq!(get(&mut vm, restored, "same"), restored);
}

#[test]
fn plain_graph_does_not_require_unused_program_shapes() {
    let mut source = Interp::new();
    record(&mut source, "unused.Shape");
    let value = source.new_table();
    source.register(value);
    field(&mut source, value, "answer", Value::num(42.0));
    let bytes = persist::save_graph(&mut source, &[value], &Policies::default()).unwrap();
    let mut target = Interp::new();
    let restored = persist::load_graph(&mut target, &bytes, &Policies::default(), None).unwrap()[0];
    target.register(restored);
    assert_eq!(get(&mut target, restored, "answer"), Value::num(42.0));
}

#[cfg(feature = "jit")]
#[test]
fn checkpoint_discards_actual_jit_entries() {
    let mut vm = fixture();
    let mut jit = nupp_vm::jit::Jit::new();
    jit.extra_addr = &vm.extra as *const _ as i64;
    jit.last_nres_addr = &vm.last_nres as *const _ as i64;
    jit.entries_addr = vm.entries.as_ptr() as i64;
    let entry = jit.try_compile(&vm.funcs[1], 1).unwrap();
    vm.entries[1] = entry as u64;
    let cell = vm.new_cell(Value::num(55.0));
    let h = vm.register(cell);
    let closure = vm.new_closure(1, &[cell]);
    vm.loaded.insert("answer".into(), closure);
    vm.register(closure);
    vm.release(h);
    let bytes =
        persist::save_vm(&mut vm, &Policies::default(), &mut ResourceCodecs::new()).unwrap();
    drop(vm);
    drop(jit);
    let mut restored =
        persist::load_vm(&bytes, &Policies::default(), &mut ResourceCodecs::new()).unwrap();
    assert!(restored.entries.iter().all(|&v| v == 0));
    let answer = restored.loaded["answer"];
    assert_eq!(restored.call_value(answer, &[]), vec![Value::num(55.0)]);
}

#[test]
fn mutation_barriers_hold_during_stress_restore() {
    let mut vm = fixture();
    vm.heap.stress = true;
    vm.heap.oracle = true;
    vm.heap.quarantine = true;
    let root = vm.new_table();
    vm.register(root);
    for _ in 0..64 {
        let cell = vm.new_cell(root);
        vm.push_array(root, cell);
    }
    let bytes = persist::save_graph(&mut vm, &[root], &Policies::default()).unwrap();
    let restored = persist::load_graph(&mut vm, &bytes, &Policies::default(), None).unwrap()[0];
    vm.register(restored);
    vm.full_cycle();
    vm.check_oracle();
    let bytes =
        persist::save_vm(&mut vm, &Policies::default(), &mut ResourceCodecs::new()).unwrap();
    let mut restored =
        persist::load_vm(&bytes, &Policies::default(), &mut ResourceCodecs::new()).unwrap();
    restored.full_cycle();
    restored.check_oracle();
}

#[test]
fn binary_interned_strings_and_record_metatables_round_trip() {
    let mut vm = Interp::new();
    vm.heap.stress = true;
    vm.heap.oracle = true;
    let table = vm.new_table();
    vm.register(table);
    let bytes = [0, 0xff, 0x80, b'a'];
    let key = vm.string_of(&bytes);
    vm.register(key);
    vm.set_index(table, key, Value::num(7.0));
    let raw = vm.new_string_bytes(&bytes);
    vm.register(raw);
    assert_eq!(vm.index_any(table, raw), Value::num(7.0));
    assert_eq!(vm.string_of(&bytes), key);
    let sid = record(&mut vm, "Meta");
    let meta = vm.new_record(sid);
    vm.register(meta);
    field(&mut vm, meta, "x", Value::num(1.0));
    unsafe {
        (*table.as_obj().unwrap().as_ptr()).table().meta = meta;
    }
    vm.heap.barrier(table.as_obj().unwrap(), meta);
    let encoded = persist::save_graph(&mut vm, &[table], &Policies::default()).unwrap();
    let restored = persist::load_graph(&mut vm, &encoded, &Policies::default(), None).unwrap()[0];
    vm.register(restored);
    assert_eq!(vm.get_index(restored, key), Value::num(7.0));
    assert_eq!(
        vm.kind_of(vm.metatable_of(restored)),
        Some(nupp_vm::heap::KIND_RECORD)
    );
    vm.full_cycle();
    vm.check_oracle();
}

#[test]
fn idle_host_pool_resumes_serving_after_restore() {
    let mut vm = fixture();
    vm.host = Some(nupp_vm::host::Host::start(1));
    let key = vm
        .host
        .as_mut()
        .unwrap()
        .submit(nupp_vm::host::Req::Sleep(0));
    assert_eq!(vm.host.as_mut().unwrap().wait().unwrap().0, key);
    let bytes =
        persist::save_vm(&mut vm, &Policies::default(), &mut ResourceCodecs::new()).unwrap();
    drop(vm);
    let mut restored =
        persist::load_vm(&bytes, &Policies::default(), &mut ResourceCodecs::new()).unwrap();
    let next = restored
        .host
        .as_mut()
        .unwrap()
        .submit(nupp_vm::host::Req::Sleep(0));
    assert!(next > key);
    assert_eq!(restored.host.as_mut().unwrap().wait().unwrap().0, next);
}

#[test]
fn native_payload_capacity_accounting_survives_repeated_load_and_collection() {
    let mut vm = Interp::new();
    for _ in 0..20 {
        let table = vm.new_table();
        let handle = vm.register(table);
        for i in 0..200 {
            vm.push_array(table, Value::num(i as f64));
            let key = vm.intern(&format!("field{i}"));
            vm.set_index(table, key, Value::num(i as f64));
        }
        let buffer = vm.heap_new_buffer();
        let h = vm.register(buffer);
        vm.buf_append(buffer, &vec![0xab; 16384]);
        let text = vm.buf_finish(buffer);
        vm.push_array(table, text);
        vm.release(h);
        let key = vm.intern("field0");
        let iterator = vm.new_iter_keys(1, table, vec![key]);
        vm.push_array(table, iterator);
        let data = persist::save_graph(&mut vm, &[table], &Policies::default()).unwrap();
        let _ = persist::load_graph(&mut vm, &data, &Policies::default(), None).unwrap();
        vm.release(handle);
        vm.full_cycle();
        assert_eq!(vm.heap.object_count(), 0);
        assert_eq!(vm.heap.live_bytes, 0);
    }
}
