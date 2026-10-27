use super::*;
use crate::{
    interp::{Interp, Op},
    simd,
    value::Value,
};

fn fixture(op: Op) -> (Box<Interp>, usize) {
    let mut vm = Box::new(Interp::new());
    crate::image::load(
        &mut vm,
        "function vector 0 0 80 12 :v\nvectors 6\nRetNil\nend\nentry 0\n",
    )
    .unwrap();
    // The next encoded slot is explicitly Slow in direct(), independent of
    // which guest opcodes the native interpreter has already acquired.
    vm.funcs[0].code = vec![op, Op::NewBytes(0, 0), Op::RetNil];
    vm.entries.resize(1, 0);
    vm.prepare_threaded();
    let tid = vm.spawn(0, &[]);
    (vm, tid)
}

fn direct(vm: &mut Interp, tid: usize) -> Ctx {
    vm.funcs[0].ins[1] = Ins::default();
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
    if ctx.status != ST_ERROR {
        assert_eq!(
            next,
            unsafe { pc.add(1) } as u64,
            "native opcode must advance without Rust step"
        );
    } else {
        assert_eq!(next, 0);
    }
    ctx
}

fn vector_set(vm: &mut Interp, tid: usize, index: usize, bytes: [u8; 16]) {
    let at = vm.tasks[tid].cur() + vm.funcs[0].off_v() + index * 2;
    vm.tasks[tid].stack[at] = u64::from_ne_bytes(bytes[..8].try_into().unwrap());
    vm.tasks[tid].stack[at + 1] = u64::from_ne_bytes(bytes[8..].try_into().unwrap());
}
fn vector_get(vm: &Interp, tid: usize, index: usize) -> [u8; 16] {
    let at = vm.tasks[tid].cur() + vm.funcs[0].off_v() + index * 2;
    let mut b = [0; 16];
    b[..8].copy_from_slice(&vm.tasks[tid].stack[at].to_ne_bytes());
    b[8..].copy_from_slice(&vm.tasks[tid].stack[at + 1].to_ne_bytes());
    b
}

#[test]
fn native_simd_lanes_match_the_scalar_oracle_with_aliasing() {
    let patterns = [
        ([0xff; 16], [1; 16], [0; 16]),
        ([0x80; 16], [0x7f; 16], [0x55; 16]),
        ([0; 16], [0; 16], [0xff; 16]),
        (
            [
                0x00, 0, 0, 0x80, 0x00, 0, 0, 0, 0x34, 0x12, 0xc0, 0x7f, 0, 0, 0x80, 0x3f,
            ],
            [0; 16],
            [
                0x00, 0, 0x80, 0x3f, 0, 0, 0x80, 0xbf, 0, 0, 0, 0, 0, 0, 0xf0, 0x3f,
            ],
        ),
        (
            [
                0, 0, 0, 0, 0, 0, 0xf0, 0x3f, 0x01, 0, 0, 0, 0, 0, 0xf8, 0x7f,
            ],
            [0, 0, 0, 0, 0, 0, 0, 0x80, 0, 0, 0, 0, 0, 0, 0xf0, 0x3f],
            [0; 16],
        ),
        (
            [0, 0, 0, 0, 0, 0, 0x0c, 0xc0, 0, 0, 0, 0, 0, 0, 0x30, 0xc0],
            [0, 0, 0, 0, 0, 0, 0x0c, 0xc0, 0, 0, 0, 0, 0, 0, 0x30, 0xc0],
            [0; 16],
        ),
    ];
    for kind in 0..10u8 {
        for (op, name) in simd::OPERATIONS.iter().enumerate() {
            // These are public packet-only instructions, not vector16.
            for (a, b, c) in patterns {
                let Ok(expected) = crate::simd_exec::vector16(name, kind, a, b, c, true) else {
                    continue;
                };
                for destination in 0..4u8 {
                    let (mut vm, tid) = fixture(Op::VOp(op as u8, kind, destination, 1, 2, 3));
                    vector_set(&mut vm, tid, 1, a);
                    vector_set(&mut vm, tid, 2, b);
                    vector_set(&mut vm, tid, 3, c);
                    let ctx = direct(&mut vm, tid);
                    assert_ne!(ctx.status, ST_ERROR);
                    assert_eq!(
                        vector_get(&vm, tid, destination as usize),
                        expected,
                        "{name}, kind {kind}, destination {destination}"
                    );
                }
            }
        }
    }
}

