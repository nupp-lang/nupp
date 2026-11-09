-- Checked-source guest programs on the standalone core: every case is built
-- through the shared guest unit, run through the bridge and the ABI/scratch
-- guard, and checked against independent expectations.
--
--   cd native/core/tests/guests && NUPP_COMPILER_ROOT=$PWD/../../../.. ../../../../bin/nupp run run.lua [CASE...]
--
-- NUPP_LUA_REFERENCE names a reference Lua 5.5 interpreter; when set, the
-- numeric expectations are recomputed with it. Bundles and outputs go under
-- build/core-guests.
--
-- The cases run in NUPP_GUEST_SHARDS processes (default 4), which share
-- about NUPP_GUEST_JOBS (default 8) bridge and guard processes, each shard
-- running its own while it selects the next case; NUPP_GUEST_SHARDS=1 runs
-- them all here. A whole run is bounded by its longest process,
-- workloadLoops in spill mode.
local json = require("serde.json")
local sharedcache = require("nupp.core.sharedcache")
local selectioncache = require("nupp.core.selectioncache")
-- The producer and the guest build carry the compiler, and a checkout that has
-- not lowered them yet spends a minute doing so as they load. A run whose every
-- selection is kept in the shared store (`nupp.core.selectioncache`) never needs
-- them, so they load on first need (`compiler`, below).
local producer, guestbuild

local function cwd()
    local pipe = assert(io.popen("pwd"))
    local path = pipe:read("*l")
    pipe:close()
    return path
end

