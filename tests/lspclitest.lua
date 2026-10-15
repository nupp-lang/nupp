-- Command-line semantic operations, driven through the real launcher.
local json = require("testjson")
local test = require("nupp.test")

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

-- Both kinds are the VM image the file lowers to, which only the VM-hosted
-- compiler produces; a LuaJIT-hosted launcher answers that it cannot.
local function requireVmCli()
   local selected = io.open(HERE .. "/../.nupp/vm-cli/current", "rb")
   if selected then
      selected:close()
   end
   test.requireCapability("vm-hosted-cli", os.getenv("NUPP_VM_CLI_IMAGE") ~= nil or selected ~= nil)
end

function M.artifactsListsWhatIsAvailableAndNamesTheEnclosingFunction()
   local dir = tempProject(ARTIFACT_PROJECT)
   local decoded = json.decode(captureJson(dir, "lsp artifacts --json sample.nupp 4 9"))
   os.execute("rm -rf '" .. dir .. "'")
   local kinds = {}
   for _, entry in ipairs(decoded.artifacts) do
      kinds[entry.kind] = entry
   end
   assert(kinds.bytecode and kinds.image, "the bytecode and the image are listed")
   assert(kinds.bytecode.scope == "module", "the bytecode is a whole-file artifact")
   assert(kinds.lua == nil, "the Lua generator's output is not an artifact")
   assert(decoded["function"].name == "scale", "the enclosing function is named")
   assert(decoded["function"].range.start.line == 1, "and positioned in source coordinates")
end

function M.artifactTakesNoOptimizationLevel()
   local dir = tempProject(ARTIFACT_PROJECT)
   local attached = capture(dir, "lsp artifact --kind bytecode -O2 sample.nupp; echo \"__exit__:$?\"")
   local lua = capture(dir, "lsp artifact --kind lua sample.nupp; echo \"__exit__:$?\"")
   os.execute("rm -rf '" .. dir .. "'")
   contains(attached, "__exit__:2", "the VM has one lowering, so -O is not an option")
   contains(lua, "__exit__:2", "and generated Lua is not a kind")
end

function M.artifactLaysTheBytecodeOutAgainstTheSource()
   requireVmCli()
   local dir = tempProject(ARTIFACT_PROJECT)
   local text = captureJson(dir, "lsp artifact --kind bytecode sample.nupp")
   local decoded = json.decode(captureJson(dir, "lsp artifact --kind bytecode --json sample.nupp"))
   os.execute("rm -rf '" .. dir .. "'")
   assert(decoded.available, "the file lowers: " .. tostring(decoded.unavailable and decoded.unavailable.detail))
   assert(decoded.text == text, "the terminal gets the artifact's text")
   assert(decoded.mapping.kind == "lines-collapsible", "the listing folds to the source's shape")
   -- Folding every indented run leaves one row per source line, so line N of
   -- the folded listing is what line N of the file compiled to.
   local rows = {}
   for row in decoded.text:gmatch("([^\n]*)\n") do
      if row:sub(1, 2) ~= "  " then
         rows[#rows + 1] = row
      end
   end
   assert(#rows == 10, "one folded row per source line, got " .. #rows .. ":\n" .. decoded.text)
   assert(rows[4]:match("^%d%d%d%d %u"), "the loop body's line holds an instruction: " .. rows[4])
   assert(rows[6] == "", "a blank line compiled to nothing")
   local fourth = false
   for _, entry in ipairs(decoded.mapping.entries) do
      fourth = fourth or entry.sourceLine == 4
      assert(entry.sourceLine >= 1 and entry.sourceLine <= 10, "an entry names a line of the file")
   end
   assert(fourth, "the mapping names the loop body")
end

function M.artifactPrintsTheModulesImageWithItsLineTable()
   requireVmCli()
   local dir = tempProject(ARTIFACT_PROJECT)
   local decoded = json.decode(captureJson(dir, "lsp artifact --kind image --json sample.nupp"))
   os.execute("rm -rf '" .. dir .. "'")
   assert(decoded.available, "the file lowers: " .. tostring(decoded.unavailable and decoded.unavailable.detail))
   contains(decoded.text, "function scale ", "the image holds the function")
   contains(decoded.text, "\n  lines ", "with its line table")
   assert(decoded.mapping.kind == "lines", "the image maps lines it can name")
   local rows = {}
   for row in decoded.text:gmatch("([^\n]*)\n") do
      rows[#rows + 1] = row
   end
   local fourth = false
   for _, entry in ipairs(decoded.mapping.entries) do
      local row = rows[entry.generatedLine]
      if entry.role == "exact" then
         assert(row and row:match("^  %u"), "an exact entry is an instruction row: " .. tostring(row))
      end
      fourth = fourth or (entry.sourceLine == 4 and entry.role == "exact")
   end
   assert(fourth, "an instruction is mapped to the loop body")
end

function M.artifactSaysWhyItCouldNotResolveOne()
   requireVmCli()
   local dir = tempProject({
      ["nupp.lua"] = 'return {include = {"."}}\n',
      ["broken.nupp"] = "local value: integer = \n",
   })
   local text = capture(dir, "lsp artifact --kind bytecode broken.nupp; echo \"__exit__:$?\"")
   local decoded = json.decode(captureJson(dir, "lsp artifact --kind bytecode --json broken.nupp"))
   os.execute("rm -rf '" .. dir .. "'")
   contains(text, "__exit__:1", "an unresolvable artifact is a failure at the terminal")
   assert(decoded.available == false, "and says so in JSON")
   assert(decoded.unavailable.reason == "not-lowered", "with the reason it refused")
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
