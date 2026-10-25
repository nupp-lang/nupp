use super::*;

// Use the actual frame/window relation, rather than independent toy windows.
// Guard both sides of the boxed window and preserve the frame header. The
// physical representation is identical for every layout under comparison.
unsafe fn invoke_native(
    pc: *const Ins,
    regs: *mut u64,
    ints: *mut i64,
    floats: *mut f64,
    ctx: *mut Ctx,
    frame: *mut u64,
    nregs: usize,
) -> *const Ins {
    let mut storage = vec![0x5a5a_1234_5a5a_1234; 4 + nregs + 1];
    std::ptr::copy_nonoverlapping(frame, storage.as_mut_ptr(), 4);
    std::ptr::copy_nonoverlapping(regs, storage.as_mut_ptr().add(4), nregs);
    let next = nupp_native_runtime_entry(
        pc,
        storage.as_mut_ptr().add(4),
        ints,
        floats,
        ctx,
        storage.as_mut_ptr(),
    );
    assert_eq!(
        &storage[..4],
        std::slice::from_raw_parts(frame, 4),
        "native leaf changed frame header"
    );
    assert_eq!(
        storage[4 + nregs],
        0x5a5a_1234_5a5a_1234,
        "native leaf wrote past register window"
    );
    std::ptr::copy_nonoverlapping(storage.as_ptr().add(4), regs, nregs);
    next
}

#[test]
fn derived_frame_entry_rejects_nonconforming_windows_without_writes() {
    if !NATIVE_DERIVED_FRAME {
        return;
    }
    let program = [
        Ins {
            op: Code::Move as u8,
            a: 0,
            b: 1,
            ..Ins::default()
        },
        Ins::default(),
    ];
    let mut regs = [11, 22, 33, 44];
    let mut ints = [0];
    let mut floats = [0.0];
    let mut ctx: Ctx = unsafe { std::mem::zeroed() };
    let next = unsafe {
        nupp_native_runtime_entry(
            program.as_ptr(),
            regs.as_mut_ptr(),
            ints.as_mut_ptr(),
            floats.as_mut_ptr(),
            &mut ctx,
            regs.as_mut_ptr(),
        )
    };
    assert_eq!(next, program.as_ptr());
    assert_eq!(regs, [11, 22, 33, 44]);
}

#[test]
fn leaf_words_match_rust_at_extremes_with_aliasing() {
    let values = [0, 1, 63, 64, 127, 0x7fff_ffff_ffff_ffff, 1 << 63, u64::MAX];
    let operations: [(Code, fn(u64, u64) -> u64); 12] = [
        (Code::IAdd, u64::wrapping_add),
        (Code::ISub, u64::wrapping_sub),
        (Code::IAnd, |a, b| a & b),
        (Code::IOr, |a, b| a | b),
        (Code::IShl, |a, b| a.wrapping_shl(b as u32)),
        (Code::IShrU, |a, b| a.wrapping_shr(b as u32)),
        (Code::ICmpSLt, |a, b| ((a as i64) < (b as i64)) as u64),
        (Code::ICmpSLe, |a, b| ((a as i64) <= (b as i64)) as u64),
        (Code::ICmpEq, |a, b| (a == b) as u64),
        (Code::ICmpNe, |a, b| (a != b) as u64),
        (Code::ICmpLt, |a, b| (a < b) as u64),
        (Code::ICmpLe, |a, b| (a <= b) as u64),
    ];
    for (code, op) in operations {
        for x in values {
            for y in values {
                for dest in [0, 1, 255] {
                    let mut ints = [0x5555_5555_5555_5555u64; 258];
                    ints[1] = x;
                    ints[2] = y;
                    let mut expected = ints;
                    expected[dest + 1] = op(x, y);
                    let mut regs = [0xaaaa_aaaa_aaaa_aaaau64; 256];
                    let mut floats = [1.25; 256];
                    let mut frame = [0; 4];
                    // All fields are integer/float/pointer types; the leaf subset
                    // may inspect OSR flags but cannot dereference an unused field.
                    let mut ctx: Ctx = unsafe { std::mem::zeroed() };
                    let program = [
                        Ins {
                            op: code as u8,
                            a: dest as u8,
                            b: 0,
                            c: 1,
                            ..Ins::default()
                        },
                        Ins::default(),
                    ];
                    let next = unsafe {
                        invoke_native(
                            program.as_ptr(),
                            regs.as_mut_ptr(),
                            ints.as_mut_ptr().add(1).cast(),
                            floats.as_mut_ptr(),
                            &mut ctx,
                            frame.as_mut_ptr(),
                            256,
                        )
                    };
                    assert_eq!(next, unsafe { program.as_ptr().add(1) });
                    assert_eq!(ints, expected, "opcode {}", code as u8);
                    assert_eq!(regs, [0xaaaa_aaaa_aaaa_aaaau64; 256]);
                    assert_eq!(floats, [1.25; 256]);
                }
            }
        }
    }
}