#[test]
fn native_simd_typed_splats_extracts_masks_and_moves_keep_lane_bits() {
    for kind in 0..10u8 {
        for raw in [
            0u64,
            1,
            u64::MAX,
            0x8000_0000_0000_0000,
            0x7ff8_1234_5678_9abc,
        ] {
            let (mut vm, tid) = fixture(Op::VSplatN(2, 1, kind));
            let off = vm.tasks[tid].cur();
            let src =
                off + if kind >= 8 {
                    vm.funcs[0].off_f()
                } else {
                    vm.funcs[0].off_i()
                } + 1;
            vm.tasks[tid].stack[src] = raw;
            direct(&mut vm, tid);
            let expected = crate::simd_exec::splat(kind, f64::from_bits(raw), raw as i64);
            assert_eq!(vector_get(&vm, tid, 2), expected, "splat {kind} {raw:x}");
            for l in 0..(16 / simd::width(kind)) as u8 {
                let (mut vm, tid) = fixture(Op::VExtractN(1, 2, kind, l));
                vector_set(&mut vm, tid, 2, expected);
                direct(&mut vm, tid);
                let (f, i) = crate::simd_exec::extract(&expected, kind, l);
                let at = vm.tasks[tid].cur()
                    + if kind >= 8 {
                        vm.funcs[0].off_f()
                    } else {
                        vm.funcs[0].off_i()
                    }
                    + 1;
                let want = if kind >= 8 { f.to_bits() } else { i as u64 };
                assert_eq!(vm.tasks[tid].stack[at], want, "extract {kind} lane {l}");
            }
        }
        for active in [0u64, 1, 3, 64, u64::MAX] {
            let lanes = (16 / simd::width(kind)) as u8;
            let (mut vm, tid) = fixture(Op::VPrefix(1, 1, kind, 2, lanes));
            let at = vm.tasks[tid].cur() + vm.funcs[0].off_i() + 1;
            vm.tasks[tid].stack[at] = active;
            direct(&mut vm, tid);
            assert_eq!(
                vector_get(&vm, tid, 1),
                crate::simd_exec::prefix(active, kind, 2, lanes)
            );
        }
    }
    for op in [Op::VMov(1, 2), Op::VAny(1, 2)] {
        let bytes = [0, 0, 0, 0, 0, 0, 0, 0x80, 0x11, 0, 0, 0, 0, 0, 0xf8, 0x7f];
        let (mut vm, tid) = fixture(op.clone());
        vector_set(&mut vm, tid, 2, bytes);
        direct(&mut vm, tid);
        if matches!(op, Op::VMov(..)) {
            assert_eq!(vector_get(&vm, tid, 1), bytes);
        } else {
            assert_eq!(
                vm.tasks[tid].stack[vm.tasks[tid].cur() + vm.funcs[0].off_i() + 1],
                1
            );
        }
    }
}

