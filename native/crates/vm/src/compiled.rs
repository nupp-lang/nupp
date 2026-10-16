//! Runtime support shared by JIT and linked native code.
//! This module has no dependency on Cranelift or executable-memory allocation.

use crate::heap::{KIND_TABLE, KIND_RECORD};
use crate::interp::Interp;
use crate::value::Value as V;

/// Compiled code ranges and their stack maps: (start, end, [(return offset, frame span, [slot offsets])]).
pub static CODE_MAPS: std::sync::Mutex<Vec<(usize, usize, Vec<(u32, u32, Vec<u32>)>)>> = std::sync::Mutex::new(Vec::new());
// Helpers and native roots belong to the thread running this VM. Worker
// collectors must never walk another thread's native stack.
use std::sync::atomic::{AtomicPtr, AtomicU64, AtomicUsize, Ordering};
thread_local! {
    static LOCAL_FP: AtomicUsize = const { AtomicUsize::new(0) };
    static LOCAL_CLOSURE: AtomicU64 = const { AtomicU64::new(0) };
    static LOCAL_CTX: AtomicPtr<Interp> = const { AtomicPtr::new(std::ptr::null_mut()) };
}
pub struct LocalFrame;
pub static HELPER_FP: LocalFrame = LocalFrame;
impl LocalFrame {
    pub fn load(&self, order: Ordering) -> usize { LOCAL_FP.with(|v| v.load(order)) }
    pub fn store(&self, value: usize, order: Ordering) { LOCAL_FP.with(|v| v.store(value, order)); }
    pub fn swap(&self, value: usize, order: Ordering) -> usize { LOCAL_FP.with(|v| v.swap(value, order)) }
}
pub struct LocalClosure;
pub static CUR_CLOSURE: LocalClosure = LocalClosure;
impl LocalClosure {
    pub fn load(&self, order: Ordering) -> u64 { LOCAL_CLOSURE.with(|v| v.load(order)) }
    pub fn store(&self, value: u64, order: Ordering) { LOCAL_CLOSURE.with(|v| v.store(value, order)); }
}
pub fn closure_address() -> u64 { LOCAL_CLOSURE.with(|v| v as *const AtomicU64 as u64) }
pub struct LocalContext;
pub static CTX: LocalContext = LocalContext;
impl LocalContext {
    pub fn load(&self, order: Ordering) -> *mut Interp { LOCAL_CTX.with(|v| v.load(order)) }
    pub fn store(&self, value: *mut Interp, order: Ordering) { LOCAL_CTX.with(|v| v.store(value, order)); }
}

/// Walks the frame-pointer chain from `fp`, handing every value a compiled
/// frame's stack map describes to `f`. Frames without a map are skipped.
pub fn walk_compiled_roots(mut fp: usize, f: &mut dyn FnMut(u64)) {
    let maps = CODE_MAPS.lock().unwrap();
    let mut guard = 0;
    while fp != 0 && guard < 100_000 {
        guard += 1;
        let ret = unsafe { *((fp + 8) as *const usize) };
        for (start, end, entries) in maps.iter() {
            if ret >= *start && ret < *end {
                let off = (ret - start) as u32;
                if let Some((_, span, offsets)) = entries.iter().find(|(o, _, _)| *o == off) {
                    // The return address lies in the compiled caller; its frame
                    // pointer is the next link, and its SP at the call is that
                    // minus the frame span.
                    let caller_fp = unsafe { *(fp as *const usize) };
                    let sp = caller_fp - *span as usize;
                    for &o in offsets { f(unsafe { *((sp + o as usize) as *const u64) }); }
                }
            }
        }
        let next = unsafe { *(fp as *const usize) };
        if next <= fp { break; }
        fp = next;
    }
}

/// Native code must honor schema write invalidation introduced in ABI 4.
/// Old native stores can bypass it, so no v3 compatibility alias is exported.
pub const AOT_ABI: u32 = 4;

// Object code binds addresses through one versioned symbol. Refresh the view
// on every access: a helper can append an image and grow its runtime tables.
// Mutable data stays with the executing VM, including on worker threads.
#[unsafe(no_mangle)]
pub extern "C" fn nupp_vm_runtime_v4() -> u64 {
    let it = ctx();
    it.entries.resize(it.funcs.len(), 0);
    for f in &it.funcs[it.calltab.len()..] {
        let plain = f.sig.iter().all(|&c| c == b'v') && f.ret != b'f' && !f.vararg;
        it.calltab.push(f.nparams as u64 | ((plain as u64) << 8));
    }
    for f in &it.funcs[it.runtime_consts.len()..] {
        it.runtime_consts.push(f.consts.as_ptr() as u64);
    }
    for shape in &it.heap.shapes[it.shape_probe.len()..] {
        it.shape_probe.push((shape.table.as_ptr() as u64, shape.mask));
    }
    it.runtime_addresses = [
        closure_address(),
        it.extra.as_ptr() as u64,
        &it.last_nres as *const usize as u64,
        it.entries.as_ptr() as u64,
        it.calltab.as_ptr() as u64,
        it.shape_probe.as_ptr() as u64,
        it.runtime_consts.as_ptr() as u64,
    ];
    it.runtime_addresses.as_ptr() as u64
}

// The image fixes each function's site order; each VM owns the mutable bank.
// Boxes keep site addresses stable while loading more functions. Neither the
// cache words nor the runtime address view are captured in checkpoints.
#[unsafe(no_mangle)]
pub extern "C" fn j_field_caches(fid: u64, count: u64) -> u64 {
    let it = ctx();
    // Indexed by function id: this runs on every compiled entry, including each
    // resume after a call, so it must not hash.
    let fid = fid as usize;
    if it.field_caches.len() <= fid { it.field_caches.resize_with(fid + 1, || None); }
    let bank = it.field_caches[fid].get_or_insert_with(|| vec![[0; 2]; count as usize].into_boxed_slice());
    assert_eq!(bank.len(), count as usize);
    bank.as_mut_ptr() as u64
}

/// A transient view for native heap-frame calls. Generated code uses only
/// this C layout, never the layout of Rust's Vec or Interp. Reentrant helpers
/// refresh it before compiled code uses a task or entry-table pointer again.
#[repr(C)]
#[derive(Default)]
pub(crate) struct FrameContext {
    pub stack: u64,
    pub stack_len: u64,
    pub current: u64,
    pub entries: u64,
    pub info: u64,
    pub functions: u64,
    pub nested: u64,
    pub depth: u64,
    pub count: u64,
    pub direct: u64,
    pub nres: u64,
    pub extra: u64,
    pub extra_n: u64,
    pub enabled: u64,
    pub valid: u64,
}

/// An inline return, consumed only by the native caller that pushed the frame.
/// Ordinary driver entries cannot produce it.
pub(crate) const FRAME_RETURN: u64 = u64::MAX - 2;

#[unsafe(no_mangle)]
pub extern "C" fn j_frame_context() -> u64 {
    &*ctx().frame_context as *const FrameContext as u64
}

