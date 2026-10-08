local cache = require("nupp.tools.build.cache")
local fingerprint = require("nupp.compiler.project.fingerprint")
local fs = require("nupp.compiler.fs")
local json = require("testjson")
local parallelcheck = require("nupp.tools.build.parallelcheck")
local process = require("nupp.compiler.process")
local stable = require("nupp.compiler.stable")
local store = require("nupp.compiler.project.store")
local time = require("nupp.time")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
if not HERE:match("^/") then
    local current = assert(io.popen("pwd"))
    HERE = current:read("*l") .. "/" .. HERE
    current:close()
end
local ROOT = assert(HERE:match("^(.*)/[^/]+$"), "tests directory has no parent")
local NUPP = ROOT .. "/bin/nupp"

local function assertEq(got, want, label)
    if got ~= want then
        error(("%s:\n  want: %s\n  got:  %s"):format(label or "mismatch", tostring(want), tostring(got)), 2)
    end
end

local function write(path, text)
    local directory = path:match("^(.*)/[^/]+$")
    if directory then
        assert(process.run(process.mkdirCommand(directory)) == 0)
    end
    local file = assert(io.open(path, "wb"))
    file:write(text)
    file:close()
end

local function projectFiles(withErrors)
    local files = {
        ["nupp.lua"] = 'return {include = {"src"}}\n',
        [
            "src/box.g.nupp"
        ] = [[
local box = {}

record box.Value
    number: number
end

function box.newValue(number: number): box.Value
    return new box.Value(number = number)
end

return box
]],
        [
            "src/resource.g.nupp"
        ] = [[
local resource = {}

record resource.Handle
    value: number
end

local function closeHandle(takes handle: resource.Handle): nil
    handle.value = 0
end

function resource.open(value: number): affine(resource.Handle, closeHandle)
    return new resource.Handle(value = value)
end

return resource
]],
        [
            "src/left.nupp"
        ] = [[
local box = require("box")

local function value(): number
    return box.newValue(20).number
end

return {value = value}
]],
        [
            "src/right.nupp"
        ] = [[
local resource = require("resource")

local function value(): number
    local handle = resource.open(22)
    return handle.value
end

return {value = value}
]],
        [
            "src/join.nupp"
        ] = [[
local left = require("left")
local right = require("right")

local function answer(): number
    return left.value() + right.value()
end

return {answer = answer}
]],
        [
            "src/qualified.nupp"
        ] = [[
module qualified

export function value(): number
    return 42
end
]],
        [
            "src/qualified_user.nupp"
        ] = [[
local function value(): number
    return qualified.value()
end

return {value = value}
]],
        [
            "src/cycle_a.g.nupp"
        ] = [[
local cycleB = require("cycle_b")
local cycleA = {}

function cycleA.base(): number
    return 1
end

function cycleA.value(): number
    return cycleB.value() + 1
end

return cycleA
]],
        [
            "src/cycle_b.g.nupp"
        ] = [[
local cycleA = require("cycle_a")
local cycleB = {}

function cycleB.value(): number
    return cycleA.base() + 1
end

return cycleB
]],
        ["src/external.d.nupp"] = "local add: function(number, number): number\nreturn {add = add}\n",
        [
            "src/external_user.nupp"
        ] = [[
local external = require("external")
local value: number = external.add(20, 22)
return value
]],
    }
    for index = 1, 8 do
        local name = ("layer%02d"):format(index)
        local dependency = index == 1 and "join" or ("layer%02d"):format(index - 1)
        files[
            "src/" .. name .. ".nupp"
        ] = ([[
local dependency = require(%q)

local function value(): number
    return dependency.%s() + 1
end

return {value = value}
]]):format(dependency, index == 1 and "answer" or "value")
    end
    if withErrors then
        files["src/broken_a.nupp"] = "local wrong: string = 1\nreturn wrong\n"
        files["src/broken_b.nupp"] = 'local wrong: integer = "wrong"\nreturn wrong\n'
    end

    return files
end

local function tempProject(withErrors)
    local directory = os.tmpname()
    os.remove(directory)
    assert(process.run(process.mkdirCommand(directory)) == 0)
    for name, text in pairs(projectFiles(withErrors)) do
        write(directory .. "/" .. name, text)
    end

    return directory
end

