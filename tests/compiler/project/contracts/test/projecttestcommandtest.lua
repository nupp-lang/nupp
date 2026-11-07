local fixture = require("helpers.projectfixture")
local testAssert = fixture.testAssert
local project = fixture.project
local process = fixture.process
local read = fixture.read
local exists = fixture.exists
local tempProject = fixture.tempProject
local remove = fixture.remove

local M = {}

function M.testCommandBuildsThenRunsArgv()
    local dir = tempProject({
        [
            "nupp.lua"
        ] = [[
return {
   include = {"src"},
   build = {outDir = "out", entries = {"main"}},
   test = {argv = {"luajit", "test.lua"}},
}
]],
        ["src/main.nupp"] = "return true\n",
        [
            "test.lua"
        ] = [[
assert(os.getenv("NUPP_TEST_BUILD") == "out", tostring(os.getenv("NUPP_TEST_BUILD")))
local f = assert(io.open("test-ran", "wb"))
f:write("yes")
f:close()
]],
    })
    testAssert.eq(project.test(dir), 0)
    testAssert.eq(read(dir .. "/test-ran"), "yes")
    assert(exists(dir .. "/out/main.lua"), "test builds first")
    remove(dir)
end

function M.testOutputOverrideRunsTheArtifactItBuilt()
    local dir = tempProject({
        [
            "nupp.lua"
        ] = [[
return {
   include = {"src"},
   build = {
      kind = "bundle",
      outDir = "build",
      output = "build/test.lua",
      entries = {"main"},
   },
   test = {argv = {"luajit", "build/test.lua"}},
}
]],
        [
            "src/main.lua"
        ] = [[
assert(os.getenv("NUPP_TEST_BUILD") == "coverage", tostring(os.getenv("NUPP_TEST_BUILD")))
local hostio = rawget(_G, "io")
local file = assert(hostio.open("test-ran", "wb"))
file:write("yes")
file:close()
]],
    })
    testAssert.eq(project.test(dir, {}, {outDir = "coverage"}), 0)
    testAssert.eq(read(dir .. "/test-ran"), "yes")
    assert(exists(dir .. "/coverage/test.lua"), "the override receives the test artifact")
    assert(not exists(dir .. "/build/test.lua"), "the manifest output is not overwritten")
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
    assert(exists(dir .. "/out/main.lua"), "the default test command builds first")
    remove(dir)
end

return M
