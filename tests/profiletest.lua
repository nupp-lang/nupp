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
local zone = require("nupp.profile.zone")

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
-- How long a window has to be for a sample to land in it.
--
-- The interval asked for is a millisecond, and no platform is obliged to deliver
-- one: Windows' default timer granularity is about fifteen. A window sized for a
-- timer that fires when asked can end with no sample at all there -- and under
-- shards the process competes for a core it is not always holding when the timer
-- does fire. Scaled rather than special-cased, so what each case is measuring
-- stays the same shape everywhere.
local SAMPLE_SCALE = package.config:sub(1, 1) == "\\" and 4 or 1

local function sampleWindow(seconds)
   return seconds * SAMPLE_SCALE
end

-- A short spin the diagnostic above can time without depending on `burn`, which
-- is declared below it.
local function burnProbe()
   local deadline = os.clock() + 0.05
   local total = 0.0
   repeat
      for i = 1, 100000 do total = total + (i % 7) * 1.5 end
   until os.clock() >= deadline

   return total
end

-- What this interpreter offers the sampler, for a failure to say rather than
-- leave to be guessed at. A count of zero has more than one cause -- no timer,
-- no profiler, a burn that returned early -- and they are not distinguishable
-- from "false".
local function describeSampling()
   local ok, jitProfile = pcall(require, "jit.profile")
   local elapsed = os.clock()
   burnProbe()
   elapsed = os.clock() - elapsed

   return ("%s (jit.profile %s, os.clock advanced %.3fs over a probe burn)")
      :format(jit and jit.os or "?", ok and jitProfile and "present" or "absent",
         elapsed)
end

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

local function fnewAbortPayload()
   local registry = require("nupp.profile.trace")
   local vmdef = require("jit.vmdef")
   local errorCode
   for code, format in pairs(vmdef.traceerr) do
      if format:find("NYI: bytecode", 1, true) then errorCode = code; break end
   end
   local opcode
   for code = 0, #vmdef.bcnames / 6 - 1 do
      if registry.opcodeName(code) == "FNEW" then opcode = code; break end
   end

   return assert(errorCode), assert(opcode)
end

local FNEW_ERROR_CODE, FNEW_OPCODE = fnewAbortPayload()

-- Feed the collector the same arguments `jit.attach` supplies for an abort.
-- Testing the event handler directly keeps aggregation independent of when the
-- JIT decides a loop is hot enough to attempt a trace.
local function emitFnewAbort(session)
   session.callback("abort", 1, emitFnewAbort, 0,
      FNEW_ERROR_CODE, FNEW_OPCODE)
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
   burn(sampleWindow(0.2))
   local report = session:stop()

   assert(report.samples > 0,
      ("a fifth of a second at 1ms must sample, got %d in %s")
         :format(report.samples, describeSampling()))
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
   burn(sampleWindow(0.2))
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
   burn(sampleWindow(0.15))
   zone.pop()
   zone.push("dropped")
   burn(sampleWindow(0.15))
   zone.pop()
   local report = session:stop()

   assert(report.samples > 0,
      ("the kept subtree was sampled, got %d in %s")
         :format(report.samples, describeSampling()))
   for _, line in ipairs(lines(report.text)) do
      assertMatch(line, "^kept", "only the filtered subtree survives")
   end
end

-- The filter names a subtree, not a character prefix: a sibling zone that merely
-- starts with the same text is outside it.
function M.sampleZoneFilterEndsAtAPathComponent()
   local session = profile.sample({intervalMs = 1, zone = "kept"})
   zone.push("keptothers")
   burn(sampleWindow(0.15))
   zone.pop()
   local report = session:stop()

   assertEq(report.samples, 0, "a sibling sharing the prefix is not the subtree")
   assertEq(report.text, "", "and nothing is reported for it")
end

function M.sampleZoneFilterThatMatchesNothingIsEmptyRatherThanEverything()
   local session = profile.sample({intervalMs = 1, zone = "absent"})
   burn(sampleWindow(0.1))
   local report = session:stop()

   assertEq(report.text, "", "no matching zone, no text")
   assertEq(report.samples, 0, "and nothing counted")
   assertEq(report.stacks, 0, "and no stacks")
end

-- Everything under the root is the harness that got here: the test runner, its
-- dofile, the pcall around each case. None of it is what was being measured.
function M.sampleRootDropsTheFramesBeneathTheProgram()
   local session = profile.sample({intervalMs = 1, root = "profiletest.lua"})
   burn(sampleWindow(0.2))
   local report = session:stop()

   assert(report.samples > 0,
      ("sampled, got %d in %s"):format(report.samples, describeSampling()))
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
   burn(sampleWindow(0.15))
   local report = session:stop(path)

   assertEq(readFile(path), report.text, "the file is the report")
   os.remove(path)
end

function M.samplePauseLeavesTheWindowOut()
   local session = profile.sample({intervalMs = 1})
   session:pause()
   session:pause()
   burn(sampleWindow(0.2))
   local report = session:stop()

   assertEq(report.samples, 0, "a paused session records nothing")
   assertEq(report.text, "", "and so has nothing to say")
end

function M.sampleResumeStartsRecordingAgain()
   local session = profile.sample({intervalMs = 1})
   session:pause()
   burn(sampleWindow(0.1))
   session:resume()
   burn(sampleWindow(0.2))
   local report = session:stop()

   assert(report.samples > 0,
      ("what ran after the resume was recorded, got %d in %s")
         :format(report.samples, describeSampling()))
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

