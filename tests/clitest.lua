-- The option grammar, the colour decision, and the command registry.
--
-- The grammar is tested directly rather than through the binary: every command
-- is now one declaration parsed by one loop, so the cases that used to be
-- spread across thirteen hand-written loops are worth stating once, here.
local spec = require("nupp.cli.spec")
local sharedOptions = require("nupp.cli.options")
local ansi = require("nupp.ansi")
local cli = require("nupp.cli")

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

function M.optimizerRelaxationsAreRepeatableAndClosed()
   local command = spec.command{
      name = "opt", summary = "optimizer", usage = {"nupp opt"},
      options = sharedOptions.optimize(),
   }
   local parsed = assert(command:parse({
      "--relax=frames", "--relax=function-identity",
   }))
   assert(parsed.values.relaxed.frames, "records frames")
   assert(parsed.values.relaxed["function-identity"], "records identity")
   local invalid, err = command:parse({"--relax=magic"})
   assert(invalid == nil and err:find("expected", 1, true), tostring(err))
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
   for _, name in ipairs(names) do
      assert(name ~= "", "a command has a name")
   end
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

return M
