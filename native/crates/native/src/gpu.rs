//! C ABI translation for the safe WGPU provider.

use nupp_native_abi::{Arena, Handle, Status, set_last_error};
use nupp_native_gpu::{GpuContext, GpuError, KernelDescriptor};
use std::ffi::{c_char, c_void};
use std::panic::{AssertUnwindSafe, catch_unwind};
use std::ptr;
use std::sync::{Arc, Mutex, MutexGuard, OnceLock, PoisonError};
use std::thread::{self, ThreadId};

/// One context and the thread that owns it. Each context has its own lock,
/// so a long Synchronize on one never stalls another thread's context.
struct Context {
    owner: ThreadId,
    gpu: Mutex<GpuContext>,
}

/// The process-wide handle table. It is held only to look a handle up,
/// insert or remove one, and nothing that can panic runs under it, so a
/// poisoned lock says nothing about its contents.
fn contexts() -> MutexGuard<'static, Arena<Arc<Context>>> {
    static CONTEXTS: OnceLock<Mutex<Arena<Arc<Context>>>> = OnceLock::new();
    CONTEXTS
        .get_or_init(|| Mutex::new(Arena::new()))
        .lock()
        .unwrap_or_else(PoisonError::into_inner)
}

fn owned_context(raw: u64, action: &str) -> Result<Arc<Context>, (Status, String)> {
    let context = contexts()
        .get(Handle::from_raw(raw))
        .map(Arc::clone)
        .map_err(|_| (Status::StaleHandle, "context handle is stale".to_owned()))?;
    if context.owner != thread::current().id() {
        return Err((
            Status::InvalidArgument,
            format!("context was {action} from a thread other than its owner"),
        ));
    }
    Ok(context)
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
    let context = owned_context(raw, "used")?;
    // A panic inside an earlier call may have left this context's device
    // half-updated, so it refuses further work; it can still be released,
    // and every other context is untouched.
    let mut gpu = context.gpu.lock().map_err(|_| {
        (
            Status::Internal,
            "context is unusable after an earlier call on it panicked".to_owned(),
        )
    })?;
    call(&mut gpu).map_err(|error| (gpu_status(&error), error.to_string()))
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
/// Configures JSONL cost output; an empty path restores the environment default.
/// # Safety
/// `path` must be readable for `length` bytes when nonzero.
pub unsafe extern "C" fn nuppNativeGpuCostsOutput(path: *const u8, length: usize) -> i32 {
    boundary(|| {
        let bytes = unsafe { input(path, length, "cost output") }?;
        let path =
            std::str::from_utf8(bytes).map_err(|e| (Status::InvalidArgument, e.to_string()))?;
        nupp_native_gpu::costs::configure((!path.is_empty()).then_some(path))
            .map_err(|e| (gpu_status(&e), e.to_string()))
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn nuppNativeGpuCostsEnabled() -> i32 {
    i32::from(nupp_native_gpu::costs::enabled())
}

#[unsafe(no_mangle)]
/// Associates an authored kernel or typed buffer with its native identity.
/// # Safety
/// `data` must be readable for `length` bytes.
pub unsafe extern "C" fn nuppNativeGpuCostMetadata(
    context: u64,
    handle: u64,
    kernel: i32,
    data: *const u8,
    length: usize,
) -> i32 {
    boundary(|| {
        let bytes = unsafe { input(data, length, "cost metadata") }?;
        with_context(context, |gpu| gpu.metadata(handle, kernel != 0, bytes))
    })
}

#[unsafe(no_mangle)]
/// Creates one thread-affine WGPU context.
///
/// # Safety
/// `output` must be writable for one `u64`.
pub unsafe extern "C" fn nuppNativeGpuContextCreate(output: *mut u64) -> i32 {
    boundary(|| {
        require_handle_output(output)?;
        let gpu = GpuContext::new().map_err(|error| (gpu_status(&error), error.to_string()))?;
        let handle = contexts()
            .insert(Arc::new(Context {
                owner: thread::current().id(),
                gpu: Mutex::new(gpu),
            }))
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
pub unsafe extern "C" fn nuppNativeGpuContextDescription(
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
pub extern "C" fn nuppNativeGpuContextRelease(raw: u64) -> i32 {
    boundary(|| {
        owned_context(raw, "released")?;
        let context = contexts()
            .remove(Handle::from_raw(raw))
            .map_err(|_| (Status::StaleHandle, "context handle is stale".to_owned()))?;
        // The owner thread is the only one that can reach this context, and
        // it is here, so no call on it is in progress.
        let Ok(mut gpu) = context.gpu.lock() else {
            return Ok(());
        };
        if nupp_native_gpu::costs::enabled() {
            gpu.synchronize()
                .map_err(|e| (gpu_status(&e), e.to_string()))?;
            let id = gpu.cost_id();
            let start = nupp_native_gpu::costs::clock();
            drop(gpu);
            drop(context);
            nupp_native_gpu::costs::record(
                id,
                "contextCleanup",
                nupp_native_gpu::costs::cleanup(start),
            );
        }
        Ok(())
    })
}

#[unsafe(no_mangle)]
/// Allocates one resident byte buffer.
///
/// # Safety
/// `output` must be writable for one `u64`.
pub unsafe extern "C" fn nuppNativeGpuBufferCreate(
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
pub extern "C" fn nuppNativeGpuBufferRelease(context: u64, buffer: u64) -> i32 {
    boundary(|| with_context(context, |gpu| gpu.release_buffer(buffer)).map(|_| ()))
}

#[unsafe(no_mangle)]
/// Uploads one checked byte range.
///
/// # Safety
/// When `length` is nonzero, `data` must be readable for `length` bytes.
pub unsafe extern "C" fn nuppNativeGpuBufferUpload(
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
pub unsafe extern "C" fn nuppNativeGpuKernelCreate(
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
pub extern "C" fn nuppNativeGpuKernelRelease(context: u64, kernel: u64) -> i32 {
    boundary(|| with_context(context, |gpu| gpu.release_kernel(kernel)).map(|_| ()))
}

#[unsafe(no_mangle)]
/// Creates an empty binding set for one kernel.
///
/// # Safety
/// `output` must be writable for one `u64`.
pub unsafe extern "C" fn nuppNativeGpuBindingsCreate(
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
pub extern "C" fn nuppNativeGpuBindingsRelease(context: u64, bindings: u64) -> i32 {
    boundary(|| with_context(context, |gpu| gpu.release_bindings(bindings)).map(|_| ()))
}

#[unsafe(no_mangle)]
#[allow(clippy::too_many_arguments)]
pub extern "C" fn nuppNativeGpuBindingsSetBuffer(
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
pub unsafe extern "C" fn nuppNativeGpuDispatch(
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
pub extern "C" fn nuppNativeGpuDownloadQueue(
    context: u64,
    buffer: u64,
    offset: u64,
    size: u64,
) -> i32 {
    boundary(|| with_context(context, |gpu| gpu.queue_download(buffer, offset, size)))
}

#[unsafe(no_mangle)]
pub extern "C" fn nuppNativeGpuSynchronize(context: u64) -> i32 {
    boundary(|| with_context(context, GpuContext::synchronize))
}

#[unsafe(no_mangle)]
/// Copies one synchronized download into caller-owned storage.
///
/// # Safety
/// `output` must be writable for `capacity` bytes when capacity is nonzero.
pub unsafe extern "C" fn nuppNativeGpuDownloadRead(
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
        let start = nupp_native_gpu::costs::clock();
        if !bytes.is_empty() {
            // SAFETY: capacity was checked before consuming the queued result.
            unsafe { ptr::copy_nonoverlapping(bytes.as_ptr(), output.cast(), bytes.len()) };
        }
        with_context(context, |gpu| {
            gpu.copied_download(buffer, offset, size, start)
        })?;
        Ok(())
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::mpsc;
    use std::time::Duration;

    /// A context on this thread, or `None` when the machine has no adapter.
    fn context_when_available() -> Option<u64> {
        let mut context = 0;
        // SAFETY: the output is valid for one u64.
        match unsafe { nuppNativeGpuContextCreate(&mut context) } {
            0 => Some(context),
            _ if std::env::var_os("NUPP_REQUIRE_GPU").is_none() => None,
            status => panic!("required GPU adapter is unavailable: {status}"),
        }
    }

    #[test]
    fn one_context_at_work_does_not_stall_another_threads_context() {
        let Some(busy) = context_when_available() else {
            return;
        };
        let (entered, inside) = mpsc::channel();
        let (finished, done) = mpsc::channel();
        let other = thread::spawn(move || {
            inside.recv().unwrap();
            let Some(context) = context_when_available() else {
                return;
            };
            let mut buffer = 0;
            // SAFETY: the output is valid for one u64.
            let status = unsafe { nuppNativeGpuBufferCreate(context, 16, &mut buffer) };
            finished.send(status).unwrap();
            assert_eq!(nuppNativeGpuContextRelease(context), 0);
        });
        // Stands in for a long Synchronize: the busy context is held until
        // the other thread's calls on its own context have finished.
        let answered = with_context(busy, |_| {
            entered.send(()).unwrap();
            Ok(done.recv_timeout(Duration::from_secs(10)))
        })
        .unwrap();
        assert_eq!(answered, Ok(0), "the other context waited on this one");
        other.join().unwrap();
        assert_eq!(nuppNativeGpuContextRelease(busy), 0);
    }

    #[test]
    fn a_panicking_kernel_build_leaves_other_contexts_usable() {
        let Some(context) = context_when_available() else {
            return;
        };
        // One word of a valid module changed: naga's SPIR-V front end panics
        // on it rather than returning an error. Only unwinding builds reach
        // the boundary's catch; release builds abort (G-1).
        let spirv = include_bytes!("../testdata/naga-panic.spv");
        let mut kernel = 0;
        // SAFETY: the SPIR-V and entrypoint cover their lengths and the
        // output is valid for one u64.
        let status = unsafe {
            nuppNativeGpuKernelCreate(
                context,
                spirv.as_ptr(),
                spirv.len(),
                c"main".as_ptr(),
                4,
                1,
                1,
                16,
                64,
                1,
                1,
                &mut kernel,
            )
        };
        assert_ne!(status, 0);
        let mut buffer = 0;
        let fresh = context_when_available().expect("a new context after the panic");
        // SAFETY: the output is valid for one u64.
        assert_eq!(
            unsafe { nuppNativeGpuBufferCreate(fresh, 16, &mut buffer) },
            0
        );
        assert_eq!(nuppNativeGpuContextRelease(fresh), 0);
        assert_eq!(nuppNativeGpuContextRelease(context), 0);
    }

    #[test]
    fn invalid_contexts_are_reported_without_pointer_dereferences() {
        assert_eq!(nuppNativeGpuBufferRelease(0, 1), Status::StaleHandle.code());
        let mut output = [0_u8; 64];
        let mut length = 0_usize;
        // SAFETY: both outputs are valid for their declared capacities.
        assert_eq!(
            unsafe {
                nuppNativeGpuContextDescription(0, output.as_mut_ptr(), output.len(), &mut length)
            },
            Status::StaleHandle.code()
        );
    }
}
