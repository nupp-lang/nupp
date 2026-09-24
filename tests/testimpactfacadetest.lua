-- Runner-facing assembly of observation fragments and the binary impact graph.

local test = require("assert")
local impact = require("runner.impact")

local M = {}

local function tempDirectory()
    local path = os.tmpname()
    os.remove(path)
    assert(os.execute(("mkdir -p %q"):format(path)) == 0)
    return path
end

local function stamps(overrides)
    local metadata = {
        project = "project:faca",
        revision = "base-revision",
        operatingSystem = "Linux",
        architecture = "x86_64",
        runtime = "LuaJIT 2.1",
        targetProfile = "native-debug",
        suiteCatalog = "catalog:99",
        stableIds = "case-ids/1",
    }
    for key, value in pairs(overrides or {}) do
        metadata[key] = value
    end

    return assert(impact.graphStamps(metadata))
end

local function fragment()
    local observer = impact.newObserver({
        runId = "run-1",
        platform = "linux-x86_64-luajit-native-debug",
        projectRoot = "/project",
    })
    observer.beginSuite("worker")
    observer.recordRequest("app.worker", "/project/src/app/worker.nupp", "suite-load")
    observer.beginCase("builds")
    observer.recordRequest("app.worker", "/project/src/app/worker.nupp", "cached-require")
    observer.recordBuildState(
        {
            modules = {
                ["app.worker"] = {sourcePath = "/project/src/app/worker.nupp", dependencies = {"app.model"},},
                ["app.model"] = {sourcePath = "/project/src/app/model.nupp", dependencies = {},},
            },
        },
        "/project"
    )
    observer.finishCase()
    observer.finishSuite()

    return observer.fragment(true)
end

local function catalog()
    return {
        {
            identity = "worker",
            path = "tests/workertest.lua",
            sliceSafe = false,
            cases = {{id = "builds", sliceSafe = true}},
        },
    }
end

local function flags(overrides)
    local value = {
        runId = "run-1",
        platform = "linux-x86_64-luajit-native-debug",
        complete = true,
        successful = true,
        unfiltered = true,
    }
    for key, item in pairs(overrides or {}) do
        value[key] = item
    end

    return value
end

function M.facadeCarriesEveryStaticallyRequiredCapability()
    test.equal(type(impact.discoverChanges), "function")
    test.equal(type(impact.select), "function")
    test.equal(type(impact.newObserver), "function")
    test.equal(type(impact.mergeFragmentsToObservation), "function")
    test.equal(type(impact.load), "function")
    test.equal(type(impact.publish), "function")
end

function M.graphStampsRequireEveryExactIdentity()
    for _, field in ipairs({
        "project",
        "revision",
        "operatingSystem",
        "architecture",
        "runtime",
        "targetProfile",
        "suiteCatalog",
        "stableIds",
    }) do
        local metadata = stamps()
        metadata[field] = nil
        test.equal(impact.graphStamps(metadata), nil, field .. " was optional")
    end
end

