//! Compiled heap-frame entries. Native code returns at every call/park boundary;
//! the interpreter performs the transfer, then re-enters the current frame.
use crate::interp::{Interp, Op};

impl Interp {
    #[cfg(feature = "compiled-runtime")]
    pub(crate) fn run_compiled_frame(&mut self, tid: usize, fid: u32, pc: usize) -> usize {
        use std::sync::atomic::Ordering;
        // Runtime boundaries execute in the driver. Entering native code at
        // one would only load and spill the same frame before returning here.
        if boundary(&self.funcs[fid as usize].code[pc]) { return pc; }
        self.frame_entries.resize(self.funcs.len(), 0);
        if self.frame_entries[fid as usize] == 0 {
            #[cfg(not(feature = "jit"))]
            {
                return pc;
            }
            #[cfg(feature = "jit")]
            {
                let Some(mut jit) = self.jit.take() else {
                    return pc;
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
            return pc;
        }
        crate::compiled::CTX.store(self, Ordering::Relaxed);
        let frame = self.tasks[tid].cur();
        let header = unsafe { self.tasks[tid].stack.as_mut_ptr().add(frame) };
        self.compiled_frame_entries += 1;
        let next = unsafe {
            std::mem::transmute::<u64, extern "C" fn(*mut u64, usize) -> u64>(entry)(header, pc)
        };
        if next == crate::value::Value::ERROR.0 {
            let value = self
                .pending_error
                .take()
                .unwrap_or(crate::value::Value::NIL);
            std::panic::panic_any(crate::builtins::LuaError(value.0));
        }
        assert!((next as usize) < self.funcs[fid as usize].code.len());
        next as usize
    }
}

/// These operations can change frame ownership or enter arbitrary Nupp code.
/// Returning to the driver before them prevents native callers surviving a park.
pub(crate) fn boundary(op: &Op) -> bool {
    matches!(op, Op::Call(..) | Op::CallT(..) | Op::CallDyn(..) | Op::CallK(..)
        | Op::StorageLen(..) | Op::FLoad(..) | Op::FStore(..) | Op::VLoad(..) | Op::VStore(..) | Op::VLoadM(..) | Op::VStoreM(..)
        | Op::CallMethod(..) | Op::PCall(..) | Op::Ret(..) | Op::RetN(..)
        | Op::RetNil | Op::FRet(..) | Op::Park(..) | Op::Checkpoint
        | Op::AffineEnter | Op::AffineMark(..) | Op::CleanupLive(..) | Op::Defer(..) | Op::DeferMethod(..) | Op::Disarm(..) | Op::DisarmAt(..) | Op::Unwind(..) | Op::VarargN(..) | Op::VarargTable(..) | Op::Require(..) | Op::RequireV(..))
}
