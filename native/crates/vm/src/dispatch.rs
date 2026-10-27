//! The Rust side of the native interpreter core: the driver that runs a task
//! on the Nupp handlers, the helpers they call by C ABI, and the hand-off of
//! an instruction to `Interp::step`. Every opcode's handler is Nupp -- the
//! `Slow` opcode's is the glue's `leave`, which answers the instruction's own
//! address -- so a chain returns here only to end, with a status in the
//! context, or to have one instruction run by the Rust interpreter, after
//! which the chain resumes from the frame driver's policy when that
//! instruction changed the frame, and at the next instruction otherwise. A
//! build without the object has no core and runs the Rust loop.
use crate::heap::Header;
#[cfg(test)]
use crate::heap::KIND_TABLE;
use crate::threaded::*;
use crate::value::{PAYLOAD, Value};

#[cfg(test)]
const NIL: u64 = Value::NIL.0;
const HDR: usize = 4;
#[inline(always)]
fn header(v: u64) -> *mut Header {
    (v & PAYLOAD) as *mut Header
}

// The layouts the handlers were compiled against, asserted here.
include!(concat!(env!("OUT_DIR"), "/native_runtime.rs"));

unsafe extern "C" {
    /// Runs the native chain from the instruction at `pc` in the frame the
    /// windows belong to. Answers an exit word: the address of the
    /// instruction Rust runs next, in the frame the context then names, or
    /// `EXIT_ERROR`.
    fn nupp_native_runtime_entry(
        pc: *const Ins,
        regs: *mut u64,
        iregs: *mut i64,
        fregs: *mut f64,
        ctx: *mut Ctx,
        frame: *mut u64,
    ) -> u64;
    /// The frame driver's policy for the frame the context names, then the
    /// chain from there: the task's entry, and what follows an instruction
    /// Rust ran that changed the frame. The same exit words.
    fn nupp_native_runtime_resume(ctx: *mut Ctx) -> u64;
}

/// The native chain's non-address exit: it ended, and the context holds the
/// status -- a helper raised, or the frame driver's service finished or
/// parked the task.
const EXIT_ERROR: u64 = 0;

