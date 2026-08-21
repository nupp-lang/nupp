local parser = require("nupp.compiler.parser")
local check = require("fragment")
local gen = require("nupp.compiler.gen")
local envMod = require("nupp.compiler.env")

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

function M.preparesAndCachesRecordJson()
   local result = run([=[
@derive(nupp.derive.Serde)
local record User
    id: uint32
    active: boolean
    name: string?
end

local first = nupp.data.serde.of(User)
local second = nupp.data.serde.of(User)
local codec = nupp.data.serde.json()
local prepared = codec:prepare(first)
local again = codec:prepare(first)
local text = prepared:encode(new User(id = 41, active = true, name = "Ada"))
local output = string.buffer.new()
prepared:write(new User(id = 42, active = false), output)
local large = string.rep("x", 4096)
local largeOutput = string.buffer.new()
largeOutput:put("prefix:")
prepared:write(new User(id = 43, active = true, name = large), largeOutput)
local streamed = string.buffer.new()
local writer = nupp.data.json.writer(streamed)
prepared:write(new User(id = 44, active = true, name = "streamed"), writer)
writer:close()
local largeStreamed = string.buffer.new()
local largeWriter = nupp.data.json.writer(largeStreamed)
prepared:write(new User(id = 45, active = true, name = string.rep("y", 128 * 1024)), largeWriter)
local stagedLength = #largeStreamed
largeWriter:close()
local restored, problem = prepared:decode(text)
local input = string.buffer.new()
input:put(text)
local bufferedRestored, bufferedProblem = prepared:decodeBuffer(input)
local rejected, rejection = prepared:decode(
    [[{"id":41,"active":true,"name":"Ada","extra":{"nested":[1,2]}}]]
)
return {
    sameBinding = first == second,
    samePrepared = prepared == again,
    schemaName = first:schema().name,
    memberIndex = first:schema():expectMember("active").index,
    text = text,
    buffered = output:tostring(),
    largeBuffered = largeOutput:tostring(),
    streamed = streamed:tostring(),
    largeStreamedLength = #largeStreamed,
    stagedLength = stagedLength,
    id = restored and restored.id,
    bufferedId = bufferedRestored and bufferedRestored.id,
    bufferedProblem = bufferedProblem,
    name = restored and restored.name,
    problem = problem,
    rejected = rejected,
    rejection = rejection,
}
]=])
   assert(result.sameBinding and result.samePrepared, "serde preparation was not cached")
   assert(result.schemaName == "User" and result.memberIndex == 2,
      "derived schema lost its logical identity")
   assert(result.text == '{"id":41,"active":true,"name":"Ada"}', result.text)
   assert(result.buffered == '{"id":42,"active":false}', result.buffered)
   assert(result.largeBuffered == 'prefix:{"id":43,"active":true,"name":"'
      .. string.rep("x", 4096) .. '"}', "large prepared write did not append exactly")
   assert(result.streamed == '{"id":44,"active":true,"name":"streamed"}',
      "prepared writer traversal did not append exactly")
   assert(result.stagedLength > 128 * 1024 and result.largeStreamedLength == result.stagedLength + 1,
      "prepared writer did not threshold-flush during a large root")
   assert(result.id == 41 and result.name == "Ada" and result.problem == nil,
      "prepared record did not round-trip")
   assert(result.bufferedId == 41 and result.bufferedProblem == nil,
      "prepared buffer decode did not round-trip")
   assert(result.rejected == nil and result.rejection:find("extra", 1, true),
      "strict raw-key decoding accepted an unknown member")
end

function M.profilesRenameKeysAndIgnoreUnknownValues()
   local result = run([=[
@derive(nupp.derive.Serde)
local record Item
    value: integer
end
local codec = nupp.data.json.newCodec{
    unknownMembers = "ignore",
    fieldNames = function(member: nupp.data.serde.Member): string
        return member.name == "value" and "a\"b" or member.name
    end,
}
local prepared = codec:prepare(nupp.data.serde.of(Item))
local text = prepared:encode(new Item(value = 7))
local restored, problem = prepared:decode([[{"ignored":{"deep":[1,2]},"a\"b":9}]])
return {text = text, value = restored and restored.value, problem = problem}
]=])
   assert(result.text == '{"a\\"b":7}', result.text)
   assert(result.value == 9 and result.problem == nil,
      "profile raw-byte lookup did not decode the escaped wire name")
end