function M.fragmentsBecomeAStoredCaseAwareGraph()
    local root = tempDirectory()
    local observation = impact.mergeFragmentsToObservation({fragment()}, catalog(), stamps(), flags())
    test.equal(observation.complete, true)
    test.equal(#observation.modules, 3)
    test.equal(observation.modules[1].name, "@manifest/8:nupp.lua")
    test.equal(observation.modules[2].name, "app.model")
    test.equal(observation.modules[3].name, "app.worker")
    test.equal(observation.modules[3].dependencies[1], "app.model")
    test.equal(observation.suites[1].path, "tests/workertest.lua")
    test.equal(observation.suites[1].sliceSafe, false)
    test.equal(observation.suites[1].cases[1].sliceSafe, true)
    test.equal(#observation.suites[1].cases[1].roots, 4)

    local published, problem = impact.publish(root, observation)
    test.equal(published, true, problem)
    local graph = assert(impact.load(root, stamps()), "the facade did not read its graph")
    test.equal(graph.cases[1][2], "builds")
    test.equal(graph.caseSliceSafe[1], true)
    test.equal(graph.moduleDependencies[3][1], 2)
    local file = io.open(impact.cachePath(root), "rb")
    test.assert(file ~= nil, "the cache path was not written")
    file:close()
    os.execute(("rm -rf %q"):format(root))
end

function M.semanticProjectDependencyPathsSelectTheirReaders()
    local root = tempDirectory()
    local observer = impact.newObserver({
        runId = "run-1",
        platform = "linux-x86_64-luajit-native-debug",
        projectRoot = "/project",
    })
    observer.beginSuite("worker")
    observer.beginCase("builds")
    observer.recordBuildState(
        {
            modules = {
                [
                    "app.worker"
                ] = {
                    sourcePath = "/project/src/app/worker.nupp",
                    dependencies = {},
                    projectDependencies = {
                        {name = "moduleCallGuarantee", key = "service\0call", paths = {"/project/src/service.nupp"},}
                    },
                },
            },
        },
        "/project"
    )
    observer.finishCase()
    observer.finishSuite()
    local observation = impact.mergeFragmentsToObservation({observer.fragment(true)}, catalog(), stamps(), flags())
    test.equal(observation.complete, true)
    local published, problem = impact.publish(root, observation)
    test.equal(published, true, problem)
    local graph = assert(impact.load(root, stamps()))
    local selected = impact.select(graph, {
        available = true,
        base = "base-revision",
        head = "working-revision",
        changes = {{status = "modified", path = "src/service.nupp"}},
        paths = {"src/service.nupp"},
    })
    test.equal(#selected.selectedSuites, 1)
    test.equal(selected.selectedSuites[1], "tests/workertest.lua")
    os.execute(("rm -rf %q"):format(root))
end

function M.fragmentIdentityAndRunStatePreventPublication()
    local root = tempDirectory()
    local mismatched = fragment()
    mismatched.platform = "another-platform"
    local identity = impact.mergeFragmentsToObservation({mismatched}, catalog(), stamps(), flags())
    test.equal(identity.complete, false)
    test.equal(impact.publish(root, identity), false)

    for _, field in ipairs({"complete", "successful", "unfiltered"}) do
        local state = impact.mergeFragmentsToObservation({fragment()}, catalog(), stamps(), flags({[field] = false}))
        test.equal(impact.publish(root, state), false, field .. " state published")
    end
    os.execute(("rm -rf %q"):format(root))
end

local function nonemptyDiff()
    return {
        available = true,
        base = "base-revision",
        head = "working-revision",
        changes = {{status = "modified", path = "notes.txt"}},
        paths = {"notes.txt"},
    }
end

local function knownUnaffecting()
    return {
        classifyPath = function()
            return {scope = "none", code = "prose-only", reason = "not consumed by tests"}
        end,
    }
end

function M.explicitUncertaintyPublishesAndAlwaysSelectsItsOwner()
    local root = tempDirectory()
    local suiteUncertain = fragment()
    suiteUncertain.owners[1].uncertainty = {{code = "dynamic-module", detail = "computed name"}}
    suiteUncertain.complete = false
    local suiteObservation = impact.mergeFragmentsToObservation({suiteUncertain}, catalog(), stamps(), flags())
    test.equal(suiteObservation.complete, true)
    test.equal(suiteObservation.suites[1].uncertainty[1], "dynamic-module:13:computed name")
    test.equal(impact.publish(root, suiteObservation), true)
    local suiteSelection = impact.select(assert(impact.load(root, stamps())), nonemptyDiff(), knownUnaffecting())
    test.equal(suiteSelection.selectedSuites[1], "tests/workertest.lua")
    test.equal(suiteSelection.fallbacks[1].code, "uncertain-suite-selected")

    local caseUncertain = fragment()
    for _, owner in ipairs(caseUncertain.owners) do
        if owner.caseId == "builds" then
            owner.uncertainty = {{code = "child-uninstrumented", detail = "native spawn"}}
        end
    end
    caseUncertain.complete = false
    local caseObservation = impact.mergeFragmentsToObservation({caseUncertain}, catalog(), stamps(), flags())
    test.equal(caseObservation.complete, true)
    test.equal(impact.publish(root, caseObservation), true)
    local caseSelection = impact.select(assert(impact.load(root, stamps())), nonemptyDiff(), knownUnaffecting())
    test.equal(caseSelection.selectedSuites[1], "tests/workertest.lua")
    test.equal(caseSelection.promotions[1].code, "uncertain-case-promoted")
    os.execute(("rm -rf %q"):format(root))
end

function M.catalogMismatchAndConflictingModulePathsAreIncomplete()
    local unknown = fragment()
    unknown.owners[1].suite = "not-in-catalog"
    local missing = impact.mergeFragmentsToObservation({unknown}, catalog(), stamps(), flags())
    test.equal(missing.complete, false)

    local conflict = fragment()
    conflict.owners[
        1
    ].roots[
        #conflict.owners[1].roots + 1
    ] = {module = "app.worker", path = "src/other-worker.nupp", provenance = {"runtime-require"},}
    local conflicting = impact.mergeFragmentsToObservation({conflict}, catalog(), stamps(), flags())
    test.equal(conflicting.complete, false)

    local unobserved = impact.mergeFragmentsToObservation({}, catalog(), stamps(), flags())
    test.equal(unobserved.complete, false, "an unobserved catalog published")
end

return M
