-- Behavioural tests for nupp.data.digest, which is nupp.data.sha256.
--
-- The digest is an `@aot` entry, so it has two lowerings: compiled ahead of
-- time where a target asks for that, and the same source on LuaJIT where it
-- does not. This suite runs the second. `bench/sha256` holds the first against
-- this one and against the C the stamped binary still boots with, on the same
-- cases, because the two lowerings agreeing is the whole claim `@aot` makes.
--
-- The published vectors pin the algorithm. Everything after them is about the
-- padding: SHA-256's failure modes cluster at the block boundary, at the
-- 56-byte point where the length tally stops fitting beside the message, and
-- at the point where that forces a second padded block.

local check = require("assert")
local digest = require("nupp.data.digest")
local data = require("nupp.data")

local M = {}

-- FIPS 180-4's examples and the two long messages published with them.
local VECTORS = {
   {"", "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"},
   {"abc", "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"},
   {
      "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq",
      "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1",
   },
   {
      "abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmnhijklmno"
         .. "ijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu",
      "cf5b16a778af8380036ce59e7b0492370b249b11e8f07a51afac45037afee9d1",
   },
}

function M.matchesThePublishedVectors()
   for index, vector in ipairs(VECTORS) do
      check.equal(digest.sha256(vector[1]), vector[2], "vector " .. index)
   end
end

function M.hashesAMillionBlocksWithoutDrifting()
   check.equal(
      digest.sha256(string.rep("a", 1000000)),
      "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0"
   )
end

function M.isReachedThroughTheDataFacility()
   for _, vector in ipairs(VECTORS) do
      check.equal(data.sha256(vector[1]), vector[2])
   end
end

function M.answersSixtyFourLowercaseHexadecimalDigitsAtEveryLength()
   for length = 0, 200 do
      local answer = digest.sha256(("abcdefghij"):rep(21):sub(1, length))
      check.assert(answer:match("^[0-9a-f]+$") ~= nil and #answer == 64,
         ("length %d answered %q"):format(length, answer))
   end
end

-- Where the padding decides between one final block and two. 55 is the last
-- length whose terminator and eight-byte tally still fit beside it, 56 is the
-- first that does not, and 64 and 128 are the whole blocks either side.
function M.paddingBoundariesEachGetTheirOwnAnswer()
   local seen = {}
   for _, length in ipairs({55, 56, 57, 63, 64, 65, 119, 120, 127, 128, 129}) do
      local answer = digest.sha256(("x"):rep(length))
      check.assert(seen[answer] == nil,
         ("lengths %s and %d hash alike"):format(tostring(seen[answer]), length))
      seen[answer] = length
   end
end

-- A digest is over bytes, not over text. An embedded NUL is the case a
-- length-terminated C string would stop at.
function M.hashesEveryByteValueIncludingNul()
   local bytes = {}
   for value = 0, 255 do
      bytes[value + 1] = string.char(value)
   end
   check.equal(
      digest.sha256(table.concat(bytes)),
      "40aff2e9d2d8922e47afd4648e6967497158785fbd1da870e7110266bf944880"
   )
   check.equal(
      digest.sha256("a\0b"),
      "59b271ae1bbcb1d31d41929817f4b16fb439eb4f31520b5ad1d5ce98920a7138"
   )
end

-- The entry reuses one scratch buffer per call and, when compiled, one
-- registered closure table per Lua state. A digest leaking into the next one
-- would show up as an answer that depends on what was hashed before it.
function M.oneCallDoesNotDisturbTheNext()
   local first = digest.sha256("first")
   digest.sha256(("y"):rep(5000))
   digest.sha256("")
   check.equal(digest.sha256("first"), first)
end

return M
