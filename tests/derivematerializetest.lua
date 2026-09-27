local providers = require("nupp.compiler.comptime.materialize.providers")
local derive = require("nupp.compiler.comptime.materialize.derive")

local function evaluator()
    local state, env = {}, {}
    providers.installEvaluator(state, env)

    return state, env.nupp.derive
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

return M