function M.dynamicValuesUseDenseResolvedSlots()
   local result = run([=[
const serde = nupp.data.serde
local builder = new serde.SchemaBuilder()
builder:structure("example.Request")
builder:required("id", serde.uint32)
builder:defaulted("active", serde.boolean, true)
builder:optional("name", serde.string)
local schema = builder:freeze()
local binding = serde.dynamic(schema)
local id = schema:expectMember("id")
local value = binding:newValue()
value:set(id, 11)
local rebound = binding:bind{id = 12}
local prepared = serde.json():prepare(binding)
local restored, problem = prepared:decode(prepared:encode(rebound))
local missingOk, missing = pcall(binding.bind, binding, {name = "absent"})
return {
    direct = value:get(id),
    id = restored and restored:get("id"),
    active = restored and restored:get("active"),
    problem = problem,
    missingOk = missingOk,
    missing = tostring(missing),
}
]=])
   assert(result.direct == 11 and result.id == 12 and result.active == true,
      "dynamic slots or defaults were not preserved")
   assert(result.problem == nil, result.problem)
   assert(not result.missingOk and result.missing:find("missing required member id", 1, true),
      "dynamic binding skipped required validation")
end

function M.dynamicValuesValidateSchemaKindsAndIntegerRanges()
   local result = run([=[
const serde = nupp.data.serde
local builder = new serde.SchemaBuilder()
builder:structure("example.Range")
builder:required("small", serde.uint8)
local binding = serde.dynamic(builder:freeze())
local wrongTypeOk, wrongType = pcall(binding.bind, binding, {small = "one"})
local rangeOk, range = pcall(binding.bind, binding, {small = 256})
local decoded, decodeProblem = serde.json():prepare(binding):decode([[{"small":256}]])
return {
    wrongTypeOk = wrongTypeOk,
    wrongType = tostring(wrongType),
    rangeOk = rangeOk,
    range = tostring(range),
    decoded = decoded,
    decodeProblem = decodeProblem,
}
]=])
   assert(not result.wrongTypeOk and result.wrongType:find("must be an integer", 1, true),
      "dynamic binding accepted the wrong scalar kind")
   assert(not result.rangeOk and result.range:find("outside uint8", 1, true),
      "dynamic binding accepted an out-of-range integer")
   assert(result.decoded == nil and result.decodeProblem:find("range", 1, true),
      "prepared native decode accepted an out-of-range integer")
end

function M.documentMembersStayInsideThePreparedTraversal()
   local result = run([=[
const serde = nupp.data.serde
local builder = new serde.SchemaBuilder()
builder:structure("example.Envelope")
builder:required("id", serde.uint32)
builder:optional("payload", serde.document)
local binding = serde.dynamic(builder:freeze())
local prepared = serde.json():prepare(binding)
local text = prepared:encode(binding:bind{
    id = 9,
    payload = {items = {1, 2}, enabled = true},
})
local value, problem = prepared:decode(text)
local payload = value and value:get("payload")
return {
    text = text,
    second = payload and payload.items[2],
    enabled = payload and payload.enabled,
    problem = problem,
}
]=])
   assert(result.text:find('"payload":', 1, true), result.text)
   assert(result.second == 2 and result.enabled == true and result.problem == nil,
      "document member did not round-trip through prepared serde")
end

function M.structsShareTheTypedWitnessAndCodec()
   local result, code = run([=[
@derive(nupp.derive.Serde)
local struct Vec3
    x: float
    y: float
    z: float
end
local witness: Type<Vec3> = Vec3
local binding: nupp.data.serde.Binding<Vec3> = nupp.data.serde.of(witness)
local prepared = nupp.data.serde.json():prepare(binding)
local text = prepared:encode(new Vec3(1.25, 2.5, 5.0))
local value, problem = prepared:decode(text)
return {text = text, y = value and value.y, problem = problem}
]=])
   assert(result.text == '{"x":1.25,"y":2.5,"z":5.0}', result.text)
   assert(result.y == 2.5 and result.problem == nil, "struct serde did not round-trip")
   assert(code:find("__derive.register", 1, true), "struct derive data was not registered")
end

