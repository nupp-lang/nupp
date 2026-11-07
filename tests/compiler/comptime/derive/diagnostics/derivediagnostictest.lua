local fixture = require("helpers.derive")
local testAssert = fixture.testAssert
local compile = fixture.compile
local errorsOf = fixture.errorsOf

local program = require("helpers.derive").program

local M = {}

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

return M
