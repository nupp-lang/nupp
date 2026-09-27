local valuebuilder = require("nupp.codec.valuebuilder")
local test = require("nupp.test")
local u32 = nupp.math.u32.wrap
local M = {}

local function finishNumber(source, start, length)
    local builder = valuebuilder.new({})
    valuebuilder.numberSlice(builder, source, start, length)
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

function M.numberTokenRejectsLeadingZero()
    local builder = valuebuilder.new({})
    local parsed = valuebuilder.numberToken(builder, "01", u32(0), u32(2))
    assert(parsed == u32(2))
    test.raises(
        function()
            valuebuilder.finish(builder)
        end,
        "no root"
    )

    local past = valuebuilder.new({})
    assert(valuebuilder.numberToken(past, "1", u32(0), u32(2)) == u32(1))
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
                valuebuilder.integerSlice(builder, token, u32(0), u32(#token))
            end,
            "integer is invalid"
        )
    end
    local builder = valuebuilder.new({})
    valuebuilder.integerSlice(builder, "-12345678901234567890", u32(0), u32(21))
    assert(valuebuilder.finish(builder) < -1e19)
end

function M.nestedValuesAndScratchStayIndependent()
    local builder = valuebuilder.newSized({}, u32(3), u32(8))
    local scratch = valuebuilder.newByteScratch(u32(8))
    valuebuilder.setScratchBytes4(scratch, u32(0), u32(0x64636261))
    valuebuilder.openObject(builder, u32(1))
    valuebuilder.keyScratch(builder, scratch, u32(1), u32(2))
    valuebuilder.openArray(builder, u32(2))
    valuebuilder.stringScratch(builder, scratch, u32(0), u32(4))
    valuebuilder.boolean(builder, true)
    valuebuilder.close(builder)
    valuebuilder.close(builder)
    local result = valuebuilder.finish(builder)
    assert(result.bc[1] == "abcd" and result.bc[2] == true)

    valuebuilder.resetByteScratch(scratch)
    test.raises(
        function()
            valuebuilder.scratchByte(scratch, u32(0))
        end,
        "read is out of bounds"
    )
    assert(result.bc[1] == "abcd")
end

return M
