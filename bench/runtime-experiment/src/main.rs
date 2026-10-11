mod heap;
mod interp;

use heap::{Body, SlotTy, Value};
use interp::{Function, Interp, Op, Outcome, State};
use std::hint::black_box;

fn cpu_now() -> f64 {
    let mut ts = libc::timespec { tv_sec: 0, tv_nsec: 0 };
    unsafe { libc::clock_gettime(libc::CLOCK_THREAD_CPUTIME_ID, &mut ts) };
    ts.tv_sec as f64 + ts.tv_nsec as f64 * 1e-9
}

fn func(name: &'static str, nparams: u8, nregs: u8, consts: Vec<Value>, code: Vec<Op>) -> Function {
    Function { name, code, consts, nparams, nregs, nireg: 8, nfreg: 8, nvreg: 8 }
}

const FIB: u32 = 0;
const MAKE: u32 = 1;
const CHECK: u32 = 2;
const TREES: u32 = 3;
const CHURN: u32 = 4;
const MAP: u32 = 5;
const DOT: u32 = 6;
const WORKER: u32 = 7;
const ALIAS: u32 = 8;
const MUTATE: u32 = 9;

fn build(it: &mut Interp) -> u32 {
    let x = it.intern("x");
    let left = it.intern("left");
    let right = it.intern("right");
    let name = it.intern("name");
    let node = it.heap.shape(&[left, right], &[SlotTy::Any, SlotTy::Any]);
    let point = it.heap.shape(&[x, name], &[SlotTy::Num, SlotTy::Str]);
    use Op::*;
    it.funcs = vec![
        func("fib", 1, 8, vec![Value::num(2.0), Value::num(1.0)], vec![
            K(2, 0), Lt(3, 1, 2), JmpIfNot(3, 1), Ret(1), K(2, 1), Sub(5, 1, 2), Call(FIB, 4, 1), K(2, 0), Sub(6, 1, 2), Call(FIB, 5, 1), Add(4, 4, 5), Ret(4),
        ]),
        func("make", 1, 8, vec![Value::num(0.0), Value::num(1.0)], vec![
            K(2, 0), Eq(3, 1, 2), JmpIfNot(3, 2), NewRecord(4, node), Ret(4), K(2, 1), Sub(5, 1, 2), Call(MAKE, 4, 1), Sub(6, 1, 2), Call(MAKE, 5, 1), NewRecord(6, node), SetSlot(6, 0, 4), SetSlot(6, 1, 5), Ret(6),
        ]),
        func("check", 1, 9, vec![Value::num(1.0)], vec![
            GetSlot(2, 1, 0), Nil(3), Eq(4, 2, 3), JmpIfNot(4, 2), K(5, 0), Ret(5), Move(6, 2), Call(CHECK, 5, 1), GetSlot(7, 1, 1), Call(CHECK, 6, 1), Add(5, 5, 6), K(2, 0), Add(5, 5, 2), Ret(5),
        ]),
        func("trees", 2, 10, vec![Value::num(0.0), Value::num(0.0), Value::num(1.0)], vec![
            K(3, 0), K(4, 1), Lt(5, 4, 1), JmpIfNot(5, 8), Move(7, 2), Call(MAKE, 6, 1), Move(8, 6), Call(CHECK, 7, 1), Add(3, 3, 7), K(5, 2), Add(4, 4, 5), Jmp(-10), Ret(3),
        ]),
        func("churn", 1, 9, vec![Value::num(0.0), Value::num(1.0), Value::num(1.0), x], vec![
            NewTable(2), K(3, 0), SetField(2, 3, 3), K(4, 1), Le(5, 4, 1), JmpIfNot(5, 6), GetField(6, 2, 3), Add(6, 6, 4), SetField(2, 3, 6), K(7, 2), Add(4, 4, 7), Jmp(-8), GetField(6, 2, 3), Ret(6),
        ]),
        func("map", 4, 5, vec![], vec![
            FUnbox(0, 3), FUnbox(1, 4), VSplat(0, 0), VSplat(1, 1), StorageLen(0, 2), IK(1, 0), IK(2, 4), IAddK(3, 1, 4), IJmpIfUle(3, 0, 1), Jmp(8),
            VLoad(2, 2, 1, 0), VLoad(3, 2, 1, 2), VFma(2, 2, 0, 1), VFma(3, 3, 0, 1), VStore(1, 1, 2, 0), VStore(1, 1, 3, 2), IAddK(1, 1, 4), Jmp(-11),
            IJmpIfUlt(1, 0, 1), Jmp(5), FLoad(2, 2, 1), FFma(2, 2, 0, 1), FStore(1, 1, 2), IAddK(1, 1, 1), Jmp(-7), RetNil,
        ]),
        func("dot", 2, 3, vec![], vec![
            FK(0, 0.0), VSplat(0, 0), VSplat(1, 0), StorageLen(0, 1), IK(1, 0), IAddK(2, 1, 4), IJmpIfUle(2, 0, 1), Jmp(8),
            VLoad(2, 1, 1, 0), VLoad(3, 1, 1, 2), VLoad(4, 2, 1, 0), VLoad(5, 2, 1, 2), VFma(0, 2, 4, 0), VFma(1, 3, 5, 1), IAddK(1, 1, 4), Jmp(-11),
            FK(1, 0.0), IJmpIfUlt(1, 0, 1), Jmp(5), FLoad(2, 1, 1), FLoad(3, 2, 1), FFma(1, 2, 3, 1), IAddK(1, 1, 1), Jmp(-7),
            VLane(2, 0, 0), VLane(3, 0, 1), FAdd(2, 2, 3), VLane(3, 1, 0), VLane(4, 1, 1), FAdd(3, 3, 4), FAdd(2, 2, 3), FAdd(2, 2, 1), FRet(2),
        ]),
        func("worker", 2, 6, vec![Value::num(0.0), Value::num(1.0)], vec![
            K(3, 0), Lt(4, 3, 1), JmpIfNot(4, 4), Park(2), K(5, 1), Add(3, 3, 5), Jmp(-6), Ret(3),
        ]),
        // alias(rec, v): untyped write of v into rec.x by name, then a typed read of slot 0.
        func("alias", 2, 5, vec![x], vec![SetField(1, 0, 2), GetSlot(3, 1, 0), Ret(3)]),
        // mutate(A, B, n): swap A[i] and B[i], old objects into old tables, and hang
        // the old A[i] off a fresh record, old object into a new one.
        func("mutate", 3, 10, vec![Value::num(1.0), Value::num(1.0)], vec![
            K(4, 0), Le(5, 4, 3), JmpIfNot(5, 9), GetIdx(6, 1, 4), GetIdx(7, 2, 4), SetIdx(1, 4, 7), SetIdx(2, 4, 6), NewRecord(8, node), SetSlot(8, 0, 6), K(9, 1), Add(4, 4, 9), Jmp(-11), Ret(4),
        ]),
    ];
    point
}

