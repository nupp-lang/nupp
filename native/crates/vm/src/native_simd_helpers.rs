//! Temporary managed-packet and storage ownership boundary. Opcode control,
//! bounds, scalar lanes and reductions are in the Nupp interpreter. Scratch
//! packets and views contain no managed pointers and never cross a dispatch.
use crate::threaded::{Ctx, ST_ERROR, enter_rust, sync};
use crate::{simd, value::Value};
const _: () = {
    assert!(std::mem::size_of::<simd::Packet>() == 2080);
    assert!(std::mem::align_of::<simd::Packet>() == 16);
};

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nupp_rt_simd_prepare(
    ctx: *mut Ctx,
    packet: *mut simd::Packet,
    operation: i64,
    kind: i64,
    source: i64,
    base: i64,
    nargs: i64,
) {
    let ctx = unsafe { &mut *ctx };
    let (it, tid) = enter_rust(ctx);
    // SIMD arity is always a fixed window, including 64 arguments. It is
    // not the call opcode's high-bit encoded trailing-result convention.
    let args: Vec<Value> = (0..nargs as usize)
        .map(|i| Value(it.tasks[tid].stack[base as usize + 1 + i]))
        .collect();
    let p = unsafe { &mut *packet };
    let r = it.guarded(|it| {
        if operation == simd::operation("store").unwrap() as i64 {
            simd::store(it, kind as u8, args.as_slice(), &[]);
            *p = simd::Packet::default();
            p.operation = operation as u64;
        } else {
            simd::prepare(
                it,
                operation as u8,
                kind as u8,
                source as u8,
                args.as_slice(),
                p,
            );
        }
        Value::NIL
    });
    if r == Value::ERROR {
        ctx.status = ST_ERROR;
    }
    sync(ctx, it);
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nupp_rt_simd_finish(
    ctx: *mut Ctx,
    packet: *const simd::Packet,
    base: i64,
    nargs: i64,
) {
    let ctx = unsafe { &mut *ctx };
    let (it, tid) = enter_rust(ctx);
    // SIMD arity is always a fixed window, including 64 arguments. It is
    // not the call opcode's high-bit encoded trailing-result convention.
    let args: Vec<Value> = (0..nargs as usize)
        .map(|i| Value(it.tasks[tid].stack[base as usize + 1 + i]))
        .collect();
    let p = unsafe { &*packet };
    let r = it.guarded(|it| {
        it.extra_n = 0;
        it.last_nres = 1;
        let v = if p.operation == simd::operation("store").unwrap() as u64 {
            Value::NIL
        } else {
            simd::finish(it, p, args.as_slice())
        };
        it.tasks[tid].stack[base as usize] = v.0;
        for k in 1..simd::result_count(p.operation as u8, nargs as usize) {
            it.tasks[tid].stack[base as usize + k] = it.extra[k - 1].0;
        }
        Value::NIL
    });
    if r == Value::ERROR {
        ctx.status = ST_ERROR;
    }
    sync(ctx, it);
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nupp_rt_span_view(
    ctx: *mut Ctx,
    value: u64,
    kind: i64,
    write: i64,
    view: *mut u64,
) {
    let ctx = unsafe { &mut *ctx };
    let (it, _) = enter_rust(ctx);
    let r = it.guarded(|it| {
        let (ptr, len) = if kind == -1 {
            let p = Value(value)
                .as_obj()
                .unwrap_or_else(|| it.err("not storage"));
            let h = unsafe { &mut *p.as_ptr() };
            if h.kind != crate::heap::KIND_STORAGE {
                it.err("not storage");
            }
            (h.aux_ptr as *const u8, h.aux_len as usize)
        } else {
            crate::storage::native_span(it, Value(value), kind as u8, write != 0)
        };
        unsafe {
            view.write(ptr as u64);
            view.add(1).write(len as u64);
        }
        Value::NIL
    });
    if r == Value::ERROR {
        ctx.status = ST_ERROR;
    }
    sync(ctx, it);
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nupp_rt_simd_error(ctx: *mut Ctx, error: i64) {
    let ctx = unsafe { &mut *ctx };
    let (it, _) = enter_rust(ctx);
    let r = it.guarded(|it| {
        it.err(match error {
            0 => "SIMD span index out of bounds",
            1 => "masked load out of bounds",
            2 => "masked store out of bounds",
            3 => "native spans have incompatible lengths",
            4 => "storage index out of bounds",
            _ => "invalid SIMD operation",
        })
    });
    if r == Value::ERROR {
        ctx.status = ST_ERROR;
    }
    sync(ctx, it);
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nupp_rt_simd_invalid(ctx: *mut Ctx, operation: i64, kind: i64) {
    let ctx = unsafe { &mut *ctx };
    let (it, _) = enter_rust(ctx);
    let r = it.guarded(|it| {
        it.err(&format!(
            "SIMD {} is not implemented for {}",
            simd::OPERATIONS
                .get(operation as usize)
                .unwrap_or(&"unknown"),
            simd::ELEMENTS.get(kind as usize).unwrap_or(&"unknown")
        ))
    });
    if r == Value::ERROR {
        ctx.status = ST_ERROR;
    }
    sync(ctx, it);
}
