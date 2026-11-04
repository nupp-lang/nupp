local testAssert = require("assert")
-- `types.layoutof(T)`, run rather than read.
--
-- Every number it reports is the build target's. The shapes below use only
-- scalars, pointers and fixed arrays that lay out identically on every 64-bit
-- target Nupp builds for, so the numbers written here hold on each of them.
local parser = require("nupp.compiler.syntax.parser")
local program = require("program")
local check = require("helpers.fragment")
local envMod = require("nupp.compiler.project.env")

local HERE = require("helpers.paths").tests
local env = envMod.new(HERE .. "/..")

-- Each program is its own module, so the structs two programs declare under one
-- name stay distinct declarations.
local programs = 0

local function runs(src, label)
    programs = programs + 1
    local name = "layout_test_" .. programs
    local result = parser.parse(src, name .. ".nupp")
    testAssert.eq(#result.errors, 0, "syntax errors in test source\n" .. src)
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
    testAssert.eq(#result.errors, 0, "syntax errors in test source")
    return check.check(result, "test", env)
end

local M = {}

function M.descriptorTypesUseTheirOwningNamespaces()
    local value = runs(
        [[
local struct NamespacedLayout
    x: float
end
const {type Layout} = require("types")
const {type File} = require("io")
const {type Assertion} = require("assert")
const {type DateFields} = require("os")
local layout: types.Layout = types.layoutof(NamespacedLayout)
local imported: Layout = layout
local importedField: Layout.Field = imported.fields[1]
local field: types.Layout.Field = layout.fields[1]
local function file(handle: io.File): io.File
    return handle
end
local assertion: assert.Assertion = assert
local importedAssertion: Assertion = assertion
local date: os.DateFields = os.date("*t")
local importedDate: DateFields = date
local function importedFile(handle: File): File
    return handle
end
importedAssertion(importedField.name == field.name)
return field.size > 0 and date.month >= 1
]],
        "namespaced descriptors"
    )
    testAssert.eq(value, true)
end

function M.fileTypeDoesNotLoadItsImplementation()
    local isolated = envMod.new(HERE .. "/..")
    local resolve = isolated.resolveModule
    local loaded = 0
    isolated.resolveModule = function(environment, name, ...)
        if name == "nupp.runtime.standardio" then
            loaded = loaded + 1
        end
        return resolve(environment, name, ...)
    end
    local parsed = parser.parse("local function same(handle: io.File): io.File return handle end\nreturn same", "test")
    for _, diagnostic in ipairs(check.check(parsed, "test", isolated)) do
        testAssert.ne(diagnostic.severity, "error", diagnostic.msg)
    end
    testAssert.eq(loaded, 0, "a prelude type must not initialize the I/O implementation")
end

function M.retiredGlobalDescriptorTypesAreRejected()
    for _, name in ipairs({"Layout", "LayoutField", "LuaFile", "Assertion", "DateFields"}) do
        local found = false
        for _, diagnostic in ipairs(diagnostics("local value: " .. name .. " = nil\n")) do
            if diagnostic.severity == "error" and diagnostic.msg:find(name, 1, true) then
                found = true
            end
        end
        testAssert.eq(found, true, name .. " must not remain global")
    end
end

function M.retiredGlobalLayoutQueryIsRejected()
    local refused = false
    for _, diagnostic in ipairs(diagnostics([[
local struct Point
    x: float
end
return layoutof(Point)
]])) do
        refused = refused or diagnostic.severity == "error" and diagnostic.msg:find("layoutof", 1, true) ~= nil
    end
    testAssert.eq(refused, true, "the bare layoutof global is removed")
end

function M.layoutQueryCannotBeStoredAsAFunctionValue()
    for _, expression in ipairs({"types.layoutof", "types?.layoutof"}) do
        local refused = false
        for _, diagnostic in ipairs(diagnostics("local query = " .. expression .. "\nprint(query)\n")) do
            refused = refused or diagnostic.code == "NUPP2402"
        end
        testAssert.eq(refused, true, "the intrinsic has no first-class runtime function: " .. expression)
    end
end

function M.shadowedTypesNamespaceUsesTheLocalMethod()
    local value = runs(
        [[
local types = {layoutof = function(value: integer): integer return value + 1 end}
return types.layoutof(41)
]]
    )
    testAssert.eq(value, 42)
end

function M.localLayoutFunctionIsAnOrdinaryFunction()
    local value = runs([[
local function layoutof(value: integer): integer
    return value + 1
end
return layoutof(41)
]])
    testAssert.eq(value, 42)
end

function M.layoutQueryRequiresExactlyOneArgument()
    for _, call in ipairs({"types.layoutof()", "types.layoutof(Point, Point)"}) do
        local refused = false
        for _, diagnostic in ipairs(diagnostics("local struct Point x: float end\nreturn " .. call .. "\n")) do
            refused = refused or diagnostic.code == "NUPP2402"
        end
        testAssert.eq(refused, true, call)
    end
end

function M.reportsFieldsInDeclarationOrder()
    local l = runs([[
local struct Vec3
    x: float32
    y: float32
    z: float32
end
return types.layoutof(Vec3)
]], "Vec3")
    testAssert.eq(l.name, "Vec3", "the declaration's name")
    testAssert.eq(#l.fields, 3, "three fields")
    testAssert.eq(l.fields[1].name, "x", "in order")
    testAssert.eq(l.fields[2].name, "y", "in order")
    testAssert.eq(l.fields[3].name, "z", "in order")
end

function M.everyNumberIsTheTargets()
    local l = runs([[
local struct Vec3
    x: float32
    y: float32
    z: float32
end
return types.layoutof(Vec3)
]], "Vec3")
    testAssert.eq(l.size, 12, "the struct's size")
    for index, f in ipairs(l.fields) do
        testAssert.eq(f.offset, (index - 1) * 4, "offset of " .. f.name)
        testAssert.eq(f.size, 4, "size of " .. f.name)
    end
end

function M.sizeAndPaddingAreDifferentQuestions()
    -- An int8 before a double: size 1, padding 7. Deriving size from the next
    -- field's offset would report 8, which is the stride.
    local l = runs(
        [[
local struct Mixed
    tag: int8
    value: float64
    id: int32
end
return types.layoutof(Mixed)
]],
        "Mixed"
    )
    testAssert.eq(l.fields[1].size, 1, "an int8 is one byte")
    testAssert.eq(l.fields[1].padding, 7, "and the rest of the gap is padding")
    testAssert.eq(l.fields[2].size, 8, "float64 is a double")
    testAssert.eq(l.fields[2].padding, 0, "which needs no padding before an int32")
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
return types.layoutof(Outer)
]],
        "Outer"
    )
    testAssert.eq(l.fields[1].name, "inner", "the nested field")
    testAssert.eq(l.fields[1].size, 8, "sized as the struct it holds")
    testAssert.eq(l.fields[1].ctype, "Inner", "and reported by its declared name")
    testAssert.eq(l.size, 12, "the whole struct")
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
return types.layoutof(Pointy)
]],
        "Pointy"
    )
    testAssert.eq(l.fields[1].ctype, "Inner *", "the pointee survives")
    testAssert.eq(l.fields[1].size, 8, "sized as a pointer")
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
return types.layoutof(Maybe)
]],
        "Maybe"
    )
    testAssert.eq(l.fields[1].size, 8, "NULL is one of its values")
