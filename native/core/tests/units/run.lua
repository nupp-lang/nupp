-- Runtime unit fixtures on the owned backend. Builds each unit through the
-- content-addressed code cache, runs every case through the standalone bridge
-- and checks the answers against counts computed here.
--
--   cd native/core/tests/units && NUPP_COMPILER_ROOT=$PWD/../../../.. ../../../../bin/nupp run run.lua [normal|spill|all] [UNIT...]
--
-- NUPP_CORE_BRIDGE selects a prebuilt bridge; otherwise cargo builds one.
local runner = require("nupp.core.unitrunner")

local function cwd()
    local pipe = assert(io.popen("pwd"))
    local path = pipe:read("*l")
    pipe:close()
    return path
end

local HERE = debug.getinfo(1, "S").source:match("^@(/.*)/[^/]*$") or cwd()
local ROOT = assert(os.getenv("NUPP_COMPILER_ROOT"), "set NUPP_COMPILER_ROOT to the checkout root")
local BUILD = ROOT .. "/build/core-units"

local function quote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function shell(command)
    local pipe = assert(io.popen(command .. " 2>&1; echo __exit__:$?"))
    local output = pipe:read("*a")
    pipe:close()
    return tonumber(output:match("__exit__:(%d+)%s*$")), (output:gsub("__exit__:%d+%s*$", ""))
end

local function write(path, bytes)
    local file = assert(io.open(path, "wb"))
    file:write(bytes)
    file:close()
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

local function words(values)
    local out = {}
    for index, value in ipairs(values) do
        local bytes = {}
        for at = 0, 7 do
            bytes[at + 1] = string.char((value >> (at * 8)) & 255)
        end
        out[index] = table.concat(bytes)
    end

    return table.concat(out)
end

local function decode(bytes, index)
    local value = 0
    for at = 8, 1, -1 do
        value = value * 256 + bytes:byte((index - 1) * 8 + at)
    end

    return value
end

local function bridge()
    local given = os.getenv("NUPP_CORE_BRIDGE")
    if given then
        return given
    end
    local target = ROOT .. "/build/core-bridge"
    local status, output = shell(
        (
            "cargo +stable build --manifest-path %s --offline --locked --bin nupp-core --target-dir %s"
        ):format(quote(ROOT .. "/native/core/bridge/Cargo.toml"), quote(target))
    )
    assert(status == 0, "bridge build failed: " .. output)

    return target .. "/debug/nupp-core"
end

