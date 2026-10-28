use super::native_numeric_tests::{direct, fixture, intput, put, value};
use super::*;
use crate::{interp::Op, numeric::Integer, value::Value};

#[test]
fn native_physical_reads_recover_caller_after_callback_success_error_and_park() {
    for kind in 0..4 {
        for outcome in 0..4 {
            let plan = crate::storage::PhysicalField {
                identity: 0,
                name: 1,
                ordinal: 0,
                offset: 0,
                kind: if kind == 3 { 8 } else { 7 },
            };
            let op = match kind {
                0 => Op::GetPhys(1, 1, plan),
                1 => Op::GetPhysF(0, 1, plan),
                2 => Op::GetPhysI(0, 1, plan),
                _ => Op::GetPhysU(0, 1, plan),
            };
            let (mut vm, tid) = fixture(op);
            let identity = vm.intern("PhysicalProbe");
            let name = vm.intern("x");
            vm.funcs[0].consts.extend([identity, name]);
            let body = match outcome {
                0 => "const 0 int64 -9223372036854775808\nNewTable 3\nK 4 0\nRet 4",
                1 => "const 0 str \"physical callback failed\"\nRaise 0",
                2 => "Park 1\nRetNil",
                _ => "const 0 true\nK 3 0\nRet 3",
            };
            let callback = crate::image::load(
                &mut vm,
                &format!("function callback 0 2 8 2 vv:v\n{body}\nend\nentry 0\n"),
            )
            .unwrap();
            let object = vm.new_table();
            put(&mut vm, tid, 1, object);
            put(&mut vm, tid, 2, object);
            let meta = vm.new_table();
            vm.register(meta);
            let index = vm.intern("__index");
            vm.set_index(meta, index, Value::func(callback));
            vm.set_metatable(object, meta);
            intput(&mut vm, tid, 0, 0x1020_3040_5060_7080);
            let float_at = vm.tasks[tid].cur() + vm.funcs[0].off_f();
            vm.tasks[tid].stack[float_at] = (-0.0f64).to_bits();
            vm.entries.resize(vm.funcs.len(), 0);
            vm.prepare_threaded();
            vm.funcs[0].ins[1].op = Code::Slow as u8;
            vm.heap.stress = true;
            vm.heap.stress_steps = true;
            vm.heap.oracle = true;
            vm.heap.quarantine = true;
            let ctx = direct(&mut vm, tid, 1);
            let failed = outcome != 0 && (outcome != 3 || kind != 0);
            assert_eq!(ctx.status == ST_ERROR, failed);
            assert_eq!(ctx.stack, vm.tasks[tid].stack.as_mut_ptr());
            assert_eq!(ctx.cur as usize, vm.tasks[tid].cur());
            assert_eq!(value(&vm, tid, 2), object);
            if !failed {
                match kind {
                    0 if outcome == 3 => assert_eq!(value(&vm, tid, 1), Value::TRUE),
                    0 => assert_eq!(
                        crate::numeric::integer(value(&vm, tid, 1)).unwrap().bits,
                        i64::MIN as u64
                    ),
                    1 => assert_eq!(vm.tasks[tid].stack[float_at], (i64::MIN as f64).to_bits()),
                    _ => assert_eq!(
                        super::native_numeric_tests::intget(&vm, tid, 0),
                        i64::MIN as u64
                    ),
                }
            } else {
                assert_eq!(value(&vm, tid, 1), object);
                assert_eq!(
                    super::native_numeric_tests::intget(&vm, tid, 0),
                    0x1020_3040_5060_7080
                );
                assert_eq!(vm.tasks[tid].stack[float_at], (-0.0f64).to_bits());
                let error = vm.pending_error.take().unwrap();
                let text = String::from_utf8_lossy(vm.bytes_of(error));
                assert!(text.contains(match outcome {
                    1 => "physical callback failed",
                    2 => "a callback parked",
                    _ if kind == 1 => "expected a number",
                    _ => "expected an integer",
                }));
            }
            vm.full_cycle();
            vm.check_oracle();
            assert!(vm.heap.is_live_slot(object.as_obj().unwrap()));
        }
    }
}