fn managed_case(name: &str, kind: u8, source: u8, seed: usize) {
    let op = simd::operation(name).unwrap();
    let source_kind = if name == "convert" { source } else { kind };
    let lanes = 8;
    let w = simd::width(source_kind);
    let mut a = [0u8; simd::CAPACITY];
    let mut b = a;
    let mut c = a;
    let integer = [
        0u64,
        1,
        u64::MAX,
        0x8000000000000000,
        0x7fffffffffffffff,
        0x8000000080000080,
        0x7f7f7f7f7f7f7f7f,
        0x0123456789abcdef,
    ];
    let floating = [
        0u64,
        0x8000000000000000,
        0x7ff8123456789abc,
        0x7ff0000000000000,
        0xfff0000000000000,
        1.0000000596046448f64.to_bits(),
        (-3.5f64).to_bits(),
        0.1f64.to_bits(),
    ];
    for i in 0..lanes {
        for (operand, packet) in [&mut a, &mut b, &mut c].into_iter().enumerate() {
            let n = (i + seed + operand * 3) % 8;
            let bits = if source_kind == 8 {
                (f64::from_bits(floating[n]) as f32).to_bits() as u64
            } else if source_kind == 9 {
                floating[n]
            } else {
                integer[n]
            };
            packet[i * w..(i + 1) * w].copy_from_slice(&bits.to_ne_bytes()[..w]);
        }
    }
    let (mut vm, tid) = fixture(Op::Simd(op, kind, source, 0, 3));
    let mask = matches!(
        name,
        "maskEq" | "maskNe" | "any" | "all" | "count" | "bits" | "first" | "select"
    );
    let shape = simd::Shape {
        kind: source_kind,
        lanes,
        mask,
        species: false,
    };
    let mut args = Vec::new();
    for bits in [&a, &b, &c] {
        let v = simd::value(&mut vm, shape, bits);
        vm.registered.push(v);
        args.push(v);
    }
    if name == "select" {
        for (i, bits) in [&b, &c].into_iter().enumerate() {
            let v = simd::value(
                &mut vm,
                simd::Shape {
                    mask: false,
                    ..shape
                },
                bits,
            );
            vm.registered.push(v);
            args[i + 1] = v;
        }
    }
    let nargs = if name == "convert" {
        let species = simd::value(
            &mut vm,
            simd::Shape {
                kind,
                lanes,
                mask: false,
                species: true,
            },
            &[],
        );
        vm.registered.push(species);
        args.insert(0, species);
        2
    } else {
        (1..=3)
            .find(|n| simd::valid_descriptor(op, kind, source, *n))
            .unwrap() as u8
    };
    vm.funcs[0].code[0] = Op::Simd(op, kind, source, 0, nargs);
    vm.funcs[0].ins.clear();
    vm.prepare_threaded();
    let base = vm.tasks[tid].cur() + 4;
    for (i, v) in args.iter().take(nargs as usize).enumerate() {
        vm.tasks[tid].stack[base + 1 + i] = v.0;
    }
    vm.heap.stress_steps = true;
    vm.heap.oracle = true;
    vm.heap.quarantine = true;
    let mut packet = simd::Packet::default();
    simd::prepare(
        &mut vm,
        op,
        kind,
        source,
        &args[..nargs as usize],
        &mut packet,
    );
    crate::simd_exec::execute(&mut packet, op, kind, source).unwrap();
    vm.extra_n = 0;
    vm.last_nres = 1;
    let expected = simd::finish(&mut vm, &packet, &args[..nargs as usize]);
    vm.registered.push(expected);
    let expected_bytes = if vm.kind_of(expected) == Some(crate::heap::KIND_BYTES) {
        Some(vm.bytes_of(expected).to_vec())
    } else {
        None
    };
    let expected_extra = vm.extra[..vm.extra_n]
        .iter()
        .map(|v| vm.bytes_of(*v).to_vec())
        .collect::<Vec<_>>();
    let expected_count = vm.last_nres;
    vm.full_cycle();
    let ctx = direct(&mut vm, tid);
    assert_ne!(ctx.status, ST_ERROR, "{name}");
    let actual = Value(vm.tasks[tid].stack[base]);
    if let Some(bytes) = expected_bytes {
        assert_eq!(
            vm.bytes_of(actual),
            bytes,
            "{name}, kind {kind}, source {source}, seed {seed}"
        );
    } else {
        assert_eq!(
            actual, expected,
            "{name}, kind {kind}, source {source}, seed {seed}"
        );
    }
    assert_eq!(ctx.last_nres as usize, expected_count, "{name}");
    for (i, bytes) in expected_extra.iter().enumerate() {
        assert_eq!(
            vm.bytes_of(Value(vm.tasks[tid].stack[base + 1 + i])),
            bytes,
            "{name} result {}",
            i + 2
        );
    }
}

#[test]
fn native_simd_managed_packets_match_scalar_execution_and_results() {
    for kind in 0..10u8 {
        for name in [
            "add",
            "sub",
            "mul",
            "div",
            "neg",
            "and",
            "or",
            "xor",
            "not",
            "eq",
            "ne",
            "lt",
            "le",
            "gt",
            "ge",
            "select",
            "fma",
            "maskEq",
            "maskNe",
            "any",
            "all",
            "count",
            "bits",
            "first",
            "orderedSum",
            "pairwiseSum",
            "algebraicSum",
            "wrappingSum",
            "andBits",
            "orBits",
            "xorBits",
            "orderedProduct",
            "pairwiseProduct",
            "algebraicProduct",
            "wrappingProduct",
            "integerMin",
            "integerMax",
            "horizontal.propagatingMin",
            "horizontal.propagatingMax",
            "horizontal.numberMin",
            "horizontal.numberMax",
            "idiv",
            "mod",
            "shl",
            "shr",
            "sar",
            "mulHigh",
            "popcount",
            "saturatingAdd",
            "saturatingSub",
            "propagatingMin",
            "propagatingMax",
            "numberMin",
            "numberMax",
            "sqrt",
            "abs",
            "floor",
            "ceil",
            "orderedDot",
            "pairwiseDot",
            "algebraicDot",
            "horizontal.propagatingArgMin",
            "horizontal.propagatingArgMax",
            "horizontal.numberArgMin",
            "horizontal.numberArgMax",
            "orderedPrefixSum",
            "prefixXor",
            "reverse",
            "interleave",
            "deinterleave",
        ] {
            let op = simd::operation(name).unwrap();
            if !(1..=3).any(|n| simd::valid_descriptor(op, kind, kind, n)) {
                continue;
            }
            if kind < 8 && matches!(name, "sqrt" | "abs" | "floor" | "ceil") {
                continue;
            }
            for seed in 0..2 {
                managed_case(name, kind, kind, seed);
            }
        }
        for source in 0..10 {
            for seed in 0..2 {
                managed_case("convert", kind, source, seed);
            }
        }
    }
}

