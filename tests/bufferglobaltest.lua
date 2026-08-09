-- `buffer`, the string.buffer module without the require.
--
-- LuaJIT keeps it in package.loaded and puts nothing on the `string` table, so
-- `string.buffer.new` would name a member this runtime does not have. A
-- compiler-provided global is the shape `carray` and `cheader` already use.
--
-- Everything here runs the generated code: the point of the global is what it
-- lowers to, and a type that checks is not evidence about that.
local parser = require("nupp.parser")
local optimize = require("nupp.optimize")
local gen = require("nupp.gen")
local check = require("fragment")
local envMod = require("nupp.env")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local env = envMod.new(HERE .. "/..")

local function assertEq(got, want, label)
   if got ~= want then
      error(("%s:\n  want: %s\n  got:  %s"):format(label or "mismatch",
         tostring(want), tostring(got)), 2)
   end
end

local function compile(src, level)
   local result = parser.parse(src, "test")
   assertEq(#result.errors, 0, "syntax errors in test source")
   local diags = check.check(result, "test", env)
   for _, diag in ipairs(diags or {}) do
      if diag.severity == "error" then
         error(("%s: %s\n%s"):format(diag.code, diag.msg, src), 2)
      end
   end
   optimize.run(result, {level = level or 1})
   local code, genDiags = gen.generate(result, "test")
   assertEq(#genDiags, 0, "gen diagnostics")
   return code
end

local function runs(src, level)
   local code = compile(src, level)
   local chunk, err = loadstring(code, "@buffer_global_test")
   if not chunk then
      error(("generated code does not load: %s\n---\n%s")
         :format(tostring(err), code), 2)
   end
   local ok, value = pcall(chunk)
   if not ok then
      error(("generated code raised: %s\n---\n%s"):format(tostring(value), code), 2)
   end
   return value, code
end

local M = {}

function M.buildsAStringWithNoRequire()
   local value = runs([[
local b = buffer.new()
b:put("a", "b")
b:put(1, 2)
return b:tostring()
]])
   assertEq(value, "ab12", "the module is reachable under its bare name")
end

function M.theModuleIsTypedRatherThanAny()
   -- If `buffer` were `any` this would check silently. It resolves to the
   -- declaration in decls/stringbuffer.d.nupp, so the arity is held.
   local result = parser.parse("local b = buffer.new(1, 2, 3, 4)\nreturn b\n", "test")
   assertEq(#result.errors, 0, "syntax errors")
   local diags = check.check(result, "test", env)
   local found = false
   for _, diag in ipairs(diags or {}) do
      if diag.severity == "error" then found = true end
   end
   assertEq(found, true, "too many arguments is an error, so the type is real")
end

function M.aShadowingBindingWins()
   local value = runs([[
local buffer = {new = function(): string return "shadowed" end}
return buffer.new()
]])
   assertEq(value, "shadowed", "a local named buffer is that local")
end

function M.anExplicitRequireStillWorks()
   local value = runs([[
const buffer = require("string.buffer")
local b = buffer.new()
b:put("x")
return b:tostring()
]])
   assertEq(value, "x", "writing the require is not broken by the global")
end

function M.oneBindingIsSharedWithOptFive()
   local code = compile([[
local b = buffer.new()
b:put("a")
local out = ""
for i = 1, 3 do
    out = out .. i
end
return b:tostring() .. out
]])
   local requires = 0
   for _ in code:gmatch('require%("string%.buffer"%)') do requires = requires + 1 end
   assertEq(requires, 1, "the global and OPT-5 require the module once between them")
end

function M.decodingRoundTrips()
   -- The module is the whole module, not a hand-picked `new`.
   local value = runs([[
local b = buffer.new()
b:encode({1, 2, 3})
local out = b:decode()
return #out
]])
   assertEq(value, 3, "encode and decode are reachable too")
end

function M.itIsNotRequiredAtLevelZero()
   -- The global is a lowering rather than an optimization, like the table
   -- intrinsics: it has to work where nothing is rewritten.
   local value = runs([[
local b = buffer.new()
b:put("zero")
return b:tostring()
]], 0)
   assertEq(value, "zero", "-O0 still resolves the global")
end

return M
