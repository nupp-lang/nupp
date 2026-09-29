-- Command-line semantic operations, driven through the real launcher.
local json = require("testjson")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
if not HERE:match("^/") then
   local pipe = assert(io.popen("pwd"))
   HERE = pipe:read("*l") .. "/" .. HERE
   pipe:close()
end
local NUPP = HERE .. "/../bin/nupp"

local function tempProject(files)
   local dir = os.tmpname()
   os.remove(dir)
   assert(os.execute("mkdir -p '" .. dir .. "'") == 0)
   for name, source in pairs(files) do
      local file = assert(io.open(dir .. "/" .. name, "wb"))
      file:write(source)
      file:close()
   end
   return dir
end

local function capture(dir, command)
   local pipe = assert(io.popen(("cd '%s' && '%s' %s 2>&1")
      :format(dir, NUPP, command)))
   local output = pipe:read("*a")
   pipe:close()
   return output
end

-- `--json` promises a clean stdout, so a JSON capture must not fold stderr into
-- it. The launcher writes "building the compiler" there when the cache is cold,
-- which never happens in a warm single-suite run and lands in front of the
-- payload under a full parallel one.
local function captureJson(dir, command)
   local pipe = assert(io.popen(("cd '%s' && '%s' %s")
      :format(dir, NUPP, command)))
   local output = pipe:read("*a")
   pipe:close()
   return output
end

local function readFile(path)
   local file = assert(io.open(path, "rb"))
   local source = file:read("*a")
   file:close()
   return source
end

local function contains(text, wanted, label)
   assert(text:find(wanted, 1, true),
      (label or "missing text") .. ": " .. wanted .. " in\n" .. text)
end

local LIB = table.concat({
   "local lib = {}",
   "",
   "--- Double a value.",
   "function lib.double(value: number): number",
   "    return value * 2",
   "end",
   "",
   "record lib.Widget",
   "    value: number",
   "end",
   "",
   "return lib",
   "",
}, "\n")

local MAIN = table.concat({
   "local lib = require(\"lib\")",
   "local answer = lib.double(21)",
   "print(answer)",
   "",
}, "\n")

local function project()
   return tempProject({
      ["nupp.lua"] = 'return {include = {"."}}\n',
      ["lib.nupp"] = LIB,
      ["main.nupp"] = MAIN,
   })
end

local M = {}

