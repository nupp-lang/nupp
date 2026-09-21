-- Compare complete scalar and authored SIMD Mandelbrot entries.
local ffi = require("ffi")
local here = assert(debug.getinfo(1, "S").source:match("^@(.*[/\\])"))
local now = dofile(here .. "clock.lua")

ffi.cdef[[
typedef struct { int32_t iterations; uint32_t escaped; } KsEscape;
typedef struct { float re; float im; } KsPoint;
void ks_mandelbrot(KsEscape *, const KsPoint *, double, double, int32_t, size_t, size_t);
void ks_mandelbrot_simd(int32_t *, uint32_t *, const float *, const float *, double, double, int32_t, size_t, size_t);
void ks_mandelbrot_simd_forced_scalar(int32_t *, uint32_t *, const float *, const float *, double, double, int32_t, size_t, size_t);
]]

local suffix = jit.os == "OSX" and ".dylib" or ".so"
local library = ffi.load(here .. "build/current/libmandelbrot" .. suffix)
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

local points = ffi.new("KsPoint[?]", count)
local pointRe = ffi.new("float[?]", count)
local pointIm = ffi.new("float[?]", count)
local dx = f32(f32(3.0) / f32(width))
local dy = f32(f32(2.4) / f32(height))
for y = 0, height - 1 do
    local cy = f32(f32(-1.2) + f32(f32(y) * dy))
    for x = 0, width - 1 do
        local point = points[y * width + x]
        point.re = f32(f32(-2.0) + f32(f32(x) * dx))
        point.im = cy
        pointRe[y * width + x] = point.re
        pointIm[y * width + x] = point.im
    end
end

local scalar = ffi.new("KsEscape[?]", count)
local vector = ffi.new("KsEscape[?]", count)
local oracle = ffi.new("KsEscape[?]", count)
local vectorIterations = ffi.new("int32_t[?]", count)
local vectorEscaped = ffi.new("uint32_t[?]", count)
local oracleIterations = ffi.new("int32_t[?]", count)
local oracleEscaped = ffi.new("uint32_t[?]", count)

local function runScalar()
    library.ks_mandelbrot(scalar, points, 1, count, maxIterations, count, count)
end

local function runVector(entry, iterations, escaped)
    entry(iterations, escaped, pointRe, pointIm, 1, count, maxIterations, count, count)
end

runScalar()
runVector(library.ks_mandelbrot_simd, vectorIterations, vectorEscaped)
runVector(library.ks_mandelbrot_simd_forced_scalar, oracleIterations, oracleEscaped)
local checksum = 0
for i = 0, count - 1 do
    vector[i].iterations = vectorIterations[i]
    vector[i].escaped = vectorEscaped[i]
    oracle[i].iterations = oracleIterations[i]
    oracle[i].escaped = oracleEscaped[i]
    assert(
        vector[i].iterations == scalar[i].iterations and vector[i].escaped == scalar[i].escaped,
        (
            "SIMD mismatch at pixel %d: scalar=(%d,%d), vector=(%d,%d), oracle=(%d,%d)"
        ):format(
            i,
            scalar[i].iterations,
            scalar[i].escaped,
            vector[i].iterations,
            vector[i].escaped,
            oracle[i].iterations,
            oracle[i].escaped
        )
    )
    assert(
        oracle[i].iterations == scalar[i].iterations and oracle[i].escaped == scalar[i].escaped,
        ("forced-scalar oracle mismatch at pixel %d"):format(i)
    )
    checksum = checksum + vector[i].iterations
end
local resultPath = os.getenv("MANDELBROT_RESULTS")
if resultPath then
    local results = assert(io.open(resultPath, "wb"))
    assert(results:write(ffi.string(vector, ffi.sizeof("KsEscape") * count)))
    assert(results:close())
end
io.write(("Mandelbrot: %dx%d, %d max iterations, checksum %d\n"):format(width, height, maxIterations, checksum))

local bodies = {
    {name = "Nupp scalar", invoke = runScalar},
    {
        name = "Nupp explicit SIMD",
        invoke = function()
            runVector(library.ks_mandelbrot_simd, vectorIterations, vectorEscaped)
        end
    },
}
for _, body in ipairs(bodies) do
    body.times = {}
    for _ = 1, 3 do
        body.invoke()
    end
end
for sample = 1, samples do
    for index = 1, #bodies do
        local body = bodies[(index + sample - 2) % #bodies + 1]
        local started = now()
        body.invoke()
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
        return sorted[middle + 1]
    end

    return (sorted[middle] + sorted[middle + 1]) / 2
end

local scalarTime = median(bodies[1].times)
for _, body in ipairs(bodies) do
    local elapsed = median(body.times)
    io.write(
        (
            "%-20s %10.0f ns/frame  %8.2f MPix/s  %.2fx scalar\n"
        ):format(body.name, elapsed * 1e9, count / elapsed / 1e6, scalarTime / elapsed)
    )
end
io.write(("%d interleaved samples per entry.\n"):format(samples))
