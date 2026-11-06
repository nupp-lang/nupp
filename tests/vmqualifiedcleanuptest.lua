local testAssert = require("assert")
local parser = require("nupp.compiler.syntax.parser")
local check = require("helpers.fragment")
local envMod = require("nupp.compiler.project.env")
local program = require("program")

local M = {}

local function run(name, body)
    local source = [[
module ]]
        .. name
        .. [[

local resources = {closed = 0}
local interface Token end
local record Value<T> is Token
    id: integer
end
function resources.release<T is Token>(takes value: T): nil
    resources.closed += 1
    @nosuspend do
        local _raw = @unsafe own.release(value)
    end
end
type resources.Owned<T> = affine(Value<T>, resources.release)
local record Factory<T>
    value: T
    function acquire(self: Factory<T>): resources.Owned<T>
        return Value<T>(id = 1)
    end
    function use(self: Factory<T>): nil
]]
        .. body
        .. [[
    end
end
function resources.run(): nil
    Factory(value = 7):use()
end
export = resources
]]
    local path = name .. ".nupp"
    local result = parser.parse(source, path)
    testAssert.eq(#result.errors, 0, result.errors[1] and result.errors[1].msg or "syntax")
    local env = envMod.new(".", {cache = false})
    local diagnostics = check.check(result, path, env, {moduleName = name})
    testAssert.eq(#diagnostics, 0, diagnostics[1] and diagnostics[1].msg or "check")
    local resources = program.run(result, name, path)
    resources.run()

    return resources.closed
end

function M.genericMethodDropsAQualifiedExportTerminal()
    testAssert.eq(run("qualifiedcleanupdrop", [[
        local value = self:acquire()
        own.drop(value)
]]), 1)
end

function M.genericMethodRearmsAQualifiedExportTerminal()
    testAssert.eq(
        run(
            "qualifiedcleanuprearm",
            [[
        local value = self:acquire()
        own.drop(value)
        value = self:acquire()
]]
        ),
        2
    )
end

return M
