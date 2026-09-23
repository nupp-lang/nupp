-- Runs the historical SIMD equivalence ledger through exact `nupp test` case
-- IDs and turns successful kills into coverage witness facts.
local M = {}

local source = debug.getinfo(1, "S").source:gsub("^@", ""):gsub("\\", "/")
local directory = assert(source:match("^(.*)/[^/]+$"))
local root = assert(directory:match("^(.*)/tests/simd$"))
local decode = assert(loadfile(root .. "/src/nupp/runtime/vendor/lunajson/decoder.lua"))()()
local encode = assert(loadfile(root .. "/src/nupp/runtime/vendor/lunajson/encoder.lua"))()()

local function read(path)
    local file, problem = io.open(path, "rb")
    if not file then
        return nil, ("cannot read %s: %s"):format(path, tostring(problem))
    end
    local text = file:read("*a") or ""
    file:close()

    return text
end

local function quote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function statusCode(status)
    if status == true then
        return 0
    end
    if type(status) ~= "number" then
        return 127
    end
    if status > 255 then
        return math.floor(status / 256)
    end

    return status
end

function M.command(testId, mutationId, stdoutPath, stderrPath)
    local environment = mutationId and ("NUPP_SIMD_EQUIVALENCE_MUTATION=" .. quote(mutationId) .. " ") or ""

    return table.concat({
        "cd ",
        quote(root),
        " && ",
        environment,
        "./bin/nupp test ",
        quote("--case=" .. testId),
        " --json --jobs=1 --timings=0 --no-color > ",
        quote(stdoutPath),
        " 2> ",
        quote(stderrPath),
    })
end

local function execute(defect)
    local stdoutPath, stderrPath = os.tmpname(), os.tmpname()
    local mutationId = defect.id
    local status = statusCode(os.execute(M.command(defect.mechanism.testId, mutationId, stdoutPath, stderrPath)))
    local stdout, stdoutProblem = read(stdoutPath)
    local stderr = read(stderrPath) or ""
    os.remove(stdoutPath)
    os.remove(stderrPath)
    if not stdout then
        return {status = status, setupFailure = stdoutProblem, stderr = stderr}
    end
    local ok, report = pcall(decode, stdout)
    if not ok or type(report) ~= "table" then
        return {
            status = status,
            setupFailure = "exact test wrote no JSON report" .. (stderr ~= "" and ": " .. stderr or ""),
            stdout = stdout,
            stderr = stderr,
        }
    end

    return {status = status, report = report, stdout = stdout, stderr = stderr}
end

local function oneExactResult(defect, execution)
    if execution.setupFailure then
        return nil, execution.setupFailure
    end
    local report = execution.report
    if type(report) ~= "table" or type(report.tests) ~= "table" then
        return nil, "exact test produced an invalid report"
    end
    if report.total ~= 1 or #report.tests ~= 1 then
        return nil, ("exact test selected %s cases instead of one"):format(tostring(report.total or #report.tests))
    end
    local result = report.tests[1]
    if result.id ~= defect.mechanism.testId then
        return nil, ("exact test ran unrelated case %s"):format(tostring(result.id))
    end

    return result
end

local function mutationKilled(defect, execution)
    local result, problem = oneExactResult(defect, execution)
    if not result then
        return nil, problem
    end
    if result.status == "not-executed" then
        return nil, "equivalence mutation was not executed"
    end
    if execution.status ~= 1 or execution.report.failed ~= 1 or result.status ~= "failed" then
        return nil, "equivalence mutation survived its witness"
    end
    local message = result.failure and result.failure.message or ""
    if not message:find(defect.mechanism.killMarker, 1, true) then
        return nil, "equivalence mutation failed for an unrelated reason: " .. message
    end
    local accepted = false
    for _, failureMode in ipairs(defect.acceptedFailureModes) do
        accepted = accepted or message:find(":" .. failureMode, 1, true) ~= nil
    end
    if not accepted then
        return nil, "equivalence mutation did not report an accepted failure mode"
    end

    return true
end

local function witness(defect)
    return {
        name = "coverage.witness",
        value = {
            id = defect.mechanism.testId,
            obligation = "simd.historical-defect",
            dimensions = {defect = defect.id},
        },
    }
end

function M.run(ledger, executor)
    executor = executor or execute
    local report = {ok = true, total = #ledger.defects, passed = 0, failed = 0, tests = {}}
    for _, defect in ipairs(ledger.defects) do
        local execution = executor(defect)
        local killed, problem
        if defect.mechanism.kind == "preserved-test" or defect.mechanism.kind == "generated-fixture-mutation" then
            killed, problem = mutationKilled(defect, execution)
        else
            killed, problem = nil, "unknown equivalence mechanism " .. tostring(defect.mechanism.kind)
        end
        local result = {
            id = "simd-equivalence/" .. defect.id,
            suite = "simd-equivalence",
            name = defect.id,
            status = killed and "passed" or "failed",
        }
        if killed then
            report.passed = report.passed + 1
            result.facts = {witness(defect)}
        else
            report.ok = false
            report.failed = report.failed + 1
            result.failure = {message = problem}
        end
        report.tests[#report.tests + 1] = result
    end

    return report
end

function M.encode(report)
    return encode(report)
end

return M
