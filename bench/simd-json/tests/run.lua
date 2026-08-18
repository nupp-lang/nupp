local ffi = require("ffi")
local cjson = require("cjson")
local json = require("simd_json")
local arena = require("simd_json.arena")
local indexer = require("simd_json.indexer")
local parser = require("simd_json.parser")
local scanner = require("simd_json.scanner")
local span = require("nupp.span")
local valueBuilder = require("nupp.value_builder")

ffi.cdef[[
   typedef struct { uint32_t v1; uint32_t v2; uint32_t v3; } SimdJsonIndexResult;
   SimdJsonIndexResult ks_index_forced_scalar(
      const uint8_t *source, uint32_t *tape, size_t count_source, size_t count_tape
   );
]]
local nativeExtension = ffi.os == "Windows" and ".dll" or ffi.os == "OSX" and ".dylib" or ".so"
local native = ffi.load("build/lib/libsimd_json_aot" .. nativeExtension)
local NodeArray = ffi.typeof("$[?]", parser.Node)
local FrameArray = ffi.typeof("$[?]", parser.Frame)

local checks = 0
local numberBits = ffi.typeof("union { double number; uint64_t bits; }")
local function check(condition, message)
   checks = checks + 1
   assert(condition, message)
end

local function same(left, right)
   if left == json.null then
      return right == cjson.null
   end
   if right == cjson.null then
      return left == json.null
   end
   if type(left) ~= type(right) then
      return false
   end
   if type(left) ~= "table" then
      if type(left) == "number" then
         local leftBits = numberBits()
         local rightBits = numberBits()
         leftBits.number = left
         rightBits.number = right
         return tostring(leftBits.bits) == tostring(rightBits.bits)
      end
      return left == right
   end
   for key, value in pairs(left) do
      if not same(value, right[key]) then
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
   "5e-324",
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
   local result = native.ks_index_forced_scalar(
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
   local builderActual = arena.decodeBuilder(source, json.null)
   local fusedActual = arena.decodeFused(source, json.null)
   local expected = cjson.decode(source)
   check(same(actual, expected), "differential mismatch for " .. source)
   check(same(arenaActual, expected), "arena differential mismatch for " .. source)
   check(same(builderActual, expected), "builder differential mismatch for " .. source)
   check(same(fusedActual, expected), "fused differential mismatch for " .. source)
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
   local stream = valueBuilder.new(json.null)
   valueBuilder.openObject(stream, nupp.math.u32.wrap(2))
   valueBuilder.key(stream, "alpha", nupp.math.u32.wrap(0), nupp.math.u32.wrap(5), false)
   valueBuilder.openArray(stream, nupp.math.u32.wrap(2))
   valueBuilder.number(stream, 1)
   valueBuilder.null(stream)
   valueBuilder.close(stream)
   valueBuilder.key(stream, "escaped\\n", nupp.math.u32.wrap(0), nupp.math.u32.wrap(9), true)
   valueBuilder.boolean(stream, true)
   valueBuilder.close(stream)
   local built = valueBuilder.finish(stream)
   check(built.alpha[1] == 1 and built.alpha[2] == json.null and built["escaped\n"] == true,
      "ordinary value stream built the wrong graph")
end

do
   local document = arena.parse([[{"safe":[1,2,3]}]])
   local nodeBytes = ffi.string(document.nodes, document.nodeCount * ffi.sizeof(parser.Node))
   local linkBytes = ffi.string(document.links, math.max(document.nodeCount - 1, 0) * 4)
   local fallback = valueBuilder.materializeTree(
      nodeBytes, linkBytes, document.source, document.root, json.null)
   check(same(fallback, cjson.decode(document.source)),
      "ordinary value-tree fallback differs from the native builder")
   local root = document.root
   document.root = document.nodeCount + 1
   check(not pcall(arena.materializeBuilder, document, json.null),
      "builder accepted an out-of-range root")
   document.root = root
   local tag = document.nodes[root - 1].tag
   document.nodes[root - 1].tag = 99
   check(not pcall(arena.materializeBuilder, document, json.null),
      "builder accepted an unknown node tag")
   document.nodes[root - 1].tag = tag
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
      local source = cjson.encode(value)
      check(same(arena.decode(source, json.null), cjson.decode(source)),
         "generated arena differential mismatch at case " .. case)
      check(same(arena.decodeBuilder(source, json.null), cjson.decode(source)),
         "generated builder differential mismatch at case " .. case)
      check(same(arena.decodeFused(source, json.null), cjson.decode(source)),
         "generated fused differential mismatch at case " .. case)
      local truncated = source:sub(1, -2)
      check(not pcall(arena.decode, truncated, json.null),
         "truncated generated document accepted at case " .. case)
      check(not pcall(arena.decodeFused, truncated, json.null),
         "truncated generated document accepted by fused parser at case " .. case)
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

   local invalidSource = '"' .. padding .. string.char(0xf0, 0x9f, 0x99) .. '"'
   valid, why = json.validate(invalidSource)
   check(not valid and type(why) == "string", "truncated boundary UTF-8 accepted at " .. prefix)
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

print(("ok - %d SIMD JSON checks"):format(checks))
