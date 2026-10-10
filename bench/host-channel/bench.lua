-- The host channel's workloads, run in the real browser guest by `run.mjs`.
--
-- Each program answers `{samples = ..., summary = ...}`. Two clocks are read:
-- `time.now()` is the page's clock, which a frame's whole round trip spends,
-- and `os.clock()` is the guest process's own CPU time, which a wait for the
-- page does not spend. The second is the scarce one: it is emulated x86, and
-- whatever the channel costs there is taken from the frame's game work.

local host = require("nupp.host")
local span = require("nupp.mem.span")
local time = require("nupp.time")
local ffi = require("ffi")

local workloads = {}

local function percentile(sorted, fraction)
    if #sorted == 0 then
        return nil
    end
    local index = math.max(1, math.min(#sorted, math.ceil(#sorted * fraction)))
    return sorted[index]
end

local function summarize(samples)
    local sorted = {}
    local total = 0
    for index, value in ipairs(samples) do
        sorted[index] = value
        total = total + value
    end
    table.sort(sorted)
    return {
        n = #sorted,
        mean = #sorted > 0 and total / #sorted or nil,
        p50 = percentile(sorted, 0.5),
        p90 = percentile(sorted, 0.9),
        p99 = percentile(sorted, 0.99),
        min = sorted[1],
        max = sorted[#sorted],
    }
end

local function bytes(size)
    local buffer = ffi.new("uint8_t[?]", math.max(size, 1))
    for index = 0, size - 1 do
        buffer[index] = index % 251
    end
    return ffi.string(buffer, size)
end

-- W1: a small call's round trip, measured over batches because the guest's
-- page clock moves in whole milliseconds.
function workloads.latency(options)
    local batch = options.batch or 50
    local batches = options.batches or 30
    local wall, cpu = {}, {}
    for _ = 1, 3 do
        host.call("test.ping", 16)
    end
    for index = 1, batches do
        local started, startedCpu = time.now(), os.clock()
        for _ = 1, batch do
            host.call("test.ping", 16)
        end
        wall[index] = (time.now() - started) / batch
        cpu[index] = (os.clock() - startedCpu) * 1000 / batch
    end
    local profile = {}
    for name, seconds in pairs(rawget(_G, "__nuppEffectsProfile") or {}) do
        profile[name] = seconds * 1000 / (batch * batches + 3)
    end
    return {samples = {wallMs = wall, cpuMs = cpu}, summary = {wallMs = summarize(wall), cpuMs = summarize(cpu), profileMsPerCall = profile}}
end

-- W5 and its parts: back-to-back frames, each taking the frame's input from the
-- page in one call and posting its render packet, against the same loop with the
-- channel left out. A frame always costs one round trip, because the input call
-- waits for the page.
function workloads.frames(options)
    local frames = options.frames or 300
    local events = options.events or 17
    local packetBytes = options.packetBytes or 0
    local assetEvery = options.assetEvery or 0
    local stub = options.stub == true
    local post = host.bindPost("bench.packet")
    local packetText = bytes(packetBytes)
    local packet = span.fromString(packetText)
    local wall, cpu = {}, {}
    for frame = 1, frames + 10 do
        local started, startedCpu = time.now(), os.clock()
        if stub then
            time.sleep(0)
        else
            local received = select("#", host.call("bench.input", events))
            assert(received >= 1, "no input")
            if packetBytes > 0 then
                post(packet)
            end
            if assetEvery > 0 and frame % assetEvery == 0 then
                host.call("test.echo", "asset.png", 512, 512)
            end
        end
        if frame > 10 then
            wall[frame - 10] = time.now() - started
            cpu[frame - 10] = (os.clock() - startedCpu) * 1000
        end
    end
    local profile = {}
    for name, seconds in pairs(rawget(_G, "__nuppEffectsProfile") or {}) do
        profile[name] = seconds * 1000 / (frames + 10)
    end
    return {samples = {wallMs = wall, cpuMs = cpu}, summary = {wallMs = summarize(wall), cpuMs = summarize(cpu), profileMsPerFrame = profile}}
end

-- W2, W4 and W5 as a game frame would use the channel: the frame's tick and its
-- render packet go out on streams, and the page answers each tick by pushing
-- that frame's pointer events, which arrive routed to a bus at the next turn.
-- `time.sleep(0)` is the frame boundary, the one round trip a frame costs.
function workloads.streamFrames(options)
    local hostevents = require("hostevents")
    local events = require("nupp.events")
    local frames = options.frames or 300
    local eventCount = options.events or 17
    local packetBytes = options.packetBytes or 0
    local assetEvery = options.assetEvery or 0
    local stub = options.stub == true
    local bus = events.newMessageBus()
    local received = 0
    bus:observe(1, hostevents.PointerMove, function(_)
        received = received + 1
    end, "bench")
    local route = not stub and host.route("bench.move", hostevents.PointerMove, bus, 1, options.inputPolicy or "dropOldest", 256) or nil
    local tick = host.bindSend("bench.frame", "latest")
    local post = host.bindSend("bench.packet", "latest")
    local packetText = bytes(packetBytes)
    local packet = span.fromString(packetText)
    local wall, cpu = {}, {}
    for frame = 1, frames + 10 do
        local started, startedCpu = time.now(), os.clock()
        if not stub then
            tick(eventCount)
            if packetBytes > 0 then
                post(packet)
            end
            if assetEvery > 0 and frame % assetEvery == 0 then
                host.call("test.echo", "asset.png", 512, 512)
            end
        end
        time.sleep(0)
        if frame > 10 then
            wall[frame - 10] = time.now() - started
            cpu[frame - 10] = (os.clock() - startedCpu) * 1000
        end
    end
    if route ~= nil then
        route:close()
    end
    return {
        samples = {wallMs = wall, cpuMs = cpu},
        summary = {wallMs = summarize(wall), cpuMs = summarize(cpu), eventsReceived = received, profileMsPerFrame = (function()
            local profile = {}
            for name, seconds in pairs(rawget(_G, "__nuppEffectsProfile") or {}) do
                profile[name] = seconds * 1000 / (frames + 10)
            end
            return profile
        end)()},
    }
end

-- W2, W4 and W5 with the channel as the frame boundary itself, as a game would
-- use it: each frame waits on one call for the next frame, the page pushes that
-- frame's pointer events beside its answer, and the packet goes out on a stream.
function workloads.channelFrames(options)
    local hostevents = require("hostevents")
    local events = require("nupp.events")
    local frames = options.frames or 300
    local eventCount = options.events or 17
    local packetBytes = options.packetBytes or 0
    local assetEvery = options.assetEvery or 0
    local bus = events.newMessageBus()
    local received = 0
    bus:observe(1, hostevents.PointerMove, function(_)
        received = received + 1
    end, "bench")
    local route = host.route("bench.move", hostevents.PointerMove, bus, 1, options.inputPolicy or "dropOldest", 256)
    local nextFrame = host.bind("bench.tick")
    local post = host.bindSend("bench.packet", "latest")
    local packetText = bytes(packetBytes)
    local packet = span.fromString(packetText)
    local wall, cpu = {}, {}
    for frame = 1, frames + 10 do
        local started, startedCpu = time.now(), os.clock()
        if packetBytes > 0 then
            post(packet)
        end
        if assetEvery > 0 and frame % assetEvery == 0 then
            host.call("test.echo", "asset.png", 512, 512)
        end
        nextFrame(eventCount)
        if frame > 10 then
            wall[frame - 10] = time.now() - started
            cpu[frame - 10] = (os.clock() - startedCpu) * 1000
        end
    end
    route:close()
    local profile = {}
    for name, seconds in pairs(rawget(_G, "__nuppEffectsProfile") or {}) do
        profile[name] = seconds * 1000 / (frames + 10)
    end
    return {
        samples = {wallMs = wall, cpuMs = cpu},
        summary = {wallMs = summarize(wall), cpuMs = summarize(cpu), eventsReceived = received, profileMsPerFrame = profile},
    }
end

-- W3b: bulk bytes in both directions, chunked by the channel.
function workloads.bulk(options)
    local size = options.size or 4 * 1024 * 1024
    local repeats = options.repeats or 5
    local upload, download = {}, {}
    local text = bytes(size)
    local view = span.fromString(text)
    local length = host.bind("test.len")
    for index = 1, repeats do
        local started = time.now()
        assert(length(view) == size)
        upload[index] = time.now() - started
        started = time.now()
        local made = host.call("test.make", size, 3)
        local _, count = made:ref()
        assert(count == size)
        download[index] = time.now() - started
    end
    return {
        samples = {uploadMs = upload, downloadMs = download},
        summary = {uploadMs = summarize(upload), downloadMs = summarize(download), bytes = size},
    }
end

-- What one host request's JSON costs the guest, apart from everything else:
-- encoding a call, and decoding an answer of a few values, as the effect layer
-- does, against packing the same values into bytes with the FFI.
function workloads.codecCost(options)
    local json = require("nupp.runtime.provider.lunajson")
    local repeats = options.repeats or 2000
    local request = {op = "call", name = "app.input", n = 2, v = {["1"] = 17, ["2"] = "frame"}, id = 12, kind = "host"}
    local answerText = json.encode({responses = {{id = 12, ok = true, value = {n = 3, v = {["1"] = 1.5, ["2"] = 2.5, ["3"] = "x"}}}}})
    local started = os.clock()
    for _ = 1, repeats do
        json.encode(request)
    end
    local encodeMs = (os.clock() - started) * 1000 / repeats
    started = os.clock()
    for _ = 1, repeats do
        json.decode(answerText)
    end
    local decodeMs = (os.clock() - started) * 1000 / repeats
    local buffer = ffi.new("uint8_t[256]")
    started = os.clock()
    for index = 1, repeats do
        local doubles = ffi.cast("double *", buffer + 8)
        ffi.cast("uint32_t *", buffer)[0] = 12
        ffi.cast("uint32_t *", buffer)[1] = 2
        doubles[0] = 17
        doubles[1] = index
    end
    local binaryMs = (os.clock() - started) * 1000 / repeats
    return {samples = {}, summary = {encodeMs = encodeMs, decodeMs = decodeMs, binaryMs = binaryMs}}
end

return workloads
