-- FFI operations the checker knows about: their return type follows the
-- type they are given, rather than collapsing to any.
local parser = require("nupp.parser")
local check = require("nupp.check")
local gen = require("nupp.gen")
local envMod = require("nupp.env")

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
   local result = parser.parse(src, "test")
   assertEq(#result.errors, 0, "syntax: "
      .. (result.errors[1] and result.errors[1].msg or ""))
   local out = {}
   for j, d in ipairs(check.check(result, "test", env)) do out[j] = d.code end
   return table.concat(out, " ")
end

local function run(src)
   local result = parser.parse(src, "test")
   assertEq(#result.errors, 0, "syntax errors")
   local diags = check.check(result, "test", env)
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
   check.check(result, "test", env)
   local code = gen.generate(result, "test")
   assert(code:find("__nuppFfi.new(P", 1, true),
      "a declared struct is already a ctype:\n" .. code)
   assert(code:find('__nuppFfi.cast("void *"', 1, true),
      "a builtin is named by its C spelling:\n" .. code)
end

return M
