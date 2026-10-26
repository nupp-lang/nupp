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
    next as *const Ins
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
    assert_eq!(next, program.as_ptr() as u64);
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

// Frame transitions. The native call and return handlers run against a real
// task stack, function table and context, and are compared with the Rust
// core's own `push` and with the stack a Rust return leaves. An exit word is
// the instruction to resume at, or `EXIT_REENTER` when the frame driver has
// a say over the frame the native chain already pushed or popped.
struct Machine {
    stack: Vec<u64>,
    funcs: Vec<FuncInfo>,
    codes: Vec<Vec<Ins>>,
    entries: Vec<u64>,
    frame_entries: Vec<u64>,
    ctx: Ctx,
}

const TEST_FRAME_WORDS: u32 = 4 + 8 + 1 + 2 + 2;

impl Machine {
    /// Two functions: the caller at frame 0, and a callee with `nparams`.
    fn new(caller: Vec<Ins>, callee: Vec<Ins>, nparams: u32) -> Box<Self> {
        let mut m = Box::new(Self {
            stack: vec![0x5a5a_0000_0000_5a5a; 4096],
            funcs: Vec::new(),
            codes: vec![caller, callee],
            entries: vec![0, 0],
            frame_entries: Vec::new(),
            ctx: unsafe { std::mem::zeroed() },
        });
        for (fid, np) in [(0, 0), (1, nparams)] {
            m.funcs.push(FuncInfo {
                code: m.codes[fid].as_ptr(),
                consts: std::ptr::null(),
                frame_words: TEST_FRAME_WORDS,
                nregs: 8,
                nparams: np,
                off_i: 4 + 8 + 1,
                off_f: 4 + 8 + 1 + 2,
                vararg: 0,
                ncode: m.codes[fid].len() as u32,
                calls: 0,
                typed: 0,
                native: 0,
            });
        }
        m.stack[0] = 0;
        m.stack[1] = u32::MAX as u64;
        m.stack[2] = NIL;
        m.stack[3] = (TEST_FRAME_WORDS as u64) << 33;
        m.sync();
        m
    }
    fn sync(&mut self) {
        self.ctx.stack = self.stack.as_mut_ptr();
        self.ctx.cap = self.stack.len() as u64;
        self.ctx.funcs = self.funcs.as_ptr();
        self.ctx.nfuncs = self.funcs.len() as u64;
        self.ctx.entries = self.entries.as_ptr();
        self.ctx.frame_entries = self.frame_entries.as_ptr();
        self.ctx.nframe_entries = self.frame_entries.len() as u64;
        self.ctx.guard = NO_GUARD;
        self.ctx.unavailable_fid = u32::MAX;
    }
    fn frame(&mut self) -> *mut u64 {
        unsafe { self.stack.as_mut_ptr().add(self.ctx.cur as usize) }
    }
    /// Runs the native chain from `pc` of the top frame's function.
    unsafe fn run(&mut self, pc: usize) -> u64 {
        let frame = self.frame();
        let fid = (*frame & 0xffff_ffff) as usize;
        let fi = &self.funcs[fid];
        nupp_native_runtime_entry(
            fi.code.add(pc),
            frame.add(HDR),
            frame.add(fi.off_i as usize).cast(),
            frame.add(fi.off_f as usize).cast(),
            &mut self.ctx,
            frame,
        )
    }
    fn code(&self, fid: usize, pc: usize) -> u64 {
        unsafe { self.codes[fid].as_ptr().add(pc) as u64 }
    }
}

fn closure_header(fid: u32) -> Box<Header> {
    let mut header: Box<Header> = Box::new(unsafe { std::mem::zeroed() });
    header.kind = KIND_CLOSURE;
    header.aux = fid;
    header
}

