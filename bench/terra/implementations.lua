-- The four implementations this benchmark compares, loaded into one process so
-- every sample is colocated: same machine, same run, interleaved.
--
-- Paths are relative to this directory, which `run.sh`, `benchmark.lua` and
-- `tests/run.lua` are all run from. The two Nupp builds declare the same module
-- name and only one of them can own it, so the compiled build is required and
-- the LuaJIT build is loaded by path -- the same arrangement `bench/sha256`
-- uses, and for the same reason.
local ffi = require("ffi")

local spans = require("nupp.mem.span")

local implementations = {}

-- One set of declarations for both native libraries. Each is loaded separately
-- and reached through its own namespace, so the shared names below resolve
-- inside whichever library the call went through.
ffi.cdef [[
typedef struct { int32_t iterations; uint32_t escaped; } TbEscape;
typedef struct { float re; float im; } TbPoint;
typedef struct { float x; float y; float vx; float vy; } TbBody;

void tbMandelbrot(TbEscape *escapes, const TbPoint *points,
   int32_t maxIterations, size_t count);
void tbAdvance(TbBody *output, const TbBody *input,
   double dt, double drag, size_t count);
double tbSumSquares(const double *values, size_t count);
void tbMix(uint32_t *output, const uint32_t *input, size_t count);
]]

local suffix = ffi.os == "OSX" and "dylib" or ffi.os == "Windows" and "dll" or "so"

--- The `@aot` entries, compiled by the `terra-bench` target.
local aot = require("kernels")

--- The same Nupp source built by `terra-bench-scalar`, left to LuaJIT.
local scalar = assert(
   loadfile("build/scalar/kernels.lua"),
   "build the terra-bench-scalar target first"
)()

--- The Terra kernels, compiled by `terra/kernels.t` through Terra's own LLVM
--- pipeline and reached over the same FFI boundary as the C control.
local terra = ffi.load("build/terra/libterrakernels." .. suffix)

--- The C control, built by the `terra_bench_control` dependency at `-O3`.
local control = ffi.load("build/aot/lib/libterra_bench_control." .. suffix)

--- Reported in this order everywhere, so two runs read the same way.
implementations.order = {"aot", "scalar", "terra", "c"}

implementations.titles = {
   aot = "Nupp @aot",
   scalar = "Nupp on LuaJIT",
   terra = "Terra",
   c = "C",
}

-- The four kernels, each with the memory it works over, the four ways of
-- running it, and a checksum the differential test reads answers out of.
--
-- Spans are built once, outside everything timed. A caller that holds an array
-- holds the span over it, so rebuilding one per call would be measuring the
-- wrapper rather than the kernel -- and it would be a cost only the two Nupp
-- routes paid.
local kernels = {}

--- Escape counts over a strip of the complex plane.
---
--- `maxIterations` is deliberately low. A high bound spends nearly all of the
--- time on interior points, which run the loop to the end and never take the
--- escape branch, and that measures one straight-line arithmetic chain instead
--- of the mixture of exits a real image has.
kernels[#kernels + 1] = {
   name = "mandelbrot",
   unit = "Mpixel/s",
   counts = {1024, 262144},
   maxIterations = 64,

   allocate = function(self, count)
      local points = ffi.new("TbPoint[?]", count)
      local output = ffi.new("TbEscape[?]", count)
      -- A raster scan of the interesting part of the plane, in rows, the way
      -- an image is actually laid out.
      --
      -- Not a scrambled walk over the same region, which an earlier draft used.
      -- It sampled the same mixture of fast and slow pixels, so it looked
      -- equivalent, and it was not: a lane-parallel body runs a group of four
      -- until the last of them escapes, so scattering neighbours costs it the
      -- whole of what lanes are for. Nupp lowers this kernel four lanes wide
      -- and neither C nor Terra vectorizes it at all, so the scrambled order
      -- was quietly measuring the one implementation's optimization against
      -- data chosen to defeat it. Neighbouring pixels belong next to each
      -- other, and here they are.
      local width = math.ceil(math.sqrt(count))
      local height = math.ceil(count / width)
      for i = 0, count - 1 do
         local column = i % width
         local row = math.floor(i / width)
         points[i].re = -2.1 + 3.0 * column / math.max(1, width - 1)
         points[i].im = -1.2 + 2.4 * row / math.max(1, height - 1)
      end
      return {
         count = count,
         points = points,
         output = output,
         reader = spans.fromCarray(points, count),
         writer = spans.writeCarray(output, count),
      }
   end,

   checksum = function(self, work)
      local total = 0
      for i = 0, work.count - 1 do
         total = (total + work.output[i].iterations * 31 + work.output[i].escaped) % 2147483647
      end
      return total
   end,

   clear = function(self, work)
      ffi.fill(work.output, ffi.sizeof("TbEscape") * work.count)
   end,

   calls = {
      aot = function(work, kernel)
         aot.mandelbrot(work.writer, work.reader, kernel.maxIterations)
      end,
      scalar = function(work, kernel)
         scalar.mandelbrot(work.writer, work.reader, kernel.maxIterations)
      end,
      terra = function(work, kernel)
         terra.tbMandelbrot(work.output, work.points, kernel.maxIterations, work.count)
      end,
      c = function(work, kernel)
         control.tbMandelbrot(work.output, work.points, kernel.maxIterations, work.count)
      end,
   },
}

