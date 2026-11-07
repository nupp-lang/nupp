local fixture = require("helpers.bundlefixture")
local NUPP = fixture.NUPP
local tempProject = fixture.tempProject
local run = fixture.run
local stampRustHost = fixture.stampRustHost

local test = require("helpers.bundlefixture").test
local EXECUTABLE = require("helpers.bundlefixture").EXECUTABLE
local BUILT = require("helpers.bundlefixture").BUILT

local M = {}

-- The task-scopes guide's fork inside a spawned child, with more items than
-- slots, run for real. Every slot held by a child waiting on the worker task it
-- forked used to deadlock the scope ("a task cannot complete: no readiness
-- source"), because the fork waited for a slot only a sibling could free and
-- every sibling was doing the same. A child now lends its slot to the task it
-- starts. `taskstest` holds the same for coroutine children; this is the fork.
function M.aSpawnedChildForkingOnAFullScopeDoesNotDeadlock()
    local dir = tempProject({
        [
            "nupp.lua"
        ] = [[
return {include = {"src"}, build = {default = "app", targets = {app = {
   kind = "binary", stub = "nupp", entries = {"main"}, outDir = "build",
}}}}
]],
        [
            "src/jobs.nupp"
        ] = [[
module jobs

export function compress(name: string, path: string): integer
    return #name + #path
end
]],
        [
            "src/main.nupp"
        ] = [[
const jobs = require("jobs")
const tasks = require("coroutine")

local paths: {[string]: string} = {}
local expected: integer = 0
for index = 1, 9 do
    paths["item" .. index] = "path/" .. index
    expected = expected + #("item" .. index) + #("path/" .. index)
end
local total: integer = 0
do local scope = tasks.scope(2) ;
    for name, path in pairs(paths) do
        scope:spawn(function(): nil
            const size = scope:work(name, path, jobs.compress):await()
            total = total + size
        end)
    end
end
print(total == expected, total)
]],
    })
    local built, builtOk = run(dir, "'" .. NUPP .. "' build")
    assert(builtOk, "the forking binary builds: " .. built)
    local output, ranOk = run(dir, EXECUTABLE)
    assert(ranOk and output:match("^true\t%d+\n$"), "children forking on a full scope all answered: " .. output)
    os.execute("rm -rf '" .. dir .. "'")
end

return M
