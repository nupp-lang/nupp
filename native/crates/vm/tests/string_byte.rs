use nupp_vm::{builtins, image, interp::Interp, numeric::Integer, value::Value};

const BYTE: &str = "function byte 0 2 8 3 vv:v\nIUnbox 0 2\nStrByte 3 1 0\nRet 3\nend\nentry 0\n";
const LAST: &str = "function last 0 1 8 3 v:v\nconst 0 num 1\nFK 0 1\nFNeg 1 0\nFToI 2 1\nStrByte 3 1 2\nRet 3\nend\nentry 0\n";

#[derive(Clone, Copy, Debug)]
enum Mode {
    Interpreter,
    Threaded,
    #[cfg(feature = "jit")]
    Ordinary,
    #[cfg(feature = "jit")]
    Frame,
}

fn modes() -> Vec<Mode> {
    let modes = vec![Mode::Interpreter, Mode::Threaded];
    #[cfg(feature = "jit")]
    let modes = {
        let mut modes = modes;
        modes.extend([Mode::Ordinary, Mode::Frame]);
        modes
    };
    modes
}

fn runtime(source: &str, mode: Mode) -> Box<Interp> {
    let mut vm = Box::new(Interp::new());
    image::load(&mut vm, source).unwrap();
    vm.install_globals();
    #[cfg(feature = "jit")]
    if matches!(mode, Mode::Frame) {
        vm.enable_scheduler().unwrap();
    }
    vm.entries.resize(vm.funcs.len(), 0);
    if matches!(mode, Mode::Threaded) {
        vm.prepare_threaded();
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
            vm.entries[0] = jit.try_compile(&vm.funcs[0], 0).unwrap() as u64;
        }
        vm.jit = Some(Box::new(jit));
    }
    vm.heap.stress = true;
    vm.heap.stress_steps = true;
    vm.heap.oracle = true;
    vm.heap.quarantine = true;
    vm
}

#[cfg(feature = "compiled-runtime")]
fn with_context<R>(vm: &mut Interp, call: impl FnOnce(&mut Interp) -> R) -> R {
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
    call(vm)
}

fn run(vm: &mut Interp, mode: Mode, args: &[Value]) -> Value {
    #[cfg(feature = "jit")]
    if matches!(mode, Mode::Ordinary) {
        return with_context(vm, |vm| {
            let entry = vm.entries[0];
            assert_ne!(entry, 0);
            assert_eq!(vm.entry_of(0), entry);
            let nparams = vm.funcs[0].nparams as usize;
            let result = vm.enter_compiled(entry, Value::NIL, args, nparams).to_vec();
            assert_eq!(result.len(), 1);
            assert_eq!(vm.compiled_frame_entries, 0);
            assert!(vm.frame_entries.iter().all(|&entry| entry == 0));
            result[0]
        });
    }
    #[cfg(feature = "jit")]
    if matches!(mode, Mode::Frame) {
        let task = vm.schedule(Value::func(0), args, None).unwrap();
        let events = vm.run_ready(1).unwrap();
        assert_eq!(events.len(), 1);
        assert_eq!(events[0].status, nupp_vm::scheduler::Status::Completed);
        assert_eq!(vm.last_nres, 1);
        let result = vm.tasks[task.index].result;
        assert!(vm.compiled_frame_entries > 0);
        assert_ne!(vm.frame_entries[0], 0);
        assert_ne!(vm.frame_entries[0], u64::MAX);
        assert_eq!(vm.entries[0], 0);
        return result;
    }
    let result = vm.call_value(Value::func(0), args);
    assert_eq!(result.len(), 1);
    if matches!(mode, Mode::Interpreter | Mode::Threaded) {
        assert_eq!(vm.compiled_frame_entries, 0);
        assert!(vm.entries.iter().all(|&entry| entry == 0));
    }
    result[0]
}

fn builtin(vm: &mut Interp, text: Value, index: i64) -> Value {
    // The builtin's public numeric conversion and the opcode's exact integer
    // window are separate. These extremes are out of range in either case.
    builtins::call(
        vm,
        builtins::id_of("string.byte").unwrap(),
        &[text, Value::num(index as f64)],
    )
    .first()
    .copied()
    .unwrap_or(Value::NIL)
}