#[test]
fn native_calls_push_the_frame_rust_pushes() {
    if !NATIVE_DERIVED_FRAME {
        return;
    }
    let mut closure = closure_header(1);
    let closure_value = Value::obj(std::ptr::NonNull::from(&mut *closure)).0;
    for nparams in 0..=4u32 {
        for nargs in 0..=5u8 {
            for (code, callee_word) in [
                (Code::Call, 0),
                (Code::CallK, Value::func(1).0),
                (Code::CallK, closure_value),
                (Code::CallDyn, Value::func(1).0),
                (Code::CallDyn, closure_value),
            ] {
                for (frame_mode, jit_frames, native, frame_entry) in
                    [(0, 0, 0, 0), (1, 0, 0, 0), (1, 1, 0, 0), (1, 0, 1, 0), (1, 0, 0, 7)]
                {
                    // Reg 1 holds the callee value, the argument window starts
                    // at reg 2, so the results land at reg 2.
                    let ins = if matches!(code, Code::Call) {
                        Ins { op: code as u8, a: 2, b: nargs, k: 1, ..Ins::default() }
                    } else {
                        Ins { op: code as u8, a: 1, b: 2, c: nargs, ..Ins::default() }
                    };
                    let caller = vec![Ins::default(), ins, Ins::default()];
                    let callee = vec![Ins::default()];
                    let mut m = Machine::new(caller, callee, nparams);
                    m.funcs[1].native = native;
                    if frame_entry != 0 {
                        m.frame_entries = vec![0, frame_entry];
                    }
                    m.ctx.frame_mode = frame_mode;
                    m.ctx.jit_frames = jit_frames;
                    m.sync();
                    m.stack[HDR + 1] = callee_word;
                    for i in 0..8 {
                        m.stack[HDR + 2 + i] = Value::num(100.0 + i as f64).0;
                    }
                    let mut expected = m.stack.clone();
                    let copied = if matches!(code, Code::Call) { nargs as u32 } else { (nargs as u32).min(nparams) };
                    let mut reference: Ctx = unsafe { std::mem::zeroed() };
                    reference.stack = expected.as_mut_ptr();
                    reference.cap = expected.len() as u64;
                    reference.funcs = m.funcs.as_ptr();
                    unsafe {
                        push(
                            &mut reference,
                            expected.as_mut_ptr(),
                            1,
                            (HDR + 2) as u32,
                            copied,
                            2,
                            if callee_word == closure_value { closure_value } else { NIL },
                        );
                    }
                    let exit = unsafe { m.run(1) };
                    let pushed = TEST_FRAME_WORDS as u64;
                    assert_eq!(m.ctx.cur, pushed, "opcode {} nargs {nargs} nparams {nparams}", code as u8);
                    assert_eq!(m.ctx.cur, reference.cur);
                    assert_eq!(m.stack, expected, "opcode {} nargs {nargs} nparams {nparams}", code as u8);
                    let driver = frame_mode != 0 && (jit_frames != 0 || native != 0 || frame_entry != 0);
                    if driver {
                        assert_eq!(exit, EXIT_REENTER, "opcode {} frame driver policy", code as u8);
                    } else {
                        assert_eq!(exit, m.code(1, 0), "opcode {} continues in the callee", code as u8);
                    }
                }
            }
        }
    }
}