#[unsafe(no_mangle)]
pub extern "C" fn j_frame_refresh() -> u64 {
    let it = ctx();
    if it.frame_context.valid != 0 { return &*it.frame_context as *const FrameContext as u64; }
    for (fid, f) in it.funcs.iter().enumerate().skip(it.frame_info.len()) {
        // Coroutine wrappers share the unavailable thunk and must enter the
        // interpreter's wrapper dispatch even when that thunk is compiled.
        let plain = fid as u32 != it.unavailable_fid && !f.vararg && f.ret != b'f' && f.sig.iter().all(|&c| c == b'v');
        it.frame_info.push(f.nparams as u64 | ((plain as u64) << 8) | ((f.frame_words() as u64) << 16));
    }
    let unwinding = it.scheduler.as_ref().is_some_and(|s| s.controls.contains_key(&it.native_task))
        && it.unwind_state(it.native_task) != V::NIL;
    let enabled = it.instruction_budget.is_none() && !unwinding
        && it.jit_threshold == 0 && !it.trace && nesting_enabled();
    #[cfg(feature = "jit")]
    let enabled = enabled && !it.spec.frames;
    let task = &mut it.tasks[it.native_task];
    *it.frame_context = FrameContext {
        stack: task.stack.as_mut_ptr() as u64,
        stack_len: task.stack.len() as u64,
        current: task.current_address() as u64,
        entries: it.frame_entries.as_ptr() as u64,
        info: it.frame_info.as_ptr() as u64,
        functions: it.frame_entries.len().min(it.frame_info.len()) as u64,
        nested: &mut it.nested_calls as *mut usize as u64,
        depth: &mut it.native_frame_depth as *mut usize as u64,
        count: &mut it.compiled_frame_entries as *mut u64 as u64,
        direct: &mut it.direct_frame as *mut usize as u64,
        nres: &mut it.last_nres as *mut usize as u64,
        extra: it.extra.as_mut_ptr() as u64,
        extra_n: &mut it.extra_n as *mut usize as u64,
        enabled: enabled as u64,
        valid: 1,
    };
    &*it.frame_context as *const FrameContext as u64
}

/// Complete an uncommon callee exit (park, interpreter resume or cleanup).
/// The common inline return never enters Rust.
#[unsafe(no_mangle)]
pub extern "C" fn j_frame_finish(next: u64, stop: u64) -> u64 {
    let it = ctx();
    let depth = std::mem::replace(&mut it.native_frame_depth, 0);
    let result = it.guarded(|it| {
        let tid = it.native_task;
        match it.finish_callee(tid, stop as usize, next) {
            Ok(true) => V(frame_address(it, tid)),
            Ok(false) => V::ERROR,
            Err(exit) => { if matches!(exit, crate::interp::Step::Return(crate::interp::Outcome::Parked(_))) { it.compiled_frame_parks += 1; } it.native_exit = Some(exit); V(1) }
        }
    });
    it.native_frame_depth = depth;
    result.0
}

/// The helpers: name, address, arity.
pub fn helper_table() -> Vec<(&'static str, *const u8, usize)> {
    let table: Vec<(&'static str, *const u8, usize)> = vec![
        ("j_phys_guard",j_phys_guard as *const u8,4), ("j_phys_set",j_phys_set as *const u8,5), ("j_phys_read_slow",j_phys_read_slow as *const u8,4), ("j_phys_write_slow",j_phys_write_slow as *const u8,4),
        ("j_field_caches", j_field_caches as *const u8, 2),
        ("j_simd_prepare", j_simd_prepare as *const u8, 5), ("j_simd_prepare_locals", j_simd_prepare_locals as *const u8, 6), ("j_simd_finish", j_simd_finish as *const u8, 3), ("j_simd_store", j_simd_store as *const u8, 4),
        ("j_native_budget", j_native_budget as *const u8, 0),
        ("j_native_bounds_error", j_native_bounds_error as *const u8, 0),
        ("j_native_span", j_native_span as *const u8, 4), ("j_native_raise", j_native_raise as *const u8, 1),
        ("j_frame_poll", j_frame_poll as *const u8, 0),
        ("j_ibox", j_ibox as *const u8, 1), ("j_ubox", j_ubox as *const u8, 1), ("j_numeric", j_numeric as *const u8, 2),
        ("j_get_index_i", j_get_index_i as *const u8, 2), ("j_set_index_i", j_set_index_i as *const u8, 3),
        ("j_frame_context", j_frame_context as *const u8, 0), ("j_frame_refresh", j_frame_refresh as *const u8, 0), ("j_frame_finish", j_frame_finish as *const u8, 2),
        ("j_frame_step", j_frame_step as *const u8, 1), ("j_frame_call", j_frame_call as *const u8, 1), ("j_frame_ret", j_frame_ret as *const u8, 1),
        ("j_storage_ptr", j_storage_ptr as *const u8, 1), ("j_storage_len", j_storage_len as *const u8, 1), ("j_slot_hash", j_slot_hash as *const u8, 1),
        ("j_len_value", j_len_value as *const u8, 1), ("j_len_number", j_len_number as *const u8, 1),
        ("j_len", j_len as *const u8, 1), ("j_get_index", j_get_index as *const u8, 2), ("j_new_record", j_new_record as *const u8, 1), ("j_new_table", j_new_table as *const u8, 0),
        ("j_set_slot", j_set_slot as *const u8, 3), ("j_set_index", j_set_index as *const u8, 3), ("j_concat", j_concat as *const u8, 2), ("j_arith_slow", j_arith_slow as *const u8, 3),
        ("j_call_dyn", j_call_dyn as *const u8, 4), ("j_call_method", j_call_method as *const u8, 3), ("j_get_field", j_get_field as *const u8, 2), ("j_get_field_ic", j_get_field_ic as *const u8, 3), ("j_set_field", j_set_field as *const u8, 3),
        ("j_new_cell", j_new_cell as *const u8, 1), ("j_set_cell", j_set_cell as *const u8, 2), ("j_new_closure", j_new_closure as *const u8, 3), ("j_tagcheck_rec", j_tagcheck_rec as *const u8, 2), ("j_is_rec", j_is_rec as *const u8, 2), ("j_slot_get", j_slot_get as *const u8, 3), ("j_slot_set", j_slot_set as *const u8, 4), ("j_last_nres", j_last_nres as *const u8, 0), ("j_scalar", j_scalar as *const u8, 3), ("j_iter_next", j_iter_next as *const u8, 1), ("j_call_builtin", j_call_builtin as *const u8, 4), ("j_tagcheck_str", j_tagcheck_str as *const u8, 1),
        ("j_new_table_sized", j_new_table_sized as *const u8, 2), ("j_ret_extra", j_ret_extra as *const u8, 2), ("j_pcall", j_pcall as *const u8, 2), ("j_new_bytes", j_new_bytes as *const u8, 1), ("j_bytes_to_str", j_bytes_to_str as *const u8, 2),
        ("j_new_buffer", j_new_buffer as *const u8, 0), ("j_buf_append", j_buf_append as *const u8, 2), ("j_buf_append_sub", j_buf_append_sub as *const u8, 4), ("j_substring", j_substring as *const u8, 3), ("j_buf_finish", j_buf_finish as *const u8, 1),
        ("j_str_byte", j_str_byte as *const u8, 2), ("j_pow", j_pow as *const u8, 2), ("j_eq_slow", j_eq_slow as *const u8, 2), ("j_require", j_require as *const u8, 1), ("j_set_method", j_set_method as *const u8, 3),
    ];
    // Specialization helpers exist only where code is generated at run time.
    #[cfg(feature = "jit")]
    let table = table.into_iter().chain(crate::specialize::helpers()).collect();
    table
}

