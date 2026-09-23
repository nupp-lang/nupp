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
    local plan = json("tests/fleet/plan.json")
    test.equal(plan.schemaVersion, 1)
    test.equal(#plan.jobs, 11)
    local hosts, tiers, compilers, runtimes, ids = {}, {}, {}, {}, {}
    for _, job in ipairs(plan.jobs) do
        test.assert(not ids[job.id], "duplicate fleet job " .. job.id)
        ids[job.id] = true
        test.equal(job.argv[1], "./bin/nupp")
        test.equal(job.argv[2], "test")
        test.assert(table.concat(job.argv, "\0"):find("--json", 1, true))
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
        test.assert(hosts[host], "missing fleet host " .. host)
    end
    for _, tier in ipairs({"baseline", "avx2", "avx512f", "neon"}) do
        test.assert(tiers[tier], "missing fleet tier " .. tier)
    end
    test.assert(compilers.clang and compilers.gcc)
    test.assert(runtimes["wasmtime-48"] and runtimes.chromium)
end

function M.endpointConfigurationCannotSupplyCommands()
    local config = json("tests/fleet/config.example.json")
    local kinds = {}
    for _, executor in pairs(config.executors) do
        kinds[executor.kind] = true
        test.equal(executor.command, nil)
        test.equal(executor.argv, nil)
    end
    test.assert(kinds["local"] and kinds.ssh and kinds.docker)
end

function M.pythonContractTestsPass()
    local log = "build/fleet-python-tests.log"
    local command = "PYTHONPYCACHEPREFIX=build/python-cache python3 -m unittest tests.test_fleet >" .. log .. " 2>&1"
    local status = os.execute(command)
    test.assert(status == 0, read(log))
end

function M.githubOffersOnlyAManualHostedFleet()
    local workflow = read(".github/workflows/simd-conformance.yml")
    test.assert(workflow:find("workflow_dispatch", 1, true))
    local classifier = dofile(".github/scripts/classify-changes.lua")
    for _, job in ipairs(classifier.jobs) do
        test.assert(job ~= "simd-conformance")
    end
end

return M