function M.preparedDebugSharesRecordAndStructSerdeBindings()
   local result, code = run([=[
@derive(nupp.derive.Debug, nupp.derive.Serde)
local record Credentials
    user: string
    @debug(redact = true)
    password: string
    @debug(skip = true)
    cache: string
end

@derive(nupp.derive.Debug, nupp.derive.Serde)
local struct Vec2
    x: float
    y: float
end

const serde = nupp.data.serde
local binding = serde.of(Credentials)
local prepared = serde.prepareDebug(binding)
local again = serde.prepareDebug(binding)
local value = new Credentials(user = "ada", password = "hunter2", cache = "cached")
local output = string.buffer.new()
prepared:write(value, output)
local point = new Vec2(1.25, 2.5)
return {
    method = value:debug(),
    prepared = prepared:format(value),
    written = output:tostring(),
    same = prepared == again,
    structMethod = point:debug(),
    structPrepared = serde.prepareDebug(serde.of(Vec2)):format(point),
}
]=])
   local expected = 'Credentials { user = "ada", password = <redacted> }'
   assert(result.method == expected and result.prepared == expected
      and result.written == expected, "record Debug paths did not share one plan")
   assert(result.same == true, "prepared Debug was not cached on the binding")
   assert(result.structMethod == "Vec2 { x = 1.25, y = 2.5 }"
      and result.structPrepared == result.structMethod,
      "struct Debug did not use its serde binding")
   assert(not code:find("debugType", 1, true),
      "Debug emitted its obsolete per-field type recipe")
   local _, serdeRecipes = code:gsub('%["serde"%]', "")
   assert(serdeRecipes == 2,
      "Debug and Serde did not merge to one schema recipe per declaration")
end

function M.dynamicSchemasUseIndexedDebugMetadata()
   local result = run([=[
const serde = nupp.data.serde
local label: nupp.data.serde.MetadataKey<string> = serde.metadataKey()
local childBuilder = new serde.SchemaBuilder()
childBuilder:structure("example.Profile")
childBuilder:required("region", serde.string)
local childSchema = childBuilder:freeze()
local childBinding = serde.dynamic(childSchema)
local builder = new serde.SchemaBuilder()
builder:structure("example.Credentials")
builder:required("user", serde.string)
builder:required("password", serde.string)
builder:required("profile", childSchema)
builder:optional("cache", serde.document)
builder:metadata(label, "credentials")
builder:memberMetadata("password", serde.debugRedact, true)
builder:memberMetadata("cache", serde.debugSkip, true)
local schema = builder:freeze()
local binding = serde.dynamic(schema)
local value = binding:bind{
    user = "ada",
    password = "hunter2",
    profile = childBinding:bind{region = "us-east-1"},
    cache = {1, 2},
}
local prepared = serde.prepareDebug(binding)
local output = string.buffer.new()
prepared:write(value, output)
return {
    formatted = prepared:format(value),
    written = output:tostring(),
    rootMetadata = schema:metadata(label),
    redacted = schema:expectMember("password"):metadata(serde.debugRedact),
}
]=])
   local expected = 'example.Credentials { user = "ada", password = <redacted>, '
      .. 'profile = example.Profile { region = "us-east-1" } }'
   assert(result.formatted == expected and result.written == expected,
      "dynamic Debug did not use the prepared schema")
   assert(result.rootMetadata == "credentials" and result.redacted == true,
      "indexed schema metadata did not retain its typed values")
end

function M.debugOnlyBindingsStayInternal()
   local result = run([=[
@derive(nupp.derive.Debug)
local record DebugOnly
    value: integer
end
local ok, problem = pcall(function(): any
    return nupp.data.serde.of(DebugOnly)
end)
return {debugged = (new DebugOnly(value = 7)):debug(), ok = ok, problem = tostring(problem)}
]=])
   assert(result.debugged == "DebugOnly { value = 7 }", result.debugged)
   assert(result.ok == false and result.problem:find("Serde was not derived", 1, true),
      "Debug-only internal binding escaped through serde.of")
end

function M.schemaDebugPreservesWideIntegerSupport()
   local result = run([=[
@derive(nupp.derive.Debug)
local record Wide
    signed: int64
    unsigned: uint64
end
return (new Wide(signed = -7LL, unsigned = 9ULL)):debug()
]=])
   assert(result == "Wide { signed = -7LL, unsigned = 9ULL }", result)
end

function M.debugPoliciesDoNotRequireTraversableFieldTypes()
   local result = run([=[
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
]=])
   assert(result == 'Policies { shown = "yes", secretCallback = <redacted> }', result)
end

function M.recursiveContainersUseTheSameLogicalGraph()
   local result = run([=[
@derive(nupp.derive.Serde)
local record Child
    label: string
end

@derive(nupp.derive.Serde)
local record Parent
    child: Child
    children: {Child}
    values: {integer}
end
local binding = nupp.data.serde.of(Parent)
local childSchema = binding:schema():expectMember("child").target as nupp.data.serde.Schema
local prepared = nupp.data.serde.json():prepare(binding)
local text = prepared:encode(
    new Parent(
        child = new Child(label = "nested"),
        children = {new Child(label = "listed")},
        values = {1, 2}
    )
)
local value, problem = prepared:decode(text)
return {
    childKind = childSchema.kind,
    childName = childSchema.name,
    label = value and value.child.label,
    listed = value and value.children[1].label,
    second = value and value.values[2],
    problem = problem,
}
]=])
   assert(result.childKind == "structure" and result.childName == "Child",
      "nested declaration became an untyped document")
   assert(result.label == "nested" and result.listed == "listed"
      and result.second == 2 and result.problem == nil,
      "nested prepared fallback did not preserve nominal values")
