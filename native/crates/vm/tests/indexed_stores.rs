use nupp_vm::{builtins, image, interp::Interp, numeric::Integer, value::Value};
use std::sync::Mutex;

static SERIAL: Mutex<()> = Mutex::new(());

#[derive(Clone, Copy, Debug)]
enum Mode {
    Interpreter,
    Threaded,
    #[cfg(feature = "compiled-runtime")]
    Helper,
    #[cfg(feature = "jit")]
    Ordinary,
    #[cfg(feature = "jit")]
    Frame,
}
fn modes() -> Vec<Mode> {
    let modes = vec![Mode::Interpreter, Mode::Threaded];
    #[cfg(feature = "compiled-runtime")]
    let modes = {
        let mut modes = modes;
        modes.push(Mode::Helper);
        modes
    };
    #[cfg(feature = "jit")]
    let modes = {
        let mut modes = modes;
        modes.extend([Mode::Ordinary, Mode::Frame]);
        modes
    };
    modes
}
fn source(op: &str) -> String {
    let store = match op {
        "SetIdx" => "SetIdx 1 2 3",
        "SetIdxF" => "FUnbox 0 2\nSetIdxF 1 0 3",
        "SetIdxI" => "IUnbox 0 2\nSetIdxI 1 0 3",
        _ => unreachable!(),
    };
    format!(
        r#"
shape 0 Shared present:any
function store 0 3 8 2 vvv:v
{store}
Ret 1
end
function declare 1 0 8 1 :v
const 0 str "\000nupp:recordType"
NewTable 1
SetMethod 0 0 1
NewRecord 2 0
RetN 1 2
end
function intercept 2 3 20 1 vvv:v
const 0 str "seenKey"
const 1 str "seenValue"
const 2 builtin rawset
const 3 builtin collectgarbage
const 4 func 3
K 15 3
CallDyn 15 10 0
K 15 2
Move 11 1
K 12 0
Move 13 2
CallDyn 15 10 3
K 15 2
Move 11 1
K 12 1
Move 13 3
CallDyn 15 10 3
K 15 4
Move 11 1
CallDyn 15 10 1
RetNil
end
function reenter 3 1 12 1 v:v
const 0 str "reentered"
const 1 builtin rawset
const 2 num 19
K 9 1
Move 5 1
K 6 0
K 7 2
CallDyn 9 4 3
RetNil
end
function refuse 4 3 10 1 vvv:v
const 0 builtin error
const 1 str "store refused"
K 8 0
K 6 1
CallDyn 8 5 1
RetNil
end
entry 0
"#
    )
}
fn runtime(op: &str, mode: Mode) -> (Box<Interp>, Value, Value) {
    let mut vm = Box::new(Interp::new());
    image::load(&mut vm, &source(op)).unwrap();
    vm.install_globals();
    let made = vm.call_value(Value::func(1), &[]);
    let (declaration, record) = (made[0], made[1]);
    vm.register(declaration);
    vm.register(record);
    let key = vm.intern("__newindex");
    vm.set_index(declaration, key, Value::func(2));
    assert_eq!(vm.metatable_of(record), Value::NIL);
    #[cfg(feature = "jit")]
    if matches!(mode, Mode::Frame) {
        vm.enable_scheduler().unwrap();
    }
    vm.entries.resize(vm.funcs.len(), 0);
    if matches!(mode, Mode::Threaded) {
        vm.prepare_threaded();
        vm.threaded = true;
    }
    #[cfg(feature = "jit")]
    if matches!(mode, Mode::Ordinary | Mode::Frame) {
        use nupp_vm::{compiled, jit::Jit};
        let mut jit = Jit::new();
        jit.cur_closure_addr = compiled::closure_address() as i64;
        jit.extra_addr = vm.extra.as_ptr() as i64;
        jit.last_nres_addr = &vm.last_nres as *const _ as i64;
        jit.entries_addr = vm.entries.as_ptr() as i64;
        if matches!(mode, Mode::Ordinary) {
            // The callback stays interpreted; native entry and reentry cross
            // the same semantic store helper without requiring a call graph.
            vm.entries[0] = jit.try_compile(&vm.funcs[0], 0).unwrap() as u64;
            // Direct entries only: every task runs as the frame driver, which
            // would otherwise compile a frame entry at the callback's first
            // entry; the frame path is `Mode::Frame`'s.
            vm.frame_threshold = u32::MAX;
        }
        vm.jit = Some(Box::new(jit));
    }
    vm.heap.stress = true;
    vm.heap.stress_steps = true;
    vm.heap.oracle = true;
    vm.heap.quarantine = true;
    (vm, declaration, record)
}
#[cfg(feature = "compiled-runtime")]
fn context<R>(vm: &mut Interp, body: impl FnOnce(&mut Interp) -> R) -> R {
    use nupp_vm::compiled;
    use std::sync::atomic::Ordering;
    struct Restore(*mut Interp);
    impl Drop for Restore {
        fn drop(&mut self) {
            compiled::CTX.store(self.0, Ordering::Relaxed);
        }
    }
    let _restore = Restore(compiled::CTX.load(Ordering::Relaxed));
    compiled::CTX.store(vm, Ordering::Relaxed);
    body(vm)
}
#[cfg(feature = "jit")]
fn native(vm: &mut Interp, args: &[Value]) {
    context(vm, |vm| {
        let entry = vm.entries[0];
        assert_ne!(entry, 0);
        assert_eq!(vm.entry_of(0), entry);
        vm.enter_compiled(entry, Value::NIL, args, 3);
    });
}
#[cfg(feature = "compiled-runtime")]
fn helper(vm: &mut Interp, object: Value, key: Value, value: Value) {
    use nupp_vm::{compiled, interp::Op};
    context(vm, |vm| {
        let integer = vm.funcs[0]
            .code
            .iter()
            .any(|op| matches!(op, Op::SetIdxI(..)));
        let result = if integer {
            compiled::j_set_index_i(object.0, nupp_vm::numeric::bits(vm, key, false), value.0)
        } else {
            compiled::j_set_index(object.0, key.0, value.0)
        };
        if Value(result) == Value::ERROR {
            let error = vm.pending_error.take().unwrap();
            std::panic::panic_any(builtins::LuaError(error.0));
        }
    });
}

