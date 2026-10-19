use nupp_vm::{
    builtins,
    interp::{Function, Interp, Op},
    scheduler::Status,
    value::Value,
};

// Test-only driver for the source compiler's unmodified coroutine lowering.
// It collects every coroutine.resume result, including the final return.
pub fn install(vm: &mut Interp) -> u32 {
    let dead = vm.intern("dead");
    vm.handles.push(dead);
    let constants = vec![
        Value::builtin(builtins::id_of("tasks.coCreate").unwrap()),
        Value::builtin(builtins::id_of("tasks.coResume").unwrap()),
        Value::builtin(builtins::id_of("tasks.coStatus").unwrap()),
        Value::num(1.),
        dead,
    ];
    let mut code = vec![
        Op::K(15, 0),
        Op::Move(4, 1),
        Op::CallDyn(15, 3, 1),
        Op::NewTable(10),
        Op::K(11, 3),
        Op::K(12, 3),
        Op::K(15, 1),
        Op::Move(7, 3),
        Op::Move(8, 2),
        Op::CallDyn(15, 6, 2),
    ];
    let check = code.len();
    code.extend([
        Op::JmpIf(6, 1),
        Op::RetNil,
        Op::SetIdx(10, 11, 7),
        Op::Add(11, 11, 12),
        Op::K(15, 2),
        Op::Move(7, 3),
        Op::CallDyn(15, 6, 1),
        Op::K(13, 4),
        Op::Eq(14, 6, 13),
    ]);
    let done = code.len();
    code.push(Op::JmpIf(14, 0));
    code.extend([Op::K(15, 1), Op::Move(7, 3), Op::CallDyn(15, 6, 1)]);
    code.push(Op::Jmp(check as i32 - code.len() as i32 - 1));
    code[done] = Op::JmpIf(14, code.len() as i32 - done as i32 - 1);
    code.push(Op::Ret(10));
    let f = Function {
        name: "cfg_reference_coroutine".into(),
        module: "cfg.reference".into(),
        path: None,
        sig: vec![b'v', b'v'],
        ret: b'v',
        nv_params: 2,
        nf_params: 0,
        code,
        consts: constants,
        nparams: 2,
        nregs: 16,
        nireg: 0,
        nfreg: 0,
        nvreg: 0,
        jump_tables: vec![],
        debug: vec![],
        vararg: false,
        ins: vec![],
    };
    let id = vm.funcs.len() as u32;
    nupp_vm::verify::verify_classes(&f, id as usize + 1).unwrap();
    vm.funcs.push(f);
    id
}
pub fn run(vm: &mut Interp, driver: u32, function: Value, args: &[Value]) -> Vec<f64> {
    assert_eq!(args.len(), 1);
    let task = vm
        .schedule(Value::func(driver), &[function, args[0]], None)
        .unwrap();
    for _ in 0..1000 {
        vm.run_ready(128).unwrap();
        match vm.scheduler.as_ref().unwrap().status(task).unwrap() {
            Status::Active => continue,
            Status::Completed => {
                let table = vm.tasks[task.index].result;
                assert_ne!(table, Value::NIL, "reference coroutine failed");
                let mut trace = vec![];
                for i in 1..10000 {
                    let v = vm.get_index(table, Value::num(i as f64));
                    if v == Value::NIL {
                        break;
                    }
                    trace.push(v.as_num());
                }
                vm.release_task(task).unwrap();
                return trace;
            }
            status => panic!("reference failed: {status:?}"),
        }
    }
    panic!("reference scheduler did not complete")
}
