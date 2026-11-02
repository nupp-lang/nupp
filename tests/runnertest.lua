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
local modulesRoot = os.getenv("NUPP_TEST_MODULES")
if not modulesRoot or modulesRoot == "" then
    modulesRoot = os.getenv("NUPP_COVERAGE_BUILD") or os.getenv("NUPP_TEST_BUILD") or "build"
    if not modulesRoot:match("^[/\\]") and not modulesRoot:match("^[A-Za-z]:[/\\]") then
        modulesRoot = ROOT .. "/" .. modulesRoot
    end
end
local MODULES = ("NUPP_TEST_MODULES=%q "):format(modulesRoot)

-- A copied Windows runner launched directly behind `io.popen` inherits OS pipe
-- handles without matching C-runtime descriptors, while its per-case capture
-- deliberately works at the descriptor layer. Give the copied runner ordinary
-- file-backed streams on every platform; `runJson` leaves standard error out of
-- the document because progress marks belong there.
local function runRedirected(path, args, stderr)
    local quoted = "'" .. path:gsub("'", "'\\''") .. "'"
    local outputPath = os.tmpname()
    local command = (
        MODULES .. "NUPP_TEST_BUILD=build luajit %s %s >%q %s"
    ):format(quoted, args or "", outputPath, stderr)
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
local test = require("assert")
local M = {}
function M.passes() test.eq(%q, %q) end
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
    test.eq(bundled.status, 0, "the bundled runner failed outside its checkout" .. evidence(bundled))
    local report = require("testjson").decode(output)
    test.eq(report.total, 2, "both external suites ran")
    test.eq(report.passed, 2, "both external suites passed")
    test.eq(#report.shards, 0, "the external run stayed serial")
    local timings = read(dir .. "/build/.nupp-test-times.json")
    test.matches(timings, '"alphatest"', "external timing history is persisted")
    test.matches(timings, '"betatest"', "every external suite is timed")
    os.execute("rm -rf " .. string.format("%q", dir))
end

function M.bundledRunnerCarriesStructuredCasesFixturesAndExactReruns()
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p " .. string.format("%q", dir .. "/tests")) == 0)
    assert(os.execute("mkdir -p " .. string.format("%q", dir .. "/src")) == 0)
    write(dir .. "/nupp.lua", 'return {include = {"src"}, build = {entries = {"main"}}}\n')
    write(dir .. "/src/main.nupp", "return true\n")
    local fixtureKey = "runner-" .. (dir:match("([^/\\]+)$") or "fixture"):gsub("[^A-Za-z0-9._-]", "-")
    write(
        dir .. "/tests/featuretest.lua",
        (
            [=[
local test = require("assert")
local M = test.suite.cases(
    {{name = "alpha", value = 20}, {name = "beta", value = 22}},
    function(row) return row.name end,
    function(row)
        local path, value, reused = test.suite.fixture(%q, function(directory)
            local count = assert(io.open("fixture-productions", "ab"))
            count:write("made\n")
            count:close()
            local artifact = assert(io.open(directory .. "/answer.txt", "wb"))
            artifact:write("42")
            artifact:close()
            return {answer = 42}
        end)
        local artifact = assert(io.open(path .. "/answer.txt", "rb"))
        test.eq(artifact:read("*a"), "42")
        artifact:close()
        test.eq(value.answer, 42)
        test.eq(type(reused), "boolean")
        test.suite.fact("example.witness", {row = row.name})
        test.suite.metric("source.bytes", row.value, "bytes")
        test.suite.work("semantic.cases", 1)
        test.suite.requirecapability("runtime.lua", true, {engine = _VERSION})
    end
)
function M.unavailable()
    test.suite.requirecapability("example.absent", false, {probe = "synthetic"})
end
return M
]=]
        ):format(fixtureKey)
    )
    write(dir .. "/tests/reruntest.lua", [[
return {fails = function() error("rerun sentinel") end}
]])
    write(
        dir .. "/tests/fixturepeertest.lua",
        (
            [=[
local test = require("assert")
return {peer = function()
    local path, value = test.suite.fixture(%q, function(directory)
        local count = assert(io.open("fixture-productions", "ab"))
        count:write("made\n")
        count:close()
        local artifact = assert(io.open(directory .. "/answer.txt", "wb"))
        artifact:write("42")
        artifact:close()
        return {answer = 42}
    end)
    test.eq(value.answer, 42)
    local artifact = assert(io.open(path .. "/answer.txt", "rb"))
    test.eq(artifact:read("*a"), "42")
    artifact:close()
end}
]=]
        ):format(fixtureKey)
    )
    write(
        dir .. "/tests/fixturefailuretest.lua",
        (
            [=[
local test = require("assert")
local function consume()
    test.suite.fixture(%q, function()
        local count = assert(io.open("failed-fixture-productions", "ab"))
        count:write("made\n")
        count:close()
        error("producer sentinel")
    end)
end
return {first = consume, second = consume}
]=]
        ):format(fixtureKey .. "-failure")
    )

    local command = ("cd %q && %q test featuretest fixturepeertest --jobs=2 --json 2>/dev/null"):format(dir, NUPP)
    local output, invocation = capturedRun(command)
    test.eq(invocation.status, 0, "structured runner case failed" .. evidence(invocation))
    local report = require("testjson").decode(output)
    test.eq(report.total, 4)
    test.eq(report.passed, 3)
    test.eq(report.notExecuted, 1)
    test.eq(report.tests[1].id, "featuretest/alpha")
    test.matches(report.tests[1].file, "tests[/\\]featuretest%.lua$")
    test.eq(report.tests[1].facts[1].name, "example.witness")
    test.eq(report.tests[1].fixtures[1].key, fixtureKey)
    test.eq(report.tests[3].status, "not-executed")
    test.eq(report.tests[3].capabilities[1].available, false)
    test.eq(report.metrics[1].name, "semantic.cases")
    test.eq(report.metrics[1].value, 2)
    test.eq(report.metrics[2].name, "source.bytes")
    test.eq(report.metrics[2].value, 42)
    local produced, reused = 0, 0
    for _, record in ipairs(report.tests) do
        for _, fixture in ipairs(record.fixtures or {}) do
            if fixture.reused then
                reused = reused + 1
            else
                produced = produced + 1
            end
        end
    end
    test.eq(produced, 1, "one case published the shared fixture")
    test.eq(reused, 2, "the other fixture consumers reported reuse")
    test.eq(read(dir .. "/fixture-productions"), "made\n", "the fixture was produced once across cases and workers")
    local fixturePath = report.tests[1].fixtures[1].path
    if not fixturePath:match("^[/\\]") and not fixturePath:match("^%a:[/\\]") then
        fixturePath = dir .. "/" .. fixturePath
    end
    local timingsBefore = require("testjson").decode(read(dir .. "/build/.nupp-test-times.json"))

    local listing, listed = capturedRun(("cd %q && %q test --list-cases 2>&1"):format(dir, NUPP))
    test.eq(listed.status, 0, "case listing failed" .. evidence(listed))
    test.matches(listing, "featuretest/alpha")
    test.matches(listing, "featuretest/unavailable")

    local filteredListing, filtered = capturedRun(
        ("cd %q && %q test --case=featuretest/beta --list-cases 2>&1"):format(dir, NUPP)
    )
    test.eq(filtered.status, 0, "filtered case listing failed" .. evidence(filtered))
    test.eq(filteredListing, "featuretest/beta\n")

    local exactOutput, exact = capturedRun(
        ("cd %q && %q test --case=featuretest/beta --jobs=1 --json 2>/dev/null"):format(dir, NUPP)
    )
    test.eq(exact.status, 0, "exact case selection failed" .. evidence(exact))
    local exactReport = require("testjson").decode(exactOutput)
    test.eq(exactReport.total, 1)
    test.eq(exactReport.tests[1].id, "featuretest/beta")
    test.eq(exactReport.tests[1].fixtures[1].reused, true)
    test.eq(read(dir .. "/fixture-productions"), "made\n", "the fixture was reused across runs")
    local timingsAfter = require("testjson").decode(read(dir .. "/build/.nupp-test-times.json"))
    test.eq(timingsAfter.suites.featuretest, timingsBefore.suites.featuretest)
    test.eq(timingsAfter.cases.featuretest.alpha, timingsBefore.cases.featuretest.alpha)
    test.eq(timingsAfter.cases.featuretest.unavailable, timingsBefore.cases.featuretest.unavailable)
    test(timingsAfter.cases.featuretest.beta ~= nil)

    test(os.remove(fixturePath .. "/answer.txt"))
    local rebuiltOutput, rebuilt = capturedRun(
        ("cd %q && %q test --case=featuretest/alpha --jobs=1 --json 2>/dev/null"):format(dir, NUPP)
    )
    test.eq(rebuilt.status, 0, "corrupt fixture recovery failed" .. evidence(rebuilt))
    local rebuiltReport = require("testjson").decode(rebuiltOutput)
    test.eq(rebuiltReport.tests[1].fixtures[1].reused, false)
    test.eq(read(fixturePath .. "/answer.txt"), "42")
    test.eq(read(dir .. "/fixture-productions"), "made\nmade\n", "a missing artifact forced one cold production")

    write(
        dir .. "/tests/fixturealiastest.lua",
        [[
local test = require("assert")
return {distinctKeys = function()
    local paths = {}
    for _, key in ipairs({"Case-Key", "case-key", "."}) do
        local path, value = test.suite.fixture(key, function(directory)
            local artifact = assert(io.open(directory .. "/value.txt", "wb"))
            artifact:write(key)
            artifact:close()
            return {key = key}
        end)
        paths[#paths + 1] = path
        test.eq(value.key, key)
    end
    test.ne(paths[1], paths[2])
    test.ne(paths[1], paths[3])
    test.ne(paths[2], paths[3])
end}
]]
    )
    local aliasOutput, aliasRun = capturedRun(
        ("cd %q && %q test fixturealiastest --jobs=1 --json 2>/dev/null"):format(dir, NUPP)
    )
    test.eq(aliasRun.status, 0, "fixture key aliases collided" .. evidence(aliasRun))
    local aliasReport = require("testjson").decode(aliasOutput)
    test.eq(aliasReport.passed, 1)

    write(
        dir .. "/infrastructure-failures.json",
        [[
{"schemaVersion":1,"tests":[
  {"id":"Nupp worker 1/<shard>","suite":"Nupp worker 1","name":"<shard>","status":"failed"},
  {"id":"featuretest/<unrun>","suite":"featuretest","name":"<unrun>","status":"failed"}
]}
]]
    )
    local infrastructureOutput, infrastructure = capturedRun(
        ("cd %q && %q test --rerun=infrastructure-failures.json --jobs=1 --json 2>/dev/null"):format(dir, NUPP)
    )
    test.eq(infrastructure.status, 0, "infrastructure-report rerun failed" .. evidence(infrastructure))
    local infrastructureReport = require("testjson").decode(infrastructureOutput)
    test.eq(infrastructureReport.total, 3)
    test.eq(infrastructureReport.notExecuted, 1)

    write(
        dir .. "/worker-only-failure.json",
        [[
{"schemaVersion":1,"tests":[
  {"id":"Nupp worker 1/<shard>","suite":"Nupp worker 1","name":"<shard>","status":"failed"}
]}
]]
    )
    local workerOnlyOutput, workerOnly = capturedRun(
        ("cd %q && %q test --rerun=worker-only-failure.json --jobs=1 2>&1"):format(dir, NUPP)
    )
    test.eq(workerOnly.status, 2, "a worker-only failure cannot select every suite" .. evidence(workerOnly))
    test.matches(workerOnlyOutput, "contains no rerunnable failed tests")

    local failedOutput, failed = capturedRun(
        ("cd %q && %q test reruntest --jobs=1 --json 2>/dev/null"):format(dir, NUPP)
    )
    test.eq(failed.status, 1, "the seed failure had the wrong status" .. evidence(failed))
    write(dir .. "/failures.json", failedOutput)
    local rerunOutput, rerun = capturedRun(
        ("cd %q && %q test --rerun=failures.json --jobs=1 --json 2>/dev/null"):format(dir, NUPP)
    )
    test.eq(rerun.status, 1, "failure-report rerun had the wrong status" .. evidence(rerun))
    local rerunReport = require("testjson").decode(rerunOutput)
    test.eq(rerunReport.total, 1)
    test.eq(rerunReport.tests[1].id, "reruntest/fails")

    local fixtureFailureOutput, fixtureFailure = capturedRun(
        ("cd %q && %q test fixturefailuretest --jobs=1 --json 2>/dev/null"):format(dir, NUPP)
    )
    test.eq(fixtureFailure.status, 1, "fixture failure fan-out had the wrong status" .. evidence(fixtureFailure))
    local fixtureFailureReport = require("testjson").decode(fixtureFailureOutput)
    test.eq(fixtureFailureReport.failed, 2)
    test.matches(fixtureFailureReport.tests[1].failure.message, "producer sentinel")
    test.matches(fixtureFailureReport.tests[2].failure.message, "producer sentinel")
    test.eq(
        read(dir .. "/failed-fixture-productions"),
        "made\n",
        "a failed fixture was produced once for every blocked case"
    )

    local retriedOutput, retried = capturedRun(
        ("cd %q && %q test fixturefailuretest --jobs=1 --json 2>/dev/null"):format(dir, NUPP)
    )
    test.eq(retried.status, 1, "fixture retry had the wrong status" .. evidence(retried))
    require("testjson").decode(retriedOutput)
    test.eq(
        read(dir .. "/failed-fixture-productions"),
        "made\nmade\n",
        "a new top-level run retried the failed fixture once"
    )

    local duplicate = test.raises(function()
        test.suite.cases(
            {1, 2},
            function()
                return "same"
            end,
            function()
            end
        )
    end)
    test.matches(tostring(duplicate), "duplicate parameterized case name")
    local unsafe = test.raises(function()
        test.suite.cases(
            {
                function()
                end
            },
            function()
                return "unsafe"
            end,
            function()
            end
        )
    end)
    test.matches(tostring(unsafe), "not serialization%-safe")
    local sparse = test.raises(function()
        test.suite.cases(
            {[1] = {name = "first"}, [3] = {name = "third"}},
            function(row)
                return row.name
            end,
            function()
            end
        )
    end)
    test.matches(tostring(sparse), "dense JSON%-compatible sequence")
    local mixed = test.raises(function()
        test.suite.cases(
            {{name = "mixed", value = {[1] = "array", label = "object"}}},
            function(row)
                return row.name
            end,
            function()
            end
        )
    end)
    test.matches(tostring(mixed), "not serialization%-safe")
    local reserved = test.raises(function()
        test.suite.cases(
            {{name = "beforeAll"}},
            function(row)
                return row.name
            end,
            function()
            end
        )
    end)
    test.matches(tostring(reserved), "reserved for a lifecycle hook")
    local runnerReserved = test.raises(function()
        test.suite.cases(
            {{name = "<unrun>"}},
            function(row)
                return row.name
            end,
            function()
            end
        )
    end)
    test.matches(tostring(runnerReserved), "reserved by the test runner")
    local control = test.raises(function()
        test.suite.cases(
            {{name = "line\nbreak"}},
            function(row)
                return row.name
            end,
            function()
            end
        )
    end)
    test.matches(tostring(control), "must not contain control characters")
    os.execute("rm -rf " .. string.format("%q", dir))
end

function M.bundledRunnerRecoversStaleFixtureLeasesAndKeepsFreshOnes()
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p " .. string.format("%q", dir .. "/tests")) == 0)
    local digest = require("nupp.compiler.project.fingerprint").contentDigest(true)

    local function fixtureSlot(key)
        return dir .. "/build/test-fixtures/fixture-" .. digest("nupp-test-fixture\0" .. key)
    end

    assert(os.execute("mkdir -p " .. string.format("%q", fixtureSlot("wrong-shape"))) == 0)
    assert(os.execute("mkdir -p " .. string.format("%q", fixtureSlot("malformed"))) == 0)
    write(dir .. "/tests/run.lua", read(ROOT .. "/tests/run.lua"))

    write(
        dir .. "/tests/stalefixtest.lua",
        [[
local test = require("assert")
local function fixture(key)
    local _, value, reused = test.suite.fixture(key, function()
        return {answer = 42}
    end)
    test.eq(value.answer, 42)
    test.eq(reused, false)
end
return {
    recoversInvalidStaleLease = function() fixture("invalid-stale") end,
    recoversStaleLease = function() fixture("stale-fixture") end,
    recoversWrongShapedMetadata = function() fixture("wrong-shape") end,
    recoversMalformedMetadata = function() fixture("malformed") end,
}
]]
    )
    write(fixtureSlot("stale-fixture") .. ".lock", tostring(os.time() - 16 * 60) .. "\n")
    write(fixtureSlot("invalid-stale") .. ".lock", "not-a-timestamp\n")
    assert(os.execute("touch -t 200001010000 " .. string.format("%q", fixtureSlot("invalid-stale") .. ".lock")) == 0)
    write(fixtureSlot("fresh-fixture") .. ".lock", "not-a-timestamp\n")
    write(fixtureSlot("wrong-shape") .. "/.nupp-fixture.json", '"not fixture metadata"\n')
    write(fixtureSlot("malformed") .. "/.nupp-fixture.json", "{not-json\n")

    local output, invocation = capturedRun(
        (
            "cd %q && %sNUPP_TEST_BUILD=%q %q stalefixtest --jobs=1 --json 2>/dev/null"
        ):format(dir, MODULES, dir .. "/build", ROOT .. "/build/nupp-test")
    )
    test.eq(invocation.status, 0, "stale fixture lease was not recovered" .. evidence(invocation))
    local report = require("testjson").decode(output)
    test.eq(report.total, 4)
    for _, record in ipairs(report.tests) do
        test.eq(record.fixtures[1].reused, false)
    end
    test.eq(require("testjson").decode(read(fixtureSlot("wrong-shape") .. "/.nupp-fixture.json")).version, 1)
    test.eq(require("testjson").decode(read(fixtureSlot("malformed") .. "/.nupp-fixture.json")).version, 1)
    test.eq(io.open(fixtureSlot("stale-fixture") .. ".lock", "rb"), nil)
    test.eq(io.open(fixtureSlot("invalid-stale") .. ".lock", "rb"), nil)
    local fresh = assert(io.open(fixtureSlot("fresh-fixture") .. ".lock", "rb"))
    fresh:close()
    os.execute("rm -rf " .. string.format("%q", dir))
end

-- A fixture's lock names the process producing it, and the wait follows that
-- process rather than the clock. A consumer gave up after 944 s on a producer
-- that was still compiling wasmtime from source, and told the user to delete a
-- lock that was live; a new run likewise reaped any lock fifteen minutes old,
-- however alive its holder. Now a live holder is waited on whatever its age, and
-- one that has exited without publishing is reclaimed at once rather than after
-- ten minutes.
function M.fixtureWaitsFollowTheProducerNotTheClock()
    if package.config:sub(1, 1) == "\\" then
        return test.suite.skip("the holders here are POSIX background processes")
    end
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p " .. string.format("%q", dir .. "/tests")) == 0)
    local digest = require("nupp.compiler.project.fingerprint").contentDigest(true)

    local function fixtureSlot(key)
        return dir .. "/build/test-fixtures/fixture-" .. digest("nupp-test-fixture\0" .. key)
    end

    assert(os.execute("mkdir -p " .. string.format("%q", dir .. "/build/test-fixtures")) == 0)
    write(dir .. "/tests/run.lua", read(ROOT .. "/tests/run.lua"))

    -- A process that has exited: its id names nobody by the time a lock does.
    assert(os.execute(("sh -c 'echo $$' > %q"):format(dir .. "/dead.pid")) == 0)
    local dead = tonumber(read(dir .. "/dead.pid"):match("%d+"))
    write(
        dir .. "/tests/holderfixtest.lua",
        (
            [[
local test = require("assert")
local function produce(key)
    local started = os.time()
    local _, value, reused = test.suite.fixture(key, function()
        return {answer = 42}
    end)
    test.eq(value.answer, 42)
    test.eq(reused, false)
    return os.time() - started
end
return {
    waitsOnALiveHolderWhateverItsAge = function()
        -- The holder runs until this says otherwise, two seconds from now.
        assert(os.execute(("(sleep 2; touch %%q) </dev/null >/dev/null 2>&1 &"):format(%q)) == 0)
        local waited = produce("live-holder")
        test(waited >= 1, "a live producer's lock was reaped after " .. waited .. "s")
    end,
    reclaimsAnExitedHoldersLock = function()
        local lock = assert(io.open(%q, "wb"))
        lock:write(os.time(), " ", %d, "\n")
        lock:close()
        local waited = produce("exited-holder")
        test(waited <= 5, "an exited producer's lock held its consumer for " .. waited .. "s")
    end,
}
]]
        ):format(dir .. "/release", fixtureSlot("exited-holder") .. ".lock", dead)
    )
    -- Sixteen minutes old, which alone made a lock stale, and held by a process
    -- that runs until the case releases it.
    assert(
        os.execute(
            (
                "sh -c 'while [ ! -f %q ]; do sleep 0.2; done' </dev/null >/dev/null 2>&1 & echo $! > %q"
            ):format(dir .. "/release", dir .. "/live.pid")
        ) == 0
    )
    local live = tonumber(read(dir .. "/live.pid"):match("%d+"))
    write(fixtureSlot("live-holder") .. ".lock", ("%d %d\n"):format(os.time() - 16 * 60, live))

    local output, invocation = capturedRun(
        (
            "cd %q && %sNUPP_TEST_BUILD=%q %q holderfixtest --jobs=1 --json 2>/dev/null"
        ):format(dir, MODULES, dir .. "/build", ROOT .. "/build/nupp-test")
    )
    write(dir .. "/release", "")
    test.eq(invocation.status, 0, "fixture locks were not judged by their holders" .. evidence(invocation))
    local report = require("testjson").decode(output)
    test.eq(report.passed, 2)
    test.eq(io.open(fixtureSlot("live-holder") .. ".lock", "rb"), nil)
    test.eq(io.open(fixtureSlot("exited-holder") .. ".lock", "rb"), nil)
    os.execute("rm -rf " .. string.format("%q", dir))
end

-- A temporary name a case makes into a directory, and fills, goes with the run
-- that handed it out. Only the empty ones used to: a populated project at such a
-- name outlived every run, and runs left some forty thousand of them behind until
-- a fixpoint failed for want of a unique temporary name.
function M.aTemporaryDirectoryACaseFillsIsRemovedWithItsRun()
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p " .. string.format("%q", dir .. "/tests")) == 0)
    assert(os.execute("mkdir -p " .. string.format("%q", dir .. "/build")) == 0)
    write(dir .. "/tests/run.lua", read(ROOT .. "/tests/run.lua"))

    write(
        dir .. "/tests/tempdirtest.lua",
        [[
return {fillsATemporaryDirectory = function()
    local project = os.tmpname()
    os.remove(project)
    assert(os.execute(("mkdir -p %q"):format(project .. "/src/deeper")) == 0)
    local file = assert(io.open(project .. "/src/deeper/main.nupp", "wb"))
    file:write("print(1)\n")
    file:close()
    local named = assert(io.open("made", "wb"))
    named:write(project)
    named:close()
end}
]]
    )
    local _, invocation = capturedRun(
        (
            "cd %q && %sNUPP_TEST_BUILD=%q %q tempdirtest --jobs=1 --json 2>/dev/null"
        ):format(dir, MODULES, dir .. "/build", ROOT .. "/build/nupp-test")
    )
    test.eq(invocation.status, 0, "the case failed" .. evidence(invocation))
    local made = read(dir .. "/made")
    local left = io.open(made .. "/src/deeper/main.nupp", "rb")
    if left then
        left:close()
        os.execute("rm -rf " .. string.format("%q", made))
    end
    test.eq(left, nil, made .. " outlived the run that handed it out")
    os.execute("rm -rf " .. string.format("%q", dir))
end

function M.exactCasesAreValidatedBeforeHooksOrCasesRun()
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p " .. string.format("%q", dir .. "/tests")) == 0)
    assert(os.execute("mkdir -p " .. string.format("%q", dir .. "/build")) == 0)
    write(dir .. "/tests/run.lua", read(ROOT .. "/tests/run.lua"))

    write(
        dir .. "/tests/hookselecttest.lua",
        [[
local function mark(name)
    local file = assert(io.open(name, "wb"))
    file:write("ran")
    file:close()
end
return {
    beforeAll = function() mark("before-ran") end,
    present = function() mark("case-ran") end,
    afterAll = function() mark("after-ran") end,
}
]]
    )
    local output, invocation = capturedRun(
        (
            "cd %q && %sNUPP_TEST_BUILD=%q %q --case=hookselecttest/present --case=hookselecttest/missing --jobs=1 2>&1"
        ):format(dir, MODULES, dir .. "/build", ROOT .. "/build/nupp-test")
    )
    test.eq(invocation.status, 2, "a missing exact case had the wrong status" .. evidence(invocation))
    test.matches(output, "no test case named hookselecttest/missing")
    test.eq(io.open(dir .. "/before-ran", "rb"), nil)
    test.eq(io.open(dir .. "/case-ran", "rb"), nil)
    test.eq(io.open(dir .. "/after-ran", "rb"), nil)

    local exactOutput, exact = capturedRun(
        (
            "cd %q && %sNUPP_TEST_BUILD=%q %q --case=hookselecttest/present --jobs=1 --json 2>/dev/null"
        ):format(dir, MODULES, dir .. "/build", ROOT .. "/build/nupp-test")
    )
    test.eq(exact.status, 0, "a valid exact case failed during load accounting" .. evidence(exact))
    local exactReport = require("testjson").decode(exactOutput)
    test.eq(exactReport.tests[1].id, "hookselecttest/present")
    test(exactReport.suites[1].durationMs >= exactReport.suites[1].loadMs)
    test.eq(read(dir .. "/before-ran"), "ran")
    test.eq(read(dir .. "/case-ran"), "ran")
    test.eq(read(dir .. "/after-ran"), "ran")

    write(dir .. "/tests/invalidnametest.lua", 'return {[""] = function() end}\n')
    local invalidOutput, invalid = capturedRun(
        (
            "cd %q && %sNUPP_TEST_BUILD=%q %q invalidnametest --list-cases 2>&1"
        ):format(dir, MODULES, dir .. "/build", ROOT .. "/build/nupp-test")
    )
    test.eq(invalid.status, 1, "an invalid handwritten case name was accepted" .. evidence(invalid))
    test.matches(invalidOutput, "case whose name is not a non%-empty string")
    os.execute("rm -rf " .. string.format("%q", dir))
end

function M.failureReportRerunsTheWholeSuiteForLifecycleHookFailures()
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p " .. string.format("%q", dir .. "/tests")) == 0)
    assert(os.execute("mkdir -p " .. string.format("%q", dir .. "/build")) == 0)
    write(dir .. "/tests/run.lua", read(ROOT .. "/tests/run.lua"))

    write(
        dir .. "/tests/hookreruntest.lua",
        [[
return {
    beforeAll = function()
        local allowed = io.open("hook-allowed", "rb")
        if not allowed then error("hook sentinel") end
        allowed:close()
    end,
    caseRunsAfterRepair = function()
        local marker = assert(io.open("case-ran", "wb"))
        marker:write("yes")
        marker:close()
    end,
}
]]
    )
    local failedOutput, failed = capturedRun(
        (
            "cd %q && %sNUPP_TEST_BUILD=%q %q hookreruntest --jobs=1 --json 2>/dev/null"
        ):format(dir, MODULES, dir .. "/build", ROOT .. "/build/nupp-test")
    )
    test.eq(failed.status, 1, "lifecycle seed failure had the wrong status" .. evidence(failed))
    local failedReport = require("testjson").decode(failedOutput)
    test.eq(failedReport.tests[1].id, "hookreruntest/beforeAll")
    write(dir .. "/failures.json", failedOutput)
    write(dir .. "/hook-allowed", "yes")
    local rerunOutput, rerun = capturedRun(
        (
            "cd %q && %sNUPP_TEST_BUILD=%q %q --rerun=failures.json --jobs=1 --json 2>/dev/null"
        ):format(dir, MODULES, dir .. "/build", ROOT .. "/build/nupp-test")
    )
    test.eq(rerun.status, 0, "lifecycle rerun failed" .. evidence(rerun))
    local report = require("testjson").decode(rerunOutput)
    test.eq(report.total, 1)
    test.eq(report.tests[1].id, "hookreruntest/caseRunsAfterRepair")
    test.eq(read(dir .. "/case-ran"), "yes")
    os.execute("rm -rf " .. string.format("%q", dir))
end

function M.invalidStructuredMetadataFailsOneCaseWithoutBreakingJson()
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p " .. string.format("%q", dir .. "/tests")) == 0)
    write(dir .. "/tests/run.lua", read(ROOT .. "/tests/run.lua"))

    write(
        dir .. "/tests/metadatatest.lua",
        [[
local test = require("assert")
return {invalid = function()
    local evidence = {probe = "valid"}
    test.suite.requirecapability("runtime.synthetic", true, evidence)
    evidence.callback = function() end
end}
]]
    )
    local output, invocation = capturedRun(
        (
            "cd %q && %sNUPP_TEST_BUILD=%q %q metadatatest --jobs=1 --json 2>/dev/null"
        ):format(dir, MODULES, dir .. "/build", ROOT .. "/build/nupp-test")
    )
    test.eq(invocation.status, 1, "invalid metadata did not fail its case" .. evidence(invocation))
    local report = require("testjson").decode(output)
    test.eq(report.failed, 1)
    test.matches(report.tests[1].failure.message, "metadata is not JSON%-compatible")
    test.eq(report.tests[1].capabilities, nil)
    os.execute("rm -rf " .. string.format("%q", dir))
end

function M.workerJobsRefillTheCanonicalArgvBetweenRuns()
    local job = require("job")
    local argv = require("io.cli").args
    local originalArg = arg
    local originalMeta = getmetatable(argv)
    local originalValues = {}
    for key, value in pairs(argv) do
        originalValues[key] = value
    end
    local originalLoadfile = loadfile
    local originalExecute, originalPopen, originalGetenv = os.execute, io.popen, os.getenv
    local names = {
        "__NUPP_TEST_EMBEDDED",
        "__NUPP_TEST_PROGRESS_FD",
        "__NUPP_TEST_LANE_CACHE",
        "__NUPP_TEST_SUITE_CATALOG",
    }
    local originals = {}
    for _, name in ipairs(names) do
        originals[name] = rawget(_G, name)
    end
    local ok, problem = xpcall(
        function()
            local paths = {}
            loadfile = function(path)
                paths[#paths + 1] = path
                return function()
                    return {argument = argv[2], verbose = argv[4]}
                end
            end
            rawset(argv, -17, "old interpreter token")
            rawset(argv, 50, "old job token")
            rawset(argv, "oldJob", "old metadata")

            local first = job.run("--queue=first", "first-cache", nil, true, "never", "first-catalog")
            test.eq(first.argument, "--queue=first")
            test.eq(first.verbose, "--verbose")
            test.eq(argv[-17], nil)
            test.eq(argv[50], nil)
            test.eq(rawget(argv, "oldJob"), nil)

            local second = job.run("--queue=second", "second-cache", nil, false, "always", "second-catalog")
            test.eq(second.argument, "--queue=second")
            test.eq(second.verbose, nil, "the prior job's optional token was removed")
            test.eq(argv[0], "tests/run.lua")
            test.eq(argv[1], "--json")
            test.eq(argv[3], "--color=always")
            test.eq(paths[1], "tests/run.lua")
            test.eq(paths[2], "tests/run.lua")
            test.eq(arg, originalArg, "worker jobs retain the raw argv object")
            test.eq(require("io.cli").args, argv, "the CLI exposes the current raw argv object")
            test.eq(getmetatable(argv), originalMeta, "the raw argv metatable is unchanged")
        end,
        debug.traceback
    )

    loadfile = originalLoadfile
    arg = originalArg
    os.execute, io.popen, os.getenv = originalExecute, originalPopen, originalGetenv
    for key in pairs(argv) do
        rawset(argv, key, nil)
    end
    for key, value in pairs(originalValues) do
        rawset(argv, key, value)
    end
    for _, name in ipairs(names) do
        rawset(_G, name, originals[name])
    end
    test(ok, problem)
end

function M.workerHostDogfoodsNuppWorkersForOrdinarySuites()
    local ordinary, ordinaryRun = runWorkerHost("lexertest --timings=0")
    test.eq(ordinaryRun.status, 0, "the worker host run succeeded" .. evidence(ordinaryRun))
    test.matches(ordinary, "1 suites across 2 Nupp workers")
    local total, passed = ordinary:match("(%d+) tests, (%d+) passed")
    assert(total ~= nil and passed ~= nil, "worker summary is missing: " .. ordinary)
    test.eq(total, passed, "every discovered lexer test passed")
    test.eq(
        ordinary:find(".................", 1, true),
        nil,
        "parallel progress is one mark per suite slice, not one per case"
    )

    local popen, popenRun = runWorkerHost("absoluteentrytest --lane=shell --jobs=1 --timings=0")
    test.eq(popenRun.status, 0, "the popen run succeeded" .. evidence(popenRun))
    test.matches(popen, "1 shell suites across 1 process workers")
    test.matches(popen, "1 tests, 1 passed")

    local isolated, isolatedRun = runWorkerHost("processnativetest --lane=isolated --timings=0")
    test.eq(isolatedRun.status, 0, "the isolated run succeeded" .. evidence(isolatedRun))
    test.eq(isolated:find("Nupp workers", 1, true), nil, "the native process suite stays off the mechanism it tests")
    test.matches(isolated, "11 tests, 11 passed")
end

function M.shellingFailureStaysInsideItsTestOnAProcessWorker()
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p " .. string.format("%q", dir .. "/tests")) == 0)
    write(dir .. "/tests/run.lua", read(ROOT .. "/tests/run.lua"))

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

    test.eq(invocation.status, 1, "the failed test made the run fail" .. evidence(invocation))
    test.eq(#report.shards, 2, "the two shelling slices ran on reusable workers")
    test.eq(report.total, 2, "the worker ran both tests")
    test.eq(report.failed, 1, "the command failure failed one test")
    test.eq(report.passed, 1, "the worker continued to the next test")
    test.eq(report.tests[1].suite, "shellingtest")
    test.matches(report.tests[1].failure.message, "the shell command failed as intended")
    test.eq(report.tests[2].suite, "shellingtest")
    test.eq(report.tests[2].status, "passed")
    os.execute("rm -rf " .. string.format("%q", dir))
end

function M.processAndNuppWorkersRunAtTheSameTime()
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p " .. string.format("%q", dir .. "/tests")) == 0)
    write(dir .. "/tests/run.lua", read(ROOT .. "/tests/run.lua"))

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
if false then require("debug.profile") end
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

    test.eq(invocation.status, 0, "the overlapping run succeeded" .. evidence(invocation))
    test.eq(report.total, 3, "all three execution lanes ran")
    test.eq(report.passed, 3, "isolated work ran first and shell work overlapped")
    test.eq(#report.shards, 6, "each execution lane reported both planned slices")
    local reportedLanes = {}
    for _, suite in ipairs(report.suites) do
        if suite.executionLane then
            reportedLanes[suite.executionLane] = true
        end
    end
    test(reportedLanes.isolated and reportedLanes.shared and reportedLanes.shell)
    os.execute("rm -rf " .. string.format("%q", dir))
end

function M.nestedRunnerTemporaryNamesStayProcessDistinct()
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p " .. string.format("%q", dir .. "/tests")) == 0)
    write(dir .. "/tests/run.lua", read(ROOT .. "/tests/run.lua"))

    write(
        dir .. "/tests/tempnametest.lua",
        [[
return {names = function()
    local name = os.tmpname()
    local output = assert(io.open(assert(os.getenv("NUPP_TEST_TEMP_OUTPUT")), "wb"))
    output:write(name)
    output:close()
end}
]]
    )

    local cache = dir .. "/shard-7"

    local function invoke(output)
        local command = (
            "cd %q && NUPP_TEST_TEMP_OUTPUT=%q NUPP_CACHE_DIR=%q %sNUPP_TEST_BUILD=%q "
            .. "%q tempnametest --jobs=1 --json 2>/dev/null"
        ):format(dir, output, cache, MODULES, dir .. "/build", ROOT .. "/build/nupp-test")
        local document, invocation = capturedRun(command)
        test.eq(invocation.status, 0, "the nested runner succeeded" .. evidence(invocation))
        test.eq(require("testjson").decode(document).passed, 1)
    end

    local first = dir .. "/first-name"
    local second = dir .. "/second-name"
    invoke(first)
    invoke(second)
    test(read(first) ~= read(second), "separate runner processes reserve distinct temporary names")
    test.eq(io.open(read(first), "rb"), nil, "a runner removes unused temporary reservations on exit")
    test.eq(io.open(read(second), "rb"), nil, "each runner cleans its own temporary reservations")
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
    test(a and b and together, "each run reports a count" .. runs)
    test.eq(together, a + b, "naming two suites runs both of them" .. runs)
end

function M.aNameMatchingNoSuiteIsAFailure()
    -- Discovering nothing and reporting it green is the shape of this that hurts:
    -- a typo in a suite name reads exactly like a suite that passed.
    local out, missing = runWorkerHost("nosuchsuitetest --timings=0")
    test.matches(out, "no tests were discovered")
    test.eq(missing.status, 1, "discovering nothing exits unsuccessfully" .. evidence(missing))
end

-- A report fed to --rerun is read by a later runner than the one that wrote it.
-- One of another schema version is refused, naming both, rather than read as
-- though its records meant what this runner's do.
function M.aRerunRefusesAReportOfAnotherSchemaVersion()
    local path = os.tmpname()
    for _, case in ipairs({
        {'"schemaVersion":0,', "is a test report of schema version 0"},
        {"", "has no schema version"},
    }) do
        write(
            path,
            "{" .. case[1] .. '"tests":[{"id":"reruntest/fails","suite":"reruntest","name":"fails","status":"failed"}]}'
        )
        local output, invocation = runWorkerHost(("--rerun=%s --timings=0"):format(path))
        test.eq(invocation.status, 2, "a report of another schema version was rerun" .. evidence(invocation))
        test.matches(output, case[2])
        test.matches(output, "this runner reads schema version 1")
    end
    os.remove(path)
end

function M.unknownRunnerOptionIsRejectedBeforeDiscovery()
    local output, invocation = runWorkerHost(
        "--exact=simdobligationtest/nativeMatrixEvidenceMigratesIntoCompactObligations --timings=0"
    )
    test.eq(invocation.status, 2, "an unknown runner option exits with usage status" .. evidence(invocation))
    test.matches(
        output,
        "unknown test option: %-%-exact=simdobligationtest/nativeMatrixEvidenceMigratesIntoCompactObligations"
    )
    test.eq(output:find("suites across", 1, true), nil, "an unknown option does not start the suite")
end

function M.indirectSimdProcessesUseTheReusableShellLane()
    local shell, shellRun = runWorkerHost("--lane=shell --list-suites")
    test.eq(shellRun.status, 0, "shell lane listing failed" .. evidence(shellRun))
    test.matches(shell, "simdnativealgorithmdifferentialtest")
    test.matches(shell, "simdprimitivedifferentialtest")
    test.matches(shell, "simdwasmalgorithmdifferentialtest")
    test.matches(shell, "simdwasmtimeconformancetest")

    local shared, sharedRun = runWorkerHost("--lane=shared --list-suites")
    test.eq(sharedRun.status, 0, "shared lane listing failed" .. evidence(sharedRun))
    test.matches(shared, "simdreducerdifferentialtest")
end

function M.fixedWidthRuntimeUsesTheFreshProcessLane()
    local isolated, isolatedRun = runWorkerHost("--lane=isolated --list-suites")
    test.eq(isolatedRun.status, 0, "isolated lane listing failed" .. evidence(isolatedRun))
    test.matches(isolated, "fixedwidthtest")

    local shell, shellRun = runWorkerHost("--lane=shell --list-suites")
    test.eq(shellRun.status, 0, "shell lane listing failed" .. evidence(shellRun))
    test.eq(shell:find("fixedwidthtest", 1, true), nil, "fixed-width runtime checks do not reuse a shell process")
end

function M.caseSlicesDetermineShellWorkerCount()
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p " .. string.format("%q", dir .. "/tests")) == 0)
    assert(os.execute("mkdir -p " .. string.format("%q", dir .. "/build")) == 0)
    write(dir .. "/tests/run.lua", read(ROOT .. "/tests/run.lua"))

    write(
        dir .. "/tests/shellingtest.lua",
        [[
local M = {}
function M.alpha() assert(os.execute("exit 0") == 0) end
function M.beta() assert(os.execute("exit 0") == 0) end
function M.gamma() assert(os.execute("exit 0") == 0) end
function M.delta() assert(os.execute("exit 0") == 0) end
return M
]]
    )
    write(
        dir .. "/build/.nupp-test-times.json",
        [[
{"suites":{"shellingtest":4000},
 "cases":{"shellingtest":{"alpha":1000,"beta":1000,"gamma":1000,"delta":1000}}}
]]
    )
    local command = (
        "cd %q && %sNUPP_TEST_BUILD=%q %q shellingtest --lane=shell --jobs=4 --timings=0 --no-color 2>&1"
    ):format(dir, MODULES, dir .. "/build", ROOT .. "/build/nupp-test")
    local output, invocation = capturedRun(command)
    test.eq(invocation.status, 0, "the sliced shell suite succeeded" .. evidence(invocation))
    test.matches(output, "1 shell suites across 2 process workers")
    test.matches(output, "4 tests, 4 passed")
    os.execute("rm -rf " .. string.format("%q", dir))
end

function M.workerHostColorsOnlyWhenAskedDownAPipe()
    local colored, coloredRun = runWorkerHost("lexertest --timings=0 --color=always")
    test(colored:find("\27[", 1, true), "--color=always paints runner output" .. evidence(coloredRun))

    local plain, plainRun = runWorkerHost("lexertest --timings=0 --no-color")
    test.eq(plain:find("\27[", 1, true), nil, "--no-color keeps redirected runner output plain" .. evidence(plainRun))
end

function M.embeddedWorkersDoNotPassTheirProgressDescriptorToNestedRunners()
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p " .. string.format("%q", dir)) == 0)
    write(dir .. "/run.lua", read(ROOT .. "/tests/run.lua"))

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
        (
            MODULES .. "NUPP_TEST_BUILD=build NUPP_TEST_PROGRESS_FD=9 luajit %q 9>%q >%q 2>&1"
        ):format(dir .. "/host.lua", progress, output)
    )
    local result = read(output)
    test(status == 0, "the outer runner failed after launching its nested runner: " .. result)
    test.matches(result, "1 tests, 1 passed, 0 skipped, 0 failed")
    os.execute("rm -rf " .. string.format("%q", dir))
end

function M.hidesPassingOutputUnlessVerbose()
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p " .. string.format("%q", dir)) == 0)
    write(dir .. "/run.lua", read(ROOT .. "/tests/run.lua"))

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
function M.failsWithoutAPosition()
   error("positionless failure", 0)
end
return M
]]
    )

    -- This case is about captured output, not the runner's own worker fan-out.
    -- Keep its copied runner in one process so the Windows test does not nest a
    -- second MSYS/native subprocess boundary inside the matrix's serial run.
    local plain = run(dir .. "/run.lua", "--jobs=1")
    test.eq(plain:find("ordinary output", 1, true), nil, "passing stdout stays hidden")
    test.eq(plain:find("diagnostic output", 1, true), nil, "passing stderr stays hidden")
    test.matches(plain, "Output from failuretest / writesBeforeFailing")
    test.matches(plain, "failing stdout")
    test.matches(plain, "failing stderr")
    test.matches(plain, "failuretest%.lua:%d+: the intended failure")
    test.matches(plain, "failuretest%.lua:%d+ %(case definition%): positionless failure")
    test.matches(plain, "stdout:\n      failing stdout")
    test.matches(plain, "stderr:\n      failing stderr")

    local verbose = run(dir .. "/run.lua", "--jobs=1 --verbose")
    test.matches(verbose, "ordinary output")
    test.matches(verbose, "diagnostic output")
    os.execute("rm -rf " .. string.format("%q", dir))
end

-- The second suite cannot finish until it sees the first suite's failure on
-- stderr. Checking the final report alone would pass even if diagnostics stayed
-- hidden behind a slow worker's final JSON pipe.
function M.reportsFailuresBeforeTheNextSuiteFinishes()
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p " .. string.format("%q", dir .. "/tests")) == 0)
    assert(os.execute("mkdir -p " .. string.format("%q", dir .. "/build")) == 0)
    write(dir .. "/tests/run.lua", read(ROOT .. "/tests/run.lua"))

    local errors = dir .. "/failures.log"
    local failure = [[
return {fails = function()
    io.stdout:write("captured failure output\n")
    error("the intended live failure")
end}
]]
    local observer = (
        [=[
return {observesFailure = function()
    local deadline = os.time() + 10
    repeat
        local file = io.open(%q, "rb")
        local text = file and file:read("*a") or ""
        if file then file:close() end
        if text:find("aearlytest / fails", 1, true)
            and text:find("the intended live failure", 1, true)
            and text:find("captured failure output", 1, true) then
            return
        end
    until os.time() >= deadline
    error("the earlier suite's failure stayed hidden")
end}
]=]
    ):format(errors)
    -- Exercise serial runs, Nupp workers, reusable shell workers, and fresh
    -- isolated children. The observer waits for another worker's diagnostic.
    local selections = {
        {args = "--jobs=1", marker = "", json = false},
        {args = "--jobs=1 --json", marker = "", json = true},
        {args = "--jobs=2 --json", marker = "", json = true, host = true},
        {args = "--jobs=2 --json", marker = '-- os.execute("true")\n', json = true},
        {args = "--jobs=2 --json", marker = '-- require("io.internal.process")\n', json = true},
    }
    for _, selection in ipairs(selections) do
        write(dir .. "/tests/aearlytest.lua", selection.marker .. failure)
        write(dir .. "/tests/zwaittest.lua", selection.marker .. observer)
        write(dir .. "/build/.nupp-test-times.json", [[
{"version":2,"suites":{"zwaittest":2000,"aearlytest":1000}}
]])
        local outputPath = dir .. "/report.out"
        local program = selection.host and string.format("%q", ROOT .. "/build/nupp-test") or "luajit tests/run.lua"
        local command = (
            "cd %q && %sNUPP_TEST_BUILD=%q %s %s >%q 2>%q"
        ):format(dir, MODULES, dir .. "/build", program, selection.args, outputPath, errors)
        os.execute(command)
        local output = read(outputPath)
        local diagnostics = read(errors)
        test.matches(diagnostics, "aearlytest / fails")
        test.matches(diagnostics, "the intended live failure")
        test.matches(diagnostics, "captured failure output")
        test.eq(diagnostics:find("the earlier suite's failure stayed hidden", 1, true), nil, diagnostics)
        if selection.json then
            local report = require("testjson").decode(output)
            test.eq(report.total, 2)
            test.eq(report.failed, 1, diagnostics)
            test.eq(report.passed, 1, diagnostics)
            if selection.args:find("jobs=2", 1, true) then
                test.eq(#report.shards, 2)
            end
        else
            test.matches(output, "2 tests, 1 passed, 0 skipped, 1 failed")
        end
    end
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
    test.eq(output:find("passing captured stdout", 1, true), nil, "repeated passing stdout stays captured")
    test.eq(output:find("passing captured stderr", 1, true), nil, "repeated passing stderr stays captured")
    test.matches(output, "slowest suites")
    test.matches(output, "slowest tests")
    test.matches(output, "slowtest%s+%d+%.?%d*m?s")
    test.matches(output, "slowtest / slow")

    -- The same run as data, where the suite's own cost is separable from its
    -- cases' rather than only rendered.
    local json = require("testjson")
    local decoded = json.decode(runJson(dir .. "/run.lua", "--jobs=1 --json"))
    test.eq(#decoded.suites, 1, "one suite record")
    local record = decoded.suites[1]
    test.eq(record.suite, "slowtest")
    test.eq(record.tests, 18)
    test.eq(record.slowestCase, "slow")
    test(record.hooksMs >= 25, "beforeAll is measured with the suite")
    test(
        record.durationMs >= record.casesMs + record.hooksMs - 1,
        "the suite is at least what its cases and hooks cost"
    )

    -- Asked for none, and the report is gone; the run still measured it.
    local quiet = run(dir .. "/run.lua", "--jobs=1 --timings=0")
    test.eq(quiet:find("slowest suites", 1, true), nil, "--timings=0 asks for no report")
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
    test.eq(#first.tests, 1, "the heavy case is a slice on its own")
    test.eq(first.tests[1].name, "heavy")
    test.eq(#second.tests, 3, "the cheap cases share the other slice")
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
            test.eq(seen[spec], nil, spec .. " was claimed twice")
            seen[spec] = true
        end
        ran = ran + report.total
    end
    test.eq(ran, 4, "every piece ran exactly once")
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
    test.eq(report.total, 2, "both queue pieces ran")
    test.eq(report.passed, 2, output)
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
    test.eq(report.total, 2, "both queue pieces ran" .. "\n" .. output)
    test.eq(report.passed, 2, output)
    os.execute("rm -rf " .. string.format("%q", dir))
end

function M.isolatedQueuePiecesRunInFreshProcesses()
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p " .. string.format("%q", dir .. "/tests")) == 0)
    assert(os.execute("mkdir -p " .. string.format("%q", dir .. "/build")) == 0)
    write(dir .. "/tests/run.lua", read(ROOT .. "/tests/run.lua"))

    write(
        dir .. "/tests/isolationmutatortest.lua",
        [[
return {mutatesNestedProcessState = function()
    math.__nupp_runner_isolation_probe = true
    rawset(_G, "__nupp_runner_top_level_probe", true)
    local cache = assert(os.getenv("NUPP_CACHE_DIR"), "the supervisor did not provide its lane cache")
    local marker = assert(io.open("lane-cache", "wb"))
    marker:write(cache)
    marker:close()
end}
]]
    )
    write(
        dir .. "/tests/isolationobservetest.lua",
        [[
return {seesFreshProcessState = function()
    assert(math.__nupp_runner_isolation_probe == nil, "nested global table state crossed an isolated queue piece")
    assert(rawget(_G, "__nupp_runner_top_level_probe") == nil, "top-level state crossed an isolated queue piece")
    local marker = assert(io.open("lane-cache", "rb"))
    local cache = marker:read("*a")
    marker:close()
    assert(cache == os.getenv("NUPP_CACHE_DIR"), "fresh pieces did not inherit the supervisor's lane cache")
    if false then rawset(_G, "classification-only", true) end
end}
]]
    )
    write(
        dir .. "/build/.nupp-test-times.json",
        [[
{"suites":{"isolationmutatortest":2000,"isolationobservetest":1000},
 "cases":{"isolationmutatortest":{"mutatesNestedProcessState":2000},
          "isolationobservetest":{"seesFreshProcessState":1000}}}
]]
    )
    local output, invocation = capturedRun(
        (
            "cd %q && %sNUPP_TEST_BUILD=%q %q isolationmutatortest isolationobservetest --lane=isolated --jobs=1 --json 2>/dev/null"
        ):format(dir, MODULES, dir .. "/build", ROOT .. "/build/nupp-test")
    )
    test.eq(invocation.status, 0, "isolated queue pieces shared process state" .. evidence(invocation))
    local report = require("testjson").decode(output)
    test.eq(report.total, 2)
    test.eq(report.passed, 2)
    test.eq(#report.shards, 1, "one supervisor respected --jobs=1")
    test.eq(#report.shards[1].specs, 2, "the supervisor dynamically claimed both pieces")
    test.eq(report.shards[1].executionLane, "isolated")
    test.eq(report.shards[1].tests, 2, "the supervisor aggregated both child reports")
    os.execute("rm -rf " .. string.format("%q", dir))
end

-- One word to the shell, whatever it holds: nothing in it is expanded.
local function shellWord(text)
    return "'" .. text:gsub("'", "'\\''") .. "'"
end

-- A copied runner in a temporary directory, with one suite in it and a second
-- that passes. A lone process-isolated suite runs in the runner's own process;
-- two are handed to workers, which is the path under test.
local function runnerProject(suite, source)
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p " .. string.format("%q", dir .. "/tests")) == 0)
    assert(os.execute("mkdir -p " .. string.format("%q", dir .. "/build")) == 0)
    write(dir .. "/tests/run.lua", read(ROOT .. "/tests/run.lua"))

    write(dir .. "/tests/" .. suite .. ".lua", source)
    write(dir .. "/tests/quiettest.lua", '-- require("io.internal.process")\nreturn {passes = function() end}\n')

    return dir
end

-- A case that starts a process which ignores being asked to stop, and outlives
-- the case. The suite names the process module so it runs in the isolated lane,
-- where each piece is a worker process of its own.
local LINGERING = [[
-- require("io.internal.process")
local function linger()
    assert(os.execute(
        "sh -c 'trap \"\" HUP INT TERM; echo $$ > lingering.tmp; mv lingering.tmp lingering.pid;"
        .. " while :; do sleep 1; done' </dev/null >/dev/null 2>&1 &"
    ) == 0)
    for _ = 1, 600 do
        local file = io.open("lingering.pid", "rb")
        if file then
            file:close()
            return
        end
        os.execute("sleep 0.1")
    end
    error("the lingering process never started")
end
]]

local function lingeringPid(dir)
    local file = io.open(dir .. "/lingering.pid", "rb")
    if not file then
        return nil
    end
    local pid = tonumber(file:read("*a"):match("%d+"))
    file:close()

    return pid
end

local function alive(pid)
    return os.execute(("kill -0 %d 2>/dev/null"):format(pid)) == 0
end

local function awaitExit(pid, seconds)
    for _ = 1, seconds * 10 do
        if not alive(pid) then
            return true
        end
        os.execute("sleep 0.1")
    end

    return not alive(pid)
end

-- Whatever a case leaves running ends with the worker that ran it. Such a
-- process used to outlive the whole run: two of them spun at a full core each
-- for days, and one holding a worker's output would have kept the runner
-- waiting for a report forever.
function M.aProcessACaseLeavesRunningEndsWithItsWorker()
    if package.config:sub(1, 1) == "\\" then
        return test.suite.skip("process groups are POSIX")
    end
    local dir = runnerProject("lingertest", LINGERING .. [[
return {leavesAProcessRunning = linger}
]])
    -- An outer coverage run leaves its protocol variable in the environment.
    -- This ordinary nested runner must still isolate the suite.
    local output, invocation = capturedRun(
        (
            "cd %q && %sNUPP_COVERAGE_FILE=%q NUPP_TEST_BUILD=%q %q lingertest quiettest --lane=isolated --jobs=1 --json 2>/dev/null"
        ):format(dir, MODULES, dir .. "/inherited-coverage.json", dir .. "/build", ROOT .. "/build/nupp-test")
    )
    local pid = lingeringPid(dir)
    local ended = pid ~= nil and awaitExit(pid, 3)
    if pid then
        os.execute(("kill -KILL %d 2>/dev/null"):format(pid))
    end
    test.eq(invocation.status, 0, "the lingering case failed" .. evidence(invocation))
    test.eq(require("testjson").decode(output).passed, 2)
    test(pid, "the case never reported its process")
    test(ended, "pid " .. tostring(pid) .. " outlived the worker whose case started it")
    os.execute("rm -rf " .. string.format("%q", dir))
end

-- And when the runner itself is killed on its own -- as a timeout wrapper does,
-- leaving its workers with nobody to report to -- they end, and what their cases
-- started ends with them.
function M.workersEndWhenTheirRunnerIsKilled()
    if package.config:sub(1, 1) == "\\" then
        return test.suite.skip("process groups are POSIX")
    end
    local dir = runnerProject(
        "stucktest",
        LINGERING .. [[
return {staysBusy = function()
    linger()
    os.execute("sleep 300")
end}
]]
    )
    -- Started from a shell that stays to wait on it, as a command would: a runner
    -- whose parent has gone ends by itself, which is the next case.
    assert(
        os.execute(
            (
                "cd %q && sh -c %s </dev/null >/dev/null 2>&1 &"
            ):format(
                dir,
                shellWord(
                    (
                        "%sNUPP_TEST_BUILD=%q %q stucktest quiettest --lane=isolated --jobs=1 --json & echo $! > runner.pid; wait"
                    ):format(MODULES, dir .. "/build", ROOT .. "/build/nupp-test")
                )
            )
        ) == 0
    )
    for _ = 1, 100 do
        local file = io.open(dir .. "/runner.pid", "rb")
        if file then
            file:close()
            break
        end
        os.execute("sleep 0.1")
    end
    local runner = tonumber(read(dir .. "/runner.pid"):match("%d+"))
    local pid
    for _ = 1, 1200 do
        pid = lingeringPid(dir)
        if pid or not alive(runner) then
            break
        end
        os.execute("sleep 0.1")
    end
    os.execute(("kill -KILL %d 2>/dev/null"):format(runner))
    local ended = pid ~= nil and awaitExit(pid, 30)
    if pid then
        os.execute(("kill -KILL %d 2>/dev/null"):format(pid))
    end
    test(pid, "the case never reported its process")
    test(ended, "pid " .. tostring(pid) .. " outlived the runner that was killed")
    os.execute("rm -rf " .. string.format("%q", dir))
end

-- A lone suite runs in the runner's own process, with no worker to end what its
-- cases leave behind. When the command that started the runner is killed on its
-- own -- `nupp test` under a wrapper that times out and kills only it -- the
-- runner used to go on, and one spun for a day and a half. It now leads a
-- process group of its own and ends it once its starter is gone: the shell that
-- started it directly, or the command it was told to watch, which may have a
-- shell of its own between the two.
function M.aRunnerEndsWhatItStartedWhenItsCommandIsKilled()
    if package.config:sub(1, 1) == "\\" then
        return test.suite.skip("process groups are POSIX")
    end
    for _, shape in ipairs({"parent", "named"}) do
        local dir = runnerProject(
            "lonetest",
            LINGERING .. [[
return {staysBusy = function()
    linger()
    os.execute("sleep 300")
end}
]]
        )
        local runner = (
            "%sNUPP_TEST_BUILD=%q %q lonetest --jobs=1 --json; :"
        ):format(MODULES, dir .. "/build", ROOT .. "/build/nupp-test")
        -- The command: a shell that waits on the runner, or one that names itself
        -- and waits on another shell that waits on the runner.
        local command = shape == "parent" and runner or ("NUPP_TEST_WATCH_PID=$$ sh -c %s; :"):format(shellWord(runner))
        assert(
            os.execute(
                (
                    "cd %q && { sh -c %s </dev/null >/dev/null 2>&1 & echo $! > command.pid; }"
                ):format(dir, shellWord(command))
            ) == 0
        )
        local started = tonumber(read(dir .. "/command.pid"):match("%d+"))
        local pid
        for _ = 1, 1200 do
            pid = lingeringPid(dir)
            if pid or not alive(started) then
                break
            end
            os.execute("sleep 0.1")
        end
        os.execute(("kill -KILL %d 2>/dev/null"):format(started))
        local ended = pid ~= nil and awaitExit(pid, 30)
        if pid then
            os.execute(("kill -KILL %d 2>/dev/null"):format(pid))
        end
        os.execute("pkill -KILL -f " .. string.format("%q", dir) .. " 2>/dev/null")
        test(pid, shape .. ": the case never reported its process")
        test(ended, shape .. ": pid " .. tostring(pid) .. " outlived the command that started its runner")
        os.execute("rm -rf " .. string.format("%q", dir))
    end
end

function M.embeddedWorkersDiscoverFromTheParentCatalogWithoutPopen()
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p " .. string.format("%q", dir .. "/queue")) == 0)
    write(dir .. "/run.lua", read(ROOT .. "/tests/run.lua"))

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
    test.eq(output, ".\n1\npasses\n", "the catalogued suite ran")
    os.execute("rm -rf " .. string.format("%q", dir))
end

function M.runsLifecycleHooksInOrder()
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p " .. string.format("%q", dir)) == 0)
    local trace = dir .. "/trace"
    write(dir .. "/run.lua", read(ROOT .. "/tests/run.lua"))

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
    test.eq(
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
    test.eq(read(trace), "beforeAll\nbeforeEach\ntest\nafterEach\nafterAll\n")
    os.execute("rm -rf " .. string.format("%q", dir))
end

function M.runsTeardownAfterFailedSetup()
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p " .. string.format("%q", dir)) == 0)
    local trace = dir .. "/trace"
    write(dir .. "/run.lua", read(ROOT .. "/tests/run.lua"))

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
    test.eq(read(trace), "beforeEach\nafterEach\nafterAll\n")
    os.execute("rm -rf " .. string.format("%q", dir))
end

function M.runsSuiteTeardownWhenSetupFails()
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p " .. string.format("%q", dir)) == 0)
    local trace = dir .. "/trace"
    write(dir .. "/run.lua", read(ROOT .. "/tests/run.lua"))

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
    test.eq(read(trace), "beforeAll\nafterAll\n")
    os.execute("rm -rf " .. string.format("%q", dir))
end

return M
