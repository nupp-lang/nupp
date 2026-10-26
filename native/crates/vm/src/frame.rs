//! Compiled heap-frame entries. Immediate runtime operations stay in native
//! code; frame transfers and parks return to the driver with no native stack.
use crate::interp::{Function, Interp, Op};

/// PCs where compiled code enters an activation: its start, and each back
/// edge, where an interpreted loop moves into compiled code.
///
/// Not the boundaries. A call that completes keeps its caller in native
/// code; one that leaves for the driver -- a park, the nesting limit -- is
/// rare (0.14% of a cold check's entries), and the interpreter finishes that
/// activation. Making each boundary and the instruction after it an entry
/// put a dispatch arm and a reload of every live register at every call,
/// which grew the code with calls times live values and made a large
/// function take seconds to compile.
pub(crate) fn resumes(f: &Function) -> std::collections::BTreeSet<usize> {
    let mut points = std::collections::BTreeSet::from([0]);
    for (pc, op) in f.code.iter().enumerate() {
        if back_edge(op) {
            points.insert(pc);
        }
    }
    points
}

/// A backward jump: a loop's back edge.
pub(crate) fn back_edge(op: &Op) -> bool {
    matches!(op, Op::Jmp(n) | Op::JmpIfIZero(_, n) | Op::JmpIf(_, n) | Op::JmpIfNot(_, n) | Op::IJmpIfUle(_, _, n) | Op::IJmpIfUlt(_, _, n) if *n < 0)
}

/// Room the JIT's tables keep for images loaded after it starts. Compiled
/// code holds their addresses as constants, so they must never move.
#[cfg(feature = "jit")]
const JIT_TABLE_ROOM: usize = 1 << 16;

impl Interp {
    /// Gives the tables the JIT's code reads by address room to grow in
    /// place. Called before the JIT records those addresses.
    #[cfg(feature = "jit")]
    pub fn reserve_jit_tables(&mut self) {
        let funcs = self.funcs.len() + JIT_TABLE_ROOM;
        let shapes = self.heap.shapes.len() + JIT_TABLE_ROOM;
        self.entries.reserve(funcs.saturating_sub(self.entries.len()));
        self.calltab.reserve(funcs.saturating_sub(self.calltab.len()));
        self.shape_probe.reserve(shapes.saturating_sub(self.shape_probe.len()));
    }

    /// After an image loads into a VM with the JIT, extends the tables its
    /// compiled code reads by address -- in place, since that code keeps the
    /// old addresses -- and what the JIT knows of each function. An image
    /// past the reserved room is refused rather than moving them.
    #[cfg(feature = "jit")]
    pub(crate) fn extend_jit_tables(&mut self) {
        let funcs = self.funcs.len();
        let shapes = self.heap.shapes.len();
        if funcs > self.entries.capacity() || funcs > self.calltab.capacity() || shapes > self.shape_probe.capacity() {
            self.err("the loaded image needs more functions or shapes than a JIT VM reserves room for");
        }
        self.entries.resize(funcs, 0);
        for fid in self.calltab.len()..funcs {
            let f = &self.funcs[fid];
            let plain = f.sig.iter().all(|&c| c == b'v') && f.ret != b'f' && !f.vararg;
            self.calltab.push(f.nparams as u64 | ((plain as u64) << 8));
        }
        for shape in self.shape_probe.len()..shapes {
            let s = &self.heap.shapes[shape];
            self.shape_probe.push((s.table.as_ptr() as u64, s.mask));
        }
        if let Some(jit) = self.jit.as_mut() {
            for fid in jit.callee_info.len()..funcs {
                let f = &self.funcs[fid];
                jit.callee_info.push((f.nparams, f.sig.iter().all(|&c| c == b'v') && f.ret != b'f' && !f.vararg));
            }
        }
    }

