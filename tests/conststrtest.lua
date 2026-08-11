-- Existing LuaJIT FFI code, typed without being rewritten: a literal cdef
-- block declares to the compiler as well as the runtime, and the constant
-- type strings that follow are read rather than ignored.
local parser = require("nupp.compiler.parser")
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

local function diagsOf(src)
   local result = parser.parse(src, "test.g.nupp")
   assertEq(#result.errors, 0, "syntax: "
      .. (result.errors[1] and result.errors[1].msg or ""))
   local out = {}
   for j, d in ipairs(check.check(result, "test.g.nupp", env)) do out[j] = d.code end
   return table.concat(out, " ")
end

-- distinct tags per case: declarations are global to the compiler's FFI
local DECL = [[
local ffi = require('ffi')
ffi.cdef[==[
struct CstA { double x; int n; };
struct CstB { struct CstA inner; };
]==]
]]

local M = {}

function M.aConstantTypeStringIsRead()
   assertEq(diagsOf(DECL .. "local p = ffi.new('struct CstA')\nlocal v: number = p.x"), "")
   assertEq(diagsOf(DECL .. "local p = ffi.new('struct CstA')\nlocal s: string = p.x"),
      "NUPP2001")
   assertEq(diagsOf(DECL .. "local p = ffi.new('struct CstA')\nlocal v = p.nope"),
      "NUPP2004")
end

function M.fieldTypesComeFromTheDeclaration()
   assertEq(diagsOf(DECL .. "local p = ffi.new('struct CstA')\nlocal n: number = p.n"), "")
   -- a nested struct keeps its own fields
   assertEq(diagsOf(DECL .. "local b = ffi.new('struct CstB')\nlocal v: number = b.inner.x"), "")
   assertEq(diagsOf(DECL .. "local b = ffi.new('struct CstB')\nlocal s: string = b.inner.x"),
      "NUPP2001")
end

function M.sizeofAndCastReadStringsToo()
   assertEq(diagsOf(DECL .. "local n: number = ffi.sizeof('struct CstA')"), "")
   assertEq(diagsOf(DECL .. "local s: string = ffi.sizeof('struct CstA')"),
      "NUPP2001")
   assertEq(diagsOf(DECL .. "local p = ffi.new('struct CstA')\n"
      .. "local r: voidptr = ffi.cast('void *', p)"), "")
end

function M.anUnknownTypeStringIsReported()
   assertEq(diagsOf(DECL .. "local p = ffi.new('struct CstNoSuch')"), "NUPP2304")
   assertEq(diagsOf(DECL .. "local p = ffi.new('not a type at all')"), "NUPP2304")
end

function M.declarationsThatDoNotParseAreReported()
   assertEq(diagsOf("local ffi = require('ffi')\nffi.cdef[[ this is not C ]]"),
      "NUPP2303")
end

function M.aRuntimeTypeStringYieldsCdataNotAny()
   -- leaving the typed path stays visible: cdata, never a silent any
   assertEq(diagsOf(DECL .. "local name = 'struct CstA'\n"
      .. "local p: cdata = ffi.new(name)"), "")
   assertEq(diagsOf(DECL .. "local name = 'struct CstA'\n"
      .. "local p: number = ffi.new(name)"), "NUPP2001")
   -- and a cdata does not silently gain fields
   assertEq(diagsOf(DECL .. "local name = 'struct CstA'\n"
      .. "local p = ffi.new(name)\nlocal v = p.x"), "NUPP2004")
end

function M.declaredStructsKeepTheirIdentityAcrossMentions()
   -- two mentions of a tag give the same type, so a value from one flows
   -- where the other is expected
   assertEq(diagsOf(DECL .. table.concat({
      "local a = ffi.new('struct CstA')",
      "local function take(v: number): nil end",
      "take(a.x)",
   }, "\n")), "")
end

function M.constIsAModifierOnlyWhenATypeFollows()
   -- `const` is a statement keyword and may also name a type; in type
   -- position it modifies only when a type comes next
   assertEq(diagsOf("local type const = number\nlocal a: const = 1"), "")
   assertEq(diagsOf("local type const = number\nlocal a: const? = nil"), "")
   assertEq(diagsOf("local type const = number\nlocal a: const | string = 1"), "")
   -- and the statement keyword is untouched
   assertEq(diagsOf("const x = 5\nprint(x)"), "")
   assertEq(diagsOf("local const = 5\nprint(const)"), "")
end

function M.constIsAPromiseNotToWrite()
   local P = "local struct P\n    x: float\nend"
   -- a mutable value satisfies a const one
   assertEq(diagsOf(P .. "\nlocal p: P = new P()\nlocal r: const P = p"), "")
   -- the reverse discards the promise
   assertEq(diagsOf(P .. "\nlocal r: const P\nlocal p: P = r"), "NUPP2001")
   assertEq(diagsOf(P .. "\nlocal p: const P* = nil"), "NUPP2001",
      "still a non-null pointer")
   assertEq(diagsOf(P .. "\nlocal p: const P*? = nil"), "")
end

function M.cFunctionPointersDecodeAsCallbackTypes()
   local cheaderMod = require("nupp.compiler.cheader")
   cheaderMod.declare("typedef void (*CbSink)(int code, const char *msg);\n"
      .. "struct CbHolder { CbSink handler; int n; };")
   local t = cheaderMod.typeFromString("struct CbHolder")
   assert(t and t.byname, "struct decoded")
   local handler = t.byname.handler
   assert(handler, "the callback field is present")
   local rendered = require("nupp.compiler.types").tostring(handler)
   assert(rendered:find("function", 1, true),
      "a pointer to a function reads as one: " .. rendered)
end

function M.lossyNarrowingIsAStrictModeLint()
   local src = "local x: number = 5\nlocal small: int32 = x"
   -- silent by default, since LuaJIT has always truncated here
   assertEq(diagsOf(src), "")
   local result = parser.parse(src, "test.g.nupp")
   local diags = check.check(result, "test.g.nupp", env, {strict = true})
   assertEq(#diags, 1, "reported under --strict")
   assertEq(diags[1].code, "NUPP2503")
   -- a wider target is not a narrowing
   local wide = parser.parse("local x: number = 5\nlocal big: number = x", "test")
   assertEq(#check.check(wide, "test", env, {strict = true}), 0)
end

function M.theCNamespaceIsTypedFromDeclarations()
   local D = "local ffi = require('ffi')\nffi.cdef[[ int nsA(const char *s); ]]\n"
   assertEq(diagsOf(D .. "local n: number = ffi.C.nsA('x')"), "")
   assertEq(diagsOf(D .. "ffi.C.nsA(42)"), "NUPP2006")
   assertEq(diagsOf(D .. "ffi.C.nsNoSuch()"), "NUPP2004")
   -- ffi.load holds the same declarations
   assertEq(diagsOf(D .. "local lib = ffi.load('m')\nlib.nsA(42)"), "NUPP2006")
end

return M
