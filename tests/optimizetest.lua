local parser = require("nupp.parser")
local optimize = require("nupp.optimize")
local gen = require("nupp.gen")

local function assertEq(got, want, label)
   if got ~= want then
      error(("%s:\n  want: %s\n  got:  %s"):format(label or "mismatch",
         tostring(want), tostring(got)), 2)
   end
end

local function assertTrue(cond, label)
   if not cond then error(label or "expected true", 2) end
end

-- Optimize at `level`, then generate. Presizing reads only the shape of the
-- tree, so checking is not needed to exercise it.
local function compile(src, level)
   local result = parser.parse(src, "test")
   assertEq(#result.errors, 0, "syntax errors in test source")
   local remarks = optimize.run(result, {level = level or 2})
   local code, diags = gen.generate(result, "test")
   assertEq(#diags, 0, "gen diagnostics for " .. src)
   return code, remarks
end

local function sized(src)
   local code = compile(src)
   return code:match("__nuppNew%((%d+),(%d+)%)")
end

local function run(src, ...)
   local code = compile(src)
   local chunk, err = loadstring(code, "@optimize_test")
   if not chunk then
      error("generated code does not load: " .. tostring(err)
         .. "\n---\n" .. code, 2)
   end
   return chunk(...)
end

local M = {}

function M.presizesARunOfNamedFields()
   local narr, nhash = sized("local t = {}\nt.a = 1\nt.b = 2\nreturn t")
   assertEq(narr, "0", "array part")
   assertEq(nhash, "2", "hash part")
end

function M.presizesArrayIndices()
   local narr, nhash = sized("local t = {}\nt[1] = 1\nt[2] = 2\nreturn t")
   assertEq(narr, "2", "array part")
   assertEq(nhash, "0", "hash part")
end

function M.presizesStringLiteralKeys()
   local narr, nhash = sized(
      "local t = {}\nt['a'] = 1\nt['b'] = 2\nreturn t")
   assertEq(narr, "0", "array part")
   assertEq(nhash, "2", "hash part")
end

function M.countsARepeatedKeyOnce()
   local _, nhash = sized(
      "local t = {}\nt.a = 1\nt.a = 2\nt.b = 3\nreturn t")
   assertEq(nhash, "2", "a repeated key is one slot")
end

function M.countsAnOpaqueKeyAsOneSlot()
   local narr, nhash = sized(
      "local k = 'x'\nlocal t = {}\nt[k] = 1\nt.b = 2\nreturn t")
   assertEq(narr, "0", "array part")
   assertEq(nhash, "2", "hash part")
end

function M.stepsOverUnrelatedStatements()
   local _, nhash = sized(
      "local t = {}\nt.a = 1\nlocal z = 5\nt.b = 2\nreturn t")
   assertEq(nhash, "2", "an unrelated statement cannot reach the table")
end

function M.leavesASingleFieldAlone()
   assertEq(sized("local t = {}\nt.a = 1\nreturn t"), nil,
      "one field is not worth a call")
end

function M.leavesANonEmptyConstructorAlone()
   assertEq(sized("local t = {1, 2}\nt.a = 1\nt.b = 2\nreturn t"), nil,
      "a constructor with entries is already sized by its entries")
end

function M.stopsWhenTheTableEscapes()
   assertEq(sized(
      "local t = {}\nprint(t)\nt.a = 1\nt.b = 2\nreturn t"), nil,
      "a call may keep the table, so the count is only a guess after it")
end

function M.stopsWhenTheTableIsRead()
   assertEq(sized(
      "local t = {}\nlocal z = t\nt.a = 1\nt.b = 2\nreturn t"), nil,
      "an alias may be written through")
end

function M.stopsWhenTheTableIsReassigned()
   assertEq(sized(
      "local t = {}\nt = {}\nt.a = 1\nt.b = 2\nreturn t"), nil,
      "the constructor no longer decides what the name holds")
end

function M.stopsAtAConditionalWrite()
   assertEq(sized(
      "local t = {}\nif x then t.a = 1 end\nt.b = 2\nreturn t"), nil,
      "a nested block is not scanned")
end

function M.stopsAtAShadowingDeclaration()
   local code = compile(
      "local t = {}\nlocal t = {}\nt.a = 1\nt.b = 2\nreturn t")
   local _, count = code:gsub("__nuppNew%(", "")
   assertEq(count, 1, "only the second t is presized")
end

function M.presizesInsideAFunctionBody()
   local narr, nhash = sized(
      "local function f()\n   local t = {}\n   t.a = 1\n   t.b = 2\n"
      .. "   return t\nend\nreturn f")
   assertEq(narr, "0", "array part")
   assertEq(nhash, "2", "hash part")
end

function M.levelZeroDoesNothing()
   local code = compile("local t = {}\nt.a = 1\nt.b = 2\nreturn t", 0)
   assertEq(code:match("__nuppNew"), nil, "-O0 performs no optimization")
   assertTrue(code:match("{%s*}") ~= nil, "the constructor is left alone")
end

function M.aDisabledPassDoesNothing()
   local result = parser.parse("local t = {}\nt.a = 1\nt.b = 2\nreturn t",
      "test")
   optimize.run(result, {level = 2, disabled = {["OPT-1"] = true}})
   local code = gen.generate(result, "test")
   assertEq(code:match("__nuppNew"), nil, "-Zno-opt=OPT-1 performs no rewrite")
end

function M.preservesTheLineCount()
   local src = "local t = {}\nt.a = 1\nt.b = 2\nreturn t"
   local code = compile(src)
   local function lines(s)
      local _, n = s:gsub("\n", "")
      return n
   end
   assertEq(lines(code), lines(src) + 1, "generated line count matches source")
end

function M.behavesTheSameAsAnEmptyConstructor()
   local t = run("local t = {}\nt.a = 1\nt.b = 2\nt[1] = 'x'\nreturn t")
   assertEq(type(t), "table", "a table is still what comes back")
   assertEq(t.a, 1, "t.a")
   assertEq(t.b, 2, "t.b")
   assertEq(t[1], "x", "t[1]")
   assertEq(#t, 1, "length")
   local keys = 0
   for _ in pairs(t) do keys = keys + 1 end
   assertEq(keys, 3, "iteration sees exactly what was assigned")
end

function M.anEmptyPresizedTableIsStillEmpty()
   local t = run("local t = {}\nt.a = nil\nt.b = nil\nreturn t")
   assertEq(next(t), nil, "assigning nil leaves the table empty")
end

function M.remarksOnWhatItDid()
   local _, remarks = compile("local t = {}\nt.a = 1\nt.b = 2\nreturn t")
   assertEq(#remarks, 1, "one remark")
   assertEq(remarks[1].code, "OPT-1", "code")
   assertEq(remarks[1].severity, "note", "a remark is reported and stepped over")
   assertEq(remarks[1].line, 1, "attributed to the constructor")
   assertTrue(remarks[1].msg:match("room for 0 array and 2 hash") ~= nil,
      "says what it did: " .. remarks[1].msg)
end

function M.remarksOnWhatItDeclined()
   local _, remarks = compile(
      "local t = {}\nprint(t)\nt.a = 1\nt.b = 2\nreturn t")
   assertEq(#remarks, 1, "one remark")
   assertEq(remarks[1].code, "OPT-1", "code")
   assertTrue(remarks[1].msg:match("not presized") ~= nil,
      "says what it declined: " .. remarks[1].msg)
   assertEq(remarks[1].related[1].line, 2, "points at the use that stopped it")
end

function M.saysNothingWhenThereIsNothingToSay()
   local _, remarks = compile("local x = 1\nreturn x")
   assertEq(#remarks, 0, "no remark without a candidate")
end

function M.levelZeroRemarksNothing()
   local _, remarks = compile("local t = {}\nt.a = 1\nt.b = 2\nreturn t", 0)
   assertEq(#remarks, 0, "a pass that did not run has nothing to report")
end

return M
