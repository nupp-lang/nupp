local traversal = require("traversal")
local json = require("nupp.codec.json")
local util = require("jit.util")
local aborts = {}
jit.attach(
    function(event, trace, func, pc, reason)
        if event == "abort" then
            local key = tostring(reason)
            aborts[key] = (aborts[key] or 0) + 1
        end
    end,
    "trace"
)
local variants = {"callbacks", "specialized", "cursor", "interpreter", "generated", "direct"}
local variantFilter = os.getenv("NUPP_SERDE_VARIANT")
if variantFilter then
    local selected = {}
    for _, variant in ipairs(variants) do
        if variant == variantFilter then
            selected[#selected + 1] = variant
        end
    end
    assert(#selected == 1, "unknown variant filter")
    variants = selected
end
local offset = arg[1] == "--" and 1 or 0
local samples = tonumber(arg[1 + offset]) or 7
local target = tonumber(arg[2 + offset]) or 0.02
assert(samples >= 1 and target > 0)
io.stderr:write(("Traversal controls: %d samples, %.3fs calibration target\n"):format(samples, target))
local cases, preparation = {}, {}
local retainedOperations = {}
local blackhole = 0
local sources = {}
for index = 1, 32 do
    sources[index] = traversal.makeValue(17 + (index - 1) * 19)
end
local source = sources[1]
-- Load the selected syntax provider before clearing compiler/startup traces.
-- Operation construction is measured later, separately for every variant.
do
    local ready = traversal.buildOperation(traversal.loadModel(3, false, "ready_"), "direct")
    local bytes = ready:encode(source, true)
    assert(ready:checksum(ready:decode(bytes)) == ready:checksum(source))
end
jit.flush()
aborts = {}

local function median(values)
    local sorted = {}
    for i, value in ipairs(values) do
        sorted[i] = value
    end
    table.sort(sorted)

    return sorted[math.floor((#sorted + 1) / 2)]
end

local function snapshot()
    collectgarbage("collect")
    local result = {traces = 0, irInstructions = 0, machineBytes = 0, retainedKiB = collectgarbage("count")}
    for index = 1, 100000 do
        local info = util.traceinfo(index)
        if info then
            result.traces = result.traces + 1
            result.irInstructions = result.irInstructions + info.nins
            local code = util.tracemc(index)
            result.machineBytes = result.machineBytes + (code and #code or 0)
        end
    end

    return result
end

local function loopFor(mode, operations, bytes, tokens, mixed)
    local body
    if mode == "encode" then
        body = "local bytes,total=op:encode(value,true); checksum=checksum+#bytes+total"
    elseif mode == "emit" then
        body = "local _,total=op:encode(value,false); checksum=checksum+total"
    elseif mode == "decode" then
        body = "local value=op:decode(bytes[index][valueIndex]); checksum=checksum+op:checksum(value)"
    else
        body = "local value=op:decode('',tokens[index][valueIndex]); checksum=checksum+op:checksum(value)"
    end
    local choose = mixed and "local index=(iteration-1)%#operations+1" or "local index=1"
    local code = "return function(operations,bytes,tokens,sources) return function(iterations) local checksum=0; "
        .. "for iteration=1,iterations do "
        .. choose
        .. "; local valueIndex=math.floor((iteration-1)/#operations)%#sources+1; local value=sources[valueIndex]; local op=operations[index]; "
        .. body
        .. " end; return checksum end end"

    return assert(loadstring(code, "=serde-benchmark-loop"))()(operations, bytes, tokens, sources)
end

local function measure(run, iterations)
    local started = os.clock()
    blackhole = blackhole + run(iterations)
    return os.clock() - started
end

local baseline = snapshot()
local layouts = {
    {name = "threeRecordMembers", count = 3, indexed = false},
    {name = "twelveRecordMembers", count = 12, indexed = false},
    {name = "threeIndexedMembers", count = 3, indexed = true},
    {name = "twelveIndexedMembers", count = 12, indexed = true},
    {name = "mixedModels", mixed = true, models = 16},
    {name = "manyModels", mixed = true, models = 128},
}
for _, layout in ipairs(layouts) do
    local models = {}
    for index = 1, layout.models or 1 do
        models[
            index
        ] = traversal.loadModel(
            layout.count or (index % 2 == 0 and 3 or 12),
            layout.indexed == nil and index % 3 == 0 or layout.indexed == true,
            "model" .. index .. "_"
        )
    end
    for _, variant in ipairs(variants) do
        local operations, bytes, tokens = {}, {}, {}
        local cold = {layout = layout.name, variant = variant, buildNanoseconds = {}, generatedBytes = 0}
        for index, model in ipairs(models) do
            local started = os.clock()
            local op = traversal.buildOperation(model, variant)
            operations[index] = op
            cold.buildNanoseconds[#cold.buildNanoseconds + 1] = (os.clock() - started) * 1e9
            cold.generatedBytes = cold.generatedBytes + op.generatedBytes
            local encoded, checksum = op:encode(source, true)
            local reference = traversal.buildOperation(model, "direct")
            local expected, expectedChecksum = reference:encode(source, true)
            assert(encoded == expected and checksum == expectedChecksum)
            local decoded = op:decode(encoded)
            assert(op:checksum(decoded) == checksum)
            local raw = {}
            for field = 1, #model.members do
                raw[field] = 16 + field
            end
            assert(op:checksum(op:decode("", raw)) == checksum)
            local unknown = encoded:sub(1, -2) .. ',"future":{"nested":[null,1,true]}}'
            assert(op:checksum(op:decode(unknown)) == checksum)
            local reversed = {}
            for field = #model.members, 1, -1 do
                reversed[#reversed + 1] = op.description.members[field].key .. ":" .. raw[field]
            end
            assert(op:checksum(op:decode("{" .. table.concat(reversed, ",") .. "}")) == checksum)
            for _, invalid in ipairs({
                "{}",
                encoded .. "garbage",
                encoded:sub(1, -2) .. ",}",
                "{" .. op.description.members[1].key .. ":1," .. op.description.members[1].key .. ":2}"
            }) do
                assert(not pcall(op.decode, op, invalid), "invalid input accepted by " .. variant)
            end
            operations[index], bytes[index], tokens[index] = op, {}, {}
            for valueIndex, varied in ipairs(sources) do
                local expectedBytes, expectedTotal = reference:encode(varied, true)
                local actualBytes, actualTotal = op:encode(varied, true)
                assert(actualBytes == expectedBytes and actualTotal == expectedTotal)
                assert(op:checksum(op:decode(expectedBytes)) == expectedTotal)
                local scalars = {}
                for field = 1, #model.members do
                    scalars[field] = varied.slots[field]
                end
                assert(op:checksum(op:decode("", scalars)) == expectedTotal)
                bytes[index][valueIndex], tokens[index][valueIndex] = expectedBytes, scalars
            end
        end
        cold.repeatedBuildNanoseconds = {}
        for sample = 1, samples do
            local started = os.clock()
            for iteration = 1, 32 do
                local fresh = traversal.buildOperation(models[(iteration - 1) % #models + 1], variant)
                retainedOperations[iteration] = fresh
            end
            cold.repeatedBuildNanoseconds[sample] = (os.clock() - started) * 1e9 / 32
            -- Every operation escapes into an existing table before the clock
            -- stops. Exercise both directions afterward so cold construction
            -- cannot disappear through dead allocation or result elimination.
            for iteration = 1, 32 do
                local fresh = retainedOperations[iteration]
                local modelIndex = (iteration - 1) % #models + 1
                local encoded, total = fresh:encode(source, true)
                assert(encoded == bytes[modelIndex][1])
                assert(fresh:checksum(fresh:decode(encoded)) == total)
                blackhole = blackhole + total
                retainedOperations[iteration] = nil
            end
        end
        preparation[#preparation + 1] = cold
        for _, mode in ipairs({"emit", "encode", "assign", "decode"}) do
            local run = loopFor(mode, operations, bytes, tokens, layout.mixed)
            local iterations = 32
            local started = os.clock()
            while measure(run, iterations) < target do
                iterations = iterations * 2
            end
            cases[
                #cases + 1
            ] = {
                layout = layout.name,
                variant = variant,
                mode = mode,
                iterations = iterations,
                warmupNanoseconds = (os.clock() - started) * 1e9,
                run = run,
                nanoseconds = {}
            }
        end
    end
end
local warmed = snapshot()
for sample = 1, samples do
    for step = 1, #cases do
        local index = sample % 2 == 0 and #cases - step + 1 or step
        local case = cases[index]
        case.nanoseconds[sample] = measure(case.run, case.iterations) * 1e9 / case.iterations
    end
end
local report = {
    scope = "Flat 3/12 selected integer members over twelve-member record/indexed carriers; not the complete S0 semantic matrix",
    runtime = jit.version,
    jitEnabled = jit.status(),
    jitCapacity = os.getenv("NUPP_JIT_LIMITS")
    or (
        os.getenv("NUPP_JIT_DEFAULT") and "LuaJIT defaults"
        or "maxtrace=20000,maxside=1000,sizemcode=16384,maxmcode=16384"
    ),
    architecture = jit.arch,
    os = jit.os,
    variantFilter = variantFilter,
    valuesPerModel = #sources,
    samples = samples,
    targetSeconds = target,
    preparation = preparation,
    jitAborts = aborts,
    baseline = baseline,
    warmed = warmed,
    final = snapshot(),
    cases = {}
}
for _, case in ipairs(cases) do
    case.run = nil
    case.medianNanoseconds = median(case.nanoseconds)
    report.cases[#report.cases + 1] = case
end
assert(blackhole > 0)
print(json.encode(report))
