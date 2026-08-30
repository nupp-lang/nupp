local ffi = require("ffi")
local span = require("nupp.mem.span")
local gpu = require("nupp.gpu")
local generated = require("quantgemv")

local here = assert(debug.getinfo(1, "S").source:match("^@(.*[/\\])"))
local now = dofile(here .. "../simd-mandelbrot/clock.lua")
local rows = tonumber(os.getenv("QUANT_ROWS") or 1024)
local width = tonumber(os.getenv("QUANT_WIDTH") or 1024)
assert(width % 2 == 0)
local scale = 0.03125
local zeroPoint = 0

local input = ffi.new("float[?]", width)
local weights8 = ffi.new("int8_t[?]", rows * width)
local weights4 = ffi.new("uint8_t[?]", rows * width / 2)
for column = 0, width - 1 do input[column] = (column % 31 - 15) / 16 end
for index = 0, rows * width - 1 do
    local value8 = index % 255 - 127
    weights8[index] = value8
    local value4 = index % 16 - 8
    local packed = math.floor(index / 2)
    local nibble = value4 < 0 and value4 + 16 or value4
    if index % 2 == 0 then weights4[packed] = nibble
    else weights4[packed] = weights4[packed] + nibble * 16 end
end

local expected8 = ffi.new("float[?]", rows)
local expected4 = ffi.new("float[?]", rows)
generated.int8Cpu(span.writeCarray(expected8, rows), span.fromCarray(weights8, rows * width),
    span.fromCarray(input, width), width, scale, zeroPoint)
generated.int4Cpu(span.writeCarray(expected4, rows), span.fromCarray(weights4, rows * width / 2),
    span.fromCarray(input, width), width, scale, zeroPoint)

local context = gpu.open()
local inputBuffer = context:buffer(ffi.typeof("float"), width)
local weights8Buffer = context:buffer(ffi.typeof("int8_t"), rows * width)
local weights4Buffer = context:buffer(ffi.typeof("uint8_t"), rows * width / 2)
local output8Buffer = context:buffer(ffi.typeof("float"), rows)
local output4Buffer = context:buffer(ffi.typeof("float"), rows)
context:upload(inputBuffer, span.fromCarray(input, width))
context:upload(weights8Buffer, span.fromCarray(weights8, rows * width))
context:upload(weights4Buffer, span.fromCarray(weights4, rows * width / 2))
local int8 = generated.int8:compile(context):bind(output8Buffer, weights8Buffer, inputBuffer)
local int4 = generated.int4:compile(context):bind(output4Buffer, weights4Buffer, inputBuffer)

local function measure(binding)
    local function dispatch()
        binding:dispatch(width, scale, zeroPoint)
        context:synchronize()
    end
    for _ = 1, 3 do dispatch() end
    local started, passes = now(), 0
    repeat dispatch(); passes = passes + 1 until now() - started >= 1.0
    return (now() - started) / passes
end
local elapsed8 = measure(int8)
local elapsed4 = measure(int4)

local output8 = ffi.new("float[?]", rows)
local output4 = ffi.new("float[?]", rows)
context:enqueueDownload(output8Buffer)
context:enqueueDownload(output4Buffer)
context:synchronize()
context:readDownloaded(output8Buffer, span.writeCarray(output8, rows))
context:readDownloaded(output4Buffer, span.writeCarray(output4, rows))
for index = 0, rows - 1 do
    assert(output8[index] == expected8[index], ("int8 GEMV mismatch at %d: got %.9g, want %.9g"):format(
        index, tonumber(output8[index]), tonumber(expected8[index])))
    assert(output4[index] == expected4[index], ("int4 GEMV mismatch at %d: got %.9g, want %.9g"):format(
        index, tonumber(output4[index]), tonumber(expected4[index])))
end

local operations = 2 * rows * width
io.write(("Quantized GEMV %dx%d: int8 and packed int4 agree element-exact with CPU AOT\n"):format(rows, width))
io.write(("%-16s %12.3f us  %8.2f GOP/s\n"):format("int8", elapsed8 * 1e6, operations / elapsed8 / 1e9))
io.write(("%-16s %12.3f us  %8.2f GOP/s\n"):format("packed int4", elapsed4 * 1e6, operations / elapsed4 / 1e9))
context:drop()
