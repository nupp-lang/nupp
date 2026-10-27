use super::*;
use crate::{
    interp::{Interp, Op},
    numeric::{self, Integer},
    value::Value,
};

pub(super) fn fixture(op: Op) -> (Box<Interp>, usize) {
    let mut vm = Box::new(Interp::new());
    crate::image::load(
        &mut vm,
        "function numeric 0 2 8 8 vv:v\nRetNil\nend\nentry 0\n",
    )
    .unwrap();
    vm.funcs[0].code = vec![op, Op::RetNil, Op::RetNil];
    vm.entries.resize(1, 0);
    vm.prepare_threaded();
    // Explicit sentinels keep this proof independent of later opcode ports.
    vm.funcs[0].ins[1].op = Code::Slow as u8;
    vm.funcs[0].ins[2].op = Code::Slow as u8;
    let tid = vm.spawn(0, &[]);
    (vm, tid)
}
pub(super) fn put(vm: &mut Interp, tid: usize, slot: usize, value: Value) {
    let at = vm.tasks[tid].cur() + 4 + slot;
    vm.tasks[tid].stack[at] = value.0;
}
pub(super) fn value(vm: &Interp, tid: usize, slot: usize) -> Value {
    Value(vm.tasks[tid].stack[vm.tasks[tid].cur() + 4 + slot])
}
pub(super) fn intput(vm: &mut Interp, tid: usize, slot: usize, value: u64) {
    let at = vm.tasks[tid].cur() + vm.funcs[0].off_i() + slot;
    vm.tasks[tid].stack[at] = value;
}
pub(super) fn intget(vm: &Interp, tid: usize, slot: usize) -> u64 {
    vm.tasks[tid].stack[vm.tasks[tid].cur() + vm.funcs[0].off_i() + slot]
}
pub(super) fn direct(vm: &mut Interp, tid: usize, expected: usize) -> Ctx {
    let mut ctx: Ctx = unsafe { std::mem::zeroed() };
    ctx.interp = (vm as *mut Interp).cast();
    ctx.tid = tid as u64;
    crate::threaded::sync(&mut ctx, vm);
    let f = &vm.funcs[0];
    assert_ne!(f.ins[0].op, Code::Slow as u8);
    let (off_i, off_f) = (f.off_i(), f.off_f());
    let pc = f.ins.as_ptr();
    let frame = unsafe { vm.tasks[tid].stack.as_mut_ptr().add(vm.tasks[tid].cur()) };
    let next = unsafe {
        nupp_native_runtime_entry(
            pc,
            frame.add(4),
            frame.add(off_i).cast(),
            frame.add(off_f).cast(),
            &mut ctx,
            frame,
        )
    };
    if ctx.status == ST_ERROR {
        assert_eq!(next, 0);
    } else {
        assert_eq!(
            next,
            unsafe { pc.add(expected) } as u64,
            "opcode escaped to Rust step"
        );
    }
    ctx
}
fn description(value: Value) -> (u64, Option<bool>) {
    match numeric::integer(value) {
        Some(i) => (i.bits, Some(i.unsigned)),
        None => (value.0, None),
    }
}
fn number(vm: &mut Interp, kind: i8, bits: u64) -> Value {
    if kind < 0 {
        Value::num(f64::from_bits(bits))
    } else {
        let value = vm.box_integer(Integer {
            bits,
            unsigned: kind != 0,
        });
        vm.register(value);
        value
    }
}

#[test]
fn native_numeric_encodes_all_numeric_operands_without_truncation() {
    for (op, name, a, b, c, imm) in [
        (Op::UUnbox(250, 249), "UUnbox", 250, 249, 0, 0),
        (Op::UBox(250, 249), "UBox", 250, 249, 0, 0),
        (Op::Div(250, 249, 248), "Div", 250, 249, 248, 0),
        (Op::Pow(250, 249, 248), "Pow", 250, 249, 248, 0),
        (Op::IDiv(250, 249, 248), "IDiv", 250, 249, 248, 0),
        (
            Op::TagCheckInt(250, 249, true),
            "TagCheckInt",
            250,
            249,
            1,
            0,
        ),
        (Op::TagCheckStr(250, 249), "TagCheckStr", 250, 249, 0, 0),
        (Op::Scalar(255, 250, 249, 248), "Scalar", 250, 249, 248, 255),
        (
            Op::IJmpIfUle(250, 249, i32::MIN),
            "IJmpIfUle",
            250,
            249,
            0,
            i32::MIN,
        ),
        (
            Op::IJmpIfUlt(250, 249, i32::MAX),
            "IJmpIfUlt",
            250,
            249,
            0,
            i32::MAX,
        ),
    ] {
        let ins = crate::threaded::encode(&op);
        assert_eq!(crate::threaded::CODE_NAMES[ins.op as usize], name);
        assert_eq!((ins.a, ins.b, ins.c, ins.imm), (a, b, c, imm));
    }
}

