-- Minimal test runner: loads tests/*test.lua and compiles tests/*test.nupp,
-- runs every function in the returned table, and reports failures with their
-- assert message. A suite may also define beforeAll, afterAll, beforeEach,
-- and afterEach lifecycle hooks.
--
-- With --json it reports the same run as one document: a record per test with
-- where it is defined, how long it took, and — when it failed — the message and
-- the file and line the error came from. Standard output and error from a test
-- are held back unless it fails or --verbose asks for them. Lines are 1-based,
-- as everywhere else; a Lua error carries no column, so none is invented.
-- The JSON codec is taken once, before any suite loads. A suite may legitimately
-- clear `package.loaded` to prove something loads lazily, and a suite that fails
-- part way through such a proof leaves it cleared. Acquiring the codec after the
-- run means one misbehaving suite turns the whole shard's report into "the shard
-- wrote no report", which loses every other suite's result and reads like an
-- infrastructure failure rather than the one test that broke.
local runnerPath = arg[0]
local dir = rawget(_G, "__NUPP_TEST_DIR")
if not dir then
    if package.config:sub(1, 1) == "\\" then
        runnerPath = runnerPath:gsub("^/([A-Za-z])(/)", function(drive, slash)
            return drive:upper() .. ":" .. slash
        end)
    end
    dir = runnerPath:match("^(.*)[/\\]") or "."
end
local buildDir = os.getenv("NUPP_COVERAGE_BUILD") or os.getenv("NUPP_TEST_BUILD") or "build"
local absoluteBuild = buildDir:match("^[/\\]") or buildDir:match("^[A-Za-z]:[/\\]")
local buildRoot = absoluteBuild and buildDir or dir .. "/../" .. buildDir
package.path = buildRoot .. "/?.lua;" .. dir .. "/?.lua;" .. package.path
-- A runner copied out of the repository -- which is how its own suite exercises
-- it as the program a person runs -- resolves the two paths above against
-- wherever it was copied to, so the compiled modules it loads before doing
-- anything are not on either of them. This names where they actually are.
local modulesRoot = os.getenv("NUPP_TEST_MODULES")
if modulesRoot and modulesRoot ~= "" then
    package.path = modulesRoot .. "/?.lua;" .. modulesRoot .. "/?/init.lua;" .. package.path
end

package.preload.testjson = package.preload.testjson or function()
    local native = require("nupp.codec.json")

    local json = {
        NULL = native.NULL,
        EMPTY_ARRAY = native.EMPTY_ARRAY,
        EMPTY_OBJECT = native.EMPTY_OBJECT,
        arrayOf = native.arrayOf,
        asArray = native.asArray,
        asObject = native.asObject,
        isArray = native.isArray,
        encode = native.encode,
        serialize = native.serialize,
        writer = native.writer,
    }

    function json.decode(text)
        return native.decode(text, native.NULL)
    end

    function json.pull(text, shape)
        return native.pull(text, shape, native.NULL)
    end

    return json
end

local testJson = require("testjson")
local embedded = rawget(_G, "__NUPP_TEST_EMBEDDED") == true
local workerHost = rawget(_G, "__NUPP_TEST_WORKER_HOST") == true

-- `tmpnam` draws from a sequence that starts again in every process, so two
-- shards running at once are handed the same name, make the same directory, and
-- one writes the sample the other is about to compile. What is reported then
-- belongs to neither of them: a parse error against source the test that failed
-- never wrote.
--
-- Impossible while the whole suite ran in one process, which is what kept it
-- hidden until the shards arrived. Salted with both the shard and process, then
-- counted within the process, so a nested runner cannot restart the same name
-- sequence inside its parent's shard.
--
-- Every platform, not just Windows, which is where this started. A suite that
-- builds a library into its temporary directory, loads it, and is still holding
-- it when another shard is handed the same name and clears it out does not get
-- a confusing diagnostic: it gets the library deleted from under a live mapping
-- and a segmentation fault with nothing on the stack. That is what the Linux
-- workers were dying of, four at a time, in whichever suite they happened to be
-- in. macOS never showed it because its `tmpnam` template is per-process
-- already.
-- The name it answers is created here, because that is what it replaces:
-- LuaJIT's `os.tmpname` reserves the name by making the file, and a caller that
-- opens it for writing is reopening something that exists and is already its
-- own. Handing back a name for a file nobody had made left the capture path
-- creating it through `open` with a mode that never had to work before, and the
-- output could then not be read back by name. Callers that want a directory
-- remove it first, as they did before.
local rawTmpname = os.tmpname
local processSalt
do
    local stateSalt = tostring({}):match("0x(%x+)") or tostring(os.clock())
    local loaded, ffi = pcall(require, "ffi")
    if loaded then
        if ffi.os == "Windows" then
            ffi.cdef[[int _getpid(void);]]
            processSalt = tostring(ffi.C._getpid()) .. "-" .. stateSalt
        else
            ffi.cdef[[int getpid(void);]]
            processSalt = tostring(ffi.C.getpid()) .. "-" .. stateSalt
        end
    else
        -- Official Lua already reserves a process-distinct temporary name on
        -- the platforms where the portable compiler runs. Retain a state-local
        -- discriminator as a second boundary when FFI is unavailable.
        processSalt = stateSalt .. "-" .. tostring(os.time())
    end
end
local shardSalt = ((os.getenv("NUPP_CACHE_DIR") or ""):match("shard%-(%d+)") or "0") .. "-" .. processSalt
local handedOut = 0
os.tmpname = function()
    handedOut = handedOut + 1
    local reserved = rawTmpname()
    local named = ("%s-%s-%d"):format((reserved:gsub("\\", "/")), shardSalt, handedOut)
    -- LuaJIT reserves this name on Unix, while its Windows `tmpnam` only names a
    -- path. Keep an existing reservation by renaming it; otherwise create the
    -- salted name, and never hand a caller a path that was not actually made.
    local renamed = os.rename(reserved, named)
    if not renamed then
        local file, problem = io.open(named, "wb")
        assert(file, ("cannot reserve temporary name %s: %s"):format(named, tostring(problem)))
        file:close()
        -- If rename failed for a reason other than an absent source, do not leave
        -- the raw reservation behind for the length of the run.
        os.remove(reserved)
    end

    return named
end

-- The suites predate Windows support and deliberately exercise shell-facing
-- CLI behaviour with POSIX commands. On Windows the VM's `system` and `popen`
-- otherwise hand those commands to cmd.exe even though the runner itself was
-- launched by Git Bash. Keep one shell dialect for the tests, and keep native
-- paths for the Windows programs those commands start.
if package.config:sub(1, 1) == "\\" then
    local rawExecute, rawPopen = os.execute, io.popen
    -- Rejected empty as well as absent: an undefined workflow variable reaches a
    -- step as the empty string, which is true in Lua, so a bare `assert` let it
    -- through and every shelled-out command became `""` instead.
    local bash = os.getenv("NUPP_TEST_BASH")
    assert(bash and bash ~= "", "NUPP_TEST_BASH must name Git Bash on Windows")
    local nativeMarker = "__NUPP_WINDOWS_COMMAND__"
    _G.__NUPP_TEST_CMD_MARKER = nativeMarker
    _G.__NUPP_TEST_BASH = bash

    local function usesTestShell(source)
        return source == "@nupp:test-runner"
            or source:find("/tests/", 1, true) ~= nil
            or source:match("^@?tests/") ~= nil
    end

    -- Asked for when a test wants it, not while this file loads. `io.popen` is
    -- refused in a shared worker lane, and a `pwd` nothing has asked for yet is
    -- no reason to be refused: reading it eagerly failed every Nupp worker on
    -- Windows the moment the suite got far enough to start one, and took every
    -- suite in those lanes down as unrun with it.
    local cwdValue

    local function currentDirectory()
        if not cwdValue then
            local pipe = assert(rawPopen("cd"))
            cwdValue = assert(pipe:read("*l")):gsub("\\", "/")
            pipe:close()
        end

        return cwdValue
    end

    local function script(command)
        command = command:gsub("(%a):/", function(drive)
            return "/" .. drive:lower() .. "/"
        end)
        local path = os.tmpname() .. ".sh"
        local file = assert(io.open(path, "wb"))
        file:write(command, "\n")
        file:close()

        return path
    end

    local function invocation(path)
        -- cmd.exe strips the first pair of quotes from a command line that starts
        -- with a quoted executable. The outer pair preserves the executable and
        -- script as two quoted arguments.
        return ('""%s" "%s""'):format(bash:gsub('"', '\\"'), path:gsub('"', '\\"'))
    end

    local function shellExecute(command)
        local path = script(command)
        local result = rawExecute(invocation(path))
        os.remove(path)

        return result
    end

    local function shellPopen(command, mode)
        local path = script(command)
        local pipe = assert(rawPopen(invocation(path), mode))
        local proxy = {}
        function proxy:read(...)
            return pipe:read(...)
        end

        function proxy:lines(...)
            return pipe:lines(...)
        end

        function proxy:close()
            local result = {pipe:close()}
            os.remove(path)
            return unpack(result)
        end

        return proxy
    end

    _G.__NUPP_TEST_SHELL_EXECUTE = shellExecute
    _G.__NUPP_TEST_SHELL_POPEN = shellPopen

    os.execute = function(command)
        if type(command) ~= "string" then
            return rawExecute(command)
        end
        if command:sub(1, #nativeMarker) == nativeMarker then
            return rawExecute(command:sub(#nativeMarker + 1))
        end
        local caller = debug.getinfo(2, "S")
        local source = caller and caller.source:gsub("\\", "/") or ""
        if not usesTestShell(source) then
            return rawExecute(command)
        end

        return shellExecute(command)
    end

    io.popen = function(command, mode)
        if command:sub(1, #nativeMarker) == nativeMarker then
            return rawPopen(command:sub(#nativeMarker + 1), mode)
        end
        local caller = debug.getinfo(2, "S")
        local source = caller and caller.source:gsub("\\", "/") or ""
        if not usesTestShell(source) then
            return rawPopen(command, mode)
        end
        if command == "pwd" then
            local unread = true
            return {
                read = function()
                    if not unread then
                        return nil
                    end
                    unread = false

                    return currentDirectory()
                end,
                lines = function()
                    return function()
                        if not unread then
                            return nil
                        end
                        unread = false

                        return currentDirectory()
                    end
                end,
                close = function()
                    return true
                end,
            }
        end

        return shellPopen(command, mode)
    end
end

local caseDefinitions = setmetatable({}, {__mode = "k"})
rawset(_G, "__NUPP_TEST_CASE_DEFINITIONS", caseDefinitions)
local test = require("nupp.test")

-- Existing suites use Lua's familiar assert spelling.  Give those assertions
-- useful falsy diagnostics, while `require("nupp.test")` exposes equal, matches,
-- raises and skip for new assertions that can say exactly what differed.
assert = test.assert

local asJson = false
local verbose = false
-- Suites named on the command line. A list rather than one name: `nupp test a b`
-- used to keep whichever came last and silently run something else, or nothing.
local only = nil
local chosen = {}
local chosenSet = nil
-- Exact stable case IDs selected directly, read from a previous report, or
-- inherited from a parent queue. Queue inheritance lets a mixed impact result
-- retain case precision without making its whole-suite portion run serially.
local chosenCases = {}
local chosenCaseCount = 0
local requestedCases = {}
local requestedCaseCount = 0
local seenCaseIds = {}
local missingCaseIds = {}
-- A lifecycle-hook failure is a suite failure, not a selectable case. A rerun
-- executes that whole suite so a repaired beforeAll or afterAll still proves
-- its cases rather than turning into an empty green run.
local wholeSuites = {}
local SYNTHETIC_CASES = {["<shard>"] = true, ["<unrun>"] = true,}
local rerunReport = nil
-- Suites this process is to run, when a parent has split them up. Empty means "decide
-- for yourself", which is what the run a person starts does.
local shard = {}
-- Named coverage a workflow asked for, and coverage it asked to be left out.
-- A group expands to suite names once the suites have been discovered, because
-- a group may be a glob and a glob has nothing to expand against until then.
local chosenGroups = {}
local excludedNames = {}
local excludedGroups = {}
-- Which execution lane to keep: `shared` runs in Nupp worker states, `shell`
-- shares reusable process workers, and `isolated` needs a process boundary
-- around its runtime state. A full run combines the latter two on one process
-- worker queue, but they remain separate answers to `--lane`.
local lane = nil
-- `--list-suites` and `--list-groups` answer what a run would cover without
-- running it, which is what a workflow author and its review need.
local listing = nil
-- Impact selection belongs to the bundled runner. A bare flag compares the
-- working tree with HEAD; a value compares it with the merge base of that ref
-- and HEAD. Selection is applied after discovery and explicit positive filters,
-- but before listing or worker planning.
local diffRequested = false
local diffRef = nil
local explainSelection = false
local diffShadow = false
local impactRecordId = nil
-- Where the work this process is to take from lives, when a parent handed out a
-- queue rather than a list. Empty means "decide for yourself" the same way an
-- empty shard does.
local queueDir = nil
-- An isolated queue worker is a supervisor only. It claims work dynamically,
-- but runs every claimed piece in a new process so process-global state cannot
-- cross the suite boundary.
local freshQueuePieces = os.getenv("NUPP_TEST_FRESH_QUEUE_PIECES") == "1"
local supervisedPiece = os.getenv("NUPP_TEST_SUPERVISED_PIECE") == "1"
local jobs = nil
local colorMode = "auto"
local colorSeen = false
local colorProblem = nil
-- How many rows the timing report shows, and whether it shows one at all. A run
-- always measures; this only decides how much of the measurement is printed.
-- `--timings` on its own means every suite and every test, which is what a
-- person asking where the time went wants.
local timingRows = 15
for _, argument in ipairs(arg) do
    if argument == "--json" then
        asJson = true
    elseif argument == "--verbose" then
        verbose = true
    elseif argument == "--color" then
        if colorSeen and colorMode ~= "always" then
            colorProblem = "color was both asked for and refused"
        end
        colorMode, colorSeen = "always", true
    elseif argument == "--no-color" then
        if colorSeen and colorMode ~= "never" then
            colorProblem = "color was both asked for and refused"
        end
        colorMode, colorSeen = "never", true
    elseif argument:match("^%-%-color=") then
        local wanted = argument:match("^%-%-color=(.*)$")
        if wanted ~= "always" and wanted ~= "never" and wanted ~= "auto" then
            colorProblem = "--color must be always, never, or auto"
        elseif colorSeen and colorMode ~= wanted then
            colorProblem = "color was both asked for and refused"
        else
            colorMode, colorSeen = wanted, true
        end
    elseif argument == "--timings" then
        timingRows = math.huge
    elseif argument:match("^%-%-timings=") then
        timingRows = tonumber(argument:match("^%-%-timings=(%d+)$")) or timingRows
    elseif argument:match("^%-%-jobs=") then
        jobs = tonumber(argument:match("^%-%-jobs=(%d+)$"))
    elseif argument:match("^%-%-queue=") then
        queueDir = argument:sub(#"--queue=" + 1)
    elseif argument:match("^%-%-shard=") then
        for name in argument:sub(#"--shard=" + 1):gmatch("[^,]+") do
            shard[#shard + 1] = name
        end
    elseif argument:match("^%-%-group=") then
        for name in argument:sub(#"--group=" + 1):gmatch("[^,]+") do
            chosenGroups[#chosenGroups + 1] = name
        end
    elseif argument:match("^%-%-exclude=") then
        for name in argument:sub(#"--exclude=" + 1):gmatch("[^,]+") do
            excludedNames[#excludedNames + 1] = name
        end
    elseif argument:match("^%-%-exclude%-group=") then
        for name in argument:sub(#"--exclude-group=" + 1):gmatch("[^,]+") do
            excludedGroups[#excludedGroups + 1] = name
        end
    elseif argument:match("^%-%-lane=") then
        lane = argument:sub(#"--lane=" + 1)
        if lane ~= "shared" and lane ~= "shell" and lane ~= "isolated" then
            io.stderr:write("nupp: --lane must be shared, shell, or isolated\n")
            os.exit(2)
        end
    elseif argument == "--list-suites" then
        listing = "suites"
    elseif argument == "--list-cases" then
        listing = "cases"
    elseif argument == "--list-groups" then
        listing = "groups"
    elseif argument == "--diff" then
        diffRequested = true
    elseif argument:match("^%-%-diff=") then
        diffRequested = true
        diffRef = argument:sub(#"--diff=" + 1)
        if diffRef == "" then
            io.stderr:write("nupp: --diff=REF requires a revision\n")
            os.exit(2)
        end
    elseif argument == "--explain-selection" then
        explainSelection = true
    elseif argument == "--shadow" then
        diffShadow = true
    elseif argument:match("^%-%-internal%-impact%-record=") then
        impactRecordId = argument:sub(#"--internal-impact-record=" + 1)
        if impactRecordId == "" then
            io.stderr:write("nupp: internal impact recording requires a run ID\n")
            os.exit(2)
        end
    elseif argument:match("^%-%-internal%-whole%-suite=") then
        local name = argument:sub(#"--internal-whole-suite=" + 1)
        if name == "" then
            io.stderr:write("nupp: internal whole-suite selection requires a suite name\n")
            os.exit(2)
        end
        wholeSuites[name] = true
    elseif argument:match("^%-%-case=") then
        local id = argument:sub(#"--case=" + 1)
        if id == "" then
            io.stderr:write("nupp: --case requires a stable case ID\n")
            os.exit(2)
        end
        if not chosenCases[id] then
            chosenCases[id] = true
            chosenCaseCount = chosenCaseCount + 1
            requestedCases[id] = true
            requestedCaseCount = requestedCaseCount + 1
        end
    elseif argument:match("^%-%-rerun=") then
        if rerunReport ~= nil then
            io.stderr:write("nupp: --rerun may be specified only once\n")
            os.exit(2)
        end
        rerunReport = argument:sub(#"--rerun=" + 1)
    elseif argument:sub(1, 1) ~= "-" then
        chosen[#chosen + 1] = argument
        only = #chosen == 1 and argument or nil
    else
        io.stderr:write("nupp: unknown test option: " .. argument .. "\n")
        os.exit(2)
    end
end
if colorProblem then
    io.stderr:write("nupp: " .. colorProblem .. "\n")
    os.exit(2)
end
if explainSelection and not diffRequested then
    io.stderr:write("nupp: --explain-selection requires --diff or --diff=REF\n")
    os.exit(2)
end
if diffShadow and not diffRequested then
    io.stderr:write("nupp: --shadow requires --diff or --diff=REF\n")
    os.exit(2)
end
if queueDir then
    local selectionFile = io.open(queueDir .. "/selection.json", "rb")
    if selectionFile then
        local encoded = selectionFile:read("*a") or ""
        selectionFile:close()
        local ok, inherited = pcall(testJson.decode, encoded)
        if not ok or type(inherited) ~= "table" then
            io.stderr:write("nupp: test queue selection metadata is invalid\n")
            os.exit(2)
        end
        for _, id in ipairs(inherited.cases or {}) do
            if type(id) ~= "string" or id == "" then
                io.stderr:write("nupp: test queue contains an invalid case ID\n")
                os.exit(2)
            elseif not chosenCases[id] then
                chosenCases[id] = true
                chosenCaseCount = chosenCaseCount + 1
            end
        end
        for _, name in ipairs(inherited.wholeSuites or {}) do
            if type(name) ~= "string" or name == "" then
                io.stderr:write("nupp: test queue contains an invalid whole-suite selection\n")
                os.exit(2)
            end
            wholeSuites[name] = true
        end
    end
end
local unfilteredTopLevel = #chosen == 0
    and #chosenGroups == 0
    and #excludedNames == 0
    and #excludedGroups == 0
    and lane == nil
    and listing == nil
    and rerunReport == nil
    and not diffRequested
    and #shard == 0
    and queueDir == nil
    and chosenCaseCount == 0
local impactFacadeAvailable = package.loaded["runner.impact"] ~= nil
if not impactFacadeAvailable then
    local loaded = pcall(require, "runner.impact")
    impactFacadeAvailable = loaded
end
if unfilteredTopLevel and impactFacadeAvailable and os.getenv("NUPP_TEST_IMPACT_RECORD") ~= "0" then
    impactRecordId = ("%d-%s"):format(os.time(), processSalt)
end
local impactRecording = impactRecordId ~= nil
local impactObserve = impactRecording and require("nupp.compiler.testimpact.observe") or nil
local impactFs = impactRecording and require("nupp.compiler.fs") or nil
local impactFragmentDir = impactRecording
    and impactFs.absolute(buildRoot .. "/.nupp-test-impact-run/" .. impactRecordId)
    or nil
if impactFragmentDir then
    assert(impactFs.mkdir(impactFragmentDir), "cannot create the test-impact fragment directory")
    if unfilteredTopLevel then
        local fragmentRoot = impactFs.dirname(impactFragmentDir)
        local files = require("nupp.io.files")
        local entries = files.list(fragmentRoot) or {}
        local staleBefore = os.time() - 86400
        for _, entry in ipairs(entries) do
            local timestamp = tonumber(entry.name:match("^(%d+)%-"))
            if entry.kind == "directory" and timestamp and timestamp < staleBefore then
                local removed, problem = files.remove(impactFs.join(fragmentRoot, entry.name), true)
                if not removed then
                    io.stderr:write(
                        "nupp: cannot remove abandoned test-impact fragments: " .. tostring(problem) .. "\n"
                    )
                end
            end
        end
    end
end
local impactObserver = impactObserve and impactObserve.new({
    runId = impactRecordId,
    platform = (jit and (jit.os .. "/" .. jit.arch)) or _VERSION,
    projectRoot = impactFs.absolute("."),
    fragmentDir = impactFragmentDir,
    compiler = os.getenv("NUPP_TEST_BIN") or tostring(arg[0]),
    childNamespace = processSalt,
}) or nil
local impactFragments = {}
local impactSliceSafe = {}
local selectionReport = nil
local selectionRequestedSuites = nil
local selectionRequestedCases = nil
local selectionRequestedCaseScope = false
if impactObserver then
    impactObserve.activate(impactObserver)
end
if rerunReport ~= nil then
    local file, problem = io.open(rerunReport, "rb")
    if not file then
        io.stderr:write(("nupp: cannot read failure report %s: %s\n"):format(rerunReport, tostring(problem)))
        os.exit(2)
    end
    local text = file:read("*a") or ""
    file:close()
    local decoded, report = pcall(testJson.decode, text)
    if not decoded or type(report) ~= "table" or type(report.tests) ~= "table" then
        io.stderr:write(("nupp: %s is not a test JSON report\n"):format(rerunReport))
        os.exit(2)
    end
    local rerunFailureCount = 0
    local rerunSelectionCount = 0
    for _, record in ipairs(report.tests) do
        if type(record) == "table" and record.status == "failed" then
            rerunFailureCount = rerunFailureCount + 1
            local id = record.id
            if type(id) ~= "string" and type(record.suite) == "string" and type(record.name) == "string" then
                -- Reports written before stable IDs can still be rerun without
                -- turning their old shape into the new report contract.
                id = record.suite .. "/" .. record.name
            end
            if type(id) ~= "string" then
                io.stderr:write(("nupp: failed test in %s has no stable ID\n"):format(rerunReport))
                os.exit(2)
            elseif record.name == "<shard>" then
                -- A worker-level failure is followed by one `<unrun>` record for every
                -- queue piece it failed to report. Those records name real suites; this
                -- aggregate names the worker and is not itself a selectable case.
            elseif (record.name == "beforeAll" or record.name == "afterAll" or record.name == "<unrun>")
                and type(record.suite) == "string"
            then
                wholeSuites[record.suite] = true
                chosen[#chosen + 1] = record.suite
                rerunSelectionCount = rerunSelectionCount + 1
            else
                rerunSelectionCount = rerunSelectionCount + 1
                if not chosenCases[id] then
                    chosenCases[id] = true
                    chosenCaseCount = chosenCaseCount + 1
                    requestedCases[id] = true
                    requestedCaseCount = requestedCaseCount + 1
                end
            end
        end
    end
    if rerunFailureCount == 0 then
        io.stderr:write(("nupp: %s contains no failed tests\n"):format(rerunReport))
        os.exit(2)
    elseif rerunSelectionCount == 0 then
        io.stderr:write(("nupp: %s contains no rerunnable failed tests\n"):format(rerunReport))
        os.exit(2)
    end
end
if chosenCaseCount > 0 and not queueDir then
    for id in pairs(chosenCases) do
        local suite = id:match("^([^/]+)/.+$")
        if not suite then
            io.stderr:write(("nupp: invalid stable case ID %s (expected suite/case)\n"):format(id))
            os.exit(2)
        end
        chosen[#chosen + 1] = suite
    end
end
if #chosen > 0 then
    chosenSet = {}
    for _, name in ipairs(chosen) do
        chosenSet[name] = true
    end
end

-- Tests often run a command specifically to make it print a diagnostic. Lua's
-- `io.output` cannot capture that command's inherited descriptors, so redirect
-- the descriptors themselves. The runner keeps duplicates for its own progress
-- marks, which must stay visible while a test owns the usual stdout and stderr.
local capture
local progressWrite
local useColor = false
local pauseBriefly = nil
local exclusiveCreate = nil
local silenceProcessOutput = function()
    return function()
    end
end
-- The descriptor the marks go to, for handing to a worker.
--
-- A worker cannot be told "your parent's standard output": `popen` has already
-- made that the pipe the report comes back on, and a mark written there lands in
-- the middle of the document. So the parent keeps a duplicate of its own stream
-- and lets the worker inherit it, which is a descriptor that still means the
-- terminal on the other side of the fork.
local progressFd = nil
local sharedProgressStream = false
-- Read before the block below stops exporting it, so this process still traces
-- while the nested runners its cases launch do not.
local traceCases = os.getenv("NUPP_TEST_TRACE_CASES") ~= nil
do
    local loaded, ffi = pcall(require, "ffi")
    if loaded then
        if ffi.os == "Windows" then
            ffi.cdef[[
            int _dup(int);
            int _dup2(int, int);
            int _open(const char *, int, int);
            int _close(int);
            int fflush(void *);
            int _write(int, const void *, unsigned int);
            int _isatty(int);
            int _putenv_s(const char *, const char *);
            void Sleep(unsigned long);
         ]]
        else
            ffi.cdef[[
            int dup(int);
            int dup2(int, int);
            int open(const char *, int, int);
            int close(int);
            int fflush(void *);
            long write(int, const void *, unsigned long);
            int isatty(int);
            int unsetenv(const char *);
            int usleep(unsigned int);
         ]]
        end
        local C = ffi.C
        local create = ffi.os == "Windows" and 0x0100 or (ffi.os == "OSX" and 0x200 or 0x40)
        local exclusive = ffi.os == "Windows" and 0x0400 or (ffi.os == "OSX" and 0x800 or 0x80)
        local truncate = ffi.os == "Windows" and 0x0200 or (ffi.os == "OSX" and 0x400 or 0x200)
        local binary = ffi.os == "Windows" and 0x8000 or 0
        local dup = ffi.os == "Windows" and C._dup or C.dup
        local dup2 = ffi.os == "Windows" and C._dup2 or C.dup2
        local open = ffi.os == "Windows" and C._open or C.open
        local close = ffi.os == "Windows" and C._close or C.close
        local write = ffi.os == "Windows" and C._write or C.write
        local isatty = ffi.os == "Windows" and C._isatty or C.isatty
        exclusiveCreate = function(path)
            local fd = open(path, create + exclusive + 1 + binary, tonumber("600", 8))
            if fd < 0 then
                return false
            end
            local stamp = tostring(os.time()) .. "\n"
            local stamped = tonumber(write(fd, stamp, #stamp)) == #stamp
            close(fd)
            if not stamped then
                os.remove(path)
                error("cannot timestamp exclusive lock " .. path, 0)
            end

            return true
        end
        pauseBriefly = ffi.os == "Windows" and function()
            C.Sleep(20)
        end or function()
            C.usleep(20000)
        end
        silenceProcessOutput = function()
            local function flush()
                io.stdout:flush();
                io.stderr:flush();
                C.fflush(nil)
            end

            flush()
            local savedOut, savedErr = dup(1), dup(2)
            local null = open(ffi.os == "Windows" and "NUL" or "/dev/null", 1 + binary, 384)
            assert(savedOut >= 0 and savedErr >= 0 and null >= 0, "cannot silence worker output")
            assert(dup2(null, 1) >= 0 and dup2(null, 2) >= 0, "cannot redirect worker output")
            close(null)

            return function()
                flush()
                assert(dup2(savedOut, 1) >= 0 and dup2(savedErr, 2) >= 0, "cannot restore worker output")
                close(savedOut);
                close(savedErr)
            end
        end
        -- Where a mark goes.
        --
        -- Ordinarily the runner's own stream: standard output, or standard error
        -- when the document is on standard output. A worker is told a descriptor
        -- instead, because its standard error is a file the parent keeps to ask why
        -- it died with, and a mark written there is a mark nobody sees. That is what
        -- made a sharded run silent: every worker was marking work off into its own
        -- file while the terminal waited for the first one to finish.
        local named = tonumber(rawget(_G, "__NUPP_TEST_PROGRESS_FD") or os.getenv("NUPP_TEST_PROGRESS_FD") or "")
        sharedProgressStream = named ~= nil
        local statusFd = named and dup(named) or dup(asJson and 2 or 1)
        progressFd = statusFd

        -- This descriptor is for one runner process, not an ambient destination
        -- for commands its tests launch. Keeping the variable would make a nested
        -- `nupp test` bypass that test's capture and write into this progress line.
        local function stopExporting(variable)
            if os.getenv(variable) == nil then
                return
            end
            if ffi.os == "Windows" then
                pcall(C._putenv_s, variable, "")
            else
                pcall(C.unsetenv, variable)
            end
        end

        if named then
            stopExporting("NUPP_TEST_PROGRESS_FD")
        end
        -- The same argument, for the same reason, one variable along.
        --
        -- `NUPP_TEST_TRACE_CASES` makes a runner name each case on standard
        -- error, so a worker killed by a signal says where it was. It is a
        -- setting for this runner process: `traceCases` above is read before
        -- this, and a worker gets the behaviour from having been given a
        -- progress descriptor rather than from the environment. Left exported,
        -- it reaches every nested `nupp test` a case launches -- and a case that
        -- asserts on a nested runner's exact output then fails because of how
        -- the outer run was invoked, which is what happened the first time CI
        -- ran this variable across a whole group rather than one suite.
        stopExporting("NUPP_TEST_TRACE_CASES")
        stopExporting("NUPP_TEST_FRESH_QUEUE_PIECES")
        stopExporting("NUPP_TEST_SUPERVISED_PIECE")

        local terminal = false
        local detected, answer = pcall(isatty, statusFd)
        if detected then
            terminal = answer ~= 0
        end

        local function requested(name)
            local value = os.getenv(name)
            return value ~= nil and value ~= "" and value ~= "0"
        end

        if colorMode == "always" then
            useColor = true
        elseif colorMode == "never" or requested("NO_COLOR") then
            useColor = false
        elseif requested("CLICOLOR_FORCE") then
            useColor = true
        else
            useColor = terminal and os.getenv("TERM") ~= "dumb"
        end

        progressWrite = function(text)
            write(statusFd, text, #text)
        end

        local function flush()
            io.stdout:flush();
            io.stderr:flush();
            C.fflush(nil)
        end

        local function read(path)
            local f = assert(io.open(path, "rb"), "cannot read captured test output")
            local text = f:read("*a")
            f:close()
            os.remove(path)

            return text
        end

        capture = embedded and function(run)
            -- File descriptors belong to the process, not to a Lua state. Redirecting
            -- them from several worker threads would make one test capture another's
            -- output and occasionally restore the wrong descriptor. Worker jobs keep
            -- Lua failures associated with their cases; suites that specifically test
            -- runner capture stay in the process-isolated lane below.
            local active = {stdout = {}, stderr = {}}
            rawset(_G, "__NUPP_TEST_CAPTURE", active)
            local originalPrint, originalWrite = print, io.write
            local originalStdout, originalStderr = io.stdout, io.stderr
            local fileOut, fileErr = assert(io.tmpfile()), assert(io.tmpfile())
            io.stdout, io.stderr = fileOut, fileErr
            print = function(...)
                local values = {}
                for index = 1, select("#", ...) do
                    values[index] = tostring(select(index, ...))
                end
                active.stdout[#active.stdout + 1] = table.concat(values, "\t") .. "\n"
            end
            io.write = function(...)
                for index = 1, select("#", ...) do
                    active.stdout[#active.stdout + 1] = tostring(select(index, ...))
                end
                return true
            end
            local ok, problem = pcall(run)
            fileOut:flush();
            fileErr:flush()
            fileOut:seek("set", 0);
            fileErr:seek("set", 0)
            active.stdout[#active.stdout + 1] = fileOut:read("*a") or ""
            active.stderr[#active.stderr + 1] = fileErr:read("*a") or ""
            print, io.write = originalPrint, originalWrite
            io.stdout, io.stderr = originalStdout, originalStderr
            fileOut:close();
            fileErr:close()
            rawset(_G, "__NUPP_TEST_CAPTURE", nil)

            return ok, problem, table.concat(active.stdout), table.concat(active.stderr)
        end or function(run)
            local outPath, errPath = os.tmpname(), os.tmpname()
            flush()
            local savedOut, savedErr = dup(1), dup(2)
            local out = open(outPath, 1 + create + truncate + binary, 384)
            local err = open(errPath, 1 + create + truncate + binary, 384)
            assert(savedOut >= 0 and savedErr >= 0 and out >= 0 and err >= 0, "cannot capture test output")
            assert(dup2(out, 1) >= 0 and dup2(err, 2) >= 0, "cannot redirect test output")
            close(out);
            close(err)
            local ok, problem = pcall(run)
            flush()
            assert(dup2(savedOut, 1) >= 0 and dup2(savedErr, 2) >= 0, "cannot restore test output")
            close(savedOut);
            close(savedErr)

            return ok, problem, read(outPath), read(errPath)
        end
    else
        -- The runner remains useful on a LuaJIT without descriptor access, but a
        -- host that cannot redirect descriptors cannot hide child-process output.
        local forced = os.getenv("CLICOLOR_FORCE")
        local refused = os.getenv("NO_COLOR")
        useColor = colorMode == "always"
            or (
                colorMode == "auto"
                and (refused == nil or refused == "" or refused == "0")
                and forced ~= nil
                and forced ~= ""
                and forced ~= "0"
            )
        progressWrite = function(text)
            local stream = asJson and io.stderr or io.stdout
            stream:write(text);
            stream:flush()
        end
        capture = function(run)
            local ok, problem = pcall(run)
            return ok, problem, "", ""
        end
    end
end

if supervisedPiece then
    -- The supervisor owns the one progress mark for this queue piece. The fresh
    -- child still captures case output normally, but stays silent on the shared
    -- progress stream so a many-case suite remains one scheduling mark.
    progressWrite = function()
    end
end

local RESET = "\27[0m"

local function paint(code, text)
    return useColor and ("\27[" .. code .. "m" .. text .. RESET) or text
end

local function progressHeading(text)
    return paint("1;36", text)
end

-- Wall clock, because most of what these tests spend time on is a subprocess,
-- which no measure of this process's own CPU time would ever see. The FFI is
-- guarded the same way nupp.cli guards it: a build without it still runs the
-- tests, it just reports coarser times.
local now
do
    local ok, ffi = pcall(require, "ffi")
    if ok then
        -- tv_usec is a long on Linux and an int on the BSDs, and reading it at
        -- the wrong width is how a timer silently returns nonsense.
        local micros = ffi.os == "Linux" and "long" or "int"
        local declared = pcall(
            ffi.cdef,
            (
                [[
         struct nupp_timeval { long tv_sec; %s tv_usec; };
         int gettimeofday(struct nupp_timeval *, void *);
      ]]
            ):format(micros)
        )
        if declared then
            local tv = ffi.new("struct nupp_timeval[1]")
            local called = pcall(function()
                ffi.C.gettimeofday(tv, nil)
            end)
            if called then
                now = function()
                    ffi.C.gettimeofday(tv, nil)
                    return tonumber(tv[0].tv_sec) * 1000 + tonumber(tv[0].tv_usec) / 1000
                end
            end
        end
    end
    now = now or function()
        return os.clock() * 1000
    end
end

-- A shard entry is a suite name, or `name#index/count` for one slice of a suite too
-- heavy to be left whole. A slice takes the cases whose position falls in it, which is
-- well defined because the case list is sorted before anything runs.
--
-- A list per suite rather than one entry, because packing is free to put two slices of
-- the same suite in one shard. Keyed singly, the second replaced the first and took its
-- cases with it: a run reported 1768 of 1790 tests and called itself green.
local wanted = nil
if #shard > 0 then
    wanted = {}
    for _, entry in ipairs(shard) do
        local name, index, count = entry:match("^(.-)#(%d+)/(%d+)$")
        name = name or entry
        local slices = wanted[name] or {}
        wanted[name] = slices
        slices[#slices + 1] = {index = tonumber(index) or 0, count = tonumber(count) or 1,}
    end
end

local suites = {}
-- Every suite there is, by name, whether or not this process was asked for it.
-- A process working from a queue does not know what it will run until it claims
-- it, so it cannot filter the listing the way one handed a list can.
local byName = {}
local discovered = {}
local suiteCatalog = {}
local explicitlyRemoved = {}
do
    local function found(f)
        local name, extension = f:match("^(.*test)%.([^.]+)$")
        if name and (extension == "lua" or extension == "nupp") then
            local info = {name = name, extension = extension}
            byName[name] = info
            discovered[#discovered + 1] = info
            suiteCatalog[#suiteCatalog + 1] = f
        end
    end

    local inherited = rawget(_G, "__NUPP_TEST_SUITE_CATALOG")
    if type(inherited) == "string" then
        for f in inherited:gmatch("[^\n]+") do
            found(f)
        end
    else
        local p = assert(io.popen("ls '" .. dir .. "'"), "cannot list test directory")
        for f in p:lines() do
            found(f)
        end
        p:close()
    end
end
table.sort(suiteCatalog)
suiteCatalog = table.concat(suiteCatalog, "\n")

--- The named groups, or an empty set when the file a checkout carries is absent.
--- Absent is only reachable from a runner copied out of the repository, which is
--- how the runner's own suite exercises it; a copy that names no group needs no
--- group definitions.
local function groupDefinitions()
    local loaded, definitions = pcall(dofile, dir .. "/groups.lua")
    if not loaded or type(definitions) ~= "table" then
        return {}
    end

    return definitions
end

--- Every suite a group names, by name. A member is a suite name or a `*` glob
--- over suite names. A member matching nothing is an error: a group that
--- silently covers less than it says is the failure this file exists to end.
local function expandGroup(name, definitions)
    local members = definitions[name]
    if not members then
        local known = {}
        for group in pairs(definitions) do
            known[#known + 1] = group
        end
        table.sort(known)
        io.stderr:write(("nupp: no test group named %s (have %s)\n"):format(name, table.concat(known, ", ")))
        os.exit(2)
    end

    local matched = {}
    for _, member in ipairs(members) do
        local hits = 0
        if member:find("*", 1, true) then
            local pattern = "^" .. member:gsub("[%^%$%(%)%%%.%[%]%+%-%?]", "%%%0"):gsub("%*", ".*") .. "$"
            for _, info in ipairs(discovered) do
                if info.name:match(pattern) then
                    matched[info.name], hits = true, hits + 1
                end
            end
        elseif byName[member] then
            matched[member], hits = true, 1
        end
        if hits == 0 then
            io.stderr:write(("nupp: test group %s names %s, which matches no suite\n"):format(name, member))
            os.exit(2)
        end
    end

    return matched
end

do
    local definitions = nil

    local function definitionsOnce()
        definitions = definitions or groupDefinitions()
        return definitions
    end

    for _, name in ipairs(chosenGroups) do
        chosenSet = chosenSet or {}
        for suite in pairs(expandGroup(name, definitionsOnce())) do
            chosenSet[suite] = true
        end
    end

    -- Exclusion answers "run everything this workflow has not already run",
    -- which is how a focused early gate stops being repeated verbatim inside
    -- the later broad one.
    for _, name in ipairs(excludedNames) do
        if not byName[name] then
            io.stderr:write(("nupp: no test suite named %s to exclude\n"):format(name))
            os.exit(2)
        end
        explicitlyRemoved[name] = true
    end
    for _, name in ipairs(excludedGroups) do
        for suite in pairs(expandGroup(name, definitionsOnce())) do
            explicitlyRemoved[suite] = true
        end
    end

    if listing == "groups" then
        local names = {}
        for name in pairs(definitionsOnce()) do
            names[#names + 1] = name
        end
        table.sort(names)
        for _, name in ipairs(names) do
            local members = {}
            for suite in pairs(expandGroup(name, definitionsOnce())) do
                members[#members + 1] = suite
            end
            table.sort(members)
            io.stdout:write(("%s: %s\n"):format(name, table.concat(members, " ")))
        end
        os.exit(0)
    end

    for _, info in ipairs(discovered) do
        local name = info.name
        if not explicitlyRemoved[name]
            and (not chosenSet or chosenSet[name])
            and (not wanted or wanted[name])
            and not queueDir
        then
            suites[#suites + 1] = info
        end
    end
end

table.sort(suites, function(a, b)
    return a.name .. "." .. a.extension < b.name .. "." .. b.extension
end)

local impactStamps = nil
local impactGraph = nil
local impactSuiteSliceSafe = nil
local runnablePlan = nil
if diffRequested then
    local requestedSuites = {}
    for _, info in ipairs(suites) do
        requestedSuites[#requestedSuites + 1] = info
    end
    local requestedCases = {}
    for id in pairs(chosenCases) do
        requestedCases[id] = true
    end
    local requestedCaseTotal = chosenCaseCount
    selectionRequestedSuites = requestedSuites
    selectionRequestedCases = requestedCases
    selectionRequestedCaseScope = requestedCaseTotal > 0
    local impactDiff = require("nupp.compiler.testimpact.diff")
    local discoveredDiff = impactDiff.discover({cwd = ".", ref = diffRef})
    if not discoveredDiff.available then
        io.stderr:write("nupp: " .. tostring(discoveredDiff.reason) .. "\n")
        os.exit(2)
    end
    impactStamps = {
        project = discoveredDiff.root,
        revision = discoveredDiff.base,
        operatingSystem = (jit and jit.os) or package.config:sub(1, 1),
        architecture = (jit and jit.arch) or "portable",
        runtime = (jit and jit.version) or _VERSION,
        targetProfile = "test",
        suiteCatalog = suiteCatalog ~= "" and suiteCatalog or "empty",
        stableIds = "suite-path+case-name/1",
    }
    local cacheBefore = now()
    impactGraph = require("nupp.compiler.testimpact.store").load(buildRoot .. "/.nupp-test-impact.buf", impactStamps)
    local cacheMs = now() - cacheBefore
    local selected
    if impactGraph then
        selected = require("nupp.compiler.testimpact.selection").select(impactGraph, discoveredDiff)
    else
        selected = {
            base = discoveredDiff.base,
            changedPaths = discoveredDiff.paths,
            affectedModules = {},
            selectedSuites = {},
            selectedCases = {},
            promotions = {},
            fallbacks = {{code = "graph-miss", reason = "no exact compatible impact graph is available",},},
            completeScope = true,
            conservative = true,
        }
    end

    local function suiteName(path)
        local file = tostring(path):gsub("\\", "/"):match("([^/]+)$") or tostring(path)
        return file:match("^(.*test)%.[^.]+$")
    end

    if impactGraph then
        impactSuiteSliceSafe = {}
        for suiteId, pathId in ipairs(impactGraph.suites or {}) do
            local name = suiteName(impactGraph.paths and impactGraph.paths[pathId])
            if name then
                impactSuiteSliceSafe[name] = impactGraph.suiteSliceSafe[suiteId] == true
                    and #((impactGraph.suiteUncertainty and impactGraph.suiteUncertainty[suiteId]) or {}) == 0
            end
        end
        -- A positive fact describes the suite at the graph revision. A change to
        -- the suite itself, or a suite-level module edge selected by the diff,
        -- may have added lifecycle state since then. Uncertainty-only promotion
        -- does not make an otherwise unchanged suite's recorded shape stale.
        for _, reason in ipairs(selected.reasons or {}) do
            if reason.kind == "suite" and (reason.code == "suite-source-changed" or reason.code == "module-impact") then
                local name = suiteName(reason.suite)
                if name then
                    impactSuiteSliceSafe[name] = false
                end
            end
        end
    end

    if not selected.completeScope then
        local requestedNames = {}
        for _, info in ipairs(suites) do
            requestedNames[info.name] = true
        end
        if requestedCaseCount > 0 then
            chosenCases = {}
            chosenCaseCount = 0
        end
        local selectedNames = {}
        local excludedImpact = {}
        for _, path in ipairs(selected.selectedSuites or {}) do
            local name = suiteName(path)
            if name and requestedNames[name] then
                if requestedCaseCount > 0 then
                    for id in pairs(requestedCases) do
                        if id:sub(1, #name + 1) == name .. "/" then
                            selectedNames[name] = true
                            chosenCases[id] = true
                            chosenCaseCount = chosenCaseCount + 1
                        end
                    end
                else
                    selectedNames[name] = true
                    wholeSuites[name] = true
                end
            elseif name and explicitlyRemoved[name] then
                excludedImpact[name] = true
            end
        end
        for _, item in ipairs(selected.selectedCases or {}) do
            local name = suiteName(item.suite)
            local id = name and (name .. "/" .. item.caseId) or nil
            if name and requestedNames[name] and (requestedCaseCount == 0 or requestedCases[id]) then
                selectedNames[name] = true
                if not chosenCases[id] then
                    chosenCases[id] = true
                    chosenCaseCount = chosenCaseCount + 1
                end
            elseif name and explicitlyRemoved[name] then
                excludedImpact[name] = true
            end
        end
        local excludedImpactNames = {}
        for name in pairs(excludedImpact) do
            excludedImpactNames[#excludedImpactNames + 1] = name
        end
        table.sort(excludedImpactNames)
        for _, name in ipairs(excludedImpactNames) do
            selected.fallbacks[
                #selected.fallbacks + 1
            ] = {
                code = "user-excluded",
                reason = "an explicit exclusion removed impacted suite " .. name,
                suite = name,
            }
        end
        local kept = {}
        for _, info in ipairs(suites) do
            if selectedNames[info.name] then
                kept[#kept + 1] = info
            end
        end
        suites = kept
        if #suites == 0 then
            selected.emptyReason = selected.emptyReason or "outside-requested-scope"
        end
    end

    -- Turn the selection into the runnable shape before prediction, lane
    -- filtering, and sharding. The graph's case catalog is exact for its
    -- revision, so selecting that complete catalog is equivalent to selecting
    -- the whole suite. Keep the exact IDs as validation witnesses even after
    -- coalescing: workers must still acknowledge every ID the query selected.
    local graphCatalog = {}
    if impactGraph then
        for suiteId, pathId in ipairs(impactGraph.suites or {}) do
            local name = suiteName(impactGraph.paths and impactGraph.paths[pathId])
            if name then
                graphCatalog[name] = {cases = {}, count = 0,}
            end
        end
        for _, item in ipairs(impactGraph.cases or {}) do
            local pathId = impactGraph.suites and impactGraph.suites[item[1]]
            local name = suiteName(impactGraph.paths and impactGraph.paths[pathId])
            local catalog = name and graphCatalog[name] or nil
            local caseName = item[2]
            if catalog and type(caseName) == "string" and not catalog.cases[caseName] then
                catalog.cases[caseName] = true
                catalog.count = catalog.count + 1
            end
        end
    end
    runnablePlan = {}
    for _, info in ipairs(suites) do
        local prefix = info.name .. "/"
        local caseIds = {}
        local caseNames = {}
        for id in pairs(chosenCases) do
            if id:sub(1, #prefix) == prefix then
                caseIds[#caseIds + 1] = id
                caseNames[#caseNames + 1] = id:sub(#prefix + 1)
            end
        end
        table.sort(caseIds)
        table.sort(caseNames)

        local whole = wholeSuites[info.name] == true or (selected.completeScope == true and requestedCaseTotal == 0)
        local catalog = graphCatalog[info.name]
        local catalogEqual = catalog ~= nil and #caseNames == catalog.count
        if catalogEqual then
            for _, caseName in ipairs(caseNames) do
                if not catalog.cases[caseName] then
                    catalogEqual = false
                    break
                end
            end
        end
        if not whole and #caseNames > 0 and catalogEqual then
            whole = true
            wholeSuites[info.name] = true
        end

        local sliceSafe = nil
        if impactSuiteSliceSafe then
            sliceSafe = impactSuiteSliceSafe[info.name]
        end
        -- An ID absent from the recorded catalog proves that the positive shape
        -- fact cannot describe this request. Run it as one piece so validation
        -- fails before lifecycle state or duplicate top-level discovery.
        if catalog and #caseNames > 0 then
            for _, caseName in ipairs(caseNames) do
                if not catalog.cases[caseName] then
                    sliceSafe = false
                    break
                end
            end
        elseif #caseNames > 0 then
            sliceSafe = false
        end

        runnablePlan[info.name] = {whole = whole, caseIds = caseIds, caseNames = caseNames, sliceSafe = sliceSafe,}
    end

    local selectedSuiteNames = {}
    for _, info in ipairs(suites) do
        if runnablePlan[info.name] and runnablePlan[info.name].whole then
            selectedSuiteNames[#selectedSuiteNames + 1] = info.name
        end
    end
    local selectedCaseIds = {}
    for _, info in ipairs(suites) do
        local plan = runnablePlan[info.name]
        if plan and not plan.whole then
            for _, id in ipairs(plan.caseIds) do
                selectedCaseIds[#selectedCaseIds + 1] = id
            end
        end
    end
    table.sort(selectedSuiteNames)
    table.sort(selectedCaseIds)
    local selectedSuiteSet = {}
    for _, name in ipairs(selectedSuiteNames) do
        selectedSuiteSet[name] = true
    end
    local selectedCaseSet = {}
    for _, id in ipairs(selectedCaseIds) do
        selectedCaseSet[id] = true
    end
    local selectionReasons = {}
    for _, reason in ipairs(selected.reasons or {}) do
        local name = suiteName(reason.suite)
        local id = name and reason.caseId and (name .. "/" .. reason.caseId) or nil
        if name and (selectedSuiteSet[name] or (id and selectedCaseSet[id])) then
            local kept = {}
            for key, value in pairs(reason) do
                kept[key] = value
            end
            kept.suite = name
            selectionReasons[#selectionReasons + 1] = kept
        end
    end

    local function reasons(records)
        local out = {}
        for _, record in ipairs(records or {}) do
            out[
                #out + 1
            ] = {code = record.code, reason = record.reason, owner = record.suite or record.path or record.caseId,}
        end

        return out
    end

    selectionReport = {
        version = 1,
        mode = "diff",
        shadow = diffShadow,
        base = discoveredDiff.base,
        graphRevision = impactGraph and discoveredDiff.base or nil,
        changedPaths = testJson.asArray(discoveredDiff.paths),
        affectedModules = testJson.asArray(selected.affectedModules or {}),
        selectedSuites = testJson.asArray(selectedSuiteNames),
        selectedCases = testJson.asArray(selectedCaseIds),
        reasons = testJson.asArray(selectionReasons),
        promotions = testJson.asArray(reasons(selected.promotions)),
        fallbacks = testJson.asArray(reasons(selected.fallbacks)),
        complete = selected.completeScope == true,
        cacheMs = cacheMs,
        queryMs = now() - cacheBefore,
        emptyReason = selected.emptyReason,
    }
    if diffShadow then
        suites = requestedSuites
        chosenCases = requestedCases
        chosenCaseCount = requestedCaseTotal
        wholeSuites = {}
        runnablePlan = nil
    end
    local stream = asJson and io.stderr or io.stdout
    stream:write(
        (
            "%s: %d changed paths, %d affected modules, %d suites and %d cases selected\n"
        ):format(
            diffShadow and "impact shadow" or "impact",
            #selectionReport.changedPaths,
            #selectionReport.affectedModules,
            #selectionReport.selectedSuites,
            #selectionReport.selectedCases
        )
    )
    if explainSelection then
        for _, path in ipairs(selectionReport.changedPaths) do
            stream:write("  " .. path .. "\n")
        end
        for _, reason in ipairs(selectionReport.promotions) do
            stream:write(("  promote %s: %s\n"):format(reason.owner or "selection", reason.reason))
        end
        for _, reason in ipairs(selectionReport.reasons) do
            local owner = reason.suite or "selection"
            if reason.caseId then
                owner = owner .. "/" .. reason.caseId
            end
            local through = reason.module and (" <- " .. reason.module) or ""
            stream:write(("  select %s%s: %s\n"):format(owner, through, reason.reason))
        end
        for _, reason in ipairs(selectionReport.fallbacks) do
            stream:write(("  fallback %s: %s\n"):format(reason.code, reason.reason))
        end
    end
end

local function loadSuite(suite)
    local path = dir .. "/" .. suite.name .. "." .. suite.extension
    if suite.extension == "lua" then
        return dofile(path)
    end

    -- A Nupp suite is an ordinary module after compilation. Keep its runtime
    -- loader installed while its cases run so it may require project modules.
    local compile = require("nupp.compiler.cli.compile")
    -- The runner is invoked from the project root, just as `nupp test` runs
    -- its configured command. Keep this root normalized for module lookup.
    local env = require("nupp.compiler.env").new(".")
    local settings = compile.settings({})
    local code, compileErr = compile.module(path, env, settings)
    if not code then
        error("cannot compile Nupp test suite " .. path .. ": " .. tostring(compileErr), 0)
    end
    local removeLoader = require("nupp.compiler.runtime").install(env, function(modulePath, e)
        return compile.module(modulePath, e, settings)
    end)
    local chunk, loadErr = loadstring(code, "@" .. path)
    if not chunk then
        removeLoader()
        error("cannot load Nupp test suite " .. path .. ": " .. tostring(loadErr), 0)
    end
    local ok, loaded = pcall(chunk)
    if not ok then
        removeLoader()
        error(loaded, 0)
    end

    return loaded, removeLoader
end

--- Where a test function is written, which is stable and worth reporting even
--- when it passes.
local function definedAt(fn)
    local parameterized = caseDefinitions[fn]
    if parameterized ~= nil then
        return parameterized.file, parameterized.line
    end
    local info = debug.getinfo(fn, "S")
    if not info then
        return nil, nil
    end

    return (info.source or ""):gsub("^@", ""), info.linedefined
end

--- Splits "tests/foo.lua:42: message" into its parts. A Lua error need not carry
--- a position at all, so the message is returned whole when it does not.
local function errorPosition(message)
    local file, line, rest = tostring(message):match("^(.-):(%d+): (.*)$")
    if not file then
        return tostring(message), nil, nil
    end

    return rest, file, tonumber(line)
end

local results = {}
-- One record per suite this process ran, so the report can say where the time
-- went at the granularity the shards are packed at. A suite is more than the sum
-- of its cases: loading it compiles a Nupp suite and runs a Lua one's top level,
-- and `beforeAll` can be the most expensive thing in the file. None of that
-- belongs to any single case, so measuring only cases loses it.
local suiteRecords = {}
local total, passed, failed, skipped, notExecutedCount = 0, 0, 0, 0, 0
local started = now()
local progressWidth = 0

-- Whether this process is the only one marking on its stream.
--
-- A worker is not: it was handed a descriptor its siblings are also writing to,
-- so the column its own marks would be at is not the column the stream is at.
-- Counting anyway is what made a sharded run break its lines at 573, 35 and 510
-- characters -- each worker faithfully wrapping at its own eightieth mark, thirty
-- six of them, into one stream.
--
-- So a worker writes marks and nothing else, and the run that owns the stream
-- closes the line when the workers are done.
local ownsProgressStream = not sharedProgressStream

local function mark(symbol)
    local styled = symbol == "." and paint("32", symbol)
        or (symbol == "S" or symbol == "N") and paint("1;33", symbol)
        or paint("1;31", symbol)
    progressWrite(styled)
    if not ownsProgressStream then
        return
    end
    progressWidth = progressWidth + 1
    if progressWidth == 80 then
        progressWrite("\n")
        progressWidth = 0
    end
end

local function captured(record)
    local output = record.output
    if not output or (output.stdout == "" and output.stderr == "") then
        return ""
    end
    local lines = {"\n  Output from " .. record.suite .. " / " .. record.name .. ":\n"}
    if output.stdout ~= "" then
        lines[#lines + 1] = "    stdout:\n" .. output.stdout
    end
    if output.stderr ~= "" then
        lines[#lines + 1] = "    stderr:\n" .. output.stderr
    end
    if lines[#lines]:sub(-1) ~= "\n" then
        lines[#lines + 1] = "\n"
    end

    return table.concat(lines)
end

local function showCaptured(record)
    local text = captured(record)
    if text == "" then
        return
    end
    local stream = asJson and io.stderr or io.stdout
    stream:write(text)
    stream:flush()
end

local HOOKS = {beforeAll = true, afterAll = true, beforeEach = true, afterEach = true,}

local function suiteParts(suiteInfo, suite)
    local hooks = {}
    local cases = {}
    for name, fn in pairs(suite) do
        if type(name) ~= "string" or name == "" then
            error(("test suite %s has a case whose name is not a non-empty string"):format(suiteInfo.name), 0)
        elseif name:find("[%c]") then
            error(("test suite %s has a case name containing a control character"):format(suiteInfo.name), 0)
        elseif SYNTHETIC_CASES[name] then
            error(("test suite %s uses reserved case name %s"):format(suiteInfo.name, name), 0)
        elseif type(fn) ~= "function" then
            error(("test suite %s entry %s is not a function"):format(suiteInfo.name, name), 0)
        elseif HOOKS[name] then
            hooks[name] = fn
        else
            cases[#cases + 1] = name
        end
    end
    table.sort(cases)

    return hooks, cases
end

local function call(fn)
    if fn == nil then
        return true
    end
    return pcall(fn)
end

local fixtureRoot = buildRoot .. "/test-fixtures"
local fixtureSerial = 0
local FIXTURE_LEASE_SECONDS = 15 * 60
local fixtureDigest = require("nupp.compiler.build.cache").contentDigest(true)

local function readJson(path)
    local file = io.open(path, "rb")
    if not file then
        return nil, "missing"
    end
    local text = file:read("*a") or ""
    file:close()
    local ok, value = pcall(testJson.decode, text)

    return ok and value or nil, ok and "valid" or "invalid"
end

local function fixtureManifest(root)
    local files = require("nupp.io.files")
    local manifest = {}

    local function walk(directory, prefix)
        for _, entry in ipairs(files.list(directory) or {}) do
            local relative = prefix == "" and entry.name or prefix .. "/" .. entry.name
            local path = directory .. "/" .. entry.name
            if relative ~= ".nupp-fixture.json" then
                if entry.kind == "directory" then
                    manifest[#manifest + 1] = {path = relative, kind = "directory"}
                    local ok, problem = walk(path, relative)
                    if not ok then
                        return nil, problem
                    end
                elseif entry.kind == "file" then
                    local file, problem = io.open(path, "rb")
                    if not file then
                        return nil, tostring(problem)
                    end
                    local content = file:read("*a")
                    file:close()
                    if content == nil then
                        return nil, "cannot read fixture artifact " .. path
                    end
                    manifest[#manifest + 1] = {path = relative, kind = "file", digest = fixtureDigest(content)}
                else
                    return nil, "fixture artifacts must be regular files or directories: " .. path
                end
            end
        end

        return true
    end

    local ok, problem = walk(root, "")
    if not ok then
        return nil, problem
    end
    table.sort(manifest, function(a, b)
        return a.path < b.path
    end)

    return manifest
end

local function fixtureMetadata(path, published, key)
    local value, state = readJson(path)
    if state == "missing" then
        return nil, "missing"
    elseif state ~= "valid"
        or type(value) ~= "table"
        or value.version ~= 1
        or value.key ~= key
        or type(value.files) ~= "table"
    then
        return nil, "invalid"
    end
    local storedCount = 0
    for index in pairs(value.files) do
        if type(index) ~= "number" or index < 1 or index ~= math.floor(index) then
            return nil, "invalid"
        end
        storedCount = storedCount + 1
    end
    local actual = fixtureManifest(published)
    if actual == nil or #actual ~= storedCount then
        return nil, "invalid"
    end
    for index = 1, storedCount do
        local expected = value.files[index]
        local found = actual[index]
        if type(expected) ~= "table"
            or type(expected.path) ~= "string"
            or (expected.kind ~= "file" and expected.kind ~= "directory")
            or expected.path ~= found.path
            or expected.kind ~= found.kind
            or expected.digest ~= found.digest
        then
            return nil, "invalid"
        end
    end

    return value, "valid"
end

local function writeText(path, text)
    local file, problem = io.open(path, "wb")
    if not file then
        error(("cannot write %s: %s"):format(path, tostring(problem)), 0)
    end
    file:write(text)
    file:close()
end

--- Finds or produces one immutable content-addressed fixture.
---
--- The lock is an exclusive-create file rather than a directory existence
--- check. Directory creation is intentionally idempotent on every supported
--- provider and therefore cannot say which worker won.
local function resolveFixture(key, produce)
    if type(key) ~= "string" or key == "" or not key:match("^[A-Za-z0-9._-]+$") then
        error("fixture keys must contain only letters, digits, dot, underscore, and hyphen", 2)
    elseif type(produce) ~= "function" then
        error("fixture producer must be a function", 2)
    elseif not exclusiveCreate then
        error("content-addressed fixtures require exclusive file creation on this runtime", 2)
    end

    local files = require("nupp.io.files")
    local made, makeProblem = files.createDirectory(fixtureRoot)
    if not made then
        error("cannot create fixture store: " .. tostring(makeProblem), 2)
    end
    local slot = "fixture-" .. fixtureDigest("nupp-test-fixture\0" .. key)
    local published = fixtureRoot .. "/" .. slot
    local metadata = published .. "/.nupp-fixture.json"
    local failure = fixtureRoot .. "/" .. slot .. ".failed.json"
    local lock = fixtureRoot .. "/" .. slot .. ".lock"

    local cached = fixtureMetadata(metadata, published, key)
    if cached ~= nil then
        return published, cached.value, true
    end
    local failedFixture = readJson(failure)
    if failedFixture ~= nil then
        error("fixture " .. key .. " failed: " .. tostring(failedFixture.message), 2)
    end

    if exclusiveCreate(lock) then
        fixtureSerial = fixtureSerial + 1
        -- Recheck after taking the lock: another producer may have published
        -- between the optimistic read and this exclusive create. If a published
        -- directory has missing or corrupt metadata, quarantine it atomically
        -- before rebuilding. Cache corruption costs one cold production and
        -- never asks the caller to repair the store by hand.
        cached = fixtureMetadata(metadata, published, key)
        if cached ~= nil then
            os.remove(lock)
            return published, cached.value, true
        elseif files.exists(published) then
            local quarantine = fixtureRoot .. "/." .. slot .. ".corrupt-" .. shardSalt .. "-" .. fixtureSerial
            files.remove(quarantine, true)
            local quarantined, quarantineProblem = files.rename(published, quarantine)
            if not quarantined then
                os.remove(lock)
                error("cannot quarantine corrupt fixture " .. key .. ": " .. tostring(quarantineProblem), 2)
            end
            local removed, removeProblem = files.remove(quarantine, true)
            if not removed then
                os.remove(lock)
                error("cannot remove corrupt fixture " .. key .. ": " .. tostring(removeProblem), 2)
            end
        end
        local temporary = fixtureRoot .. "/." .. slot .. ".tmp-" .. shardSalt .. "-" .. fixtureSerial
        files.remove(temporary, true)
        local prepared, prepareProblem = files.createDirectory(temporary)
        if not prepared then
            os.remove(lock)
            error("cannot prepare fixture " .. key .. ": " .. tostring(prepareProblem), 2)
        end
        local ok, value = pcall(produce, temporary)
        if ok then
            local files, manifestProblem = fixtureManifest(temporary)
            local encoded, document = false, nil
            if files == nil then
                ok, value = false, "fixture artifacts cannot be recorded: " .. tostring(manifestProblem)
            else
                encoded, document = pcall(testJson.encode, {version = 1, key = key, value = value, files = files})
                if not encoded then
                    ok, value = false, "fixture value is not JSON-compatible: " .. tostring(document)
                else
                    local wrote, writeProblem = pcall(writeText, temporary .. "/.nupp-fixture.json", document .. "\n")
                    if not wrote then
                        ok, value = false, writeProblem
                    end
                end
            end
        end
        if ok then
            local moved, moveProblem = files.rename(temporary, published)
            os.remove(lock)
            if not moved then
                files.remove(temporary, true)
                error("cannot publish fixture " .. key .. ": " .. tostring(moveProblem), 2)
            end

            return published, value, false
        end

        files.remove(temporary, true)
        local failureWritten, failureProblem = pcall(
            writeText,
            failure,
            testJson.encode({
                message = tostring(value)
            }) .. "\n"
        )
        os.remove(lock)
        if not failureWritten then
            error("fixture " .. key .. " failed and its result could not be published: " .. tostring(failureProblem), 2)
        end
        error("fixture " .. key .. " failed: " .. tostring(value), 2)
    end

    local deadline = os.time() + 10 * 60
    while os.time() < deadline do
        cached = fixtureMetadata(metadata, published, key)
        if cached ~= nil then
            return published, cached.value, true
        end
        failedFixture = readJson(failure)
        if failedFixture ~= nil then
            error("fixture " .. key .. " failed: " .. tostring(failedFixture.message), 2)
        end
        if pauseBriefly then
            pauseBriefly()
        end
    end
    error(
        "timed out waiting for fixture "
        .. key
        .. "; lock is "
        .. lock
        .. " (remove it after confirming no producer is running)",
        2
    )
end

-- A failed producer fans its result out to every consumer in one run. A new
-- top-level run gets one new attempt; immutable successful fixtures remain. A
-- killed producer can leave its exclusive-create lock behind. Producers belong
-- under the ten-minute cold-suite budget, so a new top-level run atomically
-- reaps locks older than fifteen minutes while leaving a live producer alone.
if not queueDir and #shard == 0 then
    pcall(function()
        local files = require("nupp.io.files")
        for _, entry in ipairs(files.list(fixtureRoot) or {}) do
            if entry.name:match("%.failed%.json$") then
                files.remove(fixtureRoot .. "/" .. entry.name)
            elseif entry.name:match("%.lock$") then
                local path = fixtureRoot .. "/" .. entry.name
                local file = io.open(path, "rb")
                local created = file and tonumber(file:read("*l") or "") or nil
                if file then
                    file:close()
                end
                local cutoff = os.time() - FIXTURE_LEASE_SECONDS
                local information = not created and files.info(path) or nil
                local stale = created and created <= cutoff
                    or information ~= nil and tonumber(information.modified) <= cutoff
                if stale then
                    fixtureSerial = fixtureSerial + 1
                    local claimed = path .. ".stale-" .. shardSalt .. "-" .. fixtureSerial
                    if files.rename(path, claimed) then
                        files.remove(claimed)
                    end
                end
            end
        end
    end)
end

-- afterEach gets a chance to clean up after a failed setup or test. If both
-- phases fail, keep the original failure as the headline and retain the
-- cleanup failure as the useful second half of the report.
local function runCase(hooks, fn)
    local ok, problem = call(hooks.beforeEach)
    if ok then
        ok, problem = call(fn)
    end
    local afterOk, afterProblem = call(hooks.afterEach)
    if not afterOk then
        if not ok then
            error(tostring(problem) .. "\n  afterEach failed: " .. tostring(afterProblem), 0)
        end
        error("afterEach failed: " .. tostring(afterProblem), 0)
    end
    if not ok then
        error(problem, 0)
    end
end

local function recordResult(suite, name, defined, ok, err, stdout, stderr, elapsed, context)
    total = total + 1
    local file, line = definedAt(defined)
    local record = {
        id = suite .. "/" .. name,
        suite = suite,
        name = name,
        file = file,
        line = line,
        durationMs = elapsed,
        status = ok and "passed" or "failed"
    }
    if context ~= nil then
        local metrics = {}
        for _, metric in pairs(context.metrics or {}) do
            metrics[#metrics + 1] = metric
        end
        table.sort(metrics, function(a, b)
            return a.name .. "\0" .. (a.unit or "") < b.name .. "\0" .. (b.unit or "")
        end)
        record.capabilities = #(context.capabilities or {}) > 0 and context.capabilities or nil
        record.fixtures = #(context.fixtures or {}) > 0 and context.fixtures or nil
        record.metrics = #metrics > 0 and metrics or nil
        if ok and #(context.facts or {}) > 0 then
            record.facts = context.facts
        end
        local encodes, encodeProblem = pcall(testJson.encode, record)
        if not encodes then
            ok = false
            local metadataProblem = errorPosition(encodeProblem)
            err = "test result metadata is not JSON-compatible: " .. metadataProblem
            record.status = "failed"
            record.capabilities = nil
            record.fixtures = nil
            record.facts = nil
            record.metrics = nil
        end
    end
    if ok then
        passed = passed + 1
        if not queueDir then
            mark(".")
        end
    elseif test.isSkip(err) then
        skipped = skipped + 1
        record.status = "skipped"
        record.skip = {reason = tostring(test.skipReason(err) or "skipped")}
        if not queueDir then
            mark("S")
        end
    elseif test.isNotExecuted(err) then
        notExecutedCount = notExecutedCount + 1
        record.status = "not-executed"
        record.notExecuted = {reason = tostring(test.notExecutedReason(err) or "not executed")}
        if not queueDir then
            mark("N")
        end
    else
        failed = failed + 1
        local message, errFile, errLine = errorPosition(err)
        record.failure = {message = message, file = errFile, line = errLine}
        record.output = {stdout = stdout, stderr = stderr}
        if traceCases then
            io.stderr:write("__failure__:", tostring(message), "\n")
        end
        if not queueDir then
            mark("E")
        end
    end
    if verbose then
        record.output = record.output or {stdout = stdout, stderr = stderr}
        showCaptured(record)
    end
    results[#results + 1] = record
end

-- Splitting the run across isolated lanes.
--
-- A hundred suites in one process took over four minutes while a whole build took
-- twelve seconds, so the wait was the suite rather than the compiler. Suites already
-- expect nothing of each other, so the split is only a matter of handing each lane a
-- list of names and adding up what comes back.
--
-- It stays serial for a single named suite, for `--jobs=1`, inside a shard, and while
-- coverage is collected -- the shards would race each other for the one counter file
-- that `NUPP_COVERAGE_FILE` names.

--- How many workers to make by default: one per processor.
---
--- It was two per processor, from a measurement on eight cores -- 71s at one per
--- core, 63s at two. That machine no longer stands for this one. On eighteen
--- cores, thirty-six workers means the longest test is competing with thirty-five
--- siblings for the machine it needs, and a run's slowest single test grew with
--- the worker count rather than staying put.
---
--- Trying to re-measure the crossover here did not settle it: fifteen consecutive
--- full runs drifted from 70s to 120s at settings that should not have differed,
--- so run order swamped the effect. One per core is the setting that does not
--- oversubscribe, and `--jobs=N` is there for a machine that wants otherwise.
local function defaultJobs()
    local handle = io.popen("getconf _NPROCESSORS_ONLN 2>/dev/null")
    local text = handle and handle:read("*l") or nil
    if handle then
        handle:close()
    end
    local found = tonumber(text or "")

    return found and found >= 1 and math.floor(found) or 4
end

--- What the last run measured, so this one can start the slow work first.
---
--- Suites are nothing like equal and nothing about a suite says in advance how long it
--- takes: `fmttest` is 282 lines and fifty seconds, `bootstraptest` is 83 lines and
--- sixteen. Source size is no guide, so the only honest estimate is what happened last
--- time. A first run with no record is evenly guessed and slow; every one after it is
--- packed from measurement.
local timingsPath = buildRoot .. "/.nupp-test-times.json"

--- Where each shard's content-keyed store goes.
---
--- Under the build directory, so `nupp clean` removes it with everything else, and
--- keyed by nothing: the stores inside stamp and key their own entries, so a stale one
--- is a miss rather than a wrong answer.
local shardCacheRoot = buildRoot .. "/.nupp-test-cache"

local recordedOnce = nil

local function recorded()
    if recordedOnce then
        return recordedOnce
    end
    recordedOnce = {suites = {}, cases = {}}
    local file = io.open(timingsPath, "rb")
    if not file then
        return recordedOnce
    end
    local text = file:read("*a")
    file:close()
    local ok, decoded = pcall(function()
        return testJson.decode(text)
    end)
    if ok and type(decoded) == "table" then
        if type(decoded.suites) == "table" then
            recordedOnce.suites = decoded.suites
        end
        if type(decoded.cases) == "table" then
            recordedOnce.cases = decoded.cases
        end
    end

    return recordedOnce
end

local function recordedTimings()
    return recorded().suites
end

--- What each case in a suite last cost, which is what a slice is packed from.
local function recordedCaseTimings(suite)
    local per = recorded().cases[suite]

    return type(per) == "table" and per or {}
end

local function updateSelectionPrediction()
    if not selectionReport then
        return
    end

    local function predictedWork(suiteNames, caseIds)
        local work = 0
        local whole = {}
        local selectedBySuite = {}
        for _, suite in ipairs(suiteNames) do
            whole[suite] = true
            work = work + (tonumber(recordedTimings()[suite]) or 0)
        end
        for _, id in ipairs(caseIds) do
            local suite, caseId = id:match("^(.-)/(.*)$")
            if suite and not whole[suite] then
                work = work + (tonumber(recordedCaseTimings(suite)[caseId]) or 0)
                selectedBySuite[suite] = true
            end
        end
        for suite in pairs(selectedBySuite) do
            local measuredCases = 0
            for _, ms in pairs(recordedCaseTimings(suite)) do
                measuredCases = measuredCases + (tonumber(ms) or 0)
            end
            work = work + math.max(0, (tonumber(recordedTimings()[suite]) or 0) - measuredCases)
        end

        return work
    end

    selectionReport.selectedWorkMs = predictedWork(selectionReport.selectedSuites, selectionReport.selectedCases)
    local requestedSuiteNames = {}
    for _, info in ipairs(selectionRequestedSuites or {}) do
        requestedSuiteNames[#requestedSuiteNames + 1] = info.name
    end
    local requestedCaseIds = {}
    for id in pairs(selectionRequestedCases or {}) do
        requestedCaseIds[#requestedCaseIds + 1] = id
    end
    if selectionRequestedCaseScope then
        requestedSuiteNames = {}
    end
    table.sort(requestedSuiteNames)
    table.sort(requestedCaseIds)
    selectionReport.requestedWorkMs = predictedWork(requestedSuiteNames, requestedCaseIds)
    selectionReport.predictedSavingsMs = math.max(0, selectionReport.requestedWorkMs - selectionReport.selectedWorkMs)
    selectionReport.predictedSavingsPercent = selectionReport.requestedWorkMs > 0
        and selectionReport.predictedSavingsMs / selectionReport.requestedWorkMs * 100
        or 0
end

updateSelectionPrediction()

--- Which slice each case of a suite belongs to.
---
--- Position was the rule -- case `n` went to slice `n % count` -- and position
--- says nothing about cost. `lsptest` ran cases from a tenth of a second to two
--- minutes, so every slice of it was a coin toss and the run's floor was
--- whichever one drew the worst. Longest-first into the emptiest slice is the
--- same makespan heuristic the shards themselves use, one level further down.
---
--- Both ends compute this from the same file: the parent, to know what a slice
--- will actually cost before it packs one, and the child, to know which cases
--- are its own. The file is rewritten once, after every child has finished, so
--- the two cannot disagree within a run.
---
--- An unmeasured case is guessed at the average of the measured ones, the same
--- way an unmeasured suite is, so a case added since the last run is not packed
--- as though it were free.
local function sliceAssignment(cases, costs, count)
    local known, counted = 0, 0
    for _, ms in pairs(costs) do
        known = known + (tonumber(ms) or 0)
        counted = counted + 1
    end
    local average = counted > 0 and known / counted or 1
    local order = {}
    for _, name in ipairs(cases) do
        order[#order + 1] = {name = name, cost = tonumber(costs[name]) or average}
    end
    table.sort(order, function(a, b)
        if a.cost ~= b.cost then
            return a.cost > b.cost
        end

        return a.name < b.name
    end)
    local filled, where = {}, {}
    for index = 0, count - 1 do
        filled[index] = 0
    end
    for _, item in ipairs(order) do
        local into = 0
        for index = 0, count - 1 do
            if filled[index] < filled[into] then
                into = index
            end
        end
        filled[into] = filled[into] + item.cost
        where[item.name] = into
    end

    return where, filled
end

--- What a suite costs a shard, from suite records rather than case records.
---
--- Cases alone under-report: loading is where a Nupp suite is compiled and a Lua
--- one runs its top level, and a `beforeAll` that builds a project belongs to no
--- case at all. Packing from case time alone therefore packs from a number that
--- can be a fraction of what the shard actually waits for.
---
--- Slices are added back up, except for loading, which is taken at its maximum
--- rather than summed. Each slice really does pay the load again, but recording
--- that would raise the suite's estimated cost, which asks for more slices, which
--- raises it again -- a run that slices further every time it is repeated. The
--- maximum is what one whole suite costs, which is the question packing asks.
local function rememberTimings(records, cases)
    local per = {}
    for _, record in ipairs(records) do
        local suite = tostring(record.suite)
        local entry = per[suite] or {work = 0, load = 0}
        per[suite] = entry
        entry.work = entry.work + (tonumber(record.casesMs) or 0) + (tonumber(record.hooksMs) or 0)
        entry.load = math.max(entry.load, tonumber(record.loadMs) or 0)
    end
    for suite, entry in pairs(per) do
        per[suite] = entry.work + entry.load
    end
    -- Every case, not only the expensive ones. What a slice is packed from is the
    -- shape of the whole suite, and a suite of two hundred cheap cases and one
    -- heavy one packs differently from a suite of one heavy case, which is a
    -- difference a list of only the heavy ones cannot express.
    local byCase = {}
    for _, record in ipairs(cases or {}) do
        local suite = tostring(record.suite)
        local into = byCase[suite] or {}
        byCase[suite] = into
        into[tostring(record.name)] = tonumber(record.durationMs) or 0
    end
    -- Merged over what was already recorded rather than written in place of it.
    -- A run that covered part of the selection -- one lane, one group, one named
    -- suite -- knows nothing about the rest, and replacing the file with only
    -- what it measured left the next run packing the other half blind. Entries
    -- for suites that no longer exist are dropped, so the file tracks the tree
    -- instead of accumulating every suite there has ever been.
    local previous = recorded()
    local suiteTimings, caseTimings = {}, {}
    for suite, ms in pairs(previous.suites or {}) do
        if byName[suite] then
            suiteTimings[suite] = ms
        end
    end
    for suite, cases in pairs(previous.cases or {}) do
        if byName[suite] then
            caseTimings[suite] = cases
        end
    end
    for suite, ms in pairs(per) do
        if chosenCaseCount == 0 or wholeSuites[suite] then
            suiteTimings[suite] = ms
        end
    end
    for suite, cases in pairs(byCase) do
        if chosenCaseCount == 0 or wholeSuites[suite] then
            caseTimings[suite] = cases
        else
            local merged = caseTimings[suite] or {}
            caseTimings[suite] = merged
            for name, ms in pairs(cases) do
                merged[name] = ms
            end
        end
    end

    local json = testJson
    local encoded, text = pcall(json.encode, {suites = suiteTimings, cases = caseTimings})
    if not encoded then
        return
    end
    local file = io.open(timingsPath, "wb")
    if not file then
        os.execute("mkdir -p " .. string.format("%q", buildRoot))
        file = io.open(timingsPath, "wb")
    end
    if file then
        file:write(text .. "\n")
        file:close()
    end
end

--- Orders the suites longest-first, slicing the ones too heavy to be left whole.
---
--- The order is all the plan is. Which worker runs which piece is decided while the
--- run is happening, by whoever is free -- see `takeWork`, which is where the reason
--- lives. Longest-first is what makes that come out well: the pieces that could still
--- unbalance the run are handed out while there is other work to hide behind them.
---
--- A suite costing more than a fair share is asked to run in slices, because one suite
--- longer than the share is on its own the floor however many workers there are: with
--- `selfFormatStable` whole, the best possible run was fifty seconds at any count.
local function planWork(list, shards, timings)
    local known, counted = 0, 0
    for _, ms in pairs(timings) do
        known = known + ms
        counted = counted + 1
    end
    -- An unmeasured suite is guessed at the average rather than zero, so a new one is
    -- not packed last behind everything.
    local average = counted > 0 and known / counted or 1

    local planned = 0
    local costs = {}
    for _, suite in ipairs(list) do
        local fullCost = tonumber(timings[suite.name]) or average
        local caseCosts = recordedCaseTimings(suite.name)
        local fullCaseWork, measuredCases = 0, 0
        for _, ms in pairs(caseCosts) do
            fullCaseWork = fullCaseWork + (tonumber(ms) or 0)
            measuredCases = measuredCases + 1
        end
        local overhead = measuredCases > 0 and math.max(0, fullCost - fullCaseWork) or 0
        local names = {}
        local normalized = runnablePlan and runnablePlan[suite.name]
        local whole = normalized and normalized.whole or chosenCaseCount == 0 or wholeSuites[suite.name]
        if whole then
            for name in pairs(caseCosts) do
                names[#names + 1] = name
            end
        elseif normalized then
            for _, name in ipairs(normalized.caseNames) do
                names[#names + 1] = name
            end
        else
            local prefix = suite.name .. "/"
            for id in pairs(chosenCases) do
                if id:sub(1, #prefix) == prefix then
                    names[#names + 1] = id:sub(#prefix + 1)
                end
            end
        end
        table.sort(names)
        local cost = fullCost
        if not whole and #names > 0 then
            local averageCase = measuredCases > 0 and fullCaseWork / measuredCases or fullCost
            cost = overhead
            for _, name in ipairs(names) do
                cost = cost + (tonumber(caseCosts[name]) or averageCase)
            end
        end
        costs[
            #costs + 1
        ] = {
            name = suite.name,
            cost = cost,
            caseCosts = caseCosts,
            names = names,
            overhead = overhead,
            whole = whole,
            normalized = normalized,
        }
        planned = planned + cost
    end

    local share = planned / shards
    local work = {}
    for _, item in ipairs(costs) do
        -- What the suite's cases last cost, which is what says whether slicing it
        -- would help and what each slice would come to. A suite whose weight is one
        -- case is not made lighter by being cut in four: three slices come back
        -- empty and the fourth is the floor it always was, so the pieces are capped
        -- at the number of cases there are to spread.
        local caseCosts = item.caseCosts
        local names = item.names
        -- Half a share rather than a whole one.
        --
        -- Slicing at the share leaves pieces exactly the size of a bin, and
        -- longest-first then puts one of them in a bin and adds whatever is left
        -- over on top: the run's floor was a shard holding a full-share slice plus
        -- four more suites. Halving the target gives the packer pieces it can fit
        -- around each other, and a slice costs only loading its suite again, which
        -- is milliseconds for all but a handful.
        local target = share / 2
        local pieces = 1
        -- A complete impact graph already observed whether cases share lifecycle
        -- state. Honor that before making pieces: the runtime check remains a
        -- defense, but cannot prevent each discarded piece from loading the suite.
        -- Ordinary runs have no recorded fact here and retain their existing plan.
        local recordedSliceSafe = impactSuiteSliceSafe and impactSuiteSliceSafe[item.name]
        local maySlice = item.whole and recordedSliceSafe ~= false
        if item.normalized then
            if item.normalized.sliceSafe ~= nil then
                maySlice = item.normalized.sliceSafe == true
            elseif not item.whole then
                maySlice = false
            end
        end
        if maySlice and target > 0 and item.cost > target then
            pieces = math.ceil(item.cost / target)
            if #names > 0 then
                pieces = math.min(pieces, #names)
            end
        end
        if pieces > 1 then
            -- Evenly, when there is nothing measured to pack from. Otherwise from the
            -- assignment the child will make, so the plan costs a slice at what that
            -- slice is going to be rather than at the suite's average.
            local sliced, overhead = nil, 0
            if #names > 0 then
                -- Whatever the suite cost beyond its cases is loading it, and every
                -- slice loads it again. Counted once per slice rather than divided
                -- between them, which is what actually happens.
                overhead = item.overhead
                local _, filled = sliceAssignment(names, caseCosts, pieces)
                sliced = filled
            end
            for index = 0, pieces - 1 do
                work[
                    #work + 1
                ] = {
                    cost = sliced and (sliced[index] + overhead) or item.cost / pieces,
                    spec = ("%s#%d/%d"):format(item.name, index, pieces)
                }
            end
        else
            work[#work + 1] = {cost = item.cost, spec = item.name}
        end
    end
    table.sort(work, function(a, b)
        if a.cost ~= b.cost then
            return a.cost > b.cost
        end

        return a.spec < b.spec
    end)

    local order, heaviest = {}, 0
    for _, item in ipairs(work) do
        order[#order + 1] = item.spec
        if item.cost > heaviest then
            heaviest = item.cost
        end
    end

    -- What this plan says the phase cannot finish under, so the report can say
    -- whether a slow run was packed badly or was simply that much work. A lane
    -- takes the next piece when it is free, so the floor is the larger of the
    -- fair share and the single heaviest piece: one piece longer than the share
    -- is the whole phase's floor however many lanes there are.

    return order, {
        planned = planned,
        lanes = shards,
        heaviest = heaviest,
        floor = math.max(shards > 0 and planned / shards or planned, heaviest),
    }
end

-- A Nupp worker owns a Lua state, not the process around that state. Suites that
-- touch process-wide facilities therefore keep the isolated lane. Looking at the
-- source as well as a short hard list makes the safe choice the default when a
-- new suite reaches one. Shell calls instead choose reusable process workers:
-- several suites share each worker, and a failed case does not end its queue.
local PROCESS_ISOLATED = {
    -- These exercise worker hosting or runner descriptor behavior even when the
    -- operation is built as a source fixture rather than called by the Lua test.
    bundletest = true,
    comptimetest = true,
    publicclitest = true,
    -- Their compiler fixtures reach build commands through shared helpers, so the
    -- process call is not text in the suite for the source scan below to find.
    deriveacceptancetest = true,
    deriveprovidertest = true,
    derivetest = true,
    eventschecktest = true,
    loggingtest = true,
    runtimereflectiontest = true,
    serdetest = true,
    -- Carries a strict interactive-latency gate when run on its own. In a broad
    -- run it still reports the metric, but gets a fresh process so one worker's
    -- allocator and JIT history do not become part of the sample.
    testimpactstoretest = true,
    typeleveltest = true,
    -- Imports cheadertest as a fixture; its top level asks the shell for an
    -- absolute checkout path on hosts where debug information is relative.
    hotreloadguaranteetest = true,
    projectlinktest = true,
    spipackagetest = true,
    spitest = true,
    profiletest = true,
    runnertest = true,
    -- These execute generated ownership cleanups. Their providers are registered
    -- in process-global runtime tables, so a reused worker state is not their
    -- isolation boundary even though the cases themselves do not shell out.
    ioscalarstest = true,
    nativefoundationstest = true,
    soatest = true,
    -- Rebuilds the math runtime through the process root and exercises LuaJIT's
    -- wide FFI operations. A long-lived shell worker can retain JIT and FFI
    -- state from unrelated suites even after its Lua globals are restored.
    fixedwidthtest = true,
    -- Builds and installs the URI provider by replacing the runtime root global.
    uritest = true,
}

local processCalls = {
    'require("nupp.io.process")',
    "require('nupp.io.process')",
    'require("nupp.profile")',
    "require('nupp.profile')",
    'require("nupp.workers")',
    "require('nupp.workers')",
    -- Reaching into the loader is process-shaped whether or not a process is
    -- started. A suite that clears a module to prove it loads lazily, injects a
    -- loader, or writes a global through `rawset` is mutating what every other
    -- suite in that state sees. None of these move a suite today -- every suite
    -- that does one of them already shells out as well -- and that is exactly
    -- why they belong here: the next one to be written might not.
    "package.loaded",
    "package.preload",
    "package.loadlib",
    "rawset(_G,",
}

local shellCalls = {"os.execute", "io.popen",}
local SHELLING = {
    -- Shelling happens in the helper so source inspection would otherwise rely
    -- on an explanatory comment retaining the implementation's exact spelling.
    simdfleetequivalencetest = true,
    simdnativealgorithmdifferentialtest = true,
    simdprimitivedifferentialtest = true,
    simdwasmalgorithmdifferentialtest = true,
    simdwasmtimeconformancetest = true,
}
local sourceBySuite = {}

local function suiteSource(suiteInfo)
    if not suiteInfo then
        return nil
    end
    local cached = sourceBySuite[suiteInfo.name]
    if cached ~= nil then
        return cached
    end
    local file = io.open(dir .. "/" .. suiteInfo.name .. "." .. suiteInfo.extension, "rb")
    if not file then
        return nil
    end
    local source = file:read("*a") or ""
    file:close()
    sourceBySuite[suiteInfo.name] = source

    return source
end

local function sourceContains(suiteInfo, calls)
    local source = suiteSource(suiteInfo)
    if source == nil then
        return false
    end
    for _, call in ipairs(calls) do
        if source:find(call, 1, true) then
            return true
        end
    end

    return false
end

local function processIsolated(suiteInfo)
    if not suiteInfo or PROCESS_ISOLATED[suiteInfo.name] then
        return suiteInfo ~= nil
    end

    return suiteSource(suiteInfo) == nil or sourceContains(suiteInfo, processCalls)
end

local function usesShell(suiteInfo)
    return suiteInfo ~= nil and (SHELLING[suiteInfo.name] or sourceContains(suiteInfo, shellCalls))
end

local function suiteLane(suiteInfo)
    if processIsolated(suiteInfo) then
        return "isolated"
    end

    return usesShell(suiteInfo) and "shell" or "shared"
end

if lane then
    local kept = {}
    for _, suiteInfo in ipairs(suites) do
        if lane == suiteLane(suiteInfo) then
            kept[#kept + 1] = suiteInfo
        end
    end
    suites = kept
    local allowed = {}
    for _, info in ipairs(suites) do
        allowed[info.name] = true
    end
    for id in pairs(chosenCases) do
        local name = id:match("^(.-)/")
        if not name or not allowed[name] then
            chosenCases[id] = nil
            chosenCaseCount = chosenCaseCount - 1
        end
    end
    for name in pairs(wholeSuites) do
        if not allowed[name] then
            wholeSuites[name] = nil
        end
    end
    if runnablePlan then
        for name in pairs(runnablePlan) do
            if not allowed[name] then
                runnablePlan[name] = nil
            end
        end
    end
    local requestedAllowed = {}
    local keptRequestedSuites = {}
    for _, info in ipairs(selectionRequestedSuites or {}) do
        if lane == suiteLane(info) then
            requestedAllowed[info.name] = true
            keptRequestedSuites[#keptRequestedSuites + 1] = info
        end
    end
    selectionRequestedSuites = keptRequestedSuites
    for id in pairs(selectionRequestedCases or {}) do
        local name = id:match("^(.-)/")
        if not name or not requestedAllowed[name] then
            selectionRequestedCases[id] = nil
        end
    end
    if selectionReport then
        local selectedSuites = {}
        for _, name in ipairs(selectionReport.selectedSuites) do
            if allowed[name] then
                selectedSuites[#selectedSuites + 1] = name
            end
        end
        local selectedCases = {}
        for _, id in ipairs(selectionReport.selectedCases) do
            local name = id:match("^(.-)/")
            if name and allowed[name] then
                selectedCases[#selectedCases + 1] = id
            end
        end
        selectionReport.selectedSuites = testJson.asArray(selectedSuites)
        selectionReport.selectedCases = testJson.asArray(selectedCases)
        local selectionReasons = {}
        for _, reason in ipairs(selectionReport.reasons) do
            if not reason.suite or allowed[reason.suite] then
                selectionReasons[#selectionReasons + 1] = reason
            end
        end
        selectionReport.reasons = testJson.asArray(selectionReasons)

        local function filterOwners(records)
            local filtered = {}
            for _, record in ipairs(records) do
                local owner = record.owner
                local file = type(owner) == "string" and owner:gsub("\\", "/"):match("([^/]+)$") or nil
                local name = file and file:match("^(.*test)%.[^.]+$") or (owner and byName[owner] and owner or nil)
                if not name or allowed[name] then
                    filtered[#filtered + 1] = record
                end
            end

            return testJson.asArray(filtered)
        end

        selectionReport.promotions = filterOwners(selectionReport.promotions)
        selectionReport.fallbacks = filterOwners(selectionReport.fallbacks)
        updateSelectionPrediction()
        if #suites == 0 then
            selectionReport.emptyReason = selectionReport.emptyReason or "outside-requested-scope"
        end
    end
end

if listing == "suites" then
    for _, info in ipairs(suites) do
        io.stdout:write(info.name .. "\n")
    end
    os.exit(0)
end

if listing == "cases" then
    for _, info in ipairs(suites) do
        local suite, removeLoader = loadSuite(info)
        local _, names = suiteParts(info, suite)
        for _, name in ipairs(names) do
            local id = info.name .. "/" .. name
            if chosenCaseCount == 0 or wholeSuites[info.name] or chosenCases[id] then
                io.stdout:write(id .. "\n")
            end
        end
        if removeLoader then
            removeLoader()
        end
    end
    os.exit(0)
end

local willShard = #shard == 0
    and #suites > 0
    and ((workerHost and not processIsolated(only and byName[only])) or (#chosen ~= 1 and #suites > 1 and jobs ~= 1))
    and not os.getenv("NUPP_COVERAGE_FILE")

-- Exact IDs are validated before any lifecycle hook or case runs. Keep the
-- loaded suites so validation does not execute their top level twice. A sharded
-- parent does not discover them: each worker owns the top level of the suites it
-- claims and reports the exact IDs it found back to the parent.
local preloadedSuites = {}
if chosenCaseCount > 0 and not queueDir and not willShard and not supervisedPiece then
    for _, info in ipairs(suites) do
        local loadBefore = now()
        local suite, removeLoader = loadSuite(info)
        local hooks, cases = suiteParts(info, suite)
        preloadedSuites[
            info.name
        ] = {suite = suite, removeLoader = removeLoader, loadMs = now() - loadBefore, hooks = hooks, cases = cases,}
        for _, name in ipairs(cases) do
            local id = info.name .. "/" .. name
            if chosenCases[id] then
                seenCaseIds[id] = true
            end
        end
    end
    local missing = {}
    for id in pairs(chosenCases) do
        if not seenCaseIds[id] then
            missing[#missing + 1] = id
        end
    end
    if #missing > 0 then
        for _, loaded in pairs(preloadedSuites) do
            if loaded.removeLoader then
                loaded.removeLoader()
            end
        end
        table.sort(missing)
        io.stderr:write("nupp: no test case named " .. table.concat(missing, ", ") .. "\n")
        os.exit(2)
    end
end

-- What the packer said each phase could not finish under, kept so the report can
-- put its prediction beside what the phase actually cost. A plan that is right
-- and a run that is slow are different problems with different fixes.
local predictions = {}
local sharded = nil
if willShard then
    do
        local json = testJson
        local shareable, alone, shelling = {}, {}, {}
        for _, suiteInfo in ipairs(suites) do
            local selectedLane = suiteLane(suiteInfo)
            local into = selectedLane == "isolated" and alone or selectedLane == "shell" and shelling or shareable
            into[#into + 1] = suiteInfo
        end

        local children = 0
        local madeShardRoot = false
        -- Whether any worker wrote a mark, so this end knows whether there is a line
        -- to close. Out here rather than in `fanOut` because it is read after it.
        local marked = false

        local function beginPhase(text)
            if marked then
                progressWrite("\n")
                marked = false
            end
            progressWrite(progressHeading(text) .. "\n")
            progressWidth = 0
        end

        --- Starts one child per group and returns the operation that reads them.
        ---
        --- Keeping start separate from collection lets both executor kinds run at
        --- once: every pipe and task is live before this process waits for either.
        ---
        --- `nupp.suspension`'s combinators would express the fan-out more directly,
        --- and do for a Nupp program, but reaching `nupp.io.process` from here means
        --- building a compiler environment first so its native provider resolves --
        --- more machinery in the parent than the parent is doing.
        ---
        --- `ownCache` gives each child a content-keyed store of its own. Every suite
        --- that runs `nupp` in a temporary project otherwise starts that project's
        --- store cold, and the most expensive thing in it -- what the compiler's own
        --- modules require, which decides what a stored answer is stamped with -- is
        --- the same answer for all of them. Per child rather than for the whole run
        --- because a store is written whole: children sharing one file would take
        --- turns discarding each other's entries. A suite running on its own has no
        --- one to share with and keeps the warm store this process was started with.
        local function startFanOut(lanes, ownCache, isolated, executionLane)
            if workerHost and ownCache and not isolated then
                local workers = require("nupp.workers")
                local job = require("job")
                local running = {}
                local scope = workers.scope()
                -- A worker state cannot redirect process-owned descriptors safely.
                -- Keep inherited output quiet for the threaded phase; ordinary Lua
                -- output is captured in its state, process-writing suites are in the
                -- process-worker queues, and progress has its own saved descriptor.
                local restoreOutput = silenceProcessOutput()
                local launched, problem = pcall(function()
                    for _, lane in ipairs(lanes) do
                        local index = children + 1
                        children = index
                        madeShardRoot = madeShardRoot or os.execute("mkdir -p '" .. shardCacheRoot .. "'") ~= nil
                        local cache = ("%s/shard-%d"):format(shardCacheRoot, index)
                        running[
                            #running + 1
                        ] = {
                            label = lane.label,
                            index = index,
                            startedAt = now() - started,
                            task = scope:spawn(
                                job.run,
                                lane.arg,
                                cache,
                                progressFd,
                                verbose,
                                colorMode,
                                suiteCatalog,
                                impactRecording and impactRecordId or nil
                            ),
                        }
                    end
                end)
                if not launched then
                    restoreOutput()
                    pcall(scope.close, scope)
                    error(problem, 0)
                end

                return function()
                    local completed, reports = pcall(function()
                        local reports = {}
                        for _, child in ipairs(running) do
                            local ok, report = pcall(function()
                                return child.task:await()
                            end)
                            if ok and type(report) == "table" then
                                report.shard = {
                                    index = child.index,
                                    names = (report.claimed and #report.claimed > 0) and report.claimed
                                    or {child.label},
                                    executionLane = executionLane,
                                    startedAt = child.startedAt,
                                    collectedAt = now() - started
                                }
                                reports[#reports + 1] = report
                            else
                                reports[#reports + 1] = {names = {child.label}, failure = tostring(report)}
                            end
                        end
                        scope:close()

                        return reports
                    end)
                    restoreOutput()
                    if not completed then
                        pcall(scope.close, scope)
                        error(reports, 0)
                    end

                    return reports
                end
            end

            local running = {}
            for _, lane in ipairs(lanes) do
                do
                    local index = children + 1
                    local label = lane.label
                    children = index
                    -- The store the children share a parent directory with is made by
                    -- whoever writes into it, and nothing had yet. A redirect into a
                    -- directory that is not there fails in the shell, before the child
                    -- runs, so every one of them would have died saying nothing.
                    madeShardRoot = madeShardRoot or os.execute("mkdir -p '" .. shardCacheRoot .. "'") ~= nil
                    -- Kept rather than inherited, so a child that dies can be asked
                    -- why. One that wrote no report used to say only that, which is the
                    -- least useful thing known about it: whether it was killed, ran out
                    -- of memory, or wrote something that was not JSON all read the
                    -- same.
                    local errors = ("%s/shard-%d.err"):format(shardCacheRoot, index)
                    local cache = ownCache and ("NUPP_CACHE_DIR='%s/shard-%d' "):format(shardCacheRoot, index) or ""
                    -- The shell reports the wait status because this end cannot:
                    -- LuaJIT's `close` on a pipe answers whether it closed, not what
                    -- happened to what was on the other side, so a child that was
                    -- killed and one that exited quietly are the same nil here. `$?`
                    -- past 128 is the signal, which is the difference between a crash
                    -- and an OOM kill. `9>&2` copies this process's standard error
                    -- aside before `2>` sends the worker's to its file, so `3>&9` hands
                    -- the worker a descriptor that still reaches the terminal. Two
                    -- destinations, one for marks and one for whatever it says on the
                    -- way down. Named rather than redirected: on POSIX the worker
                    -- inherits the descriptor across the fork and writes its marks
                    -- straight to it, while its standard error still goes to the file
                    -- this end keeps to ask a dead worker why. A Windows CRT descriptor
                    -- number is local to one process and does not survive the Rust host
                    -- -> shell -> LuaJIT boundary. Name inherited stderr there: the
                    -- surrounding group already sends it to the shard log, keeping JSON
                    -- stdout intact. Windows process-worker marks are consequently
                    -- collected rather than live. Without any descriptor, the worker
                    -- also marks into that file.
                    local processProgressFd = progressFd and (package.config:sub(1, 1) == "\\" and 2 or progressFd)
                        or nil
                    local progress = processProgressFd and ("NUPP_TEST_PROGRESS_FD=%d "):format(processProgressFd) or ""
                    local fresh = executionLane == "isolated" and "NUPP_TEST_FRESH_QUEUE_PIECES=1 " or ""
                    local invocation = rawget(_G, "__NUPP_TEST_RUNNER_COMMAND") or ("luajit '%s'"):format(arg[0])
                    local command = (
                        "{ %s%s%s%s --json %s%s --color=%s%s; echo \"__status__:$?\" >&2; } 2>'%s'"
                    ):format(
                        cache,
                        progress,
                        fresh,
                        invocation,
                        lane.arg,
                        impactRecording and (" --internal-impact-record=" .. impactRecordId) or "",
                        colorMode,
                        verbose and " --verbose" or "",
                        errors
                    )
                    running[
                        #running + 1
                    ] = {
                        label = label,
                        errors = errors,
                        index = index,
                        startedAt = now() - started,
                        pipe = io.popen(command, "r")
                    }
                end
            end

            return function()
                local reports = {}
                for _, child in ipairs(running) do
                    if not child.pipe then
                        reports[#reports + 1] = {failure = "the worker could not be started", names = {child.label}}
                    else
                        local text = child.pipe:read("*a")
                        local _, how, code = child.pipe:close()
                        local decoded, report = pcall(json.decode, text or "")
                        if decoded and type(report) == "table" then
                            -- What the parent knows and the child cannot: which shard
                            -- this was, when it was started, and when this end finished
                            -- reading it. The child's own `durationMs` is its wall
                            -- clock, which is the honest measure -- the pipes are read
                            -- in order, so when the parent noticed says more about read
                            -- order than about the shard.
                            report.shard = {
                                index = child.index,
                                names = (report.claimed and #report.claimed > 0) and report.claimed or {child.label},
                                alone = isolated or nil,
                                executionLane = executionLane,
                                startedAt = child.startedAt,
                                collectedAt = now() - started
                            }
                            reports[#reports + 1] = report
                        else
                            -- Everything known about the death, in the failure itself.
                            -- A signal names how it was killed; the tail of its
                            -- standard error says what it managed to complain about
                            -- first; the length of what it wrote separates "nothing at
                            -- all" from "not JSON".
                            local why = {}
                            if how then
                                why[#why + 1] = ("%s %s"):format(tostring(how), tostring(code))
                            end
                            local written = text or ""
                            why[#why + 1] = ("%d bytes on stdout"):format(#written)
                            if not decoded then
                                why[#why + 1] = "JSON decode: " .. tostring(report)
                                if #written > 0 then
                                    local head = written:sub(1, 1000)
                                    local tail = #written > 1000 and written:sub(-1000) or nil
                                    why[#why + 1] = "stdout head: " .. head
                                    if tail then
                                        why[#why + 1] = "stdout tail: " .. tail
                                    end
                                end
                            end
                            local errored = io.open(child.errors, "rb")
                            if errored then
                                local said = errored:read("*a") or ""
                                errored:close()
                                local status = said:match("__status__:(%d+)")
                                if status then
                                    local code = tonumber(status) or 0
                                    why[#why + 1] = code > 128 and ("killed by signal %d"):format(code - 128)
                                        or ("exit %d"):format(code)
                                    said = said:gsub("__status__:%d+%s*$", "")
                                end
                                -- The last suite the worker said it was starting. An
                                -- undecodable report does not prove the worker died: it
                                -- may have exited normally after a test failure while
                                -- an inherited writer corrupted stdout. The marks
                                -- themselves are taken out of what gets printed: there
                                -- is one per suite, and a lane's worth of them would
                                -- bury the message they are here to qualify.
                                local inFlight
                                for name in said:gmatch("__suite__:([^\n]*)") do
                                    inFlight = name
                                end
                                local inFlightCase
                                for name in said:gmatch("__case__:([^\n]*)") do
                                    inFlightCase = name
                                end
                                said = said:gsub("__suite__:[^\n]*\n?", "")
                                said = said:gsub("__case__:[^\n]*\n?", "")
                                if inFlight then
                                    why[
                                        #why + 1
                                    ] = "last reported " .. inFlight .. (inFlightCase and " / " .. inFlightCase or "")
                                end
                                if #said > 0 then
                                    why[#why + 1] = "stderr: " .. said:sub(-2000)
                                end
                            end
                            reports[
                                #reports + 1
                            ] = {
                                names = {child.label},
                                failure = "the worker wrote no report (" .. table.concat(why, "; ") .. ")"
                            }
                        end
                    end
                end

                return reports
            end
        end

        sharded = {
            results = {},
            suites = {},
            shards = {},
            total = 0,
            passed = 0,
            skipped = 0,
            notExecuted = 0,
            failed = 0,
            impactFragments = {},
            impactSliceSafe = {},
        }

        local function absorb(reports)
            for _, report in ipairs(reports) do
                if report ~= nil and report.failure then
                    -- A child that died says so as a failure of its own rather than
                    -- quietly removing its suites from the count.
                    sharded.total = sharded.total + 1
                    sharded.failed = sharded.failed + 1
                    sharded.results[
                        #sharded.results + 1
                    ] = {
                        id = table.concat(report.names, ",") .. "/<shard>",
                        suite = table.concat(report.names, ","),
                        name = "<shard>",
                        status = "failed",
                        durationMs = 0,
                        failure = {message = report.failure},
                    }
                elseif report ~= nil then
                    sharded.total = sharded.total + (report.total or 0)
                    sharded.passed = sharded.passed + (report.passed or 0)
                    sharded.skipped = sharded.skipped + (report.skipped or 0)
                    sharded.notExecuted = sharded.notExecuted + (report.notExecuted or 0)
                    sharded.failed = sharded.failed + (report.failed or 0)
                    for _, record in ipairs(report.tests or {}) do
                        sharded.results[#sharded.results + 1] = record
                    end
                    for _, record in ipairs(report.suites or {}) do
                        record.shard = report.shard and report.shard.index or nil
                        record.alone = report.shard and report.shard.alone or nil
                        record.executionLane = report.shard and report.shard.executionLane or nil
                        sharded.suites[#sharded.suites + 1] = record
                    end
                    for _, fragment in ipairs(report.impactFragments or {}) do
                        sharded.impactFragments[#sharded.impactFragments + 1] = fragment
                    end
                    for suite, safe in pairs(report.impactSliceSafe or {}) do
                        sharded.impactSliceSafe[suite] = safe
                    end
                    for _, id in ipairs(report.seenSelectedCases or {}) do
                        if chosenCases[id] then
                            seenCaseIds[id] = true
                        end
                    end
                    for _, id in ipairs(report.missingSelectedCases or {}) do
                        if chosenCases[id] then
                            missingCaseIds[id] = true
                        end
                    end
                    if report.shard then
                        sharded.shards[
                            #sharded.shards + 1
                        ] = {
                            index = report.shard.index,
                            specs = report.shard.names,
                            alone = report.shard.alone,
                            executionLane = report.shard.executionLane,
                            durationMs = tonumber(report.durationMs) or 0,
                            startedAt = report.shard.startedAt,
                            collectedAt = report.shard.collectedAt,
                            tests = report.total or 0,
                        }
                    end
                end
            end
        end

        -- Prepare a dynamically-fed queue for either Nupp worker states or process
        -- workers. Starting and collecting are separate so the shell queue can join
        -- the end of the Nupp queue without involving process-global suites.
        local function prepareQueue(list, isolated, count, executionLane, order, prediction, workerLimit)
            if #list == 0 then
                return nil
            end
            if not order then
                order, prediction = planWork(list, count, recordedTimings())
            end
            -- The plan starts from suite concurrency, then may split a heavy suite
            -- into several runnable pieces. Those pieces are real parallel work, so
            -- the worker pool is capped by the plan rather than by the suite count.
            local runnable = math.min(workerLimit or count, #order)
            prediction.lanes = runnable
            prediction.floor = math.max(
                runnable > 0 and prediction.planned / runnable or prediction.planned,
                prediction.heaviest
            )
            predictions[executionLane] = prediction
            if not madeShardRoot then
                assert(os.execute("mkdir -p '" .. shardCacheRoot .. "'") == 0, "cannot create the test queue root")
                madeShardRoot = true
            end
            local ticket = os.tmpname():match("[^/\\]+$") or tostring(#order)
            local queue = shardCacheRoot .. "/queue-" .. ticket
            assert(os.execute("mkdir '" .. queue .. "'") == 0, "cannot reserve a unique test queue")
            local listing = assert(io.open(queue .. "/order", "wb"))
            listing:write(table.concat(order, "\n") .. "\n")
            listing:close()
            local laneSuites = {}
            for _, suite in ipairs(list) do
                laneSuites[suite.name] = true
            end
            local inheritedCases = {}
            for id in pairs(chosenCases) do
                local suite = id:match("^([^/]+)/")
                if suite and laneSuites[suite] then
                    inheritedCases[#inheritedCases + 1] = id
                end
            end
            local inheritedWholeSuites = {}
            for name in pairs(wholeSuites) do
                if laneSuites[name] then
                    inheritedWholeSuites[#inheritedWholeSuites + 1] = name
                end
            end
            table.sort(inheritedCases)
            table.sort(inheritedWholeSuites)
            local selectionFile = assert(io.open(queue .. "/selection.json", "wb"))
            selectionFile:write(
                testJson.encode({
                    cases = testJson.asArray(inheritedCases),
                    wholeSuites = testJson.asArray(inheritedWholeSuites),
                }) .. "\n"
            )
            selectionFile:close()
            for index = 1, #order do
                local piece = assert(io.open(("%s/piece-%d"):format(queue, index), "wb"))
                piece:write(order[index], "\n")
                piece:close()
            end
            local lanes = {}
            for index = 1, runnable do
                lanes[
                    #lanes + 1
                ] = {arg = "--queue=" .. queue, label = (isolated and "process worker " or "Nupp worker ") .. index,}
            end

            return {
                count = #list,
                executionLane = executionLane,
                isolated = isolated,
                lanes = lanes,
                order = order,
                path = queue,
            }
        end

        local function collectQueue(queue, collect)
            if not queue then
                return
            end
            absorb(collect())
            os.execute("rm -rf '" .. queue.path .. "'")

            -- Work nobody reported having run. A worker that dies holding a piece
            -- takes it with it, and silently doing less than requested is a failure.
            local ran = {}
            for _, entry in ipairs(sharded.shards) do
                for _, spec in ipairs(entry.specs or {}) do
                    ran[spec] = true
                end
            end
            for _, spec in ipairs(queue.order) do
                if not ran[spec] then
                    sharded.total = sharded.total + 1
                    sharded.failed = sharded.failed + 1
                    sharded.results[
                        #sharded.results + 1
                    ] = {
                        id = (spec:match("^(.-)#") or spec) .. "/<unrun>",
                        suite = (spec:match("^(.-)#") or spec),
                        name = "<unrun>",
                        status = "failed",
                        durationMs = 0,
                        failure = {message = "no worker reported running " .. spec},
                    }
                end
            end
        end

        local workerCount = jobs or defaultJobs()
        local isolatedQueue = prepareQueue(
            alone,
            true,
            math.min(workerCount, #alone),
            "isolated",
            nil,
            nil,
            workerCount
        )
        local sharedQueue = prepareQueue(
            shareable,
            false,
            math.min(workerCount, #shareable),
            "shared",
            nil,
            nil,
            workerCount
        )
        local shellQueue = prepareQueue(
            shelling,
            true,
            math.min(workerCount, #shelling),
            "shell",
            nil,
            nil,
            workerCount
        )
        if isolatedQueue then
            beginPhase(("%d isolated suites across %d process workers"):format(#alone, #isolatedQueue.lanes))
        elseif sharedQueue then
            beginPhase(("%d suites across %d Nupp workers"):format(sharedQueue.count, #sharedQueue.lanes))
        elseif shellQueue then
            beginPhase(("%d shell suites across %d process workers"):format(#shelling, #shellQueue.lanes))
        end
        marked = isolatedQueue ~= nil or sharedQueue ~= nil or shellQueue ~= nil

        -- Process-global suites go first: profiler and runtime-provider state must
        -- be exercised before worker threads have existed in this process. After
        -- that, shell users can safely overlap the tail of the Nupp worker queue.
        if isolatedQueue then
            collectQueue(isolatedQueue, startFanOut(isolatedQueue.lanes, true, true, "isolated"))
        end
        if sharedQueue and isolatedQueue then
            beginPhase(("%d suites across %d Nupp workers"):format(sharedQueue.count, #sharedQueue.lanes))
        end
        local collectShared = sharedQueue and startFanOut(sharedQueue.lanes, true, false, "shared") or nil
        local collectShell
        if shellQueue then
            if sharedQueue and pauseBriefly then
                local waiting = true
                local tail = math.max(1, math.floor(#sharedQueue.lanes / 4))
                while waiting do
                    local pieces = 0
                    for index = 1, #sharedQueue.order do
                        local piece = io.open(("%s/piece-%d"):format(sharedQueue.path, index), "rb")
                        if piece then
                            piece:close()
                            pieces = pieces + 1
                        end
                    end
                    waiting = pieces > tail
                    if waiting then
                        pauseBriefly()
                    end
                end
                beginPhase(("%d shell suites joining across %d process workers"):format(#shelling, #shellQueue.lanes))
            elseif sharedQueue then
                collectQueue(sharedQueue, collectShared)
                sharedQueue, collectShared = nil, nil
                beginPhase(("%d shell suites across %d process workers"):format(#shelling, #shellQueue.lanes))
            end
            collectShell = startFanOut(shellQueue.lanes, true, true, "shell")
        end
        collectQueue(sharedQueue, collectShared)
        collectQueue(shellQueue, collectShell)

        -- Workers mark completed cases without a newline because none can know
        -- whether another lane has a final mark. The parent closes it once both
        -- phases are collected.
        if marked then
            progressWrite("\n")
            progressWidth = 0
        end

        -- Back into the order a serial run would have reported, so the output does not
        -- depend on which shard happened to finish first.
        table.sort(sharded.results, function(a, b)
            if a.suite ~= b.suite then
                return tostring(a.suite) < tostring(b.suite)
            end

            return tostring(a.name) < tostring(b.name)
        end)
        suites = {}
    end
end

--- Runs one suite, or the cases of it that one slice was given.
---
--- A parameter rather than a lookup, because the cases a process runs are
--- decided in two different ways: a shard was handed a list of specs before it
--- started, and a worker takes one spec at a time off a queue while it runs.
local restoreLane = function()
end

local function impactSourcePath(name)
    if type(name) ~= "string" then
        return nil
    end
    local modulePath = name:gsub("%.", "/")
    local candidates = {
        "src/" .. modulePath .. ".nupp",
        "src/" .. modulePath .. ".g.nupp",
        "src/" .. modulePath .. ".lua",
        "src/" .. modulePath .. "/init.nupp",
        "src/" .. modulePath .. "/init.g.nupp",
        "src/" .. modulePath .. "/init.lua",
        "tests/" .. modulePath .. ".nupp",
        "tests/" .. modulePath .. ".g.nupp",
        "tests/" .. modulePath .. ".lua",
    }
    for _, path in ipairs(candidates) do
        local file = io.open(path, "rb")
        if file then
            file:close()
            return path
        end
    end

    return nil
end

local function runSuite(suiteInfo, slices)
    -- Loading is measured with the suite rather than left out of it. A Nupp suite
    -- is compiled here, and a Lua one runs its top level here, so a suite can cost
    -- seconds before its first case starts.
    local suiteBefore = now()
    local suiteImpactPath = "tests/" .. suiteInfo.name .. "." .. suiteInfo.extension
    local savedRequire = require
    if impactObserver then
        impactObserver.beginSuite(suiteImpactPath)
        if sourceContains(suiteInfo, {'require("nupp.io.process")', "require('nupp.io.process')"}) then
            impactObserver.markUncertain(
                "child-uninstrumented",
                "suite launches through nupp.io.process without runner-owned attribution"
            )
        end
        rawset(_G, "require", function(name)
            impactObserver.recordRequest(
                name,
                impactSourcePath(name),
                package.loaded[name] ~= nil and "cached-require" or "runtime-require"
            )

            return savedRequire(name)
        end)
        impactObserver.installProcessObserver()
    end
    local loaded = preloadedSuites[suiteInfo.name]
    preloadedSuites[suiteInfo.name] = nil
    local suite, removeLoader, loadElapsed, hooks, cases
    if loaded ~= nil then
        suite = loaded.suite
        removeLoader = loaded.removeLoader
        loadElapsed = loaded.loadMs
        hooks = loaded.hooks
        cases = loaded.cases
    else
        local loadBefore = now()
        suite, removeLoader = loadSuite(suiteInfo)
        loadElapsed = now() - loadBefore
        hooks, cases = suiteParts(suiteInfo, suite)
    end

    local function finishWithoutRunning()
        if removeLoader then
            removeLoader()
        end
        if impactObserver then
            rawset(_G, "require", savedRequire)
            impactObserver.restoreProcessObserver()
            impactObserver.finishSuite()
        end
    end

    if chosenCaseCount > 0 then
        local selected = {}
        local found = {}
        for _, name in ipairs(cases) do
            local id = suiteInfo.name .. "/" .. name
            if chosenCases[id] then
                selected[#selected + 1] = name
                seenCaseIds[id] = true
                found[id] = true
            end
        end
        local prefix = suiteInfo.name .. "/"
        local missing = false
        for id in pairs(chosenCases) do
            if id:sub(1, #prefix) == prefix and not found[id] then
                missing = true
                missingCaseIds[id] = true
            end
        end
        if missing then
            finishWithoutRunning()

            return
        end
        if not wholeSuites[suiteInfo.name] then
            cases = selected
        end
    end
    local stateful = hooks.beforeAll or hooks.afterAll or hooks.beforeEach or hooks.afterEach
    if impactObserver then
        impactSliceSafe[suiteImpactPath] = not stateful
    end
    -- One slice of the suite, when the parent decided it was too heavy to leave whole.
    -- A suite with lifecycle hooks is never sliced: `beforeAll` would run once per
    -- slice and any state its cases share would be split between processes, so the
    -- whole thing goes to slice zero and the other slices find nothing to do.
    local partial = false
    for _, slice in ipairs(slices or {}) do
        if slice.count > 1 then
            partial = true
        end
    end
    if partial then
        if stateful then
            -- Never sliced: `beforeAll` would run once per slice and whatever the cases
            -- share would be split between processes. Slice zero takes the whole suite
            -- and the others find nothing to do.
            local takesAll = false
            for _, slice in ipairs(slices) do
                if slice.index == 0 then
                    takesAll = true
                end
            end
            if not takesAll then
                finishWithoutRunning()

                return
            end
        else
            -- Packing is by cost, and a shard may legitimately hold two slices of one
            -- suite, so each slice is asked for its own cases and the answers are
            -- unioned back into the sorted order the suite reports in.
            local costs = recordedCaseTimings(suiteInfo.name)
            local taken = {}
            for _, slice in ipairs(slices) do
                local where = sliceAssignment(cases, costs, slice.count)
                for _, name in ipairs(cases) do
                    if where[name] == slice.index then
                        taken[name] = true
                    end
                end
            end
            local mine = {}
            for _, name in ipairs(cases) do
                if taken[name] then
                    mine[#mine + 1] = name
                end
            end
            cases = mine
        end
    end
    local before = now()
    local ready, setupProblem, setupOut, setupErr = capture(function()
        local ok, problem = call(hooks.beforeAll)
        if not ok then
            error(problem, 0)
        end
    end)
    local setupElapsed = now() - before
    local casesElapsed = 0
    local slowestCase, slowestCaseMs = nil, -1
    if not ready then
        recordResult(
            suiteInfo.name,
            "beforeAll",
            hooks.beforeAll,
            false,
            setupProblem,
            setupOut,
            setupErr,
            setupElapsed
        )
    else
        for _, name in ipairs(cases) do
            local case = suite[name]
            if sharedProgressStream or traceCases then
                io.stderr:write("__case__:", name, "\n")
            end
            local caseBefore = now()
            local caseContext = {facts = {}, metrics = {}, capabilities = {}, fixtures = {}, fixture = resolveFixture,}
            if impactObserver then
                impactObserver.beginCase(name)
            end
            local ok, err, stdout, stderr = capture(function()
                rawset(_G, "__NUPP_TEST_CASE_CONTEXT", caseContext)
                local ran, problem = pcall(runCase, hooks, case)
                rawset(_G, "__NUPP_TEST_CASE_CONTEXT", nil)
                if not ran then
                    error(problem, 0)
                end
            end)
            rawset(_G, "__NUPP_TEST_CASE_CONTEXT", nil)
            if impactObserver then
                impactObserver.finishCase()
            end
            local caseElapsed = now() - caseBefore
            casesElapsed = casesElapsed + caseElapsed
            if caseElapsed > slowestCaseMs then
                slowestCase, slowestCaseMs = name, caseElapsed
            end
            recordResult(suiteInfo.name, name, case, ok, err, stdout, stderr, caseElapsed, caseContext)
        end
    end
    local after = now()
    local afterOk, afterProblem, afterOut, afterErr = capture(function()
        local ok, problem = call(hooks.afterAll)
        if not ok then
            error(problem, 0)
        end
    end)
    local afterElapsed = now() - after
    if not afterOk then
        recordResult(suiteInfo.name, "afterAll", hooks.afterAll, false, afterProblem, afterOut, afterErr, afterElapsed)
    end
    if removeLoader then
        removeLoader()
    end
    if impactObserver then
        rawset(_G, "require", savedRequire)
        impactObserver.restoreProcessObserver()
        impactObserver.finishSuite()
    end
    suiteRecords[
        #suiteRecords + 1
    ] = {
        suite = suiteInfo.name,
        durationMs = now() - suiteBefore + (loaded ~= nil and loadElapsed or 0),
        loadMs = loadElapsed,
        hooksMs = setupElapsed + afterElapsed,
        casesMs = casesElapsed,
        tests = #cases,
        slowestCase = slowestCase,
        slowestCaseMs = slowestCase and slowestCaseMs or nil,
    }
end

-- What a queue piece is allowed to leave behind for the next one, which is
-- nothing it can be seen to have changed.
--
-- Both kinds of lane restore now. They restore `package.loaded` differently,
-- and the difference is the whole reason a Nupp lane could not restore before:
--
--   * A process lane is a plain Lua state whose warm content is worth nothing
--     to the next piece, so it is put back exactly -- a module loaded during a
--     piece is removed.
--   * A Nupp lane's warm content is a compiled compiler, which is most of what
--     the lane exists to reuse, so it is repaired rather than reset: an entry
--     that was there when the lane started and is no longer the same value is
--     put back, and an entry that was not there is left alone. That catches the
--     contamination a piece can actually cause -- a module cleared to prove it
--     loads lazily, then "restored" as a fresh instance every earlier caller's
--     captured identity no longer matches -- without discarding the compiler
--     between every piece.
--
-- `package.path` and `package.cpath` are in the baseline because a suite that
-- points the loader somewhere and does not put it back changes where the next
-- piece's modules come from, which is the same defect wearing a different hat.
local laneBaseline = nil
if queueDir then
    local function copyTable(value)
        local copied = {}
        for key, item in pairs(value) do
            copied[key] = item
        end

        return copied
    end

    laneBaseline = {
        globals = copyTable(_G),
        loaded = copyTable(package.loaded),
        preload = copyTable(package.preload),
        path = package.path,
        cpath = package.cpath,
    }
end

restoreLane = function()
    if not laneBaseline then
        return
    end

    local function restore(value, baseline)
        for key in pairs(value) do
            if baseline[key] == nil then
                value[key] = nil
            end
        end
        for key, item in pairs(baseline) do
            value[key] = item
        end
    end

    --- Puts back what changed and leaves what was added.
    local function repair(value, baseline)
        for key, item in pairs(baseline) do
            if value[key] ~= item then
                value[key] = item
            end
        end
    end

    if embedded then
        repair(package.loaded, laneBaseline.loaded)
    else
        restore(package.loaded, laneBaseline.loaded)
    end
    restore(package.preload, laneBaseline.preload)
    restore(_G, laneBaseline.globals)
    package.path, package.cpath = laneBaseline.path, laneBaseline.cpath
end

--- What this process took off the queue, so the parent can tell work that was
--- run from work whose worker died holding it.
local claimed = {}

local function mergePieceReport(report)
    total = total + (report.total or 0)
    passed = passed + (report.passed or 0)
    skipped = skipped + (report.skipped or 0)
    notExecutedCount = notExecutedCount + (report.notExecuted or 0)
    failed = failed + (report.failed or 0)
    for _, record in ipairs(report.tests or {}) do
        results[#results + 1] = record
    end
    for _, record in ipairs(report.suites or {}) do
        suiteRecords[#suiteRecords + 1] = record
    end
    for _, fragment in ipairs(report.impactFragments or {}) do
        impactFragments[#impactFragments + 1] = fragment
    end
    for suite, safe in pairs(report.impactSliceSafe or {}) do
        impactSliceSafe[suite] = safe
    end
    for _, id in ipairs(report.seenSelectedCases or {}) do
        if chosenCases[id] then
            seenCaseIds[id] = true
        end
    end
    for _, id in ipairs(report.missingSelectedCases or {}) do
        if chosenCases[id] then
            missingCaseIds[id] = true
        end
    end
end

local function recordPieceFailure(spec, message)
    local suite = spec:match("^(.-)#") or spec
    total = total + 1
    failed = failed + 1
    results[
        #results + 1
    ] = {
        id = suite .. "/<unrun>",
        suite = suite,
        name = "<unrun>",
        status = "failed",
        durationMs = 0,
        failure = {message = message},
    }
end

local function shellQuote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function selectedCaseArguments(spec)
    local name = spec:match("^(.-)#%d+/%d+$") or spec
    local prefix = name .. "/"
    local selected = {}
    for id in pairs(chosenCases) do
        if id:sub(1, #prefix) == prefix then
            selected[#selected + 1] = id
        end
    end
    table.sort(selected)
    local arguments = {}
    if wholeSuites[name] then
        arguments[#arguments + 1] = " --internal-whole-suite=" .. shellQuote(name)
    end
    for _, id in ipairs(selected) do
        arguments[#arguments + 1] = " --case=" .. shellQuote(id)
    end

    return table.concat(arguments)
end

--- Runs one claimed isolated piece in a new process.
---
--- The long-lived process owns only queue claims and aggregation. The child is
--- handed a shard rather than the queue, so it cannot claim a second piece and
--- no module, FFI registration, or nested global table survives into the next
--- child. The supervisor's cache environment is inherited, retaining the warm
--- per-lane compiler store without retaining its process state.
local function runFreshPiece(spec)
    local invocation = rawget(_G, "__NUPP_TEST_RUNNER_COMMAND") or ("luajit '%s'"):format(arg[0])
    local errors = os.tmpname()
    local command = (
        "{ NUPP_TEST_SUPERVISED_PIECE=1 %s --json --shard=%s%s --color=%s%s%s; "
        .. "printf '\n__piece_status__:%%d\n' $?; } 2>%s"
    ):format(
        invocation,
        shellQuote(spec),
        selectedCaseArguments(spec),
        colorMode,
        verbose and " --verbose" or "",
        impactRecording and (" --internal-impact-record=" .. impactRecordId) or "",
        shellQuote(errors)
    )
    local pipe = io.popen(command, "r")
    if not pipe then
        os.remove(errors)
        recordPieceFailure(spec, "the isolated piece could not be started")
        mark("E")
        return
    end
    local text = pipe:read("*a") or ""
    pipe:close()
    local status = tonumber(text:match("__piece_status__:(%d+)%s*$"))
    text = text:gsub("%s*__piece_status__:%d+%s*$", "")
    local errorFile = io.open(errors, "rb")
    local stderr = errorFile and (errorFile:read("*a") or "") or ""
    if errorFile then
        errorFile:close()
    end
    os.remove(errors)
    local decoded, report = pcall(testJson.decode, text)
    if not decoded or type(report) ~= "table" then
        local detail = {
            "the isolated piece wrote no report",
            status and ("exit " .. status) or "unreported exit status",
            #text .. " bytes on stdout",
        }
        if not decoded then
            detail[#detail + 1] = "JSON decode: " .. tostring(report)
        end
        if #text > 0 then
            detail[#detail + 1] = "stdout: " .. text:sub(-2000)
        end
        if #stderr > 0 then
            detail[#detail + 1] = "stderr: " .. stderr:sub(-2000)
        end
        recordPieceFailure(spec, table.concat(detail, "; "))
        mark("E")
        return
    end

    local beforePassed = passed
    local beforeFailed = failed
    local beforeNotExecuted = notExecutedCount
    mergePieceReport(report)
    mark(
        failed > beforeFailed and "E"
        or passed > beforePassed and "."
        or notExecutedCount > beforeNotExecuted and "N"
        or "S"
    )
end

--- Takes work until there is none left.
---
--- Packing the whole run in advance needs the cost of every suite known in
--- advance, and it is not: the record is what the last run measured under its
--- own load, and a run measures a suite two or three times slower when it lands
--- beside four heavy ones than when it lands beside nothing. Packed from that,
--- the busiest shard came out near twice the mean and the run waited on it.
---
--- So the parent orders the work longest-first and every worker takes the next
--- piece when it has finished the last. An estimate that was wrong then costs
--- the difference rather than the whole imbalance, and the makespan is the mean
--- plus one piece.
---
--- A claim is an exclusive file creation when the runtime exposes it. This is
--- atomic between the Lua states hosted by one process on Windows, where two
--- concurrent CRT renames have both reported success for one source. Portable
--- Lua falls back to the rename protocol used by its process workers.
local function takeWork()
    local file = io.open(queueDir .. "/order", "rb")
    if not file then
        return
    end
    local specs = {}
    for line in file:lines() do
        if line ~= "" then
            specs[#specs + 1] = line
        end
    end
    file:close()

    local cursor = 0
    while true do
        local took = nil
        for step = 1, #specs do
            local index = (cursor + step - 1) % #specs + 1
            local piece = ("%s/piece-%d"):format(queueDir, index)
            local mine = ("%s/taken-%d"):format(queueDir, index)
            local won
            if exclusiveCreate then
                won = exclusiveCreate(mine)
            else
                won = os.rename(piece, mine)
            end
            if won then
                if exclusiveCreate then
                    assert(os.remove(piece), "cannot retire a claimed test queue piece")
                end
                took, cursor = index, index
                break
            end
        end
        if not took then
            return
        end
        local spec = specs[took]
        claimed[#claimed + 1] = spec
        if freshQueuePieces then
            if sharedProgressStream then
                io.stderr:write("__suite__:", spec, "\n")
            end
            runFreshPiece(spec)
            restoreLane()
        else
            local name, index, count = spec:match("^(.-)#(%d+)/(%d+)$")
            name = name or spec
            local suiteInfo = byName[name]
            if suiteInfo then
                -- Named before it is run, so that a worker which dies mid-suite says
                -- which one. A report arrives only when a shard finishes, so a killed
                -- worker sends nothing and every suite it claimed reads as `<unrun>`,
                -- including the ones it had already passed -- the crash is somewhere
                -- in a lane of dozens with nothing to say where. This goes to standard
                -- error, which for a worker is the file the parent keeps for exactly
                -- this question, and is marked so the parent can take the last one and
                -- leave the rest out of what it prints.
                if sharedProgressStream then
                    io.stderr:write("__suite__:", spec, "\n")
                end
                local beforeTotal, beforePassed = total, passed
                local beforeFailed = failed
                local beforeNotExecuted = notExecutedCount
                runSuite(suiteInfo, index and {{index = tonumber(index), count = tonumber(count)}} or nil)
                if total > beforeTotal then
                    mark(
                        failed > beforeFailed and "E"
                        or passed > beforePassed and "."
                        or notExecutedCount > beforeNotExecuted and "N"
                        or "S"
                    )
                end
            end
            restoreLane()
        end
    end
end

if queueDir then
    takeWork()
else
    for _, suiteInfo in ipairs(suites) do
        -- Named before it is run, so that a worker which dies mid-suite says
        -- which one. A report arrives only when a shard finishes, so a killed
        -- worker sends nothing and every suite it was given reads as `<unrun>`,
        -- including the ones it had already passed -- the crash is somewhere in a
        -- lane of dozens with nothing to say where. This goes to standard error,
        -- which for a worker is the file the parent keeps for exactly this
        -- question, and is marked so the parent can take the last one and leave
        -- the rest out of what it prints.
        if sharedProgressStream then
            io.stderr:write("__suite__:", suiteInfo.name, "\n")
        end
        runSuite(suiteInfo, wanted and wanted[suiteInfo.name] or nil)
    end
end
if chosenCaseCount > 0 and not queueDir then
    local missing = {}
    for id in pairs(chosenCases) do
        if not seenCaseIds[id] then
            missing[#missing + 1] = id
            missingCaseIds[id] = true
        end
    end
    if #missing > 0 and not supervisedPiece then
        table.sort(missing)
        io.stderr:write("nupp: no test case named " .. table.concat(missing, ", ") .. "\n")
        os.exit(2)
    end
end
local duration = now() - started
if sharded then
    -- Added to what this process ran rather than replacing it: the exclusive
    -- suites were run here, after the shards, and are already in `results`.
    for _, record in ipairs(sharded.results) do
        results[#results + 1] = record
    end
    for _, record in ipairs(sharded.suites) do
        suiteRecords[#suiteRecords + 1] = record
    end
    total = total + sharded.total
    passed = passed + sharded.passed
    skipped = skipped + sharded.skipped
    notExecutedCount = notExecutedCount + sharded.notExecuted
    failed = failed + sharded.failed
    for _, fragment in ipairs(sharded.impactFragments or {}) do
        impactFragments[#impactFragments + 1] = fragment
    end
    for suite, safe in pairs(sharded.impactSliceSafe or {}) do
        impactSliceSafe[suite] = safe
    end
    table.sort(results, function(a, b)
        if a.suite ~= b.suite then
            return tostring(a.suite) < tostring(b.suite)
        end

        return tostring(a.name) < tostring(b.name)
    end)
end

-- Recorded by the parent after all lanes are collected, so the next run packs
-- from every suite rather than whichever queue one worker happened to claim.
-- A shard was handed its share and a slice ran part of a suite, so neither has
-- anything to say about what a whole suite costs. Any other run does, however
-- narrow its selection was, because what it measured is merged over what was
-- there rather than written in place of it.
if #shard == 0 and not queueDir then
    rememberTimings(suiteRecords, results)
end

-- Coverage-generated modules share one small global counter table.  The runner owns
-- the process boundary, so it is the right place to turn that in-memory table into a
-- shard the parent `nupp test --coverage` command can merge after the test process
-- exits.
local coverageFile = os.getenv("NUPP_COVERAGE_FILE")
local coverage = coverageFile and rawget(_G, "__nuppCoverage") or nil
if coverageFile and coverage then
    local json = testJson
    local merged = {}
    local previous = io.open(coverageFile, "rb")
    if previous then
        local text = previous:read("*a")
        previous:close()
        local ok, old = pcall(json.decode, text)
        if ok and type(old) == "table" and type(old.hits) == "table" then
            merged = old.hits
        end
    end
    for path, counters in pairs(coverage.hits) do
        local into = merged[path] or {}
        merged[path] = into
        for id, count in pairs(counters) do
            into[id] = (into[id] or 0) + count
        end
    end
    local f, coverageErr = io.open(coverageFile, "wb")
    if not f then
        io.stderr:write("nupp: cannot write coverage data: " .. tostring(coverageErr) .. "\n")
    else
        f:write(json.encode({hits = merged}) .. "\n")
        f:close()
    end
end

if progressWidth ~= 0 then
    progressWrite("\n")
end

table.sort(suiteRecords, function(a, b)
    local left, right = tonumber(a.durationMs) or 0, tonumber(b.durationMs) or 0
    if left ~= right then
        return left > right
    end

    return tostring(a.suite) < tostring(b.suite)
end)

local metricTotalsByKey = {}
for _, record in ipairs(results) do
    for _, metric in ipairs(record.metrics or {}) do
        local key = metric.name .. "\0" .. (metric.unit or "")
        local totalMetric = metricTotalsByKey[key]
        if totalMetric == nil then
            totalMetric = {name = metric.name, value = 0, unit = metric.unit}
            metricTotalsByKey[key] = totalMetric
        end
        totalMetric.value = totalMetric.value + metric.value
    end
end
local metricTotals = {}
for _, metric in pairs(metricTotalsByKey) do
    metricTotals[#metricTotals + 1] = metric
end
table.sort(metricTotals, function(a, b)
    return a.name .. "\0" .. (a.unit or "") < b.name .. "\0" .. (b.unit or "")
end)

if impactObserver then
    impactFragments[#impactFragments + 1] = impactObserver.fragment(failed == 0)
    impactObserve.activate(nil)
end

if unfilteredTopLevel and impactRecording and failed == 0 then
    local impact = require("runner.impact")
    local discoveredHead = impact.discoverChanges({cwd = "."})
    if discoveredHead.available and #discoveredHead.paths == 0 then
        local stamps = assert(
            impact.graphStamps({
                project = discoveredHead.root,
                revision = discoveredHead.head,
                operatingSystem = (jit and jit.os) or package.config:sub(1, 1),
                architecture = (jit and jit.arch) or "portable",
                runtime = (jit and jit.version) or _VERSION,
                targetProfile = "test",
                suiteCatalog = suiteCatalog ~= "" and suiteCatalog or "empty",
                stableIds = "suite-path+case-name/1",
            })
        )
        local catalogBySuite = {}
        for _, fragment in ipairs(impactFragments) do
            for _, owner in ipairs(fragment.owners or {}) do
                local suite = catalogBySuite[owner.suite]
                if not suite then
                    suite = {
                        identity = owner.suite,
                        path = owner.suite,
                        sliceSafe = impactSliceSafe[owner.suite] == true,
                        cases = {},
                        _cases = {},
                    }
                    catalogBySuite[owner.suite] = suite
                end
                if owner.caseId and not suite._cases[owner.caseId] then
                    suite._cases[owner.caseId] = true
                    suite.cases[#suite.cases + 1] = {id = owner.caseId, sliceSafe = suite.sliceSafe,}
                end
            end
        end
        local catalog = {}
        for _, suite in pairs(catalogBySuite) do
            suite._cases = nil
            table.sort(suite.cases, function(left, right)
                return left.id < right.id
            end)
            catalog[#catalog + 1] = suite
        end
        table.sort(catalog, function(left, right)
            return left.identity < right.identity
        end)
        local observation = impact.mergeFragmentsToObservation(impactFragments, catalog, stamps, {
            runId = impactRecordId,
            platform = (jit and (jit.os .. "/" .. jit.arch)) or _VERSION,
            complete = #catalog == #discovered,
            successful = true,
            unfiltered = true,
        })
        if observation.complete then
            local published, problem = impact.publish(buildRoot, observation)
            if not published then
                io.stderr:write("nupp: cannot publish test impact graph: " .. tostring(problem) .. "\n")
            end
        else
            local problems = {}
            for _, problem in ipairs(observation.problems or {}) do
                local example = problem.example and (" (for example " .. problem.example .. ")") or ""
                problems[#problems + 1] = problem.code .. "=" .. tostring(problem.count) .. example
            end
            io.stderr:write("nupp: test impact graph was incomplete: " .. table.concat(problems, "; ") .. "\n")
        end
    end
end
if unfilteredTopLevel and impactRecording and impactFragmentDir then
    os.execute("rm -rf " .. string.format("%q", impactFragmentDir))
end

--- Where the run's time went, in the two units a person can act on.
---
--- Wall clock is what was waited for; work is what was spent, added up across the
--- shards. The distance between them is the parallelism actually achieved, and
--- the longest single shard is the floor no amount of extra shards moves -- which
--- is why the shard line reports the busiest one rather than only the average.
local function timingReport()
    local out = {}

    local function say(text)
        out[#out + 1] = text
    end

    -- Seconds once there are seconds to report, milliseconds while there are not.
    -- Most suites are under a second and a column of `0.0s` says nothing about
    -- which of them is a hundred times the others.
    local function seconds(ms)
        ms = tonumber(ms) or 0
        if ms < 1000 then
            return ("%.0fms"):format(ms)
        end

        return ("%.1fs"):format(ms / 1000)
    end

    local work = 0
    for _, record in ipairs(suiteRecords) do
        work = work + (tonumber(record.durationMs) or 0)
    end
    local headline = (
        "\n%s %s wall, %s of suite work"
    ):format(paint("1;36", "Timing:"), seconds(duration), seconds(work))
    -- Process-global work runs first, then the Nupp queue with shell workers
    -- joining its tail. Keep those three costs separate in the report.
    local byExecutionLane = {isolated = {}, shared = {}, shell = {},}
    for _, entry in ipairs(sharded and sharded.shards or {}) do
        local executionLane = entry.executionLane or (entry.alone and "isolated" or "shared")
        local entries = byExecutionLane[executionLane]
        entries[#entries + 1] = entry
    end

    local function phase(label, entries, prediction)
        if #entries == 0 then
            return
        end
        local busiest, idlest, spent = 0, math.huge, 0
        for _, entry in ipairs(entries) do
            local ms = tonumber(entry.durationMs) or 0
            spent = spent + ms
            if ms > busiest then
                busiest = ms
            end
            if ms < idlest then
                idlest = ms
            end
        end
        headline = headline .. (
            "\n  %d %s: busiest %s, idlest %s, mean %s"
        ):format(#entries, label, seconds(busiest), seconds(idlest), seconds(spent / #entries))
        -- The busiest lane is the phase's critical path. Beside it, what the
        -- packer predicted from the last run's timings: close together means the
        -- plan was right and the phase is as short as this much work gets, and
        -- far apart means either the timings are stale or one lane was starved.
        if prediction then
            headline = headline .. (
                ", predicted %s from %s over %d lanes, heaviest piece %s"
            ):format(
                seconds(prediction.floor),
                seconds(prediction.planned),
                prediction.lanes,
                seconds(prediction.heaviest)
            )
        end
    end

    phase("isolated process workers", byExecutionLane.isolated, predictions.isolated)
    phase("Nupp worker shards", byExecutionLane.shared, predictions.shared)
    phase("shell process workers", byExecutionLane.shell, predictions.shell)
    say(headline .. "\n")

    local shown = 0
    say(
        "\n" .. paint(
            "1;36",
            ("  %-27s %8s %8s %8s %8s %6s"):format("slowest suites", "wall", "load", "hooks", "cases", "tests")
        ) .. "\n"
    )
    for _, record in ipairs(suiteRecords) do
        if shown >= timingRows then
            say(("  %-27s (%d more)\n"):format("", #suiteRecords - shown))
            break
        end
        shown = shown + 1
        say(
            (
                "  %-27s %8s %8s %8s %8s %6d\n"
            ):format(
                tostring(record.suite):sub(1, 27),
                seconds(record.durationMs),
                seconds(record.loadMs),
                seconds(record.hooksMs),
                seconds(record.casesMs),
                tonumber(record.tests) or 0
            )
        )
    end

    local slowest = {}
    for _, record in ipairs(results) do
        slowest[#slowest + 1] = record
    end
    table.sort(slowest, function(a, b)
        local left, right = tonumber(a.durationMs) or 0, tonumber(b.durationMs) or 0
        if left ~= right then
            return left > right
        end

        return tostring(a.suite) .. tostring(a.name) < tostring(b.suite) .. tostring(b.name)
    end)
    shown = 0
    say("\n" .. paint("1;36", ("  %-53s %8s"):format("slowest tests", "wall")) .. "\n")
    for _, record in ipairs(slowest) do
        if shown >= timingRows then
            say(("  %-53s (%d more)\n"):format("", #slowest - shown))
            break
        end
        shown = shown + 1
        local label = ("%s / %s"):format(tostring(record.suite), tostring(record.name))
        say(("  %-53s %8s\n"):format(label:sub(1, 53), seconds(record.durationMs)))
    end

    return table.concat(out)
end

local seenSelectedCases = {}
for id in pairs(seenCaseIds) do
    if chosenCases[id] then
        seenSelectedCases[#seenSelectedCases + 1] = id
    end
end
table.sort(seenSelectedCases)
local missingSelectedCases = {}
for id in pairs(missingCaseIds) do
    if chosenCases[id] and not seenCaseIds[id] then
        missingSelectedCases[#missingSelectedCases + 1] = id
    end
end
table.sort(missingSelectedCases)

local report = {
    ok = failed == 0,
    total = total,
    passed = passed,
    skipped = skipped,
    notExecuted = notExecutedCount,
    failed = failed,
    durationMs = duration,
    tests = results,
    metrics = metricTotals,
    suites = suiteRecords,
    shards = sharded and sharded.shards or {},
    claimed = #claimed > 0 and claimed or nil,
    seenSelectedCases = (#shard > 0 or queueDir) and seenSelectedCases or nil,
    missingSelectedCases = (#shard > 0 or queueDir) and missingSelectedCases or nil,
    selection = selectionReport,
    impactFragments = impactRecording and not unfilteredTopLevel and impactFragments or nil,
    impactSliceSafe = impactRecording and not unfilteredTopLevel and impactSliceSafe or nil,
}

if embedded then
    return report
elseif asJson then
    local json = testJson
    io.write(
        json.encode({
            ok = report.ok,
            total = total,
            passed = passed,
            skipped = skipped,
            notExecuted = notExecutedCount,
            failed = failed,
            durationMs = duration,
            tests = json.asArray(results),
            metrics = json.asArray(metricTotals),
            suites = json.asArray(suiteRecords),
            shards = json.asArray(sharded and sharded.shards or {}),
            -- What the packer said each phase could not finish under, beside
            -- what it did. A phase far above its prediction was packed from
            -- stale timings or starved a lane; one at its prediction is as
            -- short as that much work gets, and only less work shortens it.
            prediction = (predictions.isolated or predictions.shared or predictions.shell)
            and {processIsolated = predictions.isolated, shared = predictions.shared, shell = predictions.shell,}
            or nil,
            -- What this process took off a queue, which is how the parent tells work
            -- that ran from work whose worker died holding it. A run that was not
            -- handed a queue took nothing, and says nothing.
            claimed = #claimed > 0 and json.asArray(claimed) or nil,
            seenSelectedCases = report.seenSelectedCases and json.asArray(report.seenSelectedCases) or nil,
            missingSelectedCases = report.missingSelectedCases and json.asArray(report.missingSelectedCases) or nil,
            selection = selectionReport,
            impactFragments = impactRecording and not unfilteredTopLevel and json.asArray(impactFragments) or nil,
            impactSliceSafe = impactRecording and not unfilteredTopLevel and impactSliceSafe or nil
        }) .. "\n"
    )
else
    if failed > 0 then
        io.write("\n" .. paint("1;31", "Failures:") .. "\n")
        for _, record in ipairs(results) do
            if record.status == "failed" then
                local label = ("%s / %s"):format(record.suite, record.name)
                io.write(("\n  %s\n      %s\n"):format(paint("1;31", label), record.failure.message))
                io.write(captured(record))
            end
        end
    end
    local summary = notExecutedCount > 0
        and (
            "%d tests, %d passed, %d skipped, %d not executed, %d failed (%.1fms)"
        ):format(total, passed, skipped, notExecutedCount, failed, duration)
        or ("%d tests, %d passed, %d skipped, %d failed (%.1fms)"):format(total, passed, skipped, failed, duration)
    io.write("\n" .. paint(failed == 0 and "1;32" or "1;31", summary) .. "\n")
    if timingRows > 0 and #suiteRecords > 0 then
        io.write(timingReport())
    end
end
-- A run that discovered nothing is a broken run, not a passing one. Reported
-- only where the whole selection is known: a shard child is handed its share of
-- the work, and a slice of a suite that carries lifecycle hooks is legitimately
-- empty because slice zero took every case.
if #shard == 0 and not queueDir and total == 0 and not (selectionReport and selectionReport.emptyReason) then
    io.stderr:write("nupp: no tests were discovered\n")
    os.exit(1)
end

os.exit(supervisedPiece and #missingSelectedCases > 0 and 2 or failed == 0 and 0 or 1)
