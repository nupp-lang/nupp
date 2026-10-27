use super::*;
use crate::interp::{Interp, Op};

fn fixture(threaded: bool) -> Box<Interp> {
    let mut vm = Box::new(Interp::new());
    crate::image::load(
        &mut vm,
        r#"
shape 0 Sample value:any
function literal 0 2 8 1 vv:v
const 0 str "module.test"
Require 1 0
Move 3 2
Ret 1
end
function loader 1 0 8 1 :v
const 0 str "answer"
const 1 num 42
NewTable 1
K 2 1
SetField 1 0 2
Ret 1
end
function dynamic 2 2 8 1 vv:v
RequireV 1 1
Move 3 2
Ret 1
end
function failing 3 0 8 1 :v
const 0 str "loader failed"
Raise 0
RetNil
end
function register 4 1 8 1 v:v
const 0 str "method"
SetMethod 0 0 1
Ret 1
end
function typedcaller 5 2 8 4 vv:v
RequireV 1 1
Ret 1
end
function parkedloader 6 1 8 1 v:v
Park 1
Ret 1
end
entry 0
module module.parked 6
module module.test 1
module module.fail 3
module module.cycle 2
"#,
    )
    .unwrap();
    vm.install_globals();
    vm.entries.resize(vm.funcs.len(), 0);
    vm.prepare_threaded();
    vm.threaded = threaded;
    vm
}

// Stop after exactly one Nupp handler, with real frame and live-root metadata.
// An explicit Slow instruction is a boundary, not a promise that some guest
// opcode will remain unported. Loader callbacks can still execute guest code.
fn invoke(vm: &mut Box<Interp>, fid: u32, op: Op, args: &[Value]) -> (usize, Ctx, u64) {
    let tid = vm.spawn(fid, args);
    invoke_task(vm, tid, op)
}

pub(super) fn invoke_task(vm: &mut Box<Interp>, tid: usize, op: Op) -> (usize, Ctx, u64) {
    let current = vm.tasks[tid].cur();
    let fid = vm.tasks[tid].stack[current] as u32;
    let code = [encode(&op), Ins::default()];
    assert_ne!(code[0].op, Code::Slow as u8);
    let original = vm.finfo[fid as usize].code;
    vm.finfo[fid as usize].code = code.as_ptr();
    let mut ctx: Ctx = unsafe { std::mem::zeroed() };
    ctx.interp = (&mut **vm as *mut Interp).cast();
    ctx.tid = tid as u64;
    ctx.marking = &vm.heap.marking;
    crate::threaded::sync(&mut ctx, vm);
    let frame = unsafe { ctx.stack.add(ctx.cur as usize) };
    let next = unsafe {
        nupp_native_runtime_entry(
            code.as_ptr(),
            frame.add(HDR),
            frame.add(vm.funcs[fid as usize].off_i()).cast(),
            frame.add(vm.funcs[fid as usize].off_f()).cast(),
            &mut ctx,
            frame,
        )
    };
    if ctx.status == 0 {
        assert_eq!(next, unsafe { code.as_ptr().add(1) } as u64);
    } else {
        assert_eq!(next, EXIT_ERROR);
    }
    vm.finfo[fid as usize].code = original;
    let value = unsafe { *ctx.stack.add(ctx.cur as usize + HDR + 1) };
    (tid, ctx, value)
}

#[test]
fn native_module_encodings_preserve_all_operand_bits() {
    let literal = encode(&Op::Require(255, u16::MAX));
    assert_eq!(
        (literal.op, literal.a, literal.imm),
        (Code::Require as u8, 255, u16::MAX as i32)
    );
    let dynamic = encode(&Op::RequireV(255, 254));
    assert_eq!(
        (dynamic.op, dynamic.a, dynamic.b),
        (Code::RequireV as u8, 255, 254)
    );
    let method = encode(&Op::SetMethod(u32::MAX, u16::MAX, 255));
    assert_eq!(
        (method.op, method.a, method.imm as u32, method.k),
        (Code::SetMethod as u8, 255, u32::MAX, u16::MAX as i64)
    );
}

#[test]
fn native_require_loads_once_preserves_aliases_and_publishes_roots() {
    for dynamic in [false, true] {
        let mut vm = fixture(true);
        let name = vm.new_string_bytes(b"module.test");
        vm.registered.push(name);
        let survivor = vm.new_table();
        vm.heap.stress = true;
        vm.heap.stress_steps = true;
        vm.heap.oracle = true;
        vm.heap.quarantine = true;
        let (fid, op) = if dynamic {
            (2, Op::RequireV(1, 1))
        } else {
            (0, Op::Require(1, 0))
        };
        let (tid, ctx, bits) = invoke(&mut vm, fid, op.clone(), &[name, survivor]);
        assert_eq!(ctx.status, 0);
        let module = Value(bits);
        assert_eq!(vm.kind_of(module), Some(crate::heap::KIND_TABLE));
        let answer = vm.intern("answer");
        assert_eq!(vm.get_index(module, answer), Value::num(42.0));
        assert_eq!(vm.tasks[tid].stack[HDR + 2], survivor.0);
        assert_eq!(vm.kind_of(survivor), Some(crate::heap::KIND_TABLE));
        let (_, repeated, again) = invoke(&mut vm, fid, op, &[name, survivor]);
        assert_eq!(repeated.status, 0);
        assert_eq!(again, module.0, "module initialization ran twice");
        vm.full_cycle();
        vm.check_oracle();
        assert_eq!(vm.kind_of(survivor), Some(crate::heap::KIND_TABLE));
        assert!(vm.pending_error.is_none());
    }
}