// Exercise the linked Nupp-authored object directly, including destinations
// that alias a source and sentinel slots around the register windows.
unsafe fn execute_leaf(
    op: Code,
    dest: usize,
    regs: &mut [u64; 258],
    ints: &mut [i64; 258],
    floats: &mut [f64; 258],
    k: i64,
) -> bool {
    let program = [
        Ins {
            op: op as u8,
            a: dest as u8,
            b: 0,
            c: 1,
            k,
            ..Ins::default()
        },
        Ins::default(),
    ];
    let mut ctx: Ctx = std::mem::zeroed();
    let mut frame = [0; 4];
    let next = invoke_native(
        program.as_ptr(),
        regs.as_mut_ptr().add(1),
        ints.as_mut_ptr().add(1),
        floats.as_mut_ptr().add(1),
        &mut ctx,
        frame.as_mut_ptr(),
        256,
    );
    assert!(next == program.as_ptr() || next == program.as_ptr().add(1));
    next == program.as_ptr().add(1)
}

fn float_values() -> Vec<f64> {
    [
        0,
        1 << 63,
        1,
        (1 << 63) | 1,
        0x0010_0000_0000_0000,
        1.25f64.to_bits(),
        (-3.5f64).to_bits(),
        f64::MAX.to_bits(),
        f64::MIN.to_bits(),
        f64::INFINITY.to_bits(),
        f64::NEG_INFINITY.to_bits(),
        0x7ff8_0000_0000_0000,
        0x7ff0_0000_0000_0001,
        0xfff8_0000_0000_1234,
        (i64::MAX as f64).to_bits(),
        (i64::MIN as f64).to_bits(),
    ]
    .into_iter()
    .map(f64::from_bits)
    .collect()
}

#[test]
fn native_float_arithmetic_preserves_ieee_and_aliasing() {
    let operations: [(Code, fn(f64, f64) -> f64); 5] = [
        (Code::FAdd, |a, b| a + b),
        (Code::FSub, |a, b| a - b),
        (Code::FMul, |a, b| a * b),
        (Code::FDiv, |a, b| a / b),
        (Code::FMod, |a, b| a - (a / b).floor() * b),
    ];
    for (code, op) in operations {
        for x in float_values() {
            for y in float_values() {
                for dest in [0, 1, 255] {
                    let mut floats = [19.25; 258];
                    floats[1] = x;
                    floats[2] = y;
                    let mut expected = floats.map(f64::to_bits);
                    let answer = op(x, y);
                    expected[dest + 1] = answer.to_bits();
                    let mut regs = [0xa5a5; 258];
                    let mut ints = [-123; 258];
                    assert!(unsafe {
                        execute_leaf(code, dest, &mut regs, &mut ints, &mut floats, 0)
                    });
                    if answer.is_nan() {
                        assert!(floats[dest + 1].is_nan());
                        expected[dest + 1] = floats[dest + 1].to_bits();
                    }
                    assert_eq!(floats.map(f64::to_bits), expected, "opcode {}", code as u8);
                    assert_eq!(regs, [0xa5a5; 258]);
                    assert_eq!(ints, [-123; 258]);
                }
            }
        }
    }
}

