-- The six bench/vm workloads timed on the standalone core and on the VM,
-- interleaved and repeated, so neither startup nor a loaded machine decides
-- the comparison.
--
--   cd native/core/tests/perf && ../../../../bin/nupp run run.lua [OPTION...]
--
-- Each run is one process measuring one workload with debug.bench: a warmup
-- and seven rounds with collection stopped, timed on the monotonic clock in
-- the process, so startup, loading and compilation stay out of the figure.
-- A repeat runs every selected workload once on every runner, the runners in
-- an order that rotates from repeat to repeat; the table reports, per
-- workload and runner, the median of the per-process figures and their
-- range, and each runner's ratio to the first, paired within a repeat.
--
-- `loops` is the exception on the core: past 2^47 its products are boxed
-- integers, and with collection stopped for the rounds they exhaust the
-- core's heap. There the core runs the guest runner's workloadLoops program
-- once, timed as a whole process (startup is a few milliseconds of its ten
-- seconds); the VM still times it in process.
--
-- Options:
--   --repeats N          repeats (default 3)
--   --cases a,b          workloads (default fib,closures,records,tables,strings,loops)
--   --core NAME=BUNDLE   a core bench bundle to time (repeatable; default the
--                        one the guest runner builds,
--                        build/core-guests/benchworkloads-normal.bundle)
--   --loops NAME=BUNDLE  the workloadLoops bundle for core NAME (default for
--                        the default core: build/core-guests/workloadLoops-normal.bundle)
--   --no-vm              leave the VM out
--   --metric M           time (default), or instructions or cycles: the core's
--                        whole-process counts from `/usr/bin/time -l`, which a
--                        loaded machine moves far less than time, for telling
--                        apart core builds a few percent apart (the VM's would
--                        count its compiler, so it has none)
--   --out FILE           also write the table to FILE
--
-- The VM runs the source through `bin/nupp run`, the CLI's linked runtime:
-- an interpreter with no JIT compiled in, so NO_JIT changes nothing there.
-- The core bundles come from the guest runner (`run.lua benchworkloads
-- workloadLoops` in ../guests); the bridge from its cargo build.
local HERE = debug.getinfo(1, "S").source:match("^@(/.*)/[^/]*$")
local ROOT = os.getenv("NUPP_COMPILER_ROOT") or (HERE and HERE .. "/../../../..") or "../../../.."
local BRIDGE = os.getenv("NUPP_CORE_BRIDGE") or ROOT .. "/build/core-bridge/debug/nupp-core"
local SOURCE = ROOT .. "/bench/vm/workloads.bench.nupp"
local CASES = {"fib", "closures", "records", "tables", "strings", "loops"}

