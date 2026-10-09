-- A browser application's guest without the emulator around it.
--
-- `runtime/luajit/bridge.lua` runs inside v86, which only a Linux build makes.
-- This runs the same application coroutine under the LuaJIT the tests use and
-- reproduces what the bridge does to every frame: the application's text is
-- decoded and re-encoded by the bridge's own lunajson, leased guest memory is
-- copied out beside the frame, and the host's answer is decoded, its writable
-- leases copied back, and encoded again before the application sees it. The
-- host is whatever reads standard output and answers on standard input: one
-- JSON object per line in each direction.
--
-- Usage: luajit guest.lua ROOT SCENARIO [NAME]

local root, scenarioFile, scenarioName = arg[1], arg[2], arg[3]
assert(root and scenarioFile, "usage: guest.lua ROOT SCENARIO [NAME]")

local ffi = require("ffi")
local bit = require("bit")
local encode = dofile(root .. "/src/nupp/runtime/vendor/lunajson/encoder.lua")()
local decode = dofile(root .. "/src/nupp/runtime/vendor/lunajson/decoder.lua")()

ffi.cdef[[
typedef struct { long tv_sec; long tv_usec; } nupp_test_timeval;
int gettimeofday(nupp_test_timeval *tv, void *tz);
]]

local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local decodeTable = {}
for index = 1, 64 do
    decodeTable[ALPHABET:byte(index)] = index - 1
end

local function base64(bytes)
    local out, length = {}, #bytes
    for index = 1, length, 3 do
        local a, b, c = bytes:byte(index, index + 2)
        local word = bit.bor(bit.lshift(a, 16), bit.lshift(b or 0, 8), c or 0)
        out[#out + 1] = string.char(
            ALPHABET:byte(bit.rshift(word, 18) + 1),
            ALPHABET:byte(bit.band(bit.rshift(word, 12), 63) + 1),
            b and ALPHABET:byte(bit.band(bit.rshift(word, 6), 63) + 1) or 61,
            c and ALPHABET:byte(bit.band(word, 63) + 1) or 61
        )
    end
    return table.concat(out)
end

local function unbase64(text)
    local out = {}
    for index = 1, #text, 4 do
        local a, b, c, d = text:byte(index, index + 3)
        local word = bit.bor(
            bit.lshift(decodeTable[a], 18),
            bit.lshift(decodeTable[b], 12),
            bit.lshift(decodeTable[c] or 0, 6),
            decodeTable[d] or 0
        )
        if c == 61 then
            out[#out + 1] = string.char(bit.rshift(word, 16))
        elseif d == 61 then
            out[#out + 1] = string.char(bit.rshift(word, 16), bit.band(bit.rshift(word, 8), 255))
        else
            out[#out + 1] = string.char(bit.rshift(word, 16), bit.band(bit.rshift(word, 8), 255), bit.band(word, 255))
        end
    end
    return table.concat(out)
end

-- The bridge's memory transport, unchanged apart from where the bytes travel.
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
    leases[nextLease] = {pointer = pointer, bytes = count, writable = writable == true}
    return nextLease
end

function guestMemory.releaseLease(id)
    leases[id] = nil
end

local function exportLeases(frame)
    local exported, seen, offset, pieces = {}, {}, 0, {}
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
                pieces[#pieces + 1] = ffi.string(lease.pointer, lease.bytes)
                exported[#exported + 1] = {id = id, offset = offset, bytes = lease.bytes, writable = lease.writable}
                offset = offset + lease.bytes
                seen[id] = true
            end
        end
    end
    exported[0] = #exported
    frame._leases = exported
    return table.concat(pieces)
end

local function importLeases(response, payload)
    assert(#payload <= transferLimit, "host transfer exceeds two MiB")
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
                and returned.offset + returned.bytes <= #payload,
                "invalid host transfer write"
            )
            ffi.copy(lease.pointer, payload:sub(returned.offset + 1, returned.offset + returned.bytes), lease.bytes)
        end
        leases[returned.id] = nil
    end
    response._leases = nil
end

local frames = 0
local function send(message)
    io.stdout:write(message, "\n")
    io.stdout:flush()
end

local function exchange(frame)
    local payload = exportLeases(frame)
    frames = frames + 1
    assert(#encode(frame) <= 1024 * 1024, "guest frame text exceeds one MiB")
    send(encode({type = "effect", frame = frame, payload = base64(payload)}))
    local line = assert(io.stdin:read("*l"), "the host closed the channel")
    assert(#line <= 4 * 1024 * 1024, "host answer exceeds the mailbox")
    local message = decode(line)
    local response = message.response
    importLeases(response, unbase64(message.payload or ""))
    return response
end

local now = ffi.new("nupp_test_timeval")
_G.__nuppBrowser = {
    memory = guestMemory,
    now = function()
        ffi.C.gettimeofday(now, nil)
        return tonumber(now.tv_sec) * 1000 + tonumber(now.tv_usec) / 1000
    end,
}

-- The compiler fixes a target's host when it builds the runtime, and the tests'
-- runtime is a native build; a browser build would carry this.
package.loaded["nupp.runtime.target"] = {dialect = "luajit", host = "browser"}

local scenarios = dofile(scenarioFile)
local body = coroutine.create(function()
    local run = assert(scenarios[scenarioName or "main"], "no such scenario")
    return run()
end)
_G.__nuppBrowser.root = body
local response
local outcome
while true do
    local ok, value = coroutine.resume(body, response)
    if not ok then
        outcome = {type = "done", ok = false, error = debug.traceback(body, tostring(value)), frames = frames}
        break
    end
    if coroutine.status(body) == "dead" then
        outcome = {type = "done", ok = true, value = value, frames = frames}
        break
    end
    assert(type(value) == "string", "application yielded an invalid effect frame")
    response = encode(exchange(decode(value)))
end
local leaked = 0
for _ in pairs(leases) do
    leaked = leaked + 1
end
outcome.leases = leaked
send(encode(outcome))
