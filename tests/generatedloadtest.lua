-- Generated Lua that will not load, reported where the file is built.
--
-- LuaJIT caps a function at sixty upvalues and refuses to parse one that reaches past
-- it. Before this, that surfaced as a load error naming a generated line, in whichever
-- command happened to require the module first -- and once, only under a coverage build,
-- because that instruments the largest function in the compiler and tips it over.

local parser = require("nupp.compiler.parser")
local check = require("fragment")
local gen = require("nupp.compiler.gen")
local envMod = require("nupp.compiler.env")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
if not HERE:match("^/") then
   local p = assert(io.popen("pwd"))
   HERE = p:read("*l") .. "/" .. HERE
   p:close()
end
local env = envMod.new(HERE .. "/..")

local M = {}

local function generate(src)
   local result = parser.parse(src, "load-test.g.nupp")
   assert(#result.errors == 0, "syntax errors")
   local diags = check.check(result, "load-test.g.nupp", env)
   assert(#diags == 0, "check: " .. (diags[1] and diags[1].msg or ""))
   return gen.generate(result, "load-test.g.nupp")
end

-- Sixty-one names read from around a function is one more than a Lua function can hold.
local function capturingSource(count)
   local lines = {}
   local reads = {}
   for i = 1, count do
      lines[#lines + 1] = ("local v%d = %d"):format(i, i)
      reads[#reads + 1] = ("v%d"):format(i)
   end
   lines[#lines + 1] = ""
   lines[#lines + 1] = "local function total(): number"
   lines[#lines + 1] = "    return " .. table.concat(reads, " + ")
   lines[#lines + 1] = "end"
   lines[#lines + 1] = ""
   lines[#lines + 1] = "return total"

   return table.concat(lines, "\n") .. "\n"
end

function M.capturingPastTheLimitIsReportedWhereItIsWritten()
   local _, diags = generate(capturingSource(61))
   assert(#diags == 1, "expected one diagnostic, got " .. #diags)
   local d = diags[1]
   assert(d.code == "NUPP3005", "code was " .. tostring(d.code))
   assert(d.msg:find("captures more than 60 names", 1, true),
      "the message says what the limit is: " .. d.msg)
   assert(d.help:find("as arguments", 1, true),
      "the help says the way out: " .. tostring(d.help))
   -- Line numbers survive generation one to one, so this is where `total` was written.
   assert(d.line == 63, "reported at line " .. tostring(d.line) .. ", expected 63")
end

-- The control, and the reason the number matters: sixty is fine and sixty-one is not, so
-- the check is reading the real limit rather than firing on anything large.
function M.capturingUpToTheLimitIsAccepted()
   local code, diags = generate(capturingSource(59))
   assert(#diags == 0, "expected no diagnostic, got " .. (diags[1] and diags[1].msg or ""))
   assert(loadstring(code, "@within-limit"), "generated code should load")
end

-- `new R(field = value)` lowers from what the checker resolved rather than from what
-- the call wrote, so an unchecked construction is one the generator writes out as the
-- call it was spelled as -- which is not Lua. Entries standing after a computed key
-- used to go unchecked, and this is where that surfaced.
function M.constructionsAfterAComputedKeyAreLowered()
   local code, diags = generate(table.concat({
      "local m = {}",
      "",
      "record m.R",
      "    f: integer",
      "end",
      "",
      "local t = {[\"a\"] = new m.R(f = 1), [\"b\"] = new m.R(f = 2)}",
      "",
      "function m.second(): integer",
      "    return t[\"b\"].f",
      "end",
      "",
      "return m",
   }, "\n") .. "\n")
   assert(#diags == 0, "expected no diagnostic, got " .. (diags[1] and diags[1].msg or ""))
   local chunk, err = loadstring(code, "@computed-key")
   assert(chunk, "generated code should load: " .. tostring(err) .. "\n---\n" .. code)
   -- Loading proves it is Lua; running proves the second entry is an instance rather
   -- than whatever calling the record's own table would have produced.
   local second = chunk().second()
   assert(second == 2, "the entry after the computed key: " .. tostring(second))
end

-- Ordinary files carry no cost and no report.
function M.anOrdinaryFileReportsNothing()
   local code, diags = generate(table.concat({
      "local m = {}",
      "",
      "function m.one(): number",
      "    return 1",
      "end",
      "",
      "return m",
   }, "\n") .. "\n")
   assert(#diags == 0, "expected no diagnostic, got " .. (diags[1] and diags[1].msg or ""))
   assert(loadstring(code, "@ordinary"), "generated code should load")
end

return M
