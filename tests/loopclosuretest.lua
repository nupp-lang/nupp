local parser = require("compiler.parser")
local check = require("fragment")
local envMod = require("compiler.env")

local function assertEq(got, want, label)
   if got ~= want then
      error(("%s:\n  want: %s\n  got:  %s"):format(label or "mismatch",
         tostring(want), tostring(got)), 2)
   end
end

-- Every NUPP2505 the source produces.
local function lint(src)
   local result = parser.parse(src, "test.g.nupp")
   assertEq(#result.errors, 0, "syntax errors in test source")
   local diags = check.check(result, "test.g.nupp", envMod.new("."), {})
   local found = {}
   for _, diag in ipairs(diags) do
      if diag.code == "NUPP2505" then found[#found + 1] = diag end
   end
   return found
end

local function assertFlagged(src, label)
   local found = lint(src)
   assertEq(#found, 1, (label or "expected one report") .. "\n" .. src)
   assertEq(found[1].lint, "loop-invariant-closure", "lint name")
   return found[1]
end

local function assertQuiet(src, label)
   local found = lint(src)
   if #found ~= 0 then
      error(("%s: reported %s at line %d\n%s"):format(
         label or "expected no report", found[1].code, found[1].line, src), 2)
   end
end

local M = {}

function M.flagsAClosureThatIgnoresTheIteration()
   local at = assertFlagged([[
for _, item in ipairs(items) do
   register(item, function(e) return e.kind == "click" end)
end
]])
   assertEq(at.line, 2, "reported at the function, not the loop")
   assertEq(at.severity, "warning", "suspicious lints warn by default")
end

function M.flagsAShortFunction()
   assertFlagged([[
for _, item in ipairs(items) do
   register(item, |e| -> e.kind == "click")
end
]], "a short function is a function")
end

function M.flagsANumericLoop()
   assertFlagged([[
for i = 1, 10 do
   register(function() return 1 end)
end
]])
end

function M.flagsAWhileLoop()
   assertFlagged([[
while more() do
   register(function() return 1 end)
end
]])
end

function M.flagsARepeatLoop()
   assertFlagged([[
repeat
   register(function() return 1 end)
until done()
]])
end

function M.flagsALocalFunctionDeclaredInALoop()
   assertFlagged([[
for i = 1, 10 do
   local function step() return 1 end
   register(step)
end
]], "a named function allocates once per iteration too")
end

function M.allowsCapturingTheLoopVariable()
   assertQuiet([[
for _, item in ipairs(items) do
   register(function() return item.id end)
end
]], "the closure differs every iteration")
end

function M.allowsCapturingTheNumericLoopVariable()
   assertQuiet([[
for i = 1, 10 do
   register(function() return i end)
end
]])
end

function M.allowsCapturingALocalDeclaredInTheLoop()
   assertQuiet([[
for _, item in ipairs(items) do
   local scaled = item.size * 2
   register(function() return scaled end)
end
]], "the local is rebound every iteration")
end

function M.flagsCapturingSomethingBoundBeforeTheLoop()
   assertFlagged([[
local factor = 2
for _, item in ipairs(items) do
   register(function(x) return x * factor end)
end
]], "a name bound before the loop is the same name every iteration")
end

function M.flagsCapturingAnEnclosingParameter()
   assertFlagged([[
local function scale(factor, items)
   for _, item in ipairs(items) do
      register(function(x) return x * factor end)
   end
end
]], "a parameter does not change across the loop")
end

function M.allowsAClosureReturnedFromInsideALoop()
   assertQuiet([[
local function finder(members)
   for _, member in ipairs(members) do
      if member.wanted then
         return function(flag) return lookup(flag) end
      end
   end
end
]], "a loop that returns runs its body once, so there is nothing repeated")
end

function M.allowsALoopThatBreaksOnItsFirstPass()
   assertQuiet([[
for _, item in ipairs(items) do
   register(function() return 1 end)
   break
end
]], "the body leaves on the first pass, so it builds one function")
end

function M.stillFlagsWhenTheBreakIsConditional()
   assertFlagged([[
for _, item in ipairs(items) do
   register(function() return 1 end)
   if item.last then break end
end
]], "a conditional break is a loop that can still go round again")
end

function M.stillFlagsWhenTheLoopOnlyContinues()
   assertFlagged([[
for _, item in ipairs(items) do
   register(function() return 1 end)
   continue
end
]], "continue ends an iteration, not the loop")
end

function M.stillFlagsInsideAFunctionThatWasReturned()
   assertFlagged([[
local function outer(items)
   return function()
      for _, item in ipairs(items) do
         register(function() return 1 end)
      end
   end
end
]], "being inside a returned function excuses that function, not a loop in it")
end

function M.allowsAClosureOutsideAnyLoop()
   assertQuiet([[
register(function(e) return e.kind == "click" end)
]])
end

function M.allowsAClosureInAFunctionDeclaredInALoop()
   assertQuiet([[
for _, item in ipairs(items) do
   register(function()
      return function() return item.id end
   end)
end
]], "the inner function belongs to the outer one, not to the loop")
end

function M.flagsOnlyTheOutermostOfNestedFunctions()
   local found = lint([[
for i = 1, 10 do
   register(function()
      return function() return 1 end
   end)
end
]])
   assertEq(#found, 1, "the inner function is not the loop's to hoist")
   assertEq(found[1].line, 2, "the outer one is reported")
end

function M.flagsInsideTheInnerOfTwoLoops()
   assertFlagged([[
for i = 1, 10 do
   for j = 1, 10 do
      register(function() return 1 end)
   end
end
]], "the innermost loop is the one it can be lifted out of")
end

function M.flagsCapturingTheOuterLoopVariableFromTheInnerLoop()
   assertFlagged([[
for i = 1, 10 do
   for j = 1, 10 do
      register(function() return i end)
   end
end
]], "invariant means invariant for the innermost loop: i does not change "
   .. "across j, so nine of every ten allocations are the same function")
end

function M.carriesAHelp()
   local at = assertFlagged([[
for i = 1, 10 do
   register(function() return 1 end)
end
]])
   assertEq(at.help, "declare it once above the loop and pass the name",
      "help text")
end

function M.canBeAllowed()
   assertQuiet([[
for i = 1, 10 do
   @allow("loop-invariant-closure")
   register(function() return 1 end)
end
]], "a lint is a judgement a statement may disagree with")
end

function M.canBeAllowedByCode()
   assertQuiet([[
for i = 1, 10 do
   @allow("NUPP2505")
   register(function() return 1 end)
end
]], "either spelling reaches the lint")
end

function M.canBeTurnedOff()
   local result = parser.parse([[
for i = 1, 10 do
   register(function() return 1 end)
end
]], "test")
   local diags = check.check(result, "test.g.nupp", envMod.new("."),
      {lints = {["loop-invariant-closure"] = "off"}})
   for _, diag in ipairs(diags) do
      assertEq(diag.code ~= "NUPP2505", true, "a lint set to off says nothing")
   end
end

return M
