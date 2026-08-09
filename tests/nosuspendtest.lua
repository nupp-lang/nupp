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

function M.aPreludeCallIsRefusedForNow()
   -- Documents a known limitation rather than a design. A prelude function is a field
   -- of a table type annotation, so there is nowhere to write `@effects` on it, and an
   -- undeclared effect is conservatively may-yield. Until declaration files can state
   -- the fact, `nosuspend` cannot admit `math.floor`.
   --
   -- This test should change, not be deleted, when that lands.
   local refusals = diagnose("nosuspend do\n    math.floor(1.5)\nend")
   assertEq(#refusals, 1, "the prelude is conservatively may-yield today")
end

return M
