-- Helper reachability from every workgroup region.

local optimize = require("nupp.compiler.aot.optimize")

local M = {}

local function integer(value)
    return {op = "constant_i32", value = tostring(value), type = "u32"}
end

local function named(name)
    return {op = "local", name = name, cName = name, type = "u32"}
end

local function call(name)
    return {op = "helper_call", helper = name, cName = name, args = {}, resultTypes = {"u32"}, type = "u32"}
end

local function helper(name, value)
    return {name = name, cName = name, params = {}, values = {value}, resultType = "u32", resultTypes = {"u32"}}
end

function M.keepsHelpersUsedByEveryWorkgroupRegion()
    local ir = {
        helpers = {
            helper("prelude", integer(1)),
            helper("groups", integer(1)),
            helper("initial", integer(0)),
            helper("phase", integer(1)),
            helper("unused", integer(0)),
        },
        workgroup = {
            prelude = {{op = "let", name = "base", cName = "base", type = "u32", value = call("prelude")}},
            groups = {op = "u32_add", left = named("base"), right = call("groups"), type = "u32"},
            shared = {{name = "scratch", element = "u32", count = 1, initial = call("initial")}},
            statements = {
                {
                    op = "phase",
                    body = {{op = "shared_store", shared = "scratch", index = integer(0), value = call("phase")}},
                }
            },
        },
    }

    optimize.program(ir)
    local names = {}
    for _, kept in ipairs(ir.helpers) do
        names[kept.name] = true
    end
    for _, required in ipairs({"prelude", "groups", "initial", "phase"}) do
        assert(names[required], "workgroup helper " .. required .. " was removed")
    end
    assert(not names.unused, "an unreachable helper remains")
end

return M
