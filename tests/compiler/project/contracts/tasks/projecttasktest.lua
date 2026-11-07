local fixture = require("helpers.projectfixture")
local testAssert = fixture.testAssert
local project = fixture.project
local read = fixture.read
local exists = fixture.exists
local tempProject = fixture.tempProject
local remove = fixture.remove

local hostSystem = require("helpers.projectfixture").hostSystem
local compiledRuntimeSources = require("helpers.projectfixture").compiledRuntimeSources

local M = {}

-- Unlike test, a task only builds when it names a target -- most won't, since
-- most of what a task runs (a dev server, a release script) isn't "the code
-- under test" the way a test command's subject always is.
function M.namedTaskRunsItsArgvWithoutBuildingByDefault()
    local dir = tempProject({
        ["nupp.lua"] = [[
return {
   include = {"src"},
   tasks = {
      greet = {argv = {"sh", "greet.sh"}},
   },
}
]],
        ["greet.sh"] = "printf hi > task-ran\n",
    })
    testAssert.eq(project.runTask(dir, "greet"), 0)
    testAssert.eq(read(dir .. "/task-ran"), "hi")
    assert(not exists(dir .. "/build"), "a task with no build key builds nothing")
    remove(dir)
end

function M.namedTaskRunsFromItsConfiguredWorkingDirectory()
    local dir = tempProject({
        [
            "nupp.lua"
        ] = [[
return {
   include = {"src"},
   build = {entries = {"main"}},
   tasks = {
      greet = {cwd = "tools", argv = {"sh", "greet.sh"}},
   },
}
]],
        ["src/main.nupp"] = "return true\n",
        ["tools/greet.sh"] = "printf hi > task-ran\n",
    })
    testAssert.eq(project.runTask(dir, "greet"), 0)
    testAssert.eq(read(dir .. "/tools/task-ran"), "hi")
    assert(not exists(dir .. "/task-ran"), "the task does not run from the outer project root")

    local described = assert(project.describeTasks(dir, "greet"))
    testAssert.eq(described.cwd, "tools", "task discovery reports the configured working directory")
    remove(dir)
end

function M.taskWorkingDirectoryMustBeANonEmptyString()
    local dir = tempProject({
        [
            "nupp.lua"
        ] = [[
return {
   build = {entries = {"main"}},
   tasks = {greet = {cwd = "", argv = {"echo", "hi"}}},
}
]],
    })
    local config, err = project.loadManifest(dir)
    testAssert.eq(config, nil, "an empty task working directory rejects the manifest")
    assert(err and err:find("tasks.greet.cwd must be a non-empty string", 1, true), tostring(err))
    remove(dir)
end

function M.namedTaskBuildsFirstWhenItNamesATarget()
    local dir = tempProject({
        [
            "nupp.lua"
        ] = [[
return {
   include = {"src"},
   build = {outDir = "out", default = "app",
      targets = {app = {entries = {"main"}}}},
   tasks = {
      greet = {build = "app", argv = {"sh", "greet.sh"}},
   },
}
]],
        ["src/main.nupp"] = "return true\n",
        ["greet.sh"] = "printf hi > task-ran\n",
    })
    testAssert.eq(project.runTask(dir, "greet"), 0)
    assert(exists(dir .. "/out/.nupp-state.json"), "a task naming a build target builds first")
    remove(dir)
end

function M.namedTaskAppendsTrailingArgsToItsArgv()
    local dir = tempProject({
        ["nupp.lua"] = [[
return {
   include = {"src"},
   tasks = {greet = {argv = {"sh", "greet.sh"}}},
}
]],
        ["greet.sh"] = [[
IFS=,
printf '%s' "$*" > task-args
]],
    })
    testAssert.eq(project.runTask(dir, "greet", {"a", "b"}), 0)
    testAssert.eq(read(dir .. "/task-args"), "a,b")
    remove(dir)
end

function M.unknownTaskNameFails()
    local dir = tempProject({["nupp.lua"] = [[
return {include = {"src"}, tasks = {greet = {argv = {"echo", "hi"}}}}
]],})
    local errorPath = os.tmpname()
    local originalStderr = io.stderr
    io.stderr = assert(io.open(errorPath, "wb"))
    local status = project.runTask(dir, "nonexistent")
    io.stderr:close()
    io.stderr = originalStderr
    os.remove(errorPath)
    testAssert.eq(status, 1, "an unconfigured task name fails rather than running nothing quietly")
    remove(dir)
end

return M
