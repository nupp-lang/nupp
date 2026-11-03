local testAssert = require("assert")
-- Typed LPeg captures and the bundled third-party re module.
local parser = require("nupp.compiler.syntax.parser")
local gen = require("nupp.compiler.lua.gen")
local check = require("helpers.fragment")
local envMod = require("nupp.compiler.project.env")

local HERE = require("helpers.paths").tests
local env = envMod.new(HERE .. "/..")
local MAXSTACK = 10000

-- Open the test rock directly so generated preload entries cannot replace the oracle.
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
    local parsed = parser.parse(source, "lpeg_test.nupp")
    testAssert.eq(#parsed.errors, 0, "syntax errors")
    local diagnostics = check.check(parsed, "lpeg_test.nupp", env)
    local code, generated = gen.generate(parsed, "lpeg_test")
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
    local chunk, why = loadstring(code, "@lpeg_test")
    assert(chunk, why and (why .. "\n---\n" .. code))

    return chunk(...)
end

local M = {}

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
} as unknown
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
        testAssert.eq(got[name].n, want[name].n, name .. " result count")
        for index = 1, want[name].n do
            testAssert.eq(got[name][index], want[name][index], name .. " result " .. index)
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
        testAssert.eq(got[name], want[name], "LPeg facade " .. name)
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
    testAssert.eq(first, "name", "typed first constant capture")
    testAssert.eq(second, 42, "typed second constant capture")
    testAssert.eq(third, true, "typed third constant capture")
    testAssert.eq(literalText, "word", "typed nested pattern capture")
    testAssert.eq(transformedText, "A", "typed callback text result")
    testAssert.eq(transformedNumber, 7, "typed callback integer result")
    testAssert.eq(runtimeText, "runtime", "typed runtime capture text")
    testAssert.eq(runtimeNumber, 9, "typed runtime capture integer")

    local codes = errorsOf(
        [==[
local lpeg = require("lpeg")
local first, second = lpeg.Cc("name", 42):match("")
local wrong: boolean? = second
]==]
    )
    testAssert.eq(
        table.concat(codes, " "),
        "NUPP2001",
        "heterogeneous captures cannot be assigned as the wrong slot type"
    )
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
} as unknown
]==]
    )
    testAssert.eq(got.luaType, "userdata", "patterns are opaque userdata")
    testAssert.eq(got.lpegType, "pattern", "lpeg.type recognizes facade userdata")
    testAssert.eq(got.tostringPrefix, true, "pattern reflection matches LPeg's shape")
    testAssert.eq(got.mutable, false, "pattern state cannot be mutated")
    testAssert.eq(got.selfField, nil, "LPeg does not expose a nonstandard self field")
    testAssert.eq(got.emptyLoop, false, "empty repetition fails during construction")
    testAssert.eq(got.captureLoop, false, "capture-only repetition fails during construction")
    testAssert.eq(got.undefined, false, "undefined rules fail during construction")
    testAssert.eq(got.left, false, "left recursion fails during construction")
    testAssert.eq(got.right, true, "right recursion remains valid")
    testAssert.eq(got.missingLookup, 8, "a missing query capture produces zero values")
    testAssert.eq(got.overlong, nil, "utfR rejects overlong UTF-8")
    testAssert.eq(got.tooLarge, nil, "utfR rejects code points above Unicode")
    testAssert.eq(got.surrogate, 4, "utfR retains LPeg's code-point range semantics")
    testAssert.eq(got.invalidLow, false, "utfR rejects a negative lower bound")
    testAssert.eq(got.invalidHigh, false, "utfR rejects a bound above Unicode")
    testAssert.eq(got.invalidOrder, false, "utfR rejects an inverted range")
    testAssert.eq(got.flat, 5, "flat AST depth does not consume backtrack stack")
    testAssert.eq(got.overflow, true, "LPeg optimizes tail-recursive grammar calls")
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
    testAssert.eq(captured[1], "item", "bundled re first capture")
    testAssert.eq(captured[2], "42", "bundled re second capture")
    testAssert.eq(first, 4, "bundled re find start")
    testAssert.eq(last, 10, "bundled re find inclusive end")
    testAssert.eq(replaced, "a#b#", "bundled re global substitution")
    testAssert.eq(patternType, "userdata", "re compiles to the same opaque pattern")
end

return M
