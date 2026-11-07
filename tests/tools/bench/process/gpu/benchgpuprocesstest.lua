local fixture = require("helpers.benchprocess")
local testAssert = fixture.testAssert
local json = fixture.json
local HERE = fixture.HERE
local NUPP = fixture.NUPP
local TIMEOUT_MS = fixture.TIMEOUT_MS
local read = fixture.read
local workspace = fixture.workspace
local inWorkspace = fixture.inWorkspace

local M = {}

function M.gpuCostFilesAreUniqueAcrossForksAndCandidates()
    local working = workspace()
    local directory, stdout = working .. "/gpu-costs", working .. "/stdout.json"
    local fixture = HERE .. "/fixtures/bench_fixed_records.nupp"
    local command = (
        "%q bench --timeout-ms "
        .. TIMEOUT_MS
        .. " --file %q --case '^fixed$' --forks 2 --against %q --margin 5 --gpu-costs %q --json > %q"
    ):format(NUPP, fixture, NUPP, directory, stdout)
    testAssert.eq(os.execute(inWorkspace(working, command)), 0, "cost routing works without requiring a GPU workload")
    local report = json.decode(read(stdout))
    local seen, count = {}, 0
    for _, side in ipairs({report.benchmarks, report.comparisons[1].baseline.benchmarks}) do
        for _, benchmark in ipairs(side) do
            for _, fork in ipairs(benchmark.forks) do
                local path = assert(fork.gpuCosts, "the fork names its GPU cost record")
                assert(not seen[path], "forks and candidates must not share a cost file")
                seen[path], count = true, count + 1
                testAssert.eq(read(path), "", "CPU-only forks invent no GPU operations")
            end
        end
    end
    testAssert.eq(count, 4, "both forks of both candidates have separate outputs")
    os.execute(("rm -rf %q"):format(working))
end

return M
