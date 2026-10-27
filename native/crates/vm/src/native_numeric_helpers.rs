//! Numeric managed boundaries and the platform power primitive. Nupp owns
//! numeric classification, integer-kind inference and all arithmetic policy.
use crate::threaded::{Ctx, ST_ERROR, enter_rust, sync};
use crate::{numeric, value::Value};

fn service(ctx: *mut Ctx, body: impl FnOnce(&mut crate::interp::Interp) -> u64) -> u64 {
    let ctx = unsafe { &mut *ctx };
    let (it, _) = enter_rust(ctx);
    let mut answer = 0;
    let result = it.guarded(|it| {
        answer = body(it);
        Value::NIL
    });
    if result == Value::ERROR {
        ctx.status = ST_ERROR;
    }
    sync(ctx, it);
    answer
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nupp_rt_arithmetic_operands(
    ctx: *mut Ctx,
    left: u64,
    right: u64,
    method: i64,
    packet: *mut u64,
) {
    service(ctx, |it| {
        let (x, y) = (Value(left), Value(right));
        let mm = match method {
            0 => crate::metamethods::MM::Div,
            1 => crate::metamethods::MM::Pow,
            2 => crate::metamethods::MM::IDiv,
            _ => it.err("invalid arithmetic metamethod"),
        };
        // These inputs stay rooted even when a callback allocates or grows
        // the task stack. The packet itself is never a managed root.
        let scope = it.open_scope();
        it.handles.extend([x, y]);
        let mut handler = it.metamethod(x, mm);
        if handler == Value::NIL {
            handler = it.metamethod(y, mm);
        }
        if handler != Value::NIL {
            let result = it
                .call_value(handler, &[x, y])
                .first()
                .copied()
                .unwrap_or(Value::NIL);
            unsafe {
                packet.write(1);
                packet.add(1).write(result.0);
            }
        } else {
            let coerce = |it: &crate::interp::Interp, v: Value| {
                if numeric::is_numeric(v) {
                    v
                } else {
                    match crate::builtins::coerce_number(it, v) {
                        Some(number) => Value::num(number),
                        None => it.op_error(crate::interp::OpErr::Arith, v),
                    }
                }
            };
            let (x, y) = (coerce(it, x), coerce(it, y));
            unsafe {
                packet.write(0);
                packet.add(2).write(x.0);
                packet.add(3).write(y.0);
            }
        }
        it.close_scope(scope);
        0
    });
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nupp_rt_operand_bits(ctx: *mut Ctx, value: u64) -> u64 {
    service(ctx, |it| numeric::operand_bits(it, Value(value)))
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nupp_rt_numeric_error(ctx: *mut Ctx, error: i64) {
    service(ctx, |it| {
        it.err(match error {
            0 => "integer kind mismatch",
            1 => "value is not a string",
            2 => "scalar intrinsic on a non-number",
            3 => "integer division by zero",
            _ => "invalid numeric error",
        })
    });
}

#[unsafe(no_mangle)]
pub extern "C" fn nupp_rt_power(left: f64, right: f64) -> f64 {
    left.powf(right)
}
