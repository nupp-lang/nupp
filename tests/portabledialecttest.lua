local parser = require("nupp.compiler.parser")
local check = require("fragment")
local envMod = require("nupp.compiler.env")
local gen = require("nupp.compiler.gen")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local ROOT = HERE == "tests" and "." or assert(HERE:match("^(.*)[/\\]tests$"))

local function assertEq(got, want, label)
   if got ~= want then
      error(("%s:\n  want: %s\n  got:  %s"):format(label or "mismatch",
         tostring(want), tostring(got)), 2)
   end
end

local function read(path)
   local file = assert(io.open(path, "rb"))
   local contents = file:read("*a")
   file:close()
   return contents
end

local function checked(src, dialect)
   local result = parser.parse(src, "portable-test.g.nupp")
   assertEq(#result.errors, 0, "portable test source parses")
   local diags = check.check(result, "portable-test.g.nupp", envMod.new(HERE), {
      dialect = dialect,
   })
   return result, diags
end

local M = {}

function M.realCorpusRunsUnderStockLuaAndLuaJIT()
   local command = ("'%s/scripts/portable-lua-corpus.sh' lua luajit 2>&1"):format(ROOT)
   local pipe = assert(io.popen(command))
   local output = pipe:read("*a")
   local ok, why, status = pipe:close()
   assert(ok, ("portable corpus failed (%s %s):\n%s"):format(tostring(why), tostring(status), output))
   assert(output:find("lua passed", 1, true), output)
   assert(output:find("luajit passed", 1, true), output)

   local generated = read(ROOT .. "/tests/portable-corpus/build/main.lua")
   for _, spelling in ipairs({"?.", "??", "+=", "1_000", "|value"}) do
      assert(not generated:find(spelling, 1, true),
         "portable generated output retained " .. spelling .. ":\n" .. generated)
   end
   assert(not generated:match("%f[%a]const%f[^%w_]"),
      "portable generated output retained const:\n" .. generated)
end

function M.explicitNativeDialectChangesNoGeneratedByte()
   local source = read(ROOT .. "/tests/portable-corpus/main.nupp")
   local default, defaultDiags = checked(source, nil)
   local native, nativeDiags = checked(source, "luajit")
   assertEq(#defaultDiags, 0, "default corpus checks")
   assertEq(#nativeDiags, 0, "explicit native corpus checks")
   assertEq(gen.generate(native, "native-corpus.nupp"), gen.generate(default, "native-corpus.nupp"),
      "explicit luajit output is byte-identical to the default")
end

function M.authoredJumpsAreRefusedOnlyByThePortableDialect()
   local source = table.concat({
      "local answer = 1",
      "goto done",
      "answer = 2",
      "::done::",
      "return answer",
   }, "\n")
   local _, nativeDiags = checked(source, "luajit")
   assertEq(#nativeDiags, 0, "LuaJIT retains authored jumps")
   local _, portableDiags = checked(source, "lua51")
   assertEq(#portableDiags, 2, "portable checking reports the label and goto")
   assertEq(portableDiags[1].code, "NUPP3009", "goto diagnostic code")
   assertEq(portableDiags[2].code, "NUPP3009", "label diagnostic code")
   assert(portableDiags[1].help:find("structured control flow", 1, true),
      "the refusal gives the structured alternative")
end

function M.cdataNumeralsRequireRepresentationsThePortableDialectDoesNotHave()
   local _, nativeDiags = checked("return 1LL, 2ULL, 3i", "luajit")
   assertEq(#nativeDiags, 0, "LuaJIT retains cdata numerals")
   local _, portableDiags = checked("return 1LL, 2ULL, 3i", "lua51")
   assertEq(#portableDiags, 3, "each unportable cdata numeral is diagnosed")
   assert(portableDiags[1].msg:find("`int64` capability", 1, true), portableDiags[1].msg)
   assert(portableDiags[3].msg:find("`cinterop` capability", 1, true), portableDiags[3].msg)
end

function M.constErasureDoesNotRewriteStringContents()
   local result, diags = checked("const value = [[const field]]\nreturn value", "lua51")
   assertEq(#diags, 0, "portable string source checks")
   local code, loweringDiags = gen.generate(result, "portable-string.nupp")
   assertEq(#loweringDiags, 0, "portable string source lowers")
   assert(code:find("[[const field]]", 1, true), "const inside a long string is preserved:\n" .. code)
   local chunk, problem = loadstring(code, "@portable-string")
   assert(chunk, tostring(problem) .. "\n" .. code)
   assertEq(chunk(), "const field", "const string value")
end

function M.cleanupContinueAndBreakUseTheStructuredLoopExit()
   local source = table.concat({
      "local h = {}",
      "local total = 0",
      "for index = 1, 3 do",
      "    handle suspension with h do",
      "        if index == 2 then continue end",
      "        total = total + index",
      "    end",
      "end",
      "while true do",
      "    handle suspension with h do",
      "        break",
      "    end",
      "end",
      "return total, true",
   }, "\n")
   local result, diags = checked(source, "lua51")
   for _, diag in ipairs(diags) do
      assert(diag.severity == "warning" or diag.severity == "note",
         "portable cleanup source checks: " .. diag.code .. " " .. diag.msg)
   end
   local code, loweringDiags = gen.generate(result, "portable-cleanup.nupp")
   assertEq(#loweringDiags, 0, "portable cleanup lowers cleanly")
   assert(not code:find("then continue", 1, true) and not code:find("\ncontinue", 1, true),
      "portable cleanup retained a continue statement:\n" .. code)
   assert(code:find("repeat", 1, true) and code:find('==\"break\"', 1, true),
      "portable loop uses a structured repeat and exit action:\n" .. code)
   local chunk, problem = loadstring(code, "@portable-cleanup")
   assert(chunk, "portable cleanup generated code loads: " .. tostring(problem) .. "\n" .. code)
   local continued, broken = chunk()
   assertEq(continued, 4, "cleanup continue reaches the authored loop")
   assertEq(broken, true, "cleanup break exits the authored loop")
end

return M
