//! C ABI translation for the safe WGPU provider.

use nupp_native_abi::{Arena, Handle, Status, set_last_error};
use nupp_native_gpu::{GpuContext, GpuError, KernelDescriptor};
use std::ffi::{c_char, c_void};
use std::panic::{AssertUnwindSafe, catch_unwind};
use std::ptr;
use std::sync::{Mutex, OnceLock};
use std::thread::{self, ThreadId};

struct Context {
    owner: ThreadId,
    gpu: GpuContext,
}

fn contexts() -> &'static Mutex<Arena<Context>> {
    static CONTEXTS: OnceLock<Mutex<Arena<Context>>> = OnceLock::new();
    CONTEXTS.get_or_init(|| Mutex::new(Arena::new()))
}

fn fail(status: Status, error: impl std::fmt::Display) -> i32 {
    set_last_error(format_args!("gpu: {error}"));
    status.code()
}

fn gpu_status(error: &GpuError) -> Status {
    match error {
        GpuError::InvalidArgument(_)
        | GpuError::OutOfBounds { .. }
        | GpuError::WrongHandle { .. }
        | GpuError::MissingBinding { .. }
        | GpuError::DownloadPending(_)
        | GpuError::DownloadNotReady(_)
        | GpuError::DownloadMismatch { .. }
        | GpuError::AdapterUnavailable(_) => Status::InvalidArgument,
        GpuError::StaleHandle(_) => Status::StaleHandle,
        GpuError::Capacity => Status::Capacity,
        GpuError::DeviceRequest(_)
        | GpuError::Validation(_)
        | GpuError::Device(_)
        | GpuError::Poll(_)
        | GpuError::Map(_)
        | GpuError::Internal(_) => Status::Internal,
    }
}

fn boundary(call: impl FnOnce() -> Result<(), (Status, String)>) -> i32 {
    match catch_unwind(AssertUnwindSafe(call)) {
        Ok(Ok(())) => Status::Ok.code(),
        Ok(Err((status, message))) => fail(status, message),
        Err(_) => fail(Status::Internal, "native provider panicked"),
    }
}

fn with_context<T>(
    raw: u64,
    call: impl FnOnce(&mut GpuContext) -> Result<T, GpuError>,
) -> Result<T, (Status, String)> {
    let mut arena = contexts()
        .lock()
        .map_err(|_| (Status::Internal, "context store is poisoned".to_owned()))?;
    let context = arena
        .get_mut(Handle::from_raw(raw))
        .map_err(|_| (Status::StaleHandle, "context handle is stale".to_owned()))?;
    if context.owner != thread::current().id() {
        return Err((
            Status::InvalidArgument,
            "context was used from a thread other than its owner".to_owned(),
        ));
    }
    call(&mut context.gpu).map_err(|error| (gpu_status(&error), error.to_string()))
}

unsafe fn input<'a>(
    data: *const u8,
    length: usize,
    name: &str,
) -> Result<&'a [u8], (Status, String)> {
    if length == 0 {
        return Ok(&[]);
    }
    if data.is_null() {
        return Err((Status::InvalidArgument, format!("{name} pointer is null")));
    }
    // SAFETY: every exported caller promises this readable range for the call.
    Ok(unsafe { std::slice::from_raw_parts(data, length) })
}

unsafe fn output_handle(output: *mut u64, value: u64) -> Result<(), (Status, String)> {
    if output.is_null() {
        return Err((Status::InvalidArgument, "handle output is null".to_owned()));
    }
    // SAFETY: the exported ABI requires writable storage for one u64.
    unsafe { output.write(value) };
    Ok(())
}

fn require_handle_output(output: *mut u64) -> Result<(), (Status, String)> {
    if output.is_null() {
        Err((Status::InvalidArgument, "handle output is null".to_owned()))
    } else {
        Ok(())
    }
}

#[unsafe(no_mangle)]
/// Creates one thread-affine WGPU context.
///
/// # Safety
/// `output` must be writable for one `u64`.
pub unsafe extern "C" fn nuppNativeV2GpuContextCreate(output: *mut u64) -> i32 {
    boundary(|| {
        require_handle_output(output)?;
        let gpu = GpuContext::new().map_err(|error| (gpu_status(&error), error.to_string()))?;
        let handle = contexts()
            .lock()
            .map_err(|_| (Status::Internal, "context store is poisoned".to_owned()))?
            .insert(Context {
                owner: thread::current().id(),
                gpu,
            })
            .map_err(|status| (status, "context capacity is exhausted".to_owned()))?;
        // SAFETY: forwarded from this function's ABI contract.
        unsafe { output_handle(output, handle.raw()) }
    })
}

