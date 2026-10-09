-- A finite codec hands owned bytes to transport. The transport controls partial
-- publication and suspension; it never retains a borrowed serializer handle.
local json = require("nupp.serde.json")
local documents = require("nupp.serde.document")
local tasks = require("nupp.tasks")
local time = require("nupp.time")
local codec = json.codec()
local original = documents.documentAdapter():contents()
local escaped, member
local adapter = {
    describe = function(_, direction)
        local description = original.adapter:describe(direction)
        member = description.member
        return description
    end,
    write = function(_, value, writer)
        escaped = writer
        return original.adapter:write(value, writer)
    end,
    read = function(_, reader)
        return original.adapter:read(reader)
    end,
}
local binding = {
    accept = function(_, consumer, state)
        return consumer:apply(adapter, state)
    end,
}
local payload = documents.string(string.rep("payload", 64))
local bytes = codec:encode(binding, payload)
assert(not pcall(escaped.writeString, escaped, member, "expired"))
local published, parked, unwound = {}, false, false
local attempted = 0

tasks.run(function(scope)
    local child = scope:spawn(function()
        local ok, problem = pcall(function()
            for at = 1, #bytes, 32 do
                attempted = attempted + 1
                published[#published + 1] = bytes:sub(at, at + 31)
                -- A full transport queue parks until capacity or cancellation.
                parked = true
                time.sleep(10000)
            end
        end)
        unwound = true
        if not ok then
            error(problem, 0)
        end
    end)
    for _ = 1, 1000 do
        if parked then
            break
        end
        time.sleep(1)
    end
    assert(parked and attempted == 1 and #table.concat(published) == 32)
    codec:clear()
    assert(codec:encode(original, documents.string("another request")) == '"another request"')
    assert(not pcall(escaped.writeString, escaped, member, "still expired"))
    assert(child:cancel("transport cancelled"))
    local ok, problem = pcall(child.await, child)
    assert(not ok and tasks.isCancelled(problem))
    assert(unwound and attempted == 1, "cancelled publication resumed or skipped cleanup")
end)
assert(table.concat(published) == bytes:sub(1, 32), "partial transport output was changed")

local completed = {}
tasks.run(function(scope)
    scope:spawn(function()
        for at = 1, #bytes, 32 do
            -- A suspended write completes before the next chunk is submitted.
            time.sleep(1)
            completed[#completed + 1] = bytes:sub(at, at + 31)
        end
    end):await()
end)
assert(table.concat(completed) == bytes)
assert(codec:decodeDocument(documents.documentAdapter(), bytes):string() == string.rep("payload", 64))
print("owned publication survives backpressure, cancellation, cache reuse, and partial output")
