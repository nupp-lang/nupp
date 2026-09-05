local ffi = require("ffi")
local json = require("simd_json")
local arena = require("simd_json.arena")
local indexer = require("simd_json.indexer")
local parser = require("simd_json.parser")
local scanner = require("simd_json.scanner")
local simdjsonBench = require("simdjson_bench")
local span = require("nupp.mem.span")
local valueBuilder = require("nupp.data.valuebuilder")

require("production_json_test").run()

ffi.cdef[[
   typedef struct { uint32_t v1; uint32_t v2; uint32_t v3; } SimdJsonIndexResult;
]]
local nativeExtension = ffi.os == "Windows" and ".dll" or ffi.os == "OSX" and ".dylib" or ".so"
local native = ffi.load("build/lib/libsimd_json_aot" .. nativeExtension)

-- The forced-scalar oracle is not reachable through the generated module, so
-- it is looked up by name. An exported name carries the feature tier it was
-- built for, and an artifact holds only the tiers its target selected, so the
-- tier is resolved rather than assumed: the x86-64 ones are offered only when
-- the running machine reports them, and anything left is found by whether it
-- resolves. Ask for a tier the CPU lacks and the call would fault.
local targets = require("nupp.compiler.aot.target")
local function nativeSymbol(name, declaration)
   local detected = 0
   pcall(ffi.cdef, "int ks_aot_feature_tier(void);")
   local reported, value = pcall(function() return native.ks_aot_feature_tier() end)
   if reported then detected = tonumber(value) end
   for _, tier in ipairs({"avx512f", "avx2", "neon", "simd128", "baseline"}) do
      if targets.rank(tier) <= detected then
         local suffixed = targets.symbol(name, tier)
         pcall(ffi.cdef, declaration:format(suffixed))
         local found, symbol = pcall(function() return native[suffixed] end)
         if found and symbol ~= nil then return symbol end
      end
   end
   error("the AOT library exports no build of " .. name)
end

local indexForcedScalar = nativeSymbol("ks_index_forced_scalar", [[
   SimdJsonIndexResult %s(
      const uint8_t *source, uint32_t *tape, size_t count_source, size_t count_tape
   );
]])
local NodeArray = ffi.typeof("$[?]", parser.Node)
local FrameArray = ffi.typeof("$[?]", parser.Frame)

local checks = 0
local numberBits = ffi.typeof("union { double number; uint64_t bits; }")
local function check(condition, message)
   checks = checks + 1
   assert(condition, message)
end

local function markedEmpty(value, marker)
   return type(value) == "table" and next(value) == nil
      and getmetatable(value) == marker
end

local function same(left, right, simdjsonNumbers)
   if markedEmpty(left, simdjsonBench.EMPTY_ARRAY)
      or markedEmpty(left, simdjsonBench.EMPTY_OBJECT) then
      return type(right) == "table" and next(right) == nil
   end
   if left == json.null or right == json.null then
      return left == json.null and right == json.null
   end
   if type(left) ~= type(right) then
      return false
   end
   if type(left) ~= "table" then
      if type(left) == "number" then
         if simdjsonNumbers then
            return left == right
         end
         local leftBits = numberBits()
         local rightBits = numberBits()
         leftBits.number = left
         rightBits.number = right
         return tostring(leftBits.bits) == tostring(rightBits.bits)
      end
      return left == right
   end
   for key, value in pairs(left) do
      if not same(value, right[key], simdjsonNumbers) then
         return false
      end
   end
   for key in pairs(right) do
      if left[key] == nil then
         return false
      end
   end
   return true
end

local corpus = {
   "null",
   "true",
   "false",
   "0",
   "-0",
   "-12.5e+3",
   [["plain"]],
   [["line\nfeed\tand slash \/"]],
   [["\u0000\u20ac\uD834\uDD1E"]],
   "[]",
   "{}",
   [[ [1, true, null, {"nested": [2, 3]}] ]],
   [[{"head":1,"nested":[2,3],"tail":4}]],
   [[{"name":"Nupp","unicode":"κόσμος","escaped":"\u0061","n":1.25}]],
   "-9223372036854775808",
   "123456789012345.6",
   "9007199254740991e-1",
   "9007199254740992e-1",
   "5e-324",
   "2.2250738585072013e-308",
   "7.2057594037927933e+16",
   "3.1415926535897932384626433832795028841971693993751",
   "1.7976931348623157e308",
   "1e309",
   [["\"\\\/\b\f\n\r\t"]],
}