#[test]
fn native_require_errors_and_lossy_names_match_the_module_service() {
    for name in [
        b"absent".as_slice(),
        b"module.fail".as_slice(),
        b"module.cycle".as_slice(),
        b"\xff".as_slice(),
    ] {
        let mut reference = fixture(false);
        let mut native = fixture(true);
        if name == b"\xff" {
            reference.modules.insert("\u{fffd}".into(), 1);
            native.modules.insert("\u{fffd}".into(), 1);
        }
        let text = String::from_utf8_lossy(name);
        let expected = reference.guarded(|it| it.require(&text));
        let value = native.new_string_bytes(name);
        let (_, ctx, result) = invoke(&mut native, 2, Op::RequireV(1, 1), &[value, Value::NIL]);
        if expected == Value::ERROR {
            assert_eq!(ctx.status, ST_ERROR);
            assert_eq!(
                native.bytes_of(native.pending_error.unwrap()),
                reference.bytes_of(reference.pending_error.unwrap())
            );
            let retry = native.guarded(|it| it.require(&text));
            assert_eq!(retry, Value::ERROR);
            assert_eq!(
                native.bytes_of(native.pending_error.unwrap()),
                reference.bytes_of(reference.pending_error.unwrap())
            );
        } else {
            assert_eq!(ctx.status, 0);
            assert_eq!(native.kind_of(Value(result)), reference.kind_of(expected));
        }
    }
    let mut vm = fixture(true);
    let (_, ctx, _) = invoke(
        &mut vm,
        2,
        Op::RequireV(1, 1),
        &[Value::num(7.0), Value::NIL],
    );
    assert_eq!(ctx.status, ST_ERROR);
    assert!(
        String::from_utf8_lossy(vm.bytes_of(vm.pending_error.unwrap()))
            .contains("bytes of a non-object")
    );
}

#[test]
fn native_method_registration_updates_shapes_and_declaration_tracking() {
    let mut vm = fixture(true);
    let method = vm.intern("method");
    for value in [Value::func(1), Value::func(3), Value::NIL] {
        vm.heap.shapes[0].mm_cache = u32::MAX;
        let before = vm.heap.proto_epoch;
        let (_, ctx, _) = invoke(&mut vm, 4, Op::SetMethod(0, 0, 1), &[value]);
        assert_eq!(ctx.status, 0);
        assert_eq!(vm.heap.shapes[0].methods.get(&method), Some(&value));
        assert_eq!(vm.heap.shapes[0].mm_cache, 0);
        assert_eq!(vm.heap.proto_epoch, before + 1);
    }
    let declaration = vm.new_table();
    let record_type = vm.intern("\0nupp:recordType");
    vm.funcs[4].consts[0] = record_type;
    for _ in 0..2 {
        let (_, ctx, _) = invoke(&mut vm, 4, Op::SetMethod(0, 0, 1), &[declaration]);
        assert_eq!(ctx.status, 0);
    }
    assert_ne!(
        unsafe { declaration.as_obj().unwrap().as_ref().flags } & crate::heap::F_DECLARATION,
        0
    );
    assert_eq!(vm.heap.declarations.get(&declaration.0).unwrap(), &[0]);
    vm.full_cycle();
    assert_eq!(vm.kind_of(declaration), Some(crate::heap::KIND_TABLE));
}

#[test]
fn native_require_recovers_typed_windows_without_reusing_loader_frames() {
    let mut vm = fixture(true);
    let name = vm.intern("module.test");
    let survivor = vm.new_table();
    let tid = vm.spawn(5, &[name, survivor]);
    let caller = vm.tasks[tid].cur();
    let off_i = vm.funcs[5].off_i();
    let off_f = vm.funcs[5].off_f();
    let integer = i64::MIN as u64;
    let floating = (-0.0f64).to_bits();
    vm.tasks[tid].stack[caller + off_i] = integer;
    vm.tasks[tid].stack[caller + off_f] = floating;
    vm.heap.stress = true;
    vm.heap.stress_steps = true;
    vm.heap.oracle = true;
    vm.heap.quarantine = true;
    let (returned_tid, ctx, result) = invoke_task(&mut vm, tid, Op::RequireV(1, 1));
    assert_eq!(returned_tid, tid);
    assert_eq!(ctx.status, 0);
    assert_eq!(ctx.cur as usize, caller);
    assert_eq!(vm.tasks.len(), tid + 1, "loader scratch task escaped");
    assert_eq!(vm.tasks[tid].stack[caller + off_i], integer);
    assert_eq!(vm.tasks[tid].stack[caller + off_f], floating);
    assert_eq!(vm.tasks[tid].stack[caller + HDR + 2], survivor.0);
    assert_eq!(vm.kind_of(Value(result)), Some(crate::heap::KIND_TABLE));
    let frame = unsafe { ctx.stack.add(caller) };
    assert_eq!(frame, unsafe {
        vm.tasks[tid].stack.as_mut_ptr().add(caller)
    });
    vm.full_cycle();
    vm.check_oracle();
    assert_eq!(vm.kind_of(survivor), Some(crate::heap::KIND_TABLE));
    assert!(vm.pending_error.is_none());
}