--- One Euler step over an array of bodies.
kernels[#kernels + 1] = {
   name = "advance",
   unit = "Melement/s",
   counts = {1024, 262144},
   dt = 0.015625,
   drag = 0.998046875,

   allocate = function(self, count)
      local input = ffi.new("TbBody[?]", count)
      local output = ffi.new("TbBody[?]", count)
      for i = 0, count - 1 do
         input[i].x = i * 0.5
         input[i].y = i * -0.25
         input[i].vx = ((i % 97) - 48) * 0.125
         input[i].vy = ((i % 89) - 44) * 0.0625
      end
      return {count = count, input = input, output = output,
         reader = spans.fromCarray(input, count),
         writer = spans.writeCarray(output, count)}
   end,

   checksum = function(self, work)
      local parts = {}
      for i = 0, work.count - 1 do
         parts[#parts + 1] = ("%a %a %a %a"):format(
            work.output[i].x, work.output[i].y, work.output[i].vx, work.output[i].vy)
      end
      return table.concat(parts, ";")
   end,

   clear = function(self, work)
      ffi.fill(work.output, ffi.sizeof("TbBody") * work.count)
   end,

   calls = {
      aot = function(work, kernel)
         aot.advance(work.writer, work.reader, kernel.dt, kernel.drag)
      end,
      scalar = function(work, kernel)
         scalar.advance(work.writer, work.reader, kernel.dt, kernel.drag)
      end,
      terra = function(work, kernel)
         terra.tbAdvance(work.output, work.input, kernel.dt, kernel.drag, work.count)
      end,
      c = function(work, kernel)
         control.tbAdvance(work.output, work.input, kernel.dt, kernel.drag, work.count)
      end,
   },
}

--- The sum of the squares of one span.
kernels[#kernels + 1] = {
   name = "sumSquares",
   unit = "Melement/s",
   -- The single-element row is how this benchmark prices its own call
   -- boundary. Every route is reached differently -- the compiled entry
   -- through its generated binding, the LuaJIT route as an ordinary Lua call,
   -- Terra and C over FFI -- and one element leaves almost nothing in the call
   -- but the call, so its nanoseconds are what the small sizes above are
   -- standing on.
   counts = {1, 1024, 262144},

   allocate = function(self, count)
      local values = ffi.new("double[?]", count)
      for i = 0, count - 1 do
         values[i] = ((i % 1021) - 510) * 0.0009765625
      end
      return {count = count, values = values, result = 0,
         reader = spans.fromCarray(values, count)}
   end,

   checksum = function(self, work)
      return ("%a"):format(work.result)
   end,

   clear = function(self, work)
      work.result = 0
   end,

   calls = {
      aot = function(work) work.result = aot.sumSquares(work.reader) end,
      scalar = function(work) work.result = scalar.sumSquares(work.reader) end,
      terra = function(work) work.result = terra.tbSumSquares(work.values, work.count) end,
      c = function(work) work.result = control.tbSumSquares(work.values, work.count) end,
   },
}

--- Four rounds of xorshift over each element.
kernels[#kernels + 1] = {
   name = "mix",
   unit = "Melement/s",
   counts = {1024, 262144},

   allocate = function(self, count)
      local input = ffi.new("uint32_t[?]", count)
      local output = ffi.new("uint32_t[?]", count)
      for i = 0, count - 1 do
         -- Never zero: xorshift fixes zero, and a span of them would measure
         -- the same arithmetic on a value no caller has.
         input[i] = i * 2654435761 + 1
      end
      return {count = count, input = input, output = output,
         reader = spans.fromCarray(input, count),
         writer = spans.writeCarray(output, count)}
   end,

   checksum = function(self, work)
      local parts = {}
      for i = 0, work.count - 1 do
         parts[#parts + 1] = ("%08x"):format(work.output[i])
      end
      return table.concat(parts)
   end,

   clear = function(self, work)
      ffi.fill(work.output, 4 * work.count)
   end,

   calls = {
      aot = function(work) aot.mix(work.writer, work.reader) end,
      scalar = function(work) scalar.mix(work.writer, work.reader) end,
      terra = function(work) terra.tbMix(work.output, work.input, work.count) end,
      c = function(work) control.tbMix(work.output, work.input, work.count) end,
   },
}

implementations.kernels = kernels

return implementations
