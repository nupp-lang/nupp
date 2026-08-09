-- else-if: an `else` containing one unannotated `if` is an `elseif` written
-- longhand. The check is syntactic, so it neither changes nor depends on flow.
local parser = require("nupp.parser")
local check = require("fragment")
local envMod = require("nupp.env")

local function assertEq(got, want, label)
   if got ~= want then
      error(("%s:\n  want: %s\n  got:  %s"):format(label or "mismatch",
         tostring(want), tostring(got)), 2)
   end
end

local function lint(src, opts)
   local result = parser.parse(src, "test.g.nupp")
   assertEq(#result.errors, 0, "syntax errors in test source")
   local diags = check.check(result, "test.g.nupp", envMod.new("."), opts or {})
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
end

function M.canBeTurnedOff()
   assertEq(#lint(CHAIN, {lints = {["else-if"] = "off"}}), 0,
      "a disabled lint says nothing")
end

return M
