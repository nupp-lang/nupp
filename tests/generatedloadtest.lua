-- Programs that lower from what the checker resolved rather than from what they wrote.

local parser = require("nupp.compiler.syntax.parser")
local check = require("fragment")
local program = require("program")
local envMod = require("nupp.compiler.project.env")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
if not HERE:match("^/") then
   local p = assert(io.popen("pwd"))
   HERE = p:read("*l") .. "/" .. HERE
   p:close()
end
local env = envMod.new(HERE .. "/..")

local M = {}

local function checked(src)
   local result = parser.parse(src, "load-test.nupp")
   assert(#result.errors == 0, "syntax errors")
   local diags = check.check(result, "load-test.nupp", env)
   assert(#diags == 0, "check: " .. (diags[1] and diags[1].msg or ""))
   return result
end

-- `new R(field = value)` lowers from what the checker resolved rather than from what
-- the call wrote, so an unchecked construction is one lowered as the call it was
-- spelled as. Entries standing after a computed key used to go unchecked.
function M.constructionsAfterAComputedKeyAreLowered()
   local result = checked(table.concat({
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
   -- The second entry is an instance rather than whatever calling the record's own
   -- table would have produced.
   local second = program.run(result, "computed-key").second()
   assert(second == 2, "the entry after the computed key: " .. tostring(second))
end

return M