fn run_to_end(it: &mut Interp, fid: u32, args: &[Value]) -> Value {
    let t = it.spawn(fid, args);
    match it.run(t) { Outcome::Done(v) => { it.tasks.truncate(t); v } Outcome::Parked(_) => panic!("unexpected park") }
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let mode = args.get(1).map(|s| s.as_str()).unwrap_or("all");
    let mut it = Interp::new();
    let point = build(&mut it);
    let x = it.intern("x");

    if mode == "all" || mode == "check" {
        // Semantics without stress.
        assert_eq!(run_to_end(&mut it, FIB, &[Value::num(20.0)]).as_num(), 6765.0);
        assert_eq!(run_to_end(&mut it, TREES, &[Value::num(3.0), Value::num(10.0)]).as_num(), 3.0 * 2047.0);
        assert_eq!(run_to_end(&mut it, CHURN, &[Value::num(1000.0)]).as_num(), 500500.0);
        // Enforced write: a well-typed untyped write lands in the slot the typed read uses.
        let rec = it.new_record(point);
        it.handles.push(rec);
        assert_eq!(run_to_end(&mut it, ALIAS, &[rec, Value::num(7.0)]).as_num(), 7.0);
        let hook = std::panic::take_hook();
        std::panic::set_hook(Box::new(|_| {}));
        let bad = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| run_to_end(&mut it, ALIAS, &[rec, x])));
        std::panic::set_hook(hook);
        assert!(bad.is_err(), "a string written through an untyped alias into a number slot must be refused");
        it.tasks.clear();
        // Collector stress with the oracle: every allocation runs a whole cycle and
        // reachability is recomputed and compared.
        it.heap.stress = true;
        it.heap.oracle = true;
        assert_eq!(run_to_end(&mut it, TREES, &[Value::num(4.0), Value::num(7.0)]).as_num(), 4.0 * 255.0);
        assert_eq!(run_to_end(&mut it, CHURN, &[Value::num(300.0)]).as_num(), 45150.0);
        let stress_stats = it.heap.stats.clone();
        it.heap.stress = false;
        it.heap.oracle = false;
        // Incremental collection with the barrier, then an oracle check at the end.
        let before = it.heap.stats.cycles;
        assert_eq!(run_to_end(&mut it, TREES, &[Value::num(40.0), Value::num(12.0)]).as_num(), 40.0 * 8191.0);
        let cycles = it.heap.stats.cycles - before;
        assert!(cycles > 0, "incremental cycles ran: {cycles}");
        it.full_cycle();
        it.check_oracle();
        // Interleaved marking with the barrier: two tables of records swap
        // members while one collector step runs per allocation.
        let node = 0u32;
        let (ta, tb) = { let a = it.new_table(); it.handles.push(a); let b = it.new_table(); it.handles.push(b); (a, b) };
        let n = 200usize;
        for i in 0..n {
            for (t, base) in [(ta, 0.0), (tb, 1000.0)] {
                let r = it.new_record(node);
                it.set_slot(r, 1, Value::num(base + i as f64));
                it.push_array(t, r);
            }
        }
        it.heap.stress_steps = true;
        it.heap.oracle = true;
        it.heap.quarantine = true;
        for _ in 0..50 { assert_eq!(run_to_end(&mut it, MUTATE, &[ta, tb, Value::num(n as f64)]).as_num(), n as f64 + 1.0); }
        it.heap.stress_steps = false;
        it.heap.oracle = false;
        let mut sum = 0.0;
        for t in [ta, tb] { for i in 0..n { let r = it.array_get(t, i); sum += it.get_slot(r, 1).as_num(); } }
        assert_eq!(sum, (0..n).map(|i| i as f64 + 1000.0 + i as f64).sum::<f64>(), "records survived the swaps intact");
        let greys = it.heap.stats.barrier_grays;
        assert!(greys > 0, "the barrier fired under interleaving: {greys}");
        it.handles.truncate(0);
        it.heap.quarantine = std::env::var("GC_QUARANTINE").is_ok();
        eprintln!("PASS runtime-experiment: stress cycles {} freed {} barrier greys {}; incremental cycles {} steps {} live objects {}", stress_stats.cycles, stress_stats.freed, greys, cycles, it.heap.stats.steps, it.heap.object_count());
        // Park and resume through nested frames: worker parks inside its loop,
        // the scheduler runs others, and each resumes where it parked.
        let keys: Vec<Value> = (0..3).map(|i| Value::num(i as f64)).collect();
        let ts: Vec<usize> = keys.iter().map(|&k| it.spawn(WORKER, &[Value::num(5.0), k])).collect();
        let mut done = 0;
        let mut rounds = 0;
        while done < ts.len() {
            for &t in &ts {
                if it.tasks[t].state == State::Runnable { match it.run(t) { Outcome::Done(v) => { assert_eq!(v.as_num(), 5.0); done += 1; } Outcome::Parked(k) => { assert_eq!(k, it.tasks[t].regs[2].0); it.resume(t); } } }
            }
            rounds += 1;
        }
        assert_eq!(rounds, 6);
        it.tasks.clear();
        if mode == "check" { return; }
    }

    // Timed workloads, CPU time of this thread, printed as name<TAB>seconds.
    let (a, b) = {
        let a = it.new_storage(65539);
        it.handles.push(a);
        let b = it.new_storage(65539);
        it.handles.push(a);
        it.handles.push(b);
        for (i, v) in unsafe { if let Body::Storage { data } = &mut (*a.as_obj().unwrap().as_ptr()).body { data } else { unreachable!() } }.iter_mut().enumerate() { *v = ((i % 61) as f64 - 30.0) / 16.0; }
        for (i, v) in unsafe { if let Body::Storage { data } = &mut (*b.as_obj().unwrap().as_ptr()).body { data } else { unreachable!() } }.iter_mut().enumerate() { *v = ((i % 37) as f64 - 18.0) / 32.0; }
        (a, b)
    };
    let out = { let o = it.new_storage(65539); it.handles.push(o); o };
    let mut sink = 0.0;
    let mut timed = |name: &str, it: &mut Interp, f: &mut dyn FnMut(&mut Interp) -> f64| {
        let start = cpu_now();
        sink += black_box(f(it));
        println!("{name}\t{:.6}", cpu_now() - start);
    };
    if mode == "all" || mode == "fib" { timed("fib30", &mut it, &mut |it| run_to_end(it, FIB, &[Value::num(30.0)]).as_num()); }
    if mode == "all" || mode == "trees" { timed("trees15x10", &mut it, &mut |it| run_to_end(it, TREES, &[Value::num(10.0), Value::num(15.0)]).as_num()); }
    if mode == "all" || mode == "churn" { timed("churn5m", &mut it, &mut |it| run_to_end(it, CHURN, &[Value::num(5e6)]).as_num()); }
    if mode == "all" || mode == "map" { timed("map65539x200", &mut it, &mut |it| { let mut s = 0.0; for _ in 0..200 { run_to_end(it, MAP, &[out, a, Value::num(1.25), Value::num(0.5)]); s += 1.0; } s }); }
    if mode == "all" || mode == "dot" { timed("dot65539x200", &mut it, &mut |it| { let mut s = 0.0; for _ in 0..200 { s += run_to_end(it, DOT, &[a, b]).as_num(); } s }); }
    if mode == "all" || mode == "park" {
        timed("park1000x1000", &mut it, &mut |it| {
            let ts: Vec<usize> = (0..1000).map(|i| it.spawn(WORKER, &[Value::num(1000.0), Value::num(i as f64)])).collect();
            let mut done = 0;
            while done < ts.len() { for &t in &ts { if it.tasks[t].state == State::Runnable { match it.run(t) { Outcome::Done(_) => done += 1, Outcome::Parked(_) => it.resume(t) } } } }
            let n = it.parks as f64;
            it.tasks.clear();
            n
        });
    }
    eprintln!("sink {sink}");
}

