local testAssert = require("assert")
local envMod = require("nupp.compiler.project.env")
local interfaceimage = require("nupp.compiler.project.interfaceimage")
local reflection = require("nupp.compiler.reflection")
local generics = require("nupp.compiler.types.generics")
local stable = require("nupp.compiler.stable")
local fs = require("nupp.compiler.fs")

local ROOT = fs.absolute(require("helpers.paths").tests .. "/..")
local QUIET_POOL_METHODS = {"free", "live", "pages", "reset", "used"}
local M = {}

local function checkedPool()
    local env = envMod.new(ROOT, {cache = false})
    local exports = assert(envMod.resolveModuleExports(env, "nupp.util.internal.pool"))
    return assert(exports.types.Pool), exports
end

local function effects(nominal, expected)
    local descriptor = reflection.describe(nominal, nominal.name, true)
    local answer = {}
    for index, node in ipairs(descriptor.types) do
        if node.kind == "record" and node.name == nominal.name then
            local methods = {}
            for _, field in ipairs(node.staticFields or {}) do
                if expected[field.name] ~= nil then
                    local callable = assert(descriptor.types[field.read])
                    testAssert.eq(callable.noYield, expected[field.name], node.name .. "." .. field.name)
                    methods[field.name] = callable.noYield
                end
            end
            testAssert.eq(stable(methods), stable(expected), "every application retains the complete effect surface")
            answer[#answer + 1] = stable(methods)
            local source = descriptor.sources[index]
            if source.origin then
                assert(source.origin == nominal, "the application keeps its declaration identity")
            end
        end
    end
    assert(#answer > 1, "the declaration and applications were reflected")
    table.sort(answer)

    return answer
end

function M.freshPoolApplicationsKeepFinalizedEffects()
    local pool = checkedPool()
    local expected = {}
    for _, name in ipairs(QUIET_POOL_METHODS) do
        expected[name] = true
    end
    effects(pool, expected)
end

function M.restoredPoolEffectsMatchFreshSourceWithoutReplacingMembers()
    local pool, exports = checkedPool()
    local expected, members = {}, {}
    for _, name in ipairs(QUIET_POOL_METHODS) do
        expected[name] = true
        members[name] = pool.staticByname[name]
    end
    local before = effects(pool, expected)
    local path = ROOT .. "/src/nupp/util/internal/pool.nupp"
    local image, problem = interfaceimage.encode({pool = {exports = exports, path = path}}, {projectPaths = {path}})
    assert(image, problem)
    local restored, failure = interfaceimage.decode(image, {nominals = {}})
    assert(restored, failure)
    local after = effects(restored.pool.exports.types.Pool, expected)
    testAssert.eq(stable(after), stable(before), "restoration preserves all reflected suspension effects")
    for _, name in ipairs(QUIET_POOL_METHODS) do
        testAssert.eq(pool.staticByname[name], members[name], "source publication keeps member identity")
        testAssert.eq(generics.rebind(members[name], {}), members[name], "an empty rebind keeps callable identity")
    end
end

function M.genericApplicationsKeepDistinctDeclaredEffects()
    local env = envMod.new(ROOT, {cache = false})
    local _, diagnostics, _, exports = envMod.checkModuleSource(
        env,
        ROOT .. "/nominal-effect-publication.nupp",
        [[
module nominal.effect.publication
export record Box<T>
    value: T
end
function Box.quiet<T>(self: Box<T>): integer
    return 1
end
function Box.waits<T>(self: Box<T>): integer
    coroutine.yield()
    return 1
end
]],
        {moduleName = "nominal.effect.publication"}
    )
    for _, diagnostic in ipairs(diagnostics) do
        assert(
            diagnostic.severity == "warning" or diagnostic.severity == "note",
            diagnostic.code .. ": " .. diagnostic.msg
        )
    end
    local box = assert(exports.types.Box)
    effects(box, {quiet = true, waits = false})
    local image, problem = interfaceimage.encode({sample = {exports = exports}})
    assert(image, problem)
    local restored, failure = interfaceimage.decode(image, {nominals = {}})
    assert(restored, failure)
    effects(restored.sample.exports.types.Box, {quiet = true, waits = false})
end

return M
