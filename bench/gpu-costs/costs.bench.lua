-- The module must come from the require-policy build, including its native CPU entry.
local here = assert(debug.getinfo(1, "S").source:match("^@(.*[/\\])"))
package.path = here .. "build/?.lua;" .. package.path
local kernels = require("kernels")
local compiledEntries = rawget(_G, "__nuppAotCompiled")
assert(compiledEntries and compiledEntries[kernels.cpu], "the CPU kernel must be registered as compiled AOT")
assert(
    kernels.device ~= nil and type(kernels.device.compile) == "function",
    "build bench/gpu-costs with aot=require before measuring; the GPU binding is missing"
)
local ffi = require("ffi")
local span = require("binary.span")
local gpu = require("io.gpu")
local bench = require("debug.bench")

local function host(invocation)
    local count = invocation.parameters.count
    local input, output, expected = ffi.new(
        "uint32_t[?]",
        count
    ), ffi.new("uint32_t[?]", count), ffi.new("uint32_t[?]", count)
    for index = 0, count - 1 do
        input[index] = index * 97 + 11
    end
    local state = {count = count, input = input, output = output, expected = expected}
    state.source = span.fromcarray(input, count)
    state.destination = span.writecarray(output, count)
    kernels.cpu(span.writecarray(expected, count), state.source)

    return state
end

local function check(state)
    for index = 0, state.count - 1 do
        assert(state.output[index] == state.expected[index], "CPU/GPU output differs at " .. index)
    end
end

local function runCpu(state)
    kernels.cpu(state.destination, state.source)
    return tonumber(state.output[state.count - 1])
end

local function runGpu(state)
    state.context:upload(state.inputBuffer, state.source)
    state.binding:dispatch()
    state.context:enqueuedownload(state.outputBuffer)
    state.context:synchronize()
    state.context:readdownloaded(state.outputBuffer, state.destination)

    return tonumber(state.output[state.count - 1])
end

local function device(invocation)
    local state = host(invocation)
    state.context = gpu.open()
    state.inputBuffer = state.context:buffer(require("nupp.runtime.standardtable").Array.uint32, state.count)
    state.outputBuffer = state.context:buffer(require("nupp.runtime.standardtable").Array.uint32, state.count)
    state.kernel = kernels.device:compile(state.context)
    state.binding = state.kernel:bind(state.outputBuffer, state.inputBuffer)
    -- Each sample gets a fresh context; first dispatch belongs to setup.
    runGpu(state)
    check(state)

    return state
end

local command, requestedCount = ...
if command == "--smoke" then
    local invocation = {parameters = {count = tonumber(requestedCount) or 4096}}
    local cpu = host(invocation)
    runCpu(cpu)
    check(cpu)
    local native = device(invocation)
    runGpu(native)
    check(native)
    runGpu(native)
    check(native)
    native.context:close()
    print("compiled CPU/GPU outputs agree for " .. invocation.parameters.count .. " elements")
    return
end

bench.suite({
    name = "gpu-costs",
    baseline = "cpu-aot",
    variants = {
        {name = "cpu-aot", setup = host, run = runCpu, teardown = check},
        {
            name = "gpu-transfer",
            setup = device,
            run = runGpu,
            teardown = function(state)
                check(state)
                state.context:close()
            end
        },
    },
    cases = {{name = "mix64", parameters = {count = {64, 4096, 262144}}}},
    warmup = 1,
    batch = 64,
    minsamples = 7,
    minms = 100,
    maxsamples = 100000,
    maxms = 3000,
})
bench.report()
