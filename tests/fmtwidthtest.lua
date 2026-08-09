-- Width-aware formatting, docblocks, and the safety invariant.
local fmt = require("nupp.compiler.fmt")
local lexer = require("nupp.compiler.lexer")

local function assertEq(got, want, label)
   if got ~= want then
      error(("%s:\n--- want ---\n%s\n--- got ---\n%s"):format(
         label or "mismatch", tostring(want), tostring(got)), 2)
   end
end

local function fmt1(src)
   local text, errors = fmt.format(src, "test")
   assert(#errors == 0, "unexpected format errors: "
      .. (errors[1] and errors[1].msg or ""))
   return text
end

local function lines(...)
   return table.concat({ ... }, "\n") .. "\n"
end

-- Every case must be idempotent, parse-stable, and within the width where
-- the formatter can manage it.
local function check(src, want, label)
   local got = fmt1(src)
   assertEq(got, want, label)
   assertEq(fmt1(got), got, (label or "case") .. " (idempotency)")
   local function kinds(text)
      local out = {}
      for _, tok in ipairs(lexer.lex(text)) do
         out[#out + 1] = tok.kind .. tok.text
      end
      return table.concat(out, " ")
   end
   assertEq(kinds(got), kinds(src), (label or "case") .. " (token stability)")
end

local M = {}

function M.internalInnerAnnotationStaysTightAndAtFileScope()
   local got = fmt1("@!internal\nlocal x=1\n")
   assertEq(got, "@!internal\nlocal x = 1\n", "internal inner annotation")
end

function M.indentIsFourSpaces()
   check("if x then\nf()\nend\n", lines("if x then", "    f()", "end"))
   check("while a do\nif b then\nc()\nend\nend\n",
      lines("while a do", "    if b then", "        c()", "    end", "end"))
end

function M.shortLinesAreLeftAlone()
   local src = lines("local x = 1 + 2", "print(x, 3)")
   check(src, src)
end

function M.softBreaksJoinWhenTheyFit()
   check(lines(
      "return {diags = result.errors, moduleType = nil, syntax = true,",
      "    result = result}"),
      "return {diags = result.errors, moduleType = nil, syntax = true, result = result}\n")
end

function M.fileNofmtTagLeavesSourceUntouched()
   local src = "@!nofmt\nlocal x=1\n"
   assertEq(fmt1(src), src)
end

function M.callArgumentsBreakOnePerLine()
   check("local v = compute(alphaArgument, betaArgument, gammaArgument, "
      .. "deltaArgument, epsilonArgument, zetaArgument, etaLongerArgument)\n",
      lines("local v = compute(",
         "    alphaArgument,",
         "    betaArgument,",
         "    gammaArgument,",
         "    deltaArgument,",
         "    epsilonArgument,",
         "    zetaArgument,",
         "    etaLongerArgument",
         ")"))
end

function M.parameterListsBreak()
   check("local function f(firstParameter: number, secondParameter: string, "
      .. "thirdParameter: boolean, fourthParameter: {number}): number\nreturn 1\nend\n",
      lines("local function f(",
         "    firstParameter: number,",
         "    secondParameter: string,",
         "    thirdParameter: boolean,",
         "    fourthParameter: {number}",
         "): number",
         "    return 1",
         "end"))
end

function M.tableConstructorsBreak()
   check("local t = { alphaValue = 1, betaValue = 2, gammaValue = 3, "
      .. "deltaValue = 4, epsilonValue = 5, zetaValue = 6, etaValue = 77 }\n",
      lines("local t = {",
         "    alphaValue = 1,",
         "    betaValue = 2,",
         "    gammaValue = 3,",
         "    deltaValue = 4,",
         "    epsilonValue = 5,",
         "    zetaValue = 6,",
         "    etaValue = 77",
         "}"))
end

function M.shapeFieldsAlwaysBreak()
   check("type Pair = {first: string, second: number}\n", lines(
      "type Pair = {",
      "    first: string,",
      "    second: number",
      "}"))
end

function M.parenthesizedTablesKeepTheirCloserTogether()
   check("local t = ({ alphaValue = 1, betaValue = 2, gammaValue = 3, "
      .. "deltaValue = 4, epsilonValue = 5, zetaValue = 6, etaValue = 77 })\n",
      lines("local t = ({",
         "    alphaValue = 1,",
         "    betaValue = 2,",
         "    gammaValue = 3,",
         "    deltaValue = 4,",
         "    epsilonValue = 5,",
         "    zetaValue = 6,",
         "    etaValue = 77",
         "})"))
end

function M.multilineShapesCloseAndDropTrailingComma()
   local src = lines(
      "type Options = {anExceptionallyLongOptionNameOne: string,",
      "anotherExceptionallyLongOptionNameTwo: string,",
      "finalOption: boolean?,}")
   local want = lines(
      "type Options = {",
      "    anExceptionallyLongOptionNameOne: string,",
      "    anotherExceptionallyLongOptionNameTwo: string,",
      "    finalOption: boolean?",
      "}")
   local got = fmt1(src)
   assertEq(got, want)
   assertEq(fmt1(got), got, "multiline shape idempotency")
end

function M.nestedGroupsBreakOutermostFirst()
   local got = fmt1("local v = outerCall(innerCall(oneArgument, twoArgument, "
      .. "threeArgument), anotherOuterArgument, aThirdOuterEvenLongerArgument)\n")
   assertEq(got, lines("local v = outerCall(",
      "    innerCall(oneArgument, twoArgument, threeArgument),",
      "    anotherOuterArgument,",
      "    aThirdOuterEvenLongerArgument",
      ")"))
   assertEq(fmt1(got), got, "nested idempotency")
end

function M.operatorFallbackWhenNoGroup()
   check("local s = someVeryLongVariableName .. anotherQuiteLongVariableName "
      .. ".. aThirdRatherLongVariableName .. aFourthLongVariableName .. tail\n",
      lines("local s = someVeryLongVariableName",
         "    .. anotherQuiteLongVariableName",
         "    .. aThirdRatherLongVariableName",
         "    .. aFourthLongVariableName",
         "    .. tail"))
end

function M.carriedIfConditionsStartWithAnd()
   check(lines(
      "if calleeTok and calleeTok.text == \"ipairs\" and global",
      "    and calleeTok.definition == global.definition and operand",
      "    and global.definition and global.definition.stable",
      "    and operand.kind == \"name\" and operandType",
      "    and operandType.tag == \"array\" then",
      "    stat.builtinIpairs = {operand = operand, type = operandType}",
      "end"), lines(
      "if calleeTok",
      "    and calleeTok.text == \"ipairs\"",
      "    and global",
      "    and calleeTok.definition == global.definition",
      "    and operand",
      "    and global.definition",
      "    and global.definition.stable",
      "    and operand.kind == \"name\"",
      "    and operandType",
      "    and operandType.tag == \"array\"",
      "then",
      "    stat.builtinIpairs = {operand = operand, type = operandType}",
      "end"))
end

function M.finalReturnsInLongFunctionsAreSeparated()
   check(lines(
      "local function total()",
      "local first = 1",
      "local second = 2",
      "local third = 3",
      "local fourth = 4",
      "return first + second + third + fourth",
      "end"), lines(
      "local function total()",
      "    local first = 1",
      "    local second = 2",
      "    local third = 3",
      "    local fourth = 4",
      "",
      "    return first + second + third + fourth",
      "end"))

   check(lines(
      "local function total()",
      "local first = 1",
      "local second = 2",
      "local third = 3",
      "return first + second + third",
      "end"), lines(
      "local function total()",
      "    local first = 1",
      "    local second = 2",
      "    local third = 3",
      "    return first + second + third",
      "end"))
end

function M.functionDeclarationsHaveBlankAfterTheirEnd()
   check(lines(
      "local function first()",
      "end",
      "local function second()",
      "end"), lines(
      "local function first()",
      "end",
      "",
      "local function second()",
      "end"))

   check(lines(
      "local function outer()",
      "local function inner()",
      "end",
      "end"), lines(
      "local function outer()",
      "    local function inner()",
      "    end",
      "end"))
end

function M.unbreakableLineIsLeftLong()
   -- a single enormous string literal has nothing to break on
   local src = "local s = '" .. ("x"):rep(140) .. "'\n"
   check(src, src)
end

function M.docblockRewrapsAtEightyEight()
   local got = fmt1("--- This description is deliberately long so that the "
      .. "formatter has to rewrap it at the documentation width rather than "
      .. "the code width at all.\nlocal x = 1\n")
   for line in got:gmatch("[^\n]+") do
      if line:sub(1, 3) == "---" then
         assert(#line <= 88, "doc line over 88 columns: " .. line)
      end
   end
   assert(got:find("--- This description", 1, true), "prefix preserved")
   assertEq(fmt1(got), got, "doc idempotency")
end

function M.docblockAnnotationsHangUnderTheirTag()
   local got = fmt1("--- Summary line.\n"
      .. "--- @param samples the samples to average, which carries a long "
      .. "description that has to wrap under its own tag\n"
      .. "--- @return the weighted mean\n"
      .. "local function f(samples) return samples end\n")
   assert(got:find("--- @param samples the samples", 1, true),
      "annotation kept on its own line:\n" .. got)
   assert(got:find("\n---     ", 1, true),
      "continuation hangs under the tag:\n" .. got)
   assert(got:find("--- @return the weighted mean", 1, true),
      "second annotation intact")
   assertEq(fmt1(got), got, "annotation idempotency")
end

function M.docblockBlankLineSeparation()
   local got = fmt1(lines(
      "local before = 1",
      "--- Documented.",
      "local function f()",
      "    return 1",
      "end",
      "local after = 2"))
   assertEq(got, lines(
      "local before = 1",
      "",
      "--- Documented.",
      "local function f()",
      "    return 1",
      "end",
      "",
      "local after = 2"))
   assertEq(fmt1(got), got, "separation idempotency")
end

function M.docblockCodeBlocksStayVerbatim()
   local src = lines(
      "--- Example:",
      "---",
      "---     local x = compute(1)",
      "---",
      "--- Done.",
      "local x = 1")
   local got = fmt1(src)
   assert(got:find("---     local x = compute(1)", 1, true),
      "indented code preserved:\n" .. got)
   assertEq(fmt1(got), got, "verbatim idempotency")
end

function M.plainCommentLinesArePreserved()
   local src = "-- This ordinary comment is deliberately split by its author.\n"
      .. "-- Its second source line must remain a separate line.\nlocal x = 1\n"
   check(src, src)
end

function M.commentsBreakOnlyWhenSafeAndNeeded()
   local prose = "-- " .. ("ordinary prose words "):rep(5)
      .. "ordinary prose words\nlocal x = 1\n"
   local got = fmt1(prose)
   assert(got ~= prose, "an over-width prose line should break")
   for line in got:gmatch("[^\n]+") do
      if line:sub(1, 2) == "--" then
         assert(#line <= 88, "safe prose line over 88 columns: " .. line)
      end
   end
   assertEq(fmt1(got), got, "safe comment break idempotency")

   local spaced = "-- " .. ("two  spaces "):rep(8)
      .. "two  spaces\nlocal x = 1\n"
   check(spaced, spaced, "intentional comment spacing")
   local word = "-- " .. ("x"):rep(100) .. "\nlocal x = 1\n"
   check(word, word, "unbreakable comment word")
end

function M.plainCommentCodeStaysVerbatim()
   local src = lines("-- Example:", "--", "--     local x = compute(1)",
      "--", "-- Done.", "local x = 1")
   check(src, src)
end

function M.unicodeUsesDisplayColumns()
   -- Precomposed and combining characters each occupy one display column,
   -- irrespective of their UTF-8 byte count.
   local precomposed = "local result = wrap('" .. ("é"):rep(52) .. "')\n"
   check(precomposed, precomposed, "precomposed width")
   local combining = "local result = wrap('" .. ("é"):rep(52) .. "')\n"
   check(combining, combining, "combining width")

   local words = (("é "):rep(40)):gsub(" $", "")
   check("--- " .. words .. "\nlocal x = 1\n",
      lines("--- " .. words, "local x = 1"), "docblock display width")

   -- East Asian wide characters occupy two columns, so merely counting code
   -- points would incorrectly leave this call on one line.
   local wide = "local result = wrap('" .. ("界"):rep(50) .. "', fallback)\n"
   check(wide, lines("local result = wrap(",
      "    '" .. ("界"):rep(50) .. "',",
      "    fallback",
      ")"), "wide character width")
end

function M.longTernariesBreakBeforeQuestionAndColon()
   check("local result = conditionWithAnExceptionallyLongAndDescriptiveName "
      .. "? valueReturnedWhenThatLongConditionIsTrue "
      .. ": valueReturnedWhenThatLongConditionIsFalse\n",
      lines("local result = conditionWithAnExceptionallyLongAndDescriptiveName",
         "    ? valueReturnedWhenThatLongConditionIsTrue",
         "    : valueReturnedWhenThatLongConditionIsFalse"))
end

function M.trailingCommentsStayOnTheirLine()
   check("local x = 1 -- why\nlocal y = 2\n",
      lines("local x = 1 -- why", "local y = 2"))
end

function M.blockCommentsAndHashbang()
   local src = lines("#!/usr/bin/env nupp", "local x = 1")
   check(src, src)
end

function M.safetyBailOnSyntaxErrors()
   local src = "if broken(\n"
   local text, errors = fmt.format(src, "test")
   assertEq(text, src, "unparseable input is returned untouched")
   assert(#errors > 0, "errors reported")
end

function M.formatterOutputStillChecks()
   -- structural sanity: format then reparse the whole corpus of examples
   local parser = require("nupp.compiler.parser")
   local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
   for _, rel in ipairs({ "/../examples/todo.nupp", "/../examples/cinterop.nupp" }) do
      local f = assert(io.open(HERE .. rel))
      local src = f:read("*a")
      f:close()
      local got = fmt1(src)
      local result = parser.parse(got, rel)
      assertEq(#result.errors, 0, "formatted example must parse: " .. rel)
      assertEq(fmt1(got), got, "example idempotency: " .. rel)
   end
end

return M
