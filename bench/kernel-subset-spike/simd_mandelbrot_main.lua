-- Measure the checksum-only Mandelbrot kernel matching Forgo's original
-- benchmark boundary. The eight stream descriptors are scheduling metadata,
-- not precomputed coordinates; all coordinate and escape work is native and
-- timed.
local ffi = require("ffi")

local here = assert(debug.getinfo(1, "S").source:match("^@(.*[/\\])"))
local now = dofile(here .. "wallclock.lua")
local out = here .. "build/simd_mandelbrot/"

ffi.cdef [[
typedef struct { int32_t lane; int32_t groupOffset; } KsForgoStream;
void ks_simd_mandelbrot(int32_t *sums,
    const KsForgoStream *streams, double first, double last,
    int32_t width, int32_t height, int32_t maxIterations, size_t count);
void ks_simd_mandelbrot_forced_scalar(int32_t *sums,
    const KsForgoStream *streams, double first, double last,
    int32_t width, int32_t height, int32_t maxIterations, size_t count);
]]

local lib = ffi.load(out .. "libsimd_mandelbrot" ..
    (jit.os == "OSX" and ".dylib" or ".so"))
local libX4 = ffi.load(out .. "../simd_mandelbrot_x4/" ..
    "libsimd_mandelbrot_x4" .. (jit.os == "OSX" and ".dylib" or ".so"))
local width = tonumber(os.getenv("MANDELBROT_WIDTH") or 1024)
local height = tonumber(os.getenv("MANDELBROT_HEIGHT") or 768)
local maxIterations = tonumber(os.getenv("MANDELBROT_ITERATIONS") or 256)
assert(width % 8 == 0, "width must be a multiple of eight")

local streams = ffi.new("KsForgoStream[8]")
local sums = ffi.new("int32_t[8]")
for stream = 0, 7 do
    streams[stream].lane = stream % 4
    streams[stream].groupOffset = stream - streams[stream].lane
end

local sink = 0
local function call(entry)
    entry(sums, streams, 1, 8, width, height, maxIterations, 8)
    local checksum = 0
    for lane = 0, 7 do
        checksum = checksum + tonumber(sums[lane])
    end
    sink = checksum
    return checksum
end

local optimizedChecksum = call(lib.ks_simd_mandelbrot)
local optimizedSums = {}
for lane = 0, 7 do
    optimizedSums[lane + 1] = tonumber(sums[lane])
end
local x4Checksum = call(libX4.ks_simd_mandelbrot)
local scalarChecksum = call(lib.ks_simd_mandelbrot_forced_scalar)
local scalarSums = {}
for lane = 0, 7 do
    scalarSums[lane + 1] = tonumber(sums[lane])
end
if optimizedChecksum ~= scalarChecksum then
    io.stderr:write("Nupp lanes:  ", table.concat(optimizedSums, ", "), "\n")
    io.stderr:write("Nupp scalar: ", table.concat(scalarSums, ", "), "\n")
end
assert(optimizedChecksum == scalarChecksum,
    ("Nupp lane/scalar checksum mismatch: %d ~= %d"):format(
        optimizedChecksum, scalarChecksum))
assert(x4Checksum == scalarChecksum,
    ("Nupp f32x4/scalar checksum mismatch: %d ~= %d"):format(
        x4Checksum, scalarChecksum))
io.write(("Mandelbrot: %dx%d, %d max iterations, checksum %d\n"):format(
    width, height, maxIterations, optimizedChecksum))

local pixels = width * height
local function benchmark(name, entry)
    for _ = 1, 3 do
        call(entry)
    end
    local started = now()
    local passes = 0
    repeat
        call(entry)
        passes = passes + 1
    until now() - started >= 1.0
    local elapsed = (now() - started) / passes
    io.write(("%-14s %10.0f ns/frame  %8.2f MPix/s\n"):format(
        name, elapsed * 1e9, pixels / elapsed / 1e6))
end

benchmark("Nupp f32x8", lib.ks_simd_mandelbrot)
benchmark("Nupp f32x4", libX4.ks_simd_mandelbrot)
benchmark("Nupp scalar", lib.ks_simd_mandelbrot_forced_scalar)
assert(sink == optimizedChecksum)
