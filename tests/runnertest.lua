-- The runner is itself a command-line program. Exercise a fresh copy so this
-- test can observe exactly what a person sees, without recursing into this
-- repository's own suite.
local test = require("assert")
local M = {}

local ROOT = debug.getinfo(1, "S").source:match("^@(.+)/tests/")
if not ROOT then
    local p = assert(io.popen("pwd"))
    ROOT = p:read("*l")
    p:close()
end
ROOT = ROOT:gsub("\\", "/")
local NUPP = os.getenv("NUPP_TEST_BIN") or ROOT .. "/bin/nupp"

local function read(path)
    local f = assert(io.open(path, "rb"))
    local text = f:read("*a")
    f:close()
    return text
end

local function write(path, text)
    local f = assert(io.open(path, "wb"))
    f:write(text)
    f:close()
end

-- A copied runner loads compiled modules before it does anything, and it cannot
-- find them from a temporary directory. Naming the repository's build directory
-- is what lets the copy be the same program as the original.
local MODULES = ("NUPP_TEST_MODULES=%q "):format(ROOT .. "/build")

-- A copied Windows runner launched directly behind `io.popen` inherits OS pipe
-- handles without matching C-runtime descriptors, while its per-case capture
-- deliberately works at the descriptor layer. Give the copied runner ordinary
-- file-backed streams on every platform; `runJson` leaves standard error out of
-- the document because progress marks belong there.
local function runRedirected(path, args, stderr)
    local quoted = "'" .. path:gsub("'", "'\\''") .. "'"
    local outputPath = os.tmpname()
    local command = (MODULES .. "luajit %s %s >%q %s"):format(quoted, args or "", outputPath, stderr)
    os.execute(command)
    local output = read(outputPath)
    os.remove(outputPath)

    return (output:gsub("\r\n", "\n"))
end

local function run(path, args)
    return runRedirected(path, args, "2>&1")
end

local function runJson(path, args)
    return runRedirected(path, args, "2>/dev/null")
end

-- A nested runner that printed no summary is the case these invocations exist to
-- catch, and it is also the case where the output alone says nothing. Which
-- command ran, how it ended, and everything it did write are all evidence, and
-- none of the three is recoverable after the fact.
--
-- The status has to travel back through the pipe. LuaJIT's `close` on a popened
-- file answers `true` whatever the child exited with, so a run that died and a
-- run that returned unexpected output are indistinguishable from the handle;
-- the shell that ran the command is asked instead. Its answer is read back out
-- of the output with a Lua pattern, so the marker is spelled without any of the
-- characters that are magic in one.
local EXIT = "@@nupp_test_exit:"

local function capturedRun(command)
    local pipe = assert(io.popen(("%s; printf '%s%%d@@\\n' $?"):format(command, EXIT)))
    local output = pipe:read("*a") or ""
    pipe:close()
    local status = tonumber(output:match(EXIT .. "(%d+)@@"))
    output = output:gsub(EXIT .. "%d+@@\n?", "")

    return output, {command = command, output = output, status = status}
end

local function runWorkerHost(args)
    return capturedRun(("cd %q && %q %s 2>&1"):format(ROOT, ROOT .. "/build/nupp-test", args))
end

