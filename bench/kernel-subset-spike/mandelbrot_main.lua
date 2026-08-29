-- Runs the AOT-compiled Mandelbrot kernel, checks it, and draws it.
--
-- Correctness first: the generated optimized and forced-scalar bodies come from
-- one IR, and a plain Lua implementation of the same recurrence is the oracle.
-- All three must agree on every pixel's escape count exactly -- not to within a
-- tolerance, because the kernel's arithmetic is specified to be the same
-- binary64 work in the same order, and a mismatch would mean the backend
-- changed an answer rather than only its speed.
local ffi = require("ffi")

local here = assert(debug.getinfo(1, "S").source:match("^@(.*[/\\])"))
local now = dofile(here .. "wallclock.lua")
-- Which kernel to run. `mandelbrot` is the ordinary binary64 one; `mandelbrot_f32`
-- is the same algorithm written in explicit binary32, which is a different
-- program with different escape counts and is checked against its own oracle.
local KERNEL = os.getenv("MANDELBROT_KERNEL") or "mandelbrot"
local PROFILE = os.getenv("MANDELBROT_PROFILE") or "display"
if PROFILE == "forgo" and KERNEL ~= "mandelbrot_f32" then
    error("the forgo comparison profile requires mandelbrot_f32", 0)
end
local OUT = here .. "build/" .. KERNEL .. "/"
package.path = OUT .. "fallback/?.lua;" .. OUT .. "fallback/?/init.lua;" .. package.path

local ordinary = require(KERNEL)
local spans = require("nupp.mem.span")

ffi.cdef[[
typedef struct { int32_t iterations; uint32_t escaped; } KsEscape;
typedef struct { float re; float im; } KsPoint;
void ks_mandelbrot(KsEscape *escapes, const KsPoint *points,
   double first, double last, int32_t maxIterations, size_t count);
void ks_mandelbrot_forced_scalar(KsEscape *escapes, const KsPoint *points,
   double first, double last, int32_t maxIterations, size_t count);
]]

local lib = ffi.load(OUT .. "lib" .. KERNEL .. (jit.os == "OSX" and ".dylib" or ".so"))

local WIDTH = tonumber(os.getenv("MANDELBROT_WIDTH") or (PROFILE == "forgo" and 1024 or 78))
local HEIGHT = tonumber(os.getenv("MANDELBROT_HEIGHT") or (PROFILE == "forgo" and 768 or 30))
local MAX_ITERATIONS = tonumber(os.getenv("MANDELBROT_ITERATIONS") or (PROFILE == "forgo" and 256 or 500))
local MIN_X = tonumber(os.getenv("MANDELBROT_MIN_X") or (PROFILE == "forgo" and -2.0 or -2.2))
local MAX_X = tonumber(os.getenv("MANDELBROT_MAX_X") or (PROFILE == "forgo" and 1.0 or 0.9))
local MIN_Y = tonumber(os.getenv("MANDELBROT_MIN_Y") or -1.2)
local MAX_Y = tonumber(os.getenv("MANDELBROT_MAX_Y") or 1.2)
-- Whether a pixel samples its cell's corner or its centre, and whether the step
-- divides by the pixel count or the gaps between them. Both conventions are in
-- use and they give different checksums, so neither is assumed.
local SAMPLE = os.getenv("MANDELBROT_SAMPLE") or (PROFILE == "forgo" and "cells" or "gaps")
local count = WIDTH * HEIGHT

local points = ffi.new("KsPoint[?]", count)
if PROFILE == "forgo" then
    -- Match the benchmark in forgo/examples/mandelbrot operation for operation.
    -- Each assignment through this cell is an explicit binary32 rounding point,
    -- including the precomputed grid that both timed kernels only consume.
    local cell = ffi.new("float[1]")
    local function f32(value)
        cell[0] = value
        return tonumber(cell[0])
    end

    local dx = f32(f32(3.0) / f32(WIDTH))
    local dy = f32(f32(2.4) / f32(HEIGHT))
    for row = 0, HEIGHT - 1 do
        local yOffset = f32(f32(row) * dy)
        local cy = f32(f32(-1.2) + yOffset)
        for column = 0, WIDTH - 1 do
            local xOffset = f32(f32(column) * dx)
            local cx = f32(f32(-2.0) + xOffset)
            local point = points[row * WIDTH + column]
            point.re = cx
            point.im = cy
        end
    end
