//! Safe, handle-based native compute over WGPU.
//!
//! WGPU owns command and device-resource lifetimes. This crate adds the
//! language-facing invariants WGPU does not provide: context ownership,
//! resource kind checks, stale-handle rejection, byte-range validation, an
//! explicit synchronization boundary, and one queued readback per buffer.

#![forbid(unsafe_code)]

use std::borrow::Cow;
use std::collections::HashMap;
use std::error::Error;
use std::fmt;
use std::num::NonZeroU64;
use std::ops::Range;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;

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

#[derive(Clone, Copy, Debug)]
struct BufferSlot {
    buffer: BufferHandle,
    offset: u64,
    size: u64,
}

enum Download {
    Pending { staging: wgpu::Buffer, offset: u64 },
    Ready { offset: u64, bytes: Vec<u8> },
}

struct BufferEntry {
    buffer: wgpu::Buffer,
    size: u64,
    download: Option<Download>,
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
}

struct BindingEntry {
    kernel: KernelHandle,
    readonly: Vec<Option<BufferSlot>>,
    writable: Vec<Option<BufferSlot>>,
    uniform: Option<wgpu::Buffer>,
}

pub struct GpuContext {
    _instance: wgpu::Instance,
    adapter: wgpu::Adapter,
    device: wgpu::Device,
    queue: wgpu::Queue,
    resources: Resources<BufferEntry, KernelEntry, BindingEntry>,
    pending_downloads: Vec<BufferHandle>,
    device_errors: Arc<Mutex<Vec<String>>>,
}