// Backedges yield a bounded worker turn without retaining native frames.
#[unsafe(no_mangle)]
pub extern "C" fn j_frame_poll() -> u64 {
    let it = ctx();
    if let Some(left) = it.instruction_budget.as_mut() {
        *left = left.saturating_sub(1);
        return (*left == 0) as u64;
    }
    0
}

// A frame operation that completes immediately stays in the native entry.
// Transfers are handed to the driver only after the native activation returns.
/// How many calls deep compiled frames run nested in native code before the
/// outermost driver takes over again. Each level holds a compiled activation
/// and the helper's own frames on the native stack.
pub(crate) const NESTED_CALL_LIMIT: usize = 96;

/// The calls whose callee may run nested: ordinary calls only, so a protected
/// call, a module load or a cleanup keeps the outermost driver's handling.
fn nested_call(op: &crate::interp::Op) -> bool {
    use crate::interp::Op;
    matches!(op, Op::Call(..) | Op::CallT(..) | Op::CallDyn(..) | Op::CallK(..) | Op::CallMethod(..))
}

/// The top frame's header address, which a stack that grew has moved.
fn frame_address(it: &mut Interp, tid: usize) -> u64 {
    let t = &mut it.tasks[tid];
    let cur = t.cur();
    unsafe { t.stack.as_mut_ptr().add(cur) as u64 }
}

/// `NO_NESTED=1` returns every call to the outermost driver, as before nesting.
fn nesting_enabled() -> bool {
    static ON: std::sync::OnceLock<bool> = std::sync::OnceLock::new();
    *ON.get_or_init(|| std::env::var_os("NO_NESTED").is_none())
}

/// A call boundary in a compiled frame: the ordinary call to a compiled
/// callee without the general step (`Interp::frame_call_fast`); the same
/// answers as `j_frame_step`, which takes every other case.
#[unsafe(no_mangle)]
pub extern "C" fn j_frame_call(pc: u64) -> u64 {
    let it = ctx();
    if it.instruction_budget.is_some() || it.nested_calls >= NESTED_CALL_LIMIT || !nesting_enabled() { return j_frame_step(pc); }
    let depth = std::mem::replace(&mut it.native_frame_depth, 0);
    let nested = it.nested_calls;
    let status = it.guarded(|it| {
        let tid = it.native_task;
        it.nested_calls += 1;
        match it.frame_call_fast(tid, pc as usize) {
            None => V(u64::MAX - 1),
            Some(Ok(true)) => V(frame_address(it, tid)),
            Some(Ok(false)) => V::ERROR,
            Some(Err(exit)) => { it.native_exit = Some(exit); V(1) }
        }
    }).0;
    it.nested_calls = nested;
    it.native_frame_depth = depth;
    if status == u64::MAX - 1 { return j_frame_step(pc); }
    status
}

/// A return boundary in a compiled frame: the frame popped directly when it
/// has nothing to clean up (`Interp::frame_ret_fast`), else `j_frame_step`.
#[unsafe(no_mangle)]
pub extern "C" fn j_frame_ret(pc: u64) -> u64 {
    let it = ctx();
    if it.instruction_budget.is_some() { return j_frame_step(pc); }
    let tid = it.native_task;
    if it.frame_ret_fast(tid, pc as usize) {
        it.native_exit = Some(crate::interp::Step::Reenter);
        return 1;
    }
    j_frame_step(pc)
}

#[unsafe(no_mangle)]
pub extern "C" fn j_frame_step(pc: u64) -> u64 {
    let it = ctx();
    // A boundary operation steps interpreted, its frame's pc and registers
    // current, so positions and operand names are exact while it runs.
    let depth = std::mem::replace(&mut it.native_frame_depth, 0);
    let nested = it.nested_calls;
    let status = it.guarded(|it| {
        let tid = it.native_task;
        let pc = pc as usize;
        if let Some(left) = it.instruction_budget.as_mut() {
            if *left == 0 {
                it.tasks[tid].note_pc(pc);
                it.native_exit = Some(crate::interp::Step::Return(crate::interp::Outcome::Parked(0)));
                return V(1);
            }
            *left -= 1;
        }
        let (win, _) = it.window(tid);
        let caller = it.tasks[tid].cur();
        let op = unsafe { *win.code.add(pc) };
        it.tasks[tid].note_pc(pc + 1);
        match it.step(tid, &win, pc) {
            crate::interp::Step::Next(next) => { assert_eq!(next, pc + 1); V(frame_address(it, tid)) }
            // A call that pushed a frame: run the callee from here, so the
            // caller continues in native code when it returns instead of
            // leaving for the driver and re-entering through its resume
            // dispatch. Past the nesting limit every native activation
            // returns, and the outermost driver resumes the frames flat.
            crate::interp::Step::Reenter if nested_call(&op) && it.tasks[tid].cur() > caller && nesting_enabled() => {
                if it.nested_calls >= NESTED_CALL_LIMIT {
                    it.unwind_nested = true;
                    it.native_exit = Some(crate::interp::Step::Reenter);
                    return V(1);
                }
                it.nested_calls += 1;
                match it.run_callee(tid, caller) {
                    Ok(true) => V(frame_address(it, tid)),
                    // A raise: its value is pending and the sentinel goes up.
                    Ok(false) => V::ERROR,
                    Err(exit) => { if matches!(exit, crate::interp::Step::Return(crate::interp::Outcome::Parked(_))) { it.compiled_frame_parks += 1; } it.native_exit = Some(exit); V(1) }
                }
            }
            exit => { if matches!(exit, crate::interp::Step::Return(crate::interp::Outcome::Parked(_))) { it.compiled_frame_parks += 1; } it.native_exit = Some(exit); V(1) }
        }
    }).0;
    it.nested_calls = nested;
    it.native_frame_depth = depth;
    status
}

