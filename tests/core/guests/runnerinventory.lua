-- The packaged test runner's suites on the core, one bounded bridge run each,
-- classified by how they end: the runner-on-core failure inventory.
--
--   ./bin/nupp run tests/core/guests/runnerinventory.lua [--bound SECONDS] [--jobs N] [SUITE...]
--
-- It runs the testrunner guest case's bundle (build/core-guests/testrunner-
-- normal.bundle, which `acceptance.nupp testrunner` builds) through the C
-- bridge once per suite, `--jobs=1 --json --fresh SUITE`, under a watchdog
-- that kills a run past `--bound` seconds (default 180). The Lua sources a
-- suite loads are compiled to chunks on the host first, as the guest case
-- compiles its own, since the core does not compile Lua text quickly. With
-- no suite named it runs every suite the runner lists and writes
-- tests/core/guests/runnerinventory.json: each suite's outcome, counts and,
-- for a suite that does not pass, the first failure and its cause.
local json = require("serde.json")
local chunkfiles = require("nupp.runtime.chunkfiles")
local sharedcache = require("nupp.core.sharedcache")

local function cwd()
    local pipe = assert(io.popen("pwd"))
    local path = pipe:read("*l")
    pipe:close()
    return path
end

local ROOT = os.getenv("NUPP_COMPILER_ROOT") or cwd()
local OUT = ROOT .. "/build/core-guests"
local WORK = ROOT .. "/build/core-runner-inventory"
local INVENTORY = ROOT .. "/tests/core/guests/runnerinventory.json"
local BUNDLE = OUT .. "/testrunner-normal.bundle"
local BRIDGE = ROOT .. "/build/c-core-bridge/nupp-core"
local TIMED_OUT = "nupp runner inventory run timed out after "
-- The same watchdog acceptance.nupp and run.lua put on their runs: the run
-- in a process group of its own, killed whole past its bound.
local WATCHDOG = [[
my $limit = shift;
my $pid = fork;
die "fork: $!" unless defined $pid;
if ($pid == 0) { setpgrp(0, 0); exec "/bin/sh", @ARGV; exit 127 }
$SIG{ALRM} = sub { kill "KILL", -$pid; waitpid $pid, 0; print STDERR "\n]]
    .. TIMED_OUT
    .. [[${limit}s\n"; exit 124 };
alarm $limit;
waitpid $pid, 0;
exit($? & 127 ? 128 + ($? & 127) : $? >> 8);
]]
-- Causes by what a failure says, most specific first; a failure no pattern
-- names keeps its own first line as its cause.
local CAUSES = {
    {"timed out after", "bound: still running at the bound"},
    {"module '([^']+)' not found", "uncarried module: %s"},
    {"no Lua source for ([%w%._]+)", "no Lua source: %s"},
    {"getinfo", "debug.getinfo"},
    {"attempt to call a nil value %(field '([%w_]+)'%)", "missing function: %s"},
    {"no chunk for", "no host-compiled chunk"},
    {"refused", "chunk compile refused"},
}

local function quote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function shell(command)
    local pipe = assert(io.popen(command .. " 2>&1; echo __exit__:$?"))
    local output = pipe:read("*a")
    pipe:close()
    return tonumber(output:match("__exit__:(%d+)%s*$")), (output:gsub("__exit__:%d+%s*$", ""))
end

local function read(path)
    local file = io.open(path, "rb")
    if not file then
        return nil
    end
    local bytes = file:read("*a")
    file:close()

    return bytes
end

local function write(path, bytes)
    local file = assert(io.open(path, "wb"))
    file:write(bytes)
    file:close()
end

local bound, jobs, named = 180, 2, {}
do
    local index = 1
    while arg[index] do
        local given = arg[index]
        if given == "--bound" or given == "--jobs" then
            local value = math.tointeger(tonumber(arg[index + 1] or ""))
            assert(value and value > 0, given .. " needs a positive integer")
            if given == "--bound" then
                bound = value
            else
                jobs = value
            end
            index = index + 1
        else
            assert(given:sub(1, 2) ~= "--", "unknown option " .. given)
            named[#named + 1] = given
        end
        index = index + 1
    end
end
assert(read(BUNDLE), "no testrunner bundle: run ./bin/nupp run tests/core/guests/acceptance.nupp testrunner first")
assert(read(BRIDGE), "no C bridge: run scripts/core-bridge")

-- Every suite the runner lists, and the file it loads it from.
local listed = {}
do
    local status, output = shell("cd " .. quote(ROOT) .. " && ./bin/nupp test --list-suites --scope=all")
    assert(status == 0, "could not list the runner's suites:\n" .. output)
    for name in output:gmatch("[^\n]+") do
        if name:match("^[%w_%-]+$") then
            listed[#listed + 1] = name
        end
    end
end
local paths = {}
do
    local _, output = shell("cd " .. quote(ROOT) .. " && find tests -name '*.lua' -o -name '*test.nupp'")
    for path in output:gmatch("[^\n]+") do
        local name = path:match("([^/]+)%.lua$") or path:match("([^/]+)%.nupp$")
        if name and not paths[name] then
            paths[name] = path
        end
    end
end
local suites = {}
if #named > 0 then
    local known = {}
    for _, name in ipairs(listed) do
        known[name] = true
    end
    for _, name in ipairs(named) do
        assert(known[name], "unknown suite " .. name)
        suites[#suites + 1] = name
    end
else
    suites = listed
end
assert(#suites > 0, "empty suite selection")

-- The Lua sources under tests/, compiled for the core where the runner finds
-- them (NUPP_CORE_CHUNKS), as run.lua compiles a case's own.
do
    local guestbuild = require("nupp.core.guestbuild")
    local compiledBy = assert(sharedcache.treeDigest(ROOT, {"src"}))
    os.execute("mkdir -p " .. quote(OUT .. "/chunks"))
    local _, output = shell("cd " .. quote(ROOT) .. " && find tests -name '*.lua' | sort")
    local compiled, refused = 0, 0
    for path in output:gmatch("[^\n]+") do
        local text = read(ROOT .. "/" .. path)
        local kept = OUT .. "/chunks/" .. chunkfiles.name(path)
        local held = read(kept)
        local current = held
            and (
                held:sub(1, #chunkfiles.contents(text, "")) == chunkfiles.contents(text, "")
                or held:sub(1, #chunkfiles.refusedcontents(text, "")) == chunkfiles.refusedcontents(text, "")
            )
            and read(kept .. ".by") == compiledBy
        if text and not current then
            local ok, contents, problem = pcall(guestbuild.sourceChunk, path)
            if not ok then
                contents, problem = nil, contents
            end
            write(kept, contents or chunkfiles.refusedcontents(text, tostring(problem)))
            write(kept .. ".by", compiledBy)
            compiled = compiled + 1
            refused = refused + (contents and 0 or 1)
        end
    end
    print(("runner inventory: compiled %d sources, %d refused"):format(compiled, refused))
end

-- The pinned C libraries the runner binds by name (its hashing binds the
-- CRC library), as scripts/c-library-paths names them.
local libraries = ""
do
    local status, output = shell("sh " .. quote(ROOT .. "/scripts/c-library-paths"))
    assert(status == 0, "could not provision the pinned C libraries:\n" .. output)
    for key, value in output:gmatch("(NUPP_[%u_]+_LIBRARY)=([^\r\n]+)") do
        libraries = libraries .. key .. "=" .. quote(value) .. " "
    end
end

-- One bounded bridge run per suite, `jobs` at once.
os.execute("rm -rf " .. quote(WORK) .. " && mkdir -p " .. quote(WORK))
write(WORK .. "/empty.bin", "")
do
    local queue = {}
    for _, suite in ipairs(suites) do
        local script = WORK .. "/" .. suite .. ".sh"
        write(
            script,
            (
                "cd %s && unset NUPP_VM_BINARY NUPP_VM_CLI_IMAGE && export %sNUPP_COMPILER_ROOT=%s NUPP_CORE_CHUNKS=%s && %s %s %s %s --jobs=1 --json --no-color --fresh %s\n"
            ):format(
                quote(ROOT),
                libraries,
                quote(ROOT),
                quote(OUT .. "/chunks"),
                quote(BRIDGE),
                quote(BUNDLE),
                quote(WORK .. "/empty.bin"),
                quote(WORK .. "/" .. suite .. ".out"),
                suite
            )
        )
        local bounded = WORK .. "/" .. suite .. ".run.sh"
        write(
            bounded,
            (
                "perl -e %s %d %s > %s 2>&1; echo $? > %s\n"
            ):format(
                quote(WATCHDOG),
                bound,
                quote(script),
                quote(WORK .. "/" .. suite .. ".log"),
                quote(WORK .. "/" .. suite .. ".status")
            )
        )
        queue[#queue + 1] = bounded
    end
    write(WORK .. "/queue", table.concat(queue, "\n") .. "\n")
    print(("runner inventory: %d suites, %d at once, %ds bound, logs in %s"):format(#suites, jobs, bound, WORK))
    shell(("xargs -P %d -n 1 sh < %s"):format(jobs, quote(WORK .. "/queue")))
end

local function causeOf(message)
    for _, rule in ipairs(CAUSES) do
        local captured = message:match(rule[1])
        if captured then
            return rule[2]:find("%s", 1, true) and rule[2]:format(captured) or rule[2]
        end
    end

    return (message:gsub(ROOT:gsub("%p", "%%%0"), "<root>"):match("^[^\n]*") or ""):sub(1, 160)
end

-- What each run says about its suite.
local rows = {}
local tally = {}
for _, suite in ipairs(suites) do
    local log = read(WORK .. "/" .. suite .. ".log") or ""
    local status = tonumber((read(WORK .. "/" .. suite .. ".status") or ""):match("%d+"))
    local row = {suite = suite, path = paths[suite]}
    local document = log:match("(%{.*%})%s*$")
    local ok, report = pcall(json.decodevalue, document or "")
    if log:find(TIMED_OUT, 1, true) then
        row.outcome, row.cause = "bound", causeOf(TIMED_OUT)
    elseif paths[suite] and paths[suite]:match("%.nupp$") then
        row.outcome, row.cause = "load-error", "a Nupp suite, which the runner loads only on the VM"
    elseif not ok or type(report) ~= "table" or type(report.total) ~= "number" then
        local last = (log:gsub("%s+$", "")):match("([^\n]*)$") or ""
        row.outcome, row.cause = "no-report", causeOf(last ~= "" and last or ("status " .. tostring(status)))
        row.first = (last:gsub(ROOT:gsub("%p", "%%%0"), "<root>")):sub(1, 240)
    else
        row.tests, row.passed, row.failed = report.total, report.passed, report.failed
        if report.total > 0 and report.passed == report.total then
            row.outcome = "passed"
        else
            row.outcome = report.total == 0 and "load-error" or report.failed == 0 and "skipped" or "failed"
            for _, test in ipairs(report.tests or {}) do
                if test.status ~= "passed" and type(test.failure) == "table" then
                    local message = tostring(test.failure.message or "")
                    row.cause = causeOf(message)
                    row.first = (
                        tostring(test.name or "") .. ": " .. message:gsub(ROOT:gsub("%p", "%%%0"), "<root>")
                    ):match("^[^\n]*")
                        :sub(1, 240)
                    break
                end
            end
            if not row.cause then
                local last = (log:gsub("%s+$", "")):match("([^\n]*)$") or ""
                row.cause = causeOf(last)
            end
        end
    end
    tally[row.outcome] = (tally[row.outcome] or 0) + 1
    rows[#rows + 1] = row
    print(("%-12s %-40s %s"):format(row.outcome, suite, row.cause or ""))
end

local outcomes = {}
for outcome, count in pairs(tally) do
    outcomes[#outcomes + 1] = ("%s %d"):format(outcome, count)
end
table.sort(outcomes)
print("runner inventory: " .. table.concat(outcomes, ", "))

if #named == 0 then
    -- Hand-written so its bytes depend only on its rows.
    local function field(name, value)
        if value == nil then
            return nil
        end
        return ('"%s": %s'):format(name, type(value) == "number" and tostring(value) or json.encodevalue(value))
    end

    local lines = {}
    for index, row in ipairs(rows) do
        local fields = {}
        for _, pair in ipairs({
            {"suite", row.suite},
            {"path", row.path},
            {"outcome", row.outcome},
            {"tests", row.tests},
            {"passed", row.passed},
            {"failed", row.failed},
            {"cause", row.cause},
            {"first", row.first}
        }) do
            fields[#fields + 1] = field(pair[1], pair[2])
        end
        lines[index] = "    {" .. table.concat(fields, ", ") .. "}"
    end
    write(
        INVENTORY,
        "{\n" .. '  "about": ' .. json.encodevalue(
            "The packaged runner's suites on the core, each run alone under a bound "
            .. "(tests/core/guests/runnerinventory.lua): how each ends, and why a suite that does not pass fails."
        ) .. ",\n" .. (
            '  "bound": %d,\n'
        ):format(bound) .. '  "suites": [\n' .. table.concat(lines, ",\n") .. "\n  ]\n}\n"
    )
    print("runner inventory: wrote " .. INVENTORY)
end
