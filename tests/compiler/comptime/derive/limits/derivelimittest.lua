local fixture = require("helpers.derive")
local testAssert = fixture.testAssert
local parser = fixture.parser
local check = fixture.check
local derive = fixture.derive
local recipeCodec = fixture.recipeCodec
local env = fixture.env
local compileAt = fixture.compileAt
local firstDeclaration = fixture.firstDeclaration

local program = require("helpers.derive").program

local M = {}

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

return M