#[test]
fn native_numeric_arithmetic_matches_exact_and_float_oracles() {
    // The boxed samples include both signs and both integer kinds. Exact
    // doubles beyond 2^53 intentionally stay doubles under today's model.
    let samples: &[(i8, u64, i8, u64)] = &[
        (0, (-5i64) as u64, 0, 2),
        (0, 5, 0, (-2i64) as u64),
        (0, i64::MIN as u64, 0, u64::MAX),
        (0, 9007199254740993, 0, 2),
        (1, u64::MAX, 1, 3),
        (-1, (-7.5f64).to_bits(), -1, 2.0f64.to_bits()),
        (-1, 1.0f64.to_bits(), -1, 0.0f64.to_bits()),
        (-1, (-0.0f64).to_bits(), -1, (-3.0f64).to_bits()),
        (-1, f64::INFINITY.to_bits(), -1, f64::INFINITY.to_bits()),
        (-1, f64::NAN.to_bits(), -1, 3.0f64.to_bits()),
        (0, 9007199254740993, -1, 3.0f64.to_bits()),
        (0, (-9007199254740993i64) as u64, -1, 2.0f64.to_bits()),
        (0, i64::MIN as u64 + 1, -1, (-1.0f64).to_bits()),
        (1, u64::MAX, -1, 3.0f64.to_bits()),
        (1, u64::MAX, 0, (-9007199254740993i64) as u64),
        (0, 9007199254740993, -1, (-3.0f64).to_bits()),
        (0, 9007199254740993, -1, 0.5f64.to_bits()),
        (0, 9007199254740993, -1, 0.0f64.to_bits()),
        (0, 9007199254740993, -1, 18446744073709551616.0f64.to_bits()),
    ];
    for operation in 0..7 {
        for &(xkind, xbits, ykind, ybits) in samples {
            let op = match operation {
                0 => Op::Div(0, 1, 2),
                1 => Op::Pow(0, 1, 2),
                2 => Op::IDiv(0, 1, 2),
                3 => Op::Add(0, 1, 2),
                4 => Op::Sub(0, 1, 2),
                5 => Op::Mul(0, 1, 2),
                _ => Op::Mod(0, 1, 2),
            };
            let name = ["div", "pow", "idiv", "add", "sub", "mul", "mod"][operation];
            let (mut vm, tid) = fixture(op);
            let x = number(&mut vm, xkind, xbits);
            let y = number(&mut vm, ykind, ybits);
            put(&mut vm, tid, 1, x);
            put(&mut vm, tid, 2, y);
            let expected = vm.guarded(|it| numeric::binary(it, x, y, name, None));
            let error = vm.pending_error.take().map(|e| vm.bytes_of(e).to_vec());
            let expected = description(expected);
            let ctx = direct(&mut vm, tid, 1);
            if let Some(error) = error {
                assert_eq!(
                    ctx.status, ST_ERROR,
                    "{name} {xkind}:{xbits} {ykind}:{ybits}"
                );
                let actual = vm.pending_error.take().unwrap();
                assert_eq!(vm.bytes_of(actual), error);
            } else {
                assert_ne!(
                    ctx.status, ST_ERROR,
                    "{name} {xkind}:{xbits} {ykind}:{ybits}"
                );
                assert_eq!(
                    description(value(&vm, tid, 0)),
                    expected,
                    "{name} {xkind}:{xbits} {ykind}:{ybits}"
                );
            }
        }
    }
}