#[test]
fn native_require_callback_park_is_an_error_without_a_resumed_caller_edge() {
    let mut vm = fixture(true);
    let name = vm.intern("module.parked");
    let survivor = vm.new_table();
    let tid = vm.spawn(2, &[name, survivor]);
    let before = vm.tasks[tid].cur();
    let (_, ctx, _) = invoke_task(&mut vm, tid, Op::RequireV(1, 1));
    assert_eq!(ctx.status, ST_ERROR);
    assert_eq!(ctx.cur as usize, before);
    assert_eq!(vm.tasks.len(), tid + 1);
    assert_eq!(
        vm.tasks[tid].stack[before + HDR + 1],
        name.0,
        "error path stored a result"
    );
    assert_eq!(vm.tasks[tid].stack[before + HDR + 2], survivor.0);
    // enter_rust publishes the next logical task position before callbacks;
    // the current native PC remains at RequireV and the error never dispatches.
    assert_eq!(ctx.pc, 0);
    assert_eq!(vm.tasks[tid].stack[before] >> 32, 1);
    assert_eq!(
        vm.bytes_of(vm.pending_error.unwrap()),
        b"runtime error: a callback parked"
    );
    assert_eq!(vm.tasks[tid].state, crate::interp::State::Runnable);
}

#[test]
fn native_require_reloads_function_metadata_after_a_loader_extends_the_image() {
    let mut vm = fixture(true);
    let mut plugin = String::new();
    let additional = vm.finfo.capacity() + 1;
    for index in 0..additional {
        plugin.push_str(&format!(
            "function extra{index} {index} 0 2 0 :v\nRetNil\nend\n"
        ));
    }
    plugin.push_str("entry 0\n");
    let image = vm.new_string_bytes(plugin.as_bytes());
    vm.funcs[1].consts = vec![
        Value::builtin(crate::builtins::id_of("vm.loadImage").unwrap()),
        image,
    ];
    vm.funcs[1].code = vec![
        Op::K(1, 0),
        Op::K(2, 1),
        Op::CallDyn(1, 1, 1),
        Op::NewTable(1),
        Op::Ret(1),
    ];
    vm.funcs[5].code = vec![
        Op::RequireV(1, 1),
        Op::IAddK(1, 0, 1),
        Op::FNeg(1, 0),
        Op::Move(3, 2),
        Op::RetN(1, 3),
    ];
    vm.prepare_threaded();
    let old_info = vm.finfo.as_ptr();
    let old_count = vm.funcs.len();
    let name = vm.intern("module.test");
    let survivor = vm.new_table();
    let tid = vm.spawn(5, &[name, survivor]);
    let caller = vm.tasks[tid].cur();
    let off_i = vm.funcs[5].off_i();
    let off_f = vm.funcs[5].off_f();
    vm.tasks[tid].stack[caller + off_i] = i64::MIN as u64;
    vm.tasks[tid].stack[caller + off_f] = (-0.0f64).to_bits();
    vm.heap.stress = true;
    vm.heap.stress_steps = true;
    vm.heap.oracle = true;
    vm.heap.quarantine = true;
    let crate::interp::Outcome::Done(value) = vm.run(tid) else {
        panic!("module caller parked");
    };
    assert_ne!(vm.finfo.as_ptr(), old_info);
    assert_eq!(vm.funcs.len(), old_count + additional);
    assert_eq!(vm.tasks[tid].results, vec![value, survivor, survivor]);
    assert_eq!(vm.kind_of(value), Some(crate::heap::KIND_TABLE));
    assert_eq!(
        vm.tasks[tid].stack[caller + off_i + 1],
        (i64::MIN + 1) as u64
    );
    assert_eq!(vm.tasks[tid].stack[caller + off_f + 1], 0.0f64.to_bits());
    assert_eq!(vm.tasks[tid].stack[caller + HDR + 2], survivor.0);
    vm.full_cycle();
    vm.check_oracle();
    assert_eq!(vm.kind_of(survivor), Some(crate::heap::KIND_TABLE));
    assert!(vm.pending_error.is_none());
}
