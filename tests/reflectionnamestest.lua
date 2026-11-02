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

return M
