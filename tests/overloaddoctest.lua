-- Every Nupp fence in the overload guide is a complete checked program. Invalid
-- examples name their intended diagnostic in a leading `-- reports:` comment.
local parser = require("nupp.parser")
local check = require("fragment")
local envMod = require("nupp.env")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local ROOT = HERE .. "/.."
local env = envMod.new(ROOT)

local function assertEq(got, want, label)
   if got ~= want then
      error(("%s:\n  want: %s\n  got:  %s"):format(label or "mismatch",
         tostring(want), tostring(got)), 2)
   end
end

local M = {}

function M.everyOverloadGuideExampleChecksAsDocumented()
   local file = assert(io.open(ROOT .. "/docs/type-system/overloads.md", "rb"))
   local markdown = file:read("*a")
   file:close()

   local count = 0
   for source in markdown:gmatch("```nupp\n(.-)\n```") do
      count = count + 1
      local expected = source:match("^%-%- reports: ([A-Z0-9, ]+)") or ""
      expected = expected:gsub(",", "")

      local result = parser.parse(source, "overloads-example-" .. count .. ".nupp")
      assertEq(#result.errors, 0,
         "syntax errors in overload guide example " .. count)

      local actual = {}
      for _, diag in ipairs(check.check(result,
         "overloads-example-" .. count .. ".nupp", env, {strict = true})) do
         if diag.severity == "error" then
            actual[#actual + 1] = diag.code
         end
      end
      assertEq(table.concat(actual, " "), expected,
         "diagnostics in overload guide example " .. count .. "\n" .. source)
   end

   assert(count >= 15, "the overload guide should remain example-rich")
end

return M
