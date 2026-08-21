local ffi = require("ffi")
local json = require("jsonNative")
local spike = require("serde_spike")

io.stdout:setvbuf("no")

local jsonOutput = arg[1] == "--json"
local samples = tonumber(jsonOutput and arg[2] or arg[1]) or 15
local warmups = 4
local targetSeconds = 0.075
local blackhole = 0

local cases = {
   { group = "debugSmall", name = "previousRenderer", call = "legacyDebugSmall", result = "#value", baseline = true },
   { group = "debugSmall", name = "derivedSchema", call = "derivedDebugSmall", result = "#value" },
   { group = "debugSmall", name = "preparedSchema", call = "preparedDebugSmall", result = "#value" },
   { group = "debugSmall", name = "preparedBuffer", call = "bufferedDebugSmall", result = "value" },

   { group = "debugMedium", name = "previousRenderer", call = "legacyDebugMedium", result = "#value", baseline = true },
   { group = "debugMedium", name = "derivedSchema", call = "derivedDebugMedium", result = "#value" },
   { group = "debugMedium", name = "preparedSchema", call = "preparedDebugMedium", result = "#value" },
   { group = "debugMedium", name = "preparedBuffer", call = "bufferedDebugMedium", result = "value" },

   { group = "debugNested", name = "previousRenderer", call = "legacyDebugNested", result = "#value", baseline = true },
   { group = "debugNested", name = "derivedSchema", call = "derivedDebugNested", result = "#value" },
   { group = "debugNested", name = "preparedSchema", call = "preparedDebugNested", result = "#value" },
   { group = "debugNested", name = "preparedBuffer", call = "bufferedDebugNested", result = "value" },

   { group = "encodeSmall", name = "currentDerived", call = "currentEncodeSmall", result = "#value" },
   { group = "encodeSmall", name = "document", call = "documentEncodeSmall", result = "#value" },
   { group = "encodeSmall", name = "directJson", call = "directEncodeSmall", result = "#value" },
   { group = "encodeSmall", name = "staticSerde", call = "serdeEncodeSmall", result = "#value" },
   { group = "encodeSmall", name = "schemaWalkRecord", call = "genericEncodeSmall", result = "#value" },
   { group = "encodeSmall", name = "schemaWalkSlots", call = "dynamicEncodeSmall", result = "#value" },
   { group = "encodeSmall", name = "nativeSchemaRecord", call = "nativeEncodeSmall", result = "#value" },
   { group = "encodeSmall", name = "nativeSchemaSlots", call = "nativeDynamicEncodeSmall", result = "#value" },
   { group = "encodeSmall", name = "preparedSerde", call = "preparedEncodeSmall", result = "#value" },
   { group = "encodeSmall", name = "preparedSerdeCopied", call = "preparedCopiedWriteSmall", result = "value" },
   { group = "encodeSmall", name = "preparedSerdeBuffered", call = "preparedWriteSmall", result = "value" },
   { group = "encodeSmall", name = "preparedSerdeWriter", call = "preparedWriterSmall", result = "value" },

   { group = "prepareAndEncodeSmall", name = "currentDerived", call = "currentEncodeSmall", result = "#value" },
   { group = "prepareAndEncodeSmall", name = "coldPreparedSerde", call = "coldPreparedEncodeSmall", result = "#value" },

   { group = "encodeMedium", name = "currentDerived", call = "currentEncodeMedium", result = "#value" },
   { group = "encodeMedium", name = "document", call = "documentEncodeMedium", result = "#value" },
   { group = "encodeMedium", name = "staticSerde", call = "serdeEncodeMedium", result = "#value" },
   { group = "encodeMedium", name = "schemaWalkRecord", call = "genericEncodeMedium", result = "#value" },
   { group = "encodeMedium", name = "schemaWalkSlots", call = "dynamicEncodeMedium", result = "#value" },
   { group = "encodeMedium", name = "nativeSchemaRecord", call = "nativeEncodeMedium", result = "#value" },
   { group = "encodeMedium", name = "nativeSchemaSlots", call = "nativeDynamicEncodeMedium", result = "#value" },
   { group = "encodeMedium", name = "preparedSerde", call = "preparedEncodeMedium", result = "#value" },
   { group = "encodeMedium", name = "preparedSerdeCopied", call = "preparedCopiedWriteMedium", result = "value" },
   { group = "encodeMedium", name = "preparedSerdeBuffered", call = "preparedWriteMedium", result = "value" },

   { group = "encodePayload4KiB", name = "currentDerived", call = "currentEncodePayload4KiB", result = "#value" },
   { group = "encodePayload4KiB", name = "preparedSerde", call = "preparedEncodePayload4KiB", result = "#value" },
   { group = "encodePayload4KiB", name = "preparedSerdeCopied", call = "preparedCopiedWritePayload4KiB", result = "value" },
   { group = "encodePayload4KiB", name = "preparedSerdeBuffered", call = "preparedWritePayload4KiB", result = "value" },

   { group = "encodePayload64KiB", name = "currentDerived", call = "currentEncodePayload64KiB", result = "#value" },
   { group = "encodePayload64KiB", name = "preparedSerde", call = "preparedEncodePayload64KiB", result = "#value" },
   { group = "encodePayload64KiB", name = "preparedSerdeCopied", call = "preparedCopiedWritePayload64KiB", result = "value" },
   { group = "encodePayload64KiB", name = "preparedSerdeBuffered", call = "preparedWritePayload64KiB", result = "value" },
   { group = "encodePayload64KiB", name = "preparedSerdeWriter", call = "preparedWriterPayload64KiB", result = "value" },

   { group = "encodeNested", name = "currentDerived", call = "currentEncodeNested", result = "#value" },
   { group = "encodeNested", name = "preparedSerde", call = "preparedEncodeNested", result = "#value" },
   { group = "encodeNested", name = "preparedSerdeBuffered", call = "preparedWriteNested", result = "value" },
   { group = "encodeNested", name = "preparedSerdeWriter", call = "preparedWriterNested", result = "value" },

   { group = "decodeSmall", name = "currentDerived", call = "currentDecodeSmall", result = "value.id" },
   { group = "decodeSmall", name = "document", call = "documentDecodeSmall", result = "value.id" },
   { group = "decodeSmall", name = "nativeSchemaRecord", call = "nativeDecodeSmall", result = "value.id" },
   { group = "decodeSmall", name = "nativeSchemaSlots", call = "nativeDynamicDecodeSmall", result = "value[1]" },
   { group = "decodeSmall", name = "preparedSerde", call = "preparedDecodeSmall", result = "value.id" },
   { group = "decodeSmall", name = "preparedSerdeBuffer", call = "preparedDecodeSmallBuffer", result = "value.id" },

   { group = "decodeMediumOrdered", name = "currentDerived", call = "currentDecodeMedium", result = "value.id" },
   { group = "decodeMediumOrdered", name = "document", call = "documentDecodeMedium", result = "value.id" },
   { group = "decodeMediumOrdered", name = "nativeSchemaRecord", call = "nativeDecodeMedium", result = "value.id" },
   { group = "decodeMediumOrdered", name = "nativeSchemaSlots", call = "nativeDynamicDecodeMedium", result = "value[1]" },
   { group = "decodeMediumOrdered", name = "preparedSerde", call = "preparedDecodeMedium", result = "value.id" },
   { group = "decodeMediumOrdered", name = "preparedSerdeBuffer", call = "preparedDecodeMediumBuffer", result = "value.id" },

   { group = "decodeMediumReverse", name = "currentDerived", call = "currentDecodeMediumReverse", result = "value.id" },
   { group = "decodeMediumReverse", name = "nativeSchemaRecord", call = "nativeDecodeMediumReverse", result = "value.id" },
   { group = "decodeMediumReverse", name = "preparedSerde", call = "preparedDecodeMediumReverse", result = "value.id" },

   { group = "decodeMediumUnknown", name = "currentDerived", call = "currentDecodeMediumUnknown", result = "value.id" },
   { group = "decodeMediumUnknown", name = "nativeSchemaRecord", call = "nativeDecodeMediumUnknown", result = "value.id" },
   { group = "decodeMediumUnknown", name = "preparedSerde", call = "preparedDecodeMediumUnknown", result = "value.id" },

   { group = "decodeNested", name = "currentDerived", call = "currentDecodeNested", result = "value.id" },
   { group = "decodeNested", name = "preparedSerde", call = "preparedDecodeNested", result = "value.id" },
   { group = "decodeNested", name = "preparedSerdeBuffer", call = "preparedDecodeNestedBuffer", result = "value.id" },

   { group = "decodePayload64KiB", name = "currentDerived", call = "currentDecodePayload64KiB", result = "#value.data" },
   { group = "decodePayload64KiB", name = "preparedSerde", call = "preparedDecodePayload64KiB", result = "#value.data" },
   { group = "decodePayload64KiB", name = "preparedSerdeBuffer", call = "preparedDecodePayload64KiBBuffer", result = "#value.data" },
}

