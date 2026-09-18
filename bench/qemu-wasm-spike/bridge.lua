local encode = dofile("/nupp/json-encoder.lua")()
local decode = dofile("/nupp/json-decoder.lua")()
local sequence = 0

local function read(path)
    local file = assert(io.open(path, "rb"))
    local bytes = assert(file:read("*a"))
    file:close()
    return bytes
end

local function write(path, bytes)
    local file = assert(io.open(path, "wb"))
    assert(file:write(bytes))
    assert(file:close())
end

local config = decode(read("/host/config.json"))
_G.__qemuConfig = config
if config.jit == false then
    jit.off();
    jit.flush()
end
-- Linux leaves the top 64 MiB of the emulated RAM outside its allocator.
-- Mapping that region gives the browser a mailbox in QEMU's existing shared heap.
local ffi = require("ffi")
ffi.cdef[[int open(const char *, int, ...); int close(int);
void *mmap(void *, size_t, int, int, int, long);]]
ffi.cdef[[double spike_clock(const void *);]]
local clock = ffi.load("spike")
local fd = ffi.C.open("/dev/mem", 2)
assert(fd >= 0, "cannot open guest physical memory")
local mailbox = ffi.cast("uint8_t *", ffi.C.mmap(nil, 64 * 1024 * 1024, 3, 1, fd, 192 * 1024 * 1024))
ffi.C.close(fd)
assert(mailbox ~= ffi.cast("void *", -1), "cannot map guest mailbox")
ffi.copy(mailbox, config.mailboxToken, #config.mailboxToken)
local header = ffi.cast("uint32_t *", mailbox + 128)
local slots = {
    ["/host/request.json"] = {4096, 8 * 1024 * 1024, 0},
    ["/host/result.json"] = {4096, 8 * 1024 * 1024, 0},
    ["/host/transfers.bin"] = {4096 + 8 * 1024 * 1024, 16 * 1024 * 1024, 1},
    ["/host/response.json"] = {32 * 1024 * 1024, 8 * 1024 * 1024, 2},
    ["/host/writeback.bin"] = {40 * 1024 * 1024, 16 * 1024 * 1024, 3}
}
local fileRead = read
read = function(path)
    local slot = slots[path]
    if not slot then
        return fileRead(path)
    end
    local length = tonumber(header[slot[3]])
    assert(length <= slot[2], "host mailbox overflow")

    return ffi.string(mailbox + slot[1], length)
end
write = function(path, bytes)
    local slot = assert(slots[path], "unknown mailbox slot")
    assert(#bytes <= slot[2], "guest mailbox overflow")
    ffi.copy(mailbox + slot[1], bytes, #bytes)
    header[slot[3]] = #bytes
end
io.write("\n@@NUPP_MAILBOX@@\n")
io.flush()
assert(io.read("*l") == "mailbox", "host did not acknowledge the mailbox")
_G.__qemuNow = function()
    return clock.spike_clock(mailbox + 168)
end
_G.__qemuTransport = {read = read, write = write}
_G.__qemuMemory = dofile("/nupp/guest-memory.lua")
if config.traceRequires then
    local original = require
    _G.require = function(name)
        io.write("require ", name, "\n")
        io.flush()
        return original(name)
    end
end
if config.worker then
    _G.__nuppWorkerEntry = "nupp.workers"
    _G.__nuppWorkerSetup = config.setup or 'require("nupp.qemu.setup")'
end
io.write("Loading guest application\n")
io.flush()
local app = read("/host/app.lua")
io.write("Read ", #app, " application bytes\n")
io.flush()
local body = coroutine.create(assert(loadstring(app, "@app.lua")))
io.write("Compiled guest application\n")
io.flush()
local answer
while true do
    local ok, frame = coroutine.resume(body, answer)
    if config.traceRequires then
        io.write("resume returned ", tostring(ok), " ", coroutine.status(body), "\n")
        io.flush()
    end
    if not ok then
        write("/host/result.json", encode({ok = false, error = tostring(frame), traceback = debug.traceback(body)}))
        io.write("\n@@NUPP_BRIDGE_DONE@@\n")
        io.flush()
        break
    elseif coroutine.status(body) == "dead" then
        write("/host/result.json", encode({ok = true, value = frame}))
        io.write("\n@@NUPP_BRIDGE_DONE@@\n")
        io.flush()
        break
    end
    assert(type(frame) == "string", "guest yielded a non-string effect")
    sequence = sequence + 1
    local memory = rawget(_G, "__qemuMemory")
    local leases = memory and memory.export() or {}
    if config.traceRequires then
        io.write("exported leases\n")
        io.flush()
    end
    local requestBytes = encode({sequence = sequence, request = decode(frame), leases = leases})
    if config.traceRequires then
        io.write("encoded ", #requestBytes, " request bytes\n");
        io.flush()
    end
    write("/host/request.json", requestBytes)
    io.write("\n@@NUPP_BRIDGE_REQUEST@@ ", sequence, "\n")
    io.flush()
    local acknowledged = assert(io.read("*l"), "host closed its response channel")
    assert(tonumber(acknowledged) == sequence, "response sequence mismatch")
    local response = decode(read("/host/response.json"))
    assert(response.sequence == sequence, "stale response")
    if memory then
        memory.import(response.writes or {})
        for _, id in ipairs(response.released or {}) do
            memory.releaseLease(id)
        end
    end
    answer = encode(response.response)
end
