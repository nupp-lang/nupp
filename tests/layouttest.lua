-- `layoutof(T)`, run rather than read.
--
-- Every number it reports is this platform's, so the assertions check against the
-- FFI itself rather than against a number written down here: a test that hardcodes
-- an offset passes on the machine it was written on and lies everywhere else.
local parser = require("nupp.parser")
local optimize = require("nupp.optimize")
local gen = require("nupp.gen")
local check = require("fragment")
local envMod = require("nupp.env")
local ffi = require("ffi")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local env = envMod.new(HERE .. "/..")

local function assertEq(got, want, label)
   if got ~= want then
      error(("%s:\n  want: %s\n  got:  %s"):format(label or "mismatch",
         tostring(want), tostring(got)), 2)
   end
end

local function runs(src, label)
   local result = parser.parse(src, "test")
   assertEq(#result.errors, 0, "syntax errors in test source\n" .. src)
   local diags = check.check(result, "test", env)
   for _, diag in ipairs(diags or {}) do
      if diag.severity == "error" then
         error(("%s: %s: %s\n%s"):format(label or "", diag.code, diag.msg, src), 2)
      end
   end
   optimize.run(result, {level = 1})
   local code, genDiags = gen.generate(result, "test")
   assertEq(#genDiags, 0, "gen diagnostics")
   local chunk, err = loadstring(code, "@layout_test")
   if not chunk then
      error(("does not load: %s\n---\n%s"):format(tostring(err), code), 2)
   end
   local ok, value = pcall(chunk)
   if not ok then
      error(("raised: %s\n---\n%s"):format(tostring(value), code), 2)
   end
   return value, code
end

local function diagnostics(src)
   local result = parser.parse(src, "test")
   assertEq(#result.errors, 0, "syntax errors in test source")
   return check.check(result, "test", env)
end

local M = {}

function M.reportsFieldsInDeclarationOrder()
   local l = runs([[
local struct Vec3
    x: float
    y: float
    z: float
end
return layoutof(Vec3)
]], "Vec3")
   assertEq(l.name, "Vec3", "the declaration's name")
   assertEq(#l.fields, 3, "three fields")
   assertEq(l.fields[1].name, "x", "in order")
   assertEq(l.fields[2].name, "y", "in order")
   assertEq(l.fields[3].name, "z", "in order")
end

function M.everyNumberAgreesWithTheFfi()
   -- The independent check: build the same ctype by hand and compare.
   local l = runs([[
local struct Vec3
    x: float
    y: float
    z: float
end
return layoutof(Vec3)
]], "Vec3")
   local ct = ffi.typeof("struct { float x; float y; float z; }")
   assertEq(l.size, ffi.sizeof(ct), "the struct's size")
   for _, f in ipairs(l.fields) do
      assertEq(f.offset, ffi.offsetof(ct, f.name), "offset of " .. f.name)
      assertEq(f.size, ffi.sizeof("float"), "size of " .. f.name)
   end
end

function M.sizeAndPaddingAreDifferentQuestions()
   -- An int8 before a double: size 1, padding 7. Deriving size from the next
   -- field's offset would report 8, which is the stride.
   local l = runs([[
local struct Mixed
    tag: int8
    value: number
    id: int32
end
return layoutof(Mixed)
]], "Mixed")
   assertEq(l.fields[1].size, 1, "an int8 is one byte")
   assertEq(l.fields[1].padding, ffi.offsetof(
      ffi.typeof("struct { int8_t tag; double value; int32_t id; }"), "value") - 1,
      "and the rest of the gap is padding")
   assertEq(l.fields[2].size, 8, "a number is a double")
   assertEq(l.fields[2].padding, 0, "which needs no padding before an int32")
end

function M.aNestedStructIsSizedFromItsCtype()
   -- The shape that cannot be sized from its spelling: nupp emits anonymous
   -- ctypes, so `ffi.sizeof("Inner")` fails and the ctype is passed instead.
   local l = runs([[
local struct Inner
    a: float
    b: float
end

local struct Outer
    inner: Inner
    w: float
end
return layoutof(Outer)
]], "Outer")
   local inner = ffi.typeof("struct { float a; float b; }")
   assertEq(l.fields[1].name, "inner", "the nested field")
   assertEq(l.fields[1].size, ffi.sizeof(inner), "sized from the ctype")
   assertEq(l.fields[1].ctype, "Inner", "and reported by its declared name")
   assertEq(l.size, ffi.sizeof(ffi.typeof("struct { $ inner; float w; }", inner)),
      "the whole struct")
end

function M.aPointerKeepsItsPointeeInTheSpelling()
   -- Every pointer is one pointer wide, so the size does not need the pointee --
   -- but the pointee is what tells two layouts apart, so it stays in the spelling.
   local l = runs([[
local struct Inner
    a: float
end

local struct Pointy
    p: Inner*
    n: int32
end
return layoutof(Pointy)
]], "Pointy")
   assertEq(l.fields[1].ctype, "Inner *", "the pointee survives")
   assertEq(l.fields[1].size, ffi.sizeof("void *"), "sized as a pointer")
end

function M.aNullablePointerIsStillAPointer()
   local l = runs([[
local struct Inner
    a: float
end

local struct Maybe
    p: Inner*?
    n: int32
end
return layoutof(Maybe)
]], "Maybe")
   assertEq(l.fields[1].size, ffi.sizeof("void *"), "NULL is one of its values")
end

function M.theFingerprintDistinguishesLayouts()
   local function fingerprintOf(fields)
      return runs(([[
local struct S
%s
end
return layoutof(S)
]]):format(fields), "S").fingerprint
   end
   local base = fingerprintOf("    x: float\n    y: float")
   assertEq(base, "x:float,y:float|" .. ffi.sizeof(
      ffi.typeof("struct { float x; float y; }")), "names, types and size")
   assert(base ~= fingerprintOf("    x: float\n    y: int32"),
      "a changed field type changes it")
   assert(base ~= fingerprintOf("    y: float\n    x: float"),
      "a reordering changes it, because the layout changed")
   assert(base ~= fingerprintOf("    x: float\n    z: float"),
      "a renamed field changes it")
end

function M.theSameCtypeAnswersFromTheSameTable()
   local same = runs([[
local struct Vec2
    x: float
    y: float
end
return layoutof(Vec2) == layoutof(Vec2)
]], "cached")
   assertEq(same, true, "building it twice is one walk, not two")
end

function M.aRecordHasNoLayout()
   local found = nil
   for _, d in ipairs(diagnostics([[
local record Point
    x: float
    y: float
end
return layoutof(Point)
]])) do
      if d.code == "NUPP2402" then found = d end
   end
   assert(found, "a record is a table and has no C layout")
   assert(found.help and found.help:find("record", 1, true),
      "and the message says why")
end

function M.aNonStructArgumentIsRefused()
   local found = false
   for _, d in ipairs(diagnostics("return layoutof(42)\n")) do
      if d.code == "NUPP2402" then found = true end
   end
   assertEq(found, true, "a number is not a struct type")
end

function M.nothingIsEmittedWhenNothingAsks()
   local _, code = runs([[
local struct Vec2
    x: float
    y: float
end
return Vec2 ~= nil
]], "unused")
   assertEq(code:find("__nuppLayout", 1, true), nil,
      "a program that never asks carries no helper")
end

function M.aNestedStructIsExpandedInTheFingerprint()
   -- The hole naming it would leave: swap Inner's floats for int32s and every
   -- size stays identical, so `inner:Inner,w:float|12` matches itself across the
   -- change and a reader takes ints for floats.
   local function fingerprintOf(innerFields)
      return runs(([[
local struct Inner
%s
end

local struct Outer
    inner: Inner
    w: float
end
return layoutof(Outer)
]]):format(innerFields), "Outer").fingerprint
   end
   local floats = fingerprintOf("    a: float\n    b: float")
   local ints = fingerprintOf("    a: int32\n    b: int32")
   assertEq(floats, "inner:{a:float,b:float},w:float|12", "the nested fields expand")
   assert(floats ~= ints,
      "a same-size change inside the nested struct still changes the fingerprint")
   local renamed = fingerprintOf("    x: float\n    y: float")
   assert(floats ~= renamed, "and so does renaming one of its fields")
end

function M.aPointerIsNotFollowedIntoTheFingerprint()
   -- The pointee is not part of this layout, and following it would not terminate
   -- for a linked structure. Two separate declarations, because a struct cannot
   -- currently point at itself at all -- see aSelfReferencingPointerIsBroken.
   local l = runs([[
local struct Inner
    a: float
    b: float
end

local struct Holder
    p: Inner*
    value: int32
end
return layoutof(Holder)
]], "Holder")
   assertEq(l.fields[1].ctype, "Inner *", "named, not expanded")
   assert(l.fingerprint:find("p:Inner %*"), "and named in the fingerprint too")
   assert(not l.fingerprint:find("{", 1, true), "the pointee is not expanded")
end

function M.aSelfReferencingPointerWorks()
   -- The shape a linked list is written in. Codegen used to spell a nested struct
   -- by substituting its ctype into an anonymous one, so a self-reference passed
   -- nil and the module died at load. Such a struct is now emitted under a named
   -- C tag, forward-declared first, which is what C does and the only thing an
   -- anonymous ctype cannot do.
   local l = runs([[
local struct Node
    next: Node*?
    value: int32
end

local head = new Node {next = nil, value = 1}
local tail = new Node {next = nil, value = 2}
head.next = tail
return layoutof(Node).size
]], "Node")
   assertEq(l, ffi.sizeof(ffi.typeof("struct { void *next; int32_t value; }")),
      "the struct is laid out like the pointer-and-int it is")
end

function M.aSelfReferencingChainCanBeWalked()
   local value = runs([[
local struct Node
    next: Node*?
    value: int32
end

local head = new Node {next = nil, value = 1}
local tail = new Node {next = nil, value = 2}
head.next = tail
return head.next.value
]], "chain")
   assertEq(value, 2, "the link is a real pointer to a real struct")
end

function M.aStructCannotContainItselfByValue()
   local found = nil
   for _, d in ipairs(diagnostics([[
local struct Loop
    me: Loop
    n: int32
end
return Loop
]])) do
      if d.code == "NUPP2201" then found = d end
   end
   assert(found, "a struct containing itself by value has no size")
   assert(found.help and found.help:find("pointer", 1, true),
      "and the repair is a pointer")
end

function M.aMutualCycleIsCaughtToo()
   local found = nil
   for _, d in ipairs(diagnostics([[
local struct A
    b: B
    n: int32
end

local struct B
    a: A
    n: int32
end
return {A, B}
]])) do
      if d.code == "NUPP2201" then found = d end
   end
   assert(found, "two structs containing each other have no size either")
end

function M.aForwardPointerBetweenStructsWorks()
   -- The same defect reached the other way: `A` points at `B`, declared after it.
   -- Tagging closes over what a tagged struct names, because `ffi.cdef` has no `$`
   -- substitution, so both ends end up named.
   local value = runs([[
local struct A
    b: B*?
    n: int32
end

local struct B
    a: A*?
    n: int32
end

local x = new A {b = nil, n = 7}
local y = new B {a = nil, n = 8}
x.b = y
y.a = x
return x.b.n * 10 + y.a.n
]], "mutual")
   assertEq(value, 87, "each side reaches the other")
end

function M.aBackwardPointerKeepsItsAnonymousCtype()
   -- Only what needs naming is named: a pointer to an already-declared struct
   -- reaches a ctype that exists, so its spelling is untouched and a program
   -- without a forward or self reference generates exactly what it did.
   local _, code = runs([[
local struct Inner
    a: float
end

local struct Holder
    p: Inner*?
    n: int32
end
return Holder ~= nil
]], "backward")
   assertEq(code:find("__nuppS_", 1, true), nil, "no tag was needed")
   assert(code:find("$ *p", 1, true), "the substitution spelling is kept")
end

return M