#[test]
fn native_simd_legacy_storage_masks_keep_bits_and_check_only_active_lanes() {
    let samples = [
        (-0.0f64).to_bits(),
        0x7ff8123456789abc,
        3.25f64.to_bits(),
        (-8.0f64).to_bits(),
    ];
    for store in [false, true] {
        for active in [-1i64, 0, 1, 2, 3] {
            for index in [-1i64, 0, 3, 4] {
                let op = if store {
                    Op::VStoreM(1, 1, 2, 0, 2)
                } else {
                    Op::VLoadM(2, 1, 1, 0, 2)
                };
                let (mut vm, tid) = fixture(op);
                let storage = vm.new_storage(4);
                vm.register(storage);
                unsafe {
                    let h = &mut *storage.as_obj().unwrap().as_ptr();
                    for (i, bits) in samples.into_iter().enumerate() {
                        h.storage().data[i] = f64::from_bits(bits);
                    }
                }
                let at = vm.tasks[tid].cur();
                let base = at + 4;
                let ints = at + vm.funcs[0].off_i();
                vm.tasks[tid].stack[base + 1] = storage.0;
                vm.tasks[tid].stack[ints + 1] = index as u64;
                vm.tasks[tid].stack[ints + 2] = active as u64;
                let bytes = [0x42; 16];
                vector_set(&mut vm, tid, 2, bytes);
                vm.full_cycle();
                let ctx = direct(&mut vm, tid);
                let failing = (0..2).any(|l| l < active && ((index + l) as u64) >= 4);
                assert_eq!(
                    ctx.status == ST_ERROR,
                    failing,
                    "store {store}, active {active}, index {index}"
                );
                if !failing && !store {
                    let mut expected = [0u8; 16];
                    for l in 0..2 {
                        if l < active {
                            expected[l as usize * 8..l as usize * 8 + 8]
                                .copy_from_slice(&samples[(index + l) as usize].to_ne_bytes());
                        }
                    }
                    assert_eq!(vector_get(&vm, tid, 2), expected);
                }
                if store {
                    let actual = unsafe {
                        (&mut *storage.as_obj().unwrap().as_ptr())
                            .storage()
                            .data
                            .iter()
                            .map(|f| f.to_bits())
                            .collect::<Vec<_>>()
                    };
                    let mut expected = samples;
                    for l in 0..2 {
                        if l < active {
                            let k = (index + l) as u64;
                            if k >= 4 {
                                break;
                            }
                            expected[k as usize] = u64::from_ne_bytes([0x42; 8]);
                        }
                    }
                    assert_eq!(
                        actual, expected,
                        "partial stores preserve scalar instruction order"
                    );
                }
            }
        }
    }
}

fn storage_call(vm: &mut Interp, name: &str, args: &[Value]) -> Value {
    let id = crate::builtins::id_of(&format!("storage.{name}")).unwrap();
    let v = vm.call_value(Value::builtin(id), args)[0];
    vm.register(v);
    v
}

