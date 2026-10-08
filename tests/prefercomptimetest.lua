local testAssert = require("nupp.test")
-- prefer-comptime: a bounded comptime trial proves that meaningful work in one
-- no-input runtime function can be replaced by a scalar literal.
local parser = require("nupp.compiler.syntax.parser")
local check = require("nupp.compiler.check")
local gen = require("nupp.compiler.lua.gen")
local envMod = require("nupp.compiler.project.env")

local sharedEnv = envMod.new(".")

local function diagnostics(src, enabled)
   local result = parser.parse(src, "test.g.nupp")
   testAssert.equal(#result.errors, 0, "syntax errors in test source")
   local opts = enabled == false and {} or {lints = {["prefer-comptime"] = "warning"}}
   local found = {}
   for _, diagnostic in ipairs(check.check(result, "test.g.nupp", sharedEnv, opts)) do
      assert(diagnostic.severity ~= "error", diagnostic.code .. ": " .. diagnostic.msg)
      if diagnostic.code == "NUPP2518" then found[#found + 1] = diagnostic end
   end
   return found
end

local function applyFix(source, fix)
   local edits = {}
   for _, edit in ipairs(fix.edits or {}) do edits[#edits + 1] = edit end
   table.sort(edits, function(a, b) return a.offset > b.offset end)
   for _, edit in ipairs(edits) do
      source = source:sub(1, edit.offset - 1) .. edit.newText
         .. source:sub(edit.offset + edit.length)
   end
   return source
end

local TOTAL = [[
local m = {}

function m.total(): integer
    local xs: {integer} = {10, 20, 30}
    local sum: integer = 0
    for index, value in ipairs(xs) do
        sum += index * value
    end
    return sum
end

return m
]]

local M = {}

function M.reportsClosedRuntimeWorkWithTheComputedResult()
   local found = diagnostics(TOTAL)
   testAssert.equal(#found, 1, "one closed function")
   local at = found[1]
   testAssert.equal(at.lint, "prefer-comptime", "lint name")
   testAssert.equal(at.severity, "warning", "configured level")
   assert(at.help and at.help:find("reduces to `140`", 1, true), at.help)
end

function M.offersAnApiPreservingComptimeFix()
   local at = diagnostics(TOTAL)[1]
   testAssert.equal(#(at.fixes or {}), 1, "one unambiguous fix")
   local rewritten = applyFix(TOTAL, at.fixes[1])
   assert(rewritten:find("function m.total%(%)"), rewritten)
   assert(rewritten:find("return comptime do", 1, true), rewritten)
   local parsed = parser.parse(rewritten, "fixed.g.nupp")
   testAssert.equal(#parsed.errors, 0, "the fix parses")
   for _, diagnostic in ipairs(check.check(parsed, "fixed.g.nupp", sharedEnv,
      {lints = {["prefer-comptime"] = "warning"}})) do
      assert(diagnostic.severity ~= "error", diagnostic.code .. ": " .. diagnostic.msg)
   end
   local generated, generationDiagnostics = gen.generate(parsed, "fixed.g.nupp")
   testAssert.equal(#generationDiagnostics, 0, "the fix generates")
   assert(generated:find("return 140", 1, true), generated)
   testAssert.equal(#diagnostics(rewritten), 0, "the fixed source is no longer suggested")
end

function M.isOffByDefault()
   testAssert.equal(#diagnostics(TOTAL, false), 0, "performance advice is opt-in")
end

function M.requiresAFunctionWithNoRuntimeInput()
   testAssert.equal(#diagnostics([[
local function total(scale: integer): integer
    local xs: {integer} = {10, 20, 30}
    local sum: integer = 0
    for index, value in ipairs(xs) do sum += index * value * scale end
    return sum
end
return total
]]), 0, "a parameter keeps the work at runtime")
end

function M.requiresClosedDeterministicWork()
   testAssert.equal(#diagnostics([[
local seed: integer = 10
local function total(): integer
    local xs: {integer} = {seed, 20, 30}
    local sum: integer = 0
    for index, value in ipairs(xs) do sum += index * value end
    return sum
end
return total
]]), 0, "a runtime capture is unavailable to comptime")
end

function M.ignoresTrivialAndAlreadyComptimeBodies()
   testAssert.equal(#diagnostics("local function answer(): integer return 42 end\nreturn answer"), 0,
      "a literal has no work to erase")
   testAssert.equal(#diagnostics([[
local function answer(): integer
    return comptime do return 6 * 7 end
end
return answer
]]), 0, "an explicit comptime block needs no advice")
end

function M.canBeAllowedAtTheDeclaration()
   testAssert.equal(#diagnostics([[
@allow("prefer-comptime")
local function total(): integer
    local xs: {integer} = {10, 20, 30}
    local sum: integer = 0
    for index, value in ipairs(xs) do sum += index * value end
    return sum
end
return total
]]), 0, "a local suppression reaches the lint")
end

return M
