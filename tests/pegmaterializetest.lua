local testAssert = require("nupp.test")
-- The textual PEG compiler at both phases, typed static materialization, Nupp
-- specialization templates, and native LPeg lowering.
local parser = require("nupp.compiler.syntax.parser")
local gen = require("nupp.compiler.lua.gen")
local check = require("fragment")
local envMod = require("nupp.compiler.project.env")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local env = envMod.new(HERE .. "/..")

-- What `nupp.compiler.runtime.peg` raises LPeg's backtrack limit to when it loads.
-- The limit is one process-wide value inside the C module rather than per pattern,
-- so anything that re-enters `luaopen_lpeg` has to put it back.
local MAXSTACK = 10000

-- Load LPeg's C module directly from the test rock tree so differential tests reach
-- it without going through package.loaded, which generated bootstrap code rewrites.
--
-- The handle is not a second instance: the loader caches the library, so this is the
-- same table `require` answers. What re-running `luaopen_lpeg` does do is reset the
-- backtrack limit to LPeg's 400 default, which is a limit the runtime raised once at
-- load and no later matcher raises again. Left alone, the next test in this process
-- to match deeper than 400 fails with a stack overflow, and which test that is
-- depends on how the suite happens to shard.
local function officialLpeg()
    for template in package.cpath:gmatch("[^;]+") do
        local path = template:gsub("%?", "lpeg")
        local file = io.open(path, "rb")
        if file then
            file:close()
            local opener, why = package.loadlib(path, "luaopen_lpeg")
            assert(opener, why)
            local lpeg = opener()
            lpeg.setmaxstack(MAXSTACK)

            return lpeg
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

