local ffi = require("ffi")
local span = require("nupp.mem.span")
local gpu = require("nupp.gpu")
local generated = require("fastmath")

local here = assert(debug.getinfo(1, "S").source:match("^@(.*[/\\])"))
local now = dofile(here .. "../simd-mandelbrot/clock.lua")
local count = tonumber(os.getenv("FAST_MATH_COUNT") or 1048576)
local input = ffi.new("float[?]", count)
for index = 0, count - 1 do
    input[index] = -10.0 + 20.0 * index / (count - 1)
end

local context = gpu.open()
local inputBuffer = context:buffer(ffi.typeof("float"), count)
local exactBuffer = context:buffer(ffi.typeof("float"), count)
local nativeBuffer = context:buffer(ffi.typeof("float"), count)
context:upload(inputBuffer, span.fromCarray(input, count))
local exact = generated.exact:compile(context):bind(exactBuffer, inputBuffer)
local native = generated.native:compile(context):bind(nativeBuffer, inputBuffer)

local function measure(binding)
    local function dispatch()
        binding:dispatch()
        context:synchronize()
    end
    for _ = 1, 3 do dispatch() end
    local started, passes = now(), 0
    repeat
        dispatch()
        passes = passes + 1
    until now() - started >= 1.0
    return (now() - started) / passes
end

local exactElapsed = measure(exact)
local nativeElapsed = measure(native)
local expected = ffi.new("float[?]", count)
local actual = ffi.new("float[?]", count)
context:enqueueDownload(exactBuffer)
context:enqueueDownload(nativeBuffer)
context:synchronize()
context:readDownloaded(exactBuffer, span.writeCarray(expected, count))
context:readDownloaded(nativeBuffer, span.writeCarray(actual, count))
local maximumRelative = 0.0
for index = 0, count - 1 do
    local relative = math.abs(tonumber(actual[index] - expected[index])) / math.max(math.abs(tonumber(expected[index])), 1e-30)
    maximumRelative = math.max(maximumRelative, relative)
end
assert(maximumRelative <= 2e-5, ("native exp relative error %.9g exceeds contract benchmark"):format(maximumRelative))

io.write(("Native exp agrees with exact polynomial within %.3g relative error\n"):format(maximumRelative))
io.write(("%-16s %12.3f us  %8.2f million values/s\n"):format(
    "exact polynomial", exactElapsed * 1e6, count / exactElapsed / 1e6))
io.write(("%-16s %12.3f us  %8.2f million values/s\n"):format(
    "native granted", nativeElapsed * 1e6, count / nativeElapsed / 1e6))
context:drop()