#[test]
fn native_numeric_boxing_and_unboxing_keep_full_integer_width() {
    for unsigned in [false, true] {
        for bits in [
            0,
            1,
            9007199254740992,
            9007199254740993,
            i64::MAX as u64,
            i64::MIN as u64,
            u64::MAX,
        ] {
            let (mut vm, tid) = fixture(if unsigned {
                Op::UBox(0, 0)
            } else {
                Op::IBox(0, 0)
            });
            intput(&mut vm, tid, 0, bits);
            vm.heap.stress = true;
            vm.heap.stress_steps = true;
            vm.heap.oracle = true;
            vm.heap.quarantine = true;
            assert_ne!(direct(&mut vm, tid, 1).status, ST_ERROR);
            let actual = value(&vm, tid, 0);
            assert_eq!(numeric::bits(&vm, actual, unsigned), bits);
            let expected = vm.box_integer(Integer { bits, unsigned });
            assert_eq!(description(actual), description(expected));
            let (mut vm, tid) = fixture(if unsigned {
                Op::UUnbox(0, 1)
            } else {
                Op::IUnbox(0, 1)
            });
            let input = vm.box_integer(Integer { bits, unsigned });
            put(&mut vm, tid, 1, input);
            assert_ne!(direct(&mut vm, tid, 1).status, ST_ERROR);
            assert_eq!(intget(&vm, tid, 0), bits);
        }
        for input in [
            Value::NIL,
            Value::num(0.5),
            Value::num(f64::NAN),
            Value::num(f64::INFINITY),
            Value::num(18446744073709551616.0),
        ] {
            let (mut vm, tid) = fixture(if unsigned {
                Op::UUnbox(0, 1)
            } else {
                Op::IUnbox(0, 1)
            });
            let expected = vm.guarded(|it| {
                numeric::bits(it, input, unsigned);
                Value::NIL
            });
            assert_eq!(expected, Value::ERROR);
            let error = vm.pending_error.take().unwrap();
            let error = vm.bytes_of(error).to_vec();
            put(&mut vm, tid, 1, input);
            assert_eq!(direct(&mut vm, tid, 1).status, ST_ERROR);
            let actual = vm.pending_error.take().unwrap();
            assert_eq!(vm.bytes_of(actual), error);
        }
    }
}

#[test]
fn native_numeric_scalar_kinds_match_saturating_conversion_oracle() {
    for kind in (0..25).chain([255]) {
        for (a, b) in [
            (4294967295.0, 33.0),
            (-2147483648.0, -1.0),
            (2147483647.0, 2.0),
            (1.5, 0.0),
            (f64::NAN, f64::INFINITY),
            (f64::INFINITY, f64::NEG_INFINITY),
            (18446744073709551616.0, -65.0),
        ] {
            let (mut vm, tid) = fixture(Op::Scalar(kind, 0, 1, 2));
            put(&mut vm, tid, 1, Value::num(a));
            put(&mut vm, tid, 2, Value::num(b));
            assert_ne!(direct(&mut vm, tid, 1).status, ST_ERROR);
            assert_eq!(
                value(&vm, tid, 0),
                if kind < 25 {
                    Value::inline_integer(crate::builtins::scalar_op(kind, a, b) as i64).unwrap()
                } else {
                    Value::num(f64::NAN)
                },
                "kind={kind} a={a} b={b}"
            );
        }
    }
    let (mut vm, tid) = fixture(Op::Scalar(1, 0, 1, 2));
    put(&mut vm, tid, 1, Value::TRUE);
    put(&mut vm, tid, 2, Value::num(1.0));
    assert_eq!(direct(&mut vm, tid, 1).status, ST_ERROR);
    let error = vm.pending_error.take().unwrap();
    assert_eq!(
        vm.bytes_of(error),
        b"runtime error: scalar intrinsic on a non-number"
    );
}

