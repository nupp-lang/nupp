-- The heap and the collector written standalone in the native profile
-- (`nupp.runtime.vm.heap`, `collector`, `gcweak`), lowered by
-- `nupp.compiler.clif.lower` and run through the glue's just-in-time runner
-- (`nupp-vm native jit`), each case in a process of its own. The fixtures
-- under `tests/fixtures/nativeheap/` build synthetic heaps and answer counts
-- this suite computes independently.
local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
-- Absolute, since the cold check runs from the project it checks.
local ROOT = (function()
    local pipe = assert(io.popen("cd '" .. HERE:gsub("'", "'\\''") .. "/..' && pwd"))
    local path = assert(pipe:read("*l"))
    pipe:close()
    return path
end)()
local FIXTURES = ROOT .. "/tests/fixtures/nativeheap"

local lower = require("nupp.compiler.clif.lower")

local M = {}

local function quote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function capture(command)
    local pipe = assert(io.popen(command .. " 2>&1; echo __exit__:$?"))
    local output = pipe:read("*a")
    pipe:close()
    local status = tonumber(output:match("__exit__:(%d+)%s*$"))

    return status, (output:gsub("__exit__:%d+%s*$", ""))
end

local glue = nil

local function glueTool()
    if not glue then
        local status, output = capture(("cd %s && python3 scripts/vm-cli glue"):format(quote(ROOT)))
        assert(status == 0, "scripts/vm-cli glue failed: " .. output)
        glue = assert(output:match("([^\r\n]+)%s*$"), "scripts/vm-cli glue named no tool")
    end

    return glue
end

local function tempDirectory()
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p " .. quote(dir)) == 0)
    return dir
end

local function write(path, text)
    local file = assert(io.open(path, "wb"))
    file:write(text)
    file:close()
end

-- The runtime modules a fixture is compiled with.
local RUNTIME = {"heap", "arena", "values", "objecthash", "objectweak", "marking", "weakentries"}

local compiled = {}

