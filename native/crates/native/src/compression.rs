use nupp_native_abi::{Arena, Handle, Status};
use nupp_native_compression::{Decoder, Encoder, Format, Step};
use std::ptr;
use std::sync::{Mutex, OnceLock};

fn encoders() -> &'static Mutex<Arena<Encoder>> {
    static ENCODERS: OnceLock<Mutex<Arena<Encoder>>> = OnceLock::new();
    ENCODERS.get_or_init(|| Mutex::new(Arena::new()))
}

fn decoders() -> &'static Mutex<Arena<Decoder>> {
    static DECODERS: OnceLock<Mutex<Arena<Decoder>>> = OnceLock::new();
    DECODERS.get_or_init(|| Mutex::new(Arena::new()))
}

fn format(value: u32) -> Result<Format, i32> {
    Format::from_abi(value).ok_or_else(|| {
        super::failed(
            Status::InvalidArgument,
            "compression format must be gzip, zlib, or deflate-raw",
        )
    })
}

fn outputs(consumed: *mut usize, written: *mut usize, state: *mut u32) -> Result<(), i32> {
    if consumed.is_null() || written.is_null() || state.is_null() {
        return Err(super::failed(
            Status::InvalidArgument,
            "compression step output is null",
        ));
    }
    Ok(())
}

fn destination<'a>(data: *mut u8, capacity: usize) -> Result<&'a mut [u8], i32> {
    if capacity == 0 {
        return Err(super::failed(
            Status::InvalidArgument,
            "compression output capacity must be positive",
        ));
    }
    if data.is_null() {
        return Err(super::failed(
            Status::InvalidArgument,
            "compression output pointer is null",
        ));
    }
    // SAFETY: the caller promises a writable range for this call.
    Ok(unsafe { std::slice::from_raw_parts_mut(data, capacity) })
}

