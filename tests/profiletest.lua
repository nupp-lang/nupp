-- nupp.profile, both channels, plus the `nupp run` flags that drive them.
--
-- A sampler is timing-dependent by construction, so nothing here asserts a
-- sample count. What it asserts is the shape: that a workload run under a
-- session produces samples at all, that they land in the zone that was open,
-- that a filter keeps what it says it keeps, and that the text is the format
-- the flame graph tools read. The workloads run against the clock rather than
-- a fixed iteration count, so a faster machine does not turn into an empty
-- report.
local profile = require("nupp.profile")
local zone = require("nupp.zone")

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

local function assertMatch(text, pattern, label)
   if not tostring(text):find(pattern) then
      error(("%s: %q does not match %s"):format(label or "no match",
         tostring(text), pattern), 2)
   end
end

local function readFile(path)
   local f = assert(io.open(path, "rb"))
   local text = f:read("*a")
   f:close()
   return text
end

local function lines(text)
   local out = {}
   for line in text:gmatch("[^\n]+") do out[#out + 1] = line end
   return out
end

-- Busy for `seconds` of CPU, in a shape the JIT will happily compile, so the
-- samples land in this file rather than in whatever the allocator was doing.
local function burn(seconds)
   local deadline = os.clock() + seconds
   local total = 0.0
   local rounds = 0
   repeat
      for i = 1, 200000 do total = total + (i % 7) * 1.5 end
      rounds = rounds + 1
   until os.clock() >= deadline
   return total, rounds
end

-- A fresh function every time, because a trace abort is a one-off: once the
-- compiler has given up on a piece of code it stops trying, and the second
-- test to run the same function would see nothing. `coroutine.wrap` closes
-- over a new closure per iteration, which is bytecode the recorder refuses.
local function newAbortingWorkload()
   return assert(loadstring([[
      local rounds = ...
      local total = 0
      for i = 1, rounds do
         local step = coroutine.wrap(function() coroutine.yield(i) end)
         total = total + step()
      end
      return total
   ]], "@abortworkload.lua"))
end

local M = {}

-------------------------------------------------------------------------------
-- Zone paths
-------------------------------------------------------------------------------

function M.zonePathIsEmptyUntilSomethingIsPushed()
   assertEq(zone.path(), "", "no session, no path")
   zone.acquire()
   assertEq(zone.path(), "", "acquired but empty")
   zone.release()
end

function M.zonePathJoinsTheStackOutermostFirst()
   zone.acquire()
   zone.push("frame")
   assertEq(zone.path(), "frame", "one zone")
   zone.push("render")
   assertEq(zone.path(), "frame/render", "two zones")
   zone.push("sprites")
   assertEq(zone.path(), "frame/render/sprites", "three zones")
   assertEq(zone.pop(), "sprites", "pop returns the zone it removed")
   assertEq(zone.path(), "frame/render", "path follows the pop")
   zone.release()
   assertEq(zone.path(), "", "release empties it")
end

-- The path is cached against a version counter, so every mutation has to bump
-- it. A push and a pop that cancel out are the case a stale cache survives.
function M.zonePathIsRebuiltAfterEveryChange()
   zone.acquire()
   zone.push("a")
   assertEq(zone.path(), "a", "before")
   zone.push("b")
   zone.pop()
   assertEq(zone.path(), "a", "after a push and a pop that cancel")
   local token = zone.enter("c")
   assertEq(zone.path(), "a/c", "enter is a push")
   zone.leave(token)
   assertEq(zone.path(), "a", "leave is a pop")
   zone.release()
end

-------------------------------------------------------------------------------
-- Sampling
-------------------------------------------------------------------------------

function M.sampleCollectsCollapsedStacks()
   local session = profile.sample({intervalMs = 1})
   burn(0.2)
   local report = session:stop()

   assert(report.samples > 0, "a fifth of a second at 1ms must sample")
   assert(report.stacks > 0, "samples fell on at least one stack")
   assertEq(report.intervalMs, 1, "the interval it ran at")
   assertEq(tostring(report), report.text, "tostring is the collapsed text")

   for _, line in ipairs(lines(report.text)) do
      assertMatch(line, "^[^%s]+ %d+$", "a collapsed line is frames and a count")
      assertMatch(line, "_%[[NICGJ]%] %d+$", "the leaf carries a VM state")
   end
end

function M.sampleAttributesToTheOpenZone()
   local session = profile.sample({intervalMs = 1})
   zone.push("frame")
   zone.push("physics")
   burn(0.2)
   zone.pop()
   zone.pop()
   local report = session:stop()

   local attributed = false
   for _, line in ipairs(lines(report.text)) do
      if line:find("^frame;physics;") then attributed = true end
   end
   assert(attributed, "samples taken under a zone lead with it:\n" .. report.text)
end

function M.sampleZoneFilterKeepsThatSubtreeAlone()
   local session = profile.sample({intervalMs = 1, zone = "kept"})
   zone.push("kept")
   burn(0.15)
   zone.pop()
   zone.push("dropped")
   burn(0.15)
   zone.pop()
   local report = session:stop()

   assert(report.samples > 0, "the kept subtree was sampled")
   for _, line in ipairs(lines(report.text)) do
      assertMatch(line, "^kept", "only the filtered subtree survives")
   end
end

function M.sampleZoneFilterThatMatchesNothingIsEmptyRatherThanEverything()
   local session = profile.sample({intervalMs = 1, zone = "absent"})
   burn(0.1)
   local report = session:stop()

   assertEq(report.text, "", "no matching zone, no text")
   assertEq(report.samples, 0, "and nothing counted")
   assertEq(report.stacks, 0, "and no stacks")
end

-- Everything under the root is the harness that got here: the test runner, its
-- dofile, the pcall around each case. None of it is what was being measured.
function M.sampleRootDropsTheFramesBeneathTheProgram()
   local session = profile.sample({intervalMs = 1, root = "profiletest.lua"})
   burn(0.2)
   local report = session:stop()

   assert(report.samples > 0, "sampled")
   local trimmed = false
   for _, line in ipairs(lines(report.text)) do
      if line:find("profiletest%.lua") then
         assertMatch(line, "^profiletest%.lua",
            "the root is the first frame once the rest is cut")
         trimmed = true
      end
   end
   assert(trimmed, "at least one stack reached this file:\n" .. report.text)
end

function M.sampleWritesTheSameTextItReturns()
   local path = os.tmpname()
   local session = profile.sample({intervalMs = 1})
   burn(0.15)
   local report = session:stop(path)

   assertEq(readFile(path), report.text, "the file is the report")
   os.remove(path)
end

function M.samplePauseLeavesTheWindowOut()
   local session = profile.sample({intervalMs = 1})
   session:pause()
   session:pause()
   burn(0.2)
   local report = session:stop()

   assertEq(report.samples, 0, "a paused session records nothing")
   assertEq(report.text, "", "and so has nothing to say")
end

function M.sampleResumeStartsRecordingAgain()
   local session = profile.sample({intervalMs = 1})
   session:pause()
   burn(0.1)
   session:resume()
   burn(0.2)
   local report = session:stop()

   assert(report.samples > 0, "what ran after the resume was recorded")
end

function M.onlyOneSampleSessionRunsAtATime()
   local session = profile.sample({intervalMs = 10})
   local ok, err = pcall(profile.sample)
   assert(not ok, "a second session must be refused")
   assertMatch(err, "already running", "and say why")
   session:stop()
end

function M.aStoppedSampleSessionRefusesEverything()
   local session = profile.sample({intervalMs = 10})
   session:stop()

   local ok, err = pcall(function() return session:stop() end)
   assert(not ok, "stopping twice is an error")
   assertMatch(err, "already stopped", "and says so")
   assert(not pcall(function() session:pause() end), "pause after stop")
   assert(not pcall(function() session:resume() end), "resume after stop")
end

function M.sampleRefusesAnIntervalItCannotHonour()
   assert(not pcall(profile.sample, {intervalMs = 0}), "zero milliseconds")
   assert(not pcall(profile.sample, {stackDepth = 0}), "zero frames")
   -- Neither attempt may leave the singleton latched.
   local session = profile.sample()
   session:stop()
end

-------------------------------------------------------------------------------
-- Trace aborts
-------------------------------------------------------------------------------

function M.traceRecordsWhereTheCompilerGaveUp()
   local workload = newAbortingWorkload()
   jit.flush()
   local session = profile.trace()
   zone.push("spawning")
   workload(3000)
   zone.pop()
   local report = session:stop()

   assert(report.totalAborts > 0, "unrecordable bytecode must be reported")
   assert(#report.sites > 0, "and land in a row")
   assert(report.blacklisted <= report.totalAborts,
      "blacklists are a subset of the aborts")

   local site = report.sites[1]
   assertEq(site.zonePath, "spawning", "the zone that was open")
   assertMatch(site.reason, "NYI", "the reason names what it could not record")
   assertMatch(site.location, "^abortworkload%.lua:%d+$", "file and line")
   assert(site.count > 0, "counted")
   assert(site.severity == "warn" or site.severity == "blacklist",
      "a refusal is not filed as information: " .. site.severity)
end

function M.traceReportRendersAsCsv()
   local workload = newAbortingWorkload()
   jit.flush()
   local session = profile.trace()
   workload(3000)
   local report = session:stop()

   local rows = lines(tostring(report))
   assertEq(rows[1], "severity,count,reason,location,zone", "the header")
   assertEq(#rows, #report.sites + 1, "one row per site, after the header")
   for index = 2, #rows do
      assertMatch(rows[index], "^%a+,%d+,", "a row leads with severity, count")
   end
end

function M.traceWritesTheCsvItReturns()
   local path = os.tmpname()
   local workload = newAbortingWorkload()
   jit.flush()
   local session = profile.trace()
   workload(2000)
   local report = session:stop(path)

   assertEq(readFile(path), tostring(report), "the file is the report")
   os.remove(path)
end

function M.tracePauseLeavesTheWindowOut()
   local workload = newAbortingWorkload()
   jit.flush()
   local session = profile.trace()
   session:pause()
   workload(3000)
   local report = session:stop()

   assertEq(report.totalAborts, 0, "a paused session counts nothing")
end

function M.onlyOneTraceSessionRunsAtATime()
   local session = profile.trace()
   local ok, err = pcall(profile.trace)
   assert(not ok, "a second session must be refused")
   assertMatch(err, "already running", "and say why")
   session:stop()
end

function M.aStoppedTraceSessionRefusesEverything()
   local session = profile.trace()
   session:stop()

   local ok, err = pcall(function() return session:stop() end)
   assert(not ok, "stopping twice is an error")
   assertMatch(err, "already stopped", "and says so")
   assert(not pcall(function() session:pause() end), "pause after stop")
   assert(not pcall(function() session:resume() end), "resume after stop")
end

-- The channels share the zone stack through a reference count, so one stopping
-- must not take the zones out from under the other.
function M.theTwoChannelsShareTheZoneStack()
   local sampling = profile.sample({intervalMs = 10})
   local tracing = profile.trace()
   zone.push("shared")
   assertEq(zone.path(), "shared", "both sessions hold the stack open")
   tracing:stop()
   assertEq(zone.path(), "shared", "one stopping does not release it")
   zone.pop()
   sampling:stop()
   assertEq(zone.path(), "", "the last one out empties it")
end

-------------------------------------------------------------------------------
-- The command line
-------------------------------------------------------------------------------

local PROGRAM = [[
local function hot(rounds: integer): number
    local total = 0.0
    for i = 1, rounds do total = total + (i % 7) * 1.5 end
    return total
end

local function stepper(rounds: integer): integer
    local total: integer = 0
    for i = 1, rounds do
        local step = coroutine.wrap(function() coroutine.yield(i) end)
        total = total + (step() as integer)
    end
    return total
end

local given = {...}
local repeats = tonumber(given[1] or "") or 40
for _ = 1, repeats do hot(2000000) end
stepper(3000)
io.write("ran\n")
]]

local function tempProject()
   local dir = os.tmpname()
   os.remove(dir)
   assert(os.execute("mkdir -p '" .. dir .. "'") == 0)
   local manifest = assert(io.open(dir .. "/nupp.lua", "wb"))
   manifest:write("return { include = { '.' } }\n")
   manifest:close()
   local program = assert(io.open(dir .. "/work.nupp", "wb"))
   program:write(PROGRAM)
   program:close()
   return dir
end

local function run(dir, argv)
   local outfile = os.tmpname()
   local status = os.execute(("cd '%s' && '%s' %s > '%s' 2>&1")
      :format(dir, NUPP, argv, outfile))
   local out = readFile(outfile)
   os.remove(outfile)
   return out, status == 0
end

function M.cliProfileWritesCollapsedStacks()
   local dir = tempProject()
   local out, ok = run(dir, "run --profile=1 work.nupp")
   assert(ok, "the program ran: " .. out)
   assertMatch(out, "ran", "the program's own output is not swallowed")
   assertMatch(out, "samples on %d+ stacks every 1ms, written to profile%.out",
      "the summary: " .. out)

   local text = readFile(dir .. "/profile.out")
   assert(#text > 0, "samples were written")
   for _, line in ipairs(lines(text)) do
      assertMatch(line, "^[^%s]+ %d+$", "collapsed: frames then a count")
      -- The root cut is what keeps this command's own frames out of a report
      -- about somebody's program.
      assert(not line:find("main%.lua"),
         "the compiler's frames are not the program's: " .. line)
   end
   os.execute("rm -rf '" .. dir .. "'")
end

function M.cliProfileOutChoosesThePath()
   local dir = tempProject()
   local out, ok = run(dir, "run --profile --profile-out samples.txt work.nupp 4")
   assert(ok, "the program ran: " .. out)
   assertMatch(out, "written to samples%.txt", "the summary names it: " .. out)
   assert(#readFile(dir .. "/samples.txt") >= 0, "the named file was written")
   local absent = io.open(dir .. "/profile.out", "rb")
   assert(not absent, "and the default was not")
   os.execute("rm -rf '" .. dir .. "'")
end

function M.cliJitAbortsWritesCsv()
   local dir = tempProject()
   local out, ok = run(dir, "run --jit-aborts work.nupp 2")
   assert(ok, "the program ran: " .. out)
   assertMatch(out, "%d+ trace aborts, %d+ blacklisted, written to "
      .. "jit%-aborts%.csv", "the summary: " .. out)

   local rows = lines(readFile(dir .. "/jit-aborts.csv"))
   assertEq(rows[1], "severity,count,reason,location,zone", "the header")
   assert(#rows > 1, "the coroutine workload aborts, so there is a row")
   assertMatch(rows[2], "^warn,%d+,NYI", "and it says what was refused")
   os.execute("rm -rf '" .. dir .. "'")
end

function M.cliJitAbortsTakesAPath()
   local dir = tempProject()
   local out, ok = run(dir, "run --jit-aborts=aborts.csv work.nupp 2")
   assert(ok, "the program ran: " .. out)
   assertMatch(out, "written to aborts%.csv", "the summary names it: " .. out)
   assertMatch(readFile(dir .. "/aborts.csv"), "^severity,count", "the CSV")
   os.execute("rm -rf '" .. dir .. "'")
end

function M.cliRejectsAnIntervalThatIsNotAWholeNumberOfMilliseconds()
   local dir = tempProject()
   for _, argument in ipairs({"--profile=x", "--profile=0", "--profile=1.5",
      "--profile="}) do
      local out, ok = run(dir, "run " .. argument .. " work.nupp 1")
      assert(not ok, argument .. " must be refused")
      assertMatch(out, "whole number of milliseconds",
         argument .. " says what it wanted: " .. out)
   end
   os.execute("rm -rf '" .. dir .. "'")
end

function M.cliRefusesADestinationForAReportNobodyAskedFor()
   local dir = tempProject()
   local out, ok = run(dir, "run --profile-out samples.txt work.nupp 1")
   assert(not ok, "--profile-out alone must be refused")
   assertMatch(out, "which was not asked for", "and say why: " .. out)

   out, ok = run(dir,
      "run --profile --profile-out a.txt --profile-out b.txt work.nupp 1")
   assert(not ok, "two destinations are one too many")
   assertMatch(out, "more than once", "and say which: " .. out)
   os.execute("rm -rf '" .. dir .. "'")
end

function M.cliRunStillTakesItsOtherArgumentsAndTheProgramsOwn()
   local dir = tempProject()
   local out, ok = run(dir, "run --strict --profile=5 -- work.nupp 3")
   assert(ok, "--strict, --profile and -- compose: " .. out)
   assertMatch(out, "ran", "the program ran")
   os.execute("rm -rf '" .. dir .. "'")
end

function M.helpDescribesTheProfilingFlags()
   local out, ok = run(HERE .. "/..", "help run")
   assert(ok, "help exits cleanly")
   assertMatch(out, "%-%-profile%[=MS%]", "the sampling flag")
   assertMatch(out, "%-%-profile%-out PATH", "where it writes")
   assertMatch(out, "%-%-jit%-aborts", "the trace channel")
end

return M