local function checkState(directory)
    local contentCache = fingerprint.sharedCacheDir(directory .. "/build/cache")
    local moduleHash = cache.moduleCompilerFingerprint(contentCache, fingerprint.contentDigest(true))
    local saved = store.openValue(directory .. "/build/cache/checks.buf", "checks/1\0" .. moduleHash).value
    assert(saved, "the check did not persist its state")

    return stable(saved)
end

local function workerPids(path)
    local file = io.open(path, "rb")
    if not file then
        return {}
    end
    local pids = {}
    for line in file:lines() do
        local pid = tonumber(line)
        if pid and pid > 1 then
            pids[pid] = true
        end
    end
    file:close()

    return pids
end

local function countKeys(values)
    local count = 0
    for _ in pairs(values) do
        count = count + 1
    end

    return count
end

local function coldCheck(directory, environment)
    os.remove(directory .. "/build/cache/checks.buf")
    local code, output = process.capture({NUPP, "check", "--json"}, {
        cwd = directory,
        env = environment,
    })
    local decoded, report = pcall(json.decode, output)
    assert(decoded, tostring(report) .. "\n" .. output)

    return code, report, checkState(directory)
end

-- Every file a build wrote, by path relative to `build`, caches aside.
local function buildOutputs(directory)
    local outputs = {}
    local list = assert(io.popen(("cd '%s/build' && find . -type f -not -path './cache/*' -not -path './.bytecode/*'"):format(
        directory
    )))
    for path in list:lines() do
        local file = assert(io.open(directory .. "/build/" .. path, "rb"))
        outputs[path] = file:read("*a")
        file:close()
    end
    list:close()

    return outputs
end

