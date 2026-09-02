-- The option grammar, the colour decision, and the command registry.
--
-- The grammar is tested directly rather than through the binary: every command
-- is now one declaration parsed by one loop, so the cases that used to be
-- spread across thirteen hand-written loops are worth stating once, here.
local spec = require("nupp.compiler.cli.spec")
local sharedOptions = require("nupp.compiler.cli.options")
local ansi = require("nupp.compiler.ansi")
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

local DEMO = spec.command{
   name = "demo",
   summary = "Demonstrate the grammar",
   usage = {"nupp demo [options] [file...]"},
   options = {
      {name = "--strict", help = "Treat strict checker rules as errors"},
      {name = "--target", value = "NAME", help = "Build a named manifest target"},
      {names = {"-o", "--out-dir"}, value = "DIR", help = "Where output goes"},
      {name = "--format", value = "FORMAT", choices = {"text", "json"},
         duplicate = "output format was specified more than once",
         help = "Output format: text (default) or json"},
      {name = "--json", key = "format", constant = "json",
         duplicate = "output format was specified more than once",
         help = "Shorthand for --format json"},
      {name = "--profile", value = "MS", form = "optional",
         help = "Sample every MS milliseconds"},
      {name = "-Zno-opt", value = "CODE", form = "attached", key = "disabled",
         repeats = true, set = true, display = "-Zno-opt=CODE",
         help = "Turn off one pass by its stable code"},
      {name = "-O", pattern = "^%-O(%d)$", value = "n", key = "optLevel",
         choices = {"0", "1", "2"}, display = "-O0, -O1, -O2",
         invalid = "the optimization level is -O0, -O1 or -O2",
         help = "Optimization level"},
   },
}

--- Parses, returning the values table, or the error message prefixed so a failed
--- parse and an unexpected value cannot be confused for each other.
local function parse(args)
   local parsed, err = DEMO:parse(args)
   if not parsed then return "ERR: " .. tostring(err) end
   return parsed.values
end

local function positional(args)
   local parsed, err = DEMO:parse(args)
   assert(parsed, "expected a parse, got: " .. tostring(err))
   return table.concat(parsed.positional, ",")
end

function M.optionsReachTheirKeyInEverySpelling()
   assert(parse({"--target", "x"}).target == "x", "a value follows its option")
   assert(parse({"--target=x"}).target == "x", "or is attached with =")
   assert(parse({"-o", "d"}).outDir == "d", "a short alias reaches the same key")
   assert(parse({"--out-dir", "d"}).outDir == "d",
      "and the key comes from the long spelling")
   assert(parse({"--strict"}).strict == true, "a flag is true when given")
   assert(parse({}).strict == nil,
      "and absent rather than false when it is not")
end

function M.malformedOptionsAreRefusedWithTheirOwnName()
   assert(parse({"--target"}) == "ERR: option --target requires a value",
      "a missing value names the option")
   assert(parse({"--target", "--strict"})
      == "ERR: option --target requires a value",
      "a value is not taken from the next option")
   assert(parse({"--target="}) == "ERR: option --target requires a value",
      "an empty attached value is still missing")
   assert(parse({"--wat"}) == "ERR: unknown option --wat",
      "an unknown option is refused")
   assert(parse({"--strict=1"}) == "ERR: option --strict does not take a value",
      "a flag given a value is refused")
end

function M.choicesAreCheckedAndCanPhraseTheirOwnRefusal()
   assert(parse({"--format", "json"}).format == "json", "a listed choice passes")
   assert(parse({"--format", "yaml"})
      == "ERR: option --format does not take yaml; expected text, json",
      "an unlisted one says what was expected")
   assert(parse({"-O5"}) == "ERR: the optimization level is -O0, -O1 or -O2",
      "a pattern option phrases its own refusal, since -O is not a spelling")
   assert(parse({"-Oz"}) == "ERR: unknown option -Oz",
      "and what the pattern does not match is simply unknown")
end

function M.spellingsOfOneChoiceRefuseEachOther()
   assert(parse({"--format", "json", "--json"})
      == "ERR: output format was specified more than once",
      "two spellings of one key are a contradiction, not two flags")
   assert(parse({"--target", "a", "--target", "b"})
      == "ERR: option --target was specified more than once",
      "and a plain repeat names the option")