#[test]
fn native_float_comparisons_include_unordered_nan() {
    let operations: [(Code, fn(f64, f64) -> bool); 4] = [
        (Code::FCmpEq, |a, b| a == b),
        (Code::FCmpNe, |a, b| a != b),
        (Code::FCmpLt, |a, b| a < b),
        (Code::FCmpLe, |a, b| a <= b),
    ];
    for (code, op) in operations {
        for x in float_values() {
            for y in float_values() {
                for dest in [0, 1, 255] {
                    let mut floats = [19.25; 258];
                    floats[1] = x;
                    floats[2] = y;
                    let before = floats.map(f64::to_bits);
                    let mut regs = [0xa5a5; 258];
                    let mut ints = [-123; 258];
                    let mut expected = ints;
                    expected[dest + 1] = op(x, y) as i64;
                    assert!(unsafe {
                        execute_leaf(code, dest, &mut regs, &mut ints, &mut floats, 0)
                    });
                    assert_eq!(ints, expected);
                    assert_eq!(regs, [0xa5a5; 258]);
                    assert_eq!(floats.map(f64::to_bits), before);
                }
            }
        }
    }
}

#[test]
fn native_float_moves_boxes_and_conversions_match_value_contract() {
    for x in float_values() {
        for dest in [0, 1, 255] {
            for code in [Code::FK, Code::FMov, Code::FNeg, Code::FBox, Code::FToI] {
                let mut floats = [19.25; 258];
                floats[1] = x;
                let mut expected_f = floats.map(f64::to_bits);
                let mut regs = [0xa5a5; 258];
                let mut expected_r = regs;
                let mut ints = [-123; 258];
                let mut expected_i = ints;
                match code {
                    Code::FK | Code::FMov => expected_f[dest + 1] = x.to_bits(),
                    Code::FNeg => expected_f[dest + 1] = (-x).to_bits(),
                    Code::FBox => expected_r[dest + 1] = Value::num(x).0,
                    Code::FToI => expected_i[dest + 1] = x as i64,
                    _ => unreachable!(),
                }
                assert!(unsafe {
                    execute_leaf(
                        code,
                        dest,
                        &mut regs,
                        &mut ints,
                        &mut floats,
                        x.to_bits() as i64,
                    )
                });
                assert_eq!(regs, expected_r);
                assert_eq!(ints, expected_i);
                assert_eq!(
                    floats.map(f64::to_bits),
                    expected_f,
                    "opcode {}",
                    code as u8
                );
            }
        }
    }
    let mut words: Vec<u64> = float_values().iter().map(|f| f.to_bits()).collect();
    for tag in 0..8 {
        words.push(crate::value::QNAN | (tag << 48) | 123);
    }
    words.extend([Value::NIL.0, Value::FALSE.0, Value::TRUE.0]);
    for word in words {
        for dest in [0, 1, 255] {
            let mut floats = [19.25; 258];
            let mut expected = floats.map(f64::to_bits);
            let mut regs = [0xa5a5; 258];
            regs[1] = word;
            let before = regs;
            let mut ints = [-123; 258];
            let valid = Value(word).is_num();
            if valid {
                expected[dest + 1] = word;
            }
            assert_eq!(
                unsafe { execute_leaf(Code::FUnbox, dest, &mut regs, &mut ints, &mut floats, 0) },
                valid
            );
            assert_eq!(regs, before);
            assert_eq!(ints, [-123; 258]);
            assert_eq!(floats.map(f64::to_bits), expected);
        }
    }
    for x in [
        i64::MIN,
        i64::MIN + 1,
        -9007199254740993,
        -1,
        0,
        1,
        9007199254740993,
        i64::MAX,
    ] {
        let mut floats = [19.25; 258];
        let mut expected = floats.map(f64::to_bits);
        expected[256] = (x as f64).to_bits();
        let mut regs = [0xa5a5; 258];
        let mut ints = [-123; 258];
        ints[1] = x;
        let before = ints;
        assert!(unsafe { execute_leaf(Code::IToF, 255, &mut regs, &mut ints, &mut floats, 0) });
        assert_eq!(floats.map(f64::to_bits), expected);
        assert_eq!(ints, before);
        assert_eq!(regs, [0xa5a5; 258]);
    }
}