function M.inspectDefinitionReferencesAndSymbols()
   local dir = project()

   local inspected = json.decode(captureJson(dir,
      "lsp inspect --json main.nupp 2 20"))
   assert(inspected.symbol.name == "double", "inspect names the member")
   assert(inspected.symbol.kind == "function", "inspect reports its kind")
   assert(inspected.symbol.detail:find("function lib.double", 1, true),
      "inspect includes the written signature")
   assert(inspected.symbol.documentation == "Double a value.",
      "inspect includes its documentation")
   assert(inspected.symbol.definition.file == "lib.nupp",
      "inspect includes the cross-file definition")

   local definition = json.decode(captureJson(dir,
      "lsp definition --json main.nupp 2 20"))
   assert(definition.definition.file == "lib.nupp",
      "definition reaches the module member")
   assert(definition.definition.range.start.line == 4,
      "definition uses one-based lines")

   local definitionSchema = json.decode(captureJson(dir,
      "lsp definition --schema"))
   assert(definitionSchema.properties.definitions,
      "the definition operation advertises contributing declarations")
   local inspectSchema = json.decode(captureJson(dir, "lsp inspect --schema"))
   assert(not inspectSchema.definitions.symbol.properties.definitions,
      "the definition-only property is not attached to inspected symbols")

   local references = json.decode(captureJson(dir,
      "lsp references --json --include-declaration main.nupp 2 20"))
   assert(#references.references == 2,
      "references includes declaration and use")
   assert(references.declarationIncluded == true,
      "references records declaration policy")

   local workspace = json.decode(captureJson(dir, "lsp symbols --json Widget"))
   assert(#workspace.symbols == 1, "workspace symbols filters by name")
   assert(workspace.symbols[1].name == "Widget", "workspace symbol is named")
   assert(workspace.symbols[1].file == nil,
      "symbol location stays nested rather than duplicating paths")
   assert(workspace.symbols[1].location.file == "lib.nupp",
      "workspace symbol carries a project-relative location")

   local document = json.decode(captureJson(dir,
      "lsp symbols --json --file lib.nupp double"))
   assert(#document.symbols == 1 and document.symbols[1].name == "lib.double",
      "document symbols expose the source outline")

   os.execute("rm -rf '" .. dir .. "'")
end

function M.inspectCarriesTheAutomaticCleanupBoundary()
   local dir = tempProject({
      ["nupp.lua"] = 'return {include = {"."}}\n',
      ["owner.nupp"] = table.concat({
         "local record Handle",
         "   name: string",
         "end",
         "local function close_handle(value: Handle)",
         "end",
         "local function open_handle(): affine(Handle, close_handle)",
         "   return new Handle(name = 'a')",
         "end",
         "local function work()",
         "   local handle = open_handle()",
         "   print(handle.name)",
         "end",
         "",
      }, "\n"),
   })
   local inspected = json.decode(captureJson(dir,
      "lsp inspect --json owner.nupp 11 10"))
   local cleanup = inspected.symbol.automaticCleanup
   assert(cleanup and cleanup.status == "automatic" and cleanup.line == 11,
      "inspect preserves the checker's cleanup boundary")
   assert(cleanup.cleanups[1] == "close_handle",
      "inspect names the cleanup that runs there")
   os.execute("rm -rf '" .. dir .. "'")
end

function M.traceCheckInspectsOneFunctionWithoutAddingAContract()
   local dir = tempProject({
      ["nupp.lua"] = 'return {include = {"."}}\n',
      ["hot.g.nupp"] = table.concat({
         "local function hot(values: {integer}): integer",
         "   local total = 0",
         "   for i = 1, #values do",
         "      local add = function(): integer return values[i] end",
         "      total = total + add()",
         "   end",
         "   return total",
         "end",
         "return hot({1, 2, 3})",
         "",
      }, "\n"),
   })
   local checked = json.decode(captureJson(dir,
      "lsp trace-check --json hot.g.nupp 5 7"))
   assert(checked.functionName == "hot", "the enclosing function is selected")
   assert(checked.contract == "inspection", "manual inspection does not add @jit")
   assert(checked.addContract and checked.addContract.newText:find("@jit", 1, true),
      "the result offers an explicit contract edit without applying it")
   local reasons = {}
   for _, finding in ipairs(checked.findings) do reasons[finding.reason] = finding end
   assert(reasons["jit/loop-function-construction"],
      "the source blocker uses the shared reason identity")
   assert(checked.traceProfile.id and checked.reasonCatalog.version == 1,
      "profile and catalog identities travel with the answer")
   os.execute("rm -rf '" .. dir .. "'")
end

-- `@jit` decorates a declaration. A function expression has no statement of its own
-- to carry it, and the offer used to splice the whole line prefix in front of it:
-- `local f = @jit\nlocal f = function`.
function M.traceCheckOffersNoContractForAFunctionExpression()
   local dir = tempProject({
      ["nupp.lua"] = 'return {include = {"."}}\n',
      ["expr.g.nupp"] = table.concat({
         "local hot = function(values: {integer}): integer",
         "   local total = 0",
         "   for i = 1, #values do",
         "      local add = function(): integer return values[i] end",
         "      total = total + add()",
         "   end",
         "   return total",
         "end",
         "return hot({1, 2, 3})",
         "",
      }, "\n"),
   })
   local checked = json.decode(captureJson(dir,
      "lsp trace-check --json expr.g.nupp 5 7"))
   assert(checked.findings and #checked.findings > 0, "the expression is inspected")
   assert(checked.addContract == nil or checked.addContract == json.null,
      "no contract edit is offered for a function expression: "
      .. tostring(checked.addContract and checked.addContract.newText))
   os.execute("rm -rf '" .. dir .. "'")
end

function M.traceCheckIncludesARepairableNoncapturingClosure()
   local dir = tempProject({
      ["nupp.lua"] = 'return {include = {"."}}\n',
      ["hot.g.nupp"] = table.concat({
         "local function hot(values: {integer}): nil",
         "   for _, value in ipairs(values) do",
         "      register(function(): integer return 1 end)",
         "   end",
         "end",
         "return hot",
         "",
      }, "\n"),
   })
   local checked = json.decode(captureJson(dir,
      "lsp trace-check --json hot.g.nupp 2 4"))
   local found
   for _, finding in ipairs(checked.findings) do
      if finding.reason == "jit/loop-function-construction" then found = finding end
   end
   assert(found and found.class == "blocker",
      "manual inspection agrees with bytecode and @jit for every FNEW: "
      .. json.encode(checked))
   os.execute("rm -rf '" .. dir .. "'")
end

function M.traceCheckFollowsAnExactImportedCallee()
   local dir = tempProject({
      ["nupp.lua"] = 'return {include = {"."}}\n',
      ["lib.g.nupp"] = table.concat({
         "local lib = {}",
         "function lib.bad(values: {integer}): integer",
         "   local total = 0",
         "   for i = 1, #values do",
         "      local add = function(): integer return values[i] end",
         "      total = total + add()",
         "   end",
         "   return total",
         "end",
         "return lib",
         "",
      }, "\n"),
      ["main.g.nupp"] = table.concat({
         "local lib = require('lib')",
         "@jit",
         "local function hot(values: {integer}): integer",
         "   return lib.bad(values)",
         "end",
         "return hot({1, 2, 3})",
         "",
      }, "\n"),
   })
   local checked = json.decode(captureJson(dir,
      "lsp trace-check --json main.g.nupp 4 8"))
   local found
   for _, finding in ipairs(checked.findings) do
      if finding.reason == "jit/loop-function-construction" then found = finding end
   end
   assert(found, "the exported callee transports its trace summary")
   assert(#found.callPath >= 2 and found.callPath[1] == "hot",
      "the imported call path starts at the inspected function")
   local diagnostics = json.decode(captureJson(dir, "check --json main.g.nupp"))
   local contractError
   for _, diagnostic in ipairs(diagnostics.diagnostics or {}) do
      if diagnostic.code == "NUPP2707" then contractError = diagnostic end
   end
   assert(contractError and contractError.message:find("jit/loop-function-construction", 1, true),
      "@jit enforces the transported reason without running either module")
   os.execute("rm -rf '" .. dir .. "'")
end

function M.renamePreviewsThenWritesEverySemanticReference()
   local dir = project()
   local preview = json.decode(captureJson(dir,
      "lsp rename --json main.nupp 2 20 twice"))
   assert(preview.written == false, "rename previews by default")
   assert(preview.oldName == "double" and preview.newName == "twice",
      "rename identifies both spellings")
   assert(#preview.edits == 2, "rename previews declaration and use")
   assert(readFile(dir .. "/main.nupp") == MAIN,
      "preview leaves source untouched")

   local output = capture(dir, "lsp rename --write main.nupp 2 20 twice")
   contains(output, "Renamed double to twice in 2 locations across 2 files",
      "write summary")
   contains(readFile(dir .. "/lib.nupp"), "function lib.twice",
      "declaration was renamed")
   contains(readFile(dir .. "/main.nupp"), "lib.twice(21)",
      "use was renamed")
   assert(capture(dir, "check main.nupp lib.nupp") == "",
      "renamed project checks clean")

   os.execute("rm -rf '" .. dir .. "'")
end

-- A rename that would rebind a name is refused and writes nothing: a member the
-- module already declares, and a local whose new name a later declaration
-- already holds, where the calls would silently run the other function.
function M.renameRefusesToRebindANameAndWritesNothing()
   local main = "local function first(): string\n    return \"first\"\nend\n\n"
      .. "local function second(): string\n    return \"second\"\nend\n\n"
      .. "print(first(), second())\n"
   local lib = "local lib = {}\n\nfunction lib.double(value: number): number\n    return value * 2\nend\n\n"
      .. "function lib.triple(value: number): number\n    return value * 3\nend\n\nreturn lib\n"
   local dir = tempProject({
      ["lib.nupp"] = lib,
      ["main.nupp"] = main,
   })
   local output = capture(dir, "lsp rename --write main.nupp 1 16 second 2>&1; echo rc=$?")
   contains(output, "rc=1", "the capturing rename fails")
   contains(output, "second at main.nupp:9:7", "the refusal names the captured use")
   assert(readFile(dir .. "/main.nupp") == main, "a refused rename writes nothing")

   output = capture(dir, "lsp rename --write lib.nupp 3 14 triple 2>&1; echo rc=$?")
   contains(output, "rc=1", "the colliding member rename fails")
   contains(output, "already declares a member named triple", "the refusal names the member")
   assert(readFile(dir .. "/lib.nupp") == lib, "a refused member rename writes nothing")
   os.execute("rm -rf '" .. dir .. "'")
end

function M.actionsAndJsonDiagnosticsAreMachineReadable()
   local dir = tempProject({
      ["nupp.lua"] = [[return {
   include = {"."},
   build = {
      default = "app",
      targets = {app = {kind = "modules", entries = {"point"}}},
   },
}
]],
      ["point.nupp"] = "local shapes = {}\nrecord Point\n"
         .. "    x: number\nend\nreturn shapes\n",
   })
   local actions = json.decode(captureJson(dir,
      "lsp actions --json --only quickfix point.nupp 2 8"))
   assert(#actions.actions == 3, "the three visibility fixes are exposed")
   local titles = {}
   for _, action in ipairs(actions.actions) do titles[#titles + 1] = action.title end
   contains(table.concat(titles, "|"), "mark it local", "local action")
   contains(table.concat(titles, "|"), "mark it global", "global action")
   -- Nothing produces a refactoring, so offering the kind would answer an empty list
   -- that cannot be told apart from "none here".
   contains(capture(dir, "lsp actions --only refactor point.nupp 2 8; echo \"__exit__:$?\""),
      "__exit__:2", "refactor is not an action kind")

   local checked = json.decode(captureJson(dir, "check --json point.nupp"))
   assert(#checked.diagnostics == 1, "JSON check emits one diagnostic")
   assert(checked.diagnostics[1].code == "NUPP2119",
      "JSON check preserves the diagnostic code")
   assert(checked.diagnostics[1].severity == "error",
      "JSON check preserves severity")
   assert(#checked.diagnostics[1].fixes == 3,
      "JSON check preserves machine-applicable fixes")
   assert(checked.diagnostics[1].range["end"].column
      - checked.diagnostics[1].range.start.column == #"Point",
      "JSON range covers the diagnostic token")

   local text = capture(dir, "check point.nupp")
   contains(text, "2 | record Point", "text diagnostic includes source")
   contains(text, "^~~~~", "text diagnostic underlines the complete name")

   local projectCheck = json.decode(captureJson(dir, "check --json"))
   assert(#projectCheck.diagnostics == 1
      and projectCheck.diagnostics[1].code == "NUPP2119",
      "project checking uses the same JSON diagnostic contract")

   os.execute("rm -rf '" .. dir .. "'")
end

function M.refinementAndSpellingFixesReachLanguageActions()
   local dir = tempProject({
      ["nupp.lua"] = 'return {include = {"."}}\n',
      ["main.nupp"] = "local wide: integer = 5\n"
         .. "local small: int32 = wide\n",
      ["field.nupp"] = "local p: {horizontal: number} = {horizontal = 1}\n"
         .. "print(p.horizonal)\n",
   })
   local narrowing = json.decode(captureJson(dir,
      "lsp actions --json --only quickfix main.nupp 2 22"))
   assert(#narrowing.actions == 2, "refinement error reaches the LSP")
   assert(narrowing.actions[1].title == "convert with `nupp.math.i32.wrap`",
      "the establishing conversion is offered")
   assert(narrowing.actions[2].title == "change the type to `integer`",
      "the identity-preserving widening is offered")

   local spelling = json.decode(captureJson(dir,
      "lsp actions --json --only quickfix field.nupp 2 9"))
   assert(#spelling.actions == 1, "field typo exposes one safe fix")
   assert(spelling.actions[1].title == "change to `horizontal`")

   local checked = json.decode(captureJson(dir, "check --json field.nupp"))
   local diagnostic = checked.diagnostics[1]
   assert(diagnostic.range["end"].column - diagnostic.range.start.column
      == #"horizonal", "JSON carries the complete token range")
   assert(diagnostic.help and diagnostic.help:find("suggested", 1, true),
      "JSON preserves structured help")
   os.execute("rm -rf '" .. dir .. "'")
end

function M.jsonDiagnosticsCarryCrossFileRelatedRanges()
   local dir = tempProject({
      ["nupp.lua"] = [[return {
   include = {"."},
   build = {entries = {"use"}},
}
]],
      ["a.nupp"] = "global record Shared end\n",
      ["b.nupp"] = "global record Shared end\n",
      ["use.nupp"] = "local value: Shared?\nreturn value\n",
   })
   local checked = json.decode(captureJson(dir, "check --json"))
   local diagnostic = checked.diagnostics[1]
   assert(diagnostic and diagnostic.code == "NUPP2102",
      "ambiguous global is serialized")
   assert(#diagnostic.related == 2,
      "JSON carries both conflicting declaration locations")
   for _, related in ipairs(diagnostic.related) do
      assert(related.file:match("[ab]%.nupp$"), "related file is identified")
      assert(related.range["end"].column - related.range.start.column
         == #"Shared", "related range covers the declaration name")
   end
   os.execute("rm -rf '" .. dir .. "'")
end

-- The artifact operations, which are what a client other than VS Code has.
--
-- An editor reaches the inspector over the protocol; everything else -- a
-- script, an agent, somebody at a terminal -- reaches the same answers here, and
-- a request with no command-line face is a request only one client can use.

local ARTIFACT_PROJECT = {
   ["nupp.lua"] = 'return {include = {"."}}\n',
   ["sample.nupp"] = table.concat({
      "local function scale(values: {number}, by: number): number",
      "    local total = 0",
      "    for _, value in ipairs(values) do",
      "        total = total + value * by",
      "    end",
      "",
      "    return total",
      "end",
      "",
      "return scale",
   }, "\n") .. "\n",
}

function M.artifactsListsWhatIsAvailableAndNamesTheEnclosingFunction()
   local dir = tempProject(ARTIFACT_PROJECT)
   local decoded = json.decode(captureJson(dir, "lsp artifacts --json sample.nupp 4 9"))
   os.execute("rm -rf '" .. dir .. "'")
   local kinds = {}
   for _, entry in ipairs(decoded.artifacts) do
      kinds[entry.kind] = entry
   end
   assert(kinds.lua and kinds.bytecode, "both kinds are listed")
   assert(kinds.lua.scope == "module", "generated Lua is a whole-file artifact")
   assert(decoded["function"].name == "scale", "the enclosing function is named")
   assert(decoded["function"].range.start.line == 1, "and positioned in source coordinates")
end

function M.artifactTakesTheOptimizationLevelEveryCommandSpells()
   local dir = tempProject(ARTIFACT_PROJECT)
   local optimized = json.decode(captureJson(dir, "lsp artifact --kind lua -O2 --json sample.nupp"))
   local spaced = capture(dir, "lsp artifact --kind lua -O 2 sample.nupp; echo \"__exit__:$?\"")
   local long = capture(dir, "lsp artifact --kind lua --opt-level 2 sample.nupp; echo \"__exit__:$?\"")
   os.execute("rm -rf '" .. dir .. "'")
   assert(optimized.available, "-O2 resolves an artifact")
   contains(spaced, "__exit__:2", "-O takes its level attached, as build and run do")
   contains(long, "__exit__:2", "--opt-level is not an option")
end

function M.artifactPrintsGeneratedLuaLineForLine()
   local dir = tempProject(ARTIFACT_PROJECT)
   local text = captureJson(dir, "lsp artifact --kind lua sample.nupp")
   local decoded = json.decode(captureJson(dir, "lsp artifact --kind lua --json sample.nupp"))
   os.execute("rm -rf '" .. dir .. "'")
   contains(text, "total = total + value * by", "the authored line is in the generated Lua")
   assert(decoded.available, "the file lowers")
   assert(decoded.mapping.kind == "line-identity", "generated Lua is line-identical to its source")
   local generated, source = 0, 0
   for _ in decoded.text:gmatch("\n") do
      generated = generated + 1
   end
   for _ in ARTIFACT_PROJECT["sample.nupp"]:gmatch("\n") do
      source = source + 1
   end
   assert(generated == source, "the lowering did not change the line count")
end

function M.artifactPrintsABytecodeListingLaidOutAgainstTheSource()
   local dir = tempProject(ARTIFACT_PROJECT)
   local decoded = json.decode(captureJson(dir, "lsp artifact --kind bytecode --json sample.nupp"))
   os.execute("rm -rf '" .. dir .. "'")
   assert(decoded.available, "the file compiles")
   assert(decoded.mapping.kind == "lines-collapsible", "a listing carries its correspondence")
   contains(decoded.text, "instructions of runtime preamble", "the preamble is named apart")
   assert(not decoded.text:find("local total = 0", 1, true),
      "the listing does not repeat the source it is laid against")
   local lines = {}
   for line in (decoded.text .. "\n"):gmatch("(.-)\n") do
      lines[#lines + 1] = line
   end
   -- Folding the indented runs leaves one row per source line.
   local visibleAt, visible = {}, 0
   for index, line in ipairs(lines) do
      if not line:match("^%s%s") then
         visible = visible + 1
      end
      visibleAt[index] = visible
   end
   for _, entry in ipairs(decoded.mapping.entries) do
      if entry.role == "exact" then
         assert(visibleAt[entry.generatedLine] == entry.sourceLine,
            ("folded row %d should be source line %d"):format(
               visibleAt[entry.generatedLine], entry.sourceLine))
      end
   end
end

function M.artifactSaysWhyItCouldNotResolveOne()
   local dir = tempProject({
      ["nupp.lua"] = 'return {include = {"."}}\n',
      ["broken.nupp"] = "local value: integer = \n",
   })
   local text = capture(dir, "lsp artifact --kind lua broken.nupp; echo \"__exit__:$?\"")
   local decoded = json.decode(captureJson(dir, "lsp artifact --kind lua --json broken.nupp"))
   os.execute("rm -rf '" .. dir .. "'")
   contains(text, "__exit__:1", "an unresolvable artifact is a failure at the terminal")
   assert(decoded.available == false, "and says so in JSON")
   assert(decoded.unavailable.reason == "not-lowered", "with the reason it refused")
end

-- Lua the generator wrote but a VM will not load is the one place the reason can
-- be read, so it is printed rather than withheld, with the problem beside it.
function M.artifactPrintsGeneratedLuaThatDoesNotLoad()
   local lines = {}
   local names = {}
   for index = 1, 61 do
      lines[#lines + 1] = ("local v%d = %d"):format(index, index)
      names[#names + 1] = "v" .. index
   end
   lines[#lines + 1] = "local function f(): number"
   lines[#lines + 1] = "    return " .. table.concat(names, " + ")
   lines[#lines + 1] = "end"
   lines[#lines + 1] = "return f()"
   local dir = tempProject({
      ["nupp.lua"] = 'return {include = {"."}}\n',
      ["many.g.nupp"] = table.concat(lines, "\n") .. "\n",
   })
   local text = capture(dir, "lsp artifact --kind lua many.g.nupp 2>&1; echo \"__exit__:$?\"")
   local decoded = json.decode(captureJson(dir, "lsp artifact --kind lua --json many.g.nupp"))
   os.execute("rm -rf '" .. dir .. "'")
   contains(text, "local function f", "the generated Lua is printed")
   contains(text, "NUPP3005", "with the reason it does not load")
   contains(text, "__exit__:0", "and the text is what was asked for")
   assert(decoded.available and decoded.problem.reason == "not-loaded", "JSON carries the problem beside it")
   assert(decoded.text:find("local function f", 1, true), "and the text")
end

-- A line or column that is not a positive integer is an argument the command
-- cannot use, which the page defines as status 2, the same as an unknown option.
-- A position the file does not have is work that was attempted, status 1.
function M.positionArgumentsThatAreNotPositionsAreUsageErrors()
   local dir = tempProject({["main.nupp"] = "local x = 1\nreturn x\n"})
   for _, arguments in ipairs({"0 0", "1 abc", "1.5 2", "1"}) do
      local output = capture(dir, "lsp inspect main.nupp " .. arguments .. " 2>&1; echo \"__exit__:$?\"")
      contains(output, "__exit__:2", arguments .. " is a usage error")
      contains(output, "Try 'nupp help lsp inspect' for usage.", arguments .. " points at the help")
   end
   contains(capture(dir, "lsp inspect main.nupp 99 1 2>&1; echo \"__exit__:$?\""), "__exit__:1",
      "a line past the end is a failed attempt")
   os.execute("rm -rf '" .. dir .. "'")
end

function M.artifactOperationsPublishTheirSchemas()
   local root = HERE .. "/.."
   local discovery = json.decode(captureJson(root, "lsp artifacts --schema"))
   local resolution = json.decode(captureJson(root, "lsp artifact --schema"))
   assert(discovery.properties.artifacts, "discovery documents what it lists")
   assert(resolution.properties.mapping.properties.kind, "resolution documents its mapping")
   assert(resolution.properties.unavailable, "and documents the unavailable case")
   local help = capture(root, "lsp --help")
   contains(help, "nupp lsp artifact", "the group lists the artifact operations")
   contains(help, "artifact only:", "and attributes the options only it takes")
end

function M.groupHelpNamesServeAndTheOperations()
   local help = capture(HERE .. "/..", "lsp --help")
   contains(help, "nupp lsp serve", "explicit server help")
   contains(help, "nupp lsp rename", "rename help")
   contains(help, "nupp lsp actions", "actions help")
end

function M.groupHelpListsWhatTheOperationsParse()
   local help = capture(HERE .. "/..", "lsp --help")
   contains(help, "references only:", "an option one operation takes says which")
   contains(help, "--include-declaration", "and is the operation's own option")
   contains(help, "symbols only:", "the symbols filter is attributed")
   contains(help, "nupp lsp <operation> --schema",
      "the group's --schema entry points at the operations")
   local refusal = capture(HERE .. "/..", "lsp --schema 2>&1; echo \"__exit__:$?\"")
   contains(refusal, "nupp lsp <operation> --schema",
      "asking the group for a schema says where to ask")
   contains(refusal, "__exit__:2", "and is a usage error")
end

return M
