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
    return {samples = {wallMs = wall, cpuMs = cpu}, summary = {wallMs = summarize(wall), cpuMs = summarize(cpu)}}
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

return workloads
