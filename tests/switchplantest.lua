local parser = require("nupp.compiler.parser")
local check = require("fragment")
local switchplan = require("nupp.compiler.switchplan")

local M = {}

local function assertEq(got, want, label)
   if got ~= want then
      error(("%s:\n  want: %s\n  got:  %s"):format(label or "mismatch",
         tostring(want), tostring(got)), 2)
   end
end

local function findSwitch(node)
   if not node or node.kind == nil then return nil end
   if node.kind == "switchExpr" then return node end
   for _, child in ipairs(node) do
      if type(child) == "table" and child.kind then
         local found = findSwitch(child)
         if found then return found end
      end
   end
end

local function sourceFor(keys, kind, resultFor)
   local lines = {
      kind == "string" and "local selector: string = 'k1'" or
         "local selector: number = 1",
      "local selected = switch selector do",
   }
   for index, key in ipairs(keys) do
      local spelling = kind == "string" and string.format("%q", key) or
         tostring(key)
      lines[#lines + 1] = ("   case %s -> %s"):format(spelling,
         resultFor and resultFor(index) or tostring(index))
   end
   lines[#lines + 1] = "   else -> 0"
   lines[#lines + 1] = "end"
   lines[#lines + 1] = "return selected"
   return table.concat(lines, "\n")
end

local function plan(source, coverage)
   local result = parser.parse(source, "switch-plan-test.g.nupp")
   assertEq(#result.errors, 0, "planner source parses")
   local diagnostics = check.check(result, "switch-plan-test.g.nupp")
   assertEq(#diagnostics, 0, diagnostics[1] and diagnostics[1].message or
      "planner source checks")
   local node = assert(findSwitch(result.root), "switch node")
   return switchplan.regular(node, coverage), node
end

local function integers(first, count, stride)
   local values = {}
   for index = 1, count do
      values[index] = first + (index - 1) * (stride or 1)
   end
   return values
end

local function strings(count)
   local values = {}
   for index = 1, count do values[index] = "k" .. index end
   return values
end

function M.denseIntegerThresholdIsExplicit()
   assertEq(plan(sourceFor(integers(1, 3), "number")).tag,
      "OrderedBranches", "below dense threshold")
   assertEq(plan(sourceFor(integers(1, 4), "number")).tag,
      "DenseIntegerMap", "at dense threshold")
end

function M.stringAndSparseFloorsAreExplicit()
   assertEq(plan(sourceFor(strings(7), "string")).tag,
      "OrderedBranches", "below string floor")
   assertEq(plan(sourceFor(strings(8), "string")).tag,
      "StringMap", "at string floor")
   assertEq(plan(sourceFor(integers(1, 15, 100), "number")).tag,
      "OrderedBranches", "below sparse floor")
   assertEq(plan(sourceFor(integers(1, 16, 100), "number")).tag,
      "SparseIntegerMap", "at sparse floor")
end

function M.coverageAlwaysKeepsOrderedConditions()
   local selected = plan(sourceFor(integers(1, 64), "number"), true)
   assertEq(selected.tag, "OrderedBranches")
   assertEq(selected.reason, "coverage needs one condition for every case")
end

function M.dynamicResultsAreNotMapped()
   local selected = plan(table.concat({
      "local selector: number = 1",
      "local selected = switch selector do",
      "   case 1 -> tostring(selector)",
      "   case 2 -> 'two'",
      "   case 3 -> 'three'",
      "   case 4 -> 'four'",
      "   else -> 'other'",
      "end",
      "return selected",
   }, "\n"))
   assertEq(selected.tag, "OrderedBranches")
   assertEq(selected.reason, "an arm result is not one inert scalar")
end

function M.dynamicFallbacksAreNotMapped()
   local selected = plan((sourceFor(strings(8), "string", function(index)
      return string.format("%q", "v" .. index)
   end):gsub("else %-> 0", "else -> tostring(#selector)")))
   assertEq(selected.tag, "OrderedBranches")
   assertEq(selected.reason, "the fallback is not one inert scalar")
end

function M.nilResultsAreRecordedForConditionalSentinels()
   local selected = plan(sourceFor(strings(8), "string", function(index)
      return index == 3 and "nil" or string.format("%q", "v" .. index)
   end))
   assertEq(selected.tag, "StringMap")
   assertEq(selected.facts.nilResult, true)
end

function M.nativePlanRequiresAnEstablishedWidth()
   assertEq(switchplan.native("f64").tag, "OrderedBranches")
   assertEq(switchplan.native("i32").tag, "NativeIntegerSwitch")
   assertEq(switchplan.native("u32").tag, "NativeIntegerSwitch")
end

return M
