-- The textual PEG compiler at both phases, typed static materialization, Nupp
-- specialization templates, and native LPeg lowering.
local parser = require("nupp.compiler.parser")
local gen = require("nupp.compiler.gen")
local check = require("fragment")
local envMod = require("nupp.compiler.env")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local env = envMod.new(HERE .. "/..")

-- Load LPeg's C module directly from the test rock tree so differential tests keep
-- an independent handle even when generated bootstrap code changes package.loaded.
local function officialLpeg()
   for template in package.cpath:gmatch("[^;]+") do
      local path = template:gsub("%?", "lpeg")
      local file = io.open(path, "rb")
      if file then
         file:close()
         local opener, why = package.loadlib(path, "luaopen_lpeg")
         assert(opener, why)
         return opener()
      end
   end
   error("the LPeg oracle is not installed in package.cpath")
end

local function officialRe(lpeg)
   local savedLpeg, savedRe = package.loaded.lpeg, package.loaded.re
   package.loaded.lpeg, package.loaded.re = lpeg, nil
   local ok, re = pcall(require, "re")
   package.loaded.lpeg, package.loaded.re = savedLpeg, savedRe
   assert(ok, re)
   return re
end

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

function M.exposesMatcherAndSupportTypesOnTheRuntimeModule()
   local value = run([[
local backend: nupp.peg.Backend = "lpeg"
local action: nupp.peg.Action = function(text: string): any return text:upper() end
local actions: nupp.peg.Actions = {upper = action}
local options: nupp.peg.CompileOptions = {backend = backend, actions = actions}
local library = nupp.peg
local matcher: nupp.peg.Peg<any> = library.compile("[a-z]+ -> upper !.", options)
return matcher("hello")
]])
   assertEq(value, "HELLO", "module-level PEG types")

   local codes = errorsOf("local old: nupp.Peg.Matcher<integer> = nil as any")
   assert(#codes > 0, "the old nupp.Peg namespace must not remain public")
end

function M.matcherProtocolPreservesItsResultType()
   local value = run([[
local function match<R...>(
    matcher: nupp.peg.Matcher<R...>,
    subject: string
): ((R...) | (nil))
    return matcher:match(subject)
end

local Word: nupp.peg.Peg<string> = nupp.peg.compile("{ [a-z]+ }")
local result: string? = match(Word, "hello")
return result
]])
   assertEq(value, "hello", "the matcher declaration chooses its result")

   local codes = errorsOf([[
local function match<R...>(matcher: nupp.peg.Matcher<R...>, subject: string):
    ((R...) | (nil))
    return matcher:match(subject)
end
local Word: nupp.peg.Peg<string> = nupp.peg.compile("{ [a-z]+ }")
local wrong: integer? = match(Word, "hello")
]])
   assertEq(table.concat(codes, " "), "NUPP2001",
      "the recovered result cannot be assigned as another capture type")
end

function M.returnsMultipleCapturesAsNativeTypedResults()
   local left, right = run([[
local Pair = nupp.peg.compile("{ [a-z]+ } ':' { [0-9]+ }")
local left, right = Pair("age:42")
if left == nil or right == nil then error("expected a match") end
local typedLeft: string = left
local typedRight: string = right
return typedLeft, typedRight
]])
   assertEq(left, "age", "first native capture")
   assertEq(right, "42", "second native capture")
end

function M.multipleCapturesWorkInForcedLpegAndComptimeCodegen()
   local lpegLeft, lpegRight, staticLeft, staticRight = run([[
local Lpeg: nupp.peg.Peg<(string, string)> = nupp.peg.compile(
    "{ [a-z]+ } ':' { [0-9]+ }",
    {backend = "lpeg"}
)
const Static: nupp.peg.Peg<(string, string)> = comptime do
    return nupp.peg.compile("{ [a-z]+ } ':' { [0-9]+ }")
end
local lpegLeft, lpegRight = Lpeg("age:42")
local staticLeft, staticRight = Static("age:42")
return lpegLeft, lpegRight, staticLeft, staticRight
]])
   assertEq(lpegLeft, "age", "LPeg first capture")
   assertEq(lpegRight, "42", "LPeg second capture")
   assertEq(staticLeft, "age", "codegen first capture")
   assertEq(staticRight, "42", "codegen second capture")
end

function M.multipleCapturesFlowThroughSearchTraversalAndReplacement()
   local first, nextPosition, left, right, count, replaced = run([[
local Pair = nupp.peg.compile("{ [a-z]+ } ':' { [0-9]+ }")
local first, nextPosition, left, right = Pair:find("!age:42!")
local count = Pair:forEachMatch("age:42 x:7", function(
    _: integer,
    _: integer,
    word: string,
    digits: string
)
    assert(word ~= "" and digits ~= "")
end)
local replaced = Pair:replaceAll(
    "age:42 x:7",
    function(_, _, word: string, digits: string): string
        return digits .. word
    end
)
return first, nextPosition, left, right, count, replaced
]])
   assertEq(first, 2, "find first")
   assertEq(nextPosition, 8, "find exclusive end")
   assertEq(left, "age", "find first capture")
   assertEq(right, "42", "find second capture")
   assertEq(count, 2, "visited matches")
   assertEq(replaced, "42age 7x", "callback replacement")
end

function M.typedActionsMayReturnSeveralNativeResults()
   local text, length, runtimeText, runtimeLength = run([[
local record Actions
    pair: function(text: string): (string, integer)
end
const Build: function(Actions): nupp.peg.Peg<(string, integer)> = comptime do
    return nupp.peg.compile("[a-z]+ -> pair !.")
end
local matcher = Build(new Actions(
    pair = function(text: string): (string, integer)
        return text, #text
    end
))
local runtime = nupp.peg.compile("[a-z]+ -> pair !.", {
    definitions = {
        pair = function(value: string): (string, integer)
            return value, #value
        end,
    },
})
local text, length = matcher("word")
local runtimeText, runtimeLength = runtime("other")
return text, length, runtimeText, runtimeLength
]])
   assertEq(text, "word", "action first result")
   assertEq(length, 4, "action second result")
   assertEq(runtimeText, "other", "runtime action first result")
   assertEq(runtimeLength, 5, "runtime action second result")
end

function M.dynamicSearchDoesNotCollapseNestedCaptures()
   local first, nextPosition, outer, inner = run([[
local source: string = "{ { [a-z]+ } }"
local Nested: nupp.peg.Peg<(string, string)> = nupp.peg.compile(source)
return Nested:find("!word!")
]])
   assertEq(first, 2, "nested capture start")
   assertEq(nextPosition, 6, "nested capture end")
   assertEq(outer, "word", "outer capture")
   assertEq(inner, "word", "inner capture")
end

function M.keepsAStaticIdentifierOnTheSpecializedRuntime()
   local source = [[
const Identifier: nupp.peg.Peg<integer> = comptime do
    return nupp.peg.compile("[a-zA-Z_] [a-zA-Z_0-9]* !.")
end
return Identifier:match("_name9"), Identifier:match("9name"), Identifier("ok")
]]
   local matched, missed, called = run(source)
   assertEq(matched, 7, "recognition returns the next byte position")
   assertEq(missed, nil, "a failed match returns nil")
   assertEq(called, 3, "the matcher call contract reaches the same machine")
   local code = compile(source)
   assert(code:find("(__nuppPegCodegen)({", 1, true), code)
   assertEq(code:find("__nuppPegReInstall", 1, true), nil,
      "ordinary static PEG excludes the runtime frontend")
   assert(code:find("require(\"lpeg\")", 1, true), code)
   assertEq(code:find("package.preload.re", 1, true), nil,
      "ordinary static PEG excludes the textual runtime frontend")
end

function M.searchesForMatchesWithoutBuildingAMatchResult()
   local found, skipped, negative, missing, emptySuffix, runtime, falseResult = run([==[
const Word = comptime do
    return nupp.peg.compile("[a-z]+ !.")
end
const End = comptime do
    return nupp.peg.compile("!.", {backend = "lpeg"})
end
local grammar: string = "'needle'"
local Runtime = nupp.peg.compile(grammar)

local record Actions
    reject: function(string): boolean
end
const FalseResult: function(Actions): nupp.peg.Peg<boolean> = comptime do
    return nupp.peg.compile("'x' -> reject", {backend = "lpeg"})
end
local ReturnsFalse = FalseResult(new Actions(
    reject = function(_: string): boolean return false end
))

return Word:isMatch("123 hello"), Word:isMatch("hello 123", 2),
    Word:isMatch("123 hello", -5), Word:isMatch("123", 5),
    End:isMatch("anything"), Runtime:isMatch("hay needle stack"),
    ReturnsFalse:isMatch("---x")
]==])
   assertEq(found, true, "static specialized search")
   assertEq(skipped, false, "search respects init")
   assertEq(negative, true, "negative search position")
   assertEq(missing, false, "out-of-range search")
   assertEq(emptySuffix, true, "search includes the final empty position")
   assertEq(runtime, true, "runtime-compiled search")
   assertEq(falseResult, true, "false capture result still denotes a match")
end

function M.findsWithPositionsAndNoMatchRecord()
   local first, nextPosition, value, recognizerFirst, recognizerNext, recognizerValue,
      emptyFirst, emptyNext, emptyValue, missingFirst, missingNext, missingValue,
      nilFirst, nilNext, nilValue = run([==[
const Word = comptime do
    return nupp.peg.compile("{ [a-z]+ }")
end
const Identifier = comptime do
    return nupp.peg.compile("[a-z]+ !.")
end
const End = comptime do
    return nupp.peg.compile("!.", {backend = "lpeg"})
end

local record Actions
    drop: function(string): nil
end
const Drop: function(Actions): nupp.peg.Peg<nil> = comptime do
    return nupp.peg.compile("'x' -> drop", {backend = "lpeg"})
end
local DropsValue = Drop(new Actions(
    drop = function(_: string): nil return nil end
))

local first, nextPosition, value = Word:find("123 hello")
local recognizerFirst, recognizerNext, recognizerValue = Identifier:find("123 hello")
local emptyFirst, emptyNext, emptyValue = End:find("abc")
local missingFirst, missingNext, missingValue = Word:find("123")
local nilFirst, nilNext, nilValue = DropsValue:find("---x")
return first, nextPosition, value, recognizerFirst, recognizerNext, recognizerValue,
    emptyFirst, emptyNext, emptyValue, missingFirst, missingNext, missingValue,
    nilFirst, nilNext, nilValue
]==])
   assertEq(first, 5, "capture search first byte")
   assertEq(nextPosition, 10, "capture search exclusive next byte")
   assertEq(value, "hello", "capture search value")
   assertEq(recognizerFirst, 5, "recognizer search first byte")
   assertEq(recognizerNext, 10, "recognizer search exclusive next byte")
   assertEq(recognizerValue, 10, "recognizer search result")
   assertEq(emptyFirst, 4, "empty search first byte")
   assertEq(emptyNext, 4, "empty search has equal positions")
   assertEq(emptyValue, 4, "empty recognizer result")
   assertEq(missingFirst, nil, "failed search first byte")
   assertEq(missingNext, nil, "failed search next byte")
   assertEq(missingValue, nil, "failed search result")
   assertEq(nilFirst, 4, "nil action still reports success")
   assertEq(nilNext, 5, "nil action reports its end")
   assertEq(nilValue, nil, "nil action result remains nil")
end

function M.findsWithASpecializedCollectionResult()
   local first, nextPosition, values = run([[
const Words = comptime do
    return nupp.peg.compile("{| { [a-z]+ } (',' { [a-z]+ })* |} !.")
end
return Words:find("invalid;one,two,three")
]])
   assertEq(first, 9, "collection search first byte")
   assertEq(nextPosition, 22, "collection search exclusive next byte")
   assertEq(table.concat(values, ":"), "one:two:three", "collection search value")
end

function M.visitsNonOverlappingMatchesWithoutIteratorObjects()
   local count, positions, values, emptyCount, emptyPositions, laterCount, dynamicCount = run([==[
const Word = comptime do
    return nupp.peg.compile("{ [a-z]+ }")
end
const Empty = comptime do
    return nupp.peg.compile("''", {backend = "lpeg"})
end
local positions: {string} = {}
local values: {string} = {}
local count = Word:forEachMatch("one, two, three", function(
    first: integer,
    nextPosition: integer,
    value: string
)
    positions[#positions + 1] = tostring(first) .. ":" .. tostring(nextPosition)
    values[#values + 1] = value
end)
local emptyPositions: {string} = {}
local emptyCount = Empty:forEachMatch("ab", function(
    first: integer,
    nextPosition: integer,
    value: integer
)
    emptyPositions[#emptyPositions + 1] = tostring(first) .. ":"
        .. tostring(nextPosition) .. ":" .. tostring(value)
end)
local laterCount = Empty:forEachMatch("ab", function() end, 2)
local grammar: string = "'x'"
local Dynamic = nupp.peg.compile(grammar)
local dynamicCount = Dynamic:forEachMatch("x-x-x", function() end)
return count, table.concat(positions, "|"), table.concat(values, "|"),
    emptyCount, table.concat(emptyPositions, "|"), laterCount, dynamicCount
]==])
   assertEq(count, 3, "visitor count")
   assertEq(positions, "1:4|6:9|11:16", "half-open visitor positions")
   assertEq(values, "one|two|three", "typed visitor values")
   assertEq(emptyCount, 3, "empty matcher visits every boundary once")
   assertEq(emptyPositions, "1:1:1|2:2:2|3:3:3", "empty match progress")
   assertEq(laterCount, 2, "empty iteration respects init")
   assertEq(dynamicCount, 3, "runtime grammar iteration")
end

function M.generatesByteTraversalForRepeatedAtoms()
   local recognizerCount, recognizerValues, captured, fromSecond, eofCount,
      eofPosition, runtimeCount, lpegCount = run([==[
const Token = comptime do
    return nupp.peg.compile("[A-Z] [a-z]*")
end
const Captured = comptime do
    return nupp.peg.compile("{ [0-9]+ }")
end
const AtEnd = comptime do
    return nupp.peg.compile("[0-9]+ !.")
end
const LPEG = comptime do
    return nupp.peg.compile("[A-Z] [a-z]*", {backend = "lpeg"})
end

local recognizerValues: {string} = {}
local recognizerCount = Token:forEachMatch("A Abc X", function(
    first: integer, nextPosition: integer, value: integer
)
    recognizerValues[#recognizerValues + 1] = tostring(first) .. ":"
        .. tostring(nextPosition) .. ":" .. tostring(value)
end)
local captured: {string} = {}
Captured:forEachMatch("a1 b22 c333", function(
    _: integer, _: integer, value: string
)
    captured[#captured + 1] = value
end)
local fromSecond = Token:forEachMatch("A Abc X", function() end, 2)
local eofPosition = 0
local eofCount = AtEnd:forEachMatch("1 x 22", function(first: integer)
    eofPosition = first
end)
local grammar: string = "[0-9]+"
local Runtime = nupp.peg.compile(grammar)
local runtimeCount = Runtime:forEachMatch("a1 b22 c333", function() end)
local lpegCount = LPEG:forEachMatch("A Abc X", function() end)
return recognizerCount, table.concat(recognizerValues, "|"),
    table.concat(captured, "|"), fromSecond, eofCount, eofPosition,
    runtimeCount, lpegCount
]==])
   assertEq(recognizerCount, 3, "generated traversal count")
   assertEq(recognizerValues, "1:2:2|3:6:6|7:8:8",
      "generated recognizer traversal values")
   assertEq(captured, "1|22|333", "generated traversal capture values")
   assertEq(fromSecond, 2, "generated traversal respects init")
   assertEq(eofCount, 1, "EOF traversal ignores earlier failed runs")
   assertEq(eofPosition, 5, "EOF traversal finds the final run")
   assertEq(runtimeCount, 3, "runtime programs generate traversal")
   assertEq(lpegCount, recognizerCount, "LPeg traversal retains parity")
end

function M.replacesFirstAndAllMatchesWithLiteralOrComputedText()
   local first, every, computed, unchanged, fromSecond, runtime, literalPercent,
      punctuation = run([==[
const Digits = comptime do
    return nupp.peg.compile("[0-9]+")
end
const Word = comptime do
    return nupp.peg.compile("{ [a-z]+ }")
end
local first = Digits:replace("room 42, floor 3", "#")
local every = Digits:replaceAll("room 42, floor 3", "#")
local computed = Word:replaceAll("one, two", function(
    first: integer,
    nextPosition: integer,
    value: string
): string
    return tostring(first) .. "=" .. value:upper() .. "@" .. tostring(nextPosition)
end)
local unchanged = Digits:replaceAll("none", "#")
local fromSecond = Digits:replaceAll("1 2 3", "#", 3)
local grammar: string = "[a-z]+"
local Runtime = nupp.peg.compile(grammar)
local runtime = Runtime:replaceAll("a-zz", "_")
local literalPercent = Digits:replaceAll("a1 b22", "%1")
local Dot = nupp.peg.compile("'a.b'")
local punctuation = Dot:replaceAll("a.b axb a.b", "x")
return first, every, computed, unchanged, fromSecond, runtime, literalPercent,
    punctuation
]==])
   assertEq(first, "room #, floor 3", "first literal replacement")
   assertEq(every, "room #, floor #", "all literal replacements")
   assertEq(computed, "1=ONE@4, 6=TWO@9", "typed replacement callback")
   assertEq(unchanged, "none", "missing match returns original text")
   assertEq(fromSecond, "1 # #", "replacement respects init")
   assertEq(runtime, "_-_", "runtime grammar replacement")
   assertEq(literalPercent, "a%1 b%1", "replacement strings stay literal")
   assertEq(punctuation, "x axb x", "literal search stays literal in generated replacement")
end

function M.specializesStaticallyKnownReplacementKinds()
   local source = [==[
local Digits = nupp.peg.compile("[0-9]+")
local callback = function(
    _: integer, _: integer, value: integer
): string
    return "<" .. tostring(value) .. ">"
end
local dynamic: string | function(integer, integer, integer): string = "!"
return Digits:replace("a12b", "#"), Digits:replace("a12b", callback),
    Digits:replaceAll("1 22", "#"), Digits:replaceAll("1 22", callback),
    Digits:replaceAll("1 22", dynamic)
]==]
   local code, diagnostics = compile(source)
   for _, diagnostic in ipairs(diagnostics) do
      assert(diagnostic.severity == "warning" or diagnostic.severity == "note",
         diagnostic.code .. ": " .. diagnostic.msg)
   end
   assert(code:find("Digits :__nuppPegReplaceLiteral (", 1, true), code)
   assert(code:find("Digits :__nuppPegReplaceCallback (", 1, true), code)
   assert(code:find("Digits :__nuppPegReplaceAllLiteral (", 1, true), code)
   assert(code:find("Digits :__nuppPegReplaceAllCallback (", 1, true), code)
   assert(code:find("Digits : replaceAll ( \"1 22\" , dynamic )", 1, true), code)

   local literalFirst, callbackFirst, literalAll, callbackAll, dynamicAll = run(source)
   assertEq(literalFirst, "a#b", "literal replace fast path")
   assertEq(callbackFirst, "a<4>b", "callback replace fast path")
   assertEq(literalAll, "# #", "literal replaceAll fast path")
   assertEq(callbackAll, "<2> <5>", "callback replaceAll fast path")
   assertEq(dynamicAll, "! !", "union replacement retains dynamic dispatch")
end

function M.replacementMakesProgressAfterEmptyMatches()
   local first, every, later, emptySubject, endOnly = run([==[
const Empty = comptime do
    return nupp.peg.compile("''", {backend = "lpeg"})
end
const End = comptime do
    return nupp.peg.compile("!.")
end
return Empty:replace("ab", "-"), Empty:replaceAll("ab", "-"),
    Empty:replaceAll("ab", "-", 2), Empty:replaceAll("", "-"),
    End:replaceAll("ab", "!")
]==])
   assertEq(first, "-ab", "first empty replacement inserts once")
   assertEq(every, "-a-b-", "empty replacement visits every boundary")
   assertEq(later, "a-b-", "empty replacement preserves prefix before init")
   assertEq(emptySubject, "-", "empty subject has one boundary")
   assertEq(endOnly, "ab!", "end assertion replaces final empty match")
end

function M.scansOnlyBytesThatCanBeginANonemptyMatch()
   local staticFirst, staticNext, staticValue, lpegFirst, runtimeFirst, replaced,
      recursiveFirst, predicateFirst, specialFirst = run([==[
const Digits = comptime do
    return nupp.peg.compile("{ [0-9]+ }")
end
const DigitsLpeg = comptime do
    return nupp.peg.compile("{ [0-9]+ }", {backend = "lpeg"})
end
const Recursive = comptime do
    return nupp.peg.compile("value <- 'x' / '(' value ')'")
end
const Predicate = comptime do
    return nupp.peg.compile("!'x' [a-z]+")
end
const Special = comptime do
    return nupp.peg.compile("']' / '-' / '^' / '%'")
end

local subject = string.rep("a", 10000) .. "42"
local staticFirst, staticNext, staticValue = Digits:find(subject)
local lpegFirst = DigitsLpeg:find(subject)
local grammar: string = "[0-9]+"
local Runtime = nupp.peg.compile(grammar)
local runtimeFirst = Runtime:find(subject)
local replaced = Digits:replaceAll("a1 b22 c333", "#")
local recursiveFirst = Recursive:find("---(((x)))")
local predicateFirst = Predicate:find("xabc")
local specialFirst = Special:find("abc^def")
return staticFirst, staticNext, staticValue, lpegFirst, runtimeFirst, replaced,
    recursiveFirst, predicateFirst, specialFirst
]==])
   assertEq(staticFirst, 10001, "static first-byte scan")
   assertEq(staticNext, 10003, "static scan result end")
   assertEq(staticValue, "42", "static scan capture")
   assertEq(lpegFirst, staticFirst, "forced LPeg first-byte scan")
   assertEq(runtimeFirst, staticFirst, "runtime first-byte scan")
   assertEq(replaced, "a# b# c#", "replacement uses the shared scan")
   assertEq(recursiveFirst, 4, "recursive first set")
   assertEq(predicateFirst, 2, "predicate before consuming prefix")
   assertEq(specialFirst, 4, "Lua-pattern punctuation is escaped")

   local code = compile([==[
const Digits = comptime do
    return nupp.peg.compile("[0-9]+")
end
return Digits:isMatch("room 42")
]==])
   assert(code:find("search={", 1, true), code)
end

function M.keepsSemanticallySensitiveSearchesOnTheGeneralPath()
   local emptyFirst, emptyNext, anyFirst, anyNext, positionFirst, positionNext,
      positionValue, possessiveFirst = run([==[
const Empty = comptime do
    return nupp.peg.compile("''")
end
const Any = comptime do
    return nupp.peg.compile(".")
end
const Position = comptime do
    return nupp.peg.compile("{} 'x'")
end
const Possessive = comptime do
    return nupp.peg.compile("[a-z]+ 'x'")
end
local emptyFirst, emptyNext = Empty:find("abc", 3)
local anyFirst, anyNext = Any:find("abc", 2)
local positionFirst, positionNext, positionValue = Position:find("--x")
local possessiveFirst = Possessive:find("ax")
return emptyFirst, emptyNext, anyFirst, anyNext, positionFirst, positionNext,
    positionValue, possessiveFirst
]==])
   assertEq(emptyFirst, 3, "nullable search retains its requested boundary")
   assertEq(emptyNext, 3, "nullable search remains empty")
   assertEq(anyFirst, 2, "any-byte search retains its requested byte")
   assertEq(anyNext, 3, "any-byte search consumes one byte")
   assertEq(positionFirst, 3, "position capture search start")
   assertEq(positionNext, 4, "position capture match end")
   assertEq(positionValue, 3, "direct recognition does not replace position captures")
   assertEq(possessiveFirst, nil, "Lua-pattern backtracking does not replace PEG repetition")
end

function M.typesRepeatedMatchingAndReplacementCallbacksFromTheGrammarResult()
   local codes = errorsOf([==[
const Word = comptime do
    return nupp.peg.compile("{ [a-z]+ }")
end
Word:forEachMatch("hello", function(_: integer, _: integer, value: integer)
    print(value)
end)
]==])
   assertEq(codes[1], "NUPP2006", "visitor result type")

   codes = errorsOf([==[
const Word = comptime do
    return nupp.peg.compile("{ [a-z]+ }")
end
Word:replaceAll("hello", function(_: integer, _: integer, _: string): integer
    return 1
end)
]==])
   assert(#codes > 0, "replacement callback must return a string")
end

function M.infersStaticMatcherResultsFromTheCanonicalGrammarAnalysis()
   local identifier, word, words = run([==[
const Identifier = comptime do
    return nupp.peg.compile("[a-zA-Z_] [a-zA-Z_0-9]* !.")
end
const Word = comptime do
    return nupp.peg.compile("{ [a-z]+ } !.")
end
const Words = comptime do
    return nupp.peg.compile("{| { [a-z]+ } (',' { [a-z]+ })* |} !.")
end
local identifier: integer = assert(Identifier("name"))
local word: string = assert(Word("hello"))
local words: {string} = assert(Words("one,two"))
return identifier, word, words
]==])
   assertEq(identifier, 5, "inferred recognizer result")
   assertEq(word, "hello", "inferred capture result")
   assertEq(table.concat(words, ":"), "one:two", "inferred collection result")

   local codes = errorsOf([==[
const Word = comptime do
    return nupp.peg.compile("{ [a-z]+ } !.")
end
local wrong: integer = assert(Word("hello"))
]==])
   assertEq(codes[1], "NUPP2001", "inferred matcher remains precise")
end

function M.requiresAFactoryBoundaryWhenStaticActionsNeedResultTypes()
   local codes, diagnostics = errorsOf([==[
const Number = comptime do
    return nupp.peg.compile("%d+ -> number !.")
end
]==])
   assertEq(codes[1], "NUPP2414", "action inference boundary")
   assert(diagnostics[1].msg:find("declared matcher factory type", 1, true), diagnostics[1].msg)
end

function M.returnsATypedSubstringCapture()
   local value = run([[
const Word: nupp.peg.Peg<string> = comptime do
    return nupp.peg.compile("{ [a-zA-Z]+ } !.")
end
return Word("Hello")
]])
   assertEq(value, "Hello", "substring capture")
end

function M.collectsRepeatedCapturesExplicitly()
   local values, found = run([[
const Words: nupp.peg.Peg<{string}> = comptime do
    return nupp.peg.compile("{| { [a-z]+ } (',' { [a-z]+ })* |} !.")
end
return Words("one,two,three"), Words:isMatch("invalid;one,two,three")
]])
   assertEq(#values, 3, "collection length")
   assertEq(table.concat(values, ":"), "one:two:three", "collection values")
   assertEq(found, true, "specialized collection search")
end

function M.groupsRepeatedCapturesExplicitly()
   local values = run([[
local matcher: nupp.peg.Peg<{string}> = comptime do
    return nupp.peg.compile("{| { [a-z]+ } (',' { [a-z]+ })* |} !.")
end
return matcher("one,two,three")
]])
   assertEq(table.concat(values, ":"), "one:two:three", "grouped values")
end

function M.excludesPegSupportFromUnrelatedPrograms()
   local code = compile("return 42")
   assertEq(code:find("__nuppPegVM", 1, true), nil, "unused helper")
   assertEq(code:find("__nuppPegCodegen", 1, true), nil, "unused code generator")
end

function M.buildsATypedMatcherFactoryForRuntimeActions()
   local result, calls = run([[
local record NumberActions
    number: function(text: string): integer
end

const Number: function(NumberActions): nupp.peg.Peg<integer> = comptime do
    return nupp.peg.compile("[0-9]+ -> number !.")
end

local calls = 0
local matcher = Number(new NumberActions(
    number = function(text: string): integer
        calls = calls + 1
        return tonumber(text) as integer
    end
))
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
const Build: function(Actions): nupp.peg.Peg<string> = comptime do
    return nupp.peg.compile("(('a' -> text) 'z' / ('ab' -> text)) !.")
end
local calls = 0
local matcher = Build(new Actions(
    text = function(value: string): string
        calls = calls + 1
        return value
    end
))
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

const Build: function(Actions): nupp.peg.Peg<{integer}> = comptime do
    return nupp.peg.compile("{| ([0-9]+ -> number) (',' ([0-9]+ -> number))* |} !.")
end

local matcher = Build(new Actions(
    number = function(value: string): integer
        return tonumber(value) as integer
    end
))
return matcher("10,20,30")
]])
   assertEq(#values, 3, "action collection length")
   assertEq(values[1] + values[2] + values[3], 60, "typed action collection")
end

function M.requiresTheExactDefinitionSlotRecord()
   local missing = errorsOf([[
local record Empty end
const Build: function(Empty): nupp.peg.Peg<string> = comptime do
    return nupp.peg.compile("'x' -> text")
end
]])
   assertEq(missing[1], "NUPP2415", "missing action slot")

   local extra = errorsOf([[
local record Actions
    text: function(value: string): string
    unused: string
end
const Build: function(Actions): nupp.peg.Peg<string> = comptime do
    return nupp.peg.compile("'x' -> text")
end
]])
   assertEq(extra[1], "NUPP2415", "unknown definition slot")
end

function M.matchesARecursiveGrammar()
   local source = [[
const Nested: nupp.peg.Peg<integer> = comptime do
    return nupp.peg.compile("start <- value !. value <- 'x' / '(' value ')'")
end
return Nested("(((x)))"), Nested("((x)")
]]
   local matched, missed = run(source)
   assertEq(matched, 8, "recursive match")
   assertEq(missed, nil, "unclosed recursion fails")
end

function M.runsDeepTailRecursiveGrammarsInLpeg()
   local matched = run([[
const Nested: nupp.peg.Peg<integer> = comptime do
    return nupp.peg.compile("start <- value !. value <- 'x' / '(' value ')'", {backend = "lpeg"})
end
local depth = 2000
local subject = string.rep("(", depth) .. "x" .. string.rep(")", depth)
return Nested(subject)
]])
   assertEq(matched, 4002, "deep recursive match")
end

function M.supportsPositionAnyAndOptionalPatterns()
   local empty, byte, tooLong = run([[
const Located: nupp.peg.Peg<integer> = comptime do
    return nupp.peg.compile("{} .? !.")
end
return Located(""), Located("x"), Located("xy")
]])
   assertEq(empty, 1, "empty position")
   assertEq(byte, 1, "position before optional byte")
   assertEq(tooLong, nil, "optional consumes at most one byte")
end

function M.exposesOnlyTextualGrammarCompilation()
   local codes = errorsOf([[
local pattern = nupp.peg.literal("x")
]])
   assertEq(codes[1], "NUPP2004", "node constructors are not public")
end

function M.supportsDifferenceAndPredicates()
   local good, keyword, digit = run([[
const Name: nupp.peg.Peg<integer> = comptime do
    return nupp.peg.compile("!('if' !.) &[a-z] [a-z]+ !.")
end
return Name("item"), Name("if"), Name("7")
]])
   assertEq(good, 5, "predicate match")
   assertEq(keyword, nil, "negative predicate")
   assertEq(digit, nil, "difference")
end

function M.usesLpegExponentSemantics()
   local twice, once, thrice, capped = run([[
const AtLeastTwo: nupp.peg.Peg<integer> = comptime do
    return nupp.peg.compile("'a'^+2 !.")
end
const AtMostTwo: nupp.peg.Peg<integer> = comptime do
    return nupp.peg.compile("'a'^-2 !.")
end
return AtLeastTwo("aa"), AtLeastTwo("a"), AtLeastTwo("aaa"), AtMostTwo("aa")
]])
   assertEq(twice, 3, "positive exponent minimum")
   assertEq(once, nil, "positive exponent rejects fewer")
   assertEq(thrice, 4, "positive exponent accepts more")
   assertEq(capped, 3, "negative exponent maximum")
end

function M.agreesWithLpegOnTheOverlappingFloor()
   local lpeg = officialLpeg()
   local matcher = run([[
const Identifier: nupp.peg.Peg<integer> = comptime do
    return nupp.peg.compile("[a-zA-Z_] [a-zA-Z_0-9]* !.")
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

function M.agreesWithLpegOnMultipleResultsCmtAndBehind()
   local got = run([==[
local packageAny: any = package
local previous = packageAny.loaded.lpeg
packageAny.loaded.lpeg = nil
local lpeg: any = require("lpeg")
packageAny.loaded.lpeg = previous
local function pack(...: any): any
    return {n = select("#", ...), ...}
end
local direct = pack((lpeg.C("a") * lpeg.C("b") * lpeg.Cc(nil, "tail")):match("ab"))
local transform: any = function(value: string): (string, string, nil, string)
    return value, value:upper(), nil, "tail"
end
local transformed = pack((lpeg.C("a") / transform):match("a"))
local matchTime = pack(lpeg.Cmt(lpeg.C("a"), function(
    _: string, _: integer, value: string
): (boolean, string, string, nil, string)
    return true, value, value:upper(), nil, "tail"
end):match("a"))
local rewound, rewindError = pcall(function(): any
    return lpeg.Cmt(lpeg.P("a"), function(): integer return 1 end):match("a")
end)
local capturedBehind = pcall(lpeg.B, lpeg.C("a"))
local variableBehind = pcall(lpeg.B, lpeg.P("a") ^ 0)
local longBehind = pcall(lpeg.B, lpeg.P(256))
local unresolvedBehind = pcall(lpeg.B, lpeg.V("S"))
local unequalChoiceBehind = pcall(lpeg.B, lpeg.P("a") + lpeg.P("bc"))
local mixedUtfBehind = pcall(lpeg.B, lpeg.utfR(0x7f, 0x80))
local fixedBehind = (lpeg.P("a") * lpeg.B(lpeg.P("a")) * lpeg.P("b")):match("ab")
local grammarPattern = lpeg.P({lpeg.V("S"), S = lpeg.P("a")})
local grammarBehind = (lpeg.P("a") * lpeg.B(grammarPattern) * lpeg.P("b")):match("ab")
local twoByte = string.char(0xc2, 0x80)
local utfBehind = (lpeg.utfR(0x80, 0x7ff) * lpeg.B(lpeg.utfR(0x80, 0x7ff))
    * lpeg.P("x")):match(twoByte .. "x")
local numericGrammar = lpeg.P({lpeg.V(2), [2] = lpeg.P("x")}):match("x")
local booleanGrammar = lpeg.P({lpeg.V(true), [true] = lpeg.P("x")}):match("x")
local classes = lpeg.locale()
local invalidStack = pcall(lpeg.setmaxstack, 0)
lpeg.setmaxstack(400)
return {
    direct = direct,
    transformed = transformed,
    matchTime = matchTime,
    rewound = rewound,
    rewindError = tostring(rewindError),
    capturedBehind = capturedBehind,
    variableBehind = variableBehind,
    longBehind = longBehind,
    unresolvedBehind = unresolvedBehind,
    unequalChoiceBehind = unequalChoiceBehind,
    mixedUtfBehind = mixedUtfBehind,
    fixedBehind = fixedBehind,
    grammarBehind = grammarBehind,
    utfBehind = utfBehind,
    numericGrammar = numericGrammar,
    booleanGrammar = booleanGrammar,
    versionType = type(lpeg.version),
    version = lpeg.version,
    printableSpace = classes.print:match(" "),
    printableNewline = classes.print:match("\n"),
    invalidStack = invalidStack,
}
]==])

   local lpeg = officialLpeg()
   local function pack(...)
      return {n = select("#", ...), ...}
   end
   local want = {}
   want.direct = pack((lpeg.C("a") * lpeg.C("b") * lpeg.Cc(nil, "tail")):match("ab"))
   want.transformed = pack((lpeg.C("a") / function(value)
      return value, value:upper(), nil, "tail"
   end):match("a"))
   want.matchTime = pack(lpeg.Cmt(lpeg.C("a"), function(_, _, value)
      return true, value, value:upper(), nil, "tail"
   end):match("a"))
   want.rewound, want.rewindError = pcall(function()
      return lpeg.Cmt(lpeg.P("a"), function() return 1 end):match("a")
   end)
   want.capturedBehind = pcall(lpeg.B, lpeg.C("a"))
   want.variableBehind = pcall(lpeg.B, lpeg.P("a") ^ 0)
   want.longBehind = pcall(lpeg.B, lpeg.P(256))
   want.unresolvedBehind = pcall(lpeg.B, lpeg.V("S"))
   want.unequalChoiceBehind = pcall(lpeg.B, lpeg.P("a") + lpeg.P("bc"))
   want.mixedUtfBehind = pcall(lpeg.B, lpeg.utfR(0x7f, 0x80))
   want.fixedBehind = (lpeg.P("a") * lpeg.B(lpeg.P("a")) * lpeg.P("b")):match("ab")
   local grammarPattern = lpeg.P({lpeg.V("S"), S = lpeg.P("a")})
   want.grammarBehind = (lpeg.P("a") * lpeg.B(grammarPattern) * lpeg.P("b"))
      :match("ab")
   local twoByte = string.char(0xc2, 0x80)
   want.utfBehind = (lpeg.utfR(0x80, 0x7ff) * lpeg.B(lpeg.utfR(0x80, 0x7ff))
      * lpeg.P("x")):match(twoByte .. "x")
   want.numericGrammar = lpeg.P({lpeg.V(2), [2] = lpeg.P("x")}):match("x")
   want.booleanGrammar = lpeg.P({lpeg.V(true), [true] = lpeg.P("x")}):match("x")
   local classes = lpeg.locale()
   want.versionType, want.version = type(lpeg.version), lpeg.version
   want.printableSpace, want.printableNewline = classes.print:match(" "),
      classes.print:match("\n")
   want.invalidStack = pcall(lpeg.setmaxstack, 0)
   lpeg.setmaxstack(400)

   for _, name in ipairs({"direct", "transformed", "matchTime"}) do
      assertEq(got[name].n, want[name].n, name .. " result count")
      for index = 1, want[name].n do
         assertEq(got[name][index], want[name][index], name .. " result " .. index)
      end
   end
   for _, name in ipairs({
      "rewound", "capturedBehind", "variableBehind", "longBehind",
      "unresolvedBehind", "unequalChoiceBehind", "mixedUtfBehind",
      "fixedBehind", "grammarBehind", "utfBehind", "numericGrammar",
      "booleanGrammar", "versionType", "version", "printableSpace",
      "printableNewline", "invalidStack",
   }) do
      assertEq(got[name], want[name], "LPeg facade " .. name)
   end
   assert(got.rewindError:find("invalid position returned by match%-time capture"),
      got.rewindError)
end

function M.typesFixedAndCallbackProducedLpegCaptureTuples()
   local first, second, third, literalText, transformedText,
      transformedNumber, runtimeText, runtimeNumber = run([==[
local lpeg = require("lpeg")
local constants = lpeg.Cc("name", 42, true)
local first, second, third = constants:match("")
local checkedFirst: string? = first
local checkedSecond: integer? = second
local checkedThird: boolean? = third

local capturedLiteral = lpeg.C(lpeg.P("word"))
local literalText = capturedLiteral:match("word")
local checkedLiteralText: string? = literalText

local transformed = lpeg.C("a") / function(value: string): (string, integer)
    return value:upper(), 7
end
local transformedText, transformedNumber = transformed:match("a")
local checkedTransformedText: string? = transformedText
local checkedTransformedNumber: integer? = transformedNumber

local runtime = lpeg.P(function(_: string, position: integer):
    (integer, string, integer)
    return position, "runtime", 9
end)
local runtimeText, runtimeNumber = runtime:match("")
local checkedRuntimeText: string? = runtimeText
local checkedRuntimeNumber: integer? = runtimeNumber
return checkedFirst, checkedSecond, checkedThird, checkedLiteralText,
    checkedTransformedText, checkedTransformedNumber, checkedRuntimeText,
    checkedRuntimeNumber
]==])
   assertEq(first, "name", "typed first constant capture")
   assertEq(second, 42, "typed second constant capture")
   assertEq(third, true, "typed third constant capture")
   assertEq(literalText, "word", "typed nested pattern capture")
   assertEq(transformedText, "A", "typed callback text result")
   assertEq(transformedNumber, 7, "typed callback integer result")
   assertEq(runtimeText, "runtime", "typed runtime capture text")
   assertEq(runtimeNumber, 9, "typed runtime capture integer")

   local codes = errorsOf([==[
local lpeg = require("lpeg")
local first, second = lpeg.Cc("name", 42):match("")
local wrong: boolean? = second
]==])
   assertEq(table.concat(codes, " "), "NUPP2001",
      "heterogeneous captures cannot be assigned as the wrong slot type")
end

function M.matchesLpegConstructionUtfAndRepresentationSemantics()
   local got = run([==[
local lpeg = require("lpeg")
local P, V = lpeg.P, lpeg.V
local pattern = P("a")
local mutable = pcall(function() (pattern as any).node = {} end)
local emptyLoop = pcall(function() return P("") ^ 0 end)
local captureLoop = pcall(function() return lpeg.Cc("x") ^ 0 end)
local undefined = pcall(function() return P({V("missing"), start = P("x")}) end)
local left = pcall(function()
    return P({"S", S = V("S") * P("a") + P("")})
end)
local right = pcall(function()
    return P({"S", S = P("a") * V("S") + P("")})
end)
local lookup = lpeg.C(P("missing")) / {}
local overlong = string.char(0xe0, 0x80, 0x80)
local tooLarge = string.char(0xf4, 0x90, 0x80, 0x80)
local surrogate = string.char(0xed, 0xa0, 0x80)
local utf = lpeg.utfR(0, 0x10ffff)
local invalidLow = pcall(lpeg.utfR, -1, 1)
local invalidHigh = pcall(lpeg.utfR, 0, 0x110000)
local invalidOrder = pcall(lpeg.utfR, 2, 1)
lpeg.setmaxstack(2)
local flat = (P("a") * P("b") * P("c") * P("d")):match("abcd")
local overflow = pcall(function()
    return P({"S", S = P("a") * V("S") + P("")}):match("aaaa")
end)
lpeg.setmaxstack(400)
return {
    luaType = type(pattern),
    lpegType = lpeg.type(pattern),
    tostringPrefix = tostring(pattern):match("^userdata:") ~= nil,
    mutable = mutable,
    selfField = (lpeg as any).lpeg,
    emptyLoop = emptyLoop,
    captureLoop = captureLoop,
    undefined = undefined,
    left = left,
    right = right,
    missingLookup = lookup:match("missing"),
    overlong = utf:match(overlong),
    tooLarge = utf:match(tooLarge),
    surrogate = utf:match(surrogate),
    invalidLow = invalidLow,
    invalidHigh = invalidHigh,
    invalidOrder = invalidOrder,
    flat = flat,
    overflow = overflow,
}
]==])
   assertEq(got.luaType, "userdata", "patterns are opaque userdata")
   assertEq(got.lpegType, "pattern", "lpeg.type recognizes facade userdata")
   assertEq(got.tostringPrefix, true, "pattern reflection matches LPeg's shape")
   assertEq(got.mutable, false, "pattern state cannot be mutated")
   assertEq(got.selfField, nil, "LPeg does not expose a nonstandard self field")
   assertEq(got.emptyLoop, false, "empty repetition fails during construction")
   assertEq(got.captureLoop, false, "capture-only repetition fails during construction")
   assertEq(got.undefined, false, "undefined rules fail during construction")
   assertEq(got.left, false, "left recursion fails during construction")
   assertEq(got.right, true, "right recursion remains valid")
   assertEq(got.missingLookup, 8, "a missing query capture produces zero values")
   assertEq(got.overlong, nil, "utfR rejects overlong UTF-8")
   assertEq(got.tooLarge, nil, "utfR rejects code points above Unicode")
   assertEq(got.surrogate, 4, "utfR retains LPeg's code-point range semantics")
   assertEq(got.invalidLow, false, "utfR rejects a negative lower bound")
   assertEq(got.invalidHigh, false, "utfR rejects a bound above Unicode")
   assertEq(got.invalidOrder, false, "utfR rejects an inverted range")
   assertEq(got.flat, 5, "flat AST depth does not consume backtrack stack")
   assertEq(got.overflow, true, "LPeg optimizes tail-recursive grammar calls")
end

function M.bundlesTheReferenceReModuleOverTheLpegFacade()
   local captured, first, last, replaced, patternType = run([==[
local re = require("re")
local pattern = re.compile("{[a-z]+} ':' {[0-9]+} !.")
local captured = {pattern:match("item:42")}
local first, last = re.find("-- item:42 --", "[a-z]+ ':' [0-9]+")
return captured, first, last, re.gsub("a1b22", "[0-9]+", "#"), type(pattern)
]==])
   assertEq(captured[1], "item", "bundled re first capture")
   assertEq(captured[2], "42", "bundled re second capture")
   assertEq(first, 4, "bundled re find start")
   assertEq(last, 10, "bundled re find inclusive end")
   assertEq(replaced, "a#b#", "bundled re global substitution")
   assertEq(patternType, "userdata", "re compiles to the same opaque pattern")
end

function M.agreesWithLpegReOnTheCaptureSurface()
   local lpeg = officialLpeg()
   local re = officialRe(lpeg)
   local same, fields, substitution, selected, formatted, upper, matchTime,
      fold, accumulate, external, externalClass, multiple, nestedCapture = run([==[
const Same: nupp.peg.Peg<any> = comptime do
    return nupp.peg.compile("{:word: { [a-z]+ } :} '=' =word !.")
end
local Fields = nupp.peg.compile("{| {:name: { [a-z]+ } :} ':' { [0-9]+ } |} !.")
local Substitution = nupp.peg.compile("{~ (({ [0-9]+ } -> '#') / .)* ~} !.")
local Selected = nupp.peg.compile("({.} {.}) -> 2 !.")
local Formatted = nupp.peg.compile("({.} {.}) -> '%2%1' !.")
local Upper = nupp.peg.compile("{[a-z]+} -> upper !.", {
    definitions = {upper = function(value: string): string return value:upper() end},
})
local MatchTime = nupp.peg.compile("{[a-z]+} => accept !.", {
    definitions = {accept = function(_: string, position: integer, value: string)
        return position, value .. "!"
    end},
})
local function sum(left: any, right: any): integer
    return (assert(tonumber(left)) + assert(tonumber(right))) as integer
end
local Fold = nupp.peg.compile("({[0-9]} {[0-9]}*) ~> sum !.", {
    definitions = {sum = sum},
})
local Accumulate = nupp.peg.compile("{[0-9]} ({[0-9]} >> sum)* !.", {
    definitions = {sum = sum},
})
local External = nupp.peg.compile("%token !.", {
    definitions = {token = "ok"},
})
local ExternalClass = nupp.peg.compile("[%token] !.", {
    definitions = {token = "ok"},
})
local Multiple = nupp.peg.compile("{| {[a-z]+} -> both |} !.", {
    definitions = {both = function(value: string) return value, value:upper() end},
})
local NestedCapture = nupp.peg.compile("{| { {'a'} } |} !.")
return Same, Fields, Substitution, Selected, Formatted, Upper, MatchTime,
    Fold, Accumulate, External, ExternalClass, Multiple, NestedCapture
]==])

   local sameOracle = re.compile("{:word: { [a-z]+ } :} '=' =word !.")
   for _, subject in ipairs({"abc=abc", "abc=abd", "x=x"}) do
      assertEq(same(subject), sameOracle:match(subject),
         "named back capture oracle for " .. subject)
   end

   local fieldsOracle = re.compile(
      "{| {:name: { [a-z]+ } :} ':' { [0-9]+ } |} !.")
   local gotFields, wantFields = fields("age:42"), fieldsOracle:match("age:42")
   assertEq(gotFields.name, wantFields.name, "named table field oracle")
   assertEq(gotFields[1], wantFields[1], "positional table field oracle")

   local cases = {
      {substitution, re.compile("{~ (({ [0-9]+ } -> '#') / .)* ~} !."), "a12b"},
      {selected, re.compile("({.} {.}) -> 2 !."), "xy"},
      {formatted, re.compile("({.} {.}) -> '%2%1' !."), "xy"},
      {upper, re.compile("{[a-z]+} -> upper !.", {
         upper = function(value) return value:upper() end,
      }), "hello"},
      {matchTime, re.compile("{[a-z]+} => accept !.", {
         accept = function(_, position, value) return position, value .. "!" end,
      }), "hello"},
      {fold, re.compile("({[0-9]} {[0-9]}*) ~> sum !.", {
         sum = function(left, right) return tonumber(left) + tonumber(right) end,
      }), "123"},
      {accumulate, re.compile("{[0-9]} ({[0-9]} >> sum)* !.", {
         sum = function(left, right) return tonumber(left) + tonumber(right) end,
      }), "123"},
      {external, re.compile("%token !.", {token = "ok"}), "ok"},
      {externalClass, re.compile("[%token] !.", {token = "ok"}), "ok"},
   }
   for index, case in ipairs(cases) do
      assertEq(case[1](case[3]), case[2]:match(case[3]),
         "LPeg re capture oracle case " .. index)
   end
   local gotMultiple = multiple("hi")
   local wantMultiple = re.compile("{| {[a-z]+} -> both |} !.", {
      both = function(value) return value, value:upper() end,
   }):match("hi")
   assertEq(gotMultiple[1], wantMultiple[1], "first transformed capture")
   assertEq(gotMultiple[2], wantMultiple[2], "second transformed capture")
   local gotNested = nestedCapture("a")
   local wantNested = re.compile("{| { {'a'} } |} !."):match("a")
   assertEq(gotNested[1], wantNested[1], "outer substring capture")
   assertEq(gotNested[2], wantNested[2], "nested substring capture")
end

function M.searchesGeneralRecognitionProgramsWithoutLosingTheirEndPosition()
   local first, nextPosition, value = run([[
local Suppressed = nupp.peg.compile("({.}) -> 0")
return Suppressed:find("x")
]])
   assertEq(first, 1, "general recognizer first position")
   assertEq(nextPosition, 2, "general recognizer exclusive end")
   assertEq(value, 2, "general recognizer result")
end

function M.compilesReNotationAtComptime()
   local source = [==[
const Identifier: nupp.peg.Peg<integer> = comptime do
    return nupp.peg.compile([[
        [a-zA-Z_] [a-zA-Z_0-9]* !.
    ]])
end
return Identifier("_name9"), Identifier("9name"), Identifier("name!")
]==]
   local matched, badHead, badTail = run(source)
   assertEq(matched, 7, "re notation static match")
   assertEq(badHead, nil, "re notation static head rejection")
   assertEq(badTail, nil, "re notation static eof rejection")
   local code = compile(source)
   assert(code:find("(__nuppPegCodegen)({", 1, true), code)
   assertEq(code:find("__nuppPegReInstall", 1, true), nil,
      "static re grammar excludes the runtime frontend")
end

function M.compilesTheSameReNotationAtRuntime()
   local static, dynamic = run([==[
const Static: nupp.peg.Peg<integer> = comptime do
    return nupp.peg.compile([[
        ('GET' / 'POST') ' ' [a-z/0-9]+ !.
    ]])
end
local grammar: string = "('GET' / 'POST') ' ' [a-z/0-9]+ !."
local Dynamic = nupp.peg.compile(grammar)
return Static, Dynamic
]==])
   for _, subject in ipairs({"GET /users/42", "POST /items", "PUT /items", "GET /Users"}) do
      assertEq(dynamic(subject), static(subject), "static/runtime re parity for " .. subject)
   end
end

function M.reusesOneMatcherShellAcrossRuntimeBackends()
   local staticResult, dynamicResult, lpegResult, sameTemplate, sameLpegShell = run([==[
const Static: nupp.peg.Peg<integer> = comptime do
    return nupp.peg.compile("[a-zA-Z_] [a-zA-Z_0-9]* !.")
end
local grammar: string = "[a-zA-Z_] [a-zA-Z_0-9]* !."
local Dynamic = nupp.peg.compile(grammar)
local LPEG = nupp.peg.compile(grammar, {backend = "lpeg"})
local staticCode = string.dump((getmetatable(Static) as any).__call)
local dynamicCode = string.dump((getmetatable(Dynamic) as any).__call)
local lpegCode = string.dump((getmetatable(LPEG) as any).__call)
return Static("name9"), Dynamic("name9"), LPEG("name9"),
    staticCode == dynamicCode, dynamicCode == lpegCode
]==])
   assertEq(dynamicResult, staticResult, "runtime specialization result")
   assertEq(lpegResult, staticResult, "forced LPeg result")
   assertEq(sameTemplate, true, "static and runtime use the same matcher template")
   assertEq(sameLpegShell, true, "kernels and LPeg share one matcher shell")
end

function M.supportsRuntimeReCapturesCollectionsAndActions()
   local words, number = run([==[
local words = nupp.peg.compile("{| { [a-z]+ } (',' { [a-z]+ })* |} !.")
local number = nupp.peg.compile("%d+ -> number !.", {
    actions = {
        number = function(text: string): any
            return tonumber(text)
        end,
    },
})
return words("one,two,three"), number("1234")
]==])
   assertEq(table.concat(words, ":"), "one:two:three", "runtime re collection")
   assertEq(number, 1234, "runtime re action")
end

function M.infersLiteralRuntimeMatcherAndActionResults()
   local word, constWord, words, number = run([==[
local Word = nupp.peg.compile("{ [a-z]+ } !.")
const WordGrammar = "{ [a-z]+ } !."
local ConstWord = nupp.peg.compile(WordGrammar)
local Words = nupp.peg.compile("{| { [a-z]+ } (',' { [a-z]+ })* |} !.")
local Number = nupp.peg.compile("%d+ -> number !.", {
    actions = {
        number = function(text: string): integer
            return assert(tonumber(text)) as integer
        end,
    },
})
local word: string = assert(Word("hello"))
local constWord: string = assert(ConstWord("hello"))
local words: {string} = assert(Words("one,two"))
local number: integer = assert(Number("42"))
return word, constWord, words, number
]==])
   assertEq(word, "hello", "literal runtime capture result")
   assertEq(constWord, "hello", "const runtime capture result")
   assertEq(table.concat(words, ":"), "one:two", "literal runtime collection result")
   assertEq(number, 42, "literal runtime action result")
end

function M.supportsRuntimeRecursiveReGrammars()
   local staticMatched, dynamicMatched, staticMissed, dynamicMissed = run([==[
const Static: nupp.peg.Peg<integer> = comptime do
    return nupp.peg.compile([[
        value <- 'x' / '(' value ')'
    ]])
end
local grammar: string = [[
    value <- 'x' / '(' value ')'
]]
local Dynamic = nupp.peg.compile(grammar)
return Static("(((x)))"), Dynamic("(((x)))"), Static("((x)"), Dynamic("((x)")
]==])
   assertEq(staticMatched, 8, "static recursive re match")
   assertEq(dynamicMatched, staticMatched, "recursive re phase parity")
   assertEq(staticMissed, nil, "static recursive re rejection")
   assertEq(dynamicMissed, staticMissed, "recursive re rejection parity")
end

function M.rejectsUnsafeRuntimeReGrammars()
   local nullable, leftRecursive, undefined = run([==[
local function rejected(source: string): boolean
    return not pcall(function()
        nupp.peg.compile(source)
    end)
end
return rejected("('')*"), rejected("value <- value / 'x'"), rejected("value <- missing")
]==])
   assertEq(nullable, true, "runtime nullable repetition rejection")
   assertEq(leftRecursive, true, "runtime left recursion rejection")
   assertEq(undefined, true, "runtime undefined rule rejection")
end

function M.reportsReSyntaxLocationsAtBothPhases()
   local codes, diagnostics = errorsOf([==[
const Broken: nupp.peg.Peg<integer> = comptime do
    return nupp.peg.compile([[
        'ok'
        [
    ]])
end
]==])
   assertEq(codes[1], "NUPP2417", "static re diagnostic code")
   assert(diagnostics[1].msg:find("line 2, column", 1, true), diagnostics[1].msg)

   local ok, why = run([==[
local ok, why = pcall(function()
    nupp.peg.compile("'ok'\n[")
end)
return ok, tostring(why)
]==])
   assertEq(ok, false, "runtime re syntax rejection")
   assert(why:find("pattern error near", 1, true), why)
end

function M.agreesBetweenSpecializedAndGeneralBackends()
   local source = [[
const FastIdentifier: nupp.peg.Peg<integer> = comptime do
    return nupp.peg.compile("[a-zA-Z_] [a-zA-Z_0-9]* !.")
end
const RefIdentifier: nupp.peg.Peg<integer> = comptime do
    return nupp.peg.compile("[a-zA-Z_] [a-zA-Z_0-9]* !.", {backend = "lpeg"})
end
const FastList: nupp.peg.Peg<{string}> = comptime do
    return nupp.peg.compile("{| { [a-z]+ } (',' { [a-z]+ })* |} !.")
end
const RefList: nupp.peg.Peg<{string}> = comptime do
    return nupp.peg.compile("{| { [a-z]+ } (',' { [a-z]+ })* |} !.", {backend = "lpeg"})
end
return FastIdentifier, RefIdentifier, FastList, RefList
]]
   local code = compile(source)
   assert(code:find("(__nuppPegCodegen)({", 1, true), code)
   assert(code:find("(__nuppPegLpeg)({", 1, true), code)
   local fastIdentifier, refIdentifier, fastList, refList = run(source)
   local inputs = {"", "a", "_ok9", "9bad", "alpha,beta", "one,two,three", "one,", ",two"}
   for _, input in ipairs(inputs) do
      assertEq(fastIdentifier(input), refIdentifier(input), "identifier backend parity for " .. input)
      local fast, ref = fastList(input), refList(input)
      assertEq(fast and table.concat(fast, ":"), ref and table.concat(ref, ":"),
         "list backend parity for " .. input)
   end
end

function M.cachesRuntimeLpegPatternsWithoutGeneratingSource()
   local afterFirst, afterCached, afterForced, autoMatched, forcedMatched = run([==[
local original: any = loadstring
local loads = 0
rawset(_G, "loadstring", function(source: string, name: string?)
    loads = loads + 1
    return original(source, name)
end)
local Auto = nupp.peg.compile("[a-z]+")
local afterFirst = loads
local Again = nupp.peg.compile("[a-z]+")
local afterCached = loads
local Forced = nupp.peg.compile("[a-z]+", {backend = "lpeg"})
local afterForced = loads
rawset(_G, "loadstring", original)
return afterFirst, afterCached, afterForced, Auto("hello"), Forced("hello")
]==])
   assertEq(afterFirst, 0, "runtime LPeg compilation generates no Lua source")
   assertEq(afterCached, afterFirst, "runtime code generation is cached")
   assertEq(afterForced, afterCached, "forced LPeg compilation generates no Lua source")
   assertEq(autoMatched, 6, "cached matcher remains usable")
   assertEq(forcedMatched, 6, "forced LPeg matcher remains usable")
end

function M.emitsAndRunsFixedWidthRecognitionPrograms()
   local source = [[
const Date: nupp.peg.Peg<integer> = comptime do
    return nupp.peg.compile("[0-9]^4 '-' [0-9]^2 '-' [0-9]^2 !.")
end
return Date("2026-08-10"), Date("2026/08/10"), Date:match("x2026-08-10", 2)
]]
   local code = compile(source)
   assert(code:find("fastFixed={", 1, true), code)
   assertEq(code:find("program.code", 1, true), nil, "no PEG bytecode program")
   assertEq(code:find("unknown PEG opcode", 1, true), nil, "no PEG opcode dispatcher")
   local matched, missed, offset = run(source)
   assertEq(matched, 11, "fixed-width call match")
   assertEq(missed, nil, "fixed-width byte rejection")
   assertEq(offset, 12, "fixed-width explicit start position")
end

function M.emitsAndRunsPackedPrefixScanPrograms()
   local source = [==[
const Route: nupp.peg.Peg<integer> = comptime do
    return nupp.peg.compile([[
        ('GET' / 'POST' / 'PUT' / 'PATCH' / 'DELETE') ' '
        [a-z0-9/_-]+ ' HTTP/1.' ('0' / '1') !.
    ]])
end
return Route("GET /users/42 HTTP/1.1"), Route("HEAD /users/42 HTTP/1.1"),
    Route("GET /Users/42 HTTP/1.1"), Route:match("xPOST /items HTTP/1.0", 2),
    Route:isMatch("prefix PATCH /items HTTP/1.1")
]==]
   local code = compile(source)
   assert(code:find("fastScan={", 1, true), code)
   assert(code:find("packedKeys={", 1, true), code)
   local matched, methodMiss, pathMiss, offset, searched = run(source)
   assertEq(matched, 23, "packed scan call match")
   assertEq(methodMiss, nil, "packed scan prefix rejection")
   assertEq(pathMiss, nil, "packed scan class rejection")
   assertEq(offset, 22, "packed scan explicit start position")
   assertEq(searched, true, "packed scan search")
end

function M.fallsBackForScanProgramsOutsideThePackedShape()
   local longMatched, longMissed, separatorMatched, separatorMissed = run([[
const Command: nupp.peg.Peg<integer> = comptime do
    return nupp.peg.compile("('OPTIONS' / 'CONNECT') ' ' [a-z]+ '!' !.")
end
const Label: nupp.peg.Peg<integer> = comptime do
    return nupp.peg.compile("('GET' / 'PUT') '::' [a-z]+ '!' !.")
end
return Command("OPTIONS value!"), Command("OPTION value!"),
    Label("GET::value!"), Label("GET:value!")
]])
   assertEq(longMatched, 15, "long prefix scan fallback")
   assertEq(longMissed, nil, "long prefix fallback rejection")
   assertEq(separatorMatched, 12, "multi-byte separator fallback")
   assertEq(separatorMissed, nil, "multi-byte separator rejection")
end

function M.rejectsNullableRepetition()
   local codes = errorsOf([[
const Bad: nupp.peg.Peg<integer> = comptime do
    return nupp.peg.compile("('')*")
end
]])
   assertEq(codes[1], "NUPP2417", "nullable repetition is rejected while finalizing")
end

function M.rejectsLeftRecursion()
   local codes = errorsOf([[
const Bad: nupp.peg.Peg<integer> = comptime do
    return nupp.peg.compile("value <- value / 'x'")
end
]])
   assertEq(codes[1], "NUPP2417", "left recursion is rejected")
end

function M.rejectsAMatcherResultTypeMismatch()
   local codes = errorsOf([[
const Bad: nupp.peg.Peg<integer> = comptime do
    return nupp.peg.compile("{ 'x' }")
end
]])
   assertEq(codes[1], "NUPP2415", "capture result and matcher type must agree")
end

return M