#[test]
fn native_physical_stores_root_boxed_arguments_and_recover_caller() {
    for kind in 0..3 {
        for outcome in 0..3 {
            let plan = crate::storage::PhysicalField {
                identity: 0,
                name: 1,
                ordinal: 0,
                offset: 0,
                kind: if kind == 1 { 10 } else { 8 },
            };
            let op = match kind {
                0 => Op::SetPhys(1, plan, 2),
                1 => Op::SetPhysF(1, plan, 0),
                _ => Op::SetPhysI(1, plan, 0),
            };
            let (mut vm, tid) = fixture(op);
            let identity = vm.intern("PhysicalProbe");
            let name = vm.intern("x");
            vm.funcs[0].consts.extend([identity, name]);
            let body = match outcome {
                0 => {
                    "const 0 builtin rawset\nconst 1 str \"seen\"\nNewTable 9\nK 4 0\nMove 6 1\nK 7 1\nMove 8 3\nCallDyn 4 5 3\nRetNil"
                }
                1 => "const 0 str \"physical store failed\"\nRaise 0",
                _ => "Park 1\nRetNil",
            };
            let callback = crate::image::load(
                &mut vm,
                &format!("function callback 0 3 12 2 vvv:v\n{body}\nend\nentry 0\n"),
            )
            .unwrap();
            let object = vm.new_table();
            put(&mut vm, tid, 1, object);
            put(&mut vm, tid, 3, object);
            let stored = vm.new_table();
            put(&mut vm, tid, 2, stored);
            let meta = vm.new_table();
            vm.register(meta);
            let index = vm.intern("__newindex");
            vm.set_index(meta, index, Value::func(callback));
            vm.set_metatable(object, meta);
            let seen = vm.intern("seen");
            vm.register(seen);
            intput(&mut vm, tid, 0, 0x8000_0000_0000_0001);
            let float_at = vm.tasks[tid].cur() + vm.funcs[0].off_f();
            vm.tasks[tid].stack[float_at] = (-0.0f64).to_bits();
            vm.install_globals();
            vm.entries.resize(vm.funcs.len(), 0);
            vm.prepare_threaded();
            vm.funcs[0].ins[1].op = Code::Slow as u8;
            vm.heap.stress = true;
            vm.heap.stress_steps = true;
            vm.heap.oracle = true;
            vm.heap.quarantine = true;
            let ctx = direct(&mut vm, tid, 1);
            assert_eq!(ctx.status == ST_ERROR, outcome != 0);
            assert_eq!(ctx.stack, vm.tasks[tid].stack.as_mut_ptr());
            assert_eq!(ctx.cur as usize, vm.tasks[tid].cur());
            assert_eq!(value(&vm, tid, 1), object);
            assert_eq!(value(&vm, tid, 2), stored);
            assert_eq!(value(&vm, tid, 3), object);
            let actual = vm.get_index(object, seen);
            if outcome == 0 {
                match kind {
                    0 => assert_eq!(actual, stored),
                    1 => assert_eq!(actual.0, (-0.0f64).to_bits()),
                    _ => {
                        let integer = crate::numeric::integer(actual).unwrap();
                        assert_eq!(integer.bits, 0x8000_0000_0000_0001);
                    }
                }
            } else {
                assert_eq!(actual, Value::NIL);
                let error = vm.pending_error.take().unwrap();
                let text = String::from_utf8_lossy(vm.bytes_of(error));
                assert!(text.contains(if outcome == 1 {
                    "physical store failed"
                } else {
                    "a callback parked"
                }));
            }
            vm.full_cycle();
            vm.check_oracle();
            assert!(vm.heap.is_live_slot(object.as_obj().unwrap()));
            assert!(vm.heap.is_live_slot(stored.as_obj().unwrap()));
        }
    }
}

