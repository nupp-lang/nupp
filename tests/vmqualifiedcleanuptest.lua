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

-- The explicit drop and the rearmed binding's scope exit both reach the
-- terminal; either one missing it leaves a single close.
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

function M.loadedCheckedModuleDoesNotNeedItsSource()
    local name = "checkedfixture"
    local path = name .. ".nupp"
    local result = parser.parse(
        [[
module checkedfixture

local calls: integer = 0
export function next(): integer
    calls += 1

    return calls
end
]],
        path
    )
    local env = envMod.new(".", {cache = false})
    local diagnostics = check.check(result, path, env, {moduleName = name})
    testAssert.eq(#diagnostics, 0, diagnostics[1] and diagnostics[1].msg or "check")
    result.source = nil

    local load = assert(program.load(result, name, path))
    local first, second = load(), load()
    testAssert.eq(first.next(), 1)
    testAssert.eq(first.next(), 2)
    testAssert.eq(second.next(), 1)
end

return M
