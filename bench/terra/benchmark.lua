-- Measures the four implementations in `implementations.lua` against each
-- other, on kernels chosen to disagree about what makes code fast.
--
-- The protocol is the one `bench/sha256` and `bench/simd-json` use.
-- Implementations alternate within a sample so a machine that drifts drifts
-- through all of them equally, each sample is a ratio against the colocated C
-- control before anything is averaged, and the reported interval is a bootstrap
-- over those paired ratios rather than a spread of raw times.
--
--    luajit benchmark.lua [--json] [SAMPLES]
--
-- Run it through `run.sh --bench`, which builds all four and sets the paths.
local ffi = require("ffi")
local implementations = require("implementations")

io.stdout:setvbuf("no")

-- The clock `bench/kernel-subset-spike` settled on, and its reasoning applies
-- here unchanged: `os.clock` reports processor time, so a run that loses the
-- CPU reads as faster the busier the machine is.
local now = dofile("../kernel-subset-spike/wallclock.lua")

local jsonOutput = arg[1] == "--json"
local samples = tonumber(arg[jsonOutput and 2 or 1]) or 15
local warmups = 4

-- How long one sample should take. Call counts are calibrated per kernel, per
-- size and per implementation to hit it, because the implementations here are
-- two orders of magnitude apart at the extremes: an element budget that gives
-- the compiled routes a reasonable sample leaves the interpreted one running
-- for minutes. Samples therefore record throughput rather than elapsed time,
-- and the ratios below are ratios of throughput.
local sampleSeconds = tonumber(os.getenv("NUPP_TERRA_BENCH_SECONDS")) or 0.05

local function median(values)
   local sorted = {}
   for index = 1, #values do
      sorted[index] = values[index]
   end
   table.sort(sorted)
   local middle = #sorted / 2
   if #sorted % 2 == 1 then
      return sorted[math.ceil(middle)]
   end
   return (sorted[middle] + sorted[middle + 1]) / 2
end