#[test]
fn native_objects_record_allocation_recovers_live_windows() {
    for dest in [0, 1] {
        let (mut vm, tid) = fixture(Op::NewRecord(dest, 0));
        let name = vm.intern("field");
        assert_eq!(
            vm.heap
                .shape("BoxingRecord", &[name], &[crate::heap::SlotTy::Any]),
            0
        );
        let survivor = vm.new_table();
        put(&mut vm, tid, 1, survivor);
        put(&mut vm, tid, 2, survivor);
        intput(&mut vm, tid, 0, i64::MIN as u64);
        let float_at = vm.tasks[tid].cur() + vm.funcs[0].off_f();
        vm.tasks[tid].stack[float_at] = (-0.0f64).to_bits();
        vm.heap.stress = true;
        vm.heap.stress_steps = true;
        vm.heap.oracle = true;
        vm.heap.quarantine = true;
        let ctx = direct(&mut vm, tid, 1);
        assert_ne!(ctx.status, ST_ERROR);
        let record = value(&vm, tid, dest as usize);
        assert_eq!(
            unsafe { record.as_obj().unwrap().as_ref().kind },
            crate::heap::KIND_RECORD
        );
        assert_eq!(vm.get_index(record, name), Value::NIL);
        assert_eq!(value(&vm, tid, 2), survivor);
        assert_eq!(
            super::native_numeric_tests::intget(&vm, tid, 0),
            i64::MIN as u64
        );
        assert_eq!(vm.tasks[tid].stack[float_at], (-0.0f64).to_bits());
        assert_eq!(ctx.stack, vm.tasks[tid].stack.as_mut_ptr());
        assert_eq!(ctx.cur as usize, vm.tasks[tid].cur());
        vm.full_cycle();
        vm.check_oracle();
        assert!(vm.heap.is_live_slot(survivor.as_obj().unwrap()));
        assert!(vm.heap.is_live_slot(record.as_obj().unwrap()));
    }
}

#[test]
fn native_objects_wide_indices_keep_exact_keys_and_roots() {
    for bits in [
        i64::MIN,
        -9007199254740993,
        -1,
        0,
        1,
        2,
        9007199254740993,
        i64::MAX,
    ] {
        let (mut vm, tid) = fixture(Op::SetIdxI(1, 0, 2));
        let table = vm.new_table();
        put(&mut vm, tid, 1, table);
        let stored = vm.new_table();
        put(&mut vm, tid, 2, stored);
        intput(&mut vm, tid, 0, bits as u64);
        vm.heap.stress = true;
        vm.heap.stress_steps = true;
        vm.heap.oracle = true;
        vm.heap.quarantine = true;
        assert_ne!(direct(&mut vm, tid, 1).status, ST_ERROR);
        let key = vm.box_integer(Integer {
            bits: bits as u64,
            unsigned: false,
        });
        assert_eq!(vm.get_index(table, key), stored);
        vm.funcs[0].code[0] = Op::GetIdxI(0, 1, 0);
        vm.funcs[0].ins[0] = crate::threaded::encode(&vm.funcs[0].code[0]);
        assert_ne!(direct(&mut vm, tid, 1).status, ST_ERROR);
        assert_eq!(value(&vm, tid, 0), stored);
    }
}

#[test]
fn native_objects_numeric_keys_share_lookup_and_array_borders() {
    let (mut vm, tid) = fixture(Op::SetIdx(1, 2, 3));
    let table = vm.new_table();
    put(&mut vm, tid, 1, table);
    for index in [2, 1, 3] {
        put(&mut vm, tid, 2, Value::num(index as f64));
        put(&mut vm, tid, 3, Value::num(index as f64 * 10.0));
        assert_ne!(direct(&mut vm, tid, 1).status, ST_ERROR);
    }
    assert_eq!(vm.array_len(table), 3);
    for index in [1, 2, 3] {
        let key = vm.box_integer(Integer {
            bits: index,
            unsigned: false,
        });
        put(&mut vm, tid, 2, key);
        vm.funcs[0].code[0] = Op::GetIdx(0, 1, 2);
        vm.funcs[0].ins[0] = crate::threaded::encode(&vm.funcs[0].code[0]);
        assert_ne!(direct(&mut vm, tid, 1).status, ST_ERROR);
        assert_eq!(value(&vm, tid, 0), Value::num(index as f64 * 10.0));
    }
}