end

function M.theFingerprintDistinguishesLayouts()
    local function fingerprintOf(fields)
        return runs(([[
local struct S
%s
end
return types.layoutof(S)
]]):format(fields), "S").fingerprint
    end

    local base = fingerprintOf("    x: float32\n    y: float32")
    testAssert.eq(base, fingerprintOf("    x: float32\n    y: float32"), "the same layout answers the same")
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
return types.layoutof(Vec2) == types.layoutof(Vec2)
]],
        "cached"
    )
    testAssert.eq(same, true, "building it twice is one walk, not two")
end

function M.aRecordHasNoLayout()
    local found = nil
    for _, d in ipairs(diagnostics([[
local record Point
    x: float32
    y: float32
end
return types.layoutof(Point)
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
    for _, d in ipairs(diagnostics("return types.layoutof(42)\n")) do
        if d.code == "NUPP2402" then
            found = true
        end
    end
    testAssert.eq(found, true, "a number is not a struct type")
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
return types.layoutof(Outer)
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
return types.layoutof(Holder)
]]
            ):format(innerFields),
            "Holder"
        )
    end

    local l = holderOf("    a: float32\n    b: float32")
    testAssert.eq(l.fields[1].ctype, "Inner *", "named, not expanded")
    testAssert.eq(
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
return types.layoutof(Node).size
]],
        "Node"
    )
    testAssert.eq(l, 16, "the struct is laid out like the pointer-and-int it is")
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
    testAssert.eq(value, 2, "the link is a real pointer to a real struct")
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
    testAssert.eq(value, 87, "each side reaches the other")
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
return types.layoutof(Vertex)
]],
        "Vertex"
    )
    testAssert.eq(l.size, 24, "the whole struct")
    testAssert.eq(l.fields[1].ctype, "float[3]", "spelled as the array it is")
    testAssert.eq(l.fields[1].size, 12, "three floats wide")
    testAssert.eq(l.fields[2].offset, 12, "and the next one follows it")
    testAssert.eq(l.fields[3].offset, 20, "as does the one after")
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
return types.layoutof(Grid)
]],
        "Grid"
    )
    testAssert.eq(l.fields[1].size, 32, "four cells wide")
    testAssert.eq(l.fields[1].ctype, "Cell[4]", "and named as the array it is")
    testAssert.eq(l.size, 36, "the whole struct")
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
    testAssert.eq(value, 12, "elements read and write where they were put")
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
return types.layoutof(Vec)
]]
    )
    testAssert.eq(#l.fields, 2, "field count")
    testAssert.eq(l.fields[1].name, "x", "first field")
    testAssert.eq(l.fields[2].name, "y", "second field")
    testAssert.eq(l.size, 8, "size")
end

return M
