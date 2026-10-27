local testAssert = require("nupp.test")
-- `layoutof(T)`, run rather than read.
--
-- Every number it reports is the build target's. The shapes below use only
-- scalars, pointers and fixed arrays that lay out identically on every 64-bit
-- target Nupp builds for, so the numbers written here hold on each of them.
local parser = require("nupp.compiler.syntax.parser")
local program = require("program")
local check = require("fragment")
local envMod = require("nupp.compiler.project.env")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local env = envMod.new(HERE .. "/..")

-- Each program is its own module, so the structs two programs declare under one
-- name stay distinct declarations.
local programs = 0

local function runs(src, label)
    programs = programs + 1
    local name = "layout_test_" .. programs
    local result = parser.parse(src, name .. ".nupp")
    testAssert.equal(#result.errors, 0, "syntax errors in test source\n" .. src)
    local diags = check.check(result, name .. ".nupp", env, {moduleName = name})
    for _, diag in ipairs(diags or {}) do
        if diag.severity == "error" then
            error(("%s: %s: %s\n%s"):format(label or "", diag.code, diag.msg, src), 2)
        end
    end
    local chunk, err = program.load(result, name)
    if not chunk then
        error(("does not load: %s\n%s"):format(tostring(err), src), 2)
    end
    local ok, value = pcall(chunk)
    if not ok then
        error(("raised: %s\n%s"):format(tostring(value), src), 2)
    end

    return value
end

local function diagnostics(src)
    local result = parser.parse(src, "test")
    testAssert.equal(#result.errors, 0, "syntax errors in test source")
    return check.check(result, "test", env)
end

local M = {}

function M.reportsFieldsInDeclarationOrder()
    local l = runs([[
local struct Vec3
    x: float32
    y: float32
    z: float32
end
return layoutof(Vec3)
]], "Vec3")
    testAssert.equal(l.name, "Vec3", "the declaration's name")
    testAssert.equal(#l.fields, 3, "three fields")
    testAssert.equal(l.fields[1].name, "x", "in order")
    testAssert.equal(l.fields[2].name, "y", "in order")
    testAssert.equal(l.fields[3].name, "z", "in order")
end

function M.everyNumberIsTheTargets()
    local l = runs([[
local struct Vec3
    x: float32
    y: float32
    z: float32
end
return layoutof(Vec3)
]], "Vec3")
    testAssert.equal(l.size, 12, "the struct's size")
    for index, f in ipairs(l.fields) do
        testAssert.equal(f.offset, (index - 1) * 4, "offset of " .. f.name)
        testAssert.equal(f.size, 4, "size of " .. f.name)
    end
end

function M.sizeAndPaddingAreDifferentQuestions()
    -- An int8 before a double: size 1, padding 7. Deriving size from the next
    -- field's offset would report 8, which is the stride.
    local l = runs([[
local struct Mixed
    tag: int8
    value: float64
    id: int32
end
return layoutof(Mixed)
]], "Mixed")
    testAssert.equal(l.fields[1].size, 1, "an int8 is one byte")
    testAssert.equal(l.fields[1].padding, 7, "and the rest of the gap is padding")
    testAssert.equal(l.fields[2].size, 8, "float64 is a double")
    testAssert.equal(l.fields[2].padding, 0, "which needs no padding before an int32")
end

function M.aNestedStructIsSizedFromItsCtype()
    local l = runs(
        [[
local struct Inner
    a: float32
    b: float32
end

local struct Outer
    inner: Inner
    w: float32
end
return layoutof(Outer)
]],
        "Outer"
    )
    testAssert.equal(l.fields[1].name, "inner", "the nested field")
    testAssert.equal(l.fields[1].size, 8, "sized as the struct it holds")
    testAssert.equal(l.fields[1].ctype, "Inner", "and reported by its declared name")
    testAssert.equal(l.size, 12, "the whole struct")
end

function M.aPointerKeepsItsPointeeInTheSpelling()
    -- Every pointer is one pointer wide, so the size does not need the pointee --
    -- but the pointee is what tells two layouts apart, so it stays in the spelling.
    local l = runs(
        [[
local struct Inner
    a: float32
end

local struct Pointy
    p: Inner*
    n: int32
end
return layoutof(Pointy)
]],
        "Pointy"
    )
    testAssert.equal(l.fields[1].ctype, "Inner *", "the pointee survives")
    testAssert.equal(l.fields[1].size, 8, "sized as a pointer")
end

function M.aNullablePointerIsStillAPointer()
    local l = runs(
        [[
local struct Inner
    a: float32
end

local struct Maybe
    p: Inner*?
    n: int32
end
return layoutof(Maybe)
]],
        "Maybe"
    )
    testAssert.equal(l.fields[1].size, 8, "NULL is one of its values")
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

    local base = fingerprintOf("    x: float32\n    y: float32")
    testAssert.equal(base, fingerprintOf("    x: float32\n    y: float32"), "the same layout answers the same")
    assert(base ~= fingerprintOf("    x: float32\n    y: int32"), "a changed field type changes it")
    assert(
        base ~= fingerprintOf("    y: float32\n    x: float32"),
        "a reordering changes it, because the layout changed"
    )
    assert(base ~= fingerprintOf("    x: float32\n    z: float32"), "a renamed field changes it")
end

function M.theSameCtypeAnswersFromTheSameTable()
    local same = runs(
        [[
local struct Vec2
    x: float32
    y: float32
end
return layoutof(Vec2) == layoutof(Vec2)
]],
        "cached"
    )
    testAssert.equal(same, true, "building it twice is one walk, not two")
end

function M.aRecordHasNoLayout()
    local found = nil
    for _, d in ipairs(diagnostics([[
local record Point
    x: float32
    y: float32
end
return layoutof(Point)
]])) do
        if d.code == "NUPP2402" then
            found = d
        end
    end
    assert(found, "a record is a table and has no C layout")
    assert(found.help and found.help:find("record", 1, true), "and the message says why")
end

function M.aNonStructArgumentIsRefused()
    local found = false
    for _, d in ipairs(diagnostics("return layoutof(42)\n")) do
        if d.code == "NUPP2402" then
            found = true
        end
    end
    testAssert.equal(found, true, "a number is not a struct type")
end

function M.aNestedStructIsExpandedInTheFingerprint()
    -- The hole naming it would leave: swap Inner's floats for int32s and every
    -- size stays identical, so `inner:Inner,w:float|12` matches itself across the
    -- change and a reader takes ints for floats.
    local function fingerprintOf(innerFields)
        return runs(
            (
                [[
local struct Inner
%s
end

local struct Outer
    inner: Inner
    w: float32
end
return layoutof(Outer)
]]
            ):format(innerFields),
            "Outer"
        ).fingerprint
    end

    local floats = fingerprintOf("    a: float32\n    b: float32")
    local ints = fingerprintOf("    a: int32\n    b: int32")
    assert(floats ~= ints, "a same-size change inside the nested struct still changes the fingerprint")
    local renamed = fingerprintOf("    x: float32\n    y: float32")
    assert(floats ~= renamed, "and so does renaming one of its fields")
end

function M.aPointerIsNotFollowedIntoTheFingerprint()
    -- The pointee is not part of this layout, and following it would not terminate
    -- for a linked structure.
    local function holderOf(innerFields)
        return runs(
            (
                [[
local struct Inner
%s
end

local struct Holder
    p: Inner*
    value: int32
end
return layoutof(Holder)
]]
            ):format(innerFields),
            "Holder"
        )
    end

    local l = holderOf("    a: float32\n    b: float32")
    testAssert.equal(l.fields[1].ctype, "Inner *", "named, not expanded")
    testAssert.equal(
        l.fingerprint,
        holderOf("    a: int32\n    b: int32").fingerprint,
        "a change inside the pointee leaves the fingerprint alone"
    )
end

function M.aSelfReferencingPointerWorks()
    -- The shape a linked list is written in: a struct pointing at its own kind.
    local l = runs(
        [[
local struct Node
    next: Node*?
    value: int32
end

local head = new Node(nil, 1)
local tail = new Node(nil, 2)
head.next = tail
return layoutof(Node).size
]],
        "Node"
    )
    testAssert.equal(l, 16, "the struct is laid out like the pointer-and-int it is")
end

function M.aSelfReferencingChainCanBeWalked()
    local value = runs(
        [[
local struct Node
    next: Node*?
    value: int32
end

local head = new Node(nil, 1)
local tail = new Node(nil, 2)
head.next = tail
local value: int32 = 0
@unsafe do
    value = head.next.value
end
return value
]],
        "chain"
    )
    testAssert.equal(value, 2, "the link is a real pointer to a real struct")
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
        if d.code == "NUPP2201" then
            found = d
        end
    end
    assert(found, "a struct containing itself by value has no size")
    assert(found.help and found.help:find("pointer", 1, true), "and the repair is a pointer")
end

function M.aMutualCycleIsCaughtToo()
    local found = nil
    for _, d in ipairs(
        diagnostics([[
local struct A
    b: B
    n: int32
end

local struct B
    a: A
    n: int32
end
return {A, B}
]])
    ) do
        if d.code == "NUPP2201" then
            found = d
        end
    end
    assert(found, "two structs containing each other have no size either")
end

function M.aForwardPointerBetweenStructsWorks()
    -- The same reached the other way: `A` points at `B`, declared after it.
    local value = runs(
        [[
local struct A
    b: B*?
    n: int32
end

local struct B
    a: A*?
    n: int32
end

local x = new A(nil, 7)
local y = new B(nil, 8)
x.b = y
y.a = x
local total: integer = 0
@unsafe do
    total = x.b.n * 10 + y.a.n
end
return total
]],
        "mutual"
    )
    testAssert.equal(value, 87, "each side reaches the other")
end

function M.aFixedArrayFieldIsLaidOutInline()
    -- `T[N]` sits in the struct's own bytes: N elements, no indirection. This is
    -- how a C struct carries a vector, and it was NUPP2201 until the field rule
    -- learned the difference between a fixed array and a variable one.
    local l = runs(
        [[
local struct Vertex
    pos: float32[3]
    uv: float32[2]
    id: int32
end
return layoutof(Vertex)
]],
        "Vertex"
    )
    testAssert.equal(l.size, 24, "the whole struct")
    testAssert.equal(l.fields[1].ctype, "float[3]", "spelled as the array it is")
    testAssert.equal(l.fields[1].size, 12, "three floats wide")
    testAssert.equal(l.fields[2].offset, 12, "and the next one follows it")
    testAssert.equal(l.fields[3].offset, 20, "as does the one after")
end

function M.aFixedArrayOfStructsIsSizedFromItsElementCtype()
    local l = runs(
        [[
local struct Cell
    a: float32
    b: float32
end

local struct Grid
    cells: Cell[4]
    n: int32
end
return layoutof(Grid)
]],
        "Grid"
    )
    testAssert.equal(l.fields[1].size, 32, "four cells wide")
    testAssert.equal(l.fields[1].ctype, "Cell[4]", "and named as the array it is")
    testAssert.equal(l.size, 36, "the whole struct")
end

function M.aFixedArrayIsUsableAtRuntime()
    local value = runs(
        [[
local struct Vertex
    pos: float32[3]
    id: int32
end

local v = new Vertex()
v.pos[0] = 1.5
v.pos[2] = 3.5
v.id = 7
return v.pos[0] + v.pos[2] + v.id
]],
        "runtime"
    )
    testAssert.equal(value, 12, "elements read and write where they were put")
end

function M.aVariableLengthArrayIsStillRefused()
    -- `T[?]` has no size, so a struct holding one has none either.
    local found = nil
    for _, d in ipairs(diagnostics([[
local struct Bad
    v: float32[?]
    n: int32
end
return Bad
]])) do
        if d.code == "NUPP2201" then
            found = d
        end
    end
    assert(found, "a variable-length array cannot be a struct field")
end

function M.aMethodDeclaredBeforeLayoutofIsNotAField()
    -- A method is not a stored field, so declaring one ahead of the layout query
    -- adds no member to the layout.
    local l = runs(
        [[
local struct Vec
    x: float32
    y: float32
end
function Vec:len(): float32
    return self.x
end
return layoutof(Vec)
]]
    )
    testAssert.equal(#l.fields, 2, "field count")
    testAssert.equal(l.fields[1].name, "x", "first field")
    testAssert.equal(l.fields[2].name, "y", "second field")
    testAssert.equal(l.size, 8, "size")
end

return M