local HERE = debug.getinfo(1, "S").source:match("^@(/.*)/[^/]*$") or cwd()
-- Another spelling of the root runs this again under its own (compilerroot).
local ROOT = require("nupp.core.compilerroot").resolve(arg[0], arg)
local shardplan = dofile(ROOT .. "/native/core/tests/guests/shardplan.lua")
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
-- NUPP_GUEST_MODES=normal runs each case's normal program only, the inner
-- loop's choice; spill joins it by default. NUPP_GUEST_STRESS=0 skips the
-- collect-at-every-allocation and interleaved runs, which a change to the heap,
-- the collector, frames or ownership needs and others do not.
local MODES = {}
for mode in (os.getenv("NUPP_GUEST_MODES") or "normal,spill"):gmatch("[^,]+") do
    MODES[#MODES + 1] = mode
end
local STRESSED = os.getenv("NUPP_GUEST_STRESS") ~= "0"
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
local GUEST_ENV = "NUPP_GUEST_PROBE=core-environment NUPP_GUEST_SCALE=3 NUPP_GUEST_LONG=" .. string.rep(
    "x",
    300
) .. " NUPP_GUEST_TEMP=" .. OUT .. "/temp" .. " "

local CASES = {
    {"bindingconditions", 0x7FFB000000000000},
    {"optionalmethodcleanups", 0x7FFF000000000001},
    {"numericsteps", 0x7FFF000000000001},
    {"stringdynamic", 0x7FFF000000000001},
    {"stringmetaonly", 0x7FFF000000000001},
    {"stringmetatable", 0x7FFF000000000001},
    {"stringmethods", 0x7FFF000000000001},
    {"stringgmatchvalues", 0x7FFF000000000001},
    {"scalarmath", 0x7FFF000000000001},
    {"scalarrandom", 0x7FFF000000000001},
    {"scalarmutation", 0x7FFF000000000001},
    {"clockprovider", 0x7FFF00000000003F},
    {"systemprovider", 0x7FFF000000000007},
    {"systeminfo", 0x7FFF00000000000F},
    {"entropy", 0x7FFF00000000000F},
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
    {"numbersFloat", 0x7FFF0001C768D923},
    {"callsResults", 0x7FFF000000259D74},
    {"tablesFloatKeys", 0x7FFF0000065C2564},
    {"stringsLibrary", 0x7FFF0000547F9CA7},
    {"callsGeneric", 0x7FFF00000C2F4BF7},
    {"callsVariadic", 0x7FFF01026AA11247},
    {"callsSpread", 0x7FFF001B69EC548D},
    {"recordsMethods", 0x7FFF000AFDC52FB5},
    {"callsProtected", 0x7FFF00001E76EFC7},
    {"protectedpacks", 0x7FFF000000000001},
    {"callstables", 0x7FFF00000000FFFF},
    {"nonreturningbodies", 0x7FFF00000000001F},
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
    {"recordsaffineraise", 0x7FFF000000025642},
    {"recordsdynamic", 0x7FFF0000002F2854},
    {"recordscallable", 0x7FFF0000073A889B},
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
    {"callsOpen", 0x7FFF000000002B71},
    {"callsExpand", 0x7FFF00000E655693},
    {"errorsMethods", 0x7FFF0000000000FF},
    {"recordsAffineReturns", 0x7FFF001A27644F86},
    {"threadsbasic", 0x7FFF000000000FFF},
    {"coroutineinheritance", 0x7FFF00000000007F},
    {"qualifiedrecordcapture", 0x7FFF000000000008},
    {"assertvalue", 0x7FFF000000000001},
    {"threadscalls", 0x7FFF00000000003F},
    {"threadsclose", 0x7FFF00000000007F},
    {"threadsiterate", 0x7FFF00000000001F},
    {"threadsmeta", 0x7FFF000000105C53},
    {"threadsmethods", 0x7FFF00000000007F},
    {"tasksbasic", 0x7FFF00000000003F},
    {"taskscancel", 0x7FFF00000000003F},
    -- 3,000 tasks parked on timers and on each other.
    {"tasksscopes", 0x7FFF00000000003F},
    -- 200,000 coroutines between collections, recursion 150,000 frames deep
    -- in one, a yield 20,000 deep and an overflow in one.
    {"threadsstacks", 0x7FFF00000000003F},
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
    {"pluckedarguments", 0x7FFF001C1CF80790},
    {"ownmanage", 0x7FFF000000000200},
    {"loopparameteralias", 0x7FFF000000000002},
    {"namedarguments", 0x7FFF000337156A8D},
    {"legacyglobals", 0x7FFF000000000463},
    {"gotocontinue", 0x7FFF0000000009E7},
    {"derivedmembers", 0x7FFF00000000000F},
    {"shortfunctions", 0x7FFF000000003BEE},
    {"modulesforward", 0x7FFF0000000000FF},
    {"modulesself", 0x7FFF000000000007},
    {"modulesdynamic", 0x7FFF000000002B20},
    {"libraryvalues", 0x7FFF00000000003F},
    {"bytebuffer", 0x7FFF000000000003},
    {"bufferstate", 0x7FFF000000000001},
    {"sharedbytes", 0x7FFF000000000001},
    {"spanreads", 0x7FFF000000000001},
    {"spanwrites", 0x7FFF000000000001},
    {"librarybasics", 0x7FFF00000000007F},
    {"cleanupfunctions", 0x7FFF000000000003},
    {"ownedcallables", 0x7FFF000000000001},
    {"scalartypeof", 0x7FFF000000000001},
    {"coreoperators", 0x7FFF0000000003FF},
    {"methodcleanups", 0x7FFF00000000001F},
    {"ownerreinit", 0x7FFF00000000007F},
    {"coreforms", 0x7FFF0000000003FF},
    {"storagebasics", 0x7FFF000000001FFF},
    {"storageprovider", 0x7FFF00000000003F},
    {"modulesqualified", 0x7FFF0000000000E6},
    {"callsoverflow", 0x7FFF000000000003},
    {"tablesfrozen", 0x7FFF000000000FFF},
    -- Packed array parts (runtime Decision 15): kinds, switches, the table
    -- library and the collector; then what Lua sees of them, as a checksum.
    {"tablespacked", 0x7FFF0000000007FF},
    {"tablespackedsemantics", 0x7FFF00000DEDBD01},
    {"serdejson", 0x7FFF000000000003},
    {"modulesretry", 0x7FFF00000000007F},
    {"errorsruntime", 0x7FFF00000000001F},
    {"hostlibrary", 0x7FFF0000000000FF},
    {"benchforms", 0x7FFF00000000003F},
    {"callarguments", 0x7FFF00001FFFFFFF},
    {"iofiles", 0x7FFF3FFFFFFFFFFF},
    {"iostandard", 0x7FFF00000000000F},
    {"reactorpipes", 0x7FFF00000007FFFF},
    {"reactorfiles", 0x7FFF000000001FFF},
    -- Parked I/O and timers in the scheduler's one loop.
    {"tasksreactor", 0x7FFF00000000001F},
    {"processexecute", 0x7FFF000000001FFF},
    {"processpopen", 0x7FFF00003FFFFFFF},
    {"processhandle", 0x7FFF000001FFFFFF},
    {"runnerlowering", 0x7FFF0000000000FF},
    {"affineconstructors", 0x7FFF0000000000FF},
    {"absentffi", 0x7FFF000000000007},
    {"guestffi", 0x7FFF000000001FFF},
    {"ffiaggregates", 0x7FFF0000003FFFFF},
    {"runnerresiduals", 0x7FFF00000000007F},
    -- Library calls spreading `...` through the library function's value.
    {"spreadlibrary", 0x7FFF0000000003FF},
    -- Library calls given every result of a call last, through the value.
    {"libraryresults", 0x7FFF000000001FFF},
    {"processlines", 0x7FFF000000000FFF},
    {"processlayer", 0x7FFF000000FFFFFF},
    -- os.exit(3): the program ends there, publishing nothing (EXITS).
    {"processexit", 0},
    -- Weak tables, finalizers and collectgarbage's options as Lua 5.5 has
    -- them; every marked table finalized at the program's end and at
    -- os.exit(4, true), which publishes nothing (EXITS).
    {"gcweak", 0x7FFF0000000001FF},
    {"gcfinalizers", 0x7FFF0000000003FF},
    {"gcoptions", 0x7FFF000000007FFF},
    {"gcend", 0x7FFF000000000005},
    {"gcexit", 0},
    -- warn's contract; an error no protected call takes reported, then
    -- every marked table finalized (EXITS).
    {"logwarn", 0x7FFF00000000007F},
    {"gcwarn", 0x7FFF000000000007},
    {"gcraise", 0},
    -- An error no protected call takes: reported on standard error, and
    -- the program ends with status 1, publishing nothing (EXITS).
    {"errorsuncaught", 0},
    -- Lua's clock and calendar (os.time, os.date, os.clock, os.difftime);
    -- os.remove, os.rename, os.tmpname, os.setlocale and io.tmpfile; and
    -- main's recursive os.remove and io.Path arguments.
    {"ostime", 0x7FFF00003FFFFFFF},
    {"osfiles", 0x7FFF00000003FFFF},
    {"filesystem", 0x7FFF000000000001},
    {"osremove", 0x7FFF000000001FFF},
    -- The compiler's host services as the core answers them for check and build.
    {"clihosts", 0x7FFF0000000000FF},
    -- C declarations through libclang, and the VM's answers to every
    -- request core-cdecl-record.lua records.
    {"corecdecl", 0x7FFF0000000007FF},
    {"loadbinary", 0x7FFF000000001FFF},
    -- A record with an array part: fields and elements apart.
    {"recordsarray", 0x7FFF00000000000F},
    -- A function statement assigning a local declared before it.
    {"forwardfunctions", 0x7FFF000000000003},
    -- Main's os filesystem and system functions; main answers the same word.
    {"osfilesystem", 0x7FFF0007FFFFFFFF},
    -- The compiler's lexer and parser on the core.
    {"compilerfront", 0x7FFF00000000000F},
    -- Lua's loaders over source text, compiled on the core by the compiler
    -- the program carries.
    {"loadsource", 0x7FFF0000000FFFFF},
    -- The compiler's lexer alone on the core, over whole source files.
    {"compilerlexer", 0x7FFF00000000000F},
    -- A checked call spreading fewer or more results than it has parameters.
    {"callsspreadshort", 0x7FFF00000000001F},
    -- Lua's debug.getinfo: sources, lines and names by level and of values.
    {"debuggetinfo", 0x7FFF00000001FFFF},
    -- The bench harness's own entry (bench/vm/workloads.bench.nupp under
    -- debug.bench), measuring fib: its record is checked (OUTPUT); the
    -- entry exports nothing.
    {"benchworkloads", 0x7FF9000000000000},
    -- 600 functions, past the 256 owners the graph schema once admitted.
    {"functionsmany", 0x7FFF00000002C04C},
    -- Recursion to 150,000 frames and an overflow at 200,000 (7 * 10^6 +
    -- the deepest call, 199,999).
    {"callsdeep", 0x7FFF0000006DDCFF},
    -- Forty calls through a function value in one function, run directly
    -- and in a coroutine that yields at each; recursion with results and
    -- extra arguments; a deep error caught (850,001 * 8 + every check, 7).
    {"callsmany", 0x7FFF00000067C28F},
    -- Pattern anchors in find, match, gmatch and gsub, and where `^` and `$`
    -- are literal.
    {"stringsanchors", 0x7FFF0005D99B5B1C},
    -- Recursive local functions called by name: declared, inferred and
    -- unannotated, variadic with several results, nested, mutually recursive
    -- and through a forward-declared local (255 * 10^6 + 1,617).
    {"callsrecursive", 0x7FFF00000F330411},
    -- 260 modules whose chunk depths sum to 4,421 frames: every one ran.
    {"modulesmany", 0x7FFB000000000000}
}
-- What the cases that print write to the host's output, as Lua 5.5 writes it
-- but for floats, which print the shorter exact text (Decision 13).
local OUTPUT = {
    outputPrint = "hello\t42\t1.5\ttrue\tnil\tfalse\n\nxxx\t3\t-0.0\t1e100\t9007199254740992.0\n"
    .. "line\t1\nline\t2\nline\t3\n",
    callsExpand = "1\t2\nx\t1\t2\n",
    outputwrite = "hello 42 1.5\n3.0 -0.0 9.223372036854776e18\nab\nx7\np\n",
    libraryspread = "1\t2\t3\n3\t3\n97\t98\t99\n2\t3\ntrue\t1\t2\n",
    moduleslazy = "main start\nshapes loading\ncounter loading\nmain required\n",
    iostandard = "a1 b\t2.5\ne\nc\n1\ttrue\t7\tx\nfalse\tboom\ntail\ttrue\nw\n",
    processexit = "before exit\nprinted\t1\n",
    gcend = "dropped\nend\t3\nend\t2\nend\t1\n",
    gcexit = "exiting\nclosed\t2\nclosed\t1\n",
    gcwarn = "warn warn: joined text 42\nwarn warn: @not a control\n"
}
-- The bench entry's record, which holds times: its shape and fib(20)'s
-- checksum (SETUP) are what is checked, not what it measured.
OUTPUT.benchworkloads = function(printed)
    local ok, record = pcall(json.decodevalue, printed)
    local case = ok and type(record) == "table" and type(record.cases) == "table" and record.cases[1]
    if type(case) ~= "table" or #record.cases ~= 1 or type(record.schema) ~= "number" then
        return false
    end
    local samples = case.samplesMs
    if type(samples) ~= "table" or #samples ~= case.rounds then
        return false
    end
    for _, sample in ipairs(samples) do
        if type(sample) ~= "number" or sample < 0 then
            return false
        end
    end

    return case.name == "fib"
        and case.kind == "case"
        and case.n == 1
        and case.rounds == 7
        and case.checksum == "6765"
        and type(case.medianMs) == "number"
