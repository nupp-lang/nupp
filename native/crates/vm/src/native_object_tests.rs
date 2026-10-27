use super::native_numeric_tests::{direct, fixture, intput, put, value};
use super::*;
use crate::{interp::Op, numeric::Integer, value::Value};

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

fn large_fixture(op: Op) -> (Box<crate::interp::Interp>, usize) {
    let mut vm = Box::new(crate::interp::Interp::new());
    crate::image::load(
        &mut vm,
        "function slots 0 0 255 4 :v\nRetNil\nend\nentry 0\n",
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
