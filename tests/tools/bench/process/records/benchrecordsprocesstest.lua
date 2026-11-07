local fixture = require("helpers.benchprocess")
local testAssert = fixture.testAssert
local json = fixture.json
local HERE = fixture.HERE
local NUPP = fixture.NUPP
local TIMEOUT_MS = fixture.TIMEOUT_MS
local read = fixture.read
local workspace = fixture.workspace
local inWorkspace = fixture.inWorkspace
local evidence = fixture.evidence

local M = {}

function M.comparisonRecordsRetainBothSidesAndVerdicts()
    local working = workspace()
    local stdout, history, baseline = working
        .. "/stdout.json", working
        .. "/history.jsonl", working
        .. "/baseline.json"
    local fixture = HERE .. "/fixtures/bench_fixed_records.nupp"

    local function run(extra)
        local command = (
            "%q bench --timeout-ms " .. TIMEOUT_MS .. " --file %q --json %s > %q"
        ):format(NUPP, fixture, extra, stdout)
        testAssert.eq(os.execute(inWorkspace(working, command)), 0, "fixed-record comparison succeeds")
        local output = read(stdout)
        testAssert.eq(
            evidence(output),
            evidence(read(working .. "/build/bench-record.json")),
            "stdout and saved record agree"
        )
        local decoded = json.decode(output)
        testAssert.eq(decoded.ok, true, "the printed document says the run succeeded")

        return decoded
    end

    local paired = run(("--case '^fixed$' --forks 12 --against %q --margin 5 --history %q"):format(NUPP, history))
    local comparison = paired.comparisons[1]
    testAssert.eq(comparison.kind, "interleaved", "paired provenance survives serialization")
    testAssert.eq(comparison.source, NUPP, "the baseline executable is named")
    local before, after = comparison.baseline.benchmarks[1], paired.benchmarks[1]
    testAssert.eq(before.case, after.case, "baseline and candidate identify the same file")
    testAssert.eq(before.name, after.name, "baseline and candidate identify the same case")
    for _, entry in ipairs({before, after}) do
        testAssert.eq(#entry.forks, 12, "every process measurement is retained")
        for index, fork in ipairs(entry.forks) do
            testAssert.eq(fork.index, index, "fork identity is retained")
            testAssert.eq(fork.measurement.samplesMs[2], 0.25, "raw ordered samples survive")
        end
    end
    local verdict = comparison.verdicts[1]
    testAssert.eq(verdict.case, after.case, "verdict identifies its program")
    testAssert.eq(verdict.name, after.name, "verdict identifies its benchmark")
    testAssert.eq(verdict.change, 0, "equal authored scores have zero change")
    testAssert.eq(verdict.interval.low, 0, "interval lower endpoint is retained")
    testAssert.eq(verdict.interval.upper, 0, "interval upper endpoint is retained")
    testAssert.eq(verdict.pValue, 1, "raw significance is retained")
    testAssert.eq(verdict.adjusted, 1, "adjusted significance is retained")
    testAssert.eq(verdict.verdict, "unchanged", "the comparison verdict is retained")
    testAssert.eq(evidence(read(history)), evidence(read(stdout)), "history retains identical evidence")
    local f = assert(io.open(baseline, "wb"));
    f:write(read(working .. "/build/bench-record.json"));
    f:close()

    local observed = run(("--case '^fixed$' --forks 1 --baseline %q --margin 5 --accept"):format(baseline))
    comparison = observed.comparisons[1]
    testAssert.eq(comparison.kind, "observational", "stored baselines are never labeled causal")
    testAssert.eq(comparison.source, baseline, "the baseline record is named")
    testAssert.eq(#comparison.baseline.benchmarks[1].forks, 12, "stored baseline measurements survive")
    testAssert.eq(comparison.baseline.comparisons, nil, "accepted baselines do not nest comparison history")
    testAssert.eq(comparison.verdicts[1].withheld, "below-minimum-forks", "too few forks explain the absent interval")
    testAssert.eq(comparison.verdicts[1].verdict, "inconclusive", "too few forks remain inconclusive")
    testAssert.eq(evidence(read(baseline)), evidence(read(stdout)), "accepted baseline retains the full report")

    local trending = run(("--case '^trend$' --forks 2 --against %q --margin 5"):format(NUPP))
    verdict = trending.comparisons[1].verdicts[1]
    testAssert.eq(verdict.withheld, "trend-warning", "trend withholding survives serialization")
    testAssert.eq(verdict.interval, nil, "a withheld interval is absent")
    testAssert.eq(verdict.verdict, "inconclusive", "a trend cannot acquire a confident verdict")
    os.execute(("rm -rf %q"):format(working))
end

return M
