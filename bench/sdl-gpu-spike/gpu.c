#include <SDL3/SDL.h>

#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#define THREADS 64u
#define MAX_COUNT 4194304u
#define GPU_REPEATS 20

static const char light_shader[] =
    "#include <metal_stdlib>\n"
    "using namespace metal;\n"
    "kernel void light(device const float *input [[buffer(0)]], "
    "device float *output [[buffer(1)]], "
    "uint index [[thread_position_in_grid]]) "
    "{ output[index] = input[index] * 1.25f + 0.5f; }\n";

static const char heavy_shader[] =
    "#include <metal_stdlib>\n"
    "using namespace metal;\n"
    "kernel void heavy(device const float *input [[buffer(0)]], "
    "device float *output [[buffer(1)]], "
    "uint index [[thread_position_in_grid]]) { "
    "float value = input[index]; "
    "for (uint step = 0; step < 64; step++) "
    "value = value * 1.00001f + 0.00001f; "
    "output[index] = value; }\n";

typedef struct {
    SDL_GPUDevice *device;
    SDL_GPUComputePipeline *light;
    SDL_GPUComputePipeline *heavy;
    SDL_GPUBuffer *input;
    SDL_GPUBuffer *output;
    SDL_GPUTransferBuffer *upload;
    SDL_GPUTransferBuffer *download;
} Bench;

static void fail(const char *what) {
    fprintf(stderr, "%s: %s\n", what, SDL_GetError());
    exit(1);
}

static double elapsed(Uint64 started) {
    return (double)(SDL_GetPerformanceCounter() - started) * 1000.0
        / (double)SDL_GetPerformanceFrequency();
}

static SDL_GPUComputePipeline *make_pipeline(
    SDL_GPUDevice *device, const char *code, size_t length, const char *entrypoint
) {
    SDL_GPUComputePipelineCreateInfo info = {
        .code_size = length,
        .code = (const Uint8 *)code,
        .entrypoint = entrypoint,
        .format = SDL_GPU_SHADERFORMAT_MSL,
        .num_readonly_storage_buffers = 1,
        .num_readwrite_storage_buffers = 1,
        .threadcount_x = THREADS,
        .threadcount_y = 1,
        .threadcount_z = 1,
    };
    SDL_GPUComputePipeline *pipeline = SDL_CreateGPUComputePipeline(device, &info);
    if (!pipeline) fail("SDL_CreateGPUComputePipeline");
    return pipeline;
}

static Bench make_bench(void) {
    const Uint32 bytes = MAX_COUNT * (Uint32)sizeof(float);
    Bench bench = {0};
    SDL_GPUBufferCreateInfo input_info = {
        .usage = SDL_GPU_BUFFERUSAGE_COMPUTE_STORAGE_READ,
        .size = bytes,
    };
    SDL_GPUBufferCreateInfo output_info = {
        .usage = SDL_GPU_BUFFERUSAGE_COMPUTE_STORAGE_WRITE,
        .size = bytes,
    };
    SDL_GPUTransferBufferCreateInfo upload_info = {
        .usage = SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD,
        .size = bytes,
    };
    SDL_GPUTransferBufferCreateInfo download_info = {
        .usage = SDL_GPU_TRANSFERBUFFERUSAGE_DOWNLOAD,
        .size = bytes,
    };

    bench.device = SDL_CreateGPUDevice(SDL_GPU_SHADERFORMAT_MSL, false, "metal");
    if (!bench.device) fail("SDL_CreateGPUDevice");
    bench.light = make_pipeline(bench.device, light_shader, sizeof light_shader, "light");
    bench.heavy = make_pipeline(bench.device, heavy_shader, sizeof heavy_shader, "heavy");
    bench.input = SDL_CreateGPUBuffer(bench.device, &input_info);
    bench.output = SDL_CreateGPUBuffer(bench.device, &output_info);
    bench.upload = SDL_CreateGPUTransferBuffer(bench.device, &upload_info);
    bench.download = SDL_CreateGPUTransferBuffer(bench.device, &download_info);
    if (!bench.input || !bench.output || !bench.upload || !bench.download) {
        fail("create buffers");
    }
    return bench;
}

static void dispatch(Bench *bench, SDL_GPUComputePipeline *pipeline, Uint32 count) {
    Uint32 bytes = count * (Uint32)sizeof(float);
    SDL_GPUCommandBuffer *commands = SDL_AcquireGPUCommandBuffer(bench->device);
    SDL_GPUCopyPass *copy;
    SDL_GPUComputePass *compute;
    SDL_GPUFence *fence;
    SDL_GPUTransferBufferLocation upload_from = {
        .transfer_buffer = bench->upload, .offset = 0,
    };
    SDL_GPUBufferRegion upload_to = {
        .buffer = bench->input, .offset = 0, .size = bytes,
    };
    SDL_GPUStorageBufferReadWriteBinding writable = {
        .buffer = bench->output, .cycle = false,
    };
    SDL_GPUBuffer *readable[] = {bench->input};
    SDL_GPUBufferRegion download_from = {
        .buffer = bench->output, .offset = 0, .size = bytes,
    };
    SDL_GPUTransferBufferLocation download_to = {
        .transfer_buffer = bench->download, .offset = 0,
    };

    if (!commands) fail("acquire command buffer");
    copy = SDL_BeginGPUCopyPass(commands);
    if (!copy) fail("begin upload pass");
    SDL_UploadToGPUBuffer(copy, &upload_from, &upload_to, false);
    SDL_EndGPUCopyPass(copy);

    compute = SDL_BeginGPUComputePass(commands, NULL, 0, &writable, 1);
    if (!compute) fail("begin compute pass");
    SDL_BindGPUComputePipeline(compute, pipeline);
    SDL_BindGPUComputeStorageBuffers(compute, 0, readable, 1);
    SDL_DispatchGPUCompute(compute, count / THREADS, 1, 1);
    SDL_EndGPUComputePass(compute);

    copy = SDL_BeginGPUCopyPass(commands);
    if (!copy) fail("begin download pass");
    SDL_DownloadFromGPUBuffer(copy, &download_from, &download_to);
    SDL_EndGPUCopyPass(copy);
    fence = SDL_SubmitGPUCommandBufferAndAcquireFence(commands);
    if (!fence) fail("submit");
    if (!SDL_WaitForGPUFences(bench->device, true, &fence, 1)) fail("wait");
    SDL_ReleaseGPUFence(bench->device, fence);
}

