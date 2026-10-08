local testAssert = require("nupp.test")
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

    testAssert.equal(first[1].source, "first.nupp", "first collection source")
    testAssert.equal(second[1].source, "second.nupp", "second collection source")
    testAssert.equal(first[1].line, 3, "source line")
    testAssert.equal(first[1].column, 7, "source column")
    testAssert.equal(observation.source, nil, "checked observation remains unchanged")
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

    testAssert.equal(public.source, "main.nupp", "public source")
    assert(public.runtimeFeatures == runtimeFeatures, "bounded feature facts remain public")
    testAssert.equal(public.blueprint, nil, "blueprint payload")
    testAssert.equal(public.generated, nil, "generated payload")
end

return M