end

function M.oneSchemaSupportsNominalAndDynamicBindingsTogether()
   local result = run([=[
@derive(nupp.derive.Serde)
local record Child
    label: string
end
@derive(nupp.derive.Serde)
local record Parent
    child: Child
    children: {Child}
    values: {integer}
end
const serde = nupp.data.serde
local nominal = serde.of(Parent)
local childSchema = nominal:schema():expectMember("child").target as nupp.data.serde.Schema
local dynamicChild = serde.dynamic(childSchema)
local dynamicParent = serde.dynamic(nominal:schema())
local codec = serde.json()
local nominalPrepared = codec:prepare(nominal)
local dynamicPrepared = codec:prepare(dynamicParent)
local nominalText = nominalPrepared:encode(
    new Parent(
        child = new Child(label = "nominal"),
        children = {new Child(label = "nominal-list")},
        values = {1, 2}
    )
)
local dynamicText = dynamicPrepared:encode(dynamicParent:bind{
    child = dynamicChild:bind{label = "dynamic"},
    children = {dynamicChild:bind{label = "dynamic-list"}},
    values = {3, 4},
})
local nominalValue = assert(nominalPrepared:decode(nominalText))
local dynamicValue = assert(dynamicPrepared:decode(dynamicText))
local child = dynamicValue:get("child") as nupp.data.serde.DynamicValue
return {
    nominal = nominalValue.child.label,
    dynamic = child:get("label"),
    dynamicList = (dynamicValue:get("children")[1] as nupp.data.serde.DynamicValue):get("label"),
    second = dynamicValue:get("values")[2],
}
]=])
   assert(result.nominal == "nominal" and result.dynamic == "dynamic"
      and result.dynamicList == "dynamic-list" and result.second == 4,
      "one logical schema did not preserve its separate physical bindings")
end

function M.typedExtensionsComputeOnce()
   local result = run([=[
local calls = 0
local key = nupp.extensions.key(function(schema: any): string
    calls = calls + 1
    return schema.name
end)
const serde = nupp.data.serde
local builder = new serde.SchemaBuilder()
builder:structure("example.Extension")
local schema = builder:freeze()
return {first = schema:extension(key), second = schema:extension(key), calls = calls}
]=])
   assert(result.first == "example.Extension" and result.second == result.first,
      "typed extension returned the wrong value")
   assert(result.calls == 1, "typed extension was recomputed")
end

function M.typedExtensionSlotsSeparateKeysAndHosts()
   local result = run([=[
local leftCalls = 0
local rightCalls = 0
local left = nupp.extensions.key(function(schema: any): string
    leftCalls = leftCalls + 1
    return "left:" .. schema.name
end)
local right = nupp.extensions.key(function(schema: any): string
    rightCalls = rightCalls + 1
    return "right:" .. schema.name
end)
const serde = nupp.data.serde
local firstBuilder = new serde.SchemaBuilder()
firstBuilder:structure("First")
local first = firstBuilder:freeze()
local secondBuilder = new serde.SchemaBuilder()
secondBuilder:structure("Second")
local second = secondBuilder:freeze()
return {
    left = first:extension(left),
    leftAgain = first:extension(left),
    right = first:extension(right),
    otherHost = second:extension(left),
    leftCalls = leftCalls,
    rightCalls = rightCalls,
}
]=])
   assert(result.left == "left:First" and result.leftAgain == result.left,
      "one extension slot did not retain its value")
   assert(result.right == "right:First", "extension slots collided on one host")
   assert(result.otherHost == "left:Second", "extension slots leaked between hosts")
   assert(result.leftCalls == 2 and result.rightCalls == 1,
      "extension providers did not run once per host and slot")
end

function M.recordOnlyDerivesStayRecordOnly()
   local problems = diagnostics([=[
@derive(nupp.derive.JSON)
local struct NotJson
    value: int32
end
]=])
   assert(problems[1] and problems[1].code == "NUPP2806"
      and problems[1].msg:find("only for records", 1, true),
      "general struct derive attachment broadened JSON")
end

function M.structPointersRequireAnExplicitAdapter()
   local problems = diagnostics([=[
@derive(nupp.derive.Serde)
local struct Borrowed
    value: int32*
end
]=])
   assert(problems[1] and problems[1].code == "NUPP2803"
      and problems[1].msg:find("not supported by Serde", 1, true),
      "Serde guessed pointer ownership")
end

return M