#[test]
fn native_calls_leave_unsupported_calls_untouched() {
    if !NATIVE_DERIVED_FRAME {
        return;
    }
    let mut closure = closure_header(1);
    let closure_value = Value::obj(std::ptr::NonNull::from(&mut *closure)).0;
    let mut iter = closure_header(1);
    iter.kind = KIND_ITER;
    let iter_value = Value::obj(std::ptr::NonNull::from(&mut *iter)).0;
    let call = Ins { op: Code::Call as u8, a: 2, b: 1, k: 1, ..Ins::default() };
    let callk = Ins { op: Code::CallK as u8, a: 1, b: 2, c: 1, ..Ins::default() };
    type Setup = fn(&mut Machine);
    let cases: Vec<(&str, Ins, u64, Setup)> = vec![
        ("vararg", call, 0, |m| m.funcs[1].vararg = 1),
        ("vararg dynamic", callk, Value::func(1).0, |m| m.funcs[1].vararg = 1),
        ("typed dynamic", callk, Value::func(1).0, |m| m.funcs[1].typed = 1),
        ("unavailable", callk, closure_value, |m| m.ctx.unavailable_fid = 1),
        ("compiled entry", callk, closure_value, |m| m.entries[1] = 0x1000),
        ("feedback", callk, closure_value, |m| m.ctx.feedback = 1),
        ("builtin", callk, Value::builtin(3).0, |_| {}),
        ("iterator", callk, iter_value, |_| {}),
        ("not callable", callk, Value::num(1.0).0, |_| {}),
        ("unknown function", callk, Value::func(9).0, |_| {}),
        ("wide argument count", Ins { c: 64, ..callk }, closure_value, |_| {}),
        ("wide static count", Ins { b: 64, ..call }, 0, |_| {}),
        ("growth", call, 0, |m| m.ctx.cap = (TEST_FRAME_WORDS * 2 - 1) as u64),
        ("growth dynamic", callk, closure_value, |m| m.ctx.cap = (TEST_FRAME_WORDS * 2 - 1) as u64),
    ];
    for (name, ins, callee_word, setup) in cases {
        let mut m = Machine::new(vec![Ins::default(), ins, Ins::default()], vec![Ins::default()], 1);
        m.stack[HDR + 1] = callee_word;
        m.stack[HDR + 3] = Value::num(7.0).0;
        setup(&mut m);
        let before = m.stack.clone();
        let exit = unsafe { m.run(1) };
        assert_eq!(exit, m.code(0, 1), "{name}: the Rust handler runs the call");
        assert_eq!(m.ctx.cur, 0, "{name}");
        assert_eq!(m.stack, before, "{name}: nothing changed");
        assert_eq!(m.funcs[1].calls, 0, "{name}: nothing counted");
    }
    // The JIT's call threshold: counted the way `count_call` counts below
    // it, and the call that would reach it goes to Rust uncounted, so the
    // Rust handler's own count reaches the threshold and hands the call to
    // the interpreter, which compiles the function.
    for threshold in [1u32, 3] {
        let mut m = Machine::new(vec![Ins::default(), callk, Ins::default()], vec![Ins::default()], 1);
        m.stack[HDR + 1] = closure_value;
        m.ctx.jit_threshold = threshold;
        for call in 1..=threshold {
            m.ctx.cur = 0;
            let exit = unsafe { m.run(1) };
            if call == threshold {
                assert_eq!(m.funcs[1].calls, threshold - 1, "the hot call is Rust's to count");
                assert_eq!(exit, m.code(0, 1), "threshold {threshold}: hot call goes to Rust");
                assert_eq!(m.ctx.cur, 0);
            } else {
                assert_eq!(m.funcs[1].calls, call);
                assert_eq!(exit, m.code(1, 0));
                assert_eq!(m.ctx.cur, TEST_FRAME_WORDS as u64);
            }
        }
    }
    // A segment that entered one frame and fell back in another names the
    // instruction and leaves the frame to the context: the entry contract.
    let frame_mode_entry = Ins { op: Code::CallK as u8, a: 1, b: 2, c: 1, ..Ins::default() };
    let mut m = Machine::new(vec![Ins::default(), frame_mode_entry], vec![Ins { op: Code::Move as u8, a: 3, b: 1, ..Ins::default() }, Ins::default()], 1);
    m.stack[HDR + 1] = closure_value;
    m.stack[HDR + 3] = Value::num(7.0).0;
    let exit = unsafe { m.run(1) };
    assert_eq!(exit, m.code(1, 1), "the callee's first instruction ran natively");
    assert_eq!(m.ctx.cur, TEST_FRAME_WORDS as u64);
    assert_eq!(m.stack[TEST_FRAME_WORDS as usize + HDR + 3], Value::num(7.0).0);
}

/// A caller frame at 0 that called at pc 5, and a callee frame above it with
/// `values` in its registers from 0.
fn returning(values: &[u64], indirect: bool) -> Box<Machine> {
    let caller = vec![Ins::default(); 8];
    let callee = vec![
        Ins { op: Code::Ret as u8, a: 1, ..Ins::default() },
        Ins { op: Code::RetNil as u8, ..Ins::default() },
        Ins { op: Code::RetN as u8, a: 0, b: values.len() as u8, ..Ins::default() },
        Ins::default(),
    ];
    let mut m = Machine::new(caller, callee, 0);
    let s = TEST_FRAME_WORDS as usize;
    m.stack[0] |= 6 << 32;
    m.stack[s] = 1;
    m.stack[s + 1] = 0 | (((HDR + 2) as u64) << 32);
    m.stack[s + 2] = NIL;
    m.stack[s + 3] = ((TEST_FRAME_WORDS as u64) << 33) | if indirect { (1 << 32) | (HDR as u64 + 5) } else { 0 };
    for (i, v) in values.iter().enumerate() {
        m.stack[s + HDR + i] = *v;
    }
    for i in 0..8 {
        m.stack[HDR + i] = Value::num(i as f64).0;
    }
    m.ctx.cur = s as u64;
    m.ctx.last_nres = 9;
    m
}

