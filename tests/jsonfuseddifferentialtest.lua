-- The AOT fused JSON decoder and the Lunajson provider are two independent
-- readings of the same grammar: one scans with vectors and walks a structural
-- tape, the other is a third-party byte-at-a-time parser Nupp did not write.
-- Where they agree on a corpus they agree because both read JSON, not because
-- one was derived from the other.
--
-- The scan itself is checked a second way, against `referenceScan` below. That
-- is this file's independent scalar reference in the sense
-- `bench/simd-json/src/simd_json/indexer_reference.nupp` is the vector
-- indexer's: it shares no mask, no lane and no tape with the decoder, and it
-- states the same contract -- the first error in byte order, and the one-based
-- position of the byte that raised it.
--
-- Nothing here builds anything. With no linked artifact the `@aot` body runs
-- as ordinary Nupp, which is the same source and the same answers; what it
-- does not exercise is the emitted C, which the `aot` group covers. Every
-- literal below is ASCII, so a byte sequence under test is written as an
-- escape and never as itself.

local fused = require("nupp.codec.json.aot")
local lunajson = require("nupp.runtime.provider.lunajson")

local M = {}

local NULL = setmetatable({}, {__tostring = function() return "null" end})

----------------------------------------------------------------------------
-- The shared corpus
----------------------------------------------------------------------------

-- Documents both decoders must accept and agree on.
local WELL_FORMED = {
    -- Scalars and the whitespace around them.
    "0", "-0", "1", "-1", "123456789", "  42  ", "\t\r\n7\n", "true", "false", "null",
    '""', '"a"', '"hello world"',

    -- Numbers at and around the edges of binary64.
    "1e308", "-1e308", "1.7976931348623157e308", "-1.7976931348623157e308",
    "5e-324", "-5e-324", "2.2250738585072014e-308", "1e-323",
    "9007199254740991", "9007199254740992", "-9007199254740991",
    "0.1", "0.2", "0.30000000000000004", "1e-7", "1E+7", "1e0", "-0.0",
    "123456789012345678901234567890", "0.000000000000000000001",
    "1.000000000000000000000000000000001", "3.141592653589793",

    -- Containers, nesting and mixed shapes.
    "[]", "{}", "[[]]", "[{}]", '{"a":{}}', "[1,2,3]", "[1,[2,[3,[4]]]]",
    '{"a":1,"b":2,"c":3}', '{"a":[1,2],"b":{"c":[3]}}',
    '[null,true,false,0,"",[],{}]',
    '{"":1}', '{"a":null,"b":null}',
    "[ 1 , 2 , 3 ]", '{ "a" : 1 }',
    '{"a":[{"b":[{"c":[{"d":1}]}]}]}',

    -- Escapes, including every simple one and the pair a supplementary
    -- codepoint needs. These are long strings, so a backslash here is the
    -- backslash the decoder sees.
    [["\""]], [["\\"]], [["\/"]], [["\b"]], [["\f"]], [["\n"]], [["\r"]], [["\t"]],
    [["\u0041"]], [["\u00e9"]], [["\u0020"]], [["\u0001"]], [["\u001f"]],
    [["\u00ff"]], [["\u0800"]], [["\uffff"]], [["\ud83d\ude00"]], [["\udbff\udfff"]],
    [["a\\b"]], [["a\\\\b"]], [["\\\""]], [["\\\\\""]], [["a\nb\tc"]],
    [["\u0041\u0042\u0043"]],
    [[{"k\"ey":"v\\alue"}]],
    [[{"\u0041":"\u00e9"}]],

    -- Literal UTF-8 of every scalar length, written as byte escapes.
    '"\195\169"', '"\226\130\172"', '"\240\159\152\128"',
    '"\194\128"', '"\223\191"', '"\224\160\128"', '"\239\191\191"',
    '"\240\144\128\128"', '"\244\143\191\191"',
    '{"\226\130\172":"\240\159\152\128"}',
}

-- Inputs neither decoder may accept.
local MALFORMED = {
    "", "   ", "\n",
    "tru", "fals", "nul", "trues", "True", "NULL",
    "+1", "01", "-", "1.", ".1", "1e", "1e+", "--1", "1.2.3", "Infinity", "NaN",
    "[", "]", "{", "}", "[1", '{"a"', '{"a":', '{"a":1', "[1,", "[1,]", "{,}", "[,]",
    '{"a":1,}', '{"a" 1}', "{a:1}", "{'a':1}", "[1 2]", '{"a":1"b":2}',
    '"unterminated', '"a\\"', '"\\"', '"\\q"', '"\\u"', '"\\u12"', '"\\uZZZZ"',
    [["\ud800"]], [["\udc00"]], [["\ud800\ud800"]], [["\ud800x"]],
    "[1,2,3]extra", "{} {}", "1 2", "null null",
    -- Control bytes are never literal inside a string.
    '"\001"', '"\009"', '"\010"', '"\031"',
    -- A backslash outside a string is not a token.
    "[\\]", "\\", '{"a":\\}',
    -- Malformed UTF-8 of every failing shape.
    '"\128"', '"\191"', '"\192\128"', '"\193\191"', '"\194"', '"\224\128\128"',
    '"\224\159\191"', '"\237\160\128"', '"\240\128\128\128"', '"\244\144\128\128"',
    '"\245\128\128\128"', '"\255"', '"\226\130"', '"\240\159\152"',
    '\226\130\172', '"a\128b"',
}

