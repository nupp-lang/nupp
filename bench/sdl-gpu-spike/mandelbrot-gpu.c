#include <SDL3/SDL.h>

#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#if defined(_WIN32)
#define EXPORT __declspec(dllexport)
#else
#define EXPORT __attribute__((visibility("default")))
#endif

typedef struct {
    float re;
    float im;
} Point;

typedef struct {
    int32_t iterations;
    uint32_t escaped;
} Escape;

typedef struct {
    uint32_t count;
    int32_t max_iterations;
} Uniforms;

static SDL_GPUDevice *device;
static SDL_GPUComputePipeline *pipeline;
static SDL_GPUBuffer *points_buffer;
static SDL_GPUBuffer *escapes_buffer;
static SDL_GPUTransferBuffer *upload;
static SDL_GPUTransferBuffer *download;
static size_t capacity;
static uint32_t thread_count;
static bool started_video;
static char error_text[512];

static bool fail(const char *operation) {
    SDL_snprintf(error_text, sizeof error_text, "%s: %s", operation, SDL_GetError());
    return false;
}

EXPORT const char *ks_gpu_error(void) {
    return error_text;
}

EXPORT void ks_gpu_shutdown(void) {
    if (device != NULL) {
        if (download != NULL) SDL_ReleaseGPUTransferBuffer(device, download);
        if (upload != NULL) SDL_ReleaseGPUTransferBuffer(device, upload);
        if (escapes_buffer != NULL) SDL_ReleaseGPUBuffer(device, escapes_buffer);
        if (points_buffer != NULL) SDL_ReleaseGPUBuffer(device, points_buffer);
        if (pipeline != NULL) SDL_ReleaseGPUComputePipeline(device, pipeline);
        SDL_DestroyGPUDevice(device);
    }
    if (started_video) SDL_QuitSubSystem(SDL_INIT_VIDEO);
    device = NULL;
    pipeline = NULL;
    points_buffer = NULL;
    escapes_buffer = NULL;
    upload = NULL;
    download = NULL;
    capacity = 0;
    thread_count = 0;
    started_video = false;
}

EXPORT bool ks_gpu_init(const char *shader_path, size_t count, uint32_t threads) {
    SDL_GPUComputePipelineCreateInfo pipeline_info;
    SDL_GPUBufferCreateInfo points_info;
    SDL_GPUBufferCreateInfo escapes_info;
    SDL_GPUTransferBufferCreateInfo upload_info;
    SDL_GPUTransferBufferCreateInfo download_info;
    size_t shader_length;
    void *shader;

    error_text[0] = '\0';
    if (device != NULL) {
        SDL_strlcpy(error_text, "GPU benchmark is already initialized", sizeof error_text);
        return false;
    }
    if (count == 0 || count > UINT32_MAX / sizeof(Point) || threads == 0) {
        SDL_strlcpy(error_text, "invalid GPU benchmark dimensions", sizeof error_text);
        return false;
    }
    started_video = SDL_WasInit(SDL_INIT_VIDEO) == 0;
    if (!SDL_InitSubSystem(SDL_INIT_VIDEO)) return fail("initialize SDL video");
    shader = SDL_LoadFile(shader_path, &shader_length);
    if (shader == NULL) {
        fail("load generated shader");
        ks_gpu_shutdown();
        return false;
    }
    device = SDL_CreateGPUDevice(SDL_GPU_SHADERFORMAT_MSL, false, "metal");
    if (device == NULL) {
        fail("create Metal GPU device");
        SDL_free(shader);
        ks_gpu_shutdown();
        return false;
    }

    SDL_zero(pipeline_info);
    pipeline_info.code_size = shader_length + 1;
    pipeline_info.code = shader;
    pipeline_info.entrypoint = "ks_mandelbrot_gpu";
    pipeline_info.format = SDL_GPU_SHADERFORMAT_MSL;
    pipeline_info.num_readonly_storage_buffers = 1;
    pipeline_info.num_readwrite_storage_buffers = 1;
    pipeline_info.num_uniform_buffers = 1;
    pipeline_info.threadcount_x = threads;
    pipeline_info.threadcount_y = 1;
    pipeline_info.threadcount_z = 1;
    pipeline = SDL_CreateGPUComputePipeline(device, &pipeline_info);
    SDL_free(shader);
    if (pipeline == NULL) {
        fail("compile generated Mandelbrot shader");
        ks_gpu_shutdown();
        return false;
    }

    SDL_zero(points_info);
    points_info.usage = SDL_GPU_BUFFERUSAGE_COMPUTE_STORAGE_READ;
    points_info.size = (uint32_t)(count * sizeof(Point));
    SDL_zero(escapes_info);
    escapes_info.usage = SDL_GPU_BUFFERUSAGE_COMPUTE_STORAGE_WRITE;
    escapes_info.size = (uint32_t)(count * sizeof(Escape));
    SDL_zero(upload_info);
    upload_info.usage = SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD;
    upload_info.size = points_info.size;
    SDL_zero(download_info);
    download_info.usage = SDL_GPU_TRANSFERBUFFERUSAGE_DOWNLOAD;
    download_info.size = escapes_info.size;
    points_buffer = SDL_CreateGPUBuffer(device, &points_info);
    escapes_buffer = SDL_CreateGPUBuffer(device, &escapes_info);
    upload = SDL_CreateGPUTransferBuffer(device, &upload_info);
    download = SDL_CreateGPUTransferBuffer(device, &download_info);
    if (points_buffer == NULL || escapes_buffer == NULL || upload == NULL || download == NULL) {
        fail("allocate Mandelbrot GPU buffers");
        ks_gpu_shutdown();
        return false;
    }
    capacity = count;
    thread_count = threads;
    return true;
}

