local parser = require("nupp.compiler.parser")
local check = require("fragment")
local envMod = require("nupp.compiler.env")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local env = envMod.new(HERE .. "/..")

local function assertEq(got, want, label)
   if got ~= want then
      error(("%s:\n  want: %s\n  got:  %s"):format(label or "mismatch",
         tostring(want), tostring(got)), 2)
   end
end

local function codes(source)
   env.loaded = {}
   local parsed = parser.parse(source, "test.g.nupp")
   assertEq(#parsed.errors, 0, "syntax: "
      .. (parsed.errors[1] and parsed.errors[1].msg or ""))
   local out = {}
   for j, diagnostic in ipairs(check.check(parsed, "test.g.nupp", env)) do
      out[j] = diagnostic.code
   end
   return table.concat(out, " ")
end

local function clean(source)
   assertEq(codes(source), "", "expected clean check for:\n" .. source)
end

local function reports(source, want)
   assertEq(codes(source), want, "for:\n" .. source)
end

local READER = table.concat({
   "local interface Reader",
   "   associated type Item",
   "   associated type Error = string",
   "end",
}, "\n") .. "\n"

local M = {}

function M.anAnswerIsReachableByPath()
   clean(READER .. table.concat({
      "local record Lines is Reader",
      "   associated type Item = string",
      "end",
      "local line: Lines.Item = 'text'",
      "return line",
   }, "\n") .. "\n")
end

function M.anAnswerIsTheTypeItNamed()
   reports(READER .. table.concat({
      "local record Lines is Reader",
      "   associated type Item = string",
      "end",
      "local line: Lines.Item = 42",
      "return line",
   }, "\n") .. "\n", "NUPP2001")
end

function M.aDefaultAnswersWithoutBeingWritten()
   clean(READER .. table.concat({
      "local record Lines is Reader",
      "   associated type Item = string",
      "end",
      "local failure: Lines.Error = 'why'",
      "return failure",
   }, "\n") .. "\n")
end

function M.aDefaultIsReplacedByAnswering()
   clean(READER .. table.concat({
      "local record Lines is Reader",
      "   associated type Item = string",
      "   associated type Error = integer",
      "end",
      "local failure: Lines.Error = 17",
      "return failure",
   }, "\n") .. "\n")
end

function M.anUnansweredRequirementReports()
   reports(READER .. table.concat({
      "local record Lines is Reader",
      "end",
      "return Lines",
   }, "\n") .. "\n", "NUPP2127")
end

function M.answeringNoContractReports()
   reports(table.concat({
      "local record Box",
      "   associated type Item = string",
      "end",
      "return Box",
   }, "\n") .. "\n", "NUPP2131")
end

function M.statingARequirementOutsideAnInterfaceReports()
   reports(table.concat({
      "local record Box",
      "   associated type Item",
      "end",
      "return Box",
   }, "\n") .. "\n", "NUPP2131")
end

function M.anAnswerHasToFitItsBound()
   reports(table.concat({
      "local interface Named",
      "   name: string",
      "end",
      "local interface Tagged",
      "   associated type Tag is Named",
      "end",
      "local record Bad is Tagged",
      "   associated type Tag = integer",
      "end",
      "return Bad",
   }, "\n") .. "\n", "NUPP2116")
end

-- An interface taking another's contract restates its requirements rather than
-- answering them, so only the implementor is held to them -- once, not twice.
function M.aRequirementIsInheritedThroughAnInterfaceChain()
   clean(READER .. table.concat({
      "local interface Buffered is Reader",
      "end",
      "local record Fast is Buffered",
      "   associated type Item = string",
      "end",
      "return Fast",
   }, "\n") .. "\n")
   reports(READER .. table.concat({
      "local interface Buffered is Reader",
      "end",
      "local record Slow is Buffered",
      "end",
      "return Slow",
   }, "\n") .. "\n", "NUPP2127")
end

-- The distinction the word exists for. A nested alias is lexically scoped and
-- reachable by path, and taking the contract does not take it.
function M.aNestedAliasIsNotInherited()
   clean(table.concat({
      "local interface Shape",
      "   type Unit = number",
      "   size: Unit",
      "end",
      "local unit: Shape.Unit = 2",
      "return unit",
   }, "\n") .. "\n")
   reports(table.concat({
      "local interface Shape",
      "   type Unit = number",
      "end",
      "local record Circle is Shape",
      "   radius: Unit",
      "end",
      "return Circle",
   }, "\n") .. "\n", "NUPP2101")
end

-- `associated` is contextual on the same rule as the rest of the added words.
function M.associatedIsStillAnOrdinaryFieldName()
   clean(table.concat({
      "local record Row",
      "   associated: boolean",
      "   type: string",
      "end",
      "local row = new Row {associated = true, type = 'x'}",
      "return row",
   }, "\n") .. "\n")
end

return M
