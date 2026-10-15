//! Weak tables: a metatable's `__mode` lets the collector drop entries whose
//! weak side is otherwise unreachable, as Lua 5.1 and LuaJIT do. Strings and
//! numbers are values and never leave a weak table.
use nupp_vm::{image, interp::Interp, scheduler::Status, value::Value};

fn vm(stress: bool) -> Box<Interp> {
    let mut vm = Box::new(Interp::new());
    vm.install_globals();
    vm.heap.stress = stress;
    vm.heap.oracle = stress;
    vm.heap.quarantine = stress;
    vm
}

/// A rooted table whose metatable declares `mode`.
fn weak_table(vm: &mut Interp, mode: &str) -> Value {
    let t = vm.new_table();
    vm.register(t);
    let meta = vm.new_table();
    let held = vm.register(meta);
    let key = vm.intern("__mode");
    vm.register(key);
    let text = vm.intern(mode);
    vm.set_index(meta, key, text);
    vm.set_metatable(t, meta);
    vm.release(held);
    t
}

fn entries(t: Value) -> usize {
    let table = unsafe { (*t.as_obj().unwrap().as_ptr()).table_ref() };
    table.array.iter().filter(|v| **v != Value::NIL).count() + table.hash.iter().count()
}

fn run(stress: bool) {
    let mut vm = vm(stress);
    let keys = weak_table(&mut vm, "k");
    let values = weak_table(&mut vm, "v");
    let both = weak_table(&mut vm, "kv");
    let strong = vm.new_table();
    vm.register(strong);

    // A key held elsewhere stays; an unreferenced key goes. The values of a
    // weak-keyed table are strong, so a value object survives with its key.
    let kept = vm.new_table();
    vm.register(kept);
    let dropped = vm.new_table();
    let held = vm.register(dropped);
    let value = vm.new_table();
    let held_value = vm.register(value);
    vm.set_index(keys, kept, value);
    vm.set_index(keys, dropped, Value::TRUE);
    vm.release(held);
    vm.release(held_value);
    let text = vm.intern("a string key");
    vm.set_index(keys, text, Value::TRUE);

    // Weak values: objects go wherever they sit, strings and numbers stay.
    for i in 1..=4 {
        let v = vm.new_table();
        let h = vm.register(v);
        vm.set_index(values, Value::num(i as f64), v);
        vm.release(h);
    }
    vm.set_index(values, Value::num(5.0), kept);
    let name = vm.intern("name");
    vm.register(name);
    let object = vm.new_table();
    let h = vm.register(object);
    vm.set_index(values, name, object);
    vm.release(h);
    let other = vm.intern("other");
    vm.register(other);
    let s = vm.intern("a string value");
    vm.set_index(values, other, s);
    vm.set_index(values, Value::num(6.0), Value::num(42.0));

    // Both weak: either side dying drops the entry.
    let k = vm.new_table();
    let h = vm.register(k);
    vm.set_index(both, k, Value::num(1.0));
    vm.release(h);
    let v = vm.new_table();
    let h = vm.register(v);
    vm.set_index(both, Value::num(2.0), v);
    vm.release(h);
    vm.set_index(both, kept, kept);

    // A table without a mode keeps everything.
    let v = vm.new_table();
    let h = vm.register(v);
    vm.set_index(strong, Value::num(1.0), v);
    vm.release(h);

    vm.full_cycle();
    vm.full_cycle();

    assert_eq!(vm.get_index(keys, kept), value, "a held key lost its entry");
    assert_eq!(vm.get_index(keys, text), Value::TRUE, "a string key was cleared");
    assert_eq!(entries(keys), 2);

    for i in 1..=4 {
        assert_eq!(vm.get_index(values, Value::num(i as f64)), Value::NIL, "weak value {i} survived");
    }
    assert_eq!(vm.get_index(values, Value::num(5.0)), kept);
    assert_eq!(vm.get_index(values, name), Value::NIL);
    assert_eq!(vm.get_index(values, other), s);
    assert_eq!(vm.get_index(values, Value::num(6.0)), Value::num(42.0));

    assert_eq!(vm.get_index(both, Value::num(2.0)), Value::NIL);
    assert_eq!(vm.get_index(both, kept), kept);
    assert_eq!(entries(both), 1);

    assert_ne!(vm.get_index(strong, Value::num(1.0)), Value::NIL);

    // A cleared key's entry stays usable: storing a new key works and
    // iteration skips what was cleared.
    let fresh = vm.new_table();
    vm.register(fresh);
    vm.set_index(keys, fresh, Value::num(7.0));
    assert_eq!(vm.get_index(keys, fresh), Value::num(7.0));
    assert_eq!(entries(keys), 3);
    vm.check_oracle();
}