static bool record_compute(
    SDL_GPUCommandBuffer *commands, int32_t max_iterations, size_t count
) {
    SDL_GPUComputePass *compute;
    SDL_GPUStorageBufferReadWriteBinding writable;
    SDL_GPUBuffer *readable[] = {points_buffer};
    Uniforms uniforms = {(uint32_t)count, max_iterations};

    SDL_PushGPUComputeUniformData(commands, 0, &uniforms, sizeof uniforms);
    SDL_zero(writable);
    writable.buffer = escapes_buffer;
    compute = SDL_BeginGPUComputePass(commands, NULL, 0, &writable, 1);
    if (compute == NULL) return fail("begin Mandelbrot compute pass");
    SDL_BindGPUComputePipeline(compute, pipeline);
    SDL_BindGPUComputeStorageBuffers(compute, 0, readable, 1);
    SDL_DispatchGPUCompute(
        compute, ((uint32_t)count + thread_count - 1) / thread_count, 1, 1
    );
    SDL_EndGPUComputePass(compute);
    return true;
}

static bool submit_and_wait(SDL_GPUCommandBuffer *commands) {
    SDL_GPUFence *fence = SDL_SubmitGPUCommandBufferAndAcquireFence(commands);
    if (fence == NULL) return fail("submit Mandelbrot GPU dispatch");
    if (!SDL_WaitForGPUFences(device, true, &fence, 1)) {
        SDL_ReleaseGPUFence(device, fence);
        return fail("wait for Mandelbrot GPU dispatch");
    }
    SDL_ReleaseGPUFence(device, fence);
    return true;
}

EXPORT bool ks_gpu_mandelbrot_resident(int32_t max_iterations, size_t count) {
    SDL_GPUCommandBuffer *commands;

    if (device == NULL || count > capacity) {
        SDL_strlcpy(error_text, "GPU benchmark is not initialized for this span", sizeof error_text);
        return false;
    }
    commands = SDL_AcquireGPUCommandBuffer(device);
    if (commands == NULL) return fail("acquire resident GPU command buffer");
    if (!record_compute(commands, max_iterations, count)) {
        SDL_CancelGPUCommandBuffer(commands);
        return false;
    }
    return submit_and_wait(commands);
}

EXPORT bool ks_gpu_mandelbrot_staged(int32_t max_iterations, size_t count) {
    SDL_GPUCommandBuffer *commands;
    SDL_GPUCopyPass *copy;
    SDL_GPUTransferBufferLocation transfer_location;
    SDL_GPUBufferRegion buffer_region;
    uint32_t point_bytes;
    uint32_t escape_bytes;

    if (device == NULL || count > capacity) {
        SDL_strlcpy(error_text, "GPU benchmark is not initialized for this span", sizeof error_text);
        return false;
    }
    point_bytes = (uint32_t)(count * sizeof(Point));
    escape_bytes = (uint32_t)(count * sizeof(Escape));
    commands = SDL_AcquireGPUCommandBuffer(device);
    if (commands == NULL) return fail("acquire staged GPU command buffer");

    SDL_zero(transfer_location);
    transfer_location.transfer_buffer = upload;
    SDL_zero(buffer_region);
    buffer_region.buffer = points_buffer;
    buffer_region.size = point_bytes;
    copy = SDL_BeginGPUCopyPass(commands);
    if (copy == NULL) {
        SDL_CancelGPUCommandBuffer(commands);
        return fail("begin staged point upload");
    }
    SDL_UploadToGPUBuffer(copy, &transfer_location, &buffer_region, false);
    SDL_EndGPUCopyPass(copy);

    if (!record_compute(commands, max_iterations, count)) {
        SDL_CancelGPUCommandBuffer(commands);
        return false;
    }

    SDL_zero(buffer_region);
    buffer_region.buffer = escapes_buffer;
    buffer_region.size = escape_bytes;
    SDL_zero(transfer_location);
    transfer_location.transfer_buffer = download;
    copy = SDL_BeginGPUCopyPass(commands);
    if (copy == NULL) {
        SDL_CancelGPUCommandBuffer(commands);
        return fail("begin staged escape download");
    }
    SDL_DownloadFromGPUBuffer(copy, &buffer_region, &transfer_location);
    SDL_EndGPUCopyPass(copy);
    return submit_and_wait(commands);
}

EXPORT bool ks_gpu_mandelbrot(
    Escape *escapes,
    const Point *points,
    double first,
    double last,
    int32_t max_iterations,
    size_t count
) {
    void *mapped;
    uint32_t point_bytes;
    uint32_t escape_bytes;

    if (device == NULL || count > capacity || first != 1.0 || last != (double)count) {
        SDL_strlcpy(error_text, "GPU benchmark requires one initialized whole-span call", sizeof error_text);
        return false;
    }
    point_bytes = (uint32_t)(count * sizeof(Point));
    escape_bytes = (uint32_t)(count * sizeof(Escape));
    mapped = SDL_MapGPUTransferBuffer(device, upload, false);
    if (mapped == NULL) return fail("map point upload");
    memcpy(mapped, points, point_bytes);
    SDL_UnmapGPUTransferBuffer(device, upload);
    if (!ks_gpu_mandelbrot_staged(max_iterations, count)) return false;

    mapped = SDL_MapGPUTransferBuffer(device, download, false);
    if (mapped == NULL) return fail("map escape download");
    memcpy(escapes, mapped, escape_bytes);
    SDL_UnmapGPUTransferBuffer(device, download);
    return true;
}
