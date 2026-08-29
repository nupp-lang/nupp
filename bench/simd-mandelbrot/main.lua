-- Measure a point-input/result-output Mandelbrot kernel. Point generation,
-- allocation, correctness checks, and checksum reduction are deliberately
-- outside the timed native calls.
local ffi = require("ffi")

local here = assert(debug.getinfo(1, "S").source:match("^@(.*[/\\])"))
local now = dofile(here .. "clock.lua")
local out = here .. "build/preferred/"

ffi.cdef [[
typedef struct { int32_t iterations; uint32_t escaped; } KsEscape;
typedef struct { float re; float im; } KsPoint;
void ks_mandelbrot(KsEscape *escapes, const KsPoint *points,
    double first, double last, int32_t maxIterations, size_t count);
void ks_mandelbrot_forced_scalar(KsEscape *escapes, const KsPoint *points,
    double first, double last, int32_t maxIterations, size_t count);
]]

local suffix = jit.os == "OSX" and ".dylib" or ".so"
local preferred = ffi.load(out .. "libmandelbrot" .. suffix)
local equalWidth = ffi.load(out .. "../equal-width/libmandelbrot_x4" .. suffix)
local width = tonumber(os.getenv("MANDELBROT_WIDTH") or 1024)
local height = tonumber(os.getenv("MANDELBROT_HEIGHT") or 768)
local maxIterations = tonumber(os.getenv("MANDELBROT_ITERATIONS") or 256)
local count = width * height

local cell = ffi.new("float[1]")
local function f32(value)
    cell[0] = value
    return tonumber(cell[0])
end

-- Construct the grid with an explicit binary32 rounding point after each step.
local points = ffi.new("KsPoint[?]", count)
local dx = f32(f32(3.0) / f32(width))
local dy = f32(f32(2.4) / f32(height))
for y = 0, height - 1 do
    local yOffset = f32(f32(y) * dy)
    local cy = f32(f32(-1.2) + yOffset)
    for x = 0, width - 1 do
        local xOffset = f32(f32(x) * dx)
        local point = points[y * width + x]
        point.re = f32(f32(-2.0) + xOffset)
        point.im = cy
    end
end

local optimized = ffi.new("KsEscape[?]", count)
local x4 = ffi.new("KsEscape[?]", count)
local scalar = ffi.new("KsEscape[?]", count)

local function run(entry, output)
    entry(output, points, 1, count, maxIterations, count)
end

run(preferred.ks_mandelbrot, optimized)
run(equalWidth.ks_mandelbrot, x4)
run(preferred.ks_mandelbrot_forced_scalar, scalar)

local checksum = 0
for i = 0, count - 1 do
    local want = scalar[i]
    local got = optimized[i]
    local gotX4 = x4[i]
    assert(got.iterations == want.iterations and got.escaped == want.escaped,
        ("preferred lane mismatch at pixel %d"):format(i))
    assert(gotX4.iterations == want.iterations and gotX4.escaped == want.escaped,
        ("equal-width lane mismatch at pixel %d"):format(i))
    checksum = checksum + got.iterations
end

local resultPath = os.getenv("MANDELBROT_RESULTS")
if resultPath then
    local results = assert(io.open(resultPath, "wb"))
    assert(results:write(ffi.string(optimized, ffi.sizeof("KsEscape") * count)))
    assert(results:close())
end

io.write(("Mandelbrot: %dx%d, %d max iterations, checksum %d\n"):format(
    width, height, maxIterations, checksum))

local function benchmark(name, entry, output)
    for _ = 1, 3 do
        run(entry, output)
    end
    local started = now()
    local passes = 0
    repeat
        run(entry, output)
        passes = passes + 1
    until now() - started >= 1.0
    local elapsed = (now() - started) / passes
    io.write(("%-14s %10.0f ns/frame  %8.2f MPix/s\n"):format(
        name, elapsed * 1e9, count / elapsed / 1e6))
end

benchmark("Nupp f32x8", preferred.ks_mandelbrot, optimized)
benchmark("Nupp f32x4", equalWidth.ks_mandelbrot, x4)
benchmark("Nupp scalar", preferred.ks_mandelbrot_forced_scalar, scalar)
assert(optimized[count - 1].iterations == scalar[count - 1].iterations)
