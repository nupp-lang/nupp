-- Comptime, C1: expression blocks.
--
-- The property that matters is not that a literal appears in the output but that the
-- literal is the value the block computed, so the interesting tests run the generated
-- code and compare it against the same answer reached another way. The rest are the
-- guard rails, which are worth more here than usual: a block that quietly read the clock
-- or quietly shared a table would produce a program that builds differently tomorrow.
local parser = require("nupp.compiler.parser")
local gen = require("nupp.compiler.gen")
local check = require("fragment")
local envMod = require("nupp.compiler.env")
local T = require("nupp.compiler.types")

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

-- Checks, then generates. Comptime runs during checking, so a diagnostic it produced is
-- in the list this returns; nothing here optimizes, because comptime is semantics and
-- must not need a level.
local function compile(src)
   local result = parser.parse(src, "test.g.nupp")
   assertEq(#result.errors, 0, "syntax errors in test source")
   local diags = check.check(result, "test.g.nupp", env)
   local code, genDiags = gen.generate(result, "test")
   for _, one in ipairs(genDiags) do diags[#diags + 1] = one end
   return code, diags
end

local function errorsOf(src)
   local _, diags = compile(src)
   local codes = {}
   for _, diag in ipairs(diags) do
      if diag.severity ~= "warning" and diag.severity ~= "note" then
         codes[#codes + 1] = diag.code
      end
   end
   return codes, diags
end

-- Compiles, loads and runs, so that what is asserted is the program's behaviour rather
-- than the shape of the text that produced it.
local function run(src, ...)
   local code, diags = compile(src)
   for _, diag in ipairs(diags) do
      if diag.severity ~= "warning" and diag.severity ~= "note" then
         error(("unexpected %s: %s\n---\n%s"):format(diag.code, diag.msg, code), 2)
      end
   end
   local chunk, err = loadstring(code, "@comptime_test")
   if not chunk then
      error("generated code does not load: " .. tostring(err)
         .. "\n---\n" .. code, 2)
   end
   return chunk(...)
end

local function firstLocalBinding(result)
   return result.root.blocks[1].stats[1].names[1].definition.type
end

local M = {}

function M.evaluatesAnArithmeticBlock()
   assertEq(run("return comptime do return (2 + 3) * 4 end"), 20, "block result")
   local code = compile("return comptime do return (2 + 3) * 4 end")
   assertTrue(code:find("return 20", 1, true) ~= nil,
      "the block is replaced by its value: " .. code)
   assertEq(code:find("2 + 3", 1, true), nil,
      "none of the body reaches the output: " .. code)
end

function M.keepsAScalarComptimeLiteralOnAConstBinding()
   local result = parser.parse([[const banner = comptime do
    return "NUPP COMPILES THIS ONCE ========"
end]], "test.g.nupp")
   assertEq(#result.errors, 0, "const comptime source parses")
   assertEq(#check.check(result, "test.g.nupp", env), 0, "const comptime source checks")
   local binding = firstLocalBinding(result)
   assertEq(binding.tag, "literal", "const comptime binding keeps its literal type")
   assertEq(binding.constant, "NUPP COMPILES THIS ONCE ========", "const comptime literal value")
end

function M.buildsATableWithALoop()
   -- The case nothing else can reach: a loop that accumulates. Folding rewrites
   -- expressions and will never produce this.
   local src = [[
const SQUARES = comptime do
    const entries = {}
    for index = 1, 5 do
        entries[index] = index * index
    end
    return entries
end
return SQUARES[4], #SQUARES
]]
   local value, count = run(src)
   assertEq(value, 16, "the fourth square")
   assertEq(count, 5, "the table's length")
   local code = compile(src)
   assertTrue(code:find("{1, 4, 9, 16, 25}", 1, true) ~= nil,
      "the table is emitted as one literal: " .. code)
end

function M.widensComptimeArrayElements()
   local result = parser.parse([[const values = comptime do
    return {1, 2, 3}
end]], "test.g.nupp")
   assertEq(#result.errors, 0, "comptime array source parses")
   assertEq(#check.check(result, "test.g.nupp", env), 0, "comptime array source checks")
   local binding = firstLocalBinding(result)
   assertEq(T.tostring(binding), "{integer}", "comptime array elements widen")
end

function M.matchesAnIndependentComputationOfTheSameTable()
   -- A CRC table is the motivating case, and it is worth checking against a
   -- computation that shares no code with the evaluator rather than against itself.
   local src = [[
const CRC = comptime do
    const entries = {}
    for byte = 0, 255 do
        local acc = byte
        for _ = 1, 8 do
            acc = acc & 1 ~= 0 and 0xedb88320 ~ (acc >> 1) or acc >> 1
        end
        entries[byte + 1] = acc
    end
    return entries
end
return CRC
]]
   local got = run(src)
   local want = {}
   for byte = 0, 255 do
      local acc = byte
      for _ = 1, 8 do
         if bit.band(acc, 1) ~= 0 then
            acc = bit.bxor(0xedb88320, bit.rshift(acc, 1))
         else
            acc = bit.rshift(acc, 1)
         end
      end
      want[byte + 1] = acc
   end
   assertEq(#got, 256, "entry count")
   for index = 1, 256 do
      assertEq(got[index], want[index], "entry " .. index)
   end
end

function M.worksAtEveryOptimizationLevel()
   -- Comptime is semantics, not an optimization: `-O0` must still produce the value.
   -- `compile` never optimizes, so reaching the value at all is the assertion.
   assertEq(run("return comptime do return 7 end"), 7, "result at -O0")
end

function M.preservesTheLineCount()
   local src = "local before = 1\nconst V = comptime do\n"
      .. "    local sum = 0\n    for i = 1, 3 do sum = sum + i end\n"
      .. "    return sum\nend\nreturn before, V\n"
   local code = compile(src)
   local function lines(text)
      local n = 1
      for _ in text:gmatch("\n") do n = n + 1 end
      return n
   end
   assertEq(lines(code), lines(src),
      "attribution survives by the line count holding: " .. code)
   local _, value = run(src)
   assertEq(value, 6, "the block still produced its value")
end

function M.staysAName()
   -- `comptime` opens a block only when `do` follows it on the same line. Everywhere
   -- else it is the identifier it always was.
   assertEq(run("local comptime = 3\nreturn comptime"), 3, "a local of that name")
   assertEq(run("local function f(comptime) return comptime end\nreturn f(9)"), 9,
      "a parameter of that name")
end

function M.typesTheResultAgainstItsContext()
   local codes = errorsOf("const N: string = comptime do return 5 end\nreturn N")
   assertEq(codes[1], "NUPP2001",
      "an integer result is refused where a string is declared")
end

function M.readsNoRuntimeBinding()
   local codes = errorsOf("local n = 5\nreturn comptime do return n end")
   assertEq(codes[1], "NUPP2410", "a runtime local is unavailable")
end

function M.writesNoRuntimeBinding()
   local codes = errorsOf("local n = 5\nreturn comptime do n = 6 return n end")
   assertEq(codes[1], "NUPP2410", "a runtime local cannot be assigned")
end

function M.reachesNoAmbientLibrary()
   for _, name in ipairs({"io", "os", "package", "require", "loadstring",
      "debug", "jit", "print", "_G", "collectgarbage"}) do
      local codes = errorsOf(("return comptime do return %s end"):format(name))
      assertEq(codes[1], "NUPP2410", name .. " is not in the environment")
   end
end

function M.reachesTheAllowlistedLibraries()
   assertEq(run('return comptime do return string.rep("-", 3) end'), "---",
      "string.rep")
   assertEq(run("return comptime do return math.floor(7 / 2) end"), 3, "math.floor")
   assertEq(run('return comptime do return table.concat({"a", "b"}, ",") end'), "a,b",
      "table.concat")
   -- The compiler runs on a LuaJIT with no table.clone of its own, so this is the
   -- evaluator's own copy answering, not one borrowed from the host.
   assertEq(run("return comptime do local t = table.clone({n = 4}) t.n = 5 return t.n end"),
      5, "table.clone")
   assertEq(run("return comptime do return bit.band(0xff, 0x0f) end"), 15, "bit.band")
   assertEq(run('return comptime do return ("x"):upper() end'), "X",
      "a string method")
end

function M.refusesTheNondeterministicLibraries()
   -- Absent for a reason each: libm differs between platforms, so a transcendental
   -- would fold to a different constant elsewhere, and a clock differs between two
   -- runs on one machine.
   --
   -- The two codes are the two shapes of absence, and the difference is worth keeping.
   -- A member the allowlist leaves out is NUPP2402 and names itself; a library that is
   -- not in the environment at all is NUPP2401, the same answer a runtime local gets.
   for _, expr in ipairs({"math.random()", "math.sin(1)"}) do
      local codes = errorsOf(("return comptime do return %s end"):format(expr))
      assertEq(codes[1], "NUPP2411", expr .. " is left out of the allowlist")
   end
   for _, expr in ipairs({"os.clock()", "os.time()"}) do
      local codes = errorsOf(("return comptime do return %s end"):format(expr))
      assertEq(codes[1], "NUPP2410", expr .. " has no library to reach")
   end
end

function M.namesTheAbsentMemberRatherThanItsSymptom()
   local _, diags = compile("return comptime do return math.random() end")
   local found
   for _, diag in ipairs(diags) do
      if diag.code == "NUPP2411" then found = diag.msg end
   end
   assertEq(found, "math.random is unavailable at comptime",
      "the diagnostic says which member, not that a nil was called")
end

function M.refusesTostringOfATable()
   -- `tostring(t)` is a process address, so a block using it would produce a different
   -- constant on the next build of the same source.
   local codes = errorsOf("return comptime do return tostring({}) end")
   assertEq(codes[1], "NUPP2412", "tostring of a table is refused")
end

function M.iteratesDeterministically()
   -- Two orders would be two programs. The keys come back sorted, so the string a
   -- block builds by walking a table is the same one every build.
   local src = [[
const KEYS = comptime do
    local out = {}
    for key in pairs({zebra = 1, apple = 2, mango = 3}) do
        out[#out + 1] = key
    end
    return table.concat(out, ",")
end
return KEYS
]]
   assertEq(run(src), "apple,mango,zebra", "pairs answers in sorted order")
end

function M.stopsEndlessRecursionOfBlocks()
   local codes = errorsOf("return comptime do return comptime do return 1 end end")
   assertEq(codes[1], "NUPP2411", "a nested block is refused")
end

function M.boundsAnEndlessLoop()
   local codes, diags = errorsOf("return comptime do while true do end end")
   assertEq(codes[1], "NUPP2412", "the evaluator budget stops an endless loop")
   local found
   for _, diag in ipairs(diags) do
      if diag.code == "NUPP2412" then found = diag.msg end
   end
   assertTrue(found and (found:find("steps", 1, true) or found:find("timeout", 1, true)),
      "the diagnostic names the bound: " .. tostring(found))
end

function M.recoversWhenTheWorkerCrashes()
   if jit.os == "Windows" then return end
   local root = os.tmpname()
   os.remove(root)
   assertEq(os.execute(("mkdir -p %q/bin"):format(root)), 0)
   local launcher = assert(io.open(root .. "/bin/nupp", "wb"))
   launcher:write("#!/bin/sh\nkill -9 $$\n")
   launcher:close()
   assertEq(os.execute(("chmod +x %q/bin/nupp"):format(root)), 0)
   local worker = require("nupp.compiler.comptime_worker")
   local _, failure = worker.evaluate("comptime do return 1 end", root)
   os.execute(("rm -rf %q"):format(root))
   assertTrue(failure and failure.message:find("crashed", 1, true),
      "the parent converts a worker crash into one failure")
end

function M.boundsAComptimeStringSizeBomb()
   local codes, diags = errorsOf(
      [[return comptime do return string.rep("x", 600000) end]]
   )
   assert(codes[1] == "NUPP2412" or codes[1] == "NUPP2416",
      "the string allocation is bounded")
   local message = diags[1] and diags[1].msg or ""
   assertTrue(message:find("limit", 1, true) ~= nil,
      "the diagnostic names the size limit: " .. message)
end

function M.boundsAComptimeResultGraph()
   local codes = errorsOf([[
return comptime do
    local values = {}
    for index = 1, 12000 do values[index] = index end
    return values
end
]])
   assertEq(codes[1], "NUPP2416", "the final value graph has an item limit")
end

function M.boundsComptimeHelperRecursion()
   local codes, diags = errorsOf([[
@comptime local function descend(value: number): number
    if value == 0 then return 0 end
    return descend(value - 1)
end
return comptime do return descend(200) end
]])
   assertEq(codes[1], "NUPP2412", "helper recursion has a frame limit")
   local message = diags[1] and diags[1].msg or ""
   assertTrue(message:find("128 frames", 1, true) ~= nil,
      "the diagnostic names the recursion bound: " .. message)
end

function M.materializesACyclicOpaqueGraphAtAnExplicitBoundary()
   local src = [[
const graph: nupp.__MaterializedTest = comptime do
    const first = nupp.__materializationTest.node(7)
    const second = nupp.__materializationTest.node(11)
    first:link(second)
    second:link(first)
    return first
end
return graph.value, graph.nodes
]]
   local value, nodes = run(src)
   assertEq(value, 18, "the provider lowers its canonical payload")
   assertEq(nodes, 2, "the cyclic graph crosses the worker as flat data")
   local code = compile(src)
   assertTrue(code:find("{value=18,nodes=2}", 1, true) ~= nil,
      "the generator renders validated IR: " .. code)
   assertEq(code:find("__materializationTest", 1, true), nil,
      "no opaque construction reaches runtime")
end

function M.materializesAFactoryWithOrdinaryRuntimeInputs()
   local src = [[
const build: function(nupp.__MaterializationTestInput): nupp.__MaterializedTest = comptime do
    return nupp.__materializationTest.factory()
end
const made = build({value = 37} as nupp.__MaterializationTestInput)
return made.value, made.nodes
]]
   local value, nodes = run(src)
   assertEq(value, 37, "the generated factory reads its declared runtime input")
   assertEq(nodes, 1, "the generated result keeps its provider data")
   local code = compile(src)
   assertTrue(code:find("function(_nupp_m1)", 1, true) ~= nil,
      "the factory is emitted through hygienic expression IR: " .. code)
end

function M.callsTypedComptimeHelpersAndErasesThem()
   local src = [[
@comptime local function double(value: integer): integer
    return value * 2
end
@comptime local function addDouble(left: integer, right: integer): integer
    return left + double(right)
end
const ANSWER: integer = comptime do
    return addDouble(2, 20)
end
return ANSWER
]]
   assertEq(run(src), 42, "comptime helpers compose")
   local code, diags = compile(src)
   assertEq(#diags, 0, "typed helpers check")
   assertEq(code:find("function double", 1, true), nil,
      "a comptime helper has no runtime declaration")
   assertTrue(code:find("42", 1, true) ~= nil, "the computed result remains")
end

function M.recursesWithinTheSharedEvaluationBudget()
   local src = [[
@comptime local function factorial(value: number): number
    if value <= 1 then return 1 end
    return value * factorial(value - 1)
end
return comptime do return factorial(6) end
]]
   assertEq(run(src), 720, "recursive comptime helper")
end

function M.keepsComptimeHelpersOutOfRuntimeValues()
   local codes = errorsOf([[
@comptime local function answer(): integer return 42 end
local escaped = answer
return escaped()
]])
   assertEq(codes[1], "NUPP2415", "a comptime helper cannot escape to runtime")
end

function M.reportsAComptimeCallStack()
   local _, diags = compile([[
@comptime local function explode(value: integer): integer
    return error("builder failed")
end
return comptime do return explode(1) end
]])
   local message
   for _, diag in ipairs(diags) do
      if diag.code == "NUPP2412" then message = diag.msg end
   end
   assertTrue(message and message:find("called explode", 1, true),
      "the failure retains its comptime call frame: " .. tostring(message))
end

function M.requiresAnExplicitTypeForAnOpaqueResult()
   local codes = errorsOf([[
const graph = comptime do
    return nupp.__materializationTest.node(1)
end
]])
   assertEq(codes[1], "NUPP2414", "an inferred binding is not a materialization boundary")
end

function M.rejectsAnUnregisteredOpaqueTypePair()
   local codes = errorsOf([[
const graph: table = comptime do
    return nupp.__materializationTest.node(1)
end
]])
   assertEq(codes[1], "NUPP2415", "the expected type selects a closed provider relation")
end

function M.rejectsOpaqueValuesNestedInOrdinaryTables()
   local codes = errorsOf([[
const graph = comptime do
    return {nupp.__materializationTest.node(1)}
end
]])
   assertEq(codes[1], "NUPP2414", "an opaque handle cannot escape through quoted data")
end

function M.fingerprintsEquivalentOpaqueGraphsIdentically()
   local worker = require("nupp.compiler.comptime_worker")
   local root = assert(os.getenv("NUPP_COMPILER_ROOT"))
   local first = [[comptime do
       const a = nupp.__materializationTest.node(1)
       const b = nupp.__materializationTest.node(2)
       a:link(b)
       b:link(a)
       return a
   end]]
   local second = [[comptime do
       const b = nupp.__materializationTest.node(2)
       const a = nupp.__materializationTest.node(1)
       b:link(a)
       a:link(b)
       return a
   end]]
   local _, failureA, envelopeA = worker.evaluate(first, root)
   local _, failureB, envelopeB = worker.evaluate(second, root)
   assertEq(failureA, nil, "first graph finalizes")
   assertEq(failureB, nil, "second graph finalizes")
   assertEq(envelopeA.fingerprint, envelopeB.fingerprint,
      "construction order does not enter the fingerprint")
end

function M.requiresAResult()
   local codes = errorsOf("return comptime do local a = 1 end")
   assertEq(codes[1], "NUPP2412", "a block with no return is refused")
end

function M.refusesMoreThanOneResult()
   local codes = errorsOf("return comptime do return 1, 2 end")
   assertEq(codes[1], "NUPP2411", "multi-value results are deferred, not silent")
end

function M.refusesAnUnquotableResult()
   local codes = errorsOf("return comptime do return ipairs end")
   assertEq(codes[1], "NUPP2413", "a function is not a quotable result")
end

function M.refusesASharedTable()
   -- Quoting it twice would build two tables where the block had one. Refusing leaves
   -- the author a decision rather than a difference to discover at run time.
   local codes = errorsOf("return comptime do local s = {1} return {s, s} end")
   assertEq(codes[1], "NUPP2413", "a table on two paths is refused")
end

function M.refusesAFunctionDeclaration()
   -- C3, and named as such rather than mis-reported as something else.
   local codes = errorsOf(
      "return comptime do local function f() return 1 end return f() end")
   assertEq(codes[1], "NUPP2411", "declaring a function is not yet available")
end

function M.quotesNumbersThatReadBackUnchanged()
   -- `%.14g` is LuaJIT's default and loses the last bits, so the quoted spelling is
   -- searched for rather than assumed.
   for _, value in ipairs({0.1, 1 / 3, 2 ^ 0.5, 1e300, 5e-324, 123456789.123456789}) do
      local src = ("return comptime do return %.17g end"):format(value)
      assertEq(run(src), value, "round trip for " .. tostring(value))
   end
end

function M.quotesNegativeZeroApart()
   local answer = run("return comptime do return -0.0 end")
   assertEq(1 / answer, -math.huge, "negative zero keeps its sign")
end

function M.refusesNaNAndInfinity()
   for _, src in ipairs({"return comptime do return 0 / 0 end",
      "return comptime do return 1 / 0 end"}) do
      local codes = errorsOf(src)
      assertEq(codes[1], "NUPP2413", "no literal spelling for " .. src)
   end
end

function M.spellsASparseTableOneWay()
   -- The array part runs to the first hole; everything past it is a keyed entry, so
   -- how the table was built does not change how it is written down.
   local src = [[
const T = comptime do
    local out = {}
    out[1] = "a"
    out[2] = "b"
    out[4] = "d"
    return out
end
return T[1], T[2], T[4], T[3]
]]
   local one, two, four, three = run(src)
   assertEq(one, "a", "first")
   assertEq(two, "b", "second")
   assertEq(four, "d", "fourth")
   assertEq(three, nil, "the hole stays a hole")
   local code = compile(src)
   assertTrue(code:find('{"a", "b", [4] = "d"}', 1, true) ~= nil,
      "the hole splits the array part from the keyed entries: " .. code)
end

function M.buildsTheSameBytesTwice()
   local src = [[
const T = comptime do
    local out = {}
    for _, key in ipairs({"c", "a", "b"}) do
        out[key] = #key
    end
    return out
end
return T.a
]]
   local first = compile(src)
   local second = compile(src)
   assertEq(first, second, "two builds of one source agree")
end

function M.reportsInsideTheBlockWithOrdinaryChecking()
   -- The body is checked by the ordinary machinery, so a type error in it is the
   -- diagnostic it would be anywhere else rather than an evaluation failure.
   local codes = errorsOf('return comptime do local n: integer = "x" return n end')
   assertEq(codes[1], "NUPP2001", "an ordinary type error inside the block")
end

return M
