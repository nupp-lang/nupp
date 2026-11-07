local fixture = require("helpers.bundlefixture")
local NUPP = fixture.NUPP
local tempProject = fixture.tempProject
local readFile = fixture.readFile
local run = fixture.run
local stampRustHost = fixture.stampRustHost

local M = {}

function M.aStampedBinaryRunsStructuredTasksOnTheSharedScheduler()
    local dir = tempProject({
        ["shared-bytes.bin"] = "engine\0bytes\255",
        [
            "nupp.lua"
        ] = [[
return {include = {"src"}, build = {default = "app", targets = {app = {
   kind = "binary", stub = "nupp", entries = {"nupp.internal.workerapp"}, outDir = "build",
   payloadOutput = "build/app.payload.lua",
}}}}
]],
        ["nupp/spi.json"] = [[{"counter.spi.Counter":["counter.provider"]}]],
        [
            "src/counter/spi.nupp"
        ] = [[module counter.spi
export interface Counter
    @readonly next: function(): integer
end]],
        [
            "src/counter/provider.nupp"
        ] = [[module counter.provider
local count: integer = 0
export function next(): integer
    count = count + 1
    return count
end]],
        [
            "src/counter/init.nupp"
        ] = [[module counter
local spi = package
local {type Counter} = require("counter.spi")
local implementation = assert(spi.providers(Counter)())
export const next = implementation.next]],
        [
            "src/jobs.nupp"
        ] = [[
module jobs
local counter = require("counter")
export function nextCounter(): integer
    return counter.next()
end

export function square(value: integer): integer
    return value * value
end

export function pair(value: integer): (integer, string)
    return value * 2, "done"
end

local function failInsideWorker(): nil
    error("deliberate worker failure", 0)
end

export function fail(): nil
    failInsideWorker()
end

export record Box
    value: integer

    record Label
        text: string

        function size(self): integer
            return #self.text
        end
    end

    function doubled(self): integer
        return self.value * 2
    end
end

export function doubleBox(box: Box): integer
    return box:doubled()
end

export function bumpBox(box: Box): Box
    box.value = box.value + 1
    return box
end

export function labelSize(label: Box.Label): integer
    return label:size()
end

export function gradual(value: any): integer
    return 1
end

export function echo(value: string): string
    return value
end

export record Payload
    id: integer
    label: string
    ready: boolean
end

export function echoPayload(value: Payload): Payload
    return value
end

export function echoDynamic(value: any): any
    return value
end

export function attachmentMarkers(value: any): string
    return value.region:tostring()
        .. ":" .. tostring(value.markers.region.__nuppRegion)
        .. ":" .. tostring(value.markers.moved.__nuppMoved)
        .. ":" .. tostring(value.markers.escaped.__nuppAttachmentTable.nested)
end

export record Sparse
    id: integer
    ready: boolean
    note: string?
end

export function echoSparse(value: Sparse): Sparse
    return value
end

const sharedbytes = bytes.SharedBytes

export function firstByte(region: bytes.SharedBytes): integer
    return region:view(0, 1)[1]
end

const heap = table.Array

export function stamp(takes frame: affine(table.Array<uint8>, table.Array.destroy), value: integer): affine(table.Array<uint8>, heap.destroy)
    local writable = frame:write()
    writable[1] = value % 256
    own.drop(writable)

    return frame
end

export function total(takes values: affine(table.Array<int32>, table.Array.destroy)): integer
    local sum: integer = 0
    do
        local readable = values:read()
        for index = 1, #readable do
            sum = sum + readable[index]
        end
    end
    own.drop(values)

    return sum
end

const tasks = require("coroutine")

export function untilCancelled(): nil
    while true do tasks.checkpoint() end
end

export function nested(shards: integer): integer
    local squared: integer = 0
    do local scope = tasks.scope() ;
        squared = scope:work(|| -> shards * shards):await()
    end

    return squared
end
]],
        [
            "src/nupp/internal/workerapp.nupp"
        ] = [[
module nupp.internal.workerapp

const capture = require("capture")
const jobs = require("jobs")
const tasks = require("coroutine")
const sharedbytes = bytes.SharedBytes

-- Exercise the private bootstrap and its resource counts directly.
const provider = require("nupp.runtime.workersprovider").provider as any
for _ = 1, 3 do
    local services = provider.openscope(nil, nil)
    assert(not services._scheduler.pooled)
    local task = services:worker(jobs.pair, 9)
    local value, label = task:await()
    assert(value == 18 and label == "done")
    services:close()
    assert(services._scheduler.dedicated == 0)
    assert(#services._scheduler.lanes == 0)
end

do
    local services = provider.openscope(nil, nil)
    local occupied: {any} = {}
    local lanes = math.max(1, math.min(os.info().parallelism, 64)) as integer
    for _ = 1, lanes do
        occupied[#occupied + 1] = services:spawn(jobs.untilCancelled)
    end
    local ok, problem = pcall(function(): nil
        assert(services:worker(jobs.square, 7):await() == 49)
        assert(#services._scheduler.lanes == lanes)
    end)
    for _, task in ipairs(occupied) do task:cancel() end
    services:close()
    assert(ok, tostring(problem))
    assert(services._scheduler.dedicated == 0)
end

do
    local services = provider.openscope(nil, nil)
    local failed = services:worker(jobs.fail)
    local ok, problem = pcall(failed.await, failed)
    assert(not ok and tostring(problem):find("deliberate worker failure", 1, true) ~= nil)
    services:close()
    assert(services._scheduler.dedicated == 0)
end

local counter = require("counter")
for index = 1, 100 do assert(counter.next() == index) end
do local scope = tasks.scope() ;
    local independent = scope:work(jobs.nextCounter)
    assert(independent:await() == 1, "the worker has the same SPI index and fresh provider state")
    assert(counter.next() == 101, "worker initialization does not mutate the caller's provider")
    const left = scope:work(6, jobs.square)
    const right = scope:work(7, jobs.square)
    const paired = scope:work(5, jobs.pair)
    const box = jobs.Box(value = 8)
    local dynamicBox = box as any
    dynamicBox.extra = "kept"
    const boxed = scope:work(box, jobs.doubleBox)
    const returnedBox = scope:work(box, jobs.bumpBox)
    const gradualBox = scope:work(box, jobs.gradual)
    const nested = scope:work(jobs.Box.Label(text = "worker"), jobs.labelSize)
    const text = scope:work("native string", jobs.echo)
    const payload = scope:work(jobs.Payload(id = 9, label = "schema", ready = true), jobs.echoPayload)
    local malformed = jobs.Payload(id = 10, label = "fallback", ready = false)
    local dynamicMalformed = malformed as any
    dynamicMalformed.id = "dynamic"
    const fallbackPayload = scope:work(malformed, jobs.echoPayload)
    const anyPayload = scope:work(jobs.Payload(id = 11, label = "any", ready = false), jobs.echoDynamic)
    local spare = jobs.Payload(id = 12, label = "extra", ready = true)
    local dynamicSpare = spare as any
    dynamicSpare.extra = "spare"
    const extraPayload = scope:work(spare, jobs.echoPayload)
    const region = sharedbytes.copy("region payload")
    const regionByte = scope:work(region:slice(7, 7), jobs.firstByte)
    const markerResult = scope:work({
        region = region:slice(0, 6),
        markers = {
            region = {__nuppRegion = 17},
            moved = {__nuppMoved = 99},
            escaped = {__nuppAttachmentTable = {nested = true}},
        },
    }, jobs.attachmentMarkers)
    const sparse = scope:work(jobs.Sparse(id = 13, ready = true), jobs.echoSparse)
    const noted = scope:work(jobs.Sparse(id = 14, ready = false, note = "held"), jobs.echoSparse)
    local doubled, label = paired:await()
    const leftValue = left:await()
    const restored = returnedBox:await()
    const restoredPayload = payload:await()
    const restoredFallback = fallbackPayload:await()
    const restoredAny = anyPayload:await()
    const restoredExtra = extraPayload:await()
    const restoredSparse = sparse:await()
    const restoredNoted = noted:await()
    print(
        leftValue,
        left:await(),
        right:await(),
        doubled,
        label,
        boxed:await(),
        restored:doubled(),
        restored is jobs.Box,
        (restored as any).extra,
        gradualBox:await(),
        nested:await(),
        text:await(),
        restoredPayload.id,
        restoredPayload.label,
        restoredPayload.ready,
        restoredPayload is jobs.Payload,
        (restoredFallback as any).id,
        restoredFallback is jobs.Payload,
        (restoredAny as any).id,
        restoredAny is jobs.Payload,
        (restoredExtra as any).extra,
        restoredExtra is jobs.Payload,
        restoredSparse.id,
        restoredSparse.note == nil,
        restoredSparse is jobs.Sparse,
        restoredNoted.note,
        regionByte:await(),
        markerResult:await(),
        region:slice(0, 6):tostring()
    )
end
print(capture.run(40))

local nestedOk, nestedProblem = pcall(function(): nil
    do local scope = tasks.scope() ;
        scope:work(4, jobs.nested):await()
    end
end)
print(not nestedOk, tostring(nestedProblem):find("another worker scope", 1, true) ~= nil)


local ok, problem = pcall(function(): nil
    do local scope = tasks.scope() ;
        scope:work(jobs.fail)
    end
end)
print(ok, tostring(problem):find("deliberate worker failure", 1, true) ~= nil)
assert(tostring(problem):find("stack traceback:", 1, true) ~= nil, tostring(problem))
assert(tostring(problem):find("nupp-worker", 1, true) ~= nil, tostring(problem))
if io.cli.args[1] == "check-stack" then
    assert(tostring(problem):find("failInsideWorker", 1, true) ~= nil, tostring(problem))
end

local copied, copyProblem = pcall(function(): nil
    do local scope = tasks.scope() ;
        scope:work(setmetatable({value = 1}, {}), jobs.gradual)
    end
end)
print(copied, tostring(copyProblem):find("has a metatable", 1, true) ~= nil)

const ffi = require("ffi")
const heap = table.Array

local frame = heap.alloc(ffi.typeof<uint8>(), 64)
do local scope = tasks.scope() ;
    frame = scope:work(frame, 200, jobs.stamp):await()
end
do
    local readable = frame:read()
    print(frame.count, readable[1])
end
own.drop(frame)

local counts = heap.alloc(ffi.typeof<int32>(), 5)
do
    local writable = counts:write()
    for index = 1, 5 do
        writable[index] = index * 3
    end
    own.drop(writable)
end
do local scope = tasks.scope() ;
    print(scope:work(counts, jobs.total):await())
end

local dynamicShared = sharedbytes as any
assert(dynamicShared.Builder == nil and dynamicShared.newBuilder == nil and dynamicShared.readFile == nil)
assert(dynamicShared.__regionParts == nil and dynamicShared.__regionFromParts == nil)
local loaded, readProblem = sharedbytes.readfile("shared-bytes.bin")
if loaded == nil then error(readProblem or "shared byte file failed") end
assert(loaded:len() == 13 and loaded:tostring() == "engine\0bytes\255")
local absent, missingReason = sharedbytes.readfile("missing-shared-bytes.bin")
assert(absent == nil and type(missingReason) == "string")

local builder = bytes.Buffer.create()
local lease = builder:reserve(3)
do local writer = lease:span() ;
    writer[1] = 104
    writer[2] = 105
    writer[3] = 33
end
lease:commit(2)
builder:put("!")
print(builder:freeze():tostring())

local type Accounted = {accounted: @nosuspend function(): integer}
local rawShared = require("nupp.mem.sharedbytes.native") as Accounted
collectgarbage("collect")
collectgarbage("collect")
local before = rawShared.accounted()
local grown: bytes.SharedBytes? = sharedbytes.copy(("y"):rep(65536))
print(rawShared.accounted() - before == 65536, grown ~= nil)
grown = nil
collectgarbage("collect")
collectgarbage("collect")
print(rawShared.accounted() == before)
]],
        [
            "src/capture.nupp"
        ] = [[
module capture

const jobs = require("jobs")
const tasks = require("coroutine")

export function run(base: integer): integer
    const box = jobs.Box(value = 21)
    do local scope = tasks.scope() ;
        const scalar = scope:work(2, |value: integer| -> base + value)
        const record = scope:work(|| -> box:doubled())
        return scalar:await() + record:await()
    end
end
]],
    })
    local built, builtOk = run(dir, "'" .. NUPP .. "' build")
    assert(builtOk, "the native worker binary builds: " .. built)
    local portablePayload = assert(readFile(dir .. "/build/app.payload.lua"))
    assert(portablePayload:sub(1, 3) ~= "\27LJ", "payloadOutput retains Lua source rather than current-host bytecode")
    assert(loadfile(dir .. "/build/app.payload.lua"), "the separately retained payload is a loadable Lua chunk")
    local executable = package.config:sub(1, 1) == "\\" and "build/app.exe" or "./build/app"
    local output, ranOk = run(dir, executable)
    assert(ranOk, "the native worker binary runs: " .. output)
    local expected = "36\t36\t49\t10\tdone\t16\t18\ttrue\tkept\t1\t6\tnative string\t9\tschema\ttrue\ttrue\tdynamic\ttrue\t11\ttrue\tspare\ttrue\t13\ttrue\ttrue\theld\t112\tregion:17:99:true\tregion\n84\ntrue\ttrue\nfalse\ttrue\nfalse\ttrue\n64\t200\n45\nhi!\ntrue\ttrue\ntrue\n"
    assert(output == expected, "results, records, captures, and failures cross structured cleanup: " .. output)
    local rustExecutable = stampRustHost(dir, dir .. "/build/app.payload.lua")
    local rustOutput, rustRanOk = run(dir, rustExecutable .. " check-stack")
    assert(rustRanOk, "the Rust worker host runs the Nupp payload: " .. rustOutput)
    assert(rustOutput == expected, "the Rust host preserves structured worker and shared-byte results: " .. rustOutput)
    os.execute("rm -rf '" .. dir .. "'")
end

return M