end

function M.anOptionalValueNeverSwallowsWhatFollowsIt()
   assert(parse({"--profile"}).profile == true, "the bare form is a yes")
   assert(parse({"--profile=5"}).profile == "5", "the attached form is a value")
   assert(positional({"--profile", "prog.nupp"}) == "prog.nupp",
      "the bare form leaves the next argument alone")
   -- The whole reason the form exists: `--profile prog.nupp` must not read the
   -- program name as an interval.
   assert(parse({"--profile", "prog.nupp"}).profile == true,
      "and does not take it as its value")
end

function M.anAttachedOnlyOptionRefusesItsBareForm()
   assert(parse({"-Zno-opt", "prog.nupp"})
      == "ERR: option -Zno-opt requires a value; write -Zno-opt=CODE",
      "the bare form is refused rather than eating the next argument")
   local disabled = parse({"-Zno-opt=a", "-Zno-opt=b"}).disabled
   assert(disabled.a and disabled.b, "repeats accumulate into a set")
end

function M.buildWideRelaxationIsNoLongerAnOptimizerOption()
   local command = spec.command{
      name = "opt", summary = "optimizer", usage = {"nupp opt"},
      options = sharedOptions.optimize(),
   }
   local parsed, err = command:parse({"--relax=frames"})
   assert(parsed == nil and err:find("unknown option", 1, true), tostring(err))
end

function M.theLiteralTerminatorEndsOptionParsing()
   assert(positional({"--", "--strict", "a"}) == "--strict,a",
      "everything after -- is positional")
   assert(parse({"--", "--strict"}).strict == nil,
      "including what would otherwise have been a flag")
   assert(positional({"a", "--strict", "b"}) == "a,b",
      "and positionals otherwise interleave with options")
end

function M.stopAtPositionalHandsTheRestToTheProgram()
   local runner = spec.command{
      name = "run", summary = "Run", usage = {"nupp run <file>"},
      stopAtPositional = true,
      options = {{name = "--strict", help = "Strict"}},
   }
   local parsed = assert(runner:parse({"--strict", "p.nupp", "--strict", "x"}))
   assert(parsed.values.strict == true, "options before the file are the compiler's")
   assert(table.concat(parsed.positional, ",") == "p.nupp,--strict,x",
      "and everything from the file on belongs to the program")
end

