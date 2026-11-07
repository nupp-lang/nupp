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

function M.runnerUsesSpecificFilesAndAppendsMachineReadableHistory()
    local working = workspace()
    local history = working .. "/history.jsonl"
    local stdout = working .. "/stdout.txt"
    local profiles = working .. "/profiles"
    local fixture = benchmarkProgram("bench_suite")
    local simpleFixture = HERE .. "/fixtures/bench_protocol.nupp"

    local ran = os.execute(
        inWorkspace(
            working,
            (
                "%q bench --timeout-ms "
                .. TIMEOUT_MS
                .. " --file %q --case %q --variant %q --parameter %q --history %q --label smoke --json > %q"
            ):format(NUPP, fixture, "^work$", "^base$", "^size=1$", history, stdout)
        )
    )
    testAssert.eq(ran, 0, "the process-isolated runner exits successfully")
    local stdoutDocument = json.decode(read(stdout))
    testAssert.eq(stdoutDocument.label, "smoke", "--json writes the merged record to stdout")
    testAssert.eq(#stdoutDocument.benchmarks, 1, "--json contains only the selected benchmarks")
    testAssert.eq(
        stdoutDocument.benchmarks[1].name,
        "protocol.work.base:size=1",
        "--json stdout contains the selected benchmark"
    )
    local line = read(history):match("[^\r\n]+")
    local document = json.decode(line)
    testAssert.eq(document.label, "smoke", "the history label is retained")
    testAssert.eq(#document.benchmarks, 1, "the runner filter selects one benchmark")
    testAssert.eq(document.benchmarks[1].name, "protocol.work.base:size=1", "the selected benchmark is named")
    testAssert.eq(document.forks, 1, "an unreplicated run records that it ran one fork")
    assert(document.seed ~= nil, "the permutation seed is recorded so an order can be reproduced")
    -- Each fork is kept whole rather than reduced to its median. A warmup classifier
    -- needs every process's ordered samples, and a summary cannot give them back.
    testAssert.eq(#document.benchmarks[1].forks, 1, "one fork was run and one fork was kept")
    assert(
        #document.benchmarks[1].forks[1].measurement.samplesMs >= 3,
        "history includes each fork's raw samples rather than only a summary"
    )
    assert(
        document.benchmarks[1].summary.intervalWithheld == "below-minimum-forks",
        "one fork names why it carries no interval instead of leaving the field absent"
    )

    -- Asked for as JSON rather than as the table: what is being asserted is which
    -- benchmark the filters selected, and a table's column widths depend on the
    -- longest name in it, so the text form would tie this to the fixture's spelling.
    local filtered = os.execute(
        inWorkspace(
            working,
            (
                "%q bench --timeout-ms "
                .. TIMEOUT_MS
                .. " --list --json --file %q --case %q --case %q --variant %q --parameter %q > %q"
            ):format(NUPP, fixture, "^absent$", "^work$", "^other$", "^size=2$", stdout)
        )
    )
    testAssert.eq(filtered, 0, "structured Lua-pattern filters select a benchmark")
    local selection = json.decode(read(stdout))
    testAssert.eq(#selection.benchmarks, 1, "one benchmark survived every filter")
    testAssert.eq(
        selection.benchmarks[1].name,
        "protocol.work.other:size=2",
        "case, variant and parameter filters combine while repeats are alternatives"
    )
    testAssert.eq(selection.benchmarks[1].file, fixture, "and the listing says which file declares it")

    local profiled = os.execute(
        inWorkspace(
            working,
            (
                "%q bench --timeout-ms "
                .. TIMEOUT_MS
                .. " --file %q --case %q --profile %q --profile-interval-ms 1 > %q"
            ):format(NUPP, simpleFixture, "^protocol$", profiles, stdout)
        )
    )
    testAssert.eq(profiled, 0, "the measured-window sampling pass exits successfully")
    local human = read(stdout)
    local resultAt = human:find("# Result: protocol", 1, true)
    local tableAt = human:find("Benchmark%s+Mode%s+Cnt%s+Score%s+Units")
    assert(human:find("NOT a confidence") ~= nil, "an unreplicated run says its spread is not an interval")
    assert(
        resultAt ~= nil and tableAt ~= nil and resultAt < tableAt,
        "a completed score streams before the final table"
    )
    local profilePath = human:match("# Profile: ([^\r\n]+)")
    assert(profilePath ~= nil, "the sampling pass names its collapsed-stack file")
    local collapsed = read(profilePath)
    assert(
        collapsed == "" or collapsed:find("^bench_protocol%.nupp:") ~= nil,
        "collected stacks are trimmed to the benchmark program"
    )
    assert(collapsed == "" or collapsed:find(" %d+$") ~= nil, "collected stacks carry sample counts")

    os.execute(("rm -rf %q"):format(working))
end

return M
