-- The public JSON policy is fixed by Nupp rather than inherited from a provider's
-- build options. These checks exercise the shipped Nupp provider directly.

local json = require("serde.json")
local test = require("assert")

local M = {}

function M.emptyContainersAreExplicit()
    assert(json.encodevalue({}) == "{}", "a plain empty table is an object")
    assert(json.encodevalue(json.asarray({})) == "[]", "asarray marks an empty array")
    assert(json.encodevalue(json.asobject({})) == "{}", "asobject marks an empty object")
    assert(json.encodevalue(json.EMPTY_ARRAY) == "[]", "EMPTY_ARRAY is serializable")
    assert(json.encodevalue(json.EMPTY_OBJECT) == "{}", "EMPTY_OBJECT is serializable")
end

function M.decodedContainerShapeIsPublic()
    assert(json.isarray(json.decodevalue("[]")), "a decoded empty array retains its shape")
    assert(not json.isarray(json.decodevalue("{}")), "a decoded empty object retains its shape")
    assert(json.isarray(json.decodevalue("[1]")), "a decoded non-empty array has array shape")
    assert(not json.isarray(json.decodevalue([[{"value":1}]])), "a decoded non-empty object has object shape")
end

function M.nullDropsOrUsesTheSuppliedValue()
    local dropped = json.decodevalue([[{"items":[1,null,2],"missing":null}]])
    assert(dropped.missing == nil and #dropped.items == 2 and dropped.items[2] == 2)
    local kept = json.decodevalue([[{"items":[1,null,2],"missing":null}]], json.NULL)
    assert(kept.missing == json.NULL and kept.items[2] == json.NULL)
    assert(
        json.encodevalue(kept) == [[{"items":[1,null,2],"missing":null}]]
        or json.encodevalue(kept) == [[{"missing":null,"items":[1,null,2]}]]
    )
end

-- The public writer appends to an io.Buffer; a provider's own writer to a
-- string.buffer.
local function outputFor(provider, prefix)
    if provider == json then
        return require("io").Buffer.create(prefix)
    end
    local output = require("string.buffer").new()
    if prefix ~= nil then
        output:put(prefix)
    end

    return output
end

local function textOf(output)
    if output.getstring ~= nil then
        return output:getstring()
    end

    return output:tostring()
end

function M.abortingWritersDiscardsOnlyUnpublishedBytes()
    for _, provider in ipairs({json, require("nupp.runtime.provider.lunajson"), require("nupp.codec.json.aot")}) do
        local output = outputFor(provider, "prefix")
        local writer = (provider == json and json.Writer.of or provider.newwriter)(output)
        writer:startarray():write(1)
        writer:abort()
        writer:abort()
        writer:close()
        assert(textOf(output) == "prefix")
        assert(not pcall(writer.write, writer, 2))
        writer = (provider == json and json.Writer.of or provider.newwriter)(output)
        writer:startarray():write(1)
        writer:flush()
        writer:write(2)
        writer:abort()
        writer:close()
        assert(textOf(output) == "prefix[1")
    end
end

local function refused(value, reason)
    return value == nil and type(reason) == "string" and reason ~= ""
end

-- Malformed text is an ordinary answer: nil and a reason, as hex.decode and
-- uri.newURI give. The reason is what tells failure apart, because the
-- document `null` is nil too when nulls are dropped.
function M.decodeAndPullAnswerAReason()
    assert(refused(json.decodevalue("[1,")), "a truncated array")
    assert(refused(json.decodevalue("")), "an empty document")
    assert(refused(json.decodevalue("{} {}")), "two documents")
    local value, reason = json.decodevalue("null")
    assert(value == nil and reason == nil, "a dropped null document is not a failure")
    value, reason = json.decodevalue("null", json.NULL)
    assert(value == json.NULL and reason == nil, "a kept null document")
    value, reason = json.decodevalue("[1,")
    assert(tostring(reason):find("^invalid JSON at byte %d+: "), tostring(reason))
    assert(refused(json.pull("[1,", true)), "a truncated pull")
    value, reason = json.pull([[{"a":1,"b":2}]], {a = true})
    assert(reason == nil and value.a == 1 and value.b == nil, "a pull")
end

function M.invalidNumbersAreAlwaysRejected()
    assert(refused(json.decodevalue("[NaN]")), "the decoder accepted NaN")
    assert(refused(json.decodevalue("[Infinity]")), "the decoder accepted Infinity")
    assert(not pcall(json.encodevalue, 0 / 0), "the encoder accepted NaN")
end

function M.exactNumberFragmentsPreserveTokensAcrossProviders()
    for _, provider in ipairs({json, require("nupp.runtime.provider.lunajson"), require("nupp.codec.json.aot")}) do
        for _, token in ipairs({"0", "-0", "1.00", "123456789012345678901234567890", "1e4000", "-2.1E-9000"}) do
            local fragment = (provider == json and provider.numbertoken or provider.numbertoken)(token)
            local encode = provider == json and provider.encodevalue or provider.encode
            assert(encode(fragment) == token)
            local output = outputFor(provider)
            local writer = (provider == json and json.Writer.of or provider.newwriter)(output)
            writer:startarray():write(fragment):endarray()
            writer:close()
            assert(textOf(output) == "[" .. token .. "]")
        end
        for _, token in ipairs({
            "",
            " 1",
            "1 ",
            "+1",
            "01",
            "-01",
            ".1",
            "1.",
            "1e",
            "1e+",
            "NaN",
            "Infinity",
            "1,2",
            "1+2",
            "true"
        }) do
            assert(
                not pcall(provider == json and provider.numbertoken or provider.numbertoken, token),
                "accepted invalid token: " .. token
            )
        end
    end
end

function M.providersRoundTripExactSignedIntegers()
    local portable = require("nupp.runtime.provider.lunajson")
    for _, provider in ipairs({portable, require("nupp.codec.json.aot")}) do
        for _, token in ipairs({
            "9007199254740993",
            "9223372036854775807",
            "-9223372036854775808",
            "-9223372036854775807",
            "0",
            "1",
            "-1",
            "42",
        }) do
            local value = assert(tonumber(token))
            assert(math.type(value) == "integer" and tostring(value) == token, "invalid integer fixture: " .. token)
            local encoded = provider.encode(value)
            assert(encoded == token, "integer precision lost: " .. token .. " encoded as " .. encoded)
            local decoded = provider.decode(encoded)
            assert(
                math.type(decoded) == "integer" and tostring(decoded) == token,
                "integer did not round-trip: " .. token
            )
        end
        for _, value in ipairs({0.1, 1.25}) do
            assert(math.type(value) == "float")
            local encoded = provider.encode(value)
            if provider == portable then
                assert(encoded == string.format("%.17g", value), "portable float encoding changed: " .. encoded)
            end
            local decoded = provider.decode(encoded)
            assert(math.type(decoded) == "float" and decoded == value, "float did not round-trip: " .. encoded)
        end
        local encoded = provider.encode(-0.0)
        assert(encoded == "-0" and 1 / provider.decode(encoded) == -math.huge, "negative zero did not round-trip")
    end
end

function M.providersPreserveNegativeZero()
    for _, provider in ipairs({require("nupp.runtime.provider.lunajson"), require("nupp.codec.json.aot"),}) do
        local encoded = provider.encode(-0.0)
        assert(encoded == "-0", "negative zero lost its sign: " .. encoded)
        assert(1 / provider.decode(encoded) == -math.huge, "negative zero did not round-trip")
        for _, token in ipairs({"-0", "-0.0", "-0e0", "-0.00E+1", "-1e-400"}) do
            local decoded = provider.decode(token)
            assert(decoded == 0 and 1 / decoded == -math.huge, "negative zero lost its sign: " .. token)
        end
        assert(1 / provider.decode("0") == math.huge, "positive zero acquired a sign")
    end
end

function M.failedWritesLeaveTheWriterAtItsPriorPosition()
    for _, provider in ipairs({require("nupp.runtime.provider.lunajson"), require("nupp.codec.json.aot"),}) do
        local output = require("string.buffer").new()
        local writer = provider.newwriter(output)
        writer:startarray():write(1)
        assert(
            not pcall(writer.write, writer, function()
            end),
            "the writer accepted a function"
        )
        writer:write(2):endarray()
        writer:close()
        assert(output:tostring() == "[1,2]", "a rejected value changed the writer")
    end
end

function M.portableEncodingRejectsInvalidUtf8Everywhere()
    for _, value in ipairs({"\255", "\192\128", "\237\160\128"}) do
        assert(not pcall(json.encodevalue, value), "the encoder accepted an invalid UTF-8 value")
        assert(not pcall(json.encodevalue, {[value] = 1}), "the encoder accepted an invalid UTF-8 key")
        assert(not pcall(json.encodedstring, value), "encodedstring accepted invalid UTF-8")
    end
    local output = require("io").Buffer.create()
    local writer = json.Writer.of(output)
    writer:startobject()
    assert(not pcall(writer.key, writer, "\255"), "the writer accepted an invalid UTF-8 key")
    writer:key("valid"):write(1):endobject()
    writer:close()
    assert(output:getstring() == [[{"valid":1}]], "a rejected key changed the writer")
end

function M.arrayMarkersRequireEveryConsecutiveIndex()
    local sparse = {}
    sparse[2] = "second"
    assert(not pcall(json.asarray, sparse), "asarray accepted an array starting at index two")

    local aotSparse = {}
    aotSparse[2] = "second"
    assert(
        not pcall(require("nupp.codec.json.aot").asarray, aotSparse),
        "the AOT provider accepted an array starting at index two"
    )
end

function M.providersPreserveWriterTransitionsAndArrayIdentity()
    for _, provider in ipairs({require("nupp.runtime.provider.lunajson"), require("nupp.codec.json.aot")}) do
        local function rejected(action, expected)
            local ok, problem = pcall(action)
            assert(not ok and tostring(problem):find(expected, 1, true), tostring(problem))
        end

        local value = {1, 2, 3}
        assert(provider.asarray(value) == value and provider.isarray(value))
        for _, invalid in ipairs({{[0] = true}, {[1.5] = true}, {[1] = true, [3] = true}, {named = true}}) do
            rejected(
                function()
                    provider.asarray(invalid)
                end,
                "consecutive positive indexes"
            )
            assert(getmetatable(invalid) == nil, "rejected marking changed the table")
        end
        rejected(
            function()
                provider.asarray(false)
            end,
            "json.asarray needs a table"
        )

        local output = require("string.buffer").new()
        local writer = provider.newwriter(output)
        writer:startobject()
        rejected(
            function()
                writer:null()
            end,
            "an object value must follow key()"
        )
        writer:key("nested"):startarray():null():startobject():key("value"):write(2):endobject():endarray()
        writer:key("pending")
        rejected(
            function()
                writer:endobject()
            end,
            "the final object key has no value"
        )
        writer:write(true):endobject()
        rejected(
            function()
                writer:startarray()
            end,
            "writer already has a root value"
        )
        writer:close()
        assert(output:tostring() == [[{"nested":[null,{"value":2}],"pending":true}]])
        rejected(
            function()
                writer:null()
            end,
            "writer is already closed"
        )
        rejected(
            function()
                writer:startobject()
            end,
            "writer is already closed"
        )
    end
end

function M.pullShapesRequireTheMatchingContainerKind()
    assert(refused(json.pull([[{"answer":42}]], json.arrayof(true))), "an array shape accepted an object")
    assert(refused(json.pull([[1,2]], {answer = true})), "an object shape accepted an array")
    assert(refused(json.pull("null", json.arrayof(true), json.NULL)), "an array shape accepted null")
    assert(refused(json.pull("null", {answer = true}, json.NULL)), "an object shape accepted null")
end

function M.portableEncodingBoundsNesting()
    local value = 0
    for _ = 1, 1025 do
        value = {value}
    end
    local ok, problem = pcall(json.encodevalue, value)
    assert(not ok and tostring(problem):find("nesting exceeds 1024", 1, true), tostring(problem))
end

function M.providersShareTheDecodeNestingBoundary()
    local providers = {require("nupp.runtime.provider.lunajson"), require("nupp.codec.json.aot"),}
    local deepest = string.rep("[", 1024) .. "1" .. string.rep("]", 1024)
    local tooDeep = "[" .. deepest .. "]"
    for _, provider in ipairs(providers) do
        local ok, value = pcall(provider.decode, deepest)
        assert(ok and type(value) == "table", "a provider rejected 1,024 nested containers: " .. tostring(value))
        local accepted, problem = pcall(provider.decode, tooDeep)
        assert(not accepted, "a provider accepted 1,025 nested containers: " .. tostring(problem))
    end
end

-- A decode failure describes the caller's text, not where in a decoder it was
-- noticed: no chunk-and-line prefix from the vendored parser, and one message
-- form on both providers.
function M.decodeProblemsNameTheTextNotTheDecoder()
    local providers = {require("nupp.runtime.provider.lunajson"), require("nupp.codec.json.aot"),}
    local malformed = {"1.", "[1,]", "{\"a\" 1}", "[] []", "tru", string.rep("[", 1025) .. string.rep("]", 1025)}
    for _, provider in ipairs(providers) do
        for _, text in ipairs(malformed) do
            local ok, problem = pcall(provider.decode, text)
            assert(not ok, ("%q was accepted"):format(text))
            problem = tostring(problem)
            assert(not problem:find("%.lua:%d") and not problem:find("%.nupp:%d"), problem)
            assert(problem:find("^invalid JSON at byte %d+: "), problem)
        end
    end
    local ok, problem = pcall(require("nupp.runtime.provider.lunajson").encode, math.huge)
    assert(not ok and not tostring(problem):find("%.lua:%d"), tostring(problem))
end

-- A number token whose value is not finite is refused, because the encoder
-- refuses what it would decode to: a document that decodes must round-trip.
-- Underflow is not an overflow, and a value too small for binary64 is zero.
local NON_FINITE = {
    {"1e400", 1},
    {"-1e400", 1},
    {"[1e309]", 2},
    {"[1, -1e309]", 5},
    {"{\"a\":0.1e400}", 6},
    {"123456789012345678901234567890e290", 1},
    {"1.7976931348623159e308", 1},
    {"[0.000001e315, 1]", 2},
}

function M.nonFiniteNumbersAreRefusedByEveryProvider()
    local providers = {lunajson = require("nupp.runtime.provider.lunajson"), aot = require("nupp.codec.json.aot"),}
    for name, provider in pairs(providers) do
        for _, row in ipairs(NON_FINITE) do
            local decoders = {
                function(text)
                    return provider.decode(text)
                end,
                function(text)
                    return provider.decode(text, provider.NULL)
                end,
                function(text)
                    return provider.verified(text)
                end,
            }
            -- The AOT pull builder exists only in the compiled artifact, which
            -- the fused-json native differential runs; this oracle cannot.
            if name == "lunajson" then
                decoders[#decoders + 1] = function(text)
                    return provider.pull(text, true)
                end
            end
            for _, decode in ipairs(decoders) do
                local ok, problem = pcall(decode, row[1])
                assert(not ok, ("%s accepted %q"):format(name, row[1]))
                test.eq(
                    tostring(problem),
                    ("invalid JSON at byte %d: number is out of range"):format(row[2]),
                    name .. " " .. row[1]
                )
            end
        end
        test.eq(provider.decode("1e-400"), 0, name .. " underflow")
        test.eq(1 / provider.decode("-1e-400"), -math.huge, name .. " negative underflow")
        test.eq(provider.decode("[1.7976931348623157e308]")[1], 1.7976931348623157e308, name .. " largest double")
        test.eq(provider.decode("1e308"), 1e308, name .. " 1e308")
    end
end

-- A member name that appears twice in one object is refused at the second
-- occurrence's opening quote, whichever value either occurrence holds, a
-- dropped null included. I-JSON forbids it, and last-wins let a first
-- occurrence of the wrong type past a schema that only saw the second.
local DUPLICATES = {
    {'{"a":1,"a":2}', 8},
    {'{"a":1, "a" :2}', 9},
    {'{"a":null,"a":2}', 11},
    {'{"a":1,"a":null}', 8},
    {'{"a":null,"a":null}', 11},
    {'{"id":"x","id":1}', 11},
    {'[{"a":1},{"b":{"c":1,"c":2}}]', 22},
    {'{"a\\u0062":1,"ab":2}', 14},
    {'{"a":{"x":1},"b":{"x":1},"a":0}', 26},
}

function M.duplicateMemberNamesAreRefusedByEveryProvider()
    local providers = {lunajson = require("nupp.runtime.provider.lunajson"), aot = require("nupp.codec.json.aot"),}
    for name, provider in pairs(providers) do
        for _, row in ipairs(DUPLICATES) do
            local decoders = {
                function(text)
                    return provider.decode(text)
                end,
                function(text)
                    return provider.decode(text, provider.NULL)
                end,
                function(text)
                    return provider.verified(text)
                end,
            }
            if name == "lunajson" then
                decoders[#decoders + 1] = function(text)
                    return provider.pull(text, {a = true})
                end
            end
            for _, decode in ipairs(decoders) do
                local ok, problem = pcall(decode, row[1])
                assert(not ok, ("%s accepted %q"):format(name, row[1]))
                test.eq(
                    tostring(problem),
                    ("invalid JSON at byte %d: duplicate member name"):format(row[2]),
                    name .. " " .. row[1]
                )
            end
        end
        -- The same name in two objects is two members.
        local value = provider.decode('[{"a":1},{"a":2},{"a":null},{"a":3}]')
        test.eq(value[1].a, 1, name)
        test.eq(value[4].a, 3, name)
        test.eq(provider.decode('{"a":{"a":{"a":1}}}').a.a.a, 1, name)
    end
end

return M
