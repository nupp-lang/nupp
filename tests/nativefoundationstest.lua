-- Whole-plan acceptance with native compilation absent: one ordinary system-shaped
-- source exercises every independent foundation and answers what it computed.
local parser = require("nupp.compiler.syntax.parser")
local check = require("fragment")
local envMod = require("nupp.compiler.project.env")
local program = require("program")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local ROOT = HERE .. "/.."

local function read(path)
   local file = assert(io.open(path, "rb"))
   local text = file:read("*a")
   file:close()
   return text
end

local M = {}

function M.ordinaryTecsShapedSourceRuns()
   local path = HERE .. "/fixtures/native_foundations.nupp"
   local parsed = parser.parse(read(path), path)
   assert(#parsed.errors == 0, parsed.errors[1] and parsed.errors[1].msg or "parse")
   local diagnostics = check.check(parsed, path, envMod.new(ROOT, {cache = false}),
      {moduleName = "tests.fixtures.native_foundations"})
   for _, diagnostic in ipairs(diagnostics) do
      assert(diagnostic.severity ~= "error", diagnostic.code .. ": " .. diagnostic.msg)
   end
   local module = program.run(parsed, "tests.fixtures.native_foundations", path)

   local x, flags = module.run()
   -- fma(0, 2, binary32(0.1)) is binary32(0.1) exactly.
   assert(x == 0.10000000149011612, "binary32 result: " .. tostring(x))
   assert(tonumber(flags) == 8, "the checked slice updates its last element")
end

return M
