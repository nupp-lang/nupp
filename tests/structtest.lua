local parser = require("nupp.compiler.parser")
local check = require("fragment")
local gen = require("nupp.compiler.gen")

local function assertEq(got, want, label)
   if got ~= want then
      error(("%s:\n  want: %s\n  got:  %s"):format(label or "mismatch",
         tostring(want), tostring(got)), 2)
   end
end

-- Full pipeline: parse, check (for reified hints), generate.
local function compile(src)
   local result = parser.parse(src, "test.g.nupp")
   assertEq(#result.errors, 0, "syntax errors")
   local diags = check.check(result, "test.g.nupp")
   local code, genDiags = gen.generate(result, "test")
   return code, diags, genDiags
end

local function diagsOf(src)
   local _, diags = compile(src)
   local out = {}
   for j, d in ipairs(diags) do out[j] = d.code .. ":" .. d.line end
   return table.concat(out, " "), diags
end

local function assertClean(src)
   local got, diags = diagsOf(src)
   assertEq(got, "", "expected clean check:\n" .. src
      .. ((diags and diags[1]) and ("\nfirst: " .. diags[1].msg) or ""))
end

-- Compile a clean program and execute it.
local function run(src)
   local code, diags, genDiags = compile(src)
   assertEq(#diags, 0, "check diagnostics"
      .. (diags[1] and (": " .. diags[1].msg) or ""))
   assertEq(#genDiags, 0, "gen diagnostics")
   local chunk, err = loadstring(code, "@struct_test")
   if not chunk then
      error("generated code does not load: " .. tostring(err)
         .. "\n---\n" .. code, 2)
   end
   return chunk()
end

local VEC = "local struct Vec2\n   x: float\n   y: float\nend\n"

local M = {}

function M.groupedFieldsRejected()
   -- every field states its own type; "x, y: float" is not grammar
   local result = require("nupp.compiler.parser").parse(
      "local struct V\n   x, y: float\nend", "test")
   assert(#result.errors > 0, "grouped fields must be a syntax error")
   assert(result.errors[1].msg:find("own explicit type", 1, true),
      "targeted message: " .. result.errors[1].msg)
end

function M.fieldValidation()
   assertClean("local struct S\n   a: number\n   b: int64\n   c: boolean\nend")
   assertEq((diagsOf("local struct S\n   name: string\nend")), "NUPP2201:2")
   assertEq((diagsOf("local struct S\n   t: {number}\nend")), "NUPP2201:2")
   assertEq((diagsOf("local struct S\n   f: function(): nil\nend")), "NUPP2201:2")
   assertEq((diagsOf("local struct S\n   o: number?\nend")), "NUPP2201:2")
   -- structs by value and (nullable) pointers are fine
   assertClean(VEC .. "local struct Body\n   pos: Vec2\n   vel: Vec2\nend")
   assertClean(VEC .. "local struct Node\n   v: number\n   next: Node*?\nend")
   -- no nested declarations inside struct bodies
   assertEq((diagsOf(
      "local struct S\n   record R\n      x: number\n   end\nend")), "NUPP2201:2")
end

function M.constructionChecking()
   assertClean(VEC .. "local v = new Vec2(1, 2)")
   assertClean(VEC .. "local v = new Vec2()")
   assertEq((diagsOf(VEC .. "local v = new Vec2 {x = 1, y = 2}")), "NUPP2202:5")
   assertEq((diagsOf(VEC .. "local v = new Vec2(x = 1, y = 2)")), "NUPP2202:5 NUPP2202:5")
   assertEq((diagsOf(VEC .. "local v = new Vec2('no')")), "NUPP2202:5")
   assertEq((diagsOf(VEC .. "local v = new Vec2(1, 2, 3)")), "NUPP2202:5")
   assertEq((diagsOf(VEC .. "local v = new Vec2('a', 2)")), "NUPP2202:5")
   -- the instance types as the nominal
   assertClean(VEC .. "local v: Vec2 = new Vec2(1, 2)")
   assertEq((diagsOf(VEC .. "local n: number = new Vec2(1)")), "NUPP2001:5")
end

function M.runtimeStructSemantics()
   assertEq(run(VEC .. [[
local v = new Vec2(3, 4)
v.x = v.x + 1
return v.x + v.y]]), 8)
   -- positional construction
   assertEq(run(VEC .. "local v = new Vec2(3, 4)\nreturn v.y"), 4)
   -- float storage really is float-width (not a Lua table)
   assertEq(run(VEC .. [[
local v = new Vec2(0.1, 0)
return v.x == 0.1]]), false) -- 0.1 is not representable in float32
end

function M.structConstructionUsesTrailingFieldDefaults()
   local src = table.concat({
      "local struct Vec2",
      "   x: float = 3",
      "   y: float = 4",
      "end",
      "local origin = new Vec2()",
      "local moved = new Vec2(10)",
      "return origin.x + origin.y + moved.x + moved.y",
   }, "\n")
   assertEq(run(src), 21)
end

function M.generatedStructBindingsAreConst()
   local code, diags, genDiags = compile(VEC .. "return Vec2")
   assertEq(#diags, 0, "check diagnostics")
   assertEq(#genDiags, 0, "gen diagnostics")
   assert(code:find("const __nuppMt_Vec2", 1, true), code)
   assert(code:find("const Vec2 = __nuppFfi.metatype", 1, true), code)
   assert(code:find('const __nuppFfi = require("ffi")', 1, true), code)
end

function M.inlineStructMethodsUseTheFfiMetatypeNamespace()
   assertEq(run(table.concat({
      "local struct Vec",
      "   x: float",
      "   function doubled(): number",
      "      return self.x * 2",
      "   end",
      "end",
      "local v = new Vec(21)",
      "return v:doubled()",
   }, "\n")), 42)
   assertEq((diagsOf(table.concat({
      "local struct Vec",
      "   x: float",
      "   metamethod __add: function(self, other: self): self",
      "end",
   }, "\n"))), "NUPP2118:3")
end

function M.methodsOnADottedStructAttachToItsMetatable()
   -- The metatable local is named by the struct's own name; a method declared on
   -- the dotted path has to reach the same local rather than a global spelled
   -- with the path's first component.
   local m, len = run(table.concat({
      "local m = {}",
      "struct m.Vec",
      "   x: number",
      "   y: number",
      "end",
      "function m.Vec:len(): number",
      "   return self.x + self.y",
      "end",
      "local v = new m.Vec(1, 2)",
      "return m, v:len()",
   }, "\n"))
   assert(type(m) == "table", "the dotted owner is the authored table")
   assertEq(len, 3)
end

-- A struct binding used to construct one where it was declared, which was a
-- construction the source did not say. Now it holds nil until something puts a
-- value in it, and reading it before that is reported rather than silently
-- given a zeroed struct.
function M.aStructBindingHoldsNothingUntilAssigned()
   assertEq((diagsOf(VEC .. "local v: Vec2\nreturn v.x + v.y")), "NUPP2207:6")
   assertEq(run(VEC .. "local v = new Vec2()\nreturn v.x + v.y"), 0)
   -- assigning first is the whole of what it asks for
   assertEq(run(VEC .. "local v: Vec2\nv = new Vec2(3, 4)\nreturn v.x + v.y"), 7)
   -- explicitly initializing a struct binding with nil is a type error
   -- (struct bindings are never nil; use Vec2? if nil is meaningful)
   assertEq((diagsOf(VEC .. "local v: Vec2 = nil")), "NUPP2001:5")
   assertClean(VEC .. "local v: Vec2? = nil")
end

function M.referenceSemantics()
   assertEq(run(VEC .. [[
local function bump(v: Vec2)
   v.x = v.x + 10
end
local v = new Vec2(1, 0)
bump(v)
return v.x]]), 11)
end

function M.nestedStructsByValue()
   assertEq(run(VEC .. [[
local struct Body
   pos: Vec2
   vel: Vec2
end
local b = new Body()
b.pos.x = 5
b.vel = new Vec2(1, 2)
return b.pos.x + b.vel.y]]), 7)
end

function M.istypeNarrowingAtRuntime()
   assertEq(run(VEC .. [[
local v: any = new Vec2(1, 2)
return v is Vec2]]), true)
   assertEq(run(VEC .. [[
local v: any = {x = 1}
return v is Vec2]]), false)
end

function M.structFieldAccessChecked()
   assertEq((diagsOf(VEC .. "local v = new Vec2()\nlocal z = v.z")), "NUPP2004:6")
   assertClean(VEC .. "local v = new Vec2()\nlocal x: number = v.x")
end

function M.lineCountInvariantWithStructs()
   local src = VEC .. "local v: Vec2\nreturn v.x"
   local code = compile(src)
   local _, srcN = src:gsub("\n", "")
   local _, codeN = code:gsub("\n", "")
   assertEq(codeN, srcN + 1, "line count changed:\n" .. code)
end

-- A field may state a bit width, which is the C bitfield it lowers to. Twenty-three
-- booleans cost twenty-three bytes; twenty-three one-bit booleans cost four.
local FLAGS = [[local struct Marks
   offset: uint32
   missing: boolean : 1
   typeColon: boolean : 1
   breakOp: boolean : 1
end
]]

function M.bitWidthReachesTheCdecl()
   local code = compile(FLAGS .. "local m: Marks\nreturn m.offset")
   assert(code:find("missing : 1", 1, true),
      "the width belongs in the emitted cdecl:\n" .. code)
end

function M.bitWidthKeepsTheDeclaredType()
   -- a one-bit boolean reads back true, not 1: packing changes the layout only
   assertEq(run(FLAGS .. [[
local m = new Marks(7, true, false, true)
return m.missing]]), true)
   assertEq(run(FLAGS .. [[
local m = new Marks(7, true, false, true)
return m.typeColon]]), false)
   assertEq(run(FLAGS .. [[
local m = new Marks(7, false, false, false)
m.breakOp = true
return m.breakOp]]), true)
end

-- Three flags fit in the padding after a uint32 either way, so packing is only
-- observable once there are more of them than the padding holds.
local MANY = {"local struct Wide\n   offset: uint32\n"}
local MANYPACKED = {"local struct Packed\n   offset: uint32\n"}
for j = 1, 23 do
   MANY[#MANY + 1] = ("   f%d: boolean\n"):format(j)
   MANYPACKED[#MANYPACKED + 1] = ("   f%d: boolean : 1\n"):format(j)
end
MANY[#MANY + 1] = "end\n"
MANYPACKED[#MANYPACKED + 1] = "end\n"

function M.bitWidthPacks()
   local wide = compile(table.concat(MANY) .. "local w: Wide")
   local packed = compile(table.concat(MANYPACKED) .. "local p: Packed")
   local ffi = require("ffi")
   local function sizeOf(code)
      return ffi.sizeof(ffi.typeof(code:match('typeof%("(struct { [^"]*})"')))
   end
   local wideSize, packedSize = sizeOf(wide), sizeOf(packed)
   assert(packedSize < wideSize,
      ("23 one-bit fields should pack: %d vs %d bytes"):format(packedSize, wideSize))
   assertEq(packedSize, 8, "one word of flags beside the uint32")
end

function M.bitWidthCheckedLikeAnyField()
   assertClean(FLAGS .. "local m = new Marks(1, true, false, true)\nlocal b: boolean = m.missing")
   assertEq(diagsOf(FLAGS .. "local m = new Marks(1, true, false, true)\nlocal n: number = m.missing"),
      "NUPP2001:8")
end

-- A width is the C bitfield the field lowers to, so it needs a layout to sit in and
-- a base C allows one on. All four of these used to parse and be discarded.
function M.bitWidthNeedsAnIntegerBase()
   assertEq(diagsOf("local struct S\n   f: float : 1\nend"), "NUPP2201:2")
   assertEq(diagsOf("local struct S\n   n: number : 4\nend"), "NUPP2201:2")
   assertClean("local struct S\n   a: uint32 : 1\n   b: boolean : 1\nend")
end

function M.bitWidthNeedsAScalar()
   assertEq(diagsOf("local struct S\n   a: uint8[4] : 2\nend"), "NUPP2201:2")
end

function M.bitWidthNeedsAStructToLiveIn()
   -- a record is a table; there is no layout for a width to describe
   assertEq(diagsOf("local record R\n   f: uint32 : 1\nend"), "NUPP2201:2")
end

return M
