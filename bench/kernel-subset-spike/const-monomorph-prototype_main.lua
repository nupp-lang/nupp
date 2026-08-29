-- Differential and paired timing for the dynamic ceiling fixture and the body
-- emitted by the experimental const-specialization discovery pass.
local ffi = require("ffi")

local here = assert(debug.getinfo(1, "S").source:match("^@(.*[/\\])"))
local now = dofile(here .. "wallclock.lua")
local ceilingOut = here .. "build/const-monomorph-ceiling/"
local prototypeOut = here .. "build/const-monomorph-prototype/"

local symbolFile = assert(io.open(prototypeOut .. "symbol.txt", "rb"))
local symbol = assert(symbolFile:read("*l"))
assert(symbolFile:close())

ffi.cdef [[
void ks_general(double *output, const double *input,
    double first, double last, double rounds, size_t count);
]]
ffi.cdef(([[
void %s(double *output, const double *input,
    double first, double last, double rounds, size_t count);
void %s_forced_scalar(double *output, const double *input,
    double first, double last, double rounds, size_t count);
]]):format(symbol, symbol))

local suffix = jit.os == "OSX" and ".dylib" or ".so"
local ceiling = ffi.load(ceilingOut .. "libconst-monomorph-ceiling" .. suffix)
local prototype = ffi.load(prototypeOut .. "libconst-monomorph-prototype" .. suffix)
local specialized = prototype[symbol]
local specializedScalar = prototype[symbol .. "_forced_scalar"]

local function input(count)
    local values = ffi.new("double[?]", math.max(count, 1))
    for index = 0, count - 1 do
        values[index] = (index % 251) * 0.03125 - 3.0
    end
    return values
end

for _, count in ipairs({0, 1, 3, 4, 5, 7, 8, 33, 1000}) do
    local source = input(count)
    local dynamic = ffi.new("double[?]", math.max(count, 1))
    local automatic = ffi.new("double[?]", math.max(count, 1))
    local scalar = ffi.new("double[?]", math.max(count, 1))
    ceiling.ks_general(dynamic, source, 1, count, 4, count)
    specialized(automatic, source, 1, count, 4, count)
    specializedScalar(scalar, source, 1, count, 4, count)
    for index = 0, count - 1 do
        assert(dynamic[index] == automatic[index], "specialized body differs at " .. index)
        assert(dynamic[index] == scalar[index], "specialized scalar body differs at " .. index)
    end
end

local count = tonumber(os.getenv("CONST_MONOMORPH_COUNT") or 1048576)
local source = input(count)
local dynamic = ffi.new("double[?]", count)
local automatic = ffi.new("double[?]", count)
local scalar = ffi.new("double[?]", count)

local function runDynamic()
    ceiling.ks_general(dynamic, source, 1, count, 4, count)
end

local function runSpecialized()
    specialized(automatic, source, 1, count, 4, count)
end

local function runScalar()
    specializedScalar(scalar, source, 1, count, 4, count)
end

local function calibrate(run)
    local passes = 1
    while true do
        local started = now()
        for _ = 1, passes do
            run()
        end
        if now() - started >= 0.1 then
            return passes
        end
        passes = passes * 2
    end
end

local passes = math.max(calibrate(runDynamic), calibrate(runSpecialized), calibrate(runScalar))
local dynamicSamples, specializedSamples, scalarSamples = {}, {}, {}
local ratios, scalarRatios = {}, {}
for sample = 1, 15 do
    local order = sample % 3
    local runs = order == 0 and {runDynamic, runSpecialized, runScalar}
        or order == 1 and {runSpecialized, runScalar, runDynamic}
        or {runScalar, runDynamic, runSpecialized}
    local times = {}
    for position, run in ipairs(runs) do
        local started = now()
        for _ = 1, passes do
            run()
        end
        times[position] = (now() - started) / passes
    end
    local dynamicPosition = order == 0 and 1 or order == 1 and 3 or 2
    local specializedPosition = order == 0 and 2 or order == 1 and 1 or 3
    local scalarPosition = order == 0 and 3 or order == 1 and 2 or 1
    dynamicSamples[sample] = times[dynamicPosition]
    specializedSamples[sample] = times[specializedPosition]
    scalarSamples[sample] = times[scalarPosition]
    ratios[sample] = dynamicSamples[sample] / specializedSamples[sample]
    scalarRatios[sample] = dynamicSamples[sample] / scalarSamples[sample]
end

local function median(values)
    table.sort(values)
    return values[math.floor((#values + 1) / 2)]
end

io.write("differential agrees for tails and the full input\n")
io.write(("dynamic rounds       %10.0f ns\n"):format(median(dynamicSamples) * 1e9))
io.write(("automatic scalar    %10.0f ns\n"):format(median(scalarSamples) * 1e9))
io.write(("automatic lanes     %10.0f ns\n"):format(median(specializedSamples) * 1e9))
io.write(("scalar speedup       %10.3fx\n"):format(median(scalarRatios)))
io.write(("specialized speedup  %10.3fx\n"):format(median(ratios)))
