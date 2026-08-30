/* SDL GPU command recording for Nupp's explicit resident-buffer API. */

#include "nupp_native.h"

#include <SDL3/SDL.h>

#include <stdlib.h>
#include <string.h>

#define NUPP_GPU_MAX_BINDINGS 16u
#define NUPP_GPU_MAX_UNIFORMS 128u

typedef struct NuppGpuContext NuppGpuContext;
typedef struct NuppGpuBuffer NuppGpuBuffer;
typedef struct NuppGpuKernel NuppGpuKernel;
typedef struct NuppGpuBinding NuppGpuBinding;

struct NuppGpuBuffer {
    NuppGpuContext *context;
    SDL_GPUBuffer *storage;
    SDL_GPUTransferBuffer *upload;
    SDL_GPUTransferBuffer *download;
    uint32_t size;
    bool upload_queued;
    bool download_queued;
    bool download_ready;
    uint32_t downloaded_offset;
    uint32_t downloaded_size;
    NuppGpuBuffer *next;
};

struct NuppGpuKernel {
    NuppGpuContext *context;
    SDL_GPUComputePipeline *pipeline;
    uint32_t readonly_count;
    uint32_t writable_count;
    uint32_t uniform_size;
    uint32_t threads;
    NuppGpuKernel *next;
};

/* One kernel attached to its buffers. The uniform block layout is the
 * compiler's: word zero is the dispatch count, the next words carry each
 * bound span's element count in slot order (read-only spans first), then one
 * element offset per span, and the authored scalar uniforms follow. Dispatch
 * patches those leading words from what was bound, so views remain allocation
 * free and shader bounds checks compare against the counts the host validated. */
struct NuppGpuBinding {
    NuppGpuContext *context;
    NuppGpuKernel *kernel;
    NuppGpuBuffer *readable[NUPP_GPU_MAX_BINDINGS];
    NuppGpuBuffer *writable[NUPP_GPU_MAX_BINDINGS];
    uint32_t span_counts[2u * NUPP_GPU_MAX_BINDINGS];
    uint32_t span_offsets[2u * NUPP_GPU_MAX_BINDINGS];
    uint32_t count;
    NuppGpuBinding *next;
};

struct NuppGpuContext {
    SDL_GPUDevice *device;
    SDL_GPUCommandBuffer *commands;
    NuppGpuBuffer *buffers;
    NuppGpuKernel *kernels;
    NuppGpuBinding *bindings;
    bool started_video;
};

static bool gpu_fail(const char *operation) {
    nupp_fail_format("gpu: %s: %s", operation, SDL_GetError());
    return false;
}

static bool owns_buffer(NuppGpuContext *context, NuppGpuBuffer *buffer) {
    if (context == NULL || buffer == NULL || buffer->context != context) {
        nupp_fail("gpu: buffer belongs to another or closed context");
        return false;
    }
    return true;
}

static void reset_queued(NuppGpuContext *context, bool completed) {
    NuppGpuBuffer *buffer;
    for (buffer = context->buffers; buffer != NULL; buffer = buffer->next) {
        buffer->upload_queued = false;
        if (buffer->download_queued) {
            buffer->download_queued = false;
            buffer->download_ready = completed;
        }
    }
}

static void cancel_commands(NuppGpuContext *context) {
    if (context->commands != NULL) {
        SDL_CancelGPUCommandBuffer(context->commands);
        context->commands = NULL;
    }
    reset_queued(context, false);
}

static SDL_GPUCommandBuffer *commands(NuppGpuContext *context) {
    if (context == NULL || context->device == NULL) {
        nupp_fail("gpu: context is closed");
        return NULL;
    }
    if (context->commands == NULL) {
        context->commands = SDL_AcquireGPUCommandBuffer(context->device);
        if (context->commands == NULL) {
            gpu_fail("acquire command buffer");
        }
    }
    return context->commands;
}

NUPP_EXPORT NuppGpuContext *nuppGpuContextCreate(void) {
    NuppGpuContext *context = calloc(1, sizeof *context);
    if (context == NULL) {
        nupp_fail("gpu: out of memory");
        return NULL;
    }
    context->started_video = SDL_WasInit(SDL_INIT_VIDEO) == 0;
    if (!SDL_InitSubSystem(SDL_INIT_VIDEO)) {
        gpu_fail("initialize SDL video");
        free(context);
        return NULL;
    }
    context->device = SDL_CreateGPUDevice(
        SDL_GPU_SHADERFORMAT_SPIRV | SDL_GPU_SHADERFORMAT_MSL, false, NULL);
    if (context->device == NULL) {
        gpu_fail("create device");
        if (context->started_video) {
            SDL_QuitSubSystem(SDL_INIT_VIDEO);
        }
        free(context);
        return NULL;
    }
    return context;
}

