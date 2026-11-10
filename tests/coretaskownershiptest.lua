local test = require("assert")
local providerstate = require("helpers.providerstate")
local parser = require("nupp.compiler.syntax.parser")
local checker = require("nupp.compiler.check")
local environment = require("nupp.compiler.project.env")
local program = require("nupp.compiler.vm.programgraph")
local tagged = require("nupp.compiler.vm.taggedprofile")
local calls = require("nupp.compiler.vm.graphcalls")
local M = {}
local NAME = "nupp.runtime.provider.coretaskownership"

local function provider()
    return providerstate.instance({[NAME] = true})(NAME)
end

function M.mapsOnlyThePrivateCleanupProvider()
    test.eq(calls.coremodule("nupp.runtime.taskownership"), NAME)
    test.eq(calls.coremodule("nupp.vm.tasks"), "nupp.vm.tasks")
end

function M.callsTheCurrentTableHookWithoutArguments()
    local cleanup = provider()
    local count, arguments = 0, nil
    local body = {
        __nuppRelease = function(...)
            count = count + 1
            arguments = select("#", ...)
        end
    }
    test.eq(cleanup.release(body), nil)
    test.eq(count, 1)
    test.eq(arguments, 0)
    body.__nuppRelease = function(...)
        count = count + 2
        arguments = select("#", ...)
    end
    cleanup.release(body)
    test.eq(count, 3)
    test.eq(arguments, 0)
end

function M.preservesBothHookLookupsAndMetatableBehavior()
    local cleanup = provider()
    local reads, called = 0, false
    local body = setmetatable({}, {
        __index = function(_, key)
            test.eq(key, "__nuppRelease")
            reads = reads + 1
            if reads == 1 then
                return function()
                    error("called the predicate's hook")
                end
            end

            return function(...)
                test.eq(select("#", ...), 0)
                called = true
            end
        end
    })
    cleanup.release(body)
    test.eq(reads, 2)
    test.eq(called, true)
end

function M.propagatesTheExactHookError()
    local problem = {}
    local ok, raised = pcall(provider().release, {
        __nuppRelease = function()
            error(problem, 0)
        end
    })
    test.eq(ok, false)
    test.eq(raised, problem)
end

function M.ordinaryValuesDoNotRunAnUncalledBody()
    local cleanup = provider()
    local called = false
    cleanup.release(function()
        called = true
    end)
    for _, body in ipairs({{}, {__nuppRelease = false}, {__nuppRelease = {}}, false, 1, "body"}) do
        test.eq(cleanup.release(body), nil)
    end
    test.eq(cleanup.release(nil), nil)
    test.eq(called, false)
end

function M.takingCapturesRequireTheirCanonicalCheckedFactory()
    local source = [[
local record Resource
    value: integer
end
local function close(takes value: Resource): nil end
local function open(): affine(Resource, close)
    return Resource(value = 7)
end
local owned = open()
local body = function(): integer takes (owned)
    return owned.value
end
print(body())
]]
    local name = "corecleanupcapture"
    local path = "=" .. name .. ".nupp"
    local parsed = parser.parse(source, path)
    test.eq(#parsed.errors, 0)
    local env = environment.new(".", {memoryOnly = true, cache = false, nativeCompilerServices = false})
    local diagnostics = checker.check(parsed, path, env, {moduleName = name, strict = false})
    for _, diagnostic in ipairs(diagnostics) do
        assert(diagnostic.severity ~= "error", diagnostic.msg)
    end
    local okay, problem = pcall(
        program.describe,
        {{name = name, path = path, parsed = parsed, diagnostics = diagnostics}},
        name
    )
    test.eq(okay, false)
    assert(
        tostring(problem)
            :find("owned callable: checked factory is missing: nupp.runtime.provider.corecallable.create", 1, true),
        tostring(problem)
    )
end

return M
