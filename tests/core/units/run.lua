-- Runtime unit fixtures on the owned backend. Builds each unit through the
-- content-addressed code cache, runs every case through the standalone bridge
-- and checks the answers against counts computed here.
--
--   cd tests/core/units && NUPP_COMPILER_ROOT=$PWD/../../.. ../../../bin/nupp run run.lua [normal|spill|all] [UNIT...]
--
-- `run.lua generate` rewrites the generated runtime files from their generators.
--
-- NUPP_CORE_BRIDGE selects a prebuilt bridge; otherwise cargo builds one.
local runner = require("nupp.core.unitrunner")
local sharedcache = require("nupp.core.sharedcache")
local kernelcompiler = require("nupp.core.kernelcompiler")

local function cwd()
    local pipe = assert(io.popen("pwd"))
    local path = pipe:read("*l")
    pipe:close()
    return path
end

local HERE = debug.getinfo(1, "S").source:match("^@(/.*)/[^/]*$") or cwd()
-- Another spelling of the root runs this again under its own (compilerroot).
local ROOT = require("nupp.core.compilerroot").resolve(arg[0], arg)
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
        ):format(quote(ROOT .. "/native/crates/core-bridge/Cargo.toml"), quote(target))
    )
    assert(status == 0, "bridge build failed: " .. output)

    return target .. "/debug/nupp-core"
end