    /// What the frame driver does as a function begins, for the threaded
    /// core, which calls this when it pushed a function with a compiled frame
    /// entry or vector instructions: refuse vector code a no-JIT host may not
    /// interpret, then run the compiled entry. Answers the pc the core goes
    /// on interpreting at, as `run_compiled_frame` does.
    pub(crate) fn enter_frame_from_core(&mut self, tid: usize, fid: u32, pc: usize, hot: bool) -> Result<usize, crate::interp::Step> {
        if pc == 0 && !self.simd_interpret && !self.compiled_frames_active_pub() && self.function_needs_native(fid) {
            self.err("SIMD function requires native compilation or a matching AOT entry (SIMD_INTERPRET=1 runs it interpreted)");
        }
        // The core counted this function's heat itself: it is due now.
        #[cfg(feature = "jit")]
        if hot && self.frame_threshold > 0 {
            self.frame_heat.resize(self.funcs.len(), 0);
            self.frame_heat[fid as usize] = self.frame_threshold - 1;
        }
        let _ = hot;
        #[cfg(feature = "compiled-runtime")]
        if self.compiled_frames_active_pub() { return self.run_compiled_frame(tid, fid, pc); }
        let _ = tid;
        Ok(pc)
    }

    #[cfg(feature = "compiled-runtime")]
    #[inline]
    fn refresh_native_frame_context(&mut self) {
        #[cfg(feature = "jit")]
        {
            let needed = !self.linked_frames.is_empty() || self.jit.as_ref().is_some_and(|jit| jit.native_frame_calls);
            if !needed { return; }
        }
        crate::compiled::j_frame_refresh();
    }

    #[cfg(feature = "compiled-runtime")]
    fn prepare_frame_entry(&mut self, fid: u32) -> u64 {
        if self.frame_entries.len() != self.funcs.len() {
            self.invalidate_frame_context();
            self.frame_entries.resize(self.funcs.len(), 0);
        }
        if self.frame_entries[fid as usize] == 0 {
            #[cfg(not(feature = "jit"))]
            {
                return 0;
            }
            #[cfg(feature = "jit")]
            {
                if self.frame_threshold > 0 && !self.function_needs_native(fid) {
                    self.frame_heat.resize(self.funcs.len(), 0);
                    let heat = &mut self.frame_heat[fid as usize];
                    *heat += 1;
                    if *heat < self.frame_threshold {
                        return 0;
                    }
                }
                // Off the main thread: the function keeps running interpreted,
                // and its entry is installed when the compile comes back.
                // Vector code compiles here, since it may have nowhere else to
                // run, as does whatever specialization compiles.
                // A zero threshold asks for every function compiled as it is
                // first entered; that stays here too.
                if self.jit_background && self.frame_threshold > 0 && !self.spec.frames && !self.function_needs_native(fid) && self.jit.is_some() {
                    self.install_finished_frames();
                    if self.frame_entries[fid as usize] != 0 { return self.frame_entries[fid as usize]; }
                    if self.jit_worker.as_ref().is_some_and(|w| w.queued(fid)) { return 0; }
                    let job = crate::jit::Job {
                        fid,
                        func: self.funcs[fid as usize].clone(),
                        closure: crate::compiled::closure_address() as i64,
                        extra: self.extra.as_ptr() as i64,
                        last_nres: &self.last_nres as *const _ as i64,
                        entries: self.entries.as_ptr() as i64,
                        calltab: self.calltab.as_ptr() as i64,
                        probe: if self.linked_frames.is_empty() { self.shape_probe.as_ptr() as i64 } else { 0 },
                        callee_info: self.jit.as_ref().map(|j| j.callee_info.clone()).unwrap_or_default(),
                        guest: self.guest_jit,
                    };
                    let worker = self.jit_worker.get_or_insert_with(|| Box::new(crate::jit::Worker::start()));
                    if worker.submit(job) { return 0; }
                    self.jit_background = false;
                }
                #[cfg(all(feature = "aot", feature = "native-runtime"))]
                if self.guest_jit {
                    // The Nupp emitter compiles the frame entry; a function
                    // it refuses stays interpreted.
                    if self.jit.is_none() { return 0; }
                    let result = crate::jit_glue::compile_here(&self.funcs[fid as usize], fid);
                    if let Err(reason) = &result { if std::env::var_os("JIT_GUEST_TRACE").is_some() { eprintln!("guest jit: {} refused: {reason}", self.funcs[fid as usize].name); } }
                    self.frame_entries[fid as usize] = result.unwrap_or(u64::MAX);
                    return self.frame_entries[fid as usize];
                }
                let Some(mut jit) = self.jit.take() else {
                    return 0;
                };
                jit.cur_closure_addr = crate::compiled::closure_address() as i64;
                jit.extra_addr = self.extra.as_ptr() as i64;
                jit.last_nres_addr = &self.last_nres as *const _ as i64;
                jit.entries_addr = self.entries.as_ptr() as i64;
                jit.calltab_addr = self.calltab.as_ptr() as i64;
                // Linked fallback code may outlive tables grown by later images.
                // Use per-site helpers instead of retaining those table addresses.
                jit.probe_addr = if self.linked_frames.is_empty() { self.shape_probe.as_ptr() as i64 } else { 0 };
                let result = jit.compile_frame(&self.funcs[fid as usize], fid);
                self.jit = Some(jit);
                // A SIMD function the typed tier refuses runs on the interpreter's
                // lane loop, like any other function it refuses.
                let _ = &result;
                self.frame_entries[fid as usize] = result.map(|p| p as u64).unwrap_or(u64::MAX);
            }
        }
        self.frame_entries[fid as usize]
    }

