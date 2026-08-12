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
      "    local now = os.time()",
      "    print(n, s, t, b, now)",
      "end",
   }, "\n"))
   assertEq(#refusals, 1, "only the unannotated one is refused")
   assertTrue(refusals[1].msg:find("time", 1, true) ~= nil,
      "and it is `os.time`, which says nothing about its effects: " .. refusals[1].msg)
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
   local concrete = generics.materialize(safe, {[tv] = T.string})
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

local function runGenerated(src)
   local _, diags, result = diagnose(src)
   for _, diag in ipairs(diags) do
      assertTrue(diag.severity == "warning" or diag.severity == "note",
         "source checks before execution: " .. diag.code .. " " .. diag.msg)
   end
   local code = gen.generate(result, "test")
   local chunk, problem = loadstring(code, "@handled-exit")
   assertTrue(chunk ~= nil, "generated Lua loads: " .. tostring(problem) .. "\n" .. code)
   return chunk()
end

function M.aReturnLeavesAHandleRegionAfterReleasingIt()
   local first, second, released = runGenerated(table.concat({
      "local released: integer = 0",
      "local h = {shutdown = function() released = released + 1 end}",
      "local function f(): integer, integer",
      "    handle suspension with h do",
      "        return 1, released",
      "    end",
      "end",
      "local answer, beforeRelease = f()",
      "return answer, beforeRelease, released",
   }, "\n"))
   assertEq(first, 1, "the first return survives the protected boundary")
   assertEq(second, 0, "return values are evaluated before release")
   assertEq(released, 1, "the installation is released exactly once")
end

function M.aBodyAndReleaseFailureAreBothPreserved()
   local ok, problem = runGenerated(table.concat({
      "local h = {shutdown = function() error('release failed') end}",
      "local ok, problem = pcall(function()",
      "    handle suspension with h do",
      "        error('body failed')",
      "    end",
      "end)",
      "return ok, tostring(problem)",
   }, "\n"))
   assertEq(ok, false, "the handled body still raises")
   assertTrue(problem:find("body failed", 1, true) ~= nil,
      "the body failure remains primary: " .. problem)
   assertTrue(problem:find("release failed", 1, true) ~= nil,
      "the release failure is retained: " .. problem)
end

function M.loopControlCanLeaveAHandleRegion()
   local continued, broken = runGenerated(table.concat({
      "local h = {}",
      "local total = 0",
      "for index = 1, 3 do",
      "    handle suspension with h do",
      "        if index == 2 then continue end",
      "        total = total + index",
      "    end",
      "end",
      "while true do",
      "    handle suspension with h do",
      "        break",
      "    end",
      "end",
      "return total, true",
   }, "\n"))
   assertEq(continued, 4, "continue reaches the enclosing loop")
   assertEq(broken, true, "break reaches the enclosing loop")
end

function M.aGotoCanLeaveAHandleRegion()
   local answer = runGenerated(table.concat({
      "local h = {}",
      "local answer = 0",
      "handle suspension with h do",
      "    answer = 1",
      "    goto done",
      "end",
      "answer = 2",
      "::done::",
      "return answer",
   }, "\n"))
   assertEq(answer, 1, "goto resumes outside after releasing the installation")
end

function M.refusesAGotoIntoAHandleRegion()
   local _, diags = diagnose(table.concat({
      "local h = {}",
      "goto inside",
      "handle suspension with h do",
      "    ::inside::",
      "end",
   }, "\n"))
   local found = 0
   for _, diag in ipairs(diags) do
      if diag.code == "NUPP2706" then found = found + 1 end
   end
   assertEq(found, 1, "one diagnostic refuses the impossible incoming edge")
end

function M.aHandleRegionRequiresAHandler()
   local _, diags = diagnose("handle suspension with 42 do\nend")
   local found = false
   for _, diag in ipairs(diags) do
      if diag.code == "NUPP2001" and diag.msg:find("handler", 1, true) then
         found = true
      end
   end
   assertTrue(found, "a concrete non-handler is rejected at the construct")
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

function M.refusesASuspendingSortComparator()
   -- The boundary belongs to the invocation: `table.sort` has a C frame on the stack
   -- while the comparator runs, so the comparator cannot yield.
   local _, diags = diagnose(table.concat({
      "local function noisy(): nil",
      "    coroutine.yield()",
      "end",
      "local t = {3, 1, 2}",
      "table.sort(t, function(a: integer, b: integer): boolean",
      "    noisy()",
      "    return a < b",
      "end)",
      "return t",
   }, "\n"))
   local found = nil
   for _, diag in ipairs(diags) do
      if diag.code == "NUPP2702" then found = diag end
   end
   assertTrue(found ~= nil, "the comparator is refused")
   assertTrue(found.msg:find("table.sort", 1, true) ~= nil,
      "and it names what reaches it: " .. found.msg)
end

function M.refusesASuspendingGsubReplacement()
   local _, diags = diagnose(table.concat({
      "local function noisy(): string",
      "    coroutine.yield()",
      "    return 'x'",
      "end",
      "local out = string.gsub('aaa', 'a', function(): string",
      "    return noisy()",
      "end)",
      "return out",
   }, "\n"))
   local found = nil
   for _, diag in ipairs(diags) do
      if diag.code == "NUPP2702" then found = diag end
   end
   assertTrue(found ~= nil, "the replacement is refused")
   assertTrue(found.msg:find("string.gsub", 1, true) ~= nil,
      "and names the call: " .. found.msg)
end

function M.allowsAQuietComparator()
   local _, diags = diagnose(table.concat({
      "local t = {3, 1, 2}",
      "table.sort(t, function(a: integer, b: integer): boolean",
      "    return tostring(a) < tostring(b)",
      "end)",
      "return t",
   }, "\n"))
   for _, diag in ipairs(diags) do
      assertTrue(diag.code ~= "NUPP2702",
         "a comparator that cannot suspend is left alone: " .. diag.msg)
   end
end

function M.doesNotMistakeALocalNamedTableForThePrelude()
   -- Definition identity, never spelling.
   local _, diags = diagnose(table.concat({
      "local function noisy(): nil",
      "    coroutine.yield()",
      "end",
      "local tbl = {sort = function(_t: {integer}, fn: function(): nil): nil",
      "    fn()",
      "end}",
      "tbl.sort({1}, function(): nil",
      "    noisy()",
      "end)",
      "return tbl",
   }, "\n"))
   for _, diag in ipairs(diags) do
      assertTrue(diag.code ~= "NUPP2702",
         "somebody else's sort is not the prelude's: " .. diag.msg)
   end
end

function M.aMetamethodIsNotARegionByItself()
   -- The boundary is the invocation, not the kind of body. An ordinary metamethod may
   -- yield on this baseline, so declaring one is not a reason to refuse anything.
   local _, diags = diagnose(table.concat({
      "local function noisy(): nil",
      "    coroutine.yield()",
      "end",
      "local record Thing",
      "    n: integer",
      "end",
      "function Thing.__tostring(_self: Thing): string",
      "    noisy()",
      "    return 'thing'",
      "end",
      "return Thing",
   }, "\n"))
   for _, diag in ipairs(diags) do
      assertTrue(diag.code ~= "NUPP2702",
         "a metamethod is not implicitly a region: " .. diag.msg)
   end
end

return M
