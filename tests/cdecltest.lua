local cdecl = require("nupp.compiler.cdecl")

local function assertEq(got, want, label)
   if got ~= want then
      error(("%s: want %s, got %s"):format(label or "mismatch",
         tostring(want), tostring(got)), 2)
   end
end

local M = {}

function M.inspectionReturnsNeutralDeclarations()
   local parsed, err = cdecl.inspect(table.concat({
      "struct NuppCdeclPoint { double x; double y; };",
      "void nuppCdeclVisit(void (*visit)(int), unsigned long n);",
   }, "\n"))
   assert(parsed, err)
   assertEq(#parsed.structs, 1)
   assertEq(parsed.structs[1].name, "NuppCdeclPoint")
   assertEq(parsed.structs[1].fields[1].type.kind, "float")
   assertEq(#parsed.functions, 1)
   local callback = parsed.functions[1].params[1].type
   assertEq(callback.kind, "pointer")
   assertEq(callback.to.kind, "function")
   assertEq(callback.to.params[1].type.bits, 32)
end

function M.fixedArraysPreserveTheirRecursiveCounts()
   local parsed, err = cdecl.inspect(
      "struct NuppCdeclArrays { int values[4]; float matrix[2][3]; };")
   assert(parsed, err)
   local fields = parsed.structs[1].fields
   assertEq(fields[1].type.kind, "array")
   assertEq(fields[1].type.count, 4)
   assertEq(fields[1].type.of.bits, 32)
   assertEq(fields[2].type.count, 2)
   assertEq(fields[2].type.of.count, 3)
   assertEq(fields[2].type.of.of.bits, 32)
end

function M.typedefNamedAnonymousAggregatesUseTheTypedefIdentity()
   local parsed, err = cdecl.inspect(
      "typedef struct { float x; float y; } NuppCdeclAnonPoint;")
   assert(parsed, err)
   assertEq(#parsed.structs, 1)
   assertEq(parsed.structs[1].name, "NuppCdeclAnonPoint")
   assertEq(parsed.structs[1].kind, "struct")
   assertEq(parsed.structs[1].fields[2].name, "y")
end

function M.preludeTypesAreNotExported()
   local parsed, err = cdecl.inspect(
      "struct NuppCdeclOwned { NuppCdeclPrelude *value; };",
      "typedef struct NuppCdeclPrelude NuppCdeclPrelude;")
   assert(parsed, err)
   assertEq(#parsed.structs, 1)
   assertEq(parsed.structs[1].name, "NuppCdeclOwned")
end

function M.enumMembersComeBackInDeclarationOrder()
   local parsed, err = cdecl.inspect(table.concat({
      "enum NuppCdeclStatus { NUPP_CDECL_OK = 0, NUPP_CDECL_LAST = 7 };",
      "typedef enum { NUPP_CDECL_ANON = 3 } NuppCdeclAnon;",
   }, "\n"))
   assert(parsed, err)
   assertEq(#parsed.enums, 2)
   assertEq(parsed.enums[1].name, "NuppCdeclStatus")
   assertEq(parsed.enums[1].values[1].name, "NUPP_CDECL_OK")
   assertEq(parsed.enums[1].values[1].value, 0)
   assertEq(parsed.enums[1].values[2].name, "NUPP_CDECL_LAST")
   assertEq(parsed.enums[1].values[2].value, 7)
   -- an anonymous enum has no name of its own and its members still count
   assertEq(parsed.enums[2].name, nil)
   assertEq(parsed.enums[2].values[1].name, "NUPP_CDECL_ANON")
   assertEq(parsed.enums[2].values[1].value, 3)
end

function M.negativeEnumMembersAreReadBack()
   -- LuaJIT keeps the value where -1 means "no size", so it cannot be read
   -- from the entry alone.
   local parsed, err = cdecl.inspect(
      "enum NuppCdeclSigned { NUPP_CDECL_ERR = -1, NUPP_CDECL_NONE = 0 };")
   assert(parsed, err)
   assertEq(parsed.enums[1].values[1].value, -1)
   assertEq(parsed.enums[1].values[2].value, 0)
end

function M.anUnusablePreludeEntryCostsOnlyItself()
   -- A system header's vocabulary is a chain, and a link this reader cannot
   -- spell must not take the declarations that do not need it with it.
   local parsed, err = cdecl.inspect(
      "struct NuppCdeclKept { int n; };",
      {"typedef struct NuppCdeclNoSuchThing *NuppCdeclFine;",
       "typedef __nupp_cdecl_never_declared_t NuppCdeclBroken;"})
   assert(parsed, err)
   assertEq(#parsed.structs, 1)
   assertEq(parsed.structs[1].name, "NuppCdeclKept")
end

function M.aRejectedDeclarationIsSetAsideNotFatal()
   local parsed, err = cdecl.inspect({
      "struct NuppCdeclOpaque;",
      "struct NuppCdeclUnsized { struct NuppCdeclOpaque inner; };",
      "int nuppCdeclSurvives(int a);",
   })
   assert(parsed, err)
   assertEq(#parsed.rejected, 1)
   assertEq(parsed.declared, 3)
   assertEq(#parsed.functions, 1)
   assertEq(parsed.functions[1].name, "nuppCdeclSurvives")
   assert(parsed.rejected[1].reason:find("size", 1, true),
      "the reason travels with it: " .. parsed.rejected[1].reason)
end

function M.oneBlobIsStillTakenOrLeftWhole()
   -- What a `cheader` pins is not a subset: a header that will not parse is
   -- the answer, and quietly typing part of it would be the wrong one.
   local parsed = cdecl.inspect(
      "struct NuppCdeclWhole { struct NuppCdeclNeverDefined inner; };")
   assertEq(parsed, nil)
end

return M
