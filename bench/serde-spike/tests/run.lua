local spike = require("serde_spike")

for _, suffix in ipairs({"Small", "Medium", "Nested"}) do
   local previous = spike["legacyDebug" .. suffix]()
   assert(spike["derivedDebug" .. suffix]() == previous,
      "derived Debug changed the " .. suffix .. " output")
   assert(spike["preparedDebug" .. suffix]() == previous,
      "prepared Debug changed the " .. suffix .. " output")
   assert(spike["bufferedDebug" .. suffix]() == #previous,
      "buffered Debug changed the " .. suffix .. " output length")
end

local small = spike.smallJson()
for _, name in ipairs({
   "currentEncodeSmall",
   "directEncodeSmall",
   "serdeEncodeSmall",
   "genericEncodeSmall",
   "dynamicEncodeSmall",
   "nativeEncodeSmall",
   "nativeDynamicEncodeSmall",
   "preparedEncodeSmall",
}) do
   assert(spike[name]() == small, name .. " produced different JSON")
end
local smallDocument = require("simdjson_bench_native").decode(spike.documentEncodeSmall())
assert(smallDocument.id == 41 and smallDocument.active and smallDocument.name == "Ada")
assert(spike.preparedWriteSmall() == #small)

local medium = spike.mediumJson()
for _, name in ipairs({
   "currentEncodeMedium",
   "serdeEncodeMedium",
   "genericEncodeMedium",
   "dynamicEncodeMedium",
   "nativeEncodeMedium",
   "nativeDynamicEncodeMedium",
   "preparedEncodeMedium",
}) do
   assert(spike[name]() == medium, name .. " produced different JSON")
end
local mediumDocument = require("simdjson_bench_native").decode(spike.documentEncodeMedium())
assert(mediumDocument.id == 41 and mediumDocument.owner == "example-owner")
assert(spike.preparedWriteMedium() == #medium)
assert(spike.preparedEncodeConstantMedium() == medium,
   "constant-field record changed the twelve-field JSON")

assert(spike.currentDecodeSmall().id == 41)
assert(spike.documentDecodeSmall().id == 41)
assert(spike.nativeDecodeSmall().id == 41)
assert(spike.nativeDynamicDecodeSmall()[1] == 41)
assert(spike.preparedDecodeSmall().id == 41)

assert(spike.currentDecodeMedium().owner == "example-owner")
assert(spike.documentDecodeMedium().owner == "example-owner")
assert(spike.nativeDecodeMedium().owner == "example-owner")
assert(spike.nativeDynamicDecodeMedium()[10] == "example-owner")
assert(spike.preparedDecodeMedium().owner == "example-owner")
assert(spike.currentDecodeMediumReverse().owner == "example-owner")
assert(spike.nativeDecodeMediumReverse().owner == "example-owner")
assert(spike.preparedDecodeMediumReverse().owner == "example-owner")
assert(spike.currentDecodeMediumUnknown().owner == "example-owner")
assert(spike.nativeDecodeMediumUnknown().owner == "example-owner")
assert(spike.preparedDecodeMediumUnknown().owner == "example-owner")

for _, name in ipairs({"preparedDecodeNested", "preparedDecodeNestedBuffer"}) do
   local nested = spike[name]()
   assert(nested.id == 41, name .. " changed the root record")
   assert(nested.child.label == "primary" and nested.child.scores[3] == 3,
      name .. " changed the nested record")
   assert(nested.children[2].label == "second" and nested.children[2].scores[1] == 6,
      name .. " changed the record array")
   assert(nested.labels.region == "us-east-1" and nested.labels.owner == "example",
      name .. " changed the map")
end
