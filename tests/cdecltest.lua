local testAssert = require("nupp.test")
local cdecl = require("nupp.compiler.cinterop.cdecl")
local ffi = require("ffi")

local M = {}

function M.inspectionReturnsNeutralDeclarations()
    local parsed, err = cdecl.inspect(
        table.concat(
            {
                "struct NuppCdeclPoint { double x; double y; };",
                "void nuppCdeclVisit(void (*visit)(int), unsigned long n);",
            },
            "\n"
        )
    )
    assert(parsed, err)
    testAssert.equal(#parsed.structs, 1)
    testAssert.equal(parsed.structs[1].name, "NuppCdeclPoint")
    testAssert.equal(parsed.structs[1].fields[1].type.kind, "float")
    testAssert.equal(#parsed.functions, 1)
    local callback = parsed.functions[1].params[1].type
    testAssert.equal(callback.kind, "pointer")
    testAssert.equal(callback.to.kind, "function")
    testAssert.equal(callback.to.params[1].type.bits, 32)
end

function M.fixedArraysPreserveTheirRecursiveCounts()
    local parsed, err = cdecl.inspect("struct NuppCdeclArrays { int values[4]; float matrix[2][3]; };")
    assert(parsed, err)
    local fields = parsed.structs[1].fields
    testAssert.equal(fields[1].type.kind, "array")
    testAssert.equal(fields[1].type.count, 4)
    testAssert.equal(fields[1].type.of.bits, 32)
    testAssert.equal(fields[2].type.count, 2)
    testAssert.equal(fields[2].type.of.count, 3)
    testAssert.equal(fields[2].type.of.of.bits, 32)
end

function M.typedefNamedAnonymousAggregatesUseTheTypedefIdentity()
    local parsed, err = cdecl.inspect("typedef struct { float x; float y; } NuppCdeclAnonPoint;")
    assert(parsed, err)
    testAssert.equal(#parsed.structs, 1)
    testAssert.equal(parsed.structs[1].name, "NuppCdeclAnonPoint")
    testAssert.equal(parsed.structs[1].kind, "struct")
    testAssert.equal(parsed.structs[1].fields[2].name, "y")
end

function M.preludeTypesAreNotExported()
    local parsed, err = cdecl.inspect(
        "struct NuppCdeclOwned { NuppCdeclPrelude *value; };",
        "typedef struct NuppCdeclPrelude NuppCdeclPrelude;"
    )
    assert(parsed, err)
    testAssert.equal(#parsed.structs, 1)
    testAssert.equal(parsed.structs[1].name, "NuppCdeclOwned")
end

function M.targetDefinitionsCompletePreludeForwardDeclarations()
    local parsed, err = cdecl.inspect("struct NuppCdeclForwardTarget { int value; };", "struct NuppCdeclForwardTarget;")
    assert(parsed, err)
    testAssert.equal(#parsed.structs, 1)
    testAssert.equal(parsed.structs[1].name, "NuppCdeclForwardTarget")
    testAssert.equal(parsed.structs[1].fields[1].name, "value")
end

function M.registryEntriesBeyondTheOldCeilingAreVisible()
    local padding = {}
    for index = 1, 4100 do
        padding[index] = ("struct NuppCdeclPadding%d { int value; };"):format(index)
    end
    ffi.cdef(table.concat(padding, "\n"))
    assert(
        tonumber(ffi.typeof("struct NuppCdeclPadding4100")) > 8192,
        "the fixture reaches beyond the former registry ceiling"
    )

    local parsed, err = cdecl.inspect("int nuppCdeclAfterPadding(int value);")
    assert(parsed, err)
    testAssert.equal(#parsed.functions, 1)
    testAssert.equal(parsed.functions[1].name, "nuppCdeclAfterPadding")
end

function M.enumMembersComeBackInDeclarationOrder()
    local parsed, err = cdecl.inspect(
        table.concat(
            {
                "enum NuppCdeclStatus { NUPP_CDECL_OK = 0, NUPP_CDECL_LAST = 7 };",
                "typedef enum { NUPP_CDECL_ANON = 3 } NuppCdeclAnon;",
            },
            "\n"
        )
    )
    assert(parsed, err)
    testAssert.equal(#parsed.enums, 2)
    testAssert.equal(parsed.enums[1].name, "NuppCdeclStatus")
    testAssert.equal(parsed.enums[1].values[1].name, "NUPP_CDECL_OK")
    testAssert.equal(parsed.enums[1].values[1].value, 0)
    testAssert.equal(parsed.enums[1].values[2].name, "NUPP_CDECL_LAST")
    testAssert.equal(parsed.enums[1].values[2].value, 7)
    -- an anonymous enum has no name of its own and its members still count
    testAssert.equal(parsed.enums[2].name, nil)
    testAssert.equal(parsed.enums[2].values[1].name, "NUPP_CDECL_ANON")
    testAssert.equal(parsed.enums[2].values[1].value, 3)
end

function M.negativeEnumMembersAreReadBack()
    -- LuaJIT keeps the value where -1 means "no size", so it cannot be read
    -- from the entry alone.
    local parsed, err = cdecl.inspect("enum NuppCdeclSigned { NUPP_CDECL_ERR = -1, NUPP_CDECL_NONE = 0 };")
    assert(parsed, err)
    testAssert.equal(parsed.enums[1].values[1].value, -1)
    testAssert.equal(parsed.enums[1].values[2].value, 0)
end

function M.anUnusablePreludeEntryCostsOnlyItself()
    -- A system header's vocabulary is a chain, and a link this reader cannot
    -- spell must not take the declarations that do not need it with it.
    local parsed, err = cdecl.inspect("struct NuppCdeclKept { int n; };", {
        "typedef struct NuppCdeclNoSuchThing *NuppCdeclFine;",
        "typedef __nupp_cdecl_never_declared_t NuppCdeclBroken;"
    })
    assert(parsed, err)
    testAssert.equal(#parsed.structs, 1)
    testAssert.equal(parsed.structs[1].name, "NuppCdeclKept")
end

function M.aRejectedDeclarationIsSetAsideNotFatal()
    local parsed, err = cdecl.inspect({
        "struct NuppCdeclOpaque;",
        "struct NuppCdeclUnsized { struct NuppCdeclOpaque inner; };",
        "int nuppCdeclSurvives(int a);",
    })
    assert(parsed, err)
    testAssert.equal(#parsed.rejected, 1)
    testAssert.equal(parsed.declared, 3)
    testAssert.equal(#parsed.functions, 1)
    testAssert.equal(parsed.functions[1].name, "nuppCdeclSurvives")
    assert(parsed.rejected[1].reason:find("size", 1, true), "the reason travels with it: " .. parsed.rejected[1].reason)
end

function M.oneBlobIsStillTakenOrLeftWhole()
    -- What a `cheader` pins is not a subset: a header that will not parse is
    -- the answer, and quietly typing part of it would be the wrong one.
    local parsed = cdecl.inspect("struct NuppCdeclWhole { struct NuppCdeclNeverDefined inner; };")
    testAssert.equal(parsed, nil)
end

function M.membersWithoutANameAreCountedNotDropped()
    local parsed, err = cdecl.inspect(table.concat({
        "struct NuppCdeclAnonMember { int tag; union { int i; double d; }; int after; };",
        "struct NuppCdeclPadding { unsigned a : 3; unsigned : 0; unsigned b : 3; unsigned : 5; };",
    }, "\n"))
    assert(parsed, err)
    local byName = {}
    for _, declaration in ipairs(parsed.structs) do
        byName[declaration.name] = declaration
    end
    testAssert.equal(byName.NuppCdeclAnonMember.anonymous, 1, "anonymous members")
    testAssert.equal(#byName.NuppCdeclAnonMember.fields, 2, "named fields")
    testAssert.equal(byName.NuppCdeclAnonMember.size, ffi.sizeof("struct NuppCdeclAnonMember"))
    testAssert.equal(byName.NuppCdeclPadding.unnamed, 2, "unnamed bitfields")
    testAssert.equal(byName.NuppCdeclPadding.fields[2].bitPos, 0, "b starts the unit the zero-width field opened")
    testAssert.equal(byName.NuppCdeclPadding.fields[2].offset, 4)
end

function M.vectorAndComplexTypesAreNotArrays()
    local parsed, err = cdecl.inspect(table.concat({
        "typedef float nupp_cdecl_v4 __attribute__((vector_size(16)));",
        "nupp_cdecl_v4 nuppCdeclVector(double _Complex z);",
    }, "\n"))
    assert(parsed, err)
    local fn = parsed.functions[1]
    testAssert.equal(fn.returns.kind, "vector")
    testAssert.equal(fn.params[1].type.kind, "complex")
end

function M.aBoolBitfieldIsABoolean()
    local parsed, err = cdecl.inspect("struct NuppCdeclFlags { bool on : 1; int level : 4; };")
    assert(parsed, err)
    local fields = parsed.structs[1].fields
    testAssert.equal(fields[1].type.kind, "boolean")
    testAssert.equal(fields[1].bitWidth, 1)
    testAssert.equal(fields[2].type.kind, "integer")
end

function M.layoutAnswersForAMemberList()
    local layout = assert(cdecl.layout("struct", "uint8_t kind; uint32_t len; uint16_t a : 3;"))
    testAssert.equal(layout.size, 12)
    testAssert.equal(layout.align, 4)
    testAssert.equal(layout.fields[2].offset, 4)
    testAssert.equal(layout.fields[3].bitWidth, 3)
    local packed = cdecl.inspect("struct __attribute__((packed)) NuppCdeclPacked { uint8_t kind; uint32_t len; };")
    testAssert.equal(packed.structs[1].size, 5, "an attribute LuaJIT reads is laid out by")
    testAssert.equal(packed.structs[1].fields[2].offset, 1)
end

function M.eachDeclarationKnowsWhichUnitIntroducedIt()
    local parsed, err = cdecl.inspect({
        "int nuppCdeclUnitOne(void);",
        "struct NuppCdeclUnitTwo { int x; };",
        "struct NuppCdeclUnitBroken { struct NuppCdeclUnitNever inner; };",
    })
    assert(parsed, err)
    testAssert.equal(parsed.functions[1].unit, 1)
    testAssert.equal(parsed.structs[1].unit, 2)
    testAssert.equal(parsed.rejected[1].unit, 3)
end

return M