#[test]
fn native_numeric_integer_tags_preserve_kind_and_reject_fractions() {
    for unsigned in [false, true] {
        for (kind, bits) in [
            (-1, (-0.0f64).to_bits()),
            (-1, 0.5f64.to_bits()),
            (-1, f64::NAN.to_bits()),
            (-1, 9223372036854775808.0f64.to_bits()),
            (0, 9007199254740993),
            (1, u64::MAX),
        ] {
            let (mut vm, tid) = fixture(Op::TagCheckInt(0, 1, unsigned));
            let input = number(&mut vm, kind, bits);
            let valid = numeric::is_kind(input, unsigned);
            put(&mut vm, tid, 1, input);
            assert_eq!(direct(&mut vm, tid, 1).status == ST_ERROR, !valid);
            if valid {
                assert_eq!(value(&vm, tid, 0), input);
            } else {
                let error = vm.pending_error.take().unwrap();
                assert_eq!(vm.bytes_of(error), b"runtime error: integer kind mismatch");
            }
        }
    }
}

#[test]
fn native_numeric_arithmetic_coerces_strings_and_preserves_callback_results() {
    for operation in 0..3 {
        let op = match operation {
            0 => Op::Div(0, 1, 2),
            1 => Op::Pow(0, 1, 2),
            _ => Op::IDiv(0, 1, 2),
        };
        let (mut vm, tid) = fixture(op);
        let x = vm.intern(" -7.5 ");
        put(&mut vm, tid, 1, x);
        put(&mut vm, tid, 2, Value::num(2.0));
        let expected = numeric::binary(
            &mut vm,
            x,
            Value::num(2.0),
            ["div", "pow", "idiv"][operation],
            None,
        );
        assert_ne!(direct(&mut vm, tid, 1).status, ST_ERROR);
        assert_eq!(value(&vm, tid, 0), expected);
        let (mut vm, tid) = fixture(op);
        let x = vm.new_table();
        vm.register(x);
        let meta = vm.new_table();
        vm.register(meta);
        // This allocating callback returns managed identity, not a number.
        crate::image::load(
            &mut vm,
            "function callback 1 2 8 0 vv:v\nNewTable 0\nRet 0\nend\n",
        )
        .unwrap();
        vm.entries.resize(2, 0);
        vm.prepare_threaded();
        vm.funcs[0].ins[1].op = Code::Slow as u8;
        let key = vm.intern(["__div", "__pow", "__idiv"][operation]);
        vm.set_index(meta, key, Value::func(1));
        vm.set_metatable(x, meta);
        put(&mut vm, tid, 1, x);
        put(&mut vm, tid, 2, Value::num(2.0));
        vm.heap.stress = true;
        vm.heap.stress_steps = true;
        vm.heap.oracle = true;
        vm.heap.quarantine = true;
        assert_ne!(direct(&mut vm, tid, 1).status, ST_ERROR);
        let actual = value(&vm, tid, 0);
        assert_eq!(
            unsafe { actual.as_obj().unwrap().as_ref().kind },
            crate::heap::KIND_TABLE
        );
    }
}

#[test]
fn native_numeric_unsigned_branch_comparisons_keep_the_sign_bit() {
    for le in [false, true] {
        for (a, b) in [
            (0, 0),
            (u64::MAX, 0),
            (0, u64::MAX),
            (1, 2),
            (u64::MAX, u64::MAX),
            (i64::MIN as u64, i64::MAX as u64),
        ] {
            let (mut vm, tid) = fixture(if le {
                Op::IJmpIfUle(0, 1, 1)
            } else {
                Op::IJmpIfUlt(0, 1, 1)
            });
            intput(&mut vm, tid, 0, a);
            intput(&mut vm, tid, 1, b);
            let taken = if le { a <= b } else { a < b };
            assert_ne!(
                direct(&mut vm, tid, if taken { 2 } else { 1 }).status,
                ST_ERROR
            );
        }
    }
}

#[test]
fn native_numeric_string_tag_accepts_identity_and_slice_only() {
    for kind in 0..5 {
        let (mut vm, tid) = fixture(Op::TagCheckStr(0, 1));
        let text = vm.intern("numeric-string");
        let input = match kind {
            0 => text,
            1 => vm.new_slice(text, 1, 3),
            2 => vm.heap_new_bytes(4),
            3 => Value::NIL,
            _ => Value::num(f64::NAN),
        };
        put(&mut vm, tid, 1, input);
        let ctx = direct(&mut vm, tid, 1);
        if kind < 2 {
            assert_ne!(ctx.status, ST_ERROR);
            assert_eq!(value(&vm, tid, 0), input);
        } else {
            assert_eq!(ctx.status, ST_ERROR);
            let error = vm.pending_error.take().unwrap();
            assert_eq!(vm.bytes_of(error), b"runtime error: value is not a string");
        }
    }
}

