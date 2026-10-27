use super::*;
use crate::interp::{Interp, Op};

fn fixture(op: Op) -> (Box<Interp>, usize) {
    let mut vm = Box::new(Interp::new());
    crate::image::load(
        &mut vm,
        "function bytes 0 0 16 8 :v\nRetNil\nend\nentry 0\n",
    )
    .unwrap();
    vm.funcs[0].code = vec![op, Op::RetNil];
    vm.entries.resize(1, 0);
    vm.prepare_threaded();
    vm.funcs[0].ins[1] = Ins::default();
    let tid = vm.spawn(0, &[]);
    (vm, tid)
}
fn value_set(vm: &mut Interp, tid: usize, slot: usize, value: Value) {
    let at = vm.tasks[tid].cur() + 4 + slot;
    vm.tasks[tid].stack[at] = value.0;
}
fn integer_set(vm: &mut Interp, tid: usize, slot: usize, value: i64) {
    let at = vm.tasks[tid].cur() + vm.funcs[0].off_i() + slot;
    vm.tasks[tid].stack[at] = value as u64;
}
fn value_get(vm: &Interp, tid: usize, slot: usize) -> Value {
    Value(vm.tasks[tid].stack[vm.tasks[tid].cur() + 4 + slot])
}
fn integer_get(vm: &Interp, tid: usize, slot: usize) -> u64 {
    vm.tasks[tid].stack[vm.tasks[tid].cur() + vm.funcs[0].off_i() + slot]
}
fn run(vm: &mut Interp, tid: usize, native: bool) -> Option<String> {
    let error = if native {
        let mut ctx: Ctx = unsafe { std::mem::zeroed() };
        ctx.interp = (vm as *mut Interp).cast();
        ctx.tid = tid as u64;
        crate::threaded::sync(&mut ctx, vm);
        let f = &vm.funcs[0];
        assert_ne!(f.ins[0].op, Code::Slow as u8);
        let pc = f.ins.as_ptr();
        let frame = unsafe { vm.tasks[tid].stack.as_mut_ptr().add(vm.tasks[tid].cur()) };
        let next = unsafe {
            nupp_native_runtime_entry(
                pc,
                frame.add(4),
                frame.add(f.off_i()).cast(),
                frame.add(f.off_f()).cast(),
                &mut ctx,
                frame,
            )
        };
        if ctx.status == ST_ERROR {
            assert_eq!(next, 0);
            vm.pending_error.take()
        } else {
            assert_eq!(
                next,
                unsafe { pc.add(1) } as u64,
                "opcode must advance without Rust step"
            );
            None
        }
    } else {
        // Compare full-chain and one-handler transport of the same Nupp body.
        std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| vm.native_handler_step(tid, 0)))
            .err()
            .map(|p| vm.error_value(p))
    };
    error.map(|v| String::from_utf8_lossy(vm.bytes_of(v)).into_owned())
}
fn source(vm: &mut Interp, carrier: usize, data: &[u8]) -> Value {
    match carrier {
        0 => vm.new_string_bytes(data),
        1 => {
            let owner = vm.new_string_bytes(data);
            vm.register(owner);
            vm.new_slice(owner, 0, data.len() as u32)
        }
        2 => {
            let v = vm.heap_new_bytes(data.len());
            vm.bytes_mut(v).copy_from_slice(data);
            v
        }
        3 => Value::TRUE,
        5 => {
            let v = vm.heap_new_aligned_bytes(data.len(), 16);
            vm.bytes_mut(v).copy_from_slice(data);
            v
        }
        _ => vm.new_table(),
    }
}

#[test]
fn native_byte_read_encodings_bounds_and_error_precedence_match_reference() {
    let data = [0, 1, 0xff, 0x80, 0x78, 0x56, 0x34, 0x12];
    for which in 0..4 {
        for carrier in 0..6 {
            for index in [0i64, 1, 2, 7, 8, -1, i64::MIN, 1i64 << 62] {
                let mut expected = None;
                for native in [false, true] {
                    let op = match which {
                        0 => Op::BytesLen(0, 1),
                        1 => Op::LoadU8(0, 1, 0),
                        2 => Op::LoadU8K(0, 1, 0),
                        _ => Op::LoadU32W(0, 1, 0),
                    };
                    let (mut vm, tid) = fixture(op);
                    let input = source(&mut vm, carrier, &data);
                    value_set(&mut vm, tid, 1, input);
                    integer_set(&mut vm, tid, 0, index);
                    vm.execution_limit = Some(11);
                    vm.instruction_budget = Some(0);
                    let error = run(&mut vm, tid, native);
                    let row = (
                        error,
                        integer_get(&vm, tid, 0),
                        vm.execution_limit,
                        vm.instruction_budget,
                    );
                    if let Some(expected) = &expected {
                        assert_eq!(&row, expected, "op {which} carrier {carrier} index {index}");
                    } else {
                        expected = Some(row);
                    }
                }
            }
        }
    }
}

#[test]
fn native_byte_stores_are_little_endian_truncate_and_keep_failed_writes_atomic() {
    for word in [false, true] {
        for carrier in 0..6 {
            for index in [0i64, 1, 4, 5, 8, -1, i64::MIN] {
                let mut expected = None;
                for native in [false, true] {
                    let (mut vm, tid) = fixture(if word {
                        Op::StoreU32(1, 0, 1)
                    } else {
                        Op::StoreU8(1, 0, 1)
                    });
                    let input = source(&mut vm, carrier, &[0xa5; 8]);
                    value_set(&mut vm, tid, 1, input);
                    integer_set(&mut vm, tid, 0, index);
                    integer_set(&mut vm, tid, 1, 0xfedcba9876543210u64 as i64);
                    let error = run(&mut vm, tid, native);
                    let data = if carrier < 3 || carrier == 5 {
                        vm.bytes_of(input).to_vec()
                    } else {
                        vec![]
                    };
                    let row = (error, data);
                    if let Some(expected) = &expected {
                        assert_eq!(
                            &row, expected,
                            "word {word} carrier {carrier} index {index}"
                        );
                    } else {
                        expected = Some(row);
                    }
                }
            }
        }
    }
}

