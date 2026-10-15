//! The VM's compression primitives: `nupp.runtime.provider.nativecompression`
//! on the VM is Nupp over these, as on LuaJIT it is Nupp over the same crate's
//! C ABI. Streams are numbered handles; each step reads and writes the byte
//! spans it is handed in place, so nothing is copied through a string.
use crate::{builtins::Outs, interp::Interp, value::Value};
use nupp_native_compression::{Decoder, Encoder, Format, Step, StreamError};
use std::collections::HashMap;

/// Live encoders and decoders by handle; a handle is spent by its release.
#[derive(Default)]
pub struct Streams { next: u64, encoders: HashMap<u64, Encoder>, decoders: HashMap<u64, Decoder> }

fn arg(args: &[Value], i: usize) -> Value { args.get(i).copied().unwrap_or(Value::NIL) }
/// A failure: `nils` empty results, then the message where the provider's
/// signature carries its reason.
fn failed_after(it: &mut Interp, nils: usize, message: &str) -> Outs {
    let message = it.heap_new_string(message);
    let mut o = Outs::new(); for _ in 0..nils { o.push(Value::NIL); } o.push(message); o
}
fn failed(it: &mut Interp, message: &str) -> Outs { failed_after(it, 1, message) }
fn format(it: &Interp, v: Value) -> Format {
    Format::from_abi(v.as_num() as u32).unwrap_or_else(|| it.err("nupp: unknown compression format"))
}
fn handle(v: Value) -> u64 { v.as_num() as u64 }

/// Runs one step over the input span (when given) and the output span, in
/// place: the heap does not move and nothing here allocates until the step
/// has returned, so the raw views stay valid across it.
fn step(it: &mut Interp, input: Option<Value>, output: Value, run: impl FnOnce(&mut Interp, &[u8], &mut [u8]) -> Option<Result<Step, StreamError>>) -> Outs {
    let source: &[u8] = match input {
        Some(span) => { let (owner, start, n) = crate::storage::byte_span(it, span, false); let b = &it.bytes_of(owner)[start..start + n]; unsafe { std::slice::from_raw_parts(b.as_ptr(), n) } }
        None => &[],
    };
    let (owner, start, n) = crate::storage::byte_span(it, output, true);
    let room = unsafe { std::slice::from_raw_parts_mut(it.bytes_mut(owner)[start..start + n].as_mut_ptr(), n) };
    let nils = if input.is_some() { 3 } else { 2 };
    let Some(result) = run(it, source, room) else { return failed_after(it, nils, "the compression stream is closed") };
    match result {
        Ok(step) => {
            let mut o = Outs::new();
            if input.is_some() { o.push(Value::num(step.consumed as f64)); }
            o.push(Value::num(step.written as f64)); o.push(Value::num(step.status as u32 as f64));
            o
        }
        Err(problem) => failed_after(it, nils, &problem.to_string()),
    }
}

pub fn call(it: &mut Interp, name: &str, args: &[Value]) -> Outs {
    let op = name.strip_prefix("ncompression.").unwrap_or(name);
    match op {
        "encoderCreate" => {
            let level = arg(args, 1).as_num();
            if !(0.0..=9.0).contains(&level) || level.fract() != 0.0 { return failed(it, "compression level must be between zero and nine"); }
            let encoder = Encoder::new(format(it, arg(args, 0)), level as u32);
            let id = it.ncompression.next; it.ncompression.next += 1;
            it.ncompression.encoders.insert(id, encoder);
            let mut o = Outs::new(); o.push(Value::num(id as f64)); o
        }
        "decoderCreate" => {
            let decoder = Decoder::new(format(it, arg(args, 0)), arg(args, 1).truthy());
            let id = it.ncompression.next; it.ncompression.next += 1;
            it.ncompression.decoders.insert(id, decoder);
            let mut o = Outs::new(); o.push(Value::num(id as f64)); o
        }
        "encoderWrite" => { let id = handle(arg(args, 0)); step(it, Some(arg(args, 1)), arg(args, 2), |it, i, o| it.ncompression.encoders.get_mut(&id).map(|e| e.write(i, o))) }
        "encoderFlush" => { let id = handle(arg(args, 0)); step(it, None, arg(args, 1), |it, _, o| it.ncompression.encoders.get_mut(&id).map(|e| e.flush(o))) }
        "encoderFinish" => { let id = handle(arg(args, 0)); step(it, None, arg(args, 1), |it, _, o| it.ncompression.encoders.get_mut(&id).map(|e| e.finish(o))) }
        "decoderRead" => { let id = handle(arg(args, 0)); step(it, Some(arg(args, 1)), arg(args, 2), |it, i, o| it.ncompression.decoders.get_mut(&id).map(|d| d.read(i, o))) }
        "decoderFinishInput" => { let id = handle(arg(args, 0)); step(it, None, arg(args, 1), |it, _, o| it.ncompression.decoders.get_mut(&id).map(|d| d.finish_input(o))) }
        "encoderRelease" | "decoderRelease" => {
            let id = handle(arg(args, 0));
            let released = if op == "encoderRelease" { it.ncompression.encoders.remove(&id).is_some() } else { it.ncompression.decoders.remove(&id).is_some() };
            let mut o = Outs::new(); o.push(Value::boolean(released)); o
        }
        _ => it.err(&format!("unknown compression operation {name}")),
    }
}
