-- Differential and paired timing for the dynamic body and a manually
-- const-specialized body. The latter is the ceiling an automatic pass can hit.
local ffi = require("ffi")

local here = assert(debug.getinfo(1, "S").source:match("^@(.*[/\\])"))
local now = dofile(here .. "wallclock.lua")
local out = here .. "build/const-monomorph-ceiling/"

ffi.cdef [[
void ks_general(double *output, const double *input,
    double first, double last, double rounds, size_t count);
void ks_rounds4(double *output, const double *input,
    double first, double last, size_t count);
void ks_rounds4_forced_scalar(double *output, const double *input,
    double first, double last, size_t count);
]]

local lib = ffi.load(out .. (jit.os == "OSX" and "libconst-monomorph-ceiling.dylib"
    or "libconst-monomorph-ceiling.so"))

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
    local specialized = ffi.new("double[?]", math.max(count, 1))
    local scalar = ffi.new("double[?]", math.max(count, 1))
    lib.ks_general(dynamic, source, 1, count, 4, count)
    lib.ks_rounds4(specialized, source, 1, count, count)
    lib.ks_rounds4_forced_scalar(scalar, source, 1, count, count)
    for index = 0, count - 1 do
        assert(dynamic[index] == specialized[index], "specialized body differs at " .. index)
        assert(dynamic[index] == scalar[index], "specialized scalar body differs at " .. index)
    end
end

local count = tonumber(os.getenv("CONST_MONOMORPH_COUNT") or 1048576)
local source = input(count)
local dynamic = ffi.new("double[?]", count)
local specialized = ffi.new("double[?]", count)
local scalar = ffi.new("double[?]", count)

local function runDynamic()
    lib.ks_general(dynamic, source, 1, count, 4, count)
end

local function runSpecialized()
    lib.ks_rounds4(specialized, source, 1, count, count)
end

local function runScalar()
    lib.ks_rounds4_forced_scalar(scalar, source, 1, count, count)
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
io.write(("dynamic rounds      %10.0f ns\n"):format(median(dynamicSamples) * 1e9))
io.write(("specialized scalar %10.0f ns\n"):format(median(scalarSamples) * 1e9))
io.write(("specialized rounds4 %10.0f ns\n"):format(median(specializedSamples) * 1e9))
io.write(("scalar speedup      %10.3fx\n"):format(median(scalarRatios)))
io.write(("specialized speedup %10.3fx\n"):format(median(ratios)))