-- Deep containers, built rather than written out.
local function nested(open, close, depth)
    return string.rep(open, depth) .. "1" .. string.rep(close, depth)
end

local function wideArray(count)
    local parts = {}
    for i = 1, count do
        parts[i] = tostring(i)
    end

    return "[" .. table.concat(parts, ",") .. "]"
end

local function wideObject(count)
    local parts = {}
    for i = 1, count do
        parts[i] = string.format('"k%d":%d', i, i)
    end

    return "{" .. table.concat(parts, ",") .. "}"
end

local function corpus()
    local all = {}
    for _, text in ipairs(WELL_FORMED) do
        all[#all + 1] = text
    end
    for depth = 1, 24 do
        all[#all + 1] = nested("[", "]", depth)
    end
    for _, count in ipairs({1, 2, 3, 15, 16, 17, 31, 32, 33, 63, 64, 65, 200}) do
        all[#all + 1] = wideArray(count)
        all[#all + 1] = wideObject(count)
    end
    -- Strings that straddle every plausible vector and block boundary, plain
    -- and escaped, so the whole-vector path and the byte-at-a-time tail both
    -- cover every shape at least once.
    for length = 0, 80 do
        all[#all + 1] = '"' .. string.rep("a", length) .. '"'
        all[#all + 1] = '["' .. string.rep("a", length) .. '","b"]'
        all[#all + 1] = '"' .. string.rep("\\n", length) .. '"'
        all[#all + 1] = '"' .. string.rep("a", length) .. '\\u00e9"'
        all[#all + 1] = '{"' .. string.rep("k", length) .. '":1}'
        all[#all + 1] = string.rep(" ", length) .. "[1]"
        all[#all + 1] = '"' .. string.rep("\226\130\172", length) .. '"'
    end
    -- Backslash runs of every parity across a vector boundary.
    for slashes = 1, 40 do
        all[#all + 1] = '"' .. string.rep("\\", slashes * 2) .. '"'
        all[#all + 1] = '"' .. string.rep("a", slashes) .. '\\\\"'
    end

    return all
end

----------------------------------------------------------------------------
-- The independent scalar reference for the structural scan
----------------------------------------------------------------------------

local OK, INVALID_UTF8, INVALID_CONTROL, INVALID_BACKSLASH = 0, 2, 3, 4

-- Reads `source` one byte after another and keeps what a JSON structural scan
-- needs: whether it is inside a string, the parity of the backslash run before
-- the current byte, and for UTF-8 how many continuation bytes the last lead
-- still owes and what range the first of them must fall in.
--
-- Answers the first scan error in byte order as a code and the one-based
-- position of the byte that raised it, or `OK, 0`. A UTF-8 scalar the end of
-- the input cut off is raised one past the last byte. It says nothing about
-- the grammar above the bytes; that is what the decoders are compared on.
local function referenceScan(source)
    local inString, slashRun = false, 0
    local owed, constraint, lastNonAscii = 0, 0, -1

    for offset = 0, #source - 1 do
        local byte = source:byte(offset + 1)
        if owed > 0 then
            local continuation = byte >= 128 and byte <= 191
            local outside = constraint == 1 and byte < 160
                or constraint == 2 and byte > 159
                or constraint == 3 and byte < 144
                or constraint == 4 and byte > 143
            if not continuation or outside then
                return INVALID_UTF8, offset + 1
            end
            owed, constraint, lastNonAscii, slashRun = owed - 1, 0, offset, 0
        elseif byte >= 128 then
            if byte < 194 or byte > 244 then
                return INVALID_UTF8, offset + 1
            elseif byte <= 223 then
                owed = 1
            elseif byte <= 239 then
                owed = 2
                if byte == 224 then
                    constraint = 1
                elseif byte == 237 then
                    constraint = 2
                end
            else
                owed = 3
                if byte == 240 then
                    constraint = 3
                elseif byte == 244 then
                    constraint = 4
                end
            end
            lastNonAscii, slashRun = offset, 0
        elseif byte == 92 then
            if not inString then
                return INVALID_BACKSLASH, offset + 1
            end
            slashRun = slashRun + 1
        else
            local escaped = slashRun % 2 == 1
            slashRun = 0
            if byte == 34 and not escaped then
                inString = not inString
            elseif byte < 32 then
                if inString or not (byte == 9 or byte == 10 or byte == 13) then
                    return INVALID_CONTROL, offset + 1
                end
            end
        end
    end

    if owed > 0 then
        return INVALID_UTF8, lastNonAscii + 2
    end

    return OK, 0
end

----------------------------------------------------------------------------
-- Comparison
----------------------------------------------------------------------------

local function render(value, seen)
    local kind = type(value)
    if value == NULL then
        return "null"
    elseif kind ~= "table" then
        if kind == "number" then
            return string.format("%.17g", value)
        end

        return kind .. ":" .. tostring(value)
    end
    seen = seen or {}
    assert(not seen[value], "the decoded value is cyclic")
    seen[value] = true
    local keys = {}
    for key in pairs(value) do
        keys[#keys + 1] = key
    end
    local array = true
    for index = 1, #keys do
        if value[index] == nil then
            array = false
            break
        end
    end
    local parts = {}
    if array then
        for index = 1, #keys do
            parts[index] = render(value[index], seen)
        end
        seen[value] = nil

        return "[" .. table.concat(parts, ",") .. "]"
    end
    table.sort(keys, function(left, right) return tostring(left) < tostring(right) end)
    for index, key in ipairs(keys) do
        parts[index] = string.format("%q", tostring(key)) .. ":" .. render(value[key], seen)
    end
    seen[value] = nil

    return "{" .. table.concat(parts, ",") .. "}"
end

local function decodedBy(provider, text)
    local ok, value = pcall(provider.decode, text, NULL)
    if not ok then
        return nil, tostring(value)
    end

    return render(value), nil
end

local function show(text)
    return (text:gsub("[^\032-\126]", function(c)
        return string.format("<%d>", c:byte())
    end)):sub(1, 60)
end

----------------------------------------------------------------------------
-- The checks
----------------------------------------------------------------------------

function M.theFusedDecoderDecodesEveryCorpusDocumentAsLunajsonDoes()
    local checked = 0
    for _, text in ipairs(corpus()) do
        local mine, myError = decodedBy(fused, text)
        local theirs, theirError = decodedBy(lunajson, text)
        assert(
            myError == nil and theirError == nil,
            string.format(
                "%s should be well formed for both: fused=%s lunajson=%s",
                show(text),
                tostring(myError),
                tostring(theirError)
            )
        )
        assert(mine == theirs, string.format("%s decodes to %s but lunajson says %s", show(text), mine, theirs))
        checked = checked + 1
    end
    assert(checked > 700, "the corpus shrank to " .. checked .. " documents")
end

function M.theFusedDecoderRejectsEveryDocumentLunajsonRejects()
    for _, text in ipairs(MALFORMED) do
        local mine, myError = decodedBy(fused, text)
        local theirs, theirError = decodedBy(lunajson, text)
        assert(myError ~= nil, string.format("%s decoded to %s but is malformed", show(text), tostring(mine)))
        assert(
            theirError ~= nil,
            string.format("lunajson accepted the malformed %s as %s", show(text), tostring(theirs))
        )
    end
end

function M.theFusedScanReportsTheSameFirstErrorAsTheScalarReference()
    local checked = 0
    for _, text in ipairs(MALFORMED) do
        local code, position = referenceScan(text)
        if code ~= OK then
            local _, message = decodedBy(fused, text)
            assert(message ~= nil, string.format("%s decoded, but the reference raises %d at %d", show(text), code, position))
            local reported = tonumber(message:match("at byte (%d+)"))
            assert(reported ~= nil, string.format("%s reported %q, which names no byte", show(text), message))
            assert(
                reported == position,
                string.format("%s raises at byte %d but the reference says %d", show(text), reported, position)
            )
            checked = checked + 1
        end
    end
    assert(checked > 20, "the reference agreed on only " .. checked .. " inputs")
end

-- Malformed byte sequences on their own, to be placed at a chosen offset.
local BAD_UTF8 = {
    "\128", "\191", "\192\128", "\193\191", "\194", "\194\065", "\224\128\128",
    "\224\159\191", "\237\160\128", "\237\191\191", "\240\128\128\128",
    "\240\143\191\191", "\244\144\128\128", "\245\128\128\128", "\255",
    "\226\130\065", "\240\159\152\065", "\226\130", "\240\159\152",
}

function M.theFusedScanFindsTheSameBadByteAtEveryVectorOffset()
    -- The checks above are all short enough to take the byte-at-a-time tail.
    -- These push the same sequences past whole vectors, so the lookup4
    -- validator is what finds them and its lane is what names the byte. The
    -- padding is ASCII inside a string, and a trailing quote is omitted on
    -- purpose: the UTF-8 error comes first in byte order either way.
    local checked = 0
    for _, bad in ipairs(BAD_UTF8) do
        for pad = 0, 72 do
            local text = '"' .. string.rep("a", pad) .. bad .. '"'
            local code, position = referenceScan(text)
            assert(code == INVALID_UTF8, string.format("the reference missed %s at pad %d", show(text), pad))
            local _, message = decodedBy(fused, text)
            assert(message ~= nil, string.format("%s decoded but holds bad UTF-8", show(text)))
            local reported = tonumber(message:match("at byte (%d+)"))
            assert(
                reported == position,
                string.format("%s raises at byte %s but the reference says %d", show(text), tostring(reported), position)
            )
            checked = checked + 1
        end
    end
    assert(checked > 1000, "only " .. checked .. " offsets were checked")
end

function M.wellFormedUnicodeSurvivesEveryVectorOffset()
    -- The same sweep for text that is valid, so a validator that is merely
    -- eager cannot pass the check above.
    local scalars = {"\194\128", "\223\191", "\224\160\128", "\239\191\191",
        "\240\144\128\128", "\244\143\191\191", "\226\130\172"}
    for _, scalar in ipairs(scalars) do
        for pad = 0, 72 do
            local text = '"' .. string.rep("a", pad) .. scalar .. string.rep("b", 3) .. '"'
            local mine, myError = decodedBy(fused, text)
            local theirs = decodedBy(lunajson, text)
            assert(myError == nil, string.format("%s was refused: %s", show(text), tostring(myError)))
            assert(mine == theirs, string.format("%s decoded differently from lunajson", show(text)))
        end
    end
end

function M.theScalarReferenceAcceptsEveryWellFormedCorpusDocument()
    for _, text in ipairs(corpus()) do
        local code, position = referenceScan(text)
        assert(code == OK, string.format("the reference rejected the well-formed %s at byte %d", show(text), position))
    end
end

function M.decodingIsUnchangedByTheSourceLength()
    -- One document at every offset a vector may start on, so the whole-vector
    -- path and the byte-at-a-time tail both cover every byte of it.
    for pad = 0, 65 do
        local text = string.rep(" ", pad) .. '{"a":[1,"b\\n",null,true],"c":{"d":-2.5}}'
        local mine, myError = decodedBy(fused, text)
        local theirs = decodedBy(lunajson, text)
        assert(myError == nil, string.format("padding by %d broke the decoder: %s", pad, tostring(myError)))
        assert(mine == theirs, string.format("padding by %d changed the value", pad))
    end
end

-- Sweep sparse Unicode transitions and short tails across vector boundaries.
-- A later malformed sequence must never displace the first error in the input.
function M.scanPreservesSparseUnicodeTransitionsAndFirstErrors()
    local euro, smile = "\226\130\172", "\240\159\152\128"
    for pad = 0, 260 do
        for _, gap in ipairs({0, 15, 16, 31, 32, 63, 64, 65, 127, 128, 129}) do
            local text = '"' .. string.rep("a", pad) .. euro .. string.rep("b", gap) .. smile .. string.rep("c", pad % 67) .. '"'
            local mine, message = decodedBy(fused, text)
            local theirs, other = decodedBy(lunajson, text)
            assert(message == nil and other == nil, "mixed Unicode refused at " .. pad .. ":" .. gap .. ": " .. tostring(message))
            assert(mine == theirs, "mixed Unicode changed at " .. pad .. ":" .. gap)
        end
        for _, bad in ipairs(BAD_UTF8) do
            for _, suffix in ipairs({"", string.rep("z", 65)}) do
                local text = '"' .. string.rep("a", pad) .. bad .. suffix .. '"'
                local code, position = referenceScan(text)
                assert(code == INVALID_UTF8, "reference missed malformed UTF-8")
                local _, message = decodedBy(fused, text)
                local reported = message and tonumber(message:match("at byte (%d+)"))
                assert(reported == position, "malformed UTF-8 at " .. pad .. ": " .. tostring(reported) .. " vs " .. position)
            end
        end
        -- A control error before later malformed Unicode stays first.
        local text = '"' .. string.rep("a", pad) .. "\001" .. string.rep("b", 65) .. "\255\""
        local code, position = referenceScan(text)
        assert(code == INVALID_CONTROL)
        local _, message = decodedBy(fused, text)
        assert(message and tonumber(message:match("at byte (%d+)")) == position, "later Unicode displaced earlier control error")
    end
end

return M
