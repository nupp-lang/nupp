-- The public JSON policy is fixed by Nupp rather than inherited from a provider's
-- build options. These checks exercise the shipped Nupp provider directly.

local json = require("nupp.codec.json")

local M = {}

function M.emptyContainersAreExplicit()
    assert(json.encode({}) == "{}", "a plain empty table is an object")
    assert(json.encode(json.asArray({})) == "[]", "asArray marks an empty array")
    assert(json.encode(json.asObject({})) == "{}", "asObject marks an empty object")
    assert(json.encode(json.EMPTY_ARRAY) == "[]", "EMPTY_ARRAY is serializable")
    assert(json.encode(json.EMPTY_OBJECT) == "{}", "EMPTY_OBJECT is serializable")
end

function M.decodedContainerShapeIsPublic()
    assert(json.isArray(json.decode("[]")), "a decoded empty array retains its shape")
    assert(not json.isArray(json.decode("{}")), "a decoded empty object retains its shape")
    assert(json.isArray(json.decode("[1]")), "a decoded non-empty array has array shape")
    assert(not json.isArray(json.decode([[{"value":1}]])), "a decoded non-empty object has object shape")
end

function M.nullDropsOrUsesTheSuppliedValue()
    local dropped = json.decode([[{"items":[1,null,2],"missing":null}]])
    assert(dropped.missing == nil and #dropped.items == 2 and dropped.items[2] == 2)
    local kept = json.decode([[{"items":[1,null,2],"missing":null}]], json.NULL)
    assert(kept.missing == json.NULL and kept.items[2] == json.NULL)
    assert(
        json.encode(kept) == [[{"items":[1,null,2],"missing":null}]]
        or json.encode(kept) == [[{"missing":null,"items":[1,null,2]}]]
    )
end

function M.invalidNumbersAreAlwaysRejected()
    assert(not pcall(json.decode, "[NaN]"), "the decoder accepted NaN")
    assert(not pcall(json.decode, "[Infinity]"), "the decoder accepted Infinity")
    assert(not pcall(json.encode, 0 / 0), "the encoder accepted NaN")
end

function M.providersPreserveNegativeZero()
    for _, provider in ipairs({require("nupp.runtime.provider.lunajson"), require("nupp.codec.json.aot"),}) do
        local encoded = provider.encode(-0.0)
        assert(encoded == "-0", "negative zero lost its sign: " .. encoded)
        assert(1 / provider.decode(encoded) == -math.huge, "negative zero did not round-trip")
    end
end

function M.failedWritesLeaveTheWriterAtItsPriorPosition()
    for _, provider in ipairs({require("nupp.runtime.provider.lunajson"), require("nupp.codec.json.aot"),}) do
        local output = require("nupp.text").newBuffer()
        local writer = provider.writer(output)
        writer:startArray():write(1)
        assert(
            not pcall(writer.write, writer, function()
            end),
            "the writer accepted a function"
        )
        writer:write(2):endArray()
        writer:close()
        assert(output:tostring() == "[1,2]", "a rejected value changed the writer")
    end
end

function M.portableEncodingRejectsInvalidUtf8Everywhere()
    for _, value in ipairs({"\255", "\192\128", "\237\160\128"}) do
        assert(not pcall(json.encode, value), "the encoder accepted an invalid UTF-8 value")
        assert(not pcall(json.encode, {[value] = 1}), "the encoder accepted an invalid UTF-8 key")
        assert(not pcall(json.encodedString, value), "encodedString accepted invalid UTF-8")
    end
    local output = require("nupp.text").newBuffer()
    local writer = json.writer(output)
    writer:startObject()
    assert(not pcall(writer.key, writer, "\255"), "the writer accepted an invalid UTF-8 key")
    writer:key("valid"):write(1):endObject()
    writer:close()
    assert(output:tostring() == [[{"valid":1}]], "a rejected key changed the writer")
end

function M.arrayMarkersRequireEveryConsecutiveIndex()
    local sparse = {}
    sparse[2] = "second"
    assert(not pcall(json.asArray, sparse), "asArray accepted an array starting at index two")

    local aotSparse = {}
    aotSparse[2] = "second"
    assert(
        not pcall(require("nupp.codec.json.aot").asArray, aotSparse),
        "the AOT provider accepted an array starting at index two"
    )
end

function M.pullShapesRequireTheMatchingContainerKind()
    assert(not pcall(json.pull, [[{"answer":42}]], json.arrayOf(true)), "an array shape accepted an object")
    assert(not pcall(json.pull, [[1,2]], {answer = true}), "an object shape accepted an array")
    assert(not pcall(json.pull, "null", json.arrayOf(true), json.NULL), "an array shape accepted null")
    assert(not pcall(json.pull, "null", {answer = true}, json.NULL), "an object shape accepted null")
end

function M.portableEncodingBoundsNesting()
    local value = 0
    for _ = 1, 1025 do
        value = {value}
    end
    local ok, problem = pcall(json.encode, value)
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

return M
