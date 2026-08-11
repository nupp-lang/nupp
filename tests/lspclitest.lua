-- Command-line semantic operations, driven through the real launcher.
local json = require("cjson").new()

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

   local inspected = json.decode(capture(dir,
      "lsp inspect --json main.nupp 2 20"))
   assert(inspected.symbol.name == "double", "inspect names the member")
   assert(inspected.symbol.kind == "function", "inspect reports its kind")
   assert(inspected.symbol.detail:find("function lib.double", 1, true),
      "inspect includes the written signature")
   assert(inspected.symbol.documentation == "Double a value.",
      "inspect includes its documentation")
   assert(inspected.symbol.definition.file == "lib.nupp",
      "inspect includes the cross-file definition")

   local definition = json.decode(capture(dir,
      "lsp definition --json main.nupp 2 20"))
   assert(definition.definition.file == "lib.nupp",
      "definition reaches the module member")
   assert(definition.definition.range.start.line == 4,
      "definition uses one-based lines")

   local references = json.decode(capture(dir,
      "lsp references --json --include-declaration main.nupp 2 20"))
   assert(#references.references == 2,
      "references includes declaration and use")
   assert(references.declarationIncluded == true,
      "references records declaration policy")

   local workspace = json.decode(capture(dir, "lsp symbols --json Widget"))
   assert(#workspace.symbols == 1, "workspace symbols filters by name")
   assert(workspace.symbols[1].name == "Widget", "workspace symbol is named")
   assert(workspace.symbols[1].file == nil,
      "symbol location stays nested rather than duplicating paths")
   assert(workspace.symbols[1].location.file == "lib.nupp",
      "workspace symbol carries a project-relative location")

   local document = json.decode(capture(dir,
      "lsp symbols --json --file lib.nupp double"))
   assert(#document.symbols == 1 and document.symbols[1].name == "lib.double",
      "document symbols expose the source outline")

   os.execute("rm -rf '" .. dir .. "'")
end

function M.renamePreviewsThenWritesEverySemanticReference()
   local dir = project()
   local preview = json.decode(capture(dir,
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
   local actions = json.decode(capture(dir,
      "lsp actions --json --only quickfix point.nupp 2 8"))
   assert(#actions.actions == 3, "the three visibility fixes are exposed")
   local titles = {}
   for _, action in ipairs(actions.actions) do titles[#titles + 1] = action.title end
   contains(table.concat(titles, "|"), "mark it local", "local action")
   contains(table.concat(titles, "|"), "mark it global", "global action")

   local checked = json.decode(capture(dir, "check --json point.nupp"))
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

   local projectCheck = json.decode(capture(dir, "check --json"))
   assert(#projectCheck.diagnostics == 1
      and projectCheck.diagnostics[1].code == "NUPP2119",
      "project checking uses the same JSON diagnostic contract")

   os.execute("rm -rf '" .. dir .. "'")
end

function M.manifestStrictnessAndSpellingFixesReachLanguageActions()
   local dir = tempProject({
      ["nupp.lua"] = 'return {include = {"."}, strict = true}\n',
      ["main.nupp"] = "local wide: number = 5\n"
         .. "local small: int32 = wide + 1\n",
      ["field.nupp"] = "local p: {horizontal: number} = {horizontal = 1}\n"
         .. "print(p.horizonal)\n",
   })
   local narrowing = json.decode(capture(dir,
      "lsp actions --json --only quickfix main.nupp 2 22"))
   assert(#narrowing.actions == 1, "manifest strict lint reaches the LSP")
   assert(narrowing.actions[1].title == "cast to `int32`",
      "strict lint exposes its fix")

   local spelling = json.decode(capture(dir,
      "lsp actions --json --only quickfix field.nupp 2 9"))
   assert(#spelling.actions == 1, "field typo exposes one safe fix")
   assert(spelling.actions[1].title == "change to `horizontal`")

   local checked = json.decode(capture(dir, "check --json field.nupp"))
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
   local checked = json.decode(capture(dir, "check --json"))
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

function M.explicitServeAndLegacyHelpRemainAvailable()
   local help = capture(HERE .. "/..", "lsp --help")
   contains(help, "nupp lsp serve", "explicit server help")
   contains(help, "nupp lsp rename", "rename help")
   contains(help, "nupp lsp actions", "actions help")
end

return M
