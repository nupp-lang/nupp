local parser = require("nupp.parser")
local optimize = require("nupp.optimize")
local gen = require("nupp.gen")
local check = require("nupp.check")
local envMod = require("nupp.env")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local env = envMod.new(HERE .. "/..")

local function assertEq(got, want, label)
   if got ~= want then
      error(("%s:\n  want: %s\n  got:  %s"):format(label or "mismatch",
         tostring(want), tostring(got)), 2)
   end
end

local function assertTrue(cond, label)
   if not cond then error(label or "expected true", 2) end
end

-- Optimize at `level`, then generate. The effect-based passes consume definition
-- and type facts left by checking; presizing remains syntax-only.
local function compile(src, level)
   local result = parser.parse(src, "test")
   assertEq(#result.errors, 0, "syntax errors in test source")
   check.check(result, "test", env)
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

function M.foldsExactPrimitiveArithmetic()
   local code = compile("return (2 + 3) * 4")
   assertTrue(code:find("return 20", 1, true) ~= nil,
      "the expression is emitted as its exact result: " .. code)
   assertEq(run("return (2 + 3) * 4"), 20, "folded arithmetic result")
end

function M.propagatesConstBindings()
   local code = compile("const size = 6\nreturn size * 7")
   assertTrue(code:find("return 42", 1, true) ~= nil,
      "a const use is replaced by its value: " .. code)
   assertEq(run("const size = 6\nreturn size * 7"), 42,
      "propagated arithmetic result")
end

function M.foldsPrimitiveStringsAndTruthiness()
   local code = compile("const prefix = 'nu'\nreturn (false or prefix) .. 'pp'")
   assertTrue(code:find('return "nupp"', 1, true) ~= nil,
      "primitive string and logical expressions fold: " .. code)
   assertEq(run("const prefix = 'nu'\nreturn (false or prefix) .. 'pp'"), "nupp",
      "folded string result")
end

function M.leavesFloatingPointArithmeticForTheTarget()
   local code = compile("return 1.5 + 2")
   assertTrue(code:find("1.5 + 2", 1, true) ~= nil,
      "floating-point arithmetic remains a target operation: " .. code)
end

function M.doesNotPropagateMutableBindings()
   local code = compile("local size = 6\nreturn size * 7")
   assertTrue(code:find("size * 7", 1, true) ~= nil,
      "only const bindings are propagated: " .. code)
end

function M.aDisabledConstantFoldPassDoesNothing()
   local result = parser.parse("return 2 + 3", "test")
   optimize.run(result, {level = 2, disabled = {["OPT-3"] = true}})
   local code = gen.generate(result, "test")
   assertTrue(code:find("2 + 3", 1, true) ~= nil,
      "-Zno-opt=OPT-3 preserves the source expression")
end

function M.rewritesStableDeclaredArrayIteration()
   local code, remarks = compile(
      "local xs: {integer} = {1, 2, 3}\nlocal sum = 0\n"
      .. "for _, value in ipairs(xs) do sum = sum + value end\nreturn sum")
   assertTrue(code:find("for __nuppT", 1, true) ~= nil,
      "numeric loop uses a proved static bound: " .. code)
   assertEq(run("local xs: {integer} = {1, 2, 3}\nlocal sum = 0\n"
      .. "for _, value in ipairs(xs) do sum = sum + value end\nreturn sum"),
      6, "numeric loop result")
   local found = false
   for _, entry in ipairs(remarks) do
      if entry.code == "OPT-2" then found = true end
   end
   assertTrue(found, "the rewrite emits an OPT-2 remark")
end

function M.rewritesProvenLoopsInsideFunctions()
   local code = compile(table.concat({
      "local function total(): number",
      "   local xs: {integer} = {2, 3}",
      "   local sum = 0",
      "   for _, value in ipairs(xs) do sum = sum + value end",
      "   return sum",
      "end",
      "return total()",
   }, "\n"))
   assertTrue(code:find("for __nuppT", 1, true) ~= nil,
      "function-local loops use the same proof: " .. code)
end

function M.keepsIpairsWhenDenseEntryIsNotProven()
   local code = compile(table.concat({
      "local function total(xs: {integer}): number",
      "   local sum = 0",
      "   for _, value in ipairs(xs) do sum = sum + value end",
      "   return sum",
      "end",
   }, "\n"))
   assertTrue(code:find("in ipairs", 1, true) ~= nil,
      "an array type alone does not prove its Lua boundary: " .. code)
end

function M.keepsIpairsWhenArrayShapeChanges()
   local code, remarks = compile(
      "local xs: {integer} = {1, 2, 3}\nlocal seen = 0\n"
      .. "for i, value in ipairs(xs) do\n"
      .. "   seen = seen + 1\n   if i == 2 then xs[4] = 4 end\nend\n"
      .. "return seen")
   assertTrue(code:find("in ipairs", 1, true) ~= nil,
      "mutating iteration keeps ipairs: " .. code)
   assertEq(run("local xs: {integer} = {1, 2, 3}\nlocal seen = 0\n"
      .. "for i, value in ipairs(xs) do\n"
      .. "   seen = seen + 1\n   if i == 2 then xs[4] = 4 end\nend\n"
      .. "return seen"), 4, "ipairs observes an append")
   local declined = false
   for _, entry in ipairs(remarks) do
      if entry.code == "OPT-2" and entry.msg:find("not rewritten", 1, true) then
         declined = true
      end
   end
   assertTrue(declined, "the declined proof is reported")
end

function M.keepsIpairsWhenACalledClosureMutatesTheArray()
   local code = compile(table.concat({
      "local xs: {integer} = {1, 2, 3}",
      "local function grow() xs[4] = 4 end",
      "for i, value in ipairs(xs) do if i == 2 then grow() end end",
   }, "\n"))
   assertTrue(code:find("in ipairs", 1, true) ~= nil,
      "a captured shape effect stops the rewrite: " .. code)
end

function M.tracksAliasesReturnedByVisibleFunctions()
   local code = compile(table.concat({
      "local xs: {integer} = {1, 2, 3}",
      "local function same(values: {integer}): {integer} return values end",
      "local alias = same(xs)",
      "for i, value in ipairs(xs) do if i == 2 then alias[4] = 4 end end",
   }, "\n"))
   assertTrue(code:find("in ipairs", 1, true) ~= nil,
      "a returned alias stops the rewrite: " .. code)
end

function M.keepsIpairsForAliasesStoredInTables()
   local code = compile(table.concat({
      "local xs: {integer} = {1, 2, 3}",
      "local aliases = {xs}",
      "local alias = aliases[1]",
      "for i, value in ipairs(xs) do if i == 2 then alias[4] = 4 end end",
   }, "\n"))
   assertTrue(code:find("in ipairs", 1, true) ~= nil,
      "an alias that entered a table stops the rewrite: " .. code)
end

function M.keepsIpairsAfterTheArrayBindingIsReassigned()
   local code = compile(table.concat({
      "local xs: {integer} = {1, 2, 3}",
      "xs = {4, 5, 6, 7}",
      "for _, value in ipairs(xs) do print(value) end",
   }, "\n"))
   assertTrue(code:find("in ipairs", 1, true) ~= nil,
      "the original literal bound does not survive reassignment: " .. code)
end

function M.allowsCallsWhoseShapeEffectsStayLocal()
   local code = compile(table.concat({
      "local function scratch()",
      "   local temporary: {integer} = {1}",
      "   temporary[2] = 2",
      "end",
      "local xs: {integer} = {1, 2, 3}",
      "for _, value in ipairs(xs) do scratch() end",
   }, "\n"))
   assertTrue(code:find("for __nuppT", 1, true) ~= nil,
      "unrelated local mutation leaves the proof intact: " .. code)
end

function M.doesNotRewriteShadowedIpairs()
   local code = compile(
      "local function ipairs(xs) return next, xs, nil end\n"
      .. "local xs: {integer} = {7}\nfor i, value in ipairs(xs) do break end")
   assertEq(code:find("for __nuppT", 1, true), nil,
      "a shadowed iterator is not the builtin")
end

function M.levelZeroKeepsIpairs()
   local code = compile(
      "local xs: {integer} = {1}\nfor _, value in ipairs(xs) do print(value) end",
      0)
   assertTrue(code:find("in ipairs", 1, true) ~= nil,
      "-O0 keeps generic iteration")
end

return M