#[test]
fn native_simd_spans_keep_owners_tails_and_atomic_write_bounds() {
    for kind in 0..10u8 {
        let width = simd::width(kind);
        let lanes = (16 / width) as u8;
        for active in [0u64, 1, lanes as u64, lanes as u64 + 1, u64::MAX] {
            for store in [false, true] {
                let op = if store {
                    Op::SpanStore(1, 1, 2, 2, kind, 0, lanes)
                } else {
                    Op::SpanLoad(2, 1, 1, 2, kind, 0, lanes)
                };
                let (mut vm, tid) = fixture(op);
                crate::image::load(&mut vm,"shape 0 Span pointer:any offset:num count:num method:set=0\nfunction WriteSpanImpl:set 0 0 1 1 :v\nsource nupp.mem.span\nRetNil\nend\n").unwrap();
                vm.install_globals();
                let element = vm.intern(simd::ELEMENTS[kind as usize]);
                let descriptor = storage_call(&mut vm, "scalar", &[element]);
                let view = storage_call(
                    &mut vm,
                    "allocateArray",
                    &[descriptor, Value::num((lanes + 2) as f64)],
                );
                for i in 0..lanes + 2 {
                    storage_call(
                        &mut vm,
                        "write",
                        &[view, Value::num(i as f64), Value::num(3.0)],
                    );
                }
                let span = vm.new_record(0);
                vm.register(span);
                vm.set_slot(span, 0, view);
                vm.set_slot(span, 1, Value::num(1.0));
                vm.set_slot(span, 2, Value::num(lanes as f64));
                vm.entries.resize(vm.funcs.len(), 0);
                vm.prepare_threaded();
                let at = vm.tasks[tid].cur();
                let ints = at + vm.funcs[0].off_i();
                vm.tasks[tid].stack[at + 5] = span.0;
                vm.tasks[tid].stack[ints + 1] = 0;
                vm.tasks[tid].stack[ints + 2] = active;
                vector_set(&mut vm, tid, 2, [0x11; 16]);
                vm.full_cycle();
                let ctx = direct(&mut vm, tid);
                // SpanLoad/Store only touch the low physical vector packet,
                // unlike the separate SpanBounds guard's whole active count.
                assert_ne!(ctx.status, ST_ERROR, "kind {kind}, active {active}");
                let used = active.min(lanes as u64) as usize;
                if store {
                    for i in 0..lanes + 2 {
                        let value = storage_call(&mut vm, "index", &[view, Value::num(i as f64)]);
                        if i == 0 || i as usize > used {
                            assert_eq!(crate::numeric::double(&vm, value), 3.0);
                        }
                    }
                } else {
                    let bytes = vector_get(&vm, tid, 2);
                    assert!(bytes[used * width..].iter().all(|b| *b == 0));
                }
            }
        }
    }
}

#[test]
fn native_simd_f64_vectors_and_fma_preserve_scalar_rounding_and_aliases() {
    let cases = [
        (
            [1.0000000000000002, -0.0],
            [0.9999999999999999, -2.0],
            [-1.0, 0.0],
        ),
        ([f64::INFINITY, f64::NAN], [0.0, 1.0], [1.0, -0.0]),
    ];
    for (a, b, c) in cases {
        let bytes = |v: [f64; 2]| {
            let mut out = [0u8; 16];
            out[..8].copy_from_slice(&v[0].to_ne_bytes());
            out[8..].copy_from_slice(&v[1].to_ne_bytes());
            out
        };
        for d in 0..4u8 {
            for (op, result) in [
                (Op::VAdd(d, 1, 2), [a[0] + b[0], a[1] + b[1]]),
                (Op::VMul(d, 1, 2), [a[0] * b[0], a[1] * b[1]]),
                (
                    Op::VFma(d, 1, 2, 3),
                    [a[0].mul_add(b[0], c[0]), a[1].mul_add(b[1], c[1])],
                ),
            ] {
                let (mut vm, tid) = fixture(op);
                vector_set(&mut vm, tid, 1, bytes(a));
                vector_set(&mut vm, tid, 2, bytes(b));
                vector_set(&mut vm, tid, 3, bytes(c));
                direct(&mut vm, tid);
                let actual = vector_get(&vm, tid, d as usize);
                for l in 0..2 {
                    let got = f64::from_ne_bytes(actual[l * 8..l * 8 + 8].try_into().unwrap());
                    if result[l].is_nan() {
                        assert!(got.is_nan());
                    } else {
                        assert_eq!(got.to_bits(), result[l].to_bits());
                    }
                }
            }
        }
        let (mut vm, tid) = fixture(Op::FFma(0, 1, 2, 3));
        let at = vm.tasks[tid].cur() + vm.funcs[0].off_f();
        vm.tasks[tid].stack[at + 1] = a[0].to_bits();
        vm.tasks[tid].stack[at + 2] = b[0].to_bits();
        vm.tasks[tid].stack[at + 3] = c[0].to_bits();
        direct(&mut vm, tid);
        let got = f64::from_bits(vm.tasks[tid].stack[at]);
        let want = a[0].mul_add(b[0], c[0]);
        if want.is_nan() {
            assert!(got.is_nan());
        } else {
            assert_eq!(got.to_bits(), want.to_bits());
        }
    }
    for (a, b) in [(0u64, 0), (1, 2), (u64::MAX, 1), (0, u64::MAX)] {
        let (mut vm, tid) = fixture(Op::GuardLenLe(1, 2));
        let at = vm.tasks[tid].cur() + vm.funcs[0].off_i();
        vm.tasks[tid].stack[at + 1] = a;
        vm.tasks[tid].stack[at + 2] = b;
        let ctx = direct(&mut vm, tid);
        assert_eq!(ctx.status == ST_ERROR, a > b);
    }
    let (mut vm, tid) = fixture(Op::LoopFact(1, 3, 2));
    direct(&mut vm, tid);
}

