use nupp_vm::{
    image,
    interp::Interp,
    simd::{self, Shape},
    value::Value,
};

const LANES: usize = 9;

#[derive(Clone, Copy, Debug)]
enum Mode {
    Interpreter,
    #[cfg(feature = "jit")]
    Ordinary,
    #[cfg(feature = "jit")]
    Frame,
}

fn modes() -> Vec<Mode> {
    let modes = vec![Mode::Interpreter];
    #[cfg(feature = "jit")]
    let modes = {
        let mut modes = modes;
        modes.extend([Mode::Ordinary, Mode::Frame]);
        modes
    };
    modes
}

fn program(kind: u8, body: &str, constants: &str) -> String {
    let mut source = format!(
        "function main 0 1 64 1 v:v\nconst 0 func 1\nconst 1 func 2\nconst 2 func 3\n{constants}{body}\nend\nfunction tile 1 1 32 1 v:v\n"
    );
    for index in 0..LANES {
        source.push_str(&format!("const {index} num {}\n", index + 1));
    }
    // The ordinary ABI accepts one table argument, not nine native parameters.
    // The transpose itself still writes nine distinct value registers/results.
    for index in 0..LANES {
        source.push_str(&format!("K 20 {index}\nGetIdx {} 1 20\n", index + 3));
    }
    source.push_str(&format!(
        "Simd transpose {} 2 {LANES}\nRetN 2 128\nend\nfunction short 2 0 2 1 :v\nconst 0 num 77\nK 1 0\nRet 1\nend\nfunction empty 3 0 2 1 :v\nRetNil\nend\nentry 0\n",
        simd::ELEMENTS[kind as usize]
    ));
    source
}

fn runtime(source: &str, mode: Mode) -> Box<Interp> {
    let mut vm = Box::new(Interp::new());
    image::load(&mut vm, source).unwrap();
    vm.install_globals();
    vm.simd_interpret = true;
    #[cfg(feature = "jit")]
    if matches!(mode, Mode::Ordinary | Mode::Frame) {
        use nupp_vm::{compiled, jit::Jit};
        vm.entries.resize(vm.funcs.len(), 0);
        let mut jit = Jit::new();
        jit.cur_closure_addr = compiled::closure_address() as i64;
        jit.extra_addr = vm.extra.as_ptr() as i64;
        jit.last_nres_addr = &vm.last_nres as *const _ as i64;
        jit.entries_addr = vm.entries.as_ptr() as i64;
        if matches!(mode, Mode::Ordinary) {
            for fid in 0..4 {
                vm.entries[fid] = jit
                    .try_compile(&vm.funcs[fid], fid as u32)
                    .unwrap_or_else(|error| panic!("ordinary entry {fid}: {error}"))
                    as u64;
            }
            // Direct entries only: every task runs as the frame driver, which
            // would otherwise compile a frame entry when a callee is entered
            // interpreted; the frame path is `Mode::Frame`'s.
            vm.frame_threshold = u32::MAX;
        }
        vm.jit = Some(Box::new(jit));
    }
    let _ = mode;
    vm.heap.stress = true;
    vm.heap.stress_steps = true;
    vm.heap.oracle = true;
    vm.heap.quarantine = true;
    vm
}

fn lane_bits(kind: u8, row: usize, column: usize) -> [u8; 8] {
    let bits = if kind == 9 {
        match (row, column) {
            (0, _) => 0x7ff8_0000_0000_0100 + column as u64,
            (1, 0) => 0x8000_0000_0000_0000,
            (1, 1) => 0,
            _ => 0x3ff0_0000_0000_0000 + (row * 64 + column) as u64,
        }
    } else {
        0xfedc_ba98_7654_0000 + (row * 64 + column) as u64
    };
    bits.to_ne_bytes()
}

fn input(vm: &mut Interp, kind: u8) -> Value {
    let table = vm.new_table();
    vm.register(table);
    for row in 0..LANES {
        let bytes: Vec<u8> = (0..LANES)
            .flat_map(|column| lane_bits(kind, row, column))
            .collect();
        let value = simd::value(
            vm,
            Shape {
                kind,
                lanes: LANES,
                mask: false,
                species: false,
            },
            &bytes,
        );
        vm.handles.push(value);
        vm.set_index(table, Value::num((row + 1) as f64), value);
        vm.handles.pop();
    }
    table
}

fn run(vm: &mut Interp, mode: Mode, table: Value) -> Vec<Value> {
    #[cfg(feature = "jit")]
    if matches!(mode, Mode::Ordinary) {
        use std::sync::atomic::Ordering;
        // Explicit entry avoids image installation's automatic heap-frame route.
        // Every image callee is precompiled too, so a silent frame fallback fails
        // the counter assertion instead of masquerading as ordinary coverage.
        struct RestoreContext(*mut Interp);
        impl Drop for RestoreContext {
            fn drop(&mut self) {
                nupp_vm::compiled::CTX.store(self.0, Ordering::Relaxed);
            }
        }
        let _context = RestoreContext(nupp_vm::compiled::CTX.load(Ordering::Relaxed));
        nupp_vm::compiled::CTX.store(&mut *vm, Ordering::Relaxed);
        let entry = vm.entries[0];
        assert_ne!(entry, 0);
        assert_eq!(vm.entry_of(0), entry);
        let values = vm.enter_compiled(entry, Value::NIL, &[table], 1).to_vec();
        assert_eq!(vm.compiled_frame_entries, 0);
        assert!(vm.frame_entries.iter().all(|&entry| entry == 0));
        return values;
    }
    let values = vm.call_value(Value::func(0), &[table]);
    #[cfg(feature = "jit")]
    if matches!(mode, Mode::Frame) {
        assert!(vm.compiled_frame_entries > 0);
        assert_ne!(vm.frame_entries[0], 0);
        assert_ne!(vm.frame_entries[0], u64::MAX);
        assert_eq!(vm.entries[0], 0);
    }
    if matches!(mode, Mode::Interpreter) {
        assert_eq!(vm.compiled_frame_entries, 0);
        assert!(vm.entries.iter().all(|&entry| entry == 0));
    }
    values
}

