//! Safe, handle-based native compute over WGPU.
//!
//! WGPU owns command and device-resource lifetimes. This crate adds the
//! language-facing invariants WGPU does not provide: context ownership,
//! resource kind checks, stale-handle rejection, byte-range validation, an
//! explicit synchronization boundary, and one queued readback per buffer.

#![forbid(unsafe_code)]

use serde_json::{Value, json};
use std::borrow::Cow;
use std::collections::HashMap;
use std::error::Error;
use std::fmt;
use std::num::NonZeroU64;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;
pub mod costs;
macro_rules! cost_record {
    ($context:expr, $operation:expr, $values:expr) => {
        if costs::enabled() {
            costs::record($context, $operation, $values);
        }
    };
}

use nupp_native_abi::{Arena, Handle, Status};

pub type BufferHandle = u64;
pub type KernelHandle = u64;
pub type BindingHandle = u64;

const COPY_ALIGNMENT: u64 = wgpu::COPY_BUFFER_ALIGNMENT;
const WAIT_TIMEOUT: Duration = Duration::from_secs(30);
static NEXT_PUBLIC_HANDLE: AtomicU64 = AtomicU64::new(1);

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ResourceKind {
    Buffer,
    Kernel,
    Binding,
}

impl fmt::Display for ResourceKind {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Buffer => formatter.write_str("buffer"),
            Self::Kernel => formatter.write_str("kernel"),
            Self::Binding => formatter.write_str("binding"),
        }
    }
}

#[derive(Debug, Eq, PartialEq)]
pub enum GpuError {
    AdapterUnavailable(String),
    DeviceRequest(String),
    InvalidArgument(String),
    OutOfBounds {
        operation: &'static str,
        offset: u64,
        size: u64,
        capacity: u64,
    },
    StaleHandle(u64),
    WrongHandle {
        handle: u64,
        expected: ResourceKind,
        actual: ResourceKind,
    },
    MissingBinding {
        writable: bool,
        slot: u32,
    },
    DownloadPending(BufferHandle),
    /// A synchronized download is waiting to be read.
    DownloadUnread(BufferHandle),
    DownloadNotReady(BufferHandle),
    DownloadMismatch {
        expected_offset: u64,
        expected_size: u64,
        requested_offset: u64,
        requested_size: u64,
    },
    Validation(String),
    Device(Vec<String>),
    Poll(String),
    Map(String),
    Capacity,
    /// The opt-in cost output could not be written. It never undoes the GPU
    /// work it was describing.
    CostOutput(String),
    Internal(&'static str),
}

impl fmt::Display for GpuError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::AdapterUnavailable(message) => {
                write!(
                    formatter,
                    "no suitable compute adapter is available: {message}"
                )
            }
            Self::DeviceRequest(message) => write!(formatter, "request GPU device: {message}"),
            Self::InvalidArgument(message) => formatter.write_str(message),
            Self::OutOfBounds {
                operation,
                offset,
                size,
                capacity,
            } => write!(
                formatter,
                "{operation} range {offset}..{} exceeds buffer size {capacity}",
                offset.saturating_add(*size)
            ),
            Self::StaleHandle(handle) => {
                write!(formatter, "unknown or released GPU handle {handle}")
            }
            Self::WrongHandle {
                handle,
                expected,
                actual,
            } => write!(
                formatter,
                "GPU handle {handle} is a {actual}, not a {expected}"
            ),
            Self::MissingBinding { writable, slot } => write!(
                formatter,
                "missing {} buffer binding at slot {slot}",
                if *writable { "writable" } else { "read-only" }
            ),
            Self::DownloadPending(handle) => {
                write!(formatter, "buffer {handle} already has a queued download")
            }
            Self::DownloadUnread(handle) => write!(
                formatter,
                "buffer {handle} has a synchronized download that has not been read yet"
            ),
            Self::DownloadNotReady(handle) => {
                write!(formatter, "buffer {handle} has no synchronized download")
            }
            Self::DownloadMismatch {
                expected_offset,
                expected_size,
                requested_offset,
                requested_size,
            } => write!(
                formatter,
                "downloaded range {expected_offset}..{} does not match requested range {requested_offset}..{}",
                expected_offset.saturating_add(*expected_size),
                requested_offset.saturating_add(*requested_size)
            ),
            Self::Validation(message) => write!(formatter, "GPU validation: {message}"),
            Self::Device(messages) => {
                write!(formatter, "GPU device error: {}", messages.join("; "))
            }
            Self::Poll(message) => write!(formatter, "poll GPU device: {message}"),
            Self::Map(message) => write!(formatter, "map GPU download: {message}"),
            Self::Capacity => formatter.write_str("GPU resource capacity exhausted"),
            Self::CostOutput(message) => formatter.write_str(message),
            Self::Internal(message) => write!(formatter, "GPU internal invariant: {message}"),
        }
    }
}

impl Error for GpuError {}

impl From<Status> for GpuError {
    fn from(status: Status) -> Self {
        match status {
            Status::Capacity => Self::Capacity,
            Status::StaleHandle => Self::Internal("resource arena rejected a registered handle"),
            _ => Self::Internal("unexpected native ABI status"),
        }
    }
}

#[derive(Clone, Debug)]
pub struct KernelDescriptor<'a> {
    pub spirv: &'a [u8],
    pub entry_point: &'a str,
    pub readonly_bindings: u32,
    pub writable_bindings: u32,
    pub uniform_size: u64,
    /// Logical invocations per WGPU workgroup. This must agree with the shader.
    pub workgroup_size: [u32; 3],
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct AdapterDescription {
    pub name: String,
    pub backend: String,
}

#[derive(Clone, Copy)]
struct ResourceRef {
    kind: ResourceKind,
    internal: Handle,
}

struct Resources<B, K, D> {
    public: HashMap<u64, ResourceRef>,
    buffers: Arena<B>,
    kernels: Arena<K>,
    bindings: Arena<D>,
}

impl<B, K, D> Resources<B, K, D> {
    fn new() -> Self {
        Self {
            public: HashMap::new(),
            buffers: Arena::new(),
            kernels: Arena::new(),
            bindings: Arena::new(),
        }
    }

    fn public_handle(&mut self, reference: ResourceRef) -> Result<u64, GpuError> {
        let handle = NEXT_PUBLIC_HANDLE
            .fetch_update(Ordering::Relaxed, Ordering::Relaxed, |next| {
                next.checked_add(1)
            })
            .map_err(|_| GpuError::Capacity)?;
        if self.public.insert(handle, reference).is_some() {
            return Err(GpuError::Capacity);
        }
        Ok(handle)
    }

    fn insert_buffer(&mut self, value: B) -> Result<BufferHandle, GpuError> {
        let internal = self.buffers.insert(value)?;
        match self.public_handle(ResourceRef {
            kind: ResourceKind::Buffer,
            internal,
        }) {
            Ok(handle) => Ok(handle),
            Err(error) => {
                let _ = self.buffers.remove(internal);
                Err(error)
            }
        }
    }

    fn insert_kernel(&mut self, value: K) -> Result<KernelHandle, GpuError> {
        let internal = self.kernels.insert(value)?;
        match self.public_handle(ResourceRef {
            kind: ResourceKind::Kernel,
            internal,
        }) {
            Ok(handle) => Ok(handle),
            Err(error) => {
                let _ = self.kernels.remove(internal);
                Err(error)
            }
        }
    }

    fn insert_binding(&mut self, value: D) -> Result<BindingHandle, GpuError> {
        let internal = self.bindings.insert(value)?;
        match self.public_handle(ResourceRef {
            kind: ResourceKind::Binding,
            internal,
        }) {
            Ok(handle) => Ok(handle),
            Err(error) => {
                let _ = self.bindings.remove(internal);
                Err(error)
            }
        }
    }

    fn reference(&self, handle: u64, expected: ResourceKind) -> Result<ResourceRef, GpuError> {
        let reference = self
            .public
            .get(&handle)
            .copied()
            .ok_or(GpuError::StaleHandle(handle))?;
        if reference.kind != expected {
            return Err(GpuError::WrongHandle {
                handle,
                expected,
                actual: reference.kind,
            });
        }
        Ok(reference)
    }

    fn buffer(&self, handle: BufferHandle) -> Result<&B, GpuError> {
        let reference = self.reference(handle, ResourceKind::Buffer)?;
        self.buffers.get(reference.internal).map_err(Into::into)
    }

    fn buffer_mut(&mut self, handle: BufferHandle) -> Result<&mut B, GpuError> {
        let reference = self.reference(handle, ResourceKind::Buffer)?;
        self.buffers.get_mut(reference.internal).map_err(Into::into)
    }

    fn kernel_mut(&mut self, handle: KernelHandle) -> Result<&mut K, GpuError> {
        let reference = self.reference(handle, ResourceKind::Kernel)?;
        self.kernels.get_mut(reference.internal).map_err(Into::into)
    }

    fn kernel(&self, handle: KernelHandle) -> Result<&K, GpuError> {
        let reference = self.reference(handle, ResourceKind::Kernel)?;
        self.kernels.get(reference.internal).map_err(Into::into)
    }

    fn binding(&self, handle: BindingHandle) -> Result<&D, GpuError> {
        let reference = self.reference(handle, ResourceKind::Binding)?;
        self.bindings.get(reference.internal).map_err(Into::into)
    }

    fn binding_mut(&mut self, handle: BindingHandle) -> Result<&mut D, GpuError> {
        let reference = self.reference(handle, ResourceKind::Binding)?;
        self.bindings
            .get_mut(reference.internal)
            .map_err(Into::into)
    }