// ---- runtime helpers --------------------------------------------------------
// Each helper is guarded: a raise inside becomes the ERROR sentinel (see
// `Interp::guarded`), which the compiled caller returns upward.
#[unsafe(no_mangle)]
pub extern "C" fn j_slot_hash(v: u64) -> u64 { crate::heap::slot_hash(v) }
#[unsafe(no_mangle)]
pub extern "C" fn j_storage_ptr(v: u64) -> u64 { let it = ctx(); it.guarded(|_| V(j_storage_ptr_impl(v))).0 }
#[unsafe(no_mangle)]
pub extern "C" fn j_storage_len(v: u64) -> u64 { let it = ctx(); it.guarded(|_| V(j_storage_len_impl(v))).0 }
#[unsafe(no_mangle)]
pub extern "C" fn j_len(v: u64) -> u64 { let it = ctx(); it.guarded(|_| V(j_len_impl(v))).0 }
// Keep j_len's raw-count ABI for existing object files. New lowering uses
// separately named helpers whose result is a boxed value or boxed double.
#[unsafe(no_mangle)]
pub extern "C" fn j_len_value(v: u64) -> u64 { ctx().guarded(|_| j_len_value_impl(v, false)).0 }
#[unsafe(no_mangle)]
pub extern "C" fn j_len_number(v: u64) -> u64 { ctx().guarded(|_| j_len_value_impl(v, true)).0 }
#[unsafe(no_mangle)]
pub extern "C" fn j_get_index(t: u64, k: u64) -> u64 { let it = ctx(); it.guarded(|_| V(j_get_index_impl(t, k))).0 }
#[unsafe(no_mangle)]
pub extern "C" fn j_new_record(shape: u64) -> u64 { let it = ctx(); it.guarded(|_| V(j_new_record_impl(shape))).0 }
#[unsafe(no_mangle)]
pub extern "C" fn j_new_table() -> u64 { let it = ctx(); it.guarded(|_| V(j_new_table_impl())).0 }
#[unsafe(no_mangle)]
pub extern "C" fn j_new_table_sized(n: u64, m: u64) -> u64 { let it = ctx(); it.guarded(|_| V(j_new_table_sized_impl(n, m))).0 }
#[unsafe(no_mangle)]
pub extern "C" fn j_set_slot(obj: u64, i: u64, v: u64) -> u64 { let it = ctx(); it.guarded(|_| V(j_set_slot_impl(obj, i, v))).0 }
#[unsafe(no_mangle)]
pub extern "C" fn j_set_index(t: u64, k: u64, v: u64) -> u64 { let it = ctx(); it.guarded(|_| V(j_set_index_impl(t, k, v))).0 }
#[unsafe(no_mangle)]
pub extern "C" fn j_concat(a: u64, b: u64) -> u64 { let it = ctx(); it.guarded(|_| V(j_concat_impl(a, b))).0 }
#[unsafe(no_mangle)]
pub extern "C" fn j_arith_slow(a: u64, b: u64, op: u64) -> u64 { let it = ctx(); it.guarded(|_| V(j_arith_slow_impl(a, b, op))).0 }
#[unsafe(no_mangle)]
pub extern "C" fn j_call_dyn(callee: u64, argv: *const u64, nargs: u64, fid: u64) -> u64 { let it = ctx(); let _caller = it.enter_caller(crate::interp::Caller::Compiled(fid as u32)); let r = it.guarded(|_| V(j_call_dyn_impl(callee, argv, nargs))).0; r }
#[unsafe(no_mangle)]
pub extern "C" fn j_call_method(name: u64, argv: *const u64, nargs: u64) -> u64 { let it = ctx(); it.guarded(|_| V(j_call_method_impl(name, argv, nargs))).0 }
#[unsafe(no_mangle)]
pub extern "C" fn j_pcall(argv: *const u64, nargs: u64) -> u64 { let it = ctx(); it.guarded(|_| V(j_pcall_impl(argv, nargs))).0 }
#[unsafe(no_mangle)]
pub extern "C" fn j_get_field(t: u64, name: u64) -> u64 { let it = ctx(); it.guarded(|_| V(j_get_field_impl(t, name))).0 }
#[unsafe(no_mangle)]
pub extern "C" fn j_get_field_ic(t: u64, name: u64, cache: *mut u64) -> u64 { let it = ctx(); it.guarded(|_| V(j_get_field_ic_impl(t, name, cache))).0 }
#[unsafe(no_mangle)]
pub extern "C" fn j_set_field(t: u64, name: u64, v: u64) -> u64 { let it = ctx(); it.guarded(|_| V(j_set_field_impl(t, name, v))).0 }
#[unsafe(no_mangle)]
pub extern "C" fn j_new_cell(v: u64) -> u64 { let it = ctx(); it.guarded(|_| V(j_new_cell_impl(v))).0 }
#[unsafe(no_mangle)]
pub extern "C" fn j_set_cell(c: u64, v: u64) -> u64 { let it = ctx(); it.guarded(|_| V(j_set_cell_impl(c, v))).0 }
#[unsafe(no_mangle)]
pub extern "C" fn j_new_closure(fid: u64, argv: *const u64, n: u64) -> u64 { let it = ctx(); it.guarded(|_| V(j_new_closure_impl(fid, argv, n))).0 }
#[unsafe(no_mangle)]
pub extern "C" fn j_call_builtin(id: u64, argv: *const u64, nargs: u64, fid: u64) -> u64 { let it = ctx(); let _caller = it.enter_caller(crate::interp::Caller::Compiled(fid as u32)); let r = it.guarded(|_| V(j_call_builtin_impl(id, argv, nargs))).0; r }
#[unsafe(no_mangle)]
pub extern "C" fn j_scalar(kind: u64, a: u64, b: u64) -> u64 { let it = ctx(); it.guarded(|it| { let (x, y) = (V(a), V(b)); if !x.is_num() || !y.is_num() { it.err("scalar intrinsic on a non-number") } V::num(crate::builtins::scalar_op(kind as u8, x.as_num(), y.as_num())) }).0 }
/// An iterator object called from compiled code: the step, its first result
/// returned and the rest through `extra`.
#[unsafe(no_mangle)]
pub extern "C" fn j_iter_next(iter: u64) -> u64 { let it = ctx(); it.guarded(|_| V(j_iter_next_impl(iter))).0 }
#[unsafe(no_mangle)]
// PadResults consumes the spill immediately after this nonallocating call.
pub extern "C" fn j_last_nres() -> u64 { let it = ctx(); it.extra_n = 0; it.last_nres as u64 }
#[unsafe(no_mangle)]
pub extern "C" fn j_slot_get(o: u64, shape: u64, slot: u64) -> u64 { let it = ctx(); it.guarded(|_| V(j_slot_get_impl(o, shape, slot))).0 }
#[unsafe(no_mangle)]
pub extern "C" fn j_slot_set(o: u64, shape: u64, slot: u64, v: u64) -> u64 { let it = ctx(); it.guarded(|_| V(j_slot_set_impl(o, shape, slot, v))).0 }
#[unsafe(no_mangle)]
pub extern "C" fn j_is_rec(v: u64, shape: u64) -> u64 { V::boolean(ctx().is_rec(V(v), shape as u32)).0 }
#[unsafe(no_mangle)]
pub extern "C" fn j_tagcheck_rec(v: u64, shape: u64) -> u64 { let it = ctx(); it.guarded(|_| V(j_tagcheck_rec_impl(v, shape))).0 }
#[unsafe(no_mangle)]
pub extern "C" fn j_tagcheck_str(v: u64) -> u64 { let it = ctx(); it.guarded(|_| V(j_tagcheck_str_impl(v))).0 }
#[unsafe(no_mangle)]
pub extern "C" fn j_ret_extra(argv: *const u64, n: u64) -> u64 { let it = ctx(); it.guarded(|_| V(j_ret_extra_impl(argv, n))).0 }
#[unsafe(no_mangle)]
pub extern "C" fn j_new_bytes(n: u64) -> u64 { let it = ctx(); it.guarded(|_| V(j_new_bytes_impl(n))).0 }
#[unsafe(no_mangle)]
pub extern "C" fn j_bytes_to_str(s: u64, n: u64) -> u64 { let it = ctx(); it.guarded(|_| V(j_bytes_to_str_impl(s, n))).0 }
#[unsafe(no_mangle)]
pub extern "C" fn j_new_buffer() -> u64 { let it = ctx(); it.guarded(|_| V(j_new_buffer_impl())).0 }
#[unsafe(no_mangle)]
pub extern "C" fn j_buf_append(buf: u64, s: u64) -> u64 { let it = ctx(); it.guarded(|_| V(j_buf_append_impl(buf, s))).0 }
#[unsafe(no_mangle)]
pub extern "C" fn j_buf_append_sub(buf: u64, s: u64, i: u64, j: u64) -> u64 { let it = ctx(); it.guarded(|_| V(j_buf_append_sub_impl(buf, s, i, j))).0 }
#[unsafe(no_mangle)]
pub extern "C" fn j_substring(s: u64, i: u64, j: u64) -> u64 { let it = ctx(); it.guarded(|_| V(j_substring_impl(s, i, j))).0 }
#[unsafe(no_mangle)]
pub extern "C" fn j_buf_finish(buf: u64) -> u64 { let it = ctx(); it.guarded(|_| V(j_buf_finish_impl(buf))).0 }
#[unsafe(no_mangle)]
pub extern "C" fn j_str_byte(s: u64, i: u64) -> u64 { let it = ctx(); it.guarded(|_| V(j_str_byte_impl(s, i))).0 }
#[unsafe(no_mangle)]
pub extern "C" fn j_eq_slow(a: u64, b: u64) -> u64 { let it = ctx(); it.guarded(|_| V(j_eq_slow_impl(a, b))).0 }
#[unsafe(no_mangle)]
pub extern "C" fn j_require(name: u64) -> u64 { let it = ctx(); it.guarded(|_| V(j_require_impl(name))).0 }
#[unsafe(no_mangle)]
pub extern "C" fn j_set_method(shape: u64, name: u64, f: u64) -> u64 { let it = ctx(); it.guarded(|_| V(j_set_method_impl(shape, name, f))).0 }

