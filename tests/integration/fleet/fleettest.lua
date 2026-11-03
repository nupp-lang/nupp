local test = require("assert")
local M = {}
local decode = assert(loadfile("src/nupp/runtime/vendor/lunajson/decoder.lua"))()()

local function read(path)
    local file = assert(io.open(path, "rb"))
    local value = file:read("*a")
    file:close()
    return value
end

local function json(path)
    return decode(read(path))
end

function M.planUsesTheMinimumOrthogonalFleet()
    local plan = json("tests/integration/fleet/plan.json")
    test.eq(plan.schemaVersion, 1)
    test.eq(#plan.jobs, 10)
    local hosts, tiers, compilers, runtimes, ids = {}, {}, {}, {}, {}
    for _, job in ipairs(plan.jobs) do
        test(not ids[job.id], "duplicate fleet job " .. job.id)
        ids[job.id] = true
        test.eq(job.argv[1], "./bin/nupp")
        test.eq(job.argv[2], "test")
        test(table.concat(job.argv, "\0"):find("--json", 1, true))
        local target = job.target or {}
        if target.os and target.arch and target.tier ~= "simd128" then
            hosts[target.os .. "-" .. target.arch] = true
        end
        if target.tier and target.tier ~= "simd128" then
            tiers[target.tier] = true
        end
        if target.compiler then
            compilers[target.compiler] = true
        end
        if target.runtime then
            runtimes[target.runtime] = true
        end
    end
    for _, host in ipairs({"linux-x64", "linux-arm64", "macos-x64", "macos-arm64", "windows-x64"}) do
        test(hosts[host], "missing fleet host " .. host)
    end
    for _, tier in ipairs({"baseline", "avx2", "avx512f", "neon"}) do
        test(tiers[tier], "missing fleet tier " .. tier)
    end
    -- Every native job compiles through nupp's own LLVM.
    test(compilers.llvm)
    for compiler in pairs(compilers) do
        test.eq(compiler, "llvm")
    end
    test(runtimes["wasmtime-48"] and runtimes.chromium)
end

function M.endpointConfigurationCannotSupplyCommands()
    local config = json("tests/integration/fleet/config.example.json")
    local kinds = {}
    for _, executor in pairs(config.executors) do
        kinds[executor.kind] = true
        test.eq(executor.command, nil)
        test.eq(executor.argv, nil)
    end
    test(kinds["local"] and kinds.ssh and kinds.docker)
end

function M.pythonContractTestsPass()
    local log = "build/fleet-python-tests.log"
    local command = "PYTHONPYCACHEPREFIX=build/python-cache python3 -m unittest tests.integration.fleet.test_fleet >"
        .. log
        .. " 2>&1"
    local status = os.execute(command)
    test(status == 0, read(log))
end

function M.githubOffersOnlyAManualHostedFleet()
    local workflow = read(".github/workflows/simd-conformance.yml")
    test(workflow:find("workflow_dispatch", 1, true))
    local classifier = dofile(".github/scripts/classify-changes.lua")
    for _, job in ipairs(classifier.jobs) do
        test(job ~= "simd-conformance")
    end
end

return M