local function compileRunner(case)
   local source = ([=[
      return function(module, iterations)
         local total = 0
         for _ = 1, iterations do
            local value = module.%s()
            total = total + %s
         end
         return total
      end
   ]=]):format(case.call, case.result)
   return assert(loadstring(source, "serde-spike:" .. case.call))()
end

local function elapsed(runner, iterations)
   local started = os.clock()
   blackhole = blackhole + runner(spike, iterations)
   return os.clock() - started
end

local function calibrate(runner)
   local iterations = 64
   while true do
      local seconds = elapsed(runner, iterations)
      if seconds >= targetSeconds then
         return iterations
      end
      local scale = math.max(2, math.min(16, math.ceil(targetSeconds / math.max(seconds, 0.000001))))
      iterations = iterations * scale
   end
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
   local values = sorted(values)
   local middle = math.floor(#values / 2) + 1
   if #values % 2 == 1 then
      return values[middle]
   end
   return (values[middle - 1] + values[middle]) * 0.5
end

local function percentile(values, fraction)
   local values = sorted(values)
   local index = math.max(1, math.min(#values, math.ceil(#values * fraction)))
   return values[index]
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

for _, case in ipairs(cases) do
   case.runner = compileRunner(case)
   for _ = 1, warmups do
      case.runner(spike, 256)
   end
   case.iterations = calibrate(case.runner)
   case.seconds = {}
end

for sample = 1, samples do
   local forward = sample % 2 == 1
   for offset = 1, #cases do
      local index = forward and offset or (#cases - offset + 1)
      local case = cases[index]
      collectgarbage("collect")
      case.seconds[sample] = elapsed(case.runner, case.iterations)
   end
end

local groups = {}
for _, case in ipairs(cases) do
   local nanoseconds = {}
   for index, seconds in ipairs(case.seconds) do
      nanoseconds[index] = seconds * 1e9 / case.iterations
   end
   case.nanoseconds = nanoseconds
   case.medianNanoseconds = median(nanoseconds)
   groups[case.group] = groups[case.group] or {}
   groups[case.group][#groups[case.group] + 1] = case
end

local report = {
   samples = samples,
   warmups = warmups,
   targetSeconds = targetSeconds,
   toolchain = {
      os = ffi.os,
      arch = ffi.arch,
      jit = jit.version,
   },
   groups = {},
}

for group, members in pairs(groups) do
   local baseline
   local baselineSamples
   for _, case in ipairs(members) do
      if case.baseline or case.name == "currentDerived" then
         baseline = case.medianNanoseconds
         baselineSamples = case.nanoseconds
         break
      end
   end
   local output = {}
   for _, case in ipairs(members) do
      output[#output + 1] = {
         name = case.name,
         medianNanoseconds = case.medianNanoseconds,
         speedupVsCurrent = baseline / case.medianNanoseconds,
         speedup = ratioSummary(baselineSamples, case.nanoseconds),
         iterations = case.iterations,
         samples = case.nanoseconds,
      }
   end
   report.groups[group] = output
end

if jsonOutput then
   local encoded = json.encode(report)
   local outputPath = os.getenv("NUPP_SERDE_BENCH_OUTPUT")
   if outputPath then
      local output = assert(io.open(outputPath, "wb"))
      assert(output:write(encoded, "\n"))
      assert(output:close())
   else
      print(encoded)
   end
else
   local order = {
      "debugSmall", "debugMedium", "debugNested",
      "encodeSmall", "prepareAndEncodeSmall", "encodeMedium", "encodePayload4KiB", "encodePayload64KiB", "encodeNested",
      "decodeSmall", "decodeMediumOrdered",
      "decodeMediumReverse", "decodeMediumUnknown", "decodeNested", "decodePayload64KiB",
   }
   for _, group in ipairs(order) do
      print(("\n%s"):format(group))
      print(("%-24s %12s %12s %21s"):format(
         "implementation", "ns/op", "vs current", "95% CI"
      ))
      for _, case in ipairs(report.groups[group]) do
         print(("%-24s %12.1f %11.2fx %9.2f–%-9.2fx"):format(
            case.name,
            case.medianNanoseconds,
            case.speedup.median,
            case.speedup.low95,
            case.speedup.high95
         ))
      end
   end
end

if blackhole == 0 then
   error("benchmark result was not consumed")
end
