-- `nupp bc`: the bytecode a file compiles to, and what a loop cannot compile.
--
-- Driven through the real binary rather than the module, because the listing and the
-- exit status are the whole interface.

local test = require("assert")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
if not HERE:match("^/") then
    local p = assert(io.popen("pwd"))
    HERE = p:read("*l") .. "/" .. HERE
    p:close()
end
local NUPP = HERE .. "/../bin/nupp"

local M = {}

local function project(files)
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p '" .. dir .. "'") == 0)
    local manifest = assert(io.open(dir .. "/nupp.lua", "wb"))
    manifest:write('return {include = {"."}}\n')
    manifest:close()
    for name, source in pairs(files) do
        local handle = assert(io.open(dir .. "/" .. name, "wb"))
        handle:write(source)
        handle:close()
    end

    return dir
end

-- LuaJIT's `popen` close answers only whether the pipe shut, never the exit status, so
-- the status is carried back through the pipe itself. `--check` is an exit status, so a
-- test that could not read one would not be testing it.
local function run(dir, argv)
    local pipe = assert(io.popen(("cd %q && NO_COLOR= '%s' bc %s 2>&1; echo \"__exit__:$?\""):format(dir, NUPP, argv)))
    local out = pipe:read("*a")
    pipe:close()
    local code = assert(tonumber(out:match("__exit__:(%d+)%s*$")), "no exit status in:\n" .. out)

    return (out:gsub("__exit__:%d+%s*$", "")), code
end

