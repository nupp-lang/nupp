-- Reified arrays: the contiguous layout that makes reifying a struct worth
-- it, and the checking that keeps it honest.
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

local P = table.concat({
   "local struct P",
   "    x: float",
   "    y: float",
   "end",
}, "\n")

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
   assertEq(#genDiags, 0, "gen diagnostics")
   local chunk, err = loadstring(code, "@carraytest")
   if not chunk then
      error("does not load: " .. tostring(err) .. "\n" .. code, 2)
   end
   return chunk()
end

local M = {}

function M.elementsAreReachableAndTyped()
   assertEq(diagsOf(P .. "\nlocal ps = carray(P, 4)\nlocal v: number = ps[0].x"), "")
   assertEq(diagsOf(P .. "\nlocal ps = carray(P, 4)\nlocal s: string = ps[0].x"),
      "NUPP2001")
   assertEq(diagsOf(P .. "\nlocal ps = carray(P, 4)\nlocal v = ps[0].nope"),
      "NUPP2004")
end

function M.indexMustBeNumericAndElementTypeIsAStruct()
   assertEq(diagsOf(P .. "\nlocal ps = carray(P, 4)\nps['k'].x = 1"), "NUPP2004")
   assertEq(diagsOf(P .. "\nlocal q = carray(4, 8)"), "NUPP2401")
   assertEq(diagsOf(P .. "\nlocal q = carray(P, 'many')"), "NUPP2401")
   -- a record is not reifiable, so it cannot back a carray
   assertEq(diagsOf("local record R\n    n: number\nend\nlocal q = carray(R, 2)"),
      "NUPP2401")
end

function M.storageIsContiguousCdata()
   -- two floats per element, four elements: the layout, not a table of tables
   assertEq(run(P .. table.concat({
      "",
      "local ffi = require('ffi')",
      "local ps = carray(P, 4)",
      "return ffi.sizeof(ps)",
   }, "\n")), 32)
end

function M.valuesRoundTripThroughTheArray()
   assertEq(run(P .. table.concat({
      "",
      "local ps = carray(P, 3)",
      "for i = 0, 2 do",
      "    ps[i].x = i * 2",
      "end",
      "return ps[2].x",
   }, "\n")), 4)
end

function M.elementsAreReferencesIntoTheArray()
   -- taking an element and writing through it changes the array, which is
   -- what makes the layout worth having
   assertEq(run(P .. table.concat({
      "",
      "local ps = carray(P, 2)",
      "local p = ps[1]",
      "p.x = 9",
      "return ps[1].x",
   }, "\n")), 9)
end

function M.fixedAndVariableLengthAreDistinct()
   assertEq(diagsOf(P .. "\nlocal ps: P[4] = carray(P, 4)"), "NUPP2001",
      "an allocation is variable-length, so it is not a P[4]")
   assertEq(diagsOf(P .. "\nlocal a: P[4]\nlocal b: P[?] = a"), "",
      "a fixed array fits where any length is accepted")
   assertEq(diagsOf(P .. "\nlocal a: P[?]\nlocal b: P[4] = a"), "NUPP2001")
end

function M.arrayTypeIsWritableInAnnotations()
   assertEq(diagsOf(P .. "\nlocal ps: P[?] = carray(P, 4)"), "")
   assertEq(diagsOf(P .. table.concat({
      "",
      "local struct Q",
      "    n: float",
      "end",
      "local ps: Q[?] = carray(P, 4)",
   }, "\n")), "NUPP2001")
end

function M.arrayCtypeIsBuiltOncePerElementType()
   local result = parser.parse(P .. "\nlocal a = carray(P, 2)\nlocal b = carray(P, 3)",
      "test")
   check.check(result, "test", env)
   local code = gen.generate(result, "test")
   assert(code:find("__nuppArrayCache", 1, true),
      "the array ctype is cached rather than rebuilt:\n" .. code)
   assert(code:find("__nuppArray(P)(", 1, true), "allocates through the cache")
end

return M