local function compileFixture(name, runtimeModules)
    if compiled[name] then
        return compiled[name]
    end
    local selected = {}
    local seen = {}
    for _, module in ipairs(runtimeModules or RUNTIME) do
        if not seen[module] then
            selected[#selected + 1] = module
            seen[module] = true
        end
    end
    if seen.marking then
        for _, module in ipairs({"childwalk", "objecttable", "backing"}) do
            if not seen[module] then
                selected[#selected + 1] = module
                seen[module] = true
            end
        end
    end
    if seen.collector then
        for _, module in ipairs({"childwalk", "objectwalk", "objecttable", "backing"}) do
            if not seen[module] then
                selected[#selected + 1] = module
                seen[module] = true
            end
        end
    end
    -- The collector's weak release path uses the same native indexes.
    if seen.gcweak then
        for _, module in ipairs({"weakindex", "backing", "objecttable"}) do
            if not seen[module] then
                selected[#selected + 1] = module
            end
        end
    end
    local paths = {FIXTURES .. "/" .. name .. ".nupp"}
    for _, module in ipairs(selected) do
        paths[#paths + 1] = ROOT .. "/src/nupp/runtime/vm/" .. module .. ".nupp"
    end
    local clif = lower.compile(ROOT, paths, {include = {"src", "tests/fixtures/nativeheap"}})
    local path = tempDirectory() .. "/" .. name .. ".clif"
    write(path, clif)
    compiled[name] = path

    return path
end

local function run(clif, name, args, input)
    local words = {}
    for index, arg in ipairs(args) do
        words[index] = quote(arg)
    end
    local command = (
        "%s native jit %s %s %s"
    ):format(quote(glueTool()), quote(clif), quote(name), table.concat(words, " "))
    if input then
        command = command .. " < " .. quote(input)
    end
    local status, output = capture(command)
    assert(status == 0, ("%s(%s): exit %s: %s"):format(name, table.concat(args, ", "), tostring(status), output))

    return (output:gsub("%s+$", ""))
end

local function check(clif, cases)
    for _, case in ipairs(cases) do
        local name, args, expected = case[1], case[2], case[3]
        local got = run(clif, name, args)
        local label = ("%s(%s)"):format(name, table.concat(args, ", "))
        assert(got == tostring(expected), label .. ": expected " .. tostring(expected) .. ", got " .. got)
    end
end

-- `heap.rs`'s size classes, and the chunk and slot arithmetic over them.
local CLASSES = {
    32,
    48,
    64,
    80,
    96,
    112,
    128,
    160,
    192,
    224,
    256,
    320,
    384,
    448,
    512,
    640,
    768,
    1024,
    1280,
    1536,
    2048,
    2560,
    3072,
    4096,
    6144,
    8192,
    12288,
    16384,
    24576,
    32768
}
local CHUNK, CHUNK_HEADER, HEADER = 262144, 64, 32

local function classOf(size)
    for index, bytes in ipairs(CLASSES) do
        if bytes >= size then
            return index - 1
        end
    end

    return 255
end

local function classSum()
    local total = 0
    for size = 1, 32768 do
        total = total + classOf(size) * (size % 7 + 1)
    end

    return total + classOf(32769)
end

local function chunksFor(count, inline)
    local slots = (CHUNK - CHUNK_HEADER) // CLASSES[classOf(HEADER + inline) + 1]
    return (count + slots - 1) // slots
end

local ALLOCATOR = {
    {"headerLayout", {}, 0},
    {"minimumObjects", {}, 0},
    {"arenaMetadataSurvivesAllocation", {}, 0},
    {"classSum", {}, classSum()},
    {"chunksFor", {10000, 16}, chunksFor(10000, 16)},
    {"chunksFor", {5460, 16}, 1},
    {"chunksFor", {5461, 16}, 2},
    {"chunksFor", {300, 4000}, chunksFor(300, 4000)},
    {"liveSlots", {10000, 16}, 10000},
    {"liveSlots", {500, 1000}, 500},
    {"liveSlots", {20, 40000}, 20},
    {"notSlots", {}, 0},
    {"reuse", {1000}, 500},
    {"reuse", {20000}, 10000 + (chunksFor(20000, 16) - 1) * 1000000},
    {"quarantined", {1000}, 1000},
    {"largeObjects", {10, 100000}, 10000},
    -- A table of 80 bytes in a 112-byte slot, a string of 9, one of 50000 on
    -- its own mapping, 32 bytes held outside: two freed leave 41 + 32.
    {"accounting", {}, 1000073},
    {"wordSet", {10000}, 0},
    {"wordSet", {3}, 0},
}

function M.theAllocatorHandsOutSlotsBySizeClassAndKnowsItsOwn()
    check(compileFixture("allocator"), ALLOCATOR)
end

function M.ownedHashStorageSharesBackingOrderAndRefusalPolicy()
    local modules = {"heap", "arena", "values", "objecthash", "objecttable", "backing"}
    check(compileFixture("valuetable", modules), {
        {"ownedHashChurn", {8}, 0},
        {"ownedHashChurn", {10000}, 0},
        {"ownedHashRefusalAndPoolReuse", {}, 0},
    })
end

-- The nodes of a ternary tree of `count` left after the root's first
-- subtree is unlinked.
local function ternaryAfterCut(count)
    local cut, stack = 0, {1}
    while #stack > 0 do
        local index = table.remove(stack)
        if index < count then
            cut = cut + 1
            for child = 3 * index + 1, 3 * index + 3 do
                stack[#stack + 1] = child
            end
        end
    end

    return count - cut
end

local GRAPHS = {
    {"listSurvives", {1000, 5000}, 1000},
    {"listSurvives", {0, 100}, 0},
    {"rings", {10, 100}, 500},
    {"rings", {1, 1000}, 1000},
    -- A hub of 5,000 slots is a large object; children of 40,000 bytes are too.
    {"fanOut", {100, 16}, 51},
    {"fanOut", {5000, 16}, 2501},
    {"fanOut", {50, 40000}, 26},
    -- The chain, its root, and a leaf under every seventh node.
    {"interleaved", {3000}, 1 + 3000 + 429},
    {"interleaved", {500}, 1 + 500 + 72},
    {"stressed", {200}, ternaryAfterCut(200)},
    {"stressed", {1}, 1},
    {"initializedBlack", {}, 1},
    {"barrierKeeps", {"false"}, 1},
    {"barrierKeeps", {"true"}, 0},
    -- Six roots in the frames, none once the task is done.
    {"frames", {}, 600},
    -- Four held, then the constant and the kept handle; the released index reused.
    {"handlesAndScopes", {}, 40021},
    {"scopedRegistration", {}, 20},
    {"nonnullRootCandidates", {}, 621},
}

function M.theCollectorKeepsWhatIsReachableAndFreesTheRest()
    check(
        compileFixture("graphs", {
            "heap",
            "collector",
            "gcweak",
            "arena",
            "values",
            "objecthash",
            "objectweak",
            "marking",
            "weakentries"
        }),
        GRAPHS
    )
end

-- Pacing alone runs the cycles: a million allocations of 48 bytes keep a
-- bounded ring live, and live bytes stay near the threshold's floor.
function M.allocationDebtPacesTheCycles()
    local clif = compileFixture("graphs", {
        "heap",
        "collector",
        "gcweak",
        "arena",
        "values",
        "objecthash",
        "objectweak",
        "marking",
        "weakentries"
    })
    local answer = tonumber(run(clif, "paced", {1000000, 100}))
    assert(answer and answer > 0, "paced answered " .. tostring(answer))
    assert(answer % 1000 == 65, "the ring and its 64 nodes survive, got " .. answer)
    assert(answer // 1000 >= 10, "allocation debt ran too few cycles: " .. answer // 1000)
end

-- Smoke numbers, read from the report rather than asserted.
function M.allocationAndCollectionThroughputRun()
    local clif = compileFixture("graphs", {
        "heap",
        "collector",
        "gcweak",
        "arena",
        "values",
        "objecthash",
        "objectweak",
        "marking",
        "weakentries"
    })
    for _, case in ipairs({{"allocNanos", {1000000, 1}}, {"collectNanos", {500000}}}) do
        local nanos = tonumber(run(clif, case[1], case[2]))
        assert(nanos and nanos > 0, case[1] .. " answered no time")
    end
    local alloc = compileFixture("allocator")
    assert(tonumber(run(alloc, "allocFreeNanos", {1000000, 16})) ~= nil)
end

-- ---- differential replay of recorded traces --------------------------------

local function read(path)
    local file = assert(io.open(path, "rb"), "cannot read " .. path)
    local text = file:read("*a")
    file:close()
    return text
end

-- The launcher selects an explicit compiler/runtime pair for this process.
-- Direct suite runners can instead use the installed pair.
local function compilerPackage()
    local runtime, image = os.getenv("NUPP_VM_BINARY"), os.getenv("NUPP_VM_CLI_IMAGE")
    if runtime and image then
        return {runtime = runtime, image = image}
    end
    local generation = read(ROOT .. "/.nupp/vm-cli/current"):gsub("%s+$", "")
    local package = ROOT .. "/.nupp/vm-cli/" .. generation

    return {runtime = package .. "/runtime", image = package .. "/compiler.image"}
end

local WORKLOADS = {"fib", "loops", "tables", "strings", "records", "closures"}

-- A project holding the workloads as `wl.<name>`, each with `main`.
local function workloadProject()
    local dir = tempDirectory()
    assert(os.execute("mkdir -p " .. quote(dir .. "/src/wl")) == 0)
    write(dir .. "/nupp.lua", 'return {name = "wl", include = {"src"}}\n')
    for _, name in ipairs(WORKLOADS) do
        write(dir .. "/src/wl/" .. name .. ".nupp", read(FIXTURES .. "/workloads/" .. name .. ".nupp"))
    end

    return dir
end

-- The traces a recording wrote into `dir`, one per thread that allocated.
local function traces(dir)
    local pipe = assert(io.popen("ls " .. quote(dir)))
    local paths = {}
    for line in pipe:lines() do
        paths[#paths + 1] = dir .. "/" .. line
    end
    pipe:close()
    assert(#paths > 0, "no trace in " .. dir)

    return paths
end

local function onlyTrace(dir)
    local paths = traces(dir)
    assert(#paths == 1, "expected one trace in " .. dir .. ", found " .. #paths)
    return paths[1]
end

-- Runs a workload on the selected Nupp core runtime with the recorder,
-- and answers its trace.
local function recordWorkload(project, name)
    local package = compilerPackage()
    local image = project .. "/" .. name .. ".image"
    local status, output = capture(
        (
            "%s run %s nupp.tools.vm.project emit %s wl.%s '' --output %s"
        ):format(quote(package.runtime), quote(package.image), quote(project), name, quote(image))
    )
    assert(status == 0, "emitting " .. name .. ": " .. output)
    local dir = tempDirectory()
    status, output = capture(
        ("NUPP_HEAP_TRACE=%s %s run %s wl.%s main"):format(quote(dir), quote(package.runtime), quote(image), name)
    )
    assert(status == 0, "running " .. name .. ": " .. output)

    return onlyTrace(dir)
end

-- Replays a trace into the Nupp heap: its counts by label, and the answer.
local function replay(trace)
    local clif = compileFixture("replay", {
        "heap",
        "collector",
        "gcweak",
        "arena",
        "values",
        "objecthash",
        "objectweak",
        "marking",
        "weakentries"
    })
    local output = run(clif, "replayTrace", {}, trace)
    local counts = {}
    for label, count in output:gmatch("(%a+) (%d+)\n") do
        counts[label] = tonumber(count)
    end
    counts.answer = tonumber(output:match("(%-?%d+)$"))
    assert(counts.snapshot, "the replay reported nothing: " .. output)

    return counts, output
end

-- Each workload's trace, replayed: the Nupp collector's marking from the
-- recorded roots agrees with the Rust collector's on every object of every
-- snapshot, exactly in atomic cycles and up to floating garbage otherwise.
function M.recordedWorkloadsReplayWithTheSameSurvivors()
    local project = workloadProject()
    for _, name in ipairs(WORKLOADS) do
        local counts, output = replay(recordWorkload(project, name))
        assert(counts.answer == 0, name .. " disagrees:\n" .. output)
        assert(counts.kept == 0 and counts.freed == 0, name .. " disagrees:\n" .. output)
        assert(counts.snapshot >= 1 and counts.atomic >= 1, name .. " recorded no atomic snapshot:\n" .. output)
        assert(counts.compared > 0 and counts.allocs > 0, name .. " compared nothing:\n" .. output)
    end
end

-- A cold check of a small project (the workloads), the compiler running on the
-- installed Nupp core runtime with the recorder on: its weak tables, interned strings
-- and incremental cycles replay with the same survivors.
function M.aRecordedColdCheckReplaysWithTheSameSurvivors()
    local project = workloadProject()
    local dir = tempDirectory()
    local package = compilerPackage()
    local status, output = capture(
        (
            "cd %s && NO_JIT=1 NUPP_VM_CLI_IMAGE=%s NUPP_VM_BINARY=%s NUPP_HEAP_TRACE=%s %s check"
        ):format(quote(project), quote(package.image), quote(package.runtime), quote(dir), quote(ROOT .. "/bin/nupp"))
    )
    assert(status == 0, "the check failed: " .. output)
    local snapshots = 0
    for _, trace in ipairs(traces(dir)) do
        local counts, replayed = replay(trace)
        assert(counts.answer == 0, "the check's trace disagrees:\n" .. replayed)
        snapshots = snapshots + counts.snapshot
    end
    assert(snapshots >= 2, "the check collected too little to compare: " .. snapshots)
end

-- Weak tables, the lookup barrier and the released list.
local WEAK = {
    -- Array length and mirror 2, the dead entry cleared, the live one kept,
    -- both unrooted nodes freed.
    {"weakValues", {}, 22111},
    {"unchangedWeakExtent", {}, 22},
    {"cycleModeSnapshot", {}, 1111},
    {"ephemerons", {}, 1111},
    {"weakBoth", {}, 111},
    {"lookupBarrier", {}, 111},
    {"released", {}, 1111},
    -- Every third node of the weak table is also held by the list.
    {"interleavedWeak", {3000}, 1000},
    {"interleavedWeak", {301}, 101},
}

function M.weakTablesClearWhatOnlyTheyHold()
    check(
        compileFixture("weak", {
            "heap",
            "collector",
            "gcweak",
            "arena",
            "values",
            "objecthash",
            "objectweak",
            "marking",
            "weakentries"
        }),
        WEAK
    )
end

function M.ordinaryCallersTransportAllWeakActionWordsToTheLeaf()
    local clif = compileFixture("weakaction")
    local file = assert(io.open(clif, "rb"))
    local text = file:read("*a")
    file:close()
    local body = assert(text:match("function %%probe%b()%s*%-%>%s*i64%s*(%b{})"), text)
    assert(body:match("sig%d+ = %(i64, i64, i64, i64, i64, i64, i64%) %-%> i64 tail"), body)
    assert(body:match("fn%d+ = %%weakLookupAction sig%d+"), body)
    check(clif, {
        {"probe", {0, 0, 0, 2, 0, 1, 2}, 0},
        {"probe", {1, 0, 0, 2, 0, 1, 2}, 1},
        {"probe", {2, 0, 1, 2, 0, 1, 2}, 2},
        {"probe", {2, 0, 2, 2, 0, 1, 2}, 0},
        {"probe", {2, 1, 0, 2, 0, 1, 2}, 0},
        {"probe", {31, 17, 0, 2, 17, 31, 47}, 1},
        {"probe", {47, 17, 1, 2, 17, 31, 47}, 2}
    })
end

function M.ownedWeakIndexesShareLookupReleaseAndBackingPolicy()
    local modules = {
        "heap",
        "arena",
        "values",
        "objecthash",
        "objectweak",
        "marking",
        "weakentries",
        "gcweak",
        "weakindex",
        "backing",
        "objecttable",
        "objectconstruct"
    }
    check(compileFixture("weakindex", modules), {{"ownedWeakIndexes", {8}, 0}, {"ownedWeakIndexes", {6000}, 0},})
end

return M