#[test]
fn native_substrings_and_prefixes_preserve_binary_bytes_aliases_and_gc_roots() {
    let data = (0..83u8).collect::<Vec<_>>();
    for substring in [false, true] {
        for carrier in 0..6 {
            for (first, last) in [
                (1, 40),
                (1, 41),
                (-9, 200),
                (90, 95),
                (30, 4),
                (0, 0),
                (2, 8),
                (i64::MIN, i64::MAX),
            ] {
                for dest in [0u8, 1] {
                    let mut expected = None;
                    for native in [false, true] {
                        let (mut vm, tid) = fixture(if substring {
                            Op::Substring(dest, 1, 0, 1)
                        } else {
                            Op::BytesToStr(dest, 1, 1)
                        });
                        let input = source(&mut vm, carrier, &data);
                        value_set(&mut vm, tid, 1, input);
                        integer_set(&mut vm, tid, 0, first);
                        integer_set(&mut vm, tid, 1, last);
                        vm.heap.stress = true;
                        vm.heap.stress_steps = true;
                        vm.heap.oracle = true;
                        vm.heap.quarantine = true;
                        let error = run(&mut vm, tid, native);
                        let result = if error.is_none() {
                            let v = value_get(&vm, tid, dest as usize);
                            Some((vm.bytes_of(v).to_vec(), unsafe {
                                v.as_obj().unwrap().as_ref().flags & crate::heap::F_INTERNED != 0
                            }))
                        } else {
                            None
                        };
                        vm.full_cycle();
                        vm.check_oracle();
                        let row = (error, result);
                        if let Some(expected) = &expected {
                            assert_eq!(
                                &row, expected,
                                "substring {substring} carrier {carrier} range {first}..{last} dest {dest}"
                            );
                        } else {
                            expected = Some(row);
                        }
                    }
                }
            }
        }
    }
}

#[test]
fn native_buffer_allocation_append_consume_and_fixed_owner_errors_match_reference() {
    for scenario in 0..9 {
        let mut expected = None;
        for native in [false, true] {
            let op = match scenario {
                0 => Op::NewBytes(0, 0),
                1 => Op::NewBuffer(0),
                2..=4 => Op::BufAppend(1, 2),
                5 => Op::BufAppendSub(1, 2, 0, 1),
                8 => Op::BufFinish(1, 1),
                _ => Op::BufFinish(0, 1),
            };
            let (mut vm, tid) = fixture(op);
            let input = if scenario == 7 {
                vm.heap_new_aligned_bytes(8, 16)
            } else {
                vm.heap_new_buffer()
            };
            vm.register(input);
            if scenario != 7 {
                vm.buf_append(input, &[0xab; 63]);
            }
            let src = if scenario == 3 {
                input
            } else if scenario == 4 {
                vm.new_slice(input, 1, 61)
            } else {
                vm.new_string_bytes(&[0x12; 80])
            };
            value_set(&mut vm, tid, 1, input);
            value_set(&mut vm, tid, 2, src);
            integer_set(&mut vm, tid, 0, 3);
            integer_set(&mut vm, tid, 1, 70);
            vm.heap.stress = true;
            vm.heap.stress_steps = true;
            vm.heap.oracle = true;
            vm.heap.quarantine = true;
            let error = run(&mut vm, tid, native);
            let result = if error.is_none() && (scenario < 2 || scenario >= 6) {
                let v = value_get(&vm, tid, if scenario == 8 { 1 } else { 0 });
                Some(vm.bytes_of(v).to_vec())
            } else {
                None
            };
            let row = (error, result, vm.bytes_of(input).to_vec());
            vm.full_cycle();
            vm.check_oracle();
            if let Some(expected) = &expected {
                assert_eq!(&row, expected, "buffer scenario {scenario}");
            } else {
                expected = Some(row);
            }
        }
    }
}

#[test]
fn all_thirteen_byte_opcodes_encode_without_operand_loss() {
    let ops = [
        Op::BytesLen(255, 254),
        Op::LoadU8(255, 254, 253),
        Op::LoadU8K(255, 254, 253),
        Op::LoadU32W(255, 254, 253),
        Op::StoreU8(255, 254, 253),
        Op::StoreU32(255, 254, 253),
        Op::NewBytes(255, 254),
        Op::BytesToStr(255, 254, 253),
        Op::NewBuffer(255),
        Op::BufAppend(255, 254),
        Op::BufAppendSub(255, 254, 253, 252),
        Op::Substring(255, 254, 253, 252),
        Op::BufFinish(255, 254),
    ];
    for op in ops {
        let i = crate::threaded::encode(&op);
        assert_ne!(i.op, Code::Slow as u8);
        assert_eq!(i.a, 255);
        match op {
            Op::BufAppendSub(..) | Op::Substring(..) => {
                assert_eq!(i.b, 254);
                assert_eq!(i.c, 253);
                assert_eq!(i.imm, 252);
            }
            Op::NewBuffer(..) => (),
            _ => assert_eq!(i.b, 254),
        }
    }
}
