use super::*;
use crate::{
    interp::{Interp, Op},
    value::Value,
};

fn fixture(vararg: bool, float_return: bool) -> (Box<Interp>, usize) {
    let mut vm = Box::new(Interp::new());
    let image = format!(
        "function caller 0 0 16 8 :v\nRetNil\nend\nfunction callee 1 4 16 8 fvfv:{}{}\nRetNil\nend\nentry 0\n",
        if float_return { "f" } else { "v" },
        if vararg { " vararg" } else { "" }
    );
    crate::image::load(&mut vm, &image).unwrap();
    vm.funcs[0].code = vec![Op::CallT(1, 3, 2, 255), Op::RetNil];
    vm.entries.resize(2, 0);
    vm.prepare_threaded();
    vm.funcs[0].ins[1].op = Code::Slow as u8;
    vm.funcs[1].ins[0].op = Code::Slow as u8;
    let tid = vm.spawn(0, &[]);
    let frame = vm.tasks[tid].cur();
    let off = vm.funcs[0].off_f();
    vm.tasks[tid].stack[frame + 4 + 4] = Value::TRUE.0;
    vm.tasks[tid].stack[frame + 4 + 5] = Value::num(17.0).0;
    vm.tasks[tid].stack[frame + off + 2] = (-0.0f64).to_bits();
    vm.tasks[tid].stack[frame + off + 3] = f64::NAN.to_bits();
    (vm, tid)
}
fn enter(vm: &mut Interp, tid: usize, capacity: Option<u64>) -> (Ctx, u64) {
    let mut ctx: Ctx = unsafe { std::mem::zeroed() };
    ctx.interp = (vm as *mut Interp).cast();
    ctx.tid = tid as u64;
    crate::threaded::sync(&mut ctx, vm);
    if let Some(cap) = capacity {
        ctx.cap = cap;
    }
    let f = &vm.funcs[0];
    let (off_i, off_f) = (f.off_i(), f.off_f());
    let pc = f.ins.as_ptr();
    assert_eq!(f.ins[0].op, Code::CallT as u8);
    let frame = unsafe { vm.tasks[tid].stack.as_mut_ptr().add(vm.tasks[tid].cur()) };
    let exit = unsafe {
        nupp_native_runtime_entry(
            pc,
            frame.add(4),
            frame.add(off_i).cast(),
            frame.add(off_f).cast(),
            &mut ctx,
            frame,
        )
    };
    (ctx, exit)
}

#[test]
fn native_calltyped_encodes_static_target_and_both_windows() {
    let ins = crate::threaded::encode(&Op::CallT(u32::MAX, 250, 249, 248));
    assert_eq!(ins.op, Code::CallT as u8);
    assert_eq!(
        (ins.a, ins.b, ins.c, ins.k),
        (250, 249, 248, u32::MAX as i64)
    );
}

#[test]
fn native_calltyped_pushes_mixed_windows_before_entering_callee() {
    for vararg in [false, true] {
        for returning in [false, true] {
            let (mut vm, tid) = fixture(vararg, returning);
            vm.execution_limit = Some(5);
            let caller = vm.tasks[tid].cur();
            let next = caller + vm.funcs[0].frame_words();
            let off = vm.funcs[1].off_f();
            let (ctx, exit) = enter(&mut vm, tid, None);
            assert_eq!(ctx.status, 0);
            assert_eq!(ctx.cur, next as u64);
            assert_eq!(
                exit,
                vm.funcs[1].ins.as_ptr() as u64,
                "CallT must enter the callee without Rust step"
            );
            let stack = &vm.tasks[tid].stack;
            assert_eq!(stack[caller] >> 32, 1);
            assert_eq!(stack[next], 1);
            assert_eq!(
                stack[next + 1],
                caller as u64 | ((caller as u64 + 4 + 3) << 32)
            );
            assert_eq!(stack[next + 2], Value::NIL.0);
            assert_eq!(
                stack[next + 3] & 0xffffffff,
                (caller + vm.funcs[0].off_f() + 2) as u64
            );
            assert_eq!((stack[next + 3] >> 32) & 1, returning as u64);
            assert_eq!(
                (stack[next + 3] >> 33) & 0xffff,
                vm.funcs[1].frame_words() as u64
            );
            assert_eq!(stack[next + 5], Value::TRUE.0);
            assert_eq!(stack[next + 6], Value::num(17.0).0);
            assert_eq!(stack[next + 7], Value::NIL.0);
            assert_eq!(stack[next + 8], Value::NIL.0);
            assert_eq!(stack[next + off], (-0.0f64).to_bits());
            assert_eq!(stack[next + off + 1], f64::NAN.to_bits());
            assert_eq!(ctx.budget, 4);
        }
    }
}

#[test]
fn native_calltyped_checks_budget_and_capacity_before_mutating_frames() {
    for vararg in [false, true] {
        for empty_budget in [false, true] {
            let (mut vm, tid) = fixture(vararg, true);
            vm.execution_limit = Some(if empty_budget { 0 } else { 5 });
            let before = vm.tasks[tid].stack.clone();
            let current = vm.tasks[tid].cur();
            let capacity = if empty_budget {
                None
            } else {
                Some((current + vm.funcs[0].frame_words() + vm.funcs[1].frame_words() - 1) as u64)
            };
            let (ctx, exit) = enter(&mut vm, tid, capacity);
            assert_eq!(exit, vm.funcs[0].ins.as_ptr() as u64);
            assert_eq!(ctx.cur, current as u64);
            assert_eq!(ctx.budget, if empty_budget { 0 } else { 5 });
            assert_eq!(vm.tasks[tid].stack, before);
        }
    }
}

#[test]
fn native_calltyped_mixed_calls_match_rust_with_growth_and_limits() {
    let image = r#"
function caller 0 0 16 8 :v
const 0 num 17
K 4 0
FK 2 2.75
FK 3 -0
CallT 1 3 2 255
FBox 0 2
Ret 0
end
function callee 1 3 16 8 vff:f
FBox 0 0
Ret 0
end
entry 0
"#;
    for grow in [false, true] {
        for limit in [None, Some(0), Some(1), Some(3)] {
            let mut expected = None;
            for threaded in [false, true] {
                let mut vm = Box::new(Interp::new());
                crate::image::load(&mut vm, image).unwrap();
                vm.entries.resize(2, 0);
                vm.prepare_threaded();
                vm.threaded = threaded;
                vm.execution_limit = limit;
                let tid = vm.spawn(0, &[]);
                if grow {
                    let n = vm.funcs[0].frame_words();
                    vm.tasks[tid].stack.truncate(n);
                }
                let result = vm.guarded(|it| match it.run(tid) {
                    crate::interp::Outcome::Done(v) => v,
                    _ => panic!("unexpected park"),
                });
                let error = vm.pending_error.take().map(|v| vm.bytes_of(v).to_vec());
                let actual = (result.0, error, vm.execution_limit);
                if let Some(expected) = &expected {
                    assert_eq!(&actual, expected, "grow={grow} limit={limit:?}");
                } else {
                    expected = Some(actual);
                }
            }
        }
    }
}