#[unsafe(no_mangle)]
/// Copies the WGPU backend and adapter name for one live context.
///
/// # Safety
/// `output_length` must be writable. When `capacity` is nonzero, `output` must
/// be writable for that many bytes, including the trailing NUL. A null output
/// with zero capacity performs a size query. The reported length excludes NUL.
pub unsafe extern "C" fn nuppNativeV2GpuContextDescription(
    raw: u64,
    output: *mut u8,
    capacity: usize,
    output_length: *mut usize,
) -> i32 {
    boundary(|| {
        if output_length.is_null() || (capacity != 0 && output.is_null()) {
            return Err((
                Status::InvalidArgument,
                "context description output is null".to_owned(),
            ));
        }
        let adapter = with_context(raw, |gpu| Ok(gpu.adapter()))?;
        let description = format!("{}: {}", adapter.backend, adapter.name);
        // SAFETY: forwarded from this function's ABI contract.
        unsafe { output_length.write(description.len()) };
        if capacity == 0 {
            return Ok(());
        }
        if capacity <= description.len() {
            return Err((
                Status::Capacity,
                "context description output is too small".to_owned(),
            ));
        }
        // SAFETY: the capacity check proves the payload and trailing NUL fit.
        unsafe {
            ptr::copy_nonoverlapping(description.as_ptr(), output, description.len());
            output.add(description.len()).write(0);
        }
        Ok(())
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn nuppNativeV2GpuContextRelease(raw: u64) -> i32 {
    boundary(|| {
        let mut arena = contexts()
            .lock()
            .map_err(|_| (Status::Internal, "context store is poisoned".to_owned()))?;
        let context = arena
            .get(Handle::from_raw(raw))
            .map_err(|_| (Status::StaleHandle, "context handle is stale".to_owned()))?;
        if context.owner != thread::current().id() {
            return Err((
                Status::InvalidArgument,
                "context was released from a thread other than its owner".to_owned(),
            ));
        }
        arena
            .remove(Handle::from_raw(raw))
            .map_err(|_| (Status::StaleHandle, "context handle is stale".to_owned()))?;
        Ok(())
    })
}

#[unsafe(no_mangle)]
/// Allocates one resident byte buffer.
///
/// # Safety
/// `output` must be writable for one `u64`.
pub unsafe extern "C" fn nuppNativeV2GpuBufferCreate(
    context: u64,
    size: u64,
    output: *mut u64,
) -> i32 {
    boundary(|| {
        require_handle_output(output)?;
        let handle = with_context(context, |gpu| gpu.create_buffer(size))?;
        // SAFETY: forwarded from this function's ABI contract.
        unsafe { output_handle(output, handle) }
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn nuppNativeV2GpuBufferRelease(context: u64, buffer: u64) -> i32 {
    boundary(|| with_context(context, |gpu| gpu.release_buffer(buffer)).map(|_| ()))
}

#[unsafe(no_mangle)]
/// Uploads one checked byte range.
///
/// # Safety
/// When `length` is nonzero, `data` must be readable for `length` bytes.
pub unsafe extern "C" fn nuppNativeV2GpuBufferUpload(
    context: u64,
    buffer: u64,
    offset: u64,
    data: *const c_void,
    length: usize,
) -> i32 {
    boundary(|| {
        // SAFETY: forwarded from this function's ABI contract.
        let bytes = unsafe { input(data.cast(), length, "upload") }?;
        with_context(context, |gpu| gpu.upload(buffer, offset, bytes))
    })
}

#[unsafe(no_mangle)]
/// Compiles canonical SPIR-V with its explicit binding shape.
///
/// # Safety
/// The SPIR-V and entrypoint pointers must cover their named byte lengths;
/// `output` must be writable for one `u64`.
#[allow(clippy::too_many_arguments)]
pub unsafe extern "C" fn nuppNativeV2GpuKernelCreate(
    context: u64,
    spirv: *const u8,
    spirv_length: usize,
    entrypoint: *const c_char,
    entrypoint_length: usize,
    readonly_bindings: u32,
    writable_bindings: u32,
    uniform_size: u64,
    workgroup_x: u32,
    workgroup_y: u32,
    workgroup_z: u32,
    output: *mut u64,
) -> i32 {
    boundary(|| {
        require_handle_output(output)?;
        // SAFETY: forwarded from this function's ABI contract.
        let spirv = unsafe { input(spirv, spirv_length, "SPIR-V") }?;
        // SAFETY: the entrypoint has the same byte-oriented pointer contract.
        let entrypoint_bytes =
            unsafe { input(entrypoint.cast(), entrypoint_length, "entrypoint") }?;
        let entrypoint = std::str::from_utf8(entrypoint_bytes).map_err(|_| {
            (
                Status::InvalidArgument,
                "entrypoint is not valid UTF-8".to_owned(),
            )
        })?;
        let descriptor = KernelDescriptor {
            spirv,
            entry_point: entrypoint,
            readonly_bindings,
            writable_bindings,
            uniform_size,
            workgroup_size: [workgroup_x, workgroup_y, workgroup_z],
        };
        let handle = with_context(context, |gpu| gpu.create_kernel(&descriptor))?;
        // SAFETY: forwarded from this function's ABI contract.
        unsafe { output_handle(output, handle) }
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn nuppNativeV2GpuKernelRelease(context: u64, kernel: u64) -> i32 {
    boundary(|| with_context(context, |gpu| gpu.release_kernel(kernel)).map(|_| ()))
}

#[unsafe(no_mangle)]
/// Creates an empty binding set for one kernel.
///
/// # Safety
/// `output` must be writable for one `u64`.
pub unsafe extern "C" fn nuppNativeV2GpuBindingsCreate(
    context: u64,
    kernel: u64,
    output: *mut u64,
) -> i32 {
    boundary(|| {
        require_handle_output(output)?;
        let handle = with_context(context, |gpu| gpu.create_bindings(kernel))?;
        // SAFETY: forwarded from this function's ABI contract.
        unsafe { output_handle(output, handle) }
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn nuppNativeV2GpuBindingsRelease(context: u64, bindings: u64) -> i32 {
    boundary(|| with_context(context, |gpu| gpu.release_bindings(bindings)).map(|_| ()))
}

#[unsafe(no_mangle)]
#[allow(clippy::too_many_arguments)]
pub extern "C" fn nuppNativeV2GpuBindingsSetBuffer(
    context: u64,
    bindings: u64,
    writable: i32,
    slot: u32,
    buffer: u64,
    offset: u64,
    size: u64,
) -> i32 {
    boundary(|| {
        with_context(context, |gpu| {
            if writable == 0 {
                gpu.set_read_buffer(bindings, slot, buffer, offset, size)
            } else if writable == 1 {
                gpu.set_write_buffer(bindings, slot, buffer, offset, size)
            } else {
                Err(GpuError::InvalidArgument(
                    "writable flag must be zero or one".to_owned(),
                ))
            }
        })
    })
}

#[unsafe(no_mangle)]
/// Enqueues one logical dispatch.
///
/// # Safety
/// When `uniform_length` is nonzero, `uniforms` must be readable for that
/// length.
#[allow(clippy::too_many_arguments)]
pub unsafe extern "C" fn nuppNativeV2GpuDispatch(
    context: u64,
    bindings: u64,
    work_items_x: u32,
    work_items_y: u32,
    work_items_z: u32,
    uniforms: *const u8,
    uniform_length: usize,
) -> i32 {
    boundary(|| {
        // SAFETY: forwarded from this function's ABI contract.
        let uniforms = unsafe { input(uniforms, uniform_length, "uniform") }?;
        with_context(context, |gpu| {
            gpu.dispatch(
                bindings,
                [work_items_x, work_items_y, work_items_z],
                uniforms,
            )
        })
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn nuppNativeV2GpuDownloadQueue(
    context: u64,
    buffer: u64,
    offset: u64,
    size: u64,
) -> i32 {
    boundary(|| with_context(context, |gpu| gpu.queue_download(buffer, offset, size)))
}

#[unsafe(no_mangle)]
pub extern "C" fn nuppNativeV2GpuSynchronize(context: u64) -> i32 {
    boundary(|| with_context(context, GpuContext::synchronize))
}

#[unsafe(no_mangle)]
/// Copies one synchronized download into caller-owned storage.
///
/// # Safety
/// `output` must be writable for `capacity` bytes when capacity is nonzero.
pub unsafe extern "C" fn nuppNativeV2GpuDownloadRead(
    context: u64,
    buffer: u64,
    offset: u64,
    size: u64,
    output: *mut c_void,
    capacity: usize,
) -> i32 {
    boundary(|| {
        let expected = usize::try_from(size).map_err(|_| {
            (
                Status::Capacity,
                "download does not fit the host address space".to_owned(),
            )
        })?;
        if capacity < expected || (expected != 0 && output.is_null()) {
            return Err((Status::Capacity, "download output is too small".to_owned()));
        }
        let bytes = with_context(context, |gpu| gpu.read_download(buffer, offset, size))?;
        if !bytes.is_empty() {
            // SAFETY: capacity was checked before consuming the queued result.
            unsafe { ptr::copy_nonoverlapping(bytes.as_ptr(), output.cast(), bytes.len()) };
        }
        Ok(())
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn invalid_contexts_are_reported_without_pointer_dereferences() {
        assert_eq!(
            nuppNativeV2GpuBufferRelease(0, 1),
            Status::StaleHandle.code()
        );
        let mut output = [0_u8; 64];
        let mut length = 0_usize;
        // SAFETY: both outputs are valid for their declared capacities.
        assert_eq!(
            unsafe {
                nuppNativeV2GpuContextDescription(0, output.as_mut_ptr(), output.len(), &mut length)
            },
            Status::StaleHandle.code()
        );
    }
}