fn store(
    vm: &mut Interp,
    mode: Mode,
    object: Value,
    key: Value,
    value: Value,
) -> Result<(), String> {
    let args = [object, key, value];
    #[cfg(feature = "jit")]
    if matches!(mode, Mode::Frame) {
        vm.schedule(Value::func(0), &args, None).unwrap();
        let events = vm.run_ready(1).unwrap();
        assert_eq!(events.len(), 1);
        assert!(vm.compiled_frame_entries > 0);
        assert_ne!(vm.frame_entries[0], 0);
        assert_ne!(vm.frame_entries[0], u64::MAX);
        assert_eq!(vm.entries[0], 0);
        return match &events[0].status {
            nupp_vm::scheduler::Status::Completed => Ok(()),
            nupp_vm::scheduler::Status::Failed(message) => Err(message.clone()),
            other => panic!("unexpected frame outcome: {other:?}"),
        };
    }
    let mark = vm.open_scope();
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        #[cfg(feature = "compiled-runtime")]
        if matches!(mode, Mode::Helper) {
            helper(vm, object, key, value);
            return;
        }
        #[cfg(feature = "jit")]
        if matches!(mode, Mode::Ordinary) {
            native(vm, &args);
            return;
        }
        vm.call_value(Value::func(0), &args);
    }));
    vm.close_scope(mark);
    assert_eq!(vm.compiled_frame_entries, 0);
    result.map_err(|error| {
        let value = vm.error_value(error);
        String::from_utf8_lossy(vm.bytes_of(value)).into_owned()
    })
}
fn assert_seen(vm: &mut Interp, object: Value, key: Value, value: Value) {
    let seen_key = vm.intern("seenKey");
    let seen_value = vm.intern("seenValue");
    let reentered = vm.intern("reentered");
    let observed = vm.get_index(object, seen_key);
    if nupp_vm::numeric::is_numeric(key) {
        assert_eq!(nupp_vm::numeric::compare(observed, key), Some(std::cmp::Ordering::Equal));
    } else { assert_eq!(observed, key); }
    assert_eq!(vm.get_index(object, seen_value), value);
    assert_eq!(vm.get_index(object, reentered), Value::num(19.0));
    assert_eq!(vm.get_index(object, key), Value::NIL);
    vm.full_cycle();
    vm.check_oracle();
}

