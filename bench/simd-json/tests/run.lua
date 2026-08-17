local ffi = require("ffi")
local cjson = require("cjson")
local json = require("simd_json")
local indexer = require("simd_json.indexer")
local scanner = require("simd_json.scanner")
local span = require("nupp.span")

ffi.cdef[[
   typedef struct { uint32_t v1; uint32_t v2; uint32_t v3; } SimdJsonIndexResult;
   SimdJsonIndexResult ks_index_forced_scalar(
      const uint8_t *source, uint32_t *tape, size_t count_source, size_t count_tape
   );
]]
local nativeExtension = ffi.os == "Windows" and ".dll" or ffi.os == "OSX" and ".dylib" or ".so"
local native = ffi.load("build/lib/libsimd_json_aot" .. nativeExtension)

local checks = 0
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

for _, source in ipairs(corpus) do
   local actual = json.decode(source)
   local expected = cjson.decode(source)
   check(same(actual, expected), "differential mismatch for " .. source)
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
