-- The classifier decides which correctness obligations a change has, so a
-- mistake in it is a defect reaching `main` with a green tick beside it. These
-- cases name representative files and assert that each selects every job
-- capable of observing its effects.
--
-- They also hold the four files that describe CI to one account of it: the
-- classifier, `.github/ci-coverage.json`, the workflow, and `tests/groups.lua`.

local test = require("assert")

local M = {}

local function classifier()
    return dofile(".github/scripts/classify-changes.lua")
end

--- The selected jobs for one changed path, as a set.
local function jobsFor(...)
    return classifier().classify({...}).jobs
end

local function selects(path, expected)
    local jobs = jobsFor(path)
    for _, name in ipairs(expected) do
        test.assert(jobs[name], ("%s should select %s"):format(path, name))
    end
end

local function doesNotSelect(path, unexpected)
    local jobs = jobsFor(path)
    for _, name in ipairs(unexpected) do
        test.assert(not jobs[name], ("%s should not select %s"):format(path, name))
    end
end

--- Every job the classifier knows about.
local function everyJob()
    return classifier().jobs
end

function M.compilerChangeSelectsEveryPlatformAndFixpoint()
    selects("src/nupp/compiler/check/callexpr.nupp", {
        "fast-checks",
        "linux-integration",
        "macos-integration",
        "windows-integration",
        "fixpoint",
        "portable-compiler",
        "gpu-linux",
        "gpu-windows",
    })
end

function M.aotChangeSelectsAotAndFixpoint()
    selects("src/nupp/compiler/aot/lower.nupp", {"fast-checks", "linux-integration", "fixpoint"})
end

function M.runtimeChangeSelectsBrowserAndNativeCoverage()
    selects("src/nupp/runtime/tasks.nupp", {"fast-checks", "linux-integration", "portable-compiler", "fixpoint"})
end

function M.browserChangeSelectsThePortableCompiler()
    selects("runtime/wasm/loader.js", {"fast-checks", "linux-integration", "portable-compiler"})
end

function M.gpuChangeSelectsBothAdapters()
    selects("src/nupp/gpu/kernel.nupp", {"gpu-linux", "gpu-windows", "fast-checks", "linux-integration"})
end

function M.nativeChangeSelectsEveryPlatform()
    selects("native/nupp-native/src/http.rs", {
        "fast-checks",
        "linux-integration",
        "macos-integration",
        "windows-integration",
        "gpu-linux",
        "gpu-windows",
        "fixpoint",
    })
end

function M.packagingChangeSelectsEveryPlatform()
    selects("templates/library/nupp.lua", {"linux-integration", "macos-integration", "windows-integration"})
end

function M.testHarnessChangeSelectsEveryPlatform()
    selects("tests/lsptest.lua", {"fast-checks", "linux-integration", "macos-integration", "windows-integration"})
end

-- `scripts/toolchain` decides what every job is built with, and `.github`
-- decides what every job is. Neither has a blast radius smaller than all of it.
function M.toolchainAndWorkflowChangesSelectEverything()
    for _, path in ipairs({
        "scripts/toolchain",
        "scripts/toolchain.pins",
        ".github/workflows/compiler.yml",
        "nupp.lua",
        "Cargo.lock",
        "rust-toolchain.toml"
    }) do
        selects(path, everyJob())
    end
end

-- The rule that makes conservatism the default rather than an aspiration: a
-- path nobody has classified is a path whose blast radius nobody knows.
function M.anUnclassifiedPathSelectsEverything()
    local selection = classifier().classify({"some/place/nobody/described.txt"})
    test.assert(selection.surfaces.unclassified, "an unknown path should be reported as unclassified")
    selects("some/place/nobody/described.txt", everyJob())
end

-- A tag, a schedule and a manual dispatch have no diff to narrow.
function M.anEmptyChangeSelectsEverything()
    local jobs = classifier().classify({}).jobs
    for _, name in ipairs(everyJob()) do
        test.assert(jobs[name], ("an empty change should select %s"):format(name))
    end
end

function M.documentationOnlyChangesProvisionNoPlatform()
    for _, path in ipairs({"docs/reference/language.md", "README.md", "docs/neps/0028-fetched-stage-zero.md"}) do
        selects(path, {"docs-site"})
        doesNotSelect(path, {
            "fast-checks",
            "linux-integration",
            "macos-integration",
            "windows-integration",
            "gpu-linux",
            "gpu-windows",
            "fixpoint",
            "portable-compiler",
        })
    end
end

-- Several paths at once is the ordinary case, and the union is what makes the
-- selection conservative rather than the last rule to match.
function M.aMixedChangeTakesTheUnionOfItsPaths()
    local jobs = jobsFor("docs/reference/language.md", "src/nupp/gpu/kernel.nupp")
    test.assert(jobs["docs-site"], "the documentation obligation should survive")
    test.assert(jobs["gpu-linux"], "the GPU obligation should survive")
end

function M.everyJobTheClassifierKnowsIsSelectableByEverything()
    local selection = classifier().classify({})
    for _, name in ipairs(everyJob()) do
        test.assert(selection.reasons[name], ("%s should record why it was selected"):format(name))
    end
end

-- The check that keeps the classifier, the workflow, the coverage map and the
-- test groups describing one CI rather than four. Called in process rather than
-- run as a subprocess, so this suite stays in the lane the fast gate runs and a
-- classification mistake is reported before any platform is provisioned.
function M.theCoverageMapAgreesWithTheWorkflow()
    local validator = dofile(".github/scripts/validate-ci-coverage.lua")
    local problems, jobs = validator.problems()
    test.equal(table.concat(problems, "; "), "")
    test.assert(jobs > 0, "the workflow should define at least one job")
end

-- A group naming a suite that has been renamed fails at the point the group is
-- finally used, on whichever platform reaches it first, which is as late as a
-- rename can be found. Ask here instead. Globs are left alone: they track new
-- suites by construction, and the runner refuses a glob matching nothing.
function M.everyNamedGroupMemberNamesASuiteThatExists()
    local groups = dofile("tests/groups.lua")
    local names = {}
    for name in pairs(groups) do
        names[#names + 1] = name
    end
    table.sort(names)
    test.assert(#names > 0, "tests/groups.lua defines no groups")
    for _, name in ipairs(names) do
        for _, member in ipairs(groups[name]) do
            if not member:find("*", 1, true) then
                local lua = io.open("tests/" .. member .. ".lua", "r")
                local nupp = lua or io.open("tests/" .. member .. ".nupp", "r")
                test.assert(nupp ~= nil, ("group %s names %s, which is not a suite"):format(name, member))
                if nupp then
                    nupp:close()
                end
            end
        end
    end
end

-- Every group the coverage map says a step runs or excludes has to be a group
-- that exists, which is the other half of the same drift.
function M.everyGroupTheWorkflowNamesIsDefined()
    local validator = dofile(".github/scripts/validate-ci-coverage.lua")
    local problems = validator.problems()
    for _, problem in ipairs(problems) do
        test.assert(not problem:find("group", 1, true), problem)
    end
end

return M
