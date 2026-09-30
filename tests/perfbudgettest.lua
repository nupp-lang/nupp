-- Performance and capacity budgets, held by quantities that do not move with load.
--
-- A budget that fails on a busy runner is worse than none: it teaches everybody to
-- re-run until green, and then it no longer holds anything. So nothing here times a
-- command. Each case measures something a regression moves and a loaded machine does
-- not -- how many directories a walk lists, how many modules an edit recompiles, how
-- many bytecode instructions a kernel compiles to, how much generated Lua the compiler
-- writes per byte of source, how many bytes the checker allocates per module as a
-- project grows -- and holds it under a ceiling with room in it. A ceiling is a
-- decision, not a snapshot: raising one is allowed, and the failure message says what
-- moved so that raising it is a choice somebody makes on purpose.
--
-- The wall-clock budgets beside these are tracked rather than enforced, because only a
-- quiet machine can say whether they held. They were measured on an Apple M5 Pro at
-- the commit that introduced this suite, and `bench/` and the measurements workflow are
-- where they are re-measured:
--
--   `nupp --version` through bin/nupp                 about 120 ms (15 ms of it the compiler)
--   unchanged whole-project `nupp check` (463 modules) about 0.4 s
--   one module body edited, whole-project check       about 0.8 s
--   an exported type of a 55-importer module edited   about 14 s
--   cold whole-project check, no cache                about 19 s, 2.3 GB peak
--   language server: edit to diagnostics, warm        under 250 ms; hover under 10 ms
--
-- Each is kept by a deterministic case below where one exists: the walk budget is what
-- keeps the unchanged check near its floor, the recompile count is what keeps the body
-- edit cheap, and the launcher's toolchain questions are held in toolchaintest.
local json = require("testjson")

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

-- LuaJIT bytecode for the benchmark programs, at the level `nupp bench` runs them.
-- Instruction counts are the compiler's output and nothing else, so a lowering that
-- starts spending more of them shows here on any machine, where the benchmark itself
-- needs a quiet one to show it. Instructions inside loops are held separately because
-- they are the ones a benchmark pays for, and a loop LuaJIT cannot record is held at
-- none: that one never compiles, and nothing else notices.
--
-- Each ceiling is about a tenth above what the file compiles to at the commit that set
-- it. An edit to a benchmark moves its own numbers, and the message says which.
local BYTECODE = {
    ["aos"] = {total = 266, loop = 80},
    ["frames"] = {total = 116, loop = 23},
    ["json-lpeg"] = {total = 795, loop = 124},
    ["nupp-lpeg-shapes"] = {total = 398, loop = 13},
    ["optparser"] = {total = 548, loop = 125},
    ["peg-kernels"] = {total = 318, loop = 30},
    ["peg-lpeg"] = {total = 540, loop = 14},
    ["peg-result-packs"] = {total = 202, loop = 26},
    ["presize"] = {total = 126, loop = 10},
    ["soa"] = {total = 785, loop = 182},
    ["trivia-record"] = {total = 232, loop = 49},
}

function M.theBenchmarkProgramsStayWithinTheirBytecodeBudgets()
    local names = {}
    for name in pairs(BYTECODE) do
        names[#names + 1] = name
    end
    table.sort(names)
    local failures = {}
    for _, name in ipairs(names) do
        local budget = BYTECODE[name]
        local file = "bench/" .. name .. ".bench.nupp"
        local out = run(ROOT, "bc -O1 --json " .. file)
        local ok, report = pcall(json.decode, out)
        assert(ok and type(report) == "table" and report.functions, file .. " did not report bytecode: " .. out)
        local total, loop, unrecordable = 0, 0, {}
        for _, fn in ipairs(report.functions) do
            for _, instruction in ipairs(fn.instructions) do
                total = total + 1
                if instruction.inLoop then
                    loop = loop + 1
                    if instruction.unrecordable then
                        unrecordable[#unrecordable + 1] = ("%s:%d %s"):format(
                            file,
                            instruction.line or 0,
                            instruction.unrecordable
                        )
                    end
                end
            end
        end
        if total > budget.total then
            failures[#failures + 1] = ("%s compiles to %d instructions, over its budget of %d"):format(
                file,
                total,
                budget.total
            )
        end
        if loop > budget.loop then
            failures[#failures + 1] = ("%s has %d instructions in loops, over its budget of %d"):format(
                file,
                loop,
                budget.loop
            )
        end
        for _, site in ipairs(unrecordable) do
            failures[#failures + 1] = "a loop LuaJIT cannot record: " .. site
        end
    end
    assert(#failures == 0, table.concat(failures, "\n"))
end

-- Generated Lua per byte of source, over the standard library and the compiler as the
-- last build wrote them. Types erase and lines map one to one, so the ratio sits well
-- under one; the per-module runtime prologue is most of what keeps it from sitting
-- lower. It measures the whole tree rather than one fixture because a lowering that
-- bloats is a lowering some module uses, and it is a ratio because the tree grows.
-- 0.715 when the ceiling was set.
local GENERATED_PER_SOURCE_BYTE = 0.80

function M.generatedLuaStaysWithinItsSizeBudget()
    local build = ROOT .. "/" .. (os.getenv("NUPP_TEST_BUILD") or "build")
    local pipe = assert(io.popen(("cd '%s/src' && find nupp -name '*.nupp' ! -name '*.d.nupp'"):format(ROOT)))
    local source, generated, modules = 0, 0, 0
    for relative in pipe:lines() do
        local base = relative:gsub("%.nupp$", ""):gsub("%.g$", "")
        local lua = readFile(build .. "/" .. base .. ".lua")
        if lua then
            source = source + #assert(readFile(ROOT .. "/src/" .. relative))
            generated = generated + #lua
            modules = modules + 1
        end
    end
    pipe:close()
    assert(modules > 300, ("only %d built modules were found under %s"):format(modules, build))
    local ratio = generated / source
    assert(
        ratio <= GENERATED_PER_SOURCE_BYTE,
        ("%d modules generate %.3f bytes of Lua per source byte, over the budget of %.2f"):format(
            modules,
            ratio,
            GENERATED_PER_SOURCE_BYTE
        )
    )
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
local ALLOCATION_PER_MODULE = 2 * 1024 * 1024
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

return M