#[test]
fn native_cell_read_checks_tag_and_kind_before_loading_payload() {
    let mut payload = Value::num(-42.5).0;
    let mut header: Header = unsafe { std::mem::zeroed() };
    header.aux_ptr = (&mut payload as *mut u64).cast();
    for kind in [KIND_CELL, KIND_CLOSURE, KIND_STR] {
        header.kind = kind;
        let object = Value::obj(std::ptr::NonNull::from(&mut header)).0;
        for word in [
            object,
            Value::NIL.0,
            Value::FALSE.0,
            Value::num(1.0).0,
            crate::value::QNAN,
        ] {
            for dest in [0, 1, 255] {
                let valid = kind == KIND_CELL && word == object;
                let mut regs = [0xa5a5; 258];
                regs[1] = word;
                let mut expected = regs;
                if valid {
                    expected[dest + 1] = payload;
                }
                let mut ints = [-123; 258];
                let mut floats = [19.25; 258];
                assert_eq!(
                    unsafe {
                        execute_leaf(Code::GetCell, dest, &mut regs, &mut ints, &mut floats, 0)
                    },
                    valid
                );
                assert_eq!(regs, expected);
                assert_eq!(ints, [-123; 258]);
                assert_eq!(floats, [19.25; 258]);
            }
        }
    }
}

#[test]
fn native_boxed_math_matches_numbers_and_leaves_tags_untouched() {
    let mut values: Vec<u64> = float_values().iter().map(|v| Value::num(*v).0).collect();
    values.extend([
        Value::NIL.0,
        Value::TRUE.0,
        Value::FALSE.0,
        Value::func(2).0,
    ]);
    let ops: [(Code, fn(f64, f64) -> u64); 6] = [
        (Code::Add, |a, b| Value::num(a + b).0),
        (Code::Sub, |a, b| Value::num(a - b).0),
        (Code::Mul, |a, b| Value::num(a * b).0),
        (Code::Mod, |a, b| Value::num(a - (a / b).floor() * b).0),
        (Code::Lt, |a, b| Value::boolean(a < b).0),
        (Code::Le, |a, b| Value::boolean(a <= b).0),
    ];
    for (code, op) in ops {
        for &x in &values {
            for &y in &values {
                for dest in [0, 1, 255] {
                    let mut regs = [0xa5a5; 258];
                    regs[1] = x;
                    regs[2] = y;
                    let mut expected = regs;
                    let valid = Value(x).is_num() && Value(y).is_num();
                    if valid {
                        expected[dest + 1] = op(f64::from_bits(x), f64::from_bits(y));
                    }
                    let mut ints = [-123; 258];
                    let mut floats = [19.25; 258];
                    assert_eq!(
                        unsafe { execute_leaf(code, dest, &mut regs, &mut ints, &mut floats, 0) },
                        valid
                    );
                    assert_eq!(regs, expected, "opcode {}", code as u8);
                    assert_eq!(ints, [-123; 258]);
                    assert_eq!(floats, [19.25; 258]);
                }
            }
        }
    }
    for x in values {
        for dest in [0, 1, 255] {
            for code in [Code::Neg, Code::Not, Code::Truthy, Code::BoolFromI] {
                let mut regs = [0xa5a5; 258];
                regs[1] = x;
                let mut expected_r = regs;
                let mut ints = [-123; 258];
                ints[1] = x as i64;
                let mut expected_i = ints;
                let mut floats = [19.25; 258];
                let valid = !matches!(code, Code::Neg) || Value(x).is_num();
                match code {
                    Code::Neg if valid => expected_r[dest + 1] = Value::num(-f64::from_bits(x)).0,
                    Code::Not => expected_r[dest + 1] = Value::boolean(!Value(x).truthy()).0,
                    Code::Truthy => expected_i[dest + 1] = Value(x).truthy() as i64,
                    Code::BoolFromI => expected_r[dest + 1] = Value::boolean(x != 0).0,
                    _ => {}
                }
                assert_eq!(
                    unsafe { execute_leaf(code, dest, &mut regs, &mut ints, &mut floats, 0) },
                    valid
                );
                assert_eq!(regs, expected_r);
                assert_eq!(ints, expected_i);
                assert_eq!(floats, [19.25; 258]);
            }
        }
    }
}

