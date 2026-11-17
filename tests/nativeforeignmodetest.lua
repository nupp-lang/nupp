local unit = require("nupp.compiler.vm.nativeunit")
local nativeos = require("nupp.compiler.vm.nativeos")
local fs = require("nupp.compiler.fs")
local M = {}

function M.consumingAndExclusiveParametersKeepTheCAbi()
    local directory = os.tmpname()
    os.remove(directory)
    assert(fs.mkdir(directory .. "/src/nupp/test"))
    local path = directory .. "/src/nupp/test/foreignmodes.nupp"
    local file = assert(io.open(path, "wb"))
    file:write(
        [[
module nupp.test.foreignmodes
cdef function nuppRelease(takes value: voidptr): int32
cdef function nuppMutate(exclusive value: voidptr): int32
export function release(takes value: voidptr): int32
    return nuppRelease(value)
end
export function mutate(exclusive value: voidptr): int32
    return nuppMutate(value)
end
]]
    )
    file:close()
    local ok, problem = pcall(function()
        local session = unit.session(
            directory,
            {{moduleName = "nupp.test.foreignmodes", path = path}},
            "aarch64-apple-darwin",
            {"src"}
        )
        local functions = session.module("nupp.test.foreignmodes").functions
        for _, name in ipairs({"release", "mutate"}) do
            local owner = assert(functions[name])
            local call = owner.body.body.stats[1].exprs[1]
            local physical = nativeos.foreign(owner, call, "int32")
            assert(#physical.params == 1 and physical.params[1] == "voidptr")
            assert(physical.result == "int32")
            assert(nativeos.validate(physical))
        end
    end)
    for _, name in ipairs({
        path,
        directory .. "/src/nupp/test",
        directory .. "/src/nupp",
        directory .. "/src",
        directory
    }) do
        os.remove(name)
    end
    assert(ok, tostring(problem))
end

return M
