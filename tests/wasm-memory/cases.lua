-- Run against the actual C memory service, on stock Lua and in Wasm.
local memory = assert(__nuppWasmHost)
local function fails(body, message)
    local ok, reason = pcall(body)
    assert(not ok and tostring(reason):find(message, 1, true), tostring(reason))
end

local allocation = memory.allocate(16)
local pointer = memory.pointer(allocation, 0, 1)
for offset = 0, 15 do
    assert(memory.load(pointer, offset, "uint8") == 0)
    memory.store(pointer, offset, "uint8", offset)
end
memory.copy(memory.offset(pointer, 2), pointer, 8)
for offset = 0, 7 do
    assert(memory.load(pointer, offset + 2, "uint8") == offset)
end
memory.copy(pointer, memory.offset(pointer, 2), 8)
for offset = 0, 7 do
    assert(memory.load(pointer, offset, "uint8") == offset)
end
memory.copy(memory.offset(pointer, 16), pointer, 0)
fails(
    function()
        memory.load(pointer, 16, "uint8")
    end,
    "bounds"
)
fails(
    function()
        memory.store(pointer, 15, "uint32", 0)
    end,
    "bounds"
)
fails(
    function()
        memory.copy(pointer, pointer, 17)
    end,
    "bounds"
)
fails(
    function()
        memory.allocate(-1)
    end,
    "nonnegative integer"
)
fails(
    function()
        memory.allocate(0 / 0)
    end,
    "nonnegative integer"
)
fails(
    function()
        memory.pointer(allocation, 0, 0)
    end,
    "positive"
)
fails(
    function()
        memory.store(pointer, 0, "uint32", math.huge)
    end,
    "finite"
)
assert(memory.pointer(memory.allocate(0), 0, 1))
print("PASS bounded zeroed memory, overlapping copy, scalar and empty boundaries")

local weak = setmetatable({}, {__mode = "v"})
local function acquire()
    local owner = memory.allocate(16)
    local view = memory.pointer(owner, 0, 1)
    memory.store(view, 0, "uint8", 173)
    weak.owner = owner
    weak.pointer = view

    return memory.lease(view, 16)
end

local lease = acquire()
collectgarbage("collect")
collectgarbage("collect")
assert(weak.owner and weak.pointer, "a live host lease must root its pointer and allocation")
local grown = memory.allocate(32 * 1024 * 1024)
assert(memory.load(memory.pointer(grown, 0, 1), 32 * 1024 * 1024 - 1, "uint8") == 0)
assert(leaseByte(lease) == 173)
assert(memory.releaseLease(lease))
assert(not memory.releaseLease(lease))
collectgarbage("collect")
collectgarbage("collect")
assert(not weak.owner and not weak.pointer, "release must discard the lease's roots")
fails(
    function()
        leaseByte(lease)
    end,
    "not live"
)
print("PASS host lease roots and releases its allocation")

local thread = coroutine.create(function()
    return acquire()
end)
weak.thread = thread
local ok, coroutineLease = coroutine.resume(thread)
assert(ok, coroutineLease)
thread = nil
collectgarbage("collect")
collectgarbage("collect")
assert(weak.thread and weak.owner, "lease release must retain the originating Lua state")
assert(leaseByte(coroutineLease) == 173)
releaseAll()
assert(not memory.releaseLease(coroutineLease))
collectgarbage("collect")
collectgarbage("collect")
assert(not weak.thread and not weak.owner, "teardown must release coroutine and payload roots")
print("PASS coroutine leases and host teardown")

assert(not memory.releaseLease(0))
local leases = {}
for index = 1, 128 do
    leases[index] = memory.lease(pointer, 16)
end
fails(
    function()
        memory.lease(pointer, 16)
    end,
    "limit"
)
releaseAll()
for _, id in ipairs(leases) do
    assert(not memory.releaseLease(id))
end
local nextLease = memory.lease(pointer, 16)
assert(nextLease ~= leases[1])
assert(memory.releaseLease(nextLease))
print("PASS lease exhaustion, invalidation and reuse")