local function compile(source)
    local parsed = parser.parse(source, "peg_materialize_test.g.nupp")
    testAssert.equal(#parsed.errors, 0, "syntax errors")
    local diagnostics = check.check(parsed, "peg_materialize_test.g.nupp", env)
    local code, generated = gen.generate(parsed, "peg_materialize_test")
    for _, diagnostic in ipairs(generated) do
        diagnostics[#diagnostics + 1] = diagnostic
    end

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
            error(("unexpected %s: %s\n---\n%s"):format(diagnostic.code, diagnostic.msg, code), 2)
        end
    end
    local chunk, why = loadstring(code, "@peg_materialize_test")
    assert(chunk, why and (why .. "\n---\n" .. code))

    return chunk(...)
end

local M = {}

function M.exposesMatcherAndSupportTypesOnTheRuntimeModule()
    local value = run(
        [[
local backend: nupp.peg.Backend = "lpeg"
local definitions: nupp.peg.Definitions = {upper = function(text: string): any return text:upper() end}
local options: nupp.peg.CompileOptions = {backend = backend, definitions = definitions}
local library = nupp.peg
local matcher: nupp.peg.Peg<any> = library.compile("[a-z]+ -> upper !.", options)
return matcher("hello")
]]
    )
    testAssert.equal(value, "HELLO", "module-level PEG types")

    local codes = errorsOf("local old: nupp.Peg.Matcher<integer> = nil as any")
    assert(#codes > 0, "the old nupp.Peg namespace must not remain public")
end

function M.matcherProtocolPreservesItsResultType()
    local value = run(
        [[
local function match<R...>(
    matcher: nupp.peg.Matcher<R...>,
    subject: string
): ((R...) | (nil))
    return matcher:match(subject)
end

local Word: nupp.peg.Peg<string> = nupp.peg.compile("{ [a-z]+ }")
local result: string? = match(Word, "hello")
return result
]]
    )
    testAssert.equal(value, "hello", "the matcher declaration chooses its result")

    local codes = errorsOf(
        [[
local function match<R...>(matcher: nupp.peg.Matcher<R...>, subject: string):
    ((R...) | (nil))
    return matcher:match(subject)
end
local Word: nupp.peg.Peg<string> = nupp.peg.compile("{ [a-z]+ }")
local wrong: integer? = match(Word, "hello")
]]
    )
    testAssert.equal(table.concat(codes, " "), "NUPP2001", "the recovered result cannot be assigned as another capture type")
end

function M.returnsMultipleCapturesAsNativeTypedResults()
    local left, right = run(
        [[
local Pair = nupp.peg.compile("{ [a-z]+ } ':' { [0-9]+ }")
local left, right = Pair("age:42")
if left == nil or right == nil then error("expected a match") end
local typedLeft: string = left
local typedRight: string = right
return typedLeft, typedRight
]]
    )
    testAssert.equal(left, "age", "first native capture")
    testAssert.equal(right, "42", "second native capture")
end

function M.multipleCapturesWorkInForcedLpegAndComptimeCodegen()
    local lpegLeft, lpegRight, staticLeft, staticRight = run(
        [[
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
]]
    )
    testAssert.equal(lpegLeft, "age", "LPeg first capture")
    testAssert.equal(lpegRight, "42", "LPeg second capture")
    testAssert.equal(staticLeft, "age", "codegen first capture")
    testAssert.equal(staticRight, "42", "codegen second capture")
end

function M.multipleCapturesFlowThroughSearchTraversalAndReplacement()
    local first, nextPosition, left, right, count, replaced = run(
        [[
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
]]
    )
    testAssert.equal(first, 2, "find first")
    testAssert.equal(nextPosition, 8, "find exclusive end")
    testAssert.equal(left, "age", "find first capture")
    testAssert.equal(right, "42", "find second capture")
    testAssert.equal(count, 2, "visited matches")
    testAssert.equal(replaced, "42age 7x", "callback replacement")
end

function M.typedActionsMayReturnSeveralNativeResults()
    local text, length, runtimeText, runtimeLength = run(
        [[
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
]]
    )
    testAssert.equal(text, "word", "action first result")
    testAssert.equal(length, 4, "action second result")
    testAssert.equal(runtimeText, "other", "runtime action first result")
    testAssert.equal(runtimeLength, 5, "runtime action second result")
end

function M.dynamicSearchDoesNotCollapseNestedCaptures()
    local first, nextPosition, outer, inner = run(
        [[
local source: string = "{ { [a-z]+ } }"
local Nested: nupp.peg.Peg<(string, string)> = nupp.peg.compile(source)
return Nested:find("!word!")
]]
    )
    testAssert.equal(first, 2, "nested capture start")
    testAssert.equal(nextPosition, 6, "nested capture end")
    testAssert.equal(outer, "word", "outer capture")
    testAssert.equal(inner, "word", "inner capture")
end

function M.keepsAStaticIdentifierOnTheSpecializedRuntime()
    local source = [[
const Identifier: nupp.peg.Peg<integer> = comptime do
    return nupp.peg.compile("[a-zA-Z_] [a-zA-Z_0-9]* !.")
end
return Identifier:match("_name9"), Identifier:match("9name"), Identifier("ok")
]]
    local matched, missed, called = run(source)
    testAssert.equal(matched, 7, "recognition returns the next byte position")
    testAssert.equal(missed, nil, "a failed match returns nil")
    testAssert.equal(called, 3, "the matcher call contract reaches the same machine")
    local code = compile(source)
    assert(code:find("(__nuppPegCodegen)({", 1, true), code)
    testAssert.equal(code:find("__nuppPegReInstall", 1, true), nil, "ordinary static PEG excludes the runtime frontend")
    assert(code:find("require(\"nupp.compiler.runtime.peg\")", 1, true), code)
    testAssert.equal(code:find("package.preload.re", 1, true), nil, "ordinary static PEG excludes the textual runtime frontend")
end

function M.searchesForMatchesWithoutBuildingAMatchResult()
    local found, skipped, negative, missing, emptySuffix, runtime, falseResult = run(
        [==[
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
]==]
    )
    testAssert.equal(found, true, "static specialized search")
    testAssert.equal(skipped, false, "search respects init")
    testAssert.equal(negative, true, "negative search position")
    testAssert.equal(missing, false, "out-of-range search")
    testAssert.equal(emptySuffix, true, "search includes the final empty position")
    testAssert.equal(runtime, true, "runtime-compiled search")
    testAssert.equal(falseResult, true, "false capture result still denotes a match")
end

function M.rejectsNonfiniteMatchPositions()
    local positive, negative, nan, fraction = run(
        [[
local Word = nupp.peg.compile("'a'")
local function rejects(value: any): boolean
    return not pcall(function()
        Word:match("a", value)
    end)
end
return rejects(math.huge), rejects(-math.huge), rejects(0 / 0), rejects(1.5)
]]
    )
    testAssert.equal(positive, true, "positive infinity is not an integer position")
    testAssert.equal(negative, true, "negative infinity is not an integer position")
    testAssert.equal(nan, true, "NaN is not an integer position")
    testAssert.equal(fraction, true, "a fractional position is not an integer position")
end

function M.findsWithPositionsAndNoMatchRecord()
    local first, nextPosition, value, recognizerFirst, recognizerNext, recognizerValue, emptyFirst, emptyNext, emptyValue, missingFirst, missingNext, missingValue, nilFirst, nilNext, nilValue = run(
        [==[
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
]==]
    )
    testAssert.equal(first, 5, "capture search first byte")
    testAssert.equal(nextPosition, 10, "capture search exclusive next byte")
    testAssert.equal(value, "hello", "capture search value")
    testAssert.equal(recognizerFirst, 5, "recognizer search first byte")
    testAssert.equal(recognizerNext, 10, "recognizer search exclusive next byte")
    testAssert.equal(recognizerValue, 10, "recognizer search result")
    testAssert.equal(emptyFirst, 4, "empty search first byte")
    testAssert.equal(emptyNext, 4, "empty search has equal positions")
    testAssert.equal(emptyValue, 4, "empty recognizer result")
    testAssert.equal(missingFirst, nil, "failed search first byte")
    testAssert.equal(missingNext, nil, "failed search next byte")
    testAssert.equal(missingValue, nil, "failed search result")
    testAssert.equal(nilFirst, 4, "nil action still reports success")
    testAssert.equal(nilNext, 5, "nil action reports its end")
    testAssert.equal(nilValue, nil, "nil action result remains nil")
end

function M.findsWithASpecializedCollectionResult()
    local first, nextPosition, values = run(
        [[
const Words = comptime do
    return nupp.peg.compile("{| { [a-z]+ } (',' { [a-z]+ })* |} !.")
end
return Words:find("invalid;one,two,three")
]]
    )
    testAssert.equal(first, 9, "collection search first byte")
    testAssert.equal(nextPosition, 22, "collection search exclusive next byte")
    testAssert.equal(table.concat(values, ":"), "one:two:three", "collection search value")
end

function M.visitsNonOverlappingMatchesWithoutIteratorObjects()
    local count, positions, values, emptyCount, emptyPositions, laterCount, dynamicCount = run(
        [==[
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
]==]
    )
    testAssert.equal(count, 3, "visitor count")
    testAssert.equal(positions, "1:4|6:9|11:16", "half-open visitor positions")
    testAssert.equal(values, "one|two|three", "typed visitor values")
    testAssert.equal(emptyCount, 3, "empty matcher visits every boundary once")
    testAssert.equal(emptyPositions, "1:1:1|2:2:2|3:3:3", "empty match progress")
    testAssert.equal(laterCount, 2, "empty iteration respects init")
    testAssert.equal(dynamicCount, 3, "runtime grammar iteration")
end

function M.generatesByteTraversalForRepeatedAtoms()
    local recognizerCount, recognizerValues, captured, fromSecond, eofCount, eofPosition, runtimeCount, lpegCount = run(
        [==[
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
]==]
    )
    testAssert.equal(recognizerCount, 3, "generated traversal count")
    testAssert.equal(recognizerValues, "1:2:2|3:6:6|7:8:8", "generated recognizer traversal values")
    testAssert.equal(captured, "1|22|333", "generated traversal capture values")
    testAssert.equal(fromSecond, 2, "generated traversal respects init")
    testAssert.equal(eofCount, 1, "EOF traversal ignores earlier failed runs")
    testAssert.equal(eofPosition, 5, "EOF traversal finds the final run")
    testAssert.equal(runtimeCount, 3, "runtime programs generate traversal")
    testAssert.equal(lpegCount, recognizerCount, "LPeg traversal retains parity")
end

function M.replacesFirstAndAllMatchesWithLiteralOrComputedText()
    local first, every, computed, unchanged, fromSecond, runtime, literalPercent, punctuation = run(
        [==[
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
]==]
    )
    testAssert.equal(first, "room #, floor 3", "first literal replacement")
    testAssert.equal(every, "room #, floor #", "all literal replacements")
    testAssert.equal(computed, "1=ONE@4, 6=TWO@9", "typed replacement callback")
    testAssert.equal(unchanged, "none", "missing match returns original text")
    testAssert.equal(fromSecond, "1 # #", "replacement respects init")
    testAssert.equal(runtime, "_-_", "runtime grammar replacement")
    testAssert.equal(literalPercent, "a%1 b%1", "replacement strings stay literal")
    testAssert.equal(punctuation, "x axb x", "literal search stays literal in generated replacement")
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
        assert(
            diagnostic.severity == "warning" or diagnostic.severity == "note",
            diagnostic.code .. ": " .. diagnostic.msg
        )
    end
    assert(code:find("Digits :__nuppPegReplaceLiteral (", 1, true), code)
    assert(code:find("Digits :__nuppPegReplaceCallback (", 1, true), code)
    assert(code:find("Digits :__nuppPegReplaceAllLiteral (", 1, true), code)
    assert(code:find("Digits :__nuppPegReplaceAllCallback (", 1, true), code)
    assert(code:find("Digits : replaceAll ( \"1 22\" , dynamic )", 1, true), code)

    local literalFirst, callbackFirst, literalAll, callbackAll, dynamicAll = run(source)
    testAssert.equal(literalFirst, "a#b", "literal replace fast path")
    testAssert.equal(callbackFirst, "a<4>b", "callback replace fast path")
    testAssert.equal(literalAll, "# #", "literal replaceAll fast path")
    testAssert.equal(callbackAll, "<2> <5>", "callback replaceAll fast path")
    testAssert.equal(dynamicAll, "! !", "union replacement retains dynamic dispatch")
end

function M.replacementMakesProgressAfterEmptyMatches()
    local first, every, later, emptySubject, endOnly = run(
        [==[
const Empty = comptime do
    return nupp.peg.compile("''", {backend = "lpeg"})
end
const End = comptime do
    return nupp.peg.compile("!.")
end
return Empty:replace("ab", "-"), Empty:replaceAll("ab", "-"),
    Empty:replaceAll("ab", "-", 2), Empty:replaceAll("", "-"),
    End:replaceAll("ab", "!")
]==]
    )
    testAssert.equal(first, "-ab", "first empty replacement inserts once")
    testAssert.equal(every, "-a-b-", "empty replacement visits every boundary")
    testAssert.equal(later, "a-b-", "empty replacement preserves prefix before init")
    testAssert.equal(emptySubject, "-", "empty subject has one boundary")
    testAssert.equal(endOnly, "ab!", "end assertion replaces final empty match")
end

function M.scansOnlyBytesThatCanBeginANonemptyMatch()
    local staticFirst, staticNext, staticValue, lpegFirst, runtimeFirst, replaced, recursiveFirst, predicateFirst, specialFirst = run(
        [==[
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
]==]
    )
    testAssert.equal(staticFirst, 10001, "static first-byte scan")
    testAssert.equal(staticNext, 10003, "static scan result end")
    testAssert.equal(staticValue, "42", "static scan capture")
    testAssert.equal(lpegFirst, staticFirst, "forced LPeg first-byte scan")
    testAssert.equal(runtimeFirst, staticFirst, "runtime first-byte scan")
    testAssert.equal(replaced, "a# b# c#", "replacement uses the shared scan")
    testAssert.equal(recursiveFirst, 4, "recursive first set")
    testAssert.equal(predicateFirst, 2, "predicate before consuming prefix")
    testAssert.equal(specialFirst, 4, "Lua-pattern punctuation is escaped")

    local code = compile(
        [==[
const Digits = comptime do
    return nupp.peg.compile("[0-9]+")
end
return Digits:isMatch("room 42")
]==]
    )
    assert(code:find("search={", 1, true), code)
end

function M.keepsSemanticallySensitiveSearchesOnTheGeneralPath()
    local emptyFirst, emptyNext, anyFirst, anyNext, positionFirst, positionNext, positionValue, possessiveFirst = run(
        [==[
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
]==]
    )
    testAssert.equal(emptyFirst, 3, "nullable search retains its requested boundary")
    testAssert.equal(emptyNext, 3, "nullable search remains empty")
    testAssert.equal(anyFirst, 2, "any-byte search retains its requested byte")
    testAssert.equal(anyNext, 3, "any-byte search consumes one byte")
    testAssert.equal(positionFirst, 3, "position capture search start")
    testAssert.equal(positionNext, 4, "position capture match end")
    testAssert.equal(positionValue, 3, "direct recognition does not replace position captures")
    testAssert.equal(possessiveFirst, nil, "Lua-pattern backtracking does not replace PEG repetition")
end

function M.typesRepeatedMatchingAndReplacementCallbacksFromTheGrammarResult()
    local codes = errorsOf(
        [==[
const Word = comptime do
    return nupp.peg.compile("{ [a-z]+ }")
end
Word:forEachMatch("hello", function(_: integer, _: integer, value: integer)
    print(value)
end)
]==]
    )
    testAssert.equal(codes[1], "NUPP2006", "visitor result type")

    codes = errorsOf(
        [==[
const Word = comptime do
    return nupp.peg.compile("{ [a-z]+ }")
end
Word:replaceAll("hello", function(_: integer, _: integer, _: string): integer
    return 1
end)
]==]
    )
    assert(#codes > 0, "replacement callback must return a string")
end

function M.infersStaticMatcherResultsFromTheCanonicalGrammarAnalysis()
    local identifier, word, words = run(
        [==[
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
]==]
    )
    testAssert.equal(identifier, 5, "inferred recognizer result")
    testAssert.equal(word, "hello", "inferred capture result")
    testAssert.equal(table.concat(words, ":"), "one:two", "inferred collection result")

    local codes = errorsOf(
        [==[
const Word = comptime do
    return nupp.peg.compile("{ [a-z]+ } !.")
end
local wrong: integer = assert(Word("hello"))
]==]
    )
    testAssert.equal(codes[1], "NUPP2001", "inferred matcher remains precise")
end

function M.requiresAFactoryBoundaryWhenStaticActionsNeedResultTypes()
    local codes, diagnostics = errorsOf(
        [==[
const Number = comptime do
    return nupp.peg.compile("%d+ -> number !.")
end
]==]
    )
    testAssert.equal(codes[1], "NUPP2414", "action inference boundary")
    assert(diagnostics[1].msg:find("declared matcher factory type", 1, true), diagnostics[1].msg)
end

function M.returnsATypedSubstringCapture()
    local value = run(
        [[
const Word: nupp.peg.Peg<string> = comptime do
    return nupp.peg.compile("{ [a-zA-Z]+ } !.")
end
return Word("Hello")
]]
    )
    testAssert.equal(value, "Hello", "substring capture")
end

function M.collectsRepeatedCapturesExplicitly()
    local values, found = run(
        [[
const Words: nupp.peg.Peg<{string}> = comptime do
    return nupp.peg.compile("{| { [a-z]+ } (',' { [a-z]+ })* |} !.")
end
return Words("one,two,three"), Words:isMatch("invalid;one,two,three")
]]
    )
    testAssert.equal(#values, 3, "collection length")
    testAssert.equal(table.concat(values, ":"), "one:two:three", "collection values")
    testAssert.equal(found, true, "specialized collection search")
end

function M.groupsRepeatedCapturesExplicitly()
    local values = run(
        [[
local matcher: nupp.peg.Peg<{string}> = comptime do
    return nupp.peg.compile("{| { [a-z]+ } (',' { [a-z]+ })* |} !.")
end
return matcher("one,two,three")
]]
    )
    testAssert.equal(table.concat(values, ":"), "one:two:three", "grouped values")
end

function M.excludesPegSupportFromUnrelatedPrograms()
    local code = compile("return 42")
    testAssert.equal(code:find("__nuppPegVM", 1, true), nil, "unused helper")
    testAssert.equal(code:find("__nuppPegCodegen", 1, true), nil, "unused code generator")
end

function M.buildsATypedMatcherFactoryForRuntimeActions()
    local result, calls = run(
        [[
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
]]
    )
    testAssert.equal(result, 1234, "action result")
    testAssert.equal(calls, 1, "one successful action")
end

function M.defersActionsUntilTheWholeMatchSucceeds()
    local value, calls = run(
        [[
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
]]
    )
    testAssert.equal(value, "ab", "winning action value")
    testAssert.equal(calls, 1, "failed alternative did not run its action")
end

function M.collectsTypedActionResults()
    local values = run(
        [[
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
]]
    )
    testAssert.equal(#values, 3, "action collection length")
    testAssert.equal(values[1] + values[2] + values[3], 60, "typed action collection")
end

function M.requiresTheExactDefinitionSlotRecord()
    local missing = errorsOf(
        [[
local record Empty end
const Build: function(Empty): nupp.peg.Peg<string> = comptime do
    return nupp.peg.compile("'x' -> text")
end
]]
    )
    testAssert.equal(missing[1], "NUPP2415", "missing action slot")

    local extra = errorsOf(
        [[
local record Actions
    text: function(value: string): string
    unused: string
end
const Build: function(Actions): nupp.peg.Peg<string> = comptime do
    return nupp.peg.compile("'x' -> text")
end
]]
    )
    testAssert.equal(extra[1], "NUPP2415", "unknown definition slot")
end

function M.matchesARecursiveGrammar()
    local source = [[
const Nested: nupp.peg.Peg<integer> = comptime do
    return nupp.peg.compile("start <- value !. value <- 'x' / '(' value ')'")
end
return Nested("(((x)))"), Nested("((x)")
]]
    local matched, missed = run(source)
    testAssert.equal(matched, 8, "recursive match")
    testAssert.equal(missed, nil, "unclosed recursion fails")
end

function M.runsDeepTailRecursiveGrammarsInLpeg()
    local matched = run(
        [[
const Nested: nupp.peg.Peg<integer> = comptime do
    return nupp.peg.compile("start <- value !. value <- 'x' / '(' value ')'", {backend = "lpeg"})
end
local depth = 2000
local subject = string.rep("(", depth) .. "x" .. string.rep(")", depth)
return Nested(subject)
]]
    )
    testAssert.equal(matched, 4002, "deep recursive match")
end

-- The same grammar, with the LPeg oracle opened first. Re-entering `luaopen_lpeg`
-- resets the backtrack limit, and the runtime raises it once at load and never
-- again, so without officialLpeg putting it back the test above passes or fails by
-- which shard it lands in rather than by anything it measures.
function M.keepsTheBacktrackLimitWhenTheOracleIsOpened()
    officialLpeg()
    local matched = run(
        [[
const Nested: nupp.peg.Peg<integer> = comptime do
    return nupp.peg.compile("start <- value !. value <- 'x' / '(' value ')'", {backend = "lpeg"})
end
local depth = 2000
local subject = string.rep("(", depth) .. "x" .. string.rep(")", depth)
return Nested(subject)
]]
    )
    testAssert.equal(matched, 4002, "deep recursive match after the oracle was opened")
end

function M.supportsPositionAnyAndOptionalPatterns()
    local empty, byte, tooLong = run(
        [[
const Located: nupp.peg.Peg<integer> = comptime do
    return nupp.peg.compile("{} .? !.")
end
return Located(""), Located("x"), Located("xy")
]]
    )
    testAssert.equal(empty, 1, "empty position")
    testAssert.equal(byte, 1, "position before optional byte")
    testAssert.equal(tooLong, nil, "optional consumes at most one byte")
end

function M.exposesOnlyTextualGrammarCompilation()
    local codes = errorsOf([[
local pattern = nupp.peg.literal("x")
]])
    testAssert.equal(codes[1], "NUPP2004", "node constructors are not public")
end

function M.supportsDifferenceAndPredicates()
    local good, keyword, digit = run(
        [[
const Name: nupp.peg.Peg<integer> = comptime do
    return nupp.peg.compile("!('if' !.) &[a-z] [a-z]+ !.")
end
return Name("item"), Name("if"), Name("7")
]]
    )
    testAssert.equal(good, 5, "predicate match")
    testAssert.equal(keyword, nil, "negative predicate")
    testAssert.equal(digit, nil, "difference")
end

function M.usesLpegExponentSemantics()
    local twice, once, thrice, capped = run(
        [[
const AtLeastTwo: nupp.peg.Peg<integer> = comptime do
    return nupp.peg.compile("'a'^+2 !.")
end
const AtMostTwo: nupp.peg.Peg<integer> = comptime do
    return nupp.peg.compile("'a'^-2 !.")
end
return AtLeastTwo("aa"), AtLeastTwo("a"), AtLeastTwo("aaa"), AtMostTwo("aa")
]]
    )
    testAssert.equal(twice, 3, "positive exponent minimum")
    testAssert.equal(once, nil, "positive exponent rejects fewer")
    testAssert.equal(thrice, 4, "positive exponent accepts more")
    testAssert.equal(capped, 3, "negative exponent maximum")
end

function M.keepsLiteralWhitespaceInsideByteClasses()
    local space, digit, letter = run(
        [[
const Class: nupp.peg.Peg<integer> = comptime do
    return nupp.peg.compile("[ %d] !.")
end
return Class(" "), Class("4"), Class("x")
]]
    )
    testAssert.equal(space, 2, "a leading class space is a member")
    testAssert.equal(digit, 2, "a predefined member remains in the class")
    testAssert.equal(letter, nil, "the class still rejects other bytes")

    local codes = errorsOf([[
const Bad: nupp.peg.Peg<integer> = comptime do
    return nupp.peg.compile("% d")
end
]])
    testAssert.equal(table.concat(codes, " "), "NUPP2417", "a predefined name starts immediately after percent")
end

function M.agreesWithLpegOnTheOverlappingFloor()
    local lpeg = officialLpeg()
    local matcher = run(
        [[
const Identifier: nupp.peg.Peg<integer> = comptime do
    return nupp.peg.compile("[a-zA-Z_] [a-zA-Z_0-9]* !.")
end
return Identifier
]]
    )
    local alpha = lpeg.R("az", "AZ") + lpeg.P("_")
    local reference = alpha * (alpha + lpeg.R("09")) ^ 0 * -lpeg.P(1)
    for _, subject in ipairs({"name", "_name9", "A0", "", "9x", "a-b"}) do
        testAssert.equal(matcher(subject), lpeg.match(reference, subject), "LPeg differential subject " .. subject)
    end
end

function M.agreesWithLpegOnMultipleResultsCmtAndBehind()
    local got = run(
        [==[
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
lpeg.setmaxstack(10000)
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
]==]
    )

    local lpeg = officialLpeg()

    local function pack(...)
        return {n = select("#", ...), ...}
    end

    local want = {}
    want.direct = pack((lpeg.C("a") * lpeg.C("b") * lpeg.Cc(nil, "tail")):match("ab"))
    want.transformed = pack(
        (lpeg.C("a") / function(value)
            return value, value:upper(), nil, "tail"
        end):match("a")
    )
    want.matchTime = pack(
        lpeg.Cmt(lpeg.C("a"), function(_, _, value)
            return true, value, value:upper(), nil, "tail"
        end):match("a")
    )
    want.rewound, want.rewindError = pcall(function()
        return lpeg.Cmt(lpeg.P("a"), function()
            return 1
        end):match("a")
    end)
    want.capturedBehind = pcall(lpeg.B, lpeg.C("a"))
    want.variableBehind = pcall(lpeg.B, lpeg.P("a") ^ 0)
    want.longBehind = pcall(lpeg.B, lpeg.P(256))
    want.unresolvedBehind = pcall(lpeg.B, lpeg.V("S"))
    want.unequalChoiceBehind = pcall(lpeg.B, lpeg.P("a") + lpeg.P("bc"))
    want.mixedUtfBehind = pcall(lpeg.B, lpeg.utfR(0x7f, 0x80))
    want.fixedBehind = (lpeg.P("a") * lpeg.B(lpeg.P("a")) * lpeg.P("b")):match("ab")
    local grammarPattern = lpeg.P({lpeg.V("S"), S = lpeg.P("a")})
    want.grammarBehind = (lpeg.P("a") * lpeg.B(grammarPattern) * lpeg.P("b")):match("ab")
    local twoByte = string.char(0xc2, 0x80)
    want.utfBehind = (lpeg.utfR(0x80, 0x7ff) * lpeg.B(lpeg.utfR(0x80, 0x7ff)) * lpeg.P("x")):match(twoByte .. "x")
    want.numericGrammar = lpeg.P({lpeg.V(2), [2] = lpeg.P("x")}):match("x")
    want.booleanGrammar = lpeg.P({lpeg.V(true), [true] = lpeg.P("x")}):match("x")
    local classes = lpeg.locale()
    want.versionType, want.version = type(lpeg.version), lpeg.version
    want.printableSpace, want.printableNewline = classes.print:match(" "), classes.print:match("\n")
    want.invalidStack = pcall(lpeg.setmaxstack, 0)
    lpeg.setmaxstack(10000)

    for _, name in ipairs({"direct", "transformed", "matchTime"}) do
        testAssert.equal(got[name].n, want[name].n, name .. " result count")
        for index = 1, want[name].n do
            testAssert.equal(got[name][index], want[name][index], name .. " result " .. index)
        end
    end
    for _, name in ipairs({
        "rewound",
        "capturedBehind",
        "variableBehind",
        "longBehind",
        "unresolvedBehind",
        "unequalChoiceBehind",
        "mixedUtfBehind",
        "fixedBehind",
        "grammarBehind",
        "utfBehind",
        "numericGrammar",
        "booleanGrammar",
        "versionType",
        "version",
        "printableSpace",
        "printableNewline",
        "invalidStack",
    }) do
        testAssert.equal(got[name], want[name], "LPeg facade " .. name)
    end
    assert(got.rewindError:find("invalid position returned by match%-time capture"), got.rewindError)
end

function M.typesFixedAndCallbackProducedLpegCaptureTuples()
    local first, second, third, literalText, transformedText, transformedNumber, runtimeText, runtimeNumber = run(
        [==[
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
]==]
    )
    testAssert.equal(first, "name", "typed first constant capture")
    testAssert.equal(second, 42, "typed second constant capture")
    testAssert.equal(third, true, "typed third constant capture")
    testAssert.equal(literalText, "word", "typed nested pattern capture")
    testAssert.equal(transformedText, "A", "typed callback text result")
    testAssert.equal(transformedNumber, 7, "typed callback integer result")
    testAssert.equal(runtimeText, "runtime", "typed runtime capture text")
    testAssert.equal(runtimeNumber, 9, "typed runtime capture integer")

    local codes = errorsOf(
        [==[
local lpeg = require("lpeg")
local first, second = lpeg.Cc("name", 42):match("")
local wrong: boolean? = second
]==]
    )
    testAssert.equal(table.concat(codes, " "), "NUPP2001", "heterogeneous captures cannot be assigned as the wrong slot type")
end

function M.matchesLpegConstructionUtfAndRepresentationSemantics()
    local got = run(
        [==[
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
lpeg.setmaxstack(10000)
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
]==]
    )
    testAssert.equal(got.luaType, "userdata", "patterns are opaque userdata")
    testAssert.equal(got.lpegType, "pattern", "lpeg.type recognizes facade userdata")
    testAssert.equal(got.tostringPrefix, true, "pattern reflection matches LPeg's shape")
    testAssert.equal(got.mutable, false, "pattern state cannot be mutated")
    testAssert.equal(got.selfField, nil, "LPeg does not expose a nonstandard self field")
    testAssert.equal(got.emptyLoop, false, "empty repetition fails during construction")
    testAssert.equal(got.captureLoop, false, "capture-only repetition fails during construction")
    testAssert.equal(got.undefined, false, "undefined rules fail during construction")
    testAssert.equal(got.left, false, "left recursion fails during construction")
    testAssert.equal(got.right, true, "right recursion remains valid")
    testAssert.equal(got.missingLookup, 8, "a missing query capture produces zero values")
    testAssert.equal(got.overlong, nil, "utfR rejects overlong UTF-8")
    testAssert.equal(got.tooLarge, nil, "utfR rejects code points above Unicode")
    testAssert.equal(got.surrogate, 4, "utfR retains LPeg's code-point range semantics")
    testAssert.equal(got.invalidLow, false, "utfR rejects a negative lower bound")
    testAssert.equal(got.invalidHigh, false, "utfR rejects a bound above Unicode")
    testAssert.equal(got.invalidOrder, false, "utfR rejects an inverted range")
    testAssert.equal(got.flat, 5, "flat AST depth does not consume backtrack stack")
    testAssert.equal(got.overflow, true, "LPeg optimizes tail-recursive grammar calls")
end

function M.bundlesTheReferenceReModuleOverTheLpegFacade()
    local captured, first, last, replaced, patternType = run(
        [==[
local re = require("re")
local pattern = re.compile("{[a-z]+} ':' {[0-9]+} !.")
local captured = {pattern:match("item:42")}
local first, last = re.find("-- item:42 --", "[a-z]+ ':' [0-9]+")
return captured, first, last, re.gsub("a1b22", "[0-9]+", "#"), type(pattern)
]==]
    )
    testAssert.equal(captured[1], "item", "bundled re first capture")
    testAssert.equal(captured[2], "42", "bundled re second capture")
    testAssert.equal(first, 4, "bundled re find start")
    testAssert.equal(last, 10, "bundled re find inclusive end")
    testAssert.equal(replaced, "a#b#", "bundled re global substitution")
    testAssert.equal(patternType, "userdata", "re compiles to the same opaque pattern")
end

function M.agreesWithLpegReOnTheCaptureSurface()
    local lpeg = officialLpeg()
    local re = officialRe(lpeg)
    local same, fields, substitution, selected, formatted, upper, matchTime, fold, accumulate, external, externalClass, multiple, nestedCapture = run(
        [==[
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
]==]
    )

    local sameOracle = re.compile("{:word: { [a-z]+ } :} '=' =word !.")
    for _, subject in ipairs({"abc=abc", "abc=abd", "x=x"}) do
        testAssert.equal(same(subject), sameOracle:match(subject), "named back capture oracle for " .. subject)
    end

    local fieldsOracle = re.compile("{| {:name: { [a-z]+ } :} ':' { [0-9]+ } |} !.")
    local gotFields, wantFields = fields("age:42"), fieldsOracle:match("age:42")
    testAssert.equal(gotFields.name, wantFields.name, "named table field oracle")
    testAssert.equal(gotFields[1], wantFields[1], "positional table field oracle")

    local cases = {
        {substitution, re.compile("{~ (({ [0-9]+ } -> '#') / .)* ~} !."), "a12b"},
        {selected, re.compile("({.} {.}) -> 2 !."), "xy"},
        {formatted, re.compile("({.} {.}) -> '%2%1' !."), "xy"},
        {
            upper,
            re.compile(
                "{[a-z]+} -> upper !.",
                {
                    upper = function(value)
                        return value:upper()
                    end,
                }
            ),
            "hello"
        },
        {
            matchTime,
            re.compile("{[a-z]+} => accept !.", {
                accept = function(_, position, value)
                    return position, value .. "!"
                end,
            }),
            "hello"
        },
        {
            fold,
            re.compile("({[0-9]} {[0-9]}*) ~> sum !.", {
                sum = function(left, right)
                    return tonumber(left) + tonumber(right)
                end,
            }),
            "123"
        },
        {
            accumulate,
            re.compile("{[0-9]} ({[0-9]} >> sum)* !.", {
                sum = function(left, right)
                    return tonumber(left) + tonumber(right)
                end,
            }),
            "123"
        },
        {
            external,
            re.compile("%token !.", {
                token = "ok"
            }),
            "ok"
        },
        {externalClass, re.compile("[%token] !.", {token = "ok"}), "ok"},
    }
    for index, case in ipairs(cases) do
        testAssert.equal(case[1](case[3]), case[2]:match(case[3]), "LPeg re capture oracle case " .. index)
    end
    local gotMultiple = multiple("hi")
    local wantMultiple = re.compile("{| {[a-z]+} -> both |} !.", {
        both = function(value)
            return value, value:upper()
        end,
    }):match("hi")
    testAssert.equal(gotMultiple[1], wantMultiple[1], "first transformed capture")
    testAssert.equal(gotMultiple[2], wantMultiple[2], "second transformed capture")
    local gotNested = nestedCapture("a")
    local wantNested = re.compile("{| { {'a'} } |} !."):match("a")
    testAssert.equal(gotNested[1], wantNested[1], "outer substring capture")
    testAssert.equal(gotNested[2], wantNested[2], "nested substring capture")
end

function M.searchesGeneralRecognitionProgramsWithoutLosingTheirEndPosition()
    local first, nextPosition, value = run(
        [[
local Suppressed = nupp.peg.compile("({.}) -> 0")
return Suppressed:find("x")
]]
    )
    testAssert.equal(first, 1, "general recognizer first position")
    testAssert.equal(nextPosition, 2, "general recognizer exclusive end")
    testAssert.equal(value, 2, "general recognizer result")
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
    testAssert.equal(matched, 7, "re notation static match")
    testAssert.equal(badHead, nil, "re notation static head rejection")
    testAssert.equal(badTail, nil, "re notation static eof rejection")
    local code = compile(source)
    assert(code:find("(__nuppPegCodegen)({", 1, true), code)
    testAssert.equal(code:find("__nuppPegReInstall", 1, true), nil, "static re grammar excludes the runtime frontend")
end

function M.compilesTheSameReNotationAtRuntime()
    local static, dynamic = run(
        [==[
const Static: nupp.peg.Peg<integer> = comptime do
    return nupp.peg.compile([[
        ('GET' / 'POST') ' ' [a-z/0-9]+ !.
    ]])
end
local grammar: string = "('GET' / 'POST') ' ' [a-z/0-9]+ !."
local Dynamic = nupp.peg.compile(grammar)
return Static, Dynamic
]==]
    )
    for _, subject in ipairs({"GET /users/42", "POST /items", "PUT /items", "GET /Users"}) do
        testAssert.equal(dynamic(subject), static(subject), "static/runtime re parity for " .. subject)
    end
end

function M.reusesOneMatcherShellAcrossRuntimeBackends()
    local staticResult, dynamicResult, lpegResult, sameTemplate, sameLpegShell = run(
        [==[
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
]==]
    )
    testAssert.equal(dynamicResult, staticResult, "runtime specialization result")
    testAssert.equal(lpegResult, staticResult, "forced LPeg result")
    testAssert.equal(sameTemplate, true, "static and runtime use the same matcher template")
    testAssert.equal(sameLpegShell, true, "kernels and LPeg share one matcher shell")
end

function M.supportsRuntimeReCapturesCollectionsAndActions()
    local words, number = run(
        [==[
local words = nupp.peg.compile("{| { [a-z]+ } (',' { [a-z]+ })* |} !.")
local number = nupp.peg.compile("%d+ -> number !.", {
    definitions = {
        number = function(text: string): any
            return tonumber(text)
        end,
    },
})
return words("one,two,three"), number("1234")
]==]
    )
    testAssert.equal(table.concat(words, ":"), "one:two:three", "runtime re collection")
    testAssert.equal(number, 1234, "runtime re action")
end

function M.infersLiteralRuntimeMatcherAndActionResults()
    local word, constWord, words, number = run(
        [==[
local Word = nupp.peg.compile("{ [a-z]+ } !.")
const WordGrammar = "{ [a-z]+ } !."
local ConstWord = nupp.peg.compile(WordGrammar)
local Words = nupp.peg.compile("{| { [a-z]+ } (',' { [a-z]+ })* |} !.")
local Number = nupp.peg.compile("%d+ -> number !.", {
    definitions = {
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
]==]
    )
    testAssert.equal(word, "hello", "literal runtime capture result")
    testAssert.equal(constWord, "hello", "const runtime capture result")
    testAssert.equal(table.concat(words, ":"), "one:two", "literal runtime collection result")
    testAssert.equal(number, 42, "literal runtime action result")
end

function M.supportsRuntimeRecursiveReGrammars()
    local staticMatched, dynamicMatched, staticMissed, dynamicMissed = run(
        [==[
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
]==]
    )
    testAssert.equal(staticMatched, 8, "static recursive re match")
    testAssert.equal(dynamicMatched, staticMatched, "recursive re phase parity")
    testAssert.equal(staticMissed, nil, "static recursive re rejection")
    testAssert.equal(dynamicMissed, staticMissed, "recursive re rejection parity")
end

function M.rejectsUnsafeRuntimeReGrammars()
    local nullable, leftRecursive, undefined = run(
        [==[
local function rejected(source: string): boolean
    return not pcall(function()
        nupp.peg.compile(source)
    end)
end
return rejected("('')*"), rejected("value <- value / 'x'"), rejected("value <- missing")
]==]
    )
    testAssert.equal(nullable, true, "runtime nullable repetition rejection")
    testAssert.equal(leftRecursive, true, "runtime left recursion rejection")
    testAssert.equal(undefined, true, "runtime undefined rule rejection")
end

function M.reportsReSyntaxLocationsAtBothPhases()
    local codes, diagnostics = errorsOf(
        [==[
const Broken: nupp.peg.Peg<integer> = comptime do
    return nupp.peg.compile([[
        'ok'
        [
    ]])
end
]==]
    )
    testAssert.equal(codes[1], "NUPP2417", "static re diagnostic code")
    assert(diagnostics[1].msg:find("line 2, column", 1, true), diagnostics[1].msg)

    local ok, why = run(
        [==[
local ok, why = pcall(function()
    nupp.peg.compile("'ok'\n[")
end)
return ok, tostring(why)
]==]
    )
    testAssert.equal(ok, false, "runtime re syntax rejection")
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
        testAssert.equal(fastIdentifier(input), refIdentifier(input), "identifier backend parity for " .. input)
        local fast, ref = fastList(input), refList(input)
        testAssert.equal(fast and table.concat(fast, ":"), ref and table.concat(ref, ":"), "list backend parity for " .. input)
    end
end

function M.cachesRuntimeLpegPatternsWithoutGeneratingSource()
    local afterFirst, afterCached, afterForced, autoMatched, forcedMatched = run(
        [==[
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
]==]
    )
    testAssert.equal(afterFirst, 0, "runtime LPeg compilation generates no Lua source")
    testAssert.equal(afterCached, afterFirst, "runtime code generation is cached")
    testAssert.equal(afterForced, afterCached, "forced LPeg compilation generates no Lua source")
    testAssert.equal(autoMatched, 6, "cached matcher remains usable")
    testAssert.equal(forcedMatched, 6, "forced LPeg matcher remains usable")
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
    testAssert.equal(code:find("program.code", 1, true), nil, "no PEG bytecode program")
    testAssert.equal(code:find("unknown PEG opcode", 1, true), nil, "no PEG opcode dispatcher")
    local matched, missed, offset = run(source)
    testAssert.equal(matched, 11, "fixed-width call match")
    testAssert.equal(missed, nil, "fixed-width byte rejection")
    testAssert.equal(offset, 12, "fixed-width explicit start position")
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
    testAssert.equal(matched, 23, "packed scan call match")
    testAssert.equal(methodMiss, nil, "packed scan prefix rejection")
    testAssert.equal(pathMiss, nil, "packed scan class rejection")
    testAssert.equal(offset, 22, "packed scan explicit start position")
    testAssert.equal(searched, true, "packed scan search")
end

function M.fallsBackForScanProgramsOutsideThePackedShape()
    local longMatched, longMissed, separatorMatched, separatorMissed = run(
        [[
const Command: nupp.peg.Peg<integer> = comptime do
    return nupp.peg.compile("('OPTIONS' / 'CONNECT') ' ' [a-z]+ '!' !.")
end
const Label: nupp.peg.Peg<integer> = comptime do
    return nupp.peg.compile("('GET' / 'PUT') '::' [a-z]+ '!' !.")
end
return Command("OPTIONS value!"), Command("OPTION value!"),
    Label("GET::value!"), Label("GET:value!")
]]
    )
    testAssert.equal(longMatched, 15, "long prefix scan fallback")
    testAssert.equal(longMissed, nil, "long prefix fallback rejection")
    testAssert.equal(separatorMatched, 12, "multi-byte separator fallback")
    testAssert.equal(separatorMissed, nil, "multi-byte separator rejection")
end

function M.rejectsNullableRepetition()
    local codes = errorsOf([[
const Bad: nupp.peg.Peg<integer> = comptime do
    return nupp.peg.compile("('')*")
end
]])
    testAssert.equal(codes[1], "NUPP2417", "nullable repetition is rejected while finalizing")
end

function M.rejectsLeftRecursion()
    local codes = errorsOf(
        [[
const Bad: nupp.peg.Peg<integer> = comptime do
    return nupp.peg.compile("value <- value / 'x'")
end
]]
    )
    testAssert.equal(codes[1], "NUPP2417", "left recursion is rejected")
end

function M.reportsUnwrappedRepetitionInsideChoiceAndRules()
    local codes = errorsOf([[
const Bad = comptime do
    return nupp.peg.compile("{'a'}* / 'b'")
end
]])
    testAssert.equal(codes[1], "NUPP2417", "a choice alternative reports its unwrapped repetition")
    local ruleCodes = errorsOf([[
const Bad = comptime do
    return nupp.peg.compile("S <- A 'x'  A <- {'a'}*")
end
]])
    testAssert.equal(ruleCodes[1], "NUPP2417", "a rule reference reports its unwrapped repetition")
end

function M.keepsGreedyScansOffThePackedPrefixKernel()
    local source = [==[
const Fast: nupp.peg.Peg<integer> = comptime do
    return nupp.peg.compile("('a' / 'b') '=' [a-z]* 'abcdefghi' !.")
end
const Native: nupp.peg.Peg<integer> = comptime do
    return nupp.peg.compile("('a' / 'b') '=' [a-z]* 'abcdefghi' !.", {backend = "lpeg"})
end
return Fast("a=abcdefghi"), Native("a=abcdefghi"), Fast("a=-abcdefghi"), Native("a=-abcdefghi")
]==]
    local code = compile(source)
    testAssert.equal(code:find("fastScan={", 1, true), nil, "a suffix the scan class accepts is not specialized")
    local fast, native, fastMiss, nativeMiss = run(source)
    testAssert.equal(fast, native, "greedy repetition agrees with LPeg")
    testAssert.equal(fast, nil, "the greedy scan swallows the suffix")
    testAssert.equal(fastMiss, nativeMiss, "a rejected byte agrees with LPeg")
end

function M.typesNestedCollectsAsNestedArrays()
    local outer, first, second, third = run(
        [==[
const Rows: nupp.peg.Peg<{{string}}> = comptime do
    return nupp.peg.compile("{| {| { [a-z]+ } (',' { [a-z]+ })* |} (';' {| { [a-z]+ } (',' { [a-z]+ })* |})* |} !.")
end
const Inferred = comptime do
    return nupp.peg.compile("{| {| { [a-z]+ } |} |} !.", {backend = "lpeg"})
end
local rows = assert(Rows("a,b;c"))
local inner: {{string}} = assert(Inferred("x"))
return #rows, rows[1][1], rows[1][2], rows[2][1] .. inner[1][1]
]==]
    )
    testAssert.equal(outer, 2, "outer collect length")
    testAssert.equal(first, "a", "first inner capture")
    testAssert.equal(second, "b", "second inner capture")
    testAssert.equal(third, "cx", "nested captures under both backends")
    local codes = errorsOf(
        [[
const Bad: nupp.peg.Peg<{string}> = comptime do
    return nupp.peg.compile("{| {| { [a-z]+ } |} |} !.")
end
]]
    )
    testAssert.equal(codes[1], "NUPP2415", "a flattened declaration does not fit a nested collect")
end

function M.rejectsAComptimeMatcherDeclaredAsAnotherType()
    local codes, diagnostics = errorsOf([[
const Wrong: string = comptime do
    return nupp.peg.compile("'a'")
end
]])
    testAssert.equal(codes[1], "NUPP2415", "a non-matcher declaration is rejected")
    assert(diagnostics[1].msg:find("nupp.peg.Peg", 1, true), diagnostics[1].msg)
end

function M.rejectsAMatcherResultTypeMismatch()
    local codes = errorsOf([[
const Bad: nupp.peg.Peg<integer> = comptime do
    return nupp.peg.compile("{ 'x' }")
end
]])
    testAssert.equal(codes[1], "NUPP2415", "capture result and matcher type must agree")
end

return M
