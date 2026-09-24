local observation = require("nupp.compiler.testimpact.observe")
local fs = require("nupp.compiler.fs")

local M = {}

local function newObservation()
    return observation.new({
        runId = "run-1",
        platform = "macos-arm64-luajit",
        fragmentDir = "build/.nupp-test-impact-run/run-1",
        projectRoot = "/repo",
        compiler = "/repo/bin/nupp",
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

function M.trackedSubprojectPathsRebaseThroughTheChildBuildRoot()
    local projectRoot = fs.absolute(".")
    local buildRoot = projectRoot .. "/examples/tracked"
    local observed = observation.new({runId = "run-1", platform = "test", projectRoot = projectRoot,})
    observed.beginSuite("tests/subprojecttest.lua")
    observed.beginCase("builds")
    observed.recordBuildState(
        {
            modules = {
                app = {
                    sourcePath = "src/app.nupp",
                    dependencies = {},
                    runtimeModules = {},
                    projectDependencies = {
                        {name = "moduleCallGuarantee", key = "leaf\0call", paths = {"src/leaf.nupp"},},
                        {name = "projectEntries", key = "Absent", paths = {"@project/catalog"},},
                    },
                },
            },
        },
        buildRoot
    )
    observed.finishCase()
    observed.finishSuite()

    local fragment = observed.fragment(true)
    local found = owner(fragment, "tests/subprojecttest.lua", "builds")
    assert(root(found, "app").path == "examples/tracked/src/app.nupp")
    local manifest
    for _, edge in ipairs(found.roots) do
        if edge.module:match("^@manifest/") then
            manifest = edge
        end
    end
    assert(manifest and manifest.path == "examples/tracked/nupp.lua")
    local edges = fragment.dependencies[1].dependencies
    assert(edges[1].path == "@project/catalog" or edges[2].path == "@project/catalog")
    assert(edges[1].path == "examples/tracked/src/leaf.nupp" or edges[2].path == "examples/tracked/src/leaf.nupp")
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

function M.externalFixtureCatalogsRemainOwnerScopedAndPathless()
    local observed = newObservation()
    observed.beginSuite("tests/buildtest.lua")
    local semantic = {}
    for index, caseId in ipairs({"first-fixture", "second-fixture"}) do
        observed.beginCase(caseId)
        observed.recordBuildState(
            {
                modules = {
                    app = {
                        sourcePath = "src/app.nupp",
                        dependencies = {},
                        runtimeModules = {},
                        projectDependencies = {
                            {name = "projectModulePath", key = "missing", paths = {"@project/catalog"},}
                        },
                    },
                },
            },
            "/private/tmp/fixture-" .. tostring(index)
        )
        observed.finishCase()
    end
    observed.finishSuite()

    local fragment = observed.fragment(true)
    for _, record in ipairs(fragment.dependencies) do
        if record.module:match("^@fixture/") and record.module:match("/app$") then
            assert(#record.dependencies == 1)
            local edge = record.dependencies[1]
            assert(edge.module:match("^@fixture/"), "fixture semantic fact is owner scoped")
            assert(edge.module:match("/@project/projectModulePath/missing/0:external$"))
            assert(edge.path == nil, "fixture catalog does not carry the repository catalog path")
            semantic[#semantic + 1] = edge.module
        end
    end
    assert(#semantic == 2, "both fixture catalogs were observed")
    assert(semantic[1] ~= semantic[2], "same-key fixture catalogs cannot merge")
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
    child.childEnvironment("grandchild")
    child.finishChild("grandchild", {
        format = observation.FORMAT,
        runId = "run-1",
        platform = "macos-arm64-luajit",
        projectRoot = "/repo",
        complete = true,
        owners = {
            {
                suite = "tests/clitest.lua",
                caseId = "tests/clitest.lua/child-build",
                roots = {
                    {module = "grandchild.module", path = "src/grandchild.nupp", provenance = {"compiler-build"},},
                },
                uncertainty = {},
            },
        },
        dependencies = {},
    })
    child.finishCase()
    child.finishSuite()
    parent.finishChild("child-1", child.fragment(true))
    parent.finishCase()
    parent.finishSuite()

    local fragment = parent.fragment(true)
    assert(root(owner(fragment, "tests/clitest.lua", "tests/clitest.lua/child-build"), "child.module"))
    assert(root(owner(fragment, "tests/clitest.lua", "tests/clitest.lua/child-build"), "grandchild.module"))
    assert(fragment.complete, "a valid child fragment settles owned work")
end

function M.compilerLaunchRecognitionRequiresTheExecutableToken()
    local compiler = "/repo/bin/nupp"
    assert(observation.compilerLaunch("'/repo/bin/nupp' check src/main.nupp", compiler, "/repo").count == 1)
    local nativeCommand = observation.compilerLaunch(
        "__NUPP_WINDOWS_COMMAND__'/repo/bin/nupp' check src/main.nupp",
        compiler,
        "/repo"
    )
    assert(nativeCommand.count == 1 and nativeCommand.nativeCommand)
    assert(observation.compilerLaunch("./bin/nupp build", compiler, "/repo").count == 1)
    assert(observation.compilerLaunch("NUPP=/repo/bin/nupp /repo/bin/nupp check", compiler, "/repo").count == 1)
    assert(observation.compilerLaunch("HERE/../bin/nupp check", compiler, "/repo").count == 1)
    assert(observation.compilerLaunch("cd /repo/tests && ../bin/nupp check", compiler, "/repo").count == 1)
    local copiedCwd = observation.compilerLaunch("cd /copy && ./bin/nupp check", compiler, "/repo")
    assert(copiedCwd.count == 0 and copiedCwd.candidates == 1)
    local outsideCwd = observation.compilerLaunch("cd /tmp && /repo/bin/nupp check missing.nupp", compiler, "/repo")
    assert(outsideCwd.count == 1 and outsideCwd.cwd == "/tmp")
    local unknownCwd = observation.compilerLaunch('cd "$HERE" && ./bin/nupp check', compiler, "/repo")
    assert(unknownCwd.count == 0 and unknownCwd.unknown)
    assert(observation.compilerLaunch("echo /repo/bin/nupp", compiler, "/repo").count == 0)
    assert(observation.compilerLaunch("mkdir -p /tmp/nupp-work/bin", compiler, "/repo").count == 0)
    assert(observation.compilerLaunch("'/tmp/nupp-tool' /repo/bin/nupp", compiler, "/repo").count == 0)
    local copied = observation.compilerLaunch("/copy/bin/nupp check", compiler, "/repo")
    assert(copied.count == 0 and copied.candidates == 1)
    local bootstrap = observation.compilerLaunch("luajit /copy/bootstrap/nupp.lua check", compiler, "/repo")
    assert(bootstrap.count == 0 and bootstrap.candidates == 1)
    local redirected = observation.compilerLaunch("{ /repo/bin/nupp check 2>&1; printf '%s' $?; }", compiler, "/repo")
    assert(redirected.count == 1 and not redirected.concurrent)
    local nestedShell = observation.compilerLaunch("sh -c '/repo/bin/nupp check src/main.nupp'", compiler, "/repo")
    assert(nestedShell.count == 1 and not nestedShell.unknown)
    assert(observation.compilerLaunch("env -u NUPP /repo/bin/nupp check", compiler, "/repo").count == 1)
    local envCwd = observation.compilerLaunch("env -C /copy ./bin/nupp check", compiler, "/repo")
    assert(envCwd.count == 0 and envCwd.candidates == 1)
    for _, wrapper in ipairs({"time", "nice", "timeout 10", "sudo",}) do
        local wrapped = observation.compilerLaunch(wrapper .. " /repo/bin/nupp check", compiler, "/repo")
        assert(wrapped.count == 0 and wrapped.unknown, wrapper .. " must remain conservative")
    end
    local conditional = observation.compilerLaunch("if /repo/bin/nupp check; then echo yes; fi", compiler, "/repo")
    assert(conditional.count == 1)
    assert(observation.compilerLaunch("! /repo/bin/nupp check", compiler, "/repo").count == 1)
    local newline = observation.compilerLaunch("/repo/bin/nupp check\n/repo/bin/nupp build", compiler, "/repo")
    assert(newline.count == 2)
    assert(observation.compilerLaunch("$NUPP check", compiler, "/repo").unknown)
    assert(not observation.compilerLaunch("sh -c '$CMD'", compiler, "/repo").unknown)
    assert(observation.compilerLaunch("sh -c '$NUPP check'", compiler, "/repo").unknown)
    local concurrent = observation.compilerLaunch("./bin/nupp check & ./bin/nupp build", compiler, "/repo")
    assert(concurrent.count == 2 and concurrent.concurrent)
    assert(observation.compilerLaunch("echo $(/repo/bin/nupp check)", compiler, "/repo").unknown)
    assert(observation.compilerLaunch("/repo/bin/nupp test", compiler, "/repo").risky)
    assert(observation.compilerLaunch("/repo/bin/nupp bench", compiler, "/repo").risky)
    assert(observation.compilerLaunch("/repo/bin/nupp bench --against=lua", compiler, "/repo").risky)
end

function M.concurrentCompilerLaunchesRemainUncertain()
    local observed = newObservation()
    observed.beginSuite("tests/clitest.lua")
    observed.beginCase("tests/clitest.lua/concurrent")
    local savedExecute = os.execute
    os.execute = function()
        return 0
    end
    observed.installProcessObserver()
    os.execute("./bin/nupp check & ./bin/nupp build")
    observed.restoreProcessObserver()
    os.execute = savedExecute
    observed.finishCase()
    observed.finishSuite()

    local fragment = observed.fragment(true)
    local uncertainty = owner(fragment, "tests/clitest.lua", "tests/clitest.lua/concurrent").uncertainty
    assert(not fragment.complete and #uncertainty == 2)
    assert(uncertainty[1].code == "child-fragment-missing")
    assert(uncertainty[2].code == "child-uninstrumented")
end

function M.windowsRunnerShellAdapterOwnsInstrumentedCompilerCommands()
    local observed = newObservation()
    observed.beginSuite("tests/clitest.lua")
    observed.beginCase("tests/clitest.lua/windows-shell")
    local savedExecute = os.execute
    local savedAdapter = rawget(_G, "__NUPP_TEST_SHELL_EXECUTE")
    local adapted
    os.execute = function()
        error("instrumented command bypassed the runner shell adapter")
    end
    rawset(_G, "__NUPP_TEST_SHELL_EXECUTE", function(command)
        adapted = command
        return 0
    end)
    observed.installProcessObserver()
    os.execute("/repo/bin/nupp check missing.nupp")
    observed.restoreProcessObserver()
    os.execute = savedExecute
    rawset(_G, "__NUPP_TEST_SHELL_EXECUTE", savedAdapter)
    observed.finishCase()
    observed.finishSuite()

    assert(type(adapted) == "string" and adapted:match("^env "))
end

function M.windowsNativeCompilerCommandsKeepTheirRawExecutionRoute()
    local observed = newObservation()
    observed.beginSuite("tests/clitest.lua")
    observed.beginCase("tests/clitest.lua/windows-native")
    local savedExecute, savedPopen = os.execute, io.popen
    local savedShellExecute = rawget(_G, "__NUPP_TEST_SHELL_EXECUTE")
    local savedShellPopen = rawget(_G, "__NUPP_TEST_SHELL_POPEN")
    local executed, opened
    os.execute = function(command)
        executed = command
        return 23
    end
    io.popen = function(command, mode)
        opened = command .. ":" .. tostring(mode)
        return {
            close = function()
                return true
            end,
        }
    end
    rawset(_G, "__NUPP_TEST_SHELL_EXECUTE", function()
        error("a native Windows command was sent through Git Bash")
    end)
    rawset(_G, "__NUPP_TEST_SHELL_POPEN", function()
        error("a native Windows capture was sent through Git Bash")
    end)
    observed.installProcessObserver()
    local command = "__NUPP_WINDOWS_COMMAND__'/repo/bin/nupp' check missing.nupp"
    assert(os.execute(command) == 23)
    local pipe = assert(io.popen(command, "r"))
    assert(pipe:close())
    observed.restoreProcessObserver()
    os.execute, io.popen = savedExecute, savedPopen
    rawset(_G, "__NUPP_TEST_SHELL_EXECUTE", savedShellExecute)
    rawset(_G, "__NUPP_TEST_SHELL_POPEN", savedShellPopen)
    observed.finishCase()
    observed.finishSuite()

    assert(executed == command, "the runner's marker-aware execute wrapper did not receive the native command")
    assert(opened == command .. ":r", "the runner's marker-aware capture wrapper did not receive the native command")
    local fragment = observed.fragment(true)
    local uncertainty = owner(fragment, "tests/clitest.lua", "tests/clitest.lua/windows-native").uncertainty
    assert(not fragment.complete and #uncertainty == 1)
    assert(uncertainty[1].code == "child-uninstrumented")
end

function M.nativeCompilerChildrenAreAttributedExceptForSealedComptimeWorkers()
    local observed = newObservation()
    observed.beginSuite("tests/buildtest.lua")
    observed.beginCase("tests/buildtest.lua/generates")
    observed.markUnattributedProcess({"/repo/bin/nupp", "__comptime-worker", "/tmp/request"})
    observed.markUnattributedProcess({"/repo/bin/nupp", "__comptime-worker-service"})
    local environment, child = observed.nativeChildEnvironment({
        "/repo/bin/nupp",
        "__generator-worker",
        "/tmp/request",
        "/tmp/result"
    })
    assert(environment and child == environment.NUPP_TEST_IMPACT_CHILD)
    observed.finishChild(child, {
        format = observation.FORMAT,
        runId = "run-1",
        platform = "macos-arm64-luajit",
        projectRoot = "/repo",
        complete = true,
        owners = {
            {
                suite = "tests/buildtest.lua",
                caseId = "tests/buildtest.lua/generates",
                roots = {{module = "generated.input", provenance = {"compiler-build"},},},
                uncertainty = {},
            },
        },
        dependencies = {},
    })
    observed.finishCase()
    observed.finishSuite()

    local fragment = observed.fragment(true)
    local found = owner(fragment, "tests/buildtest.lua", "tests/buildtest.lua/generates")
    assert(root(found, "generated.input"))
    assert(fragment.complete, "sealed comptime workers add no unobserved project work")
end

function M.workerNamespacesKeepParallelChildFragmentsDistinct()
    local first = observation.new({
        runId = "run-1",
        platform = "test",
        projectRoot = "/repo",
        childNamespace = "worker-a",
    })
    local second = observation.new({
        runId = "run-1",
        platform = "test",
        projectRoot = "/repo",
        childNamespace = "worker-b",
    })
    first.beginSuite("tests/atest.lua")
    first.beginCase("runs")
    second.beginSuite("tests/btest.lua")
    second.beginCase("runs")
    local firstEnv = first.nativeChildEnvironment({"/repo/bin/nupp", "check", "src/a.nupp"})
    local secondEnv = second.nativeChildEnvironment({"/repo/bin/nupp", "check", "src/b.nupp"})
    assert(firstEnv.NUPP_TEST_IMPACT_CHILD == "worker-a-1")
    assert(secondEnv.NUPP_TEST_IMPACT_CHILD == "worker-b-1")
    assert(firstEnv.NUPP_TEST_IMPACT_CHILD ~= secondEnv.NUPP_TEST_IMPACT_CHILD)
end

function M.incompleteForeignOrMalformedChildFragmentsNeverPartiallyMerge()
    local variants = {
        function(fragment)
            fragment.complete = false
        end,
        function(fragment)
            fragment.owners = nil
        end,
        function(fragment)
            fragment.owners = {{suite = "tests/clitest.lua", roots = {}, uncertainty = {},},}
        end,
        function(fragment)
            fragment.dependencies = nil
        end,
        function(fragment)
            fragment.owners[1].suite = "tests/foreign.lua"
        end,
        function(fragment)
            fragment.dependencies[1] = {module = "broken"}
        end,
    }
    for index, alter in ipairs(variants) do
        local observed = newObservation()
        observed.beginSuite("tests/clitest.lua")
        observed.beginCase("tests/clitest.lua/validates-" .. tostring(index))
        local child = "invalid-" .. tostring(index)
        observed.childEnvironment(child)
        local fragment = {
            format = observation.FORMAT,
            runId = "run-1",
            platform = "macos-arm64-luajit",
            projectRoot = "/repo",
            complete = true,
            owners = {
                {
                    suite = "tests/clitest.lua",
                    caseId = "tests/clitest.lua/validates-" .. tostring(index),
                    roots = {{module = "must.not.merge", provenance = {"compiler-build"},},},
                    uncertainty = {},
                },
            },
            dependencies = {{module = "must.not.merge", dependencies = {},},},
        }
        alter(fragment)
        observed.finishChild(child, fragment)
        observed.finishCase()
        observed.finishSuite()
        local complete = observed.fragment(true)
        local found = owner(complete, "tests/clitest.lua", "tests/clitest.lua/validates-" .. tostring(index))
        assert(not complete.complete and found.uncertainty[1].code == "child-fragment-missing")
        assert(not pcall(root, found, "must.not.merge"), "an invalid child prefix was partially merged")
    end
end

function M.corruptChildFragmentsRemainUncertain()
    local observed = newObservation()
    observed.beginSuite("tests/clitest.lua")
    observed.beginCase("tests/clitest.lua/corrupt")
    observed.childEnvironment("corrupt")
    local directory = os.tmpname()
    os.remove(directory)
    assert(fs.mkdir(directory))
    local path = directory .. "/corrupt.buf"
    local file = assert(io.open(path, "wb"))
    file:write("not a fragment")
    file:close()
    local fragment, problem = observation.readFragment(path)
    assert(fragment == nil and problem == "child fragment is corrupt")
    observed.finishChild("corrupt", fragment, problem)
    observed.finishCase()
    observed.finishSuite()

    local complete = observed.fragment(true)
    local uncertainty = owner(complete, "tests/clitest.lua", "tests/clitest.lua/corrupt").uncertainty
    assert(not complete.complete and uncertainty[1].code == "child-fragment-missing")
    assert(uncertainty[1].detail == "child fragment is corrupt")
    assert(require("nupp.io.files").remove(directory, true))
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
        NUPP_TEST_IMPACT_COMPILER = projectRoot .. "/bin/nupp",
        NUPP_TEST_IMPACT_CWD = projectRoot,
    }
    local child = assert(
        observation.fromEnvironment(
            function(name)
                return environment[name]
            end,
            {"check", "missing-impact-file.nupp"}
        )
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
        complete = true,
        owners = {
            {suite = "tests/clitest.lua", caseId = "tests/clitest.lua/runs-child", roots = {}, uncertainty = {},},
        },
        dependencies = {},
    })
    observation.completedBuild(
        {modules = {built = {sourcePath = "src/built.nupp", dependencies = {}, runtimeModules = {},}},},
        "."
    )
    package.loaded["impact.cached.fixture"] = {cached = true}
    assert(require("impact.cached.fixture").cached)
    local savedRe = package.loaded.re
    package.loaded.re = {cached = true}
    assert(require("re").cached)
    package.loaded.re = savedRe
    assert(require("nupp.compiler.fs"))
    assert(observation.finishProcess(child, 7))
    package.loaded["impact.cached.fixture"] = nil

    local fragment = assert(observation.readFragment(directory .. "/child-7.buf"))
    local found = owner(fragment, "tests/clitest.lua", "tests/clitest.lua/runs-child")
    local edge = root(found, "impact.cached.fixture")
    assert(edge.provenance[1] == "cached-require")
    assert(root(found, "nupp.compiler.fs").path == "src/nupp/compiler/fs.nupp")
    assert(root(found, "re").path == "src/re.g.nupp")
    assert(root(found, "@input/24:missing-impact-file.nupp").path == "missing-impact-file.nupp")
    assert(root(found, "built").provenance[1] == "compiler-build")
    assert(fragment.exitStatus == 7 and fragment.complete)
    assert(#found.uncertainty == 0, "a complete expected-failure fragment remains usable")
    assert(observation.current() == nil)
    assert(require("nupp.io.files").remove(directory, true))
end

function M.nonzeroChildWithoutCompleteInputEvidenceRemainsUncertain()
    local directory = os.tmpname()
    local projectRoot = fs.absolute(".")
    os.remove(directory)
    assert(fs.mkdir(directory))
    local environment = {
        NUPP_TEST_IMPACT_RUN_ID = "failed-run",
        NUPP_TEST_IMPACT_FORMAT = tostring(observation.FORMAT),
        NUPP_TEST_IMPACT_PLATFORM = "test-platform",
        NUPP_TEST_IMPACT_FRAGMENT_DIR = directory,
        NUPP_TEST_IMPACT_CHILD = "failed-child",
        NUPP_TEST_IMPACT_SUITE = "tests/clitest.lua",
        NUPP_TEST_IMPACT_CASE = "tests/clitest.lua/fails-before-state",
        NUPP_TEST_IMPACT_PROJECT_ROOT = projectRoot,
        NUPP_TEST_IMPACT_COMPILER = projectRoot .. "/bin/nupp",
    }
    local child = assert(
        observation.fromEnvironment(
            function(name)
                return environment[name]
            end,
            {"build"}
        )
    )
    assert(observation.finishProcess(child, 2))

    local fragment = assert(observation.readFragment(directory .. "/failed-child.buf"))
    local found = owner(fragment, "tests/clitest.lua", "tests/clitest.lua/fails-before-state")
    assert(not fragment.complete)
    assert(found.uncertainty[1].code == "child-nonzero-unobserved")
    assert(require("nupp.io.files").remove(directory, true))
end

function M.relativeCommandInputsUseTheCompilerChildWorkingDirectory()
    local observed = newObservation()
    observed.beginSuite("tests/clitest.lua")
    observed.beginCase("tests/clitest.lua/outside-input")
    observed.recordCommandInputs({"check", "missing.nupp"}, "/private/tmp/outside-project")
    assert(not observed._failureEvidence, "an input outside the repository cannot prove a complete negative lookup")
    observed.finishCase()
    observed.finishSuite()

    local found = owner(observed.fragment(true), "tests/clitest.lua", "tests/clitest.lua/outside-input")
    assert(#found.roots == 0)

    for _, command in ipairs({"build", "run", "aot",}) do
        local child = newObservation()
        child.beginSuite("tests/clitest.lua")
        child.beginCase("tests/clitest.lua/missing-" .. command)
        child.recordCommandInputs({command, "missing-impact-input.nupp"}, fs.absolute("."))
        assert(not child._failureEvidence, command .. " cannot prove a complete failed build from its input alone")
        child.finishCase()
        child.finishSuite()
    end
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
