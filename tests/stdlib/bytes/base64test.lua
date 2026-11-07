-- Behavioral tests for binary Base64 encoding.
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
local byteapi = require("bytes")

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
        check.eq(byteapi.base64encode(vector[1]), vector[2])
        check.eq(byteapi.base64decode(vector[2]), vector[1])
    end
end

--- The whole alphabet, so no entry of the table or its inverse goes untried.
function M.everyAlphabetPositionRoundTrips()
    local bytes = {}
    for value = 0, 255 do
        bytes[#bytes + 1] = string.char(value)
    end
    local all = table.concat(bytes)
    local encoded = byteapi.base64encode(all)
    check.eq(#encoded, 344)
    check.eq(byteapi.base64decode(encoded), all)
end

--- Every length across the group boundary and the block the entry reads as
--- three words, which is where a padding or a tail mistake shows.
function M.everyLengthThroughTwoBlocksRoundTrips()
    local bytes = {}
    for length = 0, 64 do
        local value = table.concat(bytes)
        check.eq(byteapi.base64decode(byteapi.base64encode(value)), value)
        check.eq(#byteapi.base64encode(value) % 4, 0)
        bytes[#bytes + 1] = string.char(length % 256)
    end
end

function M.paddingIsExactlyWhatTheRemainderAsksFor()
    check.eq(byteapi.base64encode("a"):sub(-2), "==")
    check.eq(byteapi.base64encode("ab"):sub(-1), "=")
    check.eq(byteapi.base64encode("abc"):sub(-1) == "=", false)
end

-- Text that is not base64 is an ordinary answer, nil and the reason, as
-- bytes.hexdecode gives, rather than a raise.
local function refused(text)
    local value, reason = byteapi.base64decode(text)
    check.eq(value, nil, text)
    check.eq(type(reason), "string", text)
    return reason
end

--- The decoder reports rather than returning whatever the inverse table holds
--- for a byte outside the alphabet.
function M.aCharacterOutsideTheAlphabetIsRefused()
    check.eq(refused("ab!="), "base64 input is not canonical padded base64")
    refused("....")
    refused("Zm9v\128\129\130\131")
end

--- A length that is not a whole quantum, which the padding rules make
--- unrepresentable rather than merely wrong.
function M.decodeRefusesALengthThatIsNotAQuantum()
    check.eq(refused("abc"), "base64 input length is not a multiple of four")
    refused("Zm9vY")
end

--- Padding only closes the final quantum, and unused bits must be zero so one
--- byte string has one base64 representation.
function M.decodeRefusesMalformedOrNoncanonicalPadding()
    for _, value in ipairs({"====", "A===", "AA=A", "A=AA", "=AAA", "AA==AAAA", "AAAA====", "Zh==", "Zm9="}) do
        refused(value)
    end
end

return M