/// The Rust helpers a native handler may call, by C ABI. Helpers that can
/// enter the VM publish and reload the task record; the handler publishes
/// `ctx.pc` before the call, checks `ctx.status` after it, and re-derives its
/// windows from the context, since the stack may have moved. Leaf services
/// that cannot enter the VM leave the frame state in the native context.
pub(crate) mod native_helpers {
    use super::*;
    // Temporary subsystem boundary: these services consume values and storage
    // descriptors, never decode a guest instruction or call Interp::step.
    fn record_service(ctx: *mut Ctx, body: impl FnOnce(&mut crate::interp::Interp) -> u64) -> u64 {
        let ctx = unsafe { &mut *ctx };
        let (it, _) = enter_rust(ctx);
        let mut result = 0;
        let r = it.guarded(|it| {
            result = body(it);
            Value::NIL
        });
        if r == Value::ERROR {
            ctx.status = ST_ERROR;
        }
        sync(ctx, it);
        result
    }
    #[unsafe(no_mangle)]
    pub unsafe extern "C" fn nupp_rt_require_module(ctx: *mut Ctx, name: u64) -> u64 {
        record_service(ctx, |it| {
            let bytes = it.bytes_of(Value(name)).to_vec();
            let name = String::from_utf8_lossy(&bytes);
            it.require(&name).0
        })
    }
    #[unsafe(no_mangle)]
    pub unsafe extern "C" fn nupp_rt_register_method(ctx: *mut Ctx, shape: u64, name: u64, method: u64) {
        record_service(ctx, |it| {
            it.set_method(shape as u32, Value(name), Value(method));
            0
        });
    }
    #[unsafe(no_mangle)]
    pub unsafe extern "C" fn nupp_rt_record_index(ctx: *mut Ctx, object: u64, name: u64) -> u64 {
        record_service(ctx, |it| it.index(Value(object), Value(name)).0)
    }
    #[unsafe(no_mangle)]
    pub unsafe extern "C" fn nupp_rt_record_mismatch(ctx: *mut Ctx, value: u64, shape: u64) {
        record_service(ctx, |it| {
            let value = Value(value);
            let what = match value.as_obj() {
                Some(p) => crate::heap::Heap::describe(unsafe { p.as_ref() }),
                None => format!("{:#x}", value.0),
            };
            it.err(&format!(
                "value is not an instance of the expected record ({}): {what}",
                it.heap.shapes[shape as u32 as usize].name
            ))
        });
    }
    #[unsafe(no_mangle)]
    pub unsafe extern "C" fn nupp_rt_slot_number_error(ctx: *mut Ctx) {
        record_service(ctx, |it| it.err("slot is not a number"));
    }
    #[unsafe(no_mangle)]
    pub unsafe extern "C" fn nupp_rt_physical_get(
        ctx: *mut Ctx,
        object: u64,
        identity: u64,
        name: u64,
        packed: u64,
    ) -> u64 {
        record_service(ctx, |it| {
            crate::storage::physical_get(
                it,
                Value(object),
                Value(identity),
                Value(name),
                crate::storage::PhysicalField {
                    identity: 0,
                    name: 0,
                    ordinal: (packed >> 32) as u16,
                    offset: packed as u32,
                    kind: (packed >> 48) as u8,
                },
            )
            .0
        })
    }
    #[unsafe(no_mangle)]
    pub unsafe extern "C" fn nupp_rt_physical_set(
        ctx: *mut Ctx,
        object: u64,
        identity: u64,
        name: u64,
        packed: u64,
        value: u64,
    ) {
        record_service(ctx, |it| {
            // SetPhysI may supply a newly boxed wide integer absent from any
            // value slot. Retain every argument across dynamic __newindex.
            let scope = it.open_scope();
            it.handles
                .extend([Value(object), Value(identity), Value(name), Value(value)]);
            crate::storage::physical_set(
                it,
                Value(object),
                Value(identity),
                Value(name),
                crate::storage::PhysicalField {
                    identity: 0,
                    name: 0,
                    ordinal: (packed >> 32) as u16,
                    offset: packed as u32,
                    kind: (packed >> 48) as u8,
                },
                Value(value),
            );
            it.close_scope(scope);
            0
        });
    }
    #[unsafe(no_mangle)]
    pub unsafe extern "C" fn nupp_rt_numeric_double(ctx: *mut Ctx, value: u64) -> f64 {
        f64::from_bits(record_service(ctx, |it| {
            crate::numeric::double(it, Value(value)).to_bits()
        }))
    }
    #[unsafe(no_mangle)]
    pub unsafe extern "C" fn nupp_rt_numeric_bits(ctx: *mut Ctx, value: u64, unsigned: u64) -> u64 {
        record_service(ctx, |it| {
            crate::numeric::bits(it, Value(value), unsigned != 0)
        })
    }
    #[unsafe(no_mangle)]
    pub unsafe extern "C" fn nupp_rt_box_integer(ctx: *mut Ctx, bits: u64, unsigned: u64) -> u64 {
        record_service(ctx, |it| {
            it.box_integer(crate::numeric::Integer {
                bits,
                unsigned: unsigned != 0,
            })
            .0
        })
    }
    #[unsafe(no_mangle)]
    pub unsafe extern "C" fn nupp_rt_get_field(ctx: *mut Ctx, obj: u64, name: u64) -> u64 {
        rt_get_field(ctx, obj, name)
    }
    #[unsafe(no_mangle)]
    pub unsafe extern "C" fn nupp_rt_barrier(ctx: *mut Ctx, parent: u64, child: u64) {
        rt_barrier(ctx, parent, child)
    }
    #[unsafe(no_mangle)]
    pub unsafe extern "C" fn nupp_rt_new_record(ctx: *mut Ctx, shape: u64) -> u64 {
        rt_new_record(ctx, shape as u32)
    }
    #[unsafe(no_mangle)]
    pub unsafe extern "C" fn nupp_rt_eq_slow(ctx: *mut Ctx, x: u64, y: u64) -> u64 {
        rt_eq_slow(ctx, x, y) as u64
    }
    #[unsafe(no_mangle)]
    pub unsafe extern "C" fn nupp_rt_call_iter(ctx: *mut Ctx, iter: u64, base: u64) {
        rt_call_iter(ctx, iter, base)
    }
    #[unsafe(no_mangle)]
    pub unsafe extern "C" fn nupp_rt_call_builtin(ctx: *mut Ctx, id: u64, base: u64, nargs: u64) {
        rt_call_builtin(ctx, id as u32, base, nargs as u32)
    }
    /// Feedback for the JIT at (`fid`, `pc`): `kind` 0 is a call target, 1 a
    /// receiver. Records into the specializer's own tables; moves no stack.
    #[unsafe(no_mangle)]
    pub unsafe extern "C" fn nupp_rt_observe(ctx: *mut Ctx, fid: u64, pc: u64, value: u64, kind: u64) {
        #[cfg(feature = "jit")]
        crate::specialize::rt_observe((*ctx).interp, fid as u32, pc as u32, value, kind as u32);
        #[cfg(not(feature = "jit"))]
        let _ = (ctx, fid, pc, value, kind);
    }
    /// The frame driver's service: enters the compiled frame of the function
    /// on top at `pc`, compiling it first when the core counted it `hot`, or
    /// applies the interpreter's policy for vector code. Answers the pc to go
    /// on interpreting at, or a status word.
    #[unsafe(no_mangle)]
    pub unsafe extern "C" fn nupp_rt_enter_frame(ctx: *mut Ctx, pc: u64, hot: u64) -> u64 {
        rt_enter_frame(ctx, pc as u32, hot as u32) as u64
    }
    /// A fresh string of `n` bytes the core fills in place (contracts 1.3):
    /// an allocation, so a collection may run here, under the published pc.
    #[unsafe(no_mangle)]
    pub unsafe extern "C" fn nupp_rt_new_string(ctx: *mut Ctx, n: u64) -> u64 {
        let ctx = unsafe { &mut *ctx };
        let (it, _) = enter_rust(ctx);
        let v = it.guarded(|it| it.new_string_blank(n as usize));
        if v == Value::ERROR {
            ctx.status = ST_ERROR;
        }
        sync(ctx, it);
        v.0
    }
    /// The interned string with a filled string's bytes: the one already in
    /// the table, or this one, entered now. Allocates nothing and moves no
    /// stack; the core calls it on every new string of at most forty bytes.
    #[unsafe(no_mangle)]
    pub unsafe extern "C" fn nupp_rt_intern(ctx: *mut Ctx, s: u64) -> u64 {
        let it = unsafe { &mut *((*ctx).interp as *mut crate::interp::Interp) };
        it.heap.intern_string(Value(s)).0
    }
    /// A new table with room for `n` array entries and `m` hash entries: the
    /// allocation, which is the heap's until N05; its contents are the
    /// handlers'.
    #[unsafe(no_mangle)]
    pub unsafe extern "C" fn nupp_rt_new_table(ctx: *mut Ctx, n: i64, m: i64) -> u64 {
        let ctx = unsafe { &mut *ctx };
        let (it, _) = enter_rust(ctx);
        let v = it.guarded(|it| it.new_table_sized(n as usize, m as usize));
        if v == Value::ERROR {
            ctx.status = ST_ERROR;
        }
        sync(ctx, it);
        v.0
    }
    /// The canonical form of a table key (contracts 1.3, 2.9): an uninterned
    /// string or a slice as the interned string with its bytes, an unsigned
    /// integer box as the signed one. With `create` zero nothing is
    /// allocated and nil answers for a key no live interned string spells,
    /// which is a lookup miss.
    #[unsafe(no_mangle)]
    pub unsafe extern "C" fn nupp_rt_intern_key(ctx: *mut Ctx, key: u64, create: u64) -> u64 {
        let ctx = unsafe { &mut *ctx };
        let (it, _) = enter_rust(ctx);
        let v = it.guarded(|it| {
            if create != 0 { it.key_for_store(Value(key)) } else { it.key_of(Value(key)).unwrap_or(Value::NIL) }
        });
        if v == Value::ERROR {
            ctx.status = ST_ERROR;
        }
        sync(ctx, it);
        v.0
    }
    /// The array part of a plain table at `length` entries, lengthened with
    /// nils or truncated: the handlers write the entries, the vector is the
    /// heap's until N05. This only reallocates outside storage and accounts
    /// for its capacity: it cannot collect, park, raise or move the VM stack,
    /// so the native frame and its uncharged budget can stay in the context.
    #[unsafe(no_mangle)]
    pub unsafe extern "C" fn nupp_rt_resize_array(ctx: *mut Ctx, table: u64, length: i64) {
        let it = unsafe { &mut *((*ctx).interp as *mut crate::interp::Interp) };
        let h = unsafe { &mut *header(table) };
        let before = h.external_bytes();
        h.table().array.resize(length as usize, Value::NIL);
        h.refresh();
        it.heap.account_resize(before, h.external_bytes());
    }
    /// A store to a key a table with a metatable lacks (contracts 9): the
    /// `__newindex` dispatch, which is the object library's until N04, and
    /// the raw store when the metatable holds none.
    #[unsafe(no_mangle)]
    pub unsafe extern "C" fn nupp_rt_new_index(ctx: *mut Ctx, obj: u64, key: u64, value: u64) {
        let ctx = unsafe { &mut *ctx };
        let (it, _) = enter_rust(ctx);
        let r = it.guarded(|it| {
            it.newindex(Value(obj), Value(key), Value(value));
            Value::NIL
        });
        if r == Value::ERROR {
            ctx.status = ST_ERROR;
        }
        sync(ctx, it);
    }
    /// The hash part of a plain table rehashed with room for one more entry:
    /// the entries whose values went nil drop, the rest keep their insertion
    /// order (contracts 2.13).
    #[unsafe(no_mangle)]
    pub unsafe extern "C" fn nupp_rt_grow_hash(ctx: *mut Ctx, table: u64) {
        let ctx = unsafe { &mut *ctx };
        let (it, _) = enter_rust(ctx);
        let h = unsafe { &mut *header(table) };
        let before = h.external_bytes();
        h.table().hash.grow();
        it.heap.account_resize(before, h.external_bytes());
        sync(ctx, it);
    }
    /// A closure over function `fid` with `n` nil captures the core fills in
    /// place, under the barrier while marking (contracts 4.2): an allocation,
    /// so a collection may run here, under the published pc.
    #[unsafe(no_mangle)]
    pub unsafe extern "C" fn nupp_rt_new_closure(ctx: *mut Ctx, fid: u64, n: u64) -> u64 {
        let ctx = unsafe { &mut *ctx };
        let (it, _) = enter_rust(ctx);
        let captures = vec![Value::NIL; n as usize];
        let v = it.guarded(|it| it.new_closure(fid as u32, &captures));
        if v == Value::ERROR {
            ctx.status = ST_ERROR;
        }
        sync(ctx, it);
        v.0
    }
    /// The method `recv:name(...)` calls: a string's through its metatable's
    /// `__index`, anything else's as `Interp::resolve_method` finds it (a
    /// shape method, a field, the `__index` chain). Raises as the step does
    /// for a receiver that has none. May run an `__index` function.
    #[unsafe(no_mangle)]
    pub unsafe extern "C" fn nupp_rt_resolve_method(ctx: *mut Ctx, recv: u64, name: u64) -> u64 {
        let ctx = unsafe { &mut *ctx };
        let (it, _) = enter_rust(ctx);
        let v = it.guarded(|it| {
            let (recv, name) = (Value(recv), Value(name));
            if recv.as_obj().is_none() {
                it.op_error(crate::interp::OpErr::Index, recv)
            }
            if it.is_stringish(recv) {
                let method = it.string_field(recv, name);
                if method == Value::NIL {
                    it.op_error(crate::interp::OpErr::Call, Value::NIL)
                }
                return method;
            }
            it.resolve_method(recv, name)
        });
        if v == Value::ERROR {
            ctx.status = ST_ERROR;
        }
        sync(ctx, it);
        v.0
    }
    /// The rest of a dynamic call whose callee is already at `base` of the
    /// top frame, at the published pc, as the step runs `CallDyn base base
    /// nargs`: answers the pc to go on at, or a status, as the frame driver's
    /// service does. `budgeted` is zero when Nupp already charged before
    /// resolving the callee; a plain boundary charges here.
    #[unsafe(no_mangle)]
    pub unsafe extern "C" fn nupp_rt_call_resolved(ctx: *mut Ctx, base: u64, nargs: u64, budgeted: u64) -> u64 {
        use crate::interp::{Flow, Outcome};
        let ctx = unsafe { &mut *ctx };
        let (it, tid) = enter_rust(ctx);
        it.last_nres = ctx.last_nres as usize;
        let pc = ctx.pc as usize;
        let (win, _) = it.window(tid);
        let mark = it.handles.len();
        let flow = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            if budgeted != 0 && !it.take_budget_point(tid, pc) { return Flow::Return(Outcome::Parked(0)); }
            it.op_call_dyn(tid, &win, pc + 1, base as u8, base as u8, nargs as u8)
        }));
        if flow.is_err() {
            it.handles.truncate(mark);
        }
        let r = match flow {
            Ok(Flow::Next) => (pc + 1) as u32,
            Ok(Flow::Reenter) => ST_REENTER,
            Ok(Flow::Return(Outcome::Done(v))) => {
                ctx.result = v.0;
                ST_DONE
            }
            Ok(Flow::Return(Outcome::Parked(k))) => {
                ctx.result = k;
                ST_PARKED
            }
            Err(p) => {
                let v = it.error_value(p);
                it.pending_error = Some(v);
                ctx.status = ST_ERROR;
                ST_ERROR
            }
        };
        sync(ctx, it);
        r as u64
    }
    /// Registers a cleanup on the top frame (contracts 6.5b): the record
    /// list is the task's, which only Rust grows; the guard is recomputed,
    /// so the frame's return goes through Rust, which runs it.
    #[unsafe(no_mangle)]
    pub unsafe extern "C" fn nupp_rt_defer(ctx: *mut Ctx, value: u64, callback: u64) {
        let ctx = unsafe { &mut *ctx };
        let (it, tid) = enter_rust(ctx);
        let frame = it.tasks[tid].cur();
        it.tasks[tid].cleanups.push(crate::interp::Cleanup { frame, value: Value(value), callback: Value(callback) });
        sync(ctx, it);
    }
    /// A protected call's record (contracts 5.2b, 6.4a): the callee's frame
    /// at `frame`, about to be pushed by the core above `caller`, whose
    /// register `result` takes the status and then the results. Its return
    /// and any raise below it are settled by Rust, which the guard sends
    /// them to.
    #[unsafe(no_mangle)]
    pub unsafe extern "C" fn nupp_rt_protect(ctx: *mut Ctx, frame: u64, result: u64) {
        let ctx = unsafe { &mut *ctx };
        let (it, tid) = enter_rust(ctx);
        let caller = it.tasks[tid].cur();
        it.tasks[tid].protected.push(crate::interp::Protected { frame: frame as usize, caller, result: result as usize, handler: Value::NIL });
        sync(ctx, it);
    }
    /// A raise of `value` from the core: pending until the Rust frame that
    /// entered the core re-raises it to the nearest protected call (6.4a).
    #[unsafe(no_mangle)]
    pub unsafe extern "C" fn nupp_rt_raise(ctx: *mut Ctx, value: u64) {
        let ctx = unsafe { &mut *ctx };
        let (it, _) = enter_rust(ctx);
        it.pending_error = Some(Value(value));
        ctx.status = ST_ERROR;
    }
    /// A cell holding nil, filled by the core as a closure is.
    #[unsafe(no_mangle)]
    pub unsafe extern "C" fn nupp_rt_new_cell(ctx: *mut Ctx) -> u64 {
        let ctx = unsafe { &mut *ctx };
        let (it, _) = enter_rust(ctx);
        let v = it.guarded(|it| it.new_cell(Value::NIL));
        if v == Value::ERROR {
            ctx.status = ST_ERROR;
        }
        sync(ctx, it);
        v.0
    }
}