    fn remove_buffer(&mut self, handle: BufferHandle) -> Result<B, GpuError> {
        let reference = self.reference(handle, ResourceKind::Buffer)?;
        let value = self.buffers.remove(reference.internal)?;
        self.public.remove(&handle);
        Ok(value)
    }

    fn remove_kernel(&mut self, handle: KernelHandle) -> Result<K, GpuError> {
        let reference = self.reference(handle, ResourceKind::Kernel)?;
        let value = self.kernels.remove(reference.internal)?;
        self.public.remove(&handle);
        Ok(value)
    }

    fn remove_binding(&mut self, handle: BindingHandle) -> Result<D, GpuError> {
        let reference = self.reference(handle, ResourceKind::Binding)?;
        let value = self.bindings.remove(reference.internal)?;
        self.public.remove(&handle);
        Ok(value)
    }
}

#[derive(Clone, Debug)]
struct BufferSlot {
    buffer: BufferHandle,
    offset: u64,
    size: u64,
    layout: Value,
}

enum Download {
    Pending {
        staging: wgpu::Buffer,
        offset: u64,
        /// The bytes asked for, which the staging copy may round up to a word.
        length: u64,
        version: u64,
        layout: Value,
    },
    Ready {
        offset: u64,
        bytes: Vec<u8>,
        version: u64,
        layout: Value,
    },
}

struct BufferEntry {
    buffer: wgpu::Buffer,
    size: u64,
    download: Option<Download>,
    version: u64,
    completed_download_version: Option<u64>,
    completed_download_layout: Value,
    metadata: Value,
}

struct KernelEntry {
    pipeline: wgpu::ComputePipeline,
    readonly_layout: Option<wgpu::BindGroupLayout>,
    writable_layout: Option<wgpu::BindGroupLayout>,
    uniform_layout: Option<wgpu::BindGroupLayout>,
    readonly_bindings: u32,
    writable_bindings: u32,
    uniform_size: u64,
    workgroup_size: [u32; 3],
    metadata: Value,
    dispatches: u64,
}

struct BindingEntry {
    kernel: KernelHandle,
    readonly: Vec<Option<BufferSlot>>,
    writable: Vec<Option<BufferSlot>>,
    uniform: Option<wgpu::Buffer>,
    readonly_group: Option<wgpu::BindGroup>,
    writable_group: Option<wgpu::BindGroup>,
    uniform_group: Option<wgpu::BindGroup>,
}

#[derive(Clone, Default)]
struct DeviceErrorQueue {
    messages: Arc<Mutex<Vec<String>>>,
}

impl DeviceErrorQueue {
    fn record(&self, message: String) {
        self.messages
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
            .push(message);
    }

    fn take(&self) -> Vec<String> {
        let mut messages = self
            .messages
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        std::mem::take(&mut *messages)
    }
}

struct PendingTimestamp {
    query: wgpu::QuerySet,
    operation: u64,
    kernel: KernelHandle,
}

fn timestamp_milliseconds(begin: u64, end: u64, period_ns: f32) -> Result<f64, &'static str> {
    if begin == end {
        return Err("equal-timestamps");
    }
    if end < begin {
        return Err("reversed-timestamps");
    }
    if !period_ns.is_finite() || period_ns <= 0.0 {
        return Err("invalid-timestamp-period");
    }
    Ok((end - begin) as f64 * period_ns as f64 / 1_000_000.0)
}

pub struct GpuContext {
    cost_id: u64,
    timestamp_supported: bool,
    pending_timestamps: Vec<PendingTimestamp>,
    dispatch_sequence: u64,
    _instance: wgpu::Instance,
    adapter: wgpu::Adapter,
    device: wgpu::Device,
    queue: wgpu::Queue,
    resources: Resources<BufferEntry, KernelEntry, BindingEntry>,
    pending_downloads: Vec<BufferHandle>,
    device_errors: DeviceErrorQueue,
}

impl GpuContext {
    pub fn new() -> Result<Self, GpuError> {
        let cost_id = NEXT_PUBLIC_HANDLE.fetch_add(1, Ordering::Relaxed);
        let setup_start = costs::clock();
        let instance =
            wgpu::Instance::new(wgpu::InstanceDescriptor::new_without_display_handle_from_env());
        let adapter = pollster::block_on(instance.request_adapter(&wgpu::RequestAdapterOptions {
            power_preference: wgpu::PowerPreference::HighPerformance,
            force_fallback_adapter: false,
            compatible_surface: None,
            apply_limit_buckets: false,
        }))
        .map_err(|error| GpuError::AdapterUnavailable(error.to_string()))?;
        let adapter_time = costs::elapsed(setup_start);
        let timestamp_supported =
            costs::enabled() && adapter.features().contains(wgpu::Features::TIMESTAMP_QUERY);
        let device_start = costs::clock();
        let descriptor = wgpu::DeviceDescriptor {
            label: Some("Nupp native compute device"),
            required_features: if timestamp_supported {
                wgpu::Features::TIMESTAMP_QUERY
            } else {
                wgpu::Features::empty()
            },
            required_limits: adapter.limits(),
            experimental_features: wgpu::ExperimentalFeatures::disabled(),
            memory_hints: wgpu::MemoryHints::MemoryUsage,
            trace: wgpu::Trace::Off,
        };
        let (device, queue) = pollster::block_on(adapter.request_device(&descriptor))
            .map_err(|error| GpuError::DeviceRequest(error.to_string()))?;
        let device_errors = DeviceErrorQueue::default();
        let uncaptured = device_errors.clone();
        device.on_uncaptured_error(Arc::new(move |error| {
            uncaptured.record(error.to_string());
        }));
        let lost = device_errors.clone();
        device.set_device_lost_callback(move |reason, message| {
            lost.record(format!("device lost ({reason:?}): {message}"));
        });
        let info = adapter.get_info();
        cost_record!(
            cost_id,
            "adapterDevice",
            json!({"phase": "setup", "adapter": info.name, "backend": info.backend.to_str(), "adapterMs": adapter_time, "deviceMs": costs::elapsed(device_start), "gpuTiming": if timestamp_supported { "timestamp-query" } else { "unavailable" }})
        );
        costs::check()?;
        Ok(Self {
            cost_id,
            timestamp_supported,
            pending_timestamps: Vec::new(),
            dispatch_sequence: 0,
            _instance: instance,
            adapter,
            device,
            queue,
            resources: Resources::new(),
            pending_downloads: Vec::new(),
            device_errors,
        })
    }

    pub fn cost_id(&self) -> u64 {
        self.cost_id
    }

    pub fn adapter(&self) -> AdapterDescription {
        let info = self.adapter.get_info();
        AdapterDescription {
            name: info.name,
            backend: info.backend.to_str().to_owned(),
        }
    }

    fn take_device_errors(&self) -> Vec<String> {
        self.device_errors.take()
    }