end

-- The uncaught error's report names its chunk as the core does: a long
-- path, shortened as Lua shortens one.
OUTPUT.errorsuncaught = function(printed)
    return printed:find("^before error\nprinted\t1\nnupp: [^\n]*catalogerrorsuncaught%.nupp:12: boom\n$") ~= nil
end

-- The finalizers' failures, warned of as Lua's luaE_warnerror words them,
-- each on a line as `log` starts a warning: one raised, and a __gc that is
-- no function.
OUTPUT.gcfinalizers = function(printed)
    return printed:find(
        "^warn warn: error in __gc %([^\n]*catalog%-?gc%-?finalizers%.nupp:109: boom%)\n"
        .. "warn warn: error in __gc %(attempt to call a boolean value %(metamethod '__gc'%)%)\n$"
    ) ~= nil
end

-- The report comes first, then the finalizers, newest first.
OUTPUT.gcraise = function(printed)
    return printed:find("^raising\nnupp: [^\n]*catalog%-?gc%-?raise%.nupp:20: boom\nclosed\t2\nclosed\t1\n$") ~= nil
end

-- Whether `printed` is what case `name` prints.
local function printedAs(name, printed)
    local expected = OUTPUT[name]
    if type(expected) == "function" then
        return expected(printed)
    end

    return printed == (expected or "")
end

-- Heap-using cases that also run with a collection at every allocation, and
-- with interleaved incremental collection. Full cycles under stress are
-- spaced by a share of what lives, so the full-scale workloads stay linear;
-- records and strings, at seconds a run there, run so in normal mode alone.
local STRESS = {
    ownedcallables = true,
    scalartypeof = true,
    optionalmethodcleanups = true,
    numericsteps = true,
    stringdynamic = true,
    stringmetaonly = true,
    stringmetatable = true,
    stringmethods = true,
    stringgmatchvalues = true,
    scalarmath = true,
    scalarrandom = true,
    scalarmutation = true,
    clockprovider = true,
    systemprovider = true,
    systeminfo = true,
    entropy = true,
    callsNumeric = true,
    workloadFib = true,
    tablesBasic = true,
    workloadClosures = true,
    workloadTables = true,
    workloadRecords = "normal",
    workloadStrings = "normal",
    stringsBasic = true,
    integersWide = true,
    threadsbasic = true,
    coroutineinheritance = true,
    threadscalls = true,
    threadsclose = true,
    tableslibrarycalls = true,
    tablesSort = true,
    stringsLibrary = true,
    stringsGsubFunction = true,
    libraryspread = true,
    threadsiterate = true,
    threadsmeta = true,
    threadsmethods = true,
    tasksbasic = true,
    taskscancel = true,
    tasksscopes = true,
    threadsstacks = true,
    bytebuffer = true,
    bufferstate = true,
    sharedbytes = true,
    spanwrites = true,
    recordsdynamic = true,
    spanreads = true,
    librarybasics = true,
    storagebasics = true,
    storageprovider = true,
    cleanupfunctions = true,
    coreoperators = true,
    methodcleanups = true,
    ownerreinit = true,
    coreforms = true,
    tablesfrozen = true,
    tablespacked = true,
    tablespackedsemantics = true,
    serdejson = true,
    functionsmany = true,
    callsdeep = true,
    callsmany = true,
    stringsanchors = true,
    callsrecursive = true,
    callsResults = true,
    callsVariadic = true,
    callsSpread = true,
    callsProtected = true,
    protectedpacks = true,
    callstables = true,
    nonreturningbodies = true,
    callsXpcall = true,
    recordsaffineraise = true,
    modulesretry = true,
    errorsruntime = true,
    hostlibrary = true,
    benchforms = true,
    callarguments = true,
    qualifiedrecordcapture = true,
    assertvalue = true,
    iofiles = true,
    iostandard = true,
    reactorpipes = true,
    reactorfiles = true,
    tasksreactor = true,
    processexecute = true,
    processpopen = true,
    processhandle = true,
    runnerlowering = true,
    affineconstructors = true,
    absentffi = true,
    guestffi = true,
    ffiaggregates = true,
    runnerresiduals = true,
    spreadlibrary = true,
    libraryresults = true,
    processlines = true,
    processlayer = true,
    processexit = true,
    gcweak = true,
    gcfinalizers = true,
    gcoptions = true,
    gcend = true,
    gcexit = true,
    logwarn = true,
    gcwarn = true,
    gcraise = true,
    errorsuncaught = true,
    ostime = true,
    osfiles = true,
    filesystem = true,
    osremove = true,
    loadbinary = true,
    osfilesystem = true,
    loadsource = true,
    debuggetinfo = true
}
-- Shell statements a case's runs start with: the io and pool cases may hold
-- 64 descriptors, so a handle left open, or opened by a cancelled pool job,
-- would exhaust them; the bench entry measures fib(20), BENCH_SCALE adding to
-- 29.
local SETUP = {
    iofiles = "ulimit -n 64; ",
    reactorfiles = "ulimit -n 64; ",
    processpopen = "ulimit -n 64; ",
    processlines = "ulimit -n 64; ",
    processlayer = "ulimit -n 64; ",
    benchworkloads = "export BENCH_SCALE=-9; ",
    -- The C library catalog-ffi-aggregates calls, built where each run finds it.
    -- The VM's C declaration answers catalog-core-cdecl compares its own
    -- with, recorded in the directory it then runs in.
    corecdecl = (
        "d=$(mktemp -d '%s/cdecl.XXXXXX') && cd \"$d\" && NUPP_VM_AUTO_REBUILD=0 '%s/bin/nupp' run "
        .. "'%s/native/core/tests/core-cdecl-record.lua' \"$d/recorded\" > /dev/null "
        .. "&& export CDECL_DIFF=\"$d/recorded\"; "
    ):format(OUT, ROOT, ROOT),
    ffiaggregates = (
        "d=$(mktemp -d '%s/ffi.XXXXXX') && cc -dynamiclib -o \"$d/libnuppffiaggregates.dylib\" '%s' "
        .. "&& export DYLD_LIBRARY_PATH=\"$d\"; "
    ):format(OUT, TESTS .. "/ffi-aggregates.c")
}
-- The program arguments a case is run with, after the bridge's own.
-- The bench entry measures one case, writes its record as JSON on standard
-- output, and writes the record file it always writes nowhere.
local ARGUMENTS = {hostlibrary = "alpha beta", benchworkloads = "--case fib --json --out /dev/null"}
-- Cases whose program the core refuses to compile, and what it says.
local REFUSED = {}
-- What stress cases see in place of their full size under collection at
-- every allocation and interleaved collection, which keeps every freed
-- object as a tombstone: there a collection runs between any two
-- coroutines however few they are.
local STRESS_ENV = {threadsstacks = "NUPP_GUEST_COROUTINES=4000 ", tasksscopes = "NUPP_GUEST_TASKS=300 "}
-- These refuse at run time and must publish nothing: Lua 5.5 raises for the
-- first; the second's result is a boxed integer, which cannot be published.
local STATUS = {numericModZero = 6, numericOverflow = 5}
-- The cases reference Lua 5.5 also runs, as plain Lua or through a sibling
-- .lua twin; Nupp-only cases (records, ownership, Nupp modules) are not here.
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
    protectedpacks = "catalog-protected-packs",
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
    recordscallable = "catalog-records-callable",
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
    coroutineinheritance = "catalog-coroutine-inheritance",
    threadscalls = "catalog-threads-calls",
    threadsclose = "catalog-threads-close",
    threadsiterate = "catalog-threads-iterate",
    threadsmeta = "catalog-threads-meta",
    threadsmethods = "catalog-threads-methods",
    threadsstacks = "catalog-threads-stacks",
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
    pluckedarguments = "catalog-plucked-arguments",
    ownmanage = "catalog-own-manage",
    loopparameteralias = "catalog-loop-parameter-alias",
    namedarguments = "catalog-named-arguments",
    legacyglobals = "catalog-legacy-globals",
    gotocontinue = "catalog-goto-continue",
    derivedmembers = "catalog-derive",
    shortfunctions = "catalog-short-functions",
    modulesforward = "catalog-modules-forward",
    modulesself = "catalog-modules-self",
    modulesdynamic = "catalog-modules-dynamic",
    libraryvalues = "catalog-library-values",
    callsoverflow = "catalog-calls-overflow",
    callsmany = "catalog-calls-many",
    stringsanchors = "catalog-strings-anchors",
    callsrecursive = "catalog-calls-recursive",
    modulesretry = "catalog-modules-retry",
    errorsruntime = "catalog-errors-runtime",
    tablespackedsemantics = "catalog-tables-packed-semantics",
    stringdynamic = "catalog-string-dynamic",
    stringmetaonly = "catalog-string-metatable-only",
    stringmetatable = "catalog-string-metatable",
    stringmethods = "catalog-string-methods",
    stringgmatchvalues = "catalog-string-gmatch-values",
    callarguments = "catalog-call-arguments",
    assertvalue = "catalog-assert-value",
    iofiles = "catalog-io-files",
    iostandard = "catalog-io-standard",
    processexecute = "catalog-process-execute",
    processpopen = "catalog-process-popen",
    gcweak = "catalog-gc-weak",
    gcfinalizers = "catalog-gc-finalizers",
    gcoptions = "catalog-gc-options",
    gcwarn = "catalog-gc-warn",
    ostime = "catalog-os-time",
    osfiles = "catalog-os-files",
    debuggetinfo = "catalog-debug-getinfo"
}
-- The status a program ends with when an error no protected call takes
-- ends it, as the command line's: the bridge exits so once the program has
-- reported the error.
local RAISED = 1
-- Cases whose program ends through os.exit, or an error no protected call
-- takes, with this status, publishing no result: their bridge runs are
-- checked for the status and what they printed, output and errors
-- together, and their twins against reference Lua the same way; the ABI
-- guard, which runs the entry inside a test, is not run.
local EXITS = {processexit = 3, errorsuncaught = RAISED, gcexit = 4, gcraise = RAISED}
local EXITTWINS = {processexit = "catalog-process-exit", gcexit = "catalog-gc-exit"}