#[test]
fn native_simd_transpose_reads_all_64_fixed_arguments_and_returns_64_columns() {
    let (mut vm, tid) = fixture(Op::Simd(simd::operation("transpose").unwrap(), 0, 0, 0, 64));
    let base = vm.tasks[tid].cur() + 4;
    let shape = simd::Shape {
        kind: 0,
        lanes: 64,
        mask: false,
        species: false,
    };
    for row in 0..64usize {
        let mut bits = [0; simd::CAPACITY];
        for col in 0..64 {
            bits[col] = (row * 37 + col) as u8;
        }
        let value = simd::value(&mut vm, shape, &bits);
        vm.tasks[tid].stack[base + 1 + row] = value.0;
    }
    vm.last_nres = 77;
    vm.full_cycle();
    vm.heap.stress_steps = true;
    vm.heap.oracle = true;
    vm.heap.quarantine = true;
    let ctx = direct(&mut vm, tid);
    assert_ne!(ctx.status, ST_ERROR);
    assert_eq!(ctx.last_nres, 64);
    for col in 0..64 {
        let value = Value(vm.tasks[tid].stack[base + col]);
        let bits = &vm.bytes_of(value)[16..];
        let expected: Vec<u8> = (0..64).map(|row| (row * 37 + col) as u8).collect();
        assert_eq!(bits, expected, "column {col}");
    }
}

#[test]
fn native_simd_managed_integer_float_only_operations_preserve_refusal() {
    for kind in 0..8u8 {
        for name in ["sqrt", "abs", "floor", "ceil"] {
            let op = simd::operation(name).unwrap();
            assert!(simd::valid_descriptor(op, kind, kind, 1));
            let (mut vm, tid) = fixture(Op::Simd(op, kind, kind, 0, 1));
            let value = simd::value(
                &mut vm,
                simd::Shape {
                    kind,
                    lanes: 4,
                    mask: false,
                    species: false,
                },
                &[0; simd::CAPACITY],
            );
            let base = vm.tasks[tid].cur() + 4;
            vm.tasks[tid].stack[base + 1] = value.0;
            vm.full_cycle();
            let ctx = direct(&mut vm, tid);
            assert_eq!(ctx.status, ST_ERROR, "{name}, kind {kind}");
            assert_eq!(
                vm.bytes_of(vm.pending_error.unwrap()),
                format!(
                    "runtime error: SIMD {name} is not implemented for {}",
                    simd::ELEMENTS[kind as usize]
                )
                .as_bytes()
            );
            assert_eq!(
                vm.tasks[tid].stack[base + 1],
                value.0,
                "refusal leaves inputs unchanged"
            );
        }
    }
}

#[test]
fn native_simd_descriptor_abi_matches_the_nupp_ordinal_contract() {
    let source = include_str!("../../../../src/nupp/runtime/vm/simd.nupp");
    let hash = source
        .split("OPERATION_ABI = 0x")
        .nth(1)
        .unwrap()
        .split("ULL")
        .next()
        .unwrap();
    assert_eq!(
        u64::from_str_radix(hash, 16).unwrap(),
        simd::native_abi_hash()
    );
}