fn assert_columns(vm: &Interp, kind: u8, values: &[Value]) {
    assert_eq!(values.len(), LANES);
    for (column, &value) in values.iter().enumerate() {
        assert_eq!(
            simd::shape(vm, value),
            Some(Shape {
                kind,
                lanes: LANES,
                mask: false,
                species: false,
            })
        );
        let bytes: Vec<u8> = (0..LANES)
            .flat_map(|row| lane_bits(kind, row, column))
            .collect();
        assert_eq!(&vm.bytes_of(value)[16..], bytes, "column {column}");
    }
}

fn collect_results(vm: &mut Interp, values: &[Value]) {
    vm.handles.extend_from_slice(values);
    vm.full_cycle();
    vm.check_oracle();
}

#[test]
fn wide_transpose_tail_enters_the_selected_native_abi() {
    for mode in modes() {
        for kind in [6, 9] {
            let source = program(kind, "K 20 0\nMove 4 1\nCallDyn 20 3 1\nRetN 3 128", "");
            let mut vm = runtime(&source, mode);
            let table = input(&mut vm, kind);
            let values = run(&mut vm, mode, table);
            assert_eq!(vm.last_nres, LANES, "{mode:?}");
            collect_results(&mut vm, &values);
            assert_columns(&vm, kind, &values);
        }
    }
}

#[test]
fn table_constructor_spreads_all_transpose_results() {
    for mode in modes() {
        for kind in [6, 9] {
            // Match lowering of {tile(input)}: two fixed arguments to the
            // appender, then the complete trailing call pack (66 = 64 | 2).
            let source = program(
                kind,
                "NewTableN 20 9 0\nK 21 3\nK 22 4\nMove 31 20\nMove 32 22\nK 50 0\nMove 34 1\nCallDyn 50 33 1\nCallDyn 21 30 66\nNewTable 51\nRet 20",
                "const 3 builtin vm.tableAppendResults\nconst 4 num 1\n",
            );
            let mut vm = runtime(&source, mode);
            let table = input(&mut vm, kind);
            let values = run(&mut vm, mode, table);
            assert_eq!(values.len(), 1, "{mode:?}");
            collect_results(&mut vm, &values);
            let columns: Vec<Value> = (1..=LANES)
                .map(|index| vm.get_index(values[0], Value::num(index as f64)))
                .collect();
            assert_columns(&vm, kind, &columns);
            assert_eq!(vm.get_index(values[0], Value::num(10.0)), Value::NIL);
        }
    }
}

#[test]
fn protected_prefix_and_padding_keep_the_wide_raw_pack() {
    for mode in modes() {
        for kind in [6, 9] {
            let source = program(
                kind,
                "K 3 0\nMove 4 1\nPCall 2 1\nPadResults 2 11\nNewTable 30\nRetN 2 11",
                "",
            );
            let mut vm = runtime(&source, mode);
            let table = input(&mut vm, kind);
            let values = run(&mut vm, mode, table);
            assert_eq!(values.len(), 11, "{mode:?}");
            collect_results(&mut vm, &values);
            assert_eq!(values[0], Value::TRUE);
            assert_columns(&vm, kind, &values[1..10]);
            assert_eq!(values[10], Value::NIL);
        }
    }
}

#[test]
fn later_short_and_zero_calls_replace_the_wide_count_and_padding() {
    for mode in modes() {
        for empty in [false, true] {
            for padded in [false, true] {
                let ending = if padded {
                    "PadResults 3 12\nNewTable 30\nRetN 3 12"
                } else {
                    "NewTable 30\nRetN 3 128"
                };
                let source = program(
                    6,
                    &format!(
                        "K 20 0\nMove 4 1\nCallDyn 20 3 1\nPadResults 3 12\nK 20 {}\nCallDyn 20 3 0\n{ending}",
                        if empty { 2 } else { 1 }
                    ),
                    "",
                );
                let mut vm = runtime(&source, mode);
                let table = input(&mut vm, 6);
                let values = run(&mut vm, mode, table);
                let count = if padded { 12 } else { usize::from(!empty) };
                assert_eq!(values.len(), count, "{mode:?} empty{empty} padded{padded}");
                assert_eq!(vm.last_nres, count);
                collect_results(&mut vm, &values);
                let mut expected = vec![Value::NIL; count];
                if !empty {
                    expected[0] = Value::num(77.0);
                }
                assert_eq!(values, expected);
            }
        }
    }
}