#[test]
fn native_numeric_unsigned_back_edges_charge_only_when_taken() {
    for le in [false, true] {
        for limit in [0, 1, 4] {
            for taken in [false, true] {
                let mut expected = None;
                for threaded in [false, true] {
                    let mut vm = Box::new(Interp::new());
                    crate::image::load(
                        &mut vm,
                        "function budget 0 0 4 2 :v\nRetNil\nend\nentry 0\n",
                    )
                    .unwrap();
                    let (a, b) = if taken { (0, 1) } else { (2, 1) };
                    vm.funcs[0].code = vec![
                        Op::IK(0, a),
                        Op::IK(1, b),
                        if le {
                            Op::IJmpIfUle(0, 1, -1)
                        } else {
                            Op::IJmpIfUlt(0, 1, -1)
                        },
                        Op::RetNil,
                    ];
                    vm.entries.resize(1, 0);
                    vm.prepare_threaded();
                    vm.threaded = threaded;
                    vm.execution_limit = Some(limit);
                    let tid = vm.spawn(0, &[]);
                    let result = vm.guarded(|it| match it.run(tid) {
                        crate::interp::Outcome::Done(value) => value,
                        crate::interp::Outcome::Parked(_) => panic!("unexpected park"),
                    });
                    let error = vm.pending_error.take().map(|v| vm.bytes_of(v).to_vec());
                    let actual = (result.0, error, vm.execution_limit);
                    if let Some(expected) = &expected {
                        assert_eq!(&actual, expected, "le={le} limit={limit} taken={taken}");
                    } else {
                        expected = Some(actual);
                    }
                }
            }
        }
    }
    // A finite nonzero budget is consumed inside the native loop before
    // its exhausted edge alone returns to the existing scheduler boundary.
    let (mut vm, tid) = fixture(Op::IJmpIfUlt(0, 1, -1));
    intput(&mut vm, tid, 0, 0);
    intput(&mut vm, tid, 1, u64::MAX);
    vm.execution_limit = Some(3);
    let mut ctx = direct(&mut vm, tid, 0);
    assert_eq!(ctx.budget, 0);
    assert_eq!(ctx.budget_mark, 0);
    assert_eq!(ctx.status, ST_ERROR);
    crate::threaded::charge(&mut ctx, &mut vm);
    assert_eq!(vm.execution_limit, Some(0));
}

#[test]
fn native_numeric_arithmetic_errors_and_metamethod_precedence_match_reference() {
    for operation in 0..3 {
        let op = match operation {
            0 => Op::Div(0, 1, 2),
            1 => Op::Pow(0, 1, 2),
            _ => Op::IDiv(0, 1, 2),
        };
        for bad in [Value::NIL, Value::TRUE] {
            let (mut vm, tid) = fixture(op);
            put(&mut vm, tid, 1, bad);
            put(&mut vm, tid, 2, Value::num(2.0));
            vm.guarded(|it| {
                numeric::binary(
                    it,
                    bad,
                    Value::num(2.0),
                    ["div", "pow", "idiv"][operation],
                    None,
                )
            });
            let expected = vm.pending_error.take().unwrap();
            let expected = vm.bytes_of(expected).to_vec();
            assert_eq!(direct(&mut vm, tid, 1).status, ST_ERROR);
            let actual = vm.pending_error.take().unwrap();
            assert_eq!(vm.bytes_of(actual), expected);
        }
        for left_handler in [false, true] {
            let (mut vm, tid) = fixture(op);
            crate::image::load(&mut vm,"function left 0 2 4 1 vv:v\nIK 0 17\nIBox 0 0\nRet 0\nend\nfunction right 1 2 4 1 vv:v\nIK 0 23\nIBox 0 0\nRet 0\nend\n").unwrap();
            vm.entries.resize(3, 0);
            vm.prepare_threaded();
            vm.funcs[0].ins[1].op = Code::Slow as u8;
            let x = vm.new_table();
            vm.register(x);
            let y = vm.new_table();
            vm.register(y);
            let key = vm.intern(["__div", "__pow", "__idiv"][operation]);
            let right = vm.new_table();
            vm.register(right);
            vm.set_index(right, key, Value::func(2));
            vm.set_metatable(y, right);
            if left_handler {
                let left = vm.new_table();
                vm.register(left);
                vm.set_index(left, key, Value::func(1));
                vm.set_metatable(x, left);
            }
            put(&mut vm, tid, 1, x);
            put(&mut vm, tid, 2, y);
            assert_ne!(direct(&mut vm, tid, 1).status, ST_ERROR);
            assert_eq!(
                value(&vm, tid, 0),
                Value::inline_integer(if left_handler { 17 } else { 23 }).unwrap()
            );
        }
    }
}