unsafe fn write_step(step: Step, consumed: *mut usize, written: *mut usize, state: *mut u32) {
    // SAFETY: the caller was checked by `outputs` before the operation ran.
    unsafe {
        ptr::write(consumed, step.consumed);
        ptr::write(written, step.written);
        ptr::write(state, step.status as u32);
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nuppNativeCompressionEncoderCreate(
    format_id: u32,
    level: u32,
    output: *mut u64,
) -> i32 {
    if output.is_null() {
        return super::failed(
            Status::InvalidArgument,
            "compression encoder output is null",
        );
    }
    if level > 9 {
        return super::failed(
            Status::InvalidArgument,
            "compression level must be between zero and nine",
        );
    }
    let format = match format(format_id) {
        Ok(value) => value,
        Err(status) => return status,
    };
    let handle = match encoders().lock() {
        Ok(mut arena) => match arena.insert(Encoder::new(format, level)) {
            Ok(handle) => handle,
            Err(status) => {
                return super::failed(status, "compression encoder capacity is exhausted");
            }
        },
        Err(_) => {
            return super::failed(Status::Internal, "compression encoder store is poisoned");
        }
    };
    // SAFETY: the caller supplied writable storage for one u64.
    unsafe { output.write(handle.raw()) };
    Status::Ok.code()
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nuppNativeCompressionEncoderWrite(
    raw: u64,
    input_data: *const u8,
    input_length: usize,
    output_data: *mut u8,
    output_capacity: usize,
    consumed: *mut usize,
    written: *mut usize,
    state: *mut u32,
) -> i32 {
    if let Err(status) = outputs(consumed, written, state) {
        return status;
    }
    let input = match super::input(input_data, input_length) {
        Ok(value) => value,
        Err(status) => return status,
    };
    let output = match destination(output_data, output_capacity) {
        Ok(value) => value,
        Err(status) => return status,
    };
    let step = match encoders().lock() {
        Ok(mut arena) => match arena.get_mut(Handle::from_raw(raw)) {
            Ok(encoder) => match encoder.write(input, output) {
                Ok(step) => step,
                Err(error) => return super::failed(Status::Internal, &error.to_string()),
            },
            Err(status) => return super::failed(status, "compression encoder handle is stale"),
        },
        Err(_) => return super::failed(Status::Internal, "compression encoder store is poisoned"),
    };
    // SAFETY: output pointers were checked before the stream operation.
    unsafe { write_step(step, consumed, written, state) };
    Status::Ok.code()
}

unsafe fn encoder_empty_step(
    raw: u64,
    output_data: *mut u8,
    output_capacity: usize,
    written: *mut usize,
    state: *mut u32,
    finish: bool,
) -> i32 {
    let mut consumed = 0usize;
    if let Err(status) = outputs(&mut consumed, written, state) {
        return status;
    }
    let output = match destination(output_data, output_capacity) {
        Ok(value) => value,
        Err(status) => return status,
    };
    let step = match encoders().lock() {
        Ok(mut arena) => match arena.get_mut(Handle::from_raw(raw)) {
            Ok(encoder) => {
                let result = if finish {
                    encoder.finish(output)
                } else {
                    encoder.flush(output)
                };
                match result {
                    Ok(step) => step,
                    Err(error) => return super::failed(Status::Internal, &error.to_string()),
                }
            }
            Err(status) => return super::failed(status, "compression encoder handle is stale"),
        },
        Err(_) => return super::failed(Status::Internal, "compression encoder store is poisoned"),
    };
    // SAFETY: output pointers were checked before the stream operation.
    unsafe { write_step(step, &mut consumed, written, state) };
    Status::Ok.code()
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nuppNativeCompressionEncoderFlush(
    raw: u64,
    output_data: *mut u8,
    output_capacity: usize,
    written: *mut usize,
    state: *mut u32,
) -> i32 {
    // SAFETY: this forwards the caller-owned output ranges unchanged.
    unsafe { encoder_empty_step(raw, output_data, output_capacity, written, state, false) }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nuppNativeCompressionEncoderFinish(
    raw: u64,
    output_data: *mut u8,
    output_capacity: usize,
    written: *mut usize,
    state: *mut u32,
) -> i32 {
    // SAFETY: this forwards the caller-owned output ranges unchanged.
    unsafe { encoder_empty_step(raw, output_data, output_capacity, written, state, true) }
}

#[unsafe(no_mangle)]
pub extern "C" fn nuppNativeCompressionEncoderRelease(raw: u64) -> i32 {
    match encoders().lock() {
        Ok(mut arena) => match arena.remove(Handle::from_raw(raw)) {
            Ok(_) => Status::Ok.code(),
            Err(status) => super::failed(status, "compression encoder handle is stale"),
        },
        Err(_) => super::failed(Status::Internal, "compression encoder store is poisoned"),
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nuppNativeCompressionDecoderCreate(
    format_id: u32,
    concatenated_members: i32,
    output: *mut u64,
) -> i32 {
    if output.is_null() {
        return super::failed(
            Status::InvalidArgument,
            "compression decoder output is null",
        );
    }
    let format = match format(format_id) {
        Ok(value) => value,
        Err(status) => return status,
    };
    let handle = match decoders().lock() {
        Ok(mut arena) => match arena.insert(Decoder::new(format, concatenated_members != 0)) {
            Ok(handle) => handle,
            Err(status) => {
                return super::failed(status, "compression decoder capacity is exhausted");
            }
        },
        Err(_) => {
            return super::failed(Status::Internal, "compression decoder store is poisoned");
        }
    };
    // SAFETY: the caller supplied writable storage for one u64.
    unsafe { output.write(handle.raw()) };
    Status::Ok.code()
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nuppNativeCompressionDecoderRead(
    raw: u64,
    input_data: *const u8,
    input_length: usize,
    output_data: *mut u8,
    output_capacity: usize,
    consumed: *mut usize,
    written: *mut usize,
    state: *mut u32,
) -> i32 {
    if let Err(status) = outputs(consumed, written, state) {
        return status;
    }
    let input = match super::input(input_data, input_length) {
        Ok(value) => value,
        Err(status) => return status,
    };
    let output = match destination(output_data, output_capacity) {
        Ok(value) => value,
        Err(status) => return status,
    };
    let step = match decoders().lock() {
        Ok(mut arena) => match arena.get_mut(Handle::from_raw(raw)) {
            Ok(decoder) => match decoder.read(input, output) {
                Ok(step) => step,
                Err(error) => {
                    return super::failed(Status::InvalidArgument, &error.to_string());
                }
            },
            Err(status) => return super::failed(status, "compression decoder handle is stale"),
        },
        Err(_) => return super::failed(Status::Internal, "compression decoder store is poisoned"),
    };
    // SAFETY: output pointers were checked before the stream operation.
    unsafe { write_step(step, consumed, written, state) };
    Status::Ok.code()
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn nuppNativeCompressionDecoderFinishInput(
    raw: u64,
    output_data: *mut u8,
    output_capacity: usize,
    written: *mut usize,
    state: *mut u32,
) -> i32 {
    let mut consumed = 0usize;
    if let Err(status) = outputs(&mut consumed, written, state) {
        return status;
    }
    let output = match destination(output_data, output_capacity) {
        Ok(value) => value,
        Err(status) => return status,
    };
    let step = match decoders().lock() {
        Ok(mut arena) => match arena.get_mut(Handle::from_raw(raw)) {
            Ok(decoder) => match decoder.finish_input(output) {
                Ok(step) => step,
                Err(error) => {
                    return super::failed(Status::InvalidArgument, &error.to_string());
                }
            },
            Err(status) => return super::failed(status, "compression decoder handle is stale"),
        },
        Err(_) => return super::failed(Status::Internal, "compression decoder store is poisoned"),
    };
    // SAFETY: output pointers were checked before the stream operation.
    unsafe { write_step(step, &mut consumed, written, state) };
    Status::Ok.code()
}

#[unsafe(no_mangle)]
pub extern "C" fn nuppNativeCompressionDecoderRelease(raw: u64) -> i32 {
    match decoders().lock() {
        Ok(mut arena) => match arena.remove(Handle::from_raw(raw)) {
            Ok(_) => Status::Ok.code(),
            Err(status) => super::failed(status, "compression decoder handle is stale"),
        },
        Err(_) => super::failed(Status::Internal, "compression decoder store is poisoned"),
    }
}