-- Each unit: its fixture modules, the dispatched functions with their arity,
-- and cases of {function, arguments, expected result}.
local UNITS = {
    {
        name = "acquisitionunits",
        modules = {"acquisitionunits", "acquisitionentry", "unitentry"},
        observeLanding = true,
        observerEntry = "nupp.core.acquisitionentry",
        entries = {{"acquisitionunits", "acquire", 3}},
        cases = function()
            local cases = {}
            -- The pool mode (3): the one resource the service scope journals.
            for cancel = 0, 1 do
                cases[#cases + 1] = {"acquire", {0, 3, cancel}, 1}
            end

            return cases
        end
    },
    {
        name = "bufferviewunits",
        modules = {
            "nupp.core.bufferviewunits",
            "unitentry",
            "nupp.runtime.core.corestorage",
            "nupp.runtime.core.corestrings",
            "nupp.runtime.core.coretables"
        },
        paths = {
            ["nupp.core.bufferviewunits"] = ROOT .. "/tests/core/units/nupp/core/bufferviewunits.nupp",
            ["nupp.runtime.core.corestorage"] = ROOT .. "/src/nupp/runtime/core/corestorage.nupp",
            ["nupp.runtime.core.corestrings"] = ROOT .. "/src/nupp/runtime/core/corestrings.nupp",
            ["nupp.runtime.core.coretables"] = ROOT .. "/src/nupp/runtime/core/coretables.nupp"
        },
        entries = {{"nupp.core.bufferviewunits", "lifetime", 1}},
        cases = function()
            return {{"lifetime", {0}, 0}, {"lifetime", {1}, 0}}
        end
    },

    {
        name = "bufferretirementlandingunits",
        modules = {"bufferretirementfaultunits", "longstringfaultunits", "bufferretiremententry", "releasequeueentry"},
        observeLanding = true,
        observerEntry = "nupp.core.bufferretiremententry",
        entries = {{"bufferretirementfaultunits", "failure", 2}},
        cases = function()
            return {{"failure", {0, 0}, 255}, {"failure", {0, 2}, 255}}
        end
    },
    {
        name = "bufferretirementfaultunits",
        modules = {"bufferretirementfaultunits", "longstringfaultunits", "bufferretiremententry", "releasequeueentry"},
        observeLanding = true,
        observerEntry = "nupp.core.bufferretiremententry",
        entries = {{"bufferretirementfaultunits", "failure", 2}},
        cases = function()
            return {}
        end
    },
    {
        name = "bufferretirementunits",
        modules = {"bufferretirementunits", "unitentry"},
        entries = {{"bufferretirementunits", "accounting", 0}, {"bufferretirementunits", "reclamation", 3}},
        cases = function()
            local cases = {{"accounting", {}, 0}}
            for minor = 0, 1 do
                cases[#cases + 1] = {"reclamation", {1, minor, 0}, 0}
                cases[#cases + 1] = {"reclamation", {0, minor, 0}, 0}
                cases[#cases + 1] = {"reclamation", {0, minor, 1}, 0}
            end

            return cases
        end
    },
    {
        name = "bufferstoragefaultunits",
        modules = {"nupp.core.bufferstoragefaultunits", "unitentry", "nupp.runtime.core.storage"},
        paths = {
            ["nupp.core.bufferstoragefaultunits"] = ROOT .. "/tests/core/units/nupp/core/bufferstoragefaultunits.nupp",
            ["nupp.runtime.core.storage"] = ROOT .. "/src/nupp/runtime/core/storage.nupp"
        },
        entries = {
            {"nupp.core.bufferstoragefaultunits", "maprefusal", 0},
            {"nupp.core.bufferstoragefaultunits", "cleanup", 0},
            {"nupp.core.bufferstoragefaultunits", "pending", 0}
        },
        cases = function()
            return {{"pending", {}, 0}}
        end
    },
    {
        name = "bufferstorageunits",
        modules = {"nupp.core.bufferstorageunits", "unitentry", "nupp.runtime.core.storage"},
        paths = {
            ["nupp.core.bufferstorageunits"] = ROOT .. "/tests/core/units/nupp/core/bufferstorageunits.nupp",
            ["nupp.runtime.core.storage"] = ROOT .. "/src/nupp/runtime/core/storage.nupp"
        },
        entries = {
            {"nupp.core.bufferstorageunits", "cow", 0},
            {"nupp.core.bufferstorageunits", "admission", 0},
            {"nupp.core.bufferstorageunits", "shrinkgap", 0},
            {"nupp.core.bufferstorageunits", "growth", 0},
            {"nupp.core.bufferstorageunits", "preparation", 0},
            {"nupp.core.bufferstorageunits", "preparedchanges", 0},
            {"nupp.core.bufferstorageunits", "preparedsnapshot", 0}
        },
        cases = function()
            return {
                {"cow", {}, 0},
                {"admission", {}, 0},
                {"shrinkgap", {}, 0},
                {"growth", {}, 0},
                {"preparation", {}, 0},
                {"preparedchanges", {}, 0},
                {"preparedsnapshot", {}, 0}
            }
        end
    },

    {
        name = "writerunits",
        modules = {"nupp.core.writerunits", "unitentry", "nupp.runtime.core.sharedbacking"},
        paths = {
            ["nupp.core.writerunits"] = ROOT .. "/tests/core/units/nupp/core/writerunits.nupp",
            ["nupp.runtime.core.sharedbacking"] = ROOT .. "/src/nupp/runtime/core/sharedbacking.nupp"
        },
        entries = {{"nupp.core.writerunits", "admission", 0}},
        cases = function()
            return {{"admission", {}, 0}}
        end
    },

    {
        name = "stringviewunits",
        modules = {
            "nupp.core.stringviewunits",
            "unitentry",
            "nupp.runtime.core.corestorage",
            "nupp.runtime.core.corestrings",
            "nupp.runtime.core.coretables"
        },
        paths = {
            ["nupp.core.stringviewunits"] = ROOT .. "/tests/core/units/nupp/core/stringviewunits.nupp",
            ["nupp.runtime.core.corestorage"] = ROOT .. "/src/nupp/runtime/core/corestorage.nupp",
            ["nupp.runtime.core.corestrings"] = ROOT .. "/src/nupp/runtime/core/corestrings.nupp",
            ["nupp.runtime.core.coretables"] = ROOT .. "/src/nupp/runtime/core/coretables.nupp"
        },
        entries = {{"nupp.core.stringviewunits", "lifetime", 2}},

        cases = function()
            local cases = {}
            for _, count in ipairs({0, 1, 40, 41}) do
                for minor = 0, 1 do
                    cases[#cases + 1] = {"lifetime", {count, minor}, 1023}
                end
            end

            return cases
        end
    },

    {
        name = "builderunits",
        modules = {"builderunits", "unitentry"},
        entries = {{"builderunits", "lifetime", 1}},
        cases = function()
            return {{"lifetime", {0}, 1023}, {"lifetime", {1}, 1023}}
        end
    },
    {
        name = "builderlandingunits",
        modules = {"builderunits", "builderentry"},
        observeLanding = true,
        entries = {{"builderunits", "landing", 2}, {"builderunits", "refusal", 1}},
        cases = function()
            return {{"landing", {0, 0}, 127}, {"landing", {0, 1}, 127}, {"landing", {0, 4}, 127}, {"refusal", {0}, 127}}
        end
    },
    {
        name = "heapunits",
        modules = {"heapunits", "unitentry"},
        entries = {
            {"heapunits", "chain", 2},
            {"heapunits", "garbage", 2},
            {"heapunits", "alternate", 2},
            {"heapunits", "representable", 2}
        },
        cases = function()
            local limit = 1 << 48
            -- The highest admitted extent, one that crosses the bound, one
            -- whose end overflows 64 bits, and the whole payload range.
            local cases = {
                {"representable", {limit - 4096, 4096}, 1},
                {"representable", {limit - 4096, 8192}, 0},
                {"representable", {-4096, 8192}, 0},
                {"representable", {0, limit}, 1},
                {"representable", {1, limit}, 0},
                {"representable", {0, limit + 1}, 0}
            }
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
            {"gcunits", "initializedBlack", 1},
            {"gcunits", "segmentRoots", 3},
            {"gcunits", "chunkLayout", 0},
            {"gcunits", "stackChain", 3}
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
                {"initializedBlack", {3000}, 1},
                -- A frame stack's roots end at its cursor.
                {"segmentRoots", {40, 25, 0}, 40},
                {"segmentRoots", {0, 25, 0}, 0},
                {"segmentRoots", {40, 25, 1}, 0},
                -- A stack in chunks: deep, then back to ten frames and a
                -- collection, which gives back the chunks past the one above
                -- the top; not unwound, nothing given back; a frame larger
                -- than a first chunk.
                {"chunkLayout", {}, 1},
                {"stackChain", {2000, 512, 10}, 3000010},
                {"stackChain", {2000, 512, 2000}, 2002000},
                {"stackChain", {60, 40000, 1}, 3000001}
            }
        end
    }
}

UNITS[#UNITS + 1] = {
    name = "stringticketlandingunits",
    modules = {"stringticketfaultunits", "longstringfaultunits", "stringticketentry", "releasequeueentry"},
    observeLanding = true,
    observerEntry = "nupp.core.stringticketentry",
    entries = {{"stringticketfaultunits", "failure", 2}},
    cases = function()
        return {{"failure", {0, 0}, 255}, {"failure", {0, 4}, 255}}
    end
}
UNITS[#UNITS + 1] = {
    name = "stringticketfaultunits",
    modules = {"stringticketfaultunits", "longstringfaultunits", "stringticketentry", "releasequeueentry"},
    observeLanding = true,
    observerEntry = "nupp.core.stringticketentry",
    entries = {{"stringticketfaultunits", "failure", 2}},
    cases = function()
        return {}
    end
}
UNITS[#UNITS + 1] = {
    name = "stringticketunits",
    modules = {"stringticketunits", "unitentry"},
    entries = {
        {"stringticketunits", "ownership", 0},
        {"stringticketunits", "refusals", 0},
        {"stringticketunits", "quota", 0},
        {"stringticketunits", "lifetime", 2}
    },
    cases = function()
        local cases = {{"ownership", {}, 0}, {"refusals", {}, 0}, {"quota", {}, 0}}
        for minor = 0, 1 do
            for stress = 0, 2 do
                cases[#cases + 1] = {"lifetime", {minor, stress}, 0}
            end
        end

        return cases
    end
}
UNITS[#UNITS + 1] = {
    name = "stringtickethandoff",
    modules = {"stringticketunits", "sharedlocalproducer", "unitentry"},
    entries = {{"sharedlocalproducer", "produce", 1}, {"stringticketunits", "handoff", 1}},
    cases = function()
        return {}
    end
}
UNITS[#UNITS + 1] = {
    name = "ticketunits",
    modules = {"ticketunits", "unitentry"},
    entries = {
        {"ticketunits", "basics", 0},
        {"ticketunits", "refusals", 0},
        {"ticketunits", "quota", 1},
        {"ticketunits", "interleaving", 0},
        {"ticketunits", "terminal", 1}
    },
    cases = function()
        return {
            {"basics", {}, 0},
            {"refusals", {}, 0},
            {"quota", {0}, 0},
            {"quota", {1}, 0},
            {"interleaving", {}, 0},
            {"terminal", {0}, 0}
        }
    end
}
UNITS[#UNITS + 1] = {
    name = "ticketcloseunits",
    modules = {"ticketcloseunits", "unitentry"},
    entries = {{"ticketcloseunits", "scopeclose", 2}},
    cases = function()
        local cases = {}
        for _, stress in ipairs({0, 1, 2}) do
            for _, first in ipairs({0, 1}) do
                cases[#cases + 1] = {"scopeclose", {stress, first}, 0}
            end
        end

        return cases
    end
}
UNITS[#UNITS + 1] = {
    name = "ticketproducer",
    modules = {"ticketproducer", "unitentry"},
    entries = {
        {"ticketproducer", "produceblock", 0},
        {"ticketproducer", "dispose", 1},
        {"ticketproducer", "ticket", 1}
    },
    cases = function()
        return {}
    end
}
UNITS[#UNITS + 1] = {
    name = "ticketfaultunits",
    modules = {"ticketunits", "unitentry"},
    entries = {{"ticketunits", "mapfailure", 0}, {"ticketunits", "terminal", 1}},
    cases = function()
        return {}
    end
}

UNITS[#UNITS + 1] = {
    name = "longstringunits",
    modules = {"longstringunits", "unitentry"},
    entries = {
        {"longstringunits", "representation", 1},
        {"longstringunits", "sharing", 1},
        {"longstringunits", "lifetime", 1},
        {"longstringunits", "keys", 1}
    },
    cases = function()
        return {
            {"representation", {31}, 0},
            {"representation", {40}, 0},
            {"representation", {41}, 0},
            {"representation", {97}, 0},
            {"representation", {40000}, 0},
            {"sharing", {41}, 0},
            {"sharing", {4097}, 0},
            {"lifetime", {0}, 0},
            {"lifetime", {1}, 0},
            {"keys", {0}, 0},
            {"keys", {1}, 0}
        }
    end
}

UNITS[#UNITS + 1] = {
    name = "longstringweakunits",
    modules = {"longstringunits", "unitentry"},
    entries = {{"longstringunits", "weakstrings", 2}},
    cases = function()
        return {
            {"weakstrings", {0, 1}, 0},
            {"weakstrings", {0, 2}, 0},
            {"weakstrings", {0, 3}, 0},
            {"weakstrings", {1, 1}, 0},
            {"weakstrings", {1, 2}, 0},
            {"weakstrings", {1, 3}, 0}
        }
    end
}

UNITS[#UNITS + 1] = {
    name = "longstringscopeunits",
    modules = {"longstringunits", "unitentry"},
    entries = {{"longstringunits", "scopeclose", 1}},
    cases = function()
        return {{"scopeclose", {0}, 0}, {"scopeclose", {1}, 0}, {"scopeclose", {2}, 0}}
    end
}

UNITS[#UNITS + 1] = {
    name = "longstringlandingunits",
    modules = {"longstringfaultunits", "longstringentry", "releasequeueentry"},
    observeLanding = true,
    observerEntry = "nupp.core.longstringentry",
    entries = {{"longstringfaultunits", "failure", 2}},
    cases = function()
        return {{"failure", {0, 0}, 135}, {"failure", {0, 1}, 159}, {"failure", {0, 4}, 255}}
    end
}
UNITS[#UNITS + 1] = {
    name = "longstringfaultunits",
    modules = {"longstringfaultunits", "longstringentry", "releasequeueentry"},
    observeLanding = true,
    observerEntry = "nupp.core.longstringentry",
    entries = {{"longstringfaultunits", "failure", 2}},
    -- Only the test bridge injects exact map/unmap failures.
    cases = function()
        return {}
    end
}

UNITS[#UNITS + 1] = {
    name = "releasequeueunits",
    modules = {"releasequeueunits", "unitentry"},
    entries = {{"releasequeueunits", "backlog", 1}},
    cases = function()
        return {{"backlog", {1}, 0}, {"backlog", {17}, 0}, {"backlog", {700}, 0}}
    end
}
UNITS[#UNITS + 1] = {
    name = "releasequeuelandingunits",
    modules = {"releasequeueunits", "releasequeueentry"},
    observeLanding = true,
    observerEntry = "releasequeueentry",
    entries = {{"releasequeueunits", "refusal", 2}},
    cases = function()
        return {{"refusal", {0, 0}, 127}, {"refusal", {0, 1}, 127}}
    end
}

UNITS[#UNITS + 1] = {
    name = "sharedbackingunits",
    modules = {"sharedbackingunits", "unitentry"},
    entries = {{"sharedbackingunits", "basics", 1}, {"sharedbackingunits", "refusals", 0}},
    cases = function()
        return {{"basics", {0}, 127}, {"basics", {1}, 127}, {"basics", {257}, 127}, {"refusals", {}, 1023}}
    end
}

UNITS[#UNITS + 1] = {
    name = "sharedbackingscope",
    modules = {"sharedbackingunits", "unitentry"},
    entries = {{"sharedbackingunits", "scopelifetime", 1}},
    sharedhandoff = true,
    cases = function()
        return {{"scopelifetime", {0}, 4095}}
    end
}

UNITS[#UNITS + 1] = {
    name = "sharedbackingfault",
    modules = {"sharedbackingunits", "unitentry"},
    entries = {{"sharedbackingunits", "terminalfailure", 0}, {"sharedbackingunits", "constructorrefusal", 0}},
    -- Only the cfg(test) bridge seam executes this emitted bundle.
    cases = function()
        return {}
    end
}

UNITS[#UNITS + 1] = {
    name = "atomicunits",
    modules = {"atomicunits", "unitentry"},
    entries = {{"atomicunits", "operations", 1}},
    cases = function()
        return {{"operations", {0}, 63}, {"operations", {1}, 63}, {"operations", {-1}, 63}}
    end
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
        {"explicitRegistration", {}, 20},
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
        paths = {[name] = FIXTURES .. "/nupp/core/" .. name .. ".nupp"},
        include = "tests/fixtures/nativeheap",
        entries = entries,
        cases = function()
            return SHARED[name]
        end
    }
end

UNITS[#UNITS + 1] = {
    name = "tablekeyunits",
    modules = {"tablekeyunits", "unitentry", "nupp.runtime.core.coretables"},
    paths = {["nupp.runtime.core.coretables"] = ROOT .. "/src/nupp/runtime/core/coretables.nupp"},
    entries = {
        {"tablekeyunits", "equality", 1},
        {"tablekeyunits", "growth", 1},
        {"tablekeyunits", "dead", 2},
        {"tablekeyunits", "scans", 1},
        {"tablekeyunits", "weakclears", 2},
        {"tablekeyunits", "removedyoung", 1},
        {"tablekeyunits", "blacknew", 0},
        {"tablekeyunits", "noncore", 0}
    },
    cases = function()
        return {
            {"equality", {0}, 0},
            {"equality", {1}, 0},
            {"equality", {80}, 0},
            {"growth", {8}, 0},
            {"growth", {128}, 0},
            {"dead", {0, 0}, 0},
            {"dead", {1, 0}, 0},
            {"dead", {0, 1}, 0},
            {"dead", {1, 1}, 0},
            {"scans", {0}, 0},
            {"scans", {1}, 0},
            {"weakclears", {0, 1}, 0},
            {"weakclears", {1, 1}, 0},
            {"weakclears", {0, 2}, 0},
            {"weakclears", {1, 2}, 0},
            {"removedyoung", {0}, 0},
            {"removedyoung", {256}, 0},
            {"blacknew", {}, 0},
            {"noncore", {}, 0}
        }
    end
}

UNITS[#UNITS + 1] = {
    name = "tableunits",
    modules = {"tableunits", "unitentry", "nupp.runtime.core.coretables"},
    paths = {["nupp.runtime.core.coretables"] = ROOT .. "/src/nupp/runtime/core/coretables.nupp"},
    entries = {
        {"tableunits", "sequence", 1},
        {"tableunits", "migrate", 1},
        {"tableunits", "removal", 1},
        {"tableunits", "objectKeys", 1},
        {"tableunits", "survives", 1},
        {"tableunits", "traversal", 1},
        {"tableunits", "packedround", 1},
        {"tableunits", "packedswitch", 2},
        {"tableunits", "packedskip", 1},
        {"tableunits", "packedboxes", 2}
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
        -- Packed array parts: every kind round trips; each trigger switches or
        -- keeps it; the collector visits none of a packed part; boxes made
        -- as one switches survive, collecting at every allocation or not.
        for _, n in ipairs({3, 100, 5000}) do
            cases[#cases + 1] = {"packedround", {n}, 11}
            for trigger = 0, 5 do
                local same = trigger == 1 and n - 3 or n - 2
                cases[#cases + 1] = {"packedswitch", {trigger, n}, (trigger <= 3 and 1000 or 0) + same}
            end
            cases[#cases + 1] = {"packedskip", {n}, n + 1}
        end
        for _, n in ipairs({1, 40, 300}) do
            cases[#cases + 1] = {"packedboxes", {n, 0}, 1}
            cases[#cases + 1] = {"packedboxes", {n, 1}, 1}
        end

        return cases
    end
}

-- The objects reachable at the end of genunits.churn: the same xorshift
-- sequence of changes to two-slot nodes under sixteen roots, followed here.
local function churnSurvivors(steps)
    local roots, x = {}, 88172645463325252
    for _ = 1, steps do
        x = x ~ (x << 13)
        x = x ~ (x >> 7)
        x = x ~ (x << 17)
        local op, r, q, slot = x & 7, (x >> 8) & 15, (x >> 16) & 15, (x >> 24) & 1
        if op < 3 then
            roots[r] = {}
            roots[r][slot] = roots[q]
        elseif op == 3 then
            if roots[r] then
                roots[r][slot] = {}
            end
        elseif op == 4 then
            if roots[r] then
                roots[r][slot] = roots[q]
            end
        elseif op == 5 then
            roots[r] = nil
        elseif op == 6 then
            if roots[r] then
                roots[r] = roots[r][slot]
            end
        end
    end
    local seen, count, stack = {}, 0, {}
    for i = 0, 15 do
        stack[#stack + 1] = roots[i]
    end
    while #stack > 0 do
        local node = table.remove(stack)
        if not seen[node] then
            seen[node], count = true, count + 1
            stack[#stack + 1] = node[0]
            stack[#stack + 1] = node[1]
        end
    end

    return count
end

-- Generations (Decision 20): promotion, the barrier, cards, frozen and weak
-- tables, cycles across generations, and minor collections interleaved with
-- full ones under each verification mode.
UNITS[#UNITS + 1] = {
    name = "genunits",
    modules = {"genunits", "unitentry", "nupp.runtime.core.coretables"},
    paths = {["nupp.runtime.core.coretables"] = ROOT .. "/src/nupp/runtime/core/coretables.nupp"},
    entries = {
        {"genunits", "promotion", 1},
        {"genunits", "barrier", 1},
        {"genunits", "cards", 1},
        {"genunits", "frozen", 1},
        {"genunits", "weakgen", 0},
        {"genunits", "cycles", 1},
        {"genunits", "churn", 2}
    },
    cases = function()
        local cases = {}
        for _, n in ipairs({0, 1, 500}) do
            cases[#cases + 1] = {"promotion", {n}, n * 1001000}
        end
        cases[#cases + 1] = {"barrier", {0}, 111}
        cases[#cases + 1] = {"barrier", {1}, 0}
        for _, n in ipairs({300, 1000, 5000}) do
            -- Young nodes at every fiftieth array slot, four hash pairs and one
            -- past the grown array part; the array cards the first dirtied.
            local dirty, cards = {}, 0
            for i = 50, n, 50 do
                local card = (i - 1) // 64
                if not dirty[card] then
                    dirty[card], cards = true, cards + 1
                end
            end
            cases[#cases + 1] = {"cards", {n}, n // 50 + 9 + cards * 1000}
        end
        for _, n in ipairs({1, 100}) do
            cases[#cases + 1] = {"frozen", {n}, n + n * 1000 + (n + 1) * 1000000}
        end
        cases[#cases + 1] = {"weakgen", {}, 2047}
        for _, n in ipairs({1, 50}) do
            cases[#cases + 1] = {"cycles", {n}, 3 * n + 3 * n * 1000}
        end
        for _, steps in ipairs({200, 3000}) do
            local survivors = churnSurvivors(steps)
            for mode = 0, 2 do
                cases[#cases + 1] = {"churn", {steps, mode}, survivors}
            end
        end

        return cases
    end
}

-- Weak tables and finalizers (gcweak, gcfinal): ephemeron chains,
-- resurrection in full and minor collections, a carded table taking a weak
-- mode, a frozen weak table, and storage views as weak values.
UNITS[#UNITS + 1] = {
    name = "weakunits",
    modules = {"weakunits", "unitentry", "nupp.runtime.core.coretables"},
    paths = {["nupp.runtime.core.coretables"] = ROOT .. "/src/nupp/runtime/core/coretables.nupp"},
    entries = {
        {"weakunits", "ephemerons", 1},
        {"weakunits", "resurrection", 1},
        {"weakunits", "cardsweak", 1},
        {"weakunits", "frozenweak", 0},
        {"weakunits", "views", 1},
        {"weakunits", "storageowners", 1},
        {"weakunits", "packedowners", 1}
    },
    cases = function()
        return {
            {"ephemerons", {1}, 15},
            {"ephemerons", {50}, 15},
            {"resurrection", {0}, 127},
            {"resurrection", {1}, 127},
            {"cardsweak", {1000}, 63},
            {"frozenweak", {}, 31},
            {"views", {0}, 31},
            {"views", {1}, 31},
            {"views", {2}, 31},
            {"views", {3}, 31},
            {"storageowners", {0}, 255},
            {"storageowners", {1}, 255},
            {"packedowners", {0}, 127},
            {"packedowners", {1}, 127},
            {"packedowners", {2}, 127},
            {"packedowners", {3}, 127}
        }
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

-- Error texts the core reports, and whether each names the command line
-- already: what nupp.tools.cli.error's `message` decides, checked here with
-- its own patterns.
local NAMED = {
    "nupp: no benchmark named x",
    "nupp:",
    "nupp",
    "boom",
    "a.lua:2: boom",
    "a.lua:12: nupp: failed",
    "a.lua:: nupp: x",
    "a.lua:2:nupp: x",
    "x\na.lua:2: nupp: y",
    "a:b:3: nupp: z",
    " nupp: x",
    ""
}

local function namedExpected(text)
    return (text:find("^nupp:") or text:find("^[^\n]-:%d+: nupp:")) and 1 or 0
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
    name = "storagelifetimeunits",
    modules = {"storagelifetimeunits", "unitentry", "nupp.runtime.core.corestorage", "nupp.runtime.core.coretables"},
    paths = {
        ["nupp.runtime.core.corestorage"] = ROOT .. "/src/nupp/runtime/core/corestorage.nupp",
        ["nupp.runtime.core.coretables"] = ROOT .. "/src/nupp/runtime/core/coretables.nupp"
    },
    entries = {
        {"storagelifetimeunits", "reclamation", 2},
        {"storagelifetimeunits", "relocation", 1},
        {"storagelifetimeunits", "typed", 1}
    },
    cases = function()
        local cases = {
            {"reclamation", {0, 0}, 255},
            {"reclamation", {0, 1}, 255},
            {"reclamation", {1, 0}, 255},
            {"reclamation", {1, 1}, 255},
            {"relocation", {0}, 1023},
            {"relocation", {1}, 1023}
        }
        for kind = 1, 10 do
            cases[#cases + 1] = {"typed", {kind}, 63}
        end

        return cases
    end
}

UNITS[#UNITS + 1] = {
    name = "storageunits",
    modules = {"storageunits", "unitentry", "nupp.runtime.core.storage"},
    paths = {["nupp.runtime.core.storage"] = ROOT .. "/src/nupp/runtime/core/storage.nupp"},
    entries = {
        {"storageunits", "basics", 1},
        {"storageunits", "rollback", 0},
        {"storageunits", "overlap", 1},
        {"storageunits", "aliased", 2}
    },
    cases = function()
        return {
            {"basics", {1}, 4095},
            {"basics", {7}, 4095},
            {"basics", {12}, 4095},
            {"rollback", {}, 2047},
            {"overlap", {0}, 3},
            {"overlap", {1}, 3},
            {"aliased", {0, 0}, 31},
            {"aliased", {0, 1}, 31},
            {"aliased", {1, 0}, 31},
            {"aliased", {1, 1}, 31}
        }
    end
}

UNITS[#UNITS + 1] = {
    name = "scalarunits",
    modules = {"scalarunits", "unitentry"},
    entries = {{"scalarunits", "boundaries", 1}},
    cases = function()
        local cases = {}
        for which = 1, 45 do
            cases[#cases + 1] = {"boundaries", {which}, 1}
        end

        return cases
    end
}

UNITS[#UNITS + 1] = {
    name = "systemunits",
    modules = {"systemunits", "unitentry", "nupp.runtime.core.coretables"},
    paths = {["nupp.runtime.core.coretables"] = ROOT .. "/src/nupp/runtime/core/coretables.nupp"},
    entries = {{"systemunits", "facts", 2}, {"systemunits", "integers", 0}},
    cases = function()
        local cases = {{"integers", {}, 15}}
        for _, field in ipairs({0, 1, 2}) do
            for _, minor in ipairs({0, 1}) do
                cases[#cases + 1] = {"facts", {field, minor}, 127}
            end
        end

        return cases
    end
}

UNITS[#UNITS + 1] = {
    name = "entropyunits",
    modules = {"entropyunits", "unitentry", "nupp.runtime.core.coretables"},
    paths = {["nupp.runtime.core.coretables"] = ROOT .. "/src/nupp/runtime/core/coretables.nupp"},
    entries = {{"entropyunits", "roundtrip", 2}},
    cases = function()
        local cases = {}
        for _, count in ipairs({0, 1, 40, 41, 4097, 1048576}) do
            for _, minor in ipairs({0, 1}) do
                cases[#cases + 1] = {"roundtrip", {count, minor}, 127}
            end
        end

        return cases
    end
}

UNITS[#UNITS + 1] = {
    name = "stringunits",
    modules = {
        "stringunits",
        "unitentry",
        "nupp.runtime.core.corestrings",
        "nupp.runtime.core.corepattern",
        "nupp.runtime.core.reportprefix"
    },
    paths = {
        ["nupp.runtime.core.corestrings"] = ROOT .. "/src/nupp/runtime/core/corestrings.nupp",
        ["nupp.runtime.core.corepattern"] = ROOT .. "/src/nupp/runtime/core/corepattern.nupp",
        ["nupp.runtime.core.reportprefix"] = ROOT .. "/src/nupp/runtime/core/reportprefix.nupp"
    },
    entries = {{"stringunits", "basics", 3}, {"stringunits", "gmatch", 6}, {"stringunits", "named", 4}},
    cases = function()
        local cases = {{"basics", {pack("abc", 1)[1], pack("ab", 1)[1], pack("c", 1)[1]}, 15}}
        for _, case in ipairs(GMATCH) do
            local s, p = pack(case[1], 3), pack(case[2], 2)
            cases[
                #cases + 1
            ] = {"gmatch", {s[1], s[2], s[3], p[1], p[2], #case[1] | (#case[2] << 8)}, gmatchExpected(case[1], case[2])}
        end
        for _, text in ipairs(NAMED) do
            local w = pack(text, 3)
            cases[#cases + 1] = {"named", {w[1], w[2], w[3], #text}, namedExpected(text)}
        end

        return cases
    end
}

-- The workloads whose heap traces the replay checks, recorded once from the
-- Rust heap by the VM that runs them, as tests/nativeheaptest.lua records them.
local WORKLOADS = {"fib", "loops", "tables", "strings", "records", "closures"}

local function vmPackage()
    local runtime = os.getenv("NUPP_VM_BINARY") or ""
    local image = os.getenv("NUPP_VM_CLI_IMAGE") or ""
    if runtime ~= "" or image ~= "" then
        assert(runtime ~= "" and image ~= "", "heap replay requires both NUPP_VM_BINARY and NUPP_VM_CLI_IMAGE")
        return runtime, image
    end
    local generation = read(ROOT .. "/.nupp/vm-cli/current"):gsub("%s+$", "")
    local package = ROOT .. "/.nupp/vm-cli/" .. generation

    return package .. "/runtime", package .. "/compiler.image"
end

-- The trace of workload `name`, recorded the first time it is asked for.
function workloadTrace(name)
    local traces = BUILD .. "/traces"
    local trace = traces .. "/" .. name .. ".trace"
    if read(trace) then
        return trace
    end
    local project = BUILD .. "/workloads"
    os.execute("mkdir -p " .. quote(project .. "/src/wl") .. " " .. quote(traces))
    write(project .. "/nupp.lua", 'return {name = "wl", include = {"src"}}\n')
    for _, workload in ipairs(WORKLOADS) do
        write(
            project .. "/src/wl/" .. workload .. ".nupp",
            assert(read(FIXTURES .. "/workloads/" .. workload .. ".nupp"))
        )
    end
    local runtime, compiler = vmPackage()
    local image = project .. "/" .. name .. ".image"
    local status, output = shell(
        (
            "%s run %s nupp.tools.vm.project emit %s wl.%s '' --output %s"
        ):format(quote(runtime), quote(compiler), quote(project), name, quote(image))
    )
    assert(status == 0, "emitting " .. name .. ": " .. output)
    local recorded = BUILD .. "/trace-" .. name
    os.execute("rm -rf " .. quote(recorded) .. " && mkdir -p " .. quote(recorded))
    status, output = shell(
        ("NO_AOT=1 NUPP_HEAP_TRACE=%s %s run %s wl.%s main"):format(quote(recorded), quote(runtime), quote(image), name)
    )
    assert(status == 0, "running " .. name .. ": " .. output)
    local _, listing = shell("ls " .. quote(recorded))
    local file = assert(listing:match("([^\n]+)"), "no trace recorded for " .. name)
    os.execute("mv " .. quote(recorded .. "/" .. file) .. " " .. quote(trace))

    return trace
end

-- The differential replay (tests/nativeheaptest.lua's): a trace recorded from
-- the Rust heap, on standard input, replayed into the core's collector. A case
-- names its trace as a fourth field; the answer is the disagreements, zero.
UNITS[#UNITS + 1] = {
    name = "catalogunits",
    modules = {"catalogunits", "unitentry"},
    entries = {{"catalogunits", "calls", 2}},
    cases = function()
        -- Past the 256 owners the raw catalog once admitted, up to its bound.
        local cases = {}
        for _, count in ipairs({300, 65536}) do
            cases[#cases + 1] = {"calls", {count, 0}, 1}
            cases[#cases + 1] = {"calls", {count, 1}, 0}
            cases[#cases + 1] = {"calls", {count, 2}, 1}
            cases[#cases + 1] = {"calls", {count, 3}, 0}
        end

        return cases
    end
}

UNITS[#UNITS + 1] = {
    name = "replay",
    modules = {"replay", "unitentry"},
    paths = {replay = FIXTURES .. "/nupp/core/replay.nupp"},
    include = "tests/fixtures/nativeheap",
    entries = {{"replay", "replayTrace", 0}},
    cases = function()
        -- No input is the magic word missing.
        local cases = {{"replayTrace", {}, -2, "/dev/null"}}
        for _, name in ipairs(WORKLOADS) do
            cases[#cases + 1] = {"replayTrace", {}, 0, workloadTrace(name)}
        end

        return cases
    end
}

local only = {}
for index = 2, #arg do
    only[arg[index]] = true
end

-- The raw loader's policies are generated from the graph schema and its
-- bounds, and the core library's call and text ids from their one tables:
-- each committed file stays exactly what its generator writes.
-- Each generator by a literal require: the core reaches no module by a
-- computed name (toollayeringtest).
local GENERATED = {
    {require("nupp.core.rawwiregen"), "rawwire", "nupp.core.rawwiregen"},
    {require("nupp.core.rawshapegen"), "rawroles", "nupp.core.rawshapegen"},
    {require("nupp.core.rawcataloggen"), "rawcatalogpolicy", "nupp.core.rawcataloggen"},
    {require("nupp.core.rawbudgetgen"), "rawbudgetpolicy", "nupp.core.rawbudgetgen"},
    {require("nupp.core.rawsemanticgen"), "rawsemanticpolicy", "nupp.core.rawsemanticgen"},
    {require("nupp.core.librarycallsgen"), "librarycalls", "nupp.core.librarycallsgen"},
    {require("nupp.core.storagelibrarygen"), "storagelibrary", "nupp.core.storagelibrarygen"},
    {require("nupp.core.loadlibrarygen"), "loadlibrary", "nupp.core.loadlibrarygen"},
    {require("nupp.core.debuglibrarygen"), "debuglibrary", "nupp.core.debuglibrarygen"},
    {require("nupp.core.scalarkindsgen"), "scalarkinds", "nupp.core.scalarkindsgen"},
    {require("nupp.core.librarylayoutsgen"), "librarylayouts", "nupp.core.librarylayoutsgen"},
    {require("nupp.core.librarytextsgen"), "librarytexts", "nupp.core.librarytextsgen"},
    -- A runtime module under src/ is named by its path from the root.
    {require("nupp.core.corecallvaluesgen"), "src/nupp/runtime/corecallvalues", "nupp.core.corecallvaluesgen"}
}

-- Where generated file `name` lives: a runtime core module by its name, else
-- the path from the root it names.
local function generatedPath(name)
    if name:find("/", 1, true) then
        return ROOT .. "/" .. name .. ".nupp"
    end

    return ROOT .. "/src/nupp/runtime/core/" .. name .. ".nupp"
end

-- `run.lua generate` writes every generated file and stops.
if arg[1] == "generate" then
    for _, pair in ipairs(GENERATED) do
        write(generatedPath(pair[2]), pair[1].source())
        print("wrote " .. pair[2])
    end
    os.exit(0)
end

os.execute("mkdir -p " .. quote(BUILD))
local modes = (arg[1] and arg[1] ~= "all") and {arg[1]} or {"normal", "spill"}
local tool = bridge()
local failures, passed = 0, 0
for _, pair in ipairs(GENERATED) do
    local path = generatedPath(pair[2])
    if read(path) == pair[1].source() then
        passed = passed + 1
    else
        failures = failures + 1
        print("FAIL generated " .. pair[2] .. ": differs from " .. pair[3] .. ".source()")
    end
end
-- No two library calls share an id, nor two texts, and every text a call
-- names is one; the tables assert as much as they load, and this says so
-- by name when one does not.
do
    local corelibrary = require("nupp.compiler.vm.corelibrary")
    local coretexts = require("nupp.compiler.vm.coretexts")

    local function unique(space, rows)
        local ids, names, problem = {}, {}, nil
        for _, row in ipairs(rows) do
            if ids[row.id] then
                problem = ("%s and %s share %s id %d"):format(ids[row.id], row.name, space, row.id)
            elseif names[row.name] then
                problem = ("%s names two %s ids"):format(row.name, space)
            end
            ids[row.id], names[row.name] = row.name, true
        end

        return problem, names
    end

    local calls = {}
    for _, subject in ipairs(corelibrary.subjects()) do
        for _, call in ipairs(subject.calls) do
            calls[#calls + 1] = call
        end
    end
    local callProblem = unique("library call", calls)
    local textProblem, texts = unique("text", coretexts.all())
    for _, call in ipairs(calls) do
        if call.text and not texts[call.text] then
            textProblem = call.name .. " names no text " .. call.text
        end
    end
    for _, problem in ipairs({callProblem or false, textProblem or false}) do
        if problem then
            failures = failures + 1
            print("FAIL library ids: " .. problem)
        else
            passed = passed + 1
        end
    end
end
-- The kernels' compiler part (`nupp.core.kernelcompiler`) follows every input
-- the selection reaches and leaves out only the guest program's own lowering:
-- an edit to an input changes it, an edit to that lowering does not.
do
    local inputs, excluded = kernelcompiler.inputs(ROOT), kernelcompiler.excluded(ROOT)
    local covered = {}
    for _, path in ipairs(inputs) do
        covered[path] = true
    end
    local problems = {}
    for _, path in ipairs({
        "src/nupp/compiler/vm/lower.nupp",
        "src/nupp/compiler/vm/nativegraph.nupp",
        "src/nupp/compiler/vm/functiongraph.nupp",
        "src/nupp/compiler/check/init.nupp",
        "spike/native-lowering/src/s0/select.nupp",
        "src/nupp/runtime/vm/intrinsics.d.nupp"
    }) do
        if not covered[path] then
            problems[#problems + 1] = path .. " is no input"
        end
    end
    for _, path in ipairs({
        "src/nupp/compiler/vm/taggedprofile.nupp",
        "src/nupp/compiler/vm/coregraphexecutable.nupp"
    }) do
        if covered[path] then
            problems[#problems + 1] = path .. " is an input"
        end
    end

    local function edited(target)
        return function(path)
            local bytes = read(path) or ""
            return path == ROOT .. "/" .. target and bytes .. "\n-- edited\n" or bytes
        end
    end

    local base = kernelcompiler.digestOf(ROOT, inputs)
    if kernelcompiler.digestOf(ROOT, inputs, edited("src/nupp/compiler/check/init.nupp")) == base then
        problems[#problems + 1] = "an edited input left the digest as it was"
    end
    if kernelcompiler.digestOf(ROOT, inputs, edited(excluded[1])) ~= base then
        problems[#problems + 1] = "an edited guest lowering module changed the digest"
    end
    for _, problem in ipairs(problems) do
        failures = failures + 1
        print("FAIL kernel inputs: " .. problem)
    end
    if #problems == 0 then
        passed = passed + 1
    end
end
-- What the unit builds load beyond what is loaded already: a kernel
-- selection must never load the lowering its key leaves out.
local loadedBefore = {}
for name in pairs(package.loaded) do
    loadedBefore[name] = true
end
for _, unit in ipairs(UNITS) do
    if next(only) and not only[unit.name] then
        goto continue
    end
    local fixtures, fixtureNames = {}, {}
    for _, name in ipairs(unit.modules) do
        local named = unit.paths and unit.paths[name]
        local path = named or HERE .. "/nupp/core/" .. name .. ".nupp"
        -- A module named by its path brings only the unit's own extra root, if
        -- any: the core it reaches is under src, which every unit includes.
        local include = "tests/core/units"
        if named then
            include = unit.include
        end
        local moduleName = name:find(".", 1, true) and name or "nupp.core." .. name
        fixtureNames[name] = moduleName
        fixtures[#fixtures + 1] = {moduleName = moduleName, path = path, include = include}
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
            entries[#entries + 1] = {fixtureNames[entry[1]] or entry[1], entry[2], entry[3]}
        end
        local ok, result
        while true do
            ok, result = pcall(
                runner.build,
                fixtures,
                entries,
                mode,
                sharedcache.directory("kernels"),
                unit.observeLanding,
                unit.sharedhandoff,
                unit.observerEntry and (fixtureNames[unit.observerEntry] or unit.observerEntry)
            )
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
            local stdin = case[4] and " < " .. quote(case[4]) or ""
            local status, text = shell(
                ("%s %s %s %s%s"):format(quote(tool), quote(bundle), quote(input), quote(output), stdin)
            )
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
do
    local outside = {}
    for _, path in ipairs(kernelcompiler.excluded(ROOT)) do
        outside[(path:gsub("^src/", ""):gsub("%.nupp$", ""):gsub("/", "."))] = path
    end
    for name in pairs(package.loaded) do
        if not loadedBefore[name] and outside[name] then
            failures = failures + 1
            print("FAIL kernel inputs: a unit build loaded " .. outside[name] .. ", which the kernel key leaves out")
        end
    end
end
print(("%d passed, %d failed"):format(passed, failures))
os.exit(failures == 0 and 0 or 1)