NUPP_EXPORT const char *nuppGpuContextDriver(const NuppGpuContext *context) {
    if (context == NULL || context->device == NULL) {
        return "closed";
    }
    return SDL_GetGPUDeviceDriver(context->device);
}

NUPP_EXPORT void nuppGpuContextDestroy(NuppGpuContext *context) {
    NuppGpuKernel *kernel;
    NuppGpuBuffer *buffer;
    NuppGpuBinding *binding;
    if (context == NULL) {
        return;
    }
    cancel_commands(context);
    while ((binding = context->bindings) != NULL) {
        context->bindings = binding->next;
        free(binding);
    }
    while ((kernel = context->kernels) != NULL) {
        context->kernels = kernel->next;
        SDL_ReleaseGPUComputePipeline(context->device, kernel->pipeline);
        free(kernel);
    }
    while ((buffer = context->buffers) != NULL) {
        context->buffers = buffer->next;
        if (buffer->download != NULL) {
            SDL_ReleaseGPUTransferBuffer(context->device, buffer->download);
        }
        if (buffer->upload != NULL) {
            SDL_ReleaseGPUTransferBuffer(context->device, buffer->upload);
        }
        if (buffer->storage != NULL) {
            SDL_ReleaseGPUBuffer(context->device, buffer->storage);
        }
        free(buffer);
    }
    if (context->device != NULL) {
        SDL_DestroyGPUDevice(context->device);
    }
    if (context->started_video) {
        SDL_QuitSubSystem(SDL_INIT_VIDEO);
    }
    free(context);
}

NUPP_EXPORT NuppGpuBuffer *nuppGpuBufferCreate(
    NuppGpuContext *context, size_t size
) {
    NuppGpuBuffer *buffer;
    SDL_GPUBufferCreateInfo storage_info;
    if (context == NULL || context->device == NULL || size == 0 || size > UINT32_MAX) {
        nupp_fail("gpu: buffer size must be from 1 through 4294967295 bytes");
        return NULL;
    }
    buffer = calloc(1, sizeof *buffer);
    if (buffer == NULL) {
        nupp_fail("gpu: out of memory");
        return NULL;
    }
    SDL_zero(storage_info);
    storage_info.usage = SDL_GPU_BUFFERUSAGE_COMPUTE_STORAGE_READ
        | SDL_GPU_BUFFERUSAGE_COMPUTE_STORAGE_WRITE;
    storage_info.size = (uint32_t)size;
    buffer->storage = SDL_CreateGPUBuffer(context->device, &storage_info);
    if (buffer->storage == NULL) {
        gpu_fail("create resident buffer");
        free(buffer);
        return NULL;
    }
    buffer->context = context;
    buffer->size = (uint32_t)size;
    buffer->next = context->buffers;
    context->buffers = buffer;
    return buffer;
}

