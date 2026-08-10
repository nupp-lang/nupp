-- The public PEG materializer: static construction, worker finalization, typed matcher
-- results, and the pure-Lua bytecode VM backend.
local parser = require("nupp.compiler.parser")
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

local function compile(source)
   local parsed = parser.parse(source, "peg_materialize_test.g.nupp")
   assertEq(#parsed.errors, 0, "syntax errors")
   local diagnostics = check.check(parsed, "peg_materialize_test.g.nupp", env)
   local code, generated = gen.generate(parsed, "peg_materialize_test")
   for _, diagnostic in ipairs(generated) do diagnostics[#diagnostics + 1] = diagnostic end
   return code, diagnostics
end

local function errorsOf(source)
   local _, diagnostics = compile(source)
   local codes = {}
   for _, diagnostic in ipairs(diagnostics) do
      if diagnostic.severity ~= "warning" and diagnostic.severity ~= "note" then
         codes[#codes + 1] = diagnostic.code
      end
   end
   return codes, diagnostics
end

local function run(source, ...)
   local code, diagnostics = compile(source)
   for _, diagnostic in ipairs(diagnostics) do
      if diagnostic.severity ~= "warning" and diagnostic.severity ~= "note" then
         error(("unexpected %s: %s\n---\n%s"):format(diagnostic.code,
            diagnostic.msg, code), 2)
      end
   end
   local chunk, why = loadstring(code, "@peg_materialize_test")
   assert(chunk, why and (why .. "\n---\n" .. code))
   return chunk(...)
end

local M = {}

function M.matchesAStaticIdentifierWithoutLPegAtRuntime()
   local source = [[
const Identifier: nupp.Peg.Matcher<integer> = comptime do
    const head = nupp.peg.range("az", "AZ") + nupp.peg.literal("_")
    const tail = head + nupp.peg.range("09")
    return nupp.peg.compile(head * tail^0 * nupp.peg.eof())
end
return Identifier:match("_name9"), Identifier:match("9name"), Identifier("ok")
]]
   local matched, missed, called = run(source)
   assertEq(matched, 7, "recognition returns the next byte position")
   assertEq(missed, nil, "a failed match returns nil")
   assertEq(called, 3, "the matcher call contract reaches the same machine")
   local code = compile(source)
   assert(code:find("nupp.peg.specialized", 1, true), code)
   assert(not code:find("require(\"lpeg\")", 1, true), code)
end

function M.returnsATypedSubstringCapture()
   local value = run([[
const Word: nupp.Peg.Matcher<string> = comptime do
    const alpha = nupp.peg.range("az", "AZ")
    return nupp.peg.compile(nupp.peg.capture(alpha^1) * nupp.peg.eof())
end
return Word("Hello")
]])
   assertEq(value, "Hello", "substring capture")
end

function M.collectsRepeatedCapturesExplicitly()
   local values = run([[
const Words: nupp.Peg.Matcher<{string}> = comptime do
    const word = nupp.peg.capture(nupp.peg.range("az")^1)
    const rest = (nupp.peg.literal(",") * word)^0
    return nupp.peg.compile(nupp.peg.collect(word * rest) * nupp.peg.eof())
end
return Words("one,two,three")
]])
   assertEq(#values, 3, "collection length")
   assertEq(table.concat(values, ":"), "one:two:three", "collection values")
end

function M.groupsRepeatedCapturesExplicitly()
   local values = run([[
local matcher: nupp.Peg.Matcher<{string}> = comptime do
    local item = nupp.peg.capture(nupp.peg.range("az") ^ 1)
    return nupp.peg.compile(nupp.peg.group(item * (nupp.peg.literal(",") * item) ^ 0) * nupp.peg.eof())
end
return matcher("one,two,three")
]])
   assertEq(table.concat(values, ":"), "one:two:three", "grouped values")
end

function M.excludesThePegVMFromUnrelatedPrograms()
   local code = compile("return 42")
   assertEq(code:find("__nuppPegVM", 1, true), nil, "unused helper")
end

function M.buildsATypedMatcherFactoryForRuntimeActions()
   local result, calls = run([[
local record NumberActions
    number: function(text: string): integer
end

const Number: function(NumberActions): nupp.Peg.Matcher<integer> = comptime do
    const digits = nupp.peg.range("09")^1
    return nupp.peg.compile(digits:action("number") * nupp.peg.eof())
end

local calls = 0
local matcher = Number(new NumberActions {
    number = function(text: string): integer
        calls = calls + 1
        return tonumber(text) as integer
    end,
})
return matcher("1234"), calls
]])
   assertEq(result, 1234, "action result")
   assertEq(calls, 1, "one successful action")
end

function M.defersActionsUntilTheWholeMatchSucceeds()
   local value, calls = run([[
local record Actions
    text: function(value: string): string
end
const Build: function(Actions): nupp.Peg.Matcher<string> = comptime do
    const short = nupp.peg.literal("a"):action("text") * nupp.peg.literal("z")
    const long = nupp.peg.literal("ab"):action("text")
    return nupp.peg.compile((short + long) * nupp.peg.eof())
end
local calls = 0
local matcher = Build(new Actions {
    text = function(value: string): string
        calls = calls + 1
        return value
    end,
})
return matcher("ab"), calls
]])
   assertEq(value, "ab", "winning action value")
   assertEq(calls, 1, "failed alternative did not run its action")
end

function M.collectsTypedActionResults()
   local values = run([[
local record Actions
    number: function(value: string): integer
end

const Build: function(Actions): nupp.Peg.Matcher<{integer}> = comptime do
    const number = (nupp.peg.range("09")^1):action("number")
    const tail = (nupp.peg.literal(",") * number)^0
    return nupp.peg.compile(nupp.peg.collect(number * tail) * nupp.peg.eof())
end

local matcher = Build(new Actions {
    number = function(value: string): integer
        return tonumber(value) as integer
    end,
})
return matcher("10,20,30")
]])
   assertEq(#values, 3, "action collection length")
   assertEq(values[1] + values[2] + values[3], 60, "typed action collection")
end

function M.requiresTheExactActionSlotRecord()
   local missing = errorsOf([[
local record Empty end
const Build: function(Empty): nupp.Peg.Matcher<string> = comptime do
    return nupp.peg.compile(nupp.peg.literal("x"):action("text"))
end
]])
   assertEq(missing[1], "NUPP2415", "missing action slot")

   local wrong = errorsOf([[
local record Actions
    text: function(value: integer): string
end
const Build: function(Actions): nupp.Peg.Matcher<string> = comptime do
    return nupp.peg.compile(nupp.peg.literal("x"):action("text"))
end
]])
   assertEq(wrong[1], "NUPP2415", "wrong action signature")
end

function M.matchesARecursiveGrammar()
   local matched, missed = run([[
const Nested: nupp.Peg.Matcher<integer> = comptime do
    const value = nupp.peg.reference("value")
    const body = nupp.peg.literal("x")
        + (nupp.peg.literal("(") * value * nupp.peg.literal(")"))
    const grammar = nupp.peg.grammar("value", nupp.peg.define("value", body))
    return nupp.peg.compile(#nupp.peg.literal("") * grammar * nupp.peg.eof())
end
return Nested("(((x)))"), Nested("((x)")
]])
   assertEq(matched, 8, "recursive match")
   assertEq(missed, nil, "unclosed recursion fails")
end

function M.runsDeepGrammarRecursionOnTheExplicitVMStack()
   local matched = run([[
const Nested: nupp.Peg.Matcher<integer> = comptime do
    const value = nupp.peg.reference("value")
    const body = nupp.peg.literal("x")
        + (nupp.peg.literal("(") * value * nupp.peg.literal(")"))
    const grammar = nupp.peg.grammar("value", nupp.peg.define("value", body))
    return nupp.peg.compile(#nupp.peg.literal("") * grammar * nupp.peg.eof())
end
local depth = 2000
local subject = string.rep("(", depth) .. "x" .. string.rep(")", depth)
return Nested(subject)
]])
   assertEq(matched, 4002, "deep recursive match")
end

function M.supportsPositionAnyAndOptionalOpcodes()
   local empty, byte, tooLong = run([[
const Located: nupp.Peg.Matcher<integer> = comptime do
    return nupp.peg.compile(
        nupp.peg.position() * nupp.peg.optional(nupp.peg.anyByte()) * nupp.peg.eof()
    )
end
return Located(""), Located("x"), Located("xy")
]])
   assertEq(empty, 1, "empty position")
   assertEq(byte, 1, "position before optional byte")
   assertEq(tooLong, nil, "optional consumes at most one byte")
end

function M.boundsBytecodeGrowthForSharedPatternGraphs()
   local source = [[
const Wide: nupp.Peg.Matcher<integer> = comptime do
    const p0 = nupp.peg.literal("x")
    const p1 = p0 * p0
    const p2 = p1 * p1
    const p3 = p2 * p2
    const p4 = p3 * p3
    const p5 = p4 * p4
    const p6 = p5 * p5
    const p7 = p6 * p6
    const p8 = p7 * p7
    const p9 = p8 * p8
    const p10 = p9 * p9
    const p11 = p10 * p10
    const p12 = p11 * p11
    const p13 = p12 * p12
    const p14 = p13 * p13
    const p15 = p14 * p14
    const p16 = p15 * p15
    return nupp.peg.compile(p16 * nupp.peg.eof())
end
return Wide(string.rep("x", 65536))
]]
   local code = compile(source)
   assert(#code < 20000, "shared pattern graph expanded into excessive bytecode")
   assertEq(run(source), 65537, "shared pattern match")
end

function M.supportsDifferenceAndPredicates()
   local good, keyword, digit = run([[
const Name: nupp.Peg.Matcher<integer> = comptime do
    const alpha = nupp.peg.range("az")
    const keyword = nupp.peg.literal("if") * nupp.peg.eof()
    const name = -keyword * #alpha * alpha^1 * nupp.peg.eof()
    return nupp.peg.compile(nupp.peg.difference(name, nupp.peg.range("09")))
end
return Name("item"), Name("if"), Name("7")
]])
   assertEq(good, 5, "predicate match")
   assertEq(keyword, nil, "negative predicate")
   assertEq(digit, nil, "difference")
end

function M.usesLpegExponentSemantics()
   local twice, once, thrice, capped = run([[
const AtLeastTwo: nupp.Peg.Matcher<integer> = comptime do
    return nupp.peg.compile(nupp.peg.literal("a")^2 * nupp.peg.eof())
end
const AtMostTwo: nupp.Peg.Matcher<integer> = comptime do
    return nupp.peg.compile(nupp.peg.literal("a")^-2 * nupp.peg.eof())
end
return AtLeastTwo("aa"), AtLeastTwo("a"), AtLeastTwo("aaa"), AtMostTwo("aa")
]])
   assertEq(twice, 3, "positive exponent minimum")
   assertEq(once, nil, "positive exponent rejects fewer")
   assertEq(thrice, 4, "positive exponent accepts more")
   assertEq(capped, 3, "negative exponent maximum")
end

function M.agreesWithLpegOnTheOverlappingFloor()
   local lpeg = require("lpeg")
   local matcher = run([[
const Identifier: nupp.Peg.Matcher<integer> = comptime do
    const alpha = nupp.peg.range("az", "AZ") + nupp.peg.literal("_")
    const alnum = alpha + nupp.peg.range("09")
    return nupp.peg.compile(alpha * alnum^0 * nupp.peg.eof())
end
return Identifier
]])
   local alpha = lpeg.R("az", "AZ") + lpeg.P("_")
   local reference = alpha * (alpha + lpeg.R("09"))^0 * -lpeg.P(1)
   for _, subject in ipairs({"name", "_name9", "A0", "", "9x", "a-b"}) do
      assertEq(matcher(subject), lpeg.match(reference, subject),
         "LPeg differential subject " .. subject)
   end
end

function M.agreesBetweenSpecializedAndGeneralBackends()
   local source = [[
const FastIdentifier: nupp.Peg.Matcher<integer> = comptime do
    const head = nupp.peg.range("az", "AZ") + nupp.peg.literal("_")
    const tail = head + nupp.peg.range("09")
    return nupp.peg.compile(head * tail^0 * nupp.peg.eof())
end
const RefIdentifier: nupp.Peg.Matcher<integer> = comptime do
    const head = nupp.peg.range("az", "AZ") + nupp.peg.literal("_")
    const tail = head + nupp.peg.range("09")
    return nupp.peg.compile(#nupp.peg.literal("") * head * tail^0 * nupp.peg.eof())
end
const FastList: nupp.Peg.Matcher<{string}> = comptime do
    const word = nupp.peg.capture(nupp.peg.range("az")^1)
    return nupp.peg.compile(nupp.peg.collect(word * (nupp.peg.literal(",") * word)^0) * nupp.peg.eof())
end
const RefList: nupp.Peg.Matcher<{string}> = comptime do
    const word = nupp.peg.capture(nupp.peg.range("az")^1)
    return nupp.peg.compile(#nupp.peg.literal("") * nupp.peg.collect(word * (nupp.peg.literal(",") * word)^0) * nupp.peg.eof())
end
return FastIdentifier, RefIdentifier, FastList, RefList
]]
   local code = compile(source)
   assert(code:find("nupp.peg.specialized", 1, true), code)
   assert(code:find("nupp.peg.vm", 1, true), code)
   local fastIdentifier, refIdentifier, fastList, refList = run(source)
   local inputs = {"", "a", "_ok9", "9bad", "alpha,beta", "one,two,three", "one,", ",two"}
   for _, input in ipairs(inputs) do
      assertEq(fastIdentifier(input), refIdentifier(input), "identifier backend parity for " .. input)
      local fast, ref = fastList(input), refList(input)
      assertEq(fast and table.concat(fast, ":"), ref and table.concat(ref, ":"),
         "list backend parity for " .. input)
   end
end

function M.rejectsNullableRepetition()
   local codes = errorsOf([[
const Bad: nupp.Peg.Matcher<integer> = comptime do
    return nupp.peg.compile(nupp.peg.literal("")^0)
end
]])
   assertEq(codes[1], "NUPP2417", "nullable repetition is rejected while finalizing")
end

function M.rejectsLeftRecursion()
   local codes = errorsOf([[
const Bad: nupp.Peg.Matcher<integer> = comptime do
    const self = nupp.peg.reference("value")
    const grammar = nupp.peg.grammar("value", nupp.peg.define("value", self + nupp.peg.literal("x")))
    return nupp.peg.compile(grammar)
end
]])
   assertEq(codes[1], "NUPP2417", "left recursion is rejected")
end

function M.rejectsAMatcherResultTypeMismatch()
   local codes = errorsOf([[
const Bad: nupp.Peg.Matcher<integer> = comptime do
    return nupp.peg.compile(nupp.peg.capture(nupp.peg.literal("x")))
end
]])
   assertEq(codes[1], "NUPP2415", "capture result and matcher type must agree")
end

return M
