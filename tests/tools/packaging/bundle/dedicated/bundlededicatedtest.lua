local fixture = require("helpers.bundlefixture")
local NUPP = fixture.NUPP
local tempProject = fixture.tempProject
local run = fixture.run
local stampRustHost = fixture.stampRustHost

local M = {}

function M.aStampedDedicatedWorkerExchangesChannelsBeforeReturning()
    local dir = tempProject({
        [
            "nupp.lua"
        ] = [[
return {include = {"src"}, build = {default = "app", targets = {app = {
    kind = "binary", stub = "nupp", entries = {"nupp.internal.serviceapp"}, outDir = "build",
    payloadOutput = "build/app.payload.lua",
}}}}
]],
        [
            "src/nupp/internal/servicejobs.nupp"
        ] = [[
module nupp.internal.servicejobs
local {type Sender, type Receiver} = require("nupp.workers.internal.channeltypes")
const heap = table.Array

export function bounceArray(
    takes values: affine(table.Array<int32>, heap.destroy)
): affine(table.Array<int32>, heap.destroy)
    return values
end

export function echo(value: integer): integer
    return value
end

export function service(takes incoming: Receiver<integer>, takes outgoing: Sender<integer>): integer
    local commands = incoming
    local events = outgoing
    local count: integer = 0
    while true do
        local kind, value = commands:receive()
        if kind == "closed" then return count end
        count += 1
        events:send(value * value)
    end
end

export function produce(takes outgoing: Sender<integer>): nil
    local events = outgoing
    local value: integer = 0
    while true do
        value += 1
        events:send(value)
    end
end

export function returnEndpoint(takes commands: Receiver<integer>): affine(Receiver<integer>)
    return commands
end
]],
        [
            "src/nupp/internal/serviceapp.nupp"
        ] = [[
module nupp.internal.serviceapp
local jobs = require("nupp.internal.servicejobs")
local channels = require("nupp.runtime.provider.channels") as any
local provider = require("nupp.runtime.workersprovider").provider as any
local native = require("nupp.workers.native") as any
local time = require("coroutine")
local ffi = require("ffi")
ffi.cdef("int usleep(unsigned int usec);")

-- The public API preserves both endpoint owners and the child's scope loan.
for _ = 1, 3 do
    local scope = coroutine.scope()
    local commands, requests = scope:channel<integer>(2, 64)
    local replies, events = scope:channel<integer>(1, 64)
    local child = scope:worker(requests, replies, jobs.service)
    for index = 1, 100 do
        commands:send(index)
        local kind, value = events:receive()
        assert(kind == "value" and value == index * index)
    end
    commands:close()
    events:close()
    assert(child:await() == 100)
    -- Let the thread end without polling: scope cleanup must still drive its join.
    ffi.C.usleep(2000)
end

do
    local scope = coroutine.scope()
    local sender, receiver = scope:channel<integer>(1, 64)
    local child = scope:spawn(function(): nil takes(sender)
        local output = sender
        output:send(17)
    end)
    local kind, value = receiver:receive()
    assert(kind == "value" and value == 17)
    child:await()
end

do
    local scope = coroutine.scope()
    local sender, receiver = scope:channel<affine(table.Array<uint8>, table.Array.destroy)>(1, 64)
    local first = table.Array.alloc(ffi.typeof<uint8>(), 4)
    sender:send(first)
    local second = table.Array.alloc(ffi.typeof<uint8>(), 4)
    local status, returned = sender:trysend(second)
    assert(status == "full")
    if status ~= "sent" then
        assert(returned.count == 4)
        own.drop(returned)
    end
    local kind, arrived = receiver:receive()
    if kind == "value" then
        assert(arrived.count == 4)
        own.drop(arrived)
    else
        error("the accepted array was lost")
    end
end

for _ = 1, 3 do
    local services = provider.openscope(nil, nil)
    local commands, requests = channels.create(services, 2, 64)
    local replies, events = channels.create(services, 1, 64)
    local child = services:worker(jobs.service, requests, replies)
    assert(not pcall(requests.tryreceive, requests))
    assert(not pcall(replies.trysend, replies, 1))
    for index = 1, 100 do
        commands:send(index)
        local kind, value = events:receive()
        assert(kind == "value" and value == index * index)
    end
    commands:close()
    events:close()
    assert(child:await() == 100)
    services:close()
    assert(services._scheduler.dedicated == 0)
    assert(#services._scheduler.lanes == 0)
end

-- A blocked event publisher cannot prevent cancellation or its control reply.
do
    local services = provider.openscope(nil, nil)
    local output, events = channels.create(services, 1, 64)
    local child = services:worker(jobs.produce, output)
    local deadline = os.monotonic() + 1000
    while native.endpointReady(events._state.handle, 0) ~= 0 do
        assert(os.monotonic() < deadline)
        time.sleep(1)
    end
    assert(child:cancel())
    assert(not pcall(child.await, child))
    local kind, value = events:receive()
    assert(kind == "value" and value == 1)
    assert(events:receive() == "closed")
    events:close()
    services:close()
    assert(services._scheduler.dedicated == 0)
end

-- The public guard also owns arguments when admission fails before handoff.
do
    local scope = coroutine.scope()
    local raw: any = @unsafe own.release(scope)
    local commands, requests = raw:channel(1, 64)
    raw:close()
    assert(not requests._state.closed)
    assert(not pcall(raw.worker, raw, jobs.returnEndpoint, requests))
    assert(requests._state.closed)
    commands:close()
    local values = table.Array.alloc(ffi.typeof<uint8>(), 4)
    local moved: any = @unsafe own.release(values)
    assert(not pcall(raw.work, raw, jobs.service, moved))
    assert(moved.closed)
end

-- Runtime checks back up the static scope and transfer restrictions.
do
    local services = provider.openscope(nil, nil)
    local sending, receiving = channels.create(services, 1, 64)
    sending:send("unread")
    services:close()
    assert(not pcall(receiving.tryreceive, receiving))
    assert(not pcall(sending.trysend, sending, 1))
    sending:close()
    receiving:close()
end

do
    local services = provider.openscope(nil, nil)
    local other = provider.openscope(nil, nil)
    local commands, requests = channels.create(other, 1, 64)
    local accepted, problem = pcall(services.worker, services, jobs.returnEndpoint, requests)
    assert(not accepted and tostring(problem):find("another scope", 1, true) ~= nil)
    assert(commands:trysend(1) == "closed")
    commands:close()
    other:close()
    services:close()
end

do
    local services = provider.openscope(nil, nil)
    local commands, requests = channels.create(services, 1, 64)
    local child = services:worker(jobs.returnEndpoint, requests)
    local accepted, problem = pcall(child.await, child)
    assert(not accepted and tostring(problem):find("channel endpoint", 1, true) ~= nil)
    assert(commands:trysend(1) == "closed")
    commands:close()
    services:close()
end
-- Empty and populated arrays preserve their layout and ownership in both directions.
for _, count in ipairs({0, 1, 31}) do
    local scope = coroutine.scope()
    local values = table.Array.alloc(ffi.typeof<int32>(), count)
    if count > 0 then
        local view = values:write()
        view[count] = count * 17
        own.drop(view)
    end
    values = scope:work(values, jobs.bounceArray):await()
    assert(values.count == count)
    if count > 0 then
        local view = values:read()
        assert(view[count] == count * 17)
    end
    own.drop(values)
end

-- Refuse the native handoff after it takes the array, then reuse the same lane.
do
    local closed = native.channelCreate()
    native.channelClose(closed)
    local push = native.channelPushBufferTask
    native.channelPushBufferTask = function(handle: any, id: integer, moduleName: string,
        member: string, count: number, bytes: string, attachments: any): boolean
        return push(closed, id, moduleName, member, count, bytes, attachments)
    end
    local services = provider.openscope(nil, nil)
    local values = table.Array.alloc(ffi.typeof<int32>(), 4)
    local raw: any = @unsafe own.release(values)
    local accepted = pcall(services.spawn, services, jobs.bounceArray, raw)
    native.channelPushBufferTask = push
    assert(not accepted and raw.closed)
    assert(services:spawn(jobs.echo, 17):await() == 17)
    services:close()
    native.channelDestroy(closed)
end

print("services-ok")
]],
    })
    local built, builtOk = run(dir, "'" .. NUPP .. "' build")
    assert(builtOk, "the service binary builds: " .. built)
    local output, ranOk = run(dir, stampRustHost(dir, dir .. "/build/app.payload.lua"))
    assert(ranOk and output == "services-ok\n", "dedicated channels move, communicate and settle: " .. output)
    os.execute("rm -rf '" .. dir .. "'")
end

return M
