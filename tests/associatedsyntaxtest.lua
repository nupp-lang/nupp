-- The `associated type` surface: parsing, round-tripping, formatting, erasure.
--
-- What an occurrence means -- stating a requirement or answering one -- is not the
-- parser's to decide, so nothing here asserts it. These are the shapes only.
local parser = require("nupp.compiler.parser")
local cst = require("nupp.compiler.cst")
local fmt = require("nupp.compiler.fmt")
local gen = require("nupp.compiler.gen")
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

local function parse(src)
   local result = parser.parse(src, "test.g.nupp")
   return result
end

local function roundtrip(src)
   local result = parse(src)
   assertEq(#result.errors, 0, "parse errors: "
      .. (result.errors[1] and result.errors[1].msg or ""))
   assertEq(cst.textOf(result.root), src, "round trip")
   return result
end

-- Every entry of the declaration, by kind, so a test can say what the body holds.
local function entryKinds(src)
   local result = roundtrip(src)
   local decl
   for _, stat in ipairs(result.root.blocks[1].stats) do
      if stat.kind == "recordDecl" then
         decl = stat
      end
   end
   assert(decl, "no declaration parsed")
   local kinds = {}
   for j, e in ipairs(decl.entries) do
      kinds[j] = e.kind
   end
   return table.concat(kinds, " "), decl
end

local M = {}

function M.everyFormParsesAndRoundTrips()
   local kinds = entryKinds(table.concat({
      "local interface Reader",
      "    associated type Item",
      "    associated type Chunk is Named",
      "    associated type Error = string",
      "    associated type Tag is Named = Label",
      "end",
      "return Reader",
   }, "\n") .. "\n")
   assertEq(kinds, "associatedDecl associatedDecl associatedDecl associatedDecl")
end

function M.theBoundAndTheValueAreBothRecorded()
   local _, decl = entryKinds(table.concat({
      "local interface Reader",
      "    associated type Tag is Named = Label",
      "end",
      "return Reader",
   }, "\n") .. "\n")
   local entry = decl.entries[1]
   assertEq(entry.name.text, "Tag")
   assert(entry.bound, "the bound was dropped")
   assert(entry.value, "the value was dropped")
   -- `textOf` carries a node's leading trivia, so the spacing is part of it.
   assertEq((cst.textOf(entry.bound):gsub("^%s+", "")), "Named")
   assertEq((cst.textOf(entry.value):gsub("^%s+", "")), "Label")
end

-- Contextual, on the same rule as the rest of the added words.
function M.aFieldMayStillBeCalledAssociatedOrType()
   local kinds = entryKinds(table.concat({
      "local record Row",
      "    associated: boolean",
      "    type: string",
      "end",
      "return Row",
   }, "\n") .. "\n")
   assertEq(kinds, "fieldDecl fieldDecl")
end

-- `type` has to sit on the introducer's own line, or a field named `type` following
-- a field named `associated` would be swallowed.
function M.aNewlineBetweenTheWordsIsNotTheConstruct()
   local kinds = entryKinds(table.concat({
      "local record Row",
      "    associated: boolean",
      "    type: string",
      "    other: integer",
      "end",
      "return Row",
   }, "\n") .. "\n")
   assertEq(kinds, "fieldDecl fieldDecl fieldDecl")
end

function M.nestedGenericBoundsAndValuesClose()
   roundtrip(table.concat({
      "local interface Holder",
      "    associated type Item is Box<Box<integer>>",
      "    associated type Held = Box<Box<Box<string>>>",
      "end",
      "return Holder",
   }, "\n") .. "\n")
end

-- Recovery: a broken member must not eat the ones after it.
function M.aMalformedMemberDoesNotSwallowTheRest()
   local result = parse(table.concat({
      "local interface Reader",
      "    associated type",
      "    count: integer",
      "    name: string",
      "end",
      "return Reader",
   }, "\n") .. "\n")
   assert(#result.errors > 0, "a nameless requirement parsed cleanly")
   local decl
   for _, stat in ipairs(result.root.blocks[1].stats) do
      if stat.kind == "recordDecl" then
         decl = stat
      end
   end
   local fields = 0
   for _, e in ipairs(decl.entries) do
      if e.kind == "fieldDecl" then
         fields = fields + 1
      end
   end
   assertEq(fields, 2, "the members after the broken one were swallowed")
end

function M.commentsAndAnnotationsSurvive()
   roundtrip(table.concat({
      "local interface Reader",
      "    --- What it reads.",
      "    associated type Item",
      "",
      "    -- a trailing note",
      "    associated type Error = string",
      "end",
      "return Reader",
   }, "\n") .. "\n")
end

function M.formattingIsCanonicalAndIdempotent()
   local ugly = table.concat({
      "local interface Reader",
      "    associated   type   Tag   is   Named   =   Label",
      "end",
      "return Reader",
   }, "\n") .. "\n"
   local formatted, errors = fmt.format(ugly, "test.g.nupp")
   assertEq(#errors, 0, "formatting reported: "
      .. (errors[1] and errors[1].msg or ""))
   assert(formatted:find("associated type Tag is Named = Label", 1, true),
      "not canonically spaced:\n" .. formatted)
   local again = fmt.format(formatted, "test.g.nupp")
   assertEq(again, formatted, "formatting is not idempotent")
end

-- Erasure. An associated declaration is a fact for the checker and nothing at all at
-- run time, so the generated Lua has to be what the same program without them
-- generates -- byte for byte, not merely equivalent.
function M.associatedDeclarationsEraseCompletely()
   local function generate(src)
      local result = parser.parse(src, "test.g.nupp")
      assertEq(#result.errors, 0, "syntax errors: "
         .. (result.errors[1] and result.errors[1].msg or ""))
      env.loaded = {}
      check.check(result, "test.g.nupp", env)
      local code, genDiags = gen.generate(result, "test")
      assertEq(#genDiags, 0, "gen diagnostics")
      return code
   end

   local lines = {
      "local interface Reader",
      "    associated type Item",
      "    associated type Error = string",
      "    count: integer",
      "end",
      "",
      "local record Lines is Reader",
      "    associated type Item = string",
      "    count: integer",
      "end",
      "",
      "return Lines",
   }
   -- The control keeps every other line where it was, because generated Lua follows
   -- its source's lines: removing them outright would compare two different layouts
   -- and prove nothing about erasure.
   local blanked = {}
   for j, line in ipairs(lines) do
      blanked[j] = line:find("associated type", 1, true) and "" or line
   end
   local withThem = generate(table.concat(lines, "\n") .. "\n")
   local without = generate(table.concat(blanked, "\n") .. "\n")

   assertEq(withThem, without, "an associated declaration reached the output")
end

return M
