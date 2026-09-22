-- The derived command registry and shared terminal policy.
local ansi = require("nupp.cli")
local cli = require("nupp.compiler.cli")
local json = require("testjson")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
if not HERE:match("^/") then
    local p = assert(io.popen("pwd"))
    HERE = p:read("*l") .. "/" .. HERE
    p:close()
end
local NUPP = HERE .. "/../bin/nupp"

local M = {}

function M.everyRegisteredCommandHasAGrammarAndHelp()
    local names = cli.names()
    assert(#names >= 14, "every command is registered: " .. #names)
    assert(table.concat(names, ","):find("bench", 1, true), "bench is a registered command")
    assert(not table.concat(names, ","):find("test-runner", 1, true), "the runner is not a public command")
    assert(not table.concat(names, ","):find("coverage", 1, true), "coverage is a test mode, not a command")
    for _, name in ipairs(names) do
        assert(name ~= "", "a command has a name")
    end
end

function M.completionsAreRenderedFromTheRegisteredCommandGrammar()
    local bash = cli.completion("bash")
    assert(bash:find("completions", 1, true), "completes the command itself")
    assert(bash:find("--strict", 1, true), "completes command options")
    assert(bash:find("text", 1, true) and bash:find("json", 1, true), "completes closed option values")
    assert(bash:find("compgen", 1, true), "uses its embedded static candidates")
    assert(not bash:find("__complete bash", 1, true), "does not run nupp when no field is dynamic")
    assert(bash:find("complete -F _nupp nupp", 1, true), "installs Bash completion")

    local zsh = cli.completion("zsh")
    assert(zsh:find("#compdef nupp", 1, true), "installs Zsh completion")
    assert(zsh:find("compadd", 1, true), "uses its embedded static candidates")
    assert(not zsh:find("__complete zsh", 1, true), "does not run nupp when no field is dynamic")

    local fish = cli.completion("fish")
    assert(fish:find("complete -c nupp", 1, true), "installs Fish completion")
    assert(not fish:find("__complete fish", 1, true), "does not run nupp when no field is dynamic")
end

function M.colourIsDecidedOncePerStreamAndOverriddenByMode()
    ansi.setColorMode("never")
    local plain = ansi.style(io.stdout)
    assert(plain.strong("x") == "x", "never means the text is returned unchanged")
    -- The no-colour path returns the very string it was given, so a plain report
    -- allocates nothing to say it is plain.
    assert(plain.strong == plain.faint, "and every style is the same identity function")

    ansi.setColorMode("always")
    local painted = ansi.style(io.stdout)
    assert(painted.strong("x") == "\27[1mx\27[0m", "always wraps in an escape")
    assert(ansi.severity(painted, "error")("e") == "\27[1;31me\27[0m", "an error is red")
    assert(ansi.severity(painted, "warning")("w") == "\27[1;33mw\27[0m", "a warning is yellow")
    -- A severity that is not one of the known names is treated the way the
    -- renderer already treats it: as an error.
    assert(
        ansi.severity(painted, "wat")("x") == ansi.severity(painted, "error")("x"),
        "an unknown severity paints as an error"
    )

    ansi.withColorMode("never", function()
        assert(not ansi.colorEnabled(io.stdout), "a scoped mode applies in its body")
    end)
    assert(ansi.colorEnabled(io.stdout), "a scoped mode restores the caller's mode")

    local ok = pcall(function()
        ansi.withColorMode("never", function()
            error("expected test error")
        end)
    end)
    assert(not ok, "a scoped mode preserves errors")
    assert(ansi.colorEnabled(io.stdout), "an error also restores the caller's mode")

    ansi.setColorMode("auto")
end

function M.aTableAlignsOnMeasuredTextAndPaintsAfterPadding()
    ansi.setColorMode("never")
    local plain = ansi.style(io.stdout)
    local rendered = ansi.table({
        columns = {{heading = "lint"}, {heading = "level"}, {heading = "summary"}},
        rows = {
            {ansi.cell("a"), ansi.cell("error"), ansi.cell("first")},
            {ansi.cell("longer-name"), ansi.cell("off"), ansi.cell("second")},
        },
        style = plain,
    })
    assert(
        rendered == "lint         level  summary\n" .. "a            error  first\n" .. "longer-name  off    second\n",
        "columns are as wide as their widest cell, heading included:\n" .. rendered
    )
    -- The last column is not padded. A run of trailing spaces is invisible in a
    -- terminal and very visible in anything that reads the output back.
    for line in rendered:gmatch("[^\n]+") do
        assert(not line:find("%s$"), "no line ends in padding: " .. line)
    end

    -- The point of the shared renderer: an escape is bytes with no width, so
    -- padding has to happen before painting or the escapes line up and the text
    -- does not. Both rows below carry a painted cell of a different length.
    ansi.setColorMode("always")
    local painted = ansi.style(io.stdout)
    local coloured = ansi.table({
        columns = {{heading = "name", paint = painted.strong}, {heading = "note"}},
        rows = {{ansi.cell("a"), ansi.cell("x")}, {ansi.cell("longer"), ansi.cell("y")}},
        style = painted,
    })
    local lines = {}
    for line in coloured:gmatch("[^\n]+") do
        lines[#lines + 1] = line
    end
    assert(lines[1]:find("\27%[1;35mname\27%[0m  "), "the heading is painted as a heading: " .. lines[1])
    -- Padding sits outside the escape, not inside it: styled whitespace is invisible
    -- under bold and very visible under anything that paints a background.
    assert(lines[2]:find("\27%[1ma\27%[0m     ", 1, false), "a short cell is padded after its paint")
    assert(lines[3]:find("\27%[1mlonger\27%[0m", 1, false), "a full-width cell needs no padding")

    -- A cell may paint itself whatever its column says, and may carry an aside that
    -- is painted apart from its text and measured along with it -- so a column
    -- carrying one still lines up with the column beside it.
    local mixed = ansi.table({
        columns = {{heading = "name", paint = painted.strong}, {heading = "note"}},
        rows = {
            {ansi.annotatedCell("a", " (extra)", painted.faint), ansi.cell("x")},
            {ansi.cell("longer-still"), ansi.cell("y")},
        },
        style = painted,
    })
    assert(mixed:find("\27%[2ma\27%[0m\27%[2m %(extra%)\27%[0m", 1, false), "a cell overrides its column's paint")
    local noted, plainRow
    for line in mixed:gmatch("[^\n]+") do
        if line:find("extra", 1, true) then
            noted = line
        elseif line:find("longer%-still") then
            plainRow = line
        end
    end

    local function columnAt(line)
        return #(line:gsub("\27%[[0-9;]*m", "")):match("^(.-)%s%s%S")
    end

    assert(
        columnAt(noted) == columnAt(plainRow),
        "an annotated cell is measured with its note, so the next column does not move"
    )

    ansi.setColorMode("never")
    assert(
        ansi.table({
            columns = {{heading = "only"}},
            rows = {}
        }) == "",
        "no rows prints nothing at all rather than a heading over nothing"
    )
    assert(
        ansi.table({
            columns = {{heading = "n", align = "right"}, {heading = "what"}},
            rows = {{ansi.cell("7"), ansi.cell("a")}, {ansi.cell("1234"), ansi.cell("b")}},
        }) == "   n  what\n   7  a\n1234  b\n",
        "a right aligned column pads on the left"
    )
    ansi.setColorMode("auto")
end

function M.aTableCutsTheLastColumnToFitRatherThanLettingItWrap()
    local long = "a description far longer than the window it is being printed into"

    -- The style decides whether a cut can be shown by dimming, so it is passed here
    -- rather than read from the process: a caller printing unpainted gets the marker
    -- whatever the mode says.
    local function build(width)
        return {
            columns = {{heading = "name"}, {heading = "summary"}},
            rows = {{ansi.cell("alpha"), ansi.cell(long)}, {ansi.cell("beta"), ansi.cell("short")}},
            style = ansi.style(io.stdout),
            width = width,
        }
    end

    ansi.setColorMode("never")
    -- No width is no edge, so nothing is cut. This is the pipe, and a pipe gets every
    -- byte: something reads it later that wanted all of them.
    local whole = ansi.table(build(nil))
    assert(whole:find(long, 1, true), "with no width the cell is printed whole")

    local fitted = ansi.table(build(40))
    for line in fitted:gmatch("[^\n]+") do
        assert(#line <= 40, "every line fits the width: " .. #line .. " " .. line)
    end
    assert(not fitted:find(long, 1, true), "the long cell was cut")
    assert(fitted:find("short", 1, true), "a cell that already fits is untouched")
    -- Nothing wraps: a row is still a row.
    local rows = 0
    for _ in fitted:gmatch("[^\n]+") do
        rows = rows + 1
    end
    assert(rows == 3, "heading and two rows, none of them wrapped: " .. rows)
    -- A cut says so, painted or not: unpainted the marker is the only thing saying
    -- the description continues.
    assert(fitted:find("...", 1, true), "an unpainted cut says it was cut")

    ansi.setColorMode("always")
    local painted = ansi.table(build(40))
    local cut
    for line in painted:gmatch("[^\n]+") do
        if line:find("alpha", 1, true) then
            cut = line
        end
    end
    assert(cut:find("\27%[2m"), "a painted cut fades toward the edge: " .. cut)
    -- The marker is inside the faded run rather than after it, so the line trails
    -- off into the dots instead of stopping and then being labelled.
    assert(cut:find("%.%.%.\27%[0m"), "the marker is the last of the fade, not a mark after it: " .. cut)
    assert(#(cut:gsub("\27%[[0-9;]*m", "")) == 40, "the fade and marker are inside the width, not past it")

    -- A cell's aside survives the cut. It is the shorter and more particular half, so
    -- losing it silently would lose the whole of what it said.
    ansi.setColorMode("never")
    local noted = ansi.table({
        columns = {{heading = "name"}, {heading = "summary"}},
        rows = {{ansi.cell("alpha"), ansi.annotatedCell(long, " (note)")}},
        style = ansi.style(io.stdout),
        width = 40,
    })
    assert(noted:find(" (note)", 1, true), "the aside is kept and the text cut around it")
    for line in noted:gmatch("[^\n]+") do
        assert(#line <= 40, "still fits: " .. line)
    end

    -- Too narrow to cut usefully: what would survive is a few letters and a fade,
    -- which says less than the wrapped line it replaced.
    local cramped = ansi.table(build(22))
    assert(cramped:find(long, 1, true), "below the floor the cell is left alone to wrap")

    ansi.setColorMode("auto")
end

local function capture(argv)
    -- This test defines automatic colour as a plain pipe, whatever the shell
    -- that launched the suite put in its environment.
    local pipe = assert(io.popen(("NO_COLOR= CLICOLOR_FORCE= '%s' %s 2>&1"):format(NUPP, argv)))
    local out = pipe:read("*a")
    pipe:close()
    return out
end

-- `--json` promises a clean stdout, so a JSON capture must not fold stderr into
-- it. The launcher writes "building the compiler" there when the cache is cold,
-- which is invisible in a warm single-suite run and lands in front of the
-- payload under a full parallel one.
local function captureJson(argv)
    local pipe = assert(io.popen(("NO_COLOR= CLICOLOR_FORCE= '%s' %s"):format(NUPP, argv)))
    local out = pipe:read("*a")
    pipe:close()
    return out
end

local function captureAt(directory, argv)
    local pipe = assert(io.popen(("cd '%s' && NO_COLOR= CLICOLOR_FORCE= '%s' %s 2>&1"):format(directory, NUPP, argv)))
    local out = pipe:read("*a")
    local ok = pipe:close()
    return out, ok
end

local function captureJsonAt(directory, argv)
    local pipe = assert(io.popen(("cd '%s' && NO_COLOR= CLICOLOR_FORCE= '%s' %s"):format(directory, NUPP, argv)))
    local out = pipe:read("*a")
    local ok = pipe:close()
    return out, ok
end

local function captureStatusAt(directory, argv)
    local pipe = assert(
        io.popen(
            ("cd '%s' && NO_COLOR= CLICOLOR_FORCE= '%s' %s 2>&1; echo '__exit__:'$?"):format(directory, NUPP, argv)
        )
    )
    local out = pipe:read("*a")
    pipe:close()
    local code = assert(tonumber(out:match("__exit__:(%d+)%s*$")), "no exit status in:\n" .. out)

    return (out:gsub("__exit__:%d+%s*$", "")), code
end

function M.everyPublicCommandHelpHasExamples()
    local root = require("nupp.compiler.cli.root").Root
    local grammar = ansi.application(root, {name = "nupp"})

    local function requireExamples(argv, label)
        local help = capture(argv)
        assert(help:find("\nExamples:\n\n    nupp ", 1, true), label .. " help has no command example:\n" .. help)
        local found = 0
        local inExamples = false
        for line in (help .. "\n"):gmatch("(.-)\n") do
            if line == "Examples:" then
                inExamples = true
            elseif inExamples and line:match("^    nupp%s") then
                local example = assert(line:match("^    nupp%s+(.+)$"))
                local arguments = {}
                for word in example:gmatch("%S+") do
                    arguments[#arguments + 1] = word
                end
                if arguments[1] == "--version" then
                    arguments[1] = "version"
                end
                local invocation, problem = grammar:resolve(arguments)
                assert(
                    invocation ~= nil,
                    label .. " has an invalid example: " .. line .. "\n" .. tostring(problem and problem.message)
                )
                found = found + 1
            elseif inExamples and line ~= "" then
                break
            end
        end
        assert(found > 0, label .. " help has an empty Examples section")
    end

    requireExamples("--help", "nupp")

    local function visit(subject, prefix)
        for _, child in ipairs(subject.subcommands and subject.subcommands() or {}) do
            local path = prefix == "" and child.cliName() or prefix .. " " .. child.cliName()
            requireExamples(path .. " --help", "nupp " .. path)
            visit(child, path)
        end
    end

    visit(root, "")
end

function M.aotHelpNamesArtifactsAndShowsHighlightedExamples()
    local plain = capture("aot --help")
    -- Collapsed, because the list is long enough to wrap and where it wraps is the
    -- help formatter's business rather than this test's. What is asserted is that
    -- every accepted artifact is named.
    local flowed = plain:gsub("%s+", " ")
    assert(
        flowed:find("Artifact to print: ir, c, spirv, wgsl, asm, or binding.", 1, true),
        "--emit names every accepted artifact: " .. plain
    )
    assert(
        plain:find("nupp aot --emit asm --function scale src/kernel.nupp", 1, true),
        "the help includes an assembly example: " .. plain
    )
    assert(plain:find("nupp aot --format json src/kernel.nupp", 1, true), "the help includes a JSON example: " .. plain)

    local coloured = capture("aot --color=always --help")
    assert(coloured:find("\27[1mExamples:\27[0m", 1, true), "the example heading is highlighted: " .. coloured)
    assert(coloured:find("\27[1;36mnupp\27[0m", 1, true), "the executable is highlighted: " .. coloured)
    assert(coloured:find("\27[1;32m--emit\27[0m", 1, true), "example options are highlighted: " .. coloured)
    assert(coloured:find("\27[1;34msrc/kernel.nupp\27[0m", 1, true), "example paths are highlighted: " .. coloured)

    local nested = capture("lsp inspect --color=always --help")
    assert(
        nested:find("\27[1mlsp\27[0m \27[1minspect\27[0m", 1, true),
        "every component of a nested command is highlighted: " .. nested
    )
end

function M.migrateChecksThenAtomicallyRenamesAnnotatedLua()
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p '" .. dir .. "'") == 0)
    local path = dir .. "/legacy.lua"
    local source = assert(io.open(path, "wb"))
    source:write(
        "---@param value integer\n---@return integer\n" .. "local function keep(value) return value end\nreturn keep\n"
    )
    source:close()

    local function exists(name)
        local file = io.open(name, "rb")
        if not file then
            return false
        end
        file:close()

        return true
    end

    local preview, previewed = captureAt(dir, "migrate --check legacy.lua")
    assert(previewed, "migration preview succeeds: " .. preview)
    assert(exists(path) and not exists(dir .. "/legacy.g.nupp"), "--check changes neither source nor destination")

    local output, migrated = captureAt(dir, "migrate legacy.lua")
    assert(migrated, "migration succeeds: " .. output)
    assert(not exists(path) and exists(dir .. "/legacy.g.nupp"), "the checked destination replaces the source")
    local result = assert(io.open(dir .. "/legacy.g.nupp", "rb")):read("*a")
    assert(
        result:find("local function keep(value: integer): integer", 1, true),
        "the written destination carries imported types"
    )
    os.execute("rm -rf '" .. dir .. "'")
end

function M.migrateDoesNotClaimFilesItNeverTouched()
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p '" .. dir .. "'") == 0)
    local annotated = "---@param value integer\n---@return integer\n"
        .. "local function keep(value) return value end\nreturn keep\n"
    for _, name in ipairs({"blocked.lua", "waiting.lua"}) do
        local source = assert(io.open(dir .. "/" .. name, "wb"))
        source:write(annotated)
        source:close()
    end
    local occupied = assert(io.open(dir .. "/blocked.g.nupp", "wb"))
    occupied:write("return false\n")
    occupied:close()

    local output, code = captureStatusAt(dir, "migrate blocked.lua waiting.lua")
    assert(code ~= 0, "an occupied destination refuses the batch")
    assert(output:find("blocked.g.nupp already exists", 1, true), "the planning failure is reported: " .. output)
    assert(
        not output:find("waiting.lua -> waiting.g.nupp", 1, true),
        "an untouched later plan is not printed as a success: " .. output
    )
    local untouched = io.open(dir .. "/waiting.lua", "rb")
    assert(untouched, "the later source remains where it was")
    untouched:close()
    os.execute("rm -rf '" .. dir .. "'")
end

function M.migrateJsonListsEveryPlanAfterAFailure()
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p '" .. dir .. "'") == 0)
    local bad = assert(io.open(dir .. "/bad.lua", "wb"))
    bad:write(
        "---@param value integer\n---@return string\n" .. "local function bad(value) return value end\nreturn bad\n"
    )
    bad:close()
    local waiting = assert(io.open(dir .. "/waiting.lua", "wb"))
    waiting:write(
        "---@param value integer\n---@return integer\n" .. "local function keep(value) return value end\nreturn keep\n"
    )
    waiting:close()
    local report = json.decode(captureJsonAt(dir, "migrate --json bad.lua waiting.lua"))
    assert(not report.ok and #report.errors == 1, "the first migration fails its check: " .. json.encode(report.errors))
    assert(#report.migrations == 2, "every plan is listed, the one that stopped the batch and the one it never reached")
    assert(
        report.migrations[2].source == "waiting.lua" and report.migrations[2].written == false,
        "the untouched plan is reported as not written"
    )
    os.execute("rm -rf '" .. dir .. "'")
end

function M.exportCEmitsTheCanonicalTypedHeader()
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p '" .. dir .. "/src'") == 0)
    local manifest = assert(io.open(dir .. "/nupp.lua", "wb"))
    manifest:write(
        [[return {
   include = {"src"},
   build = {entries = {"game"}, layoutTarget = "x86_64-unknown-linux-gnu"},
}
]]
    )
    manifest:close()
    local source = assert(io.open(dir .. "/src/game.nupp", "wb"))
    source:write(
        [[
local game = {}
struct game.Position
   x: float
   y: float
end
cdef function integrate(exclusive position: game.Position*?, dt: float)
function game.run(): float
   local positions = carray(game.Position, 1)
   positions[0].x = 1
   integrate(positions, 2)
   return positions[0].x
end
return game
]]
    )
    source:close()

    local output, ok = captureAt(dir, "export-c -o game.h src/game.nupp game.Position game.integrate")
    assert(ok, "export-c succeeds: " .. output)
    assert(output == "game.h\n", "the written path is reported: " .. output)
    local header = assert(io.open(dir .. "/game.h", "rb")):read("*a")
    assert(
        header:find("typedef struct nupp_4_game_8_Position_tag", 1, true),
        "the canonical ordinary-struct identity is emitted"
    )
    assert(
        header:find("void integrate(nupp_4_game_8_Position *position, float dt);", 1, true),
        "the public prototype remains typed"
    )
    assert(
        header:find("_Static_assert(offsetof(nupp_4_game_8_Position, y) == 4", 1, true),
        "every field offset is asserted"
    )

    local generated, built = captureAt(dir, "build --json")
    assert(built, "the ordinary module builds: " .. generated)
    local lua = assert(io.open(dir .. "/build/game.lua", "rb")):read("*a")
    assert(
        lua:find('cdef, "void integrate(void *, float);"', 1, true),
        "the same checked signature erases only the physical FFI pointer slot"
    )
    assert(
        os.execute(("cd '%s' && cc -std=c11 -fsyntax-only game.h"):format(dir)) == 0,
        "an independent C compiler accepts the exported header"
    )

    -- What remains calls the C implementation through the module's own cdef,
    -- which finds the symbol because a POSIX load can publish it globally.
    -- Windows resolves an FFI symbol out of a fixed set of modules instead, so
    -- the header and the erased signature are as far as this goes there.
    if jit.os == "Windows" then
        os.execute("rm -rf '" .. dir .. "'")
        require("assert").skip("a globally loaded shared library is POSIX-only")
    end

    local c = assert(io.open(dir .. "/game.c", "wb"))
    c:write(
        [[#include "game.h"
void integrate(nupp_4_game_8_Position *position, float dt) {
    position->x += dt;
    position->y = position->x * 2.0f;
}
]]
    )
    c:close()
    local library = dir .. (jit.os == "OSX" and "/libgame.dylib" or "/libgame.so")
    local shared = jit.os == "OSX" and "-dynamiclib" or "-shared -fPIC"
    assert(
        os.execute(("cd '%s' && cc -std=c11 %s -o '%s' game.c"):format(dir, shared, library)) == 0,
        "the independent typed C implementation compiles"
    )
    local loaded = require("ffi").load(library, true)
    local priorPath = package.path
    package.path = dir .. "/build/?.lua;" .. package.path
    package.loaded.game = nil
    local game = require("game")
    assert(game.run() == 3, "typed ordinary-struct storage crosses the erased FFI slot")
    package.loaded.game = nil
    package.path = priorPath
    loaded = nil
    collectgarbage()
    os.execute("rm -rf '" .. dir .. "'")
end

function M.theBinaryHonoursColourFlagsOnRealDiagnostics()
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p '" .. dir .. "'") == 0)
    local manifest = assert(io.open(dir .. "/nupp.lua", "wb"))
    manifest:write('return {include = {"."}}\n')
    manifest:close()
    local source = assert(io.open(dir .. "/bad.nupp", "wb"))
    source:write("local x: number = \"text\"\nreturn x\n")
    source:close()

    local forced = capture(("check --color=always '%s/bad.nupp'"):format(dir))
    assert(forced:find("\27[", 1, true), "--color=always colours even down a pipe: " .. forced)

    local refused = capture(("check --no-color '%s/bad.nupp'"):format(dir))
    assert(not refused:find("\27[", 1, true), "--no-color leaves no escapes: " .. refused)

    -- A pipe is not a terminal, so the default already writes plain text, and it
    -- must be exactly what --no-color wrote.
    local automatic = capture(("check '%s/bad.nupp'"):format(dir))
    assert(automatic == refused, "the default down a pipe is byte-identical to --no-color")
    assert(refused:find("NUPP", 1, true), "and it is still a diagnostic: " .. refused)

    local both = capture(("check --color=always --no-color '%s/bad.nupp'"):format(dir))
    assert(
        both:find("both asked for and refused", 1, true),
        "asking for colour and refusing it is a contradiction: " .. both
    )

    os.execute("rm -rf '" .. dir .. "'")
end

function M.binaryPrintsCompletionScripts()
    local bash = capture("completions bash")
    assert(bash:find("complete -F _nupp nupp", 1, true), "the Bash script is available through the CLI")
    assert(bash:find("--strict", 1, true), "the script reflects command options")

    local fish = capture("completions fish")
    assert(fish:find("complete -c nupp", 1, true), "the Fish script is available through the CLI")
end

-- `--version` is a spelling of the command rather than a second answer beside
-- it, so the two cannot disagree, and what they print is one line: an install
-- script and a packaging recipe both read it as one.
function M.theVersionFlagAndTheCommandPrintOneAgreedLine()
    local version = require("nupp.compiler.version")
    local expected = "nupp " .. version.VERSION .. "\n"
    assert(capture("version") == expected, "the command prints the version: " .. capture("version"))
    assert(capture("--version") == expected, "and the flag prints the same: " .. capture("--version"))

    local decoded = json.decode(captureJson("--version --json"))
    assert(decoded.version == version.VERSION, "the flag reaches the command's own JSON, not a second rendering")
    assert(decoded.runtime and decoded.runtime ~= "", "which names the interpreter underneath")
end

function M.schemaStopsAtTheProgramBoundary()
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p '" .. dir .. "'") == 0)
    local manifest = assert(io.open(dir .. "/nupp.lua", "wb"))
    manifest:write('return {include = {"."}}\n')
    manifest:close()
    local source = assert(io.open(dir .. "/main.nupp", "wb"))
    source:write("print((...))\n")
    source:close()

    local output, ok = captureAt(dir, "run main.nupp --schema")
    assert(ok and output == "--schema\n", "a program argument named --schema is preserved: " .. output)
    local schema, status = captureStatusAt(dir, "run --schema main.nupp")
    assert(status == 0 and schema:find('"type"', 1, true), "the compiler-side option still prints its schema")
    os.execute("rm -rf '" .. dir .. "'")
end

function M.lintsUsesDefaultsOutsideAConfiguredProject()
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p '" .. dir .. "'") == 0)
    local output, ok = captureAt(dir, "lints")
    assert(ok, "the default lint catalogue needs no nupp.lua: " .. output)
    assert(output:find("unused-binding", 1, true), "the default catalogue is printed: " .. output)
    os.execute("rm -rf '" .. dir .. "'")
end

-- The registry's contract is that naming a command loads its grammar and nothing
-- heavier; the compiler it needs is required inside `run`. Checked in a fresh
-- interpreter, since this process has long since loaded everything.
function M.aCommandModuleDoesNotLoadTheCompilerItRuns()
    local runtimePipe = assert(io.popen(("'%s/../scripts/toolchain' luajit"):format(HERE)))
    local runtime = assert(runtimePipe:read("*l")) .. "/bin/luajit"
    runtimePipe:close()
    local probe = (
        [[
package.path = %q
for _, name in ipairs({"aot", "lsp", "bc", "ast"}) do
   require("nupp.compiler.cli." .. name)
end
for _, heavy in ipairs({"nupp.compiler.aot.compile", "nupp.compiler.lsp",
      "nupp.compiler.tracebytecode", "nupp.compiler.lexer",
      "nupp.compiler.check", "nupp.compiler.parser"}) do
   if package.loaded[heavy] then print("loaded " .. heavy) end
end
print("done")
]]
    ):format(package.path)
    local script = os.tmpname()
    local file = assert(io.open(script, "wb"))
    file:write(probe)
    file:close()
    local pipe = assert(io.popen(("'%s' '%s' 2>&1"):format(runtime, script)))
    local out = pipe:read("*a")
    pipe:close()
    os.remove(script)
    assert(out == "done\n", "requiring a command module loads its grammar, not the compiler:\n" .. out)
end

-- `--json` positions come from an index of where each line starts; a diagnostic
-- on the last line of a file, and one on the first, both have to land where the
-- text form would put them.
function M.jsonPositionsAreResolvedThroughALineIndex()
    local report = require("nupp.compiler.cli.report")
    local path = os.tmpname()
    local file = assert(io.open(path, "wb"))
    file:write("first\nsecond line\n\nfourth\n")
    file:close()

    local function at(offset, length)
        local values = report.diagnosticValues({
            {filename = path, offset = offset, length = length, code = "NUPP0001", msg = "x", severity = "error"}
        })
        return values[1].range
    end

    local first = at(1, 5)
    assert(first.start.line == 1 and first.start.column == 1, "the first byte is 1:1")
    assert(first["end"].line == 1 and first["end"].column == 6, "and its end is on the same line")
    local second = at(7, 6)
    assert(second.start.line == 2 and second.start.column == 1, "the byte after a newline starts the next line")
    local blank = at(19, 0)
    assert(blank.start.line == 3 and blank.start.column == 1, "an empty line is a line")
    local last = at(25, 1)
    assert(
        last.start.line == 4 and last.start.column == 6,
        ("the last line resolves: got %d:%d"):format(last.start.line, last.start.column)
    )
    local past = at(27, 3)
    assert(
        past["end"].line == 5 and past["end"].column == 1,
        "a range running past the end stops at the byte after the text"
    )
    os.remove(path)
end

function M.checkNamedFilesKeepTheirExtensionStrictness()
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p '" .. dir .. "'") == 0)

    local function write(name, text)
        local file = assert(io.open(dir .. "/" .. name, "wb"))
        file:write(text)
        file:close()
    end

    local function unknown(command, expected)
        local output = captureJsonAt(dir, command)
        local report = json.decode(output)
        assert(report.timing and report.timing.totalMs >= 0, "every check form reports timing: " .. output)
        assert(type(report.timing.compiledModules) == "number", "every check reports work count")
        local found = false
        for _, diagnostic in ipairs(report.diagnostics) do
            found = found or diagnostic.code == "NUPP2105"
        end
        assert(found == expected, command .. " must respect the strict floor: " .. output)
        assert(report.ok == not expected, command .. ": " .. output)
    end

    for _, manifest in ipairs({false, true}) do
        if manifest then
            write("nupp.lua", 'return {include = {"."}}')
        end
        for _, extension in ipairs({".nupp", ".g.nupp", ".nupp", ".lua"}) do
            local name = "probe" .. extension
            write(name, "return missingForStrictCheck\n")
            unknown("check --json " .. name, extension == ".nupp")
            unknown("check --json --strict " .. name, true)
            if manifest and extension ~= ".lua" then
                unknown("check --json", extension == ".nupp")
            end
            os.remove(dir .. "/" .. name)
        end
    end
    os.execute("rm -rf '" .. dir .. "'")
end

function M.checkRefusesAManifestItCannotLoad()
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p '" .. dir .. "'") == 0)
    local manifest = assert(io.open(dir .. "/nupp.lua", "wb"))
    manifest:write("return {\n")
    manifest:close()
    local file = assert(io.open(dir .. "/m.nupp", "wb"))
    file:write("module m\nexport = {}\n")
    file:close()
    local output, code = captureStatusAt(dir, "check m.nupp")
    assert(code == 1, "a broken manifest fails the check rather than " .. "checking the file standalone: " .. output)
    assert(output:find("cannot load nupp.lua", 1, true), "the load error is what is reported: " .. output)
    local report = json.decode(captureJsonAt(dir, "check --json m.nupp"))
    assert(
        report.ok == false and report.diagnostics[1].file == "nupp.lua",
        "--json carries the same failure as a diagnostic about the manifest"
    )
    os.remove(dir .. "/nupp.lua")
    local _, standalone = captureStatusAt(dir, "check m.nupp")
    assert(standalone == 0, "and without a manifest the file is checked on its own")
    os.execute("rm -rf '" .. dir .. "'")
end

function M.initListRefusesAJsonSpellingItCannotProduce()
    local output, code = captureStatusAt(HERE, "init --list --json")
    assert(code ~= 0, "--list cannot satisfy the scaffold JSON schema")
    assert(output:find("--list has no JSON output", 1, true), "the unsupported combination is explicit: " .. output)
    assert(output:sub(1, 1) ~= "{", "template text is not mislabeled JSON")
end

function M.ownershipAuditEnumeratesForeignContractsAndUnsafeSites()
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p '" .. dir .. "'") == 0)
    local source = assert(io.open(dir .. "/surface.g.nupp", "wb"))
    source:write(
        table.concat(
            {
                "cdef function lookup(borrows key: const char*,",
                "   out value: voidptr* borrows (key)): int32",
                "cdef function visit(borrows values: const int32* countedBy(count), count: uint64)",
                "@unsafe do",
                "   local _, raw = lookup('key')",
                "   print(raw)",
                "   local text = 'key'",
                "   local bytes = ffi.cast<const uint8[?]>(text)",
                "   print(bytes[0])",
                "end",
                "local record Split left: integer right: integer end",
                "local sealed interface Splitter",
                "   @partition(left, right)",
                "   split: function(self: Splitter): Split",
                "end",
                "local record Resource name: string end",
                "local function close_resource(value: Resource) end",
                "local function open_resource(): affine(Resource, close_resource)",
                "   return new Resource(name = 'audit')",
                "end",
                "local function use_resource()",
                "   local value = open_resource()",
                "   print(value.name)",
                "end",
                "",
            },
            "\n"
        )
    )
    source:close()

    local report = json.decode(captureJson(("ownership-audit --json '%s/surface.g.nupp'"):format(dir)))
    assert(#report.foreign == 2, "both foreign declarations are reported")
    assert(report.foreign[1].name == "lookup", "the trusted function is named")
    assert(report.foreign[1].parameters[1].contract == "borrows", "the pointer parameter contract survives checking")
    assert(#report.foreign[1].results == 1, "the derived pointer result is included")
    assert(
        report.foreign[2].countedBy[1].pointer == "values"
        and report.foreign[2].countedBy[1].count == "count"
        and report.foreign[2].countedBy[1].access == "read",
        "counted pointer relationships survive checking"
    )
    assert(report.foreign[2].zeroCount:find("calls once", 1, true), "the audit reports the foreign zero-count promise")
    assert(
        #report.unsafe == 3 and report.unsafe[1].line == 4,
        "the explicit unsafe boundary, operation, and contract are enumerable"
    )
    assert(report.unsafe[2].kind == "unchecked C memory indexing", "the report names the trusted raw operation")
    assert(
        report.unsafe[3].kind == "ownership contract: partitioned result fields",
        "the report names a trusted partition contract"
    )
    assert(report.regions == nil, "automatic regions remain opt-in")

    local regions = json.decode(
        captureJson(("ownership-audit --json --regions '%s/surface.g.nupp'"):format(dir))
    ).regions
    assert(#regions == 1 and regions[1].owners[1].name == "value", "automatic cleanup sites are enumerable")
    assert(
        regions[1].id:find("function:", 1, true)
        and regions[1].activationOrder[1] == "value"
        and regions[1].cleanupOrder[1] == "value",
        "region identity and ordering are semantic and deterministic"
    )
    assert(regions[1].lowering == "general", "the audit reports the selected protected lowering")

    local schema = json.decode(captureJson("ownership-audit --schema"))
    assert(
        schema.properties.foreign and schema.properties.unsafe and schema.properties.regions,
        "the machine report has a discoverable schema"
    )
    os.execute("rm -rf '" .. dir .. "'")
end

function M.ownershipAuditFindsInlineAssertionsAndAffineCResults()
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p '" .. dir .. "'") == 0)
    local source = assert(io.open(dir .. "/inline.g.nupp", "wb"))
    source:write(
        table.concat(
            {
                "cdef function free(takes value: voidptr)",
                "cdef function acquire(size: uint64): affine(voidptr, free)",
                "local raw: voidptr",
                "local owner = @unsafe nupp.adopt<affine(voidptr, free)>(raw)",
                "local released = @unsafe nupp.release(owner)",
                "local read = @unsafe (nil as int32*)[0]",
                "return released",
                "",
            },
            "\n"
        )
    )
    source:close()

    local report = json.decode(captureJson(("ownership-audit --json '%s/inline.g.nupp'"):format(dir)))
    assert(
        #report.foreign == 2 and report.foreign[2].name == "acquire",
        "an affine C result is a trusted ownership contract"
    )
    assert(
        #report.foreign[2].results == 1 and report.foreign[2].results[1].type:find("affine(voidptr", 1, true),
        "the affine result is described"
    )
    assert(
        #report.unsafe == 4
        and report.unsafe[1].kind == "ownership assertion: adopt"
        and report.unsafe[2].kind == "ownership assertion: release",
        "inline ownership assertions are listed outside unsafe-do regions"
    )
    assert(report.unsafe[3].kind == "unchecked C memory indexing", "expression permission includes the read")
    assert(report.unsafe[4].kind == "unsafe assertion expression", "expression markers are enumerable")
    os.execute("rm -rf '" .. dir .. "'")
end

function M.ownershipAuditReportsFilesItCannotAnalyze()
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p '" .. dir .. "'") == 0)
    local broken = assert(io.open(dir .. "/broken.nupp", "wb"))
    broken:write("local =\n")
    broken:close()

    local syntax, syntaxCode = captureStatusAt(dir, "ownership-audit broken.nupp")
    assert(syntaxCode ~= 0, "unparseable input fails the audit")
    assert(syntax:find("broken.nupp:1", 1, true), "the parse failure names its source: " .. syntax)

    local missing, missingCode = captureStatusAt(dir, "ownership-audit absent.nupp")
    assert(missingCode ~= 0, "unreadable input fails the audit")
    assert(missing:find("cannot read absent.nupp", 1, true), "the read failure is reported: " .. missing)
    os.execute("rm -rf '" .. dir .. "'")
end

-- Half of a cold self-build is the trace compiler, so a compiler run raises LuaJIT's
-- side-trace threshold. A resident or program-running command must not: `lsp` amortizes
-- its traces across a session, and `run` and `task` execute somebody else's program.
local function flagsAppliedBy(command, env)
    local applied = {}
    local realStart, realGetenv, realWrite = jit.opt.start, os.getenv, io.write
    jit.opt.start = function(...)
        applied[#applied + 1] = table.concat({...}, ",")
    end
    os.getenv = function(name)
        return (env or {})[name] or realGetenv(name)
    end
    io.write = function()
    end
    pcall(cli.main, {command, "--help"})
    jit.opt.start, os.getenv, io.write = realStart, realGetenv, realWrite

    return table.concat(applied, " ")
end

local function assertFlags(command, want, env, label)
    local got = flagsAppliedBy(command, env)
    assert(got == want, ("%s: %s\n  want: %q\n  got:  %q"):format(command, label or "wrong jit flags", want, got))
end

function M.compilerRunsRaiseTheSideTraceThreshold()
    assertFlags("build", "hotexit=200,hotloop=1000")
    assertFlags("check", "hotexit=200,hotloop=1000")
end

function M.residentAndProgramRunningCommandsKeepTheDefaults()
    assertFlags("lsp", "", nil, "resident: its traces amortize across a session")
    assertFlags("run", "", nil, "runs a program this says nothing about")
    assertFlags("task", "", nil, "likewise")
end

function M.theTuningIsOverridable()
    assertFlags("build", "", {NUPP_JIT_DEFAULT = "1"}, "NUPP_JIT_DEFAULT compares the two")
    assertFlags(
        "build",
        "hotexit=60,hotloop=100",
        {NUPP_JIT_TUNE = "hotexit=60,hotloop=100"},
        "NUPP_JIT_TUNE is how a sweep moves them"
    )
end

return M