else
    for row = 0, HEIGHT - 1 do
        for column = 0, WIDTH - 1 do
            local point = points[row * WIDTH + column]
            if SAMPLE == "centre" then
                point.re = MIN_X + (MAX_X - MIN_X) * (column + 0.5) / WIDTH
                point.im = MIN_Y + (MAX_Y - MIN_Y) * (row + 0.5) / HEIGHT
            elseif SAMPLE == "cells" then
                point.re = MIN_X + (MAX_X - MIN_X) * column / WIDTH
                point.im = MIN_Y + (MAX_Y - MIN_Y) * row / HEIGHT
            else
                point.re = MIN_X + (MAX_X - MIN_X) * column / (WIDTH - 1)
                point.im = MIN_Y + (MAX_Y - MIN_Y) * row / (HEIGHT - 1)
            end
        end
    end
end

--- The same recurrence in plain Lua, as the semantic oracle. Independent of the
--- kernel source: if the generated code and the ordinary Nupp body ever agreed
--- with each other but not with the algorithm, this is what would say so.
local function reference(cx, cy)
    local zx, zy, zxSquared, zySquared, iteration = 0.0, 0.0, 0.0, 0.0, 0
    while iteration < MAX_ITERATIONS do
        if zxSquared + zySquared > 4.0 then
            return iteration, 1
        end
        zy = 2.0 * zx * zy + cy
        zx = zxSquared - zySquared + cx
        zxSquared, zySquared = zx * zx, zy * zy
        iteration = iteration + 1
    end

    return iteration, 0
end

--- The binary32 recurrence, through the released fixed-width namespace. Every
--- rounding point the source asks for happens here too, so this is the oracle
--- for the explicitly binary32 kernel rather than a tolerance on the other one.
local function referenceF32(cx, cy)
    local f32 = nupp.math.f32
    cx, cy = f32.narrow(cx), f32.narrow(cy)
    local zx, zy = f32.narrow(0.0), f32.narrow(0.0)
    local zxSquared, zySquared = f32.narrow(0.0), f32.narrow(0.0)
    local iteration = 0
    while iteration < MAX_ITERATIONS do
        if f32.add(zxSquared, zySquared) > f32.narrow(4.0) then
            return iteration, 1
        end
        zy = f32.add(f32.mul(f32.mul(zx, f32.narrow(2.0)), zy), cy)
        zx = f32.add(f32.sub(zxSquared, zySquared), cx)
        zxSquared, zySquared = f32.mul(zx, zx), f32.mul(zy, zy)
        iteration = iteration + 1
    end

    return iteration, 0
end

--- The interior test the kernels use to skip points known to be in the set. It
--- changes no answer, so the oracle has to apply it too or it would disagree
--- about how many iterations an interior point took.
local function inCardioid(cx, cy)
    local x = cx - 0.25
    local ySquared = cy * cy
    local q = x * x + ySquared
    return q * (q + x) <= 0.25 * ySquared or (cx + 1.0) * (cx + 1.0) + ySquared <= 0.0625
end

local function inCardioidF32(cx, cy)
    local f32 = nupp.math.f32
    cx, cy = f32.narrow(cx), f32.narrow(cy)
    local quarter = f32.narrow(0.25)
    local x = f32.sub(cx, quarter)
    local ySquared = f32.mul(cy, cy)
    local q = f32.add(f32.mul(x, x), ySquared)
    if f32.mul(q, f32.add(q, x)) <= f32.mul(quarter, ySquared) then
        return true
    end
    local shifted = f32.add(cx, f32.narrow(1.0))

    return f32.add(f32.mul(shifted, shifted), ySquared) <= f32.narrow(0.0625)
end

local binary32 = KERNEL:find("f32", 1, true) ~= nil
-- Whether the kernel asked for fused multiply-add. A contracted body performs
-- one rounding where the source wrote two, so it is a different computation from
-- the recurrence below and cannot be required to agree with it -- that is
-- precisely what `@relax("fp-contract")` trades away, and both oracles here are
-- exact. The source is read rather than the kernel's name matched, so a body
-- that gains or loses the line is classified by what it then is.
local contracted = false
do
    local source = assert(io.open(here .. KERNEL .. ".nupp", "rb"))
    contracted = source:read("*a"):find('@relax("fp-contract")', 1, true) ~= nil
    source:close()
