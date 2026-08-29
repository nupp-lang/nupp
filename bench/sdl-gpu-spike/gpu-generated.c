#include <SDL3/SDL.h>

#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#define COUNT 1048576u
#define THREADS 64u

typedef struct {
    Uint32 count;
    Sint32 steps;
    float scale;
    float bias;
} NuppUniforms;

static void fail(const char *what) {
    fprintf(stderr, "%s: %s\n", what, SDL_GetError());
    exit(1);
}

int main(int argc, char **argv) {
    const Uint32 bytes = COUNT * (Uint32)sizeof(float);
    size_t shader_length;
    void *shader;
    SDL_GPUDevice *device;
    SDL_GPUComputePipeline *pipeline;
    SDL_GPUBuffer *input_buffer;
    SDL_GPUBuffer *output_buffer;
    SDL_GPUTransferBuffer *upload;
    SDL_GPUTransferBuffer *download;
    SDL_GPUCommandBuffer *commands;
    SDL_GPUCopyPass *copy;
    SDL_GPUComputePass *compute;
    SDL_GPUFence *fence;
    float *input;
    float *cpu;
    float *mapped;
    Uint32 index;
    NuppUniforms uniforms = {COUNT, 64, 1.00001f, 0.00001f};

    if (argc != 2) {
        fprintf(stderr, "usage: gpu-generated KERNEL.msl\n");
        return 2;
    }
    shader = SDL_LoadFile(argv[1], &shader_length);
    if (!shader) fail("load generated shader");
    if (!SDL_Init(SDL_INIT_VIDEO)) fail("SDL_Init video");
    device = SDL_CreateGPUDevice(SDL_GPU_SHADERFORMAT_MSL, false, "metal");
    if (!device) fail("SDL_CreateGPUDevice");

    SDL_GPUComputePipelineCreateInfo pipeline_info = {
        .code_size = shader_length + 1,
        .code = shader,
        .entrypoint = "ks_heavy_gpu",
        .format = SDL_GPU_SHADERFORMAT_MSL,
        .num_readonly_storage_buffers = 1,
        .num_readwrite_storage_buffers = 1,
        .num_uniform_buffers = 1,
        .threadcount_x = THREADS,
        .threadcount_y = 1,
        .threadcount_z = 1,
    };
    pipeline = SDL_CreateGPUComputePipeline(device, &pipeline_info);
    if (!pipeline) fail("compile verified-IR shader");

    SDL_GPUBufferCreateInfo input_info = {
        .usage = SDL_GPU_BUFFERUSAGE_COMPUTE_STORAGE_READ, .size = bytes,
    };
    SDL_GPUBufferCreateInfo output_info = {
        .usage = SDL_GPU_BUFFERUSAGE_COMPUTE_STORAGE_WRITE, .size = bytes,
    };
    SDL_GPUTransferBufferCreateInfo upload_info = {
        .usage = SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD, .size = bytes,
    };
    SDL_GPUTransferBufferCreateInfo download_info = {
        .usage = SDL_GPU_TRANSFERBUFFERUSAGE_DOWNLOAD, .size = bytes,
    };
    input_buffer = SDL_CreateGPUBuffer(device, &input_info);
    output_buffer = SDL_CreateGPUBuffer(device, &output_info);
    upload = SDL_CreateGPUTransferBuffer(device, &upload_info);
    download = SDL_CreateGPUTransferBuffer(device, &download_info);
    if (!input_buffer || !output_buffer || !upload || !download) fail("create buffers");

    input = malloc(bytes);
    cpu = malloc(bytes);
    if (!input || !cpu) fail("allocate CPU buffers");
    mapped = SDL_MapGPUTransferBuffer(device, upload, false);
    if (!mapped) fail("map upload");
    for (index = 0; index < COUNT; index++) {
        float value = (float)(index % 4096) * 0.000125f;
        input[index] = value;
        mapped[index] = value;
    }
    SDL_UnmapGPUTransferBuffer(device, upload);

    commands = SDL_AcquireGPUCommandBuffer(device);
    if (!commands) fail("acquire command buffer");
    SDL_GPUTransferBufferLocation upload_from = {.transfer_buffer = upload, .offset = 0};
    SDL_GPUBufferRegion upload_to = {.buffer = input_buffer, .offset = 0, .size = bytes};
    copy = SDL_BeginGPUCopyPass(commands);
    SDL_UploadToGPUBuffer(copy, &upload_from, &upload_to, false);
    SDL_EndGPUCopyPass(copy);

    SDL_PushGPUComputeUniformData(commands, 0, &uniforms, sizeof uniforms);
    SDL_GPUStorageBufferReadWriteBinding writable = {.buffer = output_buffer, .cycle = false};
    compute = SDL_BeginGPUComputePass(commands, NULL, 0, &writable, 1);
    SDL_BindGPUComputePipeline(compute, pipeline);
    SDL_GPUBuffer *readable[] = {input_buffer};
    SDL_BindGPUComputeStorageBuffers(compute, 0, readable, 1);
    SDL_DispatchGPUCompute(compute, (COUNT + THREADS - 1) / THREADS, 1, 1);
    SDL_EndGPUComputePass(compute);

    SDL_GPUBufferRegion download_from = {.buffer = output_buffer, .offset = 0, .size = bytes};
    SDL_GPUTransferBufferLocation download_to = {.transfer_buffer = download, .offset = 0};
    copy = SDL_BeginGPUCopyPass(commands);
    SDL_DownloadFromGPUBuffer(copy, &download_from, &download_to);
    SDL_EndGPUCopyPass(copy);
    fence = SDL_SubmitGPUCommandBufferAndAcquireFence(commands);
    if (!fence || !SDL_WaitForGPUFences(device, true, &fence, 1)) fail("wait for GPU");

    for (index = 0; index < COUNT; index++) {
        Sint32 step;
        float value = input[index];
        for (step = 0; step < uniforms.steps; step++) {
            value = value * uniforms.scale + uniforms.bias;
        }
        cpu[index] = value;
    }
    mapped = SDL_MapGPUTransferBuffer(device, download, false);
    if (!mapped) fail("map download");
    for (index = 0; index < COUNT; index++) {
        float tolerance = 0.0002f * fmaxf(1.0f, fabsf(cpu[index]));
        if (fabsf(mapped[index] - cpu[index]) > tolerance) {
            fprintf(stderr, "mismatch at %u: %.9g != %.9g\n", index, mapped[index], cpu[index]);
            return 1;
        }
    }
    SDL_UnmapGPUTransferBuffer(device, download);
    printf("verified IR -> MSL -> SDL %s: %u results agree\n",
        SDL_GetGPUDeviceDriver(device), COUNT);

    SDL_ReleaseGPUFence(device, fence);
    SDL_ReleaseGPUTransferBuffer(device, download);
    SDL_ReleaseGPUTransferBuffer(device, upload);
    SDL_ReleaseGPUBuffer(device, output_buffer);
    SDL_ReleaseGPUBuffer(device, input_buffer);
    SDL_ReleaseGPUComputePipeline(device, pipeline);
    SDL_DestroyGPUDevice(device);
    SDL_free(shader);
    free(cpu);
    free(input);
    SDL_Quit();
    return 0;
}
