local fixture = require("helpers.benchprocess")
local testAssert = fixture.testAssert
local json = fixture.json
local HERE = fixture.HERE
local NUPP = fixture.NUPP
local read = fixture.read
local jsonLines = fixture.jsonLines
local workspace = fixture.workspace
local inWorkspace = fixture.inWorkspace

local M = {}

function M.caseListingIsSeparateFromApplicationOutputAndRunnerNIsFixed()
    local working = workspace()
    local casesOut = working .. "/cases.jsonl"
    local stdout = working .. "/stdout.txt"
    local recordOut = working .. "/record.json"
    local fixture = HERE .. "/fixtures/bench_protocol.nupp"

    local listed = os.execute(
        inWorkspace(working, ("%q run -O1 %q --list-cases --cases-out %q > %q"):format(NUPP, fixture, casesOut, stdout))
    )
    testAssert.eq(listed, 0, "case listing exits successfully")
    local listing = jsonLines(casesOut)
    testAssert.eq(#listing, 1, "the listing has one framed JSON declaration")
    testAssert.eq(listing[1].name, "protocol", "the listing identifies the case")
    testAssert.eq(read(stdout), "application started\n", "application output stays on stdout")

    local ran = os.execute(
        inWorkspace(
            working,
            ("%q run -O1 %q --case protocol --n 3 --out %q > %q"):format(NUPP, fixture, recordOut, stdout)
        )
    )
    testAssert.eq(ran, 0, "the selected case exits successfully")
    local record = json.decode(read(recordOut))
    testAssert.eq(record.cases[1].n, 3, "the runner's iteration count bypasses calibration")
    local human = read(stdout)
    local progressAt = human:find("# Benchmark: protocol", 1, true)
    local resultsAt = human:find("Benchmark%s+Mode%s+Cnt%s+Score%s+Units")
    assert(progressAt ~= nil, "the case is announced before it runs")
    assert(resultsAt ~= nil and progressAt < resultsAt, "progress precedes the result table")
    assert(human:find("protocol%s+p50%s+7%s+[%d.]+%s+ns/op") ~= nil, "the result is per operation")

    -- Real library output, read back through the actual CLI baseline path.
    local baseline = working .. "/baseline.json"
    for _, schema in ipairs({2, 3, 4}) do
        local prior = json.decode(read(recordOut))
        prior.schema = schema
        if schema < 4 then
            for _, measurement in ipairs(prior.cases) do
                local renamed = {}
                for key, value in pairs(measurement) do
                    if type(key) == "string" and key:match("Ms$") then
                        if type(value) == "number" then
                            value = value / 1000
                        elseif type(value) == "table" then
                            local seconds = {}
                            for index, sample in ipairs(value) do
                                seconds[index] = sample / 1000
                            end
                            value = seconds
                        end
                        renamed[key:gsub("Ms$", "Sec")] = value
                    else
                        renamed[key] = value
                    end
                end
                for key in pairs(measurement) do
                    measurement[key] = nil
                end
                for key, value in pairs(renamed) do
                    measurement[key] = value
                end
            end
        end
        local baselineText = json.encode(prior)
        local handle = assert(io.open(baseline, "wb"))
        handle:write(baselineText)
        handle:close()
        local status = os.execute(
            inWorkspace(
                working,
                (
                    "%q run -O1 %q --case protocol --n 3 --baseline %q --out %q --quiet > %q"
                ):format(NUPP, fixture, baseline, recordOut, stdout)
            )
        )
        testAssert.eq(status, 0, "standalone baseline schema " .. schema .. " reads")
        local nextRecord = json.decode(read(recordOut))
        testAssert.eq(nextRecord.schema, 4)
        assert(type(nextRecord.cases[1].medianMs) == "number", "schema4 output retains milliseconds")
        testAssert.eq(nextRecord.cases[1].medianms, nil, "the public field does not leak into JSON")
        testAssert.eq(read(baseline), baselineText, "reading a baseline does not rewrite it")
    end

    os.execute(("rm -rf %q"):format(working))
end

return M