    pub fn create_buffer(&mut self, size: u64) -> Result<BufferHandle, GpuError> {
        if size == 0 {
            return Err(GpuError::InvalidArgument(
                "GPU buffer size must be greater than zero".to_owned(),
            ));
        }
        if size > self.device.limits().max_buffer_size {
            return Err(GpuError::InvalidArgument(format!(
                "GPU buffer size {size} exceeds the device limit {}",
                self.device.limits().max_buffer_size
            )));
        }
        // Copies and storage bindings move whole words, so a buffer of narrow
        // elements whose bytes end partway through one gets the rest of that
        // word as padding nobody can address.
        let allocated = align_up(size, COPY_ALIGNMENT)?;
        let start = costs::clock();
        let buffer = self.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("Nupp resident compute buffer"),
            size: allocated,
            usage: wgpu::BufferUsages::STORAGE
                | wgpu::BufferUsages::COPY_SRC
                | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });
        let handle = self.resources.insert_buffer(BufferEntry {
            buffer,
            size,
            download: None,
            version: 0,
            completed_download_version: None,
            completed_download_layout: Value::Null,
            metadata: Value::Null,
        })?;
        cost_record!(
            self.cost_id,
            "bufferAllocate",
            json!({"buffer": handle, "version": 0, "bytes": size, "reused": false, "hostMs": costs::elapsed(start)})
        );
        Ok(handle)
    }

    pub fn release_buffer(&mut self, handle: BufferHandle) -> Result<(), GpuError> {
        if matches!(
            self.resources.buffer(handle)?.download,
            Some(Download::Pending { .. })
        ) {
            return Err(GpuError::DownloadPending(handle));
        }
        let start = costs::clock();
        self.resources.remove_buffer(handle)?;
        cost_record!(
            self.cost_id,
            "bufferRelease",
            json!({"buffer": handle, "hostMs": costs::elapsed(start)})
        );
        Ok(())
    }

    pub fn upload(
        &mut self,
        handle: BufferHandle,
        offset: u64,
        bytes: &[u8],
    ) -> Result<(), GpuError> {
        let start = costs::clock();
        let entry = self.resources.buffer_mut(handle)?;
        checked_range("upload", offset, bytes.len() as u64, entry.size)?;
        let copied = copy_extent("upload", offset, bytes.len() as u64, entry.size)?;
        if !bytes.is_empty() {
            if copied == bytes.len() as u64 {
                self.queue.write_buffer(&entry.buffer, offset, bytes);
            } else {
                let mut padded = bytes.to_vec();
                padded.resize(copied as usize, 0);
                self.queue.write_buffer(&entry.buffer, offset, &padded);
            }
            entry.version += 1;
        }
        cost_record!(
            self.cost_id,
            "upload",
            json!({"buffer": handle, "version": entry.version, "offset": offset, "bytes": bytes.len(), "layout": entry.metadata, "hostMs": costs::elapsed(start), "gpuMs": null, "gpuTiming": "unavailable", "hostCopies": 1})
        );
        Ok(())
    }

    pub fn create_kernel(
        &mut self,
        descriptor: &KernelDescriptor<'_>,
    ) -> Result<KernelHandle, GpuError> {
        let start = costs::clock();
        validate_kernel_descriptor(descriptor, &self.device.limits())?;
        let words = spirv_words(descriptor.spirv)?;
        check_workgroup_size(&words, descriptor.entry_point, descriptor.workgroup_size)?;
        let scope = self.device.push_error_scope(wgpu::ErrorFilter::Validation);
        let readonly_layout = self.storage_layout(descriptor.readonly_bindings, true);
        let writable_layout = self.storage_layout(descriptor.writable_bindings, false);
        let uniform_layout = (descriptor.uniform_size != 0).then(|| {
            self.device
                .create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
                    label: Some("Nupp uniform layout"),
                    entries: &[wgpu::BindGroupLayoutEntry {
                        binding: 0,
                        visibility: wgpu::ShaderStages::COMPUTE,
                        ty: wgpu::BindingType::Buffer {
                            ty: wgpu::BufferBindingType::Uniform,
                            has_dynamic_offset: false,
                            min_binding_size: NonZeroU64::new(descriptor.uniform_size),
                        },
                        count: None,
                    }],
                })
        });
        let layouts = [
            readonly_layout.as_ref(),
            writable_layout.as_ref(),
            uniform_layout.as_ref(),
        ];
        let pipeline_layout = self
            .device
            .create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
                label: Some("Nupp compute pipeline layout"),
                bind_group_layouts: &layouts,
                immediate_size: 0,
            });
        let module = self
            .device
            .create_shader_module(wgpu::ShaderModuleDescriptor {
                label: Some("Nupp SPIR-V compute module"),
                source: wgpu::ShaderSource::SpirV(Cow::Owned(words)),
            });
        let pipeline = self
            .device
            .create_compute_pipeline(&wgpu::ComputePipelineDescriptor {
                label: Some("Nupp compute pipeline"),
                layout: Some(&pipeline_layout),
                module: &module,
                entry_point: Some(descriptor.entry_point),
                compilation_options: wgpu::PipelineCompilationOptions::default(),
                cache: None,
            });
        self.finish_validation_scope(scope)?;
        let handle = self.resources.insert_kernel(KernelEntry {
            pipeline,
            readonly_layout,
            writable_layout,
            uniform_layout,
            readonly_bindings: descriptor.readonly_bindings,
            writable_bindings: descriptor.writable_bindings,
            uniform_size: descriptor.uniform_size,
            workgroup_size: descriptor.workgroup_size,
            metadata: Value::Null,
            dispatches: 0,
        })?;
        cost_record!(
            self.cost_id,
            "pipelineCreate",
            json!({"kernel": handle, "phase": "setup", "bytes": descriptor.spirv.len(), "entrypoint": descriptor.entry_point, "workgroup": descriptor.workgroup_size, "reused": false, "hostMs": costs::elapsed(start)})
        );
        Ok(handle)
    }

    pub fn metadata(&mut self, handle: u64, kernel: bool, bytes: &[u8]) -> Result<(), GpuError> {
        let value: Value = serde_json::from_slice(bytes)
            .map_err(|error| GpuError::InvalidArgument(format!("GPU cost metadata: {error}")))?;
        if !value.is_object() {
            return Err(GpuError::InvalidArgument(
                "GPU cost metadata must be an object".into(),
            ));
        }
        if kernel {
            self.resources.kernel_mut(handle)?.metadata = value.clone();
        } else {
            let metadata = &mut self.resources.buffer_mut(handle)?.metadata;
            if !metadata.is_object() {
                *metadata = json!({});
            }
            metadata
                .as_object_mut()
                .expect("metadata object")
                .extend(value.as_object().expect("validated object").clone());
        }
        cost_record!(
            self.cost_id,
            if kernel {
                "kernelIdentity"
            } else {
                "bufferIdentity"
            },
            json!({"handle": handle, "metadata": value})
        );
        Ok(())
    }

    fn storage_layout(&self, count: u32, read_only: bool) -> Option<wgpu::BindGroupLayout> {
        if count == 0 {
            return None;
        }
        let entries: Vec<wgpu::BindGroupLayoutEntry> = (0..count)
            .map(|binding| wgpu::BindGroupLayoutEntry {
                binding,
                visibility: wgpu::ShaderStages::COMPUTE,
                ty: wgpu::BindingType::Buffer {
                    ty: wgpu::BufferBindingType::Storage { read_only },
                    has_dynamic_offset: false,
                    min_binding_size: None,
                },
                count: None,
            })
            .collect();
        Some(
            self.device
                .create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
                    label: Some(if read_only {
                        "Nupp read-only storage layout"
                    } else {
                        "Nupp writable storage layout"
                    }),
                    entries: &entries,
                }),
        )
    }

    pub fn release_kernel(&mut self, handle: KernelHandle) -> Result<(), GpuError> {
        let start = costs::clock();
        self.resources.remove_kernel(handle)?;
        cost_record!(
            self.cost_id,
            "kernelRelease",
            json!({"kernel": handle, "hostMs": costs::elapsed(start)})
        );
        Ok(())
    }

    pub fn create_bindings(&mut self, kernel: KernelHandle) -> Result<BindingHandle, GpuError> {
        let start = costs::clock();
        let kernel_entry = self.resources.kernel(kernel)?;
        let uniform = if kernel_entry.uniform_size == 0 {
            None
        } else {
            Some(self.device.create_buffer(&wgpu::BufferDescriptor {
                label: Some("Nupp dispatch uniforms"),
                size: align_up(kernel_entry.uniform_size, 16)?,
                usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
                mapped_at_creation: false,
            }))
        };
        let binding = BindingEntry {
            kernel,
            readonly: vec![None; kernel_entry.readonly_bindings as usize],
            writable: vec![None; kernel_entry.writable_bindings as usize],
            uniform,
            readonly_group: None,
            writable_group: None,
            uniform_group: None,
        };
        let uniform_bytes = kernel_entry.uniform_size;
        let handle = self.resources.insert_binding(binding)?;
        cost_record!(
            self.cost_id,
            "bindingCreate",
            json!({"binding": handle, "kernel": kernel, "uniformBytes": uniform_bytes, "reused": false, "hostMs": costs::elapsed(start)})
        );
        Ok(handle)
    }

    pub fn release_bindings(&mut self, handle: BindingHandle) -> Result<(), GpuError> {
        let start = costs::clock();
        self.resources.remove_binding(handle)?;
        cost_record!(
            self.cost_id,
            "bindingRelease",
            json!({"binding": handle, "hostMs": costs::elapsed(start)})
        );
        Ok(())
    }

    pub fn set_read_buffer(
        &mut self,
        bindings: BindingHandle,
        slot: u32,
        buffer: BufferHandle,
        offset: u64,
        size: u64,
    ) -> Result<(), GpuError> {
        self.set_buffer_slot(bindings, false, slot, buffer, offset, size)
    }

    pub fn set_write_buffer(
        &mut self,
        bindings: BindingHandle,
        slot: u32,
        buffer: BufferHandle,
        offset: u64,
        size: u64,
    ) -> Result<(), GpuError> {
        self.set_buffer_slot(bindings, true, slot, buffer, offset, size)
    }

    fn set_buffer_slot(
        &mut self,
        bindings: BindingHandle,
        writable: bool,
        slot: u32,
        buffer: BufferHandle,
        offset: u64,
        size: u64,
    ) -> Result<(), GpuError> {
        let buffer_size = self.resources.buffer(buffer)?.size;
        checked_range("binding", offset, size, buffer_size)?;
        if size == 0 {
            return Err(GpuError::InvalidArgument(
                "GPU binding range must not be empty".to_owned(),
            ));
        }
        let size = copy_extent("storage binding", offset, size, buffer_size)?;
        let alignment = u64::from(self.device.limits().min_storage_buffer_offset_alignment);
        if !offset.is_multiple_of(alignment) {
            return Err(GpuError::InvalidArgument(format!(
                "GPU storage binding offset {offset} is not aligned to {alignment} bytes"
            )));
        }
        if size > self.device.limits().max_storage_buffer_binding_size {
            return Err(GpuError::InvalidArgument(format!(
                "GPU storage binding size {size} exceeds the device limit {}",
                self.device.limits().max_storage_buffer_binding_size
            )));
        }
        let layout = self.resources.buffer(buffer)?.metadata.clone();
        let entry = self.resources.binding_mut(bindings)?;
        let other_side = if writable {
            &entry.readonly
        } else {
            &entry.writable
        };
        if binds(other_side, buffer) {
            return Err(GpuError::InvalidArgument(
                "a GPU buffer cannot be bound for both reading and writing in one dispatch"
                    .to_owned(),
            ));
        }
        let slots = if writable {
            &mut entry.writable
        } else {
            &mut entry.readonly
        };
        let target = slots.get_mut(slot as usize).ok_or_else(|| {
            GpuError::InvalidArgument(format!(
                "GPU {} binding slot {slot} is outside the compiled kernel",
                if writable { "writable" } else { "read-only" }
            ))
        })?;
        let kernel_handle = entry.kernel;
        *target = Some(BufferSlot {
            buffer,
            offset,
            size,
            layout,
        });
        if writable {
            entry.writable_group = None;
        } else {
            entry.readonly_group = None;
        }
        cost_record!(
            self.cost_id,
            "bindBuffer",
            json!({"binding": bindings, "kernel": kernel_handle, "buffer": buffer, "writable": writable, "slot": slot, "offset": offset, "bytes": size})
        );
        Ok(())
    }

    pub fn dispatch(
        &mut self,
        bindings: BindingHandle,
        work_items: [u32; 3],
        uniforms: &[u8],
    ) -> Result<(), GpuError> {
        let start = costs::clock();
        let (kernel_handle, need_readonly, need_writable, need_uniform) = {
            let binding = self.resources.binding(bindings)?;
            (
                binding.kernel,
                binding.readonly_group.is_none(),
                binding.writable_group.is_none(),
                binding.uniform_group.is_none(),
            )
        };
        let kernel = self.resources.kernel(kernel_handle)?;
        let uniform_size = kernel.uniform_size;
        let workgroup_size = kernel.workgroup_size;
        let pipeline = kernel.pipeline.clone();
        let readonly_layout = kernel.readonly_layout.clone();
        let writable_layout = kernel.writable_layout.clone();
        let uniform_layout = kernel.uniform_layout.clone();
        if uniforms.len() as u64 != uniform_size {
            return Err(GpuError::InvalidArgument(format!(
                "GPU dispatch supplied {} uniform bytes, but the kernel requires {}",
                uniforms.len(),
                uniform_size
            )));
        }
        require_copy_alignment("uniform size", uniforms.len() as u64)?;
        let binding = self.resources.binding(bindings)?;
        self.validate_storage_slots(&binding.readonly, false)?;
        self.validate_storage_slots(&binding.writable, true)?;
        let readonly_group = if need_readonly {
            self.make_storage_group(readonly_layout.as_ref(), &binding.readonly, false)?
        } else {
            None
        };
        let writable_group = if need_writable {
            self.make_storage_group(writable_layout.as_ref(), &binding.writable, true)?
        } else {
            None
        };
        let uniform_group = if need_uniform {
            self.make_uniform_group(
                uniform_layout.as_ref(),
                binding.uniform.as_ref(),
                uniform_size,
            )?
        } else {
            None
        };
        let binding = self.resources.binding_mut(bindings)?;
        if need_readonly {
            binding.readonly_group = readonly_group;
        }
        if need_writable {
            binding.writable_group = writable_group;
        }
        if need_uniform {
            binding.uniform_group = uniform_group;
        }
        if let Some(buffer) = binding.uniform.as_ref() {
            self.queue.write_buffer(buffer, 0, uniforms);
        }
        if work_items.contains(&0) {
            return Ok(());
        }
        let groups = [
            work_items[0].div_ceil(workgroup_size[0]),
            work_items[1].div_ceil(workgroup_size[1]),
            work_items[2].div_ceil(workgroup_size[2]),
        ];
        let limits = self.device.limits();
        if groups[0] > limits.max_compute_workgroups_per_dimension
            || groups[1] > limits.max_compute_workgroups_per_dimension
            || groups[2] > limits.max_compute_workgroups_per_dimension
        {
            return Err(GpuError::InvalidArgument(format!(
                "GPU dispatch workgroup count {groups:?} exceeds the per-dimension limit {}",
                limits.max_compute_workgroups_per_dimension
            )));
        }
        let mut encoder = self
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("Nupp compute dispatch"),
            });
        let query = (self.timestamp_supported && costs::enabled()).then(|| {
            self.device.create_query_set(&wgpu::QuerySetDescriptor {
                label: Some("Nupp cost timestamps"),
                ty: wgpu::QueryType::Timestamp,
                count: 2,
            })
        });
        {
            let mut pass = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("Nupp compute pass"),
                timestamp_writes: query.as_ref().map(|query_set| {
                    wgpu::ComputePassTimestampWrites {
                        query_set,
                        beginning_of_pass_write_index: Some(0),
                        end_of_pass_write_index: Some(1),
                    }
                }),
            });
            pass.set_pipeline(&pipeline);
            if let Some(group) = binding.readonly_group.as_ref() {
                pass.set_bind_group(0, group, &[]);
            }
            if let Some(group) = binding.writable_group.as_ref() {
                pass.set_bind_group(1, group, &[]);
            }
            if let Some(group) = binding.uniform_group.as_ref() {
                pass.set_bind_group(2, group, &[]);
            }
            pass.dispatch_workgroups(groups[0], groups[1], groups[2]);
        }
        self.dispatch_sequence += 1;
        let operation = self.dispatch_sequence;
        if let Some(query) = query {
            self.pending_timestamps.push(PendingTimestamp {
                query,
                operation,
                kernel: kernel_handle,
            });
        }
        self.queue.submit([encoder.finish()]);
        let binding = self.resources.binding(bindings)?;
        let reads = binding.readonly.clone();
        let writes = binding.writable.clone();
        let read_versions = if costs::enabled() {
            reads.iter().enumerate().filter_map(|(slot, binding)| binding.as_ref().map(|binding| {
            let buffer = self.resources.buffer(binding.buffer).expect("validated binding");
            json!({"slot": slot, "buffer": binding.buffer, "version": buffer.version, "offset": binding.offset,
                "bytes": binding.size, "layout": binding.layout})
        })).collect::<Vec<_>>()
        } else {
            Vec::new()
        };
        // One logical version per dispatch even when disjoint writable slots alias.
        let mut changed = std::collections::HashSet::new();
        for slot in writes.iter().flatten() {
            if changed.insert(slot.buffer) {
                self.resources.buffer_mut(slot.buffer)?.version += 1;
            }
        }
        let kernel = self.resources.kernel_mut(kernel_handle)?;
        kernel.dispatches += 1;
        let phase = if kernel.dispatches == 1 {
            "first-use"
        } else {
            "steady-state"
        };
        let metadata = kernel.metadata.clone();
        if costs::enabled() {
            let describe = |slots: &[Option<BufferSlot>]| -> Vec<Value> {
                slots
                    .iter()
                    .enumerate()
                    .filter_map(|(slot, binding)| {
                        binding.as_ref().map(|binding| {
                    let buffer = self.resources.buffer(binding.buffer).expect("validated binding");
                    json!({"slot": slot, "buffer": binding.buffer, "version": buffer.version,
                        "offset": binding.offset, "bytes": binding.size, "layout": binding.layout})
                })
                    })
                    .collect()
            };
            costs::record(
                self.cost_id,
                "dispatch",
                json!({"dispatch": operation, "kernel": kernel_handle,
                "binding": bindings, "metadata": metadata, "phase": phase, "workItems": work_items,
                "workgroup": workgroup_size, "uniformBytes": uniforms.len(), "read": read_versions, "write": describe(&writes),
                "bindingsReused": (readonly_layout.is_none() || !need_readonly) && (writable_layout.is_none() || !need_writable) && (uniform_layout.is_none() || !need_uniform),
                "hostMs": costs::elapsed(start), "gpuMs": null,
                "gpuTiming": if self.timestamp_supported { "pending" } else { "unavailable" }}),
            );
        }
        Ok(())
    }

    fn make_storage_group(
        &self,
        layout: Option<&wgpu::BindGroupLayout>,
        slots: &[Option<BufferSlot>],
        writable: bool,
    ) -> Result<Option<wgpu::BindGroup>, GpuError> {
        let Some(layout) = layout else {
            return Ok(None);
        };
        let assigned: Vec<&BufferSlot> = slots
            .iter()
            .enumerate()
            .map(|(slot, value)| {
                value.as_ref().ok_or(GpuError::MissingBinding {
                    writable,
                    slot: slot as u32,
                })
            })
            .collect::<Result<_, _>>()?;
        let buffers: Vec<&BufferEntry> = assigned
            .iter()
            .map(|slot| self.resources.buffer(slot.buffer))
            .collect::<Result<_, _>>()?;
        let entries: Vec<wgpu::BindGroupEntry<'_>> = assigned
            .iter()
            .zip(buffers)
            .enumerate()
            .map(|(slot, (assigned, buffer))| wgpu::BindGroupEntry {
                binding: slot as u32,
                resource: wgpu::BindingResource::Buffer(wgpu::BufferBinding {
                    buffer: &buffer.buffer,
                    offset: assigned.offset,
                    size: NonZeroU64::new(assigned.size),
                }),
            })
            .collect();
        Ok(Some(self.device.create_bind_group(
            &wgpu::BindGroupDescriptor {
                label: Some(if writable {
                    "Nupp writable storage bind group"
                } else {
                    "Nupp read-only storage bind group"
                }),
                layout,
                entries: &entries,
            },
        )))
    }

    fn validate_storage_slots(
        &self,
        slots: &[Option<BufferSlot>],
        writable: bool,
    ) -> Result<(), GpuError> {
        for (slot, value) in slots.iter().enumerate() {
            let value = value.as_ref().ok_or(GpuError::MissingBinding {
                writable,
                slot: slot as u32,
            })?;
            self.resources.buffer(value.buffer)?;
        }
        Ok(())
    }

    fn make_uniform_group(
        &self,
        layout: Option<&wgpu::BindGroupLayout>,
        buffer: Option<&wgpu::Buffer>,
        uniform_size: u64,
    ) -> Result<Option<wgpu::BindGroup>, GpuError> {
        match (layout, buffer) {
            (Some(layout), Some(buffer)) => Ok(Some(self.device.create_bind_group(
                &wgpu::BindGroupDescriptor {
                    label: Some("Nupp uniform bind group"),
                    layout,
                    entries: &[wgpu::BindGroupEntry {
                        binding: 0,
                        resource: wgpu::BindingResource::Buffer(wgpu::BufferBinding {
                            buffer,
                            offset: 0,
                            size: NonZeroU64::new(uniform_size),
                        }),
                    }],
                },
            ))),
            (None, None) => Ok(None),
            _ => Err(GpuError::Internal(
                "GPU kernel uniform layout and binding disagree",
            )),
        }
    }

    pub fn queue_download(
        &mut self,
        handle: BufferHandle,
        offset: u64,
        size: u64,
    ) -> Result<(), GpuError> {
        let start = costs::clock();
        let entry = self.resources.buffer(handle)?;
        checked_range("download", offset, size, entry.size)?;
        if size == 0 {
            return Err(GpuError::InvalidArgument(
                "GPU download range must not be empty".to_owned(),
            ));
        }
        let length = size;
        let size = copy_extent("download", offset, size, entry.size)?;
        match entry.download {
            Some(Download::Pending { .. }) => return Err(GpuError::DownloadPending(handle)),
            Some(Download::Ready { .. }) => return Err(GpuError::DownloadUnread(handle)),
            None => {}
        }
        let staging = self.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("Nupp GPU readback"),
            size,
            usage: wgpu::BufferUsages::MAP_READ | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });
        let mut encoder = self
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("Nupp GPU download"),
            });
        encoder.copy_buffer_to_buffer(&entry.buffer, offset, &staging, 0, size);
        self.queue.submit([encoder.finish()]);
        cost_record!(
            self.cost_id,
            "downloadQueue",
            json!({"buffer": handle, "version": entry.version,
            "offset": offset, "bytes": size, "layout": entry.metadata, "stagingReused": false,
            "stagingBytes": size, "hostMs": costs::elapsed(start), "gpuMs": null, "gpuTiming": "unavailable"})
        );
        let version = entry.version;
        let layout = entry.metadata.clone();
        self.resources.buffer_mut(handle)?.download = Some(Download::Pending {
            staging,
            offset,
            length,
            version,
            layout,
        });
        self.pending_downloads.push(handle);
        Ok(())
    }

    pub fn synchronize(&mut self) -> Result<(), GpuError> {
        let start = costs::clock();
        self.poll_wait()?;
        cost_record!(
            self.cost_id,
            "synchronizeWait",
            json!({"hostMs": costs::elapsed(start), "pendingDownloads": self.pending_downloads.len(), "pendingTimestamps": self.pending_timestamps.len()})
        );
        while let Some(handle) = self.pending_downloads.first().copied() {
            let (staging, offset, length, version, layout) =
                match self.resources.buffer(handle)?.download.as_ref() {
                    Some(Download::Pending {
                        staging,
                        offset,
                        length,
                        version,
                        layout,
                    }) => (staging.clone(), *offset, *length, *version, layout.clone()),
                    _ => {
                        return Err(GpuError::Internal(
                            "pending download queue disagrees with buffer",
                        ));
                    }
                };
            let start = costs::clock();
            let outcome = self.map_download(&staging);
            cost_record!(
                self.cost_id,
                "downloadMapCopy",
                json!({"buffer": handle, "version": version,
                "offset": offset, "bytes": staging.size(), "layout": layout,
                "hostMs": costs::elapsed(start), "hostCopies": 1, "success": outcome.is_ok()})
            );
            // The download is settled either way. A failed map must not stay
            // pending: its map request is already in flight, so a retry would
            // fail again, and a pending download refuses to release its buffer.
            self.pending_downloads.remove(0);
            match outcome {
                Ok(mut bytes) => {
                    bytes.truncate(length as usize);
                    self.resources.buffer_mut(handle)?.download = Some(Download::Ready {
                        offset,
                        bytes,
                        version,
                        layout,
                    });
                }
                Err(error) => {
                    if let Ok(entry) = self.resources.buffer_mut(handle) {
                        entry.download = None;
                    }
                    return Err(error);
                }
            }
        }
        while let Some(pending) = self.pending_timestamps.pop() {
            let start = costs::clock();
            // Metal can resolve pass-boundary counters from the preceding
            // submission when resolution shares the compute command buffer.
            // The wait above completes every measured dispatch first; only now
            // submit its resolve/copy commands, preserving current-work identity.
            let mut encoder = self
                .device
                .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                    label: Some("Nupp timestamp readback"),
                });
            let resolve = self.device.create_buffer(&wgpu::BufferDescriptor {
                label: Some("Nupp timestamp resolve"),
                size: 256,
                usage: wgpu::BufferUsages::QUERY_RESOLVE | wgpu::BufferUsages::COPY_SRC,
                mapped_at_creation: false,
            });
            let staging = self.device.create_buffer(&wgpu::BufferDescriptor {
                label: Some("Nupp timestamp readback"),
                size: 16,
                usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
                mapped_at_creation: false,
            });
            encoder.resolve_query_set(&pending.query, 0..2, &resolve, 0);
            encoder.copy_buffer_to_buffer(&resolve, 0, &staging, 0, 16);
            self.queue.submit([encoder.finish()]);
            let bytes = self.map_download(&staging)?;
            let begin = u64::from_le_bytes(bytes[0..8].try_into().expect("timestamp width"));
            let end = u64::from_le_bytes(bytes[8..16].try_into().expect("timestamp width"));
            let period_ns = self.queue.get_timestamp_period();
            let measured = timestamp_milliseconds(begin, end, period_ns);
            cost_record!(
                self.cost_id,
                "kernelExecution",
                json!({"dispatch": pending.operation, "kernel": pending.kernel,
                "gpuMs": measured.ok(), "gpuTiming": if measured.is_ok() { "timestamp-query" } else { "unavailable" },
                "gpuTimingReason": measured.err(), "gpuTicksBegin": begin.to_string(), "gpuTicksEnd": end.to_string(),
                "gpuTickPeriodNs": period_ns,
                "instrumentationHostMs": costs::elapsed(start)})
            );
        }
        costs::check()?;
        let errors = self.take_device_errors();
        if errors.is_empty() {
            Ok(())
        } else {
            Err(GpuError::Device(errors))
        }
    }

    /// Maps one staging buffer, waits for the device, and copies it out.
    fn map_download(&self, staging: &wgpu::Buffer) -> Result<Vec<u8>, GpuError> {
        let slice = staging.slice(..);
        let (sender, receiver) = std::sync::mpsc::sync_channel(1);
        slice.map_async(wgpu::MapMode::Read, move |result| {
            let _ = sender.send(result);
        });
        self.poll_wait()?;
        receiver
            .recv()
            .map_err(|error| GpuError::Map(error.to_string()))?
            .map_err(|error| GpuError::Map(error.to_string()))?;
        let mapped = slice
            .get_mapped_range()
            .map_err(|error| GpuError::Map(error.to_string()))?;
        let bytes = mapped.to_vec();
        drop(mapped);
        staging.unmap();
        Ok(bytes)
    }

    pub fn read_download(
        &mut self,
        handle: BufferHandle,
        offset: u64,
        size: u64,
    ) -> Result<Vec<u8>, GpuError> {
        let entry = self.resources.buffer_mut(handle)?;
        let (ready_offset, bytes, version, layout) = match entry.download.take() {
            Some(Download::Ready {
                offset,
                bytes,
                version,
                layout,
            }) => (offset, bytes, version, layout),
            other => {
                entry.download = other;
                return Err(GpuError::DownloadNotReady(handle));
            }
        };
        if ready_offset != offset || bytes.len() as u64 != size {
            let expected_size = bytes.len() as u64;
            entry.download = Some(Download::Ready {
                offset: ready_offset,
                bytes,
                version,
                layout,
            });
            return Err(GpuError::DownloadMismatch {
                expected_offset: ready_offset,
                expected_size,
                requested_offset: offset,
                requested_size: size,
            });
        }
        entry.completed_download_version = Some(version);
        entry.completed_download_layout = layout;
        Ok(bytes)
    }

    pub fn copied_download(
        &self,
        handle: BufferHandle,
        offset: u64,
        size: u64,
        start: Option<std::time::Instant>,
    ) -> Result<(), GpuError> {
        let entry = self.resources.buffer(handle)?;
        cost_record!(
            self.cost_id,
            "downloadHostCopy",
            json!({"buffer": handle, "version": entry.completed_download_version, "offset": offset,
            "bytes": size, "layout": entry.completed_download_layout, "hostCopies": 1, "hostMs": costs::elapsed(start)})
        );
        // The bytes are already the caller's. A cost output that failed to
        // record the copy is reported by the next call that can still fail
        // cleanly, not by this one after the download is gone.
        Ok(())
    }

    fn finish_validation_scope(&self, scope: wgpu::ErrorScopeGuard) -> Result<(), GpuError> {
        let future = scope.pop();
        self.poll_wait()?;
        match pollster::block_on(future) {
            Some(error) => Err(GpuError::Validation(error.to_string())),
            None => Ok(()),
        }
    }

    fn poll_wait(&self) -> Result<(), GpuError> {
        self.device
            .poll(wgpu::PollType::Wait {
                submission_index: None,
                timeout: Some(WAIT_TIMEOUT),
            })
            .map(|_| ())
            .map_err(|error| GpuError::Poll(error.to_string()))
    }
}

