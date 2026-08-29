-- else-if: an `else` containing one unannotated `if`, or two mutually exclusive
-- literal tests of one local, are an `elseif` chain written longhand.
local parser = require("nupp.compiler.parser")
local check = require("fragment")
local envMod = require("nupp.compiler.env")

-- One environment for the whole suite.
--
-- Every case checks against an environment built exactly this way, and
-- building one means checking the prelude from source. Per case that was
-- most of what this suite cost; the cases share it the way the other
-- checker suites do.
local sharedEnv = envMod.new(".")

local function assertEq(got, want, label)
   if got ~= want then
      error(("%s:\n  want: %s\n  got:  %s"):format(label or "mismatch",
         tostring(want), tostring(got)), 2)
   end
end

local function lint(src, opts)
   local result = parser.parse(src, "test.g.nupp")
   assertEq(#result.errors, 0, "syntax errors in test source")
   local diags = check.check(result, "test.g.nupp", sharedEnv, opts or {})
   local found = {}
   for _, diag in ipairs(diags) do
      if diag.code == "NUPP2510" then found[#found + 1] = diag end
   end
   return found
end

local function assertFlagged(src, label)
   local found = lint(src)
   assertEq(#found, 1, (label or "expected one report") .. "\n" .. src)
   assertEq(found[1].lint, "else-if", "lint name")
   return found[1]
end

local function assertQuiet(src, label)
   local found = lint(src)
   if #found ~= 0 then
      error(("%s: reported %s at line %d\n%s"):format(
         label or "expected no report", found[1].code, found[1].line, src), 2)
   end
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

local CHAIN = [[
if first then
   firstAction()
else
   if second then
      secondAction()
   else
      fallback()
   end
end
]]

local ADJACENT = [[
local c = foo[x]
if c == "a" then
   d = hi
end
if c == "b" then
   d = boo
end
]]

local M = {}

function M.flagsAnElseContainingOnlyAnIf()
   local at = assertFlagged(CHAIN)
   assertEq(at.line, 3, "reports at else")
   assertEq(at.severity, "warning", "style lints warn by default")
   assertEq(at.help, "replace else followed by if with elseif", "carries a fix direction")
end

function M.offersAMachineApplicableFix()
   local at = assertFlagged(CHAIN)
   assertEq(#(at.fixes or {}), 1, "one unambiguous rewrite")
   local fix = at.fixes[1]
   assertEq(fix.title, "write `elseif`", "names the rewrite")
   local rewritten = applyFix(CHAIN, fix)
   assert(rewritten:find("elseif%s+second then"), "joins the condition to elseif")
   assertQuiet(rewritten, "the rewritten source has no else-if lint")
end

function M.flagsAdjacentMutuallyExclusiveConditions()
   local at = assertFlagged(ADJACENT)
   assertEq(at.line, 5, "reports at the second if")
   assertEq(at.help, "replace the second if with elseif and remove the preceding end",
      "explains the adjacent rewrite")
   local rewritten = applyFix(ADJACENT, at.fixes[1])
   assert(rewritten:find("elseif%s+c == \"b\" then"), "changes the second if")
   assertQuiet(rewritten, "the rewritten source has no else-if lint")
end

function M.allowsAdjacentConditionsThatCouldBothHold()
   assertQuiet([[
local c = foo[x]
if c == "a" then first() end
if c == "a" then second() end
]], "equal tests are not mutually exclusive")
   assertQuiet([[
local c = foo[x]
if c == "a" then c = "b" end
if c == "b" then second() end
]], "the first body changes the subject")
   assertQuiet([[
if c == "a" then first() end
if c == "b" then second() end
]], "a global may be changed by other code")
end

function M.allowsAdditionalStatementsInTheElse()
   assertQuiet([[ 
if first then
   firstAction()
else
   note()
   if second then secondAction() end
end
]], "the nested if is not the whole else")
end

function M.allowsAnAnnotatedNestedIf()
   assertQuiet([[ 
if first then
   firstAction()
else
   @allow
   if second then secondAction() end
end
]], "a pragma cannot be moved onto an elseif clause")
end

function M.canBeAllowedByNameOrCode()
   assertQuiet('@allow("else-if")\n' .. CHAIN, "allowed by name")
   assertQuiet("@allow(NUPP2510)\n" .. CHAIN, "allowed by code")
   assertQuiet(ADJACENT:gsub("if c == \"a\"", '@allow("else-if")\nif c == "a"'),
      "adjacent form allowed by name")
end

function M.canBeTurnedOff()
   assertEq(#lint(CHAIN, {lints = {["else-if"] = "off"}}), 0,
      "a disabled lint says nothing")
end

return M
