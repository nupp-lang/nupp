local parser = require("nupp.compiler.parser")
local optimize = require("nupp.compiler.optimize")
local constspecialize = require("nupp.compiler.constspecialize")
local gen = require("nupp.compiler.gen")
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

local function assertTrue(cond, label)
   if not cond then error(label or "expected true", 2) end
end

local function runOptimizer(result, options)
   local selected = {
      level = options and options.level or 0,
      filename = options and options.filename or "test.g.nupp",
      disabled = options and options.disabled or {},
      dialect = options and options.dialect or "luajit",
      constSelection = options and options.constSelection or nil,
   }
   return optimize.run(result, selected)
end

-- Optimize at `level`, then generate. The effect-based passes consume definition
-- and type facts left by checking; presizing remains syntax-only.
local function compile(src, level, coverage)
   local result = parser.parse(src, "test.g.nupp")
   assertEq(#result.errors, 0, "syntax errors in test source")
   check.check(result, "test.g.nupp", env)
   local remarks = runOptimizer(result, {level = level or 2})
   local code, diags = gen.generate(result, "test", coverage)
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
   local code = compile("local t = {}\nt.a = 1\nt.b = 2\nreturn t")
   assertTrue(code:match("local t%s*=%s*{%s*a%s*=%s*1%s*,%s*b%s*=%s*2%s*,") ~= nil,
      "named writes become constructor fields: " .. code)
   assertEq(code:match("__nuppNew"), nil, "a literal needs no table.new call")
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

function M.keepsPresizingWhenNamedWritesHaveAGap()
   local narr, nhash = sized(
      "local t = {}\nt.a = 1\nlocal z = 5\nt.b = 2\nreturn t")
   assertEq(narr, "0", "array part")
   assertEq(nhash, "2", "hash part")
end

function M.keepsPresizingRepeatedNamedFields()
   local narr, nhash = sized(
      "local t = {}\nt.a = 1\nt.a = 2\nt.b = 3\nreturn t")
   assertEq(narr, "0", "array part")
   assertEq(nhash, "2", "hash part")
end

function M.constructorFieldsKeepValueOrderAndLines()
   local code = compile(
      "local seen = {}\n"
      .. "local function take(value) seen[#seen + 1] = value; return value end\n"
      .. "local t = {}\n"
      .. "t.a = take('a')\n"
      .. "t.b = take('b')\n"
      .. "return t, table.concat(seen)")
   local chunk = assert(loadstring(code, "@presize_lines"))
   local t, seen = chunk()
   assertEq(t.a, "a", "first field")
   assertEq(t.b, "b", "second field")
   assertEq(seen, "ab", "field values retain assignment order")
   assertTrue(code:match('\n%s*a%s*=%s*take%s*%(%s*"a"%s*%)') ~= nil,
      "the first value remains on its source line: " .. code)
   assertTrue(code:match('\n%s*b%s*=%s*take%s*%(%s*"b"%s*%)') ~= nil,
      "the second value remains on its source line: " .. code)
end

function M.coverageKeepsPresizedWritesAsStatements()
   local code = compile(
      "local t = {}\nt.a = 1\nt.b = 2\nreturn t",
      2,
      {path = "test.g.nupp"})
   assertTrue(code:match("__nuppNew%s*%(%s*0%s*,%s*2%s*%)") ~= nil,
      "coverage keeps the sized constructor: " .. code)
   assertTrue(code:match("t%s*%.%s*a%s*=%s*1") ~= nil,
      "coverage keeps the first assignment: " .. code)
   assertTrue(code:match("t%s*%.%s*b%s*=%s*2") ~= nil,
      "coverage keeps the second assignment: " .. code)
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
   local _, count = code:gsub("\na=", "")
   assertEq(count, 1, "only the second t is folded into its constructor")
end

function M.presizesInsideAFunctionBody()
   local code = compile(
      "local function f()\n   local t = {}\n   t.a = 1\n   t.b = 2\n"
      .. "   return t\nend\nreturn f")
   assertTrue(code:match("local t%s*=%s*{%s*a%s*=%s*1%s*,%s*b%s*=%s*2%s*,") ~= nil,
      "function-local writes become constructor fields: " .. code)
end

function M.levelZeroDoesNothing()
   local code = compile("local t = {}\nt.a = 1\nt.b = 2\nreturn t", 0)
   assertEq(code:match("__nuppNew"), nil, "-O0 performs no optimization")
   assertTrue(code:match("{%s*}") ~= nil, "the constructor is left alone")
end

function M.aDisabledPassDoesNothing()
   local result = parser.parse("local t = {}\nt.a = 1\nt.b = 2\nreturn t",
      "test")
   runOptimizer(result, {level = 2, disabled = {["OPT-1"] = true}})
   local code = gen.generate(result, "test")
   assertEq(code:match("__nuppNew"), nil, "-Zno-opt=OPT-1 performs no rewrite")
end

function M.optimizerOptionOwnsRemarkFilenames()
   local result = parser.parse("local t = {}\nt.a = 1\nt.b = 2\nreturn t",
      "parsed.g.nupp")
   check.check(result, "checked.g.nupp", env)
   result.filename = "incidental.g.nupp"
   local remarks = runOptimizer(result, {level = 1, filename = "selected.g.nupp"})
   assertTrue(#remarks > 0, "the fixture emits an optimizer remark")
   for _, entry in ipairs(remarks) do
      assertEq(entry.filename, "selected.g.nupp", "the option owns remark attribution")
   end
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
   assertTrue(remarks[1].msg:match("created with 2 named fields") ~= nil,
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

function M.propagatesScalarComptimeConstants()
   local src = [[
const banner = comptime do
   local parts = {"nupp", "compiles", "this", "once"}
   return table.concat(parts, " "):upper() .. " " .. string.rep("=", 8)
end
return banner
]]
   local code = compile(src)
   assertTrue(code:find('return "NUPP COMPILES THIS ONCE ========"', 1, true) ~= nil,
      "a scalar comptime const is propagated: " .. code)
   assertEq(run(src), "NUPP COMPILES THIS ONCE ========",
      "propagated comptime string")
end

function M.propagatesNestedConstFields()
   local src = table.concat({
      "local M = {}",
      "const M.bar = {",
      "   const BAZ = 123,",
      "   const nested = {const name = 'nupp'},",
      "}",
      "return M.bar.BAZ, M.bar.nested.name",
   }, "\n")
   local code = compile(src)
   assertTrue(code:find("return 123 , \"nupp\"", 1, true) ~= nil,
      "nested const paths are propagated: " .. code)
   local number, text = run(src)
   assertEq(number, 123, "nested number")
   assertEq(text, "nupp", "nested string")
end

function M.deepConstFieldsAreSugarForNestedConstFields()
   local src = table.concat({
      "local M = {}",
      "const... M.bar = {",
      "   BAZ = 123,",
      "   COUNT = 0,",
      "   nested = {name = 'nupp'},",
      "}",
      "return M.bar.BAZ, M.bar.nested.name",
   }, "\n")
   local code = compile(src)
   assertTrue(code:find("return 123 , \"nupp\"", 1, true) ~= nil,
      "deep const fields are propagated: " .. code)
   local number, text = run(src)
   assertEq(number, 123, "deep number")
   assertEq(text, "nupp", "deep string")
end

function M.doesNotPropagateAConstPathAfterItsRootIsReplaced()
   local src = table.concat({
      "local M = {}",
      "const M.bar = {const BAZ = 123}",
      "M = {bar = {BAZ = 456}}",
      "return M.bar.BAZ",
   }, "\n")
   local code = compile(src)
   assertTrue(code:find("return M . bar . BAZ", 1, true) ~= nil,
      "replacing the root invalidates nested facts: " .. code)
   assertEq(run(src), 456, "the replacement remains observable")
end

function M.propagatesNestedConstFieldsAcrossARequiredModule()
   local requiredEnv = envMod.new(HERE)
   local result = parser.parse(table.concat({
      "const Foo = require('fixtures.consts')",
      "return Foo.bar.BAZ, Foo.bar.nested.name",
   }, "\n"), "test")
   assertEq(#result.errors, 0, "consumer parses")
   local diags = check.check(result, "test.g.nupp", requiredEnv)
   assertEq(#diags, 0, "consumer checks")
   runOptimizer(result, {level = 1})
   local code, generatedDiags = gen.generate(result, "test")
   assertEq(#generatedDiags, 0, "consumer generates")
   assertTrue(code:find("return 123 , \"nupp\"", 1, true) ~= nil,
      "required module constants are propagated: " .. code)
end

function M.requiresEveryImportedPathEdgeToBeConst()
   local requiredEnv = envMod.new(HERE)
   local function generated(src)
      local result = parser.parse(src, "test.g.nupp")
      assertEq(#result.errors, 0, "consumer parses")
      local diags = check.check(result, "test.g.nupp", requiredEnv)
      assertEq(#diags, 0, "consumer checks")
      runOptimizer(result, {level = 1})
      local code, generatedDiags = gen.generate(result, "test")
      assertEq(#generatedDiags, 0, "consumer generates")
      return code
   end

   local mutableRoot = generated(table.concat({
      "local Foo = require('fixtures.consts')",
      "return Foo.bar.BAZ",
   }, "\n"))
   assertTrue(mutableRoot:find("Foo . bar . BAZ", 1, true) ~= nil,
      "a mutable require binding is not propagated: " .. mutableRoot)

   local mutableEdge = generated(table.concat({
      "const Foo = require('fixtures.consts')",
      "return Foo.replaceable.BAZ",
   }, "\n"))
   assertTrue(mutableEdge:find("Foo . replaceable . BAZ", 1, true) ~= nil,
      "a mutable parent field blocks propagation: " .. mutableEdge)
end

function M.bindsRepeatedImmutableDottedCallees()
   local requiredEnv = envMod.new(HERE)
   local result = parser.parse(table.concat({
      "const Foo = require('fixtures.consts')",
      "Foo.api.ping(1)",
      "Foo.api.ping(2)",
   }, "\n"), "test")
   assertEq(#result.errors, 0, "consumer parses")
   local diags = check.check(result, "test.g.nupp", requiredEnv)
   assertEq(#diags, 0, "consumer checks")
   local remarks = runOptimizer(result, {level = 1})
   local code, generatedDiags = gen.generate(result, "test")
   assertEq(#generatedDiags, 0, "consumer generates")
   assertTrue(code:find("const __nupp_call_1= Foo . api . ping", 1, true) ~= nil,
      "first call binds the immutable path: " .. code)
   assertEq(select(2, code:gsub("__nupp_call_1", "")), 3,
      "one declaration and two calls use the generated binding")
   assertEq(select(2, code:gsub("Foo . api . ping", "")), 1,
      "the dotted path is read only once")
   local found = false
   for _, remark in ipairs(remarks) do
      if remark.code == "OPT-4" then found = true end
   end
   assertTrue(found, "OPT-4 reports the static binding")
end

function M.leavesSingleOrMutableDottedCalleesAlone()
   local requiredEnv = envMod.new(HERE)
   local function generated(src)
      local result = parser.parse(src, "test.g.nupp")
      assertEq(#result.errors, 0, "consumer parses")
      check.check(result, "test.g.nupp", requiredEnv)
      runOptimizer(result, {level = 1})
      return gen.generate(result, "test")
   end

   local single = generated(table.concat({
      "const Foo = require('fixtures.consts')",
      "Foo.api.ping(1)",
   }, "\n"))
   assertEq(single:find("__nupp_call_", 1, true), nil,
      "one call does not pay for a binding")

   local mutable = generated(table.concat({
      "local Foo = require('fixtures.consts')",
      "Foo.api.ping(1)",
      "Foo.api.ping(2)",
   }, "\n"))
   assertEq(mutable:find("__nupp_call_", 1, true), nil,
      "a mutable root is not statically bound")
end

function M.leavesStaticCalleesAloneAcrossGotoScopes()
   local requiredEnv = envMod.new(HERE)
   local result = parser.parse(table.concat({
      "const Foo = require('fixtures.consts')",
      "goto ready",
      "Foo.api.ping(1)",
      "::ready::",
      "Foo.api.ping(2)",
   }, "\n"), "test")
   assertEq(#result.errors, 0, "goto consumer parses")
   check.check(result, "test.g.nupp", requiredEnv)
   runOptimizer(result, {level = 1})
   local code = gen.generate(result, "test")
   assertEq(code:find("__nupp_call_", 1, true), nil,
      "a generated local must not change goto scope")
end

function M.staticCallableNamesDoNotCollideWithSourceNames()
   local requiredEnv = envMod.new(HERE)
   local result = parser.parse(table.concat({
      "local __nupp_call_1 = true",
      "const Foo = require('fixtures.consts')",
      "Foo.api.ping(1)",
      "Foo.api.ping(2)",
   }, "\n"), "test")
   check.check(result, "test.g.nupp", requiredEnv)
   runOptimizer(result, {level = 1})
   local code = gen.generate(result, "test")
   assertTrue(code:find("const __nupp_call_2=", 1, true) ~= nil,
      "generated names skip user identifiers: " .. code)
end

function M.aDisabledStaticCallablePassDoesNothing()
   local requiredEnv = envMod.new(HERE)
   local result = parser.parse(table.concat({
      "const Foo = require('fixtures.consts')",
      "Foo.api.ping(1)",
      "Foo.api.ping(2)",
   }, "\n"), "test")
   check.check(result, "test.g.nupp", requiredEnv)
   runOptimizer(result, {level = 1, disabled = {["OPT-4"] = true}})
   local code = gen.generate(result, "test")
   assertEq(code:find("__nupp_call_", 1, true), nil,
      "-Zno-opt=OPT-4 preserves dotted calls")
end

function M.staticCallableBindingPreservesRuntimeBehavior()
   local src = table.concat({
      "local calls = 0",
      "local function ping(n: integer): integer",
      "   calls += 1",
      "   return n + 1",
      "end",
      "const Root = {const api = {const ping = ping}}",
      "Root.api.ping(1)",
      "Root.api.ping(2)",
      "return calls",
   }, "\n")
   assertEq(run(src), 2, "the bound callable is invoked normally")
end

function M.foldsPrimitiveStringsAndTruthiness()
   local code = compile("const prefix = 'nu'\nreturn (false or prefix) .. 'pp'")
   assertTrue(code:find('return "nupp"', 1, true) ~= nil,
      "primitive string and logical expressions fold: " .. code)
   assertEq(run("const prefix = 'nu'\nreturn (false or prefix) .. 'pp'"), "nupp",
      "folded string result")
end

function M.foldsExactPrimitiveComparisons()
   local code = compile("return 'nupp' < 'rust' and 9 >= 3")
   assertTrue(code:find("return true", 1, true) ~= nil,
      "primitive comparisons fold: " .. code)
   assertEq(run("return 'nupp' < 'rust' and 9 >= 3"), true,
      "folded comparison result")
end

-- Lua's grammar takes only a name, a parenthesized expression, or another
-- suffixed expression as the prefix of a call or an index, and every fold puts a
-- scalar literal there. Emitting the bare literal produced Lua that would not
-- parse, which gen then reported as NUPP3005 against a program that was fine.
function M.parenthesizesAFoldedCallOrIndexPrefix()
   local written = "return ('abc'):find('b')"
   local writtenCode = compile(written)
   assertTrue(writtenCode:match('%("abc"%)%s*:%s*find') ~= nil,
      "written parentheses survive the fold: " .. writtenCode)
   assertEq(run(written), 2, "folded receiver still finds the byte")

   local propagated = "const greeting = 'hello'\nreturn greeting:upper()"
   local propagatedCode = compile(propagated)
   assertTrue(propagatedCode:match('%("hello"%)%s*:%s*upper') ~= nil,
      "a const receiver gains parentheses it never had: " .. propagatedCode)
   assertEq(run(propagated), "HELLO", "folded const receiver still upper-cases")

   local indexed = "const greeting = 'hello'\nreturn greeting.byte ~= nil"
   assertEq(run(indexed), true, "a folded index prefix loads and reads")
end

function M.elidesConstantConditionalArms()
   local src = table.concat({
      "if false then",
      "   error('unreachable')",
      "elseif true then",
      "   return 9",
      "else",
      "   return 10",
      "end",
   }, "\n")
   local code = compile(src)
   assertEq(code:find("unreachable", 1, true), nil,
      "the false arm is absent from generated code")
   assertEq(code:find("return 10", 1, true), nil,
      "the unselected else arm is absent from generated code")
   assertEq(run(src), 9, "the selected arm remains")
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

function M.foldsFloorDivisionAsItIsLowered()
   local code = compile("return 103 // 64")
   assertTrue(code:find("return 1", 1, true) ~= nil,
      "floor division folds: " .. code)
   assertEq(code:find("math.floor", 1, true), nil,
      "folding it also removes the call it lowers to: " .. code)
   assertEq(run("return 103 // 64"), 1, "folded floor division result")
end

function M.foldsTheAlignUpIdiomWhole()
   -- The point of `//` folding: with it the whole expression collapses, because the
   -- quotient makes the multiplication constant in turn.
   local src = "const CACHE = 64\nconst RAW = 40\n"
      .. "return (RAW + CACHE - 1) // CACHE * CACHE"
   local code = compile(src)
   assertTrue(code:find("return 64", 1, true) ~= nil,
      "aligning a constant up folds to one literal: " .. code)
   assertEq(run(src), 64, "folded alignment result")
end

function M.leavesFloorDivisionByZeroAtRuntime()
   local code = compile("return 1 // 0")
   assertTrue(code:find("math.floor", 1, true) ~= nil,
      "a zero divisor keeps the lowered division: " .. code)
end

function M.leavesFloorDivisionOfFloatsAtRuntime()
   local code = compile("return 1.5 // 2")
   assertTrue(code:find("math.floor", 1, true) ~= nil,
      "float operands are not exact, so they stay: " .. code)
end

function M.foldsBitwiseOperatorsAsTheRuntimeDoes()
   -- BitOp is the declared meaning of these operators, so the check that matters is
   -- not that a particular answer is right but that the folded answer is the one the
   -- unfolded program produces. Both sides are compiled from the same source; only
   -- the level differs.
   local values = {0, 1, 2, 3, 7, 8, 31, 32, 33, 255, 65535, -1, -2, -8,
      2147483647, -2147483648, 4294967295, 9007199254740991}
   for _, op in ipairs({"&", "|", "~", "<<", ">>", "~>>"}) do
      for _, left in ipairs(values) do
         for _, right in ipairs(values) do
            local src = ("return (%d) %s (%d)"):format(left, op, right)
            local folded, plain = compile(src, 1), compile(src, 0)
            assertTrue(folded:find("%d", 1, true) == nil,
               "no operator survives folding: " .. folded)
            local want = assert(loadstring(plain, "@plain"))()
            local got = assert(loadstring(folded, "@folded"))()
            assertEq(got, want, "folded " .. src)
         end
      end
   end
end

function M.foldsBitwiseComplement()
   local code = compile("return ~0")
   assertTrue(code:find("return -1", 1, true) ~= nil,
      "complement folds to its signed 32-bit result: " .. code)
   assertEq(run("return ~0"), -1, "folded complement result")
end

function M.foldsBitwiseOperatorsWithTheirThirtyTwoBitWrap()
   -- Named separately because these are the answers a reader assumes are bugs. A
   -- shift count is taken modulo 32, and `>>` is logical where `~>>` is arithmetic.
   assertEq(run("return 1 << 32"), 1, "a shift count wraps at 32")
   assertEq(run("return -8 >> 1"), 2147483644, "the plain shift is logical")
   assertEq(run("return -8 ~>> 1"), -4, "the tilde shift is arithmetic")
   local code = compile("return 1 << 32")
   assertTrue(code:find("return 1", 1, true) ~= nil,
      "the wrap happens at compile time too: " .. code)
end

function M.leavesBitwiseOperatorsOnMutableOperandsAlone()
   local code = compile("local shift = 3\nreturn 1 << shift")
   assertTrue(code:find("1 << shift", 1, true) ~= nil,
      "a mutable operand keeps the operator: " .. code)
end

function M.leavesBitwiseOperatorsOnBoxedIntegersAlone()
   -- A `LL` literal is cdata, whose representation is not a source rewrite's business.
   local code = compile("return 1LL << 2")
   assertTrue(code:find("1LL << 2", 1, true) ~= nil,
      "boxed integers keep the operator: " .. code)
end

function M.removesAWhileLoopWhoseTestIsConstantlyFalse()
   local src = "local seen = 0\nwhile false do seen = seen + 1 end\nreturn seen"
   local code = compile(src)
   assertEq(code:find("seen = seen + 1", 1, true), nil,
      "the body of a loop that cannot run is absent: " .. code)
   assertEq(run(src), 0, "the loop contributed nothing to run")
end

function M.removesANumericLoopWhoseBoundsAdmitNoIteration()
   for _, header in ipairs({"for i = 1, 0", "for i = 10, 1", "for i = 1, 10, -1"}) do
      local src = "local seen = 0\n" .. header
         .. " do seen = seen + i end\nreturn seen"
      local code = compile(src)
      assertEq(code:find("seen = seen + i", 1, true), nil,
         "the body is absent for " .. header .. ": " .. code)
      assertEq(run(src), 0, "no iteration ran for " .. header)
   end
end

function M.keepsALoopThatRuns()
   local src = "local seen = 0\nfor i = 1, 3 do seen = seen + i end\nreturn seen"
   local code = compile(src)
   assertTrue(code:find("seen = seen + i", 1, true) ~= nil,
      "a loop with iterations keeps its body: " .. code)
   assertEq(run(src), 6, "the loop ran")
end

function M.keepsALoopWhoseStepIsZero()
   -- `for i = 1, 10, 0` does not terminate. Deleting it would be deleting the hang,
   -- which is a change to what the program does rather than to how fast it does it.
   local code = compile("for i = 1, 10, 0 do print(i) end")
   assertTrue(code:find("for i = 1 , 10 , 0", 1, true) ~= nil,
      "a zero step is left alone: " .. code)
end

function M.keepsALoopWhoseStepIsNotConstant()
   -- The bounds read as empty only under the default step of 1, and the step is not
   -- known to be 1. A negative one gives the loop an iteration.
   local src = "local step = -1\nlocal seen = 0\n"
      .. "for i = 1, 0, step do seen = seen + 1 end\nreturn seen"
   local code = compile(src)
   assertTrue(code:find("for i = 1 , 0 , step", 1, true) ~= nil,
      "an unproved step keeps the loop: " .. code)
   assertEq(run(src), 2, "the loop this would have deleted runs twice")
end

function M.usesAProvedStepToRemoveALoop()
   local src = "const step = 1\nlocal seen = 0\n"
      .. "for i = 1, 0, step do seen = seen + 1 end\nreturn seen"
   local code = compile(src)
   assertEq(code:find("seen = seen + 1", 1, true), nil,
      "a proved step completes the proof: " .. code)
   assertEq(run(src), 0, "no iteration ran")
end

function M.keepsALoopWhoseBoundsAreNotConstant()
   local code = compile("local last = 3\nfor i = 1, last do print(i) end")
   assertTrue(code:find("for i = 1 , last", 1, true) ~= nil,
      "an unproved bound keeps the loop: " .. code)
end

function M.keepsAWhileLoopWhoseTestIsNotConstant()
   local code = compile("local going = true\nwhile going do going = false end")
   assertTrue(code:find("while going do", 1, true) ~= nil,
      "an unproved test keeps the loop: " .. code)
end

function M.removingALoopPreservesTheLineCount()
   local src = "local seen = 0\nwhile false do\n   seen = seen + 1\nend\nreturn seen\n"
   local code = compile(src)
   local function lines(text)
      local n = 1
      for _ in text:gmatch("\n") do n = n + 1 end
      return n
   end
   assertEq(lines(code), lines(src),
      "attribution survives by the line count holding: " .. code)
end

function M.aDisabledConstantFoldPassLeavesDeadLoopsAlone()
   local result = parser.parse("while false do print(1) end", "test")
   runOptimizer(result, {level = 2, disabled = {["OPT-3"] = true}})
   local code = gen.generate(result, "test")
   assertTrue(code:find("while false do", 1, true) ~= nil,
      "-Zno-opt=OPT-3 preserves the loop: " .. code)
end

function M.aDisabledConstantFoldPassDoesNothing()
   local result = parser.parse("return 2 + 3", "test")
   runOptimizer(result, {level = 2, disabled = {["OPT-3"] = true}})
   local code = gen.generate(result, "test")
   assertTrue(code:find("2 + 3", 1, true) ~= nil,
      "-Zno-opt=OPT-3 preserves the source expression")
end

function M.rewritesStableDeclaredArrayIteration()
   local code, remarks = compile(
      "local xs: {integer} = {1, 2, 3}\nlocal sum = 0\n"
      .. "for _, value in ipairs(xs) do sum = sum + value end\nreturn sum")
   assertTrue(code:find("for _=1,3 do", 1, true) ~= nil,
      "numeric loop uses a proved static bound: " .. code)
   assertEq(code:find("__nuppT", 1, true), nil,
      "the proved operand needs no generated alias")
   assertTrue(code:find("local value= xs [_]", 1, true) ~= nil,
      "the source loop value reads the array directly: " .. code)
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
   assertTrue(code:find("for _=1,2 do", 1, true) ~= nil,
      "function-local loops use the same proof: " .. code)
end

function M.usesTheSourceIndexAsTheNumericControlVariable()
   local code = compile(table.concat({
      "local xs: {integer} = {10, 20, 30}",
      "local sum = 0",
      "for index, value in ipairs(xs) do sum += index + value end",
      "return sum",
   }, "\n"))
   assertTrue(code:find("for index=1,3 do", 1, true) ~= nil,
      "the source index controls the numeric loop: " .. code)
   assertEq(code:find("local index=", 1, true), nil,
      "the index is not copied from a generated temporary")
   assertEq(run(table.concat({
      "local xs: {integer} = {10, 20, 30}",
      "local sum = 0",
      "for index, value in ipairs(xs) do sum += index + value end",
      "return sum",
   }, "\n")), 66, "direct index loop result")
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
   assertTrue(code:find("for _=1,3 do", 1, true) ~= nil,
      "unrelated local mutation leaves the proof intact: " .. code)
end

function M.doesNotRewriteShadowedIpairs()
   local code = compile(
      "local function ipairs(xs) return next, xs, nil end\n"
      .. "local xs: {integer} = {7}\nfor i, value in ipairs(xs) do break end")
   assertTrue(code:find("in ipairs", 1, true) ~= nil,
      "a shadowed iterator is not rewritten")
end

function M.levelZeroKeepsIpairs()
   local code = compile(
      "local xs: {integer} = {1}\nfor _, value in ipairs(xs) do print(value) end",
      0)
   assertTrue(code:find("in ipairs", 1, true) ~= nil,
      "-O0 keeps generic iteration")
end

-- OPT-7: a module's own single-return local helpers, inlined where they are called.

function M.inlinesASingleReturnHelper()
   local code = compile(
      "local function twice(v: number): number return v * 2.0 end\n"
      .. "local function m(x: number): number return twice(x) end\nreturn m")
   assertTrue(code:find("return ( x * 2 )", 1, true) ~= nil,
      "the call became the helper's expression: " .. code)
end

--- A helper whose body constructs a record substitutes into every field.
---
--- The named fields of `new T(...)` hold their value expressions where the copy's
--- array walk does not reach them, so a splice that followed only the array part
--- handed back the helper's own tree: the parameter travelled into the caller as
--- a free name, read as a nil global, and only where the argument happened to be
--- spelled like the parameter did the program still work.
---
--- Run rather than read, because the helper's own declaration keeps its parameter
--- name whatever the splice did, and because a surviving parameter is a nil global
--- -- reading nil out of a field is not itself an error, so the answer is what has
--- to be asked for.
function M.inlinesAHelperThatConstructsARecord()
   local source = "record Pair\n    first: number\n    second: number\nend\n"
      .. "local function pair(value: number): Pair return new Pair(first = value, second = value + 1.0) end\n"
      .. "local function m(): number local other = 7.0 local made = pair(other) return made.first + made.second end\n"
      .. "return m()"
   assertEq(run(source), 15.0, "the inlined spelling answers")
   assertEq(run(source), run(source, 0), "and answers what the call answered")
end

--- The same where the field's value is an index of the parameter rather than the
--- parameter itself, which is the shape `nupp.compiler.annotatedlua` was built on
--- and the one that reached a nil global in the compiler's own source.
function M.inlinesAHelperThatReadsAFieldOfItsParameter()
   local source = "record Spot\n    line: number\nend\n"
      .. "record Held\n    at: number\nend\n"
      .. "local function held(spot: Spot): Held return new Held(at = spot.line) end\n"
      .. "local function m(): number local somewhereElse = new Spot(line = 3.0) return held(somewhereElse).at end\n"
      .. "return m()"
   assertEq(run(source), 3.0, "the inlined spelling answers")
   assertEq(run(source), run(source, 0), "and answers what the call answered")
end

function M.inliningDoesNotChangeTheAnswer()
   local inlined = run(
      "local function mix(a: number, b: number): number return a * 3.0 - b end\n"
      .. "local function m(): number local x = 4.0 local y = 1.0 return mix(x, y) end\nreturn m()")
   local kept = run(
      "local function mix(a: number, b: number): number return a * 3.0 - b end\n"
      .. "local function m(): number local x = 4.0 local y = 1.0 return mix(x, y) end\nreturn m()", 0)
   assertEq(inlined, 11.0, "the inlined spelling answers")
   assertEq(inlined, kept, "and answers what the call answered")
end

function M.keepsPrecedenceWhereTheCallStood()
   -- The helper's body is a sum and the call sits under a multiply. Splicing it
   -- without the call's own parentheses would reassociate the arithmetic.
   local value = run(
      "local function plus(a: number, b: number): number return a + b end\n"
      .. "local function m(): number local x = 2.0 local y = 3.0 return 10.0 * plus(x, y) end\nreturn m()")
   assertEq(value, 50.0, "the spliced expression keeps the call's parentheses")
end

function M.inlinesAHelperThatGeneratesToSomethingElse()
   -- `nupp.math.u32.wrap` is not a call in the generated line, so this is the case a
   -- text substitution cannot write: the tree is spliced and `gen` lowers it at the
   -- site it now stands.
   local code = compile(
      "local function wrapped(v: integer): uint32 return nupp.math.u32.wrap(v) end\n"
      .. "local function m(x: integer): uint32 return wrapped(x) end\nreturn m")
   assertTrue(code:find("nupp.math.u32.wrap", 1, true) == nil,
      "the intrinsic did not survive as source: " .. code)
   assertTrue(code:find("__nuppBitTobit", 1, true) ~= nil,
      "it generated as the intrinsic it is, twice: " .. code)
end

function M.keepsACallInStatementPosition()
   -- A parenthesized expression is not a Lua statement, so a call standing alone has
   -- nowhere to become one however inlinable its helper is.
   local code = compile(
      "local function noted(v: number): number return v * 2.0 end\n"
      .. "local function m(x: number): nil noted(x) end\nreturn m")
   assertTrue(code:find("noted ( x )", 1, true) ~= nil,
      "the statement call is left alone: " .. code)
end

function M.keepsACallPassingALiteralToAReceiver()
   -- Lua takes only a name or a parenthesized expression as the object of a method
   -- call, so a literal substituted into one does not parse. The value would have been
   -- right and the line would not have loaded.
   local code = compile(
      'local function trimmed(s: string): string return s:gsub("%s+$", "") end\n'
      .. 'local function m(): string return trimmed("text  ") end\nreturn m')
   assertTrue(code:find("trimmed (", 1, true) ~= nil,
      "a literal is not spliced into a receiver position: " .. code:sub(-200))
end

function M.inlinesAPureComputedArgument()
   -- An operator tree over names and literals has no observable evaluation. It
   -- can be duplicated when the parameter is read twice without duplicating an
   -- effect, which is the common arithmetic-helper shape this pass exists for.
   local code = compile(
      "local function twice(v: number): number return v + v end\n"
      .. "local function m(x: number): number return twice(x * 3.0) end\nreturn m")
   assertTrue(code:find("return twice (", 1, true) == nil
      and code:find("x * 3 + x * 3", 1, true) ~= nil,
      "a pure computed argument was spliced: " .. code)
end

function M.keepsACallWhoseComputedArgumentHasAnEffect()
   local code = compile(
      "local function twice(v: number): number return v + v end\n"
      .. "local function m(nextValue: function(): number): number return twice(nextValue()) end\nreturn m")
   assertTrue(code:find("twice (", 1, true) ~= nil,
      "an effectful computed argument keeps its call: " .. code)
end

-- OPT-8: closed scalar const applications become bounded private bodies.

local CONST_ACCUMULATE = table.concat({
   "local function accumulate<const N: integer>(value: number, count: N): number",
   "   local total = value",
   "   for offset = 1, count as integer do",
   "      total = total + offset",
   "   end",
   "   return total",
   "end",
   "return accumulate(10.0, 4)",
}, "\n")

function M.monomorphizesAClosedConstApplication()
   local code, remarks = compile(CONST_ACCUMULATE)
   assertTrue(code:find("local function __nuppConst_accumulate_", 1, true) ~= nil,
      "a private body was emitted: " .. code)
   assertTrue(code:find("__nuppConst_accumulate_", 1, true)
      < code:find("( 10", 1, true), "the call names the private body")
   local found = false
   for _, entry in ipairs(remarks) do
      found = found or entry.code == "OPT-8"
   end
   assertTrue(found, "the rewrite emits an OPT-8 remark")
end

function M.usesASuppliedWholeDeliverableConstSelection()
   local result = parser.parse(CONST_ACCUMULATE, "test.g.nupp")
   assertEq(#result.errors, 0, "const selection fixture parses")
   local diagnostics = check.check(result, "test.g.nupp", env)
   assertEq(#diagnostics, 0, "const selection fixture checks")
   local plans = constspecialize.collect(result, "test.g.nupp")
   local accepted, declined = constspecialize.select(plans)
   local remarks, specializedBodies = runOptimizer(result, {
      level = 2,
      constSelection = {accepted = accepted, declined = declined, plans = plans},
   })
   local code, generated = gen.generate(result, "test")
   assertEq(#generated, 0, "const selection fixture generates")
   assertEq(specializedBodies, 1, "the supplied selection emits its private body")
   assertTrue(code:find("local function __nuppConst_accumulate_", 1, true) ~= nil,
      "the supplied selection is consumed: " .. code)
   assertEq(remarks[1].filename, "test.g.nupp", "selection and remarks share the option filename")
end

function M.constSpecializationOmitsItsCarrierAndUnrollsItsLoop()
   local code = compile(CONST_ACCUMULATE)
   local private = code:match(
      "local function __nuppConst_accumulate_[%w_]+(.-)return total end") or ""
   assertTrue(private:find("count", 1, true) == nil,
      "the private ABI and body omit the carrier: " .. private)
   assertTrue(private:find("for offset", 1, true) == nil,
      "the bounded loop is straight-line: " .. private)
   assertTrue(private:find("total = total + 4", 1, true) ~= nil,
      "the final unrolled iteration is present: " .. private)
end

function M.constSpecializationDoesNotChangeTheAnswerOrFunctionIdentity()
   local source = CONST_ACCUMULATE:gsub(
      "return accumulate%(10%.0, 4%)",
      "local held = accumulate\nlocal answer = accumulate(10.0, 4)\nreturn held == accumulate, answer"
   )
   local same, answer = run(source)
   assertEq(same, true, "the public function remains the source value")
   assertEq(answer, 20, "the private body answers like the generic body")
   local genericSame, genericAnswer = run(source, 0)
   assertEq(genericSame, same, "-O0 preserves the same public identity")
   assertEq(genericAnswer, answer, "-O0 and OPT-8 agree")
end

function M.levelZeroDoesNotMonomorphizeConstApplications()
   local code = compile(CONST_ACCUMULATE, 0)
   assertTrue(code:find("__nuppConst_", 1, true) == nil,
      "-O0 emits only the generic declaration and call")
end

function M.constSpecializationDeduplicatesAKey()
   local code = compile(CONST_ACCUMULATE:gsub(
      "return accumulate%(10%.0, 4%)",
      "return accumulate(10.0, 4) + accumulate(20.0, 4)"
   ))
   local _, declarations = code:gsub("local function __nuppConst_accumulate_", "")
   assertEq(declarations, 1, "one private body serves both calls")
end

function M.constSpecializationFollowsAConstAlias()
   local source = CONST_ACCUMULATE:gsub(
      "return accumulate%(10%.0, 4%)",
      "const run = accumulate\nreturn run(10.0, 4)"
   )
   local code = compile(source)
   assertTrue(code:find("local function __nuppConst_accumulate_", 1, true) ~= nil,
      "the declaration still owns the aliased call's body")
   assertEq(run(source), 20, "the const alias reaches the specialized body")
end

function M.constSpecializationCapsModuleBodyClasses()
   local calls = {}
   for count = 1, 9 do
      calls[#calls + 1] = ("accumulate(0.0, %d)"):format(count)
   end
   local source = CONST_ACCUMULATE:gsub(
      "return accumulate%(10%.0, 4%)",
      "return " .. table.concat(calls, " + ")
   )
   local code, remarks = compile(source)
   local _, declarations = code:gsub("local function __nuppConst_accumulate_", "")
   assertEq(declarations, 8, "the module cap is eight private body classes")
   local declined = 0
   for _, entry in ipairs(remarks) do
      if entry.code == "OPT-8" and entry.msg:find("declines", 1, true) then
         declined = declined + 1
      end
   end
   assertEq(declined, 1, "the ninth key carries a decline remark")
end

function M.constSpecializationSeparatesIntegersThatShareADecimalSpelling()
   local source = table.concat({
      "local function pick<const N: integer>(value: number, count: N): number",
      "   return value + (count as integer)",
      "end",
      "return pick(1.0, 1000000000000000), pick(1.0, 1000000000000001)",
   }, "\n")
   local code = compile(source)
   local _, declarations = code:gsub("local function __nuppConst_pick_", "")
   assertEq(declarations, 2, "two admitted const integers get two bodies")
   assertTrue(code:find("1e+15", 1, true) == nil,
      "a substituted const keeps its exact spelling: " .. code)
   local specialA, specialB = run(source)
   local genericA, genericB = run(source, 0)
   assertEq(specialA, genericA, "the first application answers like -O0")
   assertEq(specialB, genericB, "the second application answers like -O0")
end

function M.constSpecializationCoalescesKeysWithOneBackendBody()
   local calls = {}
   for count = 1, 9 do
      calls[#calls + 1] = ("tag(1.0, %d)"):format(count)
   end
   local source = table.concat({
      "local function tag<const N: integer>(value: number, count: N): number",
      "   return value + 1.0",
      "end",
      "return " .. table.concat(calls, " + "),
   }, "\n")
   local code, remarks = compile(source)
   local _, declarations = code:gsub("local function __nuppConst_tag_", "")
   assertEq(declarations, 1,
      "keys whose omitted const never reaches the body share one physical body")
   for _, entry in ipairs(remarks) do
      assertTrue(not (entry.code == "OPT-8" and entry.msg:find("declines", 1, true)),
         "coalesced semantic keys consume one cap slot")
   end
   assertEq(run(source), 18, "every key dispatches to the shared body")
end

function M.keepsACallWhoseComputedArgumentAllocates()
   local code = compile(
      "local function twice(v: string): string return v .. v end\n"
      .. "local function m(x: string): string return twice(x .. 'x') end\nreturn m")
   assertTrue(code:find("twice (", 1, true) ~= nil,
      "an allocating computed argument keeps its call: " .. code)
end

function M.keepsARecursiveHelper()
   local code = compile(
      "local function down(v: number): number return v <= 0.0 and 0.0 or down(v - 1.0) end\n"
      .. "local function m(x: number): number return down(x) end\nreturn m")
   assertTrue(code:find("return down ( x )", 1, true) ~= nil,
      "a helper naming itself is left alone: " .. code)
end

function M.keepsAHelperTheModuleReassigns()
   local code = compile(
      "local function twice(v: number): number return v * 2.0 end\n"
      .. "local function m(x: number): number return twice(x) end\n"
      .. "twice = function(v: number): number return v end\nreturn m")
   assertTrue(code:find("twice ( x )", 1, true) ~= nil,
      "a reassigned binding is not the body a call reaches: " .. code)
end

function M.keepsAHelperWhoseFreeNameIsShadowedAtTheCall()
   local code = compile(
      "local factor = 2.0\n"
      .. "local function scaled(v: number): number return v * factor end\n"
      .. "local function m(x: number): number local factor = 100.0 return scaled(x) + factor end\nreturn m")
   assertTrue(code:find("scaled ( x )", 1, true) ~= nil,
      "a free name meaning something else at the call site stops the inline: " .. code)
end

function M.levelZeroKeepsTheCall()
   local code = compile(
      "local function twice(v: number): number return v * 2.0 end\n"
      .. "local function m(x: number): number return twice(x) end\nreturn m", 0)
   assertTrue(code:find("twice ( x )", 1, true) ~= nil, "-O0 keeps the call: " .. code)
end

return M