#[test]
fn native_numeric_unbox_and_number_tag_never_escape_for_boxed_values_or_errors() {
    for (kind, bits) in [
        (-1, (-0.0f64).to_bits()),
        (-1, f64::NAN.to_bits()),
        (0, 9007199254740993),
        (1, u64::MAX),
    ] {
        let (mut vm, tid) = fixture(Op::FUnbox(0, 1));
        let input = number(&mut vm, kind, bits);
        let expected = numeric::double(&vm, input);
        put(&mut vm, tid, 1, input);
        assert_ne!(direct(&mut vm, tid, 1).status, ST_ERROR);
        let at = vm.tasks[tid].cur() + vm.funcs[0].off_f();
        assert_eq!(vm.tasks[tid].stack[at], expected.to_bits());
        let (mut vm, tid) = fixture(Op::TagCheckNum(0, 1));
        let input = number(&mut vm, kind, bits);
        put(&mut vm, tid, 1, input);
        assert_eq!(
            direct(&mut vm, tid, 1).status == ST_ERROR,
            !numeric::is_numeric(input)
        );
        if numeric::is_numeric(input) {
            assert_eq!(value(&vm, tid, 0), input);
        } else {
            let error = vm.pending_error.take().unwrap();
            assert_eq!(vm.bytes_of(error), b"runtime error: value is not a number");
        }
    }
    for op in [Op::FUnbox(0, 1), Op::TagCheckNum(0, 1)] {
        let (mut vm, tid) = fixture(op);
        put(&mut vm, tid, 1, Value::TRUE);
        assert_eq!(direct(&mut vm, tid, 1).status, ST_ERROR);
        let error = vm.pending_error.take().unwrap();
        assert_eq!(
            vm.bytes_of(error),
            if matches!(op, Op::FUnbox(..)) {
                b"runtime error: expected a number".as_slice()
            } else {
                b"runtime error: value is not a number".as_slice()
            }
        );
    }
}

#[test]
fn native_numeric_string_byte_negative_indices_match_exact_oracle() {
    for slice in [false, true] {
        for index in [i64::MIN, -5, -4, -3, -1, 0, 1, 3, 4, 5, i64::MAX] {
            let (mut vm, tid) = fixture(Op::StrByte(0, 1, 0));
            let text = vm.intern("ABCD");
            let input = if slice {
                vm.new_slice(text, 1, 3)
            } else {
                text
            };
            put(&mut vm, tid, 1, input);
            intput(&mut vm, tid, 0, index as u64);
            let expected = vm.str_byte(input, index);
            assert_ne!(direct(&mut vm, tid, 1).status, ST_ERROR);
            assert_eq!(value(&vm, tid, 0), expected, "slice={slice} index={index}");
        }
    }
    for object in [false, true] {
        let (mut vm, tid) = fixture(Op::StrByte(0, 1, 0));
        let input = if object { vm.new_table() } else { Value::NIL };
        put(&mut vm, tid, 1, input);
        assert_eq!(direct(&mut vm, tid, 1).status, ST_ERROR);
        let error = vm.pending_error.take().unwrap();
        assert_eq!(vm.bytes_of(error), b"runtime error: byte of a non-string");
    }
}