end
-- Reported rather than assumed: the gang width is the backend's choice from the
-- loop's own lane types, so a run says which one it actually got.
SHAPE = binary32 and "f32x8" or "f64x4"
local recurrence = binary32 and referenceF32 or reference
local interior = binary32 and inCardioidF32 or inCardioid

local function oracle(cx, cy)
    if interior(cx, cy) then
        return MAX_ITERATIONS, 0
    end

    return recurrence(cx, cy)
end

local optimized = ffi.new("KsEscape[?]", count)
local scalar = ffi.new("KsEscape[?]", count)
-- Where the ordinary Nupp body writes when it is being timed rather than
-- checked, so timing never shares a buffer with a correctness comparison.
local interpreted = ffi.new("KsEscape[?]", count)
lib.ks_mandelbrot(optimized, points, 1, count, MAX_ITERATIONS, count)
lib.ks_mandelbrot_forced_scalar(scalar, points, 1, count, MAX_ITERATIONS, count)

-- The two generated bodies are compared on every pixel: they come from one IR,
-- and the lane rewrite is exactly what is between them, so this is the check
-- that the rewrite changed no answer.
for index = 0, count - 1 do
    if optimized[index].iterations ~= scalar[index].iterations or optimized[index].escaped ~= scalar[index].escaped then
        error(
            (
                "SPMD pixel %d: scalar says %d/%d, lanes say %d/%d"
            ):format(
                index,
                scalar[index].iterations,
                scalar[index].escaped,
                optimized[index].iterations,
                optimized[index].escaped
            )
        )
    end
end

-- The ordinary Nupp body and the hand-written Lua recurrence anchor those two
-- to the language's meaning. Both run one pixel at a time, and for the
-- explicitly binary32 kernel every operation is an FFI round trip, so this is
-- bounded by count rather than run to the display size. What was checked is
-- printed rather than assumed: a silent cap would read like full coverage.
-- A prefix is the wrong sample. The first pixels of the grid are its top-left
-- corner, which escapes in a handful of iterations, so a prefix exercises
-- neither the interior nor the boundary where the escape count is decided --
-- and those are exactly where a rounding difference changes an answer. A
-- contracted binary32 body agrees over the first four thousand pixels and still
-- moves the whole-grid checksum.
--
-- So the budget is spread instead. The ordinary Nupp body takes a contiguous
-- range, so it runs over blocks placed evenly down the grid; the Lua recurrence
-- is per-pixel, so it strides across every row. Neither is a whole sweep, but
-- both cross the boundary.
local ORACLE_LIMIT = tonumber(os.getenv("MANDELBROT_ORACLE_LIMIT") or (binary32 and 20000 or count))
local oracleCount = math.min(count, ORACLE_LIMIT)

-- How far a contracted body drifted from the exact recurrence. An exact body has
-- no licence to drift at all, so any mismatch is a failure there; a contracted
-- one is counted and reported instead, because the check that a backend change
-- moved an answer is the whole-grid comparison of the two generated bodies above
-- and that one still holds either way.
local diverged = 0

local function differs(got, wantIterations, wantEscaped)
    return got.iterations ~= wantIterations or got.escaped ~= wantEscaped
end

local function compare(label, index, got)
    local wantIterations, wantEscaped = oracle(points[index].re, points[index].im)
    if not differs(got, wantIterations, wantEscaped) then
        return
    end
    if contracted then
        diverged = diverged + 1
        return
    end
    error(
        (
            "%s pixel %d (row %d, column %d): want %d/%d, got %d/%d"
        ):format(
            label,
            index,
            math.floor(index / WIDTH),
            index % WIDTH,
            wantIterations,
            wantEscaped,
            got.iterations,
            got.escaped
        )
    )
end

