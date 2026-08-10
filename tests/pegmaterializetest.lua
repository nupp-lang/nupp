-- The textual PEG compiler at both phases, typed static materialization, shared
-- specialization templates, and the pure-Lua bytecode VM fallback.
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

function M.exposesMatcherAndSupportTypesOnTheRuntimeModule()
   local value = run([[
local backend: nupp.peg.Backend = "vm"
local action: nupp.peg.Action = function(text: string): any return text:upper() end
local actions: nupp.peg.Actions = {upper = action}
local options: nupp.peg.CompileOptions = {backend = backend, actions = actions}
local library = nupp.peg
local matcher: nupp.peg.Peg<any> = library.compile("[a-z]+ => upper !.", options)
return matcher("hello")
]])
   assertEq(value, "HELLO", "module-level PEG types")

   local codes = errorsOf("local old: nupp.Peg.Matcher<integer> = nil as any")
   assert(#codes > 0, "the old nupp.Peg namespace must not remain public")
end

function M.matchesAStaticIdentifierWithoutLPegAtRuntime()
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
   assert(code:find("__nuppPegSpecialized", 1, true), code)
   assertEq(code:find("__nuppPegReInstall", 1, true), nil,
      "ordinary static PEG excludes the runtime frontend")
   assert(not code:find("require(\"lpeg\")", 1, true), code)
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
   local values = run([[
const Words: nupp.peg.Peg<{string}> = comptime do
    return nupp.peg.compile("{| { [a-z]+ } (',' { [a-z]+ })* |} !.")
end
return Words("one,two,three")
]])
   assertEq(#values, 3, "collection length")
   assertEq(table.concat(values, ":"), "one:two:three", "collection values")
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

function M.excludesThePegVMFromUnrelatedPrograms()
   local code = compile("return 42")
   assertEq(code:find("__nuppPegVM", 1, true), nil, "unused helper")
end

function M.buildsATypedMatcherFactoryForRuntimeActions()
   local result, calls = run([[
local record NumberActions
    number: function(text: string): integer
end

const Number: function(NumberActions): nupp.peg.Peg<integer> = comptime do
    return nupp.peg.compile("[0-9]+ => number !.")
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
const Build: function(Actions): nupp.peg.Peg<string> = comptime do
    return nupp.peg.compile("(('a' => text) 'z' / ('ab' => text)) !.")
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

const Build: function(Actions): nupp.peg.Peg<{integer}> = comptime do
    return nupp.peg.compile("{| ([0-9]+ => number) (',' ([0-9]+ => number))* |} !.")
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
const Build: function(Empty): nupp.peg.Peg<string> = comptime do
    return nupp.peg.compile("'x' => text")
end
]])
   assertEq(missing[1], "NUPP2415", "missing action slot")

   local wrong = errorsOf([[
local record Actions
    text: function(value: integer): string
end
const Build: function(Actions): nupp.peg.Peg<string> = comptime do
    return nupp.peg.compile("'x' => text")
end
]])
   assertEq(wrong[1], "NUPP2415", "wrong action signature")
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

function M.runsDeepGrammarRecursionOnTheExplicitVMStack()
   local matched = run([[
const Nested: nupp.peg.Peg<integer> = comptime do
    return nupp.peg.compile("start <- value !. value <- 'x' / '(' value ')'", {backend = "vm"})
end
local depth = 2000
local subject = string.rep("(", depth) .. "x" .. string.rep(")", depth)
return Nested(subject)
]])
   assertEq(matched, 4002, "deep recursive match")
end

function M.supportsPositionAnyAndOptionalOpcodes()
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
   local lpeg = require("lpeg")
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
   assert(code:find("__nuppPegSpecialized", 1, true), code)
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

function M.reusesTheStaticMatcherTemplateAtRuntime()
   local staticResult, dynamicResult, vmResult, sameTemplate, vmDiffers = run([==[
const Static: nupp.peg.Peg<integer> = comptime do
    return nupp.peg.compile("[a-zA-Z_] [a-zA-Z_0-9]* !.")
end
local grammar: string = "[a-zA-Z_] [a-zA-Z_0-9]* !."
local Dynamic = nupp.peg.compile(grammar)
local VM = nupp.peg.compile(grammar, {backend = "vm"})
local staticCode = string.dump((getmetatable(Static) as any).__call)
local dynamicCode = string.dump((getmetatable(Dynamic) as any).__call)
local vmCode = string.dump((getmetatable(VM) as any).__call)
return Static("name9"), Dynamic("name9"), VM("name9"),
    staticCode == dynamicCode, dynamicCode ~= vmCode
]==])
   assertEq(dynamicResult, staticResult, "runtime specialization result")
   assertEq(vmResult, staticResult, "forced VM result")
   assertEq(sameTemplate, true, "static and runtime use the same matcher template")
   assertEq(vmDiffers, true, "the VM option bypasses the specialized template")
end

function M.supportsRuntimeReCapturesCollectionsAndActions()
   local words, number = run([==[
local words = nupp.peg.compile("{| { [a-z]+ } (',' { [a-z]+ })* |} !.")
local number = nupp.peg.compile("%d+ => number !.", {
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
        [z-a]
    ]])
end
]==])
   assertEq(codes[1], "NUPP2417", "static re diagnostic code")
   assert(diagnostics[1].msg:find("line 2, column", 1, true), diagnostics[1].msg)

   local ok, why = run([==[
local ok, why = pcall(function()
    nupp.peg.compile("'ok'\n[z-a]")
end)
return ok, tostring(why)
]==])
   assertEq(ok, false, "runtime re syntax rejection")
   assert(why:find("line 2, column", 1, true), why)
end

function M.agreesBetweenSpecializedAndGeneralBackends()
   local source = [[
const FastIdentifier: nupp.peg.Peg<integer> = comptime do
    return nupp.peg.compile("[a-zA-Z_] [a-zA-Z_0-9]* !.")
end
const RefIdentifier: nupp.peg.Peg<integer> = comptime do
    return nupp.peg.compile("[a-zA-Z_] [a-zA-Z_0-9]* !.", {backend = "vm"})
end
const FastList: nupp.peg.Peg<{string}> = comptime do
    return nupp.peg.compile("{| { [a-z]+ } (',' { [a-z]+ })* |} !.")
end
const RefList: nupp.peg.Peg<{string}> = comptime do
    return nupp.peg.compile("{| { [a-z]+ } (',' { [a-z]+ })* |} !.", {backend = "vm"})
end
return FastIdentifier, RefIdentifier, FastList, RefList
]]
   local code = compile(source)
   assert(code:find("__nuppPegSpecialized", 1, true), code)
   assert(code:find("__nuppPegVM", 1, true), code)
   local fastIdentifier, refIdentifier, fastList, refList = run(source)
   local inputs = {"", "a", "_ok9", "9bad", "alpha,beta", "one,two,three", "one,", ",two"}
   for _, input in ipairs(inputs) do
      assertEq(fastIdentifier(input), refIdentifier(input), "identifier backend parity for " .. input)
      local fast, ref = fastList(input), refList(input)
      assertEq(fast and table.concat(fast, ":"), ref and table.concat(ref, ":"),
         "list backend parity for " .. input)
   end
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
    Route("GET /Users/42 HTTP/1.1"), Route:match("xPOST /items HTTP/1.0", 2)
]==]
   local code = compile(source)
   assert(code:find("fastScan={", 1, true), code)
   assert(code:find("packedKeys={", 1, true), code)
   local matched, methodMiss, pathMiss, offset = run(source)
   assertEq(matched, 23, "packed scan call match")
   assertEq(methodMiss, nil, "packed scan prefix rejection")
   assertEq(pathMiss, nil, "packed scan class rejection")
   assertEq(offset, 22, "packed scan explicit start position")
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
