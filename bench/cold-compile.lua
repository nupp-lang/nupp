-- Reproducible cold semantic-check benchmark for the compiler scheduler.
--
-- Run from the repository root after building the compiler:
--   luajit bench/cold-compile.lua --runs=5 --workers=serial,2,4,8
--
-- `serial` is `NUPP_CHECK_JOBS=1`; a number is that many semantic workers. The
-- harness preserves the caller's semantic cache, removes only the cache product
-- that makes a check warm between samples, and writes one JSON document to stdout.
--
-- macOS only: it reads elapsed time and peak memory from BSD `time -l` and
-- describes the machine with `sysctl`.

local runs = 5
local workers = {"serial", 2, 4, 8}
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

if command("uname -s") ~= "Darwin" then
    error("bench/cold-compile.lua reads BSD time -l and sysctl, and runs on macOS only", 0)
end

local cache = root .. "/build/cache/checks.buf"
local token = tostring(os.time()) .. "-" .. tostring(math.random(1000000, 9999999))
-- Beside the cache rather than in /tmp: a rename is only atomic, and only works,
-- within one file system.
local saved = cache .. ".bench-" .. token
local hadCache = read(cache) ~= nil
if hadCache then
    assert(os.rename(cache, saved), "cannot preserve " .. cache)
end

local stdout, stderr = os.tmpname(), os.tmpname()
local results = {}

local function one(lane, sample, warm)
    local environment = lane == "serial" and "NUPP_CHECK_JOBS=1"
        or "NUPP_PARALLEL_CHECK_TRACE=1 NUPP_CHECK_JOBS=" .. tostring(lane)
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
    -- A child stopped by Ctrl-C reports it in its status; stop the whole run so the
    -- cache is restored below rather than benchmarked around.
    if why == "signal" and code == 2 or type(ok) == "number" and (ok % 256 == 2 or math.floor(ok / 256) == 130) then
        error("interrupted", 0)
    end
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

-- Restored however the run ends: an error in a sample, or Ctrl-C, which LuaJIT
-- raises as an error wherever the harness was.
local ok, problem = xpcall(runAll, debug.traceback)
os.remove(stdout)
os.remove(stderr)
os.remove(cache)
if hadCache then
    assert(os.rename(saved, cache), "cannot restore " .. cache .. " from " .. saved)
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