#[test]
fn native_objects_named_record_stores_keep_declared_type_checks() {
    for good in [false, true] {
        let (mut vm, tid) = fixture(Op::SetField(1, 0, 2));
        let name = vm.intern("amount");
        let shape = vm
            .heap
            .shape("Amount", &[name], &[crate::heap::SlotTy::Num]);
        let record = vm.new_record(shape);
        put(&mut vm, tid, 1, record);
        let input = if good { Value::num(42.0) } else { Value::TRUE };
        put(&mut vm, tid, 2, input);
        vm.funcs[0].consts.push(name);
        vm.prepare_threaded();
        vm.funcs[0].ins[1].op = Code::Slow as u8;
        assert_eq!(direct(&mut vm, tid, 1).status == ST_ERROR, !good);
        if good {
            assert_eq!(vm.get_index(record, name), input);
        } else {
            let e = vm.pending_error.take().unwrap();
            assert!(
                String::from_utf8_lossy(vm.bytes_of(e))
                    .contains("value does not match the declared type of field amount of Amount")
            );
        }
    }
}

#[test]
fn native_objects_invalid_cells_and_upvalues_raise_exact_diagnostics() {
    for object in [false, true] {
        for op in [Op::GetCell(0, 1), Op::SetCell(1, 2), Op::GetUpval(0, 0)] {
            let (mut vm, tid) = fixture(op);
            let input = if object { vm.new_table() } else { Value::TRUE };
            put(&mut vm, tid, 1, input);
            if matches!(op, Op::GetUpval(..)) {
                let at = vm.tasks[tid].cur() + 2;
                vm.tasks[tid].stack[at] = input.0;
            }
            assert_eq!(direct(&mut vm, tid, 1).status, ST_ERROR);
            let e = vm.pending_error.take().unwrap();
            let text = String::from_utf8_lossy(vm.bytes_of(e));
            match op {
                Op::GetCell(..) if object => assert_eq!(
                    text,
                    "runtime error: GetCell of a non-cell in numeric at pc 1 register 1"
                ),
                Op::GetCell(..) => assert_eq!(
                    text,
                    format!(
                        "runtime error: GetCell of a non-object {:#x} in numeric at pc 1 register 1",
                        input.0
                    )
                ),
                Op::SetCell(..) => assert_eq!(text, "runtime error: not a cell"),
                _ if object => assert_eq!(text, "runtime error: not a closure"),
                _ => assert_eq!(text, "runtime error: upvalue outside a closure"),
            }
        }
    }
}

#[test]
fn native_objects_invalid_receivers_and_keys_do_not_step() {
    for op in [
        Op::GetIdx(0, 1, 2),
        Op::SetIdx(1, 2, 3),
        Op::GetField(0, 1, 0),
    ] {
        let (mut vm, tid) = fixture(op);
        let name = vm.intern("field");
        put(&mut vm, tid, 1, Value::NIL);
        put(&mut vm, tid, 2, name);
        put(&mut vm, tid, 3, Value::TRUE);
        vm.funcs[0].consts.push(name);
        vm.prepare_threaded();
        vm.funcs[0].ins[1].op = Code::Slow as u8;
        assert_eq!(direct(&mut vm, tid, 1).status, ST_ERROR);
        let e = vm.pending_error.take().unwrap();
        assert!(String::from_utf8_lossy(vm.bytes_of(e)).contains("attempt to index a nil value"));
    }
    for key in [Value::NIL, Value::num(f64::NAN)] {
        let (mut vm, tid) = fixture(Op::SetIdx(1, 2, 3));
        let table = vm.new_table();
        put(&mut vm, tid, 1, table);
        put(&mut vm, tid, 2, key);
        put(&mut vm, tid, 3, Value::TRUE);
        assert_eq!(direct(&mut vm, tid, 1).status, ST_ERROR);
        let e = vm.pending_error.take().unwrap();
        assert!(
            String::from_utf8_lossy(vm.bytes_of(e)).contains(if key == Value::NIL {
                "table index is nil"
            } else {
                "table index is NaN"
            })
        );
    }
}

pub(super) fn large_fixture(op: Op) -> (Box<crate::interp::Interp>, usize) {
    let mut vm = Box::new(crate::interp::Interp::new());
    crate::image::load(
        &mut vm,
        "function slots 0 0 255 255 :v\nRetNil\nend\nentry 0\n",
    )
    .unwrap();
    vm.funcs[0].code = vec![op, Op::RetNil];
    vm.entries.resize(1, 0);
    vm.prepare_threaded();
    vm.funcs[0].ins[1].op = Code::Slow as u8;
    let tid = vm.spawn(0, &[]);
    (vm, tid)
}

