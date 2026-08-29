-- What a build says about itself while it runs and when it finishes.
--
-- Two halves, tested the two ways they are reachable: the reporter directly,
-- which is where the timeline arithmetic and the wording live, and `nupp build`
-- through the real binary, which is where the decision to say anything at all
-- is made. The second half matters most: a build has been quiet on success for
-- as long as there have been scripts reading its output, and the only reason
-- that is still true is that nothing is written unless somebody is watching.
local progress = require("nupp.compiler.build.progress")
local ansi = require("nupp.compiler.ansi")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
if not HERE:match("^/") then
   local p = assert(io.popen("pwd"))
   HERE = p:read("*l") .. "/" .. HERE
   p:close()
end
local NUPP = HERE .. "/../bin/nupp"

local function assertEq(got, want, label)
   if got ~= want then
      error(("%s:\n  want: %s\n  got:  %s"):format(label or "mismatch",
         tostring(want), tostring(got)), 2)
   end
end

local function tempDir()
   local dir = os.tmpname()
   os.remove(dir)
   assert(os.execute("mkdir -p '" .. dir .. "'") == 0)
   return dir
end

local function tempProject()
   local dir = tempDir()
   local files = {
      ["nupp.lua"] = 'return {include = {"."}, build = {targets = {app = {'
         .. 'entries = {"main"}, outDir = "out"}}, default = "app"}}\n',
      ["lib.nupp"] = "local m = {}\nfunction m.double(n: number): number\n"
         .. "    return n * 2\nend\nreturn m\n",
      ["main.nupp"] = "local lib = require('lib')\nprint(lib.double(21))\n",
   }
   for name, text in pairs(files) do
      local file = assert(io.open(dir .. "/" .. name, "wb"))
      file:write(text)
      file:close()
   end
   return dir
end

local function constProject()
   local dir = tempDir()
   local files = {
      ["nupp.lua"] = 'return {include = {"."}, build = {targets = {app = {'
         .. 'entries = {"main"}, outDir = "out", optimize = 1}}, default = "app"}}\n',
      ["lib.nupp"] = table.concat({
         "local function accumulate<const N: integer>(value: number, count: N): number",
         "    local total = value",
         "    for offset = 1, count as integer do total = total + offset end",
         "    return total",
         "end",
         "return {accumulate = accumulate}",
      }, "\n"),
      ["main.nupp"] = "local lib = require('lib')\nreturn lib.accumulate(10.0, 4)\n",
   }
   for name, text in pairs(files) do
      local file = assert(io.open(dir .. "/" .. name, "wb"))
      file:write(text)
      file:close()
   end
   return dir
end

-- Standard output and standard error kept apart, because which one a thing is
-- written to is the whole question here: a build's report goes to stderr so that
-- `--json` on stdout stays a document a program can read.
local function run(dir, arguments, env)
   local errPath = os.tmpname()
   local command = ("cd '%s' && %s'%s' %s 2>'%s'")
      :format(dir, env or "", NUPP, arguments, errPath)
   local pipe = assert(io.popen(command))
   local out = pipe:read("*a")
   pipe:close()
   local errFile = assert(io.open(errPath, "rb"))
   local err = errFile:read("*a")
   errFile:close()
   os.remove(errPath)
   return out, err
end

-- A reporter writing somewhere the test can read. A file is not a terminal, so
-- it never rewrites a line in place, which is what makes the output comparable.
local function reporterTo(path, mode)
   local stream = assert(io.open(path, "wb"))
   return progress.new(mode, stream), stream
end

local function readAll(path)
   local file = assert(io.open(path, "rb"))
   local text = file:read("*a")
   file:close()
   return text
end

local M = {}

function M.durationsReadAsMillisecondsThenSeconds()
   assertEq(progress.duration(0), "0ms")
   assertEq(progress.duration(12.4), "12ms")
   assertEq(progress.duration(999), "999ms")
   assertEq(progress.duration(1000), "1.0s")
   assertEq(progress.duration(12345), "12.3s")
end

function M.theTimelineChargesEveryMillisecondToOneActivity()
   local report = progress.new("never")
   report:at("scan")
   report:at("check")
   report:at("scan")
   report:counted(2, 3)
   local timing = report:timing()
   local total = 0
   for _, phase in ipairs(timing.phases) do
      total = total + phase.durationMs
   end
   assert(total <= timing.totalMs + 1,
      "the parts cannot add up to more than the whole")
   assertEq(timing.compiledModules, 2)
   assertEq(timing.reusedModules, 3)
   assertEq(timing.specializedBodies, 0)
   for _, phase in ipairs(timing.phases) do
      assert(phase.durationMs >= 0, "no activity took negative time")
   end
end

