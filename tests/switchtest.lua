local parser = require("nupp.compiler.parser")
local check = require("fragment")
local gen = require("nupp.compiler.gen")

local function assertEq(got, want, label)
   if got ~= want then
      error(("%s:\n  want: %s\n  got:  %s"):format(label or "mismatch",
         tostring(want), tostring(got)), 2)
   end
end

local function checked(source)
   local result = parser.parse(source, "switch-test.g.nupp")
   assertEq(#result.errors, 0, result.errors[1] and result.errors[1].msg or
      "switch source parses")
   local diagnostics = check.check(result, "switch-test.g.nupp")
   return result, diagnostics
end

local function diagnosticCodes(source)
   local _, diagnostics = checked(source)
   local codes = {}
   for _, diagnostic in ipairs(diagnostics) do
      codes[#codes + 1] = diagnostic.code
   end
   return table.concat(codes, " "), diagnostics
end

local function run(source)
   local result, diagnostics = checked(source)
   assertEq(#diagnostics, 0, diagnostics[1] and diagnostics[1].message or
      "switch source checks")
   local code, lowering = gen.generate(result, "switch-test.g.nupp")
   assertEq(#lowering, 0, lowering[1] and lowering[1].msg or
      "switch source lowers")
   local chunk, failure = loadstring(code, "@switch_test")
   if not chunk then
      error("generated switch code does not load: " .. tostring(failure) ..
         "\n---\n" .. code, 2)
   end
   return chunk()
end

local function generate(source, coverage)
   local result, diagnostics = checked(source)
   assertEq(#diagnostics, 0, diagnostics[1] and diagnostics[1].message or
      "switch source checks")
   local code, lowering = gen.generate(result, "switch-test.g.nupp", coverage)
   assertEq(#lowering, 0, lowering[1] and lowering[1].msg or
      "switch source lowers")
   return code, result
end

local function loweringCodes(source)
   local result, diagnostics = checked(source)
   assertEq(#diagnostics, 0, diagnostics[1] and diagnostics[1].message or
      "switch source checks before lowering")
   local _, lowering = gen.generate(result, "switch-test.g.nupp")
   local codes = {}
   for _, diagnostic in ipairs(lowering) do
      codes[#codes + 1] = diagnostic.code
   end
   return table.concat(codes, " ")
end

local M = {}

function M.staticCasesAreExhaustiveAndRun()
   local first, second, third = run(table.concat({
      "local type Status = 200 | 301 | 302",
      "local function label(status: Status): string",
      "   return switch status do",
      "      case 200 -> 'ok'",
      "      case 301, 302 -> 'redirect'",
      "   end",
      "end",
      "return label(200), label(301), label(302)",
   }, "\n"))
   assertEq(first, "ok")
   assertEq(second, "redirect")
   assertEq(third, "redirect")
end

function M.typeBindingsAndDestructuringRun()
   local circle, text = run(table.concat({
      "local record Circle",
      "   radius: integer",
      "end",
      "local function measure(value: Circle | string): integer",
      "   return switch value do",
      "      case is Circle as whole {radius} -> radius + whole.radius",
      "      case is string as contents -> #contents",
      "   end",
      "end",
      "return measure(new Circle(radius = 4)), measure('abc')",
   }, "\n"))
   assertEq(circle, 8)
   assertEq(text, 3)
end

function M.blockArmsYieldWithoutChangingReturn()
   local one, other, early = run(table.concat({
      "local function describe(value: integer): string",
      "   return switch value do",
      "      case 0 -> do",
      "         return 'early'",
      "      end",
      "      case 1 -> do",
      "         local answer = 'one'",
      "         yield answer",
      "      end",
      "      else -> 'other'",
      "   end",
      "end",
      "return describe(1), describe(2), describe(0)",
   }, "\n"))
   assertEq(one, "one")
   assertEq(other, "other")
   assertEq(early, "early")
end

function M.staticExpressionArmsWorkAtComptime()
   local selected = run(table.concat({
      "const selected: string = comptime do",
      "   local code = 302",
      "   return switch code do",
      "      case 200 -> 'ok'",
      "      case 301, 302 -> 'redirect'",
      "      else -> 'other'",
      "   end",
      "end",
      "return selected",
   }, "\n"))
   assertEq(selected, "redirect")
end

function M.liftingPreservesEagerEvaluationOrder()
   local order, value = run(table.concat({
      "local events: {string} = {}",
      "local function mark(name: string, value: integer): integer",
      "   events[#events + 1] = name",
      "   return value",
      "end",
      "local function add(a: integer, b: integer, c: integer): integer",
      "   return a + b + c",
      "end",
      "local value = add(mark('left', 1), switch mark('selector', 2) do",
      "   case 2 -> mark('arm', 2)",
      "   else -> 0",
      "end, mark('right', 3))",
      "return table.concat(events, ','), value",
   }, "\n"))
   assertEq(order, "left,selector,arm,right")
   assertEq(value, 6)
end

function M.liftingPreservesAssignmentTargetOrder()
   local order, value = run(table.concat({
      "local events: {string} = {}",
      "local row = {value = 0}",
      "local function target(): {value: integer}",
      "   events[#events + 1] = 'target'",
      "   return row",
      "end",
      "local function selector(): integer",
      "   events[#events + 1] = 'selector'",
      "   return 1",
      "end",
      "target().value = switch selector() do",
      "   case 1 -> 9",
      "   else -> 0",
      "end",
      "return table.concat(events, ','), row.value",
   }, "\n"))
   assertEq(order, "target,selector")
   assertEq(value, 9)
end

function M.yieldCompletesCleanupBeforeTheSwitchContinues()
   local value, events = run(table.concat({
      "local events = ''",
      "local record Resource",
      "   name: string",
      "end",
      "local function closeResource(takes value: Resource): nil",
      "   events = events .. 'close'",
      "end",
      "local function openResource(): affine(Resource, closeResource)",
      "   return new Resource(name = 'selected')",
      "end",
      "local value = switch 1 do",
      "   case 1 -> do",
      "      with resource = openResource() do",
      "         yield resource.name",
      "      end",
      "   end",
      "end",
      "events = events .. ',after'",
      "return value, events",
   }, "\n"))
   assertEq(value, "selected")
   assertEq(events, "close,after")
end

function M.nestedSwitchesStayAtTheirStatementBoundary()
   local order, value = run(table.concat({
      "local events: {string} = {}",
      "local function mark(name: string, value: integer): integer",
      "   events[#events + 1] = name",
      "   return value",
      "end",
      "local value = switch mark('outer', 1) do",
      "   case 1 -> do",
      "      mark('before-inner', 0)",
      "      local inner = switch mark('inner', 2) do",
      "         case 2 -> 8",
      "         else -> 0",
      "      end",
      "      yield inner",
      "   end",
      "   else -> 0",
      "end",
      "return table.concat(events, ','), value",
   }, "\n"))
   assertEq(order, "outer,before-inner,inner")
   assertEq(value, 8)
end

function M.lazyPlacementIsRejected()
   local codes = loweringCodes(table.concat({
      "local ready = true",
      "local selector: number = 1",
      "local value = ready and switch selector do",
      "   case 1 -> 1",
      "   else -> 0",
      "end",
   }, "\n"))
   assertEq(codes, "NUPP2142")
end

function M.coverageCountsTestsAndSelectedArmRegions()
   local result, diagnostics = checked(table.concat({
      "local selector: number = 1",
      "local value = switch selector do",
      "   case 1 -> 'one'",
      "   case 2 -> 'two'",
      "   else -> 'other'",
      "end",
      "return value",
   }, "\n"))
   assertEq(#diagnostics, 0)
   local _, lowering, coverage = gen.generate(result, "switch-coverage.g.nupp", true)
   assertEq(#lowering, 0)
   local branches, regions = 0, 0
   for _, site in ipairs(coverage.sites) do
      if site.kind == "branch" then branches = branches + 1 end
      if site.kind == "statement" and site.line >= 3 and site.line <= 5 then
         regions = regions + 1
      end
   end
   assertEq(branches, 2)
   assertEq(regions, 3)
end

function M.denseIntegerMapsHandleEveryKindOfMiss()
   local one, four, fraction, negative, far, nan, infinity = run(table.concat({
      "local function classify(value: number): string",
      "   return switch value do",
      "      case 1 -> 'one'",
      "      case 2 -> 'two'",
      "      case 3 -> 'three'",
      "      case 4 -> 'four'",
      "      else -> 'miss'",
      "   end",
      "end",
      "return classify(1), classify(4), classify(1.5), classify(-1),",
      "   classify(1000), classify(0 / 0), classify(math.huge)",
   }, "\n"))
   assertEq(one, "one")
   assertEq(four, "four")
   assertEq(fraction, "miss")
   assertEq(negative, "miss")
   assertEq(far, "miss")
   assertEq(nan, "miss")
   assertEq(infinity, "miss")
end

function M.stringAndSparseMapsHandleHitsAndMisses()
   local lines = {
      "local function word(value: string): string?",
      "   return switch value do",
   }
   for index = 1, 8 do
      lines[#lines + 1] = ("      case 'k%d' -> %s"):format(index,
         index == 3 and "nil" or ("'v%d'"):format(index))
   end
   lines[#lines + 1] = "      else -> 'miss'"
   lines[#lines + 1] = "   end"
   lines[#lines + 1] = "end"
   lines[#lines + 1] = "local function sparse(value: number): integer"
   lines[#lines + 1] = "   return switch value do"
   for index = 1, 16 do
      lines[#lines + 1] = ("      case %d -> %d"):format(index * 100 + 1, index)
   end
   lines[#lines + 1] = "      else -> 0"
   lines[#lines + 1] = "   end"
   lines[#lines + 1] = "end"
   lines[#lines + 1] = "return word('k1'), word('k3'), word('no'), sparse(1601), sparse(2)"
   local first, nilResult, missing, sparseHit, sparseMiss = run(table.concat(lines, "\n"))
   assertEq(first, "v1")
   assertEq(nilResult, nil)
   assertEq(missing, "miss")
   assertEq(sparseHit, 16)
   assertEq(sparseMiss, 0)
end

function M.sentinelAndCoverageAreConditional()
   local source = table.concat({
      "local selector: string = 'k1'",
      "local selected = switch selector do",
      "   case 'k1' -> 'v1'",
      "   case 'k2' -> 'v2'",
      "   case 'k3' -> 'v3'",
      "   case 'k4' -> 'v4'",
      "   case 'k5' -> 'v5'",
      "   case 'k6' -> 'v6'",
      "   case 'k7' -> 'v7'",
      "   case 'k8' -> 'v8'",
      "   else -> 'miss'",
      "end",
      "return selected",
   }, "\n")
   local code = generate(source)
   assert(code:find("__nuppSwitchMap", 1, true), code)
   assertEq(code:find("__nuppSwitchNil", 1, true), nil,
      "a map without a nil result needs no sentinel")

   local covered = generate(source, true)
   assertEq(covered:find("__nuppSwitchMap", 1, true), nil,
      "coverage keeps per-case conditions")
end

function M.recordIdentityGuardUsesTheCheckerProof()
   local safe = table.concat({
      "local record First value: integer end",
      "local record Second value: integer end",
      "local function get(value: First | Second): integer",
      "   return switch value do",
      "      case is First {value} -> value",
      "      case is Second {value} -> value",
      "   end",
      "end",
      "return get(new First(value = 1))",
   }, "\n")
   local safeCode = generate(safe)
   assert(safeCode:find("=getmetatable(", 1, true), safeCode)
   assertEq(safeCode:find("?.__index", 1, true), nil,
      "a record-only residue needs no safe guard")

   local open = table.concat({
      "local record Item value: integer end",
      "local function get(value: Item?): integer",
      "   return switch value do",
      "      case is Item {value} -> value",
      "      case nil -> 0",
      "   end",
      "end",
      "return get(nil)",
   }, "\n")
   local openCode = generate(open)
   assert(openCode:find("?.__index", 1, true), openCode)
end

function M.manyMapsSpillBehindOnePrologueUpvalue()
   local lines = {}
   for functionIndex = 1, 34 do
      lines[#lines + 1] = ("local function f%d(value: string): integer%s"):format(
         functionIndex, functionIndex == 34 and "?" or "")
      lines[#lines + 1] = "   return switch value do"
      for caseIndex = 1, 8 do
         local result = functionIndex == 34 and caseIndex == 3 and "nil" or
            tostring(functionIndex * 100 + caseIndex)
         lines[#lines + 1] = ("      case 'f%d-k%d' -> %s"):format(
            functionIndex, caseIndex, result)
      end
      lines[#lines + 1] = "      else -> 0"
      lines[#lines + 1] = "   end"
      lines[#lines + 1] = "end"
   end
   lines[#lines + 1] = "return f1('f1-k1'), f34('f34-k8'), f34('f34-k3')"
   local code = generate(table.concat(lines, "\n"))
   assert(code:find("__nuppSwitchConstants", 1, true), code)
   local chunk = assert(loadstring(code, "@switch_spill"))
   local first, last, nilResult = chunk()
   assertEq(first, 101)
   assertEq(last, 3408)
   assertEq(nilResult, nil)
end

function M.switchDiagnosticsAreSpecific()
   local missing = diagnosticCodes(table.concat({
      "local type Status = 'on' | 'off'",
      "local status: Status = 'on'",
      "local value = switch status do case 'on' -> 1 end",
   }, "\n"))
   assertEq(missing, "NUPP2140")

   local duplicate = diagnosticCodes(
      "local selector: number = 1\nlocal value = switch selector do case 1, 1.0 -> 1 else -> 0 end")
   assertEq(duplicate, "NUPP2138")

   local dynamic = diagnosticCodes(
      "local value = switch 2 do case 1 + 1 -> 1 else -> 0 end")
   assertEq(dynamic, "NUPP2137")

   local escaped = diagnosticCodes(
      [[local selector: string = "a"
local value = switch selector do case "\x61", "a" -> 1 else -> 0 end]])
   assertEq(escaped, "NUPP2138")

   local fallthrough = diagnosticCodes(table.concat({
      "local value = switch 1 do",
      "   else -> do",
      "      local answer = 1",
      "   end",
      "end",
   }, "\n"))
   assertEq(fallthrough, "NUPP2141")

   local never = diagnosticCodes(table.concat({
      "local function fail(): string",
      "   return switch 1 do",
      "      case 1 -> do",
      "         error('no value')",
      "      end",
      "   end",
      "end",
   }, "\n"))
   assertEq(never, "")
end

return M