impl GpuContext {
    pub fn new() -> Result<Self, GpuError> {
        let instance =
            wgpu::Instance::new(wgpu::InstanceDescriptor::new_without_display_handle_from_env());
        let adapter = pollster::block_on(instance.request_adapter(&wgpu::RequestAdapterOptions {
            power_preference: wgpu::PowerPreference::HighPerformance,
            force_fallback_adapter: false,
            compatible_surface: None,
            apply_limit_buckets: false,
        }))
        .map_err(|error| GpuError::AdapterUnavailable(error.to_string()))?;
        let descriptor = wgpu::DeviceDescriptor {
            label: Some("Nupp native compute device"),
            required_features: wgpu::Features::empty(),
            required_limits: adapter.limits(),
            experimental_features: wgpu::ExperimentalFeatures::disabled(),
            memory_hints: wgpu::MemoryHints::MemoryUsage,
            trace: wgpu::Trace::Off,
        };
        let (device, queue) = pollster::block_on(adapter.request_device(&descriptor))
            .map_err(|error| GpuError::DeviceRequest(error.to_string()))?;
        let device_errors = Arc::new(Mutex::new(Vec::new()));
        let uncaptured = Arc::clone(&device_errors);
        device.on_uncaptured_error(Arc::new(move |error| {
            if let Ok(mut messages) = uncaptured.lock() {
                messages.push(error.to_string());
            }
        }));
        let lost = Arc::clone(&device_errors);
        device.set_device_lost_callback(move |reason, message| {
            if let Ok(mut messages) = lost.lock() {
                messages.push(format!("device lost ({reason:?}): {message}"));
            }
        });
        Ok(Self {
            _instance: instance,
            adapter,
            device,
            queue,
            resources: Resources::new(),
            pending_downloads: Vec::new(),
            device_errors,
        })
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
        match self.device_errors.lock() {
            Ok(mut errors) => std::mem::take(&mut *errors),
            Err(poisoned) => std::mem::take(&mut *poisoned.into_inner()),
        }
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
        let buffer = self.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("Nupp resident compute buffer"),
            size,
            usage: wgpu::BufferUsages::STORAGE
                | wgpu::BufferUsages::COPY_SRC
                | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });
        self.resources.insert_buffer(BufferEntry {
            buffer,
            size,
            download: None,
        })
    }

    pub fn release_buffer(&mut self, handle: BufferHandle) -> Result<(), GpuError> {
        if matches!(
            self.resources.buffer(handle)?.download,
            Some(Download::Pending { .. })
        ) {
            return Err(GpuError::DownloadPending(handle));
        }
        self.resources.remove_buffer(handle)?;
        Ok(())
    }

    pub fn upload(&self, handle: BufferHandle, offset: u64, bytes: &[u8]) -> Result<(), GpuError> {
        let entry = self.resources.buffer(handle)?;
        checked_range("upload", offset, bytes.len() as u64, entry.size)?;
        require_copy_alignment("upload offset", offset)?;
        require_copy_alignment("upload size", bytes.len() as u64)?;
        if !bytes.is_empty() {
            self.queue.write_buffer(&entry.buffer, offset, bytes);
        }
        Ok(())
    }

    pub fn create_kernel(
        &mut self,
        descriptor: &KernelDescriptor<'_>,
    ) -> Result<KernelHandle, GpuError> {
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
        self.resources.insert_kernel(KernelEntry {
            pipeline,
            readonly_layout,
            writable_layout,
            uniform_layout,
            readonly_bindings: descriptor.readonly_bindings,
            writable_bindings: descriptor.writable_bindings,
            uniform_size: descriptor.uniform_size,
            workgroup_size: descriptor.workgroup_size,
        })
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
        self.resources.remove_kernel(handle)?;
        Ok(())
    }

    pub fn create_bindings(&mut self, kernel: KernelHandle) -> Result<BindingHandle, GpuError> {
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
        };
        self.resources.insert_binding(binding)
    }

    pub fn release_bindings(&mut self, handle: BindingHandle) -> Result<(), GpuError> {
        self.resources.remove_binding(handle)?;
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
        *target = Some(BufferSlot {
            buffer,
            offset,
            size,
        });
        Ok(())
    }

    pub fn dispatch(
        &self,
        bindings: BindingHandle,
        work_items: [u32; 3],
        uniforms: &[u8],
    ) -> Result<(), GpuError> {
        let binding = self.resources.binding(bindings)?;
        let kernel = self.resources.kernel(binding.kernel)?;
        if uniforms.len() as u64 != kernel.uniform_size {
            return Err(GpuError::InvalidArgument(format!(
                "GPU dispatch supplied {} uniform bytes, but the kernel requires {}",
                uniforms.len(),
                kernel.uniform_size
            )));
        }
        require_copy_alignment("uniform size", uniforms.len() as u64)?;
        let readonly_group =
            self.make_storage_group(kernel.readonly_layout.as_ref(), &binding.readonly, false)?;
        let writable_group =
            self.make_storage_group(kernel.writable_layout.as_ref(), &binding.writable, true)?;
        let uniform_group = if let (Some(layout), Some(buffer)) =
            (kernel.uniform_layout.as_ref(), binding.uniform.as_ref())
        {
            self.queue.write_buffer(buffer, 0, uniforms);
            Some(self.device.create_bind_group(&wgpu::BindGroupDescriptor {
                label: Some("Nupp uniform bind group"),
                layout,
                entries: &[wgpu::BindGroupEntry {
                    binding: 0,
                    resource: wgpu::BindingResource::Buffer(wgpu::BufferBinding {
                        buffer,
                        offset: 0,
                        size: NonZeroU64::new(kernel.uniform_size),
                    }),
                }],
            }))
        } else {
            None
        };
        if work_items.contains(&0) {
            return Ok(());
        }
        let groups = [
            work_items[0].div_ceil(kernel.workgroup_size[0]),
            work_items[1].div_ceil(kernel.workgroup_size[1]),
            work_items[2].div_ceil(kernel.workgroup_size[2]),
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
        {
            let mut pass = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("Nupp compute pass"),
                timestamp_writes: None,
            });
            pass.set_pipeline(&kernel.pipeline);
            if let Some(group) = readonly_group.as_ref() {
                pass.set_bind_group(0, group, &[]);
            }
            if let Some(group) = writable_group.as_ref() {
                pass.set_bind_group(1, group, &[]);
            }
            if let Some(group) = uniform_group.as_ref() {
                pass.set_bind_group(2, group, &[]);
            }
            pass.dispatch_workgroups(groups[0], groups[1], groups[2]);
        }
        self.queue.submit([encoder.finish()]);
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
        let assigned: Vec<BufferSlot> = slots
            .iter()
            .enumerate()
            .map(|(slot, value)| {
                value.ok_or(GpuError::MissingBinding {
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

    pub fn queue_download(
        &mut self,
        handle: BufferHandle,
        offset: u64,
        size: u64,
    ) -> Result<(), GpuError> {
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
        self.resources.buffer_mut(handle)?.download = Some(Download::Pending { staging, offset });
        self.pending_downloads.push(handle);
        Ok(())
    }

    pub fn synchronize(&mut self) -> Result<(), GpuError> {
        self.poll_wait()?;
        while let Some(handle) = self.pending_downloads.first().copied() {
            let (staging, offset) = match self.resources.buffer(handle)?.download.as_ref() {
                Some(Download::Pending { staging, offset }) => (staging.clone(), *offset),
                _ => {
                    return Err(GpuError::Internal(
                        "pending download queue disagrees with buffer",
                    ));
                }
            };
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
            self.resources.buffer_mut(handle)?.download = Some(Download::Ready { offset, bytes });
            self.pending_downloads.remove(0);
        }
        let errors = self.take_device_errors();
        if errors.is_empty() {
            Ok(())
        } else {
            Err(GpuError::Device(errors))
        }
    }

    pub fn read_download(
        &mut self,
        handle: BufferHandle,
        offset: u64,
        size: u64,
    ) -> Result<Vec<u8>, GpuError> {
        let entry = self.resources.buffer_mut(handle)?;
        let (ready_offset, bytes) = match entry.download.take() {
            Some(Download::Ready { offset, bytes }) => (offset, bytes),
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
            });
            return Err(GpuError::DownloadMismatch {
                expected_offset: ready_offset,
                expected_size,
                requested_offset: offset,
                requested_size: size,
            });
        }
        Ok(bytes)
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
        let mut gpu = match GpuContext::new() {
            Ok(gpu) => gpu,
            Err(error) => {
                assert!(!required, "required GPU adapter is unavailable: {error}");
                eprintln!("GPU adapter test skipped: {error}");
                return;
            }
        };
        let kernel = match gpu.create_test_kernel() {
            Ok(kernel) => kernel,
            Err(error) => {
                assert!(!required, "required GPU test kernel failed: {error}");
                eprintln!("GPU adapter test skipped: {error}");
                return;
            }
        };
        let buffer = gpu.create_buffer(16).unwrap();
        gpu.upload(buffer, 0, &[1, 0, 0, 0, 2, 0, 0, 0, 3, 0, 0, 0, 4, 0, 0, 0])
            .unwrap();
        let bindings = gpu.create_bindings(kernel).unwrap();
        gpu.set_write_buffer(bindings, 0, buffer, 0, 16).unwrap();
        gpu.dispatch(bindings, [4, 1, 1], &[]).unwrap();
        gpu.queue_download(buffer, 0, 16).unwrap();
        gpu.synchronize().unwrap();
        assert_eq!(
            gpu.read_download(buffer, 0, 16).unwrap(),
            [2, 0, 0, 0, 3, 0, 0, 0, 4, 0, 0, 0, 5, 0, 0, 0]
        );
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
            })
        }
    }
}