--- The tail shapes hold the generated bodies against the ordinary Nupp one,
--- which is exact for the same reason the oracles are.
local function compareTail(label, prefix, got, want)
    if not differs(got, want.iterations, want.escaped) then
        return
    end
    if contracted then
        diverged = diverged + 1
        return
    end
    error(("%s tail differs at count %d"):format(label, prefix))
end

local BLOCKS = 32
local blockSize = math.max(1, math.floor(oracleCount / BLOCKS))
local checkedByBlocks = 0
if oracleCount >= count then
    -- The whole grid fits the budget, so there is nothing to place.
    BLOCKS, blockSize = 1, count
end
local fallback = ffi.new("KsEscape[?]", math.max(1, blockSize))
for block = 0, BLOCKS - 1 do
    local first = math.floor(block * (count - blockSize) / math.max(1, BLOCKS - 1))
    local writer = spans.writeCarray(fallback, blockSize)
    ordinary.mandelbrot(writer, spans.fromCarray(points + first, blockSize), 1, blockSize, MAX_ITERATIONS)
    writer:drop()
    for offset = 0, blockSize - 1 do
        compare("ordinary Nupp", first + offset, fallback[offset])
        compare("SPMD C", first + offset, optimized[first + offset])
    end
    checkedByBlocks = checkedByBlocks + blockSize
end

-- Every row is crossed, so a body that is only wrong deep in the set is seen.
local stride = math.max(1, math.floor(count / oracleCount))
local checkedByStride = 0
for index = 0, count - 1, stride do
    compare("SPMD C", index, optimized[index])
    compare("scalar C", index, scalar[index])
    checkedByStride = checkedByStride + 1
end

-- Exercise every whole-group/tail shape independently of the display size.
-- The source points come from the same initialized prefix, while each output
-- starts fresh so a missed or overrun lane cannot hide behind an earlier call.
-- Covers no complete group, exact groups, and every remainder for both gang
-- widths, so a four-lane and an eight-lane tail are both exercised.
for _, prefix in ipairs({0, 1, 3, 4, 5, 7, 8, 9, 15, 16, 17, 33}) do
    if prefix <= count then
        local capacity = math.max(1, prefix)
        local expected = ffi.new("KsEscape[?]", capacity)
        local forced = ffi.new("KsEscape[?]", capacity)
        local lanes = ffi.new("KsEscape[?]", capacity)
        local writer = spans.writeCarray(expected, prefix)
        ordinary.mandelbrot(writer, spans.fromCarray(points, prefix), 1, prefix, MAX_ITERATIONS)
        writer:drop()
        lib.ks_mandelbrot_forced_scalar(forced, points, 1, prefix, MAX_ITERATIONS, prefix)
        lib.ks_mandelbrot(lanes, points, 1, prefix, MAX_ITERATIONS, prefix)
        for index = 0, prefix - 1 do
            compareTail("forced scalar", prefix, forced[index], expected[index])
            compareTail("SPMD", prefix, lanes[index], expected[index])
        end
    end
end
local checksum = 0
for index = 0, count - 1 do
    checksum = checksum + optimized[index].iterations
end
io.write(("mandelbrot: %dx%d, %d max iterations, checksum %d\n"):format(WIDTH, HEIGHT, MAX_ITERATIONS, checksum))
local resultPath = os.getenv("MANDELBROT_RESULTS")
if resultPath then
    local results = assert(io.open(resultPath, "wb"))
    assert(results:write(ffi.string(optimized, ffi.sizeof("KsEscape") * count)))
    assert(results:close())
end
local verb = contracted and "were compared with" or "agree with"
io.write(
    (
        "%d pixels agree between scalar C and SPMD C; %d in %d blocks also %s ordinary Nupp, and %d strided across every row %s the Lua oracle\n"
    ):format(count, checkedByBlocks, BLOCKS, verb, checkedByStride, verb)
)
if contracted then
    io.write(
        (
            "this kernel asks for fused multiply-add, so it computes something the exact oracles do not: %d of those comparisons diverge\n"
        ):format(diverged)
    )