fn expected(bytes: &[u8], index: i64) -> Value {
    let zero = if index < 0 {
        bytes.len() as i128 + index as i128
    } else {
        index as i128 - 1
    };
    if zero >= 0 && zero < bytes.len() as i128 {
        Value::num(bytes[zero as usize] as f64)
    } else {
        Value::NIL
    }
}

fn indices(len: usize) -> Vec<i64> {
    let n = len as i64;
    vec![
        i64::MIN,
        i64::MIN + 1,
        -n - 1,
        -n,
        -2,
        -1,
        0,
        1,
        2,
        n,
        n + 1,
        i64::MAX,
    ]
}

fn input(vm: &mut Interp, bytes: &[u8], slice: bool) -> Value {
    let value = if slice {
        let mut padded = b"prefix".to_vec();
        padded.extend_from_slice(bytes);
        padded.extend_from_slice(b"suffix");
        let parent = vm.new_string_bytes(&padded);
        vm.handles.push(parent);
        let view = vm.new_slice(parent, 4, bytes.len() as u32 + 4);
        vm.handles.push(view);
        let nested = vm.new_slice(view, 2, bytes.len() as u32);
        vm.handles.pop();
        vm.handles.pop();
        assert_eq!(vm.kind_of(nested), Some(nupp_vm::heap::KIND_SLICE));
        nested
    } else {
        vm.new_string_bytes(bytes)
    };
    vm.register(value);
    // Only the final slice is rooted here. Its backing string must survive.
    vm.full_cycle();
    vm.check_oracle();
    assert_eq!(vm.bytes_of(value), bytes);
    value
}

fn matrix(slice: bool) {
    for mode in modes() {
        let mut vm = runtime(BYTE, mode);
        for bytes in [&b""[..], &b"x"[..], &b"1."[..], &b"a\0\x80\xffz"[..]] {
            let text = input(&mut vm, bytes, slice);
            for index in indices(bytes.len()) {
                let want = expected(bytes, index);
                assert_eq!(builtin(&mut vm, text, index), want);
                let arg = vm.box_integer(Integer {
                    bits: index as u64,
                    unsigned: false,
                });
                vm.handles.push(arg);
                assert_eq!(
                    run(&mut vm, mode, &[text, arg]),
                    want,
                    "{mode:?}, slice={slice}, index={index}"
                );
                vm.handles.pop();
                vm.full_cycle();
                vm.check_oracle();
                assert_eq!(vm.bytes_of(text), bytes);
            }
        }
    }
}

#[test]
fn string_positions_match_the_single_result_builtin_in_every_entry_mode() {
    matrix(false);
}

#[test]
fn relative_slice_positions_keep_only_the_backing_root_under_gc() {
    matrix(true);
}

#[test]
fn lowered_float_negative_index_reads_the_decimal_suffix() {
    for mode in modes() {
        let mut vm = runtime(LAST, mode);
        for slice in [false, true] {
            let text = input(&mut vm, b"1.", slice);
            assert_eq!(
                run(&mut vm, mode, &[text]),
                Value::num(46.0),
                "{mode:?}, slice={slice}"
            );
            vm.full_cycle();
            vm.check_oracle();
        }
    }
}

#[cfg(feature = "compiled-runtime")]
#[test]
fn guarded_compiled_helper_matches_string_and_slice_boundaries() {
    let mut vm = runtime(BYTE, Mode::Interpreter);
    for slice in [false, true] {
        let text = input(&mut vm, b"\0\x80\xff", slice);
        for index in indices(3) {
            let want = builtin(&mut vm, text, index);
            let found = with_context(&mut vm, |_| {
                // This public ABI helper uses Interp::guarded; CTX is scoped
                // to the current thread and restored even if an assertion fails.
                Value(nupp_vm::compiled::j_str_byte(text.0, index as u64))
            });
            assert_eq!(found, want, "slice={slice}, index={index}");
            assert_ne!(found, Value::ERROR);
            assert!(vm.pending_error.is_none());
        }
        vm.full_cycle();
        vm.check_oracle();
    }
}
