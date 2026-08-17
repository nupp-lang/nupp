local ffi = require("ffi")
local cjson = require("cjson")
local json = require("simd_json")
local scanner = require("simd_json.scanner")
local span = require("nupp.span")

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
}

for _, source in ipairs(corpus) do
   local actual = json.decode(source)
   local expected = cjson.decode(source)
   check(same(actual, expected), "differential mismatch for " .. source)
   local valid, why = json.validate(source)
   check(valid and why == nil, "valid input rejected: " .. tostring(why))
end

local invalid = {
   "",
   "nul",
   "01",
   "1.",
   "1e",
   "[1,]",
   [[{"a":1,}]],
   [["unterminated]],
   [["\x"]],
   [["\uD800"]],
   [["\uDC00"]],
   "true false",
   '"control\001byte"',
   '"invalid utf8 \255"',
}

for _, source in ipairs(invalid) do
   local valid, why = json.validate(source)
   check(not valid and type(why) == "string", "invalid input accepted: " .. source)
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

print(("ok - %d SIMD JSON checks"):format(checks))
