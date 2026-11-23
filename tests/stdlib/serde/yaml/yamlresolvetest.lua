-- The YAML 1.2 core schema's resolution of plain and tagged scalars
-- (serde.yaml.internal.resolve), which is plain Nupp and runs without libyaml.
local resolve = require("serde.yaml.internal.resolve")
local test = require("assert")
local M = {}

local function resolved(text)
    local kind, value, problem = resolve.plain(text)
    test(problem == nil, tostring(problem))

    return kind, value
end

function M.nullsAndBooleansAreTheCoreSchemas()
    for _, text in ipairs({"", "~", "null", "Null", "NULL"}) do
        test(resolved(text) == "null", text)
    end
    for _, text in ipairs({"true", "True", "TRUE"}) do
        local kind, value = resolved(text)
        test(kind == "boolean" and value == true, text)
    end
    for _, text in ipairs({"false", "False", "FALSE"}) do
        local kind, value = resolved(text)
        test(kind == "boolean" and value == false, text)
    end
end

function M.yamlOneOneWordsAreStrings()
    for _, text in ipairs({"yes", "no", "on", "off", "Yes", "NO", "y", "n", "nULL", "tRUE", "2026-11-20", "1_000", "0b101"}) do
        local kind, value = resolved(text)
        test(kind == "string" and value == text, text)
    end
end

function M.integersAreDecimalOctalAndHexadecimal()
    local cases = {
        ["0"] = 0,
        ["-0"] = 0,
        ["+7"] = 7,
        ["007"] = 7,
        ["-12"] = -12,
        ["0o17"] = 15,
        ["0x1F"] = 31,
        ["0xff"] = 255,
        ["9223372036854775807"] = math.maxinteger,
        ["-9223372036854775808"] = math.mininteger,
        ["0x7fffffffffffffff"] = math.maxinteger,
    }
    for text, expected in pairs(cases) do
        local kind, value = resolved(text)
        test(kind == "integer" and math.type(value) == "integer" and value == expected, text)
    end
    -- Signs and digits the core schema's octal and hexadecimal forms lack.
    for _, text in ipairs({"0o8", "-0x1", "0X1F", "0O7", "0x", "0o"}) do
        test(resolved(text) == "string", text)
    end
end

function M.anIntegerOutOfRangeIsAnError()
    for _, text in ipairs({"9223372036854775808", "-9223372036854775809", "0x8000000000000000", "0o1000000000000000000000"}) do
        local kind, value, problem = resolve.plain(text)
        test(kind == "integer" and value == nil and problem ~= nil, text)
    end
end

function M.floatsAreDecimalExponentAndSpecial()
    local cases = {
        ["1.5"] = 1.5,
        ["-0.5"] = -0.5,
        [".5"] = 0.5,
        ["+.5"] = 0.5,
        ["1."] = 1.0,
        ["1e3"] = 1000.0,
        ["1.5E-2"] = 0.015,
        ["-2.5e+1"] = -25.0,
        [".inf"] = math.huge,
        ["+.Inf"] = math.huge,
        ["-.INF"] = -math.huge,
    }
    for text, expected in pairs(cases) do
        local kind, value = resolved(text)
        test(kind == "float" and math.type(value) == "float" and value == expected, text)
    end
    for _, text in ipairs({".nan", ".NaN", ".NAN"}) do
        local kind, value = resolved(text)
        test(kind == "float" and value ~= value, text)
    end
    for _, text in ipairs({".", "1.2.3", "e3", "1e", ".e1", "-.nan", "inf", "nan", "1,5"}) do
        test(resolved(text) == "string", text)
    end
end

function M.coreTagsForceTheirTypeAndRefuseWhatDoesNotFit()
    test(resolve.tagged(resolve.STRING, "123") == "string")
    test(resolve.tagged(resolve.NONSPECIFIC, "true") == "string")
    local kind, value = resolve.tagged(resolve.INTEGER, "0x10")
    test(kind == "integer" and value == 16)
    kind, value = resolve.tagged(resolve.FLOAT, "1")
    test(kind == "float" and value == 1.0 and math.type(value) == "float")
    kind, value = resolve.tagged(resolve.BOOLEAN, "False")
    test(kind == "boolean" and value == false)
    test(resolve.tagged(resolve.NULL, "~") == "null")
    for _, pair in ipairs({
        {resolve.INTEGER, "1.5"},
        {resolve.FLOAT, "abc"},
        {resolve.BOOLEAN, "yes"},
        {resolve.NULL, "nothing"},
    }) do
        local refused, _, problem = resolve.tagged(pair[1], pair[2])
        test(refused == nil and problem ~= nil, pair[1] .. " " .. pair[2])
    end
end

function M.anyOtherTagIsRefusedByName()
    for _, tag in ipairs({"tag:yaml.org,2002:binary", "tag:yaml.org,2002:timestamp", "!python/object", "!local"}) do
        local kind, _, problem = resolve.tagged(tag, "x")
        test(kind == nil and problem ~= nil and (problem):find(tag, 1, true) ~= nil, tag)
    end
end

return M