__attribute__((noinline)) static void cpu_light(
    const float *input, float *output, Uint32 count
) {
    Uint32 index;
    for (index = 0; index < count; index++) {
        output[index] = input[index] * 1.25f + 0.5f;
    }
}

__attribute__((noinline)) static void cpu_heavy(
    const float *input, float *output, Uint32 count
) {
    Uint32 index;
    for (index = 0; index < count; index++) {
        float value = input[index];
        Uint32 step;
        for (step = 0; step < 64; step++) {
            value = value * 1.00001f + 0.00001f;
        }
        output[index] = value;
    }
}

static void measure(
    Bench *bench, const float *input, float *cpu_output, Uint32 count, bool heavy
) {
    SDL_GPUComputePipeline *pipeline = heavy ? bench->heavy : bench->light;
    void (*cpu)(const float *, float *, Uint32) = heavy ? cpu_heavy : cpu_light;
    volatile float observed = 0.0f;
    Uint64 started;
    double gpu_ms;
    double cpu_ms;
    int repeat;
    float *gpu_output;
    Uint32 index;

    dispatch(bench, pipeline, count);
    started = SDL_GetPerformanceCounter();
    for (repeat = 0; repeat < GPU_REPEATS; repeat++) {
        dispatch(bench, pipeline, count);
    }
    gpu_ms = elapsed(started) / GPU_REPEATS;

    started = SDL_GetPerformanceCounter();
    for (repeat = 0; repeat < GPU_REPEATS; repeat++) {
        cpu(input, cpu_output, count);
        observed += cpu_output[(unsigned)repeat % count];
    }
    cpu_ms = elapsed(started) / GPU_REPEATS;

    gpu_output = SDL_MapGPUTransferBuffer(bench->device, bench->download, false);
    if (!gpu_output) fail("map download");
    for (index = 0; index < count; index++) {
        float tolerance = heavy ? 0.0002f * fmaxf(1.0f, fabsf(cpu_output[index])) : 0.0f;
        if (fabsf(gpu_output[index] - cpu_output[index]) > tolerance) {
            fprintf(stderr, "%s mismatch at %u: %.9g != %.9g\n",
                heavy ? "heavy" : "light", index, gpu_output[index], cpu_output[index]);
            exit(1);
        }
    }
    SDL_UnmapGPUTransferBuffer(bench->device, bench->download);
    printf("%-5s %8u values: CPU %8.3f ms  GPU %8.3f ms  GPU/CPU %6.2fx\n",
        heavy ? "heavy" : "light", count, cpu_ms, gpu_ms, gpu_ms / cpu_ms);
    if (observed == -1.0f) puts("unreachable");
}

static void destroy_bench(Bench *bench) {
    SDL_ReleaseGPUTransferBuffer(bench->device, bench->download);
    SDL_ReleaseGPUTransferBuffer(bench->device, bench->upload);
    SDL_ReleaseGPUBuffer(bench->device, bench->output);
    SDL_ReleaseGPUBuffer(bench->device, bench->input);
    SDL_ReleaseGPUComputePipeline(bench->device, bench->heavy);
    SDL_ReleaseGPUComputePipeline(bench->device, bench->light);
    SDL_DestroyGPUDevice(bench->device);
}

int main(void) {
    static const Uint32 counts[] = {1024, 16384, 262144, 1048576, 4194304};
    float *cpu_output;
    float *input;
    float *upload;
    Uint32 index;
    size_t count_index;
    Uint64 started;
    Bench bench;

    if (!SDL_Init(SDL_INIT_VIDEO)) fail("SDL_Init video");
    started = SDL_GetPerformanceCounter();
    bench = make_bench();
    printf("driver=%s, device and two source pipelines: %.3f ms\n",
        SDL_GetGPUDeviceDriver(bench.device), elapsed(started));

    input = malloc(MAX_COUNT * sizeof *input);
    cpu_output = malloc(MAX_COUNT * sizeof *cpu_output);
    if (!input || !cpu_output) fail("allocate CPU buffers");
    upload = SDL_MapGPUTransferBuffer(bench.device, bench.upload, false);
    if (!upload) fail("map upload");
    for (index = 0; index < MAX_COUNT; index++) {
        input[index] = (float)(index % 4096) * 0.000125f;
        upload[index] = input[index];
    }
    SDL_UnmapGPUTransferBuffer(bench.device, bench.upload);

    for (count_index = 0; count_index < sizeof counts / sizeof counts[0]; count_index++) {
        measure(&bench, input, cpu_output, counts[count_index], false);
    }
    for (count_index = 0; count_index < sizeof counts / sizeof counts[0]; count_index++) {
        measure(&bench, input, cpu_output, counts[count_index], true);
    }

    free(cpu_output);
    free(input);
    destroy_bench(&bench);
    SDL_Quit();
    return 0;
}
