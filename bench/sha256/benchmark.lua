-- Measures the four SHA-256 implementations in `implementations.lua` against
-- each other, on payloads chosen to separate the two costs a digest has: the
-- per-byte compression, and the fixed cost of one call.
--
-- The protocol is the one `bench/simd-json` uses. Implementations alternate
-- within a sample so a machine that drifts drifts through all of them equally,
-- each sample is a ratio against the colocated C control before anything is
-- averaged, and the reported interval is a bootstrap over those paired ratios
-- rather than a spread of raw times.
--
--    luajit benchmark.lua [--json] [SAMPLES]
--
-- Run it through `run.sh`, which builds both targets and sets the paths.
local ffi = require("ffi")
local implementations = require("implementations")

io.stdout:setvbuf("no")

local jsonOutput = arg[1] == "--json"
local samples = tonumber(arg[jsonOutput and 2 or 1]) or 15
local warmups = 4

-- How long one sample should take. Call counts are calibrated per payload and
-- per implementation to hit it, because the implementations here are two and a
-- half orders of magnitude apart: a byte budget that gives the C control a
-- reasonable sample leaves the interpreted one running for minutes. Samples
-- therefore record throughput rather than elapsed time, and the ratios below
-- are ratios of throughput.
local sampleSeconds = tonumber(os.getenv("NUPP_SHA256_BENCH_SECONDS")) or 0.05

