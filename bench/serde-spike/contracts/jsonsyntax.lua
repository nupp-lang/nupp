local syntax = require("nupp.serde.internal.json.syntax")

local cursor = syntax.reader(
    [[ { "huge": 123456789012345678901234567890, "tiny": 1e-9000, "nulls": [null,false,"\uD83D\uDE00"] } ]]
)
cursor:start("object")
assert(cursor:nextKey() == "huge")
assert(cursor:readNumber() == "123456789012345678901234567890")
assert(cursor:nextKey() == "tiny")
assert(cursor:readNumber() == "1e-9000")
assert(cursor:nextKey() == "nulls")
cursor:start("array")
assert(cursor:nextElement())
cursor:readNull()
assert(cursor:nextElement())
assert(cursor:readBoolean() == false)
assert(cursor:nextElement())
assert(cursor:readString() == "😀")
assert(not cursor:nextElement())
assert(cursor:nextKey() == nil)
cursor:finish()
assert(
    not pcall(function()
        cursor:peek()
    end)
)

for _, input in ipairs({
    "null",
    "true",
    "false",
    "0",
    "-0",
    "-1.20e+3000",
    [["a\\b\"c"]],
    "[]",
    "{}",
    [[{"a":[1,null,{"b":2}]}]]
}) do
    local reader = syntax.reader(input)
    reader:skipValue()
    reader:finish()
end

for _, input in ipairs({
    "",
    "00",
    "-01",
    "1.",
    "1e",
    "1e+",
    "+1",
    "NaN",
    "true false",
    "nul",
    "[1,]",
    "[,1]",
    "[1 2]",
    [[{"x":1,}]],
    [[{"x":null,"\u0078":2}]],
    [[{"x" 1}]],
    [["\uD800"]],
    [["\q"]],
    '"a\nb"',
    string.char(34, 255, 34),
    "{",
    "[",
    [[{"x":[1,]}]]
}) do
    local ok = pcall(function()
        local reader = syntax.reader(input)
        reader:skipValue()
        reader:finish()
    end)
    assert(not ok, "accepted malformed JSON: " .. input)
end

assert(
    not pcall(function()
        local reader = syntax.reader("[[[]]]", 2)
        reader:skipValue()
    end)
)
assert(
    not pcall(function()
        local reader = syntax.reader("[1,2]", nil, 2)
        reader:skipValue()
    end)
)
assert(
    not pcall(function()
        local reader = syntax.reader("[1,2]")
        reader:start("array")
        assert(reader:nextElement())
        reader:nextElement()
    end)
)
assert(
    not pcall(function()
        local reader = syntax.reader("[1,2]")
        reader:start("array")
        assert(reader:nextElement())
        reader:readNumber()
        reader:readNumber()
    end)
)
local errors = require("nupp.serde.internal.errors")
local function limits(overrides)
    local bounds = {tokenBytes = 16777216, aggregateEntries = 1000000, inputBytes = 67108864}
    for key, value in pairs(overrides) do
        bounds[key] = value
    end
    return setmetatable(bounds, syntax.Limits)
end
local function limited(input, limits)
    local reader = syntax.reader(input, nil, nil, limits)
    reader:skipValue()
    reader:finish()
end

for _, value in ipairs({
    {input = '"abcdef"', limits = limits({tokenBytes = 3})},
    {input = '[0,1]', limits = limits({aggregateEntries = 1})},
    {input = '[0]', limits = limits({inputBytes = 2})},
}) do
    local accepted, refused = pcall(limited, value.input, value.limits)
    assert(not accepted and getmetatable(refused) == errors.Error)
    assert(refused.code == "limit")
end
print("JSON token contract passed")
