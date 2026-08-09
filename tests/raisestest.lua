-- `@raises`, and the lint that asks a documented function to write one.

local parser = require("nupp.parser")
local check = require("fragment")
local envMod = require("nupp.env")
local docblock = require("nupp.docblock")

local function assertEq(got, want, label)
   if got ~= want then
      error(("%s:\n  want: %s\n  got:  %s"):format(label or "mismatch",
         tostring(want), tostring(got)), 2)
   end
end

-- Every NUPP2506 the source produces.
local function lint(src, config)
   local result = parser.parse(src, "test.g.nupp")
   assertEq(#result.errors, 0, "syntax errors in test source")
   local diags = check.check(result, "test.g.nupp", envMod.new("."), config or {})
   local found = {}
   for _, diag in ipairs(diags) do
      if diag.code == "NUPP2506" then found[#found + 1] = diag end
   end
   return found
end

local function assertFlagged(src, label)
   local found = lint(src)
   assertEq(#found, 1, (label or "expected one report") .. "\n" .. src)
   assertEq(found[1].lint, "undocumented-raise", "lint name")
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

function M.flagsADocumentedFunctionThatRaises()
   local at = assertFlagged([[
--- Reads a file.
--- @param path where to read from
local function load(path)
   if not path then error("no path") end
   return path
end
]])
   assertEq(at.line, 3, "reported at the declaration")
   assertEq(at.severity, "warning", "suspicious lints warn by default")
end

function M.pointsAtTheRaise()
   local at = assertFlagged([[
--- Reads a file.
local function load(path)
   if not path then error("no path") end
   return path
end
]])
   assertEq(#at.related, 1, "the raise is a related location")
   assertEq(at.related[1].line, 3, "which is where the error call is")
   assertEq(at.related[1].message, "raises here", "labelled")
end

function M.namesTheMemberRatherThanItsTable()
   local at = assertFlagged([[
local m = {}
--- Gets one.
function m.Q:get(name)
   error("unknown query")
end
]])
   assertEq(at.col, 14, "reported at `get`, not at `m`")
   assertEq(at.msg:match("^(%S+)"), "m.Q:get", "named by its whole path")
end

function M.isQuietWhenTheRaiseIsDocumented()
   assertQuiet([[
--- Reads a file.
--- @raises when the path is missing
local function load(path)
   if not path then error("no path") end
   return path
end
]], "a documented raise is what the lint asks for")
end

-- The lint judges a promise, and a function that says nothing has made none. Asking
-- every function in a gradually typed language for a docblock would be a different
-- lint with a different name.
function M.isQuietWithoutADocblock()
   assertQuiet([[
local function load(path)
   if not path then error("no path") end
   return path
end
]], "an undocumented function has promised nothing")
end

function M.ignoresAnOrdinaryComment()
   assertQuiet([[
-- Reads a file.
local function load(path)
   if not path then error("no path") end
end
]], "only a `---` run is documentation")
end

-- A raise inside a callback belongs to the callback. This is also what keeps a
-- function that hands a raising body to `pcall` from being asked to document it.
function M.doesNotReachIntoANestedFunction()
   assertQuiet([[
--- Runs one.
local function attempt(f)
   return pcall(function() error("inner") end)
end
]], "a nested function's raises are its own")
end

function M.doesNotReachIntoAShortFunction()
   assertQuiet([[
--- Runs one.
local function attempt(xs)
   return map(xs, |x| -> error("inner"))
end
]], "a short function is a function")
end

-- `assert` means both "the caller passed the wrong thing" and "this cannot happen",
-- and the call does not say which. Reading the second as a documented raise would ask
-- for a promise about something that never occurs.
function M.doesNotCountAssert()
   assertQuiet([[
--- Reads a digest.
local function digest(hex)
   assert(#hex == 64, "a digest is 32 bytes")
   return hex
end
]], "assert is not a documented raise")
end

function M.findsARaiseInsideControlFlow()
   assertFlagged([[
--- Reads a file.
local function load(path)
   for _, p in ipairs(path) do
      if not p then
         error("no path")
      end
   end
end
]], "a raise nested in blocks is still this function's")
end

function M.flagsANamedFunction()
   assertFlagged([[
local m = {}
--- Reads a file.
function m.load(path)
   error("no path")
end
]])
end

function M.flagsAnInlineMethod()
   assertFlagged([[
record R
   --- Reads a file.
   function load(self)
      error("no path")
   end
end
]], "an inline method documents like the function it is")
end

function M.canBeAllowed()
   assertQuiet([[
--- Reads a file.
@allow("undocumented-raise")
local function load(path)
   error("no path")
end
]], "a lint is a judgement a statement may disagree with")
end

function M.canBeAllowedByCode()
   assertQuiet([[
--- Reads a file.
@allow("NUPP2506")
local function load(path)
   error("no path")
end
]], "either spelling reaches the lint")
end

function M.canBeTurnedOff()
   local found = lint([[
--- Reads a file.
local function load(path)
   error("no path")
end
]], {lints = {["undocumented-raise"] = "off"}})
   assertEq(#found, 0, "a lint set to off says nothing")
end

-- The tag itself, which `nupp doc` renders and the lint reads.

function M.parsesOneRaises()
   local doc = docblock.parse({"Reads a file.", "@raises when the path is missing"})
   assertEq(#doc.raises, 1, "one condition")
   assertEq(doc.raises[1], "when the path is missing", "its text")
   assertEq(doc.text, "Reads a file.", "the prose keeps the rest")
end

function M.parsesSeveralRaises()
   local doc = docblock.parse({
      "@raises when the path is missing",
      "@raises when the file cannot be read",
   })
   assertEq(#doc.raises, 2, "one entry per occurrence, unlike @param")
   assertEq(doc.raises[2], "when the file cannot be read", "in the order written")
end

function M.wrapsARaisesDescription()
   local doc = docblock.parse({
      "@raises when the path is missing,",
      "    which a caller cannot always tell in advance",
   })
   assertEq(#doc.raises, 1, "a continuation joins rather than starting a second")
   assertEq(doc.raises[1],
      "when the path is missing, which a caller cannot always tell in advance",
      "joined with a single space")
end

function M.keepsRaisesApartFromReturns()
   local doc = docblock.parse({
      "@return the contents",
      "@raises when the path is missing",
   })
   assertEq(#doc.returns, 1, "the return is its own list")
   assertEq(#doc.raises, 1, "and so is the raise")
   assertEq(doc.returns[1], "the contents", "neither collected the other")
end

return M
