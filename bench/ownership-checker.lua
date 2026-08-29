-- Checker throughput and summary gate for the ownership capability model.
--
-- Run from the repository root after building the compiler. Pass --mapped as
-- the third argument to include the new identity-mapped result path; omit it
-- when comparing with a compiler that predates that feature:
--   NUPP_NATIVE_LIBRARY="$PWD/build/lib/libnupp_native_dev.dylib" \
--   LUA_PATH="$PWD/build/?.lua;$PWD/.rocks/share/lua/5.1/?.lua;;" \
--   LUA_CPATH="$PWD/.rocks/lib/lua/5.1/?.so;;" \
--   luajit bench/ownership-checker.lua 15 1000 [--mapped]
--
-- This benchmark keeps runtime lowering out of the measurement. It stresses wide
-- place paths, exact and unknown indexes, identity-mapped preservation, and stable
-- public summaries. Compare the printed median and peak KiB with the merge base on
-- the same machine; plans 047-050 permit 5% warm-check, 10% cold/full-check, summary,
-- and peak-memory regressions.

local parser = require("nupp.compiler.parser")
local check = require("nupp.compiler.check")
local envMod = require("nupp.compiler.env")
local modules = require("nupp.compiler.build.modules")
local project = require("nupp.compiler.build.project")

local ROUNDS = tonumber(arg[1]) or 15
local WIDTH = tonumber(arg[2]) or 1000
local MAPPED = arg[3] == "--mapped"