fn checked_range(
    operation: &'static str,
    offset: u64,
    size: u64,
    capacity: u64,
) -> Result<(), GpuError> {
    let end = offset.checked_add(size).ok_or(GpuError::OutOfBounds {
        operation,
        offset,
        size,
        capacity,
    })?;
    if end > capacity {
        return Err(GpuError::OutOfBounds {
            operation,
            offset,
            size,
            capacity,
        });
    }
    Ok(())
}

fn require_copy_alignment(name: &'static str, value: u64) -> Result<(), GpuError> {
    if value.is_multiple_of(COPY_ALIGNMENT) {
        Ok(())
    } else {
        Err(GpuError::InvalidArgument(format!(
            "GPU {name} {value} is not aligned to {COPY_ALIGNMENT} bytes"
        )))
    }
}

/// Whether any of `slots` names `buffer`. The device tracks usage per
/// allocation, so one allocation bound to a read slot and a write slot of the
/// same dispatch is refused however far apart the ranges are.
fn binds(slots: &[Option<BufferSlot>], buffer: BufferHandle) -> bool {
    slots.iter().flatten().any(|slot| slot.buffer == buffer)
}

/// How many bytes a copy or binding of `length` at `offset` moves. Both are
/// whole words; a range whose length is not one may still end the buffer,
/// and then takes the padding after its last byte along with it.
fn copy_extent(name: &'static str, offset: u64, length: u64, size: u64) -> Result<u64, GpuError> {
    if !offset.is_multiple_of(COPY_ALIGNMENT) {
        return Err(GpuError::InvalidArgument(format!(
            "GPU {name} offset {offset} is not aligned to {COPY_ALIGNMENT} bytes"
        )));
    }
    if length.is_multiple_of(COPY_ALIGNMENT) {
        return Ok(length);
    }
    if offset.checked_add(length) != Some(size) {
        return Err(GpuError::InvalidArgument(format!(
            "GPU {name} size {length} is not a multiple of {COPY_ALIGNMENT} bytes and does not end the buffer"
        )));
    }
    align_up(length, COPY_ALIGNMENT)
}