-- What the named invocations did, whole. Summarising here would drop exactly the
-- part a report that went missing is hiding in, and a byte count separates output
-- that was never written from output that was written and lost in capture.
local function evidence(...)
    local parts = {}
    for index = 1, select("#", ...) do
        local invocation = select(index, ...)
        local ending = invocation.status and tostring(invocation.status) or "with an unreported status"
        local shape = "\n$ %s\nexited %s, wrote %d bytes:\n%s"
        parts[#parts + 1] = shape:format(invocation.command, ending, #invocation.output, invocation.output)
    end

    return table.concat(parts)
end

function M.bundledRunnerWorksOutsideTheCompilerCheckout()
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p " .. string.format("%q", dir .. "/tests")) == 0)
    assert(os.execute("mkdir -p " .. string.format("%q", dir .. "/src")) == 0)
    write(dir .. "/nupp.lua", 'return {include = {"src"}, build = {entries = {"main"}}}\n')
    write(dir .. "/src/main.nupp", "return true\n")
    for _, name in ipairs({"alpha", "beta"}) do
        write(
            ("%s/tests/%stest.lua"):format(dir, name),
            (
                [=[
local test = require("nupp.test")
local M = {}
function M.passes() test.equal(%q, %q) end
return M
]=]
            ):format(name, name)
        )
    end

    -- Keep the copied runner in one process. External discovery, persistence,
    -- and the public test command are what this case exercises; worker shape is
    -- covered independently below.
    local command = ("cd %q && %q test --jobs=1 --json 2>/dev/null"):format(dir, NUPP)
    local output, bundled = capturedRun(command)
    test.equal(bundled.status, 0, "the bundled runner failed outside its checkout" .. evidence(bundled))
    local report = require("testjson").decode(output)
    test.equal(report.total, 2, "both external suites ran")
    test.equal(report.passed, 2, "both external suites passed")
    test.equal(#report.shards, 0, "the external run stayed serial")
    local timings = read(dir .. "/build/.nupp-test-times.json")
    test.matches(timings, '"alphatest"', "external timing history is persisted")
    test.matches(timings, '"betatest"', "every external suite is timed")
    os.execute("rm -rf " .. string.format("%q", dir))
end

function M.workerHostDogfoodsNuppWorkersForOrdinarySuites()
    local ordinary, ordinaryRun = runWorkerHost("lexertest --timings=0")
    test.equal(ordinaryRun.status, 0, "the worker host run succeeded" .. evidence(ordinaryRun))
    test.matches(ordinary, "1 suites across 1 Nupp workers")
    test.matches(ordinary, "18 tests, 18 passed")
    test.equal(
        ordinary:find(".................", 1, true),
        nil,
        "parallel progress is one mark per suite slice, not one per case"
    )

    local popen, popenRun = runWorkerHost("absoluteentrytest --lane=shell --timings=0")
    test.equal(popenRun.status, 0, "the popen run succeeded" .. evidence(popenRun))
    test.matches(popen, "1 shell suites across 1 process workers")
    test.matches(popen, "1 tests, 1 passed")

    local isolated, isolatedRun = runWorkerHost("processnativetest --lane=isolated --timings=0")
    test.equal(isolatedRun.status, 0, "the isolated run succeeded" .. evidence(isolatedRun))
    test.equal(isolated:find("Nupp workers", 1, true), nil, "the native process suite stays off the mechanism it tests")
    test.matches(isolated, "11 tests, 11 passed")
end

function M.shellingFailureStaysInsideItsTestOnAProcessWorker()
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p " .. string.format("%q", dir .. "/tests")) == 0)
    write(dir .. "/tests/run.lua", read(ROOT .. "/tests/run.lua"))
    write(dir .. "/tests/assert.lua", read(ROOT .. "/tests/assert.lua"))
    write(
        dir .. "/tests/shellingtest.lua",
        [[
local M = {}
function M.fails()
    assert(os.execute("exit 7") == 0, "the shell command failed as intended")
end
function M.runsAfterTheFailure()
    local pipe = assert(io.popen("printf survived"))
    assert(pipe:read("*a") == "survived")
    assert(pipe:close())
end
return M
]]
    )

    local command = (
        "cd %q && %sNUPP_TEST_BUILD=%q %q shellingtest --lane=shell --json --timings=0 --no-color 2>/dev/null"
    ):format(dir, MODULES, dir .. "/build", ROOT .. "/build/nupp-test")
    local output, invocation = capturedRun(command)
    local report = require("testjson").decode(output)

    test.equal(invocation.status, 1, "the failed test made the run fail" .. evidence(invocation))
    test.equal(#report.shards, 1, "the shared shelling suite ran on one reusable worker")
    test.equal(report.total, 2, "the worker ran both tests")
    test.equal(report.failed, 1, "the command failure failed one test")
    test.equal(report.passed, 1, "the worker continued to the next test")
    test.equal(report.tests[1].suite, "shellingtest")
    test.matches(report.tests[1].failure.message, "the shell command failed as intended")
    test.equal(report.tests[2].suite, "shellingtest")
    test.equal(report.tests[2].status, "passed")
    os.execute("rm -rf " .. string.format("%q", dir))
end

function M.processAndNuppWorkersRunAtTheSameTime()
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p " .. string.format("%q", dir .. "/tests")) == 0)
    write(dir .. "/tests/run.lua", read(ROOT .. "/tests/run.lua"))
    write(dir .. "/tests/assert.lua", read(ROOT .. "/tests/assert.lua"))

    local shellMarker = dir .. "/shell-ready"
    local sharedMarker = dir .. "/shared-ready"

    local function suite(marker, other, shell)
        return (
            [=[
local M = {}
function M.meetsTheOtherExecutor()
    %s
    local ready = assert(io.open(%q, "wb"))
    ready:write("ready")
    ready:close()
    local deadline = os.clock() + 5
    repeat
        local found = io.open(%q, "rb")
        if found then
            found:close()
            return
        end
    until os.clock() >= deadline
    error("the other executor did not start")
end
return M
]=]
        ):format(shell and 'assert(os.execute("exit 0") == 0)' or "", marker, other)
    end

    write(dir .. "/tests/shellingtest.lua", suite(shellMarker, sharedMarker, true))
    write(dir .. "/tests/sharedtest.lua", suite(sharedMarker, shellMarker, false))
    write(
        dir .. "/tests/isolatedtest.lua",
        (
            [=[
local M = {}
if false then require("nupp.profile") end
function M.runsBeforeNuppWorkersStart()
    local started = io.open(%q, "rb")
    assert(started == nil, "the Nupp lane started before the isolated lane finished")
end
return M
]=]
        ):format(sharedMarker)
    )

    local command = (
        "cd %q && %sNUPP_TEST_BUILD=%q %q shellingtest sharedtest isolatedtest --jobs=2 --json --timings=0 --no-color 2>/dev/null"
    ):format(dir, MODULES, dir .. "/build", ROOT .. "/build/nupp-test")
    local output, invocation = capturedRun(command)
    local report = require("testjson").decode(output)

    test.equal(invocation.status, 0, "the overlapping run succeeded" .. evidence(invocation))
    test.equal(report.total, 3, "all three execution lanes ran")
    test.equal(report.passed, 3, "isolated work ran first and shell work overlapped")
    test.equal(#report.shards, 3, "the two process workers and one Nupp worker reported")
    os.execute("rm -rf " .. string.format("%q", dir))
end

function M.namingSeveralSuitesRunsEveryOneOfThem()
    -- Each name used to overwrite the one before it, so `nupp test a b` ran only `b`
    -- and reported a count that looked like an answer. Summed from the single runs
    -- rather than written down, so this keeps meaning what it says as suites grow.
    local first, firstRun = runWorkerHost("lexertest --timings=0")
    local second, secondRun = runWorkerHost("uritest --timings=0")
    local both, bothRun = runWorkerHost("lexertest uritest --timings=0")
    local a = tonumber(first:match("(%d+) tests,"))
    local b = tonumber(second:match("(%d+) tests,"))
    local together = tonumber(both:match("(%d+) tests,"))
    local runs = evidence(firstRun, secondRun, bothRun)
    test.assert(a and b and together, "each run reports a count" .. runs)
    test.equal(together, a + b, "naming two suites runs both of them" .. runs)
end

function M.aNameMatchingNoSuiteIsAFailure()
    -- Discovering nothing and reporting it green is the shape of this that hurts:
    -- a typo in a suite name reads exactly like a suite that passed.
    local out, missing = runWorkerHost("nosuchsuitetest --timings=0")
    test.matches(out, "no tests were discovered")
    test.equal(missing.status, 1, "discovering nothing exits unsuccessfully" .. evidence(missing))
end

function M.workerHostColorsOnlyWhenAskedDownAPipe()
    local colored, coloredRun = runWorkerHost("lexertest --timings=0 --color=always")
    test.assert(colored:find("\27[", 1, true), "--color=always paints runner output" .. evidence(coloredRun))

    local plain, plainRun = runWorkerHost("lexertest --timings=0 --no-color")
    test.equal(
        plain:find("\27[", 1, true),
        nil,
        "--no-color keeps redirected runner output plain" .. evidence(plainRun)
    )
end

function M.embeddedWorkersDoNotPassTheirProgressDescriptorToNestedRunners()
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p " .. string.format("%q", dir)) == 0)
    write(dir .. "/run.lua", read(ROOT .. "/tests/run.lua"))
    write(dir .. "/assert.lua", read(ROOT .. "/tests/assert.lua"))
    write(dir .. "/innertest.lua", [[
local M = {}
function M.passes() end
return M
]])
    write(
        dir .. "/outertest.lua",
        (
            [=[
local M = {}
function M.capturesNestedProgress()
   local pipe = assert(io.popen("luajit " .. %q .. " innertest --jobs=1 --no-color 2>&1"))
   local output = pipe:read("*a")
   pipe:close()
   assert(output:find(".\n\n1 tests", 1, true),
      "nested progress escaped its capture: " .. output)
end
return M
]=]
        ):format(dir .. "/run.lua")
    )
    write(
        dir .. "/host.lua",
        (
            [=[
rawset(_G, "__NUPP_TEST_PROGRESS_FD", 9)
arg = {[0] = %q, "outertest", "--jobs=1", "--no-color"}
dofile(arg[0])
]=]
        ):format(dir .. "/run.lua")
    )

    local output = dir .. "/output"
    local progress = dir .. "/progress"
    local status = os.execute(
        (MODULES .. "NUPP_TEST_PROGRESS_FD=9 luajit %q 9>%q >%q 2>&1"):format(dir .. "/host.lua", progress, output)
    )
    local result = read(output)
    test.assert(status == 0, "the outer runner failed after launching its nested runner: " .. result)
    test.matches(result, "1 tests, 1 passed, 0 skipped, 0 failed")
    os.execute("rm -rf " .. string.format("%q", dir))
end

function M.hidesPassingOutputUnlessVerbose()
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p " .. string.format("%q", dir)) == 0)
    write(dir .. "/run.lua", read(ROOT .. "/tests/run.lua"))
    write(dir .. "/assert.lua", read(ROOT .. "/tests/assert.lua"))
    write(
        dir .. "/noisytest.lua",
        [[
local M = {}
function M.writesToBothStreams()
   io.stdout:write("ordinary output\n")
   io.stderr:write("diagnostic output\n")
end
return M
]]
    )
    write(
        dir .. "/failuretest.lua",
        [[
local M = {}
function M.writesBeforeFailing()
   io.stdout:write("failing stdout\n")
   io.stderr:write("failing stderr\n")
   error("the intended failure")
end
return M
]]
    )

    -- This case is about captured output, not the runner's own worker fan-out.
    -- Keep its copied runner in one process so the Windows test does not nest a
    -- second MSYS/native subprocess boundary inside the matrix's serial run.
    local plain = run(dir .. "/run.lua", "--jobs=1")
    test.equal(plain:find("ordinary output", 1, true), nil, "passing stdout stays hidden")
    test.equal(plain:find("diagnostic output", 1, true), nil, "passing stderr stays hidden")
    test.matches(plain, "Output from failuretest / writesBeforeFailing")
    test.matches(plain, "failing stdout")
    test.matches(plain, "failing stderr")

    local verbose = run(dir .. "/run.lua", "--jobs=1 --verbose")
    test.matches(verbose, "ordinary output")
    test.matches(verbose, "diagnostic output")
    os.execute("rm -rf " .. string.format("%q", dir))
end

function M.runsNuppSuites()
    local output = run(ROOT .. "/tests/run.lua", "nupptest --json")
    test.matches(output, '"suite":"nupptest"')
    test.matches(output, '"name":"runsAsNupp"')
    test.matches(output, '"name":"requiresNuppProjectModules"')
end

-- Where the time went, which is the report a person asking why the suite takes
-- as long as it does is looking for. A suite costs more than its cases: this one
-- sleeps in `beforeAll`, so a report that only added the cases up would say the
-- suite was free.
function M.reportsWhereTheTimeWent()
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p " .. string.format("%q", dir)) == 0)
    write(dir .. "/run.lua", read(ROOT .. "/tests/run.lua"))
    write(dir .. "/assert.lua", read(ROOT .. "/tests/assert.lua"))
    write(
        dir .. "/slowtest.lua",
        [[
local M = {}
local function spin(seconds)
   local until_ = os.clock() + seconds
   while os.clock() < until_ do end
end
function M.beforeAll() spin(0.05) end
function M.quick() end
-- Keep a wide margin over captured-I/O jitter on loaded CI hosts. The assertion
-- below deliberately checks which case the runner identifies as slowest.
function M.slow() spin(0.5) end
for index = 1, 16 do
   M["captured" .. index] = function()
      io.stdout:write("passing captured stdout\n")
      io.stderr:write("passing captured stderr\n")
   end
end
return M
]]
    )

    local output = run(dir .. "/run.lua", "--jobs=1")
    test.equal(output:find("passing captured stdout", 1, true), nil, "repeated passing stdout stays captured")
    test.equal(output:find("passing captured stderr", 1, true), nil, "repeated passing stderr stays captured")
    test.matches(output, "slowest suites")
    test.matches(output, "slowest tests")
    test.matches(output, "slowtest%s+%d+%.?%d*m?s")
    test.matches(output, "slowtest / slow")

    -- The same run as data, where the suite's own cost is separable from its
    -- cases' rather than only rendered.
    local json = require("testjson")
    local decoded = json.decode(runJson(dir .. "/run.lua", "--jobs=1 --json"))
    test.equal(#decoded.suites, 1, "one suite record")
    local record = decoded.suites[1]
    test.equal(record.suite, "slowtest")
    test.equal(record.tests, 18)
    test.equal(record.slowestCase, "slow")
    test.assert(record.hooksMs >= 25, "beforeAll is measured with the suite")
    test.assert(
        record.durationMs >= record.casesMs + record.hooksMs - 1,
        "the suite is at least what its cases and hooks cost"
    )

    -- Asked for none, and the report is gone; the run still measured it.
    local quiet = run(dir .. "/run.lua", "--jobs=1 --timings=0")
    test.equal(quiet:find("slowest suites", 1, true), nil, "--timings=0 asks for no report")
    os.execute("rm -rf " .. string.format("%q", dir))
end

-- Slices are packed by what a case last cost, not by where it sits in the list.
-- One heavy case among cheap ones belongs on its own: the alternative is a slice
-- that carries it plus a share of the rest, which is the run's floor plus extra.
function M.slicesASuiteByWhatItsCasesCost()
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p " .. string.format("%q", dir .. "/tests")) == 0)
    assert(os.execute("mkdir -p " .. string.format("%q", dir .. "/build")) == 0)
    write(dir .. "/tests/run.lua", read(ROOT .. "/tests/run.lua"))
    write(dir .. "/tests/assert.lua", read(ROOT .. "/tests/assert.lua"))
    write(
        dir .. "/tests/slicedtest.lua",
        [[
local M = {}
function M.heavy() end
function M.alpha() end
function M.beta() end
function M.gamma() end
return M
]]
    )
    write(
        dir .. "/build/.nupp-test-times.json",
        [[
{"suites":{"slicedtest":1030},
 "cases":{"slicedtest":{"heavy":1000,"alpha":10,"beta":10,"gamma":10}}}
]]
    )

    local json = require("testjson")
    local first = json.decode(runJson(dir .. "/tests/run.lua", "--json --shard=slicedtest#0/2"))
    local second = json.decode(runJson(dir .. "/tests/run.lua", "--json --shard=slicedtest#1/2"))
    test.equal(#first.tests, 1, "the heavy case is a slice on its own")
    test.equal(first.tests[1].name, "heavy")
    test.equal(#second.tests, 3, "the cheap cases share the other slice")
    os.execute("rm -rf " .. string.format("%q", dir))
end

-- Who runs what is decided while the run is happening. Two workers pointed at one
-- queue divide it between them and neither runs a piece twice, which is what makes
-- an estimate that was wrong cost the difference rather than the whole imbalance.
function M.workersDivideAQueueBetweenThem()
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p " .. string.format("%q", dir .. "/tests")) == 0)
    assert(os.execute("mkdir -p " .. string.format("%q", dir .. "/queue")) == 0)
    write(dir .. "/tests/run.lua", read(ROOT .. "/tests/run.lua"))
    write(dir .. "/tests/assert.lua", read(ROOT .. "/tests/assert.lua"))
    for _, name in ipairs({"alpha", "beta", "gamma", "delta"}) do
        write(
            ("%s/tests/%stest.lua"):format(dir, name),
            ("local M = {}\nfunction M.only%s() end\nreturn M\n"):format(name)
        )
    end
    local order = {"alphatest", "betatest", "gammatest", "deltatest"}
    write(dir .. "/queue/order", table.concat(order, "\n") .. "\n")
    for index, spec in ipairs(order) do
        write(("%s/queue/piece-%d"):format(dir, index), spec .. "\n")
    end

    local json = require("testjson")
    local seen, ran = {}, 0
    for _ = 1, 2 do
        local report = json.decode(runJson(dir .. "/tests/run.lua", "--json --queue=" .. dir .. "/queue"))
        for _, spec in ipairs(report.claimed or {}) do
            test.equal(seen[spec], nil, spec .. " was claimed twice")
            seen[spec] = true
        end
        ran = ran + report.total
    end
    test.equal(ran, 4, "every piece ran exactly once")
    for _, spec in ipairs(order) do
        assert(seen[spec], spec .. " was never claimed")
    end
    os.execute("rm -rf " .. string.format("%q", dir))
end

function M.processQueueRestoresModuleGlobalsBetweenPieces()
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p " .. string.format("%q", dir .. "/tests/templater")) == 0)
    assert(os.execute("mkdir -p " .. string.format("%q", dir .. "/queue")) == 0)
    write(dir .. "/tests/run.lua", read(ROOT .. "/tests/run.lua"))
    write(dir .. "/tests/assert.lua", read(ROOT .. "/tests/assert.lua"))
    write(dir .. "/tests/templater/fill.lua", [[
module(..., package.seeall)
function render() return "ready" end
]])
    write(
        dir .. "/tests/templater.lua",
        [[
local renderer = require("templater.fill")
module(..., package.seeall)
fill = renderer.render
]]
    )
    for index, name in ipairs({"alphatest", "betatest"}) do
        write(
            dir .. "/tests/" .. name .. ".lua",
            [[
local M = {}
function M.renders()
    assert(require("templater").fill() == "ready")
end
return M
]]
        )
        write(("%s/queue/piece-%d"):format(dir, index), name .. "\n")
    end
    write(dir .. "/queue/order", "alphatest\nbetatest\n")
    local output = runJson(dir .. "/tests/run.lua", "--json --queue=" .. dir .. "/queue")
    local report = require("testjson").decode(output)
    test.equal(report.total, 2, "both queue pieces ran")
    test.equal(report.passed, 2, output)
    os.execute("rm -rf " .. string.format("%q", dir))
end

-- The queue hands one process several suites in turn, so what a piece leaves
-- behind is what the next piece starts from. Every shape of leak that has
-- actually cost a run is listed here: a module identity swapped for a decoy
-- (which is how the runner's own report decoder was once replaced), a module
-- loaded for the first time, a global invented, a global overwritten, and a
-- loader injected. Deterministic by construction -- the order file fixes which
-- piece runs first -- so this either holds or it does not, whatever the machine
-- is doing.
function M.processQueueLeavesNoPieceStateForTheNextOne()
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p " .. string.format("%q", dir .. "/tests")) == 0)
    assert(os.execute("mkdir -p " .. string.format("%q", dir .. "/queue")) == 0)
    write(dir .. "/tests/run.lua", read(ROOT .. "/tests/run.lua"))
    write(dir .. "/tests/assert.lua", read(ROOT .. "/tests/assert.lua"))
    write(dir .. "/tests/lanevictim.lua", "return {loadedBy = \"the first piece\"}\n")
    write(
        dir .. "/tests/adirtiestest.lua",
        [[
local M = {}
function M.leavesEveryShapeOfStateBehind()
    _G.laneLeakedGlobal = "left behind"
    _G._VERSION = "contaminated"
    package.preload["lane.injected"] = function() return {} end
    package.loaded["lane.hijacked"] = {"a decoy nothing ever loaded"}
    assert(require("lanevictim").loadedBy == "the first piece")
end
return M
]]
    )
    write(
        dir .. "/tests/bcleantest.lua",
        [[
local M = {}
function M.startsFromTheProcessTheRunnerBeganWith()
    assert(rawget(_G, "laneLeakedGlobal") == nil, "a global the previous piece invented")
    assert(_VERSION ~= "contaminated", "a global the previous piece overwrote")
    assert(package.preload["lane.injected"] == nil, "a loader the previous piece injected")
    assert(package.loaded["lane.hijacked"] == nil, "a module table the previous piece invented")
    assert(package.loaded["lanevictim"] == nil, "a module the previous piece loaded")
end
return M
]]
    )
    write(dir .. "/queue/order", "adirtiestest\nbcleantest\n")
    write(dir .. "/queue/piece-1", "adirtiestest\n")
    write(dir .. "/queue/piece-2", "bcleantest\n")
    local output = runJson(dir .. "/tests/run.lua", "--json --queue=" .. dir .. "/queue")
    local report = require("testjson").decode(output)
    test.equal(report.total, 2, "both queue pieces ran" .. "\n" .. output)
    test.equal(report.passed, 2, output)
    os.execute("rm -rf " .. string.format("%q", dir))
end

function M.embeddedWorkersDiscoverFromTheParentCatalogWithoutPopen()
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p " .. string.format("%q", dir .. "/queue")) == 0)
    write(dir .. "/run.lua", read(ROOT .. "/tests/run.lua"))
    write(dir .. "/assert.lua", read(ROOT .. "/tests/assert.lua"))
    write(dir .. "/catalogtest.lua", [[
local M = {}
function M.passes() end
return M
]])
    write(dir .. "/queue/order", "catalogtest\n")
    write(dir .. "/queue/piece-1", "catalogtest\n")
    write(
        dir .. "/host.lua",
        (
            [=[
rawset(_G, "__NUPP_TEST_EMBEDDED", true)
rawset(_G, "__NUPP_TEST_SUITE_CATALOG", "catalogtest.lua")
io.popen = function() error("worker discovery called popen", 0) end
arg = {[0] = %q, "--json", "--queue=" .. %q, "--no-color"}
local report = dofile(arg[0])
io.write(report.total, "\n", report.tests[1].name, "\n")
]=]
        ):format(dir .. "/run.lua", dir .. "/queue")
    )

    local output = run(dir .. "/host.lua")
    test.equal(output, ".\n1\npasses\n", "the catalogued suite ran")
    os.execute("rm -rf " .. string.format("%q", dir))
end

function M.runsLifecycleHooksInOrder()
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p " .. string.format("%q", dir)) == 0)
    local trace = dir .. "/trace"
    write(dir .. "/run.lua", read(ROOT .. "/tests/run.lua"))
    write(dir .. "/assert.lua", read(ROOT .. "/tests/assert.lua"))
    write(
        dir .. "/lifecycletest.lua",
        (
            [[
local M = {}
local trace = %q
local function mark(name)
   local f = assert(io.open(trace, "ab"))
   f:write(name, "\n")
   f:close()
end
function M.beforeAll() mark("beforeAll") end
function M.beforeEach() mark("beforeEach") end
function M.alpha() mark("alpha") end
function M.beta() mark("beta") end
function M.afterEach() mark("afterEach") end
function M.afterAll() mark("afterAll") end
return M
]]
        ):format(trace)
    )

    local output = run(dir .. "/run.lua", "lifecycletest")
    test.matches(output, "2 tests, 2 passed, 0 skipped, 0 failed")
    test.equal(
        read(trace),
        table.concat(
            {"beforeAll", "beforeEach", "alpha", "afterEach", "beforeEach", "beta", "afterEach", "afterAll", "",},
            "\n"
        )
    )
    os.execute("rm -rf " .. string.format("%q", dir))
end

function M.runsTeardownAfterFailures()
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p " .. string.format("%q", dir)) == 0)
    local trace = dir .. "/trace"
    write(dir .. "/run.lua", read(ROOT .. "/tests/run.lua"))
    write(dir .. "/assert.lua", read(ROOT .. "/tests/assert.lua"))
    write(
        dir .. "/cleanupfailtest.lua",
        (
            [[
local M = {}
local trace = %q
local function mark(name)
   local f = assert(io.open(trace, "ab"))
   f:write(name, "\n")
   f:close()
end
function M.beforeAll() mark("beforeAll") end
function M.beforeEach() mark("beforeEach") end
function M.fails() mark("test"); error("case failure") end
function M.afterEach() mark("afterEach"); error("cleanup failure") end
function M.afterAll() mark("afterAll") end
return M
]]
        ):format(trace)
    )

    local output = run(dir .. "/run.lua", "cleanupfailtest")
    test.matches(output, "case failure")
    test.matches(output, "afterEach failed: .-cleanup failure")
    test.equal(read(trace), "beforeAll\nbeforeEach\ntest\nafterEach\nafterAll\n")
    os.execute("rm -rf " .. string.format("%q", dir))
end

function M.runsTeardownAfterFailedSetup()
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p " .. string.format("%q", dir)) == 0)
    local trace = dir .. "/trace"
    write(dir .. "/run.lua", read(ROOT .. "/tests/run.lua"))
    write(dir .. "/assert.lua", read(ROOT .. "/tests/assert.lua"))
    write(
        dir .. "/setupcasefailtest.lua",
        (
            [[
local M = {}
local trace = %q
local function mark(name)
   local f = assert(io.open(trace, "ab"))
   f:write(name, "\n")
   f:close()
end
function M.beforeEach() mark("beforeEach"); error("case setup failure") end
function M.shouldNotRun() mark("test") end
function M.afterEach() mark("afterEach") end
function M.afterAll() mark("afterAll") end
return M
]]
        ):format(trace)
    )

    local output = run(dir .. "/run.lua", "setupcasefailtest")
    test.matches(output, "case setup failure")
    test.equal(read(trace), "beforeEach\nafterEach\nafterAll\n")
    os.execute("rm -rf " .. string.format("%q", dir))
end

function M.runsSuiteTeardownWhenSetupFails()
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p " .. string.format("%q", dir)) == 0)
    local trace = dir .. "/trace"
    write(dir .. "/run.lua", read(ROOT .. "/tests/run.lua"))
    write(dir .. "/assert.lua", read(ROOT .. "/tests/assert.lua"))
    write(
        dir .. "/setupfailtest.lua",
        (
            [[
local M = {}
local trace = %q
local function mark(name)
   local f = assert(io.open(trace, "ab"))
   f:write(name, "\n")
   f:close()
end
function M.beforeAll() mark("beforeAll"); error("setup failure") end
function M.shouldNotRun() mark("test") end
function M.afterAll() mark("afterAll") end
return M
]]
        ):format(trace)
    )

    local output = run(dir .. "/run.lua", "setupfailtest")
    test.matches(output, "setup failure")
    test.matches(output, "beforeAll")
    test.equal(read(trace), "beforeAll\nafterAll\n")
    os.execute("rm -rf " .. string.format("%q", dir))
end

return M
