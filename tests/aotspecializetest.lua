local specialize = require("nupp.compiler.aot.specialize")

local M = {}

local function integer(value)
    return {op = "constant_i32", value = tostring(value), type = "u32"}
end

function M.keysParametersBySemanticIdentity()
    local helper = {
        name = "combine",
        cName = "combine",
        params = {
            {op = "helper_param", name = "left", cName = "shared", type = "u32"},
            {op = "helper_param", name = "right", cName = "shared", type = "u32"},
        },
        values = {
            {
                op = "u32_add",
                left = {op = "helper_param", name = "left", cName = "shared", type = "u32"},
                right = {op = "helper_param", name = "right", cName = "shared", type = "u32"},
                type = "u32",
            },
        },
        resultType = "u32",
        resultTypes = {"u32"},
    }
    local call = {
        op = "helper_call",
        helper = "combine",
        cName = "combine",
        args = {integer(1), integer(2)},
        resultTypes = {"u32"},
        type = "u32",
    }
    local candidate = assert(specialize.propose(call, {helpers = {combine = helper}}))
    assert(candidate.replacement.left.value == "1")
    assert(candidate.replacement.right.value == "2")
    assert(not rawequal(candidate.replacement.left, call.args[1]), "replacement literals are independent copies")

    helper.params[2].name = "left"
    assert(specialize.propose(call, {helpers = {combine = helper}}) == nil)
end

return M