#[cfg(test)]
#[path = "native_tests.rs"]
mod native_tests;

#[cfg(test)]
#[path = "native_module_tests.rs"]
mod native_module_tests;

/// Runs the context's task from its top frame until it finishes, parks or
/// raises; the status says which. The chain starts at the frame driver's
/// policy. Each time it exits at an instruction, the Rust interpreter runs
/// that one instruction (`rt_exec_op`), and the chain resumes: from the
/// policy again when the instruction changed the frame, at the instruction
/// after it otherwise, with the windows derived from the frame the context
/// names.
pub(crate) unsafe fn run(ctx: *mut Ctx) -> u32 {
    (*ctx).status = 0;
    let mut exit = nupp_native_runtime_resume(ctx);
    loop {
        if exit == EXIT_ERROR {
            return (*ctx).status;
        }
        let frame = (*ctx).stack.add((*ctx).cur as usize);
        let fi = (*ctx).funcs.add(*frame as u32 as usize);
        let pc = (exit as *const Ins).offset_from((*fi).code) as u32;
        let result = rt_exec_op(ctx, pc);
        if result >= ST_ERROR && result != ST_REENTER {
            (*ctx).status = result;
            return result;
        }
        if result == ST_REENTER {
            exit = nupp_native_runtime_resume(ctx);
            continue;
        }
        let frame = (*ctx).stack.add((*ctx).cur as usize);
        let fi = (*ctx).funcs.add(*frame as u32 as usize);
        exit = nupp_native_runtime_entry(
            (*fi).code.add(result as usize),
            frame.add(HDR),
            frame.add((*fi).off_i as usize).cast(),
            frame.add((*fi).off_f as usize).cast(),
            ctx,
            frame,
        );
    }
}

#[cfg(test)]
#[path = "native_simd_tests.rs"]
mod native_simd_tests;

#[cfg(test)]
#[path = "native_numeric_tests.rs"]
mod native_numeric_tests;