function M.theSlowestModulesAreOrderedAndBounded()
   local report = progress.new("never")
   for index = 1, 9 do
      report:spent("module" .. index, index * 10)
   end
   -- Charged twice, and the charges add up rather than replacing each other:
   -- checking and generating one module are two separate measurements.
   report:spent("module1", 500)
   local slowest = report:timing().slowest
   assertEq(#slowest, progress.SLOWEST, "the list is bounded")
   assertEq(slowest[1].module, "module1", "the costliest is first")
   assertEq(slowest[1].durationMs, 510)
   for index = 2, #slowest do
      assert(slowest[index - 1].durationMs >= slowest[index].durationMs,
         "the list descends")
   end
end

function M.aQuietReporterMeasuresAndSaysNothing()
   local path = os.tmpname()
   local report, stream = reporterTo(path, "never")
   report:expect(2)
   report:step("checking something")
   report:spent("a.module", 12)
   report:counted(1, 0)
   report:finish("built", "app")
   stream:close()
   assertEq(readAll(path), "", "nothing was written")
   assert(report:timing().totalMs >= 0, "and it was measured anyway")
   os.remove(path)
end

function M.crossModuleConstBodiesBelongToTheDeclarationAndTrackIncomingKeys()
   local dir = constProject()
   local _, firstErr = run(dir, "build")
   assertEq(firstErr, "", "the first optimized build succeeds")
   local declaration = readAll(dir .. "/out/lib.lua")
   local caller = readAll(dir .. "/out/main.lua")
   assert(declaration:find("local function __nuppConst_accumulate_", 1, true),
      "the private body is emitted with its declaration")
   assert(declaration:find("__nuppConstSpecializations", 1, true),
      "the declaration publishes private linkage by public function identity")
   assert(caller:find("_G.__nuppConstSpecializations[", 1, true),
      "the checked direct call names the body without a tuple branch")
   assert(not caller:find("local function __nuppConst_accumulate_", 1, true),
      "the caller does not duplicate the body")

   local pipe = assert(io.popen((
      "cd %q && luajit -e %q"
   ):format(dir, 'package.path="out/?.lua;"..package.path; assert(require("main")==20)')))
   pipe:read("*a")
   assert(pipe:close(), "the cross-module private call answers")

   local source = assert(io.open(dir .. "/main.nupp", "wb"))
   source:write("local lib = require('lib')\nconst run = lib.accumulate\nreturn run(10.0, 5)\n")
   source:close()
   local _, secondErr = run(dir, "build")
   assertEq(secondErr, "", "changing only the incoming tuple rebuilds cleanly")
   local changed = readAll(dir .. "/out/lib.lua")
   assert(changed ~= declaration,
      "the declaring artifact changes when its incoming specialization manifest changes")
   assert(changed:find("local function __nuppConst_accumulate_", 1, true),
      "and still owns the replacement body")
end

function M.aFileBuildCountsTheBodiesItEmitted()
   -- `nupp build FILE` does not use the project module graph, so it reports its
   -- own count. It read zero however many bodies OPT-8 emitted, which made the
   -- number say a build specialized nothing whenever it specialized anything.
   local dir = tempDir()
   local file = assert(io.open(dir .. "/only.nupp", "wb"))
   file:write(table.concat({
      "local function accumulate<const N: integer>(value: number, count: N): number",
      "    local total = value",
      "    for offset = 1, count as integer do total = total + offset end",
      "    return total",
      "end",
      "return accumulate(10.0, 4) + accumulate(10.0, 7)",
   }, "\n") .. "\n")
   file:close()
   local out, err = run(dir, "build -O1 --json only.nupp")
   assertEq(err, "", "the file build succeeds quietly")
   local decoded = require("testjson").decode(out)
   assertEq(decoded.ok, true, "the file build worked: " .. out)
   local emitted = 0
   for _ in readAll(dir .. "/only.lua"):gmatch("local function __nuppConst_accumulate_") do
      emitted = emitted + 1
   end
   assertEq(emitted, 2, "two closed tuples emit two private bodies")
   assertEq(decoded.timing.specializedBodies, emitted,
      "and the reported count is the number of bodies emitted")
end

function M.aFileBuildAtLevelZeroCountsNothing()
   local dir = tempDir()
   local file = assert(io.open(dir .. "/only.nupp", "wb"))
   file:write(table.concat({
      "local function accumulate<const N: integer>(value: number, count: N): number",
      "    local total = value",
      "    for offset = 1, count as integer do total = total + offset end",
      "    return total",
      "end",
      "return accumulate(10.0, 4)",
   }, "\n") .. "\n")
   file:close()
   local out, err = run(dir, "build -O0 --json only.nupp")
   assertEq(err, "", "the unoptimized file build succeeds quietly")
   local decoded = require("testjson").decode(out)
   assertEq(decoded.timing.specializedBodies, 0, "-O0 emits and counts nothing")
   assert(not readAll(dir .. "/only.lua"):find("__nuppConst_accumulate_", 1, true),
      "-O0 leaves the generic declaration and call")
end

function M.levelZeroDoesNotPlanOrCountProjectConstBodies()
   local dir = constProject()
   local out, err = run(dir, "build -O0 --json")
   assertEq(err, "", "the unoptimized build succeeds quietly")
   local decoded = require("testjson").decode(out)
   assertEq(decoded.ok, true, "the unoptimized build worked: " .. out)
   assertEq(decoded.timing.specializedBodies, 0,
      "timing counts emitted bodies rather than eligible source calls")
   local declaration = readAll(dir .. "/out/lib.lua")
   assert(not declaration:find("__nuppConst_accumulate_", 1, true),
      "-O0 never emits the optional private body")
end

function M.theSummarySaysHowLongAndWhatCostTheMost()
   local path = os.tmpname()
   local report, stream = reporterTo(path, "always")
   report:expect(1)
   report:step("checking one.nupp")
   report:spent("one.module", 1200)
   report:spent("two.module", 30)
   report:counted(1, 4)
   report:addSpecialized(2)
   report:finish("built", "app")
   stream:close()
   local text = readAll(path)
   assert(text:match("checking one%.nupp"), "it said what it was doing: " .. text)
   assert(text:match("built app in %d"), "and how long that took: " .. text)
   assert(text:match("1 compiled, 4 reused"), "and what it did: " .. text)
   assert(text:match("2 specialized"), "and counted bodies apart from modules: " .. text)
   os.remove(path)
end

function M.aColoredSummaryPaintsSuccessAndBuildCounts()
   local path = os.tmpname()
   local stream = assert(io.open(path, "wb"))
   ansi.withMode("always", function()
      local report = progress.new("always", stream)
      report:counted(2, 3)
      report:finish("built", "app")
   end)
   stream:close()
   local text = readAll(path)
   assert(text:find("\27[1;32mbuilt app\27[0m", 1, true),
      "a successful build is green: " .. text)
   assert(text:find("\27[1;36m2 compiled, 3 reused\27[0m", 1, true),
      "the build counts are cyan: " .. text)
   os.remove(path)
end

function M.aRunWithNothingToCompileSaysSoInOneLine()
   local path = os.tmpname()
   local report, stream = reporterTo(path, "always")
   report:counted(0, 7)
   report:finish("built", "app")
   stream:close()
   local text = readAll(path)
   assert(text:match("7 modules reused"), "it said nothing was rebuilt: " .. text)
   assertEq(select(2, text:gsub("\n", "")), 1, "one line: " .. text)
   os.remove(path)
end

function M.aBuildIsQuietWhenNobodyIsWatching()
   local dir = tempProject()
   local out, err = run(dir, "build")
   assertEq(out, "", "nothing on standard output: " .. out)
   assertEq(err, "", "and nothing on standard error: " .. err)
   os.execute("rm -rf '" .. dir .. "'")
end

function M.progressAlwaysReportsToStandardError()
   local dir = tempProject()
   local _, err = run(dir, "build --progress=always")
   assert(err:match("built app in %d"), "the summary is on stderr: " .. err)
   assert(err:match("compiled"), "and says what it built: " .. err)
   local out, second = run(dir, "build --progress=always")
   assertEq(out, "", "standard output stays clear")
   assert(second:match("modules reused"),
      "a second build reports reuse: " .. second)
   os.execute("rm -rf '" .. dir .. "'")
end

function M.theEnvironmentSaysTheSameThingAndTheFlagOverrulesIt()
   local dir = tempProject()
   local _, viaEnv = run(dir, "build", "NUPP_PROGRESS=always ")
   assert(viaEnv:match("built app in %d"), "NUPP_PROGRESS=always: " .. viaEnv)
   local _, refused = run(dir, "build -q", "NUPP_PROGRESS=always ")
   assertEq(refused, "", "the flag overrules the environment: " .. refused)
   os.execute("rm -rf '" .. dir .. "'")
end

function M.jsonCarriesTheTimingAndStaysADocument()
   local dir = tempProject()
   local out, err = run(dir, "build --json")
   assertEq(err, "", "a machine reader is not narrated at: " .. err)
   local decoded = require("testjson").decode(out)
   assertEq(decoded.ok, true, "the build worked: " .. out)
   local timing = assert(decoded.timing, "there is a timing object: " .. out)
   assert(timing.totalMs > 0, "with a total")
   assertEq(type(timing.phases), "table", "and the activities it covers")
   assertEq(type(timing.slowest), "table", "and the modules that cost the most")
   local charged = 0
   for _, phase in ipairs(timing.phases) do
      charged = charged + phase.durationMs
   end
   assert(charged <= timing.totalMs + 1,
      "the activities cannot add up to more than the whole")
   local _, narrated = run(dir, "build --json --progress=always")
   assert(narrated:match("built app in %d"),
      "--progress overrules the silence --json implies: " .. narrated)
   os.execute("rm -rf '" .. dir .. "'")
end

return M
