local cjson = require("cjson")
local ffi = require("ffi")
local json = require("simd_json")
local scanner = require("simd_json.scanner")
local span = require("nupp.span")

io.stdout:setvbuf("no")

local function records()
   local rows = {}
   for index = 1, 2000 do
      rows[index] = ('{"id":%d,"active":%s,"name":"record-%d","values":[%.1f,%d,%d]}'):format(
         index,
         index % 3 ~= 0 and "true" or "false",
         index,
         index * 0.5,
         index * 2,
         index % 17
      )
   end
   return "[" .. table.concat(rows, ",") .. "]"
end

local function strings(prefix, count)
   local values = {}
   for index = 1, count do
      values[index] = prefix .. tostring(index)
   end
   return cjson.encode(values)
end

local function numbers()
   local values = {}
   for index = 1, 20000 do
      values[index] = index % 3 == 0 and index * 0.125 or index * -1.5e-3
   end
   return cjson.encode(values)
end

local payloads = {
   {name = "records", source = records(), short = false},
   {name = "ascii", source = strings("ordinary-ascii-value-", 5000), short = false},
   {name = "unicode", source = strings("κόσμος-日本語-🙂-", 3500), short = false},
   {name = "escaped", source = strings("quote-\"-slash-\\-line-\n-", 4000), short = false},
   {name = "numbers", source = numbers(), short = false},
   {name = "short", source = [[{"ok":true,"n":42,"s":"hello"}]], short = true},
}

local function hash32(source)
   local hash = 5381
   for index = 1, #source do
      hash = (hash * 33 + source:byte(index)) % 4294967296
   end
   return ("%08x"):format(hash)
end

local function command(commandLine)
   local pipe = io.popen(commandLine .. " 2>/dev/null")
   if not pipe then
      return "unavailable"
   end
   local value = pipe:read("*l") or "unavailable"
   pipe:close()
   return value
end

local jsonOutput = arg[1] == "--json"
local samples = tonumber(arg[jsonOutput and 2 or 1]) or 15
local warmups = 4
local targetBytes = tonumber(os.getenv("NUPP_JSON_BENCH_BYTES")) or 5000000

local report = {
   schema = 1,
   samples = samples,
   warmups = warmups,
   environment = {
      os = ffi.os,
      arch = ffi.arch,
      jit = jit.version,
      clang = command("clang --version"),
      uname = command("uname -a"),
      targetTier = os.getenv("NUPP_AOT_TIER") or (ffi.arch == "arm64" and "neon" or "default"),
   },
   payloads = {},
}

local names = {"classify", "nupp", "cjson"}

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

local function ratioSummary(numerator, denominator)
   local ratios = {}
   for index = 1, #numerator do
      ratios[index] = numerator[index] / denominator[index]
   end
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

for payloadIndex, payload in ipairs(payloads) do
   local source = payload.source
   local input = span.fromString(source)
   local outputStorage = ffi.new("uint8_t[?]", #source > 0 and #source or 1)
   local output = span.writeCarray(outputStorage, #source)
   local iterations = math.max(1, math.ceil(targetBytes / #source))
   if payload.short then
      iterations = math.max(iterations, 10000)
   end

   -- Keep one monomorphic loop per implementation. A single `run(name)` loop
   -- is polymorphic at its callback and makes LuaJIT's trace choice depend on
   -- which benchmark happens to warm first.
   local runners = {
      classify = function()
         local started = os.clock()
         for _ = 1, iterations do
            scanner.classify(output, input)
         end
         return os.clock() - started
      end,
      nupp = function()
         local started = os.clock()
         for _ = 1, iterations do
            json.decode(source)
         end
         return os.clock() - started
      end,
      cjson = function()
         local started = os.clock()
         for _ = 1, iterations do
            cjson.decode(source)
         end
         return os.clock() - started
      end,
   }

   for warmup = 1, warmups do
      for offset = 0, #names - 1 do
         runners[names[(warmup + offset - 1) % #names + 1]]()
      end
   end

   local raw = {classify = {}, nupp = {}, cjson = {}}
   for sample = 1, samples do
      collectgarbage()
      for offset = 0, #names - 1 do
         local name = names[(sample + payloadIndex + offset - 2) % #names + 1]
         raw[name][sample] = runners[name]()
      end
   end

   local measured = {
      name = payload.name,
      bytes = #source,
      hash = hash32(source),
      short = payload.short,
      iterations = iterations,
      seconds = raw,
      summary = {
         classifyMBps = #source * iterations / median(raw.classify) / 1000000,
         nuppMBps = #source * iterations / median(raw.nupp) / 1000000,
         cjsonMBps = #source * iterations / median(raw.cjson) / 1000000,
         nuppToCjsonThroughput = ratioSummary(raw.cjson, raw.nupp),
         classifierShare = ratioSummary(raw.classify, raw.nupp),
      },
   }
   report.payloads[#report.payloads + 1] = measured
   output:drop()
end

if jsonOutput then
   print(cjson.encode(report))
   return
end

print(("platform: %s/%s, %s, samples: %d, warmups: %d"):format(
   report.environment.os,
   report.environment.arch,
   report.environment.targetTier,
   samples,
   warmups
))
for _, payload in ipairs(report.payloads) do
   print(("payload: %-8s %7.3f MB  hash32:%s  iterations:%d"):format(
      payload.name,
      payload.bytes / 1000000,
      payload.hash,
      payload.iterations
   ))
   for _, name in ipairs(names) do
      local elapsed = median(payload.seconds[name]) / payload.iterations
      print(("  %-10s %8.3f ms  %8.1f MB/s"):format(
         name,
         elapsed * 1000,
         payload.bytes / elapsed / 1000000
      ))
   end
   print(("  nupp/cjson throughput %.3fx [%.3f, %.3f], classifier share %.1f%% [%.1f, %.1f]"):format(
      payload.summary.nuppToCjsonThroughput.median,
      payload.summary.nuppToCjsonThroughput.low95,
      payload.summary.nuppToCjsonThroughput.high95,
      payload.summary.classifierShare.median * 100,
      payload.summary.classifierShare.low95 * 100,
      payload.summary.classifierShare.high95 * 100
   ))
end
