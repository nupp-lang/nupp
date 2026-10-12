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

/// Object code asks the current thread's VM for addresses. No process-global
/// mutable address table is shared by parent and worker heaps.
#[unsafe(no_mangle)]
pub extern "C" fn nupp_vm_runtime_v2(slot: u64) -> u64 {
    let it = ctx();
    match slot {
        0 => closure_address(),
        1 => it.extra.as_ptr() as u64,
        2 => &it.last_nres as *const usize as u64,
        3 => it.entries.as_ptr() as u64,
        4 => it.calltab.as_ptr() as u64,
        5 => it.shape_probe.as_ptr() as u64,
        6 => it.runtime_consts.as_ptr() as u64,
        _ => unreachable!("invalid runtime address slot"),
    }
}

/// The helpers: name, address, arity.
pub fn helper_table() -> Vec<(&'static str, *const u8, usize)> {
    vec![
        ("j_frame_poll", j_frame_poll as *const u8, 0),
        ("j_frame_step", j_frame_step as *const u8, 1),
        ("j_storage_ptr", j_storage_ptr as *const u8, 1), ("j_storage_len", j_storage_len as *const u8, 1), ("j_slot_hash", j_slot_hash as *const u8, 1),
        ("j_len", j_len as *const u8, 1), ("j_get_index", j_get_index as *const u8, 2), ("j_new_record", j_new_record as *const u8, 1), ("j_new_table", j_new_table as *const u8, 0),
        ("j_set_slot", j_set_slot as *const u8, 3), ("j_set_index", j_set_index as *const u8, 3), ("j_concat", j_concat as *const u8, 2), ("j_arith_slow", j_arith_slow as *const u8, 3),
        ("j_call_dyn", j_call_dyn as *const u8, 4), ("j_call_method", j_call_method as *const u8, 3), ("j_get_field", j_get_field as *const u8, 2), ("j_get_field_ic", j_get_field_ic as *const u8, 3), ("j_set_field", j_set_field as *const u8, 3),
        ("j_new_cell", j_new_cell as *const u8, 1), ("j_set_cell", j_set_cell as *const u8, 2), ("j_new_closure", j_new_closure as *const u8, 3), ("j_tagcheck_rec", j_tagcheck_rec as *const u8, 2), ("j_is_rec", j_is_rec as *const u8, 2), ("j_slot_get", j_slot_get as *const u8, 3), ("j_slot_set", j_slot_set as *const u8, 4), ("j_last_nres", j_last_nres as *const u8, 0), ("j_scalar", j_scalar as *const u8, 3), ("j_iter_next", j_iter_next as *const u8, 1), ("j_call_builtin", j_call_builtin as *const u8, 4), ("j_tagcheck_str", j_tagcheck_str as *const u8, 1),
        ("j_new_table_sized", j_new_table_sized as *const u8, 2), ("j_ret_extra", j_ret_extra as *const u8, 2), ("j_pcall", j_pcall as *const u8, 2), ("j_new_bytes", j_new_bytes as *const u8, 1), ("j_bytes_to_str", j_bytes_to_str as *const u8, 2),
        ("j_new_buffer", j_new_buffer as *const u8, 0), ("j_buf_append", j_buf_append as *const u8, 2), ("j_buf_append_sub", j_buf_append_sub as *const u8, 4), ("j_substring", j_substring as *const u8, 3), ("j_buf_finish", j_buf_finish as *const u8, 1),
        ("j_str_byte", j_str_byte as *const u8, 2), ("j_pow", j_pow as *const u8, 2), ("j_eq_slow", j_eq_slow as *const u8, 2), ("j_require", j_require as *const u8, 1), ("j_set_method", j_set_method as *const u8, 3),
    ]
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
#[unsafe(no_mangle)]
pub extern "C" fn j_frame_step(pc: u64) -> u64 {
    let it = ctx();
    it.guarded(|it| {
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
        it.tasks[tid].note_pc(pc + 1);
        match it.step(tid, &win, pc) {
            crate::interp::Step::Next(next) => { assert_eq!(next, pc + 1); V(0) }
            exit => { it.native_exit = Some(exit); V(1) }
        }
    }).0
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
pub extern "C" fn j_call_dyn(callee: u64, argv: *const u64, nargs: u64, fid: u64) -> u64 { let it = ctx(); let prev = it.jit_fid; it.jit_fid = fid as u32; let r = it.guarded(|_| V(j_call_dyn_impl(callee, argv, nargs))).0; it.jit_fid = prev; r }
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
pub extern "C" fn j_call_builtin(id: u64, argv: *const u64, nargs: u64, fid: u64) -> u64 { let it = ctx(); let prev = it.jit_fid; it.jit_fid = fid as u32; let r = it.guarded(|_| V(j_call_builtin_impl(id, argv, nargs))).0; it.jit_fid = prev; r }
#[unsafe(no_mangle)]
pub extern "C" fn j_scalar(kind: u64, a: u64, b: u64) -> u64 { let it = ctx(); it.guarded(|it| { let (x, y) = (V(a), V(b)); if !x.is_num() || !y.is_num() { it.err("scalar intrinsic on a non-number") } V::num(crate::builtins::scalar_op(kind as u8, x.as_num(), y.as_num())) }).0 }
/// An iterator object called from compiled code: the step, its first result
/// returned and the rest through `extra`.
#[unsafe(no_mangle)]
pub extern "C" fn j_iter_next(iter: u64) -> u64 { let it = ctx(); it.guarded(|_| V(j_iter_next_impl(iter))).0 }
#[unsafe(no_mangle)]
pub extern "C" fn j_last_nres() -> u64 { ctx().last_nres as u64 }
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

fn j_storage_ptr_impl(v: u64) -> u64 { match V(v).as_obj() { Some(p) => unsafe { (*p.as_ptr()).aux_ptr as u64 }, None => 0 } }
fn j_storage_len_impl(v: u64) -> u64 { match V(v).as_obj() { Some(p) => unsafe { (*p.as_ptr()).aux_len }, None => 0 } }
fn j_len_impl(v: u64) -> u64 { let it = ctx(); match it.kind_of(V(v)) { Some(KIND_TABLE) | Some(KIND_RECORD) => it.array_len(V(v)) as u64, _ => it.bytes_of(V(v)).len() as u64 } }
fn j_get_index_impl(t: u64, k: u64) -> u64 { let it = ctx(); it.index_any(V(t), V(k)).0 }
fn j_new_record_impl(shape: u64) -> u64 { let _hp = enter_helper!(); let v = ctx().new_record(shape as u32); leave_helper!(_hp); v.0 }
fn j_new_table_impl() -> u64 { let _hp = enter_helper!(); let v = ctx().new_table(); leave_helper!(_hp); v.0 }
fn j_new_table_sized_impl(n: u64, m: u64) -> u64 { let _hp = enter_helper!(); let v = ctx().new_table_sized(n as usize, m as usize); leave_helper!(_hp); v.0 }
fn j_set_slot_impl(obj: u64, i: u64, v: u64) -> u64 { ctx().set_slot(V(obj), i as usize, V(v)); 0 }
fn j_set_index_impl(t: u64, k: u64, v: u64) -> u64 { let _hp = enter_helper!(); let it = ctx(); let t = V(t); if it.metatable_of(t) != V::NIL { let k = it.key_for_store(V(k)); it.newindex(t, k, V(v)); } else { it.set_index(t, V(k), V(v)); } leave_helper!(_hp); 0 }
fn j_concat_impl(a: u64, b: u64) -> u64 { let _hp = enter_helper!(); let v = ctx().concat(V(a), V(b)); leave_helper!(_hp); v.0 }
/// Arithmetic and comparison past the number fast path: strings compare by
/// content (codes 3 and 4 answer a boolean word); anything else is an error.
fn j_arith_slow_impl(a: u64, b: u64, op: u64) -> u64 {
    let it = ctx(); let (x, y) = (V(a), V(b));
    match op {
        0..=2 => { if x.is_num() && y.is_num() { return V::num(match op { 0 => x.as_num() + y.as_num(), 1 => x.as_num() - y.as_num(), _ => x.as_num() * y.as_num() }).0; } it.err("arithmetic on a non-number") }
        3 => V::boolean(if x.is_num() && y.is_num() { x.as_num() < y.as_num() } else { it.bytes_of(x) < it.bytes_of(y) }).0,
        _ => V::boolean(if x.is_num() && y.is_num() { x.as_num() <= y.as_num() } else { it.bytes_of(x) <= it.bytes_of(y) }).0,
    }
}
fn j_iter_next_impl(iter: u64) -> u64 {
    let _hp = enter_helper!();
    let it = ctx();
    let outs = crate::builtins::iter_next(it, V(iter));
    let first = outs.first().copied().unwrap_or(V::NIL);
    it.extra_n = outs.len().saturating_sub(1).min(8); for i in 0..it.extra_n { it.extra[i] = outs[i + 1]; }
    it.last_nres = outs.len();
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
    it.extra_n = outs.len().saturating_sub(1).min(8); for i in 0..it.extra_n { it.extra[i] = outs[i + 1]; }
    it.last_nres = outs.len();
    leave_helper!(_hp);
    first.0
}
fn j_call_dyn_impl(callee: u64, argv: *const u64, nargs: u64) -> u64 {
    let _hp = enter_helper!();
    let it = ctx();
    let n = if nargs & 64 != 0 && nargs < 128 { (nargs & 63) as usize + it.last_nres.min(8) } else { (nargs & 127) as usize };
    let args: &[V] = unsafe { std::slice::from_raw_parts(argv as *const V, n) };
    let scope = it.open_scope(); for &a in args { it.handles.push(a); } it.handles.push(V(callee));
    if nargs >= 128 { it.err("a spread call from compiled code"); }
    let outs = it.call_outs(V(callee), args);
    it.close_scope(scope);
    let first = outs.first().copied().unwrap_or(V::NIL);
    it.extra_n = outs.len().saturating_sub(1).min(8); for i in 0..it.extra_n { it.extra[i] = outs[i + 1]; }
    it.last_nres = outs.len();
    leave_helper!(_hp);
    first.0
}
fn j_call_method_impl(name: u64, argv: *const u64, nargs: u64) -> u64 {
    let _hp = enter_helper!();
    let it = ctx();
    let nargs = if nargs & 64 != 0 && nargs < 128 { (nargs & 63) as usize + it.last_nres.min(8) } else { nargs as usize };
    let args: &[V] = unsafe { std::slice::from_raw_parts(argv as *const V, nargs) };
    let scope = it.open_scope(); for &a in args { it.handles.push(a); }
    let outs = it.call_method(V(name), args);
    it.close_scope(scope);
    let first = outs.first().copied().unwrap_or(V::NIL);
    it.extra_n = outs.len().saturating_sub(1).min(8); for i in 0..it.extra_n { it.extra[i] = outs[i + 1]; }
    it.last_nres = outs.len();
    leave_helper!(_hp);
    first.0
}
fn j_pcall_impl(argv: *const u64, nargs: u64) -> u64 {
    let _hp = enter_helper!();
    let it = ctx();
    let nargs = if nargs & 64 != 0 { (nargs & 63) as usize + it.last_nres.min(8) } else { nargs as usize };
    let args: Vec<V> = (0..nargs).map(|i| V(unsafe { *argv.add(i) })).collect();
    let scope = it.open_scope(); for &a in &args { it.handles.push(a); }
    let outs = it.pcall_values(args[0], &args[1..]);
    it.close_scope(scope);
    it.extra_n = outs.len().saturating_sub(1).min(8); for i in 0..it.extra_n { it.extra[i] = outs[i + 1]; }
    it.last_nres = outs.len();
    leave_helper!(_hp);
    outs[0].0
}
fn j_get_field_impl(t: u64, name: u64) -> u64 { ctx().index(V(t), V(name)).0 }
/// A field read that missed its site cache: resolve by name and, for a
/// record whose shape names the field, remember the shape and slot.
pub static IC_STATS: [std::sync::atomic::AtomicU64; 8] = [const { std::sync::atomic::AtomicU64::new(0) }; 8];
pub static INTERP_CALLEES: std::sync::Mutex<Option<std::collections::HashMap<u32, u64>>> = std::sync::Mutex::new(None);
pub static IC_SITES: std::sync::Mutex<Option<std::collections::HashMap<usize, std::collections::HashSet<u32>>>> = std::sync::Mutex::new(None);
fn j_get_field_ic_impl(t: u64, name: u64, cache: *mut u64) -> u64 {
    let it = ctx(); let tv = V(t);
    if it.ic_stats { let kind = tv.as_obj().map(|p| unsafe { (*p.as_ptr()).kind }); let i = match kind { Some(KIND_RECORD) => if unsafe { *cache } == 0 { 0 } else { 1 }, Some(KIND_TABLE) => 2, _ => 3 }; IC_STATS[i].fetch_add(1, std::sync::atomic::Ordering::Relaxed); if kind == Some(KIND_RECORD) { let sh = unsafe { (*tv.as_obj().unwrap().as_ptr()).shape() }; let mut g = IC_SITES.lock().unwrap(); g.get_or_insert_with(Default::default).entry(cache as usize).or_default().insert(sh); } }
    if let Some(p) = tv.as_obj() {
        let h = unsafe { &*p.as_ptr() };
        if h.kind == KIND_RECORD { let sh = &it.heap.shapes[h.shape() as usize]; if let Some(i) = sh.slot_of(V(name)) { unsafe { *cache = h.shape() as u64 + 1; *cache.add(1) = i as u64; } return h.slots()[i].0; } }
    }
    it.index(tv, V(name)).0
}
fn j_set_field_impl(t: u64, name: u64, v: u64) -> u64 { let _hp = enter_helper!(); let it = ctx(); let t = V(t); if it.metatable_of(t) != V::NIL { it.newindex(t, V(name), V(v)); } else { it.set_field(t, V(name), V(v)); } leave_helper!(_hp); 0 }
fn j_new_cell_impl(v: u64) -> u64 { let _hp = enter_helper!(); let it = ctx(); let scope = it.open_scope(); it.handles.push(V(v)); let c = it.new_cell(V(v)); it.close_scope(scope); leave_helper!(_hp); c.0 }
fn j_set_cell_impl(c: u64, v: u64) -> u64 { ctx().set_cell(V(c), V(v)); 0 }
fn j_new_closure_impl(fid: u64, argv: *const u64, n: u64) -> u64 { let _hp = enter_helper!(); let it = ctx(); let caps: Vec<V> = (0..n as usize).map(|i| V(unsafe { *argv.add(i) })).collect(); let scope = it.open_scope(); for &c in &caps { it.handles.push(c); } let v = it.new_closure(fid as u32, &caps); it.close_scope(scope); leave_helper!(_hp); v.0 }
fn j_slot_get_impl(o: u64, shape: u64, slot: u64) -> u64 { let it = ctx(); let v = V(o); if let Some(p) = v.as_obj() { let h = unsafe { &*p.as_ptr() }; if h.kind == KIND_RECORD && h.shape() == shape as u32 { return h.slots()[slot as usize].0; } } it.slot_get_slow(v, shape as u32, slot as u16).0 }
fn j_slot_set_impl(o: u64, shape: u64, slot: u64, v: u64) -> u64 { let it = ctx(); let ov = V(o); if let Some(p) = ov.as_obj() { let h = unsafe { &*p.as_ptr() }; if h.kind == KIND_RECORD && h.shape() == shape as u32 { it.set_slot(ov, slot as usize, V(v)); return 0; } } it.slot_set_slow(ov, shape as u32, slot as u16, V(v)); 0 }
fn j_tagcheck_rec_impl(v: u64, shape: u64) -> u64 { ctx().tagcheck_rec(V(v), shape as u32); 0 }
fn j_tagcheck_str_impl(v: u64) -> u64 { let it = ctx(); if !it.is_stringish(V(v)) { it.err("value is not a string") } 0 }
/// Results past the first of a compiled return: `n` plain values from
/// `argv`, or, with 128 set, `n & 127` fixed values followed by what the
/// last call delivered (which still sits in `extra` from that call).
fn j_ret_extra_impl(argv: *const u64, n: u64) -> u64 {
    let it = ctx();
    if n >= 128 {
        // argv[i] is register start+i: the fixed values first, then the call's
        // results, which the call lowering read back into the registers that
        // follow. The first of them all is the function's own return value.
        let fixed = (n & 127) as usize;
        let total = (fixed + it.last_nres).min(8);
        let mut outs: Vec<V> = Vec::new();
        for i in 1..total { outs.push(V(unsafe { *argv.add(i) })); }
        it.extra_n = outs.len(); for (i, v) in outs.iter().enumerate() { it.extra[i] = *v; }
        it.last_nres = total.max(1);
        return 0;
    }
    it.extra_n = (n as usize).min(8); for i in 0..it.extra_n { it.extra[i] = V(unsafe { *argv.add(i) }); }
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
fn j_str_byte_impl(s: u64, i: u64) -> u64 { let it = ctx(); let bytes = it.bytes_of(V(s)); let i = i as i64; if i >= 1 && (i as usize) <= bytes.len() { V::num(bytes[i as usize - 1] as f64).0 } else { V::NIL.0 } }
fn j_pow_impl(a: u64, b: u64) -> u64 { let it = ctx(); let (x, y) = (V(a), V(b)); if !(x.is_num() && y.is_num()) { it.err("power of a non-number") } V::num(x.as_num().powf(y.as_num())).0 }
#[unsafe(no_mangle)]
pub extern "C" fn j_pow(a: u64, b: u64) -> u64 { let it = ctx(); it.guarded(|_| V(j_pow_impl(a, b))).0 }
fn j_eq_slow_impl(a: u64, b: u64) -> u64 { ctx().values_equal(V(a), V(b)) as u64 }
fn j_require_impl(name: u64) -> u64 { let _hp = enter_helper!(); let it = ctx(); let text = String::from_utf8_lossy(it.bytes_of(V(name))).into_owned(); let v = it.require(&text); leave_helper!(_hp); v.0 }
fn j_set_method_impl(shape: u64, name: u64, f: u64) -> u64 { ctx().heap.shapes[shape as usize].methods.insert(V(name), V(f)); 0 }