pub(super) fn arithmetic_alias_contract() {
    for dest in [0u8, 1, 255] {
        for operation in 0..7 {
            for (a, b) in [
                (Value::num(-0.0), Value::num(2.0)),
                (Value::num(f64::NAN), Value::num(f64::INFINITY)),
                (
                    Value::inline_integer(-5).unwrap(),
                    Value::inline_integer(2).unwrap(),
                ),
                (Value::TRUE, Value::NIL),
            ] {
                let op = match operation {
                    0 => Op::Add(dest, 1, 2),
                    1 => Op::Sub(dest, 1, 2),
                    2 => Op::Mul(dest, 1, 2),
                    3 => Op::Div(dest, 1, 2),
                    4 => Op::IDiv(dest, 1, 2),
                    5 => Op::Mod(dest, 1, 2),
                    _ => Op::Pow(dest, 1, 2),
                };
                let (mut vm, tid) = super::native_object_tests::large_fixture(op);
                put(&mut vm, tid, 1, a);
                put(&mut vm, tid, 2, b);
                let expected = vm.guarded(|it| {
                    numeric::binary(
                        it,
                        a,
                        b,
                        ["add", "sub", "mul", "div", "idiv", "mod", "pow"][operation],
                        None,
                    )
                });
                let expected = description(expected);
                let error = vm.pending_error.take().map(|v| vm.bytes_of(v).to_vec());
                let ctx = direct(&mut vm, tid, 1);
                assert_eq!(ctx.status == ST_ERROR, error.is_some());
                if let Some(error) = error {
                    let e = vm.pending_error.take().unwrap();
                    assert_eq!(vm.bytes_of(e), error);
                } else {
                    assert_eq!(
                        description(value(&vm, tid, dest as usize)),
                        expected,
                        "op={operation} dest={dest}"
                    );
                }
            }
        }
    }
}

#[test]
fn native_numeric_mixed_comparisons_preserve_integer_precision() {
    for equal in [false, true] {
        for (xkind, xbits, ykind, ybits) in [
            (0, i64::MAX as u64, -1, 9223372036854775808.0f64.to_bits()),
            (1, u64::MAX, -1, 18446744073709551616.0f64.to_bits()),
            (1, u64::MAX, 0, (-1i64) as u64),
            (0, (-5i64) as u64, -1, (-5.5f64).to_bits()),
            (-1, (-5.5f64).to_bits(), 0, (-5i64) as u64),
            (0, 0, -1, (-0.0f64).to_bits()),
            (0, 1, -1, f64::NAN.to_bits()),
            (
                0,
                i64::MIN as u64,
                -1,
                (-9223372036854775808.0f64).to_bits(),
            ),
            (0, 9007199254740993, -1, 9007199254740992.0f64.to_bits()),
        ] {
            let (mut vm, tid) = fixture(if equal {
                Op::Le(0, 1, 2)
            } else {
                Op::Lt(0, 1, 2)
            });
            let x = number(&mut vm, xkind, xbits);
            let y = number(&mut vm, ykind, ybits);
            put(&mut vm, tid, 1, x);
            put(&mut vm, tid, 2, y);
            let order = numeric::compare(x, y);
            let expected = Value::boolean(
                order == Some(std::cmp::Ordering::Less)
                    || (equal && order == Some(std::cmp::Ordering::Equal)),
            );
            assert_ne!(direct(&mut vm, tid, 1).status, ST_ERROR);
            assert_eq!(
                value(&vm, tid, 0),
                expected,
                "le={equal} x={xkind}:{xbits} y={ykind}:{ybits}"
            );
        }
    }
}

