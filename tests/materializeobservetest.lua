local testAssert = require("assert")
local observe = require("nupp.compiler.comptime.materialize.observe")

local M = {}

function M.collectionsKeepTheirOwnSourceContext()
    local payload = {provider = "test", schema = 1}
    local observation = {
        provider = "test",
        schema = 1,
        fingerprint = "abc",
        backend = "direct",
        blueprintSize = 2,
        generatedSize = 3,
        runtimeFeatures = {},
        abis = {},
        blueprint = payload,
        generated = "out",
    }
    local token = {kind = "name", text = "value", line = 3, col = 7, trivia = {}}
    local node = {kind = "comptimeExpr", materializationObservation = observation, token}
    local root = {kind = "chunk", node}

    local first = observe.collect(root, "first.nupp")
    local second = observe.collect(root, "second.nupp")

    testAssert.eq(first[1].source, "first.nupp", "first collection source")
    testAssert.eq(second[1].source, "second.nupp", "second collection source")
    testAssert.eq(first[1].line, 3, "source line")
    testAssert.eq(first[1].column, 7, "source column")
    testAssert.eq(observation.source, nil, "checked observation remains unchanged")
    assert(first[1] ~= second[1], "each collection owns its record")
    assert(first[1].blueprint == payload, "the stored cache payload remains attached")
end

function M.publicRecordsOmitCachePayloads()
    local runtimeFeatures = {"runtime.gpu"}
    local public = observe.public({
        {
            source = "main.nupp",
            line = 2,
            column = 4,
            provider = "test",
            schema = 1,
            fingerprint = "abc",
            backend = "direct",
            blueprintSize = 2,
            generatedSize = 3,
            runtimeFeatures = runtimeFeatures,
            abis = {provider = 1},
            blueprint = {secret = true},
            generated = "private",
        }
    })[1]

    testAssert.eq(public.source, "main.nupp", "public source")
    assert(public.runtimeFeatures == runtimeFeatures, "bounded feature facts remain public")
    testAssert.eq(public.blueprint, nil, "blueprint payload")
    testAssert.eq(public.generated, nil, "generated payload")
end

return M
