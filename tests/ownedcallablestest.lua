local providerstate = require("helpers.providerstate")
local parser = require("nupp.compiler.syntax.parser")
local checker = require("nupp.compiler.check")
local environment = require("nupp.compiler.project.env")
local M = {}

local function pack(...)
    return {n = select("#", ...), ...}
end

local ROOT = assert(os.getenv("NUPP_COMPILER_ROOT"))
local FACTORY = "nupp.runtime.provider.corecallable"
local fresh

local function compiler()
    if os.getenv("NUPP_SOURCE_CURRENT_CALLABLES") ~= "1" then
        return require
    end
    if not fresh then
        local owned = {}
        for _, name in ipairs({
            "graph",
            "graphcalls",
            "graphverify",
            "graphprune",
            "graphimage",
            "indexedaccess",
            "programgraph",
            "lower",
            "functiongraph",
            "functioncleanup",
            "taggedprofile",
            "taggedcalls",
            "taggedstatements",
            "taggedvalues",
            "ownedcallables",
            "ownedclosures",
            "coregraphcontracts",
            "coregraphexecutable"
        }) do
            owned["nupp.compiler.vm." .. name] = true
        end
        fresh = providerstate.instance(owned)
    end

    return fresh
end

local actual = {}
local env

local function checked(source, path, name)
    env = env or environment.new(ROOT .. "/native/core/tests/units")
    local parsed = parser.parse(source, path)
    assert(#parsed.errors == 0, parsed.errors[1] and parsed.errors[1].msg)
    local diagnostics = checker.check(parsed, path, env, {
        moduleName = name,
        strict = true,
        lints = {["unused-binding"] = "off"}
    })
    for _, diagnostic in ipairs(diagnostics) do
        assert(diagnostic.severity ~= "error", tostring(diagnostic.code) .. ": " .. tostring(diagnostic.msg))
    end

    return {name = name, path = path, parsed = parsed, diagnostics = diagnostics}
end

local function module(name)
    if not actual[name] then
        local path = ROOT .. "/src/" .. name:gsub("%.", "/") .. ".nupp"
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        actual[name] = checked(source, path, name)
    end

    return actual[name]
end

local function fixture()
    local name = "nupp.runtime.ownedcallablefixture"
    return checked(
        [[
module nupp.runtime.ownedcallablefixture
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
assert(body() == 7)
]],
        "=ownedcallablefixture.nupp",
        name
    )
end

local function catalog()
    local input = fixture()
    return compiler()(
        "nupp.compiler.vm.programgraph"
    ).describe({module("nupp.runtime.libraryvalues"), module(FACTORY), input}, input.name)
end

function M.checkedCapturesReachCompleteExecutableLowering()
    local load = compiler()
    local program = load("nupp.compiler.vm.programgraph")
    local p = catalog()
    local built = program.compile(p, load("nupp.compiler.vm.taggedprofile").forVersion(8))
    local executable = load("nupp.compiler.vm.coregraphexecutable")
    executable.validate(executable.fromChecked(built, 8))
end

function M.factoryAuthorityStaysBoundToTheCheckedCaptureClause()
    local load = compiler()
    local program = load("nupp.compiler.vm.programgraph")
    local p = catalog()
    local node, plan = next(p.callables)
    assert(node and plan)

    local function refused()
        local okay = pcall(program.verify, p)
        assert(not okay, "mutated callable metadata was admitted")
    end

    local saved = plan.owner
    plan.owner = plan.closure.id
    refused()
    plan.owner = saved
    local capture = table.remove(plan.captures)
    refused()
    plan.captures[#plan.captures + 1] = capture
    local module = plan.loader.module
    plan.loader.module = "foreign"
    refused()
    plan.loader.module = module
    local loader = p.requireByNode[plan.loader.node]
    p.requireByNode[plan.loader.node] = nil
    refused()
    p.requireByNode[plan.loader.node] = loader
    local site = p.callByNode[plan.call]
    p.callByNode[plan.call] = nil
    refused()
    p.callByNode[plan.call] = site
    assert(program.verify(p))
end

local function factory()
    return providerstate.instance({[FACTORY] = true})(FACTORY)
end

function M.uncalledReleaseRunsEveryCaptureOnceInReverseOrder()
    local events = {}

    local function close(value)
        events[#events + 1] = value
    end

    local wrapper = factory().create(
        function()
            error("uncalled body")
        end,
        {{value = "first", functions = {close}}, {value = "second", functions = {close}}}
    )
    wrapper.__nuppRelease()
    wrapper.__nuppRelease()
    assert(table.concat(events, ",") == "second,first")
    local okay, problem = pcall(wrapper)
    assert(not okay and tostring(problem):find("already called or dropped", 1, true))
end

function M.callsPreserveEmptyNilAndVariadicPacksAndConsumeTheWrapper()
    local create = factory().create
    local released = 0
    for _, count in ipairs({0, 1, 3}) do
        local wrapper = create(
            function(...)
                assert(select("#", ...) == count)
                return ...
            end,
            {
                {
                    value = true,
                    functions = {
                        function()
                            released = released + 1
                        end
                    }
                }
            }
        )
        local answer
        if count == 0 then
            answer = pack(wrapper())
        elseif count == 1 then
            answer = pack(wrapper(nil))
        else
            answer = pack(wrapper("a", nil, "c"))
        end
        assert(answer.n == count)
        wrapper.__nuppRelease()
        assert(not pcall(wrapper))
    end
    assert(released == 0)
end

function M.failedReleaseContinuesAndPreservesPrimaryAndSuppressedIdentity()
    local first, second = {}, {}
    local wrapper = factory().create(
        function()
        end,
        {
            {
                value = false,
                functions = {
                    function()
                        error(second, 0)
                    end
                }
            },
            {
                value = true,
                functions = {
                    function()
                        error(first, 0)
                    end
                }
            }
        }
    )
    local okay, failure = pcall(wrapper.__nuppRelease)
    assert(not okay and failure.primary == first and failure.suppressed[1] == second)
    wrapper.__nuppRelease()
end

function M.nilCleanupFailuresRemainFailuresAndStillConsumeTheWrapper()
    local calls = 0
    local wrapper = factory().create(
        function()
        end,
        {
            {
                value = true,
                functions = {
                    function()
                        calls = calls + 1;
                        error(nil, 0)
                    end
                }
            }
        }
    )
    local okay, problem = pcall(wrapper.__nuppRelease)
    assert(not okay and problem == nil and calls == 1)
    wrapper.__nuppRelease()
    assert(calls == 1)
end

function M.droppedWrappersReleaseCapturedObjectsWhileTheWrapperStaysLive()
    local weak = setmetatable({}, {__mode = "v"})
    local create = factory().create

    local function make(value)
        weak[1] = value
        return create(
            function()
                return value
            end,
            {
                {
                    value = value,
                    functions = {
                        function()
                        end
                    }
                }
            }
        )
    end

    local wrapper = make({})
    collectgarbage("collect")
    assert(weak[1] ~= nil)
    wrapper.__nuppRelease()
    collectgarbage("collect")
    collectgarbage("collect")
    assert(weak[1] == nil)
    assert(type(wrapper.__nuppRelease) == "function")
end

return M