#[test]
fn weak_entries_clear_after_a_full_collection() {
    run(false);
}

#[test]
fn weak_entries_clear_under_collector_stress() {
    run(true);
}

#[test]
fn incremental_cycles_clear_weak_entries() {
    let mut vm = vm(false);
    vm.heap.stress_steps = true;
    vm.heap.oracle = true;
    let keys = weak_table(&mut vm, "k");
    for i in 0..200 {
        let k = vm.new_table();
        let h = vm.register(k);
        vm.set_index(keys, k, Value::num(i as f64));
        vm.release(h);
    }
    vm.full_cycle();
    assert_eq!(entries(keys), 0);
}

// `collectgarbage("collect")` from bytecode: the key was only ever in a
// temporary register the function never reads again, which the explicit
// collection clears, so the entry goes as it does on LuaJIT.
const PROGRAM: &str = r#"
shape 0 struct:mode __mode:any
function main 0 0 12 1 :v
const 0 builtin setmetatable
const 1 str "__mode"
const 2 str "k"
const 3 builtin collectgarbage
const 4 builtin next
const 5 num 1
NewTable 1
NewTable 2
K 3 1
K 4 2
SetIdx 2 3 4
K 5 0
Move 6 1
Move 7 2
CallDyn 5 5 2
NewTable 8
K 9 5
SetIdx 1 8 9
K 10 3
CallDyn 10 10 0
K 10 4
Move 11 1
CallDyn 10 10 1
Ret 10
end
function recordMeta 1 0 12 1 :v
const 0 builtin setmetatable
const 1 str "__mode"
const 2 str "k"
const 3 builtin collectgarbage
const 4 builtin next
const 5 num 1
NewTable 1
NewRecord 2 0
K 3 1
K 4 2
SetIdx 2 3 4
K 5 0
Move 6 1
Move 7 2
CallDyn 5 5 2
NewTable 8
K 9 5
SetIdx 1 8 9
K 10 3
CallDyn 10 10 0
K 10 4
Move 11 1
CallDyn 10 10 1
Ret 10
end
entry 0
"#;

fn program(threaded: bool, scheduled: bool) -> Value {
    run_program(0, threaded, scheduled)
}

fn run_program(fid: u32, threaded: bool, scheduled: bool) -> Value {
    let mut vm = Box::new(Interp::new());
    image::load(&mut vm, PROGRAM).unwrap();
    vm.install_globals();
    vm.heap.stress = true;
    vm.heap.oracle = true;
    vm.heap.quarantine = true;
    if threaded {
        vm.prepare_threaded();
    }
    #[cfg(feature = "jit")]
    {
        vm.jit = None;
    }
    if scheduled {
        vm.enable_scheduler().unwrap();
        let task = vm.schedule(Value::func(fid), &[], None).unwrap();
        let events = vm.run_ready(1).unwrap();
        assert_eq!(events[0].status, Status::Completed);
        vm.tasks[task.index].result
    } else {
        vm.call_value(Value::func(fid), &[])[0]
    }
}

#[test]
fn explicit_collection_drops_keys_left_in_dead_registers() {
    assert_eq!(program(false, false), Value::NIL, "Rust loop");
    assert_eq!(program(true, false), Value::NIL, "threaded core");
    assert_eq!(program(false, true), Value::NIL, "scheduled frames");
}

// A metatable a constructor built as a record of its inferred shape names its
// mode in a slot.
#[test]
fn a_record_metatable_declares_a_weak_mode() {
    assert_eq!(run_program(1, false, false), Value::NIL);
    assert_eq!(run_program(1, false, true), Value::NIL);
}
