-- Compiler-owned declaration derives: semantic members, factory projection, and
-- the closed runtime recipes for Debug, Default, From, and JSON.
local parser = require("nupp.compiler.parser")
local gen = require("nupp.compiler.gen")
local check = require("fragment")
local envMod = require("nupp.compiler.env")
local derive = require("nupp.compiler.check.derive")
local recipeCodec = require("nupp.compiler.materialize.codec")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local env = envMod.new(HERE .. "/..")

local function assertEq(got, want, label)
   if got ~= want then
      error(("%s:\n  want: %s\n  got:  %s"):format(label or "mismatch",
         tostring(want), tostring(got)), 2)
   end
end

local function compileAt(source, filename, opts)
   filename = filename or "derive_test.g.nupp"
   local parsed = parser.parse(source, filename)
   assertEq(#parsed.errors, 0, "syntax errors")
   local diagnostics = check.check(parsed, filename, env, opts)
   local code, generated = gen.generate(parsed, "derive_test")
   for _, diagnostic in ipairs(generated) do diagnostics[#diagnostics + 1] = diagnostic end
   return code, diagnostics, parsed
end

local function compile(source)
   return compileAt(source, "derive_test.g.nupp")
end

local function firstDeclaration(parsed)
   local stat = parsed.root.blocks[1].stats[1]
   while stat and stat.kind == "pragmaStmt" do stat = stat.stat end
   return assert(stat, "fixture has no declaration")
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
   local _, sourceLines = source:gsub("\n", "\n")
   local _, outputLines = code:gsub("\n", "\n")
   assertEq(outputLines, sourceLines,
      "derive lowering changed the source/output line count")
   return chunk(), code
end

local M = {}

function M.derivesTheFourBuiltinsAndInfersFactoryResults()
   local result, code = run([[
@derive(nupp.derive.Debug, nupp.derive.Default, nupp.derive.JSON)
local record User
    @json(name = "user_name")
    @default("anonymous")
    name: string
    scores: {integer}
    active: boolean
end

@derive(nupp.derive.Debug, nupp.derive.From)
local record UserId
    value: integer
end

local user: User = nupp.default(User)
local id: UserId = nupp.into(42, UserId)
local printable: nupp.Debug = user
local encodable: nupp.data.JSONEncodable = user
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
@derive(nupp.derive.Default)
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
@derive(nupp.derive.JSON)
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
local payload = new Payload(name = "x", secret = "hidden", labels = {})
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
@derive(nupp.derive.Debug, nupp.derive.JSON)
local record Node
    value: integer
    next: Node?
end
local root = new Node(value = 1, next = nil)
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
@derive(nupp.derive.Debug)
local record Item
    label: string
end

@derive(nupp.derive.Debug)
local record Box<T is nupp.Debug>
    value: T
end

local record Namespace
    @derive(nupp.derive.Debug, nupp.derive.Default)
    record Inner
        count: integer
    end
end

local boxed: Box<Item> = new Box(value = new Item(label = "ok"))
local inner: Namespace.Inner = Namespace.Inner.default()
return {box = boxed:debug(), inner = inner:debug()}
]])
   assertEq(result.box, 'Box { value = Item { label = "ok" } }')
   assertEq(result.inner, "Inner { count = 0 }")
end

function M.roundTripsDiscriminatedJSONRecordUnions()
   local result = run([[
@derive(nupp.derive.JSON)
local record Cat
    kind: "cat"
    lives: integer
end
@derive(nupp.derive.JSON)
local record Dog
    kind: "dog"
    barks: boolean
end
@derive(nupp.derive.JSON)
local record Envelope
    pet: Cat | Dog
end

local envelope = new Envelope(pet = new Cat(kind = "cat", lives = 9))
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
@derive(nupp.derive.Debug, nupp.derive.Debug)
local record Bad value: integer end
]]},
      {"NUPP2802", [[
@derive(nupp.derive.Debug)
local record Bad
    debug: function(self): string
end
]]},
      {"NUPP2804", [[
local fallback = "runtime"
@derive(nupp.derive.Default)
local record Bad
    @default(fallback)
    value: string
end
]]},
      {"NUPP2805", [[
@derive(nupp.derive.From)
local record Bad
    left: integer
    right: integer
end
]]},
      {"NUPP2806", [[
@derive(nupp.derive.JSON)
local record Bad
    value: uint64
end
]]},
      {"NUPP2807", [[
@derive(nupp.derive.Default)
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

function M.requiresResolvedProviderSymbols()
   local codes = errorsOf([[
@derive(Debug)
local record Legacy
    value: integer
end
]])
   assertEq(codes[1], "NUPP2809", "bare built-in derive names are removed")
end

function M.offersWholeFixesForDuplicateAndConflictingProviders()
   local _, duplicateDiagnostics = compile([[
@derive(nupp.derive.Debug, nupp.derive.Debug)
local record Duplicate value: integer end
]])
   local _, conflictDiagnostics = compile([[
@derive(nupp.derive.Debug)
local record Conflict
    debug: function(self): string
end
]])
   local function hasFix(diagnostics, title)
      for _, diagnostic in ipairs(diagnostics) do
         for _, fix in ipairs(diagnostic.fixes or {}) do
            if fix.title == title and #fix.edits == 1 then return true end
         end
      end
      return false
   end
   assert(hasFix(duplicateDiagnostics, "remove duplicate @derive(nupp.derive.Debug)"),
      "duplicate provider has no whole removal fix")
   assert(hasFix(conflictDiagnostics, "remove @derive(nupp.derive.Debug)"),
      "generated-member collision has no whole derive removal fix")
end

function M.recheckingADerivedDeclarationIsIdempotent()
   local source = [[
@derive(nupp.derive.Debug, nupp.derive.Default, nupp.derive.JSON)
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
@derive(nupp.derive.JSON)
local record Fingerprinted
    @json(name = "first")
    value: integer
end
return Fingerprinted.fieldCodec().fingerprint
]])
   local second = run([[
@derive(nupp.derive.JSON)
local record Fingerprinted
    @json(name = "second")
    value: integer
end
return Fingerprinted.fieldCodec().fingerprint
]])
   assert(first ~= second, "a JSON annotation edit kept the codec fingerprint")
end

function M.givesEveryGeneratedMemberADistinctSemanticIdentity()
   local _, diagnostics, parsed = compile([[
@derive(nupp.derive.Debug, nupp.derive.Default, nupp.derive.JSON)
local record Identified
    value: integer
end
]])
   assertEq(#diagnostics, 0, "derive identity diagnostics")
   local nominal = assert(firstDeclaration(parsed).hoistedType)
   local defs = {
      nominal.derivedDefinitions.debug,
      nominal.derivedStaticDefinitions.default,
      nominal.derivedDefinitions.toJSON,
      nominal.derivedStaticDefinitions.fromJSON,
      nominal.derivedStaticDefinitions.fieldCodec,
   }
   local identities = {}
   for _, definition in ipairs(defs) do
      assert(definition, "missing generated definition")
      assert(definition.generatedRecipeFingerprint, "definition has no recipe provenance")
      assert(not identities[definition.generatedIdentity],
         "generated members share a semantic identity")
      identities[definition.generatedIdentity] = true
   end
   assert(defs[3].token == defs[4].token and defs[4].token == defs[5].token,
      "the three JSON members keep one written navigation origin")
end

function M.fingerprintsNestedDebugMapKeysAndIgnoresPathSpelling()
   local stringCode, stringDiagnostics, stringParsed = compileAt([[
@derive(nupp.derive.Debug)
local record Mapped entries: {[string]: string} end
]], "spelling/../mapped.g.nupp")
   local integerCode, integerDiagnostics, integerParsed = compileAt([[
@derive(nupp.derive.Debug)
local record Mapped entries: {[integer]: string} end
]], "mapped.g.nupp")
   assertEq(#stringDiagnostics, 0, "string map diagnostics")
   assertEq(#integerDiagnostics, 0, "integer map diagnostics")
   local stringRecipe = assert(firstDeclaration(stringParsed).deriveRecipe)
   local integerRecipe = assert(firstDeclaration(integerParsed).deriveRecipe)
   assert(stringRecipe.fingerprint ~= integerRecipe.fingerprint,
      "a Debug map key edit kept the recipe fingerprint")

   local alternateCode, alternateDiagnostics = compileAt([[
@derive(nupp.derive.Debug)
local record Mapped entries: {[string]: string} end
]], "/tmp/another-spelling/mapped.g.nupp")
   assertEq(#alternateDiagnostics, 0, "alternate path diagnostics")
   assertEq(alternateCode, stringCode,
      "generated bytes depend on the invocation path spelling")
end

function M.boundsFieldsAndSemanticRecipeNodesAtTheirExactLimits()
   assertEq(derive.MAX_FIELDS, 2048, "production field limit")
   assertEq(derive.MAX_RECIPE_NODES, 16384, "production semantic-node limit")
   assertEq(derive.MAX_GENERATED_MEMBERS, 6, "production generated-member limit")
   assertEq(recipeCodec.MAX_CANONICAL_BYTES, 1048576,
      "production canonical-byte limit")
   assertEq(recipeCodec.MAX_OUTPUT_BYTES, 2097152,
      "production rendered-byte limit")

   local limits = {fields = 8, nodes = 64}
   local function fixture(fields, deepLast)
      local lines = {"@derive(nupp.derive.Debug)", "local record Bounded"}
      for index = 1, fields do
         local depth = index == fields and deepLast or 7
         lines[#lines + 1] = ("    f%d: %sstring%s"):format(
            index,
            string.rep("{", depth),
            string.rep("}", depth)
         )
      end
      lines[#lines + 1] = "end"
      return table.concat(lines, "\n")
   end
   local _, atDiagnostics = compileAt(fixture(8, 7), "bounded.g.nupp",
      {deriveLimits = limits})
   for _, diagnostic in ipairs(atDiagnostics) do
      assert(diagnostic.code ~= "NUPP2808",
         "the exact field/node boundary was rejected: " .. diagnostic.msg)
   end
   local _, beyondNode = compileAt(fixture(8, 8), "bounded.g.nupp",
      {deriveLimits = limits})
   local nodeLimited = false
   for _, diagnostic in ipairs(beyondNode) do
      nodeLimited = nodeLimited or diagnostic.code == "NUPP2808"
         and diagnostic.msg:find("semantic nodes", 1, true)
   end
   assert(nodeLimited, "the semantic-node boundary has no direct NUPP2808 fixture")

   local fields = {"@derive(nupp.derive.From)", "local record TooMany"}
   for index = 1, 9 do fields[#fields + 1] = "    f" .. index .. ": integer" end
   fields[#fields + 1] = "end"
   local _, beyondFields = compileAt(table.concat(fields, "\n"),
      "bounded.g.nupp", {deriveLimits = limits})
   local fieldLimited = false
   for _, diagnostic in ipairs(beyondFields) do
      fieldLimited = fieldLimited or diagnostic.code == "NUPP2808"
         and diagnostic.msg:find("fields", 1, true)
   end
   assert(fieldLimited, "the field boundary has no direct NUPP2808 fixture")
end

function M.cancelsWithoutPublishingAPartialRecipeAndRecovers()
   local source = [[
@derive(nupp.derive.Debug, nupp.derive.Default, nupp.derive.JSON)
local record Recoverable
    names: {{{string}}}
    values: {[string]: {integer}}
end
]]
   local probes = 0
   local _, cancelledDiagnostics, parsed = compileAt(source, "cancelled.g.nupp", {
      cancelled = function()
         probes = probes + 1
         return probes > 10
      end,
   })
   assertEq(#cancelledDiagnostics, 0, "cancellation is not a diagnostic")
   assert(parsed.cancelled and parsed.deriveAborted == "cancelled",
      "the check does not expose its ordinary cancelled result")
   local declaration = firstDeclaration(parsed)
   assert(not declaration.deriveRecipe and not declaration.hoistedType.deriveRecipe,
      "a cancelled check published a partial recipe")
   assert(not declaration.hoistedType.derivedDefinitions.debug,
      "a cancelled check left a generated member behind")

   local recovered = check.check(parsed, "cancelled.g.nupp", env)
   assertEq(#recovered, 0, "the request after cancellation recovers")
   assert(not parsed.cancelled and firstDeclaration(parsed).deriveRecipe,
      "cancellation poisoned the next check")

   local budgetParsed = parser.parse(source, "budget.g.nupp")
   local budgetDiagnostics = check.check(budgetParsed, "budget.g.nupp", env,
      {deriveBudget = 10})
   local exhausted = false
   for _, diagnostic in ipairs(budgetDiagnostics) do
      exhausted = exhausted or diagnostic.code == "NUPP2808"
         and diagnostic.msg:find("work budget", 1, true)
   end
   assert(exhausted and not firstDeclaration(budgetParsed).deriveRecipe,
      "budget exhaustion did not abort the partial recipe")
   assertEq(#check.check(budgetParsed, "budget.g.nupp", env), 0,
      "budget exhaustion poisoned the retry")
end

function M.boundsRenderedRecipesAndReportsColdAndWarmObservations()
   local source = [[
@derive(nupp.derive.Debug, nupp.derive.Default, nupp.derive.From, nupp.derive.JSON)
local record ObservedClosure
    value: integer
end
]]
   local _, coldDiagnostics, cold = compileAt(source, "observed.g.nupp")
   assertEq(#coldDiagnostics, 0, "cold observation diagnostics")
   local _, warmDiagnostics, warm = compileAt(source, "observed.g.nupp")
   assertEq(#warmDiagnostics, 0, "warm observation diagnostics")
   assertEq(#cold.deriveObservations, 4, "one observation per provider")
   assertEq(#warm.deriveObservations, 4, "warm observation count")
   local expected = {
      ["nupp.derive.Debug"] = 1,
      ["nupp.derive.Default"] = 1,
      ["nupp.derive.From"] = 1,
      ["nupp.derive.JSON"] = 3,
   }
   for index, observation in ipairs(cold.deriveObservations) do
      local warmed = warm.deriveObservations[index]
      assertEq(observation.generatedMembers, expected[observation.provider],
         observation.provider .. " generated-member bound")
      assert(observation.canonicalBytes > 0 and observation.renderedBytes > 0,
         "observation omits bounded sizes")
      assertEq(observation.generatedLocals, 2, "closed recipe local bound")
      assertEq(observation.maxGeneratedUpvalues, 1, "closed recipe upvalue bound")
      assertEq(warmed.semanticFingerprint, observation.semanticFingerprint,
         "cold/warm semantic product")
      assertEq(warmed.canonicalBytes, observation.canonicalBytes,
         "cold/warm canonical size")
      assert(warmed.cached, "the warm observation is not marked cached")
   end

   local hugeName = string.rep("x", 300)
   local hugeSource = "@derive(nupp.derive.JSON)\nlocal record Huge\n"
      .. "    @json(name = \"" .. hugeName .. "\")\n"
      .. "    value: string\nend\n"
   local code, diagnostics, parsed = compileAt(hugeSource, "huge.g.nupp", {
      deriveLimits = {canonicalBytes = 256},
   })
   local limited = false
   for _, diagnostic in ipairs(diagnostics) do
      limited = limited or diagnostic.code == "NUPP2808"
         and diagnostic.msg:find("canonical bytes", 1, true)
   end
   assert(limited, "an over-limit canonical plan did not report NUPP2808")
   assert(not firstDeclaration(parsed).deriveRecipe,
      "an over-limit plan reached lowering")
   assert(not code:find("__derive.register", 1, true),
      "over-limit derive Lua was emitted")
end

function M.excludesTheRuntimeFromProgramsWithoutDerives()
   local code = compile("return 42")
   assertEq(code:find("__nuppDerive", 1, true), nil, "unused derive runtime")
end

function M.recordsTheExactRuntimeFeatureManifest()
   local _, debugDiagnostics, debug = compile([[
@derive(nupp.derive.Debug, nupp.derive.Default, nupp.derive.From)
local record Pure value: integer end
]])
   assertEq(#debugDiagnostics, 0, "pure derive feature diagnostics")
   local pureEffects = firstDeclaration(debug).compilerFeatureEffects
   assertEq(table.concat(pureEffects, ","), "stdlib.derives",
      "pure derive feature manifest")

   local _, jsonDiagnostics, json = compile([[
@derive(nupp.derive.JSON)
local record Encoded value: integer end
]])
   assertEq(#jsonDiagnostics, 0, "JSON derive feature diagnostics")
   local jsonEffects = firstDeclaration(json).compilerFeatureEffects
   assertEq(table.concat(jsonEffects, ","), "stdlib.derives,native.cjson",
      "JSON derive feature manifest")
end

function M.delimitsTheRuntimeFromAnEmittedFirstLine()
   local result = run([[local marker = "first"
@derive(nupp.derive.Debug)
local record First value: integer end
return marker .. ":" .. (new First(value = 1)):debug()
]])
   assertEq(result, "first:First { value = 1 }")
end

return M
