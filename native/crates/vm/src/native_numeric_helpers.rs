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
            3 => crate::metamethods::MM::Add,
            4 => crate::metamethods::MM::Sub,
            5 => crate::metamethods::MM::Mul,
            6 => crate::metamethods::MM::Mod,
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
            let coerce = |it: &mut crate::interp::Interp, v: Value| {
                if numeric::is_numeric(v) {
                    v
                } else {
                    match crate::builtins::coerce_numeric(it, v) {
                        Some(number) => number,
                        None => it.op_error(crate::interp::OpErr::Arith, v),
                    }
                }
            };
            let x = coerce(it, x);
            it.handles.push(x);
            let y = coerce(it, y);
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
            4 => "value is not a number",
            5 => "byte of a non-string",
            _ => "invalid numeric error",
        })
    });
}

#[unsafe(no_mangle)]
pub extern "C" fn nupp_rt_power(left: f64, right: f64) -> f64 {
    left.powf(right)
}

#[unsafe(no_mangle)]
pub extern "C" fn nupp_rt_numeric_kind(value: u64) -> i64 {
    numeric::integer(Value(value)).map_or(-1, |value| value.unsigned as i64)
}

#[unsafe(no_mangle)]
pub extern "C" fn nupp_rt_integer_bits(value: u64) -> u64 {
    numeric::integer(Value(value)).map_or(0, |value| value.bits)
}
#[unsafe(no_mangle)]
pub extern "C" fn nupp_rt_integer_double(value: u64) -> f64 {
    numeric::integer(Value(value)).map_or(f64::NAN, |value| value.double())
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn nupp_rt_unary_operand(ctx: *mut Ctx, value: u64, packet: *mut u64) {
    service(ctx, |it| {
        let value = Value(value);
        let scope = it.open_scope();
        it.handles.push(value);
        let handler = it.metamethod(value, crate::metamethods::MM::Unm);
        if handler != Value::NIL {
            let result = it
                .call_value(handler, &[value, value])
                .first()
                .copied()
                .unwrap_or(Value::NIL);
            unsafe {
                packet.write(1);
                packet.add(1).write(result.0);
            }
        } else {
            let number = crate::builtins::coerce_numeric(it, value)
                .unwrap_or_else(|| it.op_error(crate::interp::OpErr::Arith, value));
            unsafe {
                packet.write(0);
                packet.add(2).write(number.0);
            }
        }
        it.close_scope(scope);
        0
    });
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn nupp_rt_shared_metamethod(
    ctx: *mut Ctx,
    left: u64,
    right: u64,
    kind: i64,
) -> u64 {
    service(ctx, |it| {
        let (left, right) = (Value(left), Value(right));
        let scope = it.open_scope();
        it.handles.extend([left, right]);
        let mm = if kind == 0 {
            crate::metamethods::MM::Lt
        } else {
            crate::metamethods::MM::Le
        };
        let callback = it.metamethod(left, mm);
        let callback = if callback != Value::NIL && callback == it.metamethod(right, mm) {
            callback
        } else {
            Value::NIL
        };
        it.close_scope(scope);
        callback.0
    })
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn nupp_rt_binary_callback(
    ctx: *mut Ctx,
    callback: u64,
    left: u64,
    right: u64,
) -> u64 {
    service(ctx, |it| {
        let (callback, left, right) = (Value(callback), Value(left), Value(right));
        let scope = it.open_scope();
        it.handles.extend([callback, left, right]);
        let result = it
            .call_value(callback, &[left, right])
            .first()
            .copied()
            .unwrap_or(Value::NIL);
        it.close_scope(scope);
        result.0
    })
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn nupp_rt_order_error(ctx: *mut Ctx, left: u64, right: u64) {
    service(ctx, |it| {
        let (a, b) = (
            crate::builtins::type_name(it, Value(left)),
            crate::builtins::type_name(it, Value(right)),
        );
        if a == b {
            it.lua_error(&format!("attempt to compare two {a} values"))
        } else {
            it.lua_error(&format!("attempt to compare {a} with {b}"))
        }
    });
}


#[unsafe(no_mangle)]
pub unsafe extern "C" fn nupp_rt_numeric_word(ctx: *mut Ctx, value: u64, unsigned: i64) -> u64 {
    service(ctx, |it| numeric::word(it, Value(value), unsigned != 0))
}