#[test]
fn native_constants_and_upvalues_use_the_entry_context_and_frame() {
    let consts = [Value::TRUE.0, Value::num(23.0).0, Value::FALSE.0];
    let mut info: [FuncInfo; 3] = unsafe { std::mem::zeroed() };
    info[2].consts = consts.as_ptr();
    let mut captured = [Value::num(98.0).0; 256];
    captured[255] = Value::num(65.0).0;
    let mut closure: Header = unsafe { std::mem::zeroed() };
    closure.kind = KIND_CLOSURE;
    closure.aux_ptr = captured.as_mut_ptr().cast();
    let object = Value::obj(std::ptr::NonNull::from(&mut closure)).0;
    for value in [object, Value::NIL.0, Value::num(123.0).0] {
        let program = [
            Ins {
                op: Code::K as u8,
                a: 255,
                imm: 1,
                ..Ins::default()
            },
            Ins {
                op: Code::GetUpval as u8,
                a: 0,
                b: 255,
                ..Ins::default()
            },
            Ins::default(),
        ];
        let mut ctx: Ctx = unsafe { std::mem::zeroed() };
        ctx.funcs = info.as_ptr();
        ctx.nfuncs = 3;
        let mut frame = [(54321u64 << 32) | 2, 0, value, 0];
        let oldframe = frame;
        let mut regs = [0xa5a5; 258];
        let mut ints = [-123; 258];
        let mut floats = [19.25; 258];
        let next = unsafe {
            invoke_native(
                program.as_ptr(),
                regs.as_mut_ptr().add(1),
                ints.as_mut_ptr().add(1),
                floats.as_mut_ptr().add(1),
                &mut ctx,
                frame.as_mut_ptr(),
                256,
            )
        };
        assert_eq!(next, unsafe {
            program.as_ptr().add(if value == object { 2 } else { 1 })
        });
        let mut expected = [0xa5a5; 258];
        expected[256] = consts[1];
        if value == object {
            expected[1] = captured[255];
        }
        assert_eq!(regs, expected);
        assert_eq!(ints, [-123; 258]);
        assert_eq!(floats, [19.25; 258]);
        assert_eq!(frame, oldframe);
    }
}

#[test]
fn native_value_branches_yield_only_for_taken_osr_edges() {
    for code in [Code::JmpIf, Code::JmpIfNot] {
        for value in [
            Value::NIL.0,
            Value::FALSE.0,
            Value::TRUE.0,
            Value::num(0.0).0,
            crate::value::QNAN,
        ] {
            for displacement in [-2, 1] {
                for mode in [0, 1] {
                    for jit in [0, 1] {
                        for entries in [0, 1] {
                            let mut program = [Ins::default(); 5];
                            program[2] = Ins {
                                op: code as u8,
                                a: 0,
                                imm: displacement,
                                ..Ins::default()
                            };
                            let mut ctx: Ctx = unsafe { std::mem::zeroed() };
                            ctx.frame_mode = mode;
                            ctx.jit_frames = jit;
                            ctx.nframe_entries = entries;
                            let mut regs = [value];
                            let mut ints = [-123];
                            let mut floats = [19.25];
                            let mut frame = [0; 4];
                            let taken = Value(value).truthy() == (matches!(code, Code::JmpIf));
                            let expected = if taken
                                && displacement < 0
                                && mode != 0
                                && (jit != 0 || entries != 0)
                            {
                                2
                            } else if taken {
                                (3 + displacement) as usize
                            } else {
                                3
                            };
                            let next = unsafe {
                                invoke_native(
                                    program.as_ptr().add(2),
                                    regs.as_mut_ptr(),
                                    ints.as_mut_ptr(),
                                    floats.as_mut_ptr(),
                                    &mut ctx,
                                    frame.as_mut_ptr(),
                                    1,
                                )
                            };
                            assert_eq!(next, unsafe { program.as_ptr().add(expected) });
                            assert_eq!(regs, [value]);
                            assert_eq!(ints, [-123]);
                            assert_eq!(floats, [19.25]);
                        }
                    }
                }
            }
        }
    }
}

