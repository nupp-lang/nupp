-- Typing a pinned C header at compile time: LuaJIT parses it, and the
-- types are read back out of the FFI rather than translated by us.
local cheaderMod = require("nupp.cheader")
local parser = require("nupp.parser")
local check = require("nupp.check")
local gen = require("nupp.gen")
local envMod = require("nupp.env")
local T = require("nupp.types")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
if not HERE:match("^/") then
   local p = assert(io.popen("pwd"))
   HERE = p:read("*l") .. "/" .. HERE
   p:close()
end
local env = envMod.new(HERE .. "/..")

local function assertEq(got, want, label)
   if got ~= want then
      error(("%s:\n  want: %s\n  got:  %s"):format(label or "mismatch",
         tostring(want), tostring(got)), 2)
   end
end

local M = {}

local function loaded()
   local res, err = cheaderMod.load(HERE .. "/fixtures/sink.h")
   assert(res, "header must load: " .. tostring(err))
   return res
end

function M.signaturesComeFromLuaJITsOwnParse()
   local res = loaded()
   -- imported pointers are nullable: C does not say which may be NULL
   assertEq(T.tostring(res.exports.nuppSinkOpen), "function(cstring?): boolean")
   assertEq(T.tostring(res.exports.nuppSinkCategory),
      "function(int32, int32, cstring?)")
   assertEq(T.tostring(res.exports.nuppSinkClose), "function()")
   -- unsigned long is 64-bit here, and that is read from the FFI rather
   -- than assumed
   assertEq(T.tostring(res.exports.nuppSinkCount), "function(): uint64")
end

function M.pointersAndStructsDecode()
   local res = loaded()
   -- float parameter, struct pointer, double return
   assertEq(T.tostring(res.exports.nuppSinkScale),
      "function(float, SinkPoint*?): number")
end

function M.noPreprocessorNeededForASelfContainedHeader()
   -- the fixture has #ifndef/#include and still loads with no compiler
   local res, err = cheaderMod.load(HERE .. "/fixtures/sink.h")
   assert(res, "no cc required: " .. tostring(err))
end

function M.missingHeaderIsReported()
   local res, err = cheaderMod.load(HERE .. "/fixtures/nope.h")
   assert(not res, "missing header fails")
   assert(err:find("cannot read", 1, true), "says why: " .. tostring(err))
end

local function diagsOf(src)
   local result = parser.parse(src, HERE .. "/probe.nupp")
   assertEq(#result.errors, 0, "syntax: "
      .. (result.errors[1] and result.errors[1].msg or ""))
   local out = {}
   for j, d in ipairs(check.check(result, HERE .. "/probe.nupp", env)) do
      out[j] = d.code
   end
   return table.concat(out, " ")
end

function M.cheaderTypesCallSites()
   assertEq(diagsOf(table.concat({
      "local sink = cheader('fixtures/sink.h')",
      "local ok: boolean = sink.nuppSinkOpen('/tmp/x')",
      "sink.nuppSinkCategory(1, 2, 'render')",
   }, "\n")), "")
   -- a wrong argument is caught against the header's own signature
   assertEq(diagsOf(table.concat({
      "local sink = cheader('fixtures/sink.h')",
      "sink.nuppSinkOpen(42)",
   }, "\n")), "NUPP2006")
   -- so is a symbol the header does not declare
   assertEq(diagsOf(table.concat({
      "local sink = cheader('fixtures/sink.h')",
      "sink.nuppNoSuchThing()",
   }, "\n")), "NUPP2004")
end

function M.badArgumentsToCheaderAreReported()
   assertEq(diagsOf("local x = cheader()"), "NUPP2301")
   assertEq(diagsOf("local x = cheader('fixtures/missing.h')"), "NUPP2302")
end

function M.generatedCodeDeclaresAndBinds()
   local result = parser.parse(
      "local sink = cheader('fixtures/sink.h')\nreturn sink", HERE .. "/p.nupp")
   assertEq(#result.errors, 0, "parses")
   check.check(result, HERE .. "/p.nupp", env)
   local code = gen.generate(result, HERE .. "/p.nupp")
   assert(code:find("__nuppFfi.cdef", 1, true), "declares to the FFI:\n" .. code)
   assert(code:find("nuppSinkOpen", 1, true), "carries the declarations")
   assert(code:find("__nuppFfi.C", 1, true), "binds the default namespace")
   -- redeclaration is tolerated: one process may load a header twice
   assert(code:find("pcall(__nuppFfi.cdef", 1, true), "tolerates redefinition")
end

function M.namedLibraryBindsThroughFfiLoad()
   local result = parser.parse(
      "local z = cheader('fixtures/sink.h', 'z')\nreturn z", HERE .. "/p2.nupp")
   check.check(result, HERE .. "/p2.nupp", env)
   local code = gen.generate(result, HERE .. "/p2.nupp")
   assert(code:find('__nuppFfi.load("z")', 1, true),
      "resolves through the named library:\n" .. code)
end

return M
