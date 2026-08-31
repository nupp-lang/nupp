-- Naive f32 GEMM through nupp.gpu's generated binding, validated element-exact
-- against the generated CPU AOT kernel from the same source.
local ffi = require("ffi")
local span = require("nupp.mem.span")
local generated = require("gemm")
local gpu = require("nupp.gpu")

local here = assert(debug.getinfo(1, "S").source:match("^@(.*[/\\])"))
local now = dofile(here .. "../simd-mandelbrot/clock.lua")

local m = tonumber(os.getenv("GEMM_M") or 256)
local n = tonumber(os.getenv("GEMM_N") or 256)
local k = tonumber(os.getenv("GEMM_K") or 256)

local cell = ffi.new("float[1]")
local function f32(value)
    cell[0] = value
    return tonumber(cell[0])
end

-- Deterministic values in [-1, 1) so accumulation stays well-conditioned.
local state = 42
local function nextValue()
    state = (state * 1103515245 + 12345) % 2147483648
    return f32(state / 1073741824.0 - 1.0)
end

local a = ffi.new("float[?]", m * k)
local b = ffi.new("float[?]", k * n)
for i = 0, m * k - 1 do a[i] = nextValue() end
for i = 0, k * n - 1 do b[i] = nextValue() end

local expected = ffi.new("float[?]", m * n)
local spans = {
    a = span.fromCarray(a, m * k),
    b = span.fromCarray(b, k * n),
}

local cpuStarted = now()
generated.cpu(span.writeCarray(expected, m * n), spans.a, spans.b, n, k)
local cpuElapsed = now() - cpuStarted

local output = ffi.new("float[?]", m * n)
local context = gpu.open()
io.write(("GPU driver: %s\n"):format(context:driver()))
io.stdout:flush()
local cBuffer = context:buffer(ffi.typeof("float"), m * n)
local aBuffer = context:buffer(ffi.typeof("float"), m * k)
local bBuffer = context:buffer(ffi.typeof("float"), k * n)
local kernel = generated.gemm:compile(context)
local invocation = kernel:bind(cBuffer, aBuffer, bBuffer)

for i = 0, m * n - 1 do output[i] = 127.25 end
context:upload(cBuffer, span.fromCarray(output, m * n))
context:upload(aBuffer, spans.a)
context:upload(bBuffer, spans.b)
context:synchronize()

local function verifyTransfer(buffer, source, count, name)
    local copied = ffi.new("float[?]", count)
    context:enqueueDownload(buffer)
    context:synchronize()
    context:readDownloaded(buffer, span.writeCarray(copied, count))
    for i = 0, count - 1 do
        assert(copied[i] == source[i],
            ("%s transfer mismatch at element %d: got %.9g, want %.9g"):format(
                name, i, copied[i], source[i]))
    end
end

verifyTransfer(aBuffer, a, m * k, "left input")
verifyTransfer(bBuffer, b, k * n, "right input")

local function readBuffer(buffer, count)
    local copied = ffi.new("float[?]", count)
    context:enqueueDownload(buffer)
    context:synchronize()
    context:readDownloaded(buffer, span.writeCarray(copied, count))
    return copied
end

local copy = generated.copy:compile(context):bind(cBuffer, aBuffer)
copy:dispatch()
context:synchronize()
local copied = readBuffer(cBuffer, m * n)
for i = 0, m * n - 1 do
    assert(copied[i] == a[i],
        ("storage binding mismatch at element %d: got %.9g, want %.9g"):format(
            i, copied[i], a[i]))
end

local fill = generated.fill:compile(context):bind(cBuffer, aBuffer)
fill:dispatch(9.25)
context:synchronize()
local filled = readBuffer(cBuffer, m * n)
for i = 0, m * n - 1 do
    assert(filled[i] == 9.25,
        ("scalar uniform mismatch at element %d: got %.9g, want 9.25"):format(i, filled[i]))
end

local function dispatch()
    invocation:dispatch(n, k)
    context:synchronize()
end

for _ = 1, 3 do dispatch() end
local started = now()
local passes = 0
repeat
    dispatch()
    passes = passes + 1
until now() - started >= 1.0
local gpuElapsed = (now() - started) / passes

context:enqueueDownload(cBuffer)
context:synchronize()
context:readDownloaded(cBuffer, span.writeCarray(output, m * n))

assert(output[0] ~= 127.25, "GEMM dispatch left its output buffer unchanged")
for i = 0, m * n - 1 do
    assert(output[i] == expected[i],
        ("GEMM mismatch at element %d: got %.9g, want %.9g"):format(i, output[i], expected[i]))
end

local flops = 2.0 * m * n * k
io.write(("GEMM %dx%dx%d: all %d elements agree with CPU AOT\n"):format(m, n, k, m * n))
io.write(("%-16s %12.3f ms  %8.2f GFLOP/s\n"):format("Nupp CPU scalar", cpuElapsed * 1e3, flops / cpuElapsed / 1e9))
io.write(("%-16s %12.3f ms  %8.2f GFLOP/s\n"):format("SDL GPU resident", gpuElapsed * 1e3, flops / gpuElapsed / 1e9))
context:drop()