#[test]
fn native_returns_deliver_results_and_resume_the_caller() {
    if !NATIVE_DERIVED_FRAME {
        return;
    }
    let values = [Value::TRUE.0, Value::num(-0.0).0, 0xdead_beef, Value::NIL.0, 5, 6, 7, 8, 9];
    for indirect in [false, true] {
        for (frame_mode, native) in [(0, 0), (1, 0), (1, 1)] {
            // Ret delivers register 1 to the caller's result slot, or to the
            // slot the frame names when its header says so.
            let mut m = returning(&values, indirect);
            m.ctx.frame_mode = frame_mode;
            m.funcs[0].native = native;
            let before = m.stack.clone();
            let exit = unsafe { m.run(0) };
            assert_eq!(m.ctx.cur, 0);
            assert_eq!(m.ctx.last_nres, 1);
            assert_eq!(m.ctx.result, values[1]);
            let mut expected = before.clone();
            expected[if indirect { HDR + 5 } else { HDR + 2 }] = values[1];
            assert_eq!(m.stack, expected, "indirect {indirect}");
            if frame_mode != 0 && native != 0 {
                assert_eq!(exit, EXIT_REENTER);
            } else {
                assert_eq!(exit, m.code(0, 6), "resumes after the call");
            }
            // RetNil delivers nil and no results.
            let mut m = returning(&values, indirect);
            m.ctx.frame_mode = frame_mode;
            m.funcs[0].native = native;
            let exit = unsafe { m.run(1) };
            assert_eq!(m.ctx.cur, 0);
            assert_eq!(m.ctx.last_nres, 0);
            let mut expected = before.clone();
            expected[HDR + 2] = NIL;
            assert_eq!(m.stack, expected);
            assert_eq!(exit, if frame_mode != 0 && native != 0 { EXIT_REENTER } else { m.code(0, 6) });
        }
    }
    // RetN copies `n` registers to the result slots; none delivers nil.
    for n in 0..=9usize {
        let mut m = returning(&values[..n], false);
        let before = m.stack.clone();
        let exit = unsafe { m.run(2) };
        if n > 8 {
            assert_eq!(exit, m.code(1, 2), "wide returns go to Rust");
            assert_eq!(m.stack, before);
            assert_eq!(m.ctx.cur, TEST_FRAME_WORDS as u64);
            continue;
        }
        assert_eq!(exit, m.code(0, 6));
        assert_eq!(m.ctx.cur, 0);
        assert_eq!(m.ctx.last_nres, n as u64);
        let mut expected = before.clone();
        if n == 0 {
            expected[HDR + 2] = NIL;
        }
        expected[HDR + 2..HDR + 2 + n].copy_from_slice(&values[..n]);
        assert_eq!(m.stack, expected, "RetN {n}");
    }
    // Guarded frames and the task's last frame return through Rust.
    for (guard, caller, slow) in [
        (NO_GUARD, 0u64, false),
        (TEST_FRAME_WORDS as u64, 0, true),
        (TEST_FRAME_WORDS as u64 + 1, 0, true),
        (TEST_FRAME_WORDS as u64 - 1, 0, false),
        (NO_GUARD, u32::MAX as u64, true),
    ] {
        for pc in 0..3 {
            let mut m = returning(&values[..2], false);
            m.ctx.guard = guard;
            let s = TEST_FRAME_WORDS as usize;
            m.stack[s + 1] = caller | (((HDR + 2) as u64) << 32);
            let before = m.stack.clone();
            let exit = unsafe { m.run(pc) };
            if slow {
                assert_eq!(exit, m.code(1, pc), "guard {guard:#x} caller {caller:#x}");
                assert_eq!(m.stack, before);
                assert_eq!(m.ctx.cur, s as u64);
            } else {
                assert_eq!(exit, m.code(0, 6));
                assert_eq!(m.ctx.cur, 0);
            }
        }
    }
}

#[test]
fn native_result_padding_fills_only_missing_results() {
    if !NATIVE_DERIVED_FRAME {
        return;
    }
    for wanted in 0..=9u8 {
        for delivered in 0..=9u64 {
            let program = [
                Ins { op: Code::PadResults as u8, a: 2, b: wanted, ..Ins::default() },
                Ins::default(),
            ];
            let mut m = Machine::new(program.to_vec(), vec![Ins::default()], 0);
            for i in 0..12 {
                m.stack[HDR + i] = Value::num(i as f64).0;
            }
            m.ctx.last_nres = delivered;
            let mut expected = m.stack.clone();
            let exit = unsafe { m.run(0) };
            if wanted > 8 {
                assert_eq!(exit, m.code(0, 0));
                assert_eq!(m.stack, expected);
                continue;
            }
            for i in delivered..wanted as u64 {
                expected[HDR + 2 + i as usize] = NIL;
            }
            assert_eq!(exit, m.code(0, 1));
            assert_eq!(m.stack, expected, "wanted {wanted} delivered {delivered}");
        }
    }
}