NUPP_EXPORT NuppGpuKernel *nuppGpuKernelCreate(
    NuppGpuContext *context,
    const uint8_t *spirv,
    size_t spirv_length,
    const uint8_t *msl,
    size_t msl_length,
    const uint8_t *entrypoint_data,
    size_t entrypoint_length,
    uint32_t readonly_count,
    uint32_t writable_count,
    uint32_t uniform_size,
    uint32_t threads
) {
    NuppGpuKernel *kernel;
    NuppText entrypoint;
    SDL_GPUComputePipelineCreateInfo info;
    SDL_GPUShaderFormat formats;
    SDL_GPUShaderFormat format;
    const uint8_t *code;
    size_t code_length;
    uint8_t *terminated;
    if (context == NULL || context->device == NULL
        || spirv == NULL || spirv_length == 0 || spirv_length % 4 != 0
        || msl == NULL || msl_length == 0) {
        nupp_fail("gpu: kernel needs canonical SPIR-V and derived MSL");
        return NULL;
    }
    if (readonly_count > NUPP_GPU_MAX_BINDINGS
        || writable_count > NUPP_GPU_MAX_BINDINGS
        || uniform_size > NUPP_GPU_MAX_UNIFORMS
        || threads == 0) {
        nupp_fail("gpu: invalid kernel binding, uniform, or thread count");
        return NULL;
    }
    if (!nupp_text(&entrypoint, entrypoint_data, entrypoint_length, "GPU entrypoint")) {
        return NULL;
    }
    formats = SDL_GetGPUShaderFormats(context->device);
    if ((formats & SDL_GPU_SHADERFORMAT_SPIRV) != 0) {
        format = SDL_GPU_SHADERFORMAT_SPIRV;
        code = spirv;
        code_length = spirv_length;
        terminated = NULL;
    } else if ((formats & SDL_GPU_SHADERFORMAT_MSL) != 0) {
        format = SDL_GPU_SHADERFORMAT_MSL;
        code_length = msl_length + 1;
        terminated = malloc(code_length);
        if (terminated != NULL) {
            memcpy(terminated, msl, msl_length);
            terminated[msl_length] = 0;
        }
        code = terminated;
    } else {
        nupp_fail("gpu: device accepts neither SPIR-V nor MSL");
        nupp_text_free(&entrypoint);
        return NULL;
    }
    kernel = calloc(1, sizeof *kernel);
    if (code == NULL || kernel == NULL) {
        nupp_fail("gpu: out of memory");
        free(terminated);
        free(kernel);
        nupp_text_free(&entrypoint);
        return NULL;
    }
    SDL_zero(info);
    info.code_size = code_length;
    info.code = code;
    info.entrypoint = entrypoint.value;
    info.format = format;
    info.num_readonly_storage_buffers = readonly_count;
    info.num_readwrite_storage_buffers = writable_count;
    info.num_uniform_buffers = uniform_size == 0 ? 0 : 1;
    info.threadcount_x = threads;
    info.threadcount_y = 1;
    info.threadcount_z = 1;
    kernel->pipeline = SDL_CreateGPUComputePipeline(context->device, &info);
    free(terminated);
    nupp_text_free(&entrypoint);
    if (kernel->pipeline == NULL) {
        gpu_fail("compile compute kernel");
        free(kernel);
        return NULL;
    }
    kernel->context = context;
    kernel->readonly_count = readonly_count;
    kernel->writable_count = writable_count;
    kernel->uniform_size = uniform_size;
    kernel->threads = threads;
    kernel->next = context->kernels;
    context->kernels = kernel;
    return kernel;
}

NUPP_EXPORT bool nuppGpuBufferUpload(
    NuppGpuContext *context, NuppGpuBuffer *buffer, const void *source,
    size_t offset, size_t size
) {
    SDL_GPUCommandBuffer *command_buffer;
    SDL_GPUCopyPass *copy;
    SDL_GPUTransferBufferLocation from;
    SDL_GPUBufferRegion to;
    SDL_GPUTransferBufferCreateInfo upload_info;
    void *mapped;
    if (!owns_buffer(context, buffer) || source == NULL
        || offset > buffer->size || size > buffer->size - offset) {
        if (source == NULL || buffer != NULL) {
            nupp_fail("gpu: upload range is outside the resident buffer");
        }
        return false;
    }
    if (buffer->upload == NULL) {
        SDL_zero(upload_info);
        upload_info.usage = SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD;
        upload_info.size = buffer->size;
        buffer->upload = SDL_CreateGPUTransferBuffer(context->device, &upload_info);
        if (buffer->upload == NULL) {
            return gpu_fail("create upload buffer");
        }
    }
    mapped = SDL_MapGPUTransferBuffer(context->device, buffer->upload, buffer->upload_queued);
    if (mapped == NULL) {
        return gpu_fail("map upload buffer");
    }
    memcpy((uint8_t *)mapped + offset, source, size);
    SDL_UnmapGPUTransferBuffer(context->device, buffer->upload);
    command_buffer = commands(context);
    if (command_buffer == NULL) {
        return false;
    }
    SDL_zero(from);
    from.transfer_buffer = buffer->upload;
    from.offset = (uint32_t)offset;
    SDL_zero(to);
    to.buffer = buffer->storage;
    to.offset = (uint32_t)offset;
    to.size = (uint32_t)size;
    copy = SDL_BeginGPUCopyPass(command_buffer);
    if (copy == NULL) {
        gpu_fail("begin upload pass");
        cancel_commands(context);
        return false;
    }
    SDL_UploadToGPUBuffer(copy, &from, &to, false);
    SDL_EndGPUCopyPass(copy);
    buffer->upload_queued = true;
    return true;
}

NUPP_EXPORT NuppGpuBinding *nuppGpuBindingCreate(
    NuppGpuContext *context, NuppGpuKernel *kernel, uint32_t count
) {
    NuppGpuBinding *binding;
    if (context == NULL || context->device == NULL || kernel == NULL || kernel->context != context) {
        nupp_fail("gpu: binding needs a kernel from its own open context");
        return NULL;
    }
    binding = calloc(1, sizeof *binding);
    if (binding == NULL) {
        nupp_fail("gpu: out of memory");
        return NULL;
    }
    binding->context = context;
    binding->kernel = kernel;
    binding->count = count;
    binding->next = context->bindings;
    context->bindings = binding;
    return binding;
}