pub(super) fn array_contract() {
    for typed in [false, true] {
        for dest in [0u8, 1, 255] {
            for index in [
                -1.0,
                0.0,
                1.0,
                2.0,
                3.0,
                4.0,
                1.5,
                f64::NAN,
                f64::INFINITY,
                f64::NEG_INFINITY,
                9007199254740994.0,
            ] {
                let (mut vm, tid) = large_fixture(if typed {
                    Op::GetIdxI(dest, 1, 0)
                } else {
                    Op::GetIdxF(dest, 1, 0)
                });
                let table = vm.new_table();
                put(&mut vm, tid, 1, table);
                for (i, v) in [Value::num(-0.0), Value::NIL, Value::num(f64::NAN)]
                    .into_iter()
                    .enumerate()
                {
                    vm.set_index(table, Value::num((i + 1) as f64), v);
                }
                intput(&mut vm, tid, 0, index as i64 as u64);
                let f = vm.tasks[tid].cur() + vm.funcs[0].off_f();
                vm.tasks[tid].stack[f] = index.to_bits();
                let key = if typed {
                    vm.box_integer(Integer {
                        bits: index as i64 as u64,
                        unsigned: false,
                    })
                } else {
                    Value::num(index)
                };
                let expected = vm.index(table, key);
                assert_ne!(direct(&mut vm, tid, 1).status, ST_ERROR);
                assert_eq!(
                    value(&vm, tid, dest as usize),
                    expected,
                    "typed={typed} dest={dest} index={index}"
                );
            }
        }
    }
}

pub(super) fn cell_alias_contract() {
    for dest in [0u8, 1, 255] {
        for input in [
            Value::NIL,
            Value::TRUE,
            Value::num(-0.0),
            Value::num(f64::NAN),
        ] {
            let (mut vm, tid) = large_fixture(Op::GetCell(dest, 1));
            let cell = vm.new_cell(input);
            put(&mut vm, tid, 1, cell);
            assert_ne!(direct(&mut vm, tid, 1).status, ST_ERROR);
            assert_eq!(value(&vm, tid, dest as usize), input);
        }
    }
}

pub(super) fn length_contract() {
    for float in [false, true] {
        for original_dest in [0u8, 1, 255] {
            let dest = if float && original_dest == 255 {
                254
            } else {
                original_dest
            };
            for carrier in 0..3 {
                let (mut vm, tid) = large_fixture(if float {
                    Op::LenF(dest, 1)
                } else {
                    Op::Len(dest, 1)
                });
                let input = match carrier {
                    0 => vm.intern("hello"),
                    1 => {
                        let v = vm.new_table();
                        vm.set_index(v, Value::num(1.0), Value::TRUE);
                        v
                    }
                    _ => Value::TRUE,
                };
                put(&mut vm, tid, 1, input);
                let expected = vm.guarded(|it| it.length(input));
                let error = vm.pending_error.take().map(|v| vm.bytes_of(v).to_vec());
                let f = if error.is_none() && float {
                    Some(crate::numeric::double(&vm, expected))
                } else {
                    None
                };
                assert_eq!(direct(&mut vm, tid, 1).status == ST_ERROR, error.is_some());
                if let Some(error) = error {
                    let e = vm.pending_error.take().unwrap();
                    assert_eq!(vm.bytes_of(e), error);
                } else if let Some(f) = f {
                    let at = vm.tasks[tid].cur() + vm.funcs[0].off_f() + dest as usize;
                    assert_eq!(vm.tasks[tid].stack[at], f.to_bits());
                } else {
                    assert_eq!(value(&vm, tid, dest as usize), expected);
                }
            }
        }
    }
}

