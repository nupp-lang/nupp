-- Fixed-tree reduction spike: one declared 256-lane tree is executed in the
-- same stage order by the ordinary CPU control and a handwritten Metal kernel.
-- This reaches the private native ABI only while NEP 26's phase syntax is Draft.
local ffi = require("ffi")
local span = require("nupp.mem.span")
local gpu = require("nupp.gpu")

local here = assert(debug.getinfo(1, "S").source:match("^@(.*[/\\])"))
local now = dofile(here .. "../simd-mandelbrot/clock.lua")
local library = assert(os.getenv("NUPP_GPU_LIBRARY"), "NUPP_GPU_LIBRARY is required")
local C = ffi.load(library)

local workgroupSize = 256
local count = tonumber(os.getenv("REDUCTION_COUNT") or 65536)
assert(count == workgroupSize * workgroupSize, "the two-level spike takes exactly 65536 values")

local source = [=[
#include <metal_stdlib>
using namespace metal;
#pragma clang fp contract(off)

struct NuppUniforms {
    uint count;
    uint input_count;
    uint output_count;
    uint active_count;
};

inline float nupp_f32_nan() { return as_type<float>(0x7fc00000u); }
inline float nupp_f32_fma(float a, float b, float c) {
    float out = fma(a, b, c);
    return isnan(out) ? nupp_f32_nan() : out;
}
inline float nupp_f32_exp(float value) {
    float x = max(-104.0f, min(value, 88.0f));
    float y = x * 0.0078125f;
    float out = 0.0000000020876757f;
    out = nupp_f32_fma(out, y, 0.000000025052108f);
    out = nupp_f32_fma(out, y, 0.00000027557319f);
    out = nupp_f32_fma(out, y, 0.0000027557319f);
    out = nupp_f32_fma(out, y, 0.000024801587f);
    out = nupp_f32_fma(out, y, 0.0001984127f);
    out = nupp_f32_fma(out, y, 0.0013888889f);
    out = nupp_f32_fma(out, y, 0.0083333333f);
    out = nupp_f32_fma(out, y, 0.041666667f);
    out = nupp_f32_fma(out, y, 0.16666667f);
    out = nupp_f32_fma(out, y, 0.5f);
    out = nupp_f32_fma(out, y, 1.0f);
    out = nupp_f32_fma(out, y, 1.0f);
    out *= out; out *= out; out *= out; out *= out;
    out *= out; out *= out; out *= out;
    return out;
}

kernel void fixed_tree_exp_sum(
    constant NuppUniforms& uniforms [[buffer(0)]],
    device const float* input [[buffer(1)]],
    device float* output [[buffer(2)]],
    uint group [[threadgroup_position_in_grid]],
    uint local [[thread_index_in_threadgroup]])
{
    threadgroup float scratch[256];
    uint index = group * 256u + local;
    scratch[local] = index < uniforms.active_count
        ? nupp_f32_exp(input[index])
        : 0.0f;
    threadgroup_barrier(mem_flags::mem_threadgroup);
    for (uint stride = 128u; stride != 0u; stride >>= 1u) {
        if (local < stride) scratch[local] = scratch[local] + scratch[local + stride];
        threadgroup_barrier(mem_flags::mem_threadgroup);
    }
    if (local == 0u && group < uniforms.output_count) output[group] = scratch[0];
}

kernel void fixed_tree_sum(
    constant NuppUniforms& uniforms [[buffer(0)]],
    device const float* input [[buffer(1)]],
    device float* output [[buffer(2)]],
    uint group [[threadgroup_position_in_grid]],
    uint local [[thread_index_in_threadgroup]])
{
    threadgroup float scratch[256];
    uint index = group * 256u + local;
    scratch[local] = index < uniforms.active_count ? input[index] : 0.0f;
    threadgroup_barrier(mem_flags::mem_threadgroup);
    for (uint stride = 128u; stride != 0u; stride >>= 1u) {
        if (local < stride) scratch[local] = scratch[local] + scratch[local + stride];
        threadgroup_barrier(mem_flags::mem_threadgroup);
    }
    if (local == 0u && group < uniforms.output_count) output[group] = scratch[0];
}
]=]

local cell = ffi.new("float[1]")
local function narrow(value)
    cell[0] = value
    return tonumber(cell[0])
end

ffi.cdef("float fmaf(float, float, float);")
local f32 = {}
function f32.add(left, right)
    return narrow(narrow(left) + narrow(right))
