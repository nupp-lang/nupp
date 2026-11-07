local fixture = require("helpers.projectfixture")
local testAssert = fixture.testAssert
local project = fixture.project
local hash = fixture.hash
local json = fixture.json
local write = fixture.write
local read = fixture.read
local tempProject = fixture.tempProject
local remove = fixture.remove
local answerFrom = fixture.answerFrom

local hostSystem = require("helpers.projectfixture").hostSystem
local compiledRuntimeSources = require("helpers.projectfixture").compiledRuntimeSources

local M = {}

function M.annotationChangesInvalidateReflectedMaterializations()
    local dir = tempProject({
        ["nupp.lua"] = [[
return {include = {"src"}, build = {outDir = "out", entries = {"main"}}}
]],
        [
            "src/main.nupp"
        ] = [[
local models = require("models")
const UserCodec: types.reflect.FieldCodec<models.User> = comptime do
    return types.reflect.fieldcodec(types.reflect(models.User))
end
return UserCodec.fingerprint
]],
        [
            "src/models.nupp"
        ] = [[
local models = {}
@annotation(targets = {"record"})
local record wire
    name: string
end

@wire(name = "users")
record models.User
    id: integer
end
return models
]],
    })
    local cold, coldStats = {}, {}
    testAssert.eq(project.build(dir, {produced = cold, stats = coldStats}), 0)
    local firstObservation = assert(cold.materializations[1])
    testAssert.eq(firstObservation.schema, 2, "field-codec provider schema")
    testAssert.eq(firstObservation.abis.emitter, 2, "field-codec emitter ABI")
    testAssert.eq(firstObservation.abis.helper, 2, "field-codec helper ABI")
    testAssert.eq(firstObservation.abis.runtimeExpression, 2, "field-codec runtime-expression ABI")
    local first = firstObservation.fingerprint

    local source = read(dir .. "/src/models.nupp")
    write(dir .. "/src/models.nupp", source:gsub('name = "users"', 'name = "accounts"'))
    local changed, changedStats = {}, {}
    testAssert.eq(project.build(dir, {produced = changed, stats = changedStats}), 0)
    testAssert.eq(changedStats.checkedModules, 2, "changing exported reflected metadata rechecks its dependent module")
    assert(
        first ~= assert(changed.materializations[1]).fingerprint,
        "annotation values participate in the materialization fingerprint"
    )
    remove(dir)
end

function M.layoutTargetsSeparatePersistentComptimeResults()
    local function manifest(target)
        return (
            [=[
return {include = {"src"}, build = {outDir = "out", entries = {"main"},
   layoutTarget = %q}}
]=]
        ):format(target)
    end

    local dir = tempProject({
        ["nupp.lua"] = manifest("x86_64-unknown-linux-gnu"),
        [
            "src/main.nupp"
        ] = [[
local struct PointerSized
    tag: int8
    pointer: int8*
end
return comptime do return types.sizeof(PointerSized) end
]],
    })

    local lp64 = {}
    testAssert.eq(project.build(dir, {stats = lp64}), 0)
    local runtime = compiledRuntimeSources(dir, {"main"})
    testAssert.eq(lp64.checkedModules, 1 + runtime, "the first target checks the project and runtime source")

    local warm = {}
    testAssert.eq(project.build(dir, {stats = warm}), 0)
    testAssert.eq(warm.checkedModules, 0, "the same target reuses its result")

    write(dir .. "/nupp.lua", manifest("i686-unknown-linux-gnu"))
    local ilp32 = {}
    testAssert.eq(project.build(dir, {stats = ilp32}), 0)
    testAssert.eq(compiledRuntimeSources(dir, {"main"}), runtime)
    testAssert.eq(ilp32.checkedModules, 1 + runtime, "changing the target invalidates the old results")
    remove(dir)
end

return M
