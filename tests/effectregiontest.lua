-- Allocation- and raising-free checked regions and their observed module sidecars.
local parser = require("nupp.compiler.parser")
local check = require("fragment")
local envMod = require("nupp.compiler.env")
local incremental = require("nupp.compiler.incremental")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))

local function assertEq(got, want, label)
   if got ~= want then
      error(("%s:\n  want: %s\n  got:  %s"):format(label or "mismatch",
         tostring(want), tostring(got)), 2)
   end
end

local function refusals(src)
   local parsed = parser.parse(src, "effect-region.g.nupp")
   assertEq(#parsed.errors, 0, "syntax")
   local diags = check.check(parsed, "effect-region.g.nupp", envMod.new(HERE))
   local found = {}
   for _, diag in ipairs(diags) do
      if diag.code == "NUPP2710" or diag.code == "NUPP2711" then
         found[#found + 1] = diag
      end
   end
   return found, parsed
end

local M = {}

function M.sameFileCallsUseTheExistingSummary()
   local found = refusals(table.concat({
      "local function quiet(): nil local n = 1 end",
      "local function allocates(): nil local t = {} end",
      "local function raises(): nil error('bad') end",
      "noalloc do quiet(); allocates() end",
      "noraise do quiet(); raises() end",
   }, "\n"))
   assertEq(#found, 2, "one refusal per positive effect")
   assertEq(found[1].code, "NUPP2710", "allocation diagnostic")
   assertEq(found[2].code, "NUPP2711", "raising diagnostic")
end

function M.directOperationsAreCheckedAndRegionsErase()
   local found, parsed = refusals("noalloc do local t = {} end")
   assertEq(#found, 1, "table construction is an allocation")
   local generated = require("nupp.compiler.gen").generate(parsed, "effect-region.g.nupp")
   assert(generated:find("do", 1, true), "region emits a block")
   assert(not generated:find("noalloc", 1, true), "no runtime guard remains")
end

function M.fixedWidthScalarOperationsSatisfyBothRegions()
   local found = refusals(table.concat({
      "noalloc do local x = nupp.math.u32.mul(0xffffffff, 3) end",
      "noraise do local y = nupp.math.f32.fma(1.0, 2.0, 3.0) end",
   }, "\n"))
   assertEq(#found, 0, "fixed-width scalar calls have modeled negative effects")
end

function M.aCheckedRangeDischargesMatchingSpanBoundsOnly()
   local found = refusals(table.concat({
      "local span = require('nupp.span')",
      "local struct Value n: integer end",
      "const storage = carray(Value, 4)",
      "const values = span.fromCarray(storage, 4)",
      "const rows = span.range(1, 4, values)",
      "for i = rows.first, rows.last do",
      "   noalloc do local value = values:get(i) end",
      "   noraise do local value = values:get(i) end",
      "end",
      "noraise do local value = values:get(1) end",
   }, "\n"))
   assertEq(#found, 1, "only the access outside the dominated loop can raise")
   assertEq(found[1].code, "NUPP2711")
end

function M.rangeProofsRequireStableSpanIdentities()
   local found = refusals(table.concat({
      "local span = require('nupp.span')",
      "local struct Value n: integer end",
      "const storage = carray(Value, 2)",
      "local values = span.fromCarray(storage, 2)",
      "const rows = span.range(1, 2, values)",
      "for i = rows.first, rows.last do",
      "   noraise do local value = values:get(i) end",
      "end",
   }, "\n"))
   assertEq(#found, 1, "a rebindable span cannot carry a range proof")
end

function M.rangeProofsDoNotEnterNestedFunctions()
   local found = refusals(table.concat({
      "local span = require('nupp.span')",
      "local struct Value n: integer end",
      "const storage = carray(Value, 2)",
      "const values = span.fromCarray(storage, 2)",
      "const rows = span.range(1, 2, values)",
      "for i = rows.first, rows.last do",
      "   local callback = function(): nil",
      "      noraise do local value = values:get(i) end",
      "   end",
      "end",
   }, "\n"))
   assertEq(#found, 1, "a closure cannot inherit its enclosing loop's proof")
   assertEq(found[1].code, "NUPP2711")
end

function M.unknownCallbacksAndForeignCallsNeedTrustedContracts()
   local found = refusals(table.concat({
      "local function invoke(callback: function()): nil",
      "   noalloc do callback() end",
      "   noraise do callback() end",
      "end",
      "cdef function opaque(): nil",
      "noalloc do opaque() end",
      "noraise do opaque() end",
   }, "\n"))
   assertEq(#found, 4, "unknown callbacks and uncontracted C fail both proofs")
end

function M.automaticCleanupParticipatesInTheRaisingSummary()
   local found = refusals(table.concat({
      "local record Resource end",
      "@effects(yields = false)",
      "local function close(takes value: Resource): nil error('close') end",
      "local function open(): affine(Resource, close) return new Resource() end",
      "local function use(): nil local value = open() end",
      "noraise do use() end",
   }, "\n"))
   assertEq(#found, 1, "the implicit close keeps use from being noRaise")
   assert(#(found[1].related or {}) > 0, "the diagnostic carries a call chain")
end

local PROVIDER = table.concat({
   "local M = {}",
   "function M.quiet(): nil local n = 1 end",
   "function M.allocates(): nil local t = {} end",
   "function M.raises(): nil error('bad') end",
   "return M",
}, "\n")

local function withProject(consumer, fn)
   local dir = os.tmpname()
   os.remove(dir)
   assert(os.execute("mkdir -p '" .. dir .. "'"))
   local depPath, mainPath = dir .. "/dep.g.nupp", dir .. "/main.g.nupp"
   local function write(path, text)
      local f = assert(io.open(path, "w")); f:write(text); f:close()
   end
   write(depPath, PROVIDER)
   write(mainPath, consumer)
   local inc = incremental.new(dir, {cache = false})
   local ok, err = pcall(fn, inc, depPath, mainPath)
   os.execute("rm -rf '" .. dir .. "'")
   if not ok then error(err, 0) end
end

function M.importsObserveOnlyTheExactFactsTheyUse()
   withProject(table.concat({
      "local D = require('dep')",
      "noalloc do D.quiet(); D.allocates() end",
      "noraise do D.quiet(); D.raises() end",
   }, "\n"), function(inc, _, mainPath)
      local result = inc.checkFile(mainPath)
      local found = {}
      for _, diag in ipairs(result.diags) do
         if diag.code == "NUPP2710" or diag.code == "NUPP2711" then found[#found + 1] = diag end
      end
      assertEq(#found, 2, "only unsafe imported calls fail")
   end)
end

function M.gainingAGuaranteeInvalidatesARejectedObservation()
   withProject("local D = require('dep')\nnoalloc do D.allocates() end", function(inc, depPath, mainPath)
      local before = inc.checkFile(mainPath)
      assertEq(before.diags[1] and before.diags[1].code, "NUPP2710", "initial refusal")
      local cold = inc.q.stats.checkModule
      inc.changeDocument(depPath, PROVIDER:gsub("local t = {}", "local n = 1"))
      local after = inc.checkFile(mainPath)
      assertEq(#after.diags, 0, "the absent observation becomes present: "
         .. tostring(after.diags[1] and after.diags[1].code) .. " "
         .. tostring(after.diags[1] and after.diags[1].msg))
      assertEq(inc.q.stats.checkModule, cold + 2, "provider and observer recheck")
   end)
end

function M.unobservingDependantsIgnoreBodyOnlyGuaranteeChanges()
   withProject("local D = require('dep')\nlocal f = D.allocates", function(inc, depPath, mainPath)
      inc.checkFile(mainPath)
      local cold = inc.q.stats.checkModule
      inc.changeDocument(depPath, PROVIDER:gsub("local t = {}", "local n = 1"))
      inc.checkFile(mainPath)
      assertEq(inc.q.stats.checkModule, cold + 1, "only provider rechecks")
   end)
end

return M
