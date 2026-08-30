local lexer = require("nupp.compiler.lexer")

local function kindsOf(src)
   local tokens = select(1, lexer.lex(src))
   local out = {}
   for _, t in ipairs(tokens) do
      if t.kind ~= "eof" then out[#out + 1] = t.kind end
   end
   return table.concat(out, " ")
end

local function assertEq(got, want, label)
   if got ~= want then
      error(("%s:\n  want: %s\n  got:  %s"):format(label or "mismatch",
         tostring(want), tostring(got)), 2)
   end
end

local function assertRoundtrip(src)
   local tokens = select(1, lexer.lex(src))
   assertEq(lexer.textOf(tokens), src, "round-trip failed for " .. ("%q"):format(src))
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
      require("nupp.compiler.triviaarena.ffi"),
      require("nupp.compiler.triviaarena.table"),
   }
   for _, provider in ipairs(providers) do
      local arena = provider.new("  -- note\nvalue")
      assertEq(arena.count, 0, "a new arena is empty")
      assertEq(arena:append(1, 1, 2, 1, 1), 1, "the first record index")
      for index = 2, 80 do
         assertEq(arena:append(index % 4 + 1, index, index + 1,
            index + 2, index + 3), index, "append grows the arena")
      end
      local kind, offset, length, line, col = arena:record(65)
      assertEq(kind, 2, "record kind")
      assertEq(offset, 65, "record offset")
      assertEq(length, 66, "record length")
      assertEq(line, 67, "record line")
      assertEq(col, 68, "record column")
      assertEq(arena.source, "  -- note\nvalue", "the source is retained")
      -- An out-of-range index is refused, not answered from memory the record
      -- never reached: past `count` the ffi block holds zeroes that pass for a
      -- record, and before it lies foreign memory.
      for _, index in ipairs({0, -1, 81}) do
         local ok, err = pcall(function() return arena:record(index) end)
         assertEq(ok, false, "record " .. index .. " must be refused")
         assertEq(tostring(err):match("outside 1%.%.80") ~= nil, true,
            "record " .. index .. " names the range: " .. tostring(err))
      end
   end
end

function M.roundtripCorpus()
   for _, src in ipairs(CORPUS) do
      assertRoundtrip(src)
   end
end

function M.basicKinds()
   assertEq(kindsOf("local x = 1 + 2"), "local name = number + number")
   assertEq(kindsOf('return "s" .. [[l]]'), "return string .. string")
   assertEq(kindsOf("const x = 1"), "name name = number",
      "const must remain a soft keyword")
   assertEq(kindsOf("local sealed interface Token end"),
      "local sealed name name end", "sealed must be reserved")
end

function M.luajit3Operators()
   assertEq(kindsOf("a ~>> 2"), "name ~>> number")
   assertEq(kindsOf("a >> b << c"), "name >> name << name")
   assertEq(kindsOf("t?.x"), "name ?. name")
   assertEq(kindsOf("a ? b : c"), "name ? name : name")
   assertEq(kindsOf("a // b"), "name // name")
   assertEq(kindsOf("::top::"), ":: name ::")
   assertEq(kindsOf("|a| -> a"), "| name | -> name")
end

function M.customaryOperators()
   -- A customary spelling lexes as the operator it spells, so nothing
   -- downstream has to know both forms.
   assertEq(kindsOf("!a"), "not name")
   assertEq(kindsOf("a && b"), "name and name")
   assertEq(kindsOf("a || b"), "name or name")
   assertEq(kindsOf("a != b"), "name ~= name")
   -- The bytes that were written survive for the round trip and the formatter.
   local tokens = lexer.lex("a && b")
   assertEq(tokens[2].text, "&&")
   assertEq(lexer.textOf(tokens), "a && b")
   -- Longest match keeps the one-character spellings apart from the two.
   assertEq(kindsOf("a & b"), "name & name")
   assertEq(kindsOf("a | b"), "name | name")
end