local function source(bodyDelta, publicDelta)
   local lines = {
      "local M = {}",
      "local record Wide",
   }
   for index = 1, WIDTH do
      lines[#lines + 1] = ("   f%d: table"):format(index)
   end
   lines[#lines + 1] = "end"
   lines[#lines + 1] = "local record Box<T> value: T end"
   if MAPPED then
      lines[#lines + 1] = "local type View<T> = {readonly [K in keyof T]: T.[K]}"
   end
   local resultType = MAPPED and "View<Box<T>>" or "Box<T>"
   lines[#lines + 1] = "function M.box<T>(takes value: T): " .. resultType .. " preserves value"
   lines[#lines + 1] = "   return new Box(value = value)"
   lines[#lines + 1] = "end"
   lines[#lines + 1] = "local function pair(exclusive left: table, exclusive right: table): nil end"
   lines[#lines + 1] = "function M.exercise(value: Wide, indexes: {integer}): nil"
   for index = 1, WIDTH - 1, 2 do
      lines[#lines + 1] = ("   pair(value.f%d, value.f%d)"):format(index, index + 1)
   end
   if MAPPED then
      local midpoint = math.max(1, math.floor(WIDTH / 2))
      lines[#lines + 1] = "   unsafe do"
      lines[#lines + 1] = ("      local left = nupp.region(value, value.f1, 1, %d)"):format(midpoint)
      lines[#lines + 1] = ("      local right = nupp.region(value, value.f2, %d, %d)"):format(
         midpoint + 1, WIDTH)
      lines[#lines + 1] = "      pair(left, right)"
      lines[#lines + 1] = "   end"
   end
   lines[#lines + 1] = "   for index = 1, #indexes do"
   lines[#lines + 1] = "      local current = indexes[index]"
   if MAPPED then
      lines[#lines + 1] = "      unsafe do"
      lines[#lines + 1] = "         local region = nupp.region(value, value.f3, current, current)"
      lines[#lines + 1] = "         print(region)"
      lines[#lines + 1] = "      end"
   else
      lines[#lines + 1] = "      print(current)"
   end
   lines[#lines + 1] = "   end"
   lines[#lines + 1] = "   " .. (bodyDelta or "print(value.f1)")
   lines[#lines + 1] = "end"
   if publicDelta then lines[#lines + 1] = publicDelta end
   lines[#lines + 1] = "return M"
   return table.concat(lines, "\n")
end

local function write(path, contents)
   local file = assert(io.open(path, "wb"))
   file:write(contents)
   file:close()
end

local function measured(action)
   local started = os.clock()
   local result = action()
   return result, (os.clock() - started) * 1000
end

local function medianOf(values)
   table.sort(values)
   return values[math.floor((#values + 1) / 2)]
end

local function compile(text)
   local tree = parser.parse(text, "ownership-benchmark.g.nupp")
   assert(#tree.errors == 0, tree.errors[1] and tree.errors[1].msg)
   local diagnostics, moduleType = check.check(
      tree, "ownership-benchmark.g.nupp", envMod.new("."))
   for _, diagnostic in ipairs(diagnostics) do
      assert(not diagnostic.code:match("^NUPP[123]"), diagnostic.code .. ": " .. diagnostic.msg)
   end
   return moduleType
end

local sample = source()
compile(sample)
collectgarbage("collect")
local floor = collectgarbage("count")
local times, peak = {}, floor
for round = 1, ROUNDS do
   local started = os.clock()
   local moduleType = compile(sample)
   times[round] = os.clock() - started
   peak = math.max(peak, collectgarbage("count"))
   assert(moduleType)
   collectgarbage("collect")
end
table.sort(times)
local median = medianOf(times)

local original = compile(sample)
local privateEdit = compile(source("print(value.f2)"))
local originalSummary = modules.typeFingerprint(original)
local privateSummary = modules.typeFingerprint(privateEdit)
assert(originalSummary == privateSummary, "a private body edit changed the public summary")

local projectRoot = os.tmpname()
os.remove(projectRoot)
assert(os.execute("mkdir -p '" .. projectRoot .. "/src'") == 0)
write(projectRoot .. "/nupp.lua", [[
return {
   include = {"src"},
   build = {outDir = "out", entries = {"main"}},
}
]])
write(projectRoot .. "/src/lib.nupp", sample)
write(projectRoot .. "/src/main.nupp", "local lib = require('lib')\nreturn lib\n")

local function checkProject()
   local stats = {}
   local diagnostics = {}
   assert(project.check(projectRoot, {stats = stats, diagnostics = diagnostics}) == 0,
      diagnostics[1] and diagnostics[1].msg)
   return stats
end

local cold, coldMs = measured(checkProject)
assert(cold.checkedModules == 2, "the cold project check did not check both modules")

local warmTimes = {}
for round = 1, ROUNDS do
   local warm
   warm, warmTimes[round] = measured(checkProject)
   assert(warm.checkedModules == 0 and warm.reusedModules == 2,
      "unexpected warm project invalidation counts")
end

local privateTimes = {}
local privateStats
for round = 1, ROUNDS do
   local field = round % 2 == 0 and "f2" or "f3"
   write(projectRoot .. "/src/lib.nupp", source("print(value." .. field .. ")"))
   privateStats, privateTimes[round] = measured(checkProject)
   assert(privateStats.checkedModules == 1 and privateStats.reusedModules == 1,
      "a private edit escaped its module")
end

local publicTimes = {}
local publicStats
for round = 1, ROUNDS do
   local declaration = round % 2 == 0
      and "function M.version(): string return 'v2' end"
      or "function M.version(): number return 2 end"
   write(projectRoot .. "/src/lib.nupp", source("print(value.f2)", declaration))
   publicStats, publicTimes[round] = measured(checkProject)
   assert(publicStats.checkedModules == 2 and publicStats.reusedModules == 0,
      "a public edit did not invalidate its dependent")
end
assert(os.execute("rm -rf '" .. projectRoot .. "'") == 0)

local warmMs = medianOf(warmTimes)
local privateMs = medianOf(privateTimes)
local publicMs = medianOf(publicTimes)

print(("ownership checker (%s): %d fields, %d rounds"):format(
   MAPPED and "mapped" or "compatible", WIDTH, ROUNDS))
print(("  median full check: %.3f ms"):format(median * 1000))
print(("  peak checker growth: %.1f KiB"):format(peak - floor))
print(("  public summary: %d bytes"):format(#originalSummary))
print("  private edit summary: unchanged")
print(("  cold project check: %.3f ms (%d checked)"):format(
   coldMs, cold.checkedModules))
print(("  median warm project check: %.3f ms (0 checked, 2 reused)"):format(warmMs))
print(("  private edit: %.3f ms (%d checked, %d reused)"):format(
   privateMs, privateStats.checkedModules, privateStats.reusedModules))
print(("  public edit: %.3f ms (%d checked, %d reused)"):format(
   publicMs, publicStats.checkedModules, publicStats.reusedModules))
