-- One LuaJIT state per worker. Snapshot restore supplies this state fresh input.
local encode = dofile("/nupp/json-encoder.lua")()
local decode = dofile("/nupp/json-decoder.lua")()
local ffi = require("ffi")
ffi.cdef[[
int open(const char *, int, ...);
int close(int);
void *mmap(void *, size_t, int, int, int, int64_t);
double nupp_browser_clock(const void *);
]]

local function readFile(path)
    local file = assert(io.open(path, "rb"))
    local value = assert(file:read("*a"))
    assert(file:close())
    return value
end

local config = decode(readFile("/host/config.json"))
if config.jit == false then
    jit.off()
    jit.flush()
end
-- The i386 guest's math.fmod loses negative zero and returns NaN for finite
-- dividends with infinite divisors. Match the native LuaJIT remainder contract.
local rawFmod = math.fmod
local infinity = math.huge
local negativeZero = -1 / math.huge

local function exactRemainder(dividend, divisor)
    local magnitude, unit = math.abs(dividend), math.abs(divisor)
    local _, exponent = math.frexp(magnitude)
    local fraction = math.frexp(unit)
    local scaled = math.ldexp(fraction, exponent - 1)
    if scaled * 2 <= magnitude then
        scaled = scaled * 2
    end
    while scaled >= unit do
        if magnitude >= scaled then
            magnitude = magnitude - scaled
        end
        scaled = scaled * 0.5
    end

    return dividend < 0 and -magnitude or magnitude
end

math.fmod = function(dividend, divisor)
    if (divisor == infinity or divisor == -infinity) and dividend ~= infinity and dividend ~= -infinity then
        return dividend
    end
    local result = rawFmod(dividend, divisor)
    -- The guest libm also rounds some extreme finite ratios to zero. Binary
    -- long division keeps each subtraction exact and recovers their remainder.
    if result == 0
        and math.abs(dividend) < infinity
        and math.abs(divisor) < infinity
        and math.abs(dividend) > math.abs(divisor)
    then
        result = exactRemainder(dividend, divisor)
    end
    if result == 0 and (dividend < 0 or dividend == 0 and 1 / dividend < 0) then
        return negativeZero
    end

    return result
end
local address = assert(tonumber(readFile("/proc/cmdline"):match("nupp.mailbox=(%d+)")))
assert(address == 48 * 1024 * 1024 or address == 112 * 1024 * 1024)
local fd = ffi.C.open("/dev/mem", 2)
assert(fd >= 0, "cannot open guest physical mailbox")
local memory = ffi.cast("uint8_t *", ffi.C.mmap(nil, 8 * 1024 * 1024, 3, 1, fd, address))
ffi.C.close(fd)
assert(memory ~= ffi.cast("void *", -1), "cannot map guest mailbox")
local header = ffi.cast("uint32_t *", memory + 128)
local clock = ffi.load("nupp-browser")

local function read(offset, index, limit)
    local length = tonumber(header[index])
    assert(length <= limit, "host mailbox overflow")
    return ffi.string(memory + offset, length)
end

