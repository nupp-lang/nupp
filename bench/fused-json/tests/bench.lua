-- Throughput of the fused JSON decoder against Lunajson.
--
-- What is measured is `decodeEager`, the entry `nupp.codec.json.decode`
-- reaches through its provider: the vector scan, the structural tape, and the
-- eager materialization into ordinary Lua values. The public codec is not in
-- the loop, so the numbers are the decoder's rather than the dispatch's.
--
-- Lunajson is the reference column. It is the pure-Lua decoder this repository
-- already vendors, it is in the same process on the same payloads, and it is
-- what says whether a difference between two runs is the decoder or the
-- machine.
--
-- Protocol, following `bench/simd-json/README.md`: implementations alternate
-- inside every sample rather than one implementation running all its samples
-- first, so drift is shared. A full collection runs before each timed
-- implementation and collection stays enabled during it, which keeps
-- reclamation in the measurement without letting one implementation inherit
-- the other's allocation debt. Results are consumed, because a decoder that
-- builds Lua values cannot avoid building them and a benchmark that discards
-- them lets the JIT decide otherwise.

local ok, fused = pcall(require, "nupp.codec.json.internal.decoder.fusedbench")
if not ok then
    io.stderr:write("bench: the compiled decoder is not on the path; run ./run.sh\n")
    io.stderr:write(tostring(fused) .. "\n")
    os.exit(1)
end
local newDecoder = require("nupp.runtime.vendor.lunajson.decoder")
local lunajson = newDecoder()

local ARRAY_MARKER, OBJECT_MARKER = {}, {}

----------------------------------------------------------------------------
-- Proving the compiled decoder is what runs
----------------------------------------------------------------------------

-- Three independent facts, because the failure this guards against is silent:
-- a dependency module in a `kind = "modules"` project gets no ahead-of-time
-- replacement, the authored body runs interpreted, and the benchmark reports a
-- number for something nobody meant to measure.
--
--  1. the artifact `require` loaded carries the generated binding and no
--     longer carries the authored scan,
--  2. the ahead-of-time registry exists and holds the replacements,
--  3. the registered builders are C functions out of the compiled object.
local function proveCompiled(decoder, artifactPath)
    local proof = {}

    local path = assert(
        artifactPath
        or package.searchpath and package.searchpath("nupp.codec.json.internal.decoder.fusedbench", package.path)
        or "build/nupp/codec/json/internal/decoder/fusedbench.lua",
        "cannot locate the loaded decoder artifact"
    )
    local handle = assert(io.open(path, "rb"), "cannot read " .. path)
    local artifact = handle:read("*a")
    handle:close()
    proof.artifact = path
    proof.artifactBytes = #artifact
    assert(
        artifact:find("ks___nupp_const_decode_fused", 1, true),
        "the loaded artifact carries no generated binding: the decoder was not compiled ahead of time"
    )
    assert(artifact:find("__nuppAotCompiled", 1, true), "the loaded artifact records no ahead-of-time replacement")
    assert(not artifact:find("local species = ", 1, true), "the loaded artifact still carries the authored scan body")

    local registry = rawget(_G, "__nuppAotCompiled")
    assert(type(registry) == "table", "no ahead-of-time replacement registry exists")
    local replacements = 0
    for _ in pairs(registry) do
        replacements = replacements + 1
    end
    assert(replacements > 0, "the replacement registry is empty")
    proof.replacements = replacements

    local modules = rawget(_G, "__nuppAotBuilderModules")
    assert(type(modules) == "table", "no compiled builder was registered")
    local builders, object = 0, nil
    for key, registered in pairs(modules) do
        object = object or tostring(key):match("^(.-)%z") or tostring(key)
        for name, value in pairs(registered) do
            assert(
                type(value) == "function" and debug.getinfo(value, "S").what == "C",
                "registered builder " .. tostring(name) .. " is not a C function"
            )
            builders = builders + 1
        end
    end
    assert(builders > 0, "no compiled builder entry was registered")
    proof.builders = builders
    proof.object = object

    -- Observe the actual call. Ownership helpers may live in tables, so an
    -- upvalue walk cannot prove which native entry this export executes.
    local registeredEntry, nativeEntry = false, false
    proof.nativeEntries = {}
    local nativeFunctions = {}
    for key, registered in pairs(modules) do
        for _, fn in pairs(registered) do
            nativeFunctions[fn] = tostring(key):match("^(.-)%z") or tostring(key)
        end
    end
    local wasEnabled = jit.status()
    jit.off()
    debug.sethook(
        function()
            local frame = debug.getinfo(2, "fS")
            if frame then
                registeredEntry = registeredEntry or (registry[frame.func] and frame.source == "@" .. path)
                if nativeFunctions[frame.func] then
                    nativeEntry = true
                    proof.nativeEntries[frame.func] = true
                    proof.object = nativeFunctions[frame.func]
                end
            end
        end,
        "c"
    )
    local value, status = decoder.decodeEager('["native proof",123]', nil, ARRAY_MARKER, OBJECT_MARKER)
    debug.sethook()
    if wasEnabled then
        jit.on()
    end
    assert(status == 0 and value[1] == "native proof" and value[2] == 123, "native proof decode failed")
    assert(registeredEntry and nativeEntry, "the measured export did not execute its registered native builder")

    return proof
