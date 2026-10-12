//! Round-robin scheduling across 1,000 three-frame tasks and a million parks.
use nupp_vm::{image, interp::Interp, scheduler::TaskId, value::Value};
use std::time::Instant;
const PROGRAM: &str = r#"
function outer 0 1 8 2 v:v
Move 3 1
Call 1 2 1
Ret 2
end
function middle 1 1 8 2 v:v
Move 3 1
Call 2 2 1
Ret 2
end
function worker 2 1 8 2 v:v
const 0 num 1
const 1 num 0
K 2 0
K 3 1
Park 1
Sub 1 1 2
Lt 4 3 1
JmpIf 4 -4
Ret 1
end
entry 0
"#;
fn trial(scheduled: bool, threaded: bool) -> f64 {
    let mut vm = Interp::new();
    image::load(&mut vm, PROGRAM).unwrap();
    vm.prepare_threaded();
    vm.threaded = threaded;
    if scheduled {
        vm.enable_scheduler().unwrap();
    }
    let tasks: Vec<TaskId> = (0..1000)
        .map(|_| {
            if scheduled {
                vm.schedule(Value::func(0), &[Value::num(1000.0)], None)
                    .unwrap()
            } else {
                TaskId {
                    index: vm.spawn(0, &[Value::num(1000.0)]),
                    generation: 0,
                }
            }
        })
        .collect();
    let start = Instant::now();
    for turn in 0..1001 {
        if scheduled {
            if turn > 0 {
                for &t in &tasks {
                    vm.wake_task(t).unwrap();
                }
            }
            vm.run_ready(1000).unwrap();
        } else {
            for &t in &tasks {
                if turn > 0 {
                    vm.resume(t.index);
                }
                vm.run(t.index);
            }
        }
    }
    let elapsed = start.elapsed().as_nanos() as f64 / 1_000_000.0;
    assert_eq!(vm.parks, 1_000_000);
    assert!(
        tasks
            .iter()
            .all(|&t| vm.tasks[t.index].result == Value::num(0.0))
    );
    elapsed
}
fn main() {
    for threaded in [false, true] {
        for scheduled in [false, true] {
            let mut times = Vec::new();
            for i in 0..7 {
                let ns = trial(scheduled, threaded);
                if i > 1 {
                    times.push(ns);
                }
            }
            times.sort_by(f64::total_cmp);
            println!(
                "{} {}: {:.1} ns/park+resume",
                if threaded { "threaded" } else { "Rust" },
                if scheduled { "scheduler" } else { "raw driver" },
                times[times.len() / 2]
            );
        }
    }
}
