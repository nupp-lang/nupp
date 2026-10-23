-- Performance and capacity budgets, held by quantities that do not move with load.
--
-- A budget that fails on a busy runner is worse than none: it teaches everybody to
-- re-run until green, and then it no longer holds anything. So nothing here times a
-- command. Each case measures something a regression moves and a loaded machine does
-- not -- how many directories a walk lists, how many modules an edit recompiles, how
-- many bytecode instructions a kernel compiles to, how many bytes the checker
-- allocates per module as a project grows -- and holds it under a ceiling with room
-- in it. A ceiling is a decision, not a snapshot: raising one is allowed, and the
-- failure message says what moved so that raising it is a choice somebody makes on
-- purpose.
--
-- The wall-clock budgets beside these are tracked rather than enforced, because only a
-- quiet machine can say whether they held. These are medians on an Apple M5 Pro when
-- this suite was written, with the budget a regression would have to cross in
-- brackets; `bench/`, `nupp bench` and the measurements workflow re-measure them:
--
--   `nupp --version` through bin/nupp        110 ms, 16 ms of it the compiler  [150 ms]
--   a stamped hello-world binary, warm       4.4 ms                            [10 ms]
--   unchanged whole-project check, 463 mods  0.33 s                            [0.5 s]
--   one module body edited, then check       0.6 s                             [1 s]
--   an export of a 55-importer module edited 13.5 s                            [20 s]
--   cold whole-project check                 19 s, 2.3 GB peak, 0.9 GB live    [25 s, 3 GB]
--   language server initialize               0.3 s                             [0.6 s]
--   language server edit to diagnostics      15-250 ms; hover under 10 ms      [500 ms]
--
-- Each is kept by a deterministic case where one exists: the walk budget keeps the
-- unchanged check and the server's initialize near their floor, the recompile count
-- keeps an edit cheap, the allocation budget keeps a check linear in the project, and
-- the bytecode budget keeps the benchmarks' kernels what was measured.
local json = require("testjson")
local test = require("nupp.test")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
if HERE:sub(1, 1) ~= "/" and not HERE:match("^%a:[/\\]") then
    local pipe = assert(io.popen("pwd"))
    HERE = assert(pipe:read("*l")) .. "/" .. HERE
    pipe:close()
end
local ROOT = HERE .. "/.."
local NUPP = ROOT .. "/bin/nupp"

local function run(dir, argv)
    local pipe = assert(io.popen(("cd '%s' && '%s' %s 2>/dev/null"):format(dir, NUPP, argv)))
    local out = pipe:read("*a")
    pipe:close()

    return out
end

local function readFile(path)
    local file = io.open(path, "rb")
    if not file then
        return nil
    end
    local text = file:read("*a")
    file:close()

    return text
end

local function writeFile(path, text)
    local parent = assert(path:match("^(.*)[/\\]"))
    assert(os.execute("mkdir -p '" .. parent .. "'") == 0)
    local file = assert(io.open(path, "wb"))
    file:write(text)
    file:close()
end

local function temporary()
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p '" .. dir .. "'") == 0)

    return dir
end

local M = {}