local function write(value)
    assert(#value <= 1024 * 1024, "guest result exceeds one MiB")
    ffi.copy(memory + 4096, value, #value)
    header[0] = #value
end

local function signal(kind, sequence)
    io.write("\n@@NUPP_", kind, "@@ ", sequence or 0, "\n")
    io.flush()
end

local sequence = 0
local leases = {}
local nextLease = 0
local transferLimit = 2 * 1024 * 1024
local guestMemory = {}

function guestMemory.lease(pointer, count, writable)
    assert(
        type(count) == "number" and count >= 0 and count % 1 == 0 and count <= transferLimit,
        "invalid guest transfer extent"
    )
    assert(pointer ~= nil and (count == 0 or ffi.cast("void *", pointer) ~= nil), "null guest transfer pointer")
    nextLease = nextLease + 1
    assert(nextLease < 9007199254740991, "guest transfer identifiers exhausted")
    leases[nextLease] = {pointer = pointer, bytes = count, writable = writable == true}

    return nextLease
end

function guestMemory.releaseLease(id)
    leases[id] = nil
end

local function exportLeases(frame)
    local exported, seen, offset = {}, {}, 0
    for _, request in ipairs(frame.requests or {}) do
        local identifiers = {}
        for _, field in ipairs({"lease", "bodyLease", "resultLease"}) do
            if request[field] ~= nil then
                identifiers[#identifiers + 1] = request[field]
            end
        end
        for _, span in ipairs(request.spans or {}) do
            identifiers[#identifiers + 1] = span.lease
        end
        for _, id in ipairs(identifiers) do
            if id ~= nil and not seen[id] then
                local lease = assert(leases[id], "stale guest transfer lease")
                assert(offset + lease.bytes <= transferLimit, "guest transfer batch exceeds two MiB")
                ffi.copy(memory + 2 * 1024 * 1024 + offset, lease.pointer, lease.bytes)
                exported[#exported + 1] = {id = id, offset = offset, bytes = lease.bytes, writable = lease.writable}
                offset = offset + lease.bytes
                seen[id] = true
            end
        end
    end
    exported[0] = #exported
    frame._leases = exported
    header[1] = offset
end

local function importLeases(response)
    local available = tonumber(header[3])
    assert(available <= transferLimit, "host transfer exceeds two MiB")
    local seen = {}
    for _, returned in ipairs(response._leases or {}) do
        local lease = assert(leases[returned.id], "host returned a stale transfer lease")
        assert(not seen[returned.id], "host returned a duplicate transfer lease")
        seen[returned.id] = true
        if returned.offset ~= nil then
            assert(
                lease.writable
                and returned.bytes == lease.bytes
                and returned.offset >= 0
                and returned.offset % 1 == 0
                and returned.offset + returned.bytes <= available,
                "invalid host transfer write"
            )
            ffi.copy(lease.pointer, memory + 5 * 1024 * 1024 + returned.offset, lease.bytes)
        end
        leases[returned.id] = nil
    end
    response._leases = nil
end

local function exchange(kind, result)
    header[1] = 0
    if kind == "EFFECT" then
        exportLeases(result)
    end
    local codec = kind == "COMPILER" and require("nupp.runtime.provider.lunajson").encode or encode
    write(codec(result))
    signal(kind, sequence)
    assert(tonumber(io.read("*l")) == sequence, "stale guest response")
    local response = decode(read(4 * 1024 * 1024, 2, 1024 * 1024))
    if kind == "EFFECT" then
        importLeases(response)
    end
    if response.payloadField then
        assert(response.payloadField == "source", "unexpected binary payload field")
        response.source = read(5 * 1024 * 1024, 3, transferLimit)
        response.payloadField = nil
    end
    sequence = sequence + 1

    return response
end

local scalarTypes = {
    bool = "bool",
    f32 = "float",
    f64 = "double",
    i32 = "int32_t",
    u32 = "uint32_t",
    i64 = "int64_t",
    u64 = "uint64_t"
}

local function kernel(unit, symbol, descriptor)
    local params, results = descriptor.params, descriptor.results
    -- One unit per tier, widest first; the host runs the first it compiled.
    if type(unit) == "table" then
        unit[0] = #unit
    end
    local countCount = 1
    if descriptor.independentCounts then
        countCount = 0
        for _, param in ipairs(params) do
            if param.kind == "read_span" or param.kind == "write_span" then
                countCount = countCount + 1
            end
        end
    end

    return function(...)
        local values = {...}
        local arguments = ffi.new("uint64_t[?]", math.max(1, #params + countCount))
        local returned = ffi.new("uint64_t[?]", math.max(1, #results))
        local spans, allocated = {}, {}

        local function lease(pointer, bytes, writable)
            local id = guestMemory.lease(pointer, bytes, writable)
            allocated[#allocated + 1] = id
            return id
        end

        local countIndex = #params + 1
        local ok, problem = pcall(function()
            for index, param in ipairs(params) do
                if param.kind == "read_span" or param.kind == "write_span" then
                    local count = values[countIndex]
                    assert(
                        type(count) == "number" and count >= 0 and count % 1 == 0 and count <= transferLimit,
                        "invalid Wasm span count"
                    )
                    local layout = param.layout
                    local ctype = scalarTypes[param.type]
                    if param.sourceType == "uint8"
                        or param.sourceType == "int8"
                        or param.sourceType == "uint16"
                        or param.sourceType == "int16"
                    then
                        ctype = param.sourceType .. "_t"
                    end
                    local stride = layout and layout.size or ffi.sizeof(assert(ctype, "unknown Wasm span type"))
                    local fields = {}
                    for _, field in ipairs(layout and layout.fields or {}) do
                        fields[#fields + 1] = {name = field.name, offset = field.offset, bytes = field.size}
                    end
                    fields[0] = #fields
                    spans[
                        #spans + 1
                    ] = {
                        lease = lease(values[index], count * stride, param.kind == "write_span"),
                        stride = stride,
                        fields = fields
                    }
                    ffi.cast("uint32_t *", arguments + countIndex - 1)[0] = count
                    if descriptor.independentCounts then
                        countIndex = countIndex + 1
                    end
                else
                    ffi.cast(
                        assert(scalarTypes[param.type], "unknown Wasm scalar type") .. " *",
                        arguments + index - 1
                    )[0] = values[index]
                end
            end
            spans[0] = #spans
            local response = exchange("EFFECT", {
                kind = "effects",
                requests = {
                    [0] = 1,
                    {
                        id = 1,
                        kind = "aot",
                        unit = unit,
                        symbol = symbol,
                        lease = lease(arguments, (#params + countCount) * 8, false),
                        resultLease = lease(returned, #results * 8, true),
                        spans = spans
                    }
                }
            })
            local answer = assert(response.responses and response.responses[1], "missing Wasm kernel response")
            assert(not answer.error, answer.error)
        end)
        for _, id in ipairs(allocated) do
            guestMemory.releaseLease(id)
        end
        if not ok then
            error(problem, 2)
        end
        local valuesOut = {}
        for index, kind in ipairs(results) do
            local value = ffi.cast(scalarTypes[kind] .. " *", returned + index - 1)[0]
            if kind == "i64" or kind == "u64" or kind == "bool" then
                valuesOut[index] = value
            else
                valuesOut[index] = tonumber(value)
            end
        end

        return unpack(valuesOut, 1, #results)
    end
end

_G.__nuppBrowser = {
    config = config,
    memory = guestMemory,
    kernel = kernel,
    now = function()
        return clock.nupp_browser_clock(memory + 168)
    end
}
signal("MAILBOX")
assert(io.read("*l") == "mailbox", "host did not acknowledge the mailbox")

local function main()
    local app
    if config.mode == "application" then
        local bytes = readFile("/host/app.lua")
        assert(bytes:sub(1, 8) == "NUAPP001", "invalid application payload")
        local a, b, c, d = bytes:byte(9, 12)
        assert(d, "truncated application payload")
        local length = a + b * 256 + c * 65536 + d * 16777216
        assert(length <= #bytes - 12, "invalid application initialization extent")
        if config.workerEntry then
            rawset(_G, "__nuppWorkerEntry", config.workerEntry)
            rawset(_G, "__nuppWorkerSetup", config.workerSetup or "")
        end
        if length > 0 then
            assert(loadstring(bytes:sub(13, 12 + length), "@nupp-initialize"))()
        end
        local source = bytes:sub(13 + length)
        if config.managed then
            app = function()
                return _G.__nuppPlaygroundRun(source)
            end
        else
            app = assert(loadstring(source, "@nupp-app.lua"))
        end
    else
        app = assert(loadfile("/host/app.lua"))
    end
    if config.mode == "compiler" then
        local Browser = app()
        local session = Browser.new()
        local result = {ready = true}
        while true do
            local request = exchange("COMPILER", result)
            if request.kind == "close" then
                return true
            end
            local ok, answer = pcall(function()
                if request.kind == "hover" then
                    return session:hover(request.offset or 1)
                end
                assert(request.kind == "check" or request.kind == "compile", "unknown compiler request")
                assert(type(request.source) == "string", "compiler source must be a string")

                local options = request.options or {}
                options.dialect = options.dialect or "luajit"

                return session[request.kind](session, request.source, request.filename or "playground.nupp", options)
            end)
            result = ok and {ok = true, response = answer} or {ok = false, error = tostring(answer)}
        end
    end
    local body = coroutine.create(app)
    local response
    while true do
        local ok, value = coroutine.resume(body, response)
        if not ok then
            error(debug.traceback(body, tostring(value)), 0)
        end
        if coroutine.status(body) == "dead" then
            return value
        end
        assert(type(value) == "string", "application yielded an invalid effect frame")
        response = encode(exchange("EFFECT", decode(value)))
    end
end

local ok, value = xpcall(main, debug.traceback)
header[1] = 0
write(encode(ok and {ok = true, value = value} or {ok = false, error = tostring(value)}))
signal("DONE", sequence)
