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
local OUT = here .. "build/mandelbrot/"
package.path = OUT .. "fallback/?.lua;" .. OUT .. "fallback/?/init.lua;" .. package.path

local ordinary = require("mandelbrot")
local spans = require("nupp.span")

ffi.cdef [[
typedef struct { int32_t iterations; uint32_t escaped; } KsEscape;
typedef struct { float re; float im; } KsPoint;
void ks_mandelbrot(KsEscape *escapes, const KsPoint *points,
   double first, double last, int32_t maxIterations, size_t count);
void ks_mandelbrot_forced_scalar(KsEscape *escapes, const KsPoint *points,
   double first, double last, int32_t maxIterations, size_t count);
]]

local lib = ffi.load(OUT .. (jit.os == "OSX" and "libmandelbrot.dylib" or "libmandelbrot.so"))

local WIDTH = tonumber(os.getenv("MANDELBROT_WIDTH") or 78)
local HEIGHT = tonumber(os.getenv("MANDELBROT_HEIGHT") or 30)
local MAX_ITERATIONS = tonumber(os.getenv("MANDELBROT_ITERATIONS") or 500)
local MIN_X = tonumber(os.getenv("MANDELBROT_MIN_X") or -2.2)
local MAX_X = tonumber(os.getenv("MANDELBROT_MAX_X") or 0.9)
local MIN_Y = tonumber(os.getenv("MANDELBROT_MIN_Y") or -1.2)
local MAX_Y = tonumber(os.getenv("MANDELBROT_MAX_Y") or 1.2)
-- Whether a pixel samples its cell's corner or its centre, and whether the step
-- divides by the pixel count or the gaps between them. Both conventions are in
-- use and they give different checksums, so neither is assumed.
local SAMPLE = os.getenv("MANDELBROT_SAMPLE") or "gaps"
local count = WIDTH * HEIGHT

local points = ffi.new("KsPoint[?]", count)
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

--- The same recurrence in plain Lua, as the semantic oracle.
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

local optimized = ffi.new("KsEscape[?]", count)
local scalar = ffi.new("KsEscape[?]", count)
local fallback = ffi.new("KsEscape[?]", count)
lib.ks_mandelbrot(optimized, points, 1, count, MAX_ITERATIONS, count)
lib.ks_mandelbrot_forced_scalar(scalar, points, 1, count, MAX_ITERATIONS, count)
local fallbackWriter = spans.writeCarray(fallback, count)
ordinary.mandelbrot(fallbackWriter, spans.fromCarray(points, count), 1, count, MAX_ITERATIONS)
fallbackWriter:commit()

for index = 0, count - 1 do
   local wantIterations, wantEscaped = reference(points[index].re, points[index].im)
   for label, got in pairs({
      optimized = optimized[index], scalar = scalar[index], fallback = fallback[index],
   }) do
      if got.iterations ~= wantIterations or got.escaped ~= wantEscaped then
         error(("%s pixel %d: want %d/%d, got %d/%d"):format(
            label, index, wantIterations, wantEscaped, got.iterations, got.escaped))
      end
   end
end

-- Exercise every whole-group/tail shape independently of the display size.
-- The source points come from the same initialized prefix, while each output
-- starts fresh so a missed or overrun lane cannot hide behind an earlier call.
for _, prefix in ipairs({0, 1, 3, 4, 5, 7, 8, 33}) do
   if prefix <= count then
      local capacity = math.max(1, prefix)
      local expected = ffi.new("KsEscape[?]", capacity)
      local forced = ffi.new("KsEscape[?]", capacity)
      local lanes = ffi.new("KsEscape[?]", capacity)
      local writer = spans.writeCarray(expected, prefix)
      ordinary.mandelbrot(writer, spans.fromCarray(points, prefix), 1, prefix, MAX_ITERATIONS)
      writer:commit()
      lib.ks_mandelbrot_forced_scalar(forced, points, 1, prefix, MAX_ITERATIONS, prefix)
      lib.ks_mandelbrot(lanes, points, 1, prefix, MAX_ITERATIONS, prefix)
      for index = 0, prefix - 1 do
         assert(forced[index].iterations == expected[index].iterations
            and forced[index].escaped == expected[index].escaped,
            "forced scalar tail differs at count " .. prefix)
         assert(lanes[index].iterations == expected[index].iterations
            and lanes[index].escaped == expected[index].escaped,
            "SPMD tail differs at count " .. prefix)
      end
   end
end
local checksum = 0
for index = 0, count - 1 do
   checksum = checksum + optimized[index].iterations
end
io.write(("mandelbrot: %dx%d, %d max iterations, checksum %d\n")
   :format(WIDTH, HEIGHT, MAX_ITERATIONS, checksum))
io.write(("%d pixels agree across ordinary Nupp, scalar C, and SPMD C\n\n"):format(count))
if os.getenv("MANDELBROT_QUIET") then
   local function bench(name, run)
      for _ = 1, 3 do run() end
      local started = os.clock()
      local passes = 0
      while os.clock() - started < 1.0 do
         run()
         passes = passes + 1
      end
      local elapsed = (os.clock() - started) / passes
      io.write(("%-12s %12.0f ns/frame %10.2f MPix/s\n")
         :format(name, elapsed * 1e9, count / elapsed / 1e6))
   end

   bench("SPMD f64x4", function()
      lib.ks_mandelbrot(optimized, points, 1, count, MAX_ITERATIONS, count)
   end)
   bench("scalar C", function()
      lib.ks_mandelbrot_forced_scalar(scalar, points, 1, count, MAX_ITERATIONS, count)
   end)
   bench("LuaJIT", function()
      local total = 0
      for index = 0, count - 1 do
         total = total + reference(points[index].re, points[index].im)
      end

      return total
   end)
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
local function timed(name, run)
   for _ = 1, 3 do run() end
   local started = os.clock()
   local passes = 0
   while os.clock() - started < 0.25 do
      run()
      passes = passes + 1
   end
   local elapsed = (os.clock() - started) / passes
   io.write(("\n%-22s %8.3f ms  %10.1f Mpixel/s")
      :format(name, elapsed * 1000, count / elapsed / 1e6))
end

timed("AOT SPMD f64x4", function()
   lib.ks_mandelbrot(optimized, points, 1, count, MAX_ITERATIONS, count)
end)
timed("forced-scalar C", function()
   lib.ks_mandelbrot_forced_scalar(scalar, points, 1, count, MAX_ITERATIONS, count)
end)
timed("LuaJIT", function()
   local total = 0
   for index = 0, count - 1 do
      local iterations = reference(points[index].re, points[index].im)
      total = total + iterations
   end

   return total
end)
io.write("\n")