    /// Installs the frame entries the background compiler finished: a
    /// refused function stays interpreted, as a refused synchronous compile
    /// leaves it.
    #[cfg(feature = "jit")]
    pub(crate) fn install_finished_frames(&mut self) {
        let Some(worker) = self.jit_worker.as_mut() else { return };
        let finished = worker.finished();
        if finished.is_empty() { return; }
        if self.frame_entries.len() != self.funcs.len() {
            self.invalidate_frame_context();
            self.frame_entries.resize(self.funcs.len(), 0);
        }
        for (fid, result) in finished {
            if let Some(slot) = self.frame_entries.get_mut(fid as usize) {
                if *slot == 0 { *slot = result.unwrap_or(u64::MAX); }
            }
        }
    }

    /// Compile before entering a timed workload, using the same entries as
    /// on-demand compilation. Refused functions retain the interpreter fallback.
    #[cfg(feature = "jit")]
    pub fn precompile_frames(&mut self) -> usize {
        // Compiled before it returns, not queued.
        let background = std::mem::replace(&mut self.jit_background, false);
        let compiled = (0..self.funcs.len() as u32)
            .filter(|&fid| !matches!(self.prepare_frame_entry(fid), 0 | u64::MAX))
            .count();
        self.jit_background = background;
        compiled
    }

    #[cfg(feature = "compiled-runtime")]
    pub(crate) fn run_compiled_frame(
        &mut self,
        tid: usize,
        fid: u32,
        pc: usize,
    ) -> Result<usize, crate::interp::Step> {
        use std::sync::atomic::Ordering;
        #[cfg(feature = "jit")]
        if self.spec.frames { self.spec_frame_entry(fid); }
        let entry = self.prepare_frame_entry(fid);
        if entry == 0 || entry == u64::MAX {
            // A host without a code generator runs SIMD interpreted only by
            // policy: the no-JIT product refuses an unmatched plugin before
            // its first side effect rather than running a kernel a thousand
            // times slower without saying so. JIT-capable hosts under NO_JIT
            // are the oracle path and interpret freely.
            if !self.simd_interpret && self.function_needs_native(fid) {
                self.err("SIMD function requires native compilation or a matching AOT entry (SIMD_INTERPRET=1 runs it interpreted)");
            }
            return Ok(pc);
        }
        #[cfg(all(feature = "aot", feature = "native-runtime"))]
        if self.guest_jit { return self.run_guest_frame(tid, fid, pc, entry); }
        crate::compiled::CTX.store(self, Ordering::Relaxed);
        let frame = self.tasks[tid].cur();
        let header = unsafe { self.tasks[tid].stack.as_mut_ptr().add(frame) };
        self.compiled_frame_entries += 1;
        if pc != 0 { self.compiled_frame_continuations += 1; }
        let previous_task = std::mem::replace(&mut self.native_task, tid);
        let previous_exit = self.native_exit.take();
        self.native_frame_depth += 1;
        let direct = std::mem::replace(&mut self.direct_frame, usize::MAX);
        self.invalidate_frame_context();
        self.refresh_native_frame_context();
        let next = unsafe {
            std::mem::transmute::<u64, extern "C" fn(*mut u64, usize) -> u64>(entry)(header, pc)
        };
        self.direct_frame = direct;
        self.native_frame_depth -= 1;
        self.native_task = previous_task;
        self.invalidate_frame_context();
        let exit = std::mem::replace(&mut self.native_exit, previous_exit);
        if next == u64::MAX {
            return Err(exit.expect("native frame transfer"));
        }
        if next == crate::value::Value::ERROR.0 {
            let value = self
                .pending_error
                .take()
                .unwrap_or(crate::value::Value::NIL);
            std::panic::panic_any(crate::builtins::LuaError(value.0));
        }
        assert!((next as usize) < self.funcs[fid as usize].code.len());
        Ok(next as usize)
    }
}