// Each records the frame pointer it was entered with, so the collector walks
// the compiled frames above it (4.5), and restores the previous one on exit:
// helpers nest when a callback runs compiled code.

fn ctx() -> &'static mut Interp { unsafe { &mut *CTX.load(std::sync::atomic::Ordering::Relaxed) } }
// Restore the root-walk entry on raises as well as ordinary returns. A hook
// may catch a callback error and allocate again while the outer helper lives.
struct HelperFrame(usize);
impl Drop for HelperFrame {
    fn drop(&mut self) { HELPER_FP.store(self.0, std::sync::atomic::Ordering::Relaxed); }
}
macro_rules! enter_helper { () => {{ let fp: usize; unsafe { std::arch::asm!("mov {}, x29", out(reg) fp) }; HelperFrame(HELPER_FP.swap(fp, std::sync::atomic::Ordering::Relaxed)) }} }
macro_rules! leave_helper { ($prev:expr) => { drop($prev) } }

#[unsafe(no_mangle)]
pub extern "C" fn j_phys_guard(object:u64, identity:u64, name:u64, packed:u64)->u64 {
    crate::storage::physical_address(ctx(),V(object),V(identity),V(name),packed).map(|p|p as u64).unwrap_or(0)
}
#[unsafe(no_mangle)]
pub extern "C" fn j_phys_set(object:u64, identity:u64, name:u64, packed:u64, value:u64)->u64 {
    ctx().guarded(|it| { let _hp=enter_helper!();
        let plan=crate::storage::PhysicalField {identity:0,name:0,ordinal:(packed>>32) as u16,offset:packed as u32,kind:(packed>>48) as u8};
        crate::storage::physical_set(it,V(object),V(identity),V(name),plan,V(value)); V::NIL
    }).0
}
#[unsafe(no_mangle)]
pub extern "C" fn j_phys_read_slow(object:u64,name:u64,carrier:u64,out:*mut u64)->u64 {
    ctx().guarded(|it| { let _hp=enter_helper!(); let value=it.index(V(object),V(name));
        let bits=match carrier {1=>crate::numeric::double(it,value).to_bits(),2=>crate::numeric::bits(it,value,false),3=>crate::numeric::bits(it,value,true),_=>unreachable!()};
        unsafe{out.write(bits);} V::NIL
    }).0
}
#[unsafe(no_mangle)]
pub extern "C" fn j_phys_write_slow(object:u64,name:u64,bits:u64,kind:u64)->u64 {
    ctx().guarded(|it| { let _hp=enter_helper!();
        let value=if kind>=9 {V::num(f64::from_bits(bits))}else{it.box_integer(crate::numeric::Integer {bits,unsigned:kind==8})};
        let scope=it.open_scope(); it.handles.extend_from_slice(&[V(object),value]);
        let result=std::panic::catch_unwind(std::panic::AssertUnwindSafe(||it.store_field(V(object),V(name),value)));
        it.close_scope(scope); if let Err(error)=result {std::panic::resume_unwind(error);} V::NIL
    }).0
}

