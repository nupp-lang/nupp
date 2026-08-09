-- discarded-result: a call statement whose callee does nothing but return the
-- value the statement drops. The cases that matter are the ones it declines,
-- since the whole claim is that the callee was *proved* inert rather than
-- guessed at: a write, a call it could not follow, a raise, or nothing returned
-- at all is each a reason the statement might have been worth writing.

local parser = require("compiler.parser")
local check = require("compiler.check")
local envMod = require("compiler.env")

local function assertEq(got, want, label)
   if got ~= want then
      error(("%s:\n  want: %s\n  got:  %s"):format(label or "mismatch",
         tostring(want), tostring(got)), 2)
   end
end

-- This file asks for the real checker rather than the tests' fragment wrapper,
-- which turns this lint off for everything that is not about it.
local function lint(src, config)
   local result = parser.parse(src, "test.g.nupp")
   assertEq(#result.errors, 0, "syntax errors in test source")
   local found = {}
   for _, diag in ipairs(check.check(result, "test.g.nupp", envMod.new("."),
      config or {})) do
      if diag.code == "NUPP2508" then found[#found + 1] = diag end
   end
   return found
end

local function assertFlagged(src, label)
   local found = lint(src)
   assertEq(#found, 1, (label or "expected one report") .. "\n" .. src)
   assertEq(found[1].lint, "discarded-result", "lint name")
   return found[1]
end

local function assertQuiet(src, label)
   local found = lint(src)
   if #found ~= 0 then
      error(("%s: reported at line %d -- %s\n%s"):format(
         label or "expected no report", found[1].line, found[1].msg, src), 2)
   end
end

local PURE = "local function double(value: number): number\n"
   .. "   return value * 2\nend\n\n"

local M = {}

function M.flagsAPureCallWhoseResultIsDropped()
   local at = assertFlagged(PURE .. "double(21)\n\nreturn double\n")
   assertEq(at.line, 5, "reported at the statement")
   assertEq(at.severity, "warning", "suspicious lints warn by default")
   assertEq(at.msg, "double has no effects, so dropping its result leaves "
      .. "this statement doing nothing")
   assertEq(at.related and #at.related, 1, "the declaration comes with it")
   assertEq(at.related[1].line, 1, "pointing at where it was declared")
end

function M.usingTheResultIsTheWholePoint()
   assertQuiet(PURE .. "local answer = double(21)\n\nreturn answer\n",
      "the value went somewhere")
end

-- The summary is file-local, so a callee that reaches another module widens to
-- top. Everything reported is a call the compiler followed to the end.
function M.aCallItCouldNotFollowIsLeftAlone()
   assertQuiet([[
local function log(text: string): string
   print(text)
   return text
end

log("hi")

return log
]], "print is not a function this file can see through")
end

-- A summary treats a write through a non-parameter local as staying local, and
-- a local read out of a parameter is not scratch. The write check is this
-- lint's own for exactly this shape.
function M.aWriteThroughALocalReadOutOfAParameterIsAWrite()
   assertQuiet([[
local function push(target: {values: {number}}, value: number): number
   local slot = target.values
   slot[#slot + 1] = value
   return #slot
end

push({values = {}}, 1)

return push
]], "the write reaches the caller's table through a local")
end

function M.aWriteThroughAParameterIsAWrite()
   assertQuiet([[
local function put(target: {number}, value: number): number
   target[#target + 1] = value
   return #target
end

put({}, 1)

return put
]], "the parameter-rooted write is a reason to call")
end

-- A local the body allocates and never lets out is scratch, so accumulating
-- into one keeps the function inert.
function M.aScratchAccumulatorStaysInert()
   local at = assertFlagged([[
local function tally(values: {number}): number
   local sum = 0
   for _, value in ipairs(values) do
      sum = sum + value
   end
   return sum
end

tally({1, 2})

return tally
]])
   assertEq(at.line, 9, "reported at the statement")
end

function M.aRaisingCallIsLeftAlone()
   assertQuiet([[
local function require_positive(value: number): number
   if value <= 0 then error("not positive") end
   return value
end

require_positive(1)

return require_positive
]], "raising is something a call can be made for")
end

-- Returning nothing discards nothing, and `nil` is how a function spells that
-- however many results its arity claims.
function M.aFunctionThatReturnsNothingIsNotJudged()
   assertQuiet([[
local function ping(): nil end

ping()

return ping
]], "there is no result to have dropped")
   assertQuiet([[
local function ping() end

ping()

return ping
]], "nor when the signature says nothing at all")
end

function M.anAllowSilencesIt()
   assertQuiet(PURE .. '@allow("discarded-result")\ndouble(21)\n\n'
      .. "return double\n", "the statement disagreed with the judgement")
   assertQuiet(PURE .. '@allow("NUPP2508")\ndouble(21)\n\nreturn double\n',
      "and by code, which means the same lint")
end

function M.aProjectMovesItsLevel()
   local src = PURE .. "double(21)\n\nreturn double\n"
   assertEq(#lint(src, {lints = {["discarded-result"] = "off"}}), 0,
      "off is not reported")
   local raised = lint(src, {lints = {["discarded-result"] = "error"}})
   assertEq(raised[1] and raised[1].severity, "error", "raised by name")
   assertEq(#lint(src, {lints = {suspicious = "off"}}), 0, "and by category")
end

return M
