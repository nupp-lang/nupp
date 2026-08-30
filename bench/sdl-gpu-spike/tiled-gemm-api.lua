-- Workgroup-phase design spike: a handwritten tiled Metal kernel is compared
-- element-exact with both the generated naive GPU kernel and CPU AOT body.
-- It deliberately reaches the private native ABI; production source remains
-- the generated binding, and NEP 26 decides how phases become checked syntax.
local ffi = require("ffi")
local span = require("nupp.mem.span")
local generated = require("gemm")
local gpu = require("nupp.gpu")

local here = assert(debug.getinfo(1, "S").source:match("^@(.*[/\\])"))
local now = dofile(here .. "../simd-mandelbrot/clock.lua")
local library = assert(os.getenv("NUPP_GPU_LIBRARY"), "NUPP_GPU_LIBRARY is required")
local C = ffi.load(library)

local size = tonumber(os.getenv("TILED_GEMM_SIZE") or 512)
assert(size % 16 == 0, "the phase spike takes a multiple-of-sixteen square")
local m, n, k = size, size, size

local source = [=[
#include <metal_stdlib>
using namespace metal;

struct NuppUniforms {
    uint count;
    uint a_count;
    uint b_count;
    uint c_count;
    uint columns;
    uint inner;
};

inline float nupp_f32_fma(float a, float b, float c) {
    float out = fma(a, b, c);
    return isnan(out) ? as_type<float>(0x7fc00000u) : out;
}

kernel void tiled_gemm(
    constant NuppUniforms& uniforms [[buffer(0)]],
    device const float* a [[buffer(1)]],
    device const float* b [[buffer(2)]],
    device float* c [[buffer(3)]],
    uint group [[threadgroup_position_in_grid]],
    uint local [[thread_index_in_threadgroup]])
{
    threadgroup float aTile[256];
    threadgroup float bTile[256];
    uint laneRow = local / 16u;
    uint laneColumn = local % 16u;
    uint tilesPerRow = uniforms.columns / 16u;
    uint tileRow = group / tilesPerRow;
    uint tileColumn = group % tilesPerRow;
    uint row = tileRow * 16u + laneRow;
    uint column = tileColumn * 16u + laneColumn;
    uint output = row * uniforms.columns + column;
    float value = 0.0f;

    for (uint base = 0u; base < uniforms.inner; base += 16u) {
        uint aColumn = base + laneColumn;
        uint bRow = base + laneRow;
        uint ai = row * uniforms.inner + aColumn;
        uint bi = bRow * uniforms.columns + column;
        aTile[local] = aColumn < uniforms.inner && ai < uniforms.a_count ? a[ai] : 0.0f;
        bTile[local] = bRow < uniforms.inner && bi < uniforms.b_count ? b[bi] : 0.0f;
        threadgroup_barrier(mem_flags::mem_threadgroup);

        for (uint inner = 0u; inner < 16u && base + inner < uniforms.inner; inner += 1u) {
            value = nupp_f32_fma(aTile[laneRow * 16u + inner], bTile[inner * 16u + laneColumn], value);
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);
    }

    if (output < uniforms.count && output < uniforms.c_count) c[output] = value;
}
]=]

local cell = ffi.new("float[1]")
local function f32(value)
    cell[0] = value
    return tonumber(cell[0])
end

local state = 42
local function nextValue()
    state = (state * 1103515245 + 12345) % 2147483648
    return f32(state / 1073741824.0 - 1.0)
end

local a = ffi.new("float[?]", m * k)
local b = ffi.new("float[?]", k * n)
for i = 0, m * k - 1 do a[i] = nextValue() end
for i = 0, k * n - 1 do b[i] = nextValue() end

local aSpan = span.fromCarray(a, m * k)
local bSpan = span.fromCarray(b, k * n)
local expected = ffi.new("float[?]", m * n)
generated.cpu(span.writeCarray(expected, m * n), aSpan, bSpan, n, k)

local context = gpu.open()
local aBuffer = context:buffer(ffi.typeof("float"), m * k)
local bBuffer = context:buffer(ffi.typeof("float"), k * n)
local naiveBuffer = context:buffer(ffi.typeof("float"), m * n)
local tiledBuffer = context:buffer(ffi.typeof("float"), m * n)
context:upload(aBuffer, aSpan)
context:upload(bBuffer, bSpan)
context:synchronize()

local naive = generated.gemm:compile(context):bind(naiveBuffer, aBuffer, bBuffer)

local dummySpirv = "\3\2\35\7"
local tiledKernel = C.nuppGpuKernelCreate(
    context._handle,
    dummySpirv, #dummySpirv,
    source, #source,
    "tiled_gemm", 10,
    2, 1, 24, 256)
assert(tiledKernel ~= nil, ffi.string(C.nuppNativeError()))
local tiled = C.nuppGpuBindingCreate(context._handle, tiledKernel, m * n)
assert(tiled ~= nil, ffi.string(C.nuppNativeError()))
assert(C.nuppGpuBindingSetRead(tiled, 0, aBuffer._handle, m * k, false))
assert(C.nuppGpuBindingSetRead(tiled, 1, bBuffer._handle, k * n, false))
assert(C.nuppGpuBindingSetWrite(tiled, 0, tiledBuffer._handle, m * n, true))
local uniforms = ffi.new("uint32_t[6]")
uniforms[4], uniforms[5] = n, k

local function naiveDispatch()
    naive:dispatch(n, k)
    context:synchronize()
end
local function tiledDispatch()
    assert(C.nuppGpuBindingDispatch(tiled, uniforms, ffi.sizeof(uniforms)), ffi.string(C.nuppNativeError()))
    context:synchronize()
end

local function measure(dispatch)
    for _ = 1, 3 do dispatch() end
    local started, passes = now(), 0
    repeat
        dispatch()
        passes = passes + 1
    until now() - started >= 1.0
    return (now() - started) / passes
end

local naiveElapsed = measure(naiveDispatch)
local tiledElapsed = measure(tiledDispatch)

local naiveOutput = ffi.new("float[?]", m * n)
local tiledOutput = ffi.new("float[?]", m * n)
context:enqueueDownload(naiveBuffer)
context:enqueueDownload(tiledBuffer)
context:synchronize()
context:readDownloaded(naiveBuffer, span.writeCarray(naiveOutput, m * n))
context:readDownloaded(tiledBuffer, span.writeCarray(tiledOutput, m * n))
for i = 0, m * n - 1 do
    assert(naiveOutput[i] == expected[i], ("naive mismatch at %d"):format(i))
    assert(tiledOutput[i] == expected[i], ("tiled mismatch at %d: got %.9g, want %.9g"):format(
        i, tiledOutput[i], expected[i]))
end

local flops = 2.0 * m * n * k
io.write(("Tiled GEMM %dx%dx%d: both GPU kernels agree element-exact with CPU AOT\n"):format(m, n, k))
io.write(("%-16s %12.3f ms  %8.2f GFLOP/s\n"):format(
    "naive generated", naiveElapsed * 1e3, flops / naiveElapsed / 1e9))
io.write(("%-16s %12.3f ms  %8.2f GFLOP/s\n"):format(
    "16x16 phases", tiledElapsed * 1e3, flops / tiledElapsed / 1e9))
context:drop()