local function filler(length)
   local piece = "the quick brown fox jumps over the lazy dog 0123456789\n"
   local text = piece:rep(math.ceil(length / #piece))
   return text:sub(1, length)
end

-- Distinct payloads of one size, cycled through by the timing loop.
--
-- One payload hashed over and over is not what a caller does, and it is not
-- what LuaJIT measures either: everything an implementation derives from the
-- argument is loop-invariant then, and the recorder hoists it out of the loop.
-- That hid the whole of `nupp.data.digest`'s caller-side padding -- about sixty
-- nanoseconds of a three-hundred-nanosecond call -- and reported the 32-byte
-- row some twenty-five percent faster than the same code hashing different
-- bytes each time.
--
-- Enough of them that no implementation can carry work between calls, bounded
-- so the set itself does not become the thing being measured: four megabytes,
-- which leaves the large payloads a handful and the short ones plenty.
local function variants(length)
   local count = math.max(4, math.min(64, math.floor(4194304 / length)))
   local made = {}
   for index = 1, count do
      local stamp = ("%08d"):format(index)
      local body = filler(length)
      made[index] = #body <= #stamp and stamp:sub(1, #body) or stamp .. body:sub(#stamp + 1)
   end
   return made
end

local payloads = {
   {name = "32B", sources = variants(32)},
   {name = "1KiB", sources = variants(1024)},
   {name = "64KiB", sources = variants(65536)},
   {name = "1MiB", sources = variants(1048576)},
}

local function command(commandLine)
   local pipe = io.popen(commandLine .. " 2>/dev/null")
   if not pipe then
      return "unavailable"
   end
   local value = pipe:read("*l") or "unavailable"
   pipe:close()
   return value
end

local function sorted(values)
   local copy = {}
   for index, value in ipairs(values) do
      copy[index] = value
   end
   table.sort(copy)
   return copy
end

local function median(values)
   local ordered = sorted(values)
   local middle = math.floor(#ordered / 2) + 1
   if #ordered % 2 == 1 then
      return ordered[middle]
   end
   return (ordered[middle - 1] + ordered[middle]) * 0.5
end

local function percentile(values, fraction)
   local ordered = sorted(values)
   local position = math.max(1, math.min(#ordered, math.ceil(#ordered * fraction)))
   return ordered[position]
end

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

--- How many calls of `sha256` over `source` take about `sampleSeconds`.
---
--- Doubles from one call until the measurement is long enough to mean
--- something, so an implementation that is 500 times slower than another is
--- measured over 500 times fewer calls rather than over 500 times the wall
--- clock.
local function calibrate(sha256, sources)
   local count = #sources
   local calls = 1
   while true do
      local started = os.clock()
      for index = 1, calls do
         sha256(sources[(index % count) + 1])
      end
      local elapsed = os.clock() - started
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
      uname = command("uname -a"),
   },
   payloads = {},
}

for _, payload in ipairs(payloads) do
   local sources = payload.sources
   local count = #sources
   local length = #sources[1]

   -- Every implementation must agree before any of them is timed. A fast wrong
   -- answer is the failure mode a benchmark is most likely to reward. Every
   -- payload in the set, since the set is what gets hashed.
   for _, source in ipairs(sources) do
      local expected = implementations.c(source)
      for _, name in ipairs(implementations.order) do
         local answer = implementations[name](source)
         assert(answer == expected, ("%s disagrees on %s: %s"):format(name, payload.name, answer))
      end
   end

   -- One monomorphic loop per implementation, built here rather than shared
   -- through a callback: a single parameterised runner is polymorphic at its
   -- call site and makes LuaJIT's trace choice depend on which implementation
   -- happened to warm first. Each gets its own call count, so a sample is a
   -- comparable slice of wall clock rather than a comparable slice of work.
   local runners, callsFor = {}, {}
   for _, name in ipairs(implementations.order) do
      local sha256 = implementations[name]
      local calls = calibrate(sha256, sources)
      callsFor[name] = calls
      runners[name] = function()
         local started = os.clock()
         for index = 1, calls do
            sha256(sources[(index % count) + 1])
         end
         return length * calls / (os.clock() - started) / 1000000
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
      name = payload.name,
      bytes = length,
      calls = callsFor,
      megabytesPerSecond = rates,
      throughput = {},
      nanosecondsPerCall = {},
      versusControl = {},
   }
   for _, name in ipairs(implementations.order) do
      local rate = median(rates[name])
      record.throughput[name] = rate
      record.nanosecondsPerCall[name] = length / rate * 1000
      record.versusControl[name] = ratioSummary(rates[name], rates.c)
   end
   report.payloads[#report.payloads + 1] = record

   if not jsonOutput then
      io.write(("\n%s payload, %d bytes\n"):format(payload.name, length))
      io.write(("  %-16s %12s %14s %10s\n"):format("implementation", "MB/s", "ns/call", "vs C"))
      for _, name in ipairs(implementations.order) do
         io.write(("  %-16s %12.1f %14.1f %9.4fx\n"):format(
            implementations.titles[name],
            record.throughput[name],
            record.nanosecondsPerCall[name],
            record.versusControl[name].median))
      end
   end
end

-- The geometric mean over the payloads that are actually measuring compression.
-- The 32-byte row is measuring call overhead and averaging it in would hide
-- both things at once.
if not jsonOutput then
   io.write("\nGeometric mean over 1KiB, 64KiB and 1MiB, against the colocated C:\n")
end
report.large = {}
for _, name in ipairs(implementations.order) do
   local product, count = 1, 0
   for _, record in ipairs(report.payloads) do
      if record.name ~= "32B" then
         product = product * record.versusControl[name].median
         count = count + 1
      end
   end
   report.large[name] = product ^ (1 / count)
   if not jsonOutput then
      io.write(("  %-16s %9.3fx\n"):format(implementations.titles[name], report.large[name]))
   end
end

if jsonOutput then
   local function encode(value, indent)
      local kind = type(value)
      if kind == "number" then
         return ("%.17g"):format(value)
      elseif kind == "string" then
         return ("%q"):format(value)
      elseif kind == "boolean" then
         return tostring(value)
      elseif kind ~= "table" then
         return "null"
      end
      local inner = indent .. "  "
      local pieces = {}
      if #value > 0 then
         for _, item in ipairs(value) do
            pieces[#pieces + 1] = inner .. encode(item, inner)
         end
         return "[\n" .. table.concat(pieces, ",\n") .. "\n" .. indent .. "]"
      end
      local keys = {}
      for key in pairs(value) do
         keys[#keys + 1] = key
      end
      table.sort(keys)
      for _, key in ipairs(keys) do
         pieces[#pieces + 1] = ("%s%q: %s"):format(inner, key, encode(value[key], inner))
      end
      if #pieces == 0 then
         return "{}"
      end
      return "{\n" .. table.concat(pieces, ",\n") .. "\n" .. indent .. "}"
   end

   local text = encode(report, "") .. "\n"
   local destination = os.getenv("NUPP_SHA256_BENCH_OUTPUT")
   if destination then
      local out = assert(io.open(destination, "w"))
      out:write(text)
      out:close()
   else
      io.write(text)
   end
end
