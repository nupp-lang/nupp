local fixture = require("helpers.derive")
local testAssert = fixture.testAssert
local compile = fixture.compile
local firstDeclaration = fixture.firstDeclaration
local run = fixture.run

local M = {}

function M.excludesTheRuntimeFromProgramsWithoutDerives()
    local code = compile("return 42")
    testAssert.eq(code:find("__nuppDerive", 1, true), nil, "unused derive runtime")
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
        [[
local marker = "first"
@derive(types.debug)
local record First value: integer end
return marker .. ":" .. (First(value = 1)):debug()
]]
    )
    testAssert.eq(result, "first:First { value = 1 }")
end

return M