#[unsafe(no_mangle)]
pub extern "C" fn j_simd_prepare(op: u64, kind: u64, argv: *const V, n: u64, packet: *mut crate::simd::Packet) -> u64 {
    let _hp = enter_helper!();
    ctx().guarded(|vm| {
        let args = unsafe { std::slice::from_raw_parts(argv, n as usize) };
        crate::simd::prepare(vm, op as u8, kind as u8, (op >> 8) as u8, args, unsafe { &mut *packet });
        vm.extra_n = 0; vm.last_nres = 1;
        V::NIL
    }).0
}
// Pointers refer only to earlier native stack packets in this activation.
// They never enter a Value, a GC root, or a suspended heap frame.
#[unsafe(no_mangle)]
pub extern "C" fn j_simd_prepare_locals(op: u64, kind: u64, argv: *const V, n: u64, packet: *mut crate::simd::Packet, localv: *const *const crate::simd::Packet) -> u64 {
    let _hp = enter_helper!();
    ctx().guarded(|vm| {
        assert!(n <= 5);
        let args = unsafe { std::slice::from_raw_parts(argv, n as usize) };
        let mut locals = [None; 5];
        for i in 0..n as usize { locals[i] = unsafe { (*localv.add(i)).as_ref() }; }
        crate::simd::prepare_locals(vm, op as u8, kind as u8, (op >> 8) as u8, args, &locals[..n as usize], unsafe { &mut *packet });
        vm.extra_n = 0; vm.last_nres = 1;
        V::NIL
    }).0
}
#[unsafe(no_mangle)]
pub extern "C" fn j_simd_store(kind: u64, argv: *const V, n: u64, localv: *const *const crate::simd::Packet) -> u64 {
    let _hp = enter_helper!();
    ctx().guarded(|vm| {
        assert!(n <= 5);
        let args = unsafe { std::slice::from_raw_parts(argv, n as usize) };
        let mut locals = [None; 5];
        if !localv.is_null() {
            for i in 0..n as usize { locals[i] = unsafe { (*localv.add(i)).as_ref() }; }
        }
        crate::simd::store(vm, kind as u8, args, &locals[..n as usize]);
        vm.extra_n = 0; vm.last_nres = 1;
        V::NIL
    }).0
}
#[unsafe(no_mangle)]
pub extern "C" fn j_simd_finish(packet: *const crate::simd::Packet, argv: *const V, n: u64) -> u64 {
    let _hp = enter_helper!();
    ctx().guarded(|vm| {
        let args = unsafe { std::slice::from_raw_parts(argv, n as usize) };
        vm.extra_n = 0; vm.last_nres = 1;
        crate::simd::finish(vm, unsafe { &*packet }, args)
    }).0
}

fn j_storage_ptr_impl(v: u64) -> u64 { match V(v).as_obj() { Some(p) => unsafe { (*p.as_ptr()).aux_ptr as u64 }, None => 0 } }
fn j_storage_len_impl(v: u64) -> u64 { match V(v).as_obj() { Some(p) => unsafe { (*p.as_ptr()).aux_len }, None => 0 } }
fn j_len_value_impl(v: u64, number: bool) -> V {
    let _hp = enter_helper!();
    let it = ctx();
    let value = it.length(V(v));
    if number { V::num(crate::numeric::double(it, value)) } else { value }
}
fn j_len_impl(v: u64) -> u64 { let it = ctx(); match it.kind_of(V(v)) { Some(KIND_TABLE) | Some(KIND_RECORD) => it.array_len(V(v)) as u64, _ => it.bytes_of(V(v)).len() as u64 } }
fn j_get_index_impl(t: u64, k: u64) -> u64 { let _hp = enter_helper!(); let it = ctx(); it.index_any(V(t), V(k)).0 }
fn j_new_record_impl(shape: u64) -> u64 { let _hp = enter_helper!(); let v = ctx().new_record(shape as u32); leave_helper!(_hp); v.0 }
fn j_new_table_impl() -> u64 { let _hp = enter_helper!(); let v = ctx().new_table(); leave_helper!(_hp); v.0 }
fn j_new_table_sized_impl(n: u64, m: u64) -> u64 { let _hp = enter_helper!(); let v = ctx().new_table_sized(n as usize, m as usize); leave_helper!(_hp); v.0 }
fn j_set_slot_impl(obj: u64, i: u64, v: u64) -> u64 { ctx().set_slot(V(obj), i as usize, V(v)); 0 }
fn j_set_index_impl(t: u64, k: u64, v: u64) -> u64 { let _hp = enter_helper!(); let it = ctx(); let t = V(t); let k = it.key_for_store(V(k)); it.newindex(t, k, V(v)); leave_helper!(_hp); 0 }
fn j_concat_impl(a: u64, b: u64) -> u64 { let _hp = enter_helper!(); let v = ctx().concat(V(a), V(b)); leave_helper!(_hp); v.0 }
/// Arithmetic and comparison past the number fast path: strings compare by
/// content (codes 3 and 4 answer a boolean word); anything else is an error.
fn j_arith_slow_impl(a: u64, b: u64, op: u64) -> u64 {
    let _hp = enter_helper!();
    let it = ctx(); let (x, y) = (V(a), V(b));
    if matches!(op, 3 | 4) && !(crate::numeric::is_numeric(x) && crate::numeric::is_numeric(y)) {
        return it.order(x, y, op == 4).0;
    }
    crate::numeric::binary(it, x, y, ["add", "sub", "mul", "lt", "le", "div", "mod", "idiv"][op as usize], None).0
}
#[unsafe(no_mangle)]
pub extern "C" fn j_ibox(bits: u64) -> u64 { ctx().guarded(|_| { let _hp = enter_helper!(); ctx().box_integer(crate::numeric::Integer { bits, unsigned: false }) }).0 }
#[unsafe(no_mangle)]
pub extern "C" fn j_ubox(bits: u64) -> u64 { ctx().guarded(|_| { let _hp = enter_helper!(); ctx().box_integer(crate::numeric::Integer { bits, unsigned: true }) }).0 }

#[unsafe(no_mangle)]
pub extern "C" fn j_numeric(v: u64, op: u64) -> u64 { ctx().guarded(|_| {
    let _hp = enter_helper!(); let it = ctx(); let v = V(v);
    match op {
        0 => V::num(crate::numeric::double(it, v)),
        1 | 6 => { crate::numeric::bits(it, v, op == 6); v },
        4 | 5 => crate::numeric::check_kind(it, v, op == 5),
        2 => { if !v.is_num() { it.err("value is not a number"); } v },
        _ => crate::numeric::negate(it, v),
    }
}).0 }
#[unsafe(no_mangle)]
pub extern "C" fn j_get_index_i(t: u64, bits: u64) -> u64 { ctx().guarded(|_| {
    let _hp = enter_helper!(); let it = ctx();
    let key = it.box_integer(crate::numeric::Integer { bits, unsigned: false });
    it.index_any(V(t), key)
}).0 }
#[unsafe(no_mangle)]
pub extern "C" fn j_set_index_i(t: u64, bits: u64, v: u64) -> u64 { ctx().guarded(|_| {
    let _hp = enter_helper!(); let it = ctx();
    let key = it.box_integer(crate::numeric::Integer { bits, unsigned: false });
    let scope = it.open_scope(); it.handles.push(key); it.newindex(V(t), key, V(v)); it.close_scope(scope); V::NIL
}).0 }