-- The row a source line owns, from the line number to the end of the rows that
-- carry the rest of its instructions. The listing is two columns now, so "what
-- did this line compile to" is a row and its continuations rather than the lines
-- beneath a heading.
local function rowsFor(out, pattern)
    local rows, collecting = {}, false
    for line in out:gmatch("([^\n]*)\n") do
        local numbered = line:match("^%s*%d+ |")
        if numbered and line:find(pattern) then
            rows, collecting = {line}, true
        elseif numbered then
            collecting = false
        elseif collecting and line:match("^%s*|") then
            rows[#rows + 1] = line
        end
    end

    return #rows > 0 and table.concat(rows, "\n") or nil
end

local SCALE = table.concat(
    {
        "local function scale(values: {number}, by: number): number",
        "    local total = 0",
        "    for i = 1, #values do",
        "        total = total + values[i] * by",
        "    end",
        "    return total",
        "end",
        "",
        "return scale({1, 2, 3}, 2)",
        "",
    },
    "\n"
)

-- A closure reading the iteration. The `loop-invariant-closure` lint deliberately says
-- nothing about this one -- it cannot be lifted, so there is no edit to suggest -- but
-- the loop holding it still never compiles, which is the gap this closes.
local CAPTURING = table.concat(
    {
        "local function each(items: {number}, fn: function(n: number): number): number",
        "    local total = 0",
        "    for i = 1, #items do",
        "        total = total + fn(items[i])",
        "    end",
        "    return total",
        "end",
        "",
        "local out = 0",
        "for round = 1, 4 do",
        "    out = out + each({1, 2}, function(n: number): number",
        "        return n * round",
        "    end)",
        "end",
        "return out",
        "",
    },
    "\n"
)

function M.theListingShowsSourceAgainstTheInstructionsItProduced()
    local dir = project{["demo.g.nupp"] = SCALE}
    local out, code = run(dir, "demo.g.nupp")
    test.equal(code, 0, out)
    assert(out:find("%d+ |%s+for i = 1, #values do"), "source lines are shown:\n" .. out)
    assert(out:find("FORI", 1, true) and out:find("FORL", 1, true), "the loop's bytecode is shown:\n" .. out)
    assert(out:find("|%s+0%d%d%d%s+FORI"), "an instruction sits on the row of the line that wrote it:\n" .. out)
end

-- The file runs down the left and what it compiled to runs down the right. Two
-- things follow that the older listing could not show: a line is written once
-- however many functions have instructions on it -- the line declaring a nested
-- function used to appear twice, under the chunk that built the closure and
-- again under the function it opened -- and a line that compiled to nothing is
-- visibly a row with nothing beside it.
function M.theListingIsTheFileBesideWhatItCompiledTo()
    local dir = project{["demo.g.nupp"] = SCALE}
    local out, code = run(dir, "demo.g.nupp")
    test.equal(code, 0, out)
    local seen = {}
    for line in out:gmatch("[^\n]+") do
        local at = tonumber(line:match("^%s*(%d+) |"))
        if at then
            assert(not seen[at], ("line %d has more than one row of its own:\n%s"):format(at, out))
            seen[at] = true
        end
    end
    assert(seen[1], "the first line of the file has a row:\n" .. out)
    assert(out:match("\n%s*8 |%s*\n"), "a blank line is a row with nothing beside it:\n" .. out)
end

-- The listing reads down the source, not down the bytecode.
--
-- Bytecode order is not source order: a chunk builds each function with an FNEW
-- attributed to the line the function ends on, and assigns it on the line it
-- starts on, so a flat listing echoed lines 2, 12, 5, 21, 15 for a file whose
-- functions are in the obvious order. Grouping instructions under the line they
-- came from, and nesting a body under the line that declares it, is what makes
-- the listing something you can read beside the file.
function M.echoedSourceLinesOnlyEverMoveForward()
    local dir = project{["demo.g.nupp"] = SCALE}
    local out, code = run(dir, "demo.g.nupp")
    test.equal(code, 0, out)
    local seen, previous = 0, 0
    for line in out:gmatch("[^\n]+") do
        local at = tonumber(line:match("^%s*(%d+) |"))
        if at then
            seen = seen + 1
            assert(at >= previous, ("the listing goes back from line %d to line %d:\n%s"):format(previous, at, out))
            previous = at
        end
    end
    assert(seen > 3, "the listing echoes source lines:\n" .. out)
end

-- A function's instructions sit under its own line rather than wherever the
-- bytecode happened to put them.
function M.instructionsSitUnderTheLineTheyCameFrom()
    local dir = project{["demo.g.nupp"] = SCALE}
    local out = run(dir, "demo.g.nupp")
    local body = assert(rowsFor(out, "for i = 1, #values do"), "the loop header's own instructions:\n" .. out)
    assert(body:find("FORI", 1, true), "the loop opens beside the line that writes it:\n" .. body)
end

-- The runtime preamble builds functions of its own. They are preamble too, and
-- a listing that showed them put the runtime's file handling above everything
-- the reader wrote.
function M.functionsTheRuntimePreambleBuiltAreFoldedWithIt()
    local dir = project{["demo.g.nupp"] = SCALE}
    local folded = run(dir, "demo.g.nupp")
    assert(
        folded:match("instructions of runtime preamble, in %d+ function"),
        "the folded preamble counts the functions it built:\n" .. folded
    )
    assert(
        not folded:find("could not be closed", 1, true),
        "a preamble function's own instructions stay folded:\n" .. folded
    )

    local shown = run(dir, "--prologue demo.g.nupp")
    assert(shown:find("could not be closed", 1, true), "--prologue shows the functions the preamble built:\n" .. shown)
end

-- The generated runtime preamble all lands on line 1, so a listing that showed it would
-- bury the file under something nobody wrote.
function M.theRuntimePreambleIsFoldedUnlessAskedFor()
    local dir = project{["demo.g.nupp"] = SCALE}
    local folded = run(dir, "demo.g.nupp")
    assert(folded:find("instructions of runtime preamble", 1, true), "the preamble is folded by default:\n" .. folded)
    assert(not folded:find("rawset", 1, true), "folded output still names the preamble")

    local shown = run(dir, "--prologue demo.g.nupp")
    assert(not shown:find("instructions of runtime preamble", 1, true), "--prologue stops folding:\n" .. shown)
    assert(shown:find("rawset", 1, true), "--prologue shows the preamble:\n" .. shown)
end

function M.authoredCodeOnLineOneIsNotFoldedWithThePreamble()
    local source = "local answer = tonumber('42')\nreturn answer\n"
    local dir = project{["line-one.g.nupp"] = source}
    local out, code = run(dir, "line-one.g.nupp")
    test.equal(code, 0, out)
    assert(
        out:find("1 | local answer = tonumber('42')", 1, true),
        "the first authored line follows the explicit boundary:\n" .. out
    )
    assert(
        out:find('GGET', 1, true) and out:find('"tonumber"', 1, true),
        "the first line's own instructions remain visible:\n" .. out
    )
    assert(not out:find("__nupp_bc_preamble_boundary", 1, true), "the structural marker is not part of the listing")
end

function M.declaredModulesFoldTheirPreambleInsideTheLoader()
    local source = table.concat(
        {"module declared", "export function answer(): integer", "    return 42", "end", "",},
        "\n"
    )
    local dir = project{["declared.g.nupp"] = source}
    local out, code = run(dir, "declared.g.nupp")
    test.equal(code, 0, out)
    assert(out:find("instructions of runtime preamble", 1, true), "the declared module's preamble is folded:\n" .. out)
    assert(out:find("3 |     return 42", 1, true), "the declared module's authored source remains visible:\n" .. out)
end

-- What the annotations cost, answered by the instructions rather than by a benchmark:
-- an indexed multiply-accumulate over a declared `{number}` is three instructions with
-- no call, no check and no boxing among them.
function M.declaredTypesLeaveNothingBehindInTheLoop()
    local dir = project{["demo.g.nupp"] = SCALE}
    local out = run(dir, "demo.g.nupp")
    local body = assert(rowsFor(out, "total = total %+ values%[i%] %* by"), "the loop body's instructions:\n" .. out)
    assert(body:find("MULVV", 1, true) and body:find("ADDVV", 1, true), "the arithmetic is register ops:\n" .. body)
    assert(not body:find("CALL", 1, true), "the loop body calls nothing:\n" .. body)
end

function M.checkReportsALoopThatCannotCompileAndFailsForIt()
    local dir = project{["bad.g.nupp"] = CAPTURING}
    local out, code = run(dir, "--check bad.g.nupp")
    test.equal(code, 1, "a loop that cannot compile must fail --check:\n" .. out)
    assert(
        out:find("this loop never compiles: LuaJIT has no recorder for constructing a function", 1, true),
        "the instruction is marked in place:\n" .. out
    )
    assert(out:find("in a loop that cannot compile", 1, true), "the run says how many:\n" .. out)
end

-- A function built behind a guard and reused is not a function built every iteration.
-- A trace records the path it saw, so by the time the loop is hot the guarded arm is
-- cold and the trace never contains it -- the loop compiles, and saying otherwise would
-- fail a build over code that demonstrably works. This is how a shared cleanup region
-- is lowered, so it is not a corner case.
function M.aFunctionBuiltOnceBehindAGuardIsAdvisory()
    local dir = project{
        [
            "guarded.g.nupp"
        ] = table.concat(
            {
                "cdef function free(takes value: voidptr)",
                "cdef function malloc(size: uint64): voidptr",
                "local function ownedMalloc(size: integer): affine(voidptr, free)",
                "   return malloc(size)",
                "end",
                "",
                "local n = 0",
                "for i = 1, 3000 do",
                "    local value = ownedMalloc(8)",
                "end",
                "return n",
            },
            "\n"
        ) .. "\n"
    }
    local out, code = run(dir, "--check guarded.g.nupp")
    assert(code == 0, "a guarded, reused function is not a loop that cannot compile:\n" .. out)
    assert(out:find("may%-reach"), "the blocker path remains visible without claiming the whole loop fails:\n" .. out)
end

function M.cleanupRegionsWritingFunctionAndLoopLocalsStillCompile()
    local dir = project{
        [
            "captured.g.nupp"
        ] = table.concat(
            {
                "cdef function free(takes value: voidptr)",
                "cdef function malloc(size: uint64): voidptr",
                "local function ownedMalloc(size: integer): affine(voidptr, free)",
                "   return malloc(size)",
                "end",
                "local function count(limit: integer): integer",
                "   local result: integer = 0",
                "   for outer = 1, limit do",
                "      local subtotal: integer = 0",
                "      for inner = 1, outer do",
                "         local value = ownedMalloc(8)",
                "         subtotal = subtotal + inner",
                "         result = result + 1",
                "      end",
                "      result = result + subtotal",
                "   end",
                "   return result",
                "end",
                "return count(3000)",
            },
            "\n"
        ) .. "\n"
    }
    local out, code = run(dir, "--check captured.g.nupp")
    assert(code == 0, "cleanup captures must not leave either enclosing loop unrecordable:\n" .. out)
    assert(out:find("may%-reach"), "the guarded construction remains visible as an advisory path:\n" .. out)
    assert(not out:find("never compiles", 1, true), "neither loop retains a must-reach function construction:\n" .. out)
end

function M.checkPassesWhenEveryLoopCanCompile()
    local dir = project{["demo.g.nupp"] = SCALE}
    local out, code = run(dir, "--check demo.g.nupp")
    test.equal(code, 0, out)
    assert(not out:find("never compiles", 1, true), "nothing is marked:\n" .. out)
end

function M.switchInsideAHotLoopBuildsNoFunction()
    local source = table.concat(
        {
            "local total = 0",
            "for i = 1, 3000 do",
            "   local parity: number = i % 2",
            "   local value = switch parity do",
            "      case 0 -> 2",
            "      case 1 -> 1",
            "      else -> 0",
            "   end",
            "   total = total + value",
            "end",
            "return total",
            "",
        },
        "\n"
    )
    local dir = project{["switch.g.nupp"] = source}
    local out, code = run(dir, "--check switch.g.nupp")
    test.equal(code, 0, out)
    assert(not out:find("FNEW", 1, true), "switch lowering must not build an arm function:\n" .. out)
    assert(not out:find("never compiles", 1, true), "the switch loop remains trace-recordable:\n" .. out)
end

function M.mappedSwitchAllocatesNothingInsideItsHotLoop()
    local source = table.concat(
        {
            "local total = 0",
            "for i = 1, 3000 do",
            "   local value = switch i % 5 do",
            "      case 0 -> 10",
            "      case 1 -> 20",
            "      case 2 -> 30",
            "      case 3 -> 40",
            "      else -> 0",
            "   end",
            "   total = total + value",
            "end",
            "return total",
            "",
        },
        "\n"
    )
    local dir = project{["switch-map.g.nupp"] = source}
    local out, code = run(dir, "--check switch-map.g.nupp")
    test.equal(code, 0, out)
    assert(out:find("TGETV", 1, true), "the dispatch is one indexed table read:\n" .. out)
    assert(not out:find("never compiles", 1, true), "the mapped switch loop remains trace-recordable:\n" .. out)
end

function M.jsonCarriesTheFindingAndItsCount()
    local dir = project{["bad.g.nupp"] = CAPTURING}
    local out, code = run(dir, "--format json bad.g.nupp")
    test.equal(code, 0, "json output alone does not fail; --check does\n" .. out)
    local decoded = require("testjson").decode(out)
    test.equal(decoded.file, "bad.g.nupp")
    assert(decoded.unrecordable >= 1, "the count is reported: " .. tostring(decoded.unrecordable))
    assert(decoded.blockers >= decoded.unrecordable, "all blocker paths are counted")
    assert(decoded.mustBlockers == decoded.unrecordable, "the CI count is must-reach")
    assert(
        decoded.bytecodeFingerprint and decoded.traceProfile.id,
        "the exact artifact and recorder profile are identified"
    )
    assert(decoded.reasonCatalog.id == "nupp-trace-reasons-v1", "bytecode uses the shared reason catalog")
    local found = false
    for _, fn in ipairs(decoded.functions) do
        for _, instruction in ipairs(fn.instructions) do
            if instruction.unrecordable then
                found = true
                assert(instruction.inLoop, "an unrecordable instruction is marked as in a loop")
                test.equal(instruction.op, instruction.op:upper())
                assert(
                    instruction.traceReason and instruction.traceReachability == "must",
                    "the compatibility finding carries its normalized classification"
                )
            end
        end
    end
    assert(found, "json names the instruction, not only the count")
end

-- Colour is a second rendering of the same listing, never a different one. The
-- escapes go inside lines, so a listing stripped of them is the listing a pipe
-- got -- which is what keeps the line numbering an editor maps against true of
-- the coloured one as well.
function M.colorRepaintsTheListingWithoutChangingIt()
    local dir = project{["demo.g.nupp"] = SCALE}

    -- A run that had to build the compiler first says so on stderr, which this
    -- harness merges; that line belongs to neither listing.
    local function listing(text)
        return (text:gsub("nupp: [^\n]*\n", ""))
    end

    local plain, code = run(dir, "demo.g.nupp")
    test.equal(code, 0, plain)
    assert(not plain:find("\27", 1, true), "a pipe gets no escapes:\n" .. plain)

    local painted, paintedCode = run(dir, "--color demo.g.nupp")
    test.equal(paintedCode, 0, painted)
    assert(painted:find("\27", 1, true), "--color paints the listing:\n" .. painted)
    test.equal((listing(painted):gsub("\27%[[%d;]*m", "")), listing(plain))
end

-- The listing is read for the source; the bytecode beneath it is what that
-- source cost. So the source carries the colours and the instructions are muted
-- as one run, with one exception: the `;` hint, where an instruction names
-- something the reader wrote.
function M.colorHighlightsSourceAndMutesTheBytecode()
    local dir = project{["demo.g.nupp"] = 'local greeting = "hi"\nprint(greeting)\n'}
    local out = run(dir, "--color demo.g.nupp")
    assert(out:find("\27%[35mlocal\27%[0m"), "a source keyword is painted as one:\n" .. out)
    assert(out:find('\27%[32m"hi"\27%[0m'), "a source string is painted as one:\n" .. out)
    assert(out:find("\27%[90m[^\27]*GGET"), "the instruction is muted as one run:\n" .. out)
    assert(not out:find("\27%[%d+mGGET"), "no opcode carries a colour of its own:\n" .. out)
    assert(out:find('\27%[32m"print"\27%[0m'), "the hint keeps the name it carries from the source:\n" .. out)
end

function M.colorMarksAVerdictWithItsSeverity()
    local dir = project{["bad.g.nupp"] = CAPTURING}
    local out, code = run(dir, "--color --check bad.g.nupp")
    test.equal(code, 1, out)
    assert(
        out:find("\27%[31m  <%-%- this loop never compiles"),
        "a loop that cannot compile is marked in red:\n" .. out
    )
end

function M.colorIsRefusedWhenTheEnvironmentRefusesIt()
    local dir = project{["demo.g.nupp"] = SCALE}
    local out, code = run(dir, "--no-color demo.g.nupp")
    test.equal(code, 0, out)
    assert(not out:find("\27", 1, true), "--no-color writes no escapes:\n" .. out)
end

function M.doExpressionInsideAHotLoopBuildsNoFunction()
    local source = [[
local total = 0
for i = 1, 3000 do
    local value = do
        if i % 2 == 0 then yield 2 end
        yield 1
    end
    total = total + value
end
return total
]]
    local dir = project{["block.g.nupp"] = source}
    local out, code = run(dir, "--check block.g.nupp")
    test.equal(code, 0, out)
    assert(not out:find("FNEW", 1, true), out)
end

function M.bytecodeUsesTheSelectedTierAndNamesConstructorTailCalls()
    local dir = project{["constructor.g.nupp"] = [[
local function make()
    return setmetatable({}, {})
end
return make()
]]}
    local out, code = run(dir, "--json --check -O1 constructor.g.nupp")
    test.equal(code, 0, out)
    local report = require("testjson").decode(out)
    test.equal(report.optLevel, 1, "selected optimization tier")
    assert(report.risks > 0, "constructor tail call is an explicit risk")
    local found = false
    for _, fn in ipairs(report.functions) do
        for _, finding in ipairs(fn.findings) do
            if finding.reason == "jit/tailcall-constructor" then
                found = true
                test.equal(finding.class, "risk", "tail call is not a proved blocker")
            end
        end
    end
    assert(found, "named constructor tail-call reason")
    os.execute("rm -rf " .. string.format("%q", dir))
end

return M