/// Whole programs through the interpreter: recursion through dynamic and
/// static calls, multiple results, padding, stack growth under native
/// frames, and both frame modes. Every result is exact, so an instruction
/// skipped or repeated at any frame transition shows.
fn program(vm: &mut crate::interp::Interp) {
    let source = r#"
function fib 0 1 12 1 v:v
const 0 num 2
const 1 func 0
const 2 num 1
K 2 0
Lt 3 1 2
JmpIfNot 3 1
Ret 1
K 4 1
K 5 2
Sub 7 1 5
CallK 0 4 6 1 1
PadResults 6 1
K 5 0
Sub 9 1 5
CallK 0 4 8 1 1
PadResults 8 1
Add 10 6 8
Ret 10
end
function twice 1 1 8 1 v:v
const 0 num 1
K 2 0
Add 4 1 2
Call 2 3 1
PadResults 3 1
Add 6 1 2
Call 2 5 1
PadResults 5 1
Add 7 3 5
Ret 7
end
function inc 2 1 4 1 v:v
const 0 num 1
K 2 0
Add 3 1 2
Ret 3
end
function pair 3 1 6 1 v:v
const 0 num 1
K 2 0
Add 3 1 2
Add 4 3 2
Move 2 1
RetN 2 3
end
function usepair 4 1 10 1 v:v
const 0 func 3
K 2 0
Move 4 1
CallK 3 2 3 1 3
PadResults 3 4
Add 7 3 4
Add 7 7 5
Not 8 6
JmpIf 8 1
Ret 6
Ret 7
end
function depth 5 1 8 1 v:v
const 0 num 0
const 1 num 1
const 2 func 5
K 2 0
Eq 3 1 2
JmpIfNot 3 1
Ret 2
K 4 2
K 5 1
Sub 7 1 5
CallK 5 4 6 1 1
PadResults 6 1
Add 7 6 5
Ret 7
end
function nothing 6 0 4 1 :v
RetNil
end
function callnothing 7 0 6 1 :v
const 0 func 6
K 2 0
K 4 0
CallK 6 4 3 0 0
Call 6 5 0
PadResults 5 2
Ret 5
end
function layouts 8 1 10 1 v:v
const 0 func 9
const 1 func 10
K 2 0
Move 4 1
CallK 9 2 3 1 1
PadResults 3 1
K 5 1
Move 7 1
CallK 10 5 6 1 1
PadResults 6 1
Add 8 3 6
Ret 8
end
function narrow 9 1 4 1 v:v
const 0 num 0
K 2 0
Eq 3 1 2
Add 3 1 2
Ret 3
end
function wide 10 1 20 4 v:v
const 0 num 7
K 5 0
IUnbox 0 1
Ret 5
end
entry 0
"#;
    crate::image::load(vm, source).unwrap();
    vm.install_globals();
    vm.entries.resize(vm.funcs.len(), 0);
    vm.prepare_threaded();
}

#[test]
fn native_frames_run_whole_programs_in_both_frame_modes() {
    for frame_mode in [false, true] {
        let mut vm = Box::new(crate::interp::Interp::new());
        program(&mut vm);
        vm.frame_mode = frame_mode;
        let call = |vm: &mut crate::interp::Interp, fid: u32, arg: f64| {
            vm.call_value(Value::func(fid), &[Value::num(arg)])
        };
        assert_eq!(call(&mut vm, 0, 20.0), vec![Value::num(6765.0)], "fib");
        assert_eq!(call(&mut vm, 1, 10.0), vec![Value::num(24.0)], "static calls");
        assert_eq!(call(&mut vm, 4, 5.0), vec![Value::num(18.0)], "three results padded to four");
        // Deeper than the initial stack: growth happens in Rust under native
        // frames, and the native chain resumes on the moved stack.
        assert_eq!(call(&mut vm, 5, 5000.0), vec![Value::num(5000.0)], "growth");
        assert_eq!(vm.call_value(Value::func(7), &[]), vec![Value::NIL], "nil returns");
        // A segment that enters in one callee's frame, returns, and calls a
        // function with other windows at the same index must re-derive the
        // windows before the next Rust instruction: with the first callee's
        // integer window, the unbox lands on the second callee's register 5.
        assert_eq!(call(&mut vm, 8, 5.0), vec![Value::num(12.0)], "two layouts at one frame index");
    }
}


