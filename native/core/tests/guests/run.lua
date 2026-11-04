-- Checked-source guest programs on the standalone core: every case is built
-- in one process through the shared guest unit, run through the bridge and
-- the ABI/scratch guard, and checked against independent expectations.
--
--   cd native/core/tests/guests && NUPP_COMPILER_ROOT=$PWD/../../../.. ../../../../bin/nupp run run.lua [CASE...]
--
-- NUPP_LUA_REFERENCE names a reference Lua 5.5 interpreter; when set, the
-- numeric expectations are recomputed with it. Bundles and outputs go under
-- build/core-guests.
local producer = require("nupp.core.guestprogramproducer")
local guestbuild = require("nupp.core.guestbuild")
local json = require("serde.json")

local function cwd()
    local pipe = assert(io.popen("pwd"))
    local path = pipe:read("*l")
    pipe:close()
    return path
end

local HERE = debug.getinfo(1, "S").source:match("^@(/.*)/[^/]*$") or cwd()
local ROOT = assert(os.getenv("NUPP_COMPILER_ROOT"), "set NUPP_COMPILER_ROOT to the checkout root")
local OUT = ROOT .. "/build/core-guests"
local TESTS = ROOT .. "/native/core/tests"
-- The guest runtime is built through the service catalog and the unit code
-- cache; NUPP_GUEST_BUILD=frozen selects the frozen final-frame build instead.
local UNITS = os.getenv("NUPP_GUEST_BUILD") ~= "frozen"
-- Guest scratch: unit-built guests call into the collector, whose call chain
-- needs more spill room than the frozen build's 128 KiB.
local SCRATCH = UNITS and 1048576 or 131072
-- NUPP_GUEST_QUICK=1 checks selections and results only: no ABI guard,
-- refusal or audit runs, which each run the program again.
local QUICK = os.getenv("NUPP_GUEST_QUICK") == "1"
-- Workloads that run for seconds: their result is checked in both modes,
-- but the ABI guard, which runs the program again, is left to the others.
local HEAVY = {workloadLoops = true}
-- Results at BENCH_SCALE=2, run in normal mode only. Loops stays out: its 30
-- million iterations take ten seconds at either scale.
local SCALED = {
    workloadFib = 0x7FFF000000148ADD,
    workloadTables = 0x7FFF00001D161453,
    workloadStrings = 0x7FFF00000052E970,
    workloadRecords = 0x7FFF000000030D3D,
    workloadClosures = 0x7FFF0000000F414A
}
-- The environment every bridge and guard run sees, which environmentRead
-- reads back; the long value needs a second copy past the first 256 bytes.
local GUEST_ENV = "NUPP_GUEST_PROBE=core-environment NUPP_GUEST_SCALE=3 NUPP_GUEST_LONG=" .. string.rep("x", 300) .. " "

