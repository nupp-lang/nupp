-- S1: `nosuspend` regions.
--
-- Lexical, static, and erased. What is asserted here is the verdict and the erasure:
-- a call that may suspend is refused, one that provably cannot is silent, and the
-- generated code is the same either way because the region has no run-time component.
local parser = require("nupp.compiler.parser")
local gen = require("nupp.compiler.gen")
local check = require("fragment")
local envMod = require("nupp.compiler.env")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))

local function assertEq(got, want, label)
   if got ~= want then
      error(("%s:\n  want: %s\n  got:  %s"):format(label or "mismatch",
         tostring(want), tostring(got)), 2)
   end
end

local function assertTrue(cond, label)
   if not cond then error(label or "expected true", 2) end
end

local function diagnose(src)
   local env = envMod.new(HERE)
   local result = parser.parse(src, "test.g.nupp")
   assertEq(#result.errors, 0, "syntax errors in test source")
   local diags = check.check(result, "test.g.nupp", env)
   local refusals = {}
   for _, diag in ipairs(diags) do
      if diag.code == "NUPP2701" then refusals[#refusals + 1] = diag end
   end
   return refusals, diags, result
end

local QUIET = "local function quiet(): nil\n    local n = 1\nend\n"
local NOISY = "local function noisy(): nil\n    coroutine.yield()\nend\n"

local M = {}

function M.refusesACallThatSuspends()
   local refusals = diagnose(NOISY .. "nosuspend do\n    noisy()\nend")
   assertEq(#refusals, 1, "one refusal")
   assertTrue(refusals[1].msg:find("noisy", 1, true) ~= nil,
      "it names the callee: " .. refusals[1].msg)
end

function M.allowsACallThatCannot()
   local refusals = diagnose(QUIET .. "nosuspend do\n    quiet()\nend")
   assertEq(#refusals, 0, "a proved-quiet callee is silent")
end

function M.followsTheCallGraph()
   -- The suspension is two functions away. A region that only caught a direct
   -- `coroutine.yield` would catch almost nothing real.
   local src = NOISY .. "local function middle(): nil\n    noisy()\nend\n"
      .. "nosuspend do\n    middle()\nend"
   local refusals = diagnose(src)
   assertEq(#refusals, 1, "the transitive call is refused")
   assertTrue(refusals[1].msg:find("middle", 1, true) ~= nil,
      "reported at the call that was written")
end

function M.namesThePathToTheSuspension()
   local src = NOISY .. "local function middle(): nil\n    noisy()\nend\n"
      .. "nosuspend do\n    middle()\nend"
   local refusals = diagnose(src)
   local related = refusals[1] and refusals[1].related
   assertTrue(related ~= nil and #related > 0,
      "a one-line refusal is not actionable when the yield is not here")
end

function M.reachesAcrossAModuleBoundary()
   -- The fact rides on the type, so an export is answered without this file having
   -- seen its body.
   local refusals = diagnose(table.concat({
      'local B = require("fixtures.effects")',
      "nosuspend do",
      "    B.safe()",
      "    B.waits()",
      "end",
   }, "\n"))
   assertEq(#refusals, 1, "only the yielding export is refused")
   assertTrue(refusals[1].msg:find("waits", 1, true) ~= nil,
      "and it is the right one: " .. refusals[1].msg)
end

function M.refusesAnUnresolvableCall()
   -- A call the compiler cannot follow is exactly what a region exists to be careful
   -- about, so silence would be the wrong default.
   local refusals = diagnose("nosuspend do\n    someUnknownGlobal()\nend")
   assertEq(#refusals, 1, "an unresolved callee is refused")
end

function M.nestsAndEnds()
   local src = QUIET .. NOISY .. table.concat({
      "nosuspend do",
      "    quiet()",
      "end",
      "noisy()",
   }, "\n")
   assertEq(#diagnose(src), 0, "the region ends where it closes")
end

function M.erasesToAPlainBlock()
   local src = QUIET .. "nosuspend do\n    quiet()\nend\n"
   local _, _, result = diagnose(src)
   local code = gen.generate(result, "test")
   assertEq(code:find("nosuspend", 1, true), nil,
      "nothing of the region survives: " .. code)
   assertTrue(code:find("do", 1, true) ~= nil, "the block remains: " .. code)
   local function lines(text)
      local n = 1
      for _ in text:gmatch("\n") do n = n + 1 end
      return n
   end
   assertEq(lines(code), lines(src), "and the line count holds")
end

function M.staysAName()
   -- Contextual on the same rule as `unsafe`: a name followed by `do`.
   local refusals, diags = diagnose("local nosuspend = 1\nreturn nosuspend")
   assertEq(#refusals, 0, "no region was opened")
   for _, diag in ipairs(diags) do
      assertTrue(diag.severity == "warning" or diag.severity == "note",
         "an ordinary name still checks: " .. diag.code)
   end
end

function M.acceptsAnAnnotatedPreludeCall()
   -- The prelude is not special-cased. Its pure members say `nosuspend function(...)`
   -- in the declaration like anything else would, and that is what admits them.
   local refusals = diagnose(table.concat({
      "nosuspend do",
      "    local n = math.floor(1.5)",
      "    local s = string.rep('-', n)",
      "    local t = table.concat({'a'}, ',')",
      "    local b = bit.band(1, 2)",
      "    print(n, s, t, b)",
      "end",
   }, "\n"))
   assertEq(#refusals, 1, "only the unannotated one is refused")
   assertTrue(refusals[1].msg:find("print", 1, true) ~= nil,
      "and it is `print`, which says nothing about its effects: " .. refusals[1].msg)
end

function M.aBodylessAnnotatedDeclarationIsAccepted()
   -- The case the modifier exists for: a binding whose body this compiler never sees.
   local refusals = diagnose(table.concat({
      "local host: {quiet: nosuspend function(n: integer): integer}",
      "nosuspend do",
      "    host.quiet(1)",
      "end",
   }, "\n"))
   assertEq(#refusals, 0, "a declared guarantee is a guarantee")
end

function M.aBodylessUnannotatedDeclarationIsRefused()
   local refusals = diagnose(table.concat({
      "local host: {loud: function(): nil}",
      "nosuspend do",
      "    host.loud()",
      "end",
   }, "\n"))
   assertEq(#refusals, 1, "silence is not a guarantee")
end

function M.theModifierSurvivesAnAlias()
   local refusals = diagnose(table.concat({
      "local host: {quiet: nosuspend function(n: integer): integer}",
      "local f = host.quiet",
      "nosuspend do",
      "    f(1)",
      "end",
   }, "\n"))
   assertEq(#refusals, 0, "the fact is the type's, so renaming does not lose it")
end

function M.aNoSuspendFunctionSatisfiesAnOrdinarySlot()
   -- A guarantee only has to hold where one was asked for.
   local refusals, diags = diagnose(table.concat({
      "local host: {quiet: nosuspend function(n: integer): integer}",
      "local slot: function(n: integer): integer = host.quiet",
      "return slot",
   }, "\n"))
   assertEq(#refusals, 0, "no region here")
   for _, diag in ipairs(diags) do
      assertTrue(diag.severity == "warning" or diag.severity == "note",
         "it fits the wider slot: " .. diag.code .. " " .. diag.msg)
   end
end

function M.anOrdinaryFunctionDoesNotSatisfyANoSuspendSlot()
   local _, diags = diagnose(table.concat({
      "local host: {loud: function(n: integer): integer}",
      "local slot: nosuspend function(n: integer): integer = host.loud",
      "return slot",
   }, "\n"))
   local refused = nil
   for _, diag in ipairs(diags) do
      if diag.code == "NUPP2001" then refused = diag end
   end
   assertTrue(refused ~= nil, "a may-yield function cannot fill a slot that forbids it")
   assertTrue(refused.msg:find("suspend", 1, true) ~= nil,
      "and the refusal says why: " .. refused.msg)
end

function M.theModifierSurvivesGenericSubstitution()
   local T = require("nupp.compiler.types")
   local generics = require("nupp.compiler.generics")
   local tv = T.typevar("T")
   local safe = T.withYields(T.func({tv}, {tv}), false)
   local concrete = generics.subst(safe, {[tv] = T.string})
   assertEq(concrete.noYield, true, "substitution rewrites types, not effects")
   assertEq(concrete.params[1], T.string, "and the substitution happened")
end

function M.aHandleRegionInstallsAndRestores()
   local src = table.concat({
      'local s = require("nupp.suspension")',
      "local h = {park = function() end}",
      "local before = s.handled()",
      "local inside = false",
      "handle suspension with h do",
      "    inside = s.handled()",
      "end",
      "return before, inside, s.handled()",
   }, "\n")
   local refusals, diags, result = diagnose(src)
   assertEq(#refusals, 0, "no region check here")
   for _, diag in ipairs(diags) do
      assertTrue(diag.severity == "warning" or diag.severity == "note",
         "it checks: " .. diag.code .. " " .. diag.msg)
   end
   local code = gen.generate(result, "test")
   assertTrue(code:find("install", 1, true) ~= nil,
      "it elaborates to installing a handler: " .. code)
   assertTrue(code:find("release", 1, true) ~= nil,
      "and to discharging it: " .. code)
   assertEq(code:find("handle suspension", 1, true), nil,
      "with nothing of the construct surviving: " .. code)
end

function M.aHandleRegionPreservesTheLineCount()
   local src = "local h = {park = function() end}\nhandle suspension with h do\n"
      .. "    local n = 1\n    print(n)\nend\n"
   local _, _, result = diagnose(src)
   local code = gen.generate(result, "test")
   local function lines(text)
      local n = 1
      for _ in text:gmatch("\n") do n = n + 1 end
      return n
   end
   assertEq(lines(code), lines(src), "attribution holds: " .. code)
end

function M.refusesControlLeavingAHandleRegion()
   -- The body lowers to a protected closure, so a `return` inside it would return from
   -- that closure and the function around it would carry on -- silently. Refused until
   -- the lowering reuses what `with` does for the same problem.
   local _, diags = diagnose(table.concat({
      "local h = {park = function() end}",
      "local function f(): integer",
      "    handle suspension with h do",
      "        return 1",
      "    end",
      "    return 0",
      "end",
      "return f",
   }, "\n"))
   local found = nil
   for _, diag in ipairs(diags) do
      if diag.code == "NUPP2706" then found = diag end
   end
   assertTrue(found ~= nil, "leaving the region is refused rather than mis-compiled")
end

function M.allowsABreakInsideALoopInAHandleRegion()
   -- A `break` bound by a loop inside the region never crosses the closure boundary.
   local _, diags = diagnose(table.concat({
      "local h = {park = function() end}",
      "handle suspension with h do",
      "    for index = 1, 3 do",
      "        if index == 2 then",
      "            break",
      "        end",
      "    end",
      "end",
   }, "\n"))
   for _, diag in ipairs(diags) do
      assertTrue(diag.code ~= "NUPP2706",
         "a loop's own break is not leaving the region")
   end
end

function M.handleIsContextualInBothWords()
   local _, diags = diagnose(table.concat({
      "local handle = 1",
      "local suspension = 2",
      "return handle + suspension",
   }, "\n"))
   for _, diag in ipairs(diags) do
      assertTrue(diag.severity == "warning" or diag.severity == "note",
         "both stay ordinary names: " .. diag.code)
   end
end

return M
