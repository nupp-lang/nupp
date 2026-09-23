local observation = require("nupp.compiler.testimpact.observe")
local fs = require("nupp.compiler.fs")

local M = {}

local function newObservation()
    return observation.new({
        runId = "run-1",
        platform = "macos-arm64-luajit",
        fragmentDir = "build/.nupp-test-impact-run/run-1",
        projectRoot = "/repo",
    })
end

local function owner(fragment, suite, caseId)
    for _, found in ipairs(fragment.owners) do
        if found.suite == suite and found.caseId == caseId then
            return found
        end
    end
    error("no observation owner " .. suite .. "/" .. tostring(caseId), 0)
end

local function root(found, name)
    for _, edge in ipairs(found.roots) do
        if edge.module == name then
            return edge
        end
    end
    error("no module root " .. name, 0)
end

function M.suiteAndStableCaseScopesKeepCachedRequestsDistinct()
    local observed = newObservation()
    observed.beginSuite("tests/exampletest.lua")
    observed.recordRequest("fixture.shared", "/repo/src/fixture/shared.nupp", "runtime-require")
    observed.beginCase("tests/exampletest.lua/first")
    observed.recordRequest("fixture.shared", "/repo/src/fixture/shared.nupp", "cached-require")
    observed.finishCase()
    observed.beginCase("tests/exampletest.lua/second#row-a")
    observed.recordRequest("fixture.shared", "/repo/src/fixture/shared.nupp", "cached-require")
    observed.finishCase()
    observed.finishSuite()

    local fragment = observed.fragment(true)
    assert(#fragment.owners == 3, "suite load and both stable cases retain owners")
    assert(root(owner(fragment, "tests/exampletest.lua", nil), "fixture.shared").path == "src/fixture/shared.nupp")
    assert(root(owner(fragment, "tests/exampletest.lua", "tests/exampletest.lua/first"), "fixture.shared"))
    assert(root(owner(fragment, "tests/exampletest.lua", "tests/exampletest.lua/second#row-a"), "fixture.shared"))
    assert(fragment.complete, "cached requests are complete observations")
end

function M.completedBuildStateCarriesCheckedRuntimeAndSemanticProvenance()
    local observed = newObservation()
    observed.beginSuite("tests/buildtest.lua")
    observed.beginCase("tests/buildtest.lua/builds")
    observed.recordBuildState(
        {
            modules = {
                app = {
                    sourcePath = "/repo/src/app.nupp",
                    dependencies = {"library"},
                    runtimeModules = {"nupp.runtime.provider.nativefiles"},
                    compilerRuntime = {"nupp.runtime.native"},
                    projectDependencies = {
                        {name = "moduleCallGuarantee", key = "library\0call", paths = {"/repo/src/library.nupp"},}
                    },
                },
                library = {
                    sourcePath = "/repo/src/library.nupp",
                    dependencies = {},
                    runtimeModules = {},
                    projectDependencies = {},
                },
            },
        },
        "/repo"
    )
    observed.finishCase()
    observed.finishSuite()

    local fragment = observed.fragment(true)
    local found = owner(fragment, "tests/buildtest.lua", "tests/buildtest.lua/builds")
    assert(root(found, "app").path == "src/app.nupp")
    assert(root(found, "library").path == "src/library.nupp")
    assert(#fragment.dependencies == 1, "only a module with dependencies needs adjacency")
    local edges = fragment.dependencies[1].dependencies
    assert(fragment.dependencies[1].module == "app" and #edges == 4)
    assert(edges[1].module == "@project/moduleCallGuarantee/library\0call/16:src/library.nupp")
    assert(edges[1].path == "src/library.nupp")
    assert(edges[2].module == "library")
    assert(edges[3].module == "nupp.runtime.native")
    assert(edges[4].module == "nupp.runtime.provider.nativefiles")
end

function M.fixtureModulesCannotCollideWithSameNamedRepositoryModules()
    local observed = newObservation()
    observed.beginSuite("tests/buildtest.lua")
    observed.beginCase("tests/buildtest.lua/builds-fixture")
    observed.recordBuildState(
        {
            modules = {
                shared = {
                    sourcePath = "/repo/src/shared.nupp",
                    dependencies = {},
                    runtimeModules = {},
                    projectDependencies = {},
                },
            },
        },
        "/repo"
    )
    observed.recordBuildState(
        {
            modules = {
                app = {
                    sourcePath = "/private/tmp/fixture/src/app.nupp",
                    dependencies = {"shared", "external.lib", "nupp.io.path"},
                    runtimeModules = {"nupp.io.path"},
                    projectDependencies = {},
                },
                shared = {
                    sourcePath = "/private/tmp/fixture/src/shared.nupp",
                    dependencies = {},
                    runtimeModules = {},
                    projectDependencies = {},
                },
                [
                    "external.lib"
                ] = {
                    sourcePath = "/opt/dependency/external/lib.d.nupp",
                    external = true,
                    dependencies = {},
                    runtimeModules = {},
                    projectDependencies = {},
                },
                [
                    "nupp.io.path"
                ] = {
                    sourcePath = "/private/tmp/fixture/build/cache/runtime-source/nupp/io/path.nupp",
                    compilerRuntime = true,
                    dependencies = {},
                    runtimeModules = {},
                    projectDependencies = {},
                },
            },
        },
        "/private/tmp/fixture"
    )
    observed.finishCase()
    observed.finishSuite()

    local fragment = observed.fragment(true)
    local found = owner(fragment, "tests/buildtest.lua", "tests/buildtest.lua/builds-fixture")
    assert(root(found, "shared").path == "src/shared.nupp", "the repository module keeps its identity")
    local fixtureShared
    local fixtureApp
    for _, edge in ipairs(found.roots) do
        if edge.module:match("^@fixture/") and edge.module:match("/shared$") then
            fixtureShared = edge
        elseif edge.module:match("^@fixture/") and edge.module:match("/app$") then
            fixtureApp = edge
        end
    end
    assert(fixtureShared and fixtureShared.path == nil, "fixture shared has a stable synthetic identity")
    assert(fixtureApp and fixtureApp.path == nil, "fixture app does not persist its temporary path")
    assert(fixtureShared.module ~= "shared", "fixture and repository module identities cannot collide")
    assert(root(found, "external.lib").path == nil, "external identity is preserved without an absolute path")
    assert(root(found, "nupp.io.path").path == nil, "runtime identity is preserved without its staging path")

    local appDependencies
    for _, record in ipairs(fragment.dependencies) do
        if record.module == fixtureApp.module then
            appDependencies = record.dependencies
        end
    end
    assert(appDependencies and #appDependencies == 3)
    assert(appDependencies[1].module == fixtureShared.module)
    assert(appDependencies[2].module == "external.lib")
    assert(appDependencies[3].module == "nupp.io.path")
end

function M.compilerRuntimeStagingPathsCanonicalizeToRepositorySources()
    local projectRoot = fs.absolute(".")
    local observed = observation.new({
        runId = "run-1",
        platform = "macos-arm64-luajit",
        fragmentDir = "build/.nupp-test-impact-run/run-1",
        projectRoot = projectRoot,
    })
    observed.beginSuite("tests/buildtest.lua")
    observed.beginCase("tests/buildtest.lua/builds-runtime")
    observed.recordBuildState(
        {
            modules = {
                [
                    "nupp.codec.base64"
                ] = {
                    sourcePath = projectRoot .. "/build/app/cache/runtime-source/nupp/codec/base64.nupp",
                    compilerRuntime = true,
                    dependencies = {},
                    runtimeModules = {},
                    projectDependencies = {},
                },
            },
        },
        projectRoot
    )
    observed.finishCase()
    observed.finishSuite()

    local fragment = observed.fragment(true)
    local found = owner(fragment, "tests/buildtest.lua", "tests/buildtest.lua/builds-runtime")
    assert(root(found, "nupp.codec.base64").path == "src/nupp/codec/base64.nupp")
end

function M.childFragmentsCarryExactOwnershipAndMergeIntoTheCase()
    local parent = newObservation()
    parent.beginSuite("tests/clitest.lua")
    parent.beginCase("tests/clitest.lua/child-build")
    local environment = parent.childEnvironment("child-1")
    assert(environment.NUPP_TEST_IMPACT_RUN_ID == "run-1")
    assert(environment.NUPP_TEST_IMPACT_SUITE == "tests/clitest.lua")
    assert(environment.NUPP_TEST_IMPACT_CASE == "tests/clitest.lua/child-build")
    assert(environment.NUPP_TEST_IMPACT_PROJECT_ROOT == "/repo")
    assert(not pcall(parent.childEnv, "../escaped"), "child fragment names must stay inside the run directory")

    local child = observation.new({
        runId = "run-1",
        platform = "macos-arm64-luajit",
        projectRoot = environment.NUPP_TEST_IMPACT_PROJECT_ROOT,
    })
    child.beginSuite(environment.NUPP_TEST_IMPACT_SUITE)
    child.beginCase(environment.NUPP_TEST_IMPACT_CASE)
    child.recordRequest("child.module", "src/child.nupp", "child-require")
    child.finishCase()
    child.finishSuite()
    parent.finishChild("child-1", child.fragment(true))
    parent.finishCase()
    parent.finishSuite()

    local fragment = parent.fragment(true)
    assert(root(owner(fragment, "tests/clitest.lua", "tests/clitest.lua/child-build"), "child.module"))
    assert(fragment.complete, "a valid child fragment settles owned work")
end

function M.missingEscapedAndUnresolvedWorkAreExplicitUncertainty()
    local observed = newObservation()
    observed.beginSuite("tests/dynamictest.lua")
    observed.beginCase("tests/dynamictest.lua/computed")
    observed.recordRequest({}, nil)
    observed.childEnvironment("crashed")
    observed.markEscapedChild("direct native spawn")
    observed.finishCase()
    observed.finishSuite()

    local fragment = observed.fragment(true)
    local uncertainty = owner(fragment, "tests/dynamictest.lua", "tests/dynamictest.lua/computed").uncertainty
    assert(not fragment.complete and #uncertainty == 3)
    assert(uncertainty[1].code == "child-fragment-missing")
    assert(uncertainty[2].code == "child-uninstrumented")
    assert(uncertainty[3].code == "unresolved-module")
end

function M.compilerChildObservesCachedRequiresAndWritesAPrivateFragment()
    local directory = os.tmpname()
    local projectRoot = fs.absolute(".")
    os.remove(directory)
    assert(fs.mkdir(directory))
    local environment = {
        NUPP_TEST_IMPACT_RUN_ID = "child-run",
        NUPP_TEST_IMPACT_FORMAT = tostring(observation.FORMAT),
        NUPP_TEST_IMPACT_PLATFORM = "test-platform",
        NUPP_TEST_IMPACT_FRAGMENT_DIR = directory,
        NUPP_TEST_IMPACT_CHILD = "child-7",
        NUPP_TEST_IMPACT_SUITE = "tests/clitest.lua",
        NUPP_TEST_IMPACT_CASE = "tests/clitest.lua/runs-child",
        NUPP_TEST_IMPACT_PROJECT_ROOT = projectRoot,
    }
    local child = assert(
        observation.fromEnvironment(function(name)
            return environment[name]
        end)
    )
    assert(observation.current() == child)
    local nested = observation.childEnv("grandchild")
    assert(nested.NUPP_TEST_IMPACT_CASE == "tests/clitest.lua/runs-child")
    assert(nested.NUPP_TEST_IMPACT_PROJECT_ROOT == projectRoot)
    child.finishChild("grandchild", {
        format = observation.FORMAT,
        runId = "child-run",
        platform = "test-platform",
        projectRoot = projectRoot,
        owners = {},
        dependencies = {},
    })
    observation.completedBuild(
        {modules = {built = {sourcePath = "src/built.nupp", dependencies = {}, runtimeModules = {},}},},
        "."
    )
    package.loaded["impact.cached.fixture"] = {cached = true}
    assert(require("impact.cached.fixture").cached)
    assert(observation.finishProcess(child, 7))
    package.loaded["impact.cached.fixture"] = nil

    local fragment = assert(observation.readFragment(directory .. "/child-7.buf"))
    local found = owner(fragment, "tests/clitest.lua", "tests/clitest.lua/runs-child")
    local edge = root(found, "impact.cached.fixture")
    assert(edge.provenance[1] == "cached-require")
    assert(root(found, "built").provenance[1] == "compiler-build")
    assert(fragment.exitStatus == 7 and not fragment.complete)
    assert(found.uncertainty[1].code == "child-nonzero")
    assert(observation.current() == nil)
    assert(require("nupp.io.files").remove(directory, true))
end

function M.scopeErrorsCannotSilentlyMisattributeWork()
    local observed = newObservation()
    assert(not pcall(observed.recordRequest, "outside"))
    assert(not pcall(observed.beginCase, "case-without-suite"))
    observed.beginSuite("tests/exampletest.lua")
    observed.beginCase("tests/exampletest.lua/one")
    assert(not pcall(observed.finishSuite))
    observed.finishCase()
    observed.finishSuite()
end

return M