end

----------------------------------------------------------------------------
-- Corpora
----------------------------------------------------------------------------

-- Deterministic, so two checkouts measure the same bytes and a result file can
-- name the payload by digest rather than by description.
local function seeded(seed)
    local state = seed
    return function(n)
        state = (state * 1103515245 + 12345) % 2147483648
        return state % n
    end
end

local function repeatTo(build, bytes)
    local parts, total = {}, 0
    local index = 0
    while total < bytes do
        index = index + 1
        local piece = build(index)
        parts[#parts + 1] = piece
        total = total + #piece + 1
    end

    return "[" .. table.concat(parts, ",") .. "]"
end

local TARGET = 2 * 1024 * 1024
-- Increase timed work without changing the corpus or its digest.
local BATCH_BYTES = tonumber(os.getenv("NUPP_FUSED_BENCH_BATCH_BYTES")) or TARGET
assert(BATCH_BYTES >= TARGET, "benchmark batches must cover at least the default byte count")
local ONLY_PAYLOAD = os.getenv("NUPP_FUSED_BENCH_PAYLOAD")

local corpora = {}

-- Dense records: many small objects, mixed scalar members, the shape a log or
-- an API response has.
do
    local next_ = seeded(7)
    corpora[#corpora + 1] = {
        name = "records",
        what = "dense record objects, mixed scalars",
        source = repeatTo(
            function(index)
                return string.format(
                    '{"id":%d,"name":"user%d","score":%d.%02d,"active":%s,"tags":["a","b"],"rank":%d}',
                    index,
                    next_(100000),
                    next_(1000),
                    next_(100),
                    next_(2) == 1 and "true" or "false",
                    next_(64)
                )
            end,
            TARGET
        ),
    }
end

-- ASCII strings: almost every byte is inside a string value and none of them
-- needs escaping or continuation handling.
do
    local next_ = seeded(11)
    local alphabet = "abcdefghijklmnopqrstuvwxyz ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    corpora[#corpora + 1] = {
        name = "ascii",
        what = "plain ASCII string values",
        source = repeatTo(
            function()
                local bytes = {}
                for position = 1, 96 do
                    local at = next_(#alphabet) + 1
                    bytes[position] = alphabet:sub(at, at)
                end

                return '"' .. table.concat(bytes) .. '"'
            end,
            TARGET
        ),
    }
end

-- Multi-byte UTF-8: two, three and four byte sequences, which is the input
-- class a scalar validator walks byte by byte and a vector validator does not.
do
    local next_ = seeded(13)
    local glyphs = {
        "\195\169",
        "\195\188",
        "\194\169",
        "\208\180", -- two bytes
        "\230\151\165",
        "\228\184\173",
        "\226\130\172", -- three bytes
        "\240\159\142\137",
        "\240\159\154\128", -- four bytes
        "a",
        "b",
        " ",
    }
    corpora[#corpora + 1] = {
        name = "unicode",
        what = "multi-byte UTF-8 string values",
        source = repeatTo(
            function()
                local bytes = {}
                for position = 1, 48 do
                    bytes[position] = glyphs[next_(#glyphs) + 1]
                end

                return '"' .. table.concat(bytes) .. '"'
            end,
            TARGET
        ),
    }
end

-- Deep nesting: the tape walk crosses a container boundary far more often than
-- it consumes a scalar, and the builder's frame depth is what is exercised.
do
    local depth = 24
    local leaf = '{"v":1,"w":[1,2,3]}'
    local unit = leaf
    for _ = 1, depth do
        unit = '{"n":[' .. unit .. "," .. unit .. "]}"
        if #unit > 4096 then
            break
        end
    end
    corpora[#corpora + 1] = {
        name = "nested",
        what = "deeply nested containers",
        source = repeatTo(
            function()
                return unit
            end,
            TARGET
        ),
    }
end

-- A small payload, where nothing amortizes and the per-call cost is the whole
-- measurement.
corpora[
    #corpora + 1
] = {name = "small", what = "one 30-byte object per call", source = '{"id":41,"name":"Nupp","ok":1}',}

-- Cheap, stable, and enough to say two checkouts fed the same bytes.
local function digest(text)
    local hash = 2166136261
    for position = 1, #text do
        hash = hash ~ text:byte(position)
        hash = (hash * 16777619) % 4294967296
    end

    return string.format("fnv1a32:%08x", hash)
end

----------------------------------------------------------------------------
-- Measurement
----------------------------------------------------------------------------

local function decodeFused(source)
    local value, status = fused.decodeEager(source, nil, ARRAY_MARKER, OBJECT_MARKER)
    if status ~= 0 then
        error("fused decode refused the payload: status " .. tostring(status), 0)
    end

    return value
end

local function decodeLunajson(source)
    return lunajson(source)
end

local implementations = {{name = "fused", run = decodeFused}, {name = "lunajson", run = decodeLunajson},}

-- One timed batch: repeat the fixed payload to reach the requested byte
-- budget, so a fast decoder is not timed against the clock's resolution.
local function batchFor(source, implementation)
    -- The pure Lua control already takes milliseconds on these corpora.
    local bytes = implementation == "lunajson" and TARGET or BATCH_BYTES
    return math.max(1, math.floor(bytes / #source + 0.5))
end

-- Each implementation gets a separately loaded loop prototype: a tracing
-- failure in one decoder must not blacklist the others' timing loop.
local function makeTimer(run)
    return assert(
        loadstring(
            [[
        local run = ...
        return function(source, batch)
            collectgarbage("collect")
            local sink = 0
            local started = os.clock()
            for _ = 1, batch do
                local value = run(source)
                sink = sink + (type(value) == "table" and 1 or 0)
            end
            local elapsed = os.clock() - started
            assert(sink == batch, "decoder did not produce the expected arrays or objects")
            return elapsed
        end
    ]],
            "fused-json-independent-timing-loop"
        )
    )(run)
end

local function median(values)
    local sorted = {}
    for position, value in ipairs(values) do
        sorted[position] = value
    end
    table.sort(sorted)
    local count = #sorted
    if count % 2 == 1 then
        return sorted[(count + 1) / 2]
    end

    return (sorted[count / 2] + sorted[count / 2 + 1]) / 2
end

local function loadAverages()
    local handle = io.popen("uptime")
    if not handle then
        return "unavailable"
    end
    local text = handle:read("*a") or ""
    handle:close()

    -- `.` matches a newline in a Lua pattern, so the capture takes `uptime`'s
    -- trailing one with it and `%q` writes it as an escaped line break, which
    -- is not JSON.
    local averages = text:match("load averages?: *([^\n]+)") or text

    return (averages:gsub("%s+$", ""))
end

----------------------------------------------------------------------------
-- Run
----------------------------------------------------------------------------

local samples = tonumber(arg and arg[1]) or 15
local warmups = 3

local proof = proveCompiled(fused)
local baselineProof
local baselineRoot = os.getenv("NUPP_FUSED_BASELINE")
if baselineRoot then
    local module = "nupp.codec.json.internal.decoder.fusedbench"
    local oldPath, oldModule = package.path, package.loaded[module]
    local path = baselineRoot .. "/nupp/codec/json/internal/decoder/fusedbench.lua"
    package.path = baselineRoot .. "/?.lua;" .. baselineRoot .. "/?/init.lua;" .. oldPath
    local baseline = assert(loadfile(path))()
    package.path, package.loaded[module] = oldPath, oldModule
    baselineProof = proveCompiled(baseline, path)
    for entry in pairs(proof.nativeEntries) do
        assert(not baselineProof.nativeEntries[entry], "candidate and baseline reach the same native builder")
    end
    implementations[#implementations + 1] = {
        name = "baseline",
        run = function(source)
            local value, status = baseline.decodeEager(source, nil, ARRAY_MARKER, OBJECT_MARKER)
            if status ~= 0 then
                error("baseline refused the payload: status " .. tostring(status), 0)
            end

            return value
        end
    }
    io.write("baseline compiled decoder: " .. baselineProof.artifact .. "\n")
end
for _, implementation in ipairs(implementations) do
    implementation.time = makeTimer(implementation.run)
end
io.write("compiled decoder proof\n")
io.write(string.format("  artifact       %s (%d bytes)\n", proof.artifact, proof.artifactBytes))
io.write(string.format("  replacements   %d\n", proof.replacements))
io.write(string.format("  native entries %d C functions registered\n", proof.builders))
io.write("\n")

local loadBefore = loadAverages()
io.write(string.format("load averages before: %s\n", loadBefore))
io.write(
    string.format(
        "samples: %d, warmups: %d, about %.1f MiB per native batch (control 2 MiB)\n\n",
        samples,
        warmups,
        BATCH_BYTES / 1048576
    )
)

if ONLY_PAYLOAD then
    local selected = {}
    for _, payload in ipairs(corpora) do
        if payload.name == ONLY_PAYLOAD then
            selected[#selected + 1] = payload
        end
    end
    assert(#selected == 1, "unknown benchmark payload: " .. ONLY_PAYLOAD)
    corpora = selected
end

local report = {}
for _, payload in ipairs(corpora) do
    local batch = batchFor(payload.source)
    local moved = batch * #payload.source
    local times = {}
    for _, implementation in ipairs(implementations) do
        times[implementation.name] = {}
    end

    for _ = 1, warmups do
        for _, implementation in ipairs(implementations) do
            local implementationBatch = batchFor(payload.source, implementation.name)
            implementation.time(payload.source, math.max(1, math.floor(implementationBatch / 4)))
        end
    end

    for sample = 1, samples do
        -- Alternate, and rotate which implementation leads, so neither one is
        -- always the first thing a fresh collection sees.
        local order = {}
        for offset = 0, #implementations - 1 do
            order[#order + 1] = (sample + offset - 1) % #implementations + 1
        end
        for _, position in ipairs(order) do
            local implementation = implementations[position]
            local implementationBatch = batchFor(payload.source, implementation.name)
            local elapsed = implementation.time(payload.source, implementationBatch)
            local rates = times[implementation.name]
            rates[#rates + 1] = implementationBatch * #payload.source / elapsed / 1e6
        end
    end

    local row = {
        payload = payload.name,
        what = payload.what,
        bytes = #payload.source,
        digest = digest(payload.source),
        batch = batch,
        movedBytes = moved,
        rates = {},
    }
    for _, implementation in ipairs(implementations) do
        local rates = times[implementation.name]
        local sorted = {}
        for position, rate in ipairs(rates) do
            sorted[position] = rate
        end
        table.sort(sorted)
        row.rates[
            implementation.name
        ] = {
            median = median(rates),
            low = sorted[1],
            high = sorted[#sorted],
            samples = rates,
            batch = batchFor(payload.source, implementation.name),
        }
    end
    row.ratio = row.rates.fused.median / row.rates.lunajson.median
    if baselineProof then
        row.baselineRatio = row.rates.fused.median / row.rates.baseline.median
    end
    report[#report + 1] = row

    io.write(string.format("%-9s %9d bytes  %s\n", row.payload, row.bytes, row.digest))
    for _, implementation in ipairs(implementations) do
        local rate = row.rates[implementation.name]
        io.write(
            string.format(
                "  %-9s median %8.1f MB/s   min %8.1f   max %8.1f\n",
                implementation.name,
                rate.median,
                rate.low,
                rate.high
            )
        )
    end
    io.write(string.format("  fused / lunajson  %.2fx\n", row.ratio))
    if baselineProof then
        io.write(string.format("  fused / baseline  %.3fx\n", row.baselineRatio))
    end
    io.write("\n")
end

local loadAfter = loadAverages()
io.write(string.format("load averages after: %s\n", loadAfter))

local out = os.getenv("NUPP_FUSED_BENCH_OUTPUT")
if out then
    local handle = assert(io.open(out, "w"))
    handle:write("{\n")
    handle:write(string.format("  %q: %q,\n", "loadBefore", loadBefore))
    handle:write(string.format("  %q: %q,\n", "loadAfter", loadAfter))
    handle:write(string.format("  %q: %d,\n", "samples", samples))
    handle:write(string.format("  %q: %q,\n", "artifact", proof.artifact))
    handle:write(string.format("  %q: %q,\n", "object", proof.object))
    if baselineProof then
        handle:write(string.format("  %q: %q,\n", "baselineArtifact", baselineProof.artifact))
        handle:write(string.format("  %q: %q,\n", "baselineObject", baselineProof.object))
    end
    handle:write("  \"payloads\": [\n")
    for index, row in ipairs(report) do
        handle:write(
            string.format(
                "    {\"payload\": %q, \"bytes\": %d, \"digest\": %q, \"batch\": %d,\n",
                row.payload,
                row.bytes,
                row.digest,
                row.batch
            )
        )
        for _, implementation in ipairs(implementations) do
            local rate = row.rates[implementation.name]
            handle:write(
                string.format(
                    "     \"%s\": {\"median\": %.3f, \"min\": %.3f, \"max\": %.3f, \"batch\": %d, \"samples\": [",
                    implementation.name,
                    rate.median,
                    rate.low,
                    rate.high,
                    rate.batch
                )
            )
            for position, value in ipairs(rate.samples) do
                handle:write(string.format("%s%.3f", position > 1 and ", " or "", value))
            end
            handle:write("]},\n")
        end
        handle:write(string.format("     \"ratio\": %.4f}%s\n", row.ratio, index < #report and "," or ""))
    end
    handle:write("  ]\n}\n")
    handle:close()
end
