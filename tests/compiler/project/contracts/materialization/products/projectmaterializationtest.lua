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

function M.persistsVersionedMaterializationProductsAndObservations()
    local dir = tempProject({
        ["nupp.lua"] = [[
return {include = {"src"}, build = {outDir = "out", entries = {"main"}}}
]],
        [
            "src/main.nupp"
        ] = [[
local record Position
    x: number
end

const PositionCodec: types.reflect.FieldCodec<Position> = comptime do
    return types.reflect.fieldcodec(types.reflect(Position))
end

return PositionCodec:encode(Position(x = 1))
]],
    })
    local cold, coldStats = {}, {}
    testAssert.eq(project.build(dir, {produced = cold, stats = coldStats}), 0)
    testAssert.eq(#cold.materializations, 1, "the cold build reports its materialization")
    local observation = cold.materializations[1]
    testAssert.eq(observation.provider, "fieldcodec", "provider observation")
    testAssert.eq(observation.schema, 2, "provider schema")
    testAssert.eq(observation.backend, "keyed", "selected backend")
    assert(observation.blueprintSize > 0 and observation.generatedSize > 0, "bounded sizes are reported")
    testAssert.eq(observation.abis.runtimeExpression, 2, "runtime-expression ABI")
    testAssert.eq(observation.blueprint, nil, "the public record omits the canonical payload")
    testAssert.eq(observation.generated, nil, "the public record omits generated source")

    local state = json.decode(read(dir .. "/out/.nupp-state.json"))
    local cached = state.modules.main.materializations[1]
    assert(
        cached.blueprint and cached.blueprint.fingerprint == observation.fingerprint,
        "the manifest cache retains the canonical blueprint"
    )
    assert(
        type(cached.generated) == "string" and #cached.generated > 0,
        "the manifest cache retains the backend output"
    )

    local warm, warmStats = {}, {}
    testAssert.eq(project.build(dir, {produced = warm, stats = warmStats}), 0)
    testAssert.eq(warmStats.checkedModules, 0, "the cached build rechecks nothing")
    testAssert.eq(
        warm.materializations[1].fingerprint,
        observation.fingerprint,
        "the cached build reports the same canonical product"
    )
    remove(dir)
end

function M.carriedRuntimeArtifactsRequireCurrentSourceAndEmittedBytes()
    local modules = require("nupp.tools.build.modules")
    local source = "module carried\nexport function value(): integer return 7 end\n"
    local artifact = "return {value=function() return 7 end}"
    local record = {sourceHash = hash.digest(source), artifactHash = hash.digest(artifact)}
    testAssert.eq(modules.currentCarriedArtifact(record, source, artifact, hash.digest), artifact)
    testAssert.eq(
        modules.currentCarriedArtifact(nil, source, artifact, hash.digest),
        nil,
        "an orphan is not generation-owned"
    )
    testAssert.eq(
        modules.currentCarriedArtifact({}, source, artifact, hash.digest),
        nil,
        "an incomplete record is not provenance"
    )
    testAssert.eq(
        modules.currentCarriedArtifact(record, nil, artifact, hash.digest),
        nil,
        "no source falls back to carried loading"
    )
    testAssert.eq(
        modules.currentCarriedArtifact(record, source, nil, hash.digest),
        nil,
        "a missing artifact is not reusable"
    )
    testAssert.eq(modules.currentCarriedArtifact(record, source .. "-- changed\n", artifact, hash.digest), nil)
    testAssert.eq(modules.currentCarriedArtifact(record, source, artifact .. "-- changed\n", hash.digest), nil)
end

function M.cachedProducersRetainNestedRuntimeTypeWitnesses()
    local dir = tempProject({
        ["nupp.lua"] = 'return {include={"src"},build={outDir="out",entries={"main"}}}',
        -- Reaches the reflection modules from the start, so the edit below changes
        -- only the consumer and not what the build has to link.
        [
            "src/main.nupp"
        ] = 'local models=require("witnessmodels") local _=types.reflect.runtime(models.Parent) '
        .. "return models.make().child.value",
        [
            "src/witnessmodels.nupp"
        ] = [[
local models = {}
local record Child
    value: integer
end
record models.Parent
    child: Child
end
function models.make(): models.Parent
    return models.Parent(child = Child(value = 7))
end
return models
]],
    })
    testAssert.eq(project.build(dir, {}), 0)
    write(
        dir .. "/src/main.nupp",
        [[
local models = require("witnessmodels")
local info = types.reflect.runtime(models.Parent)
local child = types.reflect.runtimetype(info, info.fields[1].type as integer)
local value = models.make()
return child == getmetatable(value.child) and value.child.value == 7
]]
    )
    local stats = {}
    testAssert.eq(project.build(dir, {stats = stats}), 0)
    testAssert.eq(stats.checkedModules, 1, "only the changed consumer is checked; its reflection facade is current")
    -- Before `answerFrom`, whose binary target is another manifest to check under.
    local warm = {}
    testAssert.eq(project.build(dir, {stats = warm}), 0)
    testAssert.eq(warm.checkedModules, 0, "the complete reflection closure is then reused")
    testAssert.eq(answerFrom(dir), "true")
    remove(dir)
end

function M.foreignWitnessesSurviveCollectionBetweenModuleLoads()
    local dir = tempProject({
        ["nupp.lua"] = 'return {include={"src"},build={outDir="out",entries={"main"}}}',
        ["src/childmodels.nupp"] = [[
local models = {}
record models.Child
    value: integer
end
return models
]],
        [
            "src/parentmodels.nupp"
        ] = [[
local children = require("childmodels")
local models = {}
record models.Parent
    child: children.Child
end
return models
]],
        [
            "src/main.nupp"
        ] = [[
local children = require("childmodels")
collectgarbage("collect")
collectgarbage("collect")
local parents = require("parentmodels")
local info = types.reflect.runtime(parents.Parent)
return types.reflect.runtimetype(info, info.fields[1].type as integer) == children.Child
]],
    })
    testAssert.eq(project.build(dir, {}), 0)
    testAssert.eq(answerFrom(dir), "true")
    remove(dir)
end

return M