static bool binding_slot(
    NuppGpuBinding *binding,
    uint32_t slot,
    uint32_t limit,
    NuppGpuBuffer *buffer,
    uint32_t element_offset,
    uint32_t element_count,
    bool match_count
) {
    (void)element_offset;
    if (binding == NULL || binding->context == NULL || binding->context->device == NULL) {
        nupp_fail("gpu: binding belongs to a closed context");
        return false;
    }
    if (slot >= limit) {
        nupp_fail("gpu: binding slot is outside the compiled kernel");
        return false;
    }
    if (!owns_buffer(binding->context, buffer)) {
        return false;
    }
    if (match_count && element_count != binding->count) {
        nupp_fail("gpu: a dispatch-indexed buffer must hold one element per dispatched thread");
        return false;
    }
    return true;
}

NUPP_EXPORT bool nuppGpuBindingSetRead(
    NuppGpuBinding *binding,
    uint32_t slot,
    NuppGpuBuffer *buffer,
    uint32_t element_offset,
    uint32_t element_count,
    bool match_count
) {
    if (!binding_slot(binding, slot, binding == NULL ? 0 : binding->kernel->readonly_count,
                      buffer, element_offset, element_count, match_count)) {
        return false;
    }
    binding->readable[slot] = buffer;
    binding->span_counts[slot] = element_count;
    binding->span_offsets[slot] = element_offset;
    return true;
}

NUPP_EXPORT bool nuppGpuBindingSetWrite(
    NuppGpuBinding *binding,
    uint32_t slot,
    NuppGpuBuffer *buffer,
    uint32_t element_offset,
    uint32_t element_count,
    bool match_count
) {
    if (!binding_slot(binding, slot, binding == NULL ? 0 : binding->kernel->writable_count,
                      buffer, element_offset, element_count, match_count)) {
        return false;
    }
    binding->writable[slot] = buffer;
    binding->span_counts[binding->kernel->readonly_count + slot] = element_count;
    binding->span_offsets[binding->kernel->readonly_count + slot] = element_offset;
    return true;
}

NUPP_EXPORT bool nuppGpuBindingDispatch(
    NuppGpuBinding *binding, const void *uniforms, size_t uniform_size
) {
    NuppGpuContext *context;
    NuppGpuKernel *kernel;
    SDL_GPUCommandBuffer *command_buffer;
    SDL_GPUComputePass *compute;
    SDL_GPUStorageBufferReadWriteBinding writable_bindings[NUPP_GPU_MAX_BINDINGS];
    SDL_GPUBuffer *readable_storage[NUPP_GPU_MAX_BINDINGS];
    uint8_t patched[NUPP_GPU_MAX_UNIFORMS];
    uint32_t spans;
    uint32_t at;
    if (binding == NULL || binding->context == NULL || binding->context->device == NULL) {
        nupp_fail("gpu: binding belongs to a closed context");
        return false;
    }
    context = binding->context;
    kernel = binding->kernel;
    spans = kernel->readonly_count + kernel->writable_count;
    if (uniform_size != kernel->uniform_size
        || uniform_size < sizeof(uint32_t) * (1u + 2u * spans)
        || uniforms == NULL) {
        nupp_fail("gpu: dispatch uniforms do not match the compiled kernel");
        return false;
    }
    for (at = 0; at < kernel->readonly_count; at += 1) {
        if (binding->readable[at] == NULL) {
            nupp_fail("gpu: binding is missing a read buffer");
            return false;
        }
    }
    for (at = 0; at < kernel->writable_count; at += 1) {
        if (binding->writable[at] == NULL) {
            nupp_fail("gpu: binding is missing a write buffer");
            return false;
        }
    }
    if (binding->count == 0) {
        return true;
    }
    command_buffer = commands(context);
    if (command_buffer == NULL) {
        return false;
    }
    memcpy(patched, uniforms, uniform_size);
    memcpy(patched, &binding->count, sizeof binding->count);
    memcpy(patched + sizeof(uint32_t), binding->span_counts, sizeof(uint32_t) * spans);
    memcpy(patched + sizeof(uint32_t) * (1u + spans),
           binding->span_offsets, sizeof(uint32_t) * spans);
    SDL_PushGPUComputeUniformData(command_buffer, 0, patched, (uint32_t)uniform_size);
    for (at = 0; at < kernel->writable_count; at += 1) {
        SDL_zero(writable_bindings[at]);
        writable_bindings[at].buffer = binding->writable[at]->storage;
    }
    compute = SDL_BeginGPUComputePass(
        command_buffer, NULL, 0, writable_bindings, kernel->writable_count);
    if (compute == NULL) {
        gpu_fail("begin compute pass");
        cancel_commands(context);
        return false;
    }
    SDL_BindGPUComputePipeline(compute, kernel->pipeline);
    if (kernel->readonly_count != 0) {
        for (at = 0; at < kernel->readonly_count; at += 1) {
            readable_storage[at] = binding->readable[at]->storage;
        }
        SDL_BindGPUComputeStorageBuffers(compute, 0, readable_storage, kernel->readonly_count);
    }
    SDL_DispatchGPUCompute(
        compute, (binding->count + kernel->threads - 1) / kernel->threads, 1, 1);
    SDL_EndGPUComputePass(compute);
    return true;
}

