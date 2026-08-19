local ffi = require("ffi")
local json = require("simd_json")
local arena = require("simd_json.arena")
local indexer = require("simd_json.indexer")
local parser = require("simd_json.parser")
local scanner = require("simd_json.scanner")
local simdjsonBench = require("simdjson_bench")
local span = require("nupp.mem.span")

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
   return simdjsonBench.encode(simdjsonBench.asArray(values))
end

local function numbers()
   local values = {}
   for index = 1, 20000 do
      values[index] = index % 3 == 0 and index * 0.125 or index * -1.5e-3
   end
   return simdjsonBench.encode(simdjsonBench.asArray(values))
end

local payloads = {
   {name = "records", source = records(), short = false,
      pullShape = simdjsonBench.arrayOf({id = true, name = true})},
   {name = "ascii", source = strings("ordinary-ascii-value-", 5000), short = false,
      pullShape = simdjsonBench.arrayOf(true)},
   {name = "unicode", source = strings("κόσμος-日本語-🙂-", 3500), short = false,
      pullShape = simdjsonBench.arrayOf(true)},
   {name = "escaped", source = strings("quote-\"-slash-\\-line-\n-", 4000), short = false,
      pullShape = simdjsonBench.arrayOf(true)},
   {name = "numbers", source = numbers(), short = false,
      pullShape = simdjsonBench.arrayOf(true)},
   {name = "short", source = [[{"ok":true,"n":42,"s":"hello"}]], short = true,
      pullShape = {ok = true, n = true}},
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
local indexOnly = arg[1] == "--index-only" or jsonOutput and arg[2] == "--index-only"
local sampleArgument = jsonOutput and (indexOnly and 3 or 2) or (indexOnly and 2 or 1)
local samples = tonumber(arg[sampleArgument]) or 15
local warmups = 4
local targetBytes = tonumber(os.getenv("NUPP_JSON_BENCH_BYTES")) or 5000000

local report = {
   schema = 1,
   samples = samples,
   warmups = warmups,
   mode = indexOnly and "index" or "all",
   environment = {
      os = ffi.os,
      arch = ffi.arch,
      jit = jit.version,
      clang = command("clang --version"),
      uname = command("uname -a"),
      targetTier = os.getenv("NUPP_AOT_TIER") or (ffi.arch == "arm64" and "neon" or "default"),
      simdjson = simdjsonBench.version(),
      simdjsonImplementation = simdjsonBench.implementation(),
   },
   payloads = {},
}

local names = indexOnly and {"classify", "index"} or {
   "classify", "index", "simdjsonStage1", "simdjsonDom", "simdjsonLua", "simdjsonPull",
   "simdjsonPullSelected", "simdjsonEncode", "parse", "materialize", "build",
   "legacy", "arena", "builder", "fused", "nupp",
}

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

for payloadIndex, payload in ipairs(payloads) do
   local source = payload.source
   local input = span.fromString(source)
   local outputStorage = ffi.new("uint8_t[?]", #source > 0 and #source or 1)
   local output = span.writeCarray(outputStorage, #source)
   local tapeStorage = ffi.new("uint32_t[?]", #source > 0 and #source or 1)
   local tape = span.writeCarray(tapeStorage, #source)
   local indexed, indexError = indexer.index(input, tape)
   assert(indexError == 0 and indexed <= #source)
   local tapeRead = span.fromCarray(tapeStorage, tonumber(indexed))
   local NodeArray = ffi.typeof("$[?]", parser.Node)
   local FrameArray = ffi.typeof("$[?]", parser.Frame)
   local nodes = ffi.new(NodeArray, math.max(#source, 1))
   local links = ffi.new("uint32_t[?]", math.max(#source, 1))
   local frames = ffi.new(FrameArray, math.max(#source, 1))
   local nodeWrite = span.writeCarray(nodes, #source)
   local linkWrite = span.writeCarray(links, #source)
   local frameWrite = span.writeCarray(frames, #source)
   local document = arena.parse(source)
   local simdjsonParser = simdjsonBench.new(source)
   local simdjsonValue = simdjsonBench.decode(source, json.null)
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
      index = function()
         local started = os.clock()
         for _ = 1, iterations do
            indexer.index(input, tape)
         end
         return os.clock() - started
      end,
      simdjsonStage1 = function()
         local started = os.clock()
         for _ = 1, iterations do
            assert(simdjsonParser:stage1() == 0)
         end
         return os.clock() - started
      end,
      simdjsonDom = function()
         local started = os.clock()
         for _ = 1, iterations do
            assert(simdjsonParser:dom() == 0)
         end
         return os.clock() - started
      end,
      simdjsonLua = function()
         local started = os.clock()
         for _ = 1, iterations do
            simdjsonBench.decode(source, json.null)
         end
         return os.clock() - started
      end,
      simdjsonPull = function()
         local started = os.clock()
         for _ = 1, iterations do
            simdjsonBench.pull(source, true, json.null)
         end
         return os.clock() - started
      end,
      simdjsonPullSelected = function()
         local started = os.clock()
         for _ = 1, iterations do
            simdjsonBench.pull(source, payload.pullShape, json.null)
         end
         return os.clock() - started
      end,
      simdjsonEncode = function()
         local started = os.clock()
         for _ = 1, iterations do
            simdjsonBench.encode(simdjsonValue, json.null)
         end
         return os.clock() - started
      end,
      parse = function()
         local started = os.clock()
         for _ = 1, iterations do
            parser.parse(input, tapeRead, nodeWrite, linkWrite, frameWrite)
         end
         return os.clock() - started
      end,
      materialize = function()
         local started = os.clock()
         for _ = 1, iterations do
            arena.materialize(document, json.null)
         end
         return os.clock() - started
      end,
      build = function()
         local started = os.clock()
         for _ = 1, iterations do
            arena.materializeBuilder(document, json.null)
         end
         return os.clock() - started
      end,
      legacy = function()
         local started = os.clock()
         for _ = 1, iterations do
            json.decodeLegacy(source)
         end
         return os.clock() - started
      end,
      arena = function()
         local started = os.clock()
         for _ = 1, iterations do
            arena.decode(source, json.null)
         end
         return os.clock() - started
      end,
      builder = function()
         local started = os.clock()
         for _ = 1, iterations do
            arena.decodeBuilder(source, json.null)
         end
         return os.clock() - started
      end,
      fused = function()
         local started = os.clock()
         for _ = 1, iterations do
            arena.decodeFused(source, json.null)
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
   }

   for warmup = 1, warmups do
      for offset = 0, #names - 1 do
         runners[names[(warmup + offset - 1) % #names + 1]]()
      end
   end

   local raw = {
      classify = {}, index = {}, simdjsonStage1 = {}, simdjsonDom = {},
      simdjsonLua = {}, simdjsonPull = {}, simdjsonPullSelected = {},
      simdjsonEncode = {},
      parse = {}, materialize = {}, build = {},
      legacy = {}, arena = {}, builder = {}, nupp = {},
      fused = {},
   }
   for sample = 1, samples do
      collectgarbage()
      for offset = 0, #names - 1 do
         local name = names[(sample + payloadIndex + offset - 2) % #names + 1]
         raw[name][sample] = runners[name]()
      end
   end

   local summary = {
      classifyMBps = #source * iterations / median(raw.classify) / 1000000,
      indexMBps = #source * iterations / median(raw.index) / 1000000,
      indexToClassifierThroughput = ratioSummary(raw.classify, raw.index),
   }
   if not indexOnly then
      summary.nuppMBps = #source * iterations / median(raw.nupp) / 1000000
      summary.simdjsonStage1MBps = #source * iterations / median(raw.simdjsonStage1) / 1000000
      summary.simdjsonDomMBps = #source * iterations / median(raw.simdjsonDom) / 1000000
      summary.simdjsonLuaMBps = #source * iterations / median(raw.simdjsonLua) / 1000000
      summary.simdjsonPullMBps = #source * iterations / median(raw.simdjsonPull) / 1000000
      summary.simdjsonPullSelectedMBps =
         #source * iterations / median(raw.simdjsonPullSelected) / 1000000
      summary.simdjsonEncodeMBps = #source * iterations / median(raw.simdjsonEncode) / 1000000
      summary.legacyMBps = #source * iterations / median(raw.legacy) / 1000000
      summary.parseMBps = #source * iterations / median(raw.parse) / 1000000
      summary.materializeMBps = #source * iterations / median(raw.materialize) / 1000000
      summary.buildMBps = #source * iterations / median(raw.build) / 1000000
      summary.arenaMBps = #source * iterations / median(raw.arena) / 1000000
      summary.builderMBps = #source * iterations / median(raw.builder) / 1000000
      summary.fusedMBps = #source * iterations / median(raw.fused) / 1000000
      summary.nuppToLegacyThroughput = ratioSummary(raw.legacy, raw.nupp)
      summary.nuppToArenaThroughput = ratioSummary(raw.arena, raw.nupp)
      summary.nuppToBuilderThroughput = ratioSummary(raw.builder, raw.nupp)
      summary.nuppToSimdjsonDomThroughput = ratioSummary(raw.simdjsonDom, raw.nupp)
      summary.classifierShare = ratioSummary(raw.classify, raw.nupp)
   end
   local measured = {
      name = payload.name,
      bytes = #source,
      hash = hash32(source),
      short = payload.short,
      iterations = iterations,
      seconds = raw,
      summary = summary,
   }
   report.payloads[#report.payloads + 1] = measured
   output:drop()
   tape:drop()
   nodeWrite:drop()
   linkWrite:drop()
   frameWrite:drop()
end

do
   local pairedGeomeans = {}
   for sample = 1, samples do
      local logSum, count = 0, 0
      for _, payload in ipairs(report.payloads) do
         if not payload.short then
            logSum = logSum + math.log(payload.seconds.classify[sample] / payload.seconds.index[sample])
            count = count + 1
         end
      end
      pairedGeomeans[sample] = math.exp(logSum / count)
   end
   report.largeIndexToClassifierThroughput = bootstrapSummary(pairedGeomeans)
end

if not indexOnly then
   local pairedGeomeans = {}
   for sample = 1, samples do
      local logSum, count = 0, 0
      for _, payload in ipairs(report.payloads) do
         if not payload.short then
            logSum = logSum + math.log(
               payload.seconds.legacy[sample] / payload.seconds.nupp[sample])
            count = count + 1
         end
      end
      pairedGeomeans[sample] = math.exp(logSum / count)
   end
   report.largeNuppToLegacyThroughput = bootstrapSummary(pairedGeomeans)

   pairedGeomeans = {}
   for sample = 1, samples do
      local logSum, count = 0, 0
      for _, payload in ipairs(report.payloads) do
         if not payload.short then
            logSum = logSum + math.log(
               payload.seconds.arena[sample] / payload.seconds.nupp[sample])
            count = count + 1
         end
      end
      pairedGeomeans[sample] = math.exp(logSum / count)
   end
   report.largeNuppToArenaThroughput = bootstrapSummary(pairedGeomeans)

   pairedGeomeans = {}
   for sample = 1, samples do
      local logSum, count = 0, 0
      for _, payload in ipairs(report.payloads) do
         if not payload.short then
            logSum = logSum + math.log(
               payload.seconds.builder[sample] / payload.seconds.nupp[sample])
            count = count + 1
         end
      end
      pairedGeomeans[sample] = math.exp(logSum / count)
   end
   report.largeNuppToBuilderThroughput = bootstrapSummary(pairedGeomeans)
end

if jsonOutput then
   local encoded = simdjsonBench.encode(report)
   local outputPath = os.getenv("NUPP_JSON_BENCH_OUTPUT")
   if outputPath then
      local outputFile = assert(io.open(outputPath, "wb"))
      outputFile:write(encoded, "\n")
      outputFile:close()
   end
   print(encoded)
   return
end

print(("large-payload index/classify geometric mean %.3fx [%.3f, %.3f]"):format(
   report.largeIndexToClassifierThroughput.median,
   report.largeIndexToClassifierThroughput.low95,
   report.largeIndexToClassifierThroughput.high95
))
if not indexOnly then
   print(("large-payload fused/legacy geometric mean %.3fx [%.3f, %.3f]"):format(
      report.largeNuppToLegacyThroughput.median,
      report.largeNuppToLegacyThroughput.low95,
      report.largeNuppToLegacyThroughput.high95
   ))
   print(("large-payload fused/arena geometric mean %.3fx [%.3f, %.3f]"):format(
      report.largeNuppToArenaThroughput.median,
      report.largeNuppToArenaThroughput.low95,
      report.largeNuppToArenaThroughput.high95
   ))
   print(("large-payload fused/builder geometric mean %.3fx [%.3f, %.3f]"):format(
      report.largeNuppToBuilderThroughput.median,
      report.largeNuppToBuilderThroughput.low95,
      report.largeNuppToBuilderThroughput.high95
   ))
end

print(("platform: %s/%s, %s, samples: %d, warmups: %d"):format(
   report.environment.os,
   report.environment.arch,
   report.environment.targetTier,
   samples,
   warmups
))
if not indexOnly then
   print(("simdjson: %s, implementation: %s"):format(
      report.environment.simdjson,
      report.environment.simdjsonImplementation
   ))
end
for _, payload in ipairs(report.payloads) do
   print(("payload: %-8s %7.3f MB  hash32:%s  iterations:%d"):format(
      payload.name,
      payload.bytes / 1000000,
      payload.hash,
      payload.iterations
   ))
   for _, name in ipairs(names) do
      local elapsed = median(payload.seconds[name]) / payload.iterations
      print(("  %-15s %8.3f ms  %8.1f MB/s"):format(
         name,
         elapsed * 1000,
         payload.bytes / elapsed / 1000000
      ))
   end
   if not indexOnly then
      print(("  classifier share %.1f%% [%.1f, %.1f]"):format(
         payload.summary.classifierShare.median * 100,
         payload.summary.classifierShare.low95 * 100,
         payload.summary.classifierShare.high95 * 100
      ))
      print(("  nupp/simdjson DOM %.3fx [%.3f, %.3f]"):format(
         payload.summary.nuppToSimdjsonDomThroughput.median,
         payload.summary.nuppToSimdjsonDomThroughput.low95,
         payload.summary.nuppToSimdjsonDomThroughput.high95
      ))
      print(("  fused/legacy throughput %.3fx [%.3f, %.3f]"):format(
         payload.summary.nuppToLegacyThroughput.median,
         payload.summary.nuppToLegacyThroughput.low95,
         payload.summary.nuppToLegacyThroughput.high95
      ))
      print(("  fused/arena throughput %.3fx [%.3f, %.3f]"):format(
         payload.summary.nuppToArenaThroughput.median,
         payload.summary.nuppToArenaThroughput.low95,
         payload.summary.nuppToArenaThroughput.high95
      ))
      print(("  fused/builder throughput %.3fx [%.3f, %.3f]"):format(
         payload.summary.nuppToBuilderThroughput.median,
         payload.summary.nuppToBuilderThroughput.low95,
         payload.summary.nuppToBuilderThroughput.high95
      ))
   end
   print(("  index/classify throughput %.3fx [%.3f, %.3f]"):format(
      payload.summary.indexToClassifierThroughput.median,
      payload.summary.indexToClassifierThroughput.low95,
      payload.summary.indexToClassifierThroughput.high95
   ))
end
