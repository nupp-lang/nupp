local testAssert = require("nupp.test")
-- Compiler-owned declaration derives: semantic members, factory projection, and
-- closed runtime recipes independently of serialization bindings.
local parser = require("nupp.compiler.syntax.parser")
local gen = require("nupp.compiler.lua.gen")
local check = require("fragment")
local envMod = require("nupp.compiler.project.env")
local derive = require("nupp.compiler.check.derive")
local recipeCodec = require("nupp.compiler.comptime.materialize.codec")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local env = envMod.new(HERE .. "/..")

local function compileAt(source, filename, opts)
    filename = filename or "derive_test.g.nupp"
    local parsed = parser.parse(source, filename)
    testAssert.equal(#parsed.errors, 0, "syntax errors")
    local diagnostics = check.check(parsed, filename, env, opts)
    local code, generated = gen.generate(parsed, "derive_test")
    for _, diagnostic in ipairs(generated) do
        diagnostics[#diagnostics + 1] = diagnostic
    end

    return code, diagnostics, parsed
end

local function compile(source)
    return compileAt(source, "derive_test.g.nupp")
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
    testAssert.equal(outputLines, sourceLines, "derive lowering changed the source/output line count")

    return chunk(), code
end

local M = {}

function M.constructsFreshMutableDefaults()
    local result = run(
        [[
local record Options
    tags: {string} = {}
    values: {[string]: integer} = {}
    point: {x: integer, label: string} = {x = 0, label = ""}
end
local left = new Options()
local right = new Options()
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
    testAssert.equal(result.tags, 0)
    testAssert.equal(result.changed, nil)
    testAssert.equal(result.x, 0)
    testAssert.equal(result.distinct, true)
end

function M.supportsNestedAndBoundedGenericDebugRecords()
    local result = run(
        [[
@derive(nupp.derive.Debug)
local record Item
    label: string
end

@derive(nupp.derive.Debug)
local record Box<T is nupp.Debug>
    value: T
end

local record Namespace
    @derive(nupp.derive.Debug)
    record Inner
        count: integer = 0
    end
end

local boxed: Box<Item> = new Box(value = new Item(label = "ok"))
local inner: Namespace.Inner = new Namespace.Inner()
return {box = boxed:debug(), inner = inner:debug()}
]]
    )
    testAssert.equal(result.box, 'Box { value = Item { label = "ok" } }')
    testAssert.equal(result.inner, "Inner { count = 0 }")
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
        {"NUPP2803", [[
@derive(nupp.derive.Debug)
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
    testAssert.equal(codes[1], "NUPP2809", "bare built-in derive names are removed")
end

function M.offersWholeFixesForDuplicateAndConflictingProviders()
    local _, duplicateDiagnostics = compile(
        [[
@derive(nupp.derive.Debug, nupp.derive.Debug)
local record Duplicate value: integer end
]]
    )
    local _, conflictDiagnostics = compile(
        [[
@derive(nupp.derive.Debug)
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
        hasFix(duplicateDiagnostics, "remove duplicate @derive(nupp.derive.Debug)"),
        "duplicate provider has no whole removal fix"
    )
    assert(
        hasFix(conflictDiagnostics, "remove @derive(nupp.derive.Debug)"),
        "generated-member collision has no whole derive removal fix"
    )
end

function M.recheckingADerivedDeclarationIsIdempotent()
    local source = [[
local editor = require("tests.fixtures.deriveeditor")
@derive(nupp.derive.Debug, editor.derive)
local record Stable
    value: integer = 0
end
return new Stable()
]]
    local parsed = parser.parse(source, "derive_recheck.g.nupp")
    testAssert.equal(#parsed.errors, 0, "syntax errors")
    for pass = 1, 2 do
        local diagnostics = check.check(parsed, "derive_recheck.g.nupp", env)
        for _, diagnostic in ipairs(diagnostics) do
            if diagnostic.severity ~= "warning" and diagnostic.severity ~= "note" then
                error(("pass %d unexpectedly reported %s: %s"):format(pass, diagnostic.code, diagnostic.msg))
            end
        end
    end
end

function M.fingerprintsDebugAnnotationChanges()
    local function fingerprint(redacted)
        local source = "@derive(nupp.derive.Debug)\nlocal record Fingerprinted\n" .. (
            redacted and "@debug(redact = true)\n" or ""
        ) .. "value: string\nend"
        local _, diagnostics, parsed = compile(source)
        testAssert.equal(#diagnostics, 0)

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
    testAssert.equal(#diagnostics, 0, "derive identity diagnostics")
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
    local stringCode, stringDiagnostics, stringParsed = compileAt(
        [[
@derive(nupp.derive.Debug)
local record Mapped entries: {[string]: string} end
]],
        "spelling/../mapped.g.nupp"
    )
    local integerCode, integerDiagnostics, integerParsed = compileAt(
        [[
@derive(nupp.derive.Debug)
local record Mapped entries: {[integer]: string} end
]],
        "mapped.g.nupp"
    )
    testAssert.equal(#stringDiagnostics, 0, "string map diagnostics")
    testAssert.equal(#integerDiagnostics, 0, "integer map diagnostics")
    local stringRecipe = assert(firstDeclaration(stringParsed).deriveRecipe)
    local integerRecipe = assert(firstDeclaration(integerParsed).deriveRecipe)
    assert(stringRecipe.fingerprint ~= integerRecipe.fingerprint, "a Debug map key edit kept the recipe fingerprint")

    local alternateCode, alternateDiagnostics = compileAt(
        [[
@derive(nupp.derive.Debug)
local record Mapped entries: {[string]: string} end
]],
        "/tmp/another-spelling/mapped.g.nupp"
    )
    testAssert.equal(#alternateDiagnostics, 0, "alternate path diagnostics")
    testAssert.equal(alternateCode, stringCode, "generated bytes depend on the invocation path spelling")
end

function M.boundsFieldsAndSemanticRecipeNodesAtTheirExactLimits()
    testAssert.equal(derive.MAX_FIELDS, 2048, "production field limit")
    testAssert.equal(derive.MAX_RECIPE_NODES, 16384, "production semantic-node limit")
    testAssert.equal(derive.MAX_GENERATED_MEMBERS, 6, "production generated-member limit")
    testAssert.equal(recipeCodec.MAX_CANONICAL_BYTES, 1048576, "production canonical-byte limit")
    testAssert.equal(recipeCodec.MAX_OUTPUT_BYTES, 2097152, "production rendered-byte limit")

    local limits = {fields = 8, nodes = 64}

    local function fixture(fields, deepLast)
        local lines = {"@derive(nupp.derive.Debug)", "local record Bounded"}
        for index = 1, fields do
            local depth = index == fields and deepLast or 7
            lines[#lines + 1] = ("    f%d: %sstring%s"):format(index, string.rep("{", depth), string.rep("}", depth))
        end
        lines[#lines + 1] = "end"

        return table.concat(lines, "\n")
    end

    local _, atDiagnostics = compileAt(fixture(8, 7), "bounded.g.nupp", {deriveLimits = limits})
    for _, diagnostic in ipairs(atDiagnostics) do
        assert(diagnostic.code ~= "NUPP2808", "the exact field/node boundary was rejected: " .. diagnostic.msg)
    end
    local _, beyondNode = compileAt(fixture(8, 8), "bounded.g.nupp", {deriveLimits = limits})
    local nodeLimited = false
    for _, diagnostic in ipairs(beyondNode) do
        nodeLimited = nodeLimited or diagnostic.code == "NUPP2808" and diagnostic.msg:find("semantic nodes", 1, true)
    end
    assert(nodeLimited, "the semantic-node boundary has no direct NUPP2808 fixture")

    local fields = {"@derive(nupp.derive.Debug)", "local record TooMany"}
    for index = 1, 9 do
        fields[#fields + 1] = "    f" .. index .. ": integer"
    end
    fields[#fields + 1] = "end"
    local _, beyondFields = compileAt(table.concat(fields, "\n"), "bounded.g.nupp", {deriveLimits = limits})
    local fieldLimited = false
    for _, diagnostic in ipairs(beyondFields) do
        fieldLimited = fieldLimited or diagnostic.code == "NUPP2808" and diagnostic.msg:find("fields", 1, true)
    end
    assert(fieldLimited, "the field boundary has no direct NUPP2808 fixture")
end

function M.cancelsWithoutPublishingAPartialRecipeAndRecovers()
    local source = [[
local editor = require("tests.fixtures.deriveeditor")
@derive(nupp.derive.Debug, editor.derive)
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
    testAssert.equal(#cancelledDiagnostics, 0, "cancellation is not a diagnostic")
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

    local recovered = check.check(parsed, "cancelled.g.nupp", env)
    testAssert.equal(#recovered, 0, "the request after cancellation recovers")
    assert(not parsed.cancelled and firstDeclaration(parsed).deriveRecipe, "cancellation poisoned the next check")

    local budgetParsed = parser.parse(source, "budget.g.nupp")
    local budgetDiagnostics = check.check(budgetParsed, "budget.g.nupp", env, {deriveBudget = 10})
    local exhausted = false
    for _, diagnostic in ipairs(budgetDiagnostics) do
        exhausted = exhausted or diagnostic.code == "NUPP2808" and diagnostic.msg:find("work budget", 1, true)
    end
    assert(
        exhausted and not firstDeclaration(budgetParsed).deriveRecipe,
        "budget exhaustion did not abort the partial recipe"
    )
    testAssert.equal(#check.check(budgetParsed, "budget.g.nupp", env), 0, "budget exhaustion poisoned the retry")
end

function M.boundsRenderedRecipesAndReportsColdAndWarmObservations()
    local source = [[
local editor = require("tests.fixtures.deriveeditor")
@derive(nupp.derive.Debug, editor.derive)
local record ObservedClosure
    value: integer
end
]]
    local _, coldDiagnostics, cold = compileAt(source, "observed.g.nupp")
    testAssert.equal(#coldDiagnostics, 0, "cold observation diagnostics")
    local _, warmDiagnostics, warm = compileAt(source, "observed.g.nupp")
    testAssert.equal(#warmDiagnostics, 0, "warm observation diagnostics")
    testAssert.equal(#cold.deriveObservations, 2, "one observation per provider")
    testAssert.equal(#warm.deriveObservations, 2, "warm observation count")
    local expected = {["nupp.derive.Debug"] = 1, ["editor.derive"] = 3,}
    for index, observation in ipairs(cold.deriveObservations) do
        local warmed = warm.deriveObservations[index]
        testAssert.equal(
            observation.generatedMembers,
            expected[observation.provider],
            observation.provider .. " generated-member bound"
        )
        assert(observation.canonicalBytes > 0 and observation.renderedBytes > 0, "observation omits bounded sizes")
        testAssert.equal(observation.generatedLocals, 2, "closed recipe local bound")
        testAssert.equal(observation.maxGeneratedUpvalues, 1, "closed recipe upvalue bound")
        testAssert.equal(warmed.semanticFingerprint, observation.semanticFingerprint, "cold/warm semantic product")
        testAssert.equal(warmed.canonicalBytes, observation.canonicalBytes, "cold/warm canonical size")
        assert(warmed.cached, "the warm observation is not marked cached")
    end

    local hugeName = string.rep("x", 300)
    local hugeSource = "@derive(nupp.derive.Debug)\nlocal record " .. hugeName .. "\nvalue: string\nend\n"
    local code, diagnostics, parsed = compileAt(hugeSource, "huge.g.nupp", {deriveLimits = {canonicalBytes = 256},})
    local limited = false
    for _, diagnostic in ipairs(diagnostics) do
        limited = limited or diagnostic.code == "NUPP2808" and diagnostic.msg:find("canonical bytes", 1, true)
    end
    assert(limited, "an over-limit canonical plan did not report NUPP2808")
    assert(not firstDeclaration(parsed).deriveRecipe, "an over-limit plan reached lowering")
    assert(not code:find("__derive.register", 1, true), "over-limit derive Lua was emitted")
end

function M.excludesTheRuntimeFromProgramsWithoutDerives()
    local code = compile("return 42")
    testAssert.equal(code:find("__nuppDerive", 1, true), nil, "unused derive runtime")
end

function M.recordsTheExactRuntimeFeatureManifest()
    local _, debugDiagnostics, debug = compile([[
@derive(nupp.derive.Debug)
local record Pure value: integer end
]])
    testAssert.equal(#debugDiagnostics, 0, "pure derive feature diagnostics")
    local pureEffects = firstDeclaration(debug).compilerFeatureEffects
    testAssert.equal(table.concat(pureEffects, ","), "stdlib.derives", "pure derive feature manifest")

end

function M.delimitsTheRuntimeFromAnEmittedFirstLine()
    local result = run(
        [[local marker = "first"
@derive(nupp.derive.Debug)
local record First value: integer end
return marker .. ":" .. (new First(value = 1)):debug()
]]
    )
    testAssert.equal(result, "first:First { value = 1 }")
end

return M