-- Each unit: its fixture modules, the dispatched functions with their arity,
-- and cases of {function, arguments, expected result}.
local UNITS = {
    {
        name = "heapunits",
        modules = {"heapunits", "unitentry"},
        entries = {{"heapunits", "chain", 2}, {"heapunits", "garbage", 2}, {"heapunits", "alternate", 2}},
        cases = function()
            local cases = {}
            for _, stress in ipairs({0, 1}) do
                for _, n in ipairs(stress == 0 and {1, 10, 1000} or {1, 7, 64}) do
                    cases[#cases + 1] = {"chain", {n, stress}, n * 1000000}
                    cases[#cases + 1] = {"garbage", {n, stress}, 0}
                    cases[#cases + 1] = {"alternate", {n, stress}, (n + 1) // 2}
                end
            end

            return cases
        end
    },
    {
        name = "gcunits",
        modules = {"gcunits", "unitentry"},
        entries = {
            {"gcunits", "listSurvives", 2},
            {"gcunits", "rings", 2},
            {"gcunits", "fanOut", 2},
            {"gcunits", "barrier", 1},
            {"gcunits", "initializedBlack", 1}
        },
        cases = function()
            -- Counts from tests/nativeheaptest.lua, computed there independently.
            return {
                {"listSurvives", {1000, 5000}, 1000},
                {"listSurvives", {0, 100}, 0},
                {"rings", {10, 100}, 500},
                {"rings", {1, 1000}, 1000},
                {"fanOut", {100, 16}, 51},
                {"fanOut", {5000, 16}, 2501},
                {"fanOut", {50, 40000}, 26},
                {"barrier", {0}, 1},
                {"barrier", {1}, 0},
                {"initializedBlack", {3000}, 1}
            }
        end
    }
}

UNITS[#UNITS + 1] = {
    name = "arithunits",
    modules = {"arithunits", "unitentry"},
    entries = {{"arithunits", "floorDiv", 2}, {"arithunits", "floorMod", 2}},
    cases = function()
        local cases = {}
        for _, a in ipairs({7, -7, 6, -6, 0, 9223372036854775807, -9223372036854775807}) do
            for _, b in ipairs({2, -2, 3, -3, 1, -1}) do
                cases[#cases + 1] = {"floorDiv", {a, b}, a // b}
                cases[#cases + 1] = {"floorMod", {a, b}, a % b}
            end
        end

        return cases
    end
}

-- The CLIF-path fixtures of tests/nativeheaptest.lua, unchanged, with that
-- suite's independently computed expectations.
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

local FIXTURES = ROOT .. "/tests/fixtures/nativeheap"
local SHARED = {
    allocator = {
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
        {"accounting", {}, 1000073},
        {"wordSet", {10000}, 0},
        {"wordSet", {3}, 0}
    },
    graphs = {
        {"listSurvives", {1000, 5000}, 1000},
        {"listSurvives", {0, 100}, 0},
        {"rings", {10, 100}, 500},
        {"rings", {1, 1000}, 1000},
        {"fanOut", {100, 16}, 51},
        {"fanOut", {5000, 16}, 2501},
        {"fanOut", {50, 40000}, 26},
        {"interleaved", {3000}, 1 + 3000 + 429},
        {"interleaved", {500}, 1 + 500 + 72},
        {"stressed", {200}, ternaryAfterCut(200)},
        {"stressed", {1}, 1},
        {"initializedBlack", {}, 1},
        {"barrierKeeps", {0}, 1},
        {"barrierKeeps", {1}, 0},
        {"frames", {}, 600},
        {"handlesAndScopes", {}, 40021},
        {"scopedRegistration", {}, 20},
        {"nonnullRootCandidates", {}, 621},
        {"paced", {100000, 100}, 4065}
    },
    weak = {
        {"weakValues", {}, 22111},
        {"unchangedWeakExtent", {}, 22},
        {"cycleModeSnapshot", {}, 1111},
        {"ephemerons", {}, 1111},
        {"weakBoth", {}, 111},
        {"lookupBarrier", {}, 111},
        {"released", {}, 1111},
        {"interleavedWeak", {3000}, 1000},
        {"interleavedWeak", {301}, 101}
    },
    valuetable = {{"ownedHashChurn", {8}, 0}, {"ownedHashChurn", {10000}, 0}, {"ownedHashRefusalAndPoolReuse", {}, 0}}
}
for _, name in ipairs({"allocator", "graphs", "weak", "valuetable"}) do
    local entries, seen = {}, {}
    for _, case in ipairs(SHARED[name]) do
        if not seen[case[1]] then
            seen[case[1]] = true
            entries[#entries + 1] = {name, case[1], #case[2]}
        end
    end
    UNITS[#UNITS + 1] = {
        name = name,
        modules = {name, "unitentry"},
        paths = {[name] = FIXTURES .. "/" .. name .. ".nupp"},
        include = "tests/fixtures/nativeheap",
        entries = entries,
        cases = function()
            return SHARED[name]
        end
    }
end

UNITS[#UNITS + 1] = {
    name = "tableunits",
    modules = {"tableunits", "unitentry", "nupp.runtime.core.coretables"},
    paths = {["nupp.runtime.core.coretables"] = ROOT .. "/native/core/src/nupp/runtime/core/coretables.nupp"},
    include = "native/core/src",
    entries = {
        {"tableunits", "sequence", 1},
        {"tableunits", "migrate", 1},
        {"tableunits", "removal", 1},
        {"tableunits", "objectKeys", 1},
        {"tableunits", "survives", 1},
        {"tableunits", "traversal", 1}
    },
    cases = function()
        local cases = {}
        for _, n in ipairs({1, 4, 5, 1000, 20000}) do
            cases[#cases + 1] = {"sequence", {n}, n * (n + 1) + n * 1000000000}
            cases[#cases + 1] = {"migrate", {n}, 2 * n * 1000000000 + n * (2 * n + 1)}
            cases[#cases + 1] = {"objectKeys", {n}, n * (n + 1) // 2 + 2 * 1000000000}
            cases[#cases + 1] = {"survives", {n}, n + 1}
        end
        for _, n in ipairs({5, 6, 100}) do
            -- With five keys, clearing 5 and 4 leaves 3 last, so clearing it
            -- trims once more.
            cases[#cases + 1] = {"removal", {n}, (n == 5 and 2 or n - 2) * 1000 + 4}
        end
        for _, n in ipairs({5, 100, 1000}) do
            local half = n * (n + 1) // 2
            local sum = (half - 3) + (half + 1000 * n - 1002) + (half - 3) + (half - 2)
            cases[#cases + 1] = {"traversal", {n}, (2 * n - 2) * 1000000000 + sum * 10 + 1}
        end

        return cases
    end
}

-- Strings as little-endian words, for unit inputs.
local function pack(text, words)
    local result = {}
    for index = 1, words do
        local word = 0
        for at = 1, 8 do
            local byte = text:byte((index - 1) * 8 + at) or 0
            word = word | (byte << ((at - 1) * 8))
        end
        result[index] = word
    end

    return result
end

-- What lstrlib's gmatch_aux yields, measured as the unit does: matches
-- times a million, matched bytes times a hundred, plus captures seen.
local function gmatchExpected(subject, pattern)
    local src, last, count, matched, captured = 1, nil, 0, 0, 0
    while src <= #subject + 1 do
        local found = {subject:find("^" .. pattern, src)}
        if found[1] and found[2] + 1 ~= last then
            count = count + 1
            matched = matched + (found[2] + 1 - src)
            captured = captured + (#found - 2)
            src, last = found[2] + 1, found[2] + 1
        else
            src = src + 1
        end
    end

    return count * 1000000 + matched * 100 + captured
end

local GMATCH = {
    {"item15:item25:item35:", "item%d+5:"},
    {"hello world from lua", "%a+"},
    {"aaa", "a-"},
    {"key=val, k2=v2", "(%w+)=(%w+)"},
    {"  x  ", "%s*"},
    {"f(a(b)c)d", "%b()"},
    {"THE (quick) fox", "%f[%a]%a+"},
    {"abcabc", "()b"},
    {"aXbXc", "[^X]+"},
    {"a.b.c", "%."},
    {"hello", "l?"},
    {"ababab", "(ab)%1"},
    {"x1y22z333", "%d+"},
    {"mississippi", "s+i"}
}

UNITS[#UNITS + 1] = {
    name = "stringunits",
    modules = {"stringunits", "unitentry", "nupp.runtime.core.corestrings", "nupp.runtime.core.corepattern"},
    paths = {
        ["nupp.runtime.core.corestrings"] = ROOT .. "/native/core/src/nupp/runtime/core/corestrings.nupp",
        ["nupp.runtime.core.corepattern"] = ROOT .. "/native/core/src/nupp/runtime/core/corepattern.nupp"
    },
    include = "native/core/src",
    entries = {{"stringunits", "basics", 3}, {"stringunits", "gmatch", 6}},
    cases = function()
        local cases = {{"basics", {pack("abc", 1)[1], pack("ab", 1)[1], pack("c", 1)[1]}, 15}}
        for _, case in ipairs(GMATCH) do
            local s, p = pack(case[1], 3), pack(case[2], 2)
            cases[
                #cases + 1
            ] = {"gmatch", {s[1], s[2], s[3], p[1], p[2], #case[1] | (#case[2] << 8)}, gmatchExpected(case[1], case[2])}
        end

        return cases
    end
}

local only = {}
for index = 2, #arg do
    only[arg[index]] = true
end

os.execute("mkdir -p " .. quote(BUILD))
local modes = (arg[1] and arg[1] ~= "all") and {arg[1]} or {"normal", "spill"}
local tool = bridge()
local failures, passed = 0, 0
for _, unit in ipairs(UNITS) do
    if next(only) and not only[unit.name] then
        goto continue
    end
    local fixtures = {}
    for _, name in ipairs(unit.modules) do
        local path = unit.paths and unit.paths[name] or HERE .. "/" .. name .. ".nupp"
        local include = unit.paths and unit.paths[name] and unit.include or "native/core/tests/units"
        fixtures[#fixtures + 1] = {moduleName = name, path = path, include = include}
    end
    local index = {}
    for at, entry in ipairs(unit.entries) do
        index[entry[2]] = at - 1
    end
    for _, mode in ipairs(modes) do
        local started = os.time()
        -- A function the native profile cannot lower yet is reported as a
        -- failure with its reason and dropped, so one run shows every gap.
        local entries, refused = {}, {}
        for _, entry in ipairs(unit.entries) do
            entries[#entries + 1] = entry
        end
        local ok, result
        while true do
            ok, result = pcall(runner.build, fixtures, entries, mode, ROOT .. "/build/core-unit-cache")
            if ok then
                break
            end
            local message = tostring(result)
            local name = message:match("unit lowering: [%w_]+%.([%w_]+):")
            local dropped = false
            for at, entry in ipairs(entries) do
                if entry[2] == name then
                    table.remove(entries, at)
                    refused[name] = message
                    dropped = true
                    break
                end
            end
            if not dropped then
                error(message, 0)
            end
            failures = failures + 1
            print(("FAIL %s %s %s: not lowered: %s"):format(unit.name, mode, name, message:sub(1, 200)))
        end
        index = {}
        for at, entry in ipairs(entries) do
            index[entry[2]] = at - 1
        end
        local bundle = BUILD .. "/" .. unit.name .. "-" .. mode .. ".bundle"
        write(bundle, result.bundle)
        print(
            (
                "%s %s: built in %ds, %d owners, %d selected"
            ):format(unit.name, mode, os.time() - started, result.owners, result.selected)
        )
        for _, case in ipairs(unit.cases()) do
            if refused[case[1]] or index[case[1]] == nil then
                goto nextcase
            end
            local input, output = bundle .. ".in", bundle .. ".out"
            local values = {index[case[1]]}
            for _, value in ipairs(case[2]) do
                values[#values + 1] = value
            end
            write(input, words(values))
            os.remove(output)
            local status, text = shell(("%s %s %s %s"):format(quote(tool), quote(bundle), quote(input), quote(output)))
            local bytes = read(output)
            local label = ("%s %s %s(%s)"):format(unit.name, mode, case[1], table.concat(case[2], ", "))
            if status ~= 0 or not bytes or #bytes ~= 16 then
                failures = failures + 1
                print("FAIL " .. label .. ": bridge " .. tostring(status) .. " " .. text)
            else
                local value, failure = decode(bytes, 1), decode(bytes, 2)
                if value ~= case[3] or failure ~= 0 then
                    failures = failures + 1
                    print(("FAIL %s: expected %d, got %d (error %d)"):format(label, case[3], value, failure))
                else
                    passed = passed + 1
                end
            end
            ::nextcase::
        end
    end
    ::continue::
end
print(("%d passed, %d failed"):format(passed, failures))
os.exit(failures == 0 and 0 or 1)
