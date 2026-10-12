//! Compiled heap-frame entries. Native code returns at every call/park boundary;
//! the interpreter performs the transfer, then re-enters the current frame.
use crate::interp::Interp;

impl Interp {
    #[cfg(feature = "jit")]
    pub(crate) fn run_compiled_frame(&mut self, tid: usize, fid: u32, pc: usize) -> usize {
        use std::sync::atomic::Ordering;
        self.frame_entries.resize(self.funcs.len(), 0);
        if self.frame_entries[fid as usize] == 0 {
            let mut jit = self.jit.take().unwrap();
            jit.cur_closure_addr = &crate::compiled::CUR_CLOSURE as *const _ as i64;
            jit.extra_addr = self.extra.as_ptr() as i64;
            jit.last_nres_addr = &self.last_nres as *const _ as i64;
            jit.entries_addr = self.entries.as_ptr() as i64;
            jit.calltab_addr = self.calltab.as_ptr() as i64;
            jit.probe_addr = self.shape_probe.as_ptr() as i64;
            let result = jit.compile_frame(&self.funcs[fid as usize], fid);
            self.jit = Some(jit);
            self.frame_entries[fid as usize] = result.map(|p| p as u64).unwrap_or(u64::MAX);
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
