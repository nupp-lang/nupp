local valuebuilder = require("serde.valuebuilder")
local jsonbuilder = require("nupp.codec.json.internal.builder")
local test = require("assert")
local u32 = math.u32.wrap
local M = {}

local function finishNumber(source, start, length)
    local builder = valuebuilder.new({})
    valuebuilder.numberslice(builder, source, start, length)
    return valuebuilder.finish(builder)
end

function M.sourceRangesAreExact()
    assert(finishNumber("x12y", u32(1), u32(2)) == 12)

    for _, range in ipairs({
        {start = u32(5), length = u32(0)},
        {start = u32(4), length = u32(1)},
        {start = u32(3), length = u32(2)},
    }) do
        test.raises(
            function()
                local builder = valuebuilder.new({})
                valuebuilder.string(builder, "four", range.start, range.length, false)
            end,
            "string range is out of bounds"
        )
        test.raises(
            function()
                finishNumber("four", range.start, range.length)
            end,
            "number range is out of bounds"
        )
    end

    test.raises(
        function()
            finishNumber("", u32(0), u32(0))
        end,
        "number is invalid"
    )
end

function M.jsonOnlyEntriesLiveBesideTheDecoder()
    -- Byte readers, scratch buffers and stream events are public for any
    -- codec; the pull and serde streams, the retained escape positions and
    -- JSON's number grammar are the decoder's alone.
    for _, name in ipairs({
        "newPull",
        "newSerde",
        "stringEscapes",
        "keyEscapes",
        "scratchEscapeWord",
        "scratchEscapeLength",
        "numberToken",
    }) do
        test.eq(valuebuilder[name], nil, name .. " is not public")
        test.eq(type(jsonbuilder[name]), "function", name .. " is beside the decoder")
    end
    for _, name in ipairs({"new", "newsized", "byte", "byteat", "word", "len", "newbytescratch", "stringscratch"}) do
        test.eq(type(valuebuilder[name]), "function", name .. " stays public")
    end
end

function M.numberTokenRejectsLeadingZero()
    local builder = valuebuilder.new({})
    local parsed = jsonbuilder.numberToken(builder, "01", u32(0), u32(2))
    assert(parsed == u32(2))
    test.raises(
        function()
            valuebuilder.finish(builder)
        end,
        "no root"
    )

    local past = valuebuilder.new({})
    assert(jsonbuilder.numberToken(past, "1", u32(0), u32(2)) == u32(1))
    test.raises(
        function()
            valuebuilder.finish(past)
        end,
        "no root"
    )
end

function M.integerSlicesRejectOtherNumberForms()
    for _, token in ipairs({"", "+1", "1.0", "1e2", " 1"}) do
        test.raises(
            function()
                local builder = valuebuilder.new({})
                valuebuilder.integerslice(builder, token, u32(0), u32(#token))
            end,
            "integer is invalid"
        )
    end
    local builder = valuebuilder.new({})
    valuebuilder.integerslice(builder, "-12345678901234567890", u32(0), u32(21))
    assert(valuebuilder.finish(builder) < -1e19)
end

function M.nestedValuesAndScratchStayIndependent()
    local builder = valuebuilder.newsized({}, u32(3), u32(8))
    local scratch = valuebuilder.newbytescratch(u32(8))
    valuebuilder.setscratchbytes4(scratch, u32(0), u32(0x64636261))
    valuebuilder.openobject(builder, u32(1))
    valuebuilder.keyscratch(builder, scratch, u32(1), u32(2))
    valuebuilder.openarray(builder, u32(2))
    valuebuilder.stringscratch(builder, scratch, u32(0), u32(4))
    valuebuilder.bool(builder, true)
    valuebuilder.close(builder)
    valuebuilder.close(builder)
    local result = valuebuilder.finish(builder)
    assert(result.bc[1] == "abcd" and result.bc[2] == true)

    valuebuilder.resetbytescratch(scratch)
    test.raises(
        function()
            valuebuilder.scratchbyte(scratch, u32(0))
        end,
        "read is out of bounds"
    )
    assert(result.bc[1] == "abcd")
end

return M
