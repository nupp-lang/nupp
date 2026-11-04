local parser = require("nupp.compiler.syntax.parser")
local check = require("helpers.fragment")
local program = require("program")
local envMod = require("nupp.compiler.project.env")

local HERE = require("helpers.paths").tests
local env = envMod.new(HERE .. "/..")

local function diagnostics(source)
    local parsed = parser.parse(source, "serde_test.nupp")
    assert(#parsed.errors == 0, "serde fixture parses")
    return check.check(parsed, "serde_test.nupp", env)
end

local function run(moduleName, source)
    local filename = moduleName .. ".nupp"
    local parsed = parser.parse(source, filename)
    assert(#parsed.errors == 0, "serde fixture parses")
    local problems = check.check(parsed, filename, env, {moduleName = moduleName})
    for _, problem in ipairs(problems) do
        if problem.severity ~= "warning" and problem.severity ~= "note" then
            error(problem.code .. ": " .. problem.msg, 2)
        end
    end

    return program.run(parsed, moduleName, filename)
end

local M = {}

function M.publicNamespacesKeepOneJsonIdentityAndRespectLocalShadowing()
    local result = run(
        "serdetest.publicNamespacesKeepOneJsonIdentityAndRespectLocalShadowing",
        [=[
local direct = require("serde.json")
assert(serde.json == direct)
assert(serde.json.NULL == direct.NULL)
assert(serde.json.encodevalue == direct.encodevalue)
local record Entry
    id: uint32
end
local binding = serde.binding(Entry)
local bytes = direct.encode(binding, new Entry(id = 7))
assert(direct.decode(binding, bytes).id == 7)
assert(direct.decodevalue(bytes).id == 7)
assert(direct.encodevalue({id = 7}) == bytes)
do
    local serde = {json = {encodeValue = function(value: string): string return value end}}
    assert(serde.json.encodeValue("local") == "local")
end
return true
]=]
    )
    assert(result)
end

function M.schemaDebugPreservesWideIntegerSupport()
    local result = run(
        "serdetest.schemaDebugPreservesWideIntegerSupport",
        [=[
@derive(types.debug)
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
        "serdetest.debugNamesRecordsInsideContainers",
        [=[
@derive(types.debug)
local record Child
    label: string
end
@derive(types.debug)
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
        .. 'pair = {Child { label = "c" }, 1LL}, byName = {["only"] = Child { label = "d" }} }'
    assert(result == expected, result)
end

function M.debugPoliciesDoNotRequireTraversableFieldTypes()
    local result = run(
        "serdetest.debugPoliciesDoNotRequireTraversableFieldTypes",
        [=[
@derive(types.debug)
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
local text = types.reflect.extensionkey(function(_host: any): string
    return "text"
end)
local narrowed: types.reflect.ExtensionKey<integer> = text
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
local serde = require("serde")
local json = require("serde.json")
]]

function M.declarationBindingsAreLazyAndCached()
    local result = run(
        "serdetest.declarationBindingsAreLazyAndCached",
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
        "serdetest.rejectsMalformedAndOutOfRangeValues",
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
            "serdetest.nonFiniteMembersAreRefused",
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
        "serdetest.structsUseTheSameWitnessAndCodec",
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
        "serdetest.recursiveContainersRestoreNominalValues",
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
        "serdetest.policiesAreLocalToTheBinding",
        imports
        .. [[
local record User
    userId: integer
    secret: string = "private"
    labels: {string} = {}
end
local selected = serde.binding(User, new serde.Options(fields = {
    userId = new serde.FieldOptions(name = "id"),
    labels = new serde.FieldOptions(omitempty = true),
}, unknownmembers = "ignore"))
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
        "serdetest.debugDoesNotAuthorizeOrRestrictSerialization",
        imports
        .. [[
@derive(types.debug)
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
        "serdetest.bufferAndEmbeddedWriterKeepTheirBoundaries",
        imports
        .. [[
local record User id: integer end
local binding = serde.binding(User)
local buffer = require("string.buffer").new()
buffer:put("prefix:")
json.encodeinto(binding, new User(id = 7), buffer)
local first = buffer:get()
local writer = json.newwriter(buffer)
writer:startarray()
json.writevalue(binding, new User(id = 8), writer)
json.writevalue(binding, new User(id = 9), writer)
writer:endarray()
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

function M.canonicalSerdeKeysKeepKindsAndAccessMetadata()
    local result = run(
        "serdetest.canonicalSerdeKeysKeepKindsAndAccessMetadata",
        [=[
local serde = require("serde")
local document = require("serde.document")
local json = require("serde.json")
local adapters = require("serde.adapters")
local record Entry
    enabled: boolean = true
end
local access = serde.access(Entry)
assert(access.typeindex > 0)
assert(access.fields[1].typeindex > 0 and access.fields[1].hasdefault)
assert(access.parameters[1].typeindex > 0)
assert(access:constructionerror() == nil)
local binding = serde.binding(Entry, new serde.Options(naming = "snakecase", unknownmembers = "reject"))
local value = json.decode(binding, '{"enabled":false}')
assert(not value.enabled and json.encode(binding, value) == '{"enabled":false}')
local boolean = document.bool(true)
assert(boolean.kind == "bool" and boolean:bool())
local token = document.numbertoken("1e400")
assert(token.kind == "numbertoken" and token:numbertoken() == "1e400")
local integer = document.biginteger("123456789012345678901234567890")
assert(integer.kind == "biginteger" and integer:biginteger() == "123456789012345678901234567890")
return true
]=]
    )
    assert(result)
    local document = require("serde.document")
    local adapters = require("serde.adapters")
    local builder = require("serde.valuebuilder")
    assert(type(document.bool) == "function" and document.boolean == nil)
    assert(type(adapters.bool) == "function" and adapters.boolean == nil)
    assert(type(builder.bool) == "function" and builder.boolean == nil)
    assert(type(builder.scratchlen) == "function" and builder.scratchlength == nil)
    assert(
        document.Document.boolean == nil
        and document.Document.bigInteger == nil
        and document.Document.numberToken == nil
    )
    local codec = require("serde.json").codec()
    for _, pair in ipairs({
        {"cachedbindings", "cachedBindings"},
        {"decodebuffer", "decodeBuffer"},
        {"decodedocument", "decodeDocument"},
        {"encodedocument", "encodeDocument"},
        {"encodeinto", "encodeInto"},
        {"writevalue", "writeValue"}
    }) do
        assert(type(codec[pair[1]]) == "function" and codec[pair[2]] == nil, pair[1])
    end
    local provider = require("nupp.runtime.provider.lunajson")
    for _, pair in ipairs({
        {"arrayof", "arrayOf"},
        {"asarray", "asArray"},
        {"asobject", "asObject"},
        {"isarray", "isArray"},
        {"newwriter", "newWriter"},
        {"numbertoken", "numberToken"},
        {"encodedstring", "encodedString"},
        {"verifiedstring", "verifiedString"}
    }) do
        assert(type(provider[pair[1]]) == "function" and provider[pair[2]] == nil, pair[1])
    end
end

return M
