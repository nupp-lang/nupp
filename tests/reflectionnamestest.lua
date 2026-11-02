local test = require("assert")
local shape = require("nupp.runtime.reflectionshape")
local providers = require("nupp.compiler.comptime.materialize.providers")
local reflect = require("nupp.compiler.runtime.reflect")
local managed = require("nupp.runtime.managed")
local M = {}

local function descriptor()
    local user = {hasDefault = false, sourceKind = "user", qualifiedName = "user-owned"}
    local value = {
        schema = 1,
        name = "Value",
        qualifiedName = "fixture.Value",
        root = 1,
        fields = {{name = "fieldName", typeName = "string", hasDefault = false, defaultValue = user}},
        types = {
            {
                kind = "record",
                noReturn = false,
                typeParameters = {2},
                staticFields = {{name = "userField", hasDefault = true, defaultValue = user}},
            }
        },
    }

    return value, user
end

function M.acceptsOnlyKnownMetadataPositionsWithoutChangingPrivateInputs()
    local source, user = descriptor()
    local value = shape.accept(source)
    test.eq(value.qualifiedname, source.qualifiedName)
    test.eq(value.fields[1].typename, "string")
    test.eq(value.fields[1].hasdefault, false)
    test.eq(value.fields[1].defaultvalue, user)
    test.eq(value.types[1].noreturn, false)
    test.eq(value.types[1].typeparameters, source.types[1].typeParameters)
    test.eq(value.types[1].staticfields, value.types[1].staticFields)
    test.eq(value.types[1].staticfields[1].defaultvalue, user)
    test.eq(rawget(source, "qualifiedname"), nil)
    test.eq(rawget(source.fields[1], "hasdefault"), nil)
    test.eq(rawget(user, "sourcekind"), nil)
    test.eq(rawget(user, "hasdefault"), nil)
    test.eq(user.qualifiedName, "user-owned")
end

function M.comptimeAliasesPreserveDescriptorAndUserValueIdentity()
    local state = {}
    providers.installEvaluator(state, {})
    local source = descriptor()
    local first = providers.reflect(state, source)
    local second = providers.reflect(state, source)
    test.eq(providers.operator(state, "==", first, second), true)
    test.eq(providers.index(state, first, "qualifiedname"), "fixture.Value")
    local fields = providers.index(state, first, "fields")
    local field = providers.index(state, fields, 1)
    test.eq(providers.index(state, field, "hasdefault"), false)
    local oldvalue = providers.index(state, field, "defaultValue")
    local newvalue = providers.index(state, field, "defaultvalue")
    test.eq(providers.operator(state, "==", oldvalue, newvalue), true)
    test.eq(providers.index(state, newvalue, "sourceKind"), "user")
    test.eq(providers.index(state, newvalue, "sourcekind"), nil)
end

function M.runtimeDescriptorsRetainTheirCacheAndPrivateBlueprint()
    local namespace = {}
    local api = reflect.install(namespace)
    local source, user = descriptor()
    local witness = {}
    namespace.__reflect.blueprints[witness] = source
    local first = api.runtime(witness)
    test.eq(api.runtime(witness), first)
    test.eq(first.qualifiedname, "fixture.Value")
    test.eq(first.fields[1].defaultvalue, user)
    test.eq(first.types[1].staticfields[1].hasdefault, true)
    test.eq(rawget(source, "qualifiedname"), nil)
    test.eq(rawget(user, "sourcekind"), nil)
end

function M.managedExclusiveAliasIsTheSameOperation()
    local namespace, runtime = {}, {}
    managed.install(namespace, runtime)
    local cell = namespace.__manage(
        {count = 0},
        function()
        end,
        "fixture"
    )
    local alias = cell:alias()
    test.eq(alias.withexclusive, alias.withExclusive)
    local value, reason = alias:withexclusive(function(held)
        held.count = held.count + 1
        return held.count
    end)
    test.eq(value, 1)
    test.eq(reason, nil)
    cell:close()
    value, reason = alias:withexclusive(function()
        return 2
    end)
    test.eq(value, nil)
    test.eq(reason.code, "NUPP2614")
end

