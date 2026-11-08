local fixture = require("helpers.projectfixture")
local testAssert = fixture.testAssert
local project = fixture.project
local process = fixture.process
local read = fixture.read
local exists = fixture.exists
local tempProject = fixture.tempProject
local remove = fixture.remove

local hostSystem = require("helpers.projectfixture").hostSystem
local compiledRuntimeSources = require("helpers.projectfixture").compiledRuntimeSources

local M = {}

function M.testCommandBuildsThenRunsArgv()
    local dir = tempProject({
        [
            "nupp.lua"
        ] = [[
return {
   include = {"src"},
   build = {outDir = "out", entries = {"main"}},
   test = {argv = {"sh", "test.sh"}},
}
]],
        ["src/main.nupp"] = "return true\n",
        ["test.sh"] = "test \"$NUPP_TEST_BUILD\" = out || exit 1\nprintf yes > test-ran\n",
    })
    testAssert.eq(project.test(dir), 0)
    testAssert.eq(read(dir .. "/test-ran"), "yes")
    assert(exists(dir .. "/out/.nupp-state.json"), "test builds first")
    remove(dir)
end

function M.testCommandDefaultsToBundledRunner()
    local dir = tempProject({
        [
            "nupp.lua"
        ] = [[
return {
   include = {"src"},
   build = {
      default = "app",
      targets = {app = {outDir = "out", entries = {"main"}}},
   },
   test = {build = "app"},
}
]],
        ["src/main.nupp"] = "return true\n",
    })
    local originalRun = process.run
    local ran
    process.run = function(argv, options)
        ran = {argv = argv, options = options}
        return 0
    end
    local ok, result = pcall(project.test, dir)
    process.run = originalRun
    assert(ok, result)
    testAssert.eq(result, 0)
    testAssert.eq(ran.argv[2], "test", "the default runner stays under the test command")
    testAssert.eq(ran.argv[3], "--internal-runner", "the default test command is Nupp's bundled runner")
    testAssert.eq(ran.options.cwd, dir, "the default runner starts in the project")
    assert(exists(dir .. "/out/.nupp-state.json"), "the default test command builds first")
    remove(dir)
end

function M.completedTestBuildReusesTheArtifactAndChecksItsBytes()
    local dir = tempProject({
        [
            "nupp.lua"
        ] = [[return {include={"src"}, build={kind="binary", stub="nupp", outDir="out",
            output="out/tests", entries={"main"}, resources={{source="fixture",output="fixture"}}}}]],
        ["src/main.lua"] = "return 17\n",
        ["fixture"] = "first",
    })
    local modules = require("nupp.tools.build.modules")
    local original = modules.session

    local function build()
        local produced = {}
        testAssert.eq(project.build(dir, {testBuild = true, produced = produced}), 0)
        return produced
    end

    local ok, why = pcall(function()
        assert(not build().testBuildReused)
        local first = read(dir .. "/out/tests")
        modules.session = function()
            error("an unchanged test build entered the checker")
        end
        assert(build().testBuildReused)
        modules.session = original
        testAssert.eq(read(dir .. "/out/tests"), first)
        fixture.write(dir .. "/out/tests", "broken")
        assert(not build().testBuildReused)
        testAssert.eq(read(dir .. "/out/tests"), first)
        assert(build().testBuildReused)
        fixture.write(dir .. "/src/main.lua", "return 18\n")
        assert(not build().testBuildReused)
        assert(read(dir .. "/out/tests") ~= first)
        assert(build().testBuildReused)
        fixture.write(dir .. "/fixture", "second")
        assert(not build().testBuildReused)
        assert(build().testBuildReused)
        fixture.write(dir .. "/src/added.lua", "return true\n")
        assert(not build().testBuildReused)
        assert(build().testBuildReused)
        os.remove(dir .. "/src/added.lua")
        assert(not build().testBuildReused)
        assert(build().testBuildReused)
        os.remove(dir .. "/out/.nupp-vm-program.payload")
        assert(not build().testBuildReused)
        local statePath = dir .. "/out/.nupp-state.json"
        local state = fixture.json.decode(read(statePath))
        state.testBuild.effects = {invalid = {}}
        fixture.write(statePath, fixture.json.encode(state))
        assert(not build().testBuildReused)
    end)
    modules.session = original
    remove(dir)
    assert(ok, why)
end

function M.completedTestBuildRefreshesNativeInputsAndRejectsChangesDuringBuild()
    local dir = tempProject({
        [
            "nupp.lua"
        ] = [[return {include={"src"}, build={kind="binary", stub="nupp", outDir="out",
            output="out/tests", entries={"main"}}}]],
        ["src/main.lua"] = "return 17\n",
    })
    local stage = require("nupp.tools.build.testbuild")
    local original, version, calls, during = stage.refresh, "first", 0, false
    stage.refresh = function(...)
        calls = calls + 1
        local available = select(2, ...)
        assert(
            type(available) == "table" and available[dir .. "/out/.nupp-vm-program.payload"] == true,
            "native refresh receives the compiled runtime closure on cold and reused builds"
        )
        local host, why = original(...)
        if not host then
            return nil, why
        end
        local path = dir .. "/out/lib/native-fixture-" .. version
        fixture.write(path, read(host))
        if during then
            fixture.write(dir .. "/src/main.lua", "return 19\n")
        end

        return path
    end

    local function build(coverage)
        local produced = {}
        testAssert.eq(project.build(dir, {testBuild = true, coverage = coverage, produced = produced}), 0)
        return produced
    end

    local ok, why = pcall(function()
        assert(not build().testBuildReused)
        local before = calls
        assert(build().testBuildReused)
        testAssert.eq(calls, before + 1, "a hit still refreshes the native toolchain")
        version = "second"
        assert(not build().testBuildReused)
        assert(build().testBuildReused)
        assert(not build(true).testBuildReused, "coverage executes its own build")
        during = true
        assert(not build().testBuildReused)
        during = false
        assert(not build().testBuildReused, "a changed in-flight input cannot publish a cache entry")
        assert(build().testBuildReused)
    end)
    stage.refresh = original
    remove(dir)
    assert(ok, why)
end

function M.testBuildReuseSurvivesSeparateCliProcessesAndToolCallIds()
    local dir = tempProject({
        [
            "nupp.lua"
        ] = [[return {include={"src"}, build={kind="binary", stub="nupp", outDir="out",
            output="out/tests", entries={"main"}}, test={argv={"out/tests"}}}]],
        ["src/main.lua"] = "print('ok')\n",
    })
    local nupp = require("helpers.paths").root .. "/bin/nupp"

    local function run(id, setting)
        local code, output = process.capture({nupp, "test"}, {
            cwd = dir,
            env = {CODEX_TOOL_CALL_ID = id, NUPP_TEST_REUSE_INPUT = setting}
        })
        testAssert.eq(code, 0, output)
        testAssert.eq(output, "ok\n")

        return select(3, require("io.internal.files").stat(dir .. "/out/tests"))
    end

    local ok, why = pcall(function()
        local first = run("first-transport", "first-setting")
        testAssert.eq(
            run("second-transport", "first-setting"),
            first,
            "a separate CLI process reuses the finished artifact"
        )
        assert(run("third-transport", "changed-setting") ~= first, "actual build environment changes still rebuild")
    end)
    remove(dir)
    assert(ok, why)
end

return M
