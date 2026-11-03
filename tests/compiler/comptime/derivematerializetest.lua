local providers = require("nupp.compiler.comptime.materialize.providers")
local derive = require("nupp.compiler.comptime.materialize.derive")

local function evaluator()
    local state, env = {}, {}
    providers.installEvaluator(state, env)

    return state, env.types.derive
end

local function invoke(state, intrinsic, ...)
    local arguments = {n = select("#", ...), ...}

    return state.intrinsics[intrinsic](nil, arguments)
end

local M = {}

function M.rejectsSparseRecipeArrays()
    local state, library = evaluator()
    local receiver = assert(invoke(state, library.receiver))
    local sparse = {[1] = receiver, [2] = receiver, [4] = receiver}

    local array, arrayFailure = invoke(state, library.array, sparse)
    assert(array == nil, "derive.array accepted an argument list with a hole")
    assert(arrayFailure and arrayFailure.code == "NUPP2810", "sparse arguments used the wrong diagnostic")

    local result, resultFailure = invoke(state, library.implement, {effects = {[1] = "first", [3] = "third"}})
    assert(result == nil, "derive.implement accepted an effects list with a hole")
    assert(resultFailure and resultFailure.code == "NUPP2810", "sparse effects used the wrong diagnostic")
end

function M.ordersBooleanViewKeysDeterministically()
    local keys = {}
    local iterator = derive.sortedPairs({[true] = "yes", [false] = "no"}, false, function(value)
        return value
    end)
    while true do
        local key = iterator()
        if key == nil then
            break
        end
        keys[#keys + 1] = key
    end

    assert(keys[1] == false and keys[2] == true, "derive views do not order boolean keys")
end

function M.rejectsUnreadableFieldsAndDuplicateParameterNames()
    local state, library = evaluator()
    local field = {}
    state.opaque[field] = {provider = "derive", family = "Field", payload = {readable = false}}
    local argument, fieldFailure = invoke(state, library.field, field)
    assert(argument == nil, "derive.field accepted a write-only field")
    assert(fieldFailure and fieldFailure.code == "NUPP2810", "write-only field used the wrong diagnostic")

    local signature, forward = {}, {}
    state.opaque[signature] = {provider = "types", family = "Type", payload = {kind = "function"}}
    state.opaque[forward] = {provider = "derive", family = "Forward", payload = {}}
    local member, memberFailure = invoke(state, library.member, {
        signature = signature,
        parameters = {"value", "value"},
        forward = forward
    })
    assert(member == nil, "derive.member accepted duplicate parameter names")
    assert(memberFailure and memberFailure.code == "NUPP2810", "duplicate parameters used the wrong diagnostic")
end

function M.revalidatesMutableRecipeInputsAtFinalization()
    local state, library = evaluator()
    local receiver = assert(invoke(state, library.receiver))
    local arguments = {receiver, receiver}
    local helper = {}
    state.opaque[
        helper
    ] = {provider = "derive", family = "RuntimeHelper", payload = {module = "fixture", member = "forward"},}
    local forward = assert(invoke(state, library.forward, {helper = helper, arguments = arguments}))
    local methods = {run = forward}
    local result = assert(invoke(state, library.implement, {methods = methods}))
    arguments[1] = nil

    local envelope, finalizeFailure = providers.finalize(state, result)
    assert(envelope == nil, "derive finalization truncated a forwarding list mutated after construction")
    assert(finalizeFailure and finalizeFailure.code == "NUPP2810", "mutated recipe used the wrong diagnostic")
end

function M.canonicalInfoAndFieldKeysRetireAliasesWithoutRewritingUserViews()
    local state = evaluator()
    local ownerType, interfaceType, readType, writeType = {}, {}, {}, {}
    local input = {
        schema = 2,
        kind = "record",
        name = "Fixture",
        qualifiedName = "fixture.Fixture",
        providerIdentity = "fixture.provider",
        ownerIdentity = "fixture.owner",
        ownerType = ownerType,
        interfaceType = interfaceType,
        hasConstructor = true,
        reference = "owner",
        fingerprint = "fixture-fingerprint",
        fields = {
            {
                name = "value",
                readable = true,
                writable = true,
                readType = readType,
                writeType = writeType,
                hasDefault = true,
                defaultValue = {readType = "legacy-data", readtype = "current-data"},
                reference = "field"
            }
        },
    }
    local info = providers.materializeDeriveInfo(state, input)
    for _, names in ipairs({
        {"qualifiedname", "qualifiedName"},
        {"provideridentity", "providerIdentity"},
        {"owneridentity", "ownerIdentity"},
        {"ownertype", "ownerType"},
        {"interfacetype", "interfaceType"},
        {"hasconstructor", "hasConstructor"},
    }) do
        local current, problem = providers.index(state, info, names[1])
        assert(problem == nil, names[1] .. " was rejected")
        local preceding, failure = providers.index(state, info, names[2])
        assert(preceding == nil and failure.code == "NUPP2810", names[2] .. " was not retired")
        assert(current == state.opaque[info].payload[names[2]], names[1] .. " changed the payload")
        assert(state.opaque[info].payload[names[1]] == nil, "public aliases leaked into the private Info payload")
    end
    local fields = assert(providers.index(state, info, "fields"))
    local field = assert(providers.index(state, fields, 1))
    for _, names in ipairs({
        {"readtype", "readType"},
        {"writetype", "writeType"},
        {"hasdefault", "hasDefault"},
        {"defaultvalue", "defaultValue"},
    }) do
        local current, problem = providers.index(state, field, names[1])
        assert(problem == nil, names[1] .. " was rejected")
        local preceding, failure = providers.index(state, field, names[2])
        assert(preceding == nil and failure.code == "NUPP2810", names[2] .. " was not retired")
        assert(current == state.opaque[field].payload[names[2]], names[1] .. " changed the payload")
        assert(state.opaque[field].payload[names[1]] == nil, "public aliases leaked into the private Field payload")
    end
    local default = assert(providers.index(state, field, "defaultvalue"))
    assert(providers.index(state, default, "readType") == "legacy-data", "a user data key was remapped")
    assert(providers.index(state, default, "readtype") == "current-data", "distinct user data keys were merged")
    local unknown, failure = providers.index(state, field, "READTYPE")
    assert(unknown == nil and failure and failure.code == "NUPP2810", "unknown keys must still be refused")
end

return M
