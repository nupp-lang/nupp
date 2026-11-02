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

local function invoke(state, intrinsic, ...)
    return state.intrinsics[intrinsic](nil, {n = select("#", ...), ...})
end

function M.canonicalTypeNamesKeepPrivateBlueprintsAndRetirePrecedingKeys()
    local state, values = {}, {}
    providers.installEvaluator(state, values)
    local library = values.types
    for _, names in ipairs({
        {"bool", "boolean"},
        {"niltype", "nil_"},
        {"tabletype", "table_"},
        {"functiontype", "function_"},
        {"len", "length"},
    }) do
        assert(library[names[1]], names[1] .. " is installed")
        testAssert.eq(library[names[2]], nil, names[2] .. " is retired")
    end
    testAssert.eq(state.opaque[library.bool].payload.name, "boolean")
    testAssert.eq(state.opaque[library.niltype].payload.name, "nil")
    testAssert.eq(state.opaque[library.tabletype].payload.name, "table")
    local parameters = assert(invoke(state, library.pack, {library.string}))
    local results = assert(invoke(state, library.pack, {library.bool, library.niltype}))
    local current = assert(invoke(state, library.functiontype, parameters, results))
    testAssert.eq(current, assert(invoke(state, library.functiontype, parameters, results)))
    testAssert.eq(state.opaque[current].payload.kind, "function")
    local bounded = assert(invoke(state, library.len, library.string, 1, 4))
    testAssert.eq(bounded, assert(invoke(state, library.len, library.string, 1, 4)))
    testAssert.eq(state.opaque[bounded].payload.lengthwise, true)
    local refused, failure = invoke(state, library.len, library.string, 4, 1)
    testAssert.eq(refused, nil)
    testAssert.eq(failure.code, "NUPP2420")
end

function M.canonicalDescribeKeysPreservePrivateGraphKeys()
    local state, values = {}, {}
    providers.installEvaluator(state, values)
    local library = values.types
    local descriptor = {
        schema = reflection.SCHEMA,
        root = 1,
        types = {
            {kind = "map", readKey = 2, readValue = 3, writeKey = 2, writeValue = 3},
            {kind = "string"},
            {kind = "integer"}
        },
    }
    local imported = assert(providers.importTypeDescriptor(state, descriptor))
    local described = assert(invoke(state, library.describe, imported))
    testAssert.eq(described.sourcekind, "map")
    testAssert.eq(described.sourceKind, nil)
    for _, names in ipairs({
        {"readkey", "readKey"},
        {"readvalue", "readValue"},
        {"writekey", "writeKey"},
        {"writevalue", "writeValue"}
    }) do
        testAssert.eq(described[names[2]], nil, "preceding public descriptor keys are retired")
        assert(described[names[1]])
    end
    local nominal = assert(
        providers.importTypeDescriptor(
            state,
            {
                schema = reflection.SCHEMA,
                root = 1,
                types = {
                    {
                        kind = "record",
                        nominal = true,
                        name = "Fixture",
                        referenceFingerprint = "fixture-record",
                        fields = {}
                    }
                },
            },
            nil,
            "fixture"
        )
    )
    local nominalDescription = assert(invoke(state, library.describe, nominal))
    testAssert.eq(nominalDescription.declarationkind, "record")
    testAssert.eq(nominalDescription.declarationKind, nil)
    testAssert.eq(state.opaque[imported].payload.readkey, nil, "private blueprint keys are unchanged")
    testAssert.eq(state.opaque[imported].payload.sourcekind, nil)
    testAssert.eq(state.opaque[nominal].payload.nominal.kind, "record")
end

return M