-- The project walk visits the checkout's own root, and the output directory sits in
-- it. A native build keeps a Cargo target there: in a checkout that had built one, the
-- walk listed a hundred and forty thousand entries to keep four hundred sources, and
-- that was four fifths of an unchanged `nupp check`. The files under it were always
-- dropped afterwards, so the answer never showed the cost; what shows it is which
-- directories were listed.
function M.theProjectWalkNeverListsTheOutputDirectory()
    local envMod = require("nupp.compiler.project.env")
    local files = require("nupp.io.files")
    local dir = temporary()
    writeFile(dir .. "/src/main.nupp", "module main\nexport = true\n")
    writeFile(dir .. "/top.nupp", "module top\nexport = true\n")
    writeFile(dir .. "/build/rust/target/debug/deps/stray.nupp", "module stray\nexport = true\n")
    writeFile(dir .. "/build/generated/tool/made.nupp", "module made\nexport = true\n")

    local listed = {}
    local list = files.list
    files.list = function(path, ...)
        listed[#listed + 1] = path
        return list(path, ...)
    end
    local ok, result = pcall(function()
        local env = envMod.new(dir, {config = {include = {"src"}}})

        return {project = envMod.listProjectFiles(env), sources = envMod.listSourceFiles(env)}
    end)
    files.list = list
    assert(ok, result)
    os.execute("rm -rf '" .. dir .. "'")

    local outDir = dir .. "/build"
    for _, path in ipairs(listed) do
        assert(
            path ~= outDir and path:sub(1, #outDir + 1) ~= outDir .. "/",
            "the project walk listed " .. path .. " under the output directory"
        )
    end
    assert(#listed > 0, "the walk was observed")
    local function has(list, suffix)
        for _, path in ipairs(list) do
            if path:sub(-#suffix) == suffix then
                return true
            end
        end

        return false
    end
    assert(has(result.project, "/src/main.nupp") and has(result.project, "/top.nupp"), "the sources are listed")
    assert(has(result.sources, "/src/main.nupp"), "the include root is listed")
    assert(not has(result.project, "stray.nupp") and not has(result.sources, "stray.nupp"), "build output is not")
end

-- VM bytecode for the benchmark programs, as `nupp bc` lists the image each lowers
-- to. Instruction counts are the compiler's output and nothing else, so a lowering
-- that starts spending more of them shows here on any machine, where the benchmark
-- itself needs a quiet one to show it.
--
-- Each ceiling is about a tenth above what the file lowered to at the commit that
-- set it. An edit to a benchmark moves its own numbers, and the message says which.
--
-- aos and soa moved on 2026-10-22, with no edit to either file: each declares a
-- struct, and since 765713656 a struct's declaration carries its C layout,
-- built once in the module chunk (about 210 instructions for aos's Particle),
-- not in the timed functions.
local BYTECODE = {
    ["aos"] = 508,
    ["frames"] = 45,
    ["optparser"] = 685,
    ["presize"] = 108,
    ["soa"] = 818,
    ["trivia-record"] = 272,
}

function M.theBenchmarkProgramsStayWithinTheirBytecodeBudgets()
    -- The listing is of the VM image, which only the VM-hosted launcher lowers to.
    local selected = io.open(ROOT .. "/.nupp/vm-cli/current", "rb")
    if selected then
        selected:close()
    end
    test.requireCapability("vm-hosted-cli", os.getenv("NUPP_VM_CLI_IMAGE") ~= nil or selected ~= nil)
    local names = {}
    for name in pairs(BYTECODE) do
        names[#names + 1] = name
    end
    table.sort(names)
    local failures = {}
    for _, name in ipairs(names) do
        local budget = BYTECODE[name]
        local file = "bench/" .. name .. ".bench.nupp"
        local out = run(ROOT, "bc --json " .. file)
        local ok, report = pcall(json.decode, out)
        assert(ok and type(report) == "table" and report.functions, file .. " did not report bytecode: " .. out)
        local total = 0
        for _, fn in ipairs(report.functions) do
            total = total + #fn.instructions
        end
        if total > budget then
            failures[#failures + 1] = ("%s compiles to %d instructions, over its budget of %d"):format(
                file,
                total,
                budget
            )
        end
    end
    assert(#failures == 0, table.concat(failures, "\n"))
end

--- A project of `count` modules where module i requires i - 1, i // 2 and i // 3:
--- a graph as deep as it is long, with a fan-in the size of a real one.
local function moduleGraph(dir, count)
    for i = 0, count - 1 do
        local seen, lines = {}, {("module m%d"):format(i), ""}
        for _, j in ipairs({i - 1, math.floor(i / 2), math.floor(i / 3)}) do
            if j >= 0 and j < i and not seen[j] then
                seen[j] = true
                lines[#lines + 1] = ("const d%d = require(\"m%d\")"):format(j, j)
            end
        end
        lines[#lines + 1] = ""
        lines[#lines + 1] = ("export record R%d\n    a: number\n    b: string\nend\n"):format(i)
        lines[#lines + 1] = ("export function make(a: number): R%d\n    return new R%d(a = a, b = \"m%d\")\nend\n"):format(
            i,
            i,
            i
        )
        lines[#lines + 1] = "export function score(x: number): number"
        lines[#lines + 1] = "    local total = x"
        for j in pairs(seen) do
            lines[#lines + 1] = ("    total = total + d%d.score(x - 1) + d%d.make(x).a"):format(j, j)
        end
        lines[#lines + 1] = "    return total\nend\n"
        writeFile(("%s/src/m%d.nupp"):format(dir, i), table.concat(lines, "\n"))
    end
    writeFile(dir .. "/nupp.lua", 'return {include = {"src"}}\n')
end

--- Bytes the checker allocates checking every module of a `count`-module graph, with
--- the collector held so that what is counted is what was allocated.
local function checkerAllocation(count)
    local envMod = require("nupp.compiler.project.env")
    local parser = require("nupp.compiler.syntax.parser")
    local check = require("nupp.compiler.check")
    local dir = temporary()
    moduleGraph(dir, count)
    local env = envMod.new(dir, {config = {include = {"src"}}})
    collectgarbage()
    collectgarbage()
    collectgarbage("stop")
    local ok, result = pcall(function()
        local before = collectgarbage("count")
        for i = 0, count - 1 do
            local path = ("%s/src/m%d.nupp"):format(dir, i)
            local diags = check.check(parser.parse(assert(readFile(path)), path), path, env)
            assert(#diags == 0, path .. ": " .. tostring(diags[1] and diags[1].msg))
        end

        return (collectgarbage("count") - before) * 1024
    end)
    collectgarbage("restart")
    os.execute("rm -rf '" .. dir .. "'")
    assert(ok, result)

    return result
end

-- What checking a module costs in allocation, and that the cost stays per module as a
-- project grows. Quadratic work in the checker -- a scan over every module's exports
-- per reference, a list rebuilt per declaration -- shows as the larger project
-- allocating more per module, whatever the machine is doing. About 1.15 MB a module
-- at ten modules and 1.3 MB at forty when these were set; quadratic growth would be
-- four times the per-module figure at forty, and linear growth is none.
-- The VM counts its own object layout -- a 32-byte header per object, tables carrying
-- their insertion order -- so the same work measures about 2.5 MB a module there; its
-- budget keeps the same headroom over what it measures. The growth bound is the same.
local ALLOCATION_PER_MODULE = (rawget(_G, "__nupp_load_image") and 3.75 or 2) * 1024 * 1024
local ALLOCATION_GROWTH = 1.6

function M.theCheckerAllocatesPerModuleNotPerProject()
    local small = checkerAllocation(10) / 10
    local large = checkerAllocation(40) / 40
    assert(
        large <= ALLOCATION_PER_MODULE,
        ("checking allocates %.0f KB a module, over the budget of %.0f KB"):format(
            large / 1024,
            ALLOCATION_PER_MODULE / 1024
        )
    )
    assert(
        large / small <= ALLOCATION_GROWTH,
        ("a module costs %.0f KB to check in a project of ten and %.0f KB in a project of forty: "
            .. "the checker's work is growing with the project"):format(small / 1024, large / 1024)
    )
end

--- `nupp check --json`'s count of modules it had to check again.
local function compiledModules(dir)
    local out = run(dir, "check --json")
    local ok, report = pcall(json.decode, out)
    assert(ok and type(report) == "table" and report.timing, "check did not report timing: " .. out)
    assert(report.ok, "check failed: " .. out)

    return report.timing.compiledModules
end

-- What keeps an edit cheap is how little it makes the checker redo: a function body
-- edited is one module, and an export edited is that module and the modules that import
-- it, with the ones above them cut off because their own exports did not move. Either
-- count growing means an edit costs more on every project, and the count moves where a
-- timing on a busy runner would not.
function M.anEditRechecksOnlyWhatItCanReach()
    local dir = temporary()
    moduleGraph(dir, 12)
    local main = dir .. "/src/m0.nupp"
    local original = assert(readFile(main))
    local cold = compiledModules(dir)
    local unchanged = compiledModules(dir)
    writeFile(main, original .. "\nlocal function private(): number\n    return 1\nend\n_ = private\n")
    local body = compiledModules(dir)
    writeFile(main, original .. "\nexport function added(): number\n    return 2\nend\n")
    local interface = compiledModules(dir)
    os.execute("rm -rf '" .. dir .. "'")

    assert(cold == 12, "the first check checks every module: " .. tostring(cold))
    assert(unchanged == 0, "an unchanged project checks nothing: " .. tostring(unchanged))
    assert(body == 1, "a private edit checks one module: " .. tostring(body))
    -- m0 is imported by m1 and m2 and by nothing else directly.
    assert(interface == 3, "an export edit checks the module and its two importers: " .. tostring(interface))
end

-- What a program stamped into a binary weighs. The host is LuaJIT and the base runtime,
-- and a hello-world payload is a few hundred bytes, so the whole is about 1.2 MB on
-- arm64 macOS. The ceiling is loose on purpose -- hosts differ by platform -- and is
-- there for the regression that matters: something large, the code generator or a
-- facility nobody selected, travelling in every binary.
local STAMPED_BINARY_BYTES = 3 * 1024 * 1024

function M.aStampedHelloWorldStaysSmall()
    local dir = temporary()
    writeFile(
        dir .. "/nupp.lua",
        'return {include = {"src"}, build = {default = "app", targets = {app = {\n'
            .. '   kind = "binary", stub = "nupp", entries = {"main"}, outDir = "build",\n}}}}\n'
    )
    writeFile(dir .. "/src/main.nupp", 'print("hello")\n')
    local out = run(dir, "build")
    local windows = package.config:sub(1, 1) == "\\"
    local binary = readFile(dir .. (windows and "/build/app.exe" or "/build/app"))
    os.execute("rm -rf '" .. dir .. "'")
    assert(binary, "the hello-world binary was not built: " .. out)
    assert(
        #binary <= STAMPED_BINARY_BYTES,
        ("a stamped hello world is %d bytes, over the budget of %d"):format(#binary, STAMPED_BINARY_BYTES)
    )
end

-- A function with vector instructions runs only compiled, so a program holding
-- one is linked with the code generator; the runtime a hello world gets has none.
function M.aVectorProgramRunsFromItsBinary()
    local dir = temporary()
    writeFile(
        dir .. "/nupp.lua",
        'return {include = {"src"}, build = {default = "app", targets = {app = {\n'
            .. '   kind = "binary", stub = "nupp", entries = {"main"}, outDir = "build",\n}}}}\n'
    )
    writeFile(
        dir .. "/src/main.nupp",
        [[
local array = require("nupp.mem.array")
local span = require("nupp.mem.span")
local simd = require("nupp.simd")

local function count(borrows text: span.Span<uint8>, needle: uint32): uint32
    local found: uint32 = 0
    local cursor: uint32 = 0
    if species = simd.vectors(array.uint8) then
        while cursor + species.lanes <= #text do
            found = found + (species:load(text, cursor + 1) == needle):count()
            cursor = cursor + species.lanes
        end
    end
    while cursor < #text do
        if text[cursor + 1] == needle then
            found = found + 1
        end
        cursor = cursor + 1
    end
    return found
end

const bytes = array.bytes(70)
const w = bytes:write()
for i = 1, 70 do
    w[i] = i % 2 == 0 and 7 or 1
end
nupp.drop(w)
print(count(bytes:read(), 7))
]]
    )
    local out = run(dir, "build")
    local windows = package.config:sub(1, 1) == "\\"
    local binary = dir .. (windows and "/build/app.exe" or "/build/app")
    local built = readFile(binary) ~= nil
    local printed = ""
    if built then
        local pipe = assert(io.popen("'" .. binary .. "' 2>&1"))
        printed = pipe:read("*a")
        pipe:close()
    end
    os.execute("rm -rf '" .. dir .. "'")
    assert(built, "the vector program was not built: " .. out)
    assert(printed:match("^35%s*$"), "the vector program counted its needles: " .. printed)
end

return M