#[test]
fn native_simd_signed_narrow_division_checks_extended_remainders() {
    for kind in [1u8, 3, 5, 7] {
        let w = simd::width(kind);
        for (a, b) in [
            (-6i64, 3i64),
            (6, -3),
            (1, -1),
            (-7, 3),
            (7, -3),
            (-1, -1),
            (i64::MIN, -1),
            (17, 0),
        ] {
            for name in ["div", "idiv", "mod"] {
                let op = simd::operation(name).unwrap();
                let (mut vm, tid) = fixture(Op::Simd(op, kind, kind, 0, 2));
                let shape = simd::Shape {
                    kind,
                    lanes: 2,
                    mask: false,
                    species: false,
                };
                let mut args = Vec::new();
                for n in [a, b] {
                    let mut bits = [0; simd::CAPACITY];
                    for i in 0..2 {
                        bits[i * w..(i + 1) * w].copy_from_slice(&n.to_ne_bytes()[..w]);
                    }
                    let v = simd::value(&mut vm, shape, &bits);
                    vm.register(v);
                    args.push(v);
                }
                let base = vm.tasks[tid].cur() + 4;
                vm.tasks[tid].stack[base + 1] = args[0].0;
                vm.tasks[tid].stack[base + 2] = args[1].0;
                let mut packet = simd::Packet::default();
                simd::prepare(&mut vm, op, kind, kind, &args, &mut packet);
                crate::simd_exec::execute(&mut packet, op, kind, kind).unwrap();
                let ctx = direct(&mut vm, tid);
                assert_ne!(ctx.status, ST_ERROR);
                let got = vm.bytes_of(Value(vm.tasks[tid].stack[base]));
                assert_eq!(
                    &got[16..],
                    &packet.out[..2 * w],
                    "{name} kind{kind}: {a}/{b}"
                );
            }
        }
    }
}

#[test]
fn native_simd_legacy_storage_scalar_vectors_and_bounds_preserve_bits() {
    let samples = [
        (-0.0f64).to_bits(),
        0x7ff8123456789abc,
        3.25f64.to_bits(),
        (-8.0f64).to_bits(),
    ];
    let source = [0x7ff8000000000123u64, (-0.0f64).to_bits()];
    for (op, index) in [
        (Op::StorageLen(0, 1), 1i64),
        (Op::FLoad(0, 1, 1), 1),
        (Op::FStore(1, 1, 1), 1),
        (Op::VLoad(2, 1, 1, -1), 2),
        (Op::VStore(1, 1, 2, -1), 2),
        (Op::VSplat(2, 1), 0),
        (Op::VLane(0, 2, 0), 0),
        (Op::VLane(0, 2, 1), 0),
        (Op::FLoad(0, 1, 1), -1),
        (Op::FStore(1, 1, 1), 4),
        (Op::VLoad(2, 1, 1, 0), 3),
        (Op::VStore(1, 1, 2, 0), 3),
    ] {
        let (mut vm, tid) = fixture(op.clone());
        let storage = vm.new_storage(4);
        vm.register(storage);
        unsafe {
            let h = &mut *storage.as_obj().unwrap().as_ptr();
            for (i, bits) in samples.into_iter().enumerate() {
                h.storage().data[i] = f64::from_bits(bits);
            }
        }
        let base = vm.tasks[tid].cur();
        let ints = base + vm.funcs[0].off_i();
        let floats = base + vm.funcs[0].off_f();
        vm.tasks[tid].stack[base + 5] = storage.0;
        vm.tasks[tid].stack[ints + 1] = index as u64;
        vm.tasks[tid].stack[floats + 1] = source[0];
        let mut vec = [0; 16];
        vec[..8].copy_from_slice(&source[0].to_ne_bytes());
        vec[8..].copy_from_slice(&source[1].to_ne_bytes());
        vector_set(&mut vm, tid, 2, vec);
        let ctx = direct(&mut vm, tid);
        let failing =
            index < 0 || index >= 4 || index == 3 && matches!(op, Op::VLoad(..) | Op::VStore(..));
        assert_eq!(ctx.status == ST_ERROR, failing, "{op:?}, index {index}");
        let mut expected = samples;
        match op {
            Op::StorageLen(..) => assert_eq!(vm.tasks[tid].stack[ints], 4),
            Op::FLoad(..) if !failing => {
                assert_eq!(vm.tasks[tid].stack[floats], samples[index as usize])
            }
            Op::FStore(..) if !failing => expected[index as usize] = source[0],
            Op::VLoad(_, _, _, off) if !failing => {
                let at = (index + off as i64) as usize;
                let mut want = [0; 16];
                want[..8].copy_from_slice(&samples[at].to_ne_bytes());
                want[8..].copy_from_slice(&samples[at + 1].to_ne_bytes());
                assert_eq!(vector_get(&vm, tid, 2), want);
            }
            Op::VLoad(..) if failing => assert_eq!(
                vector_get(&vm, tid, 2),
                vec,
                "failed load must not commit a partial vector"
            ),
            Op::VStore(_, _, _, off) => {
                let at = (index + off as i64) as usize;
                if at < 4 {
                    expected[at] = source[0];
                }
                if at + 1 < 4 {
                    expected[at + 1] = source[1];
                }
            }
            Op::VSplat(..) => {
                let mut want = [0; 16];
                want[..8].copy_from_slice(&source[0].to_ne_bytes());
                want[8..].copy_from_slice(&source[0].to_ne_bytes());
                assert_eq!(vector_get(&vm, tid, 2), want);
            }
            Op::VLane(_, _, lane) => assert_eq!(vm.tasks[tid].stack[floats], source[lane as usize]),
            _ => {}
        }
        let actual = unsafe {
            (&mut *storage.as_obj().unwrap().as_ptr())
                .storage()
                .data
                .iter()
                .map(|f| f.to_bits())
                .collect::<Vec<_>>()
        };
        assert_eq!(actual, expected);
    }
}

