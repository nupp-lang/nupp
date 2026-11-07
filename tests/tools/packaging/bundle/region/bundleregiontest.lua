local fixture = require("helpers.bundlefixture")
local NUPP = fixture.NUPP
local tempProject = fixture.tempProject
local run = fixture.run
local stampRustHost = fixture.stampRustHost

local M = {}

-- A region's extent is two private fields, and a forged one used to reach the
-- native push beside a moved array: the push refused the region, and freed the
-- array twice. The transfer walk refuses it first, with the array still owned.
function M.aRegionWhoseExtentWasForgedIsRefusedBeforeItCrosses()
    local dir = tempProject({
        [
            "nupp.lua"
        ] = [[
return {include = {"src"}, build = {default = "app", targets = {app = {
   kind = "binary", stub = "nupp", entries = {"main"}, outDir = "build",
   payloadOutput = "build/app.payload.lua",
}}}}
]],
        [
            "src/jobs.nupp"
        ] = [[
module jobs

const heap = table.Array
const sharedbytes = bytes.SharedBytes

export function inspect(takes frame: affine(table.Array<uint8>, table.Array.destroy), region: bytes.SharedBytes): integer
    local count = frame.count
    own.drop(frame)
    return count + region:len()
end
]],
        [
            "src/main.nupp"
        ] = [[
const jobs = require("jobs")
const heap = table.Array
const sharedbytes = bytes.SharedBytes
const tasks = require("coroutine")

local region = sharedbytes.copy("abc")
rawset(region as any, "_length", 99)
local ok, problem = pcall(function(): nil
    local frame = heap.alloc(ffi.typeof<uint8>(), 64)
    do local scope = tasks.scope() ;
        scope:work(frame, region, jobs.inspect)
    end
end)
print(ok, tostring(problem):find("extent lies outside its storage", 1, true) ~= nil)
rawset(region as any, "_length", 3)
local frame = heap.alloc(ffi.typeof<uint8>(), 64)
do local scope = tasks.scope() ;
    print(scope:work(frame, region, jobs.inspect):await())
end
]],
    })
    local built, builtOk = run(dir, "'" .. NUPP .. "' build")
    assert(builtOk, "the forged-region binary builds: " .. built)
    local expected = "false\ttrue\n67\n"
    local rustOutput, rustRanOk = run(dir, stampRustHost(dir, dir .. "/build/app.payload.lua"))
    assert(rustRanOk and rustOutput == expected, "a forged region extent is refused before it crosses: " .. rustOutput)
    os.execute("rm -rf '" .. dir .. "'")
end

return M