fn j_iter_next_impl(iter: u64) -> u64 {
    let _hp = enter_helper!();
    let it = ctx();
    let outs = crate::builtins::iter_next(it, V(iter));
    let first = outs.first().copied().unwrap_or(V::NIL);
    it.extra_n = outs.len().saturating_sub(1).min(crate::interp::MAX_RESULTS - 1); for i in 0..it.extra_n { it.extra[i] = outs[i + 1]; }
    it.last_nres = outs.len().min(crate::interp::MAX_RESULTS);
    leave_helper!(_hp);
    first.0
}
fn j_call_builtin_impl(id: u64, argv: *const u64, nargs: u64) -> u64 {
    let _hp = enter_helper!();
    let it = ctx();
    let args: &[V] = unsafe { std::slice::from_raw_parts(argv as *const V, nargs as usize) };
    let scope = it.open_scope(); for &a in args { it.handles.push(a); }
    // A host service may park, which compiled code cannot do: the runtime path.
    let outs = if id as u32 >= crate::host::HOST_BASE { it.call_outs(V::builtin(id as u32), args) } else { crate::builtins::call(it, id as u32, args) };
    it.close_scope(scope);
    let first = outs.first().copied().unwrap_or(V::NIL);
    it.extra_n = outs.len().saturating_sub(1).min(crate::interp::MAX_RESULTS - 1); for i in 0..it.extra_n { it.extra[i] = outs[i + 1]; }
    it.last_nres = outs.len().min(crate::interp::MAX_RESULTS);
    leave_helper!(_hp);
    first.0
}
// Compiled call sites reserve eight register results, with the remaining
// values in the interpreter's result pack.
fn compiled_args<'a>(it: &Interp, argv: *const u64, nargs: u64) -> std::borrow::Cow<'a, [V]> {
    if (64..128).contains(&nargs) {
        std::borrow::Cow::Owned(it.result_pack((nargs & 63) as usize, |i| V(unsafe { *argv.add(i) })))
    } else {
        // The generated call keeps this argument area alive until the helper
        // returns. Fixed packs can keep borrowing it without allocating.
        std::borrow::Cow::Borrowed(unsafe { std::slice::from_raw_parts(argv.cast::<V>(), (nargs & 127) as usize) })
    }
}
fn j_call_dyn_impl(callee: u64, argv: *const u64, nargs: u64) -> u64 {
    let _hp = enter_helper!();
    let it = ctx();
    let values = compiled_args(it, argv, nargs);
    let args = values.as_ref();
    let scope = it.open_scope(); for &a in args { it.handles.push(a); } it.handles.push(V(callee));
    if nargs >= 128 { it.err("a spread call from compiled code"); }
    let outs = it.call_outs(V(callee), args);
    it.close_scope(scope);
    let first = outs.first().copied().unwrap_or(V::NIL);
    it.extra_n = outs.len().saturating_sub(1).min(crate::interp::MAX_RESULTS - 1); for i in 0..it.extra_n { it.extra[i] = outs[i + 1]; }
    it.last_nres = outs.len().min(crate::interp::MAX_RESULTS);
    leave_helper!(_hp);
    first.0
}
fn j_call_method_impl(name: u64, argv: *const u64, nargs: u64) -> u64 {
    let _hp = enter_helper!();
    let it = ctx();
    let values = compiled_args(it, argv, nargs);
    let args = values.as_ref();
    let scope = it.open_scope(); for &a in args { it.handles.push(a); }
    let outs = it.call_method(V(name), args);
    it.close_scope(scope);
    let first = outs.first().copied().unwrap_or(V::NIL);
    it.extra_n = outs.len().saturating_sub(1).min(crate::interp::MAX_RESULTS - 1); for i in 0..it.extra_n { it.extra[i] = outs[i + 1]; }
    it.last_nres = outs.len().min(crate::interp::MAX_RESULTS);
    leave_helper!(_hp);
    first.0
}
fn j_pcall_impl(argv: *const u64, nargs: u64) -> u64 {
    let _hp = enter_helper!();
    let it = ctx();
    let args = compiled_args(it, argv, nargs);
    let scope = it.open_scope(); for &a in args.iter() { it.handles.push(a); }
    let outs = it.pcall_values(args[0], &args[1..]);
    it.close_scope(scope);
    it.extra_n = outs.len().saturating_sub(1).min(crate::interp::MAX_RESULTS - 1); for i in 0..it.extra_n { it.extra[i] = outs[i + 1]; }
    it.last_nres = outs.len().min(crate::interp::MAX_RESULTS);
    leave_helper!(_hp);
    outs[0].0
}
fn j_get_field_impl(t: u64, name: u64) -> u64 { let _hp = enter_helper!(); ctx().field(V(t), V(name)).0 }
/// A field read that missed its site cache: resolve by name and, for a
/// record whose shape names the field, remember the shape and slot.
pub static IC_STATS: [std::sync::atomic::AtomicU64; 8] = [const { std::sync::atomic::AtomicU64::new(0) }; 8];
pub static INTERP_CALLEES: std::sync::Mutex<Option<std::collections::HashMap<u32, u64>>> = std::sync::Mutex::new(None);
pub static IC_SITES: std::sync::Mutex<Option<std::collections::HashMap<usize, std::collections::HashSet<u32>>>> = std::sync::Mutex::new(None);
fn j_get_field_ic_impl(t: u64, name: u64, cache: *mut u64) -> u64 {
    let _hp = enter_helper!();
    let it = ctx(); let tv = V(t);
    if it.ic_stats { let kind = tv.as_obj().map(|p| unsafe { (*p.as_ptr()).kind }); let i = match kind { Some(KIND_RECORD) => if unsafe { *cache } == 0 { 0 } else { 1 }, Some(KIND_TABLE) => 2, _ => 3 }; IC_STATS[i].fetch_add(1, std::sync::atomic::Ordering::Relaxed); if kind == Some(KIND_RECORD) { let sh = unsafe { (*tv.as_obj().unwrap().as_ptr()).shape() }; let mut g = IC_SITES.lock().unwrap(); g.get_or_insert_with(Default::default).entry(cache as usize).or_default().insert(sh); } }
    if let Some(p) = tv.as_obj() {
        let h = unsafe { &*p.as_ptr() };
        // A record with a metatable of its own caches its slot too; the site
        // answers a present value and asks again on nil.
        if h.kind == KIND_RECORD { let sh = &it.heap.shapes[h.shape() as usize]; if let Some(i) = sh.slot_of(V(name)) { unsafe { *cache = h.shape() as u64 + 1; *cache.add(1) = i as u64; } let v = h.slots()[i]; if v != V::NIL || h.flags & crate::heap::F_METATABLE == 0 { return v.0; } } }
    }
    it.field(tv, V(name)).0
}
fn j_set_field_impl(t: u64, name: u64, v: u64) -> u64 { let _hp = enter_helper!(); ctx().store_field(V(t), V(name), V(v)); leave_helper!(_hp); 0 }
fn j_new_cell_impl(v: u64) -> u64 { let _hp = enter_helper!(); let it = ctx(); let scope = it.open_scope(); it.handles.push(V(v)); let c = it.new_cell(V(v)); it.close_scope(scope); leave_helper!(_hp); c.0 }
fn j_set_cell_impl(c: u64, v: u64) -> u64 { ctx().set_cell(V(c), V(v)); 0 }
fn j_new_closure_impl(fid: u64, argv: *const u64, n: u64) -> u64 { let _hp = enter_helper!(); let it = ctx(); let caps: Vec<V> = (0..n as usize).map(|i| V(unsafe { *argv.add(i) })).collect(); let scope = it.open_scope(); for &c in &caps { it.handles.push(c); } let v = it.new_closure(fid as u32, &caps); it.close_scope(scope); leave_helper!(_hp); v.0 }
fn j_slot_get_impl(o: u64, shape: u64, slot: u64) -> u64 { let it = ctx(); let v = V(o); if let Some(p) = v.as_obj() { let h = unsafe { &*p.as_ptr() }; if h.kind == KIND_RECORD && h.shape() == shape as u32 && (h.flags & crate::heap::F_METATABLE == 0 || h.slots()[slot as usize] != V::NIL) { return h.slots()[slot as usize].0; } } it.slot_get_slow(v, shape as u32, slot as u16).0 }
fn j_slot_set_impl(o: u64, shape: u64, slot: u64, v: u64) -> u64 { let it = ctx(); let ov = V(o); if let Some(p) = ov.as_obj() { let h = unsafe { &*p.as_ptr() }; if h.kind == KIND_RECORD && h.shape() == shape as u32 && (h.flags & crate::heap::F_METATABLE == 0 || (h.slots()[slot as usize] != V::NIL && h.flags & crate::heap::F_STORAGE_SCHEMA == 0)) { it.set_slot(ov, slot as usize, V(v)); return 0; } } it.slot_set_slow(ov, shape as u32, slot as u16, V(v)); 0 }
fn j_tagcheck_rec_impl(v: u64, shape: u64) -> u64 { ctx().tagcheck_rec(V(v), shape as u32); 0 }
fn j_tagcheck_str_impl(v: u64) -> u64 { let it = ctx(); if !it.is_stringish(V(v)) { it.err("value is not a string") } 0 }
/// Results past the first of a compiled return: `n` plain values from
/// `argv`, or, with 128 set, `n & 127` fixed values followed by what the
/// last call delivered (which still sits in `extra` from that call).
fn j_ret_extra_impl(argv: *const u64, n: u64) -> u64 {
    let it = ctx();
    if n == 256 { it.extra_n = 0; it.last_nres = 0; return 0; }
    if n >= 128 {
        // argv[i] is register start+i: the fixed values first, then the call's
        // results, which the call lowering read back into the registers that
        // follow. The first of them all is the function's own return value.
        let fixed = (n & 127) as usize;
        let values = it.result_pack(fixed, |i| V(unsafe { *argv.add(i) }));
        it.extra_n = values.len().saturating_sub(1).min(crate::interp::MAX_RESULTS - 1);
        if it.extra_n > 0 { it.extra[..it.extra_n].copy_from_slice(&values[1..1 + it.extra_n]); }
        it.last_nres = values.len().min(crate::interp::MAX_RESULTS);
        return 0;
    }
    it.extra_n = (n as usize).min(crate::interp::MAX_RESULTS - 1); for i in 0..it.extra_n { it.extra[i] = V(unsafe { *argv.add(i) }); }
    it.last_nres = it.extra_n + 1;
    0
}
fn j_new_bytes_impl(n: u64) -> u64 { let _hp = enter_helper!(); let v = ctx().heap_new_bytes(n as usize); leave_helper!(_hp); v.0 }
fn j_bytes_to_str_impl(s: u64, n: u64) -> u64 { let _hp = enter_helper!(); let it = ctx(); let text = it.bytes_of(V(s))[..n as usize].to_vec(); let v = it.string_of(&text); leave_helper!(_hp); v.0 }
fn j_new_buffer_impl() -> u64 { let _hp = enter_helper!(); let v = ctx().heap_new_buffer(); leave_helper!(_hp); v.0 }
fn j_buf_append_impl(buf: u64, s: u64) -> u64 { let it = ctx(); let t = it.bytes_of(V(s)).to_vec(); it.buf_append(V(buf), &t); 0 }
fn j_buf_append_sub_impl(buf: u64, s: u64, i: u64, j: u64) -> u64 { let it = ctx(); let t = it.sub_bytes(V(s), i as i64, j as i64).to_vec(); it.buf_append(V(buf), &t); 0 }
fn j_substring_impl(s: u64, i: u64, j: u64) -> u64 { let _hp = enter_helper!(); let it = ctx(); let t = it.sub_bytes(V(s), i as i64, j as i64).to_vec(); let v = it.string_of(&t); leave_helper!(_hp); v.0 }
fn j_buf_finish_impl(buf: u64) -> u64 { let _hp = enter_helper!(); let v = ctx().buf_finish(V(buf)); leave_helper!(_hp); v.0 }
fn j_str_byte_impl(s: u64, i: u64) -> u64 { ctx().str_byte(V(s), i as i64).0 }
fn j_pow_impl(a: u64, b: u64) -> u64 { let _hp = enter_helper!(); crate::numeric::binary(ctx(), V(a), V(b), "pow", None).0 }
#[unsafe(no_mangle)]
pub extern "C" fn j_pow(a: u64, b: u64) -> u64 { let it = ctx(); it.guarded(|_| V(j_pow_impl(a, b))).0 }
fn j_eq_slow_impl(a: u64, b: u64) -> u64 { let _hp = enter_helper!(); let e = ctx().equals(V(a), V(b)); leave_helper!(_hp); e as u64 }
fn j_require_impl(name: u64) -> u64 { let _hp = enter_helper!(); let it = ctx(); let text = String::from_utf8_lossy(it.bytes_of(V(name))).into_owned(); let v = it.require(&text); leave_helper!(_hp); v.0 }
fn j_set_method_impl(shape: u64, name: u64, f: u64) -> u64 { ctx().set_method(shape as u32, V(name), V(f)); 0 }

#[unsafe(no_mangle)]
pub extern "C" fn j_native_span(span: u64, kind: u64, write: u64, out: *mut usize) -> u64 {
    let _hp = enter_helper!();
    let r = ctx().guarded(|it| {
        let (ptr,n) = crate::storage::native_span(it,V(span),kind as u8,write != 0);
        unsafe { *out = ptr as usize; *out.add(1) = n; }
        V::NIL
    }).0;
    leave_helper!(_hp);
    r
}
#[unsafe(no_mangle)]
pub extern "C" fn j_native_raise(value: u64) -> u64 {
    let _hp = enter_helper!();
    let r = ctx().guarded(|_| { std::panic::panic_any(crate::builtins::LuaError(value)); }).0;
    leave_helper!(_hp);
    r
}

#[unsafe(no_mangle)]
pub extern "C" fn j_native_bounds_error() -> u64 {
    let _hp = enter_helper!();
    let r = ctx().guarded(|it| { it.err("SIMD span index out of bounds"); }).0;
    leave_helper!(_hp);
    r
}

#[unsafe(no_mangle)]
pub extern "C" fn j_native_budget() -> u64 {
    ctx().instruction_budget.as_mut().map_or(0, |n| n as *mut usize as u64)
}
