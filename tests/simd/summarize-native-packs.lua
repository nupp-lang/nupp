local runner = require("tests.simd.runner")
local directory = assert(arg[1])
local selection = runner.json(directory .. "/selection.json")

local function optional(path)
    local ok, value = pcall(runner.read, path)
    return ok and value or "unavailable"
end

local function positive(value)
    return type(value) == "number" and value > 0
end

local function clean(value)
    return tostring(value):gsub("[^%w%._%-]", "-")
end

local expected, wholeTier = {}, {}

local function key(compiler, tier, family, element)
    return table.concat({compiler, tier, family, element}, "\t")
end

for compiler in ipairs(selection.compilers) do
    for _, tier in ipairs(selection.tiers) do
        local group = key(tostring(compiler), tier, "-", "-")
        wholeTier[group] = {}
        local pack = key(tostring(compiler), tier, "packs", "compact")
        expected[pack] = true
        wholeTier[group][#wholeTier[group] + 1] = pack
        for _, algorithm in ipairs(selection.algorithms) do
            local id = key(tostring(compiler), tier, "algorithms", algorithm)
            expected[id] = true
            wholeTier[group][#wholeTier[group] + 1] = id
        end
    end
end

local seen, rows, tests = {}, {}, {}
local executed, unavailable, failures = 0, 0, 0
for line in runner.read(directory .. "/matrix.tsv"):gmatch("[^\r\n]+") do
    local compiler, tier, family, element, status, evidence = line:match(
        "^([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)\t(.+)$"
    )
    assert(compiler, "malformed compact native matrix row")
    local id = key(compiler, tier, family, element)
    local row = {
        compiler = compiler,
        tier = tier,
        family = family,
        element = element,
        status = status,
        evidence = evidence
    }
    local ok, problem = pcall(function()
        assert(not seen[id], "duplicate compact native matrix row")
        seen[id] = true
        if wholeTier[id] then
            assert(status == "failed" or status == "not-executed", "invalid whole-tier status")
            for _, child in ipairs(wholeTier[id]) do
                assert(not seen[child], "whole-tier row conflicts with execution row")
                seen[child] = true
            end
            return
        end
        assert(expected[id], "matrix row was not requested")
        assert(status == "executed" or status == "failed", "invalid execution status")
        if status ~= "executed" then
            return
        end
        local report = runner.json(evidence)
        if family == "packs" then
            assert(report.ok == true and report.failed == 0, "compact harness report failed")
            local required = {
                ["simdprimitivedifferentialtest/nativeSpeciesInventory"] = false,
                ["simdprimitivedifferentialtest/nativeSemanticConformance"] = false,
            }
            for _, case in ipairs(report.tests or {}) do
                if required[case.id] ~= nil then
                    assert(case.status == "passed", case.id .. " did not execute")
                    required[case.id] = true
                end
                case.id = compiler .. "/" .. tier .. "/" .. case.id
                tests[#tests + 1] = case
            end
            for name, present in pairs(required) do
                assert(present, "compact harness report omitted " .. name)
            end
            row.execution = {ok = true, cases = report.passed, metrics = report.metrics, report = evidence,}
        else
            assert(
                report.ok == true
                and report.algorithm == element
                and report.tier == tier
                and positive(report.cases)
                and positive(report.nativeCalls),
                "algorithm execution proof is incomplete"
            )
            local command = selection.compilers[tonumber(compiler)]
            assert(report.compiler == command, "algorithm compiler differs from request")
            local prefix = clean(command) .. "/" .. tier .. "/" .. clean(optional(directory .. "/host.txt"))
            tests[
                #tests + 1
            ] = {
                id = "native-algorithm/" .. prefix .. "/" .. element,
                suite = "simd-native-algorithm",
                name = element,
                status = "passed",
                durationMs = 0,
                facts = {
                    {
                        name = "coverage.witness",
                        value = {
                            id = "native/" .. prefix .. "/algorithm/" .. element,
                            obligation = "simd.native.algorithm",
                            dimensions = {backend = "native", algorithm = element, tier = tier},
                        },
                    }
                },
            }
            row.execution = report
        end
    end)
    if not ok then
        row.status, row.reason = "failed", tostring(problem)
    end
    if row.status == "executed" then
        executed = executed + 1
    elseif row.status == "not-executed" then
        unavailable = unavailable + 1
    else
        failures = failures + 1
    end
    rows[#rows + 1] = row
end
for id in pairs(expected) do
    if not seen[id] then
        failures = failures + 1
        rows[#rows + 1] = {status = "failed", reason = "Requested compact native matrix row is missing", id = id}
    end
end

local boundaryFacts = {}
local revision = runner.read(directory .. "/revision.txt"):gsub("\n$", "")
local boundaryPrefix = clean(
    revision
) .. "/" .. clean(
    optional(directory .. "/host.txt")
) .. "/" .. clean(table.concat(selection.compilers, ",")) .. "/" .. clean(table.concat(selection.tiers, ","))
for _, boundary in ipairs(runner.json(runner.root() .. "/tests/simd/runtime-boundaries.json")) do
    boundaryFacts[
        #boundaryFacts + 1
    ] = {
        name = "coverage.witness",
        value = {
            id = "native/" .. boundaryPrefix .. "/runtime/" .. clean(boundary.target),
            obligation = "simd.runtime-boundary",
            dimensions = {target = boundary.target, status = boundary.status},
        },
    }
end
tests[
    #tests + 1
] = {
    id = "simd-native-runtime-boundaries/" .. boundaryPrefix,
    suite = "simd-native-runtime-boundaries",
    name = "recordedUnsupportedTargets",
    status = "passed",
    durationMs = 0,
    facts = boundaryFacts,
}

local report = {
    schemaVersion = 3,
    ok = failures == 0,
    total = #tests,
    passed = #tests,
    skipped = 0,
    notExecuted = unavailable,
    failed = failures,
    durationMs = 0,
    tests = tests,
    selection = selection,
    rows = rows,
    executed = executed,
    unavailable = unavailable,
    requested_native_matrix_complete = failures == 0 and unavailable == 0 and executed > 0,
    revision = revision,
    host = optional(directory .. "/host.txt"):gsub("\n$", ""),
    cpu = optional(directory .. "/cpu.txt"),
    vm = optional(directory .. "/vm.txt"),
}
runner.writeJson(directory .. "/summary.json", report)
print(
    "SIMD compact native matrix: "
    .. executed
    .. " executed, "
    .. unavailable
    .. " unavailable, "
    .. failures
    .. " failed; complete="
    .. tostring(
        report.requested_native_matrix_complete
    )
)
if failures > 0 or (executed == 0 and unavailable == 0) then
    os.exit(1)
end
