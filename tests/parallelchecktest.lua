local cache = require("nupp.tools.build.cache")
local fingerprint = require("nupp.compiler.project.fingerprint")
local fs = require("nupp.compiler.fs")
local json = require("testjson")
local modules = require("nupp.tools.build.modules")
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

local function noInterfaceStore(directory)
    local entries = require("nupp.io.files").list(directory .. "/build/cache") or {}
    for _, entry in ipairs(entries) do
        assert(not entry.name:find("^parallel%-check%-"), "parallel interface store survived: " .. entry.name)
    end
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
    noInterfaceStore(directory)

    return code, report, checkState(directory)
end

local M = {}

function M.workerPolicyKeepsSmallChecksSerialAndCapsAutomaticParallelism()
    assertEq(modules.parallelCheckPlan(63, 1048576, 8, nil).workers, 1, "module floor")
    assertEq(modules.parallelCheckPlan(64, 262143, 8, nil).workers, 1, "byte floor")
    assertEq(modules.parallelCheckPlan(64, 262144, 8, nil).workers, 6, "automatic cap")
    assertEq(modules.parallelCheckPlan(64, 262144, 2, nil).workers, 2, "available workers")
    assertEq(modules.parallelCheckPlan(4, 16, 8, 8).workers, 4, "explicit count")
    assertEq(modules.parallelCheckPlan(64, 262144, 8, 1).workers, 1, "serial escape hatch")
end

function M.parallelChecksMatchSerialRecordsAndDiagnosticsAcrossSchedules()
    local directory = tempProject(true)
    local serialCode, serialReport, serialState = coldCheck(directory, {NUPP_CHECK_JOBS = "1"})
    assertEq(serialCode, 1, "the fixture reports its authored errors")
    assertEq(serialReport.timing.parallel.mode, "serial", "one requested worker")

    for _, run in ipairs({{jobs = "2", seed = "17"}, {jobs = "3", seed = "83"}}) do
        local code, report, state = coldCheck(directory, {
            NUPP_CHECK_JOBS = run.jobs,
            NUPP_PARALLEL_CHECK_RANDOM_SEED = run.seed,
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

function M.workerAndInterfaceFailuresFallBackWithoutPublishingPartialState()
    local directory = tempProject(false)
    local serialCode, _, serialState = coldCheck(directory, {NUPP_CHECK_JOBS = "1"})
    assertEq(serialCode, 0, "serial fixture")

    for _, failure in ipairs({"start", "exit", "hang", "interface"}) do
        os.remove(directory .. "/build/cache/checks.buf")
        local code, output = process.capture({NUPP, "check", "--quiet"}, {
            cwd = directory,
            env = {
                NUPP_CHECK_JOBS = "2",
                NUPP_PARALLEL_CHECK_TRACE = "1",
                NUPP_TEST_PARALLEL_CHECK_FAILURE = failure,
            },
        })
        assertEq(code, 0, failure .. " fallback exit status")
        assert(output:find("parallel cold check fell back:", 1, true), failure .. " did not report its fallback: " .. output)
        assertEq(checkState(directory), serialState, failure .. " fallback records")
        noInterfaceStore(directory)
    end

    assert(require("nupp.io.files").remove(directory, true))
end

function M.anInterruptedCheckLeavesNoWorkersAndItsStoreIsScavenged()
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
    local deadline = time.now() + 5000
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

    deadline = time.now() + 5000
    for pid in pairs(pids) do
        while ffi.C.kill(pid, 0) == 0 and time.now() < deadline do
            time.sleep(10)
        end
        assert(ffi.C.kill(pid, 0) ~= 0, "parallel worker survived its interrupted parent: " .. tostring(pid))
    end

    local stale = directory .. "/build/cache/parallel-check-crashed"
    assert(process.run(process.mkdirCommand(stale)) == 0)
    write(stale .. "/partial.buf", "partial")
    time.sleep(10)
    local code = process.capture({NUPP, "check", "--quiet"}, {
        cwd = directory,
        env = {
            NUPP_CHECK_JOBS = "2",
            NUPP_TEST_PARALLEL_CHECK_STALE = "1",
        },
    })
    assertEq(code, 0, "check after interrupted store")
    noInterfaceStore(directory)
    assert(require("nupp.io.files").remove(directory, true))
end

return M
