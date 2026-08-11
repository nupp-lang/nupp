-- Compiler-owned declaration derives: semantic members, factory projection, and
-- the closed runtime recipes for Debug, Default, From, and JSON.
local parser = require("nupp.compiler.parser")
local gen = require("nupp.compiler.gen")
local check = require("fragment")
local envMod = require("nupp.compiler.env")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local env = envMod.new(HERE .. "/..")

local function assertEq(got, want, label)
   if got ~= want then
      error(("%s:\n  want: %s\n  got:  %s"):format(label or "mismatch",
         tostring(want), tostring(got)), 2)
   end
end

local function compile(source)
   local parsed = parser.parse(source, "derive_test.g.nupp")
   assertEq(#parsed.errors, 0, "syntax errors")
   local diagnostics = check.check(parsed, "derive_test.g.nupp", env)
   local code, generated = gen.generate(parsed, "derive_test")
   for _, diagnostic in ipairs(generated) do diagnostics[#diagnostics + 1] = diagnostic end
   return code, diagnostics, parsed
end

local function errorsOf(source)
   local _, diagnostics = compile(source)
   local out = {}
   for _, diagnostic in ipairs(diagnostics) do
      if diagnostic.severity ~= "warning" and diagnostic.severity ~= "note" then
         out[#out + 1] = diagnostic.code
      end
   end
   return out, diagnostics
end

local function run(source)
   local code, diagnostics = compile(source)
   for _, diagnostic in ipairs(diagnostics) do
      if diagnostic.severity ~= "warning" and diagnostic.severity ~= "note" then
         error(("unexpected %s: %s\n---\n%s"):format(diagnostic.code, diagnostic.msg, code), 2)
      end
   end
   local chunk, why = loadstring(code, "@derive_test")
   assert(chunk, why and (why .. "\n---\n" .. code))
   return chunk(), code
end

local M = {}

function M.derivesTheFourBuiltinsAndInfersFactoryResults()
   local result, code = run([[
@derive(Debug, Default, JSON)
local record User
    @json(name = "user_name")
    @default("anonymous")
    name: string
    scores: {integer}
    active: boolean
end

@derive(Debug, From)
local record UserId
    value: integer
end

local user: User = nupp.default(User)
local id: UserId = nupp.into(42, UserId)
local printable: nupp.Debug = user
local encodable: nupp.JSONEncodable = user
local text = encodable:toJSON()
local decoded, err = User.fromJSON(text)
assert(decoded and not err)
local restored = decoded as User
return {
    debug = printable:debug(),
    id = id:debug(),
    text = text,
    name = restored.name,
    scores = #restored.scores,
    active = restored.active,
}
]])
   assertEq(result.debug, 'User { name = "anonymous", scores = {}, active = false }')
   assertEq(result.id, "UserId { value = 42 }")
   assertEq(result.text, '{"user_name":"anonymous","scores":[],"active":false}')
   assertEq(result.name, "anonymous")
   assertEq(result.scores, 0)
   assertEq(result.active, false)
   assert(code:find("__derive.register", 1, true), code)
end

function M.constructsFreshMutableDefaults()
   local result = run([[
@derive(Default)
local record Options
    tags: {string}
    values: {[string]: integer}
    point: {x: integer, label: string}
end
local left = Options.default()
local right = Options.default()
left.tags[1] = "changed"
left.values.changed = 1
left.point.x = 9
return {
    tags = #right.tags,
    changed = right.values.changed,
    x = right.point.x,
    distinct = left.tags ~= right.tags and left.values ~= right.values
        and left.point ~= right.point,
}
]])
   assertEq(result.tags, 0)
   assertEq(result.changed, nil)
   assertEq(result.x, 0)
   assertEq(result.distinct, true)
end

function M.appliesJSONPoliciesAndKeepsDecoderConfigurationPrivate()
   local result = run([[
@derive(JSON)
@json(unknown = "ignore")
local record Payload
    @default("missing")
    name: string
    @json(omit = true)
    secret: string
    @json(omitEmpty = true)
    labels: {string}
end

-- A process-visible setting must not alter the private derived decoder.
local previousDepth = nupp.data.decodeMaxDepth()
nupp.data.decodeMaxDepth(1)
local decoded, err = Payload.fromJSON('{"labels":[],"extra":{"nested":true}}')
nupp.data.decodeMaxDepth(previousDepth)
local codec = Payload.fieldCodec()
local checked, checkedErr = codec:decode({name = "ok", labels = {"a"}})
local payload = new Payload {name = "x", secret = "hidden", labels = {}}
local keyed = codec:encode(payload)
return {
    name = decoded and decoded.name,
    secret = decoded and decoded.secret,
    labels = decoded and #decoded.labels,
    arrayMt = decoded and getmetatable(decoded.labels),
    error = err,
    checked = checked and checked.name,
    checkedError = checkedErr,
    fingerprint = codec.fingerprint,
    keyedName = keyed.name,
    keyedSecret = keyed.secret,
    keyedLabels = keyed.labels,
    text = payload:toJSON(),
}
]])
   assertEq(result.name, "missing")
   assertEq(result.secret, "")
   assertEq(result.labels, 0)
   assertEq(result.arrayMt, nil)
   assertEq(result.error, nil)
   assertEq(result.checked, "ok")
   assertEq(result.checkedError, nil)
   assert(result.fingerprint:find("maxdepth=128", 1, true), result.fingerprint)
   assertEq(result.keyedName, "x")
   assertEq(result.keyedSecret, nil)
   assertEq(result.keyedLabels, nil)
   assertEq(result.text, '{"name":"x"}')
end

function M.handlesRecursiveDebugAndJSONGraphs()
   local result = run([[
@derive(Debug, JSON)
local record Node
    value: integer
    next: Node?
end
local root = new Node {value = 1, next = nil}
root.next = root
local debugged = root:debug()
local encoded, cycle = pcall(function(): string return root:toJSON() end)
local decoded, err = Node.fromJSON('{"value":1,"next":{"value":2,"next":null}}')
return {
    debugged = debugged,
    encoded = encoded,
    cycle = tostring(cycle),
    nested = decoded and decoded.next and decoded.next.value,
    error = err,
}
]])
   assert(result.debugged:find("<cycle>", 1, true), result.debugged)
   assertEq(result.encoded, false)
   assert(result.cycle:find("cyclic JSON value", 1, true), result.cycle)
   assertEq(result.nested, 2)
   assertEq(result.error, nil)
end

function M.supportsNestedAndBoundedGenericDebugRecords()
   local result = run([[
@derive(Debug)
local record Item
    label: string
end

@derive(Debug)
local record Box<T is nupp.Debug>
    value: T
end

local record Namespace
    @derive(Debug, Default)
    record Inner
        count: integer
    end
end

local boxed: Box<Item> = new Box {value = new Item {label = "ok"}}
local inner: Namespace.Inner = Namespace.Inner.default()
return {box = boxed:debug(), inner = inner:debug()}
]])
   assertEq(result.box, 'Box { value = Item { label = "ok" } }')
   assertEq(result.inner, "Inner { count = 0 }")
end

function M.roundTripsDiscriminatedJSONRecordUnions()
   local result = run([[
@derive(JSON)
local record Cat
    kind: "cat"
    lives: integer
end
@derive(JSON)
local record Dog
    kind: "dog"
    barks: boolean
end
@derive(JSON)
local record Envelope
    pet: Cat | Dog
end

local envelope = new Envelope {pet = new Cat {kind = "cat", lives = 9}}
local text = envelope:toJSON()
local decoded, err = Envelope.fromJSON('{"pet":{"kind":"dog","barks":true}}')
assert(decoded and not err)
local pet = (decoded as Envelope).pet
local bark = false
if pet.kind == "dog" then bark = pet.barks end
return {text = text, bark = bark, dog = getmetatable(pet) == Dog}
]])
   assertEq(result.text, '{"pet":{"kind":"cat","lives":9}}')
   assertEq(result.bark, true)
   assertEq(result.dog, true)
end

function M.reportsProviderAndSchemaFailuresAtTheDeclaration()
   local cases = {
      {"NUPP2801", [[
@derive(Debug, Debug)
local record Bad value: integer end
]]},
      {"NUPP2802", [[
@derive(Debug)
local record Bad
    debug: function(self): string
end
]]},
      {"NUPP2804", [[
local fallback = "runtime"
@derive(Default)
local record Bad
    @default(fallback)
    value: string
end
]]},
      {"NUPP2805", [[
@derive(From)
local record Bad
    left: integer
    right: integer
end
]]},
      {"NUPP2806", [[
@derive(JSON)
local record Bad
    value: uint64
end
]]},
      {"NUPP2807", [[
@derive(Default)
local record Bad
    next: Bad
end
]]},
   }
   for _, fixture in ipairs(cases) do
      local codes, diagnostics = errorsOf(fixture[2])
      local found = false
      for _, code in ipairs(codes) do found = found or code == fixture[1] end
      if not found then
         local shown = {}
         for _, diagnostic in ipairs(diagnostics) do
            shown[#shown + 1] = diagnostic.code .. ": " .. diagnostic.msg
         end
         error(("missing %s:\n%s"):format(fixture[1], table.concat(shown, "\n")))
      end
   end
end

function M.recheckingADerivedDeclarationIsIdempotent()
   local source = [[
@derive(Debug, Default, JSON)
local record Stable
    value: integer
end
return Stable.default()
]]
   local parsed = parser.parse(source, "derive_recheck.g.nupp")
   assertEq(#parsed.errors, 0, "syntax errors")
   for pass = 1, 2 do
      local diagnostics = check.check(parsed, "derive_recheck.g.nupp", env)
      for _, diagnostic in ipairs(diagnostics) do
         if diagnostic.severity ~= "warning" and diagnostic.severity ~= "note" then
            error(("pass %d unexpectedly reported %s: %s")
               :format(pass, diagnostic.code, diagnostic.msg))
         end
      end
   end
end

function M.fingerprintsJSONSchemaAndAnnotationChanges()
   local first = run([[
@derive(JSON)
local record Fingerprinted
    @json(name = "first")
    value: integer
end
return Fingerprinted.fieldCodec().fingerprint
]])
   local second = run([[
@derive(JSON)
local record Fingerprinted
    @json(name = "second")
    value: integer
end
return Fingerprinted.fieldCodec().fingerprint
]])
   assert(first ~= second, "a JSON annotation edit kept the codec fingerprint")
end

function M.excludesTheRuntimeFromProgramsWithoutDerives()
   local code = compile("return 42")
   assertEq(code:find("__nuppDerive", 1, true), nil, "unused derive runtime")
end

function M.delimitsTheRuntimeFromAnEmittedFirstLine()
   local result = run([[local marker = "first"
@derive(Debug)
local record First value: integer end
return marker .. ":" .. (new First {value = 1}):debug()
]])
   assertEq(result, "first:First { value = 1 }")
end

return M