function M.helpIsRenderedFromTheGrammarThatParses()
   ansi.withMode("never", function()
      local text = DEMO:help()
      -- The point of the abstraction: an option cannot be parsed and undocumented.
      for _, wanted in ipairs({"--strict", "--target NAME", "-o, --out-dir DIR",
         "--profile[=MS]", "-Zno-opt=CODE", "-O0, -O1, -O2", "--color[=WHEN]",
         "-h, --help"}) do
         assert(text:find(wanted, 1, true),
            "help documents " .. wanted .. ": " .. text)
      end
      assert(text:find("Usage:\n  nupp demo", 1, true), "help has a usage line")
   end)
   -- Long help wraps and the continuation aligns under the first line's text.
   local wrapped = spec.wrap("one two three four five", 9)
   assert(#wrapped == 3 and wrapped[1] == "one two", "greedy wrap: " .. wrapped[1])
end

function M.everyRegisteredCommandHasAGrammarAndHelp()
   local names = cli.names()
   assert(#names >= 14, "every command is registered: " .. #names)
   local hasBackend = false
   for _, name in ipairs(names) do
      assert(name ~= "", "a command has a name")
      hasBackend = hasBackend or name == "backend"
   end
   assert(hasBackend, "the backend conformance command is registered")
end

function M.completionsAreRenderedFromTheRegisteredCommandGrammar()
   local commands = cli.commands()
   local rendered = require("nupp.compiler.cli.completions")
   local bash = rendered.render("bash", commands)
   assert(bash:find("completions", 1, true), "completes the command itself")
   assert(bash:find("--strict", 1, true), "completes command options")
   assert(bash:find("text json", 1, true),
      "completes closed option values")
   assert(not bash:find("--color)", 1, true),
      "optional choices are not offered as a following word")
   assert(bash:find("complete -F _nupp nupp", 1, true), "installs Bash completion")

   local zsh = rendered.render("zsh", commands)
   assert(zsh:find("#compdef nupp", 1, true), "installs Zsh completion")
   assert(zsh:find("case $words[1] in", 1, true),
      "dispatches on the command after _arguments narrows the words")
   assert(zsh:find("if (( CURRENT == 2 )); then", 1, true),
      "offers positional choices at the narrowed first argument")
   assert(zsh:find("check:Type-check source", 1, true),
      "uses the command schema's summary")

   local fish = rendered.render("fish", commands)
   assert(fish:find("complete -c nupp", 1, true), "installs Fish completion")
   assert(fish:find("function __fish_nupp_needs_command", 1, true),
      "has a guard dedicated to top-level command completion")
   assert(fish:find("-n '__fish_nupp_needs_command' -a check", 1, true),
      "offers command names before a command is present")
   assert(fish:find("-l color -a 'always never auto'", 1, true)
      and not fish:find("-l color -r", 1, true),
      "optional choices do not consume the following word")
   assert(fish:find("-l strict", 1, true), "includes long options")
end

function M.colourIsDecidedOncePerStreamAndOverriddenByMode()
   ansi.setMode("never")
   local plain = ansi.style(io.stdout)
   assert(plain.strong("x") == "x", "never means the text is returned unchanged")
   -- The no-colour path returns the very string it was given, so a plain report
   -- allocates nothing to say it is plain.
   assert(plain.strong == plain.faint,
      "and every style is the same identity function")

   ansi.setMode("always")
   local painted = ansi.style(io.stdout)
   assert(painted.strong("x") == "\27[1mx\27[0m", "always wraps in an escape")
   assert(ansi.forSeverity(painted, "error")("e") == "\27[1;31me\27[0m",
      "an error is red")
   assert(ansi.forSeverity(painted, "warning")("w") == "\27[1;33mw\27[0m",
      "a warning is yellow")
   -- A severity that is not one of the known names is treated the way the
   -- renderer already treats it: as an error.
   assert(ansi.forSeverity(painted, "wat")("x")
      == ansi.forSeverity(painted, "error")("x"),
      "an unknown severity paints as an error")

   ansi.withMode("never", function()
      assert(not ansi.enabled(io.stdout), "a scoped mode applies in its body")
   end)
   assert(ansi.enabled(io.stdout), "a scoped mode restores the caller's mode")

   local ok = pcall(function()
      ansi.withMode("never", function() error("expected test error") end)
   end)
   assert(not ok, "a scoped mode preserves errors")
   assert(ansi.enabled(io.stdout), "an error also restores the caller's mode")

   ansi.setMode("auto")
end

local function capture(argv)
   -- This test defines automatic colour as a plain pipe, whatever the shell
   -- that launched the suite put in its environment.
   local pipe = assert(io.popen(("NO_COLOR= CLICOLOR_FORCE= '%s' %s 2>&1")
      :format(NUPP, argv)))
   local out = pipe:read("*a")
   pipe:close()
   return out
end

-- `--json` promises a clean stdout, so a JSON capture must not fold stderr into
-- it. The launcher writes "building the compiler" there when the cache is cold,
-- which is invisible in a warm single-suite run and lands in front of the
-- payload under a full parallel one.
local function captureJson(argv)
   local pipe = assert(io.popen(("NO_COLOR= CLICOLOR_FORCE= '%s' %s")
      :format(NUPP, argv)))
   local out = pipe:read("*a")
   pipe:close()
   return out
end

local function captureAt(directory, argv)
   local pipe = assert(io.popen(("cd '%s' && NO_COLOR= CLICOLOR_FORCE= '%s' %s 2>&1")
      :format(directory, NUPP, argv)))
   local out = pipe:read("*a")
   local ok = pipe:close()
   return out, ok
end

local function captureJsonAt(directory, argv)
   local pipe = assert(io.popen(("cd '%s' && NO_COLOR= CLICOLOR_FORCE= '%s' %s")
      :format(directory, NUPP, argv)))
   local out = pipe:read("*a")
   local ok = pipe:close()
   return out, ok
end

local function captureStatusAt(directory, argv)
   local pipe = assert(io.popen((
      "cd '%s' && NO_COLOR= CLICOLOR_FORCE= '%s' %s 2>&1; echo '__exit__:'$?"
   ):format(directory, NUPP, argv)))
   local out = pipe:read("*a")
   pipe:close()
   local code = assert(tonumber(out:match("__exit__:(%d+)%s*$")),
      "no exit status in:\n" .. out)
   return (out:gsub("__exit__:%d+%s*$", "")), code
end

function M.migrateChecksThenAtomicallyRenamesAnnotatedLua()
   local dir = os.tmpname()
   os.remove(dir)
   assert(os.execute("mkdir -p '" .. dir .. "'") == 0)
   local path = dir .. "/legacy.lua"
   local source = assert(io.open(path, "wb"))
   source:write("---@param value integer\n---@return integer\n"
      .. "local function keep(value) return value end\nreturn keep\n")
   source:close()
   local function exists(name)
      local file = io.open(name, "rb")
      if not file then return false end
      file:close()
      return true
   end

   local preview, previewed = captureAt(dir, "migrate --check legacy.lua")
   assert(previewed, "migration preview succeeds: " .. preview)
   assert(exists(path) and not exists(dir .. "/legacy.g.nupp"),
      "--check changes neither source nor destination")

   local output, migrated = captureAt(dir, "migrate legacy.lua")
   assert(migrated, "migration succeeds: " .. output)
   assert(not exists(path) and exists(dir .. "/legacy.g.nupp"),
      "the checked destination replaces the source")
   local result = assert(io.open(dir .. "/legacy.g.nupp", "rb")):read("*a")
   assert(result:find("local function keep(value: integer): integer", 1, true),
      "the written destination carries imported types")
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
   assert(output:find("blocked.g.nupp already exists", 1, true),
      "the planning failure is reported: " .. output)
   assert(not output:find("waiting.lua -> waiting.g.nupp", 1, true),
      "an untouched later plan is not printed as a success: " .. output)
   local untouched = io.open(dir .. "/waiting.lua", "rb")
   assert(untouched, "the later source remains where it was")
   untouched:close()
   os.execute("rm -rf '" .. dir .. "'")
end

function M.exportCEmitsTheCanonicalTypedHeader()
   local dir = os.tmpname()
   os.remove(dir)
   assert(os.execute("mkdir -p '" .. dir .. "/src'") == 0)
   local manifest = assert(io.open(dir .. "/nupp.lua", "wb"))
   manifest:write([[return {
   include = {"src"},
   build = {entries = {"game"}, layoutTarget = "x86_64-unknown-linux-gnu"},
}
]])
   manifest:close()
   local source = assert(io.open(dir .. "/src/game.nupp", "wb"))
   source:write([[
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
]])
   source:close()

   local output, ok = captureAt(dir,
      "export-c -o game.h src/game.nupp game.Position game.integrate")
   assert(ok, "export-c succeeds: " .. output)
   assert(output == "game.h\n", "the written path is reported: " .. output)
   local header = assert(io.open(dir .. "/game.h", "rb")):read("*a")
   assert(header:find("typedef struct nupp_4_game_8_Position_tag", 1, true),
      "the canonical ordinary-struct identity is emitted")
   assert(header:find(
      "void integrate(nupp_4_game_8_Position *position, float dt);", 1, true),
      "the public prototype remains typed")
   assert(header:find("_Static_assert(offsetof(nupp_4_game_8_Position, y) == 4", 1, true),
      "every field offset is asserted")

   local generated, built = captureAt(dir, "build --json")
   assert(built, "the ordinary module builds: " .. generated)
   local lua = assert(io.open(dir .. "/build/game.lua", "rb")):read("*a")
   assert(lua:find('cdef, "void integrate(void *, float);"', 1, true),
      "the same checked signature erases only the physical FFI pointer slot")
   assert(os.execute(("cd '%s' && cc -std=c11 -fsyntax-only game.h"):format(dir)) == 0,
      "an independent C compiler accepts the exported header")

   -- What remains calls the C implementation through the module's own cdef,
   -- which finds the symbol because a POSIX load can publish it globally.
   -- Windows resolves an FFI symbol out of a fixed set of modules instead, so
   -- the header and the erased signature are as far as this goes there.
   if jit.os == "Windows" then
      os.execute("rm -rf '" .. dir .. "'")
      require("assert").skip("a globally loaded shared library is POSIX-only")
   end

   local c = assert(io.open(dir .. "/game.c", "wb"))
   c:write([[#include "game.h"
void integrate(nupp_4_game_8_Position *position, float dt) {
    position->x += dt;
    position->y = position->x * 2.0f;
}
]])
   c:close()
   local library = dir .. (jit.os == "OSX" and "/libgame.dylib" or "/libgame.so")
   local shared = jit.os == "OSX" and "-dynamiclib" or "-shared -fPIC"
   assert(os.execute(("cd '%s' && cc -std=c11 %s -o '%s' game.c"):format(
      dir, shared, library)) == 0, "the independent typed C implementation compiles")
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
   assert(forced:find("\27[", 1, true),
      "--color=always colours even down a pipe: " .. forced)

   local refused = capture(("check --no-color '%s/bad.nupp'"):format(dir))
   assert(not refused:find("\27[", 1, true),
      "--no-color leaves no escapes: " .. refused)

   -- A pipe is not a terminal, so the default already writes plain text, and it
   -- must be exactly what --no-color wrote.
   local automatic = capture(("check '%s/bad.nupp'"):format(dir))
   assert(automatic == refused,
      "the default down a pipe is byte-identical to --no-color")
   assert(refused:find("NUPP", 1, true),
      "and it is still a diagnostic: " .. refused)

   local both = capture(("check --color=always --no-color '%s/bad.nupp'")
      :format(dir))
   assert(both:find("both asked for and refused", 1, true),
      "asking for colour and refusing it is a contradiction: " .. both)

   os.execute("rm -rf '" .. dir .. "'")
end

function M.binaryPrintsCompletionScripts()
   local bash = capture("completions bash")
   assert(bash:find("complete -F _nupp nupp", 1, true),
      "the Bash script is available through the CLI")
   assert(bash:find("--strict", 1, true), "the script reflects command options")

   local fish = capture("completions fish")
   assert(fish:find("complete -c nupp", 1, true),
      "the Fish script is available through the CLI")
end

function M.lintsUsesDefaultsOutsideAConfiguredProject()
   local dir = os.tmpname()
   os.remove(dir)
   assert(os.execute("mkdir -p '" .. dir .. "'") == 0)
   local output, ok = captureAt(dir, "lints")
   assert(ok, "the default lint catalogue needs no nupp.lua: " .. output)
   assert(output:find("unused-binding", 1, true),
      "the default catalogue is printed: " .. output)
   os.execute("rm -rf '" .. dir .. "'")
end

-- The registry's contract is that naming a command loads its grammar and nothing
-- heavier; the compiler it needs is required inside `run`. Checked in a fresh
-- interpreter, since this process has long since loaded everything.
function M.aCommandModuleDoesNotLoadTheCompilerItRuns()
   local runtimePipe = assert(io.popen(("'%s/../scripts/toolchain' luajit")
      :format(HERE)))
   local runtime = assert(runtimePipe:read("*l")) .. "/bin/luajit"
   runtimePipe:close()
   local probe = ([[
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
]]):format(package.path)
   local script = os.tmpname()
   local file = assert(io.open(script, "wb"))
   file:write(probe)
   file:close()
   local pipe = assert(io.popen(("'%s' '%s' 2>&1"):format(runtime, script)))
   local out = pipe:read("*a")
   pipe:close()
   os.remove(script)
   assert(out == "done\n",
      "requiring a command module loads its grammar, not the compiler:\n" .. out)
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
   assert(code == 1, "a broken manifest fails the check rather than " ..
      "checking the file standalone: " .. output)
   assert(output:find("cannot load nupp.lua", 1, true),
      "the load error is what is reported: " .. output)
   local report = json.decode(captureJsonAt(dir, "check --json m.nupp"))
   assert(report.ok == false and report.diagnostics[1].file == "nupp.lua",
      "--json carries the same failure as a diagnostic about the manifest")
   os.remove(dir .. "/nupp.lua")
   local _, standalone = captureStatusAt(dir, "check m.nupp")
   assert(standalone == 0, "and without a manifest the file is checked on its own")
   os.execute("rm -rf '" .. dir .. "'")
end

function M.initListRefusesAJsonSpellingItCannotProduce()
   local output, code = captureStatusAt(HERE, "init --list --json")
   assert(code ~= 0, "--list cannot satisfy the scaffold JSON schema")
   assert(output:find("--list has no JSON output", 1, true),
      "the unsupported combination is explicit: " .. output)
   assert(output:sub(1, 1) ~= "{", "template text is not mislabeled JSON")
end

function M.backendRuntimePreservesMultilineSeamFailures()
   local dir = os.tmpname()
   os.remove(dir)
   assert(os.execute("mkdir -p '" .. dir .. "'") == 0)
   local manifest = assert(io.open(dir .. "/nupp.lua", "wb"))
   manifest:write('return {include = {"."}}\n')
   manifest:close()
   local backend = assert(io.open(dir .. "/brokenbackend.g.nupp", "wb"))
   backend:write([[
module brokenbackend
const Backend = require("nupp.runtime.backend")
const JSON = require("nupp.runtime.seam.json")
export = Backend.new("broken", {JSON.seam("brokenprovider"),})
]])
   backend:close()
   local provider = assert(io.open(dir .. "/brokenprovider.g.nupp", "wb"))
   provider:write([[
module brokenprovider
local provider: any = {NULL = {}, EMPTY_ARRAY = {}, EMPTY_OBJECT = {}}
local function same(value: any): any return value end
provider.arrayOf = same
provider.asArray = same
provider.asObject = same
provider.isArray = same
provider.decode = same
provider.encoded = same
provider.encodedString = same
provider.pull = same
provider.serialize = same
provider.verified = same
provider.verifiedString = same
provider.writer = same
function provider.encode(value: any): string
   error("first seam line\nsecond seam line", 0)
end
export = provider
]])
   provider:close()
   local runtimePipe = assert(io.popen(("'%s/../scripts/toolchain' luajit")
      :format(HERE)))
   local runtime = assert(runtimePipe:read("*l")) .. "/bin/luajit"
   runtimePipe:close()

   local output = captureJsonAt(dir,
      ("backend test brokenbackend --runtime '%s' --json"):format(runtime))
   local report = json.decode(output)
   assert(not report.ok and #report.seams == 1,
      "the deliberately broken seam is reported: " .. output)
   assert(report.seams[1].problem:find("first seam line\nsecond seam line", 1, true),
      "the line-based runtime report reconstructs the complete failure")
   os.execute("rm -rf '" .. dir .. "'")
end

function M.ownershipAuditEnumeratesForeignContractsAndUnsafeSites()
   local dir = os.tmpname()
   os.remove(dir)
   assert(os.execute("mkdir -p '" .. dir .. "'") == 0)
   local source = assert(io.open(dir .. "/surface.g.nupp", "wb"))
   source:write(table.concat({
      "cdef function lookup(borrows key: const char*,",
      "   out value: voidptr* borrows (key)): int32",
      "cdef function visit(borrows values: const int32* countedBy(count), count: uint64)",
      "unsafe do",
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
   }, "\n"))
   source:close()

   local report = json.decode(captureJson(("ownership-audit --json '%s/surface.g.nupp'")
      :format(dir)))
   assert(#report.foreign == 2, "both foreign declarations are reported")
   assert(report.foreign[1].name == "lookup", "the trusted function is named")
   assert(report.foreign[1].parameters[1].contract == "borrows",
      "the pointer parameter contract survives checking")
   assert(#report.foreign[1].results == 1,
      "the derived pointer result is included")
   assert(report.foreign[2].countedBy[1].pointer == "values"
      and report.foreign[2].countedBy[1].count == "count"
      and report.foreign[2].countedBy[1].access == "read",
      "counted pointer relationships survive checking")
   assert(report.foreign[2].zeroCount:find("calls once", 1, true),
      "the audit reports the foreign zero-count promise")
   assert(#report.unsafe == 3 and report.unsafe[1].line == 4,
      "the explicit unsafe boundary, operation, and contract are enumerable")
   assert(report.unsafe[2].kind == "unchecked C memory indexing",
      "the report names the trusted raw operation")
   assert(report.unsafe[3].kind == "ownership contract: partitioned result fields",
      "the report names a trusted partition contract")
   assert(report.regions == nil, "automatic regions remain opt-in")

   local regions = json.decode(captureJson((
      "ownership-audit --json --regions '%s/surface.g.nupp'"
   ):format(dir))).regions
   assert(#regions == 1 and regions[1].owners[1].name == "value",
      "automatic cleanup sites are enumerable")
   assert(regions[1].id:find("function:", 1, true)
      and regions[1].activationOrder[1] == "value"
      and regions[1].cleanupOrder[1] == "value",
      "region identity and ordering are semantic and deterministic")
   assert(regions[1].lowering == "general",
      "the audit reports the selected protected lowering")

   local schema = json.decode(captureJson("ownership-audit --schema"))
   assert(schema.properties.foreign and schema.properties.unsafe
      and schema.properties.regions,
      "the machine report has a discoverable schema")
   os.execute("rm -rf '" .. dir .. "'")
end

function M.ownershipAuditFindsInlineAssertionsAndAffineCResults()
   local dir = os.tmpname()
   os.remove(dir)
   assert(os.execute("mkdir -p '" .. dir .. "'") == 0)
   local source = assert(io.open(dir .. "/inline.g.nupp", "wb"))
   source:write(table.concat({
      "cdef function free(takes value: voidptr)",
      "cdef function acquire(size: uint64): affine(voidptr, free)",
      "local raw: voidptr",
      "local owner = unsafe adopt raw as affine(voidptr, free)",
      "local released = unsafe release owner",
      "return released",
      "",
   }, "\n"))
   source:close()

   local report = json.decode(captureJson(("ownership-audit --json '%s/inline.g.nupp'")
      :format(dir)))
   assert(#report.foreign == 2 and report.foreign[2].name == "acquire",
      "an affine C result is a trusted ownership contract")
   assert(#report.foreign[2].results == 1
      and report.foreign[2].results[1].type:find("affine(voidptr", 1, true),
      "the affine result is described")
   assert(#report.unsafe == 2
      and report.unsafe[1].kind == "ownership assertion: adopt"
      and report.unsafe[2].kind == "ownership assertion: release",
      "inline ownership assertions are listed outside unsafe-do regions")
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
   assert(syntax:find("broken.nupp:1", 1, true),
      "the parse failure names its source: " .. syntax)

   local missing, missingCode = captureStatusAt(dir, "ownership-audit absent.nupp")
   assert(missingCode ~= 0, "unreadable input fails the audit")
   assert(missing:find("cannot read absent.nupp", 1, true),
      "the read failure is reported: " .. missing)
   os.execute("rm -rf '" .. dir .. "'")
end

-- Half of a cold self-build is the trace compiler, so a compiler run raises LuaJIT's
-- side-trace threshold. A resident or program-running command must not: `lsp` amortizes
-- its traces across a session, and `run` and `task` execute somebody else's program.
local function flagsAppliedBy(command, env)
   local applied = {}
   local realStart, realGetenv, realWrite = jit.opt.start, os.getenv, io.write
   jit.opt.start = function(...) applied[#applied + 1] = table.concat({...}, ",") end
   os.getenv = function(name) return (env or {})[name] or realGetenv(name) end
   io.write = function() end
   pcall(cli.main, {command, "--help"})
   jit.opt.start, os.getenv, io.write = realStart, realGetenv, realWrite
   return table.concat(applied, " ")
end

local function assertFlags(command, want, env, label)
   local got = flagsAppliedBy(command, env)
   assert(got == want, ("%s: %s\n  want: %q\n  got:  %q")
      :format(command, label or "wrong jit flags", want, got))
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
   assertFlags("build", "hotexit=60,hotloop=100", {NUPP_JIT_TUNE = "hotexit=60,hotloop=100"},
      "NUPP_JIT_TUNE is how a sweep moves them")
end

return M