#[test]
fn declaration_handlers_receive_exact_keys_with_gc_and_reentry_in_every_mode() {
    let _lock = SERIAL.lock().unwrap_or_else(|p| p.into_inner());
    for mode in modes() {
        for op in ["SetIdx", "SetIdxF", "SetIdxI"] {
            let (mut vm, _, record) = runtime(op, mode);
            let key = Value::num(if op == "SetIdxI" { -7.0 } else { 0.5 });
            let value = vm.new_table();
            vm.register(value);
            store(&mut vm, mode, record, key, value).unwrap();
            assert_seen(&mut vm, record, key, value);
        }
    }
}

#[test]
fn occupied_record_keys_and_rawset_bypass_handlers() {
    let _lock = SERIAL.lock().unwrap_or_else(|p| p.into_inner());
    for mode in modes() {
        for op in ["SetIdx", "SetIdxF", "SetIdxI"] {
            let (mut vm, _, record) = runtime(op, mode);
            let key = Value::num(1.0);
            vm.set_index(record, key, Value::FALSE);
            store(&mut vm, mode, record, key, Value::TRUE).unwrap();
            assert_eq!(vm.get_index(record, key), Value::TRUE);
            store(&mut vm, mode, record, key, Value::NIL).unwrap();
            assert_eq!(vm.get_index(record, key), Value::NIL);
            builtins::call(
                &mut vm,
                builtins::id_of("rawset").unwrap(),
                &[record, key, Value::FALSE],
            );
            assert_eq!(vm.get_index(record, key), Value::FALSE);
            let seen = vm.intern("seenKey");
            assert_eq!(vm.get_index(record, seen), Value::NIL);
        }
        let (mut vm, _, record) = runtime("SetIdx", mode);
        let field = vm.intern("present");
        vm.set_index(record, field, Value::FALSE);
        store(&mut vm, mode, record, field, Value::TRUE).unwrap();
        assert_eq!(vm.get_index(record, field), Value::TRUE);
    }
}

#[test]
fn array_holes_call_newindex_but_occupied_slots_stay_raw() {
    let _lock = SERIAL.lock().unwrap_or_else(|p| p.into_inner());
    let mut bypassed = vec![];
    for mode in modes() {
        for op in ["SetIdx", "SetIdxF", "SetIdxI"] {
            let (mut vm, declaration, _) = runtime(op, mode);
            let table = vm.new_table();
            vm.register(table);
            for key in 1..=3 {
                vm.set_index(table, Value::num(key as f64), Value::FALSE);
            }
            vm.set_index(table, Value::num(2.0), Value::NIL);
            vm.set_metatable(table, declaration);
            store(&mut vm, mode, table, Value::num(1.0), Value::num(11.0)).unwrap();
            assert_eq!(vm.get_index(table, Value::num(1.0)), Value::num(11.0));
            store(&mut vm, mode, table, Value::num(2.0), Value::num(12.0)).unwrap();
            let seen = vm.intern("seenKey");
            if nupp_vm::numeric::compare(vm.get_index(table, seen), Value::num(2.0)) != Some(std::cmp::Ordering::Equal)
                || vm.get_index(table, Value::num(2.0)) != Value::NIL
            {
                bypassed.push(format!("{mode:?} {op}"));
            }
        }
    }
    assert!(
        bypassed.is_empty(),
        "array holes bypassed __newindex: {bypassed:?}"
    );
}

