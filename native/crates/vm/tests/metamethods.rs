//! Metamethod programs exercise observed native dispatch, chained native
//! dispatch, typed entries, and scheduled frames under collector stress.
//! The checked-in image and per-program expected output cover callback order,
//! returned values, errors, and logical resume behavior.
use nupp_vm::{graph, interp::Interp, scheduler::Status, value::Value};

const IMAGE: &[u8] = include_bytes!("metamethods/metamethods.image");
const PROGRAMS: &[(&str, &str)] = &[
    ("arith", include_str!("metamethods/arith.expected")),
    ("call", include_str!("metamethods/call.expected")),
    ("concat", include_str!("metamethods/concat.expected")),
    ("eq", include_str!("metamethods/eq.expected")),
    ("ignored", include_str!("metamethods/ignored.expected")),
    ("index", include_str!("metamethods/index.expected")),
    ("len", include_str!("metamethods/len.expected")),
    ("metatable", include_str!("metamethods/metatable.expected")),
    ("newindex", include_str!("metamethods/newindex.expected")),
    ("order", include_str!("metamethods/order.expected")),
    ("pairs", include_str!("metamethods/pairs.expected")),
    ("records", include_str!("metamethods/records.expected")),
    ("slots", include_str!("metamethods/slots.expected")),
    ("tostring", include_str!("metamethods/tostring.expected")),
];

#[derive(Clone, Copy, Debug)]
enum Mode {
    Observed,
    Threaded,
    #[cfg(feature = "jit")]
    Typed,
    #[cfg(feature = "jit")]
    Frame,
}

fn fixture(mode: Mode) -> Box<Interp> {
    let mut vm = Box::new(Interp::new());
    graph::load(&mut vm, IMAGE).unwrap();
    vm.install_globals();
    vm.threaded = !matches!(mode, Mode::Observed);
    vm.entries.resize(vm.funcs.len(), 0);
    if matches!(mode, Mode::Threaded) {
        vm.prepare_threaded();
    }
    #[cfg(feature = "jit")]
    if matches!(mode, Mode::Typed | Mode::Frame) {
        use nupp_vm::{compiled, jit::Jit};
        vm.entries.resize(vm.funcs.len(), 0);
        let mut jit = Jit::new();
        jit.extra_addr = vm.extra.as_ptr() as i64;
        jit.last_nres_addr = &vm.last_nres as *const _ as i64;
        jit.entries_addr = vm.entries.as_ptr() as i64;
        jit.callee_info = vm
            .funcs
            .iter()
            .map(|f| (f.nparams, f.sig.iter().all(|&c| c == b'v') && f.ret != b'f' && !f.vararg))
            .collect();
        vm.calltab = jit.callee_info.iter().map(|&(np, plain)| np as u64 | ((plain as u64) << 8)).collect();
        jit.calltab_addr = vm.calltab.as_ptr() as i64;
        vm.shape_probe = vm.heap.shapes.iter().map(|s| (s.table.as_ptr() as u64, s.mask)).collect();
        jit.probe_addr = vm.shape_probe.as_ptr() as i64;
        compiled::CTX.store(&mut *vm, std::sync::atomic::Ordering::Relaxed);
        if matches!(mode, Mode::Typed) {
            for id in 0..vm.funcs.len() {
                if vm.funcs[id].name.starts_with("module:") {
                    continue;
                }
                if let Ok(entry) = jit.try_compile(&vm.funcs[id].clone(), id as u32) {
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

fn run(vm: &mut Interp, mode: Mode, program: &str) -> String {
    let module = vm.require(program);
    let root = vm.register(module);
    let key = vm.intern("main");
    let main = vm.get_index(module, key);
    let result = if matches!(mode, Mode::Observed | Mode::Threaded) || cfg!(not(feature = "jit")) || !frame(mode) {
        let value = vm.guarded(|vm| vm.call_value(main, &[]).first().copied().unwrap_or(Value::NIL));
        if value == Value::ERROR {
            let error = vm.pending_error.take().unwrap();
            panic!("{program} on {mode:?} raised {}", String::from_utf8_lossy(vm.bytes_of(error)));
        }
        value
    } else {
        let task = vm.schedule(main, &[], None).unwrap();
        let events = vm.run_ready(1).unwrap();
        match &events[0].status {
            Status::Completed => vm.tasks[task.index].result,
            status => panic!("{program} on {mode:?}: {status:?}"),
        }
    };
    let text = String::from_utf8_lossy(vm.bytes_of(result)).into_owned();
    vm.release(root);
    text
}

fn frame(mode: Mode) -> bool {
    #[cfg(feature = "jit")]
    if matches!(mode, Mode::Frame) {
        return true;
    }
    let _ = mode;
    false
}

#[test]
fn metamethod_programs_agree_across_native_entries() {
    let modes = [
        Mode::Observed,
        Mode::Threaded,
        #[cfg(feature = "jit")]
        Mode::Typed,
        #[cfg(feature = "jit")]
        Mode::Frame,
    ];
    for mode in modes {
        let mut vm = fixture(mode);
        for (program, expected) in PROGRAMS {
            let actual = run(&mut vm, mode, program);
            assert_eq!(actual, *expected, "{program} on {mode:?}");
        }
        vm.full_cycle();
        vm.check_oracle();
    }
}

fn call_export(vm: &mut Interp, mode: Mode, name: &str) -> Result<Value, String> {
    let module = vm.require("call");
    let root = vm.register(module);
    let key = vm.intern(name);
    let function = vm.get_index(module, key);
    let result = if frame(mode) {
        let task = vm.schedule(function, &[], None).unwrap();
        let events = vm.run_ready(1).unwrap();
        match &events[0].status {
            Status::Completed => Ok(vm.tasks[task.index].result),
            Status::Failed(error) => Err(error.clone()),
            status => panic!("{name} on {mode:?}: {status:?}"),
        }
    } else {
        let value = vm.guarded(|vm| vm.call_value(function, &[]).first().copied().unwrap_or(Value::NIL));
        if value == Value::ERROR {
            let error = vm.pending_error.take().unwrap();
            Err(String::from_utf8_lossy(vm.bytes_of(error)).into_owned())
        } else {
            Ok(value)
        }
    };
    vm.release(root);
    result
}

/// A handler that raises leaves no root behind: compiled code calling a
/// callable table used to leave its arguments on the handle stack.
#[test]
fn raising_handlers_release_their_roots_on_every_tier() {
    let modes = [
        Mode::Observed,
        Mode::Threaded,
        #[cfg(feature = "jit")]
        Mode::Typed,
        #[cfg(feature = "jit")]
        Mode::Frame,
    ];
    for mode in modes {
        let mut vm = fixture(mode);
        vm.require("call");
        let (handles, registered) = (vm.handles.len(), vm.registered.iter().filter(|v| **v != Value::NIL).count());
        // Twelve of the thirteen cases raise (the VM honors `__len`), twenty times.
        assert_eq!(call_export(&mut vm, mode, "raising"), Ok(Value::inline_integer(240).unwrap()), "{mode:?}");
        assert_eq!(vm.handles.len(), handles, "caught raises left roots on {mode:?}");
        let error = call_export(&mut vm, mode, "uncaught").unwrap_err();
        assert!(error.contains("uncaught"), "{mode:?}: {error}");
        assert_eq!(vm.handles.len(), handles, "an uncaught raise left roots on {mode:?}");
        assert_eq!(vm.registered.iter().filter(|v| **v != Value::NIL).count(), registered, "{mode:?}");
        vm.full_cycle();
        vm.check_oracle();
    }
}