end
io.write("\n")
if os.getenv("MANDELBROT_QUIET") then
    local function bench(name, run)
        for _ = 1, 3 do
            run()
        end
        local started = now()
        local passes = 0
        while now() - started < 1.0 do
            run()
            passes = passes + 1
        end
        local elapsed = (now() - started) / passes
        io.write(("%-12s %12.0f ns/frame %10.2f MPix/s\n"):format(name, elapsed * 1e9, count / elapsed / 1e6))
    end

    bench("SPMD " .. SHAPE, function()
        lib.ks_mandelbrot(optimized, points, 1, count, MAX_ITERATIONS, count)
    end)
    bench("scalar C", function()
        lib.ks_mandelbrot_forced_scalar(scalar, points, 1, count, MAX_ITERATIONS, count)
    end)
    if not os.getenv("MANDELBROT_NATIVE_ONLY") then
        bench("LuaJIT", function()
            local writer = spans.writeCarray(interpreted, count)
            ordinary.mandelbrot(writer, spans.fromCarray(points, count), 1, count, MAX_ITERATIONS)
            writer:drop()
        end)
    end
    os.exit(0)
end

local SHADES = " .:-=+*#%@"
for row = 0, HEIGHT - 1 do
    local line = {}
    for column = 0, WIDTH - 1 do
        local cell = optimized[row * WIDTH + column]
        if cell.escaped == 0 then
            line[#line + 1] = "@"
        else
            local shade = math.floor(math.log(cell.iterations + 1) / math.log(MAX_ITERATIONS + 1) * 9)
            line[#line + 1] = SHADES:sub(shade + 1, shade + 1)
        end
    end
    io.write(table.concat(line), "\n")
end

-- Timing is a sanity check rather than a gate: one call over the whole grid,
-- against the same recurrence interpreted by LuaJIT.
local function timed(name, run, pixels)
    pixels = pixels or count
    for _ = 1, 3 do
        run()
    end
    local started = now()
    local passes = 0
    while now() - started < 0.25 do
        run()
        passes = passes + 1
    end
    local elapsed = (now() - started) / passes
    io.write(
        (
            "\n%-22s %8.3f ms  %10.1f Mpixel/s%s"
        ):format(
            name,
            elapsed * 1000,
            pixels / elapsed / 1e6,
            pixels ~= count and (" (over %d pixels)"):format(pixels) or ""
        )
    )
end

timed("AOT SPMD " .. SHAPE, function()
    lib.ks_mandelbrot(optimized, points, 1, count, MAX_ITERATIONS, count)
end)
timed("forced-scalar C", function()
    lib.ks_mandelbrot_forced_scalar(scalar, points, 1, count, MAX_ITERATIONS, count)
end)
-- The same function with AOT off, so the three rows differ in how the body was
-- compiled and in nothing else. Timing the bare recurrence instead would drop
-- the interior test the compiled bodies run, which is most of the work on this
-- view, and would report LuaJIT as slower than it is.
--
-- The ordinary body for the binary32 program performs every rounding point
-- through an FFI store and load, so it is timed over a sample and reported as a
-- per-pixel rate. That cost is the price of the explicitly binary32 source, not
-- an artifact of measuring it: it is what this program costs with AOT off.
--
-- The sample is spread the way the oracle sweep is, and for the same reason. A
-- prefix of this grid is its top-left corner, where every pixel escapes in a
-- handful of iterations, so a rate measured there is one the rest of the grid
-- never sees -- about three times the spread one. The ordinary body takes a
-- contiguous range, so the sample is blocks placed evenly down the grid rather
-- than a stride.
local LUA_BLOCKS = 32
local luaPixels = binary32 and math.min(count, 20000) or count
local luaBlock, luaStarts = count, {0}
if luaPixels < count then
    luaBlock = math.max(1, math.floor(luaPixels / LUA_BLOCKS))
    luaStarts = {}
    for block = 0, LUA_BLOCKS - 1 do
        luaStarts[#luaStarts + 1] = math.floor(block * (count - luaBlock) / math.max(1, LUA_BLOCKS - 1))
    end
end
timed(
    "LuaJIT",
    function()
        for _, first in ipairs(luaStarts) do
            local writer = spans.writeCarray(interpreted, luaBlock)
            ordinary.mandelbrot(writer, spans.fromCarray(points + first, luaBlock), 1, luaBlock, MAX_ITERATIONS)
            writer:drop()
        end
    end,
    #luaStarts * luaBlock
)
io.write("\n")
