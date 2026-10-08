local testAssert = require("nupp.test")
-- Every Nupp fence in the overload guide is a complete checked program. Invalid
-- examples name their intended diagnostic in a leading `-- reports:` comment.
local parser = require("nupp.compiler.syntax.parser")
local check = require("fragment")
local envMod = require("nupp.compiler.project.env")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local ROOT = HERE .. "/.."
local env = envMod.new(ROOT)

local M = {}

function M.everyOverloadGuideExampleChecksAsDocumented()
   local file = assert(io.open(ROOT .. "/docs/learn/language/types/overloads.md", "rb"))
   local markdown = file:read("*a")
   file:close()
   markdown = markdown:gsub("\r\n?", "\n")

   local count = 0
   -- A fence may carry options, such as the `:refused` examplestest reads.
   for source in markdown:gmatch("```nupp[^\n]*\n(.-)\n```") do
      count = count + 1
      local expected = source:match("^%-%- reports: ([A-Z0-9, ]+)") or ""
      expected = expected:gsub(",", "")

      local result = parser.parse(source, "overloads-example-" .. count .. ".nupp")
      testAssert.equal(#result.errors, 0,
         "syntax errors in overload guide example " .. count)

      local actual = {}
      for _, diag in ipairs(check.check(result,
         "overloads-example-" .. count .. ".nupp", env, {strict = true})) do
         if diag.severity == "error" then
            actual[#actual + 1] = diag.code
         end
      end
      testAssert.equal(table.concat(actual, " "), expected,
         "diagnostics in overload guide example " .. count .. "\n" .. source)
   end

   assert(count >= 15, "the overload guide should remain example-rich")
end

return M
