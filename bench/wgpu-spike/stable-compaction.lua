local ffi = require("ffi")
local span = require("nupp.mem.span")
local gpu = require("nupp.gpu")
local generated = require("compaction")

local here = assert(debug.getinfo(1, "S").source:match("^@(.*[/\\])"))
local now = dofile(here .. "../simd-mandelbrot/clock.lua")
local block = 256
local count = tonumber(os.getenv("COMPACTION_COUNT") or 65536)
assert(count % block == 0 and count <= block * block,
    "the generated hierarchy takes 256 through 65536 values in complete blocks")
local groups = count / block

local input = ffi.new("uint32_t[?]", count)
local selected = ffi.new("uint32_t[?]", count)
local expected = {}
local state = 42
for index = 0, count - 1 do
    input[index] = index * 17 + 3
    state = (state * 1103515245 + 12345) % 2147483648
    selected[index] = state % 5 == 0 and 1 or 0
    if selected[index] ~= 0 then expected[#expected + 1] = tonumber(input[index]) end
end

local context = gpu.open()
local element = ffi.typeof("uint32_t")
local inputBuffer = context:buffer(element, count)
local selectedBuffer = context:buffer(element, count)
local blockedBuffer = context:buffer(element, count)
local paddedCountsBuffer = context:buffer(element, block)
local countsBuffer = paddedCountsBuffer:subview({0}, {groups})
local offsetsBuffer = context:buffer(element, block)
local outputBuffer = context:buffer(element, count)
context:upload(inputBuffer, span.fromCarray(input, count))
context:upload(selectedBuffer, span.fromCarray(selected, count))

local zeros = ffi.new("uint32_t[?]", block)
context:upload(paddedCountsBuffer, span.fromCarray(zeros, block))
context:synchronize()

local pack = generated.blocks:compile(context):bind(
    blockedBuffer, countsBuffer, inputBuffer, selectedBuffer)
local offsets = generated.offsets:compile(context):bind(offsetsBuffer, paddedCountsBuffer)
local scatter = generated.scatter:compile(context):bind(
    outputBuffer, blockedBuffer, countsBuffer, offsetsBuffer)

local function dispatch()
    pack:dispatch()
    offsets:dispatch()
    scatter:dispatch()
    context:synchronize()
end

for _ = 1, 3 do dispatch() end
local started, passes = now(), 0
repeat
    dispatch()
    passes = passes + 1
until now() - started >= 1.0
local elapsed = (now() - started) / passes

local output = ffi.new("uint32_t[?]", count)
context:enqueueDownload(outputBuffer)
context:synchronize()
context:readDownloaded(outputBuffer, span.writeCarray(output, count))
for index, value in ipairs(expected) do
    assert(output[index - 1] == value,
        ("stable compaction mismatch at %d: got %d, want %d"):format(
            index - 1, tonumber(output[index - 1]), value))
end

io.write(("Stable compaction: %d selected from %d values in original order\n"):format(#expected, count))
io.write(("%-16s %12.3f us  %8.2f million values/s\n"):format(
    "three kernels", elapsed * 1e6, count / elapsed / 1e6))
context:drop()