end
function f32.fma(left, right, addend)
    return narrow(ffi.C.fmaf(narrow(left), narrow(right), narrow(addend)))
end
function f32.exp(value)
    local x = math.max(-104.0, math.min(narrow(value), 88.0))
    local y = narrow(x * 0.0078125)
    local out = narrow(0.0000000020876757)
    for _, coefficient in ipairs({
        0.000000025052108, 0.00000027557319, 0.0000027557319,
        0.000024801587, 0.0001984127, 0.0013888889,
        0.0083333333, 0.041666667, 0.16666667, 0.5, 1.0, 1.0,
    }) do
        out = f32.fma(out, y, coefficient)
    end
    for _ = 1, 7 do out = narrow(out * out) end
    return out
end

local state = 42
local values = ffi.new("float[?]", count)
for index = 0, count - 1 do
    state = (state * 1103515245 + 12345) % 2147483648
    values[index] = narrow(-16.0 * state / 2147483648.0)
end

local function tree(sourceValues, active, transform)
    local groups = math.ceil(active / workgroupSize)
    local out = {}
    for group = 0, groups - 1 do
        local scratch = {}
        for localIndex = 0, workgroupSize - 1 do
            local index = group * workgroupSize + localIndex
            local value = index < active and sourceValues[index] or 0.0
            scratch[localIndex] = transform and transform(value) or value
        end
        local stride = workgroupSize / 2
        while stride >= 1 do
            for localIndex = 0, stride - 1 do
                scratch[localIndex] = f32.add(scratch[localIndex], scratch[localIndex + stride])
            end
            stride = stride / 2
        end
        out[group] = scratch[0]
    end
    return out
end

local expectedPartials = tree(values, count, f32.exp)
local expected = tree(expectedPartials, workgroupSize)[0]

local context = gpu.open()
local input = context:buffer(ffi.typeof("float"), count)
local partials = context:buffer(ffi.typeof("float"), count)
local result = context:buffer(ffi.typeof("float"), workgroupSize)
context:upload(input, span.fromCarray(values, count))
context:synchronize()

local dummySpirv = "\3\2\35\7"
local function makeKernel(entrypoint)
    local kernel = C.nuppGpuKernelCreate(
        context._handle,
        dummySpirv, #dummySpirv,
        source, #source,
        entrypoint, #entrypoint,
        1, 1, 16, workgroupSize)
    assert(kernel ~= nil, ffi.string(C.nuppNativeError()))
    return kernel
end

local firstKernel = makeKernel("fixed_tree_exp_sum")
local secondKernel = makeKernel("fixed_tree_sum")
local first = C.nuppGpuBindingCreate(context._handle, firstKernel, count)
local second = C.nuppGpuBindingCreate(context._handle, secondKernel, workgroupSize)
assert(first ~= nil and second ~= nil, ffi.string(C.nuppNativeError()))
assert(C.nuppGpuBindingSetRead(first, 0, input._handle, count, false))
assert(C.nuppGpuBindingSetWrite(first, 0, partials._handle, count, true))
assert(C.nuppGpuBindingSetRead(second, 0, partials._handle, count, false))
assert(C.nuppGpuBindingSetWrite(second, 0, result._handle, workgroupSize, true))

local firstUniforms = ffi.new("uint32_t[4]")
firstUniforms[3] = count
local secondUniforms = ffi.new("uint32_t[4]")
secondUniforms[3] = workgroupSize

local function dispatch()
    assert(C.nuppGpuBindingDispatch(first, firstUniforms, ffi.sizeof(firstUniforms)), ffi.string(C.nuppNativeError()))
    assert(C.nuppGpuBindingDispatch(second, secondUniforms, ffi.sizeof(secondUniforms)), ffi.string(C.nuppNativeError()))
    context:synchronize()
end

for _ = 1, 3 do dispatch() end
local started, passes = now(), 0
repeat
    dispatch()
    passes = passes + 1
until now() - started >= 1.0
local elapsed = (now() - started) / passes

local output = ffi.new("float[?]", workgroupSize)
context:enqueueDownload(result)
context:synchronize()
context:readDownloaded(result, span.writeCarray(output, workgroupSize))
assert(output[0] == expected, ("reduction mismatch: got %.9g, want %.9g"):format(output[0], expected))

io.write(("Fixed 256-lane exp-sum tree: GPU and CPU agree at %.9g\n"):format(expected))
io.write(("%-16s %12.3f us  %8.2f million values/s\n"):format(
    "two GPU levels", elapsed * 1e6, count / elapsed / 1e6))
context:drop()