local function quote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function split(text)
    local list = {}
    for item in text:gmatch("[^,]+") do
        list[#list + 1] = item
    end
    return list
end

local function pair(text, option)
    local name, value = assert(text, option .. " takes NAME=BUNDLE"):match("^([^=]+)=(.+)$")
    return assert(name, option .. " takes NAME=BUNDLE"), value
end

local repeats, cases, cores, loops, vm, out, metric = 3, CASES, {}, {}, true, nil, "time"
local at = 1
while at <= #arg do
    local option = arg[at]
    if option == "--repeats" then
        repeats = assert(math.tointeger(tonumber(arg[at + 1])), "--repeats takes a count")
        at = at + 1
    elseif option == "--cases" then
        cases = split(assert(arg[at + 1], "--cases takes a list"))
        at = at + 1
    elseif option == "--core" then
        local name, bundle = pair(arg[at + 1], option)
        cores[#cores + 1] = {name = name, bundle = bundle}
        at = at + 1
    elseif option == "--loops" then
        local name, bundle = pair(arg[at + 1], option)
        loops[name] = bundle
        at = at + 1
    elseif option == "--no-vm" then
        vm = false
    elseif option == "--metric" then
        metric = assert(arg[at + 1], "--metric takes time, instructions or cycles")
        assert(metric == "time" or metric == "instructions" or metric == "cycles", "unknown metric " .. metric)
        at = at + 1
    elseif option == "--out" then
        out = assert(arg[at + 1], "--out takes a path")
        at = at + 1
    else
        error("unknown option " .. tostring(option))
    end
    at = at + 1
end
if #cores == 0 then
    cores[1] = {name = "core", bundle = ROOT .. "/build/core-guests/benchworkloads-normal.bundle"}
    loops.core = loops.core or ROOT .. "/build/core-guests/workloadLoops-normal.bundle"
end

local empty = os.tmpname()
local nowhere = os.tmpname()

-- One process's figure in milliseconds, or nil when it printed no record.
local function record(command, case)
    local pipe = assert(io.popen(command .. " 2>/dev/null"))
    local printed = pipe:read("*a")
    pipe:close()
    local median = tonumber(printed:match('"medianMs":([%d%.eE+-]+)'))
    if not median or printed:match('"name":"([^"]+)"') ~= case then
        return nil
    end
    return median
end

-- The wall time of a whole process, in milliseconds, or nil when it failed.
local function whole(command)
    local started = os.monotonic()
    local ok = os.execute(command .. " > /dev/null 2>&1")
    local elapsed = os.monotonic() - started
    if not ok then
        return nil
    end
    return elapsed
end

-- What `/usr/bin/time -l` counted for a whole process (COUNTERS[metric]),
-- or nil when it failed.
local COUNTERS = {instructions = "instructions retired", cycles = "cycles elapsed"}
-- How the log and table show each metric: its unit and its scale.
local UNITS = {time = "ms", instructions = "G instructions", cycles = "G cycles"}
local SCALE = {time = 1, instructions = 1e9, cycles = 1e9}

local function counted(command)
    local pipe = assert(io.popen("/usr/bin/time -l " .. command .. " 2>&1 >/dev/null"))
    local printed = pipe:read("*a")
    local ok = pipe:close()
    if not ok then
        return nil
    end
    return tonumber(printed:match("(%d+)%s+" .. COUNTERS[metric]))
end

-- Every runner: a name, and what measures workload `case` (nil when it has
-- no way to).
local runners = {}
for _, core in ipairs(cores) do
    runners[#runners + 1] = {
        name = core.name,
        measure = function(case)
            if case == "loops" then
                local bundle = loops[core.name]
                if not bundle then
                    return nil
                end
                local command = ("%s %s %s %s"):format(quote(BRIDGE), quote(bundle), quote(empty), quote(nowhere))
                if metric ~= "time" then
                    return counted(command)
                end
                return whole(command)
            end
            if metric ~= "time" then
                return counted(
                    ("%s %s %s %s --case %s --json --out /dev/null"):format(
                        quote(BRIDGE),
                        quote(core.bundle),
                        quote(empty),
                        quote(nowhere),
                        quote(case)
                    )
                )
            end
            return record(
                ("%s %s %s %s --case %s --json --out /dev/null"):format(
                    quote(BRIDGE),
                    quote(core.bundle),
                    quote(empty),
                    quote(nowhere),
                    quote(case)
                ),
                case
            )
        end
    }
end
if vm then
    runners[#runners + 1] = {
        name = "vm",
        measure = function(case)
            if metric ~= "time" then
                return nil
            end
            return record(
                ("cd %s && ./bin/nupp run %s --case %s --json --out /dev/null"):format(
                    quote(ROOT),
                    quote(SOURCE),
                    quote(case)
                ),
                case
            )
        end
    }
end

local function median(list)
    local sorted = {}
    for _, value in pairs(list) do
        sorted[#sorted + 1] = value
    end
    if #sorted == 0 then
        return nil
    end
    table.sort(sorted)
    local n = #sorted
    if n % 2 == 1 then
        return sorted[(n + 1) // 2]
    end
    return (sorted[n // 2] + sorted[n // 2 + 1]) / 2
end

local function range(list)
    local low, high = math.huge, 0
    for _, value in pairs(list) do
        low, high = math.min(low, value), math.max(high, value)
    end
    return low, high
end

-- results[case][runner][repeat] = milliseconds, absent for a failed run.
local results = {}
for _, case in ipairs(cases) do
    results[case] = {}
    for _, runner in ipairs(runners) do
        results[case][runner.name] = {}
    end
end
for round = 1, repeats do
    for _, case in ipairs(cases) do
        for step = 0, #runners - 1 do
            local runner = runners[(round - 1 + step) % #runners + 1]
            local value = runner.measure(case)
            results[case][runner.name][round] = value
            io.stderr:write(
                ("repeat %d %s %s %s\n"):format(
                    round,
                    case,
                    runner.name,
                    value and ("%.1f %s"):format(value / SCALE[metric], UNITS[metric]) or "failed"
                )
            )
        end
    end
end

local lines = {}
local function line(text)
    lines[#lines + 1] = text
end
local header = {"| workload"}
local rule = {"| ---"}
for index, runner in ipairs(runners) do
    header[#header + 1] = runner.name .. " " .. UNITS[metric] .. " (range)"
    rule[#rule + 1] = "---:"
    if index > 1 then
        header[#header + 1] = runner.name .. " / " .. runners[1].name
        rule[#rule + 1] = "---:"
    end
end
line(table.concat(header, " | ") .. " |")
line(table.concat(rule, " | ") .. " |")
for _, case in ipairs(cases) do
    local row = {"| " .. case}
    local first = results[case][runners[1].name]
    for index, runner in ipairs(runners) do
        local list = results[case][runner.name]
        local middle = median(list)
        if middle then
            local low, high = range(list)
            local scale = SCALE[metric]
            row[#row + 1] = ("%.0f (%.0f-%.0f)"):format(middle / scale, low / scale, high / scale)
        else
            row[#row + 1] = "-"
        end
        if index > 1 then
            local ratios = {}
            for round = 1, repeats do
                if list[round] and first[round] then
                    ratios[#ratios + 1] = list[round] / first[round]
                end
            end
            local ratio = median(ratios)
            if ratio then
                local low, high = range(ratios)
                row[#row + 1] = ("%.3f (%.3f-%.3f)"):format(ratio, low, high)
            else
                row[#row + 1] = "-"
            end
        end
    end
    line(table.concat(row, " | ") .. " |")
end
line("")
if metric == "time" then
    line(
        ("%d repeats; each figure is the median over repeats of one process's median of seven in-process rounds"):format(
            repeats
        ) .. " (core loops: one whole process)."
    )
else
    line(("%d repeats; each figure is the median over repeats of one whole process's %s."):format(repeats, COUNTERS[metric]))
end
local text = table.concat(lines, "\n") .. "\n"
io.write(text)
if out then
    local file = assert(io.open(out, "w"))
    file:write(text)
    file:close()
end
os.remove(empty)
os.remove(nowhere)
