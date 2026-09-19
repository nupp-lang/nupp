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

local function exchange(kind, result)
    write(encode(result))
    signal(kind, sequence)
    assert(tonumber(io.read("*l")) == sequence, "stale guest response")
    local response = decode(read(4 * 1024 * 1024, 2, 1024 * 1024))
    if response.payloadField then
        assert(response.payloadField == "source", "unexpected binary payload field")
        response.source = read(5 * 1024 * 1024, 3, 2 * 1024 * 1024)
        response.payloadField = nil
    end
    sequence = sequence + 1

    return response
end

_G.__nuppBrowser = {
    config = config,
    now = function()
        return clock.nupp_browser_clock(memory + 168)
    end
}
signal("MAILBOX")
assert(io.read("*l") == "mailbox", "host did not acknowledge the mailbox")

local function main()
    local app = assert(loadfile("/host/app.lua"))
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
write(encode(ok and {ok = true, value = value} or {ok = false, error = tostring(value)}))
signal("DONE", sequence)
