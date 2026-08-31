-- Generated structured-workgroup GEMM compared element-exact with the
-- generated naive GPU kernel and CPU AOT body.
local ffi = require("ffi")
local span = require("nupp.mem.span")
local generated = require("gemm")
local gpu = require("nupp.gpu")

local here = assert(debug.getinfo(1, "S").source:match("^@(.*[/\\])"))
local now = dofile(here .. "../simd-mandelbrot/clock.lua")
local size = tonumber(os.getenv("TILED_GEMM_SIZE") or 512)
assert(size % 16 == 0, "the phase spike takes a multiple-of-sixteen square")
local m, n, k = size, size, size

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
local tiled = generated.tiled:compile(context):bind(tiledBuffer, aBuffer, bBuffer)

local function naiveDispatch()
    naive:dispatch(n, k)
    context:synchronize()
end
local function tiledDispatch()
    tiled:dispatch(n, k)
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
