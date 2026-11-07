local fixture = require("helpers.bundlefixture")
local NUPP = fixture.NUPP
local tempProject = fixture.tempProject
local run = fixture.run
local stampRustHost = fixture.stampRustHost

local test = require("helpers.bundlefixture").test
local EXECUTABLE = require("helpers.bundlefixture").EXECUTABLE
local BUILT = require("helpers.bundlefixture").BUILT

local M = {}

-- A worker scope lists only what it may still owe something to. Settled tasks leave
-- it however long the scope lives, a handle still answers after its task has left,
-- and a result holding a moved allocation nothing consumed stays listed so close can
-- free it.
function M.aLongLivedScopeListsOnlyTheWorkerTasksItStillOwes()
    local dir = tempProject({
        [
            "nupp.lua"
        ] = [[
return {include = {"src"}, build = {default = "app", targets = {app = {
   kind = "binary", stub = "nupp", entries = {"nupp.internal.scopeobserver"}, outDir = "build",
}}}}
]],
        [
            "src/jobs.nupp"
        ] = [[
module jobs

const heap = table.Array

export function square(value: integer): integer
    return value * value
end

export function stamp(takes frame: affine(table.Array<uint8>, table.Array.destroy), value: integer): affine(table.Array<uint8>, heap.destroy)
    local writable = frame:write()
    writable[1] = value % 256
    own.drop(writable)

    return frame
end
]],
        [
            "src/nupp/internal/scopeobserver.nupp"
        ] = [[
const heap = table.Array
const jobs = require("jobs")
const tasks = require("coroutine")

const lifecycle = rawget(require("nupp.tasks"), "__lifecycle") as function(borrows scope: tasks.Scope): {workers: integer}

local most: integer = 0
local repeated = false
do local scope = tasks.scope(4) ;
    const first = scope:work(3, jobs.square)
    for index = 1, 40 do
        scope:work(index, jobs.square)
        const counts = lifecycle(scope)
        if counts.workers > most then
            most = counts.workers
        end
    end
    repeated = first:await() == 9 and first:await() == 9
end
print(most <= 4, repeated)

local frame = heap.alloc(ffi.typeof<uint8>(), 64)
local owing: integer = -1
do local scope = tasks.scope(1) ;
    scope:work(frame, 7, jobs.stamp)
    for index = 1, 10 do
        scope:work(index, jobs.square)
    end
    scope:work(11, jobs.square):await()
    owing = lifecycle(scope).workers
end
print(owing)
]],
    })
    local built, builtOk = run(dir, "'" .. NUPP .. "' build")
    assert(builtOk, "the worker binary builds: " .. built)
    local output, ranOk = run(dir, EXECUTABLE)
    -- A moved native array has to be freed by whoever holds it last, so its
    -- unconsumed result stays listed for close. On the VM the array is managed
    -- storage the undelivered result drops, and nothing stays owed.
    local owed = "0"
    assert(
        ranOk and output == "true\ttrue\n" .. owed .. "\n",
        "settled worker tasks left the scope and the unconsumed moved result stayed: " .. output
    )
    os.execute("rm -rf '" .. dir .. "'")
end

return M