#[test]
fn back_edges_finish_without_native_recursion_and_yield_before_osr() {
    let program = [
        Ins {
            op: Code::IAddK as u8,
            a: 0,
            b: 0,
            k: -1,
            ..Ins::default()
        },
        Ins {
            op: Code::JmpIfIZero as u8,
            a: 0,
            imm: 1,
            ..Ins::default()
        },
        Ins {
            op: Code::Jmp as u8,
            imm: -3,
            ..Ins::default()
        },
        Ins::default(),
    ];
    for (jit, entries) in [(0, 0), (1, 0), (0, 1)] {
        let mut ctx: Ctx = unsafe { std::mem::zeroed() };
        ctx.frame_mode = 1;
        ctx.jit_frames = jit;
        ctx.nframe_entries = entries;
        let mut ints = [1_000_000];
        let mut regs = [0];
        let mut floats = [0.0];
        let mut frame = [0; 4];
        let next = unsafe {
            invoke_native(
                program.as_ptr(),
                regs.as_mut_ptr(),
                ints.as_mut_ptr(),
                floats.as_mut_ptr(),
                &mut ctx,
                frame.as_mut_ptr(),
                1,
            )
        };
        let osr = jit != 0 || entries != 0;
        assert_eq!(next, unsafe {
            program.as_ptr().add(if osr { 2 } else { 3 })
        });
        assert_eq!(ints[0], if osr { 999_999 } else { 0 });
    }
}

#[repr(C)]
struct NativeTableFixture {
    header: Header,
    payload: crate::heap::TablePayload,
}
impl NativeTableFixture {
    fn new(values: &[Value]) -> Box<Self> {
        let mut fixture = Box::new(Self {
            header: unsafe { std::mem::zeroed() },
            payload: crate::heap::TablePayload {
                array: values.to_vec(),
                hash: Default::default(),
                meta: Value::NIL,
            },
        });
        fixture.header.kind = KIND_TABLE;
        fixture.header.aux_len = values.len() as u64;
        fixture.header.aux_ptr = fixture.payload.array.as_mut_ptr().cast();
        fixture
    }
    fn value(&mut self) -> u64 {
        Value::obj(std::ptr::NonNull::from(&mut self.header)).0
    }
}

#[test]
fn native_array_reads_guard_bounds_integrality_and_metatables() {
    let mut table = NativeTableFixture::new(&[Value::num(12.0), Value::NIL, Value::TRUE]);
    for kind in [KIND_TABLE, KIND_RECORD] {
        for meta in [Value::NIL, Value::TRUE] {
            table.header.kind = kind;
            table.payload.meta = meta;
            for word in [table.value(), Value::NIL.0, Value::num(4.0).0] {
                for index in [
                    -1.0,
                    -0.0,
                    0.5,
                    1.0,
                    1.5,
                    2.0,
                    3.0,
                    4.0,
                    f64::NAN,
                    f64::INFINITY,
                    9223372036854775808.0,
                ] {
                    for code in [Code::GetIdxF, Code::GetIdxI] {
                        for dest in [0, 1, 255] {
                            let mut regs = [0xa5a5; 258];
                            regs[1] = word;
                            let mut ints = [-123; 258];
                            ints[2] = index as i64;
                            let mut floats = [19.25; 258];
                            floats[2] = index;
                            let oldints = ints;
                            let oldfloats = floats.map(f64::to_bits);
                            let d = if matches!(code, Code::GetIdxI) {
                                ints[2] as f64
                            } else {
                                index
                            };
                            let slot = d as usize;
                            let valid = kind == KIND_TABLE
                                && word == table.value()
                                && d >= 1.0
                                && d <= 3.0
                                && d == slot as f64
                                && (slot != 2 || meta == Value::NIL);
                            let mut expected = regs;
                            if valid {
                                expected[dest + 1] = table.payload.array[slot - 1].0;
                            }
                            assert_eq!(
                                unsafe {
                                    execute_leaf(code, dest, &mut regs, &mut ints, &mut floats, 0)
                                },
                                valid
                            );
                            assert_eq!(regs, expected);
                            assert_eq!(ints, oldints);
                            assert_eq!(floats.map(f64::to_bits), oldfloats);
                        }
                    }
                }
            }
        }
    }
}

