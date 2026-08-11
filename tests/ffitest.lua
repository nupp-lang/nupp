-- FFI operations the checker knows about: their return type follows the
-- type they are given, rather than collapsing to any.
local parser = require("nupp.compiler.parser")
local check = require("fragment")
local gen = require("nupp.compiler.gen")
local envMod = require("nupp.compiler.env")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local env = envMod.new(HERE .. "/..")

local function assertEq(got, want, label)
   if got ~= want then
      error(("%s:\n  want: %s\n  got:  %s"):format(label or "mismatch",
         tostring(want), tostring(got)), 2)
   end
end

local P = "local struct P\n    x: float\n    y: float\nend"

local function diagsOf(src)
   local result = parser.parse(src, "test.g.nupp")
   assertEq(#result.errors, 0, "syntax: "
      .. (result.errors[1] and result.errors[1].msg or ""))
   local out = {}
   for j, d in ipairs(check.check(result, "test.g.nupp", env)) do out[j] = d.code end
   return table.concat(out, " ")
end

local function run(src)
   local result = parser.parse(src, "test.g.nupp")
   assertEq(#result.errors, 0, "syntax errors")
   local diags = check.check(result, "test.g.nupp", env)
   assertEq(#diags, 0, "check: " .. (diags[1] and diags[1].msg or ""))
   local code, genDiags = gen.generate(result, "test")
   assertEq(#genDiags, 0, "gen: " .. (genDiags[1] and genDiags[1].msg or ""))
   local chunk, err = loadstring(code, "@ffitest")
   if not chunk then
      error("does not load: " .. tostring(err) .. "\n" .. code, 2)
   end
   return chunk()
end

local M = {}

function M.newReturnsTheTypeItWasGiven()
   assertEq(diagsOf(P .. "\nlocal p = ffi.new<P>()\nlocal v: number = p.x"), "")
   assertEq(diagsOf(P .. "\nlocal p = ffi.new<P>()\nlocal s: string = p.x"),
      "NUPP2001")
   assertEq(diagsOf(P .. "\nlocal p = ffi.new<P>()\nlocal v = p.nope"),
      "NUPP2004")
end

function M.castReturnsTheTargetType()
   assertEq(diagsOf(P .. table.concat({
      "",
      "local p = ffi.new<P>()",
      "local raw = ffi.cast<voidptr>(p)",
      "local back: voidptr = raw",
   }, "\n")), "")
   assertEq(diagsOf(P .. table.concat({
      "",
      "local p = ffi.new<P>()",
      "local raw = ffi.cast<voidptr>(p)",
      "local wrong: string = raw",
   }, "\n")), "NUPP2001")
end

function M.sizeofAndTypeofAreTyped()
   assertEq(diagsOf(P .. "\nlocal n: number = ffi.sizeof<P>()"), "")
   assertEq(diagsOf(P .. "\nlocal s: string = ffi.sizeof<P>()"), "NUPP2001")
   -- typeof yields the runtime ctype standing for the type
   assertEq(diagsOf(P .. "\nlocal c: ctype<P> = ffi.typeof<P>()"), "")
   assertEq(diagsOf(P .. "\nlocal c: ctype<voidptr> = ffi.typeof<P>()"),
      "NUPP2001")
end

function M.gcKeepsTheTypeOfItsValue()
   assertEq(diagsOf(P .. table.concat({
      "",
      "local p = ffi.gc(ffi.new<P>(), nil)",
      "local v: number = p.x",
   }, "\n")), "")
   assertEq(diagsOf(P .. table.concat({
      "",
      "local p = ffi.gc(ffi.new<P>(), nil)",
      "local s: string = p.x",
   }, "\n")), "NUPP2001")
end

function M.istypeNarrows()
   assertEq(diagsOf(P .. table.concat({
      "",
      "local v: any",
      "if ffi.istype<P>(v) then",
      "    local n: number = v.x",
      "end",
   }, "\n")), "")
   assertEq(diagsOf(P .. table.concat({
      "",
      "local v: any",
      "if ffi.istype<P>(v) then",
      "    local s: string = v.x",
      "end",
   }, "\n")), "NUPP2001")
end

function M.comparisonChainsStillParse()
   -- only ffi.<intrinsic> takes a type argument, so `a < b > c` is
   -- ordinary Lua everywhere else
   assertEq(diagsOf("local a, b, c = 1, 2, 3\nprint(a < b > c)"), "NUPP2003")
   assertEq(diagsOf("local t = {new = 1}\nlocal a, b = 1, 2\nprint(t.new < a > b)"),
      "NUPP2003")
end

function M.intrinsicsRunAtRuntime()
   assertEq(run(P .. table.concat({
      "",
      "local p = ffi.new<P>()",
      "p.x = 3",
      "p.y = 4",
      "return p.x + p.y",
   }, "\n")), 7)
   -- a struct's size is its layout, not a table's
   assertEq(run(P .. "\nreturn ffi.sizeof<P>()"), 8)
   assertEq(run(P .. "\nlocal p = ffi.new<P>()\nreturn ffi.istype<P>(p)"), true)
   assertEq(run(P .. "\nreturn ffi.istype<P>(42)"), false)
end

function M.builtinTypesUseTheirCSpelling()
   local result = parser.parse(P .. "\nlocal p = ffi.new<P>()\nlocal r = ffi.cast<voidptr>(p)",
      "test")
   check.check(result, "test.g.nupp", env)
   local code = gen.generate(result, "test")
   assert(code:find("__nuppFfi.new(P", 1, true),
      "a declared struct is already a ctype:\n" .. code)
   assert(code:find('__nuppFfi.cast("void *"', 1, true),
      "a builtin is named by its C spelling:\n" .. code)
end

-- Viewing a string as a C array is how the build's digest reads eight bytes at
-- a time. The checker already typed it; the generator had no spelling for it.
function M.castToACArrayIsAPointerCast()
   local function codeFor(src)
      local result = parser.parse(src, "test.g.nupp")
      check.check(result, "test.g.nupp", env)
      return gen.generate(result, "test")
   end
   -- The string is bound first: a pointer into a temporary outlives it, and
   -- the ownership checker says so (NUPP2501).
   local code = codeFor(
      'local s = "abcdefgh"\nlocal w = ffi.cast<const uint64[?]>(s)')
   -- Not `uint64_t[?]`: LuaJIT refuses a cast to a variable-length array, and
   -- a pointer is what indexing the result wants anyway.
   assert(code:find('__nuppFfi.cast("const uint64_t *"', 1, true),
      "a C array cast is a pointer cast:\n" .. code)
   local fixed = codeFor(
      'local s = "abcdefgh"\nlocal w = ffi.cast<uint32[4]>(s)')
   assert(fixed:find('__nuppFfi.cast("uint32_t *"', 1, true),
      "a fixed C array casts to its element pointer too:\n" .. fixed)
   -- Away from a cast, an array keeps the spelling C gives it.
   local allocated = codeFor("local w = ffi.sizeof<uint64[4]>()")
   assert(allocated:find('__nuppFfi.sizeof("uint64_t[4]"', 1, true),
      "an array spells as an array everywhere else:\n" .. allocated)
   assertEq(run(table.concat({
      'local s = "ABC"',
      'local w = ffi.cast<const uint8[?]>(s)',
      'unsafe do return w[1] end',
   }, "\n")), 66)
   assertEq(run("return ffi.sizeof<uint64[4]>()"), 32)
end

-- `ffi.C` is typed from what the checked file declared, not from what the
-- compiler's process happens to hold. The registry LuaJIT keeps is global and
-- has no idea who declared what, so reading it for membership let one program
-- see another's symbols and let a standard facility's own bindings displace a
-- file's.

function M.theCNamespaceHoldsWhatThisFileDeclared()
   assertEq(diagsOf(table.concat({
      'local ffi = require("ffi")',
      'ffi.cdef[[int nuppProbeDeclared(int);]]',
      "local n: integer = ffi.C.nuppProbeDeclared(1)",
   }, "\n")), "", "a declared symbol is a member")

   assertEq(diagsOf(table.concat({
      'local ffi = require("ffi")',
      "local n: integer = ffi.C.nuppProbeNeverDeclared(1)",
   }, "\n")), "NUPP2004", "a symbol this file never declared is not")
end

function M.anotherProgramsDeclarationsAreNotVisible()
   -- The first check declares it to the process for good; the second must still
   -- refuse it, because the second program did not.
   assertEq(diagsOf(table.concat({
      'local ffi = require("ffi")',
      'ffi.cdef[[int nuppLeakProbe(int);]]',
      "local n: integer = ffi.C.nuppLeakProbe(1)",
   }, "\n")), "", "the declaring program sees it")

   assertEq(diagsOf(table.concat({
      'local ffi = require("ffi")',
      "local n: integer = ffi.C.nuppLeakProbe(1)",
   }, "\n")), "NUPP2004", "a program that declared nothing does not")
end

function M.checkingTheSameSourceTwiceKeepsItsDeclarations()
   -- LuaJIT holds the block after the first check, so a second run declares
   -- nothing new. The names have to come back anyway.
   local source = table.concat({
      'local ffi = require("ffi")',
      'ffi.cdef[[int nuppRepeatProbe(int);]]',
      "local n: integer = ffi.C.nuppRepeatProbe(1)",
   }, "\n")
   assertEq(diagsOf(source), "", "first check")
   assertEq(diagsOf(source), "", "second check over the same source")
end

function M.aGuardedCdefStillDeclares()
   -- `pcall(ffi.cdef, ...)` is how a program tolerates redeclaring a name the
   -- process already holds, and it is what the compiler's own ansi module does.
   assertEq(diagsOf(table.concat({
      'local ffi = require("ffi")',
      'pcall(ffi.cdef, "int nuppGuardedProbe(int);")',
      "local n: integer = ffi.C.nuppGuardedProbe(1)",
   }, "\n")), "", "a guarded declaration is still a declaration")
end

function M.ffiLoadCarriesTheSameNamespace()
   assertEq(diagsOf(table.concat({
      'local ffi = require("ffi")',
      'ffi.cdef[[int nuppLoadProbe(int);]]',
      'local lib = ffi.load("probe")',
      "local n: integer = lib.nuppLoadProbe(1)",
   }, "\n")), "", "a declared symbol is reachable through ffi.load")

   assertEq(diagsOf(table.concat({
      'local ffi = require("ffi")',
      'local lib = ffi.load("probe")',
      "local n: integer = lib.nuppUndeclaredThroughLoad(1)",
   }, "\n")), "NUPP2004", "and an undeclared one is not")
end

function M.aStandardFacilityDoesNotDisplaceAFilesOwnDeclarations()
   -- Initializing an FFI-backed facility runs a large `ffi.cdef` in this
   -- process. Nothing about that may change what a file's own `ffi.C` holds.
   local stdlib = require("nupp.compiler.stdlib")
   local previous = rawget(_G, "nupp")
   _G.nupp = nil
   local ok = pcall(function()
      assert(loadstring(stdlib.bootstrap({["stdlib.io"] = true})))()
      local buffer = _G.nupp.io.newBuffer("probe")
      return buffer:length()
   end)
   _G.nupp = previous
   assert(ok, "the facility initialized")

   assertEq(diagsOf(table.concat({
      'local ffi = require("ffi")',
      'pcall(ffi.cdef, "int nuppIsattyProbe(int);")',
      "local n: integer = ffi.C.nuppIsattyProbe(1)",
   }, "\n")), "", "the file still sees what it declared")

   assertEq(diagsOf(table.concat({
      'local ffi = require("ffi")',
      "local n: integer = ffi.C.nuppBytesLength(1)",
   }, "\n")), "NUPP2004", "and does not see the facility's bindings")
end

return M
