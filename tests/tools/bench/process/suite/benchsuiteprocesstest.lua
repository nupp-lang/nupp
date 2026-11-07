local fixture = require("helpers.benchprocess")
local testAssert = fixture.testAssert
local json = fixture.json
local HERE = fixture.HERE
local NUPP = fixture.NUPP
local read = fixture.read
local jsonLines = fixture.jsonLines
local benchmarkProgram = fixture.benchmarkProgram
local workspace = fixture.workspace
local inWorkspace = fixture.inWorkspace

local M = {}

function M.suitesExpandParametersAndRequireOneSelectedPair()
    local working = workspace()
    local casesOut = working .. "/cases.jsonl"
    local stdout = working .. "/stdout.txt"
    local stderr = working .. "/stderr.txt"
    local recordOut = working .. "/record.json"
    local fixture = HERE .. "/fixtures/bench_suite.nupp"
    local program = benchmarkProgram("bench_suite")

    local listed = os.execute(
        inWorkspace(working, ("%q run -O1 %q --list-cases --cases-out %q > %q"):format(NUPP, fixture, casesOut, stdout))
    )
    testAssert.eq(listed, 0, "suite listing exits successfully")
    local listing = jsonLines(casesOut)
    local names = {}
    for index, declaration in ipairs(listing) do
        names[index] = declaration.name
        testAssert.eq(declaration.suite, "protocol", "the listing identifies its suite")
        testAssert.eq(declaration.caseName, "work", "the listing identifies its logical case")
    end
    testAssert.eq(
        table.concat(names, "\n"),
        table.concat(
            {
                "protocol.work.base:size=1",
                "protocol.work.other:size=1",
                "protocol.work.base:size=2",
                "protocol.work.other:size=2",
            },
            "\n"
        ),
        "parameters and variants expand into stable names"
    )
    testAssert.eq(listing[2].variant, "other", "the listing identifies its variant")
    testAssert.eq(listing[4].parameters.size, 2, "the listing carries structured parameters")

    local unsafe = os.execute(inWorkspace(working, ("%q run -O1 %q > %q 2> %q"):format(NUPP, program, stdout, stderr)))
    assert(unsafe ~= 0, "a direct multi-benchmark run fails")
    assert(
        read(stderr):find("defines more than one benchmark", 1, true) ~= nil,
        "the failure explains how to select an isolated benchmark"
    )

    local selected = "protocol.work.other:size=2"
    local ran = os.execute(
        inWorkspace(working, ("%q run -O1 %q --case %q --out %q --quiet"):format(NUPP, program, selected, recordOut))
    )
    testAssert.eq(ran, 0, "the selected suite pair exits successfully")
    local record = json.decode(read(recordOut))
    local measurement = record.cases[1]
    testAssert.eq(measurement.name, selected, "the selected pair is measured")
    testAssert.eq(measurement.kind, "suite", "the record distinguishes adaptive suites")
    testAssert.eq(measurement.variant, "other", "the variant identity is structured")
    testAssert.eq(measurement.parameters.size, 2, "the parameter identity is structured")
    testAssert.eq(measurement.sampleIterations, 2, "the declared sample batching is recorded")
    testAssert.eq(measurement.operationsPerInvocation, 2, "operation normalization is recorded")
    assert(#measurement.samplesMs >= 3, "raw normalized samples are retained")
    assert(measurement.meanMs ~= nil and measurement.stdevMs ~= nil, "summary statistics are retained")

    os.execute(("rm -rf %q"):format(working))
end

return M