#[test]
fn native_numeric_negation_and_order_callbacks_preserve_managed_results() {
    for bits in [
        i64::MIN as u64,
        (-5i64) as u64,
        0,
        9007199254740993,
        u64::MAX,
    ] {
        let (mut vm, tid) = fixture(Op::Neg(0, 1));
        let input = vm.box_integer(Integer {
            bits,
            unsigned: false,
        });
        put(&mut vm, tid, 1, input);
        let expected = vm.guarded(|it| numeric::negate(it, input));
        let expected = description(expected);
        assert_ne!(direct(&mut vm, tid, 1).status, ST_ERROR);
        assert_eq!(description(value(&vm, tid, 0)), expected);
    }
    for or_equal in [false, true] {
        let (mut vm, tid) = fixture(if or_equal {
            Op::Le(0, 1, 2)
        } else {
            Op::Lt(0, 1, 2)
        });
        crate::image::load(
            &mut vm,
            "function truthy 0 2 8 2 vv:v\nNewTable 0\nRet 0\nend\n",
        )
        .unwrap();
        vm.entries.resize(2, 0);
        vm.prepare_threaded();
        vm.funcs[0].ins[1].op = Code::Slow as u8;
        let left = vm.new_table();
        put(&mut vm, tid, 1, left);
        let right = vm.new_table();
        put(&mut vm, tid, 2, right);
        let meta = vm.new_table();
        vm.register(meta);
        let key = vm.intern("__lt");
        vm.set_index(meta, key, Value::func(1));
        vm.set_metatable(left, meta);
        vm.set_metatable(right, meta);
        vm.heap.stress = true;
        vm.heap.stress_steps = true;
        vm.heap.oracle = true;
        vm.heap.quarantine = true;
        assert_ne!(direct(&mut vm, tid, 1).status, ST_ERROR);
        assert_eq!(value(&vm, tid, 0), Value::boolean(!or_equal));
    }
}

#[test]
fn native_numeric_equality_uses_exact_subtypes_and_unordered_nan() {
    for negate in [false, true] {
        for (xkind, xbits, ykind, ybits) in [
            (0, 1, -1, 1.0f64.to_bits()),
            (0, 0, -1, (-0.0f64).to_bits()),
            (0, 9007199254740993, -1, 9007199254740992.0f64.to_bits()),
            (0, i64::MAX as u64, 1, i64::MAX as u64),
            (0, (-1i64) as u64, 1, u64::MAX),
            (0, 1, -1, f64::NAN.to_bits()),
        ] {
            let (mut vm, tid) = fixture(if negate {
                Op::Ne(0, 1, 2)
            } else {
                Op::Eq(0, 1, 2)
            });
            let x = number(&mut vm, xkind, xbits);
            let y = number(&mut vm, ykind, ybits);
            put(&mut vm, tid, 1, x);
            put(&mut vm, tid, 2, y);
            let equal = numeric::compare(x, y) == Some(std::cmp::Ordering::Equal);
            assert_ne!(direct(&mut vm, tid, 1).status, ST_ERROR);
            assert_eq!(value(&vm, tid, 0), Value::boolean(equal != negate));
        }
    }
}

#[test]
fn native_numeric_scalar_preserves_exact_integer_low_words() {
    for kind in 0..25 {
        let (mut vm, tid) = fixture(Op::Scalar(kind, 0, 1, 2));
        let left = vm.box_integer(Integer { bits: 9007199254740993, unsigned: false });
        vm.register(left);
        let right = vm.box_integer(Integer { bits: u64::MAX - 1, unsigned: true });
        vm.register(right);
        put(&mut vm, tid, 1, left);
        put(&mut vm, tid, 2, right);
        let expected = crate::builtins::scalar_value(kind, left, right);
        assert_ne!(direct(&mut vm, tid, 1).status, ST_ERROR);
        assert_eq!(value(&vm, tid, 0), expected, "scalar kind {kind}");
    }
}


#[test]
fn native_numeric_string_coercions_keep_exact_integer_roots_and_subtypes() {
    for op in [Op::Add(0, 1, 2), Op::Neg(0, 1)] {
        let (mut vm, tid) = fixture(op);
        let left = vm.intern("9007199254740993");
        vm.register(left);
        put(&mut vm, tid, 1, left);
        let right = vm.intern("9223372036854775807");
        vm.register(right);
        put(&mut vm, tid, 2, right);
        vm.heap.stress = true;
        vm.heap.stress_steps = true;
        vm.heap.oracle = true;
        vm.heap.quarantine = true;
        assert_ne!(direct(&mut vm, tid, 1).status, ST_ERROR);
        let expected = if matches!(op, Op::Neg(..)) { 9007199254740993u64.wrapping_neg() }
                       else { 9007199254740993u64.wrapping_add(i64::MAX as u64) };
        assert_eq!(numeric::integer(value(&vm, tid, 0)).unwrap().bits, expected);
        vm.full_cycle();
        vm.check_oracle();
    }
}
