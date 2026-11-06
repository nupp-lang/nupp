local bytes = require("nupp.compiler.vm.imagebytes")
local graphimage = require("nupp.compiler.vm.graphimage")
local legacyimage = require("nupp.compiler.vm.legacyimage")
local graph = require("nupp.compiler.vm.graph")
local M = {}

local function hex(value)
    return (value:gsub(".", function(c)
        return string.format("%02x", c:byte())
    end))
end

local function refuses(action, message)
    local ok, problem = pcall(action)
    assert(not ok, "accepted an invalid byte encoding")
    assert(tostring(problem):find(message, 1, true), tostring(problem))
end

function M.wordsAndShiftedVarintsKeepExactBoundaries()
    for _, row in ipairs({
        {0, "00000000", "01"},
        {126, "7e000000", "7f"},
        {127, "7f000000", "8001"},
        {255, "ff000000", "8002"},
        {16382, "fe3f0000", "ff7f"},
        {16383, "ff3f0000", "808001"},
        {4294967294, "feffffff", "ffffffff0f"},
        {4294967295, "ffffffff", "00"},
    }) do
        assert(hex(bytes.wordbytes(row[1])) == row[2])
        assert(hex(bytes.varint(row[1])) == row[3])
    end
    for _, image in ipairs({graphimage, legacyimage}) do
        for _, invalid in ipairs({-1, 0.5, 4294967296, math.huge}) do
            refuses(
                function()
                    image.encoder().finish({entry = invalid})
                end,
                "image word out of range"
            )
        end
    end
end

function M.wideIntegersRetainExactTextAndNumberRules()
    for _, row in ipairs({
        {"0", "0000000000000000"},
        {"+65536", "0000010000000000"},
        {"-1", "ffffffffffffffff"},
        {"9223372036854775807", "ffffffffffffff7f"},
        {"-9223372036854775808", "0000000000000080"},
        {"18446744073709551615", "ffffffffffffffff"},
        {"0x0123456789abcdef", "efcdab8967452301"},
        {"-0X8000000000000000", "0000000000000080"},
    }) do
        assert(hex(bytes.widetextbytes(row[1])) == row[2])
    end
    for _, row in ipairs({
        {0, "0000000000000000"},
        {-1, "ffffffffffffffff"},
        {4294967296, "0000000001000000"},
        {9007199254740991, "ffffffffffff1f00"},
        {-9007199254740991, "010000000000e0ff"},
    }) do
        assert(hex(bytes.widebytes(row[1])) == row[2])
    end
    for _, invalid in ipairs({"", "+", "0x", "1.5", "0xg", "12x", "18446744073709551616", "-0x10000000000000000"}) do
        refuses(
            function()
                bytes.widetextbytes(invalid)
            end,
            "wide literal"
        )
    end
    for _, invalid in ipairs({0.5, 9007199254740992, -9007199254740992, math.huge, 0 / 0}) do
        refuses(
            function()
                bytes.widebytes(invalid)
            end,
            "outside the exact integer range"
        )
    end
end

function M.binary64KeepsSpecialValuesAndExactMantissas()
    for _, row in ipairs({
        {0.0, "0000000000000000"},
        {-0.0, "0000000000000080"},
        {1, "000000000000f03f"},
        {-1, "000000000000f0bf"},
        {1 + 2 ^ -52, "010000000000f03f"},
        {2 ^ -1074, "0100000000000000"},
        {2 ^ -1022, "0000000000001000"},
        {(2 - 2 ^ -52) * 2 ^ 1023, "ffffffffffffef7f"},
        {math.huge, "000000000000f07f"},
        {-math.huge, "000000000000f0ff"},
        {0 / 0, "000000000000f87f"},
    }) do
        assert(hex(bytes.floatbytes(row[1])) == row[2], row[2])
    end
    for _, image in ipairs({graphimage, legacyimage}) do
        assert(image.floatBytes == bytes.floatbytes)
        assert(image.wideBytes == bytes.widebytes)
        assert(image.wideTextBytes == bytes.widetextbytes)
    end
end

local function fixture()
    local g = graph.new(0)
    g.name, g.module = "bytecodec", "fixture"
    g.constants = {
        {kind = "num", value = -0.0},
        {kind = "num", value = 1.5},
        {kind = "int64", value = "-9223372036854775808"},
        {kind = "uint64", value = "18446744073709551615"},
        {kind = "str", value = "A\0Z"},
    }
    graph.block(g).term = {kind = "return", edges = {}}

    return g
end

function M.independentEncodersKeepPreExtractionImageBytes()
    local expected = "4e5550504752414606070a62797465636f646563086669787475726501152d393232333337323033363835343737353830381531383434363734343037333730393535313631350441005a01030000000000000080000000000000f83f0101010002010200010103770101010106040104020504060507060101010201010400000001020100010100000101"
    for _, image in ipairs({graphimage, legacyimage}) do
        assert(hex(image.encode({functions = {fixture()}})) == expected)
        assert(image.MAGIC == "NUPPGRAF" and image.VERSION == 5)
    end
    assert(graphimage.encoder().addRegisters == nil)
    local raw = legacyimage.encoder()
    raw.addRegisters({
        name = "raw",
        module = "fixture",
        nparams = 0,
        constants = {},
        positions = {},
        blocks = {{code = {}, pos = {}, term = {kind = "return", targets = {}}}}
    })
    assert(
        hex(
            raw.finish({})
        ) == "4e55505047524146060404726177086669787475726501010101010100020102000101037703010101010102010400000001"
    )
end

function M.checkedFloatPayloadAdapterStaysGraphOnly()
    local g = fixture()
    g.constants = {{kind = "num", value = bytes.floatbytes(-0.0)}}
    local encoded = graphimage.encode({functions = {g}})
    g.constants[1].value = -0.0
    assert(encoded == graphimage.encode({functions = {g}}))
    g.constants[1].value = "short"
    refuses(
        function()
            graphimage.encode({functions = {g}})
        end,
        "float literal payload must be eight bytes"
    )
end

return M