-- What a printed text must match: exactly this string, or this function's
-- test of it.
local function matches(expected, printed)
    if type(expected) == "function" then
        return expected(printed)
    end

    return printed == expected
end

-- Whether `printed` is the uncaught error's output with `report` last, a
-- Lua pattern.
local function reported(report)
    return function(printed)
        return printed:find("^before error\nprinted\t1\n" .. report .. "\n$") ~= nil
    end
end

-- Further runs of a case's program, with these arguments, that an error no
-- protected call takes ends: each ends with status RAISED, publishes
-- nothing and prints this (matches). The bench entry asked for a case it
-- does not have reports it as `nupp bench` does. The uncaught error's
-- objects are shown by their __tostring as lua.c's message handler shows
-- them, its "(error object is a table value)" for an answer that is no
-- string and the __tostring's own error for one it raises, and values with
-- no string form as the VM shows them.
local RAISES = {
    benchworkloads = {{"--case '^fib$' --json --out /dev/null", "nupp: no benchmark named ^fib$\n"}},
    errorsuncaught = {
        {"tostring", reported("nupp: custom text")},
        {"nonstring", reported("nupp: %(error object is a table value%)")},
        {"raising", reported("nupp: [^\n]*catalogerrorsuncaught%.nupp:42: inner")},
        {"named", reported("nupp: already named")},
        {"table", reported("nupp: table: 0x%x+")},
        {"nil", reported("nupp: nil")},
        {"module", reported("nupp: module 'nupp.core.absentmodule' not found:\n.*")}
    }
}
-- The twins that run commands: the reference interpreter they run under is
-- built with LUA_USE_POSIX (see `posixreference`).
local POSIXTWINS = {
    ["catalog-call-arguments"] = true,
    ["catalog-process-execute"] = true,
    ["catalog-process-popen"] = true,
    ["catalog-process-exit"] = true,
    -- os.tmpname: mkstemp under /tmp, where the generic build calls tmpnam.
    ["catalog-os-files"] = true
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

-- Wall seconds by phase and by case, for the summary the run ends with.
local timing = {phase = "setup", case = "setup", phases = {}, cases = {}}

local function account(seconds)
    timing.phases[timing.phase] = (timing.phases[timing.phase] or 0) + seconds
    timing.cases[timing.case] = (timing.cases[timing.case] or 0) + seconds
end

local function shell(command)
    local began = os.time()
    local pipe = assert(io.popen(command .. " 2>&1; echo __exit__:$?"))
    local output = pipe:read("*a")
    pipe:close()
    account(os.time() - began)

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

-- The bridge and guard runs are independent processes: each is queued with
-- what checks its result and starts at once in a pool of NUPP_GUEST_JOBS,
-- while the next case is selected; `drain` waits for the pool and checks
-- each result in queue order.
local JOBS = math.tointeger(tonumber(os.getenv("NUPP_GUEST_JOBS") or "")) or 8
local queue = {}
local pool = nil

local function defer(phase, command, done)
    local directory = timing.jobs
    if pool == nil then
        os.execute("rm -rf " .. quote(directory) .. " && mkdir -p " .. quote(directory))
        os.execute("mkfifo " .. quote(directory .. "/queue"))
        os.execute(
            (
                "(xargs -P %d -n 1 sh < %s > %s 2>&1; echo $? > %s) < /dev/null > /dev/null 2>&1 &"
            ):format(
                JOBS,
                quote(directory .. "/queue"),
                quote(directory .. "/pool.log"),
                quote(directory .. "/pool.status")
            )
        )
        pool = {directory = directory, writer = assert(io.open(directory .. "/queue", "w"))}
    end
    queue[#queue + 1] = {phase = phase, case = timing.case, done = done}
    local base = directory .. "/" .. #queue
    local file = assert(io.open(base .. ".sh", "wb"))
    file:write(
        "began=$(date +%s)\n{ " .. command .. "\n} > " .. quote(
            base .. ".out"
        ) .. " 2>&1\n" .. "echo $? $began $(date +%s) > " .. quote(base .. ".status") .. "\n"
    )
    file:close()
    pool.writer:write(base .. ".sh\n")
    pool.writer:flush()
end

local function drain()
    if pool == nil then
        return
    end
    local directory = pool.directory
    pool.writer:close()
    pool = nil
    timing.phase, timing.case = "jobs wait", "jobs"
    local done = quote(directory .. "/pool.status")
    shell("while [ ! -f " .. done .. " ]; do sleep 0.2; done")
    assert(read(directory .. "/pool.status") == "0\n", "job runner failed: " .. (read(directory .. "/pool.log") or ""))
    local jobs = queue
    queue = {}
    for index, job in ipairs(jobs) do
        local base = directory .. "/" .. index
        local code, began, ended = (assert(read(base .. ".status"), "job status missing")):match("^(%d+) (%d+) (%d+)")
        timing.phase, timing.case = job.phase, job.case
        account(tonumber(ended) - tonumber(began))
        job.done(tonumber(code), read(base .. ".out") or "")
    end
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
    local fixtures = guestbuild.fixtures()
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
    for _, fixture in ipairs(fixtures) do
        canonical[#canonical + 1] = fixture.path
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
        local directories = {}
        for _, fixture in ipairs(fixtures) do
            local path = base .. "/source/" .. fixture.module:gsub("%.", "/") .. ".nupp"
            local directory = assert(path:match("^(.*)/[^/]+$"))
            if not directories[directory] then
                os.execute("mkdir -p " .. quote(directory))
                directories[directory] = true
            end
            write(path, fixture.source)
            assert(read(path) == fixture.source, "staged guest source differs: " .. fixture.path)
        end
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

-- The reference interpreter `lua` names, rebuilt from its own sources with
-- LUA_USE_POSIX (`make posix`) under OUT, once: the oracle's is built
-- generic, where popen raises and os.execute answers raw wait statuses.
local posixbuilt = {}

local function posixreference(lua)
    if posixbuilt[lua] then
        return posixbuilt[lua]
    end
    local source = assert(lua:match("^(.*)/src/lua$"), "reference Lua is not a source tree's src/lua: " .. lua)
    local tree = OUT .. "/lua-posix"
    local built = tree .. "/src/lua"
    local version = OUT .. "/lua-posix.source"
    if read(version) ~= source or not read(built) then
        local status, output = shell(
            (
                "rm -rf %s && cp -R %s %s && cd %s/src && make clean > /dev/null && make posix"
            ):format(quote(tree), quote(source), quote(tree), quote(tree))
        )
        assert(status == 0, "POSIX reference Lua build failed: " .. output)
        write(version, source)
    end
    posixbuilt[lua] = built

    return built
end

-- Reference Lua 5.5 results for the numeric fixtures, as NaN-boxed words. A
-- sibling .lua file is a hand-written twin for fixtures Lua cannot parse.
local function oracle(lua, fixture)
    if POSIXTWINS[fixture] then
        lua = posixreference(lua)
    end
    local twin = read(TESTS .. "/" .. fixture .. ".lua")
    local source = twin
    if not source then
        local lines = {}
        for line in assert(read(TESTS .. "/" .. fixture .. ".nupp")):gmatch("[^\n]*\n?") do
            if not line:match("^module ") then
                line = line:gsub("^export const result = ", "return ")
                    :gsub("^export = ", "return ")
                    :gsub("^local (%w+): %w+ =", "local %1 =")
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
    -- The result is written last, after whatever the fixture prints.
    local result = output:match("([^\n]*)$")
    local kind, value = result:sub(1, 1), result:sub(2)
    if kind == "E" then
        return "error"
    elseif kind == "I" then
        local number = math.tointeger(tonumber(value))
        if number < -(1 << 47) or number >= (1 << 47) then
            return "integer"
        end
        return 0x7FFF000000000000 | (number & 0xFFFFFFFFFFFF)
    end
    -- In two halves: past 2^63 the VM's tonumber with a base answers a
    -- float, where Lua wraps.
    local high, low = tonumber(value:sub(1, 8), 16), tonumber(value:sub(9, 16), 16)
    assert(kind == "F" and high and low, ("%s: unexpected reference output %q"):format(fixture, output))
    local bits = (high << 32) | low
    if bits & 0x7FF0000000000000 == 0x7FF0000000000000 and bits & 0xFFFFFFFFFFFFF ~= 0 then
        return 0x7FF8000000000000
    end

    return bits
end

-- Code bytes by the words they encode: programs alike share an entry.
local codes = {}

local function bundleOf(selected, scratch)
    local code = codes[selected.words]
    if code == nil then
        local words = {}
        for index, word in ipairs(selected.words) do
            words[index] = u32(word)
        end
        code = table.concat(words)
        codes[selected.words] = code
    end
    local data = fromHex(selected.dataHex)
    assert(#data == selected.dataBytes, "data extent")

    return "NUPPCORE" .. u64(
        1
    ) .. u64(
        1
    ) .. u64(
        selected.entry
    ) .. u64(#code) .. u64(#data) .. u64(scratch) .. u64(1) .. u64(0) .. code .. data, #code, data
end

-- The generated case: six blocks of a hundred local functions, each
-- calling the one before it and adding its own number, so the program has
-- six hundred functions and the sum of 1 to 600 (180300) for its result.
local function functionsmany()
    local lines = {"module nupp.core.catalogfunctionsmany", "", "local total = 0"}
    for block = 0, 5 do
        lines[#lines + 1] = "do"
        for k = 1, 100 do
            local number = block * 100 + k
            local inner = k == 1 and "x" or ("f" .. (k - 1) .. "(x)")
            lines[
                #lines + 1
            ] = (
                "    local function f%d(x: integer): integer\n        return %s + %d\n    end"
            ):format(k, inner, number)
        end
        lines[#lines + 1] = "    total = total + f100(0)"
        lines[#lines + 1] = "end"
    end
    lines[#lines + 1] = "export const result = total"
    os.execute("mkdir -p " .. quote(OUT .. "/generated"))
    write(OUT .. "/generated/functionsmany.nupp", table.concat(lines, "\n") .. "\n")
end

-- The generated modules case: main requires 260 modules, each a chain of
-- sixteen functions its chunk calls into, so the chunks' depths sum to
-- 4,421 frames while no stack is deeper than 18 (main, a chunk and its
-- chain). Nothing in it calls back or recurses, so its catalog's frame
-- depth is that bound. Each source is staged where the guest project reads
-- it as well.
-- Its modules set their values with `export =`: an export table is published
-- through a library call, which the depth bound must assume may call back,
-- so named exports would bound its frames at the recursion limit instead.
local MANY_DEPTH = 18

local function modulesmany()
    local staged = ROOT .. "/build/core-guest-programs/source/nupp/core"
    os.execute("mkdir -p " .. quote(OUT .. "/generated") .. " " .. quote(staged))
    local main = {"module nupp.core.catalogmodulesmany", "", "-- Every generated module, required as main starts."}
    local names = guestbuild.modules("modulesmany")
    for index, name in ipairs(names) do
        local lines = {
            "module nupp.core.catalog" .. name,
            "",
            ("-- Generated module %d of %d, a chain of sixteen calls."):format(index, #names),
            "local function f1(): boolean",
            "    return true",
            "end"
        }
        for k = 2, 16 do
            lines[#lines + 1] = ("local function f%d(): boolean\n    return f%d()\nend"):format(k, k - 1)
        end
        lines[#lines + 1] = "export = f16()"
        local text = table.concat(lines, "\n") .. "\n"
        write(OUT .. "/generated/" .. name .. ".nupp", text)
        write(staged .. "/catalog" .. name .. ".nupp", text)
    end
    -- More modules than a chunk may have locals, so none is kept in one.
    main[#main + 1] = "local all = true"
    for _, name in ipairs(names) do
        main[#main + 1] = ("if not require(\"nupp.core.catalog%s\") then\n    all = false\nend"):format(name)
    end
    main[#main + 1] = "export = all"
    local text = table.concat(main, "\n") .. "\n"
    write(OUT .. "/generated/modulesmany.nupp", text)
    write(staged .. "/catalogmodulesmany.nupp", text)
end

-- Loads the producer and the guest build on first need, and prepares what
-- their builds read: the generated cases and the staged sources. A shard's
-- parent prepared them before it started the shard.
local function compiler()
    if producer == nil then
        guestbuild = require("nupp.core.guestbuild")
        producer = require("nupp.core.guestprogramproducer")
        if not os.getenv("NUPP_GUEST_SHARD") then
            functionsmany()
            modulesmany()
            stage()
        end
    end

    return producer, guestbuild
end

-- Runs the cases in NUPP_GUEST_SHARDS processes at once (default 4), each
-- selecting and running its share: selection is one process's work, so
-- shards are what spread it. Cases are dealt by what they cost last run; the
-- audited cases go to the first shard, which alone runs the audits. Answers
-- false when the cases are run here instead.
local function shards(selectedCases, bridge, guard)
    local count = math.tointeger(tonumber(os.getenv("NUPP_GUEST_SHARDS") or "")) or 4
    count = math.min(count, #selectedCases // 4)
    if count < 2 then
        return false
    end
    local cost = {}
    local listing = io.popen("cat " .. quote(OUT) .. "/costs/* 2>/dev/null")
    if listing then
        for line in listing:lines() do
            local name, seconds = line:match("^([^\t]+)\t([%d%.]+)$")
            if name then
                cost[name] = (cost[name] or 0) + tonumber(seconds)
            end
        end
        listing:close()
    end
    local audited = {}
    for _, item in ipairs(AUDITS) do
        audited[item[1]] = true
    end
    local names = {}
    for index, case in ipairs(selectedCases) do
        names[index] = case[1]
    end
    local members = shardplan.plan(names, cost, audited, count)
    count = #members
    if count < 2 then
        return false
    end
    os.execute("rm -f " .. quote(OUT) .. "/costs/*")
    -- The shards build from what this process prepares.
    compiler()
    local commands = {}
    for index = 1, count do
        local log = ("%s/shard-%d.log"):format(OUT, index)
        commands[
            index
        ] = (
            "NUPP_GUEST_SHARD=%d/%d NUPP_GUEST_AUDITS=%s NUPP_GUEST_BRIDGE=%s NUPP_GUEST_GUARD=%s NUPP_GUEST_JOBS=%d %s run run.lua %s > %s 2>&1 &"
        ):format(
            index,
            count,
            index == 1 and "1" or "0",
            quote(bridge),
            quote(guard),
            JOBS // count + 1,
            quote(ROOT .. "/bin/nupp"),
            table.concat(members[index], " "),
            quote(log)
        )
    end
    local started = os.time()
    shell("cd " .. quote(HERE) .. " && " .. table.concat(commands, "\n") .. "\nwait")
    local total, failed = checks, #failures
    for index = 1, count do
        local log = read(("%s/shard-%d.log"):format(OUT, index)) or ""
        local done, bad = log:match("shard result (%d+) (%d+)")
        for line in log:gmatch("[^\n]+") do
            if line:match("^FAIL ") then
                print(line)
            end
        end
        if done then
            total, failed = total + tonumber(done), failed + tonumber(bad)
            print(("shard %d: %d cases, %s checks, %s failed"):format(index, #members[index], done, bad))
        else
            failed = failed + 1
            print(("FAIL shard %d stopped before its result:\n%s"):format(index, log))
        end
    end
    print(("%d checks, %d failed, %ds in %d shards"):format(total, failed, os.time() - started, count))
    os.exit(failed == 0 and 0 or 1)
end

local function main()
    os.execute("mkdir -p " .. quote(OUT))
    -- Its parent wrote the generated case a shard reads.
    if not os.getenv("NUPP_GUEST_SHARD") then
        -- The directory the io cases write their files in, afresh.
        os.execute("rm -rf " .. quote(OUT .. "/temp") .. " && mkdir -p " .. quote(OUT .. "/temp"))
    end
    -- The cases named, in the order named, or every case.
    local selectedCases = {}
    if #arg == 0 then
        for _, case in ipairs(CASES) do
            selectedCases[#selectedCases + 1] = case
        end
    end
    for _, name in ipairs(arg) do
        for _, case in ipairs(CASES) do
            if case[1] == name then
                selectedCases[#selectedCases + 1] = case
            end
        end
    end
    -- A shard runs the cases it is given with the tools and sources its
    -- parent prepared (see `shards`).
    local shard = os.getenv("NUPP_GUEST_SHARD")
    local lua = os.getenv("NUPP_LUA_REFERENCE")
    if lua and not shard then
        timing.phase = "oracle"
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
        -- The twins that end through os.exit: their status and output.
        for name, fixture in pairs(EXITTWINS) do
            local status, printed = shell(
                GUEST_ENV .. quote(posixreference(lua)) .. " " .. quote(TESTS .. "/" .. fixture .. ".lua")
            )
            check(status == EXITS[name], ("oracle %s status %s"):format(name, tostring(status)))
            check(printedAs(name, printed), "oracle " .. name .. " printed output")
        end
    end
    -- Library names and texts share one id space in guesttexts: an id two
    -- of them claim prints the one in place of the other.
    local claimed = {}
    for name, id in (
        shard and "" or read(ROOT .. "/native/core/src/nupp/runtime/core/guesttexts.nupp")
    ):gmatch("export const ([%u_]+): uint64 = (%d+)ULL") do
        check(claimed[id] == nil, ("text id %s is both %s and %s"):format(id, tostring(claimed[id]), name))
        claimed[id] = name
    end
    local bridge, guard = os.getenv("NUPP_GUEST_BRIDGE"), os.getenv("NUPP_GUEST_GUARD")
    if not shard then
        timing.phase = "tools"
        bridge, guard = tools()
        if shards(selectedCases, bridge, guard) then
            return
        end
    end
    local started = os.time()
    timing.jobs = OUT .. "/jobs" .. (shard and "-" .. shard:match("^(%d+)") or "")
    -- Each case is selected as its turn comes, while the runs queued for
    -- the cases before it go on.
    local selections = {}
    local selectedSeconds = 0
    -- Each case's profile version, kept beside its selection.
    local versions = {}
    local kept = 0

    local function selection(name, mode)
        local began = os.time()
        timing.phase, timing.case = "select", name
        local parts = {name, mode, tostring(UNITS and SCRATCH or 131072), UNITS and "units" or "frozen"}
        local held, extra = selectioncache.lookup(ROOT, parts)
        if held and type(extra) == "table" and math.type(extra.version) == "integer" then
            selections[name .. "-" .. mode], versions[name] = held, extra.version
            kept = kept + 1
        else
            compiler()
            if UNITS then
                selections[
                    name .. "-" .. mode
                ] = producer.selectUnits(name, mode, tostring(SCRATCH), sharedcache.directory("kernels"))
            else
                selections[name .. "-" .. mode] = producer.select(name, mode, "131072")
            end
            versions[name] = guestbuild.version(name)
            selectioncache.keep(ROOT, parts, selections[name .. "-" .. mode], {version = versions[name]})
        end
        account(os.time() - began)
        selectedSeconds = selectedSeconds + os.time() - began

        return selections[name .. "-" .. mode]
    end

    local empty = OUT .. "/empty.bin"
    write(empty, "")

    -- Queues a bridge run; `after` gets what it printed, its output and
    -- errors together.
    local function bridgeRun(label, bundle, input, output, expectedStatus, environment, after)
        local kind = label:match(" (%a+)") or "bridge"
        local phase = label:match("^audit") and "audit bridge" or ("bridge " .. kind)
        local arguments = ARGUMENTS[label:match("^(%w+)")]
        defer(
            phase,
            (
                SETUP[label:match("^(%w+)")] or ""
            ) .. (
                environment or GUEST_ENV
            ) .. (
                "%s %s %s %s"
            ):format(
                quote(bridge),
                quote(bundle),
                quote(input),
                quote(output)
            ) .. (arguments and " " .. arguments or ""),
            function(status, printed)
                check((status == 0) == (expectedStatus == 0), label .. " bridge status")
                if after then
                    after(printed)
                end
            end
        )
    end

    local function guarded(label, bundle, input, highWater, expectedPath, status)
        if QUICK or HEAVY[label:match("^(%w+)")] then
            return
        end
        local env = (
            SETUP[label:match("^(%w+)")] or ""
        ) .. GUEST_ENV .. (
            "CORE_TEST_BUNDLE=%s CORE_TEST_INPUT=%s CORE_TEST_HIGH_WATER=%d "
        ):format(quote(bundle), quote(input), highWater)
        local arguments = ARGUMENTS[label:match("^(%w+)")]
        if arguments then
            env = env .. "CORE_TEST_ARGUMENTS=" .. quote(arguments) .. " "
        end
        local test = "abi::generated_entry_preserves_c_abi_and_output"
        if status then
            env = env .. "CORE_TEST_STATUS=" .. status .. " "
            test = "abi::generated_entry_returns_requested_status"
        else
            env = env .. "CORE_TEST_EXPECTED=" .. quote(expectedPath) .. " "
        end
        local phase = label:match("^audit") and "audit guard" or "guard"
        defer(phase, env .. quote(guard) .. " --ignored --exact " .. test .. " --test-threads=1", function(_, output)
            check(output:find("1 passed; 0 failed; 0 ignored;", 1, true) ~= nil, label .. " guard")
        end)
    end

    local sentinel = "refused guest operation left output unchanged"

    local function refuses(label, bundle, input)
        if QUICK then
            return
        end
        local output = OUT .. "/" .. label .. ".out"
        write(output, sentinel)
        bridgeRun(label, bundle, input, output, 1, nil, function()
            check(read(output) == sentinel, label .. " published nothing")
        end)
    end

    for _, case in ipairs(selectedCases) do
        local name, expectedWord = case[1], case[2]
        if REFUSED[name] then
            timing.case, timing.phase = name, "select"
            local began = os.time()
            compiler()
            local compiled, problem = pcall(guestbuild.program, name)
            account(os.time() - began)
            check(
                not compiled and tostring(problem):find(REFUSED[name]) ~= nil,
                name .. " refusal: " .. tostring(problem)
            )
        end
        for _, mode in ipairs(REFUSED[name] and {} or MODES) do
            local label = name .. "-" .. mode
            timing.case = name
            local selected = selection(name, mode)
            check(selected.caseName == name and selected.mode == mode, label .. " identity")
            -- The binary chunks it loads, where it reads them.
            for _, chunk in ipairs(selected.chunks or {}) do
                write(OUT .. "/temp/" .. chunk.name .. ".chunk", fromHex(chunk.hex))
            end
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
            local profile = versions[name]
            local modules = (name == "modulePair" or name == "moduleTriple") and 2 or 1
            check(version == (profile >= 3 and profile or modules), label .. " descriptor version")
            local bundle = OUT .. "/" .. label .. ".bundle"
            write(bundle, bundleBytes)
            -- Each in every collection mode the case runs in.
            local modes = {{"", empty}}
            if RAISES[name] and UNITS and STRESSED and STRESS[name] then
                local stress = OUT .. "/" .. label .. "-raises-stress.bin"
                write(stress, u64(-1) .. u64(0) .. u64(1))
                local stepped = OUT .. "/" .. label .. "-raises-interleaved.bin"
                write(stepped, u64(-1) .. u64(0) .. u64(2))
                modes[#modes + 1] = {" stress", stress}
                modes[#modes + 1] = {" interleaved", stepped}
            end
            for index, raise in ipairs(RAISES[name] or {}) do
                for _, run in ipairs(modes) do
                    local output = OUT .. "/" .. label .. "-raises" .. index .. run[1]:gsub(" ", "-") .. ".out"
                    local raised = ("%s%s raises (%s)"):format(label, run[1], raise[1])
                    write(output, sentinel)
                    defer(
                        "bridge raise",
                        (
                            SETUP[name] or ""
                        ) .. GUEST_ENV .. (
                            "%s %s %s %s %s"
                        ):format(quote(bridge), quote(bundle), quote(run[2]), quote(output), raise[1]),
                        function(status, printed)
                            check(status == RAISED, ("%s: exit status %s"):format(raised, tostring(status)))
                            check(matches(raise[2], printed), raised .. ": printed " .. printed)
                            check(read(output) == sentinel, raised .. ": published nothing")
                        end
                    )
                end
            end
            if STATUS[name] then
                refuses(label, bundle, empty)
                guarded(label, bundle, empty, highWater, nil, STATUS[name])
            elseif EXITS[name] then
                -- It ends through os.exit: its status and what it printed,
                -- in each collection mode, and no result published.
                local runs = {{"", empty}}
                if UNITS and STRESSED and STRESS[name] then
                    local stress = OUT .. "/" .. label .. "-stress.bin"
                    write(stress, u64(-1) .. u64(0) .. u64(1))
                    local stepped = OUT .. "/" .. label .. "-interleaved.bin"
                    write(stepped, u64(-1) .. u64(0) .. u64(2))
                    runs[#runs + 1] = {" stress", stress}
                    runs[#runs + 1] = {" interleaved", stepped}
                end
                for _, run in ipairs(runs) do
                    local output = OUT .. "/" .. label .. run[1]:gsub(" ", "-") .. ".out"
                    write(output, sentinel)
                    defer(
                        "bridge exit",
                        (
                            SETUP[name] or ""
                        ) .. GUEST_ENV .. (
                            "%s %s %s %s"
                        ):format(quote(bridge), quote(bundle), quote(run[2]), quote(output)),
                        function(status, printed)
                            check(
                                status == EXITS[name],
                                ("%s%s exit status %s"):format(label, run[1], tostring(status))
                            )
                            check(printedAs(name, printed), label .. run[1] .. " printed output")
                            check(read(output) == sentinel, label .. run[1] .. " published nothing")
                        end
                    )
                end
            else
                local expected = OUT .. "/" .. label .. ".expected"
                write(expected, u64(expectedWord))
                local output = OUT .. "/" .. label .. ".out"
                os.remove(output)
                bridgeRun(label, bundle, empty, output, 0, nil, function(printed)
                    check(read(output) == u64(expectedWord), ("%s result %016x"):format(label, expectedWord))
                    check(printedAs(name, printed), label .. " printed output")
                end)
                guarded(label, bundle, empty, highWater, expected)
                -- The same result with a collection at every allocation.
                if UNITS and STRESSED and (STRESS[name] == true or STRESS[name] == mode) then
                    local input = OUT .. "/" .. label .. "-stress.bin"
                    write(input, u64(-1) .. u64(0) .. u64(1))
                    local stressed = OUT .. "/" .. label .. "-stress.out"
                    os.remove(stressed)
                    local environment = STRESS_ENV[name] and GUEST_ENV .. STRESS_ENV[name]
                    bridgeRun(label .. " stress", bundle, input, stressed, 0, environment, function(again)
                        check(printedAs(name, again), label .. " printed output under collect-at-every-allocation")
                        check(read(stressed) == u64(expectedWord), label .. " result under collect-at-every-allocation")
                    end)
                    -- And with interleaved incremental collection, the
                    -- oracle checking every cycle (a failure is status 1001).
                    local stepped = OUT .. "/" .. label .. "-interleaved.bin"
                    write(stepped, u64(-1) .. u64(0) .. u64(2))
                    local steppedOut = OUT .. "/" .. label .. "-interleaved.out"
                    os.remove(steppedOut)
                    bridgeRun(label .. " interleaved", bundle, stepped, steppedOut, 0, environment, function(
                        printedStepped
                    )
                        check(printedAs(name, printedStepped), label .. " printed output under interleaved collection")
                        check(read(steppedOut) == u64(expectedWord), label .. " result under interleaved collection")
                    end)
                end
                -- The workloads read BENCH_SCALE at run time; scale 2 has its own
                -- checksums (bench/vm/workloads.bench.nupp).
                if SCALED[name] and label:match("%-normal$") then
                    local scaled = OUT .. "/" .. label .. "-scale2.out"
                    os.remove(scaled)
                    bridgeRun(label .. " scale 2", bundle, empty, scaled, 0, GUEST_ENV .. "BENCH_SCALE=2 ", function()
                        check(read(scaled) == u64(SCALED[name]), label .. " result at BENCH_SCALE=2")
                    end)
                end
                defer(
                    "guard short",
                    (
                        "CORE_TEST_BUNDLE=%s CORE_TEST_INPUT=%s CORE_TEST_HIGH_WATER=0 %s --ignored --exact abi::generated_entry_refuses_short_regions --test-threads=1"
                    ):format(quote(bundle), quote(empty), quote(guard)),
                    function(_, short)
                        check(
                            short:find("1 passed; 0 failed; 0 ignored;", 1, true) ~= nil,
                            label .. " short regions refused"
                        )
                    end
                )
                local body = selected.programs[#selected.programs]
                if name:match("^numeric") then
                    local loop = false
                    for _, functionBody in ipairs(selected.programs) do
                        local seen, backward = {}, false
                        for _, instruction in ipairs(functionBody.instructions) do
                            seen[instruction[1]] = true
                            backward = backward or instruction[1] == "Jmp" and instruction[2] < 0
                        end
                        loop = loop or seen.Le and seen.Add and seen.JmpIf and backward
                    end
                    check(loop, label .. " numeric loop shape")
                end
                if name == "callarguments" or name == "threadsclose" then
                    local wordBytes, diagnosticBytes = 8, 24
                    local v3Bytes, formatWord, rowsWord, countWord = 152, 16, 17, 18
                    local diagnosticFormat, legacyFormat, methodFlag, tailFlag = 4, 3, 1, 2
                    local rows, count = get64(data, rowsWord * wordBytes), get64(data, countWord * wordBytes)
                    check(get64(data, 4 * wordBytes) == v3Bytes, label .. " V3 record offset")
                    check(
                        get64(data, formatWord * wordBytes) == diagnosticFormat and count > 0,
                        label .. " diagnostic format"
                    )
                    local prefix = bundleBytes:sub(1, 72 + codeBytes)

                    local function invalid(suffix, offset, bytes)
                        local path = OUT .. "/" .. label .. "-diagnostic-" .. suffix .. ".bundle"
                        write(path, prefix .. put(data, offset, bytes))
                        guarded(label .. " diagnostic " .. suffix, path, empty, highWater, nil, 1)
                    end

                    invalid("format", formatWord * wordBytes, u64(diagnosticFormat + 1))
                    invalid("offset", rowsWord * wordBytes, u64(rows + wordBytes))
                    invalid("count", countWord * wordBytes, u64(count - 1))
                    invalid("method", rows, u64(methodFlag + tailFlag + 1))
                    invalid("forward", rows + 2 * wordBytes, u64(3))
                    invalid("name-metadata", rows + wordBytes, u64(v3Bytes))
                    local named
                    for i = 0, count - 1 do
                        local nameOffset = get64(data, rows + i * diagnosticBytes + wordBytes)
                        if nameOffset ~= 0 then
                            named = nameOffset
                            break
                        end
                    end
                    check(named ~= nil, label .. " named diagnostic")
                    invalid("name-bound", named, u64(65537))
                    invalid("name-terminator", named + wordBytes + get64(data, named), string.char(1))
                    local legacy = {data:sub(1, rows)}
                    for i = 0, count - 1 do
                        local offset = rows + i * diagnosticBytes
                        legacy[#legacy + 1] = u64(get64(data, offset) % (methodFlag + 1))
                        legacy[#legacy + 1] = data:sub(offset + wordBytes + 1, offset + diagnosticBytes)
                    end
                    legacy[#legacy + 1] = data:sub(rows + count * diagnosticBytes + 1)
                    local legacyData = put(table.concat(legacy), formatWord * wordBytes, u64(legacyFormat))
                    local legacyPath = OUT .. "/" .. label .. "-diagnostic-legacy.bundle"
                    write(legacyPath, prefix .. legacyData)
                    guarded(label .. " diagnostic legacy", legacyPath, empty, highWater, expected, nil)
                    local invalidLegacy = OUT .. "/" .. label .. "-diagnostic-legacy-tail.bundle"
                    write(invalidLegacy, prefix .. put(legacyData, rows, u64(tailFlag)))
                    guarded(label .. " diagnostic legacy tail", invalidLegacy, empty, highWater, nil, 1)
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
                if name == "modulesmany" then
                    -- Its frame depth is its deepest stack, not the chunks'
                    -- depths summed; the catalog admits a depth up to the
                    -- recursion bound, 200,000, and refuses one past it.
                    local depth = 11 * 8
                    check(get64(data, depth) == MANY_DEPTH, label .. " frame depth is the deepest stack")
                    local prefix = bundleBytes:sub(1, 72 + codeBytes)
                    local bound = OUT .. "/" .. label .. "-depth-bound.bundle"
                    write(bound, prefix .. put(data, depth, u64(200000)))
                    guarded(label .. " depth at the bound", bound, empty, highWater, expected)
                    local past = OUT .. "/" .. label .. "-depth-past.bundle"
                    write(past, prefix .. put(data, depth, u64(200001)))
                    guarded(label .. " depth past the bound", past, empty, highWater, nil, 1)
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

    print(
        (
            "selected %d programs in %ds, %d kept from the shared store"
        ):format(#selectedCases * #MODES, selectedSeconds, kept)
    )
    drain()
    print(("primary checks done at %ds"):format(os.time() - started))
    -- Supplemental lifecycle audits wrap selected primary programs.
    for _, mode in ipairs(MODES) do
        if QUICK or os.getenv("NUPP_GUEST_AUDITS") == "0" then
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
                timing.case, timing.phase = "audit " .. name, "audit select"
                local began = os.time()
                compiler()
                local selected = UNITS
                    and producer.selectUnits(name, mode, tostring(SCRATCH), sharedcache.directory("kernels"), scenario)
                    or producer.select(name, mode, "131072", scenario)
                account(os.time() - began)
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
                    bridgeRun(label, bundle, empty, output, 0, nil, function()
                        check(read(output) == u64(expectedWord), label .. " result")
                    end)
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
    drain()
    -- What each case cost, which the next run's shards are balanced by.
    if shard then
        local costs = {}
        for name, seconds in pairs(timing.cases) do
            costs[#costs + 1] = name .. "\t" .. tostring(seconds)
        end
        os.execute("mkdir -p " .. quote(OUT .. "/costs"))
        write(OUT .. "/costs/" .. shard:match("^(%d+)"), table.concat(costs, "\n") .. "\n")
    end

    local function summary(title, map, limit)
        local names = {}
        for key in pairs(map) do
            names[#names + 1] = key
        end
        table.sort(names, function(a, b)
            return map[a] > map[b]
        end)
        print(title)
        for index = 1, math.min(limit, #names) do
            print(("  %8.1fs  %s"):format(map[names[index]], names[index]))
        end
    end

    summary("seconds by phase", timing.phases, 100)
    summary("slowest cases", timing.cases, 12)
    summary("processor seconds in selection", guestbuild and guestbuild.timings or {}, 100)
    print(("%d checks, %d failed, %ds"):format(checks, #failures, os.time() - started))
    if shard then
        print(("shard result %d %d"):format(checks, #failures))
    end
    os.exit(#failures == 0 and 0 or 1)
end

main()