-- A build from nothing but the caches every command keeps, which a check would also
-- have had: no build state and no artifact.
local function coldBuild(directory, environment, extra)
    os.execute(
        ("cd '%s' && rm -f build/.nupp-state.json build/.nupp-complete && "
        .. "find build -name '*.lua' -not -path 'build/cache/*' -delete 2>/dev/null"):format(directory)
    )
    local argv = {NUPP, "build", "--json"}
    for _, argument in ipairs(extra or {}) do
        argv[#argv + 1] = argument
    end
    local code, output = process.capture(argv, {cwd = directory, env = environment})
    local decoded, report = pcall(json.decode, output)
    assert(decoded, tostring(report) .. "\n" .. output)
    local outputs = buildOutputs(directory)
    local state = json.decode(assert(outputs["./.nupp-state.json"], "the build wrote no state"))
    outputs["./.nupp-state.json"] = nil
    -- How long a derive took, and whether this process had expanded it already, say
    -- nothing about the module.
    for _, record in pairs(state.modules or {}) do
        for _, derive in ipairs(record.derives or {}) do
            derive.durationMs, derive.cached = nil, nil
        end
    end

    return code, report, stable(outputs), stable(state)
end

local M = {}

function M.workerPolicyKeepsSmallChecksSerialAndCapsAutomaticParallelism()
    assertEq(parallelcheck.plan(63, 1048576, 8, nil).workers, 1, "module floor")
    assertEq(parallelcheck.plan(64, 262143, 8, nil).workers, 1, "byte floor")
    assertEq(parallelcheck.plan(64, 262144, 8, nil).workers, 6, "automatic cap")
    assertEq(parallelcheck.plan(64, 262144, 2, nil).workers, 2, "available workers")
    assertEq(parallelcheck.plan(4, 16, 8, 8).workers, 4, "explicit count")
    assertEq(parallelcheck.plan(64, 262144, 8, 1).workers, 1, "serial escape hatch")
end

function M.parallelChecksMatchSerialRecordsAndDiagnosticsAcrossSchedules()
    local directory = tempProject(true)
    local serialCode, serialReport, serialState = coldCheck(directory, {NUPP_CHECK_JOBS = "1"})
    assertEq(serialCode, 1, "the fixture reports its authored errors")
    assertEq(serialReport.timing.parallel.mode, "serial", "one requested worker")

    for _, run in ipairs({{jobs = "2", seed = "17"}, {jobs = "3", seed = "83"}}) do
        local code, report, state = coldCheck(directory, {
            NUPP_CHECK_JOBS = run.jobs,
            NUPP_TEST_PARALLEL_CHECK_RANDOM_SEED = run.seed,
        })
        assertEq(code, serialCode, "parallel exit status")
        assertEq(stable(report.diagnostics), stable(serialReport.diagnostics), "parallel diagnostics")
        assertEq(state, serialState, "parallel check records")
        assertEq(report.timing.parallel.mode, "parallel", "parallel timing mode")
        assertEq(report.timing.parallel.workers, tonumber(run.jobs), "parallel worker count")
        assertEq(report.timing.parallel.retries, 0, "healthy workers are not retried")
    end

    assert(require("nupp.io.files").remove(directory, true))
end

-- Checking a module whose effects need a feature runtime stages that runtime's
-- carried source, and from then on the name resolves to the staged file. Workers
-- check with nothing staged, so every record that names such a module was taken
-- before the move and validated after it: the fingerprint has to say both are the
-- same carried module or the coordinator checks the project a second time.
function M.recordsNamingStagedStandardModulesAreReused()
    local directory = os.tmpname()
    os.remove(directory)
    write(directory .. "/nupp.lua", 'return {include = {"src"}}\n')
    write(
        directory .. "/src/clock.nupp",
        [[
local files = require("nupp.io.files")
local time = require("nupp.time")

local function stamp(path: string): number
    if files.exists(path) then
        return time.now()
    end
    return 0
end

return {stamp = stamp}
]]
    )
    for index = 1, 6 do
        write(
            directory .. ("/src/user%d.nupp"):format(index),
            ([[
local clock = require("clock")
local files = require("nupp.io.files")
local time = require("nupp.time")

local function value(path: string): number
    local exists = files.exists(path) and 1 or 0
    return clock.stamp(path) + time.now() + exists + %d
end

local function described(info: files.Info?): boolean
    return info ~= nil
end

return {value = value, described = described}
]]):format(index)
        )
    end

    local serialCode, _, serialState = coldCheck(directory, {NUPP_CHECK_JOBS = "1"})
    assertEq(serialCode, 0, "serial fixture")
    local code, report, state = coldCheck(directory, {NUPP_CHECK_JOBS = "2"})
    assertEq(code, 0, "parallel exit status")
    assertEq(report.timing.parallel.mode, "parallel", "parallel timing mode")
    assertEq(report.timing.parallel.rechecked, 0, "worker records survive validation")
    assertEq(state, serialState, "parallel check records")

    assert(require("nupp.io.files").remove(directory, true))
end

-- Staging a runtime's carried source checks the modules that name it again, from
-- the same parse. A call's destination stored on the tree by the first check named
-- that check's copy of a standard type, and the second check's copy of the callee
-- could not unify with it: serially, `newObservers()` into an `Observers<integer>`
-- field lost its binder, while a worker, which stages nothing, inferred it.
function M.aStandardGenericFillsAFieldInEitherSchedule()
    local directory = os.tmpname()
    os.remove(directory)
    write(directory .. "/nupp.lua", 'return {include = {"src"}}\n')
    write(
        directory .. "/src/world.nupp",
        [[
const {type Observers} = require("nupp.events")
local events = require("nupp.events")
local files = require("nupp.io.files")

local record World
    observers: Observers<integer>
end

local function newWorld(): World
    local world = new World(observers = events.newObservers())
    world.observers = events.newObservers()
    return world
end

local function fresh(): Observers<integer>
    return events.newObservers()
end

local function count(path: string): integer
    return files.exists(path) and newWorld().observers.count or fresh().count
end

return {count = count}
]]
    )
    for index = 1, 4 do
        write(
            directory .. ("/src/user%d.nupp"):format(index),
            ([[
local world = require("world")
local files = require("nupp.io.files")

local function value(path: string): integer
    return world.count(path) + (files.exists(path) and %d or 0)
end

return {value = value}
]]):format(index)
        )
    end

    local serialCode, serialReport = coldCheck(directory, {NUPP_CHECK_JOBS = "1"})
    assertEq(stable(serialReport.diagnostics), stable({}), "serial diagnostics")
    assertEq(serialCode, 0, "serial fixture")
    local code, report = coldCheck(directory, {NUPP_CHECK_JOBS = "2"})
    assertEq(code, 0, "parallel exit status")
    assertEq(stable(report.diagnostics), stable(serialReport.diagnostics), "parallel diagnostics")

    assert(require("nupp.io.files").remove(directory, true))
end

-- Checking an `@annotation` declaration registers it with the environment rather
-- than exporting it. A worker that imports the declaring module instead of checking
-- it must still know the annotation, or every application it checks is unknown and
-- the coordinator caches that answer for the next warm check to repeat.
function M.projectAnnotationsReachEveryWorker()
    local directory = os.tmpname()
    os.remove(directory)
    write(directory .. "/nupp.lua", 'return {include = {"src"}}\n')
    write(
        directory .. "/src/lib/ann.nupp",
        [[
module lib.ann

@annotation(targets = {"record", "struct"})
export record tag
    name: string?
end

export function noop(): nil
end
]]
    )
    for index = 1, 6 do
        write(
            directory .. ("/src/use%d.nupp"):format(index),
            ([[
const ann = require("lib.ann")

@tag(name = "x")
local record Marked%d
    value: number = 0
end

local function make(): number
    ann.noop()
    local marked = new Marked%d(value = 1)
    return marked.value
end

return {make = make}
]]):format(index, index)
        )
    end

    local serialCode, serialReport, serialState = coldCheck(directory, {NUPP_CHECK_JOBS = "1"})
    assertEq(serialCode, 0, "serial fixture: " .. json.encode(serialReport.diagnostics))
    local code, report, state = coldCheck(directory, {NUPP_CHECK_JOBS = "4"})
    assertEq(report.timing.parallel.mode, "parallel", "parallel timing mode")
    assertEq(#report.diagnostics, 0, "parallel diagnostics: " .. json.encode(report.diagnostics))
    assertEq(code, 0, "parallel exit status")
    assertEq(state, serialState, "parallel check records")
    local warmCode, warmOutput = process.capture({NUPP, "check", "--json"}, {cwd = directory})
    assertEq(warmCode, 0, "the warm check reuses clean records: " .. warmOutput)

    assert(require("nupp.io.files").remove(directory, true))
end

-- A build generates in the worker that checked, so what a parallel build writes has
-- to be what the serial build writes, byte for byte, at every optimization level.
function M.parallelBuildsWriteWhatSerialBuildsWrite()
    local directory = tempProject(false)
    for _, level in ipairs({"-O0", "-O2"}) do
        local serialCode, serialReport, serialOutputs, serialState = coldBuild(
            directory,
            {NUPP_CHECK_JOBS = "1"},
            {level}
        )
        assertEq(serialCode, 0, level .. " serial build: " .. json.encode(serialReport.diagnostics))
        local code, report, outputs, state = coldBuild(directory, {NUPP_CHECK_JOBS = "3"}, {level})
        assertEq(code, 0, level .. " parallel build: " .. json.encode(report.diagnostics))
        assertEq(report.timing.parallel.mode, "parallel", level .. " parallel timing mode")
        assertEq(report.timing.parallel.rechecked, 0, level .. " worker records survive validation")
        assertEq(outputs, serialOutputs, level .. " build outputs")
        assertEq(state, serialState, level .. " build state")
    end

    assert(require("nupp.io.files").remove(directory, true))
end

-- Const specialization is planned across every module of a build at once. A
-- project declaring a const-generic function is built in one process, and says so;
-- its check, which plans nothing, still uses workers.
function M.constGenericProjectsBuildSerially()
    local directory = tempProject(false)
    write(
        directory .. "/src/scaled.nupp",
        [[
local function doubled<const N: integer>(value: number, count: N): number
    local total = value
    for _ = 1, count as integer do
        total = total * 2.0
    end
    return total
end

local function four(): number
    return doubled(1, 2)
end

return {four = four}
]]
    )
    local code, report = coldBuild(directory, {NUPP_CHECK_JOBS = "2"}, {"-O2"})
    assertEq(code, 0, "const-generic build: " .. json.encode(report.diagnostics))
    assertEq(report.timing.parallel.mode, "serial", "the build stays in one process")
    assert(
        tostring(report.timing.parallel.reason):find("const-generic", 1, true),
        "the build says why: " .. tostring(report.timing.parallel.reason)
    )
    local checkCode, checkReport = coldCheck(directory, {NUPP_CHECK_JOBS = "2"})
    assertEq(checkCode, 0, "const-generic check")
    assertEq(checkReport.timing.parallel.mode, "parallel", "a check plans no specialization")

    assert(require("nupp.io.files").remove(directory, true))
end

function M.workerAndInterfaceFailuresFallBackWithoutPublishingPartialState()
    local directory = tempProject(false)
    local serialCode, _, serialState = coldCheck(directory, {NUPP_CHECK_JOBS = "1"})
    assertEq(serialCode, 0, "serial fixture")

    -- `exit` stops a worker before the scan, `hang` outlives the request deadline,
    -- `interface` damages every interface a worker sends so the consumer's decode
    -- refuses it, and `crash` stops a worker in every check, restarted or not.
    for _, failure in ipairs({"exit", "hang", "interface", "crash"}) do
        local code, report, state = coldCheck(directory, {
            NUPP_CHECK_JOBS = "2",
            NUPP_TEST_PARALLEL_CHECK_FAILURE = failure,
        })
        assertEq(code, 0, failure .. " fallback exit status")
        assertEq(report.timing.parallel.mode, "serial-fallback", failure .. " fell back")
        assertEq(state, serialState, failure .. " fallback records")
        if failure == "crash" then
            assert(report.timing.parallel.retries >= 1, "a crashed worker was restarted before falling back")
        end
    end

    -- One worker stopping mid-check is restarted, and the run stays parallel.
    local code, report, state = coldCheck(directory, {
        NUPP_CHECK_JOBS = "2",
        NUPP_TEST_PARALLEL_CHECK_FAILURE = "crash-once",
    })
    assertEq(code, 0, "restarted worker exit status")
    assertEq(report.timing.parallel.mode, "parallel", "a restarted worker keeps the check parallel")
    assertEq(report.timing.parallel.retries, 1, "the stopped worker was retried once")
    assertEq(state, serialState, "restarted worker records")

    assert(require("nupp.io.files").remove(directory, true))
end

function M.anInterruptedCheckLeavesNoWorkers()
    if package.config:sub(1, 1) == "\\" then
        return
    end
    local ffi = require("ffi")
    pcall(ffi.cdef, "int kill(int, int);")
    local lookup = assert(io.popen("command -v perl"))
    local perl = lookup:read("*l")
    lookup:close()
    if not perl or perl == "" then
        return
    end
    local directory = tempProject(false)
    local pidFile = directory .. "/workers.pid"
    local activeFile = directory .. "/active.pid"
    local child = assert(process.startIsolated({
        perl,
        "-MPOSIX=:signal_h",
        "-e",
        '$SIG{INT}="DEFAULT"; my $s=POSIX::SigSet->new(SIGINT); '
            .. "sigprocmask(SIG_UNBLOCK,$s); POSIX::setpgid(0,0); exec @ARGV;",
        NUPP,
        "check",
        "--quiet",
    }, {
        cwd = directory,
        env = {
            NUPP_CHECK_JOBS = "2",
            NUPP_PARALLEL_CHECK_TRACE = "1",
            NUPP_TEST_PARALLEL_CHECK_PAUSE_MS = "1000",
            NUPP_TEST_PARALLEL_CHECK_ACTIVE_FILE = activeFile,
            NUPP_TEST_PARALLEL_CHECK_PID_FILE = pidFile,
        },
    }))
    -- Generous: the waits end as soon as the workers are up, and a loaded host can
    -- take several seconds to start two compilers.
    local deadline = time.now() + 60000
    local pids = workerPids(pidFile)
    while countKeys(pids) < 2 do
        assert(time.now() < deadline, "parallel workers did not start")
        time.sleep(10)
        pids = workerPids(pidFile)
    end
    while next(workerPids(activeFile)) == nil do
        assert(time.now() < deadline, "parallel workers did not begin a request")
        time.sleep(10)
    end
    assertEq(ffi.C.kill(-child.pid, 2), 0, "send SIGINT")
    local exit = child:wait()
    local said = ""
    while true do
        local chunk = child.stderr:poll()
        if chunk == nil then
            break
        end
        said = said .. chunk
    end
    child:close()
    assert(
        not exit:succeeded(),
        ("the interrupted check did not stop: code=%s killed=%s timedOut=%s"):format(
            tostring(exit.exitCode),
            tostring(exit.killed),
            tostring(exit.timedOut)
        )
            .. " output="
            .. said
    )

    deadline = time.now() + 60000
    for pid in pairs(pids) do
        while ffi.C.kill(pid, 0) == 0 and time.now() < deadline do
            time.sleep(10)
        end
        assert(ffi.C.kill(pid, 0) ~= 0, "parallel worker survived its interrupted parent: " .. tostring(pid))
    end

    assert(require("nupp.io.files").remove(directory, true))
end

return M