function M.acceptsEveryProducedDescriptorKeyAtItsExactRecordBoundary()
    local source, user = descriptor()
    local node = source.types[1]
    node.moduleName = "owner.Value"
    node.deriveKey = "owner.Value"
    node.arrayOf = 2
    node.varargType = 2
    node.borrowedFrom = 2
    node.borrowedFromMany = {2, 3}
    node.borrowedResult = 2
    node.parameterPack = 2
    node.returnPack = 2
    node.yieldPack = 2
    node.resumePack = 2
    node.startPack = 2
    node.resultKind = "owner.Value"
    node.transferOnly = false
    node.countTerm = 2
    node.readKey = 2
    node.readValue = 2
    node.writeKey = 2
    node.writeValue = 2
    node.kind = "protocolThread"
    node.operation = "comptimeTypeCall"
    node.index = {readKey = 2, readValue = 3, writeKey = 4, writeValue = 5}
    node.construction = {requiresFactory = false, params = {{name = "readKey"}}}
    node.cleanups = {{functionType = 2, name = "readKey", key = "tasks.isDone"}}
    local public = shape.accept(source)
    local current = public.types[1]
    for _, names in ipairs({
        {"modulename", "moduleName"},
        {"derivekey", "deriveKey"},
        {"arrayof", "arrayOf"},
        {"varargtype", "varargType"},
        {"borrowedfrom", "borrowedFrom"},
        {"borrowedfrommany", "borrowedFromMany"},
        {"borrowedresult", "borrowedResult"},
        {"parameterpack", "parameterPack"},
        {"returnpack", "returnPack"},
        {"yieldpack", "yieldPack"},
        {"resumepack", "resumePack"},
        {"startpack", "startPack"},
        {"resultkind", "resultKind"},
        {"transferonly", "transferOnly"},
        {"countterm", "countTerm"},
        {"readkey", "readKey"},
        {"readvalue", "readValue"},
        {"writekey", "writeKey"},
        {"writevalue", "writeValue"},
    }) do
        test.eq(current[names[1]], node[names[2]], names[1])
        test.eq(current[names[1]], current[names[2]], "accepting keys share the value")
        test.eq(rawget(node, names[1]), nil, "private graph was not changed")
    end
    for _, names in ipairs({
        {"readkey", "readKey"},
        {"readvalue", "readValue"},
        {"writekey", "writeKey"},
        {"writevalue", "writeValue"},
    }) do
        test.eq(current.index[names[1]], node.index[names[2]])
        test.eq(current.index[names[1]], current.index[names[2]])
        test.eq(rawget(node.index, names[1]), nil)
    end
    test.eq(current.construction.requiresfactory, false)
    test.eq(current.construction.requiresFactory, false)
    test.eq(current.construction.params, node.construction.params)
    test.eq(current.cleanups[1].functiontype, 2)
    test.eq(current.cleanups[1].functionType, 2)
    test.eq(current.cleanups[1].key, "tasks.isDone", "native ID is unchanged")
    test.eq(current.cleanups[1].name, "readKey", "user member identity is unchanged")
    test.eq(current.kind, "protocolThread", "single-valued tag changes belong to final adoption")
    test.eq(current.operation, "comptimeTypeCall")
    test.eq(public.fields[1].defaultvalue, user)
    test.eq(user.qualifiedName, "user-owned")
    test.eq(rawget(user, "qualifiedname"), nil)
    test.eq(rawget(node.construction, "requiresfactory"), nil)
    test.eq(rawget(node.cleanups[1], "functiontype"), nil)

    local state = {}
    providers.installEvaluator(state, {})
    local held = providers.reflect(state, source)
    local types = providers.index(state, held, "types")
    local first = providers.index(state, types, 1)
    local index = providers.index(state, first, "index")
    test.eq(providers.index(state, first, "modulename"), "owner.Value")
    test.eq(providers.index(state, index, "readkey"), 2)
    local namespace = {}
    local runtime = reflect.install(namespace)
    local witness = {}
    namespace.__reflect.blueprints[witness] = source
    local published = runtime.runtime(witness)
    test.eq(published.types[1].index.readkey, 2)
    test.eq(published.types[1].cleanups[1].functiontype, 2)
    test.eq(runtime.runtime(witness), published)
end

return M
