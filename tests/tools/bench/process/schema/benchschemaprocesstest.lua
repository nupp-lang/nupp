local fixture = require("helpers.benchprocess")
local testAssert = fixture.testAssert
local json = fixture.json
local HERE = fixture.HERE
local NUPP = fixture.NUPP
local TIMEOUT_MS = fixture.TIMEOUT_MS
local read = fixture.read
local benchmarkProgram = fixture.benchmarkProgram
local workspace = fixture.workspace
local inWorkspace = fixture.inWorkspace

local M = {}

-- A baseline's schema is checked where it is read. A version three document kept
-- its durations in seconds under other names, so it still reads for the
-- deterministic counters and every duration verdict against it is inconclusive. A
-- schema this version does not read is refused, naming both, rather than decoding
-- as a baseline that matches nothing and passes.
function M.aBaselineSchemaIsCheckedWhereItIsRead()
    local working = workspace(true)
    local stdout, stderr, baseline = working .. "/stdout.json", working .. "/stderr.txt", working .. "/baseline.json"
    local fixture = benchmarkProgram("bench_fixed_records")

    local function run(extra)
        local command = (
            "%q bench --timeout-ms " .. TIMEOUT_MS .. " --file %q --json %s > %q 2> %q"
        ):format(NUPP, fixture, extra, stdout, stderr)

        return os.execute(inWorkspace(working, command))
    end

    local function write(document)
        local f = assert(io.open(baseline, "wb"))
        f:write(json.encode(document))
        f:close()
    end

    local function rename(value)
        if type(value) ~= "table" then
            return value
        end
        local renamed = {}
        for key, item in pairs(value) do
            if type(key) == "string" and key:match("%lMs$") and key ~= "p50Ms" and key ~= "p999Ms" then
                key = key:gsub("Ms$", "Sec")
            end
            renamed[key] = rename(item)
        end

        return setmetatable(renamed, getmetatable(value))
    end

    local compared = ("--case '^fixed$' --forks 12 --baseline %q --margin 5"):format(baseline)
    testAssert.eq(run("--case '^fixed$' --forks 12"), 0, "the baseline run succeeds:\n" .. read(stderr))
    local current = json.decode(read(stdout))
    testAssert.eq(current.schema, 5, "a record is written at schema 5")

    -- Equal constant populations have zero rank-sum variance and no interval.
    -- Author a distinct baseline duration so the interval assertion below tests
    -- both schema boundaries without depending on measured timing.
    local summary = current.benchmarks[1].summary
    summary.medianMs = 0.26
    summary.intervalLowMs = 0.26
    summary.intervalHighMs = 0.26
    for index in ipairs(summary.samplesMs) do
        summary.samplesMs[index] = 0.26
    end
    for index in ipairs(summary.forkSummariesMs) do
        summary.forkSummariesMs[index] = 0.26
        local measurement = current.benchmarks[1].forks[index].measurement
        measurement.medianMs = 0.26
        for sample in ipairs(measurement.samplesMs) do
            measurement.samplesMs[sample] = 0.26
        end
    end

    write(current)
    testAssert.eq(run(compared), 0, "a current baseline compares")
    local comparison = json.decode(read(stdout)).comparisons[1]
    testAssert.eq(comparison.kind, "observational", "a current baseline is compared")
    testAssert.eq(#comparison.verdicts, 1, "a current baseline's durations are compared")
    testAssert.eq(comparison.verdicts[1].withheld, nil, "and nothing about the baseline withholds them")
    assert(read(stderr):find("nothing is comparable", 1, true) == nil, read(stderr))

    -- Twice as fast in the baseline, so this run is a regression the comparison finds.
    local faster = json.decode(json.encode(current))
    local summaries = faster.benchmarks[1].summary.forkSummariesMs
    for index = 1, #summaries do
        summaries[index] = summaries[index] / 2
    end
    write(faster)
    testAssert.eq(run(compared), 0, "a duration verdict never changes the exit status")
    local verdict = json.decode(read(stdout)).comparisons[1].verdicts[1]
    testAssert.eq(verdict.verdict, "regressed", "a slower run against a current baseline is a regression")

    local previous = json.decode(json.encode(faster))
    previous.schema = 4
    write(previous)
    testAssert.eq(run(compared), 0, "a version four baseline still reads")
    comparison = json.decode(read(stdout)).comparisons[1]
    testAssert.eq(comparison.kind, "observational", "a version four baseline is compared")
    verdict = comparison.verdicts[1]
    testAssert.eq(verdict.withheld, "baseline-schema", "the schema withholds the interval")
    testAssert.eq(verdict.verdict, "inconclusive", "durations against a version four baseline are inconclusive")
    assert(read(stderr):find("is schema 4", 1, true) ~= nil, read(stderr))
    testAssert.eq(comparison.baseline.benchmarks[1].summary.medianms, nil, "runner documents stay wire-only")

    local older = rename(current)
    older.schema = 3
    write(older)
    testAssert.eq(run(compared), 0, "a version three baseline still reads")
    comparison = json.decode(read(stdout)).comparisons[1]
    testAssert.eq(comparison.kind, "observational", "a version three baseline is compared")
    verdict = comparison.verdicts[1]
    testAssert.eq(verdict.interval, nil, "a version three baseline has no durations to compare")
    testAssert.eq(verdict.verdict, "inconclusive", "durations against a version three baseline are inconclusive")

    older.schema = 2
    write(older)
    assert(run(compared) ~= 0, "the runner still requires schema3 or later")
    assert(read(stderr):find("has schema 2", 1, true) ~= nil)

    current.schema = 6
    write(current)
    assert(run(compared) ~= 0, "a foreign schema is refused")
    local problem = read(stderr)
    assert(problem:find("has schema 6; this bench reads schema 5", 1, true) ~= nil, problem)

    write({benchmarks = {}})
    assert(run(compared) ~= 0, "a document without a schema is refused")
    problem = read(stderr)
    assert(problem:find("has schema none", 1, true) ~= nil, problem)
    os.execute(("rm -rf %q"):format(working))
end

return M
