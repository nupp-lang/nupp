local parser = require("compiler.parser")
local check = require("fragment")
local optimize = require("compiler.optimize")
local gen = require("compiler.gen")
local envMod = require("compiler.env")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local env = envMod.new(HERE .. "/..")

local function assertEq(got, want, label)
   if got ~= want then
      error(("%s:\n  want: %s\n  got:  %s"):format(label or "mismatch",
         tostring(want), tostring(got)), 2)
   end
end

local function compile(src, level)
   local result = parser.parse(src, "test.g.nupp")
   assertEq(#result.errors, 0, "syntax errors")
   local diags = check.check(result, "test.g.nupp", env)
   assertEq(#diags, 0, "check diagnostics")
   optimize.run(result, {level = level or 0})
   local code, generatedDiags = gen.generate(result, "test")
   assertEq(#generatedDiags, 0, "generation diagnostics")
   return code
end

local function run(src, level)
   local code = compile(src, level)
   local chunk, err = loadstring(code, "@table_intrinsic_test")
   if not chunk then
      error("generated code does not load: " .. tostring(err)
         .. "\n---\n" .. code, 2)
   end
   return chunk()
end

local function occurrences(text, literal)
   local _, count = text:gsub(literal:gsub("(%W)", "%%%1"), "")
   return count
end

local M = {}

function M.injectsEachUsedTableBuiltinOnce()
   local src = table.concat({
      "local first = table.new(2, 0)",
      "local second = table.new(0, 2)",
      "table.clear(first)",
      "table.clear(second)",
      "return first, second",
   }, "\n")
   local code = compile(src)
   assertEq(occurrences(code, 'require("table.new")'), 1,
      "one table.new binding")
   assertEq(occurrences(code, 'require("table.clear")'), 1,
      "one table.clear binding")
   assert(code:find('const __nuppNew = require("table.new")', 1, true), code)
   assert(code:find('const __nuppClear = require("table.clear")', 1, true), code)
   local first, second = run(src)
   assertEq(next(first), nil, "first table was cleared")
   assertEq(next(second), nil, "second table was cleared")
end

function M.presizingSharesTheUserTableNewBinding()
   local code = compile(table.concat({
      "local sized = {}",
      "sized.left = 1",
      "sized.right = 2",
      "local explicit = table.new(1, 0)",
      "return sized, explicit",
   }, "\n"), 1)
   assertEq(occurrences(code, 'require("table.new")'), 1,
      "OPT-1 and source calls share one binding")
   assertEq(occurrences(code, "__nuppNew"), 3,
      "one declaration and two calls use the binding")
end

function M.tableIntrinsicsRemainIntrinsicAtOptimizationLevelOne()
   local src = table.concat({
      "local value = table.new(0, 1)",
      "table.clear(value)",
      "table.clear(value)",
      "return value",
   }, "\n")
   local code = compile(src, 1)
   assertEq(occurrences(code, 'require("table.new")'), 1,
      "optimized source keeps the table.new binding")
   assertEq(occurrences(code, 'require("table.clear")'), 1,
      "OPT-4 does not capture table.clear before it is loaded")
   assertEq(code:find("__nupp_call_", 1, true), nil,
      "table intrinsics bypass static-callable binding")
   assertEq(next(run(src, 1)), nil, "optimized intrinsic calls run")
end

function M.leavesAShadowedTableAlone()
   local src = table.concat({
      "local table = {",
      "   new = function() return 7 end,",
      "   clear = function() return 8 end,",
      "}",
      "return table.new(), table.clear()",
   }, "\n")
   local code = compile(src)
   assertEq(code:find('require("table.new")', 1, true), nil,
      "shadowed table.new is ordinary code")
   assertEq(code:find('require("table.clear")', 1, true), nil,
      "shadowed table.clear is ordinary code")
   local first, second = run(src)
   assertEq(first, 7, "shadowed new result")
   assertEq(second, 8, "shadowed clear result")
end

function M.generatedBindingsAvoidSourceNames()
   local src = table.concat({
      "local __nuppNew = 'new'",
      "local __nuppClear = 'clear'",
      "local value = table.new(0, 1)",
      "value.key = true",
      "table.clear(value)",
      "return __nuppNew, __nuppClear, next(value)",
   }, "\n")
   local code = compile(src)
   assertEq(code:find('const __nuppNew = require("table.new")', 1, true), nil,
      "table.new binding avoids the source name")
   assertEq(code:find('const __nuppClear = require("table.clear")', 1, true), nil,
      "table.clear binding avoids the source name")
   local first, second, remaining = run(src)
   assertEq(first, "new", "source new name survives")
   assertEq(second, "clear", "source clear name survives")
   assertEq(remaining, nil, "generated clear binding works")
end

function M.injectedBindingsPreserveLineCount()
   local src = "local value = table.new(0, 0)\ntable.clear(value)\nreturn value"
   local code = compile(src)
   local _, sourceLines = src:gsub("\n", "")
   local _, generatedLines = code:gsub("\n", "")
   assertEq(generatedLines, sourceLines + 1, "generated line count")
end

return M
