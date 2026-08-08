-- Literal types, unions of them, and interface conformance.
local parser = require("nupp.parser")
local check = require("nupp.check")
local envMod = require("nupp.env")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local env = envMod.new(HERE .. "/..")

local function assertEq(got, want, label)
   if got ~= want then
      error(("%s:\n  want: %s\n  got:  %s"):format(label or "mismatch",
         tostring(want), tostring(got)), 2)
   end
end

local function diagsOf(src)
   local result = parser.parse(src, "test")
   assertEq(#result.errors, 0, "syntax: "
      .. (result.errors[1] and result.errors[1].msg or ""))
   local out = {}
   for j, d in ipairs(check.check(result, "test", env)) do
      out[j] = d.code .. ":" .. d.line
   end
   return table.concat(out, " ")
end

local function assertClean(src)
   assertEq(diagsOf(src), "", "expected clean:\n" .. src)
end

local COLOR = "local type Color = 'red' | 'green' | 'blue'"

local M = {}

function M.literalUnionMembersAssignDirectly()
   assertClean(COLOR .. "\nlocal c: Color = 'red'")
   assertClean(COLOR .. "\nlocal c: Color = 'blue'")
   assertEq(diagsOf(COLOR .. "\nlocal c: Color = 'purple'"), "NUPP2001:2")
   -- the message names the offending value and the members it is not one of
   local result = parser.parse(COLOR .. "\nlocal c: Color = 'purple'", "t")
   local d = check.check(result, "t", env)[1]
   assert(d.msg:find('"purple"', 1, true), "names the value: " .. d.msg)
   assert(d.msg:find('"blue"', 1, true), "names the members: " .. d.msg)
end

function M.literalUnionsRemainStrings()
   assertClean(COLOR .. "\nlocal c: Color = 'red'\nlocal s: string = c")
   assertClean(COLOR .. "\nlocal f = function(c: Color): string return c end")
end

function M.literalUnionMembersFlowThroughCalls()
   assertClean(COLOR .. table.concat({
      "",
      "local function paint(c: Color): nil end",
      "paint('green')",
   }, "\n"))
   assertEq(diagsOf(COLOR .. table.concat({
      "",
      "local function paint(c: Color): nil end",
      "paint('mauve')",
   }, "\n")), "NUPP2006:3")
end

function M.literalsAreStringsButInferredBindingsWiden()
   assertClean("local s: string = 'text'")
   -- an inferred binding holds a string, not that one string
   assertClean("local s = 'a'\ns = 'b'")
   -- an annotated literal type keeps its exact value
   assertEq(diagsOf(COLOR .. "\nlocal c: Color = 'red'\nc = 'purple'"),
      "NUPP2001:3")
end

function M.literalsStillConvertAtTheCBoundary()
   assertClean("cdef function strlen(s: cstring): uint64\nstrlen('hi')")
end

local SHAPE = table.concat({
   "local interface Shape",
   "    area: function(self: Shape): number",
   "end",
}, "\n")

local CIRCLE = table.concat({
   "local record Circle",
   "    r: number",
   "end",
   "function Circle:area(): number",
   "    return 3 * self.r * self.r",
   "end",
}, "\n")

function M.interfacesConformStructurally()
   -- no `implements` clause: carrying the members is enough
   assertClean(SHAPE .. "\n" .. CIRCLE .. "\nlocal s: Shape = Circle{r = 1}")
end

function M.interfaceConformanceIsChecked()
   local wrongShape = table.concat({
      "local record Square",
      "    side: number",
      "end",
   }, "\n")
   local d = diagsOf(SHAPE .. "\n" .. wrongShape
      .. "\nlocal s: Shape = Square{side = 1}")
   assertEq(d, "NUPP2001:7")
   -- a member with the wrong type is caught too
   local badArea = table.concat({
      "local record Blob",
      "    n: number",
      "end",
      "function Blob:area(): string",
      "    return 'nope'",
      "end",
   }, "\n")
   assertEq(diagsOf(SHAPE .. "\n" .. badArea
      .. "\nlocal s: Shape = Blob{n = 1}"), "NUPP2001:10")
end

function M.interfacesAcceptPlainShapes()
   assertClean(table.concat({
      "local interface Named",
      "    name: string",
      "end",
      "local n: Named = {name = 'x'}",
   }, "\n"))
   assertEq(diagsOf(table.concat({
      "local interface Named",
      "    name: string",
      "end",
      "local n: Named = {name = 1}",
   }, "\n")), "NUPP2001:4")
end

function M.strictModeReportsUnknownNames()
   local src = "print(undefinedThing)\nlocal x = 1\nprint(x)"
   -- gradual by default: unknown names are `any` and check silently
   assertClean(src)
   -- under --strict they are errors, while known names stay quiet
   local result = parser.parse(src, "test")
   local diags = check.check(result, "test", env, {strict = true})
   assertEq(#diags, 1, "one unknown name")
   assertEq(diags[1].code, "NUPP2105")
   assert(diags[1].msg:find("undefinedThing", 1, true),
      "names the variable: " .. diags[1].msg)
end

function M.strictModeAcceptsDeclaredAndStdlibNames()
   local result = parser.parse(table.concat({
      "local n = 1",
      "local function f(): number return n end",
      "print(f(), string.format('%d', 1), math.floor(2.5))",
   }, "\n"), "test")
   local diags = check.check(result, "test", env, {strict = true})
   assertEq(#diags, 0, "declared locals and the stdlib are known: "
      .. (diags[1] and diags[1].msg or ""))
end

local BOX = table.concat({
   "local record Box<T>",
   "    value: T",
   "end",
}, "\n")

function M.genericDeclarationsBindTheirParameters()
   assertClean(BOX)
   assertClean("local record Pair<K, V>\n    key: K\n    value: V\nend")
end

function M.typeArgumentsSubstituteIntoFields()
   assertClean(BOX .. "\nlocal b: Box<number>\nlocal n: number = b.value")
   assertEq(diagsOf(BOX .. "\nlocal b: Box<number>\nlocal s: string = b.value"),
      "NUPP2001:5")
   assertClean(BOX .. "\nlocal b: Box<string>\nlocal s: string = b.value")
end

function M.differentArgumentsAreDifferentTypes()
   assertEq(diagsOf(BOX .. table.concat({
      "",
      "local n: Box<number>",
      "local s: Box<string> = n",
   }, "\n")), "NUPP2001:5")
   -- and the message distinguishes them
   local result = parser.parse(BOX .. "\nlocal n: Box<number>\nlocal s: Box<string> = n", "t")
   local d = check.check(result, "t", env)[1]
   assert(d.msg:find("Box<number>", 1, true), "renders arguments: " .. d.msg)
end

function M.constructionInfersTheArgument()
   assertClean(BOX .. "\nlocal b: Box<number> = Box{value = 1}")
   assertClean(BOX .. "\nlocal b: Box<string> = Box{value = 'x'}")
   assertEq(diagsOf(BOX .. "\nlocal b: Box<string> = Box{value = 1}"),
      "NUPP2001:4")
end

function M.typeArgumentsVaryCovariantly()
   -- an integer box is a number box, as integer is a number
   assertClean(BOX .. "\nlocal b: Box<number> = Box{value = 1}")
end

return M
