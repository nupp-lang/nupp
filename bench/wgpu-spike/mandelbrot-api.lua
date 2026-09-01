-- Exercise nupp.gpu at the same point-array boundary as simd-mandelbrot.
local ffi = require("ffi")
local span = require("nupp.mem.span")
local generated = require("mandelbrot")
local gpu = require("nupp.gpu")

local here = assert(debug.getinfo(1, "S").source:match("^@(.*[/\\])"))
local now = dofile(here .. "../simd-mandelbrot/clock.lua")

ffi.cdef [[
typedef struct { int32_t iterations; uint32_t escaped; } KsEscape;
typedef struct { float re; float im; } KsPoint;
]]

local function read(path)
    local file = assert(io.open(path, "rb"))
    local value = assert(file:read("*a"))
    assert(file:close())
    return value
end

local expectedPath = assert(arg[1], "usage: mandelbrot-api.lua EXPECTED.bin")
local width = tonumber(os.getenv("MANDELBROT_WIDTH") or 1024)
local height = tonumber(os.getenv("MANDELBROT_HEIGHT") or 768)
local maxIterations = tonumber(os.getenv("MANDELBROT_ITERATIONS") or 256)
local count = width * height
assert(count % 64 == 0, "Mandelbrot GPU workgroups require a pixel count divisible by 64")

local points = ffi.new("KsPoint[?]", count)
local cell = ffi.new("float[1]")
local function f32(value)
    cell[0] = value
    return tonumber(cell[0])
end

local dx = f32(f32(3.0) / f32(width))
local dy = f32(f32(2.4) / f32(height))
for y = 0, height - 1 do
    local cy = f32(f32(-1.2) + f32(f32(y) * dy))
    for x = 0, width - 1 do
        local point = points[y * width + x]
        point.re = f32(f32(-2.0) + f32(f32(x) * dx))
        point.im = cy
    end
end

local output = ffi.new("KsEscape[?]", count)
local context = gpu.open()
local pointBuffer = context:buffer(ffi.typeof("KsPoint"), count)
local escapeBuffer = context:buffer(ffi.typeof("KsEscape"), count)
local kernel = generated.mandelbrot:compile(context)
local invocation = kernel:bind(escapeBuffer, pointBuffer)

context:upload(pointBuffer, span.fromCarray(points, count))
context:synchronize()

local function dispatch()
    invocation:dispatch(maxIterations)
    context:synchronize()
end

for _ = 1, 3 do dispatch() end
local started = now()
local passes = 0
repeat
    dispatch()
    passes = passes + 1
until now() - started >= 1.0
local elapsed = (now() - started) / passes

context:enqueueDownload(escapeBuffer)
context:synchronize()
context:readDownloaded(escapeBuffer, span.writeCarray(output, count))

local expected = read(expectedPath)
assert(#expected == ffi.sizeof("KsEscape") * count, "unexpected SIMD result size")
local checksum = 0
for i = 0, count - 1 do
    local want = ffi.cast("const KsEscape *", expected)[i]
    local got = output[i]
    assert(got.iterations == want.iterations and got.escaped == want.escaped,
        ("WGPU API mismatch at pixel %d: got %d/%d, want %d/%d"):format(
            i, got.iterations, got.escaped, want.iterations, want.escaped))
    checksum = checksum + got.iterations
end

io.write(("Mandelbrot GPU API: %dx%d, %d max iterations, checksum %d\n"):format(
    width, height, maxIterations, checksum))
io.write(("%-16s %10.0f ns/frame  %8.2f MPix/s\n"):format(
    "WGPU resident", elapsed * 1e9, count / elapsed / 1e6))
context:drop()
