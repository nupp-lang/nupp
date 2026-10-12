use nupp_vm::{
    image,
    interp::Interp,
    persist::{self, Policies, ResourceCodecs},
    scheduler::Status,
    value::Value,
};
#[test]
fn nested_coroutine_yield_and_timer_park_restore() {
    let mut vm = Interp::new();
    image::load(&mut vm, include_str!("coroutines.bytecode")).unwrap();
    vm.install_globals();
    let host = vm.host_table();
    vm.loaded.insert("nupp.host".into(), host);
    vm.enable_scheduler().unwrap();
    let task = vm.schedule(Value::func(2), &[], None).unwrap();
    vm.run_ready(32).unwrap();
    assert_eq!(
        vm.scheduler.as_ref().unwrap().status(task),
        Some(&Status::Active)
    );
    assert_eq!(vm.scheduler.as_ref().unwrap().next_wakeup(), Some(5));
    let bytes = persist::save_vm(
        &mut vm,
        &Policies::default(),
        &mut ResourceCodecs::default(),
    )
    .unwrap();
    let mut restored =
        persist::load_vm(&bytes, &Policies::default(), &mut ResourceCodecs::default()).unwrap();
    restored.heap.stress_steps = true;
    restored.heap.oracle = true;
    restored.heap.quarantine = true;
    restored.advance_to(5).unwrap();
    restored.run_ready(32).unwrap();
    assert_eq!(
        restored.scheduler.as_ref().unwrap().status(task),
        Some(&Status::Completed)
    );
    assert_eq!(
        restored.tasks[task.index].results,
        vec![Value::TRUE, Value::TRUE, Value::num(42.0)]
    );
}

#[test]
fn cancelling_resumer_drains_nested_coroutines() {
    let mut vm = Interp::new();
    image::load(&mut vm, include_str!("coroutines.bytecode")).unwrap();
    vm.install_globals();
    let host = vm.host_table();
    vm.loaded.insert("nupp.host".into(), host);
    vm.enable_scheduler().unwrap();
    let task = vm.schedule(Value::func(2), &[], None).unwrap();
    vm.run_ready(32).unwrap();
    vm.cancel_task(task).unwrap();
    vm.run_ready(32).unwrap();
    assert_eq!(
        vm.scheduler.as_ref().unwrap().status(task),
        Some(&Status::Cancelled)
    );
    assert!(
        vm.scheduler
            .as_ref()
            .unwrap()
            .tasks()
            .all(|t| vm.scheduler.as_ref().unwrap().status(t) != Some(&Status::Active))
    );
    assert_eq!(vm.scheduler.as_ref().unwrap().next_wakeup(), None);
}