fn align_up(value: u64, alignment: u64) -> Result<u64, GpuError> {
    value
        .checked_add(alignment - 1)
        .map(|sum| sum / alignment * alignment)
        .ok_or_else(|| GpuError::InvalidArgument("GPU allocation size overflow".to_owned()))
}

fn spirv_words(bytes: &[u8]) -> Result<Vec<u32>, GpuError> {
    if bytes.is_empty() || !bytes.len().is_multiple_of(4) {
        return Err(GpuError::InvalidArgument(
            "SPIR-V must be a non-empty sequence of complete 32-bit words".to_owned(),
        ));
    }
    let words: Vec<u32> = bytes
        .as_chunks::<4>()
        .0
        .iter()
        .copied()
        .map(u32::from_le_bytes)
        .collect();
    if words.first().copied() != Some(0x0723_0203) {
        return Err(GpuError::InvalidArgument(
            "SPIR-V has an invalid magic word or byte order".to_owned(),
        ));
    }
    Ok(words)
}

const OP_ENTRY_POINT: u32 = 15;
const OP_EXECUTION_MODE: u32 = 16;
const EXECUTION_MODEL_GL_COMPUTE: u32 = 5;
const EXECUTION_MODE_LOCAL_SIZE: u32 = 17;

/// The instructions after the five-word header, each as its opcode and
/// operands, refusing a word count that is zero or runs past the module.
fn spirv_instructions(words: &[u32]) -> Result<Vec<(u32, &[u32])>, GpuError> {
    let mut instructions = Vec::new();
    let mut at = 5.min(words.len());
    while at < words.len() {
        let count = (words[at] >> 16) as usize;
        if count == 0 || at + count > words.len() {
            return Err(GpuError::InvalidArgument(format!(
                "SPIR-V instruction at word {at} has an invalid length"
            )));
        }
        instructions.push((words[at] & 0xffff, &words[at + 1..at + count]));
        at += count;
    }
    Ok(instructions)
}