function M.interpolatedStrings()
   assertEq(kindsOf("`a ${x} b`"), "istringOpen name istringClose")
   assertEq(kindsOf("`${a} and ${b}`"),
      "istringOpen name istringMid name istringClose")
   assertEq(kindsOf("`plain`"), "string")
   -- braces inside the interpolation are matched
   assertEq(kindsOf("`v ${ {n = 1}.n }`"),
      "istringOpen { name = number } . name istringClose")
   -- nested interpolated strings
   assertEq(kindsOf("`o ${`i ${x}`}`"),
      "istringOpen istringOpen name istringClose istringClose")
   local _, errors = lexer.lex("`open ${x")
   assertEq(errors[#errors].msg, "unterminated interpolated string")
end

function M.numberLiterals()
   assertEq(kindsOf("10LL 0xffULL 3i 0x1p4 12.5e-3 .5 1e3i"),
      "number number number number number number number")
   local tokens = lexer.lex("0xffULL")
   assertEq(tokens[1].text, "0xffULL", "suffix text")
   -- '1..2' must lex as number .. number (concat), not a malformed number
   assertEq(kindsOf("1..2"), "number .. number")
end

function M.numberLiteralSeparators()
   local src = "1_234 1_ 1__2 0_x_ff 0x_ff_ 1_.5 1._5 "
      .. "1_e_3 0x1_p_2 1_U_L_L"
   assertEq(kindsOf(src),
      "number number number number number number number number number number")
   assertRoundtrip(src)
end

function M.malformedNumbers()
   local tokens, errors = lexer.lex("local a = 0x")
   assertEq(tokens[4].kind, "error")
   assertEq(#errors, 1)
   assertEq(errors[1].msg, "malformed number")
   assertRoundtrip("local a = 0x + 12abc")
end

function M.triviaPreserved()
   local tokens = lexer.lex("  -- lead\nlocal x")
   local tok = tokens[1]
   assertEq(tok.triviaCount, 3, "trivia count") -- spaces, comment, newline
   assertEq(lexer.triviaKind(tok, 1), "whitespace")
   assertEq(lexer.triviaKind(tok, 2), "comment")
   assertEq(lexer.triviaText(tok, 2), "-- lead")
   assertEq(lexer.triviaKind(tok, 3), "whitespace")
   local eof = tokens[#tokens]
   assertEq(eof.kind, "eof")
end

function M.trailingTriviaOnEof()
   local tokens = lexer.lex("return 1 -- done\n")
   local eof = tokens[#tokens]
   assertEq(eof.triviaCount, 3) -- space, comment, newline
   assertEq(lexer.triviaKind(eof, 2), "comment")
end

function M.positions()
   local tokens = lexer.lex("local x\n  return y")
   -- tokens: local x return y eof
   assertEq(tokens[1].line, 1); assertEq(tokens[1].col, 1)
   assertEq(tokens[2].line, 1); assertEq(tokens[2].col, 7)
   assertEq(tokens[3].line, 2); assertEq(tokens[3].col, 3)
   assertEq(tokens[4].line, 2); assertEq(tokens[4].col, 10)
   assertEq(tokens[3].offset, 11)
end

function M.multilineStringPositions()
   local tokens = lexer.lex("local s = [[a\nb]] return 1")
   -- token after the multi-line string must be on line 2
   assertEq(tokens[5].kind, "return")
   assertEq(tokens[5].line, 2)
   assertEq(tokens[5].col, 5)
end

function M.unterminatedString()
   local tokens, errors = lexer.lex("local s = 'oops\nreturn 1")
   assertEq(tokens[4].kind, "error")
   assertEq(errors[1].msg, "unterminated string")
   assertEq(errors[1].code, "NUPP1001")
   assert(errors[1].length > 1, "lexical range covers the malformed token")
   -- lexing continues on the next line
   assertEq(tokens[5].kind, "return")
   assertRoundtrip("local s = 'oops\nreturn 1")
end

function M.escapedNewlineInString()
   assertEq(kindsOf("local s = 'a\\\nb'"), "local name = string")
end

function M.unterminatedLongComment()
   local tokens, errors = lexer.lex("--[[ open")
   assertEq(errors[1].msg, "unterminated long comment")
   assertEq(tokens[#tokens].kind, "eof")
   assertEq(lexer.triviaKind(tokens[#tokens], 1), "comment")
end

function M.unexpectedCharacters()
   local tokens, errors = lexer.lex("a $ b")
   assertEq(tokens[2].kind, "error")
   assertEq(#errors, 1)
   assertRoundtrip("a $ b")
end

return M
