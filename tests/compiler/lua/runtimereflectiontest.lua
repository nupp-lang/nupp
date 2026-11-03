local testAssert = require("assert")
-- First-class record type witnesses and lazy runtime descriptors.
local parser = require("nupp.compiler.syntax.parser")
local check = require("helpers.fragment")
local gen = require("nupp.compiler.lua.gen")
local envMod = require("nupp.compiler.project.env")

local HERE = require("helpers.paths").tests
local env = envMod.new(HERE .. "/..")

local function compile(source)
    local parsed = parser.parse(source, "runtime_reflection.nupp")
    testAssert.eq(#parsed.errors, 0, "syntax errors")
    local diagnostics = check.check(parsed, "runtime_reflection.nupp", env)
    testAssert.eq(#diagnostics, 0, "check: " .. (diagnostics[1] and diagnostics[1].msg or ""))
    local code, generated = gen.generate(parsed, "runtime_reflection")
    testAssert.eq(#generated, 0, "generation diagnostics")

    return code
end

local function run(source)
    local code = compile(source)
    local chunk, why = loadstring(code, "@runtime_reflection")
    assert(chunk, why and (why .. "\n---\n" .. code))
    return chunk(), code
end

local M = {}

function M.constructionKeepsStoredCallbacksAndOmitsMethods()
    local result = run(
        [[
local events = require("events")
@derive(events.event)
local record Action
    callback: function(): integer
    extra: integer = 5
    function evaluate(self): integer
        return self.callback() + self.extra
    end
end
local description = Action.reflect()
local bus: events.MessageBus<integer> = events.newbus()
local result = 0
bus:observe(1, Action, |event| -> do result = event:evaluate() end)
bus:emit(1, Action, callback = function(): integer return 7 end)
return {construction = description.types[description.root].construction as unknown, result = result}
]]
    )
    testAssert.eq(#result.construction.params, 2)
    testAssert.eq(result.construction.params[1].name, "callback")
    testAssert.eq(result.construction.params[1].optional, false)
    testAssert.eq(result.construction.params[2].name, "extra")
    testAssert.eq(result.construction.params[2].optional, true)
    testAssert.eq(result.result, 12)
end

function M.recordsExposeTypeWitnessesAndLazyDescriptors()
    local result, code = run(
        [[
local record User
    id: integer
    name: string = "anonymous"
end

local witness: Type<User> = User
local value: User = new User(id = 7)
local first = User.reflect()
local second = User.reflect()
return {
    witness = witness == User,
    distinct = User ~= value,
    cached = first == second,
    name = first.name as string,
    field = first.fields[1].name as string,
}
]]
    )
    testAssert.eq(result.witness, true, "Type<T> witness")
    testAssert.eq(result.distinct, true, "type is not an instance")
    testAssert.eq(result.cached, true, "reflect cache")
    testAssert.eq(result.name, "User", "descriptor name")
    testAssert.eq(result.field, "id", "descriptor fields")
    assert(code:find("_G.nupp.__reflect.register", 1, true), code)
end

function M.doesNotEmitReflectionForUnusedRecords()
    local code = compile(
        [[
local record Quiet
    value: integer
end
local quiet = new Quiet(value = 1)
return quiet.value
]]
    )
    testAssert.eq(code:find("_G.nupp.__reflect", 1, true), nil, "unused reflection runtime")
end

function M.extensionsAreTypedAndLazy()
    local User = run(
        [[
local record User id: integer end
return {target = User, info = User.reflect() as types.reflect.Info}
]]
    )
    local reflection = require("types.reflect")
    local calls = 0
    local key = reflection.extensionkey(function(info)
        calls = calls + 1
        return info.name
    end)
    assert(User.info:extension(key) == "User")
    assert(User.info:extension(key) == "User" and calls == 1)
    local ok, problem = pcall(User.info.extension, User.info, {
        build = function()
            return "untyped"
        end
    })
    assert(not ok and tostring(problem):find("not an extension key", 1, true), tostring(problem))
end

function M.genericConsumersReceiveUnannotatedTypeMetadata()
    local result = run(
        [[
local function describe<T>(target: Type<T>): types.reflect.Info
    return types.reflect.runtime(target)
end
local record User
    name: string
end
local function make(): types.reflect.Info
    local record Local
        count: integer = 3
    end
    return describe(Local)
end
local first = describe(User)
local second = describe(User)
local left, right = make(), make()
return {cached = first == second, field = first.fields[1].name,
    distinct = left ~= right, same = left.fingerprint == right.fingerprint}
]]
    )
    testAssert.eq(result.cached, true)
    testAssert.eq(result.field, "name")
    testAssert.eq(result.distinct, true)
    testAssert.eq(result.same, true)
end

function M.genericReflectionSupportsStructWitnesses()
    local result = run(
        [[
local function describe<T>(target: Type<T>): types.reflect.Info
    return types.reflect.runtime(target)
end

local struct Point
    x: int32
    y: int32
end
local info = describe(Point)
return {kind = info.kind, field = info.fields[2].name}
]]
    )
    testAssert.eq(result.kind, "struct")
    testAssert.eq(result.field, "y")
end

function M.localWitnessDescriptorsFollowTheirOwnersLifetime()
    local make = run(
        [[
return function(): (unknown, types.reflect.Info)
    local record Item
        value: integer
    end
    return Item, types.reflect.runtime(Item)
end
]]
    )
    local witness, info = make()
    local weak = setmetatable({witness, info}, {__mode = "v"})
    info = nil
    collectgarbage("collect")
    testAssert.eq(weak[2], require("types.reflect").runtime(witness), "a live type retains its descriptor")
    info = weak[2]
    witness = nil
    collectgarbage("collect")
    testAssert.eq(weak[1], info.type, "a live descriptor retains its type")
    info = nil
    collectgarbage("collect")
    collectgarbage("collect")
    testAssert.eq(weak[1], nil, "an unused local type is collectible")
    testAssert.eq(weak[2], nil, "its descriptor is collectible")
end

function M.witnessMetadataDoesNotReplaceUserStaticMembers()
    local result = run(
        [[
local record User
    id: integer
    function reflect(): string
        return "mine"
    end
end
local function describe<T>(target: Type<T>): types.reflect.Info
    return types.reflect.runtime(target)
end
local info = describe(User)
return {name = info.name, custom = User.reflect()}
]]
    )
    testAssert.eq(result.name, "User")
    testAssert.eq(result.custom, "mine")
end

function M.aModuleReturnCanUseATypeWitness()
    local info = run([[
local record Message
    text: string
end
return types.reflect.runtime(Message)
]])
    testAssert.eq(info.name, "Message")
    testAssert.eq(info.fields[1].name, "text")
end

function M.nestedWitnessesRetainTheirDeclarationsAcrossShadowing()
    local result = run(
        [[
local record Leaf
    value: integer
end
local record Root
    leaf: Leaf
end
local expected = Leaf
local info = types.reflect.runtime(Root)
do
    local record Leaf
        value: integer
    end
    local actual = types.reflect.runtimetype(info, info.fields[1].type as integer)
    return {original = actual == expected, different = actual ~= Leaf}
end
]]
    )
    testAssert.eq(result.original, true)
    testAssert.eq(result.different, true)
end

function M.forwardWitnessesResolveAfterTheirDeclarationExecutes()
    local result = run(
        [[
local record First
    next: Second?
end
local info = types.reflect.runtime(First)
local index: integer = 0
for i, node in ipairs(info.types) do
    if node.kind == "record" and node.name == "Second" then index = i end
end
local before = types.reflect.runtimetype(info, index)
local record Second
    next: First?
end
local after = types.reflect.runtimetype(info, index)
return {absent = before == nil, correct = after == Second}
]]
    )
    testAssert.eq(result.absent, true)
    testAssert.eq(result.correct, true)
end

function M.freshLocalGraphsDoNotShareRuntimeWitnesses()
    local result = run(
        [[
local function make(): (types.reflect.Info, Type<unknown>?)
    local record Child
        value: integer
    end
    local record Parent
        child: Child
    end
    local info = types.reflect.runtime(Parent)
    return info, types.reflect.runtimetype(info, info.fields[1].type as integer)
end
local first, left = make()
local second, right = make()
return {distinct = left ~= right, stable = left == types.reflect.runtimetype(first, first.fields[1].type as integer),
    same = first.fingerprint == second.fingerprint}
]]
    )
    testAssert.eq(result.distinct, true)
    testAssert.eq(result.stable, true)
    testAssert.eq(result.same, true)
end

function M.aliasesRetainMetadataWhenTheirTypeIsErased()
    local result = run(
        [[
local record User
    name: string
end
local Alias = User
local erased = Alias as Type<unknown>
local stored: {Type<unknown>} = {Alias as Type<unknown>}
local first = types.reflect.runtime(erased)
local second = types.reflect.runtime(stored[1])
return {same = first == second, field = first.fields[1].name}
]]
    )
    testAssert.eq(result.same, true)
    testAssert.eq(result.field, "name")
end

function M.identityAndMetatableUsesDoNotCarryDescriptors()
    local result, code = run(
        [[
local record User
    name: string
end
local Alias = User;
(User as {[string]: any}).__tostring = function(): string return "user" end
local value = new User(name = "a")
return getmetatable(value) == Alias and User == (Alias as any)
]]
    )
    testAssert.eq(result, true)
    testAssert.eq(code:find("__reflect", 1, true), nil)
end

function M.lowercaseReflectionFunctionsKeepHandlesAndWitnessIdentity()
    local result = run(
        [[
local record Leaf value: integer end
local record Root leaf: Leaf end
local info = types.reflect.runtime(Root)
local extension = types.reflect.extensionkey(function(host: any): string return host.name end)
local reachable = types.reflect.runtimetype
local witness = reachable(info, info.fields[1].type as integer)
return {sameKey = types.reflect.extensionkey == types.reflect.extensionkey,
    sameWitness = reachable == types.reflect.runtimetype,
    witness = witness == Leaf, info = info, extension = extension}
]]
    )
    testAssert.eq(result.sameKey, true)
    testAssert.eq(result.sameWitness, true)
    testAssert.eq(result.witness, true)
    testAssert.eq(result.info:extension(result.extension), "Root")
    local source = [[
local types = {reflect = {extensionkey = function(): integer return 37 end}}
return types.reflect.extensionkey()
]]
    testAssert.eq(run(source), 37)
end

return M