/// The words of a SPIR-V literal string, NUL-terminated and padded to a word.
fn spirv_string(words: &[u32]) -> (Vec<u8>, usize) {
    let mut bytes = Vec::new();
    for (index, word) in words.iter().enumerate() {
        for byte in word.to_le_bytes() {
            if byte == 0 {
                return (bytes, index + 1);
            }
            bytes.push(byte);
        }
    }
    (bytes, words.len())
}

/// Refuses a declared workgroup size that is not the one the entry point's
/// `LocalSize` execution mode compiles in. Dispatch geometry is computed from
/// the declared size, so a wrong one silently covers the wrong elements.
fn check_workgroup_size(
    words: &[u32],
    entry_point: &str,
    declared: [u32; 3],
) -> Result<(), GpuError> {
    let instructions = spirv_instructions(words)?;
    let entry = instructions.iter().find_map(|(opcode, operands)| {
        if *opcode != OP_ENTRY_POINT
            || operands.len() < 3
            || operands[0] != EXECUTION_MODEL_GL_COMPUTE
        {
            return None;
        }
        let (name, _) = spirv_string(&operands[2..]);
        (name == entry_point.as_bytes()).then_some(operands[1])
    });
    let Some(entry) = entry else {
        return Ok(());
    };
    let compiled = instructions.iter().find_map(|(opcode, operands)| {
        (*opcode == OP_EXECUTION_MODE
            && operands.len() == 5
            && operands[0] == entry
            && operands[1] == EXECUTION_MODE_LOCAL_SIZE)
            .then(|| [operands[2], operands[3], operands[4]])
    });
    match compiled {
        Some(compiled) if compiled != declared => Err(GpuError::InvalidArgument(format!(
            "GPU kernel declares workgroup size {declared:?}, but {entry_point} is compiled for {compiled:?}"
        ))),
        _ => Ok(()),
    }
}