local function percentile(values, fraction)
   local sorted = {}
   for index = 1, #values do
      sorted[index] = values[index]
   end
   table.sort(sorted)
   local at = math.max(1, math.min(#sorted, math.ceil(fraction * #sorted)))
   return sorted[at]
end

--- A bootstrap over the paired ratios, resampled with a fixed seed so two runs
--- of the same data report the same interval.
local function bootstrapSummary(ratios)
   local bootstrap = {}
   local state = 104729
   for sample = 1, 2000 do
      local resampled = {}
      for index = 1, #ratios do
         state = state * 48271 % 2147483647
         resampled[index] = ratios[state % #ratios + 1]
      end
      bootstrap[sample] = median(resampled)
   end
   return {
      median = median(ratios),
      low95 = percentile(bootstrap, 0.025),
      high95 = percentile(bootstrap, 0.975),
   }
end

local function ratioSummary(numerator, denominator)
   local ratios = {}
   for index = 1, #numerator do
      ratios[index] = numerator[index] / denominator[index]
   end
   return bootstrapSummary(ratios)
end

local function command(line)
   local handle = io.popen(line .. " 2>/dev/null")
   if not handle then
      return nil
   end
   local text = handle:read("*a")
   handle:close()
   return (text:gsub("%s+$", ""):gsub("\n.*", ""))
end

--- How many calls take about `sampleSeconds`.
---
--- Doubles from one call until the measurement is long enough to mean
--- something, so an implementation a hundred times slower than another is
--- measured over a hundred times fewer calls rather than over a hundred times
--- the wall clock.
local function calibrate(run)
   local calls = 1
   while true do
      local started = now()
      for _ = 1, calls do
         run()
      end
      local elapsed = now() - started
      if elapsed >= sampleSeconds or calls >= 100000000 then
         return calls
      end
      calls = math.max(calls * 2, math.ceil(calls * sampleSeconds / math.max(elapsed, 1e-6)))
   end
end

local report = {
   schema = 1,
   samples = samples,
   warmups = warmups,
   environment = {
      os = ffi.os,
      arch = ffi.arch,
      jit = jit.version,
      cc = command("cc --version"),
      terra = command("./vendor/terra-*/bin/terra -e 'print(terralib.version)'"),
      uname = command("uname -a"),
   },
   rows = {},
}

for _, kernel in ipairs(implementations.kernels) do
   for _, count in ipairs(kernel.counts) do
      -- Every implementation gets its own memory. Sharing one output buffer
      -- would let whichever ran first leave the cache warm for the next, and
      -- the order is fixed, so that warmth would land on the same
      -- implementation every sample.
      --
      -- And each gets several copies of it, cycled through by the timing loop,
      -- because one buffer called over and over is not what a caller does and
      -- is not what LuaJIT measures either. Everything the Nupp source derives
      -- from its argument is loop-invariant then, and the recorder hoists the
      -- whole call out of the loop: the single-element `sumSquares` row read as
      -- 0.2 ns and three times the speed of C, which is less than one call.
      -- The copies hold identical bytes and differ only in address, so every
      -- call still does exactly the same work -- what they deny the recorder is
      -- the proof that it already has the answer.
      --
      -- Few enough that the set does not become the thing being measured. The
      -- large sizes are past every cache either way, and four copies of a small
      -- one is still a small working set.
      local copies = count <= 65536 and 4 or 2
      local work = {}
      for _, name in ipairs(implementations.order) do
         work[name] = {}
         for copy = 1, copies do
            work[name][copy] = kernel:allocate(count)
         end
      end

      -- Every implementation must agree before any of them is timed. This
      -- repeats what `tests/run.lua` establishes over many more sizes, on
      -- exactly the buffers about to be measured, because a benchmark that
      -- only measures is a benchmark that can reward a wrong answer.
      local expected
      for _, name in ipairs(implementations.order) do
         for copy = 1, copies do
            kernel:clear(work[name][copy])
            kernel.calls[name](work[name][copy], kernel)
            local answer = kernel:checksum(work[name][copy])
            expected = expected or answer
            assert(answer == expected, ("%s disagrees on %s at %d elements"):format(
               name, kernel.name, count))
         end
      end

      -- One monomorphic loop per implementation, built here rather than shared
      -- through a callback: a single parameterised runner is polymorphic at its
      -- call site and makes LuaJIT's trace choice depend on which
      -- implementation happened to warm first. Each gets its own call count, so
      -- a sample is a comparable slice of wall clock rather than a comparable
      -- slice of work.
      local runners, callsFor = {}, {}
      for _, name in ipairs(implementations.order) do
         local call = kernel.calls[name]
         local mine = work[name]
         local run = function(calls)
            for index = 1, calls do
               call(mine[(index % copies) + 1], kernel)
            end
         end
         local calls = calibrate(function() run(1) end)
         callsFor[name] = calls
         runners[name] = function()
            local started = now()
            run(calls)
            return count * calls / (now() - started) / 1000000
         end
      end

      for _ = 1, warmups do
         for _, name in ipairs(implementations.order) do
            runners[name]()
         end
      end

      local rates = {}
      for _, name in ipairs(implementations.order) do
         rates[name] = {}
      end
      for sample = 1, samples do
         for _, name in ipairs(implementations.order) do
            rates[name][sample] = runners[name]()
         end
      end

      local record = {
         kernel = kernel.name,
         elements = count,
         unit = kernel.unit,
         copies = copies,
         calls = callsFor,
         elementsPerSecond = rates,
         throughput = {},
         nanosecondsPerCall = {},
         versusControl = {},
      }
      for _, name in ipairs(implementations.order) do
         local rate = median(rates[name])
         record.throughput[name] = rate
         record.nanosecondsPerCall[name] = count / rate * 1000
         record.versusControl[name] = ratioSummary(rates[name], rates.c)
      end
      report.rows[#report.rows + 1] = record

      if not jsonOutput then
         io.write(("\n%s, %d %s\n"):format(
            kernel.name, count, count == 1 and "element" or "elements"))
         io.write(("  %-16s %14s %14s %10s\n")
            :format("implementation", kernel.unit, "ns/call", "vs C"))
         for _, name in ipairs(implementations.order) do
            io.write(("  %-16s %14.1f %14.1f %9.3fx\n"):format(
               implementations.titles[name],
               record.throughput[name],
               record.nanosecondsPerCall[name],
               record.versusControl[name].median))
         end
      end
   end
end

if jsonOutput then
   -- A small serializer rather than a dependency: this file is run by the
   -- repository's LuaJIT with nothing on the path but the two Nupp builds.
   local function encode(value, indent)
      local kind = type(value)
      if kind == "number" then
         return (value ~= value or value == math.huge or value == -math.huge)
            and "null" or ("%.17g"):format(value)
      elseif kind == "boolean" then
         return tostring(value)
      elseif kind == "string" then
         return ("%q"):format(value):gsub("\\\n", "\\n")
      elseif kind == "nil" then
         return "null"
      end

      local nested = indent .. "  "
      if value[1] ~= nil or next(value) == nil then
         local parts = {}
         for index = 1, #value do
            parts[index] = nested .. encode(value[index], nested)
         end
         return #parts == 0 and "[]"
            or "[\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "]"
      end

      local keys = {}
      for key in pairs(value) do
         keys[#keys + 1] = key
      end
      table.sort(keys)
      local parts = {}
      for index = 1, #keys do
         parts[index] = nested .. ("%q"):format(keys[index]) .. ": "
            .. encode(value[keys[index]], nested)
      end
      return "{\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "}"
   end

   local text = encode(report, "") .. "\n"
   local destination = os.getenv("NUPP_TERRA_BENCH_OUTPUT")
   if destination then
      local handle = assert(io.open(destination, "w"))
      handle:write(text)
      handle:close()
   else
      io.write(text)
   end
end
