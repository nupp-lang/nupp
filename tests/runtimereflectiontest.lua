local testAssert = require("nupp.test")
-- First-class record type witnesses and lazy runtime descriptors.
local parser = require("nupp.compiler.syntax.parser")
local check = require("fragment")
local gen = require("nupp.compiler.lua.gen")
local envMod = require("nupp.compiler.project.env")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local env = envMod.new(HERE .. "/..")

local function compile(source)
    local parsed = parser.parse(source, "runtime_reflection.g.nupp")
    testAssert.equal(#parsed.errors, 0, "syntax errors")
    local diagnostics = check.check(parsed, "runtime_reflection.g.nupp", env)
    testAssert.equal(#diagnostics, 0, "check: " .. (diagnostics[1] and diagnostics[1].msg or ""))
    local code, generated = gen.generate(parsed, "runtime_reflection")
    testAssert.equal(#generated, 0, "generation diagnostics")

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
local events = require("nupp.events")
@derive(events.Event)
local record Action
    callback: function(): integer
    extra: integer = 5
    function evaluate(self): integer
        return self.callback() + self.extra
    end
end
local description = Action.reflect()
local bus: events.MessageBus<integer> = events.newMessageBus()
local result = 0
bus:observe(1, Action, |event| -> do result = event:evaluate() end)
bus:emit(1, Action, callback = function(): integer return 7 end)
return {construction = description.types[description.root].construction, result = result}
]]
    )
    testAssert.equal(#result.construction.params, 2)
    testAssert.equal(result.construction.params[1].name, "callback")
    testAssert.equal(result.construction.params[1].optional, false)
    testAssert.equal(result.construction.params[2].name, "extra")
    testAssert.equal(result.construction.params[2].optional, true)
    testAssert.equal(result.result, 12)
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
    name = first.name,
    field = first.fields[1].name,
}
]]
    )
    testAssert.equal(result.witness, true, "Type<T> witness")
    testAssert.equal(result.distinct, true, "type is not an instance")
    testAssert.equal(result.cached, true, "reflect cache")
    testAssert.equal(result.name, "User", "descriptor name")
    testAssert.equal(result.field, "id", "descriptor fields")
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
    testAssert.equal(code:find("_G.nupp.__reflect", 1, true), nil, "unused reflection runtime")
end

function M.extensionsAreTypedAndLazy()
    local User = run([[
local record User id: integer end
return {target = User, info = User.reflect()}
]])
    local reflection = _G.nupp.reflect
    local calls = 0
    local key = reflection.extensionKey(function(info)
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
local function describe<T>(target: Type<T>): nupp.reflect.Info
    return nupp.reflect.runtime(target)
end
local record User
    name: string
end
local function make(): nupp.reflect.Info
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
    testAssert.equal(result.cached, true)
    testAssert.equal(result.field, "name")
    testAssert.equal(result.distinct, true)
    testAssert.equal(result.same, true)
end

function M.genericReflectionSupportsStructWitnesses()
    local result = run(
        [[
local function describe<T>(target: Type<T>): nupp.reflect.Info
    return nupp.reflect.runtime(target)
end

local struct Point
    x: int32
    y: int32
end
local info = describe(Point)
return {kind = info.kind, field = info.fields[2].name}
]]
    )
    testAssert.equal(result.kind, "struct")
    testAssert.equal(result.field, "y")
end

function M.localWitnessDescriptorsFollowTheirOwnersLifetime()
    local make = run(
        [[
return function()
    local record Item
        value: integer
    end
    return Item, nupp.reflect.runtime(Item)
end
]]
    )
    local witness, info = make()
    local weak = setmetatable({witness, info}, {__mode = "v"})
    info = nil
    collectgarbage("collect")
    testAssert.equal(weak[2], _G.nupp.reflect.runtime(witness), "a live type retains its descriptor")
    info = weak[2]
    witness = nil
    collectgarbage("collect")
    testAssert.equal(weak[1], info.type, "a live descriptor retains its type")
    info = nil
    collectgarbage("collect")
    collectgarbage("collect")
    testAssert.equal(weak[1], nil, "an unused local type is collectible")
    testAssert.equal(weak[2], nil, "its descriptor is collectible")
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
local function describe<T>(target: Type<T>): nupp.reflect.Info
    return nupp.reflect.runtime(target)
end
local info = describe(User)
return {name = info.name, custom = User.reflect()}
]]
    )
    testAssert.equal(result.name, "User")
    testAssert.equal(result.custom, "mine")
end

function M.aModuleReturnCanUseATypeWitness()
    local info = run([[
local record Message
    text: string
end
return nupp.reflect.runtime(Message)
]])
    testAssert.equal(info.name, "Message")
    testAssert.equal(info.fields[1].name, "text")
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
local info = nupp.reflect.runtime(Root)
do
    local record Leaf
        value: integer
    end
    local actual = nupp.reflect.runtimeType(info, info.fields[1].type as integer)
    return {original = actual == expected, different = actual ~= Leaf}
end
]]
    )
    testAssert.equal(result.original, true)
    testAssert.equal(result.different, true)
end

function M.forwardWitnessesResolveAfterTheirDeclarationExecutes()
    local result = run(
        [[
local record First
    next: Second?
end
local info = nupp.reflect.runtime(First)
local index: integer = 0
for i, node in ipairs(info.types) do
    if node.kind == "record" and node.name == "Second" then index = i end
end
local before = nupp.reflect.runtimeType(info, index)
local record Second
    next: First?
end
local after = nupp.reflect.runtimeType(info, index)
return {absent = before == nil, correct = after == Second}
]]
    )
    testAssert.equal(result.absent, true)
    testAssert.equal(result.correct, true)
end

function M.freshLocalGraphsDoNotShareRuntimeWitnesses()
    local result = run(
        [[
local function make(): (nupp.reflect.Info, Type<unknown>?)
    local record Child
        value: integer
    end
    local record Parent
        child: Child
    end
    local info = nupp.reflect.runtime(Parent)
    return info, nupp.reflect.runtimeType(info, info.fields[1].type as integer)
end
local first, left = make()
local second, right = make()
return {distinct = left ~= right, stable = left == nupp.reflect.runtimeType(first, first.fields[1].type as integer),
    same = first.fingerprint == second.fingerprint}
]]
    )
    testAssert.equal(result.distinct, true)
    testAssert.equal(result.stable, true)
    testAssert.equal(result.same, true)
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
local first = nupp.reflect.runtime(erased)
local second = nupp.reflect.runtime(stored[1])
return {same = first == second, field = first.fields[1].name}
]]
    )
    testAssert.equal(result.same, true)
    testAssert.equal(result.field, "name")
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
    testAssert.equal(result, true)
    testAssert.equal(code:find("__reflect", 1, true), nil)
end

return M