fn validate_kernel_descriptor(
    descriptor: &KernelDescriptor<'_>,
    limits: &wgpu::Limits,
) -> Result<(), GpuError> {
    if descriptor.entry_point.is_empty() || descriptor.entry_point.as_bytes().contains(&0) {
        return Err(GpuError::InvalidArgument(
            "GPU entry point must be non-empty text without NUL bytes".to_owned(),
        ));
    }
    spirv_words(descriptor.spirv)?;
    if !descriptor.uniform_size.is_multiple_of(COPY_ALIGNMENT) {
        return Err(GpuError::InvalidArgument(format!(
            "GPU uniform size must be aligned to {COPY_ALIGNMENT} bytes"
        )));
    }
    if descriptor.uniform_size > limits.max_uniform_buffer_binding_size {
        return Err(GpuError::InvalidArgument(format!(
            "GPU uniform size {} exceeds the device limit {}",
            descriptor.uniform_size, limits.max_uniform_buffer_binding_size
        )));
    }
    let [x, y, z] = descriptor.workgroup_size;
    if x == 0 || y == 0 || z == 0 {
        return Err(GpuError::InvalidArgument(
            "GPU workgroup dimensions must be nonzero".to_owned(),
        ));
    }
    let invocations = u64::from(x) * u64::from(y) * u64::from(z);
    if x > limits.max_compute_workgroup_size_x
        || y > limits.max_compute_workgroup_size_y
        || z > limits.max_compute_workgroup_size_z
        || invocations > u64::from(limits.max_compute_invocations_per_workgroup)
    {
        return Err(GpuError::InvalidArgument(format!(
            "GPU workgroup size {:?} exceeds device limits",
            descriptor.workgroup_size
        )));
    }
    if descriptor.readonly_bindings > limits.max_storage_buffers_per_shader_stage
        || descriptor.writable_bindings > limits.max_storage_buffers_per_shader_stage
        || descriptor.readonly_bindings > limits.max_bindings_per_bind_group
        || descriptor.writable_bindings > limits.max_bindings_per_bind_group
        || descriptor
            .readonly_bindings
            .saturating_add(descriptor.writable_bindings)
            > limits.max_storage_buffers_per_shader_stage
    {
        return Err(GpuError::InvalidArgument(
            "GPU storage binding count exceeds the device limit".to_owned(),
        ));
    }
    let required_bind_groups = if descriptor.uniform_size != 0 {
        3
    } else if descriptor.writable_bindings != 0 {
        2
    } else if descriptor.readonly_bindings != 0 {
        1
    } else {
        0
    };
    if required_bind_groups > limits.max_bind_groups {
        return Err(GpuError::InvalidArgument(format!(
            "GPU kernel requires {required_bind_groups} bind groups, but the device supports {}",
            limits.max_bind_groups
        )));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn invalid_timestamp_intervals_do_not_claim_device_duration() {
        assert_eq!(timestamp_milliseconds(10, 1010, 2.0), Ok(0.002));
        assert_eq!(timestamp_milliseconds(0, 0, 1.0), Err("equal-timestamps"));
        assert_eq!(
            timestamp_milliseconds(u64::MAX, u64::MAX, 1.0),
            Err("equal-timestamps")
        );
        assert_eq!(
            timestamp_milliseconds(10, 9, 1.0),
            Err("reversed-timestamps")
        );
        for period in [0.0, -1.0, f32::NAN, f32::INFINITY] {
            assert_eq!(
                timestamp_milliseconds(10, 20, period),
                Err("invalid-timestamp-period")
            );
        }
    }

    #[test]
    fn device_faults_are_buffered_and_drained_once() {
        let errors = DeviceErrorQueue::default();
        let first = errors.clone();
        let second = errors.clone();
        std::thread::scope(|scope| {
            scope.spawn(move || first.record("uncaptured validation error".to_owned()));
            scope.spawn(move || second.record("device lost".to_owned()));
        });
        let mut drained = errors.take();
        drained.sort();
        assert_eq!(drained, ["device lost", "uncaptured validation error"]);
        assert!(errors.take().is_empty());
    }

    #[test]
    fn device_faults_survive_a_poisoned_callback_queue() {
        let errors = DeviceErrorQueue::default();
        let poisoned = errors.clone();
        assert!(
            std::thread::spawn(move || {
                let _guard = poisoned.messages.lock().unwrap();
                panic!("simulated callback failure");
            })
            .join()
            .is_err()
        );
        errors.record("device lost after callback failure".to_owned());
        assert_eq!(
            errors.take(),
            ["device lost after callback failure".to_owned()]
        );
    }

    #[test]
    fn resource_tables_reject_wrong_and_stale_handles() {
        let mut resources = Resources::<u64, u64, u64>::new();
        let buffer = resources.insert_buffer(11).unwrap();
        assert_eq!(
            resources.remove_kernel(buffer),
            Err(GpuError::WrongHandle {
                handle: buffer,
                expected: ResourceKind::Kernel,
                actual: ResourceKind::Buffer,
            })
        );
        assert_eq!(resources.remove_buffer(buffer), Ok(11));
        assert_eq!(
            resources.remove_buffer(buffer),
            Err(GpuError::StaleHandle(buffer))
        );
    }

    #[test]
    fn public_handles_do_not_cross_contexts() {
        let mut left = Resources::<(), (), ()>::new();
        let mut right = Resources::<(), (), ()>::new();
        let handle = left.insert_buffer(()).unwrap();
        assert_eq!(right.buffer(handle), Err(GpuError::StaleHandle(handle)));
        assert_ne!(handle, right.insert_buffer(()).unwrap());
    }

    #[test]
    fn range_checks_reject_overflow_and_overrun() {
        assert_eq!(checked_range("test", 4, 4, 8), Ok(()));
        assert!(matches!(
            checked_range("test", 5, 4, 8),
            Err(GpuError::OutOfBounds { .. })
        ));
        assert!(matches!(
            checked_range("test", u64::MAX, 2, u64::MAX),
            Err(GpuError::OutOfBounds { .. })
        ));
    }

    #[test]
    fn a_range_that_ends_the_buffer_may_end_partway_through_a_word() {
        assert_eq!(copy_extent("upload", 0, 8, 8), Ok(8));
        assert_eq!(copy_extent("upload", 0, 3, 3), Ok(4));
        assert_eq!(copy_extent("upload", 4, 3, 7), Ok(4));
        assert!(copy_extent("upload", 0, 3, 8).is_err());
        assert!(copy_extent("upload", 2, 2, 4).is_err());
    }

    #[test]
    fn narrow_buffers_move_bytes_that_end_partway_through_a_word_when_available() {
        let Ok(mut gpu) = GpuContext::new() else {
            assert!(std::env::var_os("NUPP_REQUIRE_GPU").is_none());
            return;
        };
        let buffer = gpu.create_buffer(3).unwrap();
        gpu.upload(buffer, 0, &[1, 2, 3]).unwrap();
        gpu.queue_download(buffer, 0, 3).unwrap();
        gpu.synchronize().unwrap();
        assert_eq!(gpu.read_download(buffer, 0, 3).unwrap(), [1, 2, 3]);
        let kernel = gpu.create_test_kernel().unwrap();
        let bindings = gpu.create_bindings(kernel).unwrap();
        gpu.set_write_buffer(bindings, 0, buffer, 0, 3).unwrap();
        gpu.release_bindings(bindings).unwrap();
        gpu.release_kernel(kernel).unwrap();
        gpu.release_buffer(buffer).unwrap();
    }

    #[test]
    fn a_cost_output_failure_leaves_a_consumed_download_read_when_available() {
        let _costs_guard = costs::TEST_LOCK
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        let Ok(mut gpu) = GpuContext::new() else {
            assert!(std::env::var_os("NUPP_REQUIRE_GPU").is_none());
            return;
        };
        let buffer = gpu.create_buffer(16).unwrap();
        gpu.upload(buffer, 0, &[9; 16]).unwrap();
        gpu.queue_download(buffer, 0, 16).unwrap();
        gpu.synchronize().unwrap();
        assert_eq!(gpu.read_download(buffer, 0, 16).unwrap(), [9; 16]);
        costs::inject_failure("injected write failure");
        assert_eq!(gpu.copied_download(buffer, 0, 16, None), Ok(()));
        assert!(matches!(costs::check(), Err(GpuError::CostOutput(_))));
        gpu.release_buffer(buffer).unwrap();
    }

    #[test]
    fn one_allocation_is_not_bound_for_reading_and_writing() {
        let slot = |buffer| {
            Some(BufferSlot {
                buffer,
                offset: 0,
                size: 4,
                layout: Value::Null,
            })
        };
        assert!(binds(&[None, slot(7)], 7));
        assert!(!binds(&[None, slot(7)], 8));
        assert!(!binds(&[None, None], 7));
    }

    fn module_with_local_size(size: [u32; 3]) -> Vec<u32> {
        let mut words = vec![0x0723_0203, 0x0001_0300, 0, 20, 0];
        // OpEntryPoint GLCompute %4 "main"
        words.extend([(5 << 16) | OP_ENTRY_POINT, EXECUTION_MODEL_GL_COMPUTE, 4]);
        words.push(u32::from_le_bytes(*b"main"));
        words.push(0);
        // OpExecutionMode %4 LocalSize x y z
        words.extend([(6 << 16) | OP_EXECUTION_MODE, 4, EXECUTION_MODE_LOCAL_SIZE]);
        words.extend(size);
        words
    }

    #[test]
    fn a_declared_workgroup_size_must_be_the_compiled_one() {
        let words = module_with_local_size([64, 1, 1]);
        assert_eq!(check_workgroup_size(&words, "main", [64, 1, 1]), Ok(()));
        assert!(check_workgroup_size(&words, "main", [128, 1, 1]).is_err());
        assert_eq!(check_workgroup_size(&words, "other", [128, 1, 1]), Ok(()));
        let mut truncated = words.clone();
        truncated.truncate(words.len() - 1);
        assert!(check_workgroup_size(&truncated, "main", [64, 1, 1]).is_err());
    }

    #[test]
    fn an_unread_download_says_so_when_available() {
        let Ok(mut gpu) = GpuContext::new() else {
            assert!(std::env::var_os("NUPP_REQUIRE_GPU").is_none());
            return;
        };
        let buffer = gpu.create_buffer(16).unwrap();
        gpu.queue_download(buffer, 0, 16).unwrap();
        assert_eq!(
            gpu.queue_download(buffer, 0, 16),
            Err(GpuError::DownloadPending(buffer))
        );
        gpu.synchronize().unwrap();
        assert_eq!(
            gpu.queue_download(buffer, 0, 16),
            Err(GpuError::DownloadUnread(buffer))
        );
        gpu.read_download(buffer, 0, 16).unwrap();
        gpu.queue_download(buffer, 0, 16).unwrap();
        gpu.synchronize().unwrap();
        gpu.release_buffer(buffer).unwrap();
    }

    #[test]
    fn spirv_ingestion_is_bounded_and_endian_checked() {
        assert!(spirv_words(&[]).is_err());
        assert!(spirv_words(&[3, 2, 35]).is_err());
        assert!(spirv_words(&[7, 35, 2, 3]).is_err());
        assert_eq!(spirv_words(&[3, 2, 35, 7]), Ok(vec![0x0723_0203]));
    }

    #[test]
    fn adapter_compute_round_trip_when_available() {
        let _costs_guard = costs::TEST_LOCK
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        let required = std::env::var_os("NUPP_REQUIRE_GPU").is_some();
        let costs_path =
            std::env::temp_dir().join(format!("nupp-gpu-integration-{}.jsonl", std::process::id()));
        costs::configure(Some(costs_path.to_str().unwrap())).unwrap();
        let mut gpu = match GpuContext::new() {
            Ok(gpu) => gpu,
            Err(error) => {
                assert!(!required, "required GPU adapter is unavailable: {error}");
                eprintln!("GPU adapter test skipped: {error}");
                costs::configure(None).unwrap();
                std::fs::remove_file(&costs_path).unwrap();
                return;
            }
        };
        let context_id = gpu.cost_id();
        let timestamp_supported = gpu.timestamp_supported;
        let kernel = match gpu.create_test_kernel() {
            Ok(kernel) => kernel,
            Err(error) => {
                assert!(!required, "required GPU test kernel failed: {error}");
                eprintln!("GPU adapter test skipped: {error}");
                costs::configure(None).unwrap();
                std::fs::remove_file(&costs_path).unwrap();
                return;
            }
        };
        gpu.metadata(kernel, true, br#"{"sourceFile":"round-trip.nupp","sourceLine":8,"artifactId":"fixture","writableNames":["values"]}"#).unwrap();
        let buffer = gpu.create_buffer(16).unwrap();
        gpu.metadata(
            buffer,
            false,
            br#"{"format":"uint32","shape":[4],"elementBytes":4}"#,
        )
        .unwrap();
        gpu.upload(buffer, 0, &[1, 0, 0, 0, 2, 0, 0, 0, 3, 0, 0, 0, 4, 0, 0, 0])
            .unwrap();
        let bindings = gpu.create_bindings(kernel).unwrap();
        gpu.set_write_buffer(bindings, 0, buffer, 0, 16).unwrap();
        gpu.metadata(buffer, false, br#"{"shape":[2,2],"strides":[2,1]}"#)
            .unwrap();
        gpu.dispatch(bindings, [4, 1, 1], &[]).unwrap();
        gpu.dispatch(bindings, [4, 1, 1], &[]).unwrap();
        gpu.queue_download(buffer, 0, 16).unwrap();
        // This upload is ordered after the queued copy; its version must not
        // replace the downloaded snapshot's provenance.
        gpu.metadata(buffer, false, br#"{"shape":[1,4],"strides":[4,1]}"#)
            .unwrap();
        gpu.upload(buffer, 0, &[0; 16]).unwrap();
        gpu.synchronize().unwrap();
        assert_eq!(
            gpu.read_download(buffer, 0, 16).unwrap(),
            [3, 0, 0, 0, 4, 0, 0, 0, 5, 0, 0, 0, 6, 0, 0, 0]
        );
        gpu.copied_download(buffer, 0, 16, costs::clock()).unwrap();
        // Exercise hardware without timestamp support even on an adapter that
        // supports queries. No host duration may masquerade as device time.
        gpu.timestamp_supported = false;
        gpu.dispatch(bindings, [4, 1, 1], &[]).unwrap();
        gpu.synchronize().unwrap();
        costs::configure(None).unwrap();
        // A retained device keeps its feature capability, but disabling costs
        // must stop allocating and resolving queries on later dispatches.
        gpu.timestamp_supported = timestamp_supported;
        gpu.dispatch(bindings, [4, 1, 1], &[]).unwrap();
        assert!(gpu.pending_timestamps.is_empty());
        gpu.synchronize().unwrap();
        let text = std::fs::read_to_string(&costs_path).unwrap();
        let rows: Vec<Value> = text
            .lines()
            .map(|line| serde_json::from_str(line).unwrap())
            .filter(|row: &Value| row["context"] == context_id)
            .collect();
        assert!(rows.iter().any(|r| r["operation"] == "adapterDevice"));
        let dispatches: Vec<_> = rows
            .iter()
            .filter(|r| r["operation"] == "dispatch")
            .collect();
        assert_eq!(dispatches.len(), 3);
        assert_eq!(dispatches[2]["gpuTiming"], "unavailable");
        assert!(dispatches[2]["gpuMs"].is_null());
        assert_eq!(dispatches[0]["phase"], "first-use");
        assert_eq!(dispatches[1]["phase"], "steady-state");
        assert_eq!(dispatches[0]["bindingsReused"], false);
        assert_eq!(
            dispatches[1]["bindingsReused"], true,
            "absent layouts do not count as cache misses"
        );
        assert_eq!(dispatches[1]["write"][0]["version"], 3);
        assert_eq!(
            dispatches[0]["write"][0]["layout"]["shape"],
            json!([4]),
            "bindings retain their own view shape"
        );
        assert_eq!(dispatches[0]["metadata"]["writableNames"][0], "values");
        for operation in ["downloadQueue", "downloadMapCopy", "downloadHostCopy"] {
            let row = rows.iter().find(|r| r["operation"] == operation).unwrap();
            assert_eq!(
                row["version"], 3,
                "{operation} keeps the queued snapshot version"
            );
            assert_eq!(row["bytes"], 16);
            assert_eq!(
                row["layout"]["shape"],
                json!([2, 2]),
                "{operation} keeps queued layout"
            );
        }
        if timestamp_supported {
            let timings: Vec<_> = rows
                .iter()
                .filter(|r| r["operation"] == "kernelExecution")
                .collect();
            assert_eq!(timings.len(), 2);
            for timing in timings {
                let begin = timing["gpuTicksBegin"].as_str().unwrap().parse().unwrap();
                let end = timing["gpuTicksEnd"].as_str().unwrap().parse().unwrap();
                let period = timing["gpuTickPeriodNs"].as_f64().unwrap() as f32;
                match timestamp_milliseconds(begin, end, period) {
                    Ok(milliseconds) => {
                        assert_eq!(timing["gpuTiming"], "timestamp-query");
                        assert_eq!(timing["gpuMs"].as_f64(), Some(milliseconds));
                        assert!(timing["gpuTimingReason"].is_null());
                    }
                    Err(reason) => {
                        assert_eq!(timing["gpuTiming"], "unavailable");
                        assert!(timing["gpuMs"].is_null());
                        assert_eq!(timing["gpuTimingReason"], reason);
                    }
                }
            }
        } else {
            assert_eq!(dispatches[0]["gpuTiming"], "unavailable");
        }
        std::fs::remove_file(costs_path).unwrap();
        gpu.release_bindings(bindings).unwrap();
        gpu.release_kernel(kernel).unwrap();
        gpu.release_buffer(buffer).unwrap();
        assert_eq!(
            gpu.release_buffer(buffer),
            Err(GpuError::StaleHandle(buffer))
        );
    }

    #[test]
    #[ignore = "asserts a wall-clock ratio between two dispatches, so host load fails it; \
                run it with --ignored on a quiet machine"]
    fn adapter_timestamps_belong_to_the_current_dispatch_when_available() {
        let _costs_guard = costs::TEST_LOCK
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        let required = std::env::var_os("NUPP_REQUIRE_GPU").is_some();
        let path = std::env::temp_dir().join(format!(
            "nupp-gpu-current-timestamps-{}.jsonl",
            std::process::id()
        ));
        costs::configure(Some(path.to_str().unwrap())).unwrap();
        let mut gpu = match GpuContext::new() {
            Ok(gpu) => gpu,
            Err(error) => {
                costs::configure(None).unwrap();
                std::fs::remove_file(path).unwrap();
                assert!(!required, "required GPU adapter is unavailable: {error}");
                return;
            }
        };
        if !gpu.timestamp_supported {
            costs::configure(None).unwrap();
            std::fs::remove_file(path).unwrap();
            return;
        }
        const SHADER: &str = r#"
            @group(1) @binding(0) var<storage, read_write> values: array<u32>;
            @compute @workgroup_size(64)
            fn main(@builtin(global_invocation_id) id: vec3<u32>) {
                var value = id.x + 11u;
                for (var round = 0u; round < 64u; round++) {
                    value = value * 1664525u + 1013904223u;
                    value = value ^ (value >> 13u);
                }
                values[id.x] = value;
            }
        "#;
        let kernel = gpu.create_wgsl_test_kernel(SHADER, [64, 1, 1]).unwrap();
        const COUNT: u32 = 262144;
        let bytes = u64::from(COUNT) * 4;
        let buffer = gpu.create_buffer(bytes).unwrap();
        let binding = gpu.create_bindings(kernel).unwrap();
        gpu.set_write_buffer(binding, 0, buffer, 0, bytes).unwrap();
        let mut expected = Vec::with_capacity(bytes as usize);
        for index in 0..COUNT {
            let mut value = index + 11;
            for _ in 0..64 {
                value = value.wrapping_mul(1664525).wrapping_add(1013904223);
                value ^= value >> 13;
            }
            expected.extend_from_slice(&value.to_le_bytes());
        }
        // The large/small contrast checks attribution, not performance: a
        // one-submission-old counter would reverse these two populations.
        for count in [COUNT, 64, COUNT, 64, COUNT] {
            gpu.dispatch(binding, [count, 1, 1], &[]).unwrap();
            gpu.queue_download(buffer, 0, bytes).unwrap();
            gpu.synchronize().unwrap();
            assert_eq!(gpu.read_download(buffer, 0, bytes).unwrap(), expected);
        }
        let sequence = gpu.dispatch_sequence;
        gpu.dispatch(binding, [0, 1, 1], &[]).unwrap();
        assert_eq!(gpu.dispatch_sequence, sequence);
        assert!(gpu.pending_timestamps.is_empty());
        costs::configure(None).unwrap();
        let rows: Vec<Value> = std::fs::read_to_string(&path)
            .unwrap()
            .lines()
            .map(|line| serde_json::from_str(line).unwrap())
            .collect();
        let mut heavy = Vec::new();
        let mut light = Vec::new();
        for row in rows
            .iter()
            .filter(|row| row["operation"] == "kernelExecution")
        {
            let milliseconds = row["gpuMs"].as_f64().unwrap_or_else(|| {
                panic!("nonempty dispatch has no usable device interval: {row}")
            });
            assert!(milliseconds > 0.0);
            if row["dispatch"].as_u64().unwrap() % 2 == 1 {
                heavy.push(milliseconds);
            } else {
                light.push(milliseconds);
            }
        }
        assert_eq!((heavy.len(), light.len()), (3, 2));
        heavy.sort_by(f64::total_cmp);
        light.sort_by(f64::total_cmp);
        assert!(
            heavy[1] > 2.0 * light[1],
            "timestamps are not attributed to current work: heavy={heavy:?}, light={light:?}"
        );
        std::fs::remove_file(path).unwrap();
    }

    impl GpuContext {
        fn create_test_kernel(&mut self) -> Result<KernelHandle, GpuError> {
            const SHADER: &str = r#"
                @group(1) @binding(0)
                var<storage, read_write> values: array<u32>;

                @compute @workgroup_size(1)
                fn main(@builtin(global_invocation_id) id: vec3<u32>) {
                    values[id.x] = values[id.x] + 1u;
                }
            "#;
            self.create_wgsl_test_kernel(SHADER, [1, 1, 1])
        }

        fn create_wgsl_test_kernel(
            &mut self,
            shader: &str,
            workgroup_size: [u32; 3],
        ) -> Result<KernelHandle, GpuError> {
            let scope = self.device.push_error_scope(wgpu::ErrorFilter::Validation);
            let module = self
                .device
                .create_shader_module(wgpu::ShaderModuleDescriptor {
                    label: Some("Nupp GPU round-trip test"),
                    source: wgpu::ShaderSource::Wgsl(Cow::Borrowed(shader)),
                });
            let pipeline = self
                .device
                .create_compute_pipeline(&wgpu::ComputePipelineDescriptor {
                    label: Some("Nupp GPU round-trip test pipeline"),
                    layout: None,
                    module: &module,
                    entry_point: Some("main"),
                    compilation_options: wgpu::PipelineCompilationOptions::default(),
                    cache: None,
                });
            self.finish_validation_scope(scope)?;
            let writable_layout = Some(pipeline.get_bind_group_layout(1));
            self.resources.insert_kernel(KernelEntry {
                pipeline,
                readonly_layout: None,
                writable_layout,
                uniform_layout: None,
                readonly_bindings: 0,
                writable_bindings: 1,
                uniform_size: 0,
                workgroup_size,
                metadata: Value::Null,
                dispatches: 0,
            })
        }
    }
}