function M.recordedTracePayloadUsesTheStaticReasonIdentity()
   local registry = require("nupp.profile.trace")
   local reason, raw = registry.runtime(FNEW_ERROR_CODE, FNEW_OPCODE)
   assertEq(reason.id, "jit/loop-function-construction",
      "recorded VM payload and static bytecode share an identity")
   assertEq(reason.class, "blocker", "the operation-level classification")
   assertMatch(raw, "FNEW", "raw recorder detail remains visible")
end

function M.unknownTracePayloadStaysVisibleWithoutInventedAdvice()
   local registry = require("nupp.profile.trace")
   local reason, raw = registry.runtime(2147483647, "opaque")
   assertEq(reason.id, "jit/runtime-unknown", "unknown stays unknown")
   assertEq(reason.repair, nil, "an unknown event has no guessed repair")
   assertMatch(raw, "2147483647", "the raw VM identity remains visible")
end

-- The digest is a fixed-width word however the hash lands: a negative 32-bit
-- value must not widen the rendering.
function M.traceProfileDigestIsEightHexCharacters()
   local registry = require("nupp.profile.trace")
   local described = registry.profile()
   assertMatch(described.bytecodeSchema, "^%x%x%x%x%x%x%x%x$",
      "the bytecode schema digest")
   assertMatch(described.id, described.bytecodeSchema,
      "and the profile id carries it")
end

function M.traceRecordsWhereTheCompilerGaveUp()
   local session = profile.trace()
   emitFnewAbort(session)
   local report = session:stop()

   assertEq(report.totalAborts, 1, "the emitted abort is counted")
   assertEq(#report.sites, 1, "the emitted abort has one site")
   assertEq(report.sites[1].reasonId, "jit/loop-function-construction",
      "the unrecordable bytecode is reported")
   assertEq(report.sites[1].reasonClass, "blocker",
      "the operation-level classification is preserved")
   assertMatch(report.sites[1].rawReason, "FNEW",
      "the VM's bytecode detail remains visible")
end

function M.traceReportRendersAsCsv()
   local session = profile.trace()
   emitFnewAbort(session)
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
   local session = profile.trace()
   emitFnewAbort(session)
   local report = session:stop(path)

   assertEq(readFile(path), tostring(report), "the file is the report")
   os.remove(path)
end

function M.tracePauseLeavesTheWindowOut()
   local session = profile.trace()
   session:pause()
   emitFnewAbort(session)
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
        local function step(): integer return i end
        total = total + step()
    end
    return total
end

local given = {...}
local repeats = tonumber(given[1] or "") or 40
for _ = 1, repeats do hot(2000000) end
stepper(3000)
io.write("ran\n")
]]

-- The profiled program's repeat count, which is the window a sample has to land
-- in for the cases that run it as a command. `sampleWindow` sizes the in-process
-- ones; this is the same scaling reaching the one that is a separate program,
-- whose workload the test can only set through its argument.
local function sampleRepeats(repeats)
   return tostring(repeats * SAMPLE_SCALE)
end

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
   local failing = assert(io.open(dir .. "/fail.nupp", "wb"))
   failing:write("error('program sentinel', 0)\n")
   failing:close()
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
   local out, ok = run(dir, "run --profile=1 work.nupp " .. sampleRepeats(40))
   assert(ok, "the program ran: " .. out)
   assertMatch(out, "ran", "the program's own output is not swallowed")
   assertMatch(out, "samples on %d+ stacks every 1ms, written to profile%.out",
      "the summary: " .. out)

   local text = readFile(dir .. "/profile.out")
   assert(#text > 0,
      ("samples were written, got %d bytes in %s")
         :format(#text, describeSampling()))
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
   local out, ok = run(dir,
      "run --profile --profile-out samples.txt work.nupp " .. sampleRepeats(4))
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
   assert(#rows > 1, "the closure workload aborts, so there is a row")
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

function M.cliJitAbortsWritesNormalizedJson()
   local dir = tempProject()
   local out, ok = run(dir,
      "run --jit-aborts=aborts.json --json work.nupp 2")
   assert(ok, "the program ran: " .. out)
   local report = require("testjson").decode(readFile(dir .. "/aborts.json"))
   assert(report.traceProfile.id, "the VM profile is explicit")
   assertEq(report.reasonCatalog.id, "nupp-trace-reasons-v1",
      "the stable registry is explicit")
   assert(#report.sites > 0, "the workload produced an observed abort")
   assertEq(report.sites[1].reasonId, "jit/loop-function-construction",
      "the observed FNEW uses the static identity")
   assertEq(report.sites[1].class, "blocker", "the reason class is preserved")
   assertMatch(report.sites[1].rawReason, "FNEW", "the raw VM detail remains")
   os.execute("rm -rf '" .. dir .. "'")
end

function M.jitAbortWriteFailureStillReportsTheProgramError()
   if package.config:sub(1, 1) == "\\" then
      require("assert").skip("POSIX directory permissions provide this failure seam")
   end
   local dir = tempProject()
   assert(os.execute("mkdir -p '" .. dir .. "/locked'") == 0)
   assert(os.execute("chmod 555 '" .. dir .. "/locked'") == 0)
   local out, ok = run(dir,
      "run --jit-aborts=locked/aborts.csv fail.nupp")
   assert(not ok, "both the run and its report write fail")
   assertMatch(out, "program sentinel",
      "the program's own failure survives the report failure: " .. out)
   assertMatch(out, "locked/aborts%.csv",
      "the report write failure is also retained: " .. out)
   assert(os.execute("chmod 755 '" .. dir .. "/locked'") == 0)
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