impl Interp {
    /// Runs the frame a compiled caller's call just pushed until the caller's
    /// frame at `stop` is on top again. The common case calls the callee's
    /// compiled entry directly and finds the caller on top when it returns;
    /// anything else (a park, an interpreted callee, a deeper transfer) goes
    /// through `drive_until`. A raise inside comes back as the error sentinel
    /// with the value pending, as it would from any compiled frame.
    #[cfg(feature = "compiled-runtime")]
    pub(crate) fn run_callee(&mut self, tid: usize, stop: usize) -> Result<bool, crate::interp::Step> {
        let s = self.tasks[tid].cur();
        let fid = (self.tasks[tid].stack[s] & 0xffff_ffff) as u32;
        // The same entry accounting `run_compiled_frame` does.
        #[cfg(feature = "jit")]
        if self.spec.frames { self.spec_frame_entry(fid); }
        let entry = self.prepare_frame_entry(fid);
        if entry != 0 && entry != u64::MAX {
            let header = unsafe { self.tasks[tid].stack.as_mut_ptr().add(s) };
            self.compiled_frame_entries += 1;
            self.native_frame_depth += 1;
            self.refresh_native_frame_context();
            let next = unsafe { std::mem::transmute::<u64, extern "C" fn(*mut u64, usize) -> u64>(entry)(header, 0) };
            self.native_frame_depth -= 1;
            return self.finish_callee(tid, stop, next);
        }
        self.drive_until(tid, stop).map(|()| true)
    }

    #[cfg(feature = "compiled-runtime")]
    #[inline(always)]
    pub(crate) fn finish_callee(&mut self, tid: usize, stop: usize, next: u64) -> Result<bool, crate::interp::Step> {
        if next == crate::value::Value::ERROR.0 { return Ok(false); }
        if next == u64::MAX {
            match self.native_exit.take() {
                Some(crate::interp::Step::Reenter) if self.tasks[tid].cur() == stop => return Ok(true),
                Some(crate::interp::Step::Reenter) => { if self.unwind_nested { return Err(crate::interp::Step::Reenter); } }
                Some(exit) => return Err(exit),
                None => unreachable!("native frame transfer without an exit"),
            }
        } else {
            self.tasks[tid].note_pc(next as usize);
        }
        self.drive_until(tid, stop).map(|()| true)
    }
}

/// These operations can change frame ownership or enter arbitrary Nupp code.
/// A helper executes them against the heap frame and returns a transfer status;
/// a park always leaves native code before the scheduler runs another task.
/// The classification is `effects::of_op`'s transfer class.
pub(crate) fn boundary(op: &Op) -> bool { crate::effects::of_op(op).transfers() }

