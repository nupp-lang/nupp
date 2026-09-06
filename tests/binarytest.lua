local check = require("assert")
local binary = require("nupp.data.binary")
local M = {}
local magic = "NVB\1"
local function refuses(fn, fragment)
    local ok, reason = pcall(fn)
    check.equal(ok, false)
    check.equal(tostring(reason):find(fragment, 1, true) ~= nil, true)
end

function M.fixedWireVectors()
    check.equal(binary.encode(nil), magic .. "\0")
    check.equal(binary.encode(false), magic .. "\1")
    check.equal(binary.encode(true), magic .. "\2")
    check.equal(binary.encode(1), magic .. "\3\0\0\0\0\0\0\240\63")
    check.equal(binary.encode("\0\255"), magic .. "\4\2\0\0\0\0\255")
    check.equal(binary.encode({}), magic .. "\5\0\0\0\0")
    check.equal(binary.decode(magic .. "\3\0\0\0\0\0\0\240\63"), 1)
    check.equal(binary.decode(magic .. "\0"), nil)
end

function M.numericBoundaries()
    for _, value in ipairs({
        0,
        -0.0,
        1,
        -1,
        1.5,
        math.pi,
        2 ^ -1074,
        2 ^ -1022,
        2 ^ -1022 - 2 ^ -1074,
        2 ^ 53 - 1,
        2 ^ 53,
        1.7976931348623157e308
    }) do
        local result = binary.decode(binary.encode(value))
        check.equal(result, value)
        if value == 0 then
            check.equal(1 / result, 1 / value)
        end
    end
end

function M.randomFiniteNumbers()
    -- Walk exponents and fraction bits without depending on a global RNG seed.
    for exponent = -1074, 1023, 7 do
        for _, mantissa in ipairs({1, 1.0000000000000002, 1.25, 1.9999999999999998}) do
            local value = math.ldexp(mantissa, exponent)
            check.equal(binary.decode(binary.encode(value)), value)
            check.equal(binary.decode(binary.encode(-value)), -value)
        end
    end
end

function M.binaryStringsAndSparseNumericKeys()
    local bytes = {}
    for i = 0, 255 do
        bytes[#bytes + 1] = string.char(i)
    end
    local payload = table.concat(bytes)
    local original = {[0] = payload, [-3.5] = false, [10000] = {x = 4}, ["0"] = true}
    local decoded = binary.decode(binary.encode(original))
    check.equal(decoded[0], payload)
    check.equal(decoded[-3.5], false)
    check.equal(decoded[10000].x, 4)
    check.equal(decoded["0"], true)
    decoded[10000].x = 10
    check.equal(original[10000].x, 4)
end

function M.stableOrderingAndCopiedAliases()
    local shared = {x = 2}
    local first = {z = shared, a = shared, [3] = "three", [1] = "one"}
    local second = {[1] = "one", [3] = "three", a = {x = 2}, z = {x = 2}}
    check.equal(binary.encode(first), binary.encode(second))
    local result = binary.decode(binary.encode(first))
    check.equal(result.a == result.z, false)
end

function M.refusesUnsupportedValues()
    local cyclic = {};
    cyclic.self = cyclic
    refuses(
        function()
            binary.encode(cyclic)
        end,
        "cycle"
    )
    refuses(
        function()
            binary.encode(setmetatable({}, {}))
        end,
        "plain tables"
    )
    refuses(
        function()
            binary.encode(function()
            end)
        end,
        "cannot encode"
    )
    refuses(
        function()
            binary.encode({[true] = 1})
        end,
        "table keys"
    )
    for _, value in ipairs({math.huge, -math.huge, 0 / 0}) do
        refuses(
            function()
                binary.encode(value)
            end,
            "finite"
        )
    end
end

function M.refusesMalformedDocuments()
    local valid = binary.encode({[1] = "bytes", x = {true, false, -3.5}})
    for i = 0, #valid - 1 do
        check.equal(pcall(binary.decode, valid:sub(1, i)), false)
    end
    refuses(
        function()
            binary.decode(valid .. "x")
        end,
        "trailing"
    )
    refuses(
        function()
            binary.decode("NVB\2\0")
        end,
        "header"
    )
    refuses(
        function()
            binary.decode(magic .. "\6")
        end,
        "unknown tag"
    )
    refuses(
        function()
            binary.decode(magic .. "\3\0\0\0\0\0\0\240\127")
        end,
        "finite"
    )
    refuses(
        function()
            binary.decode(magic .. "\4\255\255\255\255")
        end,
        "truncated"
    )
    local key = "\4\1\0\0\0x"
    refuses(
        function()
            binary.decode(magic .. "\5\2\0\0\0" .. key .. "\1" .. key .. "\2")
        end,
        "duplicate"
    )
    refuses(
        function()
            binary.decode(magic .. "\5\1\0\0\0\2\1")
        end,
        "table key"
    )
    refuses(
        function()
            binary.decode(magic .. "\5\1\0\0\0" .. key .. "\0")
        end,
        "nil table value"
    )
    refuses(
        function()
            binary.decode(magic .. "\5\255\255\255\255")
        end,
        "value limit"
    )
end

function M.nestingLimitInBothDirections()
    local value = {}
    for i = 1, 127 do
        value = {value}
    end
    binary.decode(binary.encode(value))
    refuses(
        function()
            binary.encode({value})
        end,
        "depth limit"
    )
    local nested = magic .. string.rep("\5\1\0\0\0\4\1\0\0\0x", 129) .. "\2"
    refuses(
        function()
            binary.decode(nested)
        end,
        "depth limit"
    )
end

return M
