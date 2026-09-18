local ffi = require("ffi")
local transport = assert(_G.__qemuTransport)
local memory = {}
local leases = {}
local owners = setmetatable({}, {__mode = "k"})
local nextId = 0
local totalBytes = 0
local LIMIT = 16 * 1024 * 1024
local kinds = {
    uint8 = "uint8_t",
    int8 = "int8_t",
    uint16 = "uint16_t",
    int16 = "int16_t",
    uint32 = "uint32_t",
    int32 = "int32_t",
    uint64 = "uint64_t",
    int64 = "int64_t",
    float = "float",
    double = "double"
}

function memory.allocate(bytes)
    assert(bytes >= 0 and bytes <= LIMIT and bytes == math.floor(bytes), "invalid allocation")
    return ffi.new("uint8_t[?]", math.max(1, bytes))
end

function memory.pointer(allocation, index, stride)
    local pointer = ffi.cast("uint8_t *", allocation) + index * stride
    owners[pointer] = allocation
    return pointer
end

function memory.offset(pointer, bytes)
    local result = ffi.cast("uint8_t *", pointer) + bytes
    owners[result] = owners[pointer] or pointer
    return result
end

function memory.load(pointer, offset, kind)
    return ffi.cast(assert(kinds[kind]) .. " *", memory.offset(pointer, offset))[0]
end

function memory.store(pointer, offset, kind, value)
    ffi.cast(assert(kinds[kind]) .. " *", memory.offset(pointer, offset))[0] = value
end

memory.copy = ffi.copy
function memory.descriptor(value)
    return {bytes = ffi.sizeof(value)}
end

function memory.lease(pointer, bytes, writable)
    assert(type(bytes) == "number" and bytes >= 0 and bytes == math.floor(bytes), "invalid lease extent")
    assert(totalBytes + bytes <= LIMIT, "guest transfer byte limit exceeded")
    assert(type(pointer) == "cdata", "guest lease needs a native pointer")
    nextId = nextId + 1
    leases[nextId] = {pointer = pointer, owner = owners[pointer], bytes = bytes, writable = writable == true}
    totalBytes = totalBytes + bytes

    return nextId
end

function memory.releaseLease(id)
    local lease = leases[id]
    if lease then
        totalBytes = totalBytes - lease.bytes
        leases[id] = nil
    end
end

function memory.export()
    local result = {}
    local chunks = {}
    local offset = 0
    for id, lease in pairs(leases) do
        chunks[#chunks + 1] = ffi.string(lease.pointer, lease.bytes)
        result[#result + 1] = {id = id, bytes = lease.bytes, writable = lease.writable, offset = offset}
        offset = offset + lease.bytes
    end
    if offset > 0 then
        transport.write("/host/transfers.bin", table.concat(chunks))
    end

    return result
end

function memory.import(writes)
    local seen = {}
    local data = #writes > 0 and transport.read("/host/writeback.bin") or ""
    for _, write in ipairs(writes) do
        local lease = assert(leases[write.id], "host wrote an expired lease")
        assert(not seen[write.id] and lease.writable and write.bytes == lease.bytes, "invalid host writeback")
        seen[write.id] = true
        assert(
            type(write.offset) == "number" and write.offset >= 0 and write.offset == math.floor(write.offset),
            "invalid writeback offset"
        )
        local bytes = data:sub(write.offset + 1, write.offset + write.bytes)
        assert(#bytes == lease.bytes, "short host writeback")
        ffi.copy(lease.pointer, bytes, #bytes)
    end
end

function memory.stats()
    local count = 0
    for _ in pairs(leases) do
        count = count + 1
    end

    return {leases = count, bytes = totalBytes}
end

return memory