local CASES = {
    {"boolean", 0x7FFB000000000000},
    {"nilValue", 0x7FF9000000000000},
    {"live", 0x7FFB000000000000},
    {"fresh", 0x7FFB000000000000},
    {"nested", 0x7FFB000000000000},
    {"branchTrue", 0x7FFB000000000000},
    {"branchFalse", 0x7FFA000000000000},
    {"branchElseif", 0x7FFB000000000000},
    {"branchLive", 0x7FFB000000000000},
    {"modulePair", 0x7FFA000000000000},
    {"moduleTriple", 0x7FFB000000000000},
    {"numberAdd", 0x4017000000000000},
    {"numberNegativeZero", 0x8000000000000000},
    {"numberNaN", 0x7FF8000000000000},
    {"numberBranch", 0x7FFB000000000000},
    {"numberLoop", 0x4008000000000000},
    {"numberLoopZero", 0x0000000000000000},
    {"numericFor", 0x7FFF0059B114AFBA},
    {"numericFloat", 0x4125486B80000000},
    {"numericModZero", false},
    {"numericOverflow", false},
    {"numericControl", 0x7FFF00083C5DD2BB},
    {"workloadLoops", 0x7FFF0000000B9CCE},
    {"callsNumeric", 0x7FFF00000005DFF1},
    {"workloadFib", 0x7FFF0000000CB228},
    {"tablesBasic", 0x7FFF5B0A5989C37B},
    {"workloadClosures", 0x7FFF00000007A0B4},
    {"workloadTables", 0x7FFF00001D148D33},
    {"workloadRecords", 0x7FFF0000000C3500},
    {"workloadStrings", 0x7FFF000000509842},
    {"stringsBasic", 0x7FFF0000000004B1},
    {"integersWide", 0x7FFF00064B7743CB},
    {"numbersText", 0x7FFF000004A6983A},
    {"environmentRead", 0x7FFF000011E63D2B},
    {"numbersFloat", 0x7FFF0001D94A7C23},
    {"callsResults", 0x7FFF000000259D74},
    {"tablesFloatKeys", 0x7FFF0000065C2564},
    {"stringsLibrary", 0x7FFF0000547F9CA7},
    {"callsGeneric", 0x7FFF00000C2F4BF7},
    {"callsVariadic", 0x7FFF01026AA11247},
    {"callsSpread", 0x7FFF001B69EC548D},
    {"recordsMethods", 0x7FFF000AFDC52FB5},
    {"callsProtected", 0x7FFF00001E76EFC7},
    {"recordsInline", 0x7FFF0000000A1A00},
    {"errorsPositions", 0x7FFF00000001B207},
    {"tablesMeta", 0x7FFF006F110BB14D},
    {"errorsTexts", 0x7FFF00000000007F},
    {"callsXpcall", 0x7FFF000000005277},
    {"tablesMetaops", 0x7FFF000000A98AC7},
    {"tablesLibrary", 0x7FFF000000CC9B63},
    {"stringsFormat", 0x7FFF000ACA5444AA},
    {"recordsConstructors", 0x7FFF000000042A91},
    {"numbersMath", 0x7FFF00000010F44A},
    {"recordsAffine", 0x7FFF000000007D88},
    {"recordsAffineErrors", 0x7FFF00000632F03D},
    {"recordsaffineraise", 0x7FFF000000008182},
    {"recordsdynamic", 0x7FFF0000002F2854},
    {"tablesSort", 0x7FFF000000560C7F},
    {"stringsGsubFunction", 0x7FFF00000000003F},
    {"stringsQuoted", 0x7FFF00000000003F},
    {"outputPrint", 0x7FFF000000000006},
    {"numbersPower", 0x7FFF00018C459471},
    {"libraryRanges", 0x7FFF00000000001F},
    {"numbersRandom", 0x7FFF00003A3E66EE},
    {"errorsLibrary", 0x7FFF000000000FFF},
    {"callsAny", 0x7FFF00000001B05A},
    {"recordsMetamethods", 0x7FFF0000043EE3C6},
    {"callsPacks", 0x7FFF0000002F5D00},
    {"callsOpen", 0x7FFF000000000461},
    {"callsExpand", 0x7FFF00000E655693},
    {"errorsMethods", 0x7FFF00000000000F},
    {"recordsAffineReturns", 0x7FFF001A27644F86},
    {"threadsbasic", 0x7FFF000000000FFF},
    {"threadscalls", 0x7FFF00000000003F},
    {"threadsclose", 0x7FFF00000000007F},
    {"threadsiterate", 0x7FFF00000000001F},
    {"threadsmeta", 0x7FFF000000105C53},
    {"outputwrite", 0x7FFF000000000001},
    {"libraryspread", 0x7FFF000000000C8D},
    {"tableslibrarymeta", 0x7FFF000000000007},
    {"tableslibrarycalls", 0x7FFF0000000003FF},
    {"tablesmetaarity", 0x7FFF0000000004BE},
    {"moduleslazy", 0x7FFF000000000520},
    {"modulesnamed", 0x7FFF0000000004D8},
    {"modulespattern", 0x7FFF0000000000E6},
    {"modulesrecords", 0x7FFF000000002BD9},
    {"modulescycle", 0x7FFF000000000017},
    {"modulesdynamic", 0x7FFF000000002B20},
    {"libraryvalues", 0x7FFF00000000003F},
    {"textbuffer", 0x7FFF0000000007FF},
    {"stringbuffer", 0x7FFF000000000003},
    {"librarybasics", 0x7FFF00000000007F},
    {"cleanupfunctions", 0x7FFF000000000003},
    {"storagebasics", 0x7FFF000000001FFF},
    {"storageprovider", 0x7FFF00000000003F},
    {"modulesqualified", 0x7FFF0000000000E6},
    {"callsoverflow", 0x7FFF000000000003}
}
-- What the cases that print write to the host's output, as Lua 5.5 writes it.
local OUTPUT = {
    textbuffer = "shown\n",
    outputPrint = "hello\t42\t1.5\ttrue\tnil\tfalse\n\nxxx\t3\t-0.0\t1e+100\t9007199254740992.0\n"
        .. "line\t1\nline\t2\nline\t3\n",
    callsExpand = "1\t2\nx\t1\t2\n",
    outputwrite = "hello 42 1.5\n3.0 -0.0 9.2233720368547758e+18\nab\nx7\np\n",
    libraryspread = "1\t2\t3\n3\t3\n97\t98\t99\n2\t3\ntrue\t1\t2\n",
    moduleslazy = "main start\nshapes loading\ncounter loading\nmain required\n"
}
-- Heap-using cases that also run with a whole collection at every
-- allocation. records and strings allocate per iteration, which makes their
-- full-scale workloads quadratic there; stringsBasic and tablesBasic stand in.
local STRESS = {
    callsNumeric = true,
    workloadFib = true,
    tablesBasic = true,
    workloadClosures = true,
    workloadTables = true,
    stringsBasic = true,
    integersWide = true,
    threadsbasic = true,
    threadscalls = true,
    threadsclose = true,
    tableslibrarycalls = true,
    tablesSort = true,
    stringsLibrary = true,
    stringsGsubFunction = true,
    libraryspread = true,
    threadsiterate = true,
    threadsmeta = true,
    textbuffer = true,
    stringbuffer = true,
    librarybasics = true,
    storagebasics = true,
    storageprovider = true,
    cleanupfunctions = true
}
-- These refuse at run time and must publish nothing: Lua 5.5 raises for the
-- first; the second's result is a boxed integer, which cannot be published.
local STATUS = {numericModZero = 6, numericOverflow = 5}
local NUMERIC = {
    numericFor = "catalog-numeric-for",
    numericFloat = "catalog-numeric-float",
    numericModZero = "catalog-numeric-modzero",
    numericOverflow = "catalog-numeric-overflow",
    numericControl = "catalog-numeric-control",
    workloadLoops = "catalog-workload-loops",
    callsNumeric = "catalog-calls-numeric",
    workloadFib = "catalog-workload-fib",
    tablesBasic = "catalog-tables-basic",
    workloadClosures = "catalog-workload-closures",
    workloadTables = "catalog-workload-tables",
    workloadRecords = "catalog-workload-records",
    workloadStrings = "catalog-workload-strings",
    stringsBasic = "catalog-strings-basic",
    integersWide = "catalog-integers-wide",
    numbersText = "catalog-numbers-text",
    environmentRead = "catalog-environment",
    numbersFloat = "catalog-numbers-float",
    callsResults = "catalog-calls-results",
    tablesFloatKeys = "catalog-tables-floatkeys",
    stringsLibrary = "catalog-strings-library",
    callsGeneric = "catalog-calls-generic",
    callsVariadic = "catalog-calls-variadic",
    callsSpread = "catalog-calls-spread",
    recordsMethods = "catalog-records-methods",
    callsProtected = "catalog-calls-protected",
    recordsInline = "catalog-records-inline",
    errorsPositions = "catalog-errors-positions",
    tablesMeta = "catalog-tables-meta",
    errorsTexts = "catalog-errors-texts",
    callsXpcall = "catalog-calls-xpcall",
    tablesMetaops = "catalog-tables-metaops",
    tablesLibrary = "catalog-tables-library",
    stringsFormat = "catalog-strings-format",
    recordsConstructors = "catalog-records-constructors",
    numbersMath = "catalog-numbers-math",
    recordsAffine = "catalog-records-affine",
    recordsAffineErrors = "catalog-records-affine-errors",
    recordsaffineraise = "catalog-records-affine-raise",
    recordsdynamic = "catalog-records-dynamic",
    tablesSort = "catalog-tables-sort",
    stringsGsubFunction = "catalog-strings-gsubfn",
    stringsQuoted = "catalog-strings-quoted",
    outputPrint = "catalog-output-print",
    numbersPower = "catalog-numbers-power",
    libraryRanges = "catalog-library-ranges",
    numbersRandom = "catalog-numbers-random",
    errorsLibrary = "catalog-errors-library",
    callsAny = "catalog-calls-any",
    recordsMetamethods = "catalog-records-metamethods",
    callsPacks = "catalog-calls-packs",
    callsOpen = "catalog-calls-open",
    callsExpand = "catalog-calls-expand",
    errorsMethods = "catalog-errors-methods",
    recordsAffineReturns = "catalog-records-affine-returns",
    threadsbasic = "catalog-threads-basic",
    threadscalls = "catalog-threads-calls",
    threadsclose = "catalog-threads-close",
    threadsiterate = "catalog-threads-iterate",
    threadsmeta = "catalog-threads-meta",
    outputwrite = "catalog-output-write",
    libraryspread = "catalog-library-spread",
    tableslibrarymeta = "catalog-tables-library-meta",
    tableslibrarycalls = "catalog-tables-library-calls",
    tablesmetaarity = "catalog-tables-meta-arity",
    moduleslazy = "catalog-modules-main",
    modulesnamed = "catalog-modules-named",
    modulespattern = "catalog-modules-pattern",
    modulesrecords = "catalog-modules-records",
    modulescycle = "catalog-modules-cycle",
    modulesdynamic = "catalog-modules-dynamic",
    libraryvalues = "catalog-library-values",
    textbuffer = "catalog-text-buffer",
    stringbuffer = "catalog-string-buffer",
    librarybasics = "catalog-library-basics",
    cleanupfunctions = "catalog-cleanup-functions",
    serdejson = "catalog-serde-json",
    storagebasics = "catalog-storage-basics",
    storageprovider = "catalog-storage-provider",
    modulesqualified = "catalog-modules-qualified",
    callsoverflow = "catalog-calls-overflow"
}
local FIXTURES = {
    "catalog-boolean",
    "catalog-nil",
    "catalog-live",
    "catalog-fresh",
    "catalog-nested",
    "catalog-branch-true",
    "catalog-branch-false",
    "catalog-branch-elseif",
    "catalog-branch-live",
    "catalog-module-prefix",
    "catalog-module-main",
    "catalog-module-middle",
    "catalog-module-triple",
    "catalog-number-add",
    "catalog-number-negative-zero",
    "catalog-number-nan",
    "catalog-number-branch",
    "catalog-number-loop",
    "catalog-number-loop-zero",
    "catalog-numeric-for",
    "catalog-numeric-float",
    "catalog-numeric-modzero",
    "catalog-numeric-overflow",
    "catalog-numeric-control",
    "catalog-workload-loops",
    "catalog-workload-fib",
    "catalog-calls-numeric",
    "catalog-tables-basic",
    "catalog-workload-closures",
    "catalog-workload-tables",
    "catalog-workload-records",
    "catalog-workload-strings",
    "catalog-strings-basic",
    "catalog-integers-wide"
}
local AUDITS = {
    {"fresh", "success"},
    {"nilValue", "success"},
    {"nested", "success"},
    {"nested", "budget0"},
    {"nested", "budget2"},
    {"nested", "budget4"},
    {"nested", "cancel"},
    {"modulePair", "budget1"}
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

local function u64(value)
    local out = {}
    for at = 0, 7 do
        out[at + 1] = string.char((value >> (at * 8)) & 255)
    end

    return table.concat(out)
end

local function u32(value)
    return string.char(value & 255, (value >> 8) & 255, (value >> 16) & 255, (value >> 24) & 255)
end

local function get64(bytes, offset)
    local value = 0
    for at = 8, 1, -1 do
        value = (value << 8) | bytes:byte(offset + at)
    end

    return value
end

local function put(bytes, offset, encoded)
    return bytes:sub(1, offset) .. encoded .. bytes:sub(offset + #encoded + 1)
end

local function fromHex(text)
    return (text:gsub("..", function(pair)
        return string.char(tonumber(pair, 16))
    end))
end

local failures, checks = {}, 0

local function same(a, b)
    if type(a) ~= type(b) then
        return false
    elseif type(a) ~= "table" then
        return a == b
    end
    for key, value in pairs(a) do
        if not same(value, b[key]) then
            return false
        end
    end
    for key in pairs(b) do
        if a[key] == nil then
            return false
        end
    end

    return true
end

local function check(ok, label)
    checks = checks + 1
    if not ok then
        failures[#failures + 1] = label
        print("FAIL " .. label)
    end

    return ok
end

-- The bridge and its ABI/scratch guard, built once with cargo.
local function tools()
    local target = ROOT .. "/build/core-bridge"
    local manifest = quote(ROOT .. "/native/core/bridge/Cargo.toml")
    local status, output = shell(
        (
            "cargo +stable build --manifest-path %s --offline --locked --bin nupp-core --target-dir %s"
        ):format(manifest, quote(target))
    )
    assert(status == 0, "bridge build failed: " .. output)
    status, output = shell(
        (
            "cargo +stable test --manifest-path %s --offline --locked --no-run --message-format=json --target-dir %s"
        ):format(manifest, quote(target))
    )
    assert(status == 0, "guard build failed: " .. output)
    local guard
    for line in output:gmatch("[^\n]+") do
        if line:find('"profile":{[^}]*"test":true') and line:find('"executable":"') then
            guard = line:match('"executable":"([^"]+)"')
        end
    end

    return target .. "/debug/nupp-core", assert(guard, "guard test executable not found")
end

-- Stage the source snapshots the closed guest builds read: the canonical core
-- sources, the negative module and the module fixtures.
local function stage()
    local canonical = {}
    for _, name in ipairs({
        "arena",
        "frames",
        "context",
        "frameaccess",
        "instances",
        "guestcatalog",
        "guestentry",
        "guestops",
        "guesthandlers"
    }) do
        canonical[#canonical + 1] = "native/core/src/nupp/runtime/core/" .. name .. ".nupp"
    end
    for _, name in ipairs({"intrinsics.d.nupp", "program.d.nupp", "slots.d.nupp", "values.nupp"}) do
        canonical[#canonical + 1] = "src/nupp/runtime/vm/" .. name
    end
    canonical[#canonical + 1] = "native/core/tests/guest-contract-negatives.nupp"
    for _, fixture in ipairs(FIXTURES) do
        canonical[#canonical + 1] = "native/core/tests/" .. fixture .. ".nupp"
    end
    for _, directory in ipairs({"core-guest-programs", "core-guest-audit"}) do
        local base = ROOT .. "/build/" .. directory
        os.execute(
            "mkdir -p " .. quote(base .. "/source/nupp/runtime/core") .. " " .. quote(base .. "/source/nupp/core")
        )
        local names = {}
        for _, name in ipairs(canonical) do
            names[#names + 1] = name
        end
        write(base .. "/source/nupp/runtime/core/guestnegatives.nupp", read(TESTS .. "/guest-contract-negatives.nupp"))
        if directory == "core-guest-audit" then
            names[#names + 1] = "native/core/tests/guest-lifecycle-audit.nupp"
            write(base .. "/source/nupp/runtime/core/guestaudit.nupp", read(TESTS .. "/guest-lifecycle-audit.nupp"))
        end
        for _, fixture in ipairs({
            "catalog-module-prefix",
            "catalog-module-main",
            "catalog-module-middle",
            "catalog-module-triple",
            "catalog-modules-shapes",
            "catalog-modules-counter",
            "catalog-modules-main",
            "catalog-modules-geometry",
            "catalog-modules-named",
            "catalog-modules-pattern",
            "catalog-modules-boxes",
            "catalog-modules-records",
            "catalog-modules-ping",
            "catalog-modules-pong",
            "catalog-modules-cycle",
            "catalog-modules-qualified",
            "catalog-modules-dynamic",
            "catalog-library-values",
            "catalog-text-buffer",
            "catalog-string-buffer",
            "catalog-library-basics",
            "catalog-cleanup-functions",
            "catalog-serde-json",
            "catalog-storage-basics",
            "catalog-storage-provider"
        }) do
            write(
                base .. "/source/nupp/core/" .. fixture:gsub("-", "") .. ".nupp",
                read(TESTS .. "/" .. fixture .. ".nupp")
            )
        end
        -- A module under a root of its own, which a qualified path names.
        os.execute("mkdir -p " .. quote(base .. "/source/atlas"))
        write(base .. "/source/atlas/geometry.nupp", read(TESTS .. "/catalog-atlas-geometry.nupp"))
        local sources = {}
        for _, name in ipairs(names) do
            sources[name] = assert(read(ROOT .. "/" .. name), name)
        end
        write(
            base .. "/snapshot.json",
            json.encodevalue({
                version = 1,
                target = "aarch64-apple-darwin",
                sources = sources
            })
        )
    end
end

-- Reference Lua 5.5 results for the numeric fixtures, as NaN-boxed words. A
-- sibling .lua file is a hand-written twin for fixtures Lua cannot parse.
local function oracle(lua, fixture)
    local twin = read(TESTS .. "/" .. fixture .. ".lua")
    local source = twin
    if not source then
        local lines = {}
        for line in assert(read(TESTS .. "/" .. fixture .. ".nupp")):gmatch("[^\n]*\n?") do
            if not line:match("^module ") then
                line = line:gsub("^export = ", "return "):gsub("^local (%w+): %w+ =", "local %1 =")
                lines[#lines + 1] = line
            end
        end
        source = table.concat(lines)
    end
    local program = OUT .. "/" .. fixture .. ".oracle.lua"
    write(
        program,
        -- On the twin's first line, so error positions keep their lines.
        "local ok, v = pcall(function() "
        .. source
        .. "\nend)\n"
        .. "if not ok then io.write('E', tostring(v))\n"
        .. "elseif math.type(v) == 'integer' then io.write('I', string.format('%d', v))\n"
        .. "else io.write('F', string.format('%016x', string.unpack('<I8', string.pack('<d', v)))) end\n"
    )
    local status, output = shell(GUEST_ENV .. quote(lua) .. " " .. quote(program))
    assert(status == 0, output)
    local kind, value = output:sub(1, 1), output:sub(2)
    if kind == "E" then
        return "error"
    elseif kind == "I" then
        local number = math.tointeger(tonumber(value))
        if number < -(1 << 47) or number >= (1 << 47) then
            return "integer"
        end
        return 0x7FFF000000000000 | (number & 0xFFFFFFFFFFFF)
    end
    local bits = tonumber(value, 16)
    if bits & 0x7FF0000000000000 == 0x7FF0000000000000 and bits & 0xFFFFFFFFFFFFF ~= 0 then
        return 0x7FF8000000000000
    end

    return bits
end

local function bundleOf(selected, scratch)
    local words = {}
    for index, word in ipairs(selected.words) do
        words[index] = u32(word)
    end
    local code, data = table.concat(words), fromHex(selected.dataHex)
    assert(#data == selected.dataBytes, "data extent")

    return "NUPPCORE" .. u64(
        1
    ) .. u64(
        1
    ) .. u64(
        selected.entry
    ) .. u64(#code) .. u64(#data) .. u64(scratch) .. u64(1) .. u64(0) .. code .. data, #code, data
end

local function main()
    os.execute("mkdir -p " .. quote(OUT))
    local selectedCases = {}
    local wanted = {}
    for _, name in ipairs(arg) do
        wanted[name] = true
    end
    for _, case in ipairs(CASES) do
        if next(wanted) == nil or wanted[case[1]] then
            selectedCases[#selectedCases + 1] = case
        end
    end
    local lua = os.getenv("NUPP_LUA_REFERENCE")
    if lua then
        for name, fixture in pairs(NUMERIC) do
            local observed = oracle(lua, fixture)
            local expected
            for _, case in ipairs(CASES) do
                if case[1] == name then
                    expected = case[2]
                end
            end
            if name == "numericModZero" then
                check(observed == "error", "oracle " .. name .. " raises")
            elseif name == "numericOverflow" then
                check(observed == "integer", "oracle " .. name .. " leaves the immediate range")
            else
                check(observed == expected, ("oracle %s: %s"):format(name, tostring(observed)))
            end
        end
    end
    local bridge, guard = tools()
    stage()
    local started = os.time()
    local list = {}
    for _, case in ipairs(selectedCases) do
        list[#list + 1] = case[1] .. ":normal"
        list[#list + 1] = case[1] .. ":spill"
    end
    local selections = {}
    for _, item in ipairs(list) do
        local name, mode = item:match("^(%w+):(%w+)$")
        if UNITS then
            selections[
                name .. "-" .. mode
            ] = producer.selectUnits(name, mode, tostring(SCRATCH), ROOT .. "/build/core-unit-cache")
        else
            selections[name .. "-" .. mode] = producer.select(name, mode, "131072")
        end
    end
    print(("selected %d programs in %ds"):format(#list, os.time() - started))
    local empty = OUT .. "/empty.bin"
    write(empty, "")

    -- Answers what the bridge wrote, its output and errors together.
    local function bridgeRun(label, bundle, input, output, expectedStatus, environment)
        local status, printed = shell(
            (
                environment or GUEST_ENV
            ) .. ("%s %s %s %s"):format(quote(bridge), quote(bundle), quote(input), quote(output))
        )
        check((status == 0) == (expectedStatus == 0), label .. " bridge status")

        return printed
    end

    local function guarded(label, bundle, input, highWater, expectedPath, status)
        if QUICK or HEAVY[label:match("^(%w+)")] then
            return
        end
        local env = GUEST_ENV .. (
            "CORE_TEST_BUNDLE=%s CORE_TEST_INPUT=%s CORE_TEST_HIGH_WATER=%d "
        ):format(quote(bundle), quote(input), highWater)
        local test = "abi::generated_entry_preserves_c_abi_and_output"
        if status then
            env = env .. "CORE_TEST_STATUS=" .. status .. " "
            test = "abi::generated_entry_returns_requested_status"
        else
            env = env .. "CORE_TEST_EXPECTED=" .. quote(expectedPath) .. " "
        end
        local _, output = shell(env .. quote(guard) .. " --ignored --exact " .. test .. " --test-threads=1")
        check(output:find("1 passed; 0 failed; 0 ignored;", 1, true) ~= nil, label .. " guard")
    end

    local sentinel = "refused guest operation left output unchanged"

    local function refuses(label, bundle, input)
        if QUICK then
            return
        end
        local output = OUT .. "/" .. label .. ".out"
        write(output, sentinel)
        bridgeRun(label, bundle, input, output, 1)
        check(read(output) == sentinel, label .. " published nothing")
    end

    for _, case in ipairs(selectedCases) do
        local name, expectedWord = case[1], case[2]
        for _, mode in ipairs({"normal", "spill"}) do
            local label = name .. "-" .. mode
            local selected = selections[label]
            check(selected.caseName == name and selected.mode == mode, label .. " identity")
            if mode == "spill" then
                local normal = selections[name .. "-normal"]
                check(same(selected.programs, normal.programs), label .. " stream independent of mode")
                for _, item in ipairs(selected.metrics) do
                    check(item.integerRegisters == 0 and item.floatRegisters == 0, label .. " spills everything")
                end
            end
            local highWater = selected.spillOffset + selected.callBytes
            check(highWater <= SCRATCH, label .. " high water")
            local bundleBytes, codeBytes, data = bundleOf(selected, SCRATCH)
            local version = get64(data, 0)
            -- The profile version from v3; before it one module is descriptor v1.
            local profile = guestbuild.version(name)
            local modules = (name == "modulePair" or name == "moduleTriple") and 2 or 1
            check(version == (profile >= 3 and profile or modules), label .. " descriptor version")
            local bundle = OUT .. "/" .. label .. ".bundle"
            write(bundle, bundleBytes)
            if STATUS[name] then
                refuses(label, bundle, empty)
                guarded(label, bundle, empty, highWater, nil, STATUS[name])
            else
                local expected = OUT .. "/" .. label .. ".expected"
                write(expected, u64(expectedWord))
                local output = OUT .. "/" .. label .. ".out"
                os.remove(output)
                local printed = bridgeRun(label, bundle, empty, output, 0)
                check(read(output) == u64(expectedWord), ("%s result %016x"):format(label, expectedWord))
                check(printed == (OUTPUT[name] or ""), label .. " printed output")
                guarded(label, bundle, empty, highWater, expected)
                -- The same result with a whole collection at every allocation.
                if STRESS[name] and UNITS then
                    local input = OUT .. "/" .. label .. "-stress.bin"
                    write(input, u64(-1) .. u64(0) .. u64(1))
                    local stressed = OUT .. "/" .. label .. "-stress.out"
                    os.remove(stressed)
                    local again = bridgeRun(label .. " stress", bundle, input, stressed, 0)
                    check(again == (OUTPUT[name] or ""), label .. " printed output under collect-at-every-allocation")
                    check(read(stressed) == u64(expectedWord), label .. " result under collect-at-every-allocation")
                    -- And with interleaved incremental collection, the
                    -- oracle checking every cycle (a failure is status 1001).
                    local stepped = OUT .. "/" .. label .. "-interleaved.bin"
                    write(stepped, u64(-1) .. u64(0) .. u64(2))
                    local steppedOut = OUT .. "/" .. label .. "-interleaved.out"
                    os.remove(steppedOut)
                    local printedStepped = bridgeRun(label .. " interleaved", bundle, stepped, steppedOut, 0)
                    check(printedStepped == (OUTPUT[name] or ""), label .. " printed output under interleaved collection")
                    check(read(steppedOut) == u64(expectedWord), label .. " result under interleaved collection")
                end
                -- The workloads read BENCH_SCALE at run time; scale 2 has its own
                -- checksums (bench/vm/workloads.bench.nupp).
                if SCALED[name] and label:match("%-normal$") then
                    local scaled = OUT .. "/" .. label .. "-scale2.out"
                    os.remove(scaled)
                    bridgeRun(label .. " scale 2", bundle, empty, scaled, 0, GUEST_ENV .. "BENCH_SCALE=2 ")
                    check(read(scaled) == u64(SCALED[name]), label .. " result at BENCH_SCALE=2")
                end
                local _, short = shell(
                    (
                        "CORE_TEST_BUNDLE=%s CORE_TEST_INPUT=%s CORE_TEST_HIGH_WATER=0 %s --ignored --exact abi::generated_entry_refuses_short_regions --test-threads=1"
                    ):format(quote(bundle), quote(empty), quote(guard))
                )
                check(short:find("1 passed; 0 failed; 0 ignored;", 1, true) ~= nil, label .. " short regions refused")
                local body = selected.programs[#selected.programs]
                if name:match("^numeric") then
                    local seen, backward = {}, false
                    for _, instruction in ipairs(body.instructions) do
                        seen[instruction[1]] = true
                        backward = backward or instruction[1] == "Jmp" and instruction[2] < 0
                    end
                    check(seen.Le and seen.Add and seen.JmpIf and backward, label .. " numeric loop shape")
                end
                if name == "modulePair" then
                    local modules = get64(data, 15 * 8)
                    check(
                        get64(data, 0) == 2 and get64(data, 3 * 8) == 1 and get64(data, 14 * 8) == 2,
                        label .. " descriptor"
                    )
                    check(get64(data, modules) == 0 and get64(data, modules + 8) == 1, label .. " module order")
                    local entry = selected.programs[2]
                    local requirePc
                    for index, instruction in ipairs(entry.instructions) do
                        if instruction[1] == "Require" then
                            requirePc = index - 1
                        end
                    end
                    local at = selected.catalogOffsets.code[2] + requirePc * 16 + 4
                    local prefix = bundleBytes:sub(1, 72 + codeBytes)
                    local wrong = OUT .. "/" .. label .. "-wrong-import.bundle"
                    write(wrong, prefix .. put(data, at, u32(1)))
                    guarded(label .. " wrong import", wrong, empty, highWater, nil, 4)
                    local duplicate = OUT .. "/" .. label .. "-duplicate.bundle"
                    write(duplicate, prefix .. put(data, modules, u64(1)))
                    guarded(label .. " duplicate module", duplicate, empty, highWater, nil, 1)
                    local count = OUT .. "/" .. label .. "-count.bundle"
                    write(count, prefix .. put(data, 14 * 8, u64(3)))
                    guarded(label .. " module count", count, empty, highWater, nil, 1)
                end
                if name == "numberAdd" or name == "numberBranch" then
                    local op = name == "numberAdd" and "Add" or "Lt"
                    local pc
                    for index, instruction in ipairs(body.instructions) do
                        if instruction[1] == op and not pc then
                            pc = index - 1
                        end
                    end
                    local prefix = bundleBytes:sub(1, 72 + codeBytes)
                    local at = selected.catalogOffsets.code[#selected.catalogOffsets.code] + pc * 16 + 3
                    local slot = OUT .. "/" .. label .. "-wrong-slot.bundle"
                    write(slot, prefix .. put(data, at, string.char(249)))
                    refuses(label .. "-wrong-slot", slot, empty)
                    local operand = OUT .. "/" .. label .. "-tagged-operand.bundle"
                    local constants = selected.catalogOffsets.constants
                    write(
                        operand,
                        prefix .. put(data, constants[name == "numberAdd" and 1 or #constants], u64(0x7FFB000000000000))
                    )
                    refuses(label .. "-tagged-operand", operand, empty)
                end
                local budgets = {{0, 0, 2}, {0, 1, 3}}
                if name == "numberLoop" or name == "numericFor" or name == "modulePair" then
                    budgets[#budgets + 1], budgets[#budgets + 2] = {1, 0, 2}, {2, 0, 2}
                elseif name == "nested" then
                    budgets[#budgets + 1], budgets[#budgets + 2] = {2, 0, 2}, {4, 0, 2}
                elseif name == "moduleTriple" then
                    budgets[#budgets + 1] = {1, 0, 2}
                elseif name == "numberLoopZero" then
                    budgets = {}
                end
                for _, item in ipairs(budgets) do
                    local input = ("%s/%s-budget%d-cancel%d.bin"):format(OUT, label, item[1], item[2])
                    write(input, u64(item[1]) .. u64(item[2]))
                    guarded(
                        ("%s budget %d cancel %d"):format(label, item[1], item[2]),
                        bundle,
                        input,
                        highWater,
                        nil,
                        item[3]
                    )
                    refuses(("%s-budget%d-cancel%d"):format(label, item[1], item[2]), bundle, input)
                end
                if name == "numberLoop" or name == "numberLoopZero" then
                    local budget = name == "numberLoop" and 3 or 0
                    local input = ("%s/%s-budget%d.bin"):format(OUT, label, budget)
                    write(input, u64(budget) .. u64(0))
                    guarded(label .. " completes within budget", bundle, input, highWater, expected)
                end
            end
        end
    end

    print(("primary checks done at %ds"):format(os.time() - started))
    -- Supplemental lifecycle audits wrap selected primary programs.
    for _, mode in ipairs({"normal", "spill"}) do
        if QUICK then
            break
        end
        for _, item in ipairs(AUDITS) do
            local name, scenario = item[1], item[2]
            local present = false
            for _, case in ipairs(selectedCases) do
                present = present or case[1] == name
            end
            if present then
                local label = ("audit-%s-%s-%s"):format(name, mode, scenario)
                local selected = UNITS
                    and producer.selectUnits(name, mode, tostring(SCRATCH), ROOT .. "/build/core-unit-cache", scenario)
                    or producer.select(name, mode, "131072", scenario)
                local primary = selections[name .. "-" .. mode]
                check(same(selected.programs, primary.programs), label .. " stream unchanged")
                check(same(selected.dispatch, primary.dispatch), label .. " dispatch unchanged")
                local highWater = selected.spillOffset + selected.callBytes
                local bundleBytes = bundleOf(selected, selected.scratchBytes)
                local bundle = OUT .. "/" .. label .. ".bundle"
                write(bundle, bundleBytes)
                if scenario == "success" then
                    local expectedWord
                    for _, case in ipairs(CASES) do
                        if case[1] == name then
                            expectedWord = case[2]
                        end
                    end
                    local expected = OUT .. "/" .. label .. ".expected"
                    write(expected, u64(expectedWord))
                    local output = OUT .. "/" .. label .. ".out"
                    os.remove(output)
                    bridgeRun(label, bundle, empty, output, 0)
                    check(read(output) == u64(expectedWord), label .. " result")
                    guarded(label, bundle, empty, highWater, expected)
                else
                    local budgets = {
                        budget0 = {0, 0},
                        budget1 = {1, 0},
                        budget2 = {2, 0},
                        budget4 = {4, 0},
                        cancel = {0, 1}
                    }
                    local input = OUT .. "/" .. label .. ".bin"
                    write(input, u64(budgets[scenario][1]) .. u64(budgets[scenario][2]))
                    local status = scenario == "cancel" and 3 or 2
                    check(selected.audit.expectedStatus == status, label .. " expected status")
                    guarded(label, bundle, input, highWater, nil, status)
                end
            end
        end
    end
    print(("%d checks, %d failed, %ds"):format(checks, #failures, os.time() - started))
    os.exit(#failures == 0 and 0 or 1)
end

main()