#[test]
fn native_objects_length_callbacks_keep_values_and_result_tail() {
    for nonnumber in [false, true] {
        for float in [false, true] {
            let (mut vm, tid) = fixture(if float { Op::LenF(0, 1) } else { Op::Len(0, 1) });
            let source = if nonnumber {
                "function result 0 1 8 2 v:v\nconst 0 true\nK 0 0\nRet 0\nend\n"
            } else {
                "function result 0 1 8 2 v:v\nconst 0 num 1.5\nK 0 0\nRet 0\nend\n"
            };
            crate::image::load(&mut vm, source).unwrap();
            vm.entries.resize(2, 0);
            vm.prepare_threaded();
            vm.funcs[0].ins[1].op = Code::Slow as u8;
            let object = vm.new_table();
            put(&mut vm, tid, 1, object);
            let meta = vm.new_table();
            vm.register(meta);
            let key = vm.intern("__len");
            vm.set_index(meta, key, Value::func(1));
            vm.set_metatable(object, meta);
            vm.extra[0] = Value::TRUE;
            vm.extra[1] = Value::NIL;
            vm.extra_n = 2;
            vm.last_nres = 3;
            vm.heap.stress = true;
            vm.heap.stress_steps = true;
            vm.heap.oracle = true;
            vm.heap.quarantine = true;
            let ctx = direct(&mut vm, tid, 1);
            assert_eq!(ctx.status == ST_ERROR, nonnumber && float);
            assert_eq!(
                (vm.extra[0], vm.extra[1], vm.extra_n),
                (Value::TRUE, Value::NIL, 2)
            );
            assert_eq!(ctx.last_nres, 3);
            if !float {
                assert_eq!(
                    value(&vm, tid, 0),
                    if nonnumber {
                        Value::TRUE
                    } else {
                        Value::num(1.5)
                    }
                );
            } else if nonnumber {
                let e = vm.pending_error.take().unwrap();
                assert_eq!(vm.bytes_of(e), b"runtime error: expected a number");
            }
        }
    }
}

#[test]
fn native_objects_concat_uses_shared_subtype_text_and_metatable_protocol() {
    for dest in [0u8, 1, 255] {
        for kind in 0..7 {
            let (mut vm, tid) = large_fixture(Op::Concat(dest, 1, 2));
            let left = match kind {
                0 => vm.intern("left"),
                1 => Value::num(1.0),
                2 => Value::num(-0.0),
                3 => Value::num(f64::NAN),
                4 => Value::inline_integer(1).unwrap(),
                5 => vm.box_integer(Integer {
                    bits: u64::MAX,
                    unsigned: true,
                }),
                _ => Value::TRUE,
            };
            put(&mut vm, tid, 1, left);
            let right = vm.intern("right");
            put(&mut vm, tid, 2, right);
            let expected = vm.guarded(|it| it.concat(left, right));
            let error = vm.pending_error.take().map(|v| vm.bytes_of(v).to_vec());
            let text = if error.is_none() {
                Some(vm.bytes_of(expected).to_vec())
            } else {
                None
            };
            vm.heap.stress = true;
            vm.heap.stress_steps = true;
            vm.heap.oracle = true;
            vm.heap.quarantine = true;
            assert_eq!(direct(&mut vm, tid, 1).status == ST_ERROR, error.is_some());
            if let Some(error) = error {
                let e = vm.pending_error.take().unwrap();
                assert_eq!(vm.bytes_of(e), error);
            } else {
                assert_eq!(vm.bytes_of(value(&vm, tid, dest as usize)), text.unwrap());
            }
        }
    }
    let (mut vm, tid) = fixture(Op::Concat(0, 1, 2));
    crate::image::load(&mut vm, "function identity 0 2 8 2 vv:v\nRet 1\nend\n").unwrap();
    vm.entries.resize(2, 0);
    vm.prepare_threaded();
    vm.funcs[0].ins[1].op = Code::Slow as u8;
    let object = vm.new_table();
    put(&mut vm, tid, 1, object);
    put(&mut vm, tid, 2, Value::TRUE);
    let meta = vm.new_table();
    vm.register(meta);
    let key = vm.intern("__concat");
    vm.set_index(meta, key, Value::func(1));
    vm.set_metatable(object, meta);
    assert_ne!(direct(&mut vm, tid, 1).status, ST_ERROR);
    assert_eq!(value(&vm, tid, 0), object);
}
