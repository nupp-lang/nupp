-- The heap and the collector written standalone in the native profile
-- (`nupp.runtime.vm.heap`, `collector`, `gcweak`), lowered by
-- `nupp.compiler.clif.lower` and run through the glue's just-in-time runner
-- (`nupp-vm native jit`), each case in a process of its own. The fixtures
-- under `tests/fixtures/nativeheap/` build synthetic heaps and answer counts
-- this suite computes independently.
local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local ROOT = HERE .. "/.."
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
local RUNTIME = {"heap", "arena", "values"}

local compiled = {}

local function compileFixture(name, runtimeModules)
    if compiled[name] then
        return compiled[name]
    end
    local paths = {FIXTURES .. "/" .. name .. ".nupp"}
    for _, module in ipairs(runtimeModules or RUNTIME) do
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
    local command = ("%s native jit %s %s %s"):format(quote(glueTool()), quote(clif), quote(name), table.concat(words, " "))
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
local CLASSES = {32, 48, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 384, 448, 512, 640, 768, 1024, 1280,
    1536, 2048, 2560, 3072, 4096, 6144, 8192, 12288, 16384, 24576, 32768}
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
    {"headerLayout", {}, 0}, {"classSum", {}, classSum()},
    {"chunksFor", {10000, 16}, chunksFor(10000, 16)}, {"chunksFor", {5460, 16}, 1}, {"chunksFor", {5461, 16}, 2},
    {"chunksFor", {300, 4000}, chunksFor(300, 4000)},
    {"liveSlots", {10000, 16}, 10000}, {"liveSlots", {500, 1000}, 500}, {"liveSlots", {20, 40000}, 20},
    {"notSlots", {}, 0}, {"reuse", {1000}, 500}, {"reuse", {20000}, 10000 + (chunksFor(20000, 16) - 1) * 1000000}, {"quarantined", {1000}, 1000},
    {"largeObjects", {10, 100000}, 10000},
    -- A table of 80 bytes in a 112-byte slot, a string of 9, one of 50000 on
    -- its own mapping, 32 bytes held outside: two freed leave 41 + 32.
    {"accounting", {}, 1000073},
    {"wordSet", {10000}, 0}, {"wordSet", {3}, 0},
}

function M.theAllocatorHandsOutSlotsBySizeClassAndKnowsItsOwn()
    check(compileFixture("allocator"), ALLOCATOR)
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
    {"listSurvives", {1000, 5000}, 1000}, {"listSurvives", {0, 100}, 0},
    {"rings", {10, 100}, 500}, {"rings", {1, 1000}, 1000},
    -- A hub of 5,000 slots is a large object; children of 40,000 bytes are too.
    {"fanOut", {100, 16}, 51}, {"fanOut", {5000, 16}, 2501}, {"fanOut", {50, 40000}, 26},
    -- The chain, its root, and a leaf under every seventh node.
    {"interleaved", {3000}, 1 + 3000 + 429}, {"interleaved", {500}, 1 + 500 + 72},
    {"stressed", {200}, ternaryAfterCut(200)}, {"stressed", {1}, 1},
    {"initializedBlack", {}, 1},
    {"barrierKeeps", {"false"}, 1}, {"barrierKeeps", {"true"}, 0},
    -- Six roots in the frames, none once the task is done.
    {"frames", {}, 600},
    -- Four held, then the constant and the kept handle; the released index reused.
    {"handlesAndScopes", {}, 40021},
    {"scopedRegistration", {}, 20},
}

function M.theCollectorKeepsWhatIsReachableAndFreesTheRest()
    check(compileFixture("graphs", {"heap", "collector", "arena", "values"}), GRAPHS)
end

-- Pacing alone runs the cycles: a million allocations of 48 bytes keep a
-- bounded ring live, and live bytes stay near the threshold's floor.
function M.allocationDebtPacesTheCycles()
    local clif = compileFixture("graphs", {"heap", "collector", "arena", "values"})
    local answer = tonumber(run(clif, "paced", {1000000, 100}))
    assert(answer and answer > 0, "paced answered " .. tostring(answer))
    assert(answer % 1000 == 65, "the ring and its 64 nodes survive, got " .. answer)
    assert(answer // 1000 >= 10, "allocation debt ran too few cycles: " .. answer // 1000)
end

-- Smoke numbers, read from the report rather than asserted.
function M.allocationAndCollectionThroughputRun()
    local clif = compileFixture("graphs", {"heap", "collector", "arena", "values"})
    for _, case in ipairs({{"allocNanos", {1000000, 1}}, {"collectNanos", {500000}}}) do
        local nanos = tonumber(run(clif, case[1], case[2]))
        assert(nanos and nanos > 0, case[1] .. " answered no time")
    end
    local alloc = compileFixture("allocator")
    assert(tonumber(run(alloc, "allocFreeNanos", {1000000, 16})) ~= nil)
end

return M