#[test]
fn table_handlers_and_explicit_record_metatables_preserve_redirects() {
    let _lock = SERIAL.lock().unwrap_or_else(|p| p.into_inner());
    for mode in modes() {
        for op in ["SetIdx", "SetIdxF", "SetIdxI"] {
            let (mut vm, declaration, record) = runtime(op, mode);
            let redirect = vm.new_table();
            vm.register(redirect);
            let newindex = vm.intern("__newindex");
            vm.set_index(declaration, newindex, redirect);
            store(&mut vm, mode, record, Value::num(7.0), Value::TRUE).unwrap();
            assert_eq!(vm.get_index(redirect, Value::num(7.0)), Value::TRUE);
            assert_eq!(vm.get_index(record, Value::num(7.0)), Value::NIL);
            let own = vm.new_table();
            vm.register(own);
            vm.set_index(own, newindex, Value::func(2));
            vm.set_metatable(record, own);
            store(&mut vm, mode, record, Value::num(8.0), Value::FALSE).unwrap();
            assert_seen(&mut vm, record, Value::num(8.0), Value::FALSE);
            assert_eq!(vm.get_index(redirect, Value::num(8.0)), Value::NIL);
        }
    }
}

#[test]
fn replacing_a_declaration_handler_propagates_its_error() {
    let _lock = SERIAL.lock().unwrap_or_else(|p| p.into_inner());
    for mode in modes() {
        for op in ["SetIdx", "SetIdxF", "SetIdxI"] {
            let (mut vm, declaration, record) = runtime(op, mode);
            store(&mut vm, mode, record, Value::num(3.0), Value::TRUE).unwrap();
            let newindex = vm.intern("__newindex");
            vm.set_index(declaration, newindex, Value::func(4));
            let roots = vm.registered.iter().filter(|&&v| v != Value::NIL).count();
            let error = store(&mut vm, mode, record, Value::num(4.0), Value::TRUE).unwrap_err();
            assert!(error.contains("store refused"), "{mode:?} {op}: {error}");
            assert_eq!(
                vm.registered.iter().filter(|&&v| v != Value::NIL).count(),
                roots,
                "{mode:?} {op}: a failed handler must release temporary roots"
            );
            assert_eq!(vm.get_index(record, Value::num(4.0)), Value::NIL);
            vm.full_cycle();
            vm.check_oracle();
        }
    }
}

#[test]
fn plain_sparse_maps_keep_wide_fractional_and_absent_keys() {
    let _lock = SERIAL.lock().unwrap_or_else(|p| p.into_inner());
    for mode in modes() {
        let (mut vm, _, _) = runtime("SetIdx", mode);
        let table = vm.new_table();
        vm.register(table);
        let signed = vm.box_integer(Integer {
            bits: i64::MIN as u64,
            unsigned: false,
        });
        vm.register(signed);
        let unsigned = vm.box_integer(Integer {
            bits: u64::MAX,
            unsigned: true,
        });
        vm.register(unsigned);
        for key in [
            signed,
            unsigned,
            Value::num(-1.0),
            Value::num(0.0),
            Value::num(0.5),
            Value::num(100.0),
        ] {
            store(&mut vm, mode, table, key, Value::TRUE).unwrap();
            assert_eq!(vm.get_index(table, key), Value::TRUE);
        }
        assert_eq!(vm.array_len(table), 0);
        assert_eq!(vm.get_index(table, Value::num(50.0)), Value::NIL);
        vm.full_cycle();
        vm.check_oracle();
    }
}

#[test]
fn raw_maps_continue_to_reject_nil_and_nan_keys() {
    let _lock = SERIAL.lock().unwrap_or_else(|p| p.into_inner());
    for mode in modes() {
        for key in [Value::NIL, Value::num(f64::NAN)] {
            let (mut vm, _, _) = runtime("SetIdx", mode);
            let table = vm.new_table();
            vm.register(table);
            let error = store(&mut vm, mode, table, key, Value::TRUE).unwrap_err();
            assert!(error.contains("table index is"), "{mode:?}: {error}");
        }
    }
}

#[test]
fn integer_stores_keep_keys_beyond_the_double_integer_range() {
    let _lock = SERIAL.lock().unwrap_or_else(|p| p.into_inner());
    for mode in modes() {
        for bits in [i64::MIN as u64, i64::MAX as u64] {
            let (mut vm, _, record) = runtime("SetIdxI", mode);
            let key = vm.box_integer(Integer {
                bits,
                unsigned: false,
            });
            vm.register(key);
            store(&mut vm, mode, record, key, Value::TRUE).unwrap();
            assert_seen(&mut vm, record, key, Value::TRUE);
        }
    }
}
