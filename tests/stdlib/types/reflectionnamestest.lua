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
    test.eq(value.types[1].staticFields, nil)
    test.eq(value.types[1].staticfields[1].defaultvalue, user)
    test.eq(rawget(source, "qualifiedname"), nil)
    test.eq(rawget(source.fields[1], "hasdefault"), nil)
    test.eq(rawget(user, "sourcekind"), nil)
    test.eq(rawget(user, "hasdefault"), nil)
    test.eq(user.qualifiedName, "user-owned")
end

function M.comptimeCanonicalKeysPreserveDescriptorAndUserValueIdentity()
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
    local oldvalue, failure = providers.index(state, field, "defaultValue")
    test.eq(oldvalue, nil)
    test.eq(failure, nil)
    local newvalue = providers.index(state, field, "defaultvalue")
    test.eq(providers.operator(state, "==", newvalue, providers.index(state, field, "defaultvalue")), true)
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

function M.managedExclusiveOperationRetiresThePrecedingMethod()
    local namespace, runtime = {}, {}
    managed.install(namespace, runtime)
    local cell = namespace.__manage(
        {count = 0},
        function()
        end,
        "fixture"
    )
    local alias = cell:alias()
    test.eq(type(alias.withexclusive), "function")
    test.eq(alias.withExclusive, nil)
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
        test.eq(current[names[2]], nil, "preceding public key is retired")
        test.eq(rawget(node, names[1]), nil, "private graph was not changed")
    end
    for _, names in ipairs({
        {"readkey", "readKey"},
        {"readvalue", "readValue"},
        {"writekey", "writeKey"},
        {"writevalue", "writeValue"},
    }) do
        test.eq(current.index[names[1]], node.index[names[2]])
        test.eq(current.index[names[2]], nil)
        test.eq(rawget(node.index, names[1]), nil)
    end
    test.eq(current.construction.requiresfactory, false)
    test.eq(current.construction.requiresFactory, nil)
    test.eq(current.construction.params, node.construction.params)
    test.eq(current.cleanups[1].functiontype, 2)
    test.eq(current.cleanups[1].functionType, nil)
    test.eq(current.cleanups[1].key, "tasks.isDone", "native ID is unchanged")
    test.eq(current.cleanups[1].name, "readKey", "user member identity is unchanged")
    test.eq(current.kind, "protocolthread")
    test.eq(current.operation, "comptimetypecall")
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

-- Old accepting-seed descriptors and current descriptors converge at one public
-- boundary. Private T/blueprint tags and user data are never normalized in place.
function M.acceptingSeedTagsNormalizeAtEveryPublishedPosition()
    local tags = {
        {"protocolThread", "protocolthread"},
        {"genericAlias", "genericalias"},
        {"typeHandle", "typehandle"},
        {"packResult", "packresult"},
        {"constLiteral", "constliteral"},
        {"constVar", "constvar"},
        {"constOp", "constop"},
    }
    for _, names in ipairs(tags) do
        local user = {kind = names[1], operation = "comptimeTypeCall"}
        local source = {
            kind = names[1],
            fields = {{kind = names[1], defaultValue = user}},
            types = {{kind = names[1], operation = "comptimeTypeCall"}}
        }
        local current = shape.accept(source)
        test.eq(current.kind, names[2])
        test.eq(current.fields[1].kind, names[2])
        test.eq(current.types[1].kind, names[2])
        test.eq(current.types[1].operation, "comptimetypecall")
        test.eq(current.fields[1].defaultvalue, user)
        test.eq(source.kind, names[1])
        test.eq(source.fields[1].kind, names[1])
        test.eq(source.types[1].kind, names[1])
        test.eq(source.types[1].operation, "comptimeTypeCall")
        test.eq(user.kind, names[1])
        test.eq(user.operation, "comptimeTypeCall")
        local again = shape.accept(current)
        test.eq(again.kind, names[2])
        test.eq(again.fields[1].kind, names[2])
        test.eq(again.types[1].kind, names[2])
        test.eq(again.types[1].operation, "comptimetypecall")
        test.eq(again.fields[1].defaultvalue, user)
        local state = {}
        providers.installEvaluator(state, {})
        local held = providers.reflect(state, source)
        test.eq(providers.index(state, held, "kind"), names[2])
        local fields = providers.index(state, held, "fields")
        test.eq(providers.index(state, providers.index(state, fields, 1), "kind"), names[2])
        local nodes = providers.index(state, held, "types")
        local first = providers.index(state, nodes, 1)
        test.eq(providers.index(state, first, "kind"), names[2])
        test.eq(providers.index(state, first, "operation"), "comptimetypecall")
    end
end

function M.canonicalDescriptorKeysWinWithoutMergingUserData()
    local source = {
        qualifiedName = "old",
        qualifiedname = "current",
        fields = {{hasDefault = true, hasdefault = false}},
        types = {{noReturn = true, noreturn = false}}
    }
    local value = shape.accept(source)
    test.eq(value.qualifiedname, "current")
    test.eq(value.qualifiedName, nil)
    test.eq(value.fields[1].hasdefault, false)
    test.eq(value.fields[1].hasDefault, nil)
    test.eq(value.types[1].noreturn, false)
    test.eq(value.types[1].noReturn, nil)
    test.eq(source.fields[1].hasDefault, true)
    test.eq(source.fields[1].hasdefault, false)
end

return M
