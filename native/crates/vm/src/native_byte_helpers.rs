//! Temporary byte allocation, growable storage and error services. Instruction
//! operands, span clamping and scalar memory access belong to byteops.nupp.
use crate::interp::Interp;
use crate::threaded::{Ctx, ST_ERROR, enter_rust, sync};
use crate::value::Value;

fn service(ctx: *mut Ctx, body: impl FnOnce(&mut Interp) -> Value) -> u64 {
    let ctx = unsafe { &mut *ctx };
    let (it, _) = enter_rust(ctx);
    let result = it.guarded(body);
    if result == Value::ERROR {
        ctx.status = ST_ERROR;
    }
    sync(ctx, it);
    result.0
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn nupp_rt_byte_type_error(ctx: *mut Ctx, value: u64, write: i64) {
    service(ctx, |it| {
        if write != 0 {
            it.bytes_mut(Value(value));
        } else {
            it.bytes_of(Value(value));
        }
        Value::NIL
    });
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn nupp_rt_byte_range_error(
    ctx: *mut Ctx,
    kind: i64,
    index: u64,
    length: u64,
) {
    service(ctx, |it| match kind {
        0 => it.err("byte read out of range"),
        1 => it.err("word read out of range"),
        2 => it.err("byte write out of range"),
        3 => it.err("word write out of range"),
        4 => panic!("index out of bounds: the len is {length} but the index is {index}"),
        5 => panic!("range end index {index} out of range for slice of length {length}"),
        6 => panic!("range start index {index} out of range for slice of length {length}"),
        _ => unreachable!("byte range error kind"),
    });
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn nupp_rt_allocate_bytes(ctx: *mut Ctx, length: u64) -> u64 {
    service(ctx, |it| it.heap_new_bytes(length as usize))
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn nupp_rt_allocate_buffer(ctx: *mut Ctx) -> u64 {
    service(ctx, |it| it.heap_new_buffer())
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn nupp_rt_append_bytes(
    ctx: *mut Ctx,
    buffer: u64,
    source: u64,
    offset: u64,
    length: u64,
) {
    service(ctx, |it| {
        // Snapshot before any resize: source can alias the buffer or a view
        // into its current backing allocation. The Nupp caller bounds the span.
        let text = it.bytes_of(Value(source))[offset as usize..(offset + length) as usize].to_vec();
        it.buf_append(Value(buffer), &text);
        Value::NIL
    });
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn nupp_rt_consume_buffer(ctx: *mut Ctx, buffer: u64) -> u64 {
    service(ctx, |it| it.buf_finish(Value(buffer)))
}
