local testAssert = require("assert")
local providers = require("nupp.compiler.comptime.materialize.providers")
local reflection = require("nupp.compiler.reflection")

local M = {}

function M.rejectsMalformedImportedTypeDescriptors()
    local state = {}
    providers.installEvaluator(state, {})

    local tooMany = {schema = reflection.SCHEMA, root = 1, types = {}}
    for index = 1, 10001 do
        tooMany.types[index] = {kind = "string"}
    end
    local oversized, oversizedFailure = providers.importTypeDescriptor(state, tooMany)
    testAssert.eq(oversized, nil, "an oversized input descriptor is rejected")
    testAssert.eq(oversizedFailure.code, "NUPP2415", "oversized input uses the provider diagnostic")

    local droppedEdge = {
        schema = reflection.SCHEMA,
        root = 1,
        types = {{kind = "map", readKey = 99, writeKey = 2, writeValue = 3}, {kind = "string"}, {kind = "number"}}
    }
    local dropped, droppedFailure = providers.importTypeDescriptor(state, droppedEdge)
    testAssert.eq(dropped, nil, "an invalid capability edge is not treated as absent")
    testAssert.eq(droppedFailure.code, "NUPP2415", "an invalid edge uses the provider diagnostic")

    local malformedPack = {
        schema = reflection.SCHEMA,
        root = 1,
        types = {{kind = "pack", head = {2}}, {kind = "string"}}
    }
    local pack, packFailure = providers.importTypeDescriptor(state, malformedPack)
    testAssert.eq(pack, nil, "a malformed pack member is rejected")
    testAssert.eq(packFailure.code, "NUPP2415", "a malformed pack uses the provider diagnostic")
end

return M
