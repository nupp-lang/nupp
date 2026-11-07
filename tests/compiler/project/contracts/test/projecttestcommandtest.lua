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

return M
