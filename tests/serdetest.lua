local parser = require("nupp.compiler.syntax.parser")
local check = require("fragment")
local gen = require("nupp.compiler.lua.gen")
local envMod = require("nupp.compiler.project.env")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local env = envMod.new(HERE .. "/..")

local function diagnostics(source)
    local parsed = parser.parse(source, "serde_test.g.nupp")
    assert(#parsed.errors == 0, "serde fixture parses")
    return check.check(parsed, "serde_test.g.nupp", env)
end

local function run(source)
    local parsed = parser.parse(source, "serde_test.g.nupp")
    assert(#parsed.errors == 0, "serde fixture parses")
    local problems = check.check(parsed, "serde_test.g.nupp", env)
    for _, problem in ipairs(problems) do
        if problem.severity ~= "warning" and problem.severity ~= "note" then
            error(problem.code .. ": " .. problem.msg, 2)
        end
    end
    local code, generated = gen.generate(parsed, "serde_test")
    assert(#generated == 0, generated[1] and generated[1].msg)
    local chunk, why = loadstring(code, "@serde_test")
    assert(chunk, why and (why .. "\n---\n" .. code))

    return chunk(), code
end

local M = {}

function M.schemaDebugPreservesWideIntegerSupport()
    local result = run(
        [=[
@derive(nupp.derive.Debug)
local record Wide
    signed: int64
    unsigned: uint64
end
return (new Wide(signed = -7LL, unsigned = 9ULL)):debug()
]=]
    )
    assert(result == "Wide { signed = -7LL, unsigned = 9ULL }", result)
end

-- A record names itself wherever it sits. One inside a list, a tuple, or a map
-- used to render as a bare table, because only fields carried the type's name.
function M.debugNamesRecordsInsideContainers()
    local result = run(
        [=[
@derive(nupp.derive.Debug)
local record Child
    label: string
end
@derive(nupp.derive.Debug)
local record Parent
    first: Child
    rest: {Child}
    pair: {Child, integer}
    byName: {[string]: Child}
end
return (new Parent(
    first = new Child(label = "a"),
    rest = {new Child(label = "b")},
    pair = {new Child(label = "c"), 1},
    byName = {only = new Child(label = "d")}
)):debug()
]=]
    )
    local expected = 'Parent { first = Child { label = "a" }, rest = {Child { label = "b" }}, '
        .. 'pair = {Child { label = "c" }, 1}, byName = {["only"] = Child { label = "d" }} }'
    assert(result == expected, result)
end

function M.debugPoliciesDoNotRequireTraversableFieldTypes()
    local result = run(
        [=[
@derive(nupp.derive.Debug)
local record Policies
    shown: string
    @debug(skip = true)
    callback: function(): nil
    @debug(redact = true)
    secretCallback: function(): nil
end
local noop = function(): nil end
return (new Policies(shown = "yes", callback = noop, secretCallback = noop)):debug()
]=]
    )
    assert(result == 'Policies { shown = "yes", secretCallback = <redacted> }', result)
end

function M.typedExtensionKeysKeepTheirValueType()
    local problems = diagnostics(
        [=[
local text = nupp.reflect.extensionKey(function(_host: any): string
    return "text"
end)
local narrowed: nupp.reflect.ExtensionKey<integer> = text
print(narrowed)
]=]
    )
    local first
    for _, problem in ipairs(problems) do
        if problem.severity ~= "warning" and problem.severity ~= "note" then
            first = problem
            break
        end
    end
    assert(
        first
        and first.code == "NUPP2001"
        and first.msg:find("ExtensionKey<string> is not a ExtensionKey<integer>", 1, true),
        "an extension key was narrowed to another value type"
    )
end

-- Schema/model-specific contracts are exercised by serdecontracttest, including
-- indexed values, documents, extension identity, ownership, and persistence.
local imports = [[
local serde = require("nupp.serde")
local json = require("nupp.serde.json")
]]

function M.declarationBindingsAreLazyAndCached()
    local result = run(
        imports
        .. [[
local record User
    id: uint32
    active: boolean
    name: string?
end
local binding = serde.binding(User)
local codec = json.codec()
local encoded = codec:encode(binding, new User(id = 41, active = false))
local restored = codec:decode(binding, encoded)
return {same = binding == serde.binding(User), encoded = encoded,
    id = restored.id, active = restored.active, name = restored.name,
    nominal = getmetatable(restored) == User}
]]
    )
    assert(result.same and result.nominal)
    assert(result.encoded == '{"id":41,"active":false,"name":null}', result.encoded)
    assert(result.id == 41 and result.active == false and result.name == nil)
end

function M.rejectsMalformedAndOutOfRangeValues()
    local result = run(
        imports
        .. [=[
local record Value
    id: uint32
    active: boolean
end
local binding = serde.binding(Value)
local rejected = 0
for _, input in ipairs({
    '{"id":0}', '{"id":-1,"active":true}', '{"id":4294967296,"active":true}',
    '{"id":1.5,"active":true}', '{"id":"1","active":true}',
    '{"id":1,"active":true,"id":2}', '{"id":1,"active":true,"extra":0}',
    '{"id":1,"active":true} trailing', '{"id":1,"active":true,}',
}) do
    local ok, problem = pcall(json.decode, binding, input)
    assert(not ok and tostring(problem) ~= "")
    rejected += 1
end
local first = json.decode(binding, '{"id":4294967295,"active":false}')
return {rejected = rejected, max = first.id}
]=]
    )
    assert(result.rejected == 9 and result.max == 4294967295)
end

function M.nonFiniteMembersAreRefused()
    assert(
        run(
            imports
            .. [[
local record Value value: number end
local binding = serde.binding(Value)
for _, value in ipairs({math.huge, -math.huge, 0 / 0}) do
    assert(not pcall(json.encode, binding, new Value(value = value)))
end
return true
]]
        )
    )
end

function M.structsUseTheSameWitnessAndCodec()
    local result = run(
        imports
        .. [[
local struct Vec3 x: float y: float z: float end
local witness: Type<Vec3> = Vec3
local binding = serde.binding(witness)
local bytes = json.encode(binding, new Vec3(1.25, 2.5, 5.0))
local value = json.decode(binding, bytes)
return {bytes = bytes, y = value.y}
]]
    )
    assert(result.bytes == '{"x":1.25,"y":2.5,"z":5}' and result.y == 2.5, result.bytes)
end

function M.recursiveContainersRestoreNominalValues()
    local result = run(
        imports
        .. [[
local record Node
    name: string
    children: {Node}
end
local binding = serde.binding(Node)
local bytes = json.encode(binding, new Node(name = "root", children = {new Node(name = "leaf", children = {})}))
local restored = json.decode(binding, bytes)
return {bytes = bytes, leaf = restored.children[1].name,
    nominal = getmetatable(restored.children[1]) == Node}
]]
    )
    assert(result.bytes == '{"name":"root","children":[{"name":"leaf","children":[]}]}', result.bytes)
    assert(result.leaf == "leaf" and result.nominal)
end

function M.policiesAreLocalToTheBinding()
    local result = run(
        imports
        .. [[
local record User
    userId: integer
    secret: string = "private"
    labels: {string} = {}
end
local selected = serde.binding(User, new serde.Options(fields = {
    userId = new serde.FieldOptions(name = "id"),
    labels = new serde.FieldOptions(omitEmpty = true),
}, unknownMembers = "ignore"))
local value = new User(userId = 7)
local first = json.decode(selected, '{"id":1,"extra":[null,true]}')
local second = json.decode(selected, '{"id":2}')
first.labels[1] = "changed"
return {selected = json.encode(selected, value), ordinary = json.encode(serde.binding(User), value),
    secret = second.secret, fresh = #second.labels == 0}
]]
    )
    assert(result.selected == '{"id":7}' and result.secret == "private" and result.fresh)
    assert(result.ordinary == '{"userId":7,"secret":"private","labels":[]}', result.ordinary)
end

function M.debugDoesNotAuthorizeOrRestrictSerialization()
    local result = run(
        imports
        .. [[
@derive(nupp.derive.Debug)
local record Credentials
    user: string
    @debug(redact = true)
    password: string
end
local value = new Credentials(user = "Ada", password = "secret")
return {shown = value:debug(), bytes = json.encode(serde.binding(Credentials), value)}
]]
    )
    assert(result.shown == 'Credentials { user = "Ada", password = <redacted> }', result.shown)
    assert(result.bytes == '{"user":"Ada","password":"secret"}', result.bytes)
end

function M.bufferAndEmbeddedWriterKeepTheirBoundaries()
    local result = run(
        imports
        .. [[
local record User id: integer end
local binding = serde.binding(User)
local buffer = require("nupp.text").newBuffer()
buffer:put("prefix:")
json.encodeInto(binding, new User(id = 7), buffer)
local first = buffer:get()
local writer = nupp.codec.json.newWriter(buffer)
writer:startArray()
json.writeValue(binding, new User(id = 8), writer)
json.writeValue(binding, new User(id = 9), writer)
writer:endArray()
writer:close()
return {first = first, embedded = buffer:get()}
]]
    )
    assert(result.first == 'prefix:{"id":7}' and result.embedded == '[{"id":8},{"id":9}]')
end

function M.bindingsKeepTheirValueType()
    local problems = diagnostics(
        imports
        .. [[
local record Left value: string end
local record Right value: string end
local left: serde.Binding<Left> = serde.binding(Left)
local wrong: serde.Binding<Right> = left
return wrong
]]
    )
    local found = false
    for _, problem in ipairs(problems) do
        found = found or problem.code == "NUPP2001"
    end
    assert(found, "a binding was assigned a different nominal value type")
end

return M
