-- Behavioural tests for nupp.data.base64.
--
-- Encoding is an `@aot` entry, so it has two lowerings: compiled ahead of time
-- where a target asks for that, and the same source on LuaJIT where it does
-- not. This suite runs the second. `bench/base64` holds the first against this
-- one, against hand-written C, and against a memory copy.
--
-- RFC 4648's own vectors pin the alphabet and the padding. Everything after
-- them is about the two boundaries this encoding has: the three-byte group,
-- where a remainder of one or two bytes changes how many `=` follow, and the
-- twelve-byte block the compiled entry reads as three words.

local check = require("assert")
local base64 = require("nupp.data.base64")

local M = {}

-- RFC 4648 section 10.
local VECTORS = {
   {"", ""},
   {"f", "Zg=="},
   {"fo", "Zm8="},
   {"foo", "Zm9v"},
   {"foob", "Zm9vYg=="},
   {"fooba", "Zm9vYmE="},
   {"foobar", "Zm9vYmFy"},
}

function M.publishedVectorsEncodeAndDecode()
   for _, vector in ipairs(VECTORS) do
      check.equal(base64.encode(vector[1]), vector[2])
      check.equal(base64.decode(vector[2]), vector[1])
   end
end

--- The whole alphabet, so no entry of the table or its inverse goes untried.
function M.everyAlphabetPositionRoundTrips()
   local bytes = {}
   for value = 0, 255 do
      bytes[#bytes + 1] = string.char(value)
   end
   local all = table.concat(bytes)
   local encoded = base64.encode(all)
   check.equal(#encoded, 344)
   check.equal(base64.decode(encoded), all)
end

--- Every length across the group boundary and the block the entry reads as
--- three words, which is where a padding or a tail mistake shows.
function M.everyLengthThroughTwoBlocksRoundTrips()
   local bytes = {}
   for length = 0, 64 do
      local value = table.concat(bytes)
      check.equal(base64.decode(base64.encode(value)), value)
      check.equal(#base64.encode(value) % 4, 0)
      bytes[#bytes + 1] = string.char(length % 256)
   end
end

function M.paddingIsExactlyWhatTheRemainderAsksFor()
   check.equal(base64.encode("a"):sub(-2), "==")
   check.equal(base64.encode("ab"):sub(-1), "=")
   check.equal(base64.encode("abc"):sub(-1) == "=", false)
end

function M.aLengthThatIsNotAQuantumIsRefused()
   check.equal(pcall(base64.decode, "abc"), false)
   check.equal(pcall(base64.decode, "a"), false)
end

--- The decoder reports rather than returning whatever the inverse table holds
--- for a byte outside the alphabet.
function M.aCharacterOutsideTheAlphabetIsRefused()
   check.equal(pcall(base64.decode, "ab!="), false)
   check.equal(pcall(base64.decode, "....") , false)
   check.equal(pcall(base64.decode, "Zm9v\128\129\130\131"), false)
end

return M
