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
use std::ops::Range;
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
    pub vendor: u32,
    pub device: u32,
    pub backend: String,
    pub device_type: String,
    pub driver: String,
    pub driver_info: String,
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
    staging: wgpu::Buffer,
    operation: u64,
    kernel: KernelHandle,
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
            vendor: info.vendor,
            device: info.device,
            backend: info.backend.to_str().to_owned(),
            device_type: format!("{:?}", info.device_type),
            driver: info.driver,
            driver_info: info.driver_info,
        }
    }

    pub fn take_device_errors(&self) -> Vec<String> {
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
        let start = costs::clock();
        let buffer = self.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("Nupp resident compute buffer"),
            size,
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
        require_copy_alignment("upload offset", offset)?;
        require_copy_alignment("upload size", bytes.len() as u64)?;
        if !bytes.is_empty() {
            self.queue.write_buffer(&entry.buffer, offset, bytes);
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
        require_copy_alignment("storage binding size", size)?;
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
        let query = self.timestamp_supported.then(|| {
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
            encoder.resolve_query_set(&query, 0..2, &resolve, 0);
            encoder.copy_buffer_to_buffer(&resolve, 0, &staging, 0, 16);
            self.pending_timestamps.push(PendingTimestamp {
                staging,
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
        require_copy_alignment("download offset", offset)?;
        require_copy_alignment("download size", size)?;
        if entry.download.is_some() {
            return Err(GpuError::DownloadPending(handle));
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
            let (staging, offset, version, layout) =
                match self.resources.buffer(handle)?.download.as_ref() {
                    Some(Download::Pending {
                        staging,
                        offset,
                        version,
                        layout,
                    }) => (staging.clone(), *offset, *version, layout.clone()),
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
                Ok(bytes) => {
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
            let bytes = self.map_download(&pending.staging)?;
            let begin = u64::from_le_bytes(bytes[0..8].try_into().expect("timestamp width"));
            let end = u64::from_le_bytes(bytes[8..16].try_into().expect("timestamp width"));
            let milliseconds = end.wrapping_sub(begin) as f64
                * self.queue.get_timestamp_period() as f64
                / 1_000_000.0;
            cost_record!(
                self.cost_id,
                "kernelExecution",
                json!({"dispatch": pending.operation, "kernel": pending.kernel,
                "gpuMs": milliseconds, "gpuTiming": "timestamp-query", "instrumentationHostMs": costs::elapsed(start)})
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
        costs::check()
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
) -> Result<Range<u64>, GpuError> {
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
    Ok(offset..end)
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
        assert_eq!(checked_range("test", 4, 4, 8), Ok(4..8));
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
    fn spirv_ingestion_is_bounded_and_endian_checked() {
        assert!(spirv_words(&[]).is_err());
        assert!(spirv_words(&[3, 2, 35]).is_err());
        assert!(spirv_words(&[7, 35, 2, 3]).is_err());
        assert_eq!(spirv_words(&[3, 2, 35, 7]), Ok(vec![0x0723_0203]));
    }

    #[test]
    fn adapter_compute_round_trip_when_available() {
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
            assert!(timings.iter().all(|r| r["gpuMs"].as_f64().unwrap() >= 0.0));
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
            let scope = self.device.push_error_scope(wgpu::ErrorFilter::Validation);
            let module = self
                .device
                .create_shader_module(wgpu::ShaderModuleDescriptor {
                    label: Some("Nupp GPU round-trip test"),
                    source: wgpu::ShaderSource::Wgsl(Cow::Borrowed(SHADER)),
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
                workgroup_size: [1, 1, 1],
                metadata: Value::Null,
                dispatches: 0,
            })
        }
    }
}
