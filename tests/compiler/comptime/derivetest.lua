local testAssert = require("assert")
-- Compiler-owned declaration derives: semantic members, factory projection, and
-- closed runtime recipes independently of serialization bindings.
local parser = require("nupp.compiler.syntax.parser")
local program = require("program")
local check = require("helpers.fragment")
local envMod = require("nupp.compiler.project.env")
local derive = require("nupp.compiler.check.derive")
local recipeCodec = require("nupp.compiler.comptime.materialize.codec")

local HERE = require("helpers.paths").tests
local env = envMod.new(HERE .. "/..")

local function compileAt(source, filename, opts)
    filename = filename or "derive_test.nupp"
    local parsed = parser.parse(source, filename)
    testAssert.eq(#parsed.errors, 0, "syntax errors")
    local checking = {}
    for key, value in pairs(opts or {}) do
        checking[key] = value
    end
    checking.moduleName = checking.moduleName or "derive_test"
    local diagnostics = check.check(parsed, filename, env, checking)

    return parsed, diagnostics, parsed
end

local function compile(source)
    return compileAt(source, "derive_test.nupp")
end

local function firstDeclaration(parsed)
    for _, stat in ipairs(parsed.root.blocks[1].stats) do
        while stat and stat.kind == "pragmaStmt" do
            stat = stat.stat
        end
        if stat and stat.kind == "recordDecl" then
            return stat
        end
    end
    error("fixture has no declaration")
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

local function run(moduleName, source)
    local parsed, diagnostics = compileAt(source, moduleName .. ".nupp", {moduleName = moduleName})
    for _, diagnostic in ipairs(diagnostics) do
        if diagnostic.severity ~= "warning" and diagnostic.severity ~= "note" then
            error(("unexpected %s: %s\n---\n%s"):format(diagnostic.code, diagnostic.msg, source), 2)
        end
    end

    return program.run(parsed, moduleName)
end

local M = {}

function M.constructsFreshMutableDefaults()
    local result = run(
        "derivetest.constructsFreshMutableDefaults",
        [[
local record Options
    tags: {string} = {}
    values: {[string]: integer} = {}
    point: {x: integer, label: string} = {x = 0, label = ""}
end
local left = Options()
local right = Options()
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
]]
    )
    testAssert.eq(result.tags, 0)
    testAssert.eq(result.changed, nil)
    testAssert.eq(result.x, 0)
    testAssert.eq(result.distinct, true)
end

function M.supportsNestedAndBoundedGenericDebugRecords()
    local result = run(
        "derivetest.supportsNestedAndBoundedGenericDebugRecords",
        [[
@derive(types.debug)
local record Item
    label: string
end

@derive(types.debug)
local record Box<T is types.Debug>
    value: T
end

local record Namespace
    @derive(types.debug)
    record Inner
        count: integer = 0
    end
end

local boxed: Box<Item> = Box(value = Item(label = "ok"))
local inner: Namespace.Inner = Namespace.Inner()
return {box = boxed:debug(), inner = inner:debug()}
]]
    )
    testAssert.eq(result.box, 'Box { value = Item { label = "ok" } }')
    testAssert.eq(result.inner, "Inner { count = 0LL }")
end

function M.debugsDerivedStructsAndRecordsHoldingThem()
    -- A struct's derived debug is the renderer itself; reading it as a custom
    -- method made the renderer call itself until the stack ran out.
    local result = run(
        "derivetest.debugsDerivedStructsAndRecordsHoldingThem",
        [[
@derive(types.debug)
local struct Point
    x: float64
    y: float32
end

@derive(types.debug)
local record Shape
    origin: Point
end

local point = Point(1, 2)
local shape = Shape(origin = point)
return {point = point:debug(), shape = shape:debug()}
]]
    )
    testAssert.eq(result.point, "Point { x = 1.0, y = 2.0 }")
    testAssert.eq(result.shape, "Shape { origin = Point { x = 1.0, y = 2.0 } }")
end

function M.reportsProviderAndSchemaFailuresAtTheDeclaration()
    local cases = {
        {"NUPP2801", [[
@derive(types.debug, types.debug)
local record Bad value: integer end
]]},
        {"NUPP2802", [[
@derive(types.debug)
local record Bad
    debug: function(self): string
end
]]},
        {"NUPP2803", [[
@derive(types.debug)
local record Bad
    value: function(): nil
end
]]},
    }
    for _, fixture in ipairs(cases) do
        local codes, diagnostics = errorsOf(fixture[2])
        local found = false
        for _, code in ipairs(codes) do
            found = found or code == fixture[1]
        end
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
    testAssert.eq(codes[1], "NUPP2809", "bare built-in derive names are removed")
end

function M.offersWholeFixesForDuplicateAndConflictingProviders()
    local _, duplicateDiagnostics = compile(
        [[
@derive(types.debug, types.debug)
local record Duplicate value: integer end
]]
    )
    local _, conflictDiagnostics = compile(
        [[
@derive(types.debug)
local record Conflict
    debug: function(self): string
end
]]
    )

    local function hasFix(diagnostics, title)
        for _, diagnostic in ipairs(diagnostics) do
            for _, fix in ipairs(diagnostic.fixes or {}) do
                if fix.title == title and #fix.edits == 1 then
                    return true
                end
            end
        end

        return false
    end

    assert(
        hasFix(duplicateDiagnostics, "remove duplicate @derive(types.debug)"),
        "duplicate provider has no whole removal fix"
    )
    assert(
        hasFix(conflictDiagnostics, "remove @derive(types.debug)"),
        "generated-member collision has no whole derive removal fix"
    )
end

function M.recheckingADerivedDeclarationIsIdempotent()
    local source = [[
local editor = require("tests.fixtures.deriveeditor")
@derive(types.debug, editor.derive)
local record Stable
    value: integer = 0
end
return Stable()
]]
    local parsed = parser.parse(source, "derive_recheck.nupp")
    testAssert.eq(#parsed.errors, 0, "syntax errors")
    for pass = 1, 2 do
        local diagnostics = check.check(parsed, "derive_recheck.nupp", env)
        for _, diagnostic in ipairs(diagnostics) do
            if diagnostic.severity ~= "warning" and diagnostic.severity ~= "note" then
                error(("pass %d unexpectedly reported %s: %s"):format(pass, diagnostic.code, diagnostic.msg))
            end
        end
    end
end

function M.fingerprintsDebugAnnotationChanges()
    local function fingerprint(redacted)
        local source = "@derive(types.debug)\nlocal record Fingerprinted\n" .. (
            redacted and "@debug(redact = true)\n" or ""
        ) .. "value: string\nend"
        local _, diagnostics, parsed = compile(source)
        testAssert.eq(#diagnostics, 0)

        return firstDeclaration(parsed).deriveRecipe.fingerprint
    end

    assert(fingerprint(false) ~= fingerprint(true), "a rendering policy edit kept its recipe fingerprint")
end

function M.givesEveryGeneratedMemberADistinctSemanticIdentity()
    local _, diagnostics, parsed = compile(
        [[
local editor = require("tests.fixtures.deriveeditor")
@derive(editor.derive)
local record Identified value: integer end
]]
    )
    testAssert.eq(#diagnostics, 0, "derive identity diagnostics")
    local nominal = assert(firstDeclaration(parsed).hoistedType)
    local defs = {
        nominal.derivedDefinitions.inspect,
        nominal.derivedStaticDefinitions.kind,
        nominal.derivedStaticDefinitions.fields
    }
    local identities = {}
    for _, definition in ipairs(defs) do
        assert(definition and definition.generatedRecipeFingerprint, "missing generated provenance")
        assert(not identities[definition.generatedIdentity], "generated members share an identity")
        identities[definition.generatedIdentity] = true
    end
    assert(
        defs[1].token == defs[2].token and defs[2].token == defs[3].token,
        "one provider's members share a written navigation origin"
    )
end

function M.fingerprintsNestedDebugMapKeysAndIgnoresPathSpelling()
    local _, stringDiagnostics, stringParsed = compileAt(
        [[
@derive(types.debug)
local record Mapped entries: {[string]: string} end
]],
        "spelling/../mapped.nupp"
    )
    local _, integerDiagnostics, integerParsed = compileAt(
        [[
@derive(types.debug)
local record Mapped entries: {[integer]: string} end
]],
        "mapped.nupp"
    )
    testAssert.eq(#stringDiagnostics, 0, "string map diagnostics")
    testAssert.eq(#integerDiagnostics, 0, "integer map diagnostics")
    local stringRecipe = assert(firstDeclaration(stringParsed).deriveRecipe)
    local integerRecipe = assert(firstDeclaration(integerParsed).deriveRecipe)
    assert(stringRecipe.fingerprint ~= integerRecipe.fingerprint, "a Debug map key edit kept the recipe fingerprint")

    local _, alternateDiagnostics, alternateParsed = compileAt(
        [[
@derive(types.debug)
local record Mapped entries: {[string]: string} end
]],
        -- The same file spelled from the suite's own directory: a file outside
        -- the project is another module, and an image names its module.
        HERE .. "/../mapped.nupp"
    )
    testAssert.eq(#alternateDiagnostics, 0, "alternate path diagnostics")
    testAssert.eq(
        program.image(alternateParsed, "derive_test"),
        program.image(stringParsed, "derive_test"),
        "the image depends on the invocation path spelling"
    )
end

function M.boundsFieldsAndSemanticRecipeNodesAtTheirExactLimits()
    testAssert.eq(derive.MAX_FIELDS, 2048, "production field limit")
    testAssert.eq(derive.MAX_RECIPE_NODES, 16384, "production semantic-node limit")
    testAssert.eq(derive.MAX_GENERATED_MEMBERS, 6, "production generated-member limit")
    testAssert.eq(recipeCodec.MAX_CANONICAL_BYTES, 1048576, "production canonical-byte limit")
    testAssert.eq(recipeCodec.MAX_OUTPUT_BYTES, 2097152, "production rendered-byte limit")

    local limits = {fields = 8, nodes = 64}

    local function fixture(fields, deepLast)
        local lines = {"@derive(types.debug)", "local record Bounded"}
        for index = 1, fields do
            local depth = index == fields and deepLast or 7
            lines[#lines + 1] = ("    f%d: %sstring%s"):format(index, string.rep("{", depth), string.rep("}", depth))
        end
        lines[#lines + 1] = "end"

        return table.concat(lines, "\n")
    end

    local _, atDiagnostics = compileAt(fixture(8, 7), "bounded.nupp", {deriveLimits = limits})
    for _, diagnostic in ipairs(atDiagnostics) do
        assert(diagnostic.code ~= "NUPP2808", "the exact field/node boundary was rejected: " .. diagnostic.msg)
    end
    local _, beyondNode = compileAt(fixture(8, 8), "bounded.nupp", {deriveLimits = limits})
    local nodeLimited = false
    for _, diagnostic in ipairs(beyondNode) do
        nodeLimited = nodeLimited or diagnostic.code == "NUPP2808" and diagnostic.msg:find("semantic nodes", 1, true)
    end
    assert(nodeLimited, "the semantic-node boundary has no direct NUPP2808 fixture")

    local fields = {"@derive(types.debug)", "local record TooMany"}
    for index = 1, 9 do
        fields[#fields + 1] = "    f" .. index .. ": integer"
    end
    fields[#fields + 1] = "end"
    local _, beyondFields = compileAt(table.concat(fields, "\n"), "bounded.nupp", {deriveLimits = limits})
    local fieldLimited = false
    for _, diagnostic in ipairs(beyondFields) do
        fieldLimited = fieldLimited or diagnostic.code == "NUPP2808" and diagnostic.msg:find("fields", 1, true)
    end
    assert(fieldLimited, "the field boundary has no direct NUPP2808 fixture")
end

function M.cancelsWithoutPublishingAPartialRecipeAndRecovers()
    local source = [[
local editor = require("tests.fixtures.deriveeditor")
@derive(types.debug, editor.derive)
local record Recoverable
    names: {{{string}}}
    values: {[string]: {integer}}
end
]]
    local probes = 0
    local _, cancelledDiagnostics, parsed = compileAt(source, "cancelled.nupp", {
        cancelled = function()
            probes = probes + 1
            return probes > 10
        end,
    })
    testAssert.eq(#cancelledDiagnostics, 0, "cancellation is not a diagnostic")
    assert(
        parsed.cancelled and parsed.deriveAborted == "cancelled",
        "the check does not expose its ordinary cancelled result"
    )
    local declaration = firstDeclaration(parsed)
    assert(
        not declaration.deriveRecipe and not declaration.hoistedType.deriveRecipe,
        "a cancelled check published a partial recipe"
    )
    assert(not declaration.hoistedType.derivedDefinitions.debug, "a cancelled check left a generated member behind")

    local recovered = check.check(parsed, "cancelled.nupp", env)
    testAssert.eq(#recovered, 0, "the request after cancellation recovers")
    assert(not parsed.cancelled and firstDeclaration(parsed).deriveRecipe, "cancellation poisoned the next check")

    local budgetParsed = parser.parse(source, "budget.nupp")
    local budgetDiagnostics = check.check(budgetParsed, "budget.nupp", env, {deriveBudget = 10})
    local exhausted = false
    for _, diagnostic in ipairs(budgetDiagnostics) do
        exhausted = exhausted or diagnostic.code == "NUPP2808" and diagnostic.msg:find("work budget", 1, true)
    end
    assert(
        exhausted and not firstDeclaration(budgetParsed).deriveRecipe,
        "budget exhaustion did not abort the partial recipe"
    )
    testAssert.eq(#check.check(budgetParsed, "budget.nupp", env), 0, "budget exhaustion poisoned the retry")
end

function M.boundsRenderedRecipesAndReportsColdAndWarmObservations()
    local source = [[
local editor = require("tests.fixtures.deriveeditor")
@derive(types.debug, editor.derive)
local record ObservedClosure
    value: integer
end
]]
    local _, coldDiagnostics, cold = compileAt(source, "observed.nupp")
    testAssert.eq(#coldDiagnostics, 0, "cold observation diagnostics")
    local _, warmDiagnostics, warm = compileAt(source, "observed.nupp")
    testAssert.eq(#warmDiagnostics, 0, "warm observation diagnostics")
    testAssert.eq(#cold.deriveObservations, 2, "one observation per provider")
    testAssert.eq(#warm.deriveObservations, 2, "warm observation count")
    local expected = {["types.debug"] = 1, ["editor.derive"] = 3,}
    for index, observation in ipairs(cold.deriveObservations) do
        local warmed = warm.deriveObservations[index]
        testAssert.eq(
            observation.generatedMembers,
            expected[observation.provider],
            observation.provider .. " generated-member bound"
        )
        assert(observation.canonicalBytes > 0 and observation.renderedBytes > 0, "observation omits bounded sizes")
        testAssert.eq(observation.generatedLocals, 2, "closed recipe local bound")
        testAssert.eq(observation.maxGeneratedUpvalues, 1, "closed recipe upvalue bound")
        testAssert.eq(warmed.semanticFingerprint, observation.semanticFingerprint, "cold/warm semantic product")
        testAssert.eq(warmed.canonicalBytes, observation.canonicalBytes, "cold/warm canonical size")
        assert(warmed.cached, "the warm observation is not marked cached")
    end

    local hugeName = string.rep("x", 300)
    local hugeSource = "@derive(types.debug)\nlocal record " .. hugeName .. "\nvalue: string\nend\n"
    local _, diagnostics, parsed = compileAt(hugeSource, "huge.nupp", {deriveLimits = {canonicalBytes = 256},})
    local limited = false
    for _, diagnostic in ipairs(diagnostics) do
        limited = limited or diagnostic.code == "NUPP2808" and diagnostic.msg:find("canonical bytes", 1, true)
    end
    assert(limited, "an over-limit canonical plan did not report NUPP2808")
    assert(not firstDeclaration(parsed).deriveRecipe, "an over-limit plan reached lowering")
end

function M.recordsTheExactRuntimeFeatureManifest()
    local _, debugDiagnostics, debug = compile([[
@derive(types.debug)
local record Pure value: integer end
]])
    testAssert.eq(#debugDiagnostics, 0, "pure derive feature diagnostics")
    local pureEffects = firstDeclaration(debug).compilerFeatureEffects
    testAssert.eq(table.concat(pureEffects, ","), "stdlib.derives", "pure derive feature manifest")

end

function M.delimitsTheRuntimeFromAnEmittedFirstLine()
    local result = run(
        "derivetest.delimitsTheRuntimeFromAnEmittedFirstLine",
        [[
local marker = "first"
@derive(types.debug)
local record First value: integer end
return marker .. ":" .. (First(value = 1)):debug()
]]
    )
    testAssert.eq(result, "first:First { value = 1LL }")
end

return M
