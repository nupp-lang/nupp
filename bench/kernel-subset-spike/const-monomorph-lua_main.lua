-- Differential and paired timing for the ordinary-Lua source shapes behind
-- the const-monomorphization proposal: a runtime bound, a literal bound that
-- retains its inner loop, and the same four iterations written straight-line.
local ffi = require("ffi")

local here = assert(debug.getinfo(1, "S").source:match("^@(.*[/\\])"))
local now = dofile(here .. "wallclock.lua")
local out = here .. "build/const-monomorph-ceiling/"
package.path = out .. "fallback/?.lua;" .. out .. "fallback/?/init.lua;" .. package.path

local ordinary = require("const-monomorph-ceiling")
local spans = require("nupp.mem.span")

local function input(count)
    local values = ffi.new("double[?]", math.max(count, 1))
    for index = 0, count - 1 do
        values[index] = (index % 251) * 0.03125 - 3.0
    end
    return values
end

local function runDynamicBody(output, source, count)
    local writer = spans.writeCarray(output, count)
    ordinary.general(writer, source, 1, count, 4)
    writer:drop()
end

local function runFixedBody(output, source, count)
    local writer = spans.writeCarray(output, count)
    ordinary.rounds4(writer, source, 1, count)
    writer:drop()
end

local function runUnrolledBody(output, source, count)
    local writer = spans.writeCarray(output, count)
    ordinary.rounds4Unrolled(writer, source, 1, count)
    writer:drop()
end

for _, count in ipairs({0, 1, 3, 4, 5, 7, 8, 33, 1000}) do
    local sourceArray = input(count)
    local source = spans.fromCarray(sourceArray, count)
    local dynamic = ffi.new("double[?]", math.max(count, 1))
    local fixed = ffi.new("double[?]", math.max(count, 1))
    local unrolled = ffi.new("double[?]", math.max(count, 1))
    runDynamicBody(dynamic, source, count)
    runFixedBody(fixed, source, count)
    runUnrolledBody(unrolled, source, count)
    for index = 0, count - 1 do
        assert(dynamic[index] == fixed[index], "literal loop differs at " .. index)
        assert(dynamic[index] == unrolled[index], "unrolled body differs at " .. index)
    end
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

local count = tonumber(os.getenv("CONST_MONOMORPH_COUNT") or 1048576)
local sourceArray = input(count)
local source = spans.fromCarray(sourceArray, count)
local output = ffi.new("double[?]", count)
local shape = arg[1] == "--sample" and arg[2] or nil
local bodies = {
    dynamic = function() runDynamicBody(output, source, count) end,
    fixed = function() runFixedBody(output, source, count) end,
    unrolled = function() runUnrolledBody(output, source, count) end,
}

if shape then
    local run = assert(bodies[shape], "unknown const-monomorph shape " .. tostring(shape))
    local passes = calibrate(run)
    local started = now()
    for _ = 1, passes do
        run()
    end
    io.write(("%.17g\n"):format((now() - started) / passes))
    return
end

-- Give each shape a fresh recorder. When all three hot loops share one LuaJIT
-- process, trace-number and side-trace order can make one inherit recorder
-- state from another, which measures the driver rather than the source shape.
local names = {"dynamic", "fixed", "unrolled"}
local samples = {dynamic = {}, fixed = {}, unrolled = {}}
local fixedRatios, unrolledRatios = {}, {}
for sample = 1, 15 do
    local first = (sample - 1) % #names + 1
    for offset = 0, #names - 1 do
        local name = names[(first + offset - 1) % #names + 1]
        local command = ("luajit %q --sample %s"):format(arg[0], name)
        local child = assert(io.popen(command, "r"))
        local elapsed = assert(tonumber(assert(child:read("*l"))))
        assert(child:close(), "isolated " .. name .. " sample failed")
        samples[name][sample] = elapsed
    end
    fixedRatios[sample] = samples.dynamic[sample] / samples.fixed[sample]
    unrolledRatios[sample] = samples.dynamic[sample] / samples.unrolled[sample]
end

local function median(values)
    table.sort(values)
    return values[math.floor((#values + 1) / 2)]
end

io.write("ordinary Lua differential agrees for tails and the full input\n")
io.write(("runtime bound       %10.0f ns\n"):format(median(samples.dynamic) * 1e9))
io.write(("literal-bound loop  %10.0f ns\n"):format(median(samples.fixed) * 1e9))
io.write(("straight-line body  %10.0f ns\n"):format(median(samples.unrolled) * 1e9))
io.write(("literal-loop speedup %10.3fx\n"):format(median(fixedRatios)))
io.write(("unrolled speedup     %10.3fx\n"):format(median(unrolledRatios)))
