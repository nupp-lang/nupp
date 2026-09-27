-- Behavioral tests for the compiler's private one-shot SHA-256 implementation.
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
local digest = require("nupp.digest.internal.sha256")
local data = require("nupp.digest")

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

function M.hashesThePublishedMillionByteMessage()
    check.equal(
        digest.sha256(string.rep("a", 1000000)),
        "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0"
    )
end

function M.isReachedThroughTheDataFacility()
    for _, vector in ipairs(VECTORS) do
        check.equal(data.hexDigest("sha256", vector[1]), vector[2])
    end
end

function M.answersSixtyFourLowercaseHexadecimalDigitsAtEveryLength()
    for length = 0, 200 do
        local answer = digest.sha256(("abcdefghij"):rep(21):sub(1, length))
        check.assert(
            answer:match("^[0-9a-f]+$") ~= nil and #answer == 64,
            ("length %d answered %q"):format(length, answer)
        )
    end
end

-- Independent OpenSSL vectors around the padding choice and whole-block
-- boundaries. 55 is the last length whose tally fits in one final block; 56
-- is the first that needs two.
function M.paddingBoundariesMatchIndependentVectors()
    local vectors = {
        {55, "d5e285683cd4efc02d021a5c62014694958901005d6f71e89e0989fac77e4072"},
        {56, "04c26261370ee7541549d16dee320c723e3fd14671e66a099afe0a377c16888e"},
        {57, "ae14a2563ccf969d99aca69ce6bb74981f734bbf9f655f73b8f06db68cab5217"},
        {63, "75220b47218278e656f2013bb8f0c455a25eaf01e86c64924e9d48d89776d6f2"},
        {64, "7ce100971f64e7001e8fe5a51973ecdfe1ced42befe7ee8d5fd6219506b5393c"},
        {65, "9537c5fdf120482f7d58d25e9ed583f52c02b4e304ea814db1633ad565aed7e9"},
        {119, "000b48d4edf0fa7bee3c6236ecd2785baa5db4eeb8bb54341b029e0d9fa5fb0c"},
        {120, "13f05a0b594787f5ecd315edc96141bd3243203d1b7d4f0836f37308b276ba98"},
        {127, "70156a14adbabf98cff3a71c7084b417abf057a8efd27329ca36b7202c87d81f"},
        {128, "24da1b81d0b16df6428eee73c69fcb2a93c76bc6df706f0c6670fe6bfe800464"},
        {129, "0ec9eb33e74510bcdd1f2ea55206e82f21649c5c2becbf2b433eb475b34c01bd"},
    }
    for _, vector in ipairs(vectors) do
        check.equal(digest.sha256(("x"):rep(vector[1])), vector[2], "length " .. vector[1])
    end
end

-- A digest is over bytes, not over text. An embedded NUL is the case a
-- length-terminated C string would stop at.
function M.hashesEveryByteValueIncludingNul()
    local bytes = {}
    for value = 0, 255 do
        bytes[value + 1] = string.char(value)
    end
    check.equal(digest.sha256(table.concat(bytes)), "40aff2e9d2d8922e47afd4648e6967497158785fbd1da870e7110266bf944880")
    check.equal(digest.sha256("a\0b"), "59b271ae1bbcb1d31d41929817f4b16fb439eb4f31520b5ad1d5ce98920a7138")
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
