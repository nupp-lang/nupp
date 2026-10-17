-- Process report transport controls through the ordinary installed CLI.
-- Fixtures poison a local runner so every process must use the carried source.
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

local function decode(text)
    local json = require("nupp.codec.json")
    local value, reason = json.decode(text, json.NULL)
    if reason ~= nil then
        error(reason, 2)
    end

    return value
end

local function fixtureProject()
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p " .. string.format("%q", dir .. "/tests")) == 0)
    assert(os.execute("mkdir -p " .. string.format("%q", dir .. "/build")) == 0)
    write(dir .. "/tests/run.lua", 'error("the internal CLI loaded the fixture runner")\n')
    write(dir .. "/tests/assert.lua", read(ROOT .. "/tests/assert.lua"))

    return dir
end

local EXIT = "@@nupp_test_exit:"

local function capturedRun(command)
    local pipe = assert(io.popen(("%s; printf '%s%%d@@\\n' $?"):format(command, EXIT)))
    local output = pipe:read("*a") or ""
    pipe:close()
    local status = tonumber(output:match(EXIT .. "(%d+)@@"))
    output = output:gsub(EXIT .. "%d+@@\n?", "")

    return output, {command = command, output = output, status = status}
end

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

local function shellWord(text)
    return "'" .. text:gsub("'", "'\\''") .. "'"
end

local RUNNER = shellWord(NUPP) .. " test --internal-runner"

-- Top-level suite output runs outside the per-case capture. Keep the parent
-- quiet when planning; only a real process child writes this framing noise.
local function noisyWorkerSuite(failing, hookFailure)
    return [[
for _, argument in ipairs(arg) do
    if argument:match("^%-%-queue=") or argument:match("^%-%-shard=") then
        io.stdout:write('q {"not":"the report"}\n')
        break
    end
end
local M = {}
function M.case()
    local test = require("nupp.test")
    test.metric("transport", ]]
        .. (
            failing and "4.5" or "-2.5"
        ) .. [[, "items")
    test.metric("transport", 0.5, "items")
    assert(os.execute("exit 0") == 0)
    ]] .. (
            failing and 'error("transport case failure")' or ''
        ) .. [[
end
]] .. (
            failing and hookFailure ~= false and 'function M.afterAll() error("transport hook failure") end\n' or ''
        ) .. [[
return M
]]
end

