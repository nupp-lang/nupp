-- Reproducible cold semantic-check benchmark for the compiler scheduler.
--
-- Run from the repository root after building the compiler:
--   luajit bench/cold-compile.lua --runs=5 --workers=serial,1,2,4,8
--
-- The harness preserves the caller's semantic cache, removes only the cache product
-- that makes a check warm between samples, and writes one JSON document to stdout.

local runs = 5
local workers = {"serial", 1, 2, 4, 8}
local root = os.getenv("NUPP_COMPILER_ROOT") or "."

for _, argument in ipairs(arg) do
    local count = argument:match("^%-%-runs=(%d+)$")
    local lanes = argument:match("^%-%-workers=(.+)$")
    if count then
        runs = assert(tonumber(count))
    elseif lanes then
        workers = {}
        for lane in lanes:gmatch("[^,]+") do
            workers[#workers + 1] = lane == "serial" and lane or assert(tonumber(lane), "worker count is an integer")
        end
    else
        error("unknown argument " .. argument, 0)
    end
end

local function quote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function read(path)
    local file = io.open(path, "rb")
    if not file then
        return nil
    end
    local value = file:read("*a")
    file:close()

    return value
end

local function command(command)
    local pipe = assert(io.popen(command .. " 2>/dev/null", "r"))
    local output = pipe:read("*a") or ""
    pipe:close()

    local trimmed = output:gsub("%s+$", "")

    return trimmed
end

local function json(value)
    local kind = type(value)
    if kind == "nil" then
        return "null"
    elseif kind == "boolean" or kind == "number" then
        return tostring(value)
    elseif kind == "string" then
        return '"' .. value:gsub('[%z\1-\31\\"]', function(byte)
            local escapes = {
                ['"'] = '\\"',
                ['\\'] = '\\\\',
                ['\b'] = '\\b',
                ['\f'] = '\\f',
                ['\n'] = '\\n',
                ['\r'] = '\\r',
                ['\t'] = '\\t',
            }

            return escapes[byte] or ("\\u%04x"):format(byte:byte())
        end) .. '"'
    elseif kind == "table" then
        if #value > 0 then
            local encoded = {}
            for position, item in ipairs(value) do
                encoded[position] = json(item)
            end
            return "[" .. table.concat(encoded, ",") .. "]"
        end
        local keys, encoded = {}, {}
        for key in pairs(value) do
            keys[#keys + 1] = key
        end
        table.sort(keys)
        for position, key in ipairs(keys) do
            encoded[position] = json(key) .. ":" .. json(value[key])
        end
        return "{" .. table.concat(encoded, ",") .. "}"
    end
    error("cannot encode " .. kind, 0)
end

local function median(samples)
    local ordered = {}
    for position, value in ipairs(samples) do
        ordered[position] = value
    end
    table.sort(ordered)

    return ordered[math.ceil(#ordered / 2)]
end

local cache = root .. "/build/cache/checks.buf"
local token = tostring(os.time()) .. "-" .. tostring(math.random(1000000, 9999999))
local saved = "/tmp/nupp-cold-compile-cache-" .. token .. ".buf"
local hadCache = read(cache) ~= nil
if hadCache then
    assert(os.rename(cache, saved), "cannot preserve " .. cache)
end

local temporary = "/tmp/nupp-cold-compile-" .. token
local results = {}

local function one(lane, sample, warm)
    local stdout = temporary .. ".out"
    local stderr = temporary .. ".err"
    local environment = lane == "serial" and "NUPP_SERIAL_CHECK=1"
        or "NUPP_EXPERIMENTAL_PARALLEL_CHECK=1 NUPP_PARALLEL_CHECK_TRACE=1 NUPP_CHECK_JOBS=" .. tostring(lane)
    local invocation = table.concat(
        {
            "cd",
            quote(root),
            "&&",
            "/usr/bin/time -lp env",
            environment,
            "./bin/nupp check --json",
            ">",
            quote(stdout),
            "2>",
            quote(stderr)
        },
        " "
    )
    local ok, why, code = os.execute(invocation)
    local report = read(stdout) or ""
    local trace = read(stderr) or ""
    os.remove(stdout)
    os.remove(stderr)
    local elapsed = tonumber(trace:match("real%s+([%d.]+)"))
    local rss = tonumber(trace:match("(%d+)%s+maximum resident set size"))
    local counters = trace:match("parallel cold check: ([^\n]+)")
    local successful = ok == true or ok == 0 or report:find('"ok":true', 1, true) ~= nil
    if not successful then
        error(
            (
                "sample %s/%d failed (%s %s):\n%s\n%s"
            ):format(tostring(lane), sample, tostring(why), tostring(code), report, trace),
            0
        )
    end

    return {
        run = sample,
        warm = warm,
        seconds = assert(elapsed, "time did not report elapsed seconds"),
        maxRssBytes = rss,
        compiledModules = tonumber(report:match('"compiledModules":(%d+)')),
        reusedModules = tonumber(report:match('"reusedModules":(%d+)')),
        compilerMs = tonumber(report:match('"totalMs":([%d.]+)')),
        counters = counters,
    }
end

local function runAll()
    for _, lane in ipairs(workers) do
        local entry = {workers = lane, cold = {}, warm = {}}
        local coldTimes, warmTimes = {}, {}
        for sample = 1, runs do
            os.remove(cache)
            local cold = one(lane, sample, false)
            entry.cold[#entry.cold + 1] = cold
            coldTimes[#coldTimes + 1] = cold.seconds
            local warm = one(lane, sample, true)
            entry.warm[#entry.warm + 1] = warm
            warmTimes[#warmTimes + 1] = warm.seconds
        end
        entry.coldMedianSeconds = median(coldTimes)
        entry.warmMedianSeconds = median(warmTimes)
        results[#results + 1] = entry
    end
end

local ok, problem = xpcall(runAll, debug.traceback)
os.remove(cache)
if hadCache then
    assert(os.rename(saved, cache), "cannot restore " .. cache)
end
if not ok then
    error(problem, 0)
end

local machine = {
    os = command("uname -s"),
    architecture = command("uname -m"),
    cpu = command("sysctl -n machdep.cpu.brand_string"),
    logicalCores = tonumber(command("sysctl -n hw.logicalcpu")),
    physicalCores = tonumber(command("sysctl -n hw.physicalcpu")),
}
local report = {
    schema = 1,
    kind = "nupp-cold-semantic-check",
    commit = command("git -C " .. quote(root) .. " rev-parse HEAD"),
    dirty = command("git -C " .. quote(root) .. " status --porcelain") ~= "",
    runs = runs,
    machine = machine,
    results = results,
}
io.write(json(report), "\n")
