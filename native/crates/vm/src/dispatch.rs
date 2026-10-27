//! Native handler entry transport and named C ABI services. Full chains end
//! with an explicit status; compiled boundaries enter the same handlers with
//! an all-leave dispatch table, stopping after one instruction. No boundary
//! decodes or executes a guest opcode in Rust.
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
    /// next instruction at an explicit stop boundary, or
    /// `EXIT_ERROR`.
    #[cfg(test)]
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
    fn nupp_native_runtime_step(pc: *const Ins, regs: *mut u64, ints: *mut u64,
        floats: *mut u64, ctx: *mut Ctx, frame: *mut u64) -> u64;
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
    pub unsafe extern "C" fn nupp_rt_scheduler_poll(ctx: *mut Ctx) {
        record_service(ctx, |it| { crate::scheduler::checkpoint(it); 0 });
    }
    #[unsafe(no_mangle)]
    pub unsafe extern "C" fn nupp_rt_memory_poll(ctx: *mut Ctx) {
        record_service(ctx, |it| { it.back_edge(); 0 });
    }
    #[unsafe(no_mangle)]
    pub unsafe extern "C" fn nupp_rt_task_park(ctx: *mut Ctx, key: u64, resume: u64) {
        let ctx = unsafe { &mut *ctx };
        let (it, tid) = enter_rust(ctx);
        it.parks += 1;
        it.tasks[tid].note_pc(resume as usize);
        it.tasks[tid].state = crate::interp::State::Parked(key);
        sync(ctx, it);
        ctx.result = key;
        ctx.status = ST_PARKED;
    }
    #[unsafe(no_mangle)]
    pub unsafe extern "C" fn nupp_rt_mark_affine(ctx: *mut Ctx, closure: u64, drop: u64) -> u64 {
        record_service(ctx, |it| it.affine_mark(Value(closure), Value(drop)).0)
    }
    #[unsafe(no_mangle)]
    pub unsafe extern "C" fn nupp_rt_enter_affine(ctx: *mut Ctx, closure: u64) {
        record_service(ctx, |it| { it.affine_enter(Value(closure)); 0 });
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
    pub unsafe extern "C" fn nupp_rt_object_length(ctx: *mut Ctx, value: u64) -> u64 {
        record_service(ctx, |it| {
            let scope = it.open_scope();
            it.handles.push(Value(value));
            let result = it.length(Value(value));
            it.close_scope(scope);
            result.0
        })
    }
    #[unsafe(no_mangle)]
    pub unsafe extern "C" fn nupp_rt_concat_values(ctx: *mut Ctx, left: u64, right: u64) -> u64 {
        record_service(ctx, |it| {
            let scope = it.open_scope();
            it.handles.extend([Value(left), Value(right)]);
            let result = it.concat(Value(left), Value(right));
            it.close_scope(scope);
            result.0
        })
    }
    #[unsafe(no_mangle)]
    pub unsafe extern "C" fn nupp_rt_store_field(ctx: *mut Ctx, object: u64, name: u64, value: u64) {
        record_service(ctx, |it| {
            let scope = it.open_scope();
            it.handles.extend([Value(object), Value(name), Value(value)]);
            it.store_field(Value(object), Value(name), Value(value));
            it.close_scope(scope);
            0
        });
    }
    #[unsafe(no_mangle)]
    pub unsafe extern "C" fn nupp_rt_cell_error(ctx: *mut Ctx, value: u64, kind: i64, slot: i64) {
        let context = unsafe { &*ctx };
        let pc = context.pc as usize + 1;
        let fid = unsafe { *context.stack.add(context.cur as usize) } as u32;
        record_service(ctx, |it| match kind {
            0 => it.err(&format!("GetCell of a non-object {:#x} in {} at pc {} register {}", value, it.funcs[fid as usize].name, pc, slot)),
            1 => it.err(&format!("GetCell of a non-cell in {} at pc {} register {}", it.funcs[fid as usize].name, pc, slot)),
            2 => it.err("not a cell"),
            3 => it.err("upvalue outside a closure"),
            _ => it.err("not a closure"),
        });
    }
    #[unsafe(no_mangle)]
    pub unsafe extern "C" fn nupp_rt_get_field(ctx: *mut Ctx, obj: u64, name: u64) -> u64 {
        record_service(ctx, |it| {
            let scope = it.open_scope();
            it.handles.extend([Value(obj), Value(name)]);
            let value = it.field(Value(obj), Value(name));
            it.close_scope(scope);
            value.0
        })
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
    // Success preserves the caller's unpublished frame and budget. Only
    // refusal publishes state before error conversion can collect.
    #[unsafe(no_mangle)]
    pub unsafe extern "C" fn nupp_rt_resize_array(ctx: *mut Ctx, table: u64, length: i64) {
        let outcome = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            let it = unsafe { &mut *((*ctx).interp as *mut crate::interp::Interp) };
            let h = unsafe { &mut *header(table) };
            let before = h.external_bytes();
            h.table().array.resize(length as usize, Value::NIL);
            h.refresh();
            it.heap.account_resize(before, h.external_bytes());
        }));
        if let Err(payload) = outcome {
            let ctx = unsafe { &mut *ctx };
            let (it, _) = enter_rust(ctx);
            it.guarded(|_| std::panic::resume_unwind(payload));
            ctx.status = ST_ERROR;
            sync(ctx, it);
        }
    }
    /// A store to a key a table with a metatable lacks (contracts 9): the
    /// `__newindex` dispatch, which is the object library's until N04, and
    /// the raw store when the metatable holds none.
    #[unsafe(no_mangle)]
    pub unsafe extern "C" fn nupp_rt_new_index(ctx: *mut Ctx, obj: u64, key: u64, value: u64) {
        let ctx = unsafe { &mut *ctx };
        let (it, _) = enter_rust(ctx);
        let r = it.guarded(|it| {
            let scope = it.open_scope();
            it.handles.extend([Value(obj), Value(key), Value(value)]);
            it.newindex(Value(obj), Value(key), Value(value));
            it.close_scope(scope);
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
        let result = it.guarded(|it| {
            let h = unsafe { &mut *header(table) };
            let before = h.external_bytes();
            h.table().hash.grow();
            it.heap.account_resize(before, h.external_bytes());
            Value::NIL
        });
        if result == Value::ERROR { ctx.status = ST_ERROR; }
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
#[path = "native_boundary_tests.rs"]
mod native_boundary_tests;
#[cfg(test)]
#[path = "native_target_transfer_tests.rs"]
mod native_target_transfer_tests;
#[cfg(test)]
#[path = "native_cleanup_transfer_tests.rs"]
mod native_cleanup_transfer_tests;

#[cfg(test)]
#[path = "native_tests.rs"]
mod native_tests;

#[cfg(test)]
#[path = "native_module_tests.rs"]
mod native_module_tests;

#[cfg(test)]
#[path = "native_state_tests.rs"]
mod native_state_tests;

/// Enter one shared handler with the existing all-leave dispatch table.
/// No bytecode is decoded here beyond locating its retained encoded body.
pub(crate) unsafe fn step(ctx: *mut Ctx, pc: usize) -> u64 {
    let frame = unsafe { (*ctx).stack.add((*ctx).cur as usize) };
    let info = unsafe { &*(*ctx).funcs.add((*frame & 0xffff_ffff) as usize) };
    assert!(pc < info.ncode as usize);
    let instruction = unsafe { info.code.add(pc) };
    assert_ne!(unsafe { (*instruction).op }, Code::Slow as u8, "unencoded native boundary");
    unsafe { nupp_native_runtime_step(instruction, frame.add(HDR), frame.add(info.off_i as usize).cast(),
        frame.add(info.off_f as usize).cast(), ctx, frame) }
}

/// The linked Nupp core owns every guest opcode. A normal dispatch chain
/// finishes only by a published done, park or error status.
pub(crate) unsafe fn run(ctx: *mut Ctx) -> u32 {
    unsafe { (*ctx).status = 0; }
    let exit = unsafe { nupp_native_runtime_resume(ctx) };
    assert_eq!(exit, EXIT_ERROR, "native core returned an instruction without a transfer");
    let status = unsafe { (*ctx).status };
    assert!(matches!(status, ST_DONE | ST_PARKED | ST_ERROR), "native core status {status:#x}");
    status
}

#[cfg(test)]
#[path = "native_simd_tests.rs"]
mod native_simd_tests;

#[cfg(test)]
#[path = "native_numeric_tests.rs"]
mod native_numeric_tests;

#[cfg(test)]
#[path = "native_byte_tests.rs"]
mod native_byte_tests;

#[cfg(test)]
#[path = "native_calltyped_tests.rs"]
mod native_calltyped_tests;

#[cfg(test)]
#[path = "native_object_tests.rs"]
mod native_object_tests;
