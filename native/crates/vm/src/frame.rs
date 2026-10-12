//! Compiled heap-frame entries. Immediate runtime operations stay in native
//! code; frame transfers and parks return to the driver with no native stack.
use crate::interp::{Interp, Op};

impl Interp {
    #[cfg(feature = "compiled-runtime")]
    pub(crate) fn run_compiled_frame(
        &mut self,
        tid: usize,
        fid: u32,
        pc: usize,
    ) -> Result<usize, crate::interp::Step> {
        use std::sync::atomic::Ordering;
        self.frame_entries.resize(self.funcs.len(), 0);
        if self.frame_entries[fid as usize] == 0 {
            #[cfg(not(feature = "jit"))]
            {
                return Ok(pc);
            }
            #[cfg(feature = "jit")]
            {
                let Some(mut jit) = self.jit.take() else {
                    return Ok(pc);
                };
                jit.cur_closure_addr = crate::compiled::closure_address() as i64;
                jit.extra_addr = self.extra.as_ptr() as i64;
                jit.last_nres_addr = &self.last_nres as *const _ as i64;
                jit.entries_addr = self.entries.as_ptr() as i64;
                jit.calltab_addr = self.calltab.as_ptr() as i64;
                jit.probe_addr = self.shape_probe.as_ptr() as i64;
                let result = jit.compile_frame(&self.funcs[fid as usize], fid);
                self.jit = Some(jit);
                self.frame_entries[fid as usize] = result.map(|p| p as u64).unwrap_or(u64::MAX);
            }
        }
        let entry = self.frame_entries[fid as usize];
        if entry == u64::MAX {
            return Ok(pc);
        }
        crate::compiled::CTX.store(self, Ordering::Relaxed);
        let frame = self.tasks[tid].cur();
        let header = unsafe { self.tasks[tid].stack.as_mut_ptr().add(frame) };
        self.compiled_frame_entries += 1;
        let previous_task = std::mem::replace(&mut self.native_task, tid);
        let previous_exit = self.native_exit.take();
        let next = unsafe {
            std::mem::transmute::<u64, extern "C" fn(*mut u64, usize) -> u64>(entry)(header, pc)
        };
        self.native_task = previous_task;
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

/// These operations can change frame ownership or enter arbitrary Nupp code.
/// A helper executes them against the heap frame and returns a transfer status;
/// a park always leaves native code before the scheduler runs another task.
pub(crate) fn boundary(op: &Op) -> bool {
    matches!(
        op,
        Op::Call(..)
            | Op::CallT(..)
            | Op::CallDyn(..)
            | Op::CallK(..)
            | Op::StorageLen(..)
            | Op::FLoad(..)
            | Op::FStore(..)
            | Op::VLoad(..)
            | Op::VStore(..)
            | Op::VLoadM(..)
            | Op::VStoreM(..)
            | Op::CallMethod(..)
            | Op::PCall(..)
            | Op::Ret(..)
            | Op::RetN(..)
            | Op::RetNil
            | Op::FRet(..)
            | Op::Park(..)
            | Op::Checkpoint
            | Op::AffineEnter
            | Op::AffineMark(..)
            | Op::CleanupLive(..)
            | Op::Defer(..)
            | Op::DeferMethod(..)
            | Op::Disarm(..)
            | Op::DisarmAt(..)
            | Op::Unwind(..)
            | Op::VarargN(..)
            | Op::VarargTable(..)
            | Op::Require(..)
            | Op::RequireV(..)
    )
}
