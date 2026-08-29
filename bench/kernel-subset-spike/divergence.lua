-- How much work a gang wastes on a divergent loop.
--
-- Every lane in a gang runs until the last lane in that gang retires, so the
-- gang executes max(iterations) over its lanes rather than the average. Widening
-- the gang takes that maximum over more pixels, and a maximum over more samples
-- is larger. This measures the effect on the real grid rather than assuming it:
-- it is the difference between the lane-iterations a gang actually executes and
-- the pixel-iterations the answer needed.
--
-- The ceiling this reports is what the eight-lane body can be against the
-- four-lane one, and it is not 2.00x. At cap 256 on this view it is 1.68x, and
-- the measured ratio is about 1.60x -- so the lowering runs at roughly 95 percent
-- of what the algorithm allows, and the remainder is the per-pixel gather and
-- scatter, which costs the same however many lanes share it.
local ffi = require("ffi")

local here = assert(debug.getinfo(1, "S").source:match("^@(.*[/\\])"))
local OUT = here .. "build/mandelbrot_f32/"

ffi.cdef [[
typedef struct { int32_t iterations; uint32_t escaped; } KsEscape;
typedef struct { float re; float im; } KsPoint;
void ks_mandelbrot(KsEscape *escapes, const KsPoint *points,
   double first, double last, int32_t maxIterations, size_t count);
]]

local lib = ffi.load(OUT .. (jit.os == "OSX" and "libmandelbrot_f32.dylib" or "libmandelbrot_f32.so"))

local WIDTH = tonumber(os.getenv("MANDELBROT_WIDTH") or 1024)
local HEIGHT = tonumber(os.getenv("MANDELBROT_HEIGHT") or 768)
local MAX_ITERATIONS = tonumber(os.getenv("MANDELBROT_ITERATIONS") or 256)
local MIN_X, MAX_X = -2.2, 0.9
local MIN_Y, MAX_Y = -1.2, 1.2

local count = WIDTH * HEIGHT
local points = ffi.new("KsPoint[?]", count)
for row = 0, HEIGHT - 1 do
   for column = 0, WIDTH - 1 do
      local point = points[row * WIDTH + column]
      point.re = MIN_X + (MAX_X - MIN_X) * (column + 0.5) / WIDTH
      point.im = MIN_Y + (MAX_Y - MIN_Y) * (row + 0.5) / HEIGHT
   end
end

local escapes = ffi.new("KsEscape[?]", count)
lib.ks_mandelbrot(escapes, points, 1, count, MAX_ITERATIONS, count)

-- What a pixel actually cost the loop, which is not what it reports.
--
-- The kernel's interior test sets `iterations` to the cap for a point inside the
-- main cardioid or the period-2 bulb, and then the loop runs zero times for it.
-- A point that genuinely iterated to the cap reports the same number, so the
-- output cannot tell them apart and this test has to be repeated here.
--
-- Reading the reported count instead treats the whole cardioid as maximally
-- expensive. That is not a small error: the cardioid is contiguous and covers a
-- large part of this view, so it makes every gang that touches it look equally
-- slow at four lanes and at eight, and hides exactly the divergence that
-- widening the gang introduces.
local function interior(cx, cy)
   local shifted = cx - 0.25
   local ySquared = cy * cy
   local q = shifted * shifted + ySquared
   if q * (q + shifted) <= 0.25 * ySquared then return true end

   return (cx + 1.0) * (cx + 1.0) + ySquared <= 0.0625
end

local cost = ffi.new("int32_t[?]", count)
for index = 0, count - 1 do
   local point = points[index]
   cost[index] = interior(point.re, point.im) and 0 or escapes[index].iterations
end

--- Lane-iterations a gang of `lanes` executes: each whole gang runs its slowest
--- lane's count, once, for every lane in it.
local function executed(lanes)
   local total = 0
   local index = 0
   while index + lanes <= count do
      local slowest = 0
      for lane = 0, lanes - 1 do
         local iterations = cost[index + lane]
         if iterations > slowest then slowest = iterations end
      end
      total = total + slowest * lanes
      index = index + lanes
   end
   -- The scalar tail runs each remaining pixel for exactly its own count.
   while index < count do
      total = total + cost[index]
      index = index + 1
   end

   return total
end

local needed = 0
for index = 0, count - 1 do needed = needed + cost[index] end

io.write(("grid %dx%d, cap %d, %d pixels\n"):format(WIDTH, HEIGHT, MAX_ITERATIONS, count))
io.write(("%-8s %14s %14s %8s\n"):format("lanes", "executed", "needed", "waste"))
for _, lanes in ipairs({1, 2, 4, 8, 16}) do
   local ran = executed(lanes)
   io.write(("%-8d %14d %14d %7.2fx\n"):format(lanes, ran, needed, ran / needed))
end
local four, eight = executed(4), executed(8)
io.write(("\neight lanes execute %.3fx the lane-iterations four do\n"):format(eight / four))
io.write(("so the iteration loop's ceiling is 2 / %.3f = %.2fx, not 2.00x\n")
   :format(eight / four, 2 / (eight / four)))