local function workerArtifactsIn(dir, suffix)
    local pipe = assert(
        io.popen(
            ("find %s -type f -name %s"):format(shellWord(dir .. "/build/.nupp-test-cache"), shellWord("*." .. suffix))
        )
    )
    local paths = {}
    for path in pipe:lines() do
        if path:find("/reports-", 1, true) then
            paths[#paths + 1] = path
        end
    end
    pipe:close()
    table.sort(paths)

    return paths
end

local function checkTransportMetrics(report)
    local byId = {}
    for _, row in ipairs(report.tests) do
        byId[row.id] = row
    end
    for id, expected in pairs({["noisepasstest/case"] = -2, ["noisefailtest/case"] = 5}) do
        local metrics = byId[id].metrics
        test.equal(#metrics, 1)
        test.equal(metrics[1].name, "transport")
        test.equal(metrics[1].unit, "items")
        test.equal(metrics[1].value, expected, "signed fractional contributions survive the worker")
    end
    test.equal(#report.metrics, 1)
    test.equal(report.metrics[1].name, "transport")
    test.equal(report.metrics[1].unit, "items")
    test.equal(report.metrics[1].value, 3, "the parent sums metrics from passing and failing rows")
end

-- One known case per suite keeps this transport control unsliced. Empty
-- stateful slices run hooks too; their scheduling is outside this fixture.
local function seedWholeNoiseSuites(dir)
    write(
        dir .. "/build/.nupp-test-times.json",
        '{"suites":{"noisepasstest":1,"noisefailtest":1},"cases":{"noisepasstest":{"case":1},"noisefailtest":{"case":1}}}'
    )
end

local function transportRunner(fresh)
    local dir = fixtureProject()
    seedWholeNoiseSuites(dir)
    write(dir .. "/tests/noisepasstest.lua", noisyWorkerSuite(false))
    write(dir .. "/tests/noisefailtest.lua", noisyWorkerSuite(true))
    local arguments = "noisepasstest noisefailtest --lane=shell --jobs=2 --json --timings=0"
    local env = ""
    if fresh then
        assert(os.execute("mkdir -p " .. shellWord(dir .. "/queue")) == 0)
        write(dir .. "/queue/order", "noisepasstest\nnoisefailtest\n")
        write(dir .. "/queue/piece-1", "noisepasstest\n")
        write(dir .. "/queue/piece-2", "noisefailtest\n")
        arguments = "--json --queue=" .. shellWord(dir .. "/queue")
        env = "NUPP_TEST_FRESH_QUEUE_PIECES=1 "
    end
    local output, invocation = capturedRun(
        (
            "cd %s && %s NUPP_TEST_BUILD=%s %s %s 2>/dev/null"
        ):format(shellWord(dir), env, shellWord(dir .. "/build"), RUNNER, arguments)
    )
    test.equal(invocation.status, 1, "only the intentional test/hook failures fail" .. evidence(invocation))
    local report = decode(output)
    test.equal(report.total, 3, "a failed afterAll adds a result beyond the declared case count")
    test.equal(report.passed, 1)
    test.equal(report.failed, 2)
    checkTransportMetrics(report)
    local byId = {}
    for _, record in ipairs(report.tests) do
        byId[record.id] = record
        test.equal(record.name == "<shard>" or record.name == "<unrun>", false, "no report was lost")
    end
    test.equal(byId["noisepasstest/case"].status, "passed")
    test.matches(byId["noisefailtest/case"].failure.message, "transport case failure")
    test.matches(byId["noisefailtest/afterAll"].failure.message, "transport hook failure")
    local noise = ""
    for _, path in ipairs(workerArtifactsIn(dir, "out")) do
        noise = noise .. read(path)
    end
    test.matches(noise, 'q {"not":"the report"}')
    test.assert(#workerArtifactsIn(dir, "json") >= 2, "each child retained its complete report")
    test.assert(#workerArtifactsIn(dir, "err") >= 2, "each child retained its stderr")
    if fresh then
        test.equal(#report.claimed, 2, "the supervisor kept its claims")
        test.matches(noise, "__piece_status__:1", "the full piece stdout includes its terminal status")
    end

    return dir
end

function M.processReportsIgnoreRawSuiteOutputAndCountHookFailures()
    local dir = transportRunner(false)
    os.execute("rm -rf " .. shellWord(dir))
end

function M.freshPieceReportsIgnoreRawSuiteOutputAndCountHookFailures()
    local dir = transportRunner(true)
    os.execute("rm -rf " .. shellWord(dir))
end

function M.workerReportsRejectMissingMalformedAndAbnormalChildren()
    for _, fresh in ipairs({false, true}) do
        for _, mode in ipairs({
            "missing",
            "malformed",
            "shape",
            "containers",
            "counts",
            "metric-array",
            "metric-row",
            "metric-name",
            "metric-value",
            "metric-unit",
            "exit",
            "signal"
        }) do
            local dir = fixtureProject()
            write(dir .. "/tests/alphatest.lua", 'return {case = function() assert(os.execute("exit 0") == 0) end}\n')
            write(dir .. "/tests/betatest.lua", 'return {case = function() assert(os.execute("exit 0") == 0) end}\n')
            local wrapper = dir .. "/worker.sh"
            local document = mode == "malformed" and "{not-json"
                or mode == "shape" and "{}"
                or mode == "containers"
                and '{"schemaVersion":1,"ok":true,"total":0,"passed":0,"failed":0,"skipped":0,"notExecuted":0,"durationMs":0,"tests":{},"suites":{}}'
                or mode == "counts"
                and '{"schemaVersion":1,"ok":true,"total":0,"passed":1,"failed":0,"skipped":0,"notExecuted":0,"durationMs":0,"tests":[],"suites":[]}'
                or '{"schemaVersion":1,"ok":true,"total":0,"passed":0,"failed":0,"skipped":0,"notExecuted":0,"durationMs":0,"tests":[],"suites":[]}'
            local badMetrics = {
                ["metric-array"] = "{}",
                ["metric-row"] = "[false]",
                ["metric-name"] = '[{"name":"","value":1}]',
                ["metric-value"] = '[{"name":"transport","value":"bad"}]',
                ["metric-unit"] = '[{"name":"transport","value":1,"unit":false}]',
            }
            if badMetrics[mode] then
                document = '{"schemaVersion":1,"ok":true,"total":1,"passed":1,"failed":0,"skipped":0,"notExecuted":0,"durationMs":0,"tests":[{"id":"alphatest/case","suite":"alphatest","name":"case","status":"passed","durationMs":0,"metrics":'
                    .. badMetrics[
                        mode
                    ] .. '}],"suites":[]}'
            end
            write(
                wrapper,
                '#!/bin/sh\nfor argument in "$@"; do\ncase "$argument" in --worker-report=*) report=${argument#--worker-report=};; esac\ndone\n'
                .. (
                    mode ~= "missing" and ("printf '%%s' %s >\"$report\"\n"):format(shellWord(document)) or ""
                ) .. 'printf \'q bad-child\\n\'\n' .. (
                    mode == "signal" and "kill -KILL $$\n" or mode == "exit" and "exit 2\n" or "exit 0\n"
                )
            )
            assert(os.execute("chmod +x " .. shellWord(wrapper)) == 0)
            write(
                dir .. "/tests/groups.lua",
                (
                    "rawset(_G, '__NUPP_TEST_RUNNER_COMMAND', %q)\nreturn {fixture = {'alphatest', 'betatest'}}\n"
                ):format(shellWord(wrapper))
            )
            local args = "--group=fixture --lane=shell --jobs=2 --json"
            local env = ""
            if fresh then
                assert(os.execute("mkdir -p " .. shellWord(dir .. "/queue")) == 0)
                write(dir .. "/queue/order", "alphatest\n")
                write(dir .. "/queue/piece-1", "alphatest\n")
                args = "--json --group=fixture --queue=" .. shellWord(dir .. "/queue")
                env = "NUPP_TEST_FRESH_QUEUE_PIECES=1 "
            end
            local output, invocation = capturedRun(
                (
                    "cd %s && %s NUPP_TEST_BUILD=%s %s %s 2>/dev/null"
                ):format(shellWord(dir), env, shellWord(dir .. "/build"), RUNNER, args)
            )
            test.equal(invocation.status, 1, "an invalid child cannot pass" .. evidence(invocation))
            local report = decode(output)
            test.assert(report.failed > 0)
            local failures = ""
            for _, record in ipairs(report.tests) do
                failures = failures .. (record.failure and record.failure.message or "")
            end
            local expected = mode == "missing" and "cannot read report"
                or mode == "malformed" and "JSON decode"
                or (mode == "shape" or mode == "containers") and "invalid worker report"
                or mode == "counts" and "invalid worker counter passed"
                or badMetrics[mode] and "invalid worker metric"
                or mode == "exit" and "worker exit 2"
                or "worker killed by signal 9"
            test.assert(failures:find(expected, 1, true), failures)
            test.assert(failures:find("artifacts:", 1, true), failures)
            local outFiles = workerArtifactsIn(dir, "out")
            test.assert(#outFiles > 0)
            test.matches(read(outFiles[1]), "q bad%-child")
            if mode ~= "missing" then
                test.equal(read(workerArtifactsIn(dir, "json")[1]), document, "rejected bytes were retained in full")
            end
            os.execute("rm -rf " .. shellWord(dir))
        end
    end
end

function M.workerReportPathsAreNotReusedAcrossInvocations()
    local dir = transportRunner(false)
    local before = workerArtifactsIn(dir, "json")
    local old = {}
    for _, path in ipairs(before) do
        old[path] = read(path)
    end
    -- Lifecycle failure is covered above. These reruns isolate report path
    -- ownership while sharing one build root and potentially updated timings.
    write(dir .. "/tests/noisefailtest.lua", noisyWorkerSuite(true, false))
    local invocation = (
        "cd %s && NUPP_TEST_BUILD=%s %s noisepasstest noisefailtest --lane=shell --jobs=2 --json"
    ):format(shellWord(dir), shellWord(dir .. "/build"), RUNNER)
    local output, runs = capturedRun(
        (
            "(%s >%s 2>/dev/null) & first=$!; (%s >%s 2>/dev/null) & second=$!; wait $first; a=$?; wait $second; b=$?; printf '%%s %%s\n' $a $b"
        ):format(invocation, shellWord(dir .. "/first.json"), invocation, shellWord(dir .. "/second.json"))
    )
    test.equal(runs.status, 0, evidence(runs))
    test.matches(output, "1 1", "both concurrent invocations reached their intentional failures")
    for _, name in ipairs({"first", "second"}) do
        local report = decode(read(dir .. "/" .. name .. ".json"))
        test.equal(report.total, 2)
        test.equal(report.passed, 1)
        test.equal(report.failed, 1)
        test.equal(#report.tests, 2)
        local expected = {["noisepasstest/case"] = "passed", ["noisefailtest/case"] = "failed"}
        local byId = {}
        for _, row in ipairs(report.tests) do
            test.assert(expected[row.id], "only the two intentional case rows may be reported")
            test.assert(not byId[row.id], "concurrent reports contain no duplicate case IDs")
            test.equal(row.status, expected[row.id])
            byId[row.id] = row
        end
        test.assert(byId["noisepasstest/case"] and byId["noisefailtest/case"], "both cases ran")
        test.matches(byId["noisefailtest/case"].failure.message, "transport case failure")
        checkTransportMetrics(report)
    end
    local after = workerArtifactsIn(dir, "json")
    test.assert(#after > #before, "a later invocation reserved different report paths")
    for path, text in pairs(old) do
        test.equal(read(path), text, "a prior report was not overwritten")
    end
    os.execute("rm -rf " .. shellWord(dir))
end

function M.explicitWorkerReportRequiresAUsableUniquePath()
    local dir = fixtureProject()
    write(dir .. "/tests/quiettest.lua", 'return {passes = function() end}\n')
    for _, arguments in ipairs({"--worker-report=", "--worker-report=a --worker-report=b", "--worker-report=a"}) do
        local output, invocation = capturedRun(
            (
                "cd %s && NUPP_TEST_BUILD=%s %s quiettest --jobs=1 %s 2>&1"
            ):format(shellWord(dir), shellWord(dir .. "/build"), RUNNER, arguments)
        )
        test.equal(invocation.status, 2, evidence(invocation))
        test.matches(output, "%-%-worker%-report requires")
    end
    local path = dir .. "/missing/report.json"
    local output, invocation = capturedRun(
        (
            "cd %s && NUPP_TEST_BUILD=%s %s quiettest --jobs=1 --json --worker-report=%s 2>&1"
        ):format(shellWord(dir), shellWord(dir .. "/build"), RUNNER, shellWord(path))
    )
    test.assert(invocation.status ~= 0, "an explicit report write failure cannot pass" .. evidence(invocation))
    test.equal(io.open(path, "rb"), nil)
    test.equal(output:find('"schemaVersion"', 1, true), nil, "no silent stdout report fallback")
    os.execute("rm -rf " .. shellWord(dir))
end

function M.internalCliWorkersUseTheCarriedReportTransport()
    for _, fresh in ipairs({false, true}) do
        local dir = fixtureProject()
        seedWholeNoiseSuites(dir)
        -- Both paths must use the compiler's carried runner, not the fixture copy.
        write(dir .. "/tests/run.lua", 'error("the internal CLI loaded the copied runner")\n')
        write(dir .. "/tests/noisepasstest.lua", noisyWorkerSuite(false))
        write(dir .. "/tests/noisefailtest.lua", noisyWorkerSuite(true))
        local reportPath = dir .. "/private report.json"
        local arguments = "noisepasstest noisefailtest --lane=shell --jobs=2"
        local env = ""
        if fresh then
            assert(os.execute("mkdir -p " .. shellWord(dir .. "/queue")) == 0)
            write(dir .. "/queue/order", "noisepasstest\nnoisefailtest\n")
            write(dir .. "/queue/piece-1", "noisepasstest\n")
            write(dir .. "/queue/piece-2", "noisefailtest\n")
            arguments = "--queue=" .. shellWord(dir .. "/queue")
            env = "NUPP_TEST_FRESH_QUEUE_PIECES=1 "
        end
        local output, invocation = capturedRun(
            (
                "cd %s && %s NUPP_TEST_BUILD=%s %s test --internal-runner --json --worker-report=%s %s 2>/dev/null"
            ):format(shellWord(dir), env, shellWord(dir .. "/build"), shellWord(NUPP), shellWord(reportPath), arguments)
        )
        test.equal(invocation.status, 1, "only the intentional failures fail" .. evidence(invocation))
        test.equal(output:find('"schemaVersion"', 1, true), nil, "the private report was not written on stdout")
        local report = decode(read(reportPath))
        test.equal(report.total, 3)
        test.equal(report.passed, 1)
        test.equal(report.failed, 2)
        checkTransportMetrics(report)
        for _, record in ipairs(report.tests) do
            test.equal(
                record.name == "<shard>" or record.name == "<unrun>",
                false,
                "the carried child used the same protocol"
            )
        end
        if fresh then
            test.equal(#report.claimed, 2)
            local noise = ""
            for _, path in ipairs(workerArtifactsIn(dir, "out")) do
                noise = noise .. read(path)
            end
            test.matches(noise, "__piece_status__:1", "the carried CLI collected fresh-piece files")
        end
        os.execute("rm -rf " .. shellWord(dir))
    end
end

return M
