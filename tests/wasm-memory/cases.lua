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

local uint32 = {size = 4}
function uint32:read(view, offset)
    return memory.load(view, offset, "uint32")
end

function uint32:write(view, offset, value)
    memory.store(view, offset, "uint32", value)
end

local typed = memory.typed(pointer, uint32)
assert(#typed == 4)
typed[0] = 4294967295
assert(typed[0] == 4294967295)
local tail = typed + 2
assert(#tail == 2 and tail + -2 == typed)
assert(#(typed + 4) == 0)
fails(
    function()
        return typed[-1]
    end,
    "nonnegative integer"
)
fails(
    function()
        return typed[4]
    end,
    "bounds"
)
fails(
    function()
        return typed + -1
    end,
    "bounds"
)
fails(
    function()
        return typed + 5
    end,
    "bounds"
)
local text = "rooted immutable bytes"
local borrowed = memory.borrowString(text)
assert(borrowed == memory.borrowString(text), "borrowing must preserve the string address")
assert(memory.string(borrowed, #text) == text)
fails(
    function()
        memory.store(borrowed, 0, "uint8", 0)
    end,
    "read-only"
)
fails(
    function()
        memory.copy(borrowed, pointer, 1)
    end,
    "read-only"
)
fails(
    function()
        memory.fill(borrowed, 1, 0)
    end,
    "read-only"
)
local readOnly = memory.typed(borrowed, uint32)
fails(
    function()
        readOnly[0] = 0
    end,
    "read-only"
)
fails(
    function()
        memory.fill(pointer, 17, 0)
    end,
    "bounds"
)
fails(
    function()
        memory.fill(pointer, 1, 256)
    end,
    "bounds"
)
memory.fill(pointer, 16, 255)
assert(memory.string(pointer, 16) == string.rep("\255", 16))
print("PASS typed bounds, zero-copy string identity and read-only enforcement")
for _, kind in ipairs({"int8", "int16", "int32", "integer"}) do
    memory.store(pointer, 0, kind, -1.75)
    assert(memory.load(pointer, 0, kind) == -1, "integer stores truncate before wrapping")
end
for _, kind in ipairs({"uint8", "uint16", "uint32"}) do
    memory.store(pointer, 0, kind, -0.75)
    assert(memory.load(pointer, 0, kind) == 0, "negative fractions truncate toward zero")
    memory.store(pointer, 0, kind, 1.75)
    assert(memory.load(pointer, 0, kind) == 1, "positive fractions truncate toward zero")
end
print("PASS integer storage truncates before wrapping")

local wide = memory.int64
local signed = wide.int64
local unsigned = wide.uint64
local render = wide.toString
assert(render(wide.add(signed("9223372036854775807"), signed("1"))) == "-9223372036854775808")
assert(render(wide.sub(signed("-9223372036854775808"), signed("1"))) == "9223372036854775807")
assert(render(wide.mul(signed("4294967296"), signed("4294967296"))) == "0")
assert(render(wide.div(signed("-7"), signed("3"))) == "-2")
assert(render(wide.mod(signed("-7"), signed("3"))) == "-1")
assert(render(wide.div(signed("-9223372036854775808"), signed("-1"))) == "-9223372036854775808")
assert(render(wide.mod(signed("-9223372036854775808"), signed("-1"))) == "0")
assert(wide.compare(unsigned("18446744073709551615"), unsigned("1")) > 0)
assert(render(wide.rshift(unsigned("18446744073709551615"), 63)) == "1")
assert(render(wide.arshift(signed("-2"), 1)) == "-1")
assert(render(wide.lshift(unsigned("1"), 63)) == "9223372036854775808")
assert(render(wide.lshift(unsigned("1"), 64)) == "1")
assert(render(wide.bnot(unsigned("0"))) == "18446744073709551615")
assert(render(wide.band(unsigned("0xffff0000ffff0000"), unsigned("0x00ff00ff00ff00ff"))) == "71776119077928960")
assert(render(wide.pow(signed("3"), signed("20"))) == "3486784401")
assert(wide.toNumber(signed("42")) == 42)
fails(
    function()
        wide.div(signed("1"), signed("0"))
    end,
    "division by zero"
)
fails(
    function()
        signed("xyz")
    end,
    "digit"
)
fails(
    function()
        signed(math.huge)
    end,
    "finite"
)
for _, value in ipairs({"0", "1", "9007199254740993", "9223372036854775807", "-9223372036854775808", "-1"}) do
    memory.store(pointer, 1, "int64", signed(value))
    assert(render(memory.load(pointer, 1, "int64")) == value)
end
memory.store(pointer, 0, "uint64", unsigned("18446744073709551615"))
assert(render(memory.load(pointer, 0, "uint64")) == "18446744073709551615")
print("PASS exact signed and unsigned 64-bit arithmetic and unaligned storage")

for _, row in ipairs({
    {"uint8", 255},
    {"int8", -128},
    {"uint16", 65535},
    {"int16", -32768},
    {"uint32", 4294967295},
    {"int32", -2147483648},
    {"float", 1.25},
    {"number", -1.25},
    {"uint64", unsigned("18446744073709551615")},
    {"int64", signed("-9223372036854775808")},
}) do
    assert(memory.decode(row[1], memory.encode(row[1], row[2])) == row[2])
end
fails(
    function()
        memory.decode("uint32", "x")
    end,
    "width"
)
print("PASS exact scalar encoding without an intermediate byte allocation")

local function region(bytes)
    return memory.pointer(memory.allocate(bytes), 0, 1)
end

local references = region(12)
local copies = region(12)
local referenced = region(4)
memory.store(referenced, 0, "uint32", 314159)
weak.referenced = referenced
memory.storeReference(references, 0, referenced)
referenced = nil
collectgarbage("collect")
assert(weak.referenced and memory.load(memory.loadReference(references, 0), 0, "uint32") == 314159)
memory.copyAt(copies, 4, references, 0, 4)
memory.fill(references, 12, 0)
collectgarbage("collect")
assert(weak.referenced and memory.load(memory.loadReference(copies, 4), 0, "uint32") == 314159)
memory.copyAt(copies, 8, copies, 4, 4)
memory.store(copies, 4, "uint32", 0)
collectgarbage("collect")
assert(weak.referenced and memory.loadReference(copies, 4) == nil)
assert(memory.load(memory.loadReference(copies, 8), 0, "uint32") == 314159)
memory.fill(copies, 12, 0)
collectgarbage("collect")
collectgarbage("collect")
assert(not weak.referenced, "overwriting the last reference must release its owner")
assert(memory.loadReference(copies, 8) == nil)
local a, b = region(4), region(4)
weak.a, weak.b = a, b
memory.storeReference(a, 0, b)
memory.storeReference(b, 0, a)
a, b = nil, nil
collectgarbage("collect")
collectgarbage("collect")
assert(not weak.a and not weak.b, "allocation reference cycles must remain collectable")
print("PASS reference roots, overlap-safe struct copies, overwrite barriers and cycles")

local readLease = memory.lease(borrowed, #text)
assert(not leaseWritable(readLease))
assert(memory.releaseLease(readLease))
fails(
    function()
        memory.lease(borrowed, #text, true)
    end,
    "read-only"
)
local writeLease = memory.lease(pointer, 16, true)
assert(leaseWritable(writeLease))
assert(memory.releaseLease(writeLease))
assert(not leaseWritable(writeLease))
print("PASS host transfer permissions and revocation")
local ints = memory.typed(memory.pointer(memory.allocate(16), 0, 1), {
    size = 4,
    read = function(_, p, at)
        return memory.load(p, at, "int32")
    end,
    write = function(_, p, at, v)
        return memory.store(p, at, "int32", v)
    end,
})
assert((ints + 4) - ints == 4 and ints < ints + 1 and ints <= ints)
assert((ints + 3) - 2 == ints + 1)
fails(
    function()
        return ints - (ints + 5)
    end,
    "bounds"
)
local zeroes = memory.typed(
    memory.pointer(memory.allocate(0), 0, 1),
    {
        size = 0,
        read = function()
            return {}
        end,
        write = function()
        end,
    },
    3
)
assert(#zeroes == 3 and #memory.offset(zeroes, 2) == 1 and #(zeroes + 3) == 0)
assert((zeroes + 3) - zeroes == 3)
assert(type(zeroes[2]) == "table")
fails(
    function()
        return zeroes[3]
    end,
    "bounds"
)
print("PASS bounded pointer arithmetic and zero-sized element counts")

local stable = memory.pointer(memory.allocate(16), 0, 1)
memory.store(stable, 0, "uint32", 71)
failLargeAllocations(true)
local allocated, allocationError = pcall(memory.allocate, 4096)
failLargeAllocations(false)
assert(not allocated and tostring(allocationError):find("memory"))
assert(memory.load(stable, 0, "uint32") == 71)
assert(memory.allocate(4096))
print("PASS allocation failure preserves live storage and the host remains usable")

-- Separate pointer projections into one allocation share reference-slot offsets.
local owner = memory.allocate(12)
local root = memory.pointer(owner, 0, 1)
local middle = memory.pointer(owner, 4, 1)
local target = memory.pointer(memory.allocate(4), 0, 1)
memory.store(target, 0, "uint32", 99)
memory.storeReference(middle, 0, target)
assert(memory.load(memory.loadReference(root, 4), 0, "uint32") == 99)
memory.fill(middle, 4, 0)
assert(memory.loadReference(root, 4) == nil)
print("PASS independent pointer projections share allocation reference roots")
