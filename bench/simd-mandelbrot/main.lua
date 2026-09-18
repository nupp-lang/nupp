-- Measure a point-input/result-output Mandelbrot kernel. Point generation,
-- allocation, correctness checks, and checksum reduction are deliberately
-- outside the timed native calls; everything the compiled function itself does
-- -- the whole-vector loop, the masked tail, the per-lane retirement and the
-- horizontal any-live test -- is inside them.
--
-- Three bodies are timed:
--
--   preferred    the gang the NEON tier picks, two registers of binary32
--   equal width  the same source pinned to one 16-byte register
--   scalar       the `_forced_scalar` twin, which is both the oracle every
--                pixel is checked against and the baseline the speedups are
--                over
--
-- Those two roles coincide here and do not in general. A body with a `@simd`
-- region inside it gets an oracle carrying `KS_SCALAR_ORACLE`, which is
-- `optnone` on Clang and `optimize("O0")` on GCC, and a -O0 function is not a
-- baseline anything can be said to be faster than. This kernel is a map
-- program, so its oracle carries the loop pragma instead and is compiled -O3
-- with the toolchain's vectorizers turned off for that loop -- which is the
-- separately identified no-vector artifact the plan asks for, already built.
-- Checked: the two spellings emit the same 66 instructions here.
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
local samples = tonumber(os.getenv("MANDELBROT_SAMPLES") or 9)
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

-- Correctness first, and against the oracle rather than against each other.
run(preferred.ks_mandelbrot, optimized)
run(equalWidth.ks_mandelbrot, x4)
run(preferred.ks_mandelbrot_forced_scalar, scalar)

local checked = {preferred = optimized, ["equal width"] = x4}
local checksum = 0
for i = 0, count - 1 do
    local want = scalar[i]
    for name, output in pairs(checked) do
        local got = output[i]
        assert(got.iterations == want.iterations and got.escaped == want.escaped,
            ("%s mismatch at pixel %d"):format(name, i))
    end
    checksum = checksum + optimized[i].iterations
end

local resultPath = os.getenv("MANDELBROT_RESULTS")
if resultPath then
    local results = assert(io.open(resultPath, "wb"))
    assert(results:write(ffi.string(optimized, ffi.sizeof("KsEscape") * count)))
    assert(results:close())
end

io.write(("Mandelbrot: %dx%d, %d max iterations, checksum %d\n"):format(
    width, height, maxIterations, checksum))
io.write("Every pixel of both vector bodies agrees with the scalar one.\n")

-- One frame each, in turn, repeated: drift on a machine that is not quiet is
-- then shared between the implementations rather than landing on whichever one
-- happened to run while something else was compiling.
local bodies = {
    {name = "Nupp f32x8", entry = preferred.ks_mandelbrot, output = optimized},
    {name = "Nupp f32x4", entry = equalWidth.ks_mandelbrot, output = x4},
    {name = "Nupp scalar", entry = preferred.ks_mandelbrot_forced_scalar, output = scalar},
}

for _, body in ipairs(bodies) do
    body.times = {}
    for _ = 1, 3 do
        run(body.entry, body.output)
    end
end
for sample = 1, samples do
    -- Rotate which body leads, so a first-in-the-round cost is not one body's.
    for index = 1, #bodies do
        local body = bodies[(index + sample - 2) % #bodies + 1]
        local started = now()
        run(body.entry, body.output)
        body.times[#body.times + 1] = now() - started
    end
end

local function median(values)
    local sorted = {}
    for index, value in ipairs(values) do
        sorted[index] = value
    end
    table.sort(sorted)
    local middle = math.floor(#sorted / 2)
    if #sorted % 2 == 1 then
        return sorted[middle + 1], sorted[1], sorted[#sorted]
    end

    return (sorted[middle] + sorted[middle + 1]) / 2, sorted[1], sorted[#sorted]
end

local baseline = nil
for _, body in ipairs(bodies) do
    local middle, lowest, highest = median(body.times)
    body.median = middle
    if body.name == "Nupp scalar" then
        baseline = middle
    end
    io.write(("%-15s %10.0f ns/frame  %8.2f MPix/s  (%.2f-%.2f)\n"):format(
        body.name, middle * 1e9, count / middle / 1e6,
        count / highest / 1e6, count / lowest / 1e6))
end
for _, body in ipairs(bodies) do
    io.write(("%-15s %6.2fx the scalar baseline\n"):format(body.name, baseline / body.median))
end
io.write(("%d samples each, alternating inside every sample.\n"):format(samples))

assert(optimized[count - 1].iterations == scalar[count - 1].iterations)
