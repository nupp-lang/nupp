local cdecl = require("nupp.cdecl")

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

function M.preludeTypesAreNotExported()
   local parsed, err = cdecl.inspect(
      "struct NuppCdeclOwned { NuppCdeclPrelude *value; };",
      "typedef struct NuppCdeclPrelude NuppCdeclPrelude;")
   assert(parsed, err)
   assertEq(#parsed.structs, 1)
   assertEq(parsed.structs[1].name, "NuppCdeclOwned")
end

return M
