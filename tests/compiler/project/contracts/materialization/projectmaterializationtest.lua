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

local M = {}

function M.persistsVersionedMaterializationProductsAndObservations()
    local dir = tempProject({
        ["nupp.lua"] = [[
return {include = {"src"}, build = {outDir = "out", entries = {"main"}}}
]],
        [
            "src/main.nupp"
        ] = [[
local record Message
    text: string
end
const Codec: types.reflect.FieldCodec<Message> = comptime do
    return types.reflect.fieldcodec(types.reflect(Message))
end

return Codec:encode(Message(text = "ok")).text as string
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
    local coldBytes = read(dir .. "/out/main.lua")

    local warm, warmStats = {}, {}
    testAssert.eq(project.build(dir, {produced = warm, stats = warmStats}), 0)
    testAssert.eq(warmStats.checkedModules, 0, "the cached build rechecks nothing")
    testAssert.eq(
        warm.materializations[1].fingerprint,
        observation.fingerprint,
        "the cached build reports the same canonical product"
    )
    testAssert.eq(read(dir .. "/out/main.lua"), coldBytes, "cold and cached backend output is byte-identical")
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
        ["src/main.nupp"] = 'local models=require("witnessmodels") return models.make().child.value',
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
    local producer = read(dir .. "/out/witnessmodels.lua")
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
    local state = json.decode(read(dir .. "/out/.nupp-state.json"))
    testAssert.eq(
        state.modules["types.reflect"].compilerRuntime,
        true,
        "the generation-owned reflection facade is reused"
    )
    local bundled = require("nupp.compiler.bundled")
    testAssert.eq(
        read(dir .. "/out/types/reflect.lua"),
        read(bundled.moduleDir() .. "/../../types/reflect.lua"),
        "the current reflection artifact is preserved byte-for-byte"
    )
    testAssert.eq(read(dir .. "/out/witnessmodels.lua"), producer)
    testAssert.eq(answerFrom(dir .. "/out", dir), "true", producer .. read(dir .. "/out/main.lua"))
    local warm = {}
    testAssert.eq(project.build(dir, {stats = warm}), 0)
    testAssert.eq(warm.checkedModules, 0, "the complete reflection closure is then reused")
    testAssert.eq(read(dir .. "/out/witnessmodels.lua"), producer)
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
    testAssert.eq(answerFrom(dir .. "/out", dir), "true")
    remove(dir)
end

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
    testAssert.eq(lp64.checkedModules, 1, "the first target is checked")
    assert(read(dir .. "/out/main.lua"):find("return 16", 1, true), "the LP64 result was generated")

    local warm = {}
    testAssert.eq(project.build(dir, {stats = warm}), 0)
    testAssert.eq(warm.checkedModules, 0, "the same target reuses its result")

    write(dir .. "/nupp.lua", manifest("i686-unknown-linux-gnu"))
    local ilp32 = {}
    testAssert.eq(project.build(dir, {stats = ilp32}), 0)
    testAssert.eq(ilp32.checkedModules, 1, "changing the target invalidates the old result")
    assert(read(dir .. "/out/main.lua"):find("return 8", 1, true), "the ILP32 result replaces the LP64 result")
    remove(dir)
end

function M.exportedLayoutChangesInvalidateOnlyTheirReaders()
    local model = [[
local models = {}
struct models.Wire
    tag: int8
    value: int32
end
function models.body(): number return 1 end
return models
]]
    local dir = tempProject({
        [
            "nupp.lua"
        ] = [[
return {include = {"src"}, build = {outDir = "out", entries = {"main"},
   layoutTarget = "x86_64-unknown-linux-gnu"}}
]],
        ["src/main.nupp"] = [[
local models = require("models")
return comptime do return types.sizeof(models.Wire) end
]],
        ["src/models.nupp"] = model,
    })

    local cold = {}
    testAssert.eq(project.build(dir, {stats = cold}), 0)
    testAssert.eq(cold.checkedModules, 2, "the layout reader and declaration check cold")
    assert(read(dir .. "/out/main.lua"):find("return 8", 1, true), "the first layout was folded")

    write(dir .. "/src/models.nupp", model:gsub("return 1", "return 2"))
    local body = {}
    testAssert.eq(project.build(dir, {stats = body}), 0)
    testAssert.eq(body.checkedModules, 1, "a body edit checks only its module")
    testAssert.eq(body.reusedModules, 1, "the layout reader cuts off at the interface")

    write(dir .. "/src/models.nupp", model:gsub("value: int32", "value: number"))
    local changed = {}
    testAssert.eq(project.build(dir, {stats = changed}), 0)
    testAssert.eq(changed.checkedModules, 2, "a field layout edit rechecks its reader")
    assert(read(dir .. "/out/main.lua"):find("return 16", 1, true), "the changed layout replaced the old folded result")
    remove(dir)
end

return M