#[test]
fn native_record_reads_check_shape_number_and_nil_metamethods() {
    let mut record = NativeTableFixture::new(&[Value::NIL, Value::NIL]);
    for kind in [KIND_RECORD, KIND_TABLE] {
        for shape in [0, 1, u32::MAX] {
            for flags in [0, F_METATABLE] {
                record.header.kind = kind;
                record.header.aux = shape;
                record.header.flags = flags;
                for value in [
                    Value::NIL,
                    Value::num(-0.0),
                    Value::num(f64::NAN),
                    Value::TRUE,
                ] {
                    record.payload.array[1] = value;
                    for code in [Code::GetSlot, Code::GetSlotF] {
                        for dest in [0, 1, 255] {
                            let mut regs = [0xa5a5; 258];
                            regs[1] = record.value();
                            let mut expected_r = regs;
                            let mut floats = [19.25; 258];
                            let mut expected_f = floats.map(f64::to_bits);
                            let mut ints = [-123; 258];
                            let valid = kind == KIND_RECORD
                                && shape == 0
                                && if matches!(code, Code::GetSlotF) {
                                    value.is_num()
                                } else {
                                    value != Value::NIL || flags & F_METATABLE == 0
                                };
                            if valid {
                                if matches!(code, Code::GetSlotF) {
                                    expected_f[dest + 1] = value.0;
                                } else {
                                    expected_r[dest + 1] = value.0;
                                }
                            }
                            assert_eq!(
                                unsafe {
                                    execute_leaf(code, dest, &mut regs, &mut ints, &mut floats, 0)
                                },
                                valid
                            );
                            assert_eq!(regs, expected_r);
                            assert_eq!(floats.map(f64::to_bits), expected_f);
                            assert_eq!(ints, [-123; 258]);
                        }
                    }
                }
            }
        }
    }
}

#[test]
fn native_lengths_preserve_unsigned_conversion_and_kind_guards() {
    let mut object = NativeTableFixture::new(&[]);
    for kind in [KIND_TABLE, KIND_STR, KIND_SLICE, KIND_RECORD] {
        for meta in [Value::NIL, Value::TRUE] {
            object.header.kind = kind;
            object.payload.meta = meta;
            for length in [0, 1, 9007199254740993, 1 << 63, u64::MAX] {
                object.header.aux_len = length;
                for word in [object.value(), Value::NIL.0] {
                    for code in [Code::Len, Code::LenF] {
                        for dest in [0, 1, 255] {
                            let mut regs = [0xa5a5; 258];
                            regs[1] = word;
                            let mut expected_r = regs;
                            let mut floats = [19.25; 258];
                            let mut expected_f = floats.map(f64::to_bits);
                            let mut ints = [-123; 258];
                            let valid = word == object.value()
                                && (kind == KIND_STR
                                    || kind == KIND_SLICE
                                    || (kind == KIND_TABLE && meta == Value::NIL));
                            if valid {
                                if matches!(code, Code::LenF) {
                                    expected_f[dest + 1] = (length as f64).to_bits();
                                } else {
                                    expected_r[dest + 1] = Value::num(length as f64).0;
                                }
                            }
                            assert_eq!(
                                unsafe {
                                    execute_leaf(code, dest, &mut regs, &mut ints, &mut floats, 0)
                                },
                                valid
                            );
                            assert_eq!(regs, expected_r);
                            assert_eq!(floats.map(f64::to_bits), expected_f);
                            assert_eq!(ints, [-123; 258]);
                        }
                    }
                }
            }
        }
    }
}
