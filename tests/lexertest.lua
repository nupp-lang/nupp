local testAssert = require("nupp.test")
local lexer = require("nupp.compiler.syntax.lexer")

local function kindsOf(src)
    local tokens = select(1, lexer.lex(src))
    local out = {}
    for _, t in ipairs(tokens) do
        if t.kind ~= "eof" then
            out[#out + 1] = t.kind
        end
    end

    return table.concat(out, " ")
end

local function assertRoundtrip(src)
    local tokens = select(1, lexer.lex(src))
    testAssert.equal(lexer.textOf(tokens), src, "round-trip failed for " .. ("%q"):format(src))
end

local CORPUS = {
    "",
    "   \n\t \n",
    "local x = 1 + 2  -- comment\n",
    "--[[ long\ncomment ]] return 1\n",
    "--[==[ nested ]] ]==]--tail",
    "#!/usr/bin/env luajit\nprint('hi')\n",
    "\239\187\191local bom = true",
    'local s = "a\\"b\\\\" .. \'c\'',
    "local long = [[raw\nlines]] .. [=[with ]] inside]=]",
    "if a ~= b and c ~= d then return not e end",
    "local f = |a, b| -> a + b",
    "local g = x -> x * 2",
    "local s = `sum: ${1 + 2} done`",
    "local t = `nested ${ {a = 1}.a } braces`",
    "local u = `deep ${`inner ${x}`} nesting`",
    "local plain = `no interpolation`",
    "local multi = `line one\nline ${x}\nthree`",
    "local bad = `unterminated ${expr",
    "local v = cond ? left : right",
    "local n = t?.field?.other",
    "goto done ::done::",
    "local h = 0xFFULL + 10LL + 3i + 0x1p4 + 12.5e-3 + .5",
    "y = a & b | c ~ d << 2 >> 3 ~>> 4",
    "q = a // b / c",
    "f(...)",
    "local bad = 'unterminated",
    "--[[ never closed",
    "weird @ $ chars",
}

local M = {}

function M.triviaArenaProvidersShareOneContract()
    local providers = {
        require("nupp.compiler.syntax.triviaarena.ffi"),
        require("nupp.compiler.syntax.triviaarena.table"),
    }
    for _, provider in ipairs(providers) do
        local arena = provider.new("  -- note\nvalue")
        testAssert.equal(arena.count, 0, "a new arena is empty")
        testAssert.equal(arena:append(1, 1, 2, 1, 1), 1, "the first record index")
        for index = 2, 80 do
            testAssert.equal(
                arena:append(index % 4 + 1, index, index + 1, index + 2, index + 3),
                index,
                "append grows the arena"
            )
        end
        local kind, offset, length, line, col = arena:record(65)
        testAssert.equal(kind, 2, "record kind")
        testAssert.equal(offset, 65, "record offset")
        testAssert.equal(length, 66, "record length")
        testAssert.equal(line, 67, "record line")
        testAssert.equal(col, 68, "record column")
        testAssert.equal(arena.source, "  -- note\nvalue", "the source is retained")
        -- An out-of-range index is refused, not answered from memory the record
        -- never reached: past `count` the ffi block holds zeroes that pass for a
        -- record, and before it lies foreign memory.
        for _, index in ipairs({0, -1, 81}) do
            local ok, err = pcall(function()
                return arena:record(index)
            end)
            testAssert.equal(ok, false, "record " .. index .. " must be refused")
            testAssert.equal(
                tostring(err):match("outside 1%.%.80") ~= nil,
                true,
                "record " .. index .. " names the range: " .. tostring(err)
            )
        end
    end
end

function M.roundtripCorpus()
    for _, src in ipairs(CORPUS) do
        assertRoundtrip(src)
    end
end

function M.basicKinds()
    testAssert.equal(kindsOf("local x = 1 + 2"), "local name = number + number")
    testAssert.equal(kindsOf('return "s" .. [[l]]'), "return string .. string")
    testAssert.equal(kindsOf("const x = 1"), "name name = number", "const must remain a soft keyword")
    testAssert.equal(kindsOf("local sealed interface Token end"), "local name name name end", "sealed is a soft keyword")
end

function M.luajit3Operators()
    testAssert.equal(kindsOf("a ~>> 2"), "name ~>> number")
    testAssert.equal(kindsOf("a >> b << c"), "name >> name << name")
    testAssert.equal(kindsOf("t?.x"), "name ?. name")
    testAssert.equal(kindsOf("a ? b : c"), "name ? name : name")
    testAssert.equal(kindsOf("a // b"), "name // name")
    testAssert.equal(kindsOf("::top::"), ":: name ::")
    testAssert.equal(kindsOf("|a| -> a"), "| name | -> name")
end

function M.customaryOperators()
    -- A customary form lexes as its classic operator, so nothing
    -- downstream has to know both forms.
    testAssert.equal(kindsOf("!a"), "not name")
    testAssert.equal(kindsOf("a && b"), "name and name")
    testAssert.equal(kindsOf("a || b"), "name or name")
    testAssert.equal(kindsOf("a != b"), "name ~= name")
    -- The bytes that were written survive for the round trip and the formatter.
    local tokens = lexer.lex("a && b")
    testAssert.equal(tokens[2].text, "&&")
    testAssert.equal(lexer.textOf(tokens), "a && b")
    -- Longest match keeps the one-character forms apart from the two-character ones.
    testAssert.equal(kindsOf("a & b"), "name & name")
    testAssert.equal(kindsOf("a | b"), "name | name")
end

function M.byteBoundariesPreserveTriviaAndPositions()
    local bom = "\239\187\191"
    local tokens = lexer.lex(bom .. "local value")
    testAssert.equal(lexer.triviaKind(tokens[1], 1), "bom")
    testAssert.equal(lexer.triviaText(tokens[1], 1), bom)
    testAssert.equal(tokens[1].offset, 4)
    testAssert.equal(tokens[1].line, 1)
    testAssert.equal(tokens[1].col, 4)

    tokens = lexer.lex("#!/usr/bin/env nupp\r\nlocal value")
    testAssert.equal(lexer.triviaKind(tokens[1], 1), "hashbang")
    testAssert.equal(lexer.triviaText(tokens[1], 1), "#!/usr/bin/env nupp\r\n")
    testAssert.equal(tokens[1].offset, 22)
    testAssert.equal(tokens[1].line, 2)
    testAssert.equal(tokens[1].col, 1)
    assertRoundtrip(bom .. "local value")
    assertRoundtrip("#!/usr/bin/env nupp\r\nlocal value")
end

function M.everySourceByteMakesProgress()
    for value = 0, 255 do
        local source = string.char(value)
        local tokens = lexer.lex(source)
        assert(#tokens >= 1 and #tokens <= 2, "one byte produces at most one token and eof")
        testAssert.equal(tokens[#tokens].kind, "eof", "byte " .. value .. " reaches eof")
        testAssert.equal(lexer.textOf(tokens), source, "byte " .. value .. " round trips")
    end

    local source = "\192\175name"
    local tokens, errors = lexer.lex(source)
    testAssert.equal(#errors, 2, "each malformed UTF-8 lead byte is one lexical error")
    testAssert.equal(errors[1].offset, 1)
    testAssert.equal(errors[2].offset, 2)
    testAssert.equal(tokens[3].kind, "name")
    testAssert.equal(lexer.textOf(tokens), source)
end

function M.interpolatedStrings()
    testAssert.equal(kindsOf("`a ${x} b`"), "istringOpen name istringClose")
    testAssert.equal(kindsOf("`${a} and ${b}`"), "istringOpen name istringMid name istringClose")
    testAssert.equal(kindsOf("`plain`"), "string")
    -- braces inside the interpolation are matched
    testAssert.equal(kindsOf("`v ${ {n = 1}.n }`"), "istringOpen { name = number } . name istringClose")
    -- nested interpolated strings
    testAssert.equal(kindsOf("`o ${`i ${x}`}`"), "istringOpen istringOpen name istringClose istringClose")
    local _, errors = lexer.lex("`open ${x")
    testAssert.equal(errors[#errors].msg, "unterminated interpolated string")
    local trailing, trailingErrors = lexer.lex("`\\")
    testAssert.equal(trailing[#trailing].kind, "eof", "a final escape still reaches eof")
    testAssert.equal(trailingErrors[#trailingErrors].msg, "unterminated interpolated string")
    testAssert.equal(lexer.textOf(trailing), "`\\", "the malformed string still round trips")
end

function M.numberLiterals()
    testAssert.equal(kindsOf("10LL 0xffULL 3i 0x1p4 12.5e-3 .5 1e3i"), "number number number number number number number")
    local tokens = lexer.lex("0xffULL")
    testAssert.equal(tokens[1].text, "0xffULL", "suffix text")
    -- '1..2' must lex as number .. number (concat), not a malformed number
    testAssert.equal(kindsOf("1..2"), "number .. number")
end

function M.numberLiteralSeparators()
    local src = "1_234 1_ 1__2 0_x_ff 0x_ff_ 1_.5 1._5 " .. "1_e_3 0x1_p_2 1_U_L_L"
    testAssert.equal(kindsOf(src), "number number number number number number number number number number")
    assertRoundtrip(src)
end

function M.malformedNumbers()
    local tokens, errors = lexer.lex("local a = 0x")
    testAssert.equal(tokens[4].kind, "error")
    testAssert.equal(#errors, 1)
    testAssert.equal(errors[1].msg, "malformed number")
    assertRoundtrip("local a = 0x + 12abc")
end

function M.triviaPreserved()
    local tokens = lexer.lex("  -- lead\nlocal x")
    local tok = tokens[1]
    testAssert.equal(tok.triviaCount, 3, "trivia count") -- spaces, comment, newline
    testAssert.equal(lexer.triviaKind(tok, 1), "whitespace")
    testAssert.equal(lexer.triviaKind(tok, 2), "comment")
    testAssert.equal(lexer.triviaText(tok, 2), "-- lead")
    testAssert.equal(lexer.triviaKind(tok, 3), "whitespace")
    local eof = tokens[#tokens]
    testAssert.equal(eof.kind, "eof")
end

function M.trailingTriviaOnEof()
    local tokens = lexer.lex("return 1 -- done\n")
    local eof = tokens[#tokens]
    testAssert.equal(eof.triviaCount, 3) -- space, comment, newline
    testAssert.equal(lexer.triviaKind(eof, 2), "comment")
end

function M.positions()
    local tokens = lexer.lex("local x\n  return y")
    -- tokens: local x return y eof
    testAssert.equal(tokens[1].line, 1);
    testAssert.equal(tokens[1].col, 1)
    testAssert.equal(tokens[2].line, 1);
    testAssert.equal(tokens[2].col, 7)
    testAssert.equal(tokens[3].line, 2);
    testAssert.equal(tokens[3].col, 3)
    testAssert.equal(tokens[4].line, 2);
    testAssert.equal(tokens[4].col, 10)
    testAssert.equal(tokens[3].offset, 11)
end

function M.multilineStringPositions()
    local tokens = lexer.lex("local s = [[a\nb]] return 1")
    -- token after the multi-line string must be on line 2
    testAssert.equal(tokens[5].kind, "return")
    testAssert.equal(tokens[5].line, 2)
    testAssert.equal(tokens[5].col, 5)
end

function M.unterminatedString()
    local tokens, errors = lexer.lex("local s = 'oops\nreturn 1")
    testAssert.equal(tokens[4].kind, "error")
    testAssert.equal(errors[1].msg, "unterminated string")
    testAssert.equal(errors[1].code, "NUPP1001")
    assert(errors[1].length > 1, "lexical range covers the malformed token")
    -- lexing continues on the next line
    testAssert.equal(tokens[5].kind, "return")
    assertRoundtrip("local s = 'oops\nreturn 1")
end

function M.escapedNewlineInString()
    testAssert.equal(kindsOf("local s = 'a\\\nb'"), "local name = string")
end

function M.unterminatedLongComment()
    local tokens, errors = lexer.lex("--[[ open")
    testAssert.equal(errors[1].msg, "unterminated long comment")
    testAssert.equal(tokens[#tokens].kind, "eof")
    testAssert.equal(lexer.triviaKind(tokens[#tokens], 1), "comment")
end

function M.unexpectedCharacters()
    local tokens, errors = lexer.lex("a $ b")
    testAssert.equal(tokens[2].kind, "error")
    testAssert.equal(#errors, 1)
    assertRoundtrip("a $ b")
end

-- A backtick body becomes the one Lua literal both the generator and the value
-- reader agree on: an escaped quote is left as the escape it already is, and an
-- escaped backslash before a quote does not hide the quote from escaping.
function M.backtickBodiesQuoteEscapedQuotesOnce()
    local cases = {
        {[[a\"b]], [["a\"b"]], 'a"b'},
        {[[a\\"b]], [["a\\\"b"]], [[a\"b]]},
        {[[a"b]], [["a\"b"]], 'a"b'},
        {[[a\`b\$c]], [["a`b$c"]], "a`b$c"},
        {"a\nb", [["a\nb"]], "a\nb"},
        {[[a\tb]], [["a\tb"]], "a\tb"},
    }
    for _, case in ipairs(cases) do
        local body, quoted, value = case[1], case[2], case[3]
        testAssert.equal(lexer.quoteBacktickBody(body), quoted, "quoting " .. body)
        testAssert.equal(lexer.stringValue("`" .. body .. "`"), value, "value of " .. body)
        testAssert.equal(lexer.stringValue(quoted), value, "the quoted form agrees")
    end
end

-- The errors `lex` reports for `src`, as "line:col message" strings.
local function errorsOf(src)
    local _, errors = lexer.lex(src)
    local out = {}
    for _, e in ipairs(errors) do
        out[#out + 1] = ("%d:%d %s"):format(e.line, e.col, e.msg)
    end
    return table.concat(out, "; ")
end

-- A short string continues past a line break the way LuaJIT reads it: `\z` skips the
-- whitespace after it, newlines included, and a backslash before CR LF or LF CR
-- escapes that one line break. Both leave a raw newline after the escape.
function M.stringContinuationsFollowLuaJIT()
    for _, src in ipairs({
        'local s = "a\\z\n   b"\nprint(s)',
        'local s = "a\\z\r\n\r\n   b"\r\nprint(s)',
        'local s = "a\\\r\nb"\r\nprint(s)',
        'local s = "a\\\n\rb"\nprint(s)',
        'local s = "a\\\rb"',
    }) do
        testAssert.equal(kindsOf(src):match("^local name = (%a+)"), "string", "one string token for " .. ("%q"):format(src))
        testAssert.equal(errorsOf(src), "", "no error for " .. ("%q"):format(src))
        assertRoundtrip(src)
    end
    local tokens = select(1, lexer.lex('local s = "a\\z\n   b"\nprint(s)'))
    testAssert.equal(tokens[5].line, 3, "lines after a continued string are counted")
end

-- An escape LuaJIT refuses is refused here, at the escape, rather than passing the
-- check and failing when the generated chunk loads.
function M.invalidEscapesAreErrorsAtTheEscape()
    for src, want in pairs({
        ['print("\\q")'] = "1:8 invalid escape sequence '\\q'",
        ['x = "ab\\300"'] = "1:8 invalid escape sequence '\\300'",
        ["x = '\\x4g'"] = "1:6 invalid escape sequence '\\x4g'",
        ['x = "\\u{110000}"'] = "1:6 invalid escape sequence '\\u{110000}'",
        ['x = "\\u{7FFFFFFF}"'] = "1:6 invalid escape sequence '\\u{7FFFFFFF}'",
        ['x = "\\u{}"'] = "1:6 invalid escape sequence '\\u{}'",
        ['x = "\\u41"'] = "1:6 invalid escape sequence '\\u4'",
    }) do
        testAssert.equal(errorsOf(src), want, src)
        assertRoundtrip(src)
    end
    for _, src in ipairs({
        'x = "\\a\\b\\f\\n\\r\\t\\v\\\\\\"\\\'"',
        'x = "\\255\\0\\9\\x41\\xfF"',
        'x = "\\u{10FFFF}\\u{0000000041}"',
    }) do
        testAssert.equal(errorsOf(src), "", src)
    end
end

-- `LL`, `ULL` make an integer cdata literal; LuaJIT refuses them on a numeral with a
-- fraction or an exponent.
function M.integerSuffixesNeedAnIntegerNumeral()
    for _, src in ipairs({"x = 1.5LL", "x = 1e5LL", "x = 2.ULL", "x = 0x1p4LL", "x = 0x1.8ll"}) do
        testAssert.equal(errorsOf(src), "1:5 malformed number", src)
    end
    for _, src in ipairs({"x = 15LL", "x = 0xFFULL", "x = 1.5i", "x = 1e5i", "x = 1_000LL"}) do
        testAssert.equal(errorsOf(src), "", src)
    end
end

-- A byte that starts no token is named in the message as ASCII, so the message is
-- valid UTF-8 whatever the source is.
function M.unexpectedBytesAreNamedInASCII()
    local _, errors = lexer.lex("local \255\254 = 2")
    testAssert.equal(#errors, 2)
    testAssert.equal(errors[1].msg, 'unexpected character "\\xFF"')
    testAssert.equal(errors[2].msg, 'unexpected character "\\xFE"')
    local _, others = lexer.lex("x = $")
    testAssert.equal(others[1].msg, 'unexpected character "$"')
end

-- LuaJIT skips a hashbang line after a byte-order mark too.
function M.aHashbangMayFollowAByteOrderMark()
    local src = "\239\187\191#!/usr/bin/env nupp\nprint(1)\n"
    testAssert.equal(errorsOf(src), "")
    testAssert.equal(kindsOf(src), "name ( number )")
    assertRoundtrip(src)
end

-- Rows no other case pins: a long bracket closes only at its own level, a numeral
-- running into name characters is malformed, and vertical tab and form feed are
-- whitespace.
function M.longBracketsNumeralsAndWhitespaceEdges()
    local tokens = select(1, lexer.lex("x = [==[ a ]] b ]=] c ]==] y"))
    testAssert.equal(tokens[3].text, "[==[ a ]] b ]=] c ]==]", "the string runs to its own level's closer")
    testAssert.equal(tokens[4].text, "y")
    testAssert.equal(errorsOf("x = 12abc"), "1:5 malformed number")
    testAssert.equal(errorsOf("x = 0x"), "1:5 malformed number")
    testAssert.equal(kindsOf("a\vb\fc"), "name name name")
    testAssert.equal(errorsOf("a\vb\fc"), "")
end

return M