NUPP_EXPORT bool nuppGpuBufferDownload(
    NuppGpuContext *context, NuppGpuBuffer *buffer, size_t offset, size_t size
) {
    SDL_GPUCommandBuffer *command_buffer;
    SDL_GPUCopyPass *copy;
    SDL_GPUBufferRegion from;
    SDL_GPUTransferBufferLocation to;
    SDL_GPUTransferBufferCreateInfo download_info;
    if (!owns_buffer(context, buffer)
        || offset > buffer->size || size > buffer->size - offset) {
        if (buffer != NULL) {
            nupp_fail("gpu: download range is outside the resident buffer");
        }
        return false;
    }
    if (buffer->download_queued) {
        nupp_fail("gpu: buffer already has a download queued");
        return false;
    }
    if (buffer->download == NULL) {
        SDL_zero(download_info);
        download_info.usage = SDL_GPU_TRANSFERBUFFERUSAGE_DOWNLOAD;
        download_info.size = buffer->size;
        buffer->download = SDL_CreateGPUTransferBuffer(context->device, &download_info);
        if (buffer->download == NULL) {
            return gpu_fail("create download buffer");
        }
    }
    command_buffer = commands(context);
    if (command_buffer == NULL) {
        return false;
    }
    SDL_zero(from);
    from.buffer = buffer->storage;
    from.offset = (uint32_t)offset;
    from.size = (uint32_t)size;
    SDL_zero(to);
    to.transfer_buffer = buffer->download;
    to.offset = (uint32_t)offset;
    copy = SDL_BeginGPUCopyPass(command_buffer);
    if (copy == NULL) {
        gpu_fail("begin download pass");
        cancel_commands(context);
        return false;
    }
    SDL_DownloadFromGPUBuffer(copy, &from, &to);
    SDL_EndGPUCopyPass(copy);
    buffer->download_queued = true;
    buffer->download_ready = false;
    buffer->downloaded_offset = (uint32_t)offset;
    buffer->downloaded_size = (uint32_t)size;
    return true;
}

NUPP_EXPORT bool nuppGpuSynchronize(NuppGpuContext *context) {
    SDL_GPUFence *fence;
    if (context == NULL || context->device == NULL) {
        nupp_fail("gpu: context is closed");
        return false;
    }
    if (context->commands == NULL) {
        return true;
    }
    fence = SDL_SubmitGPUCommandBufferAndAcquireFence(context->commands);
    context->commands = NULL;
    if (fence == NULL) {
        reset_queued(context, false);
        return gpu_fail("submit commands");
    }
    if (!SDL_WaitForGPUFences(context->device, true, &fence, 1)) {
        SDL_ReleaseGPUFence(context->device, fence);
        reset_queued(context, false);
        return gpu_fail("wait for commands");
    }
    SDL_ReleaseGPUFence(context->device, fence);
    reset_queued(context, true);
    return true;
}

NUPP_EXPORT bool nuppGpuBufferRead(
    NuppGpuContext *context, NuppGpuBuffer *buffer, void *destination,
    size_t offset, size_t size
) {
    void *mapped;
    if (!owns_buffer(context, buffer) || destination == NULL
        || offset > buffer->size || size > buffer->size - offset) {
        if (destination == NULL || buffer != NULL) {
            nupp_fail("gpu: read range is outside the downloaded buffer");
        }
        return false;
    }
    if (!buffer->download_ready
        || offset != buffer->downloaded_offset || size != buffer->downloaded_size) {
        nupp_fail("gpu: buffer has no matching synchronized download");
        return false;
    }
    mapped = SDL_MapGPUTransferBuffer(context->device, buffer->download, false);
    if (mapped == NULL) {
        return gpu_fail("map download buffer");
    }
    memcpy(destination, (uint8_t *)mapped + offset, size);
    SDL_UnmapGPUTransferBuffer(context->device, buffer->download);
    return true;
}