#[cfg(all(test, feature = "jit"))]
mod tests {
    use super::*;
    use crate::{
        persist::{self, Policies, ResourceCodecs},
        scheduler::Status,
        value::Value,
    };
    fn native_vm(source: &str) -> Box<Interp> {
        let mut vm = Box::new(Interp::new());
        crate::image::load(&mut vm, source).unwrap();
        vm.install_globals();
        vm.heap.stress_steps = true;
        vm.heap.oracle = true;
        vm.heap.quarantine = true;
        vm.jit = Some(Box::new(crate::jit::Jit::new()));
        vm.jit.as_mut().unwrap().native_frame_calls = true;
        vm.precompile_frames();
        vm
    }

    #[test]
    fn native_calls_preserve_live_objects_and_result_packs() {
        let mut vm = native_vm(r#"
function triple 0 3 12 2 vvv:v
NewTable 4
RetN 1 3
end
function main 1 0 40 4 :v
const 0 func 0
const 1 num 10
const 2 num 20
const 3 num 12
const 4 str "answer"
const 5 num 42
NewTable 20
K 21 4
K 22 5
SetIdx 20 21 22
K 1 0
K 3 1
K 4 2
K 5 3
CallDyn 1 2 3
PadResults 2 4
GetIdx 31 20 21
Add 32 2 3
Add 32 32 4
Eq 33 31 32
Ret 33
end
entry 1
"#);
        for _ in 0..4 {
            assert_eq!(vm.call_value(Value::func(1), &[]), vec![Value::TRUE]);
            assert_eq!(vm.direct_frame, usize::MAX);
            assert_eq!(vm.nested_calls, 0);
            assert_eq!(vm.native_frame_depth, 0);
        }
    }

    #[test]
    fn native_call_refreshes_task_pointers_after_metamethod_reentry() {
        let source = r#"
function index 0 2 4 1 vv:v
Ret 1
end
function read 1 1 4 1 v:v
const 0 str "missing"
GetField 2 1 0
Ret 2
end
function main 2 0 20 2 :v
const 0 builtin setmetatable
const 1 str "__index"
const 2 func 0
const 3 func 1
K 1 0
NewTable 3
NewTable 4
K 5 1
K 6 2
SetIdx 4 5 6
CallDyn 1 2 2
K 7 3
Move 9 2
CallDyn 7 8 1
Eq 10 2 8
Ret 10
end
entry 2
"#;
        for scheduled in [false, true] {
            let mut vm = native_vm(source);
            if scheduled {
                vm.enable_scheduler().unwrap();
                let task = vm.schedule(Value::func(2), &[], None).unwrap();
                vm.tasks.shrink_to_fit();
                assert_eq!(vm.run_ready(1).unwrap()[0].status, Status::Completed);
                assert_eq!(vm.tasks[task.index].result, Value::TRUE);
            } else {
                let tid = vm.spawn_closure(Value::func(2), &[]);
                vm.tasks.shrink_to_fit();
                assert!(matches!(vm.run(tid), crate::interp::Outcome::Done(Value::TRUE)));
            }
            assert_eq!(vm.direct_frame, usize::MAX);
            assert_eq!(vm.nested_calls, 0);
        }
    }

    #[test]
    fn native_calls_drain_before_parking_and_restore_without_native_code() {
        let mut vm = native_vm(r#"
function wait 0 1 4 1 v:v
Park 1
Ret 1
end
function main 1 0 32 2 :v
const 0 func 0
const 1 str "answer"
const 2 num 42
NewTable 20
K 21 1
K 22 2
SetIdx 20 21 22
K 1 0
Move 3 22
CallDyn 1 2 1
GetIdx 23 20 21
Eq 24 2 23
Ret 24
end
entry 1
"#);
        vm.enable_scheduler().unwrap();
        let task = vm.schedule(Value::func(1), &[], None).unwrap();
        assert!(vm.run_ready(1).unwrap().is_empty());
        assert_eq!(vm.direct_frame, usize::MAX);
        assert_eq!(vm.nested_calls, 0);
        assert_eq!(vm.native_frame_depth, 0);
        let bytes = crate::persist::save_vm(&mut vm, &Default::default(), &mut Default::default()).unwrap();
        let mut restored = crate::persist::load_vm(&bytes, &Default::default(), &mut Default::default()).unwrap();
        assert!(restored.jit.is_none());
        for vm in [&mut *vm, &mut restored] {
            vm.wake_task(task).unwrap();
            assert_eq!(vm.run_ready(1).unwrap()[0].status, Status::Completed);
            assert_eq!(vm.tasks[task.index].result, Value::TRUE);
            assert_eq!(vm.direct_frame, usize::MAX);
            assert_eq!(vm.nested_calls, 0);
            assert_eq!(vm.native_frame_depth, 0);
        }
    }

    #[test]
    fn native_error_restores_the_vm_for_another_call() {
        let mut vm = native_vm(r#"
function fail 0 0 12 2 :v
const 0 builtin error
const 1 str "boom"
K 1 0
K 3 1
CallDyn 1 2 1
RetNil
end
function main 1 0 12 2 :v
const 0 func 0
K 1 0
CallDyn 1 2 0
Ret 2
end
function answer 2 0 4 1 :v
const 0 num 42
K 1 0
Ret 1
end
entry 1
"#);
        assert!(std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| vm.call_value(Value::func(1), &[]))).is_err());
        assert_eq!(vm.direct_frame, usize::MAX);
        assert_eq!(vm.nested_calls, 0);
        assert_eq!(vm.native_frame_depth, 0);
        assert_eq!(vm.call_value(Value::func(2), &[]), vec![Value::num(42.0)]);
    }

    #[test]
    fn native_recursion_grows_the_stack_and_unwinds_the_nesting_cap() {
        let mut vm = native_vm(r#"
function recurse 0 1 16 2 v:v
const 0 num 0
const 1 num 1
const 2 func 0
K 2 0
Eq 3 1 2
JmpIfNot 3 1
Ret 1
K 2 1
K 4 2
Sub 6 1 2
CallK 0 4 5 1 1
K 2 1
Add 5 5 2
Ret 5
end
entry 0
"#);
        assert_eq!(vm.call_value(Value::func(0), &[Value::num(400.0)]), vec![Value::num(400.0)]);
        assert_eq!(vm.direct_frame, usize::MAX);
        assert_eq!(vm.nested_calls, 0);
        assert_eq!(vm.native_frame_depth, 0);
    }

    #[test]
    fn native_calls_preserve_integer_float_and_vector_windows() {
        let mut vm = native_vm(r#"
function identity 0 1 4 1 v:v
Ret 1
end
function main 1 0 16 4 :v
const 0 func 0
const 1 num 5
K 1 0
K 3 1
FUnbox 0 3
IK 0 7
CallDyn 1 2 1
IToF 2 0
FAdd 3 1 2
FBox 4 3
Add 5 4 2
Ret 5
end
entry 1
"#);
        vm.frame_entries.fill(0);
        vm.jit = Some(Box::new(crate::jit::Jit::new()));
        vm.jit.as_mut().unwrap().native_frame_calls = true;
        let f = &mut vm.funcs[1];
        f.nvreg = 1;
        let at = f.code.iter().position(|op| matches!(op, Op::IK(..))).unwrap();
        f.code.insert(at, Op::VSplat(0, 0));
        let at = f.code.iter().position(|op| matches!(op, Op::IToF(..))).unwrap();
        f.code.insert(at, Op::VLane(1, 0, 1));
        vm.precompile_frames();
        assert_eq!(vm.call_value(Value::func(1), &[]), vec![Value::num(17.0)]);
    }

    #[test]
    fn native_callee_with_cleanup_returns_through_the_driver_once() {
        let mut vm = native_vm(r#"
function cleanup 0 1 4 1 v:v
const 0 func 1
K 2 0
Defer 1 2
Ret 1
end
function drop 1 1 6 1 v:v
const 0 str "count"
const 1 num 1
GetField 2 1 0
K 3 1
Add 2 2 3
SetField 1 0 2
RetNil
end
function main 2 0 12 2 :v
const 0 func 0
const 1 str "count"
const 2 num 0
K 1 0
NewTable 3
K 4 2
SetField 3 1 4
CallDyn 1 2 1
GetField 5 2 1
Ret 5
end
entry 2
"#);
        for _ in 0..3 {
            assert_eq!(vm.call_value(Value::func(2), &[]), vec![Value::num(1.0)]);
            assert_eq!(vm.direct_frame, usize::MAX);
        }
    }

    #[test]
    fn native_call_preserves_a_precompiled_coroutine_wrapper() {
        let mut vm = native_vm(r#"
function body 0 0 4 1 :v
const 0 num 42
K 1 0
Ret 1
end
function main 1 0 12 2 :v
const 0 builtin tasks.coWrap
const 1 func 0
K 1 0
K 3 1
CallDyn 1 2 1
CallDyn 2 4 0
Ret 4
end
entry 1
"#);
        vm.enable_scheduler().unwrap();
        let task = vm.schedule(Value::func(1), &[], None).unwrap();
        vm.run_ready(256).unwrap();
        assert_eq!(vm.scheduler.as_ref().unwrap().status(task), Some(&Status::Completed));
        assert_eq!(vm.tasks[task.index].result, Value::num(42.0));
    }

    #[test]
    fn native_calls_return_nil_and_fall_back_for_missing_arguments() {
        let mut vm = native_vm(r#"
function nothing 0 0 4 1 :v
RetNil
end
function identity 1 1 4 1 v:v
Ret 1
end
function main 2 0 20 2 :v
const 0 func 0
const 1 func 1
const 2 num 42
K 1 0
CallDyn 1 2 0
K 4 1
CallDyn 4 5 0
Eq 7 2 5
Ret 7
end
entry 2
"#);
        assert_eq!(vm.call_value(Value::func(2), &[]), vec![Value::TRUE]);
    }

    #[test]
    fn interpreter_checkpoint_resumes_between_compiled_entries() {
        let mut vm = Box::new(Interp::new());
        crate::image::load(
            &mut vm,
            r#"
function main 0 0 8 2 :v
const 0 str "answer"
const 1 num 42
NewTable 1
K 2 0
K 3 1
SetIdx 1 2 3
IK 0 3
IAddK 0 0 -1
JmpIfIZero 0 1
Jmp -3
GetIdx 4 1 2
Ret 4
end
entry 0
"#,
        )
        .unwrap();
        vm.install_globals();
        vm.enable_scheduler().unwrap();
        vm.heap.stress_steps = true;
        vm.heap.oracle = true;
        vm.heap.quarantine = true;
        vm.jit = None;
        let task = vm.schedule(Value::func(0), &[], None).unwrap();
        // A budget of one back edge: the loop's second one parks the task at
        // the jump, in the middle of the activation.
        vm.instruction_budget = Some(1);
        assert!(vm.run_ready(1).unwrap().is_empty());
        let frame = vm.tasks[task.index].cur();
        assert_eq!(vm.tasks[task.index].stack[frame] >> 32, 7);
        let bytes =
            persist::save_vm(&mut vm, &Policies::default(), &mut ResourceCodecs::new()).unwrap();
        let mut restored =
            persist::load_vm(&bytes, &Policies::default(), &mut ResourceCodecs::new()).unwrap();
        restored.jit = Some(Box::new(crate::jit::Jit::new()));
        restored.instruction_budget = None;
        // The resumed activation is past the function's only entry, at its
        // start: the interpreter finishes it.
        assert_eq!(restored.run_ready(1).unwrap()[0].status, Status::Completed);
        assert_eq!(restored.tasks[task.index].result, Value::num(42.0));
        // The next call enters compiled code from the start.
        let again = restored.schedule(Value::func(0), &[], None).unwrap();
        assert_eq!(restored.run_ready(1).unwrap()[0].status, Status::Completed);
        assert_eq!(restored.tasks[again.index].result, Value::num(42.0));
        assert!(restored.compiled_frame_entries > 0);
    }
}