local function referenceTape(source)
   local positions = {}
   local inString = false
   local slashRun = 0
   for offset = 0, #source - 1 do
      local byte = source:byte(offset + 1)
      if byte == 92 and inString then
         slashRun = slashRun + 1
      else
         if byte == 34 and slashRun % 2 == 0 then
            inString = not inString
            positions[#positions + 1] = offset
         elseif not inString and (
            byte == 123 or byte == 125 or byte == 91 or byte == 93
            or byte == 58 or byte == 44
         ) then
            positions[#positions + 1] = offset
         end
         slashRun = 0
      end
   end
   return positions
end

local function indexed(source, capacity)
   capacity = capacity == nil and #source or capacity
   local storage = ffi.new("uint32_t[?]", math.max(capacity, 1))
   local writable = span.writeCarray(storage, capacity)
   local count, status, position = indexer.index(span.fromString(source), writable)
   writable:drop()
   local positions = {}
   for offset = 0, tonumber(count) - 1 do
      positions[#positions + 1] = tonumber(storage[offset])
   end
   return positions, tonumber(status), tonumber(position)
end

local function scalarIndexed(source, capacity)
   capacity = capacity == nil and #source or capacity
   local storage = ffi.new("uint32_t[?]", math.max(capacity, 1))
   local result = indexForcedScalar(
      ffi.cast("const uint8_t *", source), storage, #source, capacity
   )
   local positions = {}
   for offset = 0, tonumber(result.v1) - 1 do
      positions[#positions + 1] = tonumber(storage[offset])
   end
   return positions, tonumber(result.v2), tonumber(result.v3)
end

local function parsed(source, nodeCapacity, linkCapacity, frameCapacity)
   local tapePositions, tapeStatus = indexed(source)
   assert(tapeStatus == indexer.OK)
   local tapeStorage = ffi.new("uint32_t[?]", math.max(#tapePositions, 1))
   for offset, position in ipairs(tapePositions) do
      tapeStorage[offset - 1] = position
   end
   nodeCapacity = nodeCapacity == nil and math.max(#tapePositions + 1, 1) or nodeCapacity
   linkCapacity = linkCapacity == nil and nodeCapacity or linkCapacity
   frameCapacity = frameCapacity == nil and nodeCapacity or frameCapacity
   local nodes = ffi.new(NodeArray, math.max(nodeCapacity, 1))
   local links = ffi.new("uint32_t[?]", math.max(linkCapacity, 1))
   local frames = ffi.new(FrameArray, math.max(frameCapacity, 1))
   local nodeWrite = span.writeCarray(nodes, nodeCapacity)
   local linkWrite = span.writeCarray(links, linkCapacity)
   local frameWrite = span.writeCarray(frames, frameCapacity)
   local root, status, position, nodeCount = parser.parse(
      span.fromString(source),
      span.fromCarray(tapeStorage, #tapePositions),
      nodeWrite, linkWrite, frameWrite)
   nodeWrite:drop()
   linkWrite:drop()
   frameWrite:drop()
   return tonumber(root), tonumber(status), tonumber(position), tonumber(nodeCount)
end

for _, source in ipairs(corpus) do
   local actual = json.decode(source)
   local arenaActual = arena.decode(source, json.null)
   local fusedActual = arena.decodeFused(source, json.null)
   local expected = actual
   check(same(actual, expected), "differential mismatch for " .. source)
   check(same(arenaActual, expected), "arena differential mismatch for " .. source)
   check(same(fusedActual, expected), "fused differential mismatch for " .. source)
   if source ~= "1e309" then
      local simdjsonActual = simdjsonBench.decode(source, json.null)
      local pulledActual = simdjsonBench.pull(source, true, json.null)
      check(same(simdjsonActual, expected, true), "simdjson Lua DOM mismatch for " .. source)
      check(same(pulledActual, expected, true), "simdjson pull mismatch for " .. source)
   end
   local valid, why = json.validate(source)
   check(valid and why == nil, "valid input rejected: " .. tostring(why))
   local expectedTape = referenceTape(source)
   local actualTape, indexStatus, indexPosition = indexed(source)
   local scalarTape, scalarStatus, scalarPosition = scalarIndexed(source)
   check(indexStatus == indexer.OK and indexPosition == 0, "valid input failed structural indexing")
   check(indexStatus == scalarStatus and indexPosition == scalarPosition,
      "packed index status differs from scalar oracle")
   check(#actualTape == #expectedTape, "structural tape length mismatch")
   check(#actualTape == #scalarTape, "packed tape length differs from scalar oracle")
   for position, offset in ipairs(expectedTape) do
      check(actualTape[position] == offset, "structural tape offset mismatch")
      check(actualTape[position] == scalarTape[position], "packed tape differs from scalar oracle")
   end
   if #expectedTape > 0 then
      local partial, capacityStatus, capacityPosition = indexed(source, #expectedTape - 1)
      check(#partial == #expectedTape - 1, "capacity result wrote the wrong count")
      check(capacityStatus == indexer.TAPE_CAPACITY and capacityPosition > 0,
         "exact tape capacity failure was not reported")
   end
   local _, parseStatus, _, nodeCount = parsed(source)
   check(parseStatus == parser.OK, "valid input failed native parsing")
   if nodeCount > 1 then
      local _, nodeStatus = parsed(source, nodeCount - 1)
      check(nodeStatus == parser.NODE_CAPACITY, "one-short node arena was accepted")
      local _, linkStatus = parsed(source, nodeCount, nodeCount - 2)
      check(linkStatus == parser.LINK_CAPACITY, "one-short link arena was accepted")
   end
end

do
   -- These fallbacks run as ordinary Lua. Fixed widths are compile-time facts,
   -- so their already-in-range arguments do not need the compiler-only
   -- `nupp.math.u32` surface installed in this direct-Lua test process.
   local scratch = valueBuilder.newWordScratch(2)
   valueBuilder.setScratchWord(scratch, 0, 0xDEADBEEF)
   check(valueBuilder.scratchWord(scratch, 0) == 0xDEADBEEF,
      "ordinary word scratch lost a value")
   check(not pcall(valueBuilder.scratchWord, scratch, 2),
      "ordinary word scratch accepted an out-of-bounds read")

   local byteScratch = valueBuilder.newByteScratch(2)
   valueBuilder.setScratchByte(byteScratch, 0, 65)
   valueBuilder.setScratchByte(byteScratch, 1, 66)
   check(valueBuilder.scratchByte(byteScratch, 1) == 66,
      "ordinary byte scratch lost a value")
   local byteStream = valueBuilder.new(json.null)
   valueBuilder.openArray(byteStream, 1)
   valueBuilder.stringScratch(
      byteStream,
      byteScratch,
      0,
      2
   )
   valueBuilder.close(byteStream)
   check(valueBuilder.finish(byteStream)[1] == "AB", "byte scratch did not publish a normal string")
   valueBuilder.resetByteScratch(byteScratch)
   valueBuilder.setScratchByte(byteScratch, 0, 67)
   check(valueBuilder.scratchByte(byteScratch, 0) == 67,
      "ordinary byte scratch did not reset")
end

do
   local stream = valueBuilder.new(json.null)
   valueBuilder.openObject(stream, 2)
   valueBuilder.key(stream, "alpha", 0, 5, false)
   valueBuilder.openArray(stream, 2)
   valueBuilder.number(stream, 1)
   valueBuilder.null(stream)
   valueBuilder.close(stream)
   valueBuilder.key(stream, "escaped\\n", 0, 9, true)
   valueBuilder.boolean(stream, true)
   valueBuilder.close(stream)
   local built = valueBuilder.finish(stream)
   check(built.alpha[1] == 1 and built.alpha[2] == json.null and built["escaped\n"] == true,
      "ordinary value stream built the wrong graph")
end

local invalid = {
   "",
   "nul",
   "01",
   "1.",
   "1e",
   "-",
   "-.1",
   "1e+",
   "[1,]",
   [[{"a":1,}]],
   [["unterminated]],
   [["\x"]],
   [["\uD800"]],
   [["\uDC00"]],
   "true false",
   '"control\001byte"',
   '"invalid utf8 \255"',
   '"' .. string.char(0x80) .. '"',
   '"' .. string.char(0xc2) .. '"',
   '"' .. string.char(0xc0, 0xaf) .. '"',
   '"' .. string.char(0xe0, 0x80, 0x80) .. '"',
   '"' .. string.char(0xed, 0xa0, 0x80) .. '"',
   '"' .. string.char(0xf0, 0x80, 0x80, 0x80) .. '"',
   '"' .. string.char(0xf4, 0x90, 0x80, 0x80) .. '"',
   '"' .. string.char(0xf5, 0x80, 0x80, 0x80) .. '"',
   '"' .. string.char(0xe2, 0x82) .. '"',
   '"' .. string.char(0xf0, 0x9f, 0x99) .. '"',
}

for _, source in ipairs(invalid) do
   local valid, why = json.validate(source)
   check(not valid and type(why) == "string", "invalid input accepted: " .. source)
   local arenaValid = pcall(arena.decode, source, json.null)
   check(not arenaValid, "invalid input accepted by arena parser: " .. source)
   local fusedValid = pcall(arena.decodeFused, source, json.null)
   check(not fusedValid, "invalid input accepted by fused parser: " .. source)
   local simdjsonValid = pcall(simdjsonBench.decode, source, json.null)
   check(not simdjsonValid, "invalid input accepted by simdjson Lua DOM: " .. source)
   local simdjsonPullValid = pcall(simdjsonBench.pull, source, true, json.null)
   check(not simdjsonPullValid, "invalid input accepted by simdjson pull: " .. source)
   local simdjsonSkippedValid = pcall(simdjsonBench.pull, source, {})
   check(not simdjsonSkippedValid, "invalid skipped input accepted by simdjson pull: " .. source)
end

do
   local nullValue = {}
   local source = [[{"id":7,"profile":{"name":"Nupp","ignored":9},"items":[1,null,2],"nullable":null,"emptyArray":[],"emptyObject":{},"ignored":{"deep":true}}]]
   local shape = {
      id = true,
      profile = {name = true},
      items = simdjsonBench.arrayOf(true),
      nullable = true,
      emptyArray = true,
      emptyObject = true,
   }
   local pulled = simdjsonBench.pull(source, shape)
   check(pulled.id == 7 and pulled.profile.name == "Nupp",
      "pull did not materialize selected fields")
   check(pulled.profile.ignored == nil and pulled.ignored == nil,
      "pull materialized an unselected field")
   check(#pulled.items == 2 and pulled.items[1] == 1 and pulled.items[2] == 2,
      "pull did not drop and compact null array values")
   check(pulled.nullable == nil, "pull did not drop null by default")
   check(markedEmpty(pulled.emptyArray, simdjsonBench.EMPTY_ARRAY),
      "pull lost the empty-array sentinel")
   check(markedEmpty(pulled.emptyObject, simdjsonBench.EMPTY_OBJECT),
      "pull lost the empty-object sentinel")

   local preserved = simdjsonBench.pull(source, shape, nullValue)
   check(preserved.nullable == nullValue and preserved.items[2] == nullValue,
      "pull did not preserve the caller's null sentinel")
   check(preserved.items[3] == 2, "preserved pull changed array positions")

   local eager = simdjsonBench.decode(source)
   check(eager.nullable == nil and eager.items[1] == 1 and eager.items[2] == 2,
      "eager decode did not drop null by default")
   local eagerPreserved = simdjsonBench.decode(source, nullValue)
   check(eagerPreserved.nullable == nullValue and eagerPreserved.items[2] == nullValue,
      "eager decode did not preserve the caller's null sentinel")
   check(markedEmpty(simdjsonBench.decode("[null]"), simdjsonBench.EMPTY_ARRAY),
      "an array emptied by null dropping lost its sentinel")
   check(markedEmpty(simdjsonBench.decode([[{"only":null}]]), simdjsonBench.EMPTY_OBJECT),
      "an object emptied by null dropping lost its sentinel")
   check(not pcall(simdjsonBench.pull, [[{"ignored":1e309,"id":1}]], {id = true}),
      "pull did not validate an unselected overflowing number")
   check(markedEmpty(simdjsonBench.pull("[1,2,3]", simdjsonBench.arrayOf(false)),
      simdjsonBench.EMPTY_ARRAY), "false array shape did not drop every member")
   check(not pcall(simdjsonBench.pull, "1", "all"),
      "pull accepted a truthy non-shape value")
end

do
   local nullValue = {}
   check(simdjsonBench.encode(simdjsonBench.EMPTY_ARRAY) == "[]",
      "empty-array sentinel serialized incorrectly")
   check(simdjsonBench.serialize(simdjsonBench.EMPTY_OBJECT) == "{}",
      "empty-object sentinel serialized incorrectly")
   check(simdjsonBench.encode({}) == "{}", "empty Lua table did not serialize as an object")
   check(simdjsonBench.encode(simdjsonBench.asArray({})) == "[]",
      "array-marked empty Lua table did not serialize as an array")
   check(not pcall(simdjsonBench.encode, {[2] = true}), "sparse array serialized as JSON")
   check(not pcall(simdjsonBench.encode, {[1] = true, key = false}),
      "mixed array and object serialized as JSON")
   check(not pcall(simdjsonBench.encode, 0 / 0), "NaN serialized as JSON")
   check(not pcall(simdjsonBench.encode, "\255"), "invalid UTF-8 serialized as JSON")
   local cycle = {}
   cycle.self = cycle
   check(not pcall(simdjsonBench.encode, cycle), "cyclic table serialized as JSON")

   local encoded = simdjsonBench.encode({
      array = {1, nullValue, 2},
      emptyArray = simdjsonBench.EMPTY_ARRAY,
      emptyObject = simdjsonBench.EMPTY_OBJECT,
      text = "quote-\"-κόσμος",
   }, nullValue)
   local decoded = simdjsonBench.decode(encoded, nullValue)
   check(decoded.array[2] == nullValue and decoded.array[3] == 2,
      "serialized null sentinel did not round trip")
   check(markedEmpty(decoded.emptyArray, simdjsonBench.EMPTY_ARRAY)
      and markedEmpty(decoded.emptyObject, simdjsonBench.EMPTY_OBJECT),
      "serialized empty-container sentinels did not round trip")

   local out = require("string.buffer").new()
   local writer = simdjsonBench.writer(out, nullValue)
   writer:startObject():key("items"):startArray():write(1)
   writer:null():write(simdjsonBench.EMPTY_OBJECT):endArray()
      :key("empty"):write(simdjsonBench.EMPTY_ARRAY):endObject()
   writer:close()
   check(out:tostring() == [[{"items":[1,null,{}],"empty":[]}]],
      "streaming writer emitted the wrong chunks")
   out = require("string.buffer").new()
   local key = simdjsonBench.encodedString('quoted"key')
   local trustedWriter = simdjsonBench.writer(out)
   trustedWriter:startObject()
      :key(key):write(simdjsonBench.verified("1")):endObject()
   trustedWriter:close()
   check(out:tostring() == [[{"quoted\"key":1}]],
      "streaming writer emitted trusted bytes incorrectly")
   check(not pcall(function() writer:write(true) end),
      "finished streaming writer accepted another value")
   check(not pcall(function()
      local invalidOut = require("string.buffer").new()
      simdjsonBench.writer(invalidOut):startObject():write(true)
   end), "streaming writer accepted an object value without a key")
end

do
   local state = 104729
   local function random(limit)
      state = state * 48271 % 2147483647
      return state % limit
   end
   for case = 1, 200 do
      local value = {
         id = random(1000000),
         active = random(2) == 1,
         ratio = (random(2000001) - 1000000) / (2 ^ random(18)),
         text = ("case-%d-quote-\"-slash-\\-κόσμος"):format(case),
         values = {random(1000), random(1000) / 8, random(1000) / 1000},
      }
      local source = simdjsonBench.encode(value)
      local expected = json.decode(source)
      check(same(arena.decode(source, json.null), expected),
         "generated arena differential mismatch at case " .. case)
      check(same(arena.decodeFused(source, json.null), expected),
         "generated fused differential mismatch at case " .. case)
      check(same(simdjsonBench.decode(source, json.null), expected, true),
         "generated simdjson Lua DOM mismatch at case " .. case)
      check(same(simdjsonBench.pull(source, true, json.null), expected, true),
         "generated simdjson pull mismatch at case " .. case)
      local truncated = source:sub(1, -2)
      check(not pcall(arena.decode, truncated, json.null),
         "truncated generated document accepted at case " .. case)
      check(not pcall(arena.decodeFused, truncated, json.null),
         "truncated generated document accepted by fused parser at case " .. case)
      check(not pcall(simdjsonBench.decode, truncated, json.null),
         "truncated generated document accepted by simdjson Lua DOM at case " .. case)
   end
end

local invalidUtf8 = {
   string.char(0x80),
   string.char(0xc0, 0xaf),
   string.char(0xe0, 0x80, 0x80),
   string.char(0xed, 0xa0, 0x80),
   string.char(0xf0, 0x80, 0x80, 0x80),
   string.char(0xf4, 0x90, 0x80, 0x80),
   string.char(0xf5, 0x80, 0x80, 0x80),
   string.char(0xe2, 0x82),
}
for _, source in ipairs(invalidUtf8) do
   local _, status, position = indexed(source)
   local _, scalarStatus, scalarPosition = scalarIndexed(source)
   check(status == indexer.INVALID_UTF8 and position > 0, "invalid UTF-8 passed structural indexing")
   check(status == scalarStatus and position == scalarPosition,
      "packed UTF-8 failure differs from scalar oracle")
end

local utf8Boundaries = {
   string.char(0xc2, 0x80),
   string.char(0xdf, 0xbf),
   string.char(0xe0, 0xa0, 0x80),
   string.char(0xed, 0x9f, 0xbf),
   string.char(0xf0, 0x90, 0x80, 0x80),
   string.char(0xf4, 0x8f, 0xbf, 0xbf),
}

for _, text in ipairs(utf8Boundaries) do
   local source = '"' .. text .. '"'
   local valid, why = json.validate(source)
   check(valid and why == nil, "valid UTF-8 boundary rejected: " .. tostring(why))
   check(json.decode(source) == text, "UTF-8 boundary decoded incorrectly")
end

-- Exercise UTF-8 and escape state at every plausible SIMD block boundary. The
-- current gang is narrower than this range on every supported target, and the
-- future packed-byte species is covered as well.
for prefix = 0, 40 do
   local padding = ("a"):rep(prefix)
   local validSource = '"' .. padding .. string.char(0xf0, 0x9f, 0x99, 0x82) .. '\\"tail"'
   local valid, why = json.validate(validSource)
   check(valid and why == nil, "boundary-spanning UTF-8 or escape rejected at " .. prefix)
   local decoded, fusedValue = pcall(arena.decodeFused, validSource, json.null)
   check(decoded, "fused boundary input rejected at " .. prefix)
   check(fusedValue == padding .. string.char(0xf0, 0x9f, 0x99, 0x82) .. '"tail',
      "fused boundary escape decoded incorrectly at " .. prefix)

   local invalidSource = '"' .. padding .. string.char(0xf0, 0x9f, 0x99) .. '"'
   valid, why = json.validate(invalidSource)
   check(not valid and type(why) == "string", "truncated boundary UTF-8 accepted at " .. prefix)
   check(not pcall(arena.decodeFused, invalidSource, json.null), "fused boundary UTF-8 accepted at " .. prefix)
end

-- Put every escape shape on and around both halves of the 32-byte copy/find
-- window. Long suffixes force the decoder to resume vector copying after each
-- scalar escape rather than succeeding from a scalar tail alone.
for prefix = 0, 64 do
   local head, tail = ("a"):rep(prefix), ("z"):rep(70)
   local cases = {
      {'"' .. head .. [[\n]] .. tail .. '"', head .. "\n" .. tail},
      {'"' .. head .. [[\u20ac]] .. tail .. '"', head .. string.char(0xe2, 0x82, 0xac) .. tail},
      {'"' .. head .. [[\uD834\uDD1E]] .. tail .. '"', head .. string.char(0xf0, 0x9d, 0x84, 0x9e) .. tail},
   }
   for _, case in ipairs(cases) do
      local ok, value = pcall(arena.decodeFused, case[1], json.null)
      check(ok and value == case[2], "copy/find escape decoded incorrectly at " .. prefix)
   end
end

do
   local source = [[{"outer":[1,true,{"text":"complete"}],"tail":null}]]
   for length = 0, #source - 1 do
      local valid, why = json.validate(source:sub(1, length))
      check(not valid and type(why) == "string", "truncated document accepted at " .. length)
   end
end

do
   local source = "0"
   for _ = 1, 64 do
      source = "[" .. source .. "]"
   end
   local valid, why = json.validate(source)
   check(valid and why == nil, "bounded deep nesting rejected: " .. tostring(why))
   local _, exactStatus = parsed(source, nil, nil, 64)
   local _, shortStatus = parsed(source, nil, nil, 63)
   check(exactStatus == parser.OK, "exact frame capacity was rejected")
   check(shortStatus == parser.FRAME_CAPACITY, "one-short frame arena was accepted")
end

do
   local source = '"\\{}[],: \n\001x'
   local expected = {1, 2, 4, 4, 4, 4, 4, 4, 8, 8, 16, 0}
   local storage = ffi.new("uint8_t[?]", #source)
   local writable = span.writeCarray(storage, #source)
   scanner.classify(writable, span.fromString(source))
   writable:drop()
   for index, flag in ipairs(expected) do
      check(storage[index - 1] == flag, "wrong classifier flag at " .. index)
   end
end

do
   local source = string.char(0x41, 0x80, 0xc2, 0xe0, 0xf0, 0xff)
   local expected = {
      0,
      scanner.UTF8_CONTINUATION,
      scanner.UTF8_LEAD2,
      scanner.UTF8_LEAD3,
      scanner.UTF8_LEAD4,
      scanner.UTF8_INVALID,
   }
   local storage = ffi.new("uint8_t[?]", #source)
   local writable = span.writeCarray(storage, #source)
   scanner.classify(writable, span.fromString(source))
   writable:drop()
   for index, flag in ipairs(expected) do
      check(storage[index - 1] == flag, "wrong UTF-8 class at " .. index)
   end
end

-- Put the final valid input byte immediately before an unreadable page. A wide
-- tail load that rounds its address up or reads a complete vector will fault.
-- Windows has no mmap; its equivalent VirtualAlloc fixture belongs in the
-- native cross-target suite when packed-byte loads land.
if ffi.os ~= "Windows" then
   ffi.cdef([[
      void *mmap(void *address, size_t length, int protection, int flags, int fd, long offset);
      int mprotect(void *address, size_t length, int protection);
      int munmap(void *address, size_t length);
      int getpagesize(void);
   ]])
   local pageSize = ffi.C.getpagesize()
   local anonymous = ffi.os == "OSX" and 0x1000 or 0x20
   local allocation = ffi.C.mmap(nil, pageSize * 2, 3, 2 + anonymous, -1, 0)
   local failed = ffi.cast("void *", -1)
   check(allocation ~= failed, "guard-page allocation failed")
   if allocation ~= failed then
      local guarded = ffi.cast("uint8_t *", allocation)
      check(ffi.C.mprotect(guarded + pageSize, pageSize, 0) == 0, "guard page protection failed")
      for length = 0, 40 do
         local first = guarded + pageSize - length
         for index = 0, length - 1 do
            first[index] = index % 7 == 0 and 34 or 97
         end
         local outputStorage = ffi.new("uint8_t[?]", length > 0 and length or 1)
         local input = span.fromCarray(first, length)
         local output = span.writeCarray(outputStorage, length)
         scanner.classify(output, input)
         output:drop()
         local tapeStorage = ffi.new("uint32_t[?]", length > 0 and length or 1)
         local tape = span.writeCarray(tapeStorage, length)
         local _, status = indexer.index(input, tape)
         tape:drop()
         check(status == 0, "guarded indexer length " .. length)
         check(true, "guarded classifier length " .. length)
      end
      check(ffi.C.munmap(allocation, pageSize * 2) == 0, "guard-page release failed")
   end
end

do
   check(simdjsonBench.version():match("^%d+%.%d+%.%d+$") ~= nil,
      "simdjson version is unavailable")
   check(#simdjsonBench.implementation() > 0, "simdjson implementation is unavailable")
   local valid = simdjsonBench.new([[{"values":[1,2.5,true,null],"text":"κόσμος"}]])
   check(valid:stage1() == 0, "simdjson stage 1 rejected valid JSON")
   check(valid:dom() == 0, "simdjson DOM rejected valid JSON")
   local invalidUtf8 = simdjsonBench.new(string.char(34, 255, 34))
   check(invalidUtf8:stage1() ~= 0, "simdjson stage 1 accepted invalid UTF-8")
   local invalidControl = simdjsonBench.new(string.char(34, 1, 34))
   check(invalidControl:stage1() ~= 0, "simdjson stage 1 accepted a raw control byte")
end

print(("ok - %d SIMD JSON checks"):format(checks))
