local fixture = require("helpers.bundlefixture")
local NUPP = fixture.NUPP
local tempProject = fixture.tempProject
local run = fixture.run
local stampRustHost = fixture.stampRustHost

local test = require("helpers.bundlefixture").test
local EXECUTABLE = require("helpers.bundlefixture").EXECUTABLE
local BUILT = require("helpers.bundlefixture").BUILT

local M = {}

function M.aStampedBinaryParksChannelWaitsWithoutBlockingSiblingTasks()
    local dir = tempProject({
        [
            "nupp.lua"
        ] = [[
return {include = {"src"}, build = {default = "app", targets = {app = {
    kind = "binary", stub = "nupp", entries = {"nupp.internal.channelapp"}, outDir = "build",
    payloadOutput = "build/app.payload.lua",
}}}}
]],
        [
            "src/nupp/internal/channelapp.nupp"
        ] = [[
module nupp.internal.channelapp
local channels = require("nupp.runtime.provider.channels") as any
local storage = require("nupp.runtime.provider.workers") as any
local tasks = require("coroutine")

-- Byte bounds can refuse before the message-count bound, and nil is data.
do
    local sender, receiver = channels.create({}, 2, 10)
    assert(sender:trysend("123") == "sent")
    local status, unsent = sender:trysend("456")
    assert(status == "full" and unsent == "456")
    local kind, value = receiver:tryreceive()
    assert(kind == "value" and value == "123")
    assert(sender:trysend(nil) == "sent")
    assert(sender:trysend(nil) == "sent")
    assert(sender:trysend(nil) == "full")
    local oversized = pcall(sender.trysend, sender, string.rep("x", 100))
    assert(not oversized)
    local forged = setmetatable({}, getmetatable(sender))
    assert(not pcall(sender.trysend, forged, 1))
    sender:close()
    kind, value = receiver:receive()
    assert(kind == "value" and value == nil)
    kind, value = receiver:receive()
    assert(kind == "value" and value == nil)
    assert(receiver:receive() == "closed")
    receiver:close()
end

-- A refused move returns a usable owner; acceptance transfers it exactly once.
do
    local sender, receiver = channels.create({}, 1, 128)
    assert(sender:trysend(nil) == "sent")
    local buffer = table.Array.alloc(ffi.typeof<uint8>(), 4)
    do local writing = buffer:write(); writing[1] = 23 end
    local raw: any = @unsafe own.release(buffer)
    local status, unsent = sender:trysend(raw)
    assert(status == "full" and raw.closed)
    assert(unsent:read():get(1) == 23)
    assert(receiver:receive() == "value")
    assert(sender:trysend(unsent) == "sent" and unsent.closed)
    local kind, arrived = receiver:receive()
    assert(kind == "value" and arrived:read():get(1) == 23)
    storage.channeldrop(arrived)
    local published = bytes.SharedBytes.copy("a\0b")
    assert(sender:trysend(published) == "sent")
    kind, arrived = receiver:receive()
    assert(kind == "value" and arrived:tostring() == "a\0b")
    assert(published:tostring() == "a\0b")
    local large = bytes.SharedBytes.copy(string.rep("x", 4096))
    assert(not pcall(sender.send, sender, large:slice(0, 1)))
    receiver:close()
    local refused = table.Array.alloc(ffi.typeof<uint8>(), 4)
    status, unsent = sender:trysend(@unsafe own.release(refused))
    assert(status == "closed" and unsent.count == 4)
    storage.channeldrop(unsent)
    sender:close()
end

local observed = 0
do local scope = tasks.scope(2, 1000) ;
    local sender, receiver = channels.create({}, 1, 64)
    scope:spawn(function(): nil
        for index = 1, 100 do sender:send(index) end
        sender:close()
    end)
    scope:spawn(function(): nil
        while true do
            local kind, value = receiver:receive()
            if kind == "closed" then break end
            observed += 1
            assert(value == observed)
        end
        receiver:close()
    end)
end
assert(observed == 100)

-- Cancellation removes a parked subscription without accepting its pending send.
for _, sending in ipairs({false, true}) do
    local sender, receiver = channels.create({}, 1, 64)
    if sending then sender:send(1) end
    local entered = false
    local began, started = channels.create({}, 1, 64)
    do local scope = tasks.scope(1, 1000) ;
        local child = scope:spawn(function(): nil
            entered = true
            began:send(true)
            if sending then sender:send(2) else receiver:receive() end
        end)
        assert(started:receive() == "value")
        assert(entered)
        child:cancel()
    end
    began:close()
    started:close()
    if sending then
        local kind, value = receiver:tryreceive()
        assert(kind == "value" and value == 1)
    end
    assert(receiver:tryreceive() == "empty")
    sender:close()
    receiver:close()
end
print("channels-ok")
]],
    })
    local built, builtOk = run(dir, "'" .. NUPP .. "' build")
    assert(builtOk, "the channel binary builds: " .. built)
    local output, ranOk = run(dir, stampRustHost(dir, dir .. "/build/app.payload.lua"))
    assert(ranOk and output == "channels-ok\n", "channel waits cooperate and cancel: " .. output)
    os.execute("rm -rf '" .. dir .. "'")
end

return M
