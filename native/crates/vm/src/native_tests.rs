use super::*;
use crate::interp::Op;
use crate::heap::{F_METATABLE, KIND_CELL, KIND_CLOSURE, KIND_RECORD, KIND_SLICE, KIND_STR};

fn num(x: f64) -> u64 {
    Value::num(x).0
}
fn boolean(x: bool) -> u64 {
    Value::boolean(x).0
}
fn truthy(x: u64) -> bool {
    Value(x).truthy()
}

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
    let values = [0, 1, 63, 64, 127, 0x0123_4567_89ab_cdef, 0x7fff_ffff_ffff_ffff, 1 << 63, u64::MAX];
    let operations: [(Code, fn(u64, u64) -> u64); 15] = [
        (Code::IAdd, u64::wrapping_add),
        (Code::ISub, u64::wrapping_sub),
        (Code::IAnd, |a, b| a & b),
        (Code::IOr, |a, b| a | b),
        (Code::IXor, |a, b| a ^ b),
        (Code::INot, |a, _| !a),
        (Code::IBswap32, |a, _| (a as u32).swap_bytes() as u64),
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

#[test]
fn every_encoded_native_opcode_has_a_linked_nupp_handler() {
    assert_eq!(CODE_NAMES.len(), Op::NAMES.len() + 1);
    for name in Op::NAMES {
        let code = code_by_name(name).unwrap_or_else(|| panic!("{name} has no native dispatch entry"));
        assert_ne!(code, Code::Slow as u8);
    }
    for (code, name) in CODE_NAMES.iter().enumerate().skip(1) {
        assert!(NATIVE_RUNTIME_HANDLER_CODES.contains(&(code as u8)), "{name} silently uses the leave table entry");
    }
    assert!(!NATIVE_RUNTIME_HANDLER_CODES.contains(&(Code::Slow as u8)));
}

#[test]
fn remaining_integer_leaf_encodings_reach_their_native_handlers() {
    use crate::interp::Op;
    let cases = [
        (Op::IXor(255, 254, 253), Code::IXor, 253),
        (Op::INot(255, 254), Code::INot, 0),
        (Op::IBswap32(255, 254), Code::IBswap32, 0),
    ];
    for (op, code, third) in cases {
        let ins = encode(&op);
        assert_eq!((ins.op, ins.a, ins.b, ins.c), (code as u8, 255, 254, third));
    }
}

#[test]
fn native_integer_literals_moves_and_masks_preserve_all_bits() {
    let values = [0, 1, -1, i64::MIN, i64::MAX, 0x1234_5678_90ab_cdef];
    for code in [Code::IK, Code::IMov, Code::IAddK, Code::IMaskU32] {
        for source in values {
            for immediate in values {
                for dest in [0, 1, 255] {
                    let mut regs = [0xa5a5; 258];
                    let mut ints = [-123; 258];
                    let mut floats = [19.25; 258];
                    ints[1] = source;
                    let mut expected = ints;
                    expected[dest + 1] = match code {
                        Code::IK => immediate,
                        Code::IMov => source,
                        Code::IAddK => source.wrapping_add(immediate),
                        Code::IMaskU32 => source & 0xffff_ffff,
                        _ => unreachable!(),
                    };
                    assert!(unsafe {
                        execute_leaf(code, dest, &mut regs, &mut ints, &mut floats, immediate)
                    });
                    assert_eq!(
                        ints, expected,
                        "{code:?}: source {source}, immediate {immediate}"
                    );
                    assert_eq!(regs, [0xa5a5; 258]);
                    assert_eq!(floats, [19.25; 258]);
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

/// A function table for a test of back edges: one function whose code is
/// `program`, far from hot.
fn one_function(program: &[Ins]) -> FuncInfo {
    FuncInfo {
        code: program.as_ptr(),
        consts: std::ptr::null(),
        frame_words: 8,
        nregs: 1,
        nparams: 0,
        off_i: 5,
        off_f: 6,
        off_v: 8,
        vararg: 0,
        ncode: program.len() as u32,
        calls: 0,
        typed: 0,
        native: 0,
        nv_params: 0,
        nf_params: 0,
        float_return: 0,
    }
}

/// A taken back edge counts toward its function's heat while
/// the JIT may compile frames, and is taken natively while the function is
/// neither hot nor compiled; anything else leaves the loop alone.
#[test]
fn native_value_branches_count_heat_on_taken_back_edges() {
    for code in [Code::JmpIf, Code::JmpIfNot] {
        for value in [
            Value::NIL.0,
            Value::FALSE.0,
            Value::TRUE.0,
            Value::num(0.0).0,
            crate::value::QNAN,
        ] {
            for displacement in [-2, 1] {
                {
                    for jit in [0, 1] {
                        for entries in [0, 1] {
                            let mut program = [Ins::default(); 5];
                            program[2] = Ins {
                                op: code as u8,
                                a: 0,
                                imm: displacement,
                                ..Ins::default()
                            };
                            // Native code writes the heat through the context's
                            // pointer: the table is mutable, and read back below.
                            let mut funcs = [one_function(&program)];
                            let frame_entries = [0u64];
                            let mut ctx: Ctx = unsafe { std::mem::zeroed() };
                            ctx.jit_frames = jit;
                            ctx.funcs = funcs.as_mut_ptr();
                            ctx.nfuncs = 1;
                            ctx.frame_entries = frame_entries.as_ptr();
                            ctx.nframe_entries = entries;
                            ctx.frame_threshold = 100;
                            ctx.budget = u64::MAX;
                            let mut regs = [value];
                            let mut ints = [-123];
                            let mut floats = [19.25];
                            let mut frame = [0; 4];
                            let taken = Value(value).truthy() == (matches!(code, Code::JmpIf));
                            let expected = if taken { (3 + displacement) as usize } else { 3 };
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
                            let heat = (taken && displacement < 0 && jit != 0) as u32;
                            let counted = unsafe { std::ptr::read_volatile(&funcs[0].calls) };
                            assert_eq!(counted, heat, "{code:?} jit {jit} entries {entries}");
                        }
                    }
                }
            }
        }
    }
}

#[test]
fn back_edges_finish_without_native_recursion() {
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
        let mut funcs = [one_function(&program)];
        let frame_entries = [0u64];
        let mut ctx: Ctx = unsafe { std::mem::zeroed() };
        ctx.jit_frames = jit;
        ctx.funcs = funcs.as_mut_ptr();
        ctx.nfuncs = 1;
        ctx.frame_entries = frame_entries.as_ptr();
        ctx.nframe_entries = entries;
        // Never hot: the whole loop runs natively, one edge counted at a time.
        ctx.frame_threshold = u32::MAX;
        ctx.budget = u64::MAX;
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
        assert_eq!(next, unsafe { program.as_ptr().add(3) });
        assert_eq!(ints[0], 0);
        let counted = unsafe { std::ptr::read_volatile(&funcs[0].calls) };
        assert_eq!(counted, if jit != 0 { 999_999 } else { 0 });
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
fn native_array_reads_answer_the_array_part_and_misses_in_place() {
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
                            let in_array = d >= 1.0 && d <= 3.0 && d == slot as f64;
                            let present = in_array && table.payload.array[slot - 1] != Value::NIL;
                            // A record, and a table with a metatable whose
                            // array part does not answer, go to the helper,
                            // which this fixture has no runtime for.
                            if word == table.value() && (kind != KIND_TABLE || (meta != Value::NIL && !present)) {
                                continue;
                            }
                            // An integer a double cannot hold is a boxed key: Rust's.
                            let boxed = matches!(code, Code::GetIdxI) && ints[2].unsigned_abs() > 1 << 53;
                            let valid = word == table.value() && !boxed;
                            let mut expected = regs;
                            if valid {
                                // The array part, or a miss in the empty hash part.
                                expected[dest + 1] = if in_array { table.payload.array[slot - 1].0 } else { Value::NIL.0 };
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
fn native_record_leaf_reads_preserve_aliasing_and_numeric_bits() {
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
                            if !valid { continue; }
                            if valid {
                                if matches!(code, Code::GetSlotF) {
                                    expected_f[dest + 1] = value.0;
                                } else {
                                    expected_r[dest + 1] = value.0;
                                }
                            }
                            assert_eq!(
                                unsafe {
                                    execute_leaf(code, dest, &mut regs, &mut ints, &mut floats, 1)
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
// the instruction to resume at. The frame driver's service (a compiled frame
// entry, a hot function, vector code) needs an interpreter and is covered by
// the whole-program and specialization suites; here the policy's own
// decisions -- counting heat, interpreting -- are what is checked.
struct Machine {
    interp: Box<crate::interp::Interp>,
    stack: Vec<u64>,
    funcs: Vec<FuncInfo>,
    codes: Vec<Vec<Ins>>,
    frame_entries: Vec<u64>,
    slow_calls: Vec<u8>,
    ctx: Ctx,
}

const TEST_FRAME_WORDS: u32 = 4 + 8 + 1 + 2 + 2;

impl Machine {
    /// Two functions: the caller at frame 0, and a callee with `nparams`.
    fn new(caller: Vec<Ins>, callee: Vec<Ins>, nparams: u32) -> Box<Self> {
        let mut m = Box::new(Self {
            interp: Box::new(crate::interp::Interp::new()),
            stack: vec![0x5a5a_0000_0000_5a5a; 4096],
            funcs: Vec::new(),
            codes: vec![caller, callee],
            frame_entries: Vec::new(),
            slow_calls: Vec::new(),
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
                off_v: TEST_FRAME_WORDS,
                vararg: 0,
                ncode: m.codes[fid].len() as u32,
                calls: 0,
                typed: 0,
                native: 0,
                nv_params: np,
                nf_params: 0,
                float_return: 0,
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
        self.ctx.interp = (&mut *self.interp as *mut crate::interp::Interp).cast();
        self.ctx.stack = self.stack.as_mut_ptr();
        self.ctx.cap = self.stack.len() as u64;
        self.ctx.funcs = self.funcs.as_ptr();
        self.ctx.nfuncs = self.funcs.len() as u64;
        self.ctx.frame_entries = self.frame_entries.as_ptr();
        self.ctx.nframe_entries = self.frame_entries.len() as u64;
        self.ctx.slow_calls = self.slow_calls.as_ptr();
        self.ctx.nslow_calls = self.slow_calls.len() as u64;
        self.ctx.guard = NO_GUARD;
        self.ctx.unavailable_fid = u32::MAX;
        self.ctx.frame_threshold = 1 << 20;
        self.ctx.budget = u64::MAX;
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

#[test]
fn native_back_edges_preserve_unlimited_and_stop_at_finite_budgets() {
    let code = vec![
        Ins {
            op: Code::IAddK as u8,
            k: -1,
            ..Ins::default()
        },
        Ins {
            op: Code::JmpIfIZero as u8,
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
    for (budget, remaining, count, pc) in [
        (0, 0, 3, 2),
        (1, 0, 2, 2),
        (2, 0, 1, 2),
        (3, 0, 0, 3),
        (u64::MAX, u64::MAX, 0, 3),
    ] {
        let mut m = Machine::new(code.clone(), vec![Ins::default()], 0);
        let integer = m.funcs[0].off_i as usize;
        m.stack[integer] = 4;
        m.ctx.budget = budget;
        let exit = unsafe { m.run(0) };
        assert_eq!(exit, m.code(0, pc), "budget {budget}");
        assert_eq!(m.ctx.budget, remaining, "budget {budget}");
        assert_eq!(m.stack[integer], count, "budget {budget}");
    }
}

#[test]
fn native_call_paths_preserve_unlimited_and_charge_finite_budgets() {
    for op in [Code::Call, Code::CallK, Code::CallDyn] {
        for vararg in [0, 1] {
            for budget in [0, 1, 7, u64::MAX] {
                let ins = if matches!(op, Code::Call) {
                    Ins {
                        op: op as u8,
                        a: 2,
                        k: 1,
                        ..Ins::default()
                    }
                } else {
                    Ins {
                        op: op as u8,
                        a: 1,
                        b: 2,
                        k: 1,
                        ..Ins::default()
                    }
                };
                let mut m = Machine::new(vec![ins], vec![Ins::default()], 0);
                m.funcs[1].vararg = vararg;
                m.stack[HDR + 1] = Value::func(1).0;
                m.ctx.budget = budget;
                let exit = unsafe { m.run(0) };
                let callee = usize::from(budget != 0);
                assert_eq!(
                    exit,
                    m.code(callee, 0),
                    "op {} vararg {vararg} budget {budget}",
                    op as u8
                );
                let remaining = if budget == u64::MAX {
                    budget
                } else {
                    budget.saturating_sub(1)
                };
                assert_eq!(
                    m.ctx.budget, remaining,
                    "op {} vararg {vararg} budget {budget}",
                    op as u8
                );
            }
        }
    }
}

/// The frame a call pushes, as the Rust core pushed it (contracts 5.1): the
/// reference the native call handlers are compared with.
unsafe fn push(ctx: *mut Ctx, frame: *mut u64, fid: u32, args: u32, nargs: u32, pc: u32, closure: u64) {
    let fi = (*ctx).funcs.add(fid as usize);
    let s = (*ctx).cur;
    *frame = (*frame & 0xffff_ffff) | ((pc as u64) << 32);
    let ns = s + ((*frame.add(3) >> 33) & 0xffff);
    let words = (*fi).frame_words as u64;
    let st = (*ctx).stack;
    let nf = st.add(ns as usize);
    *nf = fid as u64;
    *nf.add(1) = s | ((args as u64) << 32);
    *nf.add(2) = closure;
    *nf.add(3) = words << 33;
    for i in 0..nargs {
        *nf.add(HDR + 1 + i as usize) = *st.add(args as usize + 1 + i as usize);
    }
    for i in nargs..(*fi).nparams {
        *nf.add(HDR + 1 + i as usize) = NIL;
    }
    (*ctx).cur = ns;
}

fn closure_header(fid: u32) -> Box<Header> {
    let mut header: Box<Header> = Box::new(unsafe { std::mem::zeroed() });
    header.kind = KIND_CLOSURE;
    header.aux = fid;
    header
}

#[test]
fn native_calls_push_the_frame_rust_pushes() {
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
                for jit_frames in [0, 1] {
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
                    assert_eq!(exit, m.code(1, 0), "opcode {} continues in the callee", code as u8);
                    // Under the JIT, a function starting counts toward its heat.
                    assert_eq!(m.funcs[1].calls, jit_frames, "opcode {} heat", code as u8);
                }
            }
        }
    }
}

#[test]
fn native_calls_leave_unsupported_calls_untouched() {
    let mut closure = closure_header(1);
    let closure_value = Value::obj(std::ptr::NonNull::from(&mut *closure)).0;
    let call = Ins { op: Code::Call as u8, a: 2, b: 1, k: 1, ..Ins::default() };
    let callk = Ins { op: Code::CallK as u8, a: 1, b: 2, c: 1, ..Ins::default() };
    type Setup = fn(&mut Machine);
    let cases: Vec<(&str, Ins, u64, Setup)> = vec![
        ("typed dynamic", callk, Value::func(1).0, |m| m.funcs[1].typed = 1),
        ("unavailable", callk, closure_value, |m| m.ctx.unavailable_fid = 1),
        // Builtins run through the helper, except a host service and one the
        // slow-call table names; an iterator runs through its helper too, as
        // does feedback, so none of those leaves anything untouched here.
        ("host service", callk, Value::builtin(1000).0, |_| {}),
        ("slow builtin", callk, Value::builtin(3).0, |m| { m.slow_calls = vec![0, 0, 0, 1]; m.sync(); }),
        ("not callable", callk, Value::num(1.0).0, |_| {}),
        ("unknown function", callk, Value::func(9).0, |_| {}),
        // A result pack past the window, and both spread flags at once.
        ("wide result pack", Ins { c: 64 | 1, ..callk }, closure_value, |m| m.ctx.last_nres = 9),
        ("both flags", Ins { c: 128 | 64, ..callk }, closure_value, |_| {}),
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
    // A segment that entered one frame and fell back in another names the
    // instruction and leaves the frame to the context: the entry contract.
    let entering = Ins { op: Code::CallK as u8, a: 1, b: 2, c: 1, ..Ins::default() };
    let mut m = Machine::new(vec![Ins::default(), entering], vec![Ins { op: Code::Move as u8, a: 3, b: 1, ..Ins::default() }, Ins::default()], 1);
    m.stack[HDR + 1] = closure_value;
    m.stack[HDR + 3] = Value::num(7.0).0;
    let exit = unsafe { m.run(1) };
    assert_eq!(exit, m.code(1, 1), "the callee's first instruction ran natively");
    assert_eq!(m.ctx.cur, TEST_FRAME_WORDS as u64);
    assert_eq!(m.stack[TEST_FRAME_WORDS as usize + HDR + 3], Value::num(7.0).0);
}

/// Contracts 5.1: a vararg callee's surplus lies just below its header, the
/// count in header word 3; a count flagged 128 appends the caller's own
/// varargs and one flagged 64 the last call's results; a callee without
/// varargs drops what its parameters do not take.
#[test]
fn native_calls_spread_varargs_below_the_callee_header() {
    let (a, b, c) = (Value::num(1.0).0, Value::num(2.0).0, Value::num(3.0).0);
    let call = Ins { op: Code::Call as u8, a: 2, b: 3, k: 1, ..Ins::default() };
    let callk = Ins { op: Code::CallK as u8, a: 1, b: 2, c: 1, ..Ins::default() };
    // (name, instruction, callee nparams, callee vararg, caller varargs,
    // last result count, the registers from base + 1, parameters, surplus)
    type Case = (&'static str, Ins, u32, u32, Vec<u64>, u64, Vec<u64>, Vec<u64>, Vec<u64>);
    let cases: Vec<Case> = vec![
        ("static", call, 1, 1, vec![], 0, vec![a, b, c], vec![a], vec![b, c]),
        ("static short", call, 4, 1, vec![], 0, vec![a, b, c], vec![a, b, c, NIL], vec![]),
        ("frame varargs", Ins { c: 128 | 1, ..callk }, 1, 1, vec![b, c], 0, vec![a], vec![a], vec![b, c]),
        ("frame varargs dropped", Ins { c: 128 | 1, ..callk }, 2, 0, vec![b, c], 0, vec![a], vec![a, b], vec![]),
        ("no frame varargs", Ins { c: 128, ..callk }, 1, 1, vec![], 0, vec![], vec![NIL], vec![]),
        ("result pack", Ins { c: 64 | 1, ..callk }, 1, 1, vec![], 2, vec![a, b, c], vec![a], vec![b, c]),
        ("wide plain count", Ins { b: 64 | 1, ..call }, 2, 0, vec![], 1, vec![a, b], vec![a, b], vec![]),
    ];
    for (name, ins, nparams, vararg, varargs, nres, args, params, surplus) in cases {
        let mut m = Machine::new(vec![Ins::default(), ins, Ins::default()], vec![Ins::default()], nparams);
        m.funcs[1].vararg = vararg;
        // The caller's frame sits above its own varargs.
        let s = varargs.len();
        for (i, v) in varargs.iter().enumerate() { m.stack[i] = *v; }
        m.stack[s] = 0;
        m.stack[s + 1] = u32::MAX as u64;
        m.stack[s + 2] = NIL;
        m.stack[s + 3] = ((TEST_FRAME_WORDS as u64) << 33) | ((s as u64) << 49);
        m.stack[s + HDR + 1] = Value::func(1).0;
        for (i, v) in args.iter().enumerate() { m.stack[s + HDR + 3 + i] = *v; }
        m.sync();
        m.ctx.cur = s as u64;
        m.ctx.last_nres = nres;
        let exit = unsafe { m.run(1) };
        let ns = s + TEST_FRAME_WORDS as usize + surplus.len();
        assert_eq!(exit, m.code(1, 0), "{name}: continues in the callee");
        assert_eq!(m.ctx.cur, ns as u64, "{name}");
        assert_eq!(m.stack[s] >> 32, 2, "{name}: the caller resumes after the call");
        assert_eq!(m.stack[ns], 1, "{name}");
        assert_eq!(m.stack[ns + 1], s as u64 | (((s + HDR + 2) as u64) << 32), "{name}");
        assert_eq!(m.stack[ns + 3], ((TEST_FRAME_WORDS as u64) << 33) | ((surplus.len() as u64) << 49), "{name}");
        assert_eq!(&m.stack[ns - surplus.len()..ns], &surplus[..], "{name}: surplus");
        assert_eq!(&m.stack[ns + HDR + 1..ns + HDR + 1 + params.len()], &params[..], "{name}: parameters");
    }
}

/// `Switch` reads its function's jump tables past the last instruction
/// (`FuncInfo.ncode`), as `encode_function` packs them: a start word per
/// table, then each table's length, default and offsets, relative to the
/// instruction after the switch. An index past either end takes the default.
#[test]
fn native_switch_reads_the_tables_past_the_code() {
    let words: [i32; 12] = [2, 7, 3, 4, 0, 1, 2, 1, -3, -4, 0, 0];
    for (table, index, target) in [(0, 0, 5), (0, 2, 7), (0, 3, 9), (0, -1, 9), (1, 0, 1), (1, 5, 2)] {
        let mut code = vec![Ins::default(); 10];
        code[4] = Ins { op: Code::Switch as u8, a: 2, imm: table, ..Ins::default() };
        for w in words.chunks(4) {
            let b = w[0].to_le_bytes();
            code.push(Ins { op: b[0], a: b[1], b: b[2], c: b[3], imm: w[1], k: (w[2] as u32 as i64) | ((w[3] as i64) << 32) });
        }
        let mut m = Machine::new(code, vec![Ins::default()], 0);
        m.funcs[0].ncode = 10;
        m.sync();
        let off_i = m.funcs[0].off_i as usize;
        m.stack[off_i + 2] = index as u64;
        let exit = unsafe { m.run(4) };
        assert_eq!(exit, m.code(0, target), "table {table} index {index}");
    }
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
    let values = [Value::TRUE.0, Value::num(-0.0).0, 0xdead_beef, Value::NIL.0, 5, 6, 7, 8, 9];
    for indirect in [false, true] {
        {
            // Ret delivers register 1 to the caller's result slot, or to the
            // slot the frame names when its header says so.
            let mut m = returning(&values, indirect);
            let before = m.stack.clone();
            let exit = unsafe { m.run(0) };
            assert_eq!(m.ctx.cur, 0);
            assert_eq!(m.ctx.last_nres, 1);
            assert_eq!(m.ctx.result, values[1]);
            let mut expected = before.clone();
            expected[if indirect { HDR + 5 } else { HDR + 2 }] = values[1];
            assert_eq!(m.stack, expected, "indirect {indirect}");
            assert_eq!(exit, m.code(0, 6), "resumes after the call");
            // RetNil delivers nil and no results.
            let mut m = returning(&values, indirect);
            let exit = unsafe { m.run(1) };
            assert_eq!(m.ctx.cur, 0);
            assert_eq!(m.ctx.last_nres, 0);
            let mut expected = before.clone();
            expected[HDR + 2] = NIL;
            assert_eq!(m.stack, expected);
            assert_eq!(exit, m.code(0, 6));
        }
    }
    // RetN copies `n` registers to the result slots; none delivers nil.
    for n in 0..=9usize {
        let mut m = returning(&values[..n], false);
        let before = m.stack.clone();
        let exit = unsafe { m.run(2) };
        assert_eq!(exit, m.code(0, 6));
        assert_eq!(m.ctx.cur, 0);
        assert_eq!(m.ctx.last_nres, n as u64);
        let mut expected = before.clone();
        if n == 0 {
            expected[HDR + 2] = NIL;
        }
        expected[HDR + 2..HDR + 2 + n.min(8)].copy_from_slice(&values[..n.min(8)]);
        assert_eq!(m.stack, expected, "RetN {n}");
    }
    // A guard belonging to a lower frame does not affect this return.
    for pc in 0..3 {
        let mut m = returning(&values[..2], false);
        m.ctx.guard = TEST_FRAME_WORDS as u64 - 1;
        let exit = unsafe { m.run(pc) };
        assert_eq!(exit, m.code(0, 6));
        assert_eq!(m.ctx.cur, 0);
    }
}

// The return ABI stores absolute words; the Nupp handlers translate them to
// a caller frame plus a logical value or float slot before delivery.
#[test]
fn native_returns_use_the_resumed_frames_logical_windows() {
    let bits = [
        Value::TRUE.0,
        (-0.0f64).to_bits(),
        0x7ff8_0000_0000_0042,
        Value::NIL.0,
        5,
        6,
        7,
        8,
    ];
    for caller in [0usize, 23] {
        for value_slot in [0usize, 5] {
            for indirect in [false, true] {
                for (pc, count) in [(0usize, 1usize), (1, 0), (2, 0), (2, 1), (2, 8)] {
                    let mut m = returning(&bits, indirect);
                    let callee = 128usize;
                    let caller_header = m.stack[..HDR].to_vec();
                    let callee_words = m.stack[TEST_FRAME_WORDS as usize
                        ..TEST_FRAME_WORDS as usize + TEST_FRAME_WORDS as usize]
                        .to_vec();
                    m.stack[caller..caller + HDR].copy_from_slice(&caller_header);
                    m.stack[callee..callee + callee_words.len()].copy_from_slice(&callee_words);
                    // Deliberately use a different float-window displacement.
                    let off_f = 40usize;
                    let float_slot = 3usize;
                    m.funcs[0].nregs = 16;
                    m.funcs[0].off_i = 21;
                    m.funcs[0].off_f = off_f as u32;
                    m.funcs[0].frame_words = 64;
                    m.stack[caller + 3] = 64 << 33;
                    let source = if value_slot == 0 { 1 } else { 2 };
                    m.codes[1][0].a = source as u8;
                    m.stack[callee + 1] =
                        caller as u64 | (((caller + HDR + value_slot) as u64) << 32);
                    m.stack[callee + 3] = ((TEST_FRAME_WORDS as u64) << 33)
                        | if indirect {
                            (1 << 32) | (caller + off_f + float_slot) as u64
                        } else {
                            0
                        };
                    m.codes[1][2].b = count as u8;
                    m.ctx.cur = callee as u64;
                    let mut expected = m.stack.clone();
                    if pc == 0 {
                        expected[caller
                            + if indirect {
                                off_f + float_slot
                            } else {
                                HDR + value_slot
                            }] = bits[source];
                    } else if count == 0 {
                        // Nil and multi-result returns always target values,
                        // including a frame with the float-return flag set.
                        expected[caller + HDR + value_slot] = NIL;
                    } else {
                        expected[caller + HDR + value_slot..caller + HDR + value_slot + count]
                            .copy_from_slice(&bits[..count]);
                    }
                    let exit = unsafe { m.run(pc) };
                    assert_eq!(exit, m.code(0, 6));
                    assert_eq!(m.ctx.cur, caller as u64);
                    assert_eq!(m.ctx.last_nres, count as u64);
                    assert_eq!(
                        m.stack, expected,
                        "caller {caller} slot {value_slot} indirect {indirect} pc {pc} count {count}"
                    );
                }
            }
        }
    }
}

#[test]
fn native_single_return_padding_matches_logical_slot_zero() {
    for (destination, pad_slot, indirect) in [
        (0usize, 0usize, false),
        (5, 5, false),
        (0, 5, false),
        (0, 0, true),
    ] {
        let mut m = returning(&[Value::TRUE.0, Value::num(-0.0).0], indirect);
        let caller = 31usize;
        let callee = 128usize;
        let caller_header = m.stack[..HDR].to_vec();
        let callee_words = m.stack
            [TEST_FRAME_WORDS as usize..TEST_FRAME_WORDS as usize + TEST_FRAME_WORDS as usize]
            .to_vec();
        m.stack[caller..caller + HDR].copy_from_slice(&caller_header);
        m.stack[callee..callee + callee_words.len()].copy_from_slice(&callee_words);
        m.stack[callee + 1] = caller as u64 | (((caller + HDR + destination) as u64) << 32);
        m.stack[callee + 3] = ((TEST_FRAME_WORDS as u64) << 33)
            | if indirect {
                (1 << 32) | (caller + m.funcs[0].off_f as usize + 1) as u64
            } else {
                0
            };
        m.codes[0][6] = Ins {
            op: Code::PadResults as u8,
            a: pad_slot as u8,
            b: 3,
            ..Ins::default()
        };
        m.ctx.cur = callee as u64;
        let mut expected = m.stack.clone();
        let target = caller
            + if indirect {
                m.funcs[0].off_f as usize + 1
            } else {
                HDR + destination
            };
        expected[target] = Value::num(-0.0).0;
        // A nonmatching or float destination leaves PadResults to dispatch;
        // it still pads according to last_nres. Both routes resume at pc 7.
        expected[caller + HDR + pad_slot + 1] = NIL;
        expected[caller + HDR + pad_slot + 2] = NIL;
        let exit = unsafe { m.run(0) };
        assert_eq!(exit, m.code(0, 7));
        assert_eq!(m.ctx.cur, caller as u64);
        assert_eq!(m.ctx.last_nres, 1);
        assert_eq!(m.stack, expected);
    }
}

#[test]
fn native_result_padding_fills_only_missing_results() {
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
            for i in 8..delivered.min(wanted as u64) {
                expected[HDR + 2 + i as usize] = Value::NIL.0;
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
/// static calls, multiple results, padding, and stack growth under native
/// frames. Every result is exact, so an instruction skipped or repeated at
/// any frame transition shows.
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
function rounded 11 1 10 1 v:v
const 0 builtin math.floor
const 1 num 0.5
K 2 0
K 3 1
Add 4 1 3
CallK 0 2 3 1 1
PadResults 3 1
Ret 3
end
function iterated 12 1 14 1 v:v
const 0 builtin ipairs
const 1 num 1
NewTable 2
K 3 1
SetIdx 2 3 1
K 4 0
Move 6 2
CallK 0 4 5 1 1
PadResults 5 1
CallK 0 5 6 0 2
PadResults 6 2
Add 8 6 7
Ret 8
end
entry 0
"#;
    crate::image::load(vm, source).unwrap();
    vm.install_globals();
    vm.entries.resize(vm.funcs.len(), 0);
    vm.prepare_threaded();
}

#[test]
fn native_helper_preserves_the_current_return_count() {
    let mut vm = Box::new(crate::interp::Interp::new());
    program(&mut vm);
    let table = vm.new_table();
    vm.registered.push(table);
    let key = vm.intern("missing");
    vm.registered.push(key);
    let tid = vm.spawn(6, &[]);
    let mut ctx: Ctx = unsafe { std::mem::zeroed() };
    ctx.interp = (&mut *vm as *mut crate::interp::Interp).cast();
    ctx.tid = tid as u64;
    crate::threaded::sync(&mut ctx, &mut vm);
    for (stale, returned) in [(3, 1), (1, 0), (0, 4)] {
        vm.last_nres = stale;
        ctx.last_nres = returned;
        let result = unsafe { crate::threaded::rt_get_field(&mut ctx, table.0, key.0) };
        assert_eq!(result, Value::NIL.0);
        assert_eq!(ctx.last_nres, returned);
        assert_eq!(vm.last_nres, returned as usize);
    }
}

#[test]
fn native_equality_helper_publishes_and_reloads_the_active_frame() {
    let mut vm = Box::new(crate::interp::Interp::new());
    program(&mut vm);
    let left = vm.new_table();
    vm.registered.push(left);
    let right = vm.new_table();
    vm.registered.push(right);
    let tid = vm.spawn(6, &[]);
    vm.execution_limit = Some(20);
    let mut ctx: Ctx = unsafe { std::mem::zeroed() };
    ctx.interp = (&mut *vm as *mut crate::interp::Interp).cast();
    ctx.tid = tid as u64;
    crate::threaded::sync(&mut ctx, &mut vm);
    let current = vm.funcs[6].frame_words();
    let root_header = vm.tasks[tid].stack[0];
    // A native push has made a second frame without updating Task.cur.
    let stack = &mut vm.tasks[tid].stack;
    stack[current] = 6;
    stack[current + 1] = ((HDR + 2) as u64) << 32;
    stack[current + 2] = NIL;
    stack[current + 3] = (current as u64) << 33;
    stack[current + HDR..current * 2].fill(NIL);
    ctx.cur = current as u64;
    ctx.pc = 0;
    ctx.budget = 17;
    ctx.last_nres = 4;
    vm.last_nres = 1;

    let equal = crate::threaded::rt_eq_slow(&mut ctx, left.0, right.0);

    assert_eq!(equal, 0);
    assert_eq!(vm.tasks[tid].cur(), current);
    assert_eq!(vm.tasks[tid].stack[current] >> 32, 1);
    assert_eq!(vm.tasks[tid].stack[0], root_header);
    assert_eq!(vm.execution_limit, Some(17));
    assert_eq!(ctx.budget, 17);
    assert_eq!(ctx.budget_mark, 17);
    assert_eq!(vm.last_nres, 4);
    assert_eq!(ctx.last_nres, 4);
    assert_eq!(ctx.stack, vm.tasks[tid].stack.as_mut_ptr());
    assert_eq!(ctx.funcs, vm.finfo.as_ptr());
}

#[test]
fn native_equality_callbacks_keep_callee_only_roots_and_result_state() {
    let source = r#"
function parent 0 0 8 1 :v
RetNil
end
function equal_many 1 2 8 1 vv:v
const 0 true
const 1 num 2
const 2 num 3
NewTable 6
NewTable 7
K 3 0
K 4 1
K 5 2
RetN 3 3
end
function equal_raise 2 2 8 1 vv:v
const 0 str "equality error"
const 1 builtin error
NewTable 3
K 4 1
K 6 0
CallK 0 4 5 1 0
RetNil
end
function equal_none 3 2 8 1 vv:v
NewTable 3
RetNil
end
entry 0
"#;
    for (fid, expected, nres, status, budget) in [
        (1, 1, 3, 0, 17),
        (2, 0, 4, crate::threaded::ST_ERROR, 16),
        (3, 0, 0, 0, 17),
    ] {
        let mut vm = Box::new(crate::interp::Interp::new());
        crate::image::load(&mut vm, source).unwrap();
        vm.entries.resize(vm.funcs.len(), 0);
        vm.prepare_threaded();
        let left = vm.new_table();
        vm.registered.push(left);
        let right = vm.new_table();
        vm.registered.push(right);
        let meta = vm.new_table();
        vm.registered.push(meta);
        let key = vm.intern("__eq");
        vm.set_index(meta, key, Value::func(fid));
        vm.set_metatable(left, meta);
        vm.set_metatable(right, meta);
        let survivor = vm.new_table();
        let tid = vm.spawn(0, &[]);
        let mut ctx: Ctx = unsafe { std::mem::zeroed() };
        ctx.interp = (&mut *vm as *mut crate::interp::Interp).cast();
        ctx.tid = tid as u64;
        vm.execution_limit = Some(20);
        crate::threaded::sync(&mut ctx, &mut vm);
        let current = vm.funcs[0].frame_words();
        let stack = &mut vm.tasks[tid].stack;
        stack[current] = 0;
        stack[current + 1] = ((HDR + 2) as u64) << 32;
        stack[current + 2] = NIL;
        stack[current + 3] = (current as u64) << 33;
        stack[current + HDR..current * 2].fill(NIL);
        // This object is reachable only from the unpublished native frame.
        stack[current + HDR + 1] = survivor.0;
        ctx.cur = current as u64;
        ctx.pc = 0;
        ctx.budget = 17;
        ctx.last_nres = 4;
        vm.last_nres = 1;
        vm.heap.stress = true;
        vm.heap.stress_steps = true;
        vm.heap.oracle = true;
        vm.heap.quarantine = true;

        let equal = crate::threaded::rt_eq_slow(&mut ctx, left.0, right.0);

        assert_eq!(equal, expected, "callback {fid}");
        assert_eq!(ctx.status, status, "callback {fid}");
        assert_eq!(vm.tasks[tid].cur(), current);
        assert_eq!(vm.tasks[tid].stack[current] >> 32, 1);
        assert_eq!(vm.tasks.len(), 1);
        assert_eq!(vm.last_nres, nres);
        assert_eq!(ctx.last_nres, nres as u64);
        assert_eq!(vm.execution_limit, Some(budget));
        assert_eq!(ctx.budget, budget as u64);
        assert_eq!(ctx.budget_mark, budget as u64);
        assert_eq!(ctx.stack, vm.tasks[tid].stack.as_mut_ptr());
        assert_eq!(ctx.funcs, vm.finfo.as_ptr());
        assert_eq!(vm.kind_of(survivor), Some(crate::heap::KIND_TABLE));
        if status != 0 {
            assert_eq!(vm.bytes_of(vm.pending_error.unwrap()), b"equality error");
        }
        vm.full_cycle();
        vm.check_oracle();
        assert_eq!(vm.kind_of(survivor), Some(crate::heap::KIND_TABLE));
    }
}

#[test]
fn native_array_resize_preserves_unpublished_frame_state_and_budget() {
    let mut vm = Box::new(crate::interp::Interp::new());
    program(&mut vm);
    let table = vm.new_table();
    vm.registered.push(table);
    let tid = vm.spawn(6, &[]);
    vm.execution_limit = Some(20);
    let mut ctx: Ctx = unsafe { std::mem::zeroed() };
    ctx.interp = (&mut *vm as *mut crate::interp::Interp).cast();
    ctx.tid = tid as u64;
    crate::threaded::sync(&mut ctx, &mut vm);
    ctx.budget -= 3;
    let stack = ctx.stack;
    let frame = vm.tasks[tid].cur();
    let unpublished_header = vm.tasks[tid].stack[frame];
    let before = vm.heap.live_bytes;
    let before_capacity = unsafe { (*header(table.0)).external_bytes() };

    unsafe {
        native_helpers::nupp_rt_resize_array(&mut ctx, table.0, 257);
        let h = &mut *header(table.0);
        assert_eq!(h.aux_len, 257);
        assert!(h.slots().iter().all(|v| *v == Value::NIL));
        assert_eq!(
            vm.heap.live_bytes - before,
            h.external_bytes() - before_capacity
        );
        h.table().array[0] = Value::num(7.0);
        native_helpers::nupp_rt_resize_array(&mut ctx, table.0, 1);
        let h = &*header(table.0);
        assert_eq!(h.slots(), &[Value::num(7.0)]);
        assert_eq!(h.aux_ptr, h.table_ref().array.as_ptr().cast_mut().cast());
    }
    assert_eq!(ctx.stack, stack);
    assert_eq!(vm.tasks[tid].stack[frame], unpublished_header);
    assert_eq!(ctx.budget, 17);
    assert_eq!(ctx.budget_mark, 20);
    assert_eq!(vm.execution_limit, Some(20));
    crate::threaded::charge(&mut ctx, &mut vm);
    assert_eq!(vm.execution_limit, Some(17));
}

#[test]
fn native_frames_run_whole_programs() {
    {
        let mut vm = Box::new(crate::interp::Interp::new());
        program(&mut vm);
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
        // A builtin and an iterator called through CallK run in Rust from the
        // argument window; the chain goes on in the caller with their results.
        assert_eq!(call(&mut vm, 11, 2.75), vec![Value::num(3.0)], "builtin call");
        assert_eq!(call(&mut vm, 12, 41.0), vec![Value::num(42.0)], "iterator call");
    }
}



// Contracts 4.5/5.1/5.2b: a spent scheduler slice publishes the next edge,
// all logical windows, closure and varargs. A source limit raises instead.
#[test]
fn native_budget_slices_preserve_roots_windows_and_result_packs() {
    fn fixture() -> (
        Box<crate::interp::Interp>,
        crate::scheduler::TaskId,
        Value,
        Value,
        Value,
    ) {
        let mut vm = Box::new(crate::interp::Interp::new());
        crate::image::load(
            &mut vm,
            r#"
function main 0 0 24 3 :v vararg
const 0 str "count"
const 1 num 1
const 2 func 1
const 3 func 2
GetUpval 1 0
K 2 0
VarargN 3 2
IK 0 3
IK 1 -7
FK 0 0.25
K 10 2
Move 11 3
Move 12 4
CallK 1 10 10 2 3
GetIdx 5 1 2
K 6 1
Add 5 5 6
SetIdx 1 2 5
IAddK 0 0 -1
JmpIfIZero 0 1
Jmp -7
K 13 3
Move 14 10
Move 15 11
Move 16 12
CallK 2 13 13 64 3
Move 9 13
Move 10 14
Move 11 15
IBox 7 1
FBox 8 0
RetN 7 5
end
function pack 1 2 6 1 vv:v
Nil 3
RetN 1 3
end
function echo 2 3 6 1 vvv:v
RetN 1 3
end
entry 0
"#,
        )
        .unwrap();
        vm.install_globals();
        vm.heap.stress_steps = true;
        vm.heap.oracle = true;
        vm.heap.quarantine = true;
        let roots = vm.registered.len();
        let counter = vm.new_table();
        vm.registered.push(counter);
        let key = vm.intern("count");
        vm.set_index(counter, key, Value::num(0.0));
        let payload = vm.new_table();
        vm.registered.push(payload);
        vm.set_index(payload, Value::num(1.0), counter);
        let message = vm.intern("rooted only by parked frames and their varargs");
        vm.registered.push(message);
        let closure = vm.new_closure(0, &[counter]);
        vm.enable_scheduler().unwrap();
        let task = vm.schedule(closure, &[message, payload], None).unwrap();
        vm.registered.truncate(roots);
        vm.prepare_threaded();
        assert!(vm.threaded);
        (vm, task, counter, payload, message)
    }

    let (mut vm, task, counter, payload, message) = fixture();
    // The slice is replenished by the embedding scheduler, while the source
    // limit is cumulative over all turns. Neither means one bytecode opcode.
    vm.execution_limit = Some(99);
    for expected_count in 1..=3 {
        vm.instruction_budget = Some(1);
        assert!(vm.run_ready(1).unwrap().is_empty());
        assert_eq!(vm.instruction_budget, Some(0));
        assert_eq!(vm.direct_frame, usize::MAX);
        assert_eq!(vm.nested_calls, 0);
        assert_eq!(vm.native_frame_depth, 0);
        let frame = vm.tasks[task.index].cur();
        assert_eq!(vm.tasks[task.index].stack[frame] & 0xffff_ffff, 0);
        assert_eq!(
            vm.tasks[task.index].stack[frame] >> 32,
            if expected_count < 3 { 16 } else { 21 }
        );
        // Every collection happens after native execution has relinquished
        // its pointers. The closure and surplus arguments are the only roots.
        vm.full_cycle();
        let key = vm.intern("count");
        assert_eq!(
            vm.get_index(counter, key),
            Value::num(expected_count as f64)
        );
        assert_eq!(vm.get_index(payload, Value::num(1.0)), counter);
        assert_eq!(
            vm.bytes_of(message),
            b"rooted only by parked frames and their varargs"
        );
        // A scheduler turn restores its own last-result count, even if another
        // task or embedding call changed the interpreter's scratch register.
        vm.last_nres = 77;
    }
    vm.instruction_budget = Some(1);
    // Only calls and taken back edges consume or test the slice. The root
    // RetN after this call must complete even though the slice reaches zero.
    let events = vm.run_ready(1).unwrap();
    assert_eq!(events.len(), 1);
    assert_eq!(events[0].status, crate::scheduler::Status::Completed);
    assert_eq!(
        vm.tasks[task.index].results,
        vec![
            Value::num(-7.0),
            Value::num(0.25),
            message,
            payload,
            Value::NIL
        ]
    );
    assert_eq!(vm.execution_limit, Some(95));
    assert!(vm.run_ready(1).unwrap().is_empty());
    vm.full_cycle();
    let key = vm.intern("count");
    assert_eq!(vm.get_index(counter, key), Value::num(3.0));

    let (mut limited, task, _, _, _) = fixture();
    limited.execution_limit = Some(1);
    limited.instruction_budget = None;
    let events = limited.run_ready(1).unwrap();
    assert_eq!(events.len(), 1);
    assert!(
        matches!(&events[0].status, crate::scheduler::Status::Failed(message) if message.contains("source chunk instruction limit exceeded"))
    );
    assert_eq!(limited.execution_limit, Some(0));
    assert_eq!(limited.tasks[task.index].state, crate::interp::State::Done);
}

const CALL_BUDGET_IMAGE: &str = r#"
function builtin 0 1 10 2 v:v
const 0 builtin math.floor
K 2 0
Move 4 1
CallK 0 2 3 1 1
Ret 3
end
function iterator 1 1 14 2 v:v
const 0 builtin ipairs
const 1 num 1
NewTable 2
K 3 1
SetIdx 2 3 1
K 4 0
Move 6 2
CallK 0 4 5 1 1
CallK 0 5 6 0 2
Ret 7
end
function typed_call 2 0 8 4 :v
FK 1 2.75
CallT 3 2 1 0
FRet 1
end
function typed 3 1 8 4 f:f
FRet 0
end
function growth_call 4 0 8 2 :v
Call 5 2 0
Ret 2
end
function answer 5 0 8 2 :v
const 0 num 42
K 2 0
Ret 2
end
function error_call 6 0 8 2 :v
const 0 builtin error
const 1 str "budget error"
K 2 0
K 4 1
CallK 0 2 3 1 0
RetNil
end
function protected 7 0 8 2 :v
const 0 func 5
K 2 0
PCall 1 0
Ret 2
end
function terminal 8 0 4 2 :v
RetNil
end
function builtin_dyn 9 1 10 2 v:v
const 0 builtin math.floor
K 2 0
Move 4 1
CallDyn 2 3 1
Ret 3
end
function protected_alias 10 0 8 2 :v
const 0 builtin pcall
const 1 func 5
K 1 0
K 3 1
CallDyn 1 2 1
Ret 3
end
entry 0
"#;

fn call_budget_vm(threaded: bool) -> Box<crate::interp::Interp> {
    let mut vm = Box::new(crate::interp::Interp::new());
    crate::image::load(&mut vm, CALL_BUDGET_IMAGE).unwrap();
    vm.install_globals();
    vm.entries.resize(vm.funcs.len(), 0);
    vm.prepare_threaded();
    vm.threaded = threaded;
    vm
}

fn call_budget_outcome(vm: &mut crate::interp::Interp, tid: usize) -> String {
    match std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| vm.run(tid))) {
        Ok(crate::interp::Outcome::Done(value)) => format!("done:{:#x}", value.0),
        Ok(crate::interp::Outcome::Parked(key)) => format!("parked:{key}"),
        Err(error) => {
            let value = vm.error_value(error);
            format!("error:{}", String::from_utf8_lossy(vm.bytes_of(value)))
        }
    }
}

#[test]
fn native_finite_call_budgets_match_the_rust_budget_points() {
    for fid in [0u32, 1, 2, 4, 6, 7, 8, 9, 10] {
        for limit in [Some(7usize), Some(2), Some(1), Some(0), None] {
            let mut expected = None;
            for threaded in [false, true] {
                let mut vm = call_budget_vm(threaded);
                let tid = vm.spawn(fid, &[Value::num(41.75)]);
                if fid == 4 {
                    // Force the call to fall back before a native push.
                    vm.tasks[tid]
                        .stack
                        .truncate(vm.funcs[fid as usize].frame_words());
                }
                vm.execution_limit = limit;
                let outcome = call_budget_outcome(&mut vm, tid);
                let row = (outcome, vm.execution_limit);
                if let Some(expected) = &expected {
                    assert_eq!(&row, expected, "function {fid}, limit {limit:?}");
                } else {
                    expected = Some(row);
                }
            }
        }
    }
}

#[test]
fn native_scheduled_call_budgets_match_rust_and_allow_terminal_instructions() {
    for fid in [0u32, 1, 2, 4, 6, 7, 8, 9, 10] {
        for slice in [Some(0usize), Some(1), Some(2), None] {
            for limit in [None, Some(0usize), Some(7)] {
                let mut expected = None;
                for threaded in [false, true] {
                    let mut vm = call_budget_vm(threaded);
                    vm.enable_scheduler().unwrap();
                    let task = vm
                        .schedule(Value::func(fid), &[Value::num(41.75)], None)
                        .unwrap();
                    vm.execution_limit = limit;
                    vm.instruction_budget = slice;
                    let outcome = call_budget_outcome(&mut vm, task.index);
                    let error = vm.tasks[task.index].error;
                    let error = if error == Value::NIL {
                        String::new()
                    } else {
                        String::from_utf8_lossy(vm.bytes_of(error)).into_owned()
                    };
                    let row = (outcome, vm.execution_limit, vm.instruction_budget, error);
                    if let Some(expected) = &expected {
                        assert_eq!(
                            &row, expected,
                            "function {fid}, slice {slice:?}, limit {limit:?}"
                        );
                    } else {
                        if limit == Some(0) && matches!(fid, 0 | 1 | 2 | 4 | 6 | 9 | 10) {
                            assert!(
                                row.0.contains("source chunk instruction limit exceeded"),
                                "source limit must win over a slice park: {row:?}"
                            );
                        }
                        if slice == Some(0)
                            && limit == Some(7)
                            && matches!(fid, 0 | 1 | 2 | 4 | 6 | 9 | 10)
                        {
                            assert_eq!(row.0, "parked:0");
                            assert_eq!(row.1, Some(7), "a park must not consume source budget");
                        }
                        if fid == 8 {
                            assert_eq!(row.0, format!("done:{:#x}", Value::NIL.0));
                            assert!(row.3.is_empty());
                        }
                        expected = Some(row);
                    }
                }
            }
        }
    }
}

#[test]
fn native_resolved_call_boundary_charges_once_and_does_not_run_at_zero() {
    for scheduled in [false, true] {
        for budget in [0usize, 1, 7] {
            let mut vm = call_budget_vm(true);
            let tid = if scheduled {
                vm.enable_scheduler().unwrap();
                vm.schedule(Value::func(0), &[], None).unwrap().index
            } else {
                vm.spawn(0, &[])
            };
            // A target already resolved into the result/argument window.
            vm.tasks[tid].stack[HDR + 3] =
                Value::builtin(crate::builtins::id_of("math.floor").unwrap()).0;
            vm.tasks[tid].stack[HDR + 4] = Value::num(41.75).0;
            vm.execution_limit = if scheduled { Some(20) } else { Some(budget) };
            vm.instruction_budget = scheduled.then_some(budget);
            let mut ctx: Ctx = unsafe { std::mem::zeroed() };
            ctx.interp = (&mut *vm as *mut crate::interp::Interp).cast();
            ctx.tid = tid as u64;
            ctx.pc = 2;
            crate::threaded::sync(&mut ctx, &mut vm);
            let before = vm.tasks[tid].stack[HDR + 3];
            let result = unsafe { native_helpers::nupp_rt_call_resolved(&mut ctx, 3, 1, 1) };
            if budget == 0 {
                assert_eq!(vm.tasks[tid].stack[HDR + 3], before);
                if scheduled {
                    assert_eq!(result, ST_PARKED as u64);
                    assert_eq!(vm.execution_limit, Some(20));
                    assert_eq!(vm.tasks[tid].stack[vm.tasks[tid].cur()] >> 32, 2);
                } else {
                    assert_eq!(result, ST_ERROR as u64);
                    assert!(
                        vm.bytes_of(vm.pending_error.unwrap())
                            .ends_with(b"source chunk instruction limit exceeded")
                    );
                }
            } else {
                assert_eq!(result, 3);
                assert_eq!(vm.tasks[tid].stack[HDR + 3], Value::num(41.0).0);
                assert_eq!(
                    vm.execution_limit,
                    Some(if scheduled { 19 } else { budget - 1 })
                );
                assert_eq!(vm.instruction_budget, scheduled.then_some(budget - 1));
            }
        }
    }
}

#[test]
fn native_method_call_budget_is_taken_before_resolving_the_target() {
    let source = r#"
function caller 0 1 8 2 v:v
const 0 str "target"
CallMethod 0 0 1
Ret 0
end
function resolve 1 2 8 2 vv:v
const 0 str "hits"
const 1 num 1
const 2 func 2
GetField 3 1 0
K 4 1
Add 3 3 4
SetField 1 0 3
K 5 2
Ret 5
end
function method 2 1 4 2 v:v
const 0 num 42
K 2 0
Ret 2
end
entry 0
"#;
    for scheduled in [false, true] {
        for budget in [Some(0usize), Some(1), Some(7), None] {
            let mut expected = None;
            for threaded in [false, true] {
                let mut vm = Box::new(crate::interp::Interp::new());
                crate::image::load(&mut vm, source).unwrap();
                vm.entries.resize(vm.funcs.len(), 0);
                vm.prepare_threaded();
                vm.threaded = threaded;
                if scheduled {
                    vm.enable_scheduler().unwrap();
                }
                let receiver = vm.new_table();
                vm.registered.push(receiver);
                let hits = vm.intern("hits");
                vm.set_index(receiver, hits, Value::num(0.0));
                let meta = vm.new_table();
                vm.registered.push(meta);
                let index = vm.intern("__index");
                vm.set_index(meta, index, Value::func(1));
                vm.set_metatable(receiver, meta);
                let tid = if scheduled {
                    vm.schedule(Value::func(0), &[receiver], None)
                        .unwrap()
                        .index
                } else {
                    vm.spawn(0, &[receiver])
                };
                vm.execution_limit = if scheduled { None } else { budget };
                vm.instruction_budget = if scheduled { budget } else { None };
                let outcome = call_budget_outcome(&mut vm, tid);
                let observed = vm.get_index(receiver, hits);
                assert_eq!(
                    observed,
                    Value::num(if budget == Some(0) { 0.0 } else { 1.0 })
                );
                let row = (outcome, vm.execution_limit, vm.instruction_budget);
                if let Some(expected) = &expected {
                    assert_eq!(&row, expected);
                } else {
                    expected = Some(row);
                }
            }
        }
    }
}

#[test]
fn native_and_rust_charge_only_taken_backward_conditions() {
    for instruction in [
        "JmpIf 1 -1",
        "JmpIfNot 1 -1",
        "JmpIfIZero 0 -1",
        "IJmpIfUle 0 1 -1",
        "IJmpIfUlt 0 1 -1",
    ] {
        for taken in [false, true] {
            let setup = match instruction {
                "JmpIf 1 -1" => {
                    if taken {
                        "K 1 0"
                    } else {
                        "Nil 1"
                    }
                }
                "JmpIfNot 1 -1" => {
                    if taken {
                        "Nil 1"
                    } else {
                        "K 1 0"
                    }
                }
                "JmpIfIZero 0 -1" => {
                    if taken {
                        "IK 0 0"
                    } else {
                        "IK 0 1"
                    }
                }
                _ => {
                    if taken {
                        "IK 0 1\nIK 1 2"
                    } else {
                        "IK 0 2\nIK 1 1"
                    }
                }
            };
            // The text fixture reader predates the unsigned conditional
            // opcodes. Install those existing operations after parsing.
            let parsed = if instruction.starts_with("IJmpIf") {
                "JmpIfIZero 0 -1"
            } else {
                instruction
            };
            let source = format!(
                "function condition 0 0 4 2 :v\nconst 0 num 1\n{setup}\n{parsed}\nRetNil\nend\nentry 0\n"
            );
            for (limit, slice) in [
                (Some(0usize), None),
                (Some(1), None),
                (None, Some(0usize)),
                (None, Some(1)),
                (Some(7), Some(1)),
            ] {
                let mut expected = None;
                for threaded in [false, true] {
                    let mut vm = Box::new(crate::interp::Interp::new());
                    crate::image::load(&mut vm, &source).unwrap();
                    if instruction.starts_with("IJmpIf") {
                        let at = vm.funcs[0].code.len() - 2;
                        vm.funcs[0].code[at] = if instruction.starts_with("IJmpIfUle") {
                            crate::interp::Op::IJmpIfUle(0, 1, -1)
                        } else {
                            crate::interp::Op::IJmpIfUlt(0, 1, -1)
                        };
                    }
                    vm.entries.resize(vm.funcs.len(), 0);
                    vm.prepare_threaded();
                    vm.threaded = threaded;
                    let tid = if slice.is_some() {
                        vm.enable_scheduler().unwrap();
                        vm.schedule(Value::func(0), &[], None).unwrap().index
                    } else {
                        vm.spawn(0, &[])
                    };
                    vm.execution_limit = limit;
                    vm.instruction_budget = slice;
                    let outcome = call_budget_outcome(&mut vm, tid);
                    let row = (outcome, vm.execution_limit, vm.instruction_budget);
                    if !taken {
                        assert_eq!(row, (format!("done:{:#x}", Value::NIL.0), limit, slice));
                    } else if limit == Some(7) {
                        assert_eq!(row, ("parked:0".into(), Some(6), Some(0)));
                    }
                    if let Some(expected) = &expected {
                        assert_eq!(
                            &row, expected,
                            "{instruction}, taken {taken}, limit {limit:?}, slice {slice:?}"
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
fn native_dynamic_record_reads_canonicalize_string_keys() {
    let source = r#"
function read 0 2 5 1 vv:v
GetIdx 3 1 2
Ret 3
end
entry 0
"#;
    for threaded in [false, true] {
        for slice in [false, true] {
            let mut vm = crate::interp::Interp::new();
            crate::image::load(&mut vm, source).unwrap();
            let name = vm.intern("field");
            vm.registered.push(name);
            let shape = vm
                .heap
                .shape("dynamic-key-record", &[name], &[crate::heap::SlotTy::Any]);
            let record = vm.new_record(shape);
            vm.registered.push(record);
            vm.set_index(record, name, Value::TRUE);
            let key = if slice {
                let owner = vm.new_string_bytes(b"__field__");
                vm.registered.push(owner);
                vm.new_slice(owner, 2, 5)
            } else {
                vm.new_string_bytes(b"field")
            };
            vm.registered.push(key);
            assert_ne!(key, name, "fixture must use a noncanonical string key");
            assert_eq!(vm.get_index_any(record, key), Value::TRUE);
            vm.entries.resize(vm.funcs.len(), 0);
            vm.prepare_threaded();
            vm.threaded = threaded;
            let tid = vm.spawn(0, &[record, key]);
            assert!(
                matches!(vm.run(tid), crate::interp::Outcome::Done(v) if v == Value::TRUE),
                "threaded {threaded}, slice {slice}"
            );
        }
    }
}

#[test]
fn native_dynamic_record_missing_keys_preserve_index_callbacks() {
    let source = r#"
function read 0 2 5 1 vv:v
GetIdx 3 1 2
Ret 3
end
function echo_key 1 2 4 1 vv:v
Ret 2
end
function answer_true 2 2 4 1 vv:v
const 0 true
K 3 0
Ret 3
end
entry 0
"#;
    for nil_key in [false, true] {
        let mut vm = crate::interp::Interp::new();
        crate::image::load(&mut vm, source).unwrap();
        let field = vm.intern("field");
        vm.registered.push(field);
        let shape = vm
            .heap
            .shape("missing-key-record", &[field], &[crate::heap::SlotTy::Any]);
        let record = vm.new_record(shape);
        vm.registered.push(record);
        let key = if nil_key {
            Value::NIL
        } else {
            vm.new_string_bytes(b"unknown-fresh-key")
        };
        vm.registered.push(key);
        let meta = vm.new_table();
        vm.registered.push(meta);
        let index = vm.intern("__index");
        vm.set_index(meta, index, Value::func(if nil_key { 2 } else { 1 }));
        vm.set_metatable(record, meta);
        vm.entries.resize(vm.funcs.len(), 0);
        vm.prepare_threaded();
        vm.threaded = true;
        let tid = vm.spawn(0, &[record, key]);
        let expected = if nil_key { Value::TRUE } else { key };
        let outcome = vm.run(tid);
        assert!(
            matches!(outcome, crate::interp::Outcome::Done(v) if v == expected),
            "nil key {nil_key}, outcome {outcome:?}"
        );
    }
}
#[test]
fn native_protected_push_preserves_finite_and_exhausted_budgets() {
    let source = r#"
function protected 0 3 8 1 vvv:v
PCall 1 1
Ret 2
end
function identity 1 1 4 1 v:v
Ret 1
end
entry 0
"#;
    for scheduled in [false, true] {
        for budget in [0usize, 1, 7, usize::MAX] {
            for closure in [false, true] {
                let mut vm = Box::new(crate::interp::Interp::new());
                crate::image::load(&mut vm, source).unwrap();
                let callee = if closure {
                    vm.new_closure(1, &[])
                } else {
                    Value::func(1)
                };
                vm.registered.push(callee);
                vm.entries.resize(vm.funcs.len(), 0);
                vm.prepare_threaded();
                vm.funcs[1].ins[0] = Ins::default();
                let args = [Value::NIL, callee, Value::TRUE];
                let tid = if scheduled {
                    vm.enable_scheduler().unwrap();
                    vm.schedule(Value::func(0), &args, None).unwrap().index
                } else {
                    vm.spawn(0, &args)
                };
                vm.execution_limit = (budget != usize::MAX).then_some(budget);
                vm.instruction_budget = if scheduled && budget != usize::MAX {
                    Some(budget)
                } else {
                    None
                };
                let mut ctx: Ctx = unsafe { std::mem::zeroed() };
                ctx.interp = (&mut *vm as *mut crate::interp::Interp).cast();
                ctx.tid = tid as u64;
                crate::threaded::sync(&mut ctx, &mut vm);
                let frame = ctx.stack;
                let pc = vm.finfo[0].code;
                let next = unsafe {
                    nupp_native_runtime_entry(
                        pc,
                        frame.add(HDR),
                        frame.add(vm.funcs[0].off_i()).cast(),
                        frame.add(vm.funcs[0].off_f()).cast(),
                        &mut ctx,
                        frame,
                    )
                };
                let pushed = vm.funcs[0].frame_words();
                assert_eq!(
                    ctx.cur, pushed as u64,
                    "scheduled {scheduled}, budget {budget}, closure {closure}"
                );
                // Stop explicitly at the callee entry to isolate the native
                // protected push from the native return path.
                assert_eq!(next, vm.finfo[1].code as u64);
                assert_eq!(vm.tasks[tid].protected.len(), 1);
                let protected = &vm.tasks[tid].protected[0];
                assert_eq!(
                    (protected.frame, protected.caller, protected.result),
                    (pushed, 0, HDR + 1)
                );
                assert_eq!(ctx.guard, pushed as u64);
                assert_eq!(ctx.budget, budget as u64);
                assert_eq!(ctx.budget_mark, budget as u64);
                assert_eq!(vm.execution_limit, (budget != usize::MAX).then_some(budget));
                assert_eq!(vm.tasks[tid].stack[pushed + HDR + 1], Value::TRUE.0);
                assert_eq!(
                    vm.tasks[tid].stack[pushed + 2],
                    if closure { callee.0 } else { Value::NIL.0 }
                );
                assert_eq!(vm.tasks[tid].stack[0] >> 32, 1);
            }
        }
    }
}
#[test]
fn native_finite_method_calls_charge_before_resolution_and_stay_native() {
    let source = r#"
function caller 0 1 8 2 v:v
const 0 str "target"
CallMethod 0 0 1
Ret 0
end
function identity 1 1 4 2 v:v
Ret 1
end
function variable 2 1 4 2 v:v vararg
Ret 1
end
entry 0
"#;
    for scheduled in [false, true] {
        for budget in [1usize, 2, 7] {
            for mode in 0..4 {
                let mut vm = Box::new(crate::interp::Interp::new());
                crate::image::load(&mut vm, source).unwrap();
                let target = match mode {
                    0 => Value::func(1),
                    1 => vm.new_closure(1, &[]),
                    2 => Value::builtin(crate::builtins::id_of("type").unwrap()),
                    _ => Value::func(2),
                };
                vm.registered.push(target);
                let receiver = vm.new_table();
                vm.registered.push(receiver);
                let name = vm.intern("target");
                vm.set_index(receiver, name, target);
                vm.entries.resize(vm.funcs.len(), 0);
                vm.prepare_threaded();
                let tid = if scheduled {
                    vm.enable_scheduler().unwrap();
                    vm.schedule(Value::func(0), &[receiver], None)
                        .unwrap()
                        .index
                } else {
                    vm.spawn(0, &[receiver])
                };
                vm.execution_limit = Some(budget);
                vm.instruction_budget = scheduled.then_some(budget);
                let mut ctx: Ctx = unsafe { std::mem::zeroed() };
                ctx.interp = (&mut *vm as *mut crate::interp::Interp).cast();
                ctx.tid = tid as u64;
                let slow_calls = vec![0u8; crate::builtins::NAMES.len()];
                ctx.slow_calls = slow_calls.as_ptr();
                ctx.nslow_calls = slow_calls.len() as u64;
                crate::threaded::sync(&mut ctx, &mut vm);
                let frame = ctx.stack;
                let pc = vm.finfo[0].code;
                let next = unsafe {
                    nupp_native_runtime_entry(
                        pc,
                        frame.add(HDR),
                        frame.add(vm.funcs[0].off_i()).cast(),
                        frame.add(vm.funcs[0].off_f()).cast(),
                        &mut ctx,
                        frame,
                    )
                };
                // The method and terminal return both stay in Nupp; completion
                // exits by status rather than an instruction handoff.
                assert_eq!(
                    next,
                    0,
                    "scheduled {scheduled}, budget {budget}, mode {mode}"
                );
                assert_eq!(ctx.status, ST_DONE);
                assert_eq!(ctx.cur, 0);
                assert_eq!(ctx.budget, (budget - 1) as u64);
                assert_eq!(vm.execution_limit, Some(budget - 1));
                assert_eq!(vm.instruction_budget, scheduled.then_some(budget - 1));
                let result = Value(vm.tasks[tid].stack[HDR]);
                if mode == 2 {
                    assert_eq!(vm.bytes_of(result), b"table");
                } else {
                    assert_eq!(result, receiver);
                }
            }
        }
    }
}

#[test]
fn native_precharged_resolved_call_does_not_charge_again() {
    for scheduled in [false, true] {
        for budget in [0usize, 1, 7] {
            let mut vm = call_budget_vm(true);
            let tid = if scheduled {
                vm.enable_scheduler().unwrap();
                vm.schedule(Value::func(0), &[], None).unwrap().index
            } else {
                vm.spawn(0, &[])
            };
            vm.tasks[tid].stack[HDR + 3] =
                Value::builtin(crate::builtins::id_of("math.floor").unwrap()).0;
            vm.tasks[tid].stack[HDR + 4] = Value::num(41.75).0;
            vm.execution_limit = Some(budget);
            vm.instruction_budget = scheduled.then_some(budget);
            let mut ctx: Ctx = unsafe { std::mem::zeroed() };
            ctx.interp = (&mut *vm as *mut crate::interp::Interp).cast();
            ctx.tid = tid as u64;
            ctx.pc = 2;
            crate::threaded::sync(&mut ctx, &mut vm);
            let result = unsafe { native_helpers::nupp_rt_call_resolved(&mut ctx, 3, 1, 0) };
            assert_eq!(result, 3);
            assert_eq!(vm.tasks[tid].stack[HDR + 3], Value::num(41.0).0);
            assert_eq!(vm.execution_limit, Some(budget));
            assert_eq!(vm.instruction_budget, scheduled.then_some(budget));
            assert_eq!(ctx.budget, budget as u64);
        }
    }
}


#[test]
fn record_and_physical_encodings_have_native_owners() {
    let field = crate::storage::PhysicalField {
        identity: 65534,
        name: 65535,
        ordinal: 32768,
        offset: 0x87654321,
        kind: 8,
    };
    for op in [
        Op::GetSlot(3, 1, 65535, 0x87654321),
        Op::GetSlotF(3, 1, 65535, 0x87654321),
        Op::SetSlot(1, 65535, 3, 0x87654321),
        Op::SetSlotF(1, 65535, 3, 0x87654321),
        Op::TagCheckRec(3, 1, 0x87654321),
        Op::IsRec(3, 1, 0x87654321),
        Op::GetPhys(3, 1, field),
        Op::GetPhysF(3, 1, field),
        Op::GetPhysI(3, 1, field),
        Op::GetPhysU(3, 1, field),
        Op::SetPhys(1, field, 3),
        Op::SetPhysF(1, field, 3),
        Op::SetPhysI(1, field, 3),
    ] {
        let encoded = crate::threaded::encode(&op);
        assert_ne!(encoded.op, Code::Slow as u8);
        match op {
            Op::GetSlot(..) | Op::GetSlotF(..) | Op::SetSlot(..) | Op::SetSlotF(..) => {
                assert_eq!(encoded.k, 65535);
                assert_eq!(encoded.imm as u32, 0x87654321);
            }
            Op::GetPhys(..)
            | Op::GetPhysF(..)
            | Op::GetPhysI(..)
            | Op::GetPhysU(..)
            | Op::SetPhys(..)
            | Op::SetPhysF(..)
            | Op::SetPhysI(..) => {
                assert_eq!(encoded.imm as u32, 0xfffffffe);
                assert_eq!(encoded.k as u64 & 0x00ffffffffffffff, field.packed(false));
            }
            _ => (),
        }
    }
}

fn record_contract_vm(threaded: bool) -> Box<crate::interp::Interp> {
    let mut vm = Box::new(crate::interp::Interp::new());
    let fields = (0..300)
        .map(|i| format!("f{i}:any"))
        .collect::<Vec<_>>()
        .join(" ");
    let source = format!(
        r#"
shape 0 Wide {fields}
shape 1 Other f299:any
function read 0 1 8 3 v:v
GetSlot 3 1 299 0
Ret 3
end
function readf 1 1 8 3 v:v
GetSlotF 0 1 299 0
FBox 3 0
Ret 3
end
function write 2 2 8 3 vv:v
SetSlot 1 299 2 0
Ret 1
end
function writef 3 2 8 3 vv:v
FUnbox 0 2
SetSlotF 1 299 0 0
Ret 1
end
function check 4 1 8 3 v:v
TagCheckRec 3 1 0
Ret 3
end
function isrec 5 1 8 3 v:v
IsRec 3 1 0
Ret 3
end
function index 6 2 8 3 vv:v
NewTable 3
const 0 num 42
K 4 0
Ret 4
end
function newindex 7 3 12 3 vvv:v
const 0 builtin rawset
const 1 str "seen"
NewTable 9
K 4 0
Move 6 1
K 7 1
Move 8 3
CallDyn 4 5 3
RetNil
end
entry 0
"#
    );
    crate::image::load(&mut vm, &source).unwrap();
    vm.install_globals();
    vm.entries.resize(vm.funcs.len(), 0);
    vm.prepare_threaded();
    vm.threaded = threaded;
    vm
}

#[test]
fn native_wide_record_slots_match_shape_misses_and_metatable_callbacks() {
    for threaded in [false, true] {
        for carrier in [0u32, 1, 2] {
            let mut vm = record_contract_vm(threaded);
            let object = if carrier == 2 {
                vm.new_table()
            } else {
                vm.new_record(carrier)
            };
            vm.registered.push(object);
            let name = vm.intern("f299");
            vm.set_index(object, name, Value::num(-0.0));
            vm.execution_limit = Some(17);
            vm.instruction_budget = Some(0);
            assert_eq!(vm.call_value(Value::func(0), &[object])[0].0, num(-0.0));
            assert_eq!(vm.call_value(Value::func(1), &[object])[0].0, num(-0.0));
            assert_eq!(
                vm.execution_limit,
                Some(17),
                "leaf slots do not charge source budget"
            );
            assert_eq!(
                vm.instruction_budget,
                Some(0),
                "leaf slots do not park at zero slice budget"
            );
            vm.instruction_budget = None;
            vm.call_value(Value::func(2), &[object, Value::TRUE]);
            assert_eq!(vm.get_index(object, name), Value::TRUE);
            vm.call_value(Value::func(3), &[object, Value::num(3.25)]);
            assert_eq!(vm.get_index(object, name), Value::num(3.25));
            assert_eq!(
                vm.call_value(Value::func(5), &[object])[0],
                Value::boolean(carrier == 0)
            );
            if carrier == 0 {
                assert_eq!(vm.call_value(Value::func(4), &[object])[0], object);
            } else {
                assert_eq!(
                    vm.guarded(|vm| vm.call_value(Value::func(4), &[object])[0]),
                    Value::ERROR
                );
                let error = vm.pending_error.take().unwrap();
                assert!(
                    String::from_utf8_lossy(vm.bytes_of(error)).contains("expected record (Wide)")
                );
            }
            vm.set_index(object, name, Value::NIL);
            let meta = vm.new_table();
            vm.registered.push(meta);
            let index = vm.intern("__index");
            vm.set_index(meta, index, Value::func(6));
            let newindex = vm.intern("__newindex");
            vm.set_index(meta, newindex, Value::func(7));
            vm.set_metatable(object, meta);
            vm.heap.stress = true;
            vm.heap.stress_steps = true;
            vm.heap.oracle = true;
            vm.heap.quarantine = true;
            assert_eq!(
                vm.call_value(Value::func(0), &[object])[0],
                Value::num(42.0)
            );
            assert_eq!(
                vm.call_value(Value::func(1), &[object])[0],
                Value::num(42.0)
            );
            vm.call_value(Value::func(2), &[object, Value::num(99.0)]);
            let seen = vm.intern("seen");
            assert_eq!(vm.get_index(object, seen), Value::num(99.0));
            // A nil slot follows __newindex even on the expected shape.
            vm.call_value(Value::func(3), &[object, Value::num(101.5)]);
            assert_eq!(
                vm.get_index(object, seen),
                Value::num(101.5), "threaded {threaded}, carrier {carrier}"
            );
            vm.full_cycle();
            vm.check_oracle();
        }
    }
}

#[test]
fn native_slot_float_errors_match_reference_after_name_resolution() {
    for threaded in [false, true] {
        for carrier in [0u32, 1, 2] {
            let mut vm = record_contract_vm(threaded);
            let object = if carrier == 2 {
                vm.new_table()
            } else {
                vm.new_record(carrier)
            };
            vm.registered.push(object);
            let name = vm.intern("f299");
            vm.set_index(object, name, Value::TRUE);
            assert_eq!(
                vm.guarded(|vm| vm.call_value(Value::func(1), &[object])[0]),
                Value::ERROR
            );
            let error = vm.pending_error.take().unwrap();
            assert_eq!(vm.bytes_of(error), b"runtime error: slot is not a number");
        }
    }
}

// Enter just the native chain. Any instruction fallback remains an address,
// so these regressions cannot pass by silently running the Rust step.
unsafe fn return_chain(vm: &mut crate::interp::Interp, ctx: &mut Ctx, pc: usize) -> u64 {
    let frame = ctx.stack.add(ctx.cur as usize);
    let fid = (*frame & u32::MAX as u64) as usize;
    let info = &vm.finfo[fid];
    nupp_native_runtime_entry(
        info.code.add(pc),
        frame.add(HDR),
        frame.add(info.off_i as usize).cast(),
        frame.add(info.off_f as usize).cast(),
        ctx,
        frame,
    )
}

fn return_context(vm: &mut crate::interp::Interp, tid: usize) -> Ctx {
    let mut ctx: Ctx = unsafe { std::mem::zeroed() };
    ctx.interp = (vm as *mut crate::interp::Interp).cast();
    ctx.tid = tid as u64;
    crate::threaded::sync(&mut ctx, vm);
    ctx
}

#[test]
fn native_terminal_returns_own_full_packs_and_zero_budget_roots() {
    for scheduled in [false, true] {
        for instruction in ["Ret 1", "RetNil", "RetN 1 0", "RetN 1 127", "RetN 1 255"] {
            let source = format!("function root 0 0 255 2 :v\n{instruction}\nend\nentry 0\n");
            let mut vm = Box::new(crate::interp::Interp::new());
            crate::image::load(&mut vm, &source).unwrap();
            vm.prepare_threaded();
            let tid = if scheduled {
                vm.enable_scheduler().unwrap();
                vm.schedule(Value::func(0), &[], None).unwrap().index
            } else {
                vm.spawn(0, &[])
            };
            // Give every value distinct managed identity, with the only tail
            // roots in extra. Completion must transfer that ownership to Task.
            let mut input = Vec::new();
            for i in 0..255 {
                let value = vm.new_string_bytes(format!("return-managed-{i}").as_bytes());
                vm.registered.push(value);
                input.push(value);
            }
            for i in 0..135 {
                vm.tasks[tid].stack[HDR + 1 + i] = input[i].0;
            }
            for i in 0..127 {
                vm.extra[i] = input[128 + i];
            }
            vm.extra_n = 127;
            vm.last_nres = 128;
            vm.registered.clear();
            vm.execution_limit = Some(0);
            vm.instruction_budget = Some(0);
            let mut ctx = return_context(&mut vm, tid);
            let exit = unsafe { return_chain(&mut vm, &mut ctx, 0) };
            assert_eq!(
                exit, 0,
                "terminal {instruction}, scheduled {scheduled} returned an instruction"
            );
            assert_eq!(ctx.status, ST_DONE);
            assert!(matches!(vm.tasks[tid].state, crate::interp::State::Done));
            let expected: &[Value] = match instruction {
                "Ret 1" => &input[..1],
                "RetNil" | "RetN 1 0" => &[],
                "RetN 1 127" => &input[..127],
                _ => &input,
            };
            assert_eq!(ctx.last_nres as usize, expected.len());
            assert_eq!(
                ctx.result,
                expected.first().copied().unwrap_or(Value::NIL).0
            );
            if instruction != "Ret 1" {
                assert_eq!(vm.tasks[tid].results, expected);
            }
            assert_eq!(vm.extra_n, 0);
            assert_eq!(vm.execution_limit, Some(0));
            assert_eq!(vm.instruction_budget, Some(0));
            vm.full_cycle();
            for (i, value) in expected.iter().enumerate() {
                assert_eq!(
                    vm.bytes_of(*value),
                    format!("return-managed-{i}").as_bytes()
                );
            }
        }
    }
}

#[test]
fn native_large_return_packs_survive_gc_before_wide_padding() {
    for trailing in [false, true] {
        let encoded = if trailing { 255 } else { 127 };
        let source = format!(
            "function caller 0 0 255 2 :v\nCall 1 0 0\nPadResults 0 255\nRetNil\nend\nfunction callee 1 0 150 2 :v\nRetN 1 {encoded}\nend\nentry 0\n"
        );
        let mut vm = Box::new(crate::interp::Interp::new());
        crate::image::load(&mut vm, &source).unwrap();
        vm.prepare_threaded();
        // Stop before PadResults, force a collection, then restore it. The
        // second native entry must execute padding and reach the next marker.
        let padding = vm.funcs[0].ins[1];
        vm.funcs[0].ins[1] = Ins::default();
        vm.funcs[0].ins[2] = Ins::default();
        let tid = vm.spawn(0, &[]);
        vm.tasks[tid].stack.resize(1024, 0);
        let mut ctx = return_context(&mut vm, tid);
        let caller_words = vm.funcs[0].frame_words();
        unsafe {
            push(&mut ctx, ctx.stack, 1, HDR as u32, 0, 1, Value::NIL.0);
        }
        let callee = ctx.cur as usize;
        assert_eq!(callee, caller_words);
        let mut input = Vec::new();
        for i in 0..255 {
            let value = vm.new_string_bytes(format!("wide-return-{i}").as_bytes());
            vm.registered.push(value);
            input.push(value);
        }
        for i in 0..135 {
            vm.tasks[tid].stack[callee + HDR + 1 + i] = input[i].0;
        }
        for i in 0..127 {
            vm.extra[i] = input[128 + i];
        }
        vm.extra_n = 127;
        ctx.last_nres = 128;
        // Re-derive after the helper above expanded the task stack.
        ctx.stack = vm.tasks[tid].stack.as_mut_ptr();
        vm.registered.clear();
        let exit = unsafe { return_chain(&mut vm, &mut ctx, 0) };
        assert_eq!(
            exit,
            unsafe { vm.finfo[0].code.add(1) } as u64,
            "RetN must not fall back"
        );
        assert_eq!(ctx.cur, 0);
        let count = if trailing { 128 } else { 127 };
        assert_eq!(ctx.last_nres, count);
        assert_eq!(vm.extra_n, count as usize - 1);
        vm.tasks[tid].set_cur(0);
        vm.last_nres = count as usize;
        vm.full_cycle();
        for i in 0..count as usize - 1 {
            assert_eq!(
                vm.bytes_of(vm.extra[i]),
                format!("wide-return-{}", i + 1).as_bytes()
            );
        }
        vm.funcs[0].ins[1] = padding;
        let exit = unsafe { return_chain(&mut vm, &mut ctx, 1) };
        assert_eq!(
            exit,
            unsafe { vm.finfo[0].code.add(2) } as u64,
            "PadResults must not fall back"
        );
        assert_eq!(vm.extra_n, 0);
        for i in 0..255 {
            let expected = if i < count as usize {
                input[i]
            } else {
                Value::NIL
            };
            assert_eq!(vm.tasks[tid].stack[HDR + i], expected.0);
        }
    }
}

#[test]
fn native_guarded_returns_finalize_protection_without_instruction_fallback() {
    let source = "function caller 0 0 40 2 :v\nPCall 1 0\nPadResults 1 16\nRetNil\nend\nfunction callee 1 0 20 2 :v\nRetN 1 12\nend\nentry 0\n";
    for scheduled in [false, true] {
        let mut vm = Box::new(crate::interp::Interp::new());
        crate::image::load(&mut vm, source).unwrap();
        vm.prepare_threaded();
        vm.funcs[0].ins[2] = Ins::default();
        let tid = if scheduled {
            vm.enable_scheduler().unwrap();
            vm.schedule(Value::func(0), &[], None).unwrap().index
        } else {
            vm.spawn(0, &[])
        };
        let mut ctx = return_context(&mut vm, tid);
        unsafe {
            push(&mut ctx, ctx.stack, 1, (HDR + 2) as u32, 0, 1, Value::NIL.0);
        }
        let retired = ctx.cur as usize;
        for i in 0..12 {
            vm.tasks[tid].stack[retired + HDR + 1 + i] = num(i as f64 + 0.5);
        }
        vm.tasks[tid].protected.push(crate::interp::Protected {
            frame: retired,
            caller: 0,
            result: HDR + 1,
            handler: Value::NIL,
        });
        ctx.guard = retired as u64;
        ctx.budget = 0;
        ctx.budget_mark = 0;
        vm.execution_limit = Some(0);
        vm.instruction_budget = Some(0);
        let exit = unsafe { return_chain(&mut vm, &mut ctx, 0) };
        assert_eq!(exit, unsafe { vm.finfo[0].code.add(2) } as u64);
        assert_eq!(ctx.status, 0);
        assert_eq!(ctx.cur, 0);
        assert_eq!(ctx.last_nres, 13);
        assert_eq!(ctx.guard, NO_GUARD);
        assert!(vm.tasks[tid].protected.is_empty());
        assert_eq!(vm.tasks[tid].stack[HDR + 1], Value::TRUE.0);
        for i in 0..12 {
            assert_eq!(vm.tasks[tid].stack[HDR + 2 + i], num(i as f64 + 0.5));
        }
        assert_eq!(&vm.tasks[tid].stack[HDR + 14..HDR + 17], &[Value::NIL.0; 3]);
        assert_eq!(vm.execution_limit, Some(0));
        assert_eq!(vm.instruction_budget, Some(0));
    }
}

#[test]
fn native_cleanup_returns_reload_roots_and_preserve_error_before_transfer() {
    let source = r#"
function root 0 0 32 2 :v
RetN 1 12
end
function cleanup 1 1 255 2 v:v
const 0 str "closed"
const 1 num 1
NewTable 20
GetField 2 1 0
K 3 1
Add 2 2 3
SetField 1 0 2
RetNil
end
function failedCleanup 2 1 8 2 v:v
const 0 builtin error
const 1 str "cleanup failed exactly"
K 2 0
K 4 1
CallDyn 2 3 1
RetNil
end
entry 0
"#;
    for fails in [false, true] {
        let mut vm = Box::new(crate::interp::Interp::new());
        crate::image::load(&mut vm, source).unwrap();
        vm.install_globals();
        vm.prepare_threaded();
        vm.threaded = true;
        let object = vm.new_table();
        vm.registered.push(object);
        let closed = vm.intern("closed");
        vm.set_index(object, closed, Value::num(0.0));
        let tid = vm.spawn(0, &[]);
        let mut expected = Vec::new();
        for i in 0..12 {
            let value = vm.new_string_bytes(format!("cleanup-root-{i}").as_bytes());
            vm.tasks[tid].stack[HDR + 1 + i] = value.0;
            expected.push(value);
        }
        vm.tasks[tid].cleanups.push(crate::interp::Cleanup {
            frame: 0,
            value: object,
            callback: Value::func(if fails { 2 } else { 1 }),
        });
        vm.heap.stress_steps = true;
        vm.heap.oracle = true;
        vm.heap.quarantine = true;
        vm.last_nres = 77;
        let mut ctx = return_context(&mut vm, tid);
        let exit = unsafe { return_chain(&mut vm, &mut ctx, 0) };
        assert_eq!(
            exit, 0,
            "guarded return must not become an instruction fallback"
        );
        assert!(vm.tasks[tid].cleanups.is_empty());
        if fails {
            assert_eq!(ctx.status, ST_ERROR);
            assert!(matches!(
                vm.tasks[tid].state,
                crate::interp::State::Runnable
            ));
            assert_eq!(ctx.cur, 0);
            assert_eq!(ctx.last_nres, 77);
            let error = vm.pending_error.take().unwrap();
            assert_eq!(vm.bytes_of(error), b"cleanup failed exactly");
            assert!(vm.tasks[tid].results.is_empty());
        } else {
            assert_eq!(ctx.status, ST_DONE);
            assert_eq!(vm.tasks[tid].results, expected);
            assert_eq!(vm.get_index(object, closed), Value::num(1.0));
            vm.full_cycle();
            for (i, value) in expected.iter().enumerate() {
                assert_eq!(vm.bytes_of(*value), format!("cleanup-root-{i}").as_bytes());
            }
        }
    }
}

#[test]
fn native_return_cleanup_parks_snapshots_and_completes_once() {
    use crate::persist::{self, Policies, ResourceCodecs};
    let source = r#"
function root 0 1 16 2 v:v
RetN 1 1
end
function cleanup 1 1 16 2 v:v
const 0 str "nupp.host"
const 1 str "sleep"
const 2 num 5
const 3 str "closed"
const 4 num 1
Require 2 0
GetField 3 2 1
K 5 2
CallDyn 3 4 1
GetField 6 1 3
K 7 4
Add 6 6 7
SetField 1 3 6
RetNil
end
entry 0
"#;
    let mut vm = Box::new(crate::interp::Interp::new());
    crate::image::load(&mut vm, source).unwrap();
    vm.install_globals();
    let host = vm.host_table();
    vm.loaded.insert("nupp.host".into(), host);
    vm.prepare_threaded();
    vm.threaded = true;
    vm.enable_scheduler().unwrap();
    let object = vm.new_table();
    vm.registered.push(object);
    let closed = vm.intern("closed");
    vm.set_index(object, closed, Value::num(0.0));
    let task = vm.schedule(Value::func(0), &[object], None).unwrap();
    vm.tasks[task.index].cleanups.push(crate::interp::Cleanup {
        frame: 0,
        value: object,
        callback: Value::func(1),
    });
    vm.scheduler
        .as_mut()
        .unwrap()
        .ready
        .retain(|&tid| tid != task.index);
    vm.execution_limit = Some(20);
    let mut ctx = return_context(&mut vm, task.index);
    let exit = unsafe { return_chain(&mut vm, &mut ctx, 0) };
    assert_eq!(
        exit, 0,
        "cleanup park must leave by status, not Rust instruction"
    );
    assert_eq!(ctx.status, ST_PARKED);
    assert_eq!(ctx.cur, 0);
    assert_eq!(
        vm.tasks[task.index].stack[0] >> 32,
        0,
        "retry same return after wait"
    );
    assert_eq!(
        vm.execution_limit,
        Some(20),
        "return/cleanup polling charges no call edge"
    );
    vm.run_ready(16).unwrap();
    assert_eq!(vm.scheduler.as_ref().unwrap().next_wakeup(), Some(5));
    vm.full_cycle();
    let bytes = persist::save_vm(
        &mut vm,
        &Policies::default(),
        &mut ResourceCodecs::default(),
    )
    .unwrap();
    let mut restored =
        persist::load_vm(&bytes, &Policies::default(), &mut ResourceCodecs::default()).unwrap();
    restored.prepare_threaded();
    restored.threaded = true;
    restored.heap.stress_steps = true;
    restored.heap.oracle = true;
    restored.heap.quarantine = true;
    restored.advance_to(5).unwrap();
    for _ in 0..8 {
        restored.run_ready(16).unwrap();
    }
    assert!(matches!(
        restored.tasks[task.index].state,
        crate::interp::State::Done
    ));
    let result = restored.tasks[task.index].result;
    assert_eq!(restored.tasks[task.index].results, [result]);
    let closed = restored.intern("closed");
    assert_eq!(restored.get_index(result, closed), Value::num(1.0));
    restored.run_ready(16).unwrap();
    assert_eq!(restored.get_index(result, closed), Value::num(1.0));
}

#[test]
fn native_float_returns_keep_scalar_bits_and_typed_caller_windows() {
    let patterns = [
        0,
        (-0.0f64).to_bits(),
        3.25f64.to_bits(),
        f64::INFINITY.to_bits(),
        0x7ff8_0000_0000_0042,
        0xfffc_dead_beef_1234,
        0x7ff0_0000_0000_0001,
    ];
    for bits in patterns {
        for terminal in [false, true] {
            for indirect in [false, true] {
                let source = "function caller 0 0 24 8 :v\nRetNil\nend\nfunction callee 1 0 24 8 :f\nFRet 1\nend\nentry 0\n";
                let mut vm = Box::new(crate::interp::Interp::new());
                crate::image::load(&mut vm, source).unwrap();
                vm.prepare_threaded();
                vm.funcs[0].ins[0] = Ins::default();
                let tid = vm.spawn(if terminal { 1 } else { 0 }, &[]);
                vm.tasks[tid].stack.resize(512, 0);
                let mut ctx = return_context(&mut vm, tid);
                if !terminal {
                    unsafe {
                        push(&mut ctx, ctx.stack, 1, (HDR + 3) as u32, 0, 0, Value::NIL.0);
                    }
                    if indirect {
                        vm.tasks[tid].stack[ctx.cur as usize + 3] |=
                            (1 << 32) | (vm.funcs[0].off_f() + 4) as u64;
                    }
                }
                let callee = ctx.cur as usize;
                let at = callee + vm.funcs[1].off_f() + 1;
                vm.tasks[tid].stack[at] = bits;
                vm.execution_limit = Some(0);
                vm.instruction_budget = Some(0);
                ctx.budget = 0;
                ctx.budget_mark = 0;
                let expected = Value::num(f64::from_bits(bits));
                let before = vm.tasks[tid].stack.clone();
                let exit = unsafe { return_chain(&mut vm, &mut ctx, 0) };
                if terminal {
                    assert_eq!(
                        exit, 0,
                        "FRet must complete rather than return an instruction"
                    );
                    assert_eq!(ctx.status, ST_DONE);
                    assert_eq!(vm.tasks[tid].result, expected);
                    assert!(vm.tasks[tid].results.is_empty());
                } else {
                    assert_eq!(
                        exit, vm.finfo[0].code as u64,
                        "FRet must reach caller marker"
                    );
                    let destination = if indirect {
                        vm.funcs[0].off_f() + 4
                    } else {
                        HDR + 3
                    };
                    let mut after = before;
                    after[destination] = expected.0;
                    assert_eq!(
                        vm.tasks[tid].stack, after,
                        "bits {bits:x}, indirect {indirect}"
                    );
                    assert_eq!(ctx.cur, 0);
                }
                assert_eq!(ctx.last_nres, 1);
                assert_eq!(ctx.result, expected.0);
                assert_eq!(vm.execution_limit, Some(0));
                assert_eq!(vm.instruction_budget, Some(0));
            }
        }
    }
}

#[test]
fn native_float_returns_poll_cleanup_and_keep_error_precedence() {
    let source = r#"
function root 0 0 16 4 :f
FRet 2
end
function cleanup 1 1 16 2 v:v
const 0 str "closed"
const 1 num 1
GetField 2 1 0
K 3 1
Add 2 2 3
SetField 1 0 2
RetNil
end
function failure 2 1 8 2 v:v
const 0 builtin error
const 1 str "float cleanup failed"
K 2 0
K 4 1
CallDyn 2 3 1
RetNil
end
entry 0
"#;
    for fails in [false, true] {
        let mut vm = Box::new(crate::interp::Interp::new());
        crate::image::load(&mut vm, source).unwrap();
        vm.install_globals();
        vm.prepare_threaded();
        vm.threaded = true;
        let object = vm.new_table();
        vm.registered.push(object);
        let closed = vm.intern("closed");
        vm.set_index(object, closed, Value::num(0.0));
        let tid = vm.spawn(0, &[]);
        let at = vm.funcs[0].off_f() + 2;
        vm.tasks[tid].stack[at] = (-0.0f64).to_bits();
        vm.tasks[tid].cleanups.push(crate::interp::Cleanup {
            frame: 0,
            value: object,
            callback: Value::func(if fails { 2 } else { 1 }),
        });
        vm.heap.stress_steps = true;
        vm.heap.oracle = true;
        vm.last_nres = 13;
        let mut ctx = return_context(&mut vm, tid);
        let exit = unsafe { return_chain(&mut vm, &mut ctx, 0) };
        assert_eq!(exit, 0);
        assert!(vm.tasks[tid].cleanups.is_empty());
        if fails {
            assert_eq!(ctx.status, ST_ERROR);
            assert_eq!(ctx.last_nres, 13);
            assert!(matches!(
                vm.tasks[tid].state,
                crate::interp::State::Runnable
            ));
            let error = vm.pending_error.take().unwrap();
            assert_eq!(vm.bytes_of(error), b"float cleanup failed");
        } else {
            assert_eq!(ctx.status, ST_DONE);
            assert_eq!(ctx.last_nres, 1);
            assert_eq!(vm.tasks[tid].result.0, (-0.0f64).to_bits());
            assert_eq!(vm.get_index(object, closed), Value::num(1.0));
        }
    }
}