fn native_span_fixture(
    kind: u8,
    op: Op,
    len: usize,
    writable: bool,
) -> (Box<Interp>, usize, Value, Value) {
    let (mut vm, tid) = fixture(op);
    let method = if writable { " method:set=0" } else { "" };
    crate::image::load(&mut vm,&format!("shape 0 Span pointer:any offset:num count:num{method}\nfunction WriteSpanImpl:set 0 0 1 1 :v\nsource nupp.mem.span\nRetNil\nend\n")).unwrap();
    vm.install_globals();
    let element = vm.intern(simd::ELEMENTS[kind as usize]);
    let descriptor = storage_call(&mut vm, "scalar", &[element]);
    let view = storage_call(
        &mut vm,
        "allocateArray",
        &[descriptor, Value::num((len + 2) as f64)],
    );
    let span = vm.new_record(0);
    vm.register(span);
    vm.set_slot(span, 0, view);
    vm.set_slot(span, 1, Value::num(1.0));
    vm.set_slot(span, 2, Value::num(len as f64));
    vm.entries.resize(vm.funcs.len(), 0);
    vm.prepare_threaded();
    let at = vm.tasks[tid].cur();
    vm.tasks[tid].stack[at + 5] = span.0;
    (vm, tid, span, view)
}

#[test]
fn native_simd_span_lengths_guards_and_readonly_owners_are_checked() {
    for kind in 0..10u8 {
        let (mut vm, tid, _, _) = native_span_fixture(kind, Op::SpanLen(0, 1, kind), 128, true);
        direct(&mut vm, tid);
        assert_eq!(
            vm.tasks[tid].stack[vm.tasks[tid].cur() + vm.funcs[0].off_i()],
            128
        );
        for (index, count, writable, write) in [
            (u64::MAX, 0u64, true, true),
            (u64::MAX, 1, true, false),
            (1, 128, true, true),
            (0, 65, true, false),
            (0, 64, true, true),
            (0, 0, false, true),
            (0, 1, false, false),
        ] {
            let (mut vm, tid, _, _) =
                native_span_fixture(kind, Op::SpanBounds(1, 1, 2, kind, write), 128, writable);
            let at = vm.tasks[tid].cur() + vm.funcs[0].off_i();
            vm.tasks[tid].stack[at + 1] = index;
            vm.tasks[tid].stack[at + 2] = count;
            let ctx = direct(&mut vm, tid);
            let failed = write && !writable
                || count != 0 && (count > 128 || index > 128 - count || count > 64);
            assert_eq!(
                ctx.status == ST_ERROR,
                failed,
                "kind {kind} index {index} count {count} writable {writable} write {write}"
            );
        }
        let lanes = (16 / simd::width(kind)) as u8;
        let (mut vm, tid, _, view) = native_span_fixture(
            kind,
            Op::SpanStore(1, 1, 2, 2, kind, 0, lanes),
            lanes as usize,
            true,
        );
        for i in 0..lanes as usize + 2 {
            storage_call(
                &mut vm,
                "write",
                &[view, Value::num(i as f64), Value::num(3.0)],
            );
        }
        let at = vm.tasks[tid].cur() + vm.funcs[0].off_i();
        vm.tasks[tid].stack[at + 1] = 1;
        vm.tasks[tid].stack[at + 2] = lanes as u64;
        vector_set(&mut vm, tid, 2, [0x42; 16]);
        let ctx = direct(&mut vm, tid);
        assert_eq!(ctx.status, ST_ERROR);
        for i in 0..lanes as usize + 2 {
            let v = storage_call(&mut vm, "index", &[view, Value::num(i as f64)]);
            assert_eq!(
                crate::numeric::double(&vm, v),
                3.0,
                "failed SpanStore is atomic"
            );
        }
    }
}
