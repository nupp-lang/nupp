local doc = require("nupp.compiler.doc")
local highlight = require("nupp.compiler.doc.highlight")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
if not HERE:match("^/") then
   local pipe = assert(io.popen("pwd"))
   HERE = pipe:read("*l") .. "/" .. HERE
   pipe:close()
end
local NUPP = os.getenv("NUPP_TEST_BIN") or HERE .. "/../bin/nupp"

local function readFile(path)
   local f = assert(io.open(path, "rb"))
   local text = f:read("*a")
   f:close()
   return text
end

local function tempProject(files)
   local dir = os.tmpname()
   os.remove(dir)
   assert(os.execute("mkdir -p '" .. dir .. "'") == 0)
   for name, text in pairs(files) do
      local sub = name:match("^(.*)/[^/]+$")
      if sub then assert(os.execute("mkdir -p '" .. dir .. "/" .. sub .. "'") == 0) end
      local f = assert(io.open(dir .. "/" .. name, "wb"))
      f:write(text)
      f:close()
   end
   return dir
end

local function capture(command)
   local pipe = assert(io.popen(command .. " 2>&1"))
   local output = pipe:read("*a")
   pipe:close()
   return output
end

local SOURCE = table.concat({
   "--- Arithmetic helpers.",
   "--- See the [guide](../guide.html).",
   "--- @module",
   "--- Adds two values.",
   "--- @param left First",
   "---     value.",
   "--- @param right Second value.",
   "--- @return Their sum.",
   "function add(left: number, right: number): number",
   "   return left + right",
   "end",
   "",
   "--- A point in two dimensions.",
   "--- @typearg T Coordinate representation.",
   "record Point<T>",
   "   --- Horizontal coordinate.",
   "   x: number",
   "   --- Vertical coordinate.",
   "   y: number",
   "end",
}, "\n") .. "\n"

local M = {}

function M.extractsStructuredDocsFromTheParserCST()
   local module, errors = doc.extract(SOURCE, "src/math.nupp", "math")
   assert(module, errors and errors[1] and errors[1].msg)
   assert(#errors == 0)
   assert(module.text == "Arithmetic helpers.\nSee the [guide](../guide.html).\nAdds two values.",
      module.text)
   assert(#module.items == 2, "expected function and record")
   local add = module.items[1]
   assert(add.name == "add" and add.kind == "function")
   assert(add.signature == "function add(left: number, right: number): number",
      add.signature)
   assert(add.params[1].text == "First value.")
   assert(add.returns[1].text == "Their sum.")
   local point = module.items[2]
   assert(point.name == "Point" and #point.members == 2)
   assert(point.typeargs[1].text == "Coordinate representation.")
   assert(point.members[1].text == "Horizontal coordinate.")
end

local DECLARATIONS = table.concat({
   "--[[",
   "# Numbers",
   "",
   "Declarations for the **number** library.",
   "]]",
   "",
   "--- Returns the largest argument.",
   "---",
   "--- @typearg V The compared type.",
   "--- @param ... The numbers to compare.",
   "--- @return The largest of them.",
   "local max: function<V>(...: V): V",
   "",
   "--- A counter.",
   "local record Counter",
   "   --- How far it has counted.",
   "   count: number",
   "",
   "   --- Advances the counter.",
   "   ---",
   "   --- @param by How much to add.",
   "   --- @return The counter itself.",
   "   step: function(c: Counter, by: number): Counter",
   "end",
}, "\n") .. "\n"

function M.documentsAFileHeaderLongCommentAsTheModule()
   local module = assert(doc.extract(DECLARATIONS, "src/num.d.nupp", "num",
      {includeAll = true}))
   assert(module.text == "# Numbers\n\nDeclarations for the **number** library.",
      module.text)
end

function M.documentsTypedBindingsAsTheFunctionsTheyDeclare()
   local module = assert(doc.extract(DECLARATIONS, "src/num.d.nupp", "num",
      {includeAll = true}))
   local max
   for _, item in ipairs(module.items) do
      if item.name == "max" then max = item end
   end
   assert(max, "typed function binding missing")
   assert(max.kind == "function", max.kind)
   assert(max.typeargs[1].name == "V" and max.typeargs[1].text == "The compared type.")
   assert(max.params[1].name == "..." and max.params[1].type == "V", max.params[1].type)
   assert(max.params[1].text == "The numbers to compare.", max.params[1].text)
   assert(max.returns[1].type == "V" and max.returns[1].text == "The largest of them.")
end

function M.documentsFunctionTypedRecordFieldsAsMethods()
   local module = assert(doc.extract(DECLARATIONS, "src/num.d.nupp", "num",
      {includeAll = true}))
   local counter
   for _, item in ipairs(module.items) do
      if item.name == "Counter" then counter = item end
   end
   assert(counter, "record missing")
   local step, count
   for _, member in ipairs(counter.members) do
      if member.name == "step" then step = member end
      if member.name == "count" then count = member end
   end
   assert(count and not count.isFunction, "data field must stay a field")
   assert(step and step.isFunction, "function-typed field must document as a method")
   assert(step.params[2].name == "by" and step.params[2].text == "How much to add.")
   assert(step.returns[1].text == "The counter itself.", step.returns[1].text)
   local markdown = doc.markdown({module})
   assert(markdown:find("#### Methods", 1, true), "methods section missing")
   assert(markdown:find("###### Arguments", 1, true), "method arguments missing")
   assert(markdown:find("| `count` | `number` |", 1, true), "fields table missing")
end

function M.documentsInheritedContractsMetamethodsAndInlineMethods()
   local source = table.concat({
      "--- A callable task.",
      "record Task<T is Value> is Named, Runnable where true",
      "   --- Builds a task.",
      "   metamethod __call: function(self, value: T): self",
      "   --- Describes it.",
      "   --- @param prefix Leading text.",
      "   --- @return Description.",
      "   function describe(prefix: string): string",
      "      return prefix",
      "   end",
      "end",
   }, "\n")
   local module = assert(doc.extract(source, "src/task.nupp", "task",
      {includeAll = true, includePrivate = true}))
   local task = module.items[1]
   assert(task.signature == table.concat({
      "record Task<T is Value> is",
      "    Named,",
      "    Runnable",
      "    where true",
      "    metamethod __call: function(self, value: T): self",
      "    function describe(prefix: string): string",
      "        return prefix",
      "    end",
      "end",
   }, "\n"), task.signature)
   assert(not task.signature:find("---", 1, true), task.signature)
   assert(task.members[1].name == "__call" and task.members[1].isMetamethod)
   assert(task.members[2].name == "describe" and task.members[2].isFunction)
   assert(task.members[2].params[1].name == "prefix")
end

function M.documentsDeclarationsWrappedInAnnotations()
   local source = table.concat({
      "--- Opens an owned handle.",
      "--- @param path Where to open it.",
      "--- @return The owned handle.",
      "@owned(close)",
      "function resources.open(path: string): LuaFile",
      "   return assert(io.open(path))",
      "end",
   }, "\n")
   local module = assert(doc.extract(source, "src/resources.nupp", "resources"))
   assert(#module.items == 1, "the annotated function was not documented")
   local open = module.items[1]
   assert(open.name == "resources.open", open.name)
   assert(open.doc.text == "Opens an owned handle.", open.doc.text)
   assert(open.params[1].text == "Where to open it.", open.params[1].text)
   assert(open.returns[1].text == "The owned handle.", open.returns[1].text)
end

function M.namespaceTagSynthesizesModulesFromAShapesFields()
   local source = table.concat({
      "--- @namespace lib",
      "local lib: {",
      "   data: {",
      "      --- Encodes a value.",
      "      encode: function(value: any): string",
      "   },",
      "   math: lib.MathLibrary",
      "}",
      "",
      "--- Scalar helpers.",
      "record lib.MathLibrary",
      "   --- Adds two numbers.",
      "   add: function(a: number, b: number): number",
      "end",
   }, "\n")
   local module, errors, extra = doc.extract(source, "src/lib.d.nupp", "lib", {includeAll = true})
   assert(module, errors and errors[1] and errors[1].msg)
   assert(#module.items == 1, "the record stays an ordinary item")
   assert(module.items[1].name == "MathLibrary", module.items[1].name)
   assert(extra and #extra == 2, extra and #extra)
   local byName = {}
   for _, mod in ipairs(extra) do
      byName[mod.name] = mod
   end
   assert(byName["lib.data"], "an inline field becomes its own module")
   assert(byName["lib.data"].items[1].name == "encode")
   assert(byName["lib.data"].items[1].kind == "function")
   assert(byName["lib.data"].items[1].doc.text == "Encodes a value.")
   assert(byName["lib.math"], "a field spelled by name follows it to the same file's record")
   assert(byName["lib.math"].items[1].name == "add")
   assert(byName["lib.math"].items[1].params[1].name == "a")
end

function M.standardDataApiHasCompleteDocumentation()
   local source = readFile(HERE .. "/../src/nupp/compiler/decls/prelude.d.nupp")
   local module, errors, extra = doc.extract(source,
      "src/nupp/compiler/decls/prelude.d.nupp", "nupp.compiler.decls.prelude")
   assert(module, errors and errors[1] and errors[1].msg)

   local data
   for _, candidate in ipairs(extra or {}) do
      if candidate.name == "nupp.data" then data = candidate end
   end
   assert(data, "the prelude did not synthesize nupp.data")
   for _, item in ipairs(data.items) do
      assert(item.doc.text ~= "", "nupp.data." .. item.name .. " has no documentation")
      for _, param in ipairs(item.params) do
         assert(param.text ~= "", "nupp.data." .. item.name .. " parameter "
            .. param.name .. " has no documentation")
      end
      for index, result in ipairs(item.returns) do
         assert(result.text ~= "", "nupp.data." .. item.name .. " return "
            .. index .. " has no documentation")
      end
   end

   local json
   for _, item in ipairs(module.items) do
      if item.name == "JSON" then json = item end
   end
   assert(json, "the prelude did not document nupp.JSON")
   for _, member in ipairs(json.members) do
      assert(member.text ~= "", "nupp.JSON." .. member.name .. " has no documentation")
      for _, param in ipairs(member.params) do
         assert(param.text ~= "", "nupp.JSON." .. member.name .. " parameter "
            .. param.name .. " has no documentation")
      end
      for index, result in ipairs(member.returns) do
         assert(result.text ~= "", "nupp.JSON." .. member.name .. " return "
            .. index .. " has no documentation")
      end
   end
end

function M.standardIOApiHasCompleteDocumentation()
   local source = readFile(HERE .. "/../src/nupp/compiler/decls/prelude.d.nupp")
   local module, errors, extra = doc.extract(source,
      "src/nupp/compiler/decls/prelude.d.nupp", "nupp.compiler.decls.prelude")
   assert(module, errors and errors[1] and errors[1].msg)

   local io
   for _, candidate in ipairs(extra or {}) do
      if candidate.name == "nupp.io" then io = candidate end
   end
   assert(io, "the prelude did not synthesize nupp.io")
   for _, item in ipairs(io.items) do
      assert(item.doc.text ~= "", "nupp.io." .. item.name .. " has no documentation")
      for _, param in ipairs(item.params) do
         assert(param.text ~= "", "nupp.io." .. item.name .. " parameter "
            .. param.name .. " has no documentation")
      end
      for index, result in ipairs(item.returns) do
         assert(result.text ~= "", "nupp.io." .. item.name .. " return "
            .. index .. " has no documentation")
      end
   end

   local expected = {
      Buffer = true,
      ByteView = true,
      Path = true,
      PathLibrary = true,
      Reader = true,
      URI = true,
      URIComponents = true,
      URILibrary = true,
      Writer = true,
   }
   local found = {}
   local path
   for _, item in ipairs(module.items) do
      if expected[item.name] then
         found[item.name] = true
         if item.name == "Path" then path = item end
         local prefix = "nupp." .. item.name
         assert(item.doc.text ~= "", prefix .. " has no documentation")
         for _, member in ipairs(item.members) do
            assert(member.text ~= "", prefix .. "." .. member.name
               .. " has no documentation")
            for _, param in ipairs(member.params) do
               assert(param.text ~= "", prefix .. "." .. member.name .. " parameter "
                  .. param.name .. " has no documentation")
            end
            for index, result in ipairs(member.returns) do
               assert(result.text ~= "", prefix .. "." .. member.name .. " return "
                  .. index .. " has no documentation")
            end
         end
      end
   end
   for name in pairs(expected) do
      assert(found[name], "the prelude did not document nupp." .. name)
   end
   assert(path, "the prelude did not document nupp.Path")
   assert(path.signature:sub(1, #"record nupp.Path\n    toString:")
      == "record nupp.Path\n    toString:", path.signature)
   assert(path.signature:sub(-#"    isRelative: function(self: nupp.Path): boolean\nend")
      == "    isRelative: function(self: nupp.Path): boolean\nend", path.signature)
   assert(not path.signature:find("---", 1, true), path.signature)
end

function M.standardMathApiHasCompleteDocumentation()
   local source = readFile(HERE .. "/../src/nupp/compiler/decls/prelude.d.nupp")
   local module, errors, extra = doc.extract(source,
      "src/nupp/compiler/decls/prelude.d.nupp", "nupp.compiler.decls.prelude")
   assert(module, errors and errors[1] and errors[1].msg)

   local mathModule
   for _, candidate in ipairs(extra or {}) do
      if candidate.name == "nupp.math" then mathModule = candidate end
   end
   assert(mathModule, "the prelude did not synthesize nupp.math")
   for _, item in ipairs(mathModule.items) do
      assert(item.doc.text ~= "", "nupp.math." .. item.name .. " has no documentation")
      for _, param in ipairs(item.params) do
         assert(param.text ~= "", "nupp.math." .. item.name .. " parameter "
            .. param.name .. " has no documentation")
      end
      for index, result in ipairs(item.returns) do
         assert(result.text ~= "", "nupp.math." .. item.name .. " return "
            .. index .. " has no documentation")
      end
   end

   local expected = {MathLibrary = true, Vec2Library = true}
   local found = {}
   for _, item in ipairs(module.items) do
      if expected[item.name] then
         found[item.name] = true
         local prefix = "nupp." .. item.name
         assert(item.doc.text ~= "", prefix .. " has no documentation")
         for _, member in ipairs(item.members) do
            assert(member.text ~= "", prefix .. "." .. member.name
               .. " has no documentation")
            for _, param in ipairs(member.params) do
               assert(param.text ~= "", prefix .. "." .. member.name .. " parameter "
                  .. param.name .. " has no documentation")
            end
            for index, result in ipairs(member.returns) do
               assert(result.text ~= "", prefix .. "." .. member.name .. " return "
                  .. index .. " has no documentation")
            end
         end
      end
   end
   for name in pairs(expected) do
      assert(found[name], "the prelude did not document nupp." .. name)
   end
end

function M.standardResourcesApiHasCompleteDocumentation()
   local source = readFile(HERE .. "/../src/nupp/resources.nupp")
   local module, errors = doc.extract(source, "src/nupp/resources.nupp",
      "nupp.resources")
   assert(module, errors and errors[1] and errors[1].msg)
   assert(#errors == 0)
   assert(module.text ~= "", "nupp.resources has no module documentation")

   local expected = {
      ["resources.open_file"] = true,
      ["resources.open_process"] = true,
      ["resources.temporary_file"] = true,
   }
   assert(#module.items == 3, "nupp.resources must document exactly three functions")
   for _, item in ipairs(module.items) do
      local prefix = item.path
      assert(expected[item.name], prefix .. " is not part of the public API")
      expected[item.name] = nil
      assert(item.kind == "function", prefix .. " is not documented as a function")
      assert(item.doc.text ~= "", prefix .. " has no documentation")
      for _, param in ipairs(item.params) do
         assert(param.text ~= "", prefix .. " parameter " .. param.name
            .. " has no documentation")
      end
      for index, result in ipairs(item.returns) do
         assert(result.text ~= "", prefix .. " return " .. index
            .. " has no documentation")
      end
      assert(#item.raises > 0, prefix .. " has no documented failure condition")
   end
   assert(next(expected) == nil, "nupp.resources is missing a public function")
end

function M.hidesPrivateMembersUnlessExplicitlyIncluded()
   local source = table.concat({
      "record Public",
      "   visible: number",
      "   _secret: number",
      "   function _calculate(): number",
      "      return 1",
      "   end",
      "end",
   }, "\n")
   local public = assert(doc.extract(source, "src/public.nupp", "public"))
   local publicRecord
   for _, item in ipairs(public.items) do
      if item.name == "Public" then publicRecord = item end
   end
   assert(#publicRecord.members == 1, "private record members leaked")
   assert(publicRecord.members[1].name == "visible")
   local complete = assert(doc.extract(source, "src/public.nupp", "public",
      {includePrivate = true}))
   local completeRecord
   for _, item in ipairs(complete.items) do
      if item.name == "Public" then completeRecord = item end
   end
   assert(#completeRecord.members == 3, "private record members were not included")
end

function M.keepsMarkdownInsideDescriptionCells()
   local module = assert(doc.extract(table.concat({
      "--- Adds.",
      "--- @param left The `left` value.",
      "function add(left: number): number return left end",
   }, "\n"), "src/math.nupp", "math"))
   local markdown = doc.markdown({module})
   assert(markdown:find("| The `left` value. |", 1, true), markdown)
end

function M.markdownMatchesTheNuppdocShape()
   local module = assert(doc.extract(SOURCE, "src/math.nupp", "math"))
   local markdown = doc.markdown({module}, "Example API")
   assert(markdown:find("# Module: `math`", 1, true))
   assert(markdown:find("```nupp\nfunction add", 1, true))
   -- the prose introduces the declaration, the signature follows it
   assert(markdown:find("Adds two values.\n\n```nupp\nfunction add", 1, true),
      markdown)
   assert(markdown:find("#### Arguments", 1, true))
   assert(markdown:find("#### Type parameters", 1, true))
   assert(markdown:find('<a id="math.Point"></a>', 1, true))
end

function M.highlightsLjppWithTheNativeLexer()
   local html = doc.highlight(table.concat({
      "--- Construct a point.",
      "local record Box",
      "   readonly point: Point",
      "   writeonly replacement: Point",
      "   point: Point",
      "end",
      "with box = openBox() do",
      "   inspect(box)",
      "end",
      "local function make(point: Point): Point",
      "   return point ?? new Point {x = 1}",
      "end",
   }, "\n"), {Point = "#math.Point"})
   assert(html:find("nuppdoc-token-comment", 1, true))
   assert(html:find("nuppdoc-token-keyword", 1, true))
   assert(html:find("nuppdoc-token-function", 1, true))
   assert(html:find("nuppdoc-token-type", 1, true))
   assert(html:find("nuppdoc-token-number", 1, true))
   assert(html:find("nuppdoc-token-operator", 1, true))
   assert(html:find("keyword-record", 1, true), html)
   assert(html:find("keyword-readonly", 1, true), html)
   assert(html:find("keyword-writeonly", 1, true), html)
   assert(html:find("keyword-with", 1, true), html)
   assert(html:find('href="#math.Point"', 1, true))
end

function M.highlightsCurrentNuppSyntaxWithTheParser()
   local html = doc.highlight(table.concat({
      "@!internal",
      "local interface Factory<P...>",
      "   constructor(...: P...)",
      "   end",
      "   matches self.ready",
      "   end",
      "end",
      "local function worker(): const unknown & Serializable",
      "   yields (number) resumes (boolean)",
      "   return new Factory()",
      "end",
   }, "\n"))
   assert(html:find("nuppdoc-token-meta", 1, true), html)
   assert(html:find(">internal</span>", 1, true), html)
   assert(html:find("keyword-constructor", 1, true), html)
   assert(html:find("keyword-matches", 1, true), html)
   assert(html:find("keyword-yields", 1, true), html)
   assert(html:find("keyword-resumes", 1, true), html)
   assert(html:find("keyword-new", 1, true), html)
   assert(html:find("nuppdoc-token-type", 1, true), html)
end

function M.linksOnlyTheDeclaredMembersOfAContainerSignature()
   local html = highlight.nuppSource(table.concat({
      "interface Buffer",
      "    length: function(self: Buffer): integer",
      "end",
   }, "\n"), nil, {length = "#Buffer.length"})
   assert(html:find('<a class="nuppdoc-code-link nuppdoc-code-link-property" '
      .. 'href="#Buffer.length"><span class="token property '
      .. 'nuppdoc-token-property">length</span></a>', 1, true), html)
   assert(not html:find('href="#Buffer.length"><span class="token variable '
      .. 'nuppdoc-token-variable">self</span>', 1, true), html)
end

function M.scintilluaLexerUnderstandsCurrentNuppSyntax()
   local root = HERE .. "/.."
   highlight.configureScintillua(root, {lexers = "docs/lexers"})
   local html = assert(highlight.scintilluaSource(table.concat({
      "@!internal",
      "local function worker<P...>(): unknown & Serializable",
      "   yields (number) resumes (boolean)",
      "   return new Factory {count = 1_000}",
      "end",
   }, "\n"), "nupp"))
   assert(html:find("nuppdoc-token-meta", 1, true), html)
   assert(html:find("keyword-yields", 1, true), html)
   assert(html:find("keyword-resumes", 1, true), html)
   assert(html:find("keyword-new", 1, true), html)
   assert(html:find("nuppdoc-token-type", 1, true), html)
   assert(html:find("nuppdoc-token-number", 1, true), html)
end

-- Without a manifest the command falls back to documenting ".", which drags
-- in every checkout, cache and worktree the project happens to contain.
-- `local` in a .d.nupp is not privacy: the prelude's bindings become globals
-- and a bundled module's locals are what it returns, so the file is public
-- surface throughout. An ordinary module keeps the opposite default.
function M.documentsDeclarationFilesWithoutAskingForEverything()
   local declarations = table.concat({
      "--- The shared limit.",
      "--- @return The limit.",
      "local limit: function(): number",
      "",
      "--- An implementation detail.",
      "--- @local",
      "local hidden: function(): number",
   }, "\n") .. "\n"
   local module = assert(doc.extract(declarations, "src/lib.d.nupp", "lib"))
   local names = {}
   for _, item in ipairs(module.items) do names[item.name] = true end
   assert(names.limit, "a declaration file must document without --all")
   assert(not names.hidden, "@local must still opt a declaration out")
   local plain = assert(doc.extract(declarations, "src/lib.nupp", "lib"))
   assert(#plain.items == 0, "an ordinary module must keep its locals private")
end

function M.documentsTheProjectSourcesRatherThanTheWholeTree()
   local dir = tempProject({
      ["nupp.lua"] = "return { include = {\"src\"} }\n",
      ["src/math.nupp"] = SOURCE,
      ["src/.worktree/copy.nupp"] = "--- A hidden copy.\nfunction copied(): number return 1 end\n",
      ["scratch/extra.nupp"] = "--- Outside the include list.\nfunction extra(): number return 2 end\n",
   })
   local output = capture(("cd '%s' && '%s' doc markdown -o api.md"):format(dir, NUPP))
   assert(output == "", output)
   local api = readFile(dir .. "/api.md")
   assert(api:find("# Module: `math`", 1, true), api)
   assert(not api:find("copied", 1, true), "documented a hidden directory")
   assert(not api:find("extra", 1, true), "documented outside the include list")
   os.execute("rm -rf '" .. dir .. "'")
end

function M.hidesPrivateSourcePathsUnlessExplicitlyIncluded()
   local dir = tempProject({
      ["src/visible.nupp"] = "function visible(): number return 1 end\n",
      ["src/_hidden.nupp"] = "function hidden(): number return 2 end\n",
      ["src/internal/secret.nupp"] = "function secret(): number return 3 end\n",
   })
   local config = {include = {"src"}}
   assert(doc.build(dir, config, {sources = {"src"}},
      {format = "markdown", output = "public.md"}) == 0)
   local public = readFile(dir .. "/public.md")
   assert(public:find("Module: `visible`", 1, true), public)
   assert(not public:find("Module: `_hidden`", 1, true), public)
   assert(not public:find("Module: `internal.secret`", 1, true), public)

   assert(doc.build(dir, config, {sources = {"src"}, includePrivate = true},
      {format = "markdown", output = "complete.md"}) == 0)
   local complete = readFile(dir .. "/complete.md")
   assert(complete:find("Module: `_hidden`", 1, true), complete)
   assert(complete:find("Module: `internal.secret`", 1, true), complete)
   os.execute("rm -rf '" .. dir .. "'")
end

function M.internalInitHidesItsDocumentationTree()
   local dir = tempProject({
      ["src/nupp/compiler/init.nupp"] = "@!internal\nreturn {}\n",
      ["src/nupp/compiler/parser.nupp"] = "function parse(): number return 1 end\n",
      ["src/public.nupp"] = "function visible(): number return 2 end\n",
   })
   local config = {include = {"src"}}
   assert(doc.build(dir, config, {sources = {"src"}},
      {format = "markdown", output = "public.md"}) == 0)
   local public = readFile(dir .. "/public.md")
   assert(public:find("Module: `public`", 1, true), public)
   assert(not public:find("Module: `nupp.compiler`", 1, true), public)
   assert(not public:find("Module: `nupp.compiler.parser`", 1, true), public)

   assert(doc.build(dir, config, {sources = {"src"}, includePrivate = true},
      {format = "markdown", output = "complete.md"}) == 0)
   local complete = readFile(dir .. "/complete.md")
   assert(complete:find("Module: `nupp.compiler`", 1, true), complete)
   assert(complete:find("Module: `nupp.compiler.parser`", 1, true), complete)
   os.execute("rm -rf '" .. dir .. "'")
end

function M.hoistsQualifiedTypesOutOfHiddenDeclarationModules()
   local dir = tempProject({
      ["src/nupp/init.nupp"] = table.concat({
         "--[[",
         "The public namespace.",
         "]]",
         "",
         "--- Makes a codec.",
         "function newJSON(): nupp.JSON end",
      }, "\n") .. "\n",
      ["src/nupp/compiler/init.nupp"] = "@!internal\nreturn {}\n",
      ["src/nupp/compiler/prelude.d.nupp"] = table.concat({
         "--- One JSON codec.",
         "interface nupp.JSON",
         "   encodeJSON: function(value: any): string",
         "end",
      }, "\n") .. "\n",
   })
   local config = {include = {"src"}}
   assert(doc.build(dir, config, {sources = {"src"}},
      {format = "site", output = "site"}) == 0)
   local public = readFile(dir .. "/site/modules/nupp/index.html")
   assert(public:find('<section class="nuppdoc-api-item" id="nupp.JSON">',
      1, true), public)
   assert(public:find('href="../../modules/nupp/index.html#nupp.JSON"',
      1, true), "qualified return type did not link to its declaration")
   assert(not io.open(dir .. "/site/modules/nupp/compiler/prelude/index.html", "rb"),
      "the hidden declaration module was documented")
   os.execute("rm -rf '" .. dir .. "'")
end

function M.constructorPatternDecidesTheConstructorsGroup()
   local files = {
      ["src/engine.nupp"] = table.concat({
         "--[[",
         "The engine.",
         "]]",
         "",
         "--- Starts one.",
         "function newEngine(): nil end",
         "",
         "--- Builds one.",
         "function makeEngine(): nil end",
      }, "\n") .. "\n",
   }
   local config = {include = {"src"}}
   local function render(settings, out)
      local dir = tempProject(files)
      settings.sources = {"src"}
      assert(doc.build(dir, config, settings, {format = "site", output = out}) == 0)
      local page = readFile(dir .. "/" .. out .. "/modules/engine/index.html")
      local markdown = readFile(dir .. "/" .. out .. "/modules/engine.md")
      os.execute("rm -rf '" .. dir .. "'")
      return page, markdown
   end

   local function constructors(page)
      return page:match("<h3>Constructors</h3>(.-)</table>")
   end
   local function functions(page)
      return page:match("<h3>Functions</h3>(.-)</table>")
   end

   local default, defaultMarkdown = render({}, "site")
   assert(constructors(default):find("newEngine", 1, true), default)
   assert(functions(default):find("makeEngine", 1, true), default)
   local defaultConstructorsAt = assert(default:find('<h2 id="constructors">Constructors',
      1, true))
   local defaultFunctionsAt = assert(default:find('<h2 id="functions">Functions',
      defaultConstructorsAt, true))
   assert(default:find('id="engine.newEngine"><h3>', defaultConstructorsAt, true)
      < defaultFunctionsAt, default)
   assert(default:find('id="engine.makeEngine"><h3>', defaultFunctionsAt, true),
      default)
   local defaultMarkdownConstructorsAt = assert(defaultMarkdown:find(
      "\n## Constructors\n", 1, true))
   local defaultMarkdownFunctionsAt = assert(defaultMarkdown:find(
      "\n## Functions\n", defaultMarkdownConstructorsAt, true))
   assert(defaultMarkdown:find("`newEngine`", defaultMarkdownConstructorsAt, true)
      < defaultMarkdownFunctionsAt, defaultMarkdown)
   assert(defaultMarkdown:find("`makeEngine`", defaultMarkdownFunctionsAt, true),
      defaultMarkdown)

   local renamed, renamedMarkdown = render({constructorPattern = "^make"}, "renamed")
   assert(constructors(renamed):find("<th>Constructor</th><th>Description</th>",
      1, true), renamed)
   assert(constructors(renamed):find("makeEngine", 1, true), renamed)
   assert(functions(renamed):find("newEngine", 1, true), renamed)
   local renamedConstructorsAt = assert(renamedMarkdown:find(
      "\n## Constructors\n", 1, true))
   local renamedFunctionsAt = assert(renamedMarkdown:find(
      "\n## Functions\n", renamedConstructorsAt, true))
   assert(renamedMarkdown:find("`makeEngine`", renamedConstructorsAt, true)
      < renamedFunctionsAt, renamedMarkdown)
   assert(renamedMarkdown:find("`newEngine`", renamedFunctionsAt, true),
      renamedMarkdown)

   -- an empty pattern is how a project says its functions are just functions
   local none, noneMarkdown = render({constructorPattern = ""}, "none")
   assert(not none:find("<h3>Constructors</h3>", 1, true), none)
   assert(none:find("<h3>Functions</h3>", 1, true), none)
   assert(not none:find('<h2 id="constructors">', 1, true), none)
   assert(none:find('<h2 id="functions">Functions', 1, true), none)
   assert(not noneMarkdown:find("\n## Constructors\n", 1, true), noneMarkdown)
   assert(noneMarkdown:find("\n## Functions\n", 1, true), noneMarkdown)
end

function M.markdownLinksNestedModulesAndReferences()
   local dir = tempProject({
      ["src/engine/init.nupp"] = table.concat({
         "--[[",
         "The engine. Sound comes out of [](engine.audio), and a run holds one",
         "[](engine.Engine).",
         "]]",
         "",
         "--- A running engine.",
         "record Engine",
         "   running: boolean",
         "end",
      }, "\n") .. "\n",
      ["src/engine/audio.nupp"] = "--[[\nAudio helpers.\n]]\nfunction play(): nil end\n",
   })
   local config = {include = {"src"}}
   assert(doc.build(dir, config, {sources = {"src"}},
      {format = "markdown", output = "api.md"}) == 0)
   local api = readFile(dir .. "/api.md")
   -- one document holds every module, so every reference in it resolves
   assert(api:find('<a id="engine"></a>', 1, true), api)
   assert(api:find("## Modules", 1, true), api)
   assert(api:find("| [`engine.audio`](#engine.audio) | Audio helpers. |", 1, true),
      api)
   assert(api:find("[`engine.audio`](#engine.audio), and a run holds one", 1, true),
      api)
   assert(api:find("[`engine.Engine`](#engine.Engine)", 1, true), api)
   os.execute("rm -rf '" .. dir .. "'")
end

function M.docsBuildTargetWritesSiteAndMarkdown()
   local dir = tempProject({
      ["nupp.lua"] = [[return {
   include = {"src"},
   build = {default = "docs", targets = {
      docs = {kind = "docs", sources = {"src"}, format = "both",
         outDir = "site", title = "Example API"},
   }},
}
]],
      ["src/math.nupp"] = SOURCE,
   })
   local checked = capture(("cd '%s' && '%s' check --target docs"):format(dir, NUPP))
   assert(checked == "", checked)
   assert(not io.open(dir .. "/site/index.html", "rb"),
      "checking a docs target must not write output")
   local output = capture(("cd '%s' && '%s' build"):format(dir, NUPP))
   assert(output == "", output)
   local html = readFile(dir .. "/site/modules/math/index.html")
   assert(html:find("nuppdoc%-shell"), "Nuppdoc layout class missing")
   assert(html:find('<span class="nuppdoc-mark">++</span>', 1, true),
      "default header mark missing")
   assert(html:find('id="math.add"', 1, true), "API anchor missing")
   assert(html:find('<a href="../guide.html">guide</a>', 1, true),
      "Markdown link missing")
   assert(html:find("nuppdoc-token-keyword", 1, true),
      "NUPP syntax highlighting missing")
   assert(readFile(dir .. "/site/api.md"):find("# Module: `math`", 1, true))
   assert(readFile(dir .. "/site/assets/style.css"):find(
      "%-%-nuppdoc%-dark%-accent"), "Nuppdoc theme tokens missing")
   os.execute("rm -rf '" .. dir .. "'")
end

function M.siteMatchesTheNuppdocPageModel()
   local dir = tempProject({
      ["nupp.lua"] = [[return {
   include = {"src"},
   build = {default = "docs", targets = {
      docs = {kind = "docs", sources = {"src"}, format = "site",
         outDir = "site", title = "Example API", name = "Example",
         description = "A small documented project.",
         public = "docs/public",
         customCss = "docs/site.css",
         logo = "images/project.svg",
         github = "https://github.com/example/project",
         pages = {
            {path = "", title = "Example", source = "docs/index.md",
               layout = "home", heroTitle = "Build with Nupp",
               heroText = "Typed LuaJIT programs without ceremony.",
               heroContent = "A brief welcome.",
               heroImage = "images/project.svg",
               heroImageAlt = "Example project icon",
               heroActions = {
                  {text = "Get started", path = "guide", theme = "brand"},
               },
               features = {
                  {title = "Fast", details = "Parse-only docs.",
                     code = "local speed: number = 1"},
               }},
            {path = "guide", title = "Guide", source = "docs/guide.md"},
            {path = "reference/details", title = "Details",
               source = "docs/details.md"},
            {path = "modules/math", title = "Arithmetic",
               source = "docs/math-overview.md"},
         },
      },
   }},
}
]],
      ["docs/index.md"] = "Welcome to the project.\n\n<!-- nupp:features -->\n\n## More details\n",
      ["docs/math-overview.md"] = table.concat({
         "Hand-written prose above the generated API.",
         "",
         "## Where to start",
         "",
         "With [](math.add), and then the [guide](guide.md).",
      }, "\n") .. "\n",
      ["docs/public/images/project.svg"] = "<svg><title>Example</title></svg>\n",
      ["docs/site.css"] = ":root{--example-project-accent:#315f58}\n",
      ["docs/guide.md"] = table.concat({
         "# Guide",
         "",
         "Human-readable setup instructions.",
         "",
         "Start from [](math.add), or from [the engine](engine).",
         "",
         "A reference in a code span is shown rather than made: `[](math.add)`.",
         "",
         "````",
         "```nupp",
         "local x = 1",
         "```",
         "<<< @docs/snippet.abnf",
         "````",
         "",
         "## After the fence",
         "",
         "Still part of the page.",
         "",
         "::: note Before you begin",
         "Use **Lunamark** inside this callout.",
         ":::",
         "",
         "## Checked workflows",
         "",
         "Build and run the example.",
         "Read the [details](details.md).",
         "",
         "```lua",
         "local answer = 42 -- highlighted Lua",
         "```",
         "",
         "```nupp",
         "local point: Point",
         "```",
         "",
         "```lua:line-numbers",
         "local first = 1",
         "local second = 2",
         "```",
         "",
         "```lua:line-numbers=41 [Excerpt]",
         "local offset = true",
         "```",
         "",
         "```glsl",
         "uniform vec4 color;",
         "```",
         "",
         "::: code-group",
         "```nupp [Nupp]",
         "local record Resource end",
         "with resource = openResource() do",
         "   dispose(resource)",
         "end",
         "```",
         "",
         "```lua [Generated Lua]",
         "local resource = openResource()",
         "dispose(resource)",
         "```",
         ":::",
         "",
      }, "\n"),
      ["docs/details.md"] = "# Details\n\nA deeper reference.\n\n"
         .. "<<< @docs/snippet.abnf\n",
      ["docs/snippet.abnf"] = 'rule = "literal" / other\n',
      ["src/math.nupp"] = SOURCE,
      ["src/engine/init.nupp"] = table.concat({
         "--[[",
         "Engine entry point.",
         "",
         "Sound comes out of [audio](engine.audio).",
         "]]",
         "",
         "--- A running engine.",
         "record Engine",
         "   running: boolean",
         "end",
         "",
         "--- Starts an engine. Hands back an [](engine.Engine) whose",
         "--- [](engine.Engine.running) is already true, and never [](nothing.at.all).",
         "function newEngine(): Engine end",
         "",
         "--- Boots the engine.",
         "function boot(): nil end",
      }, "\n") .. "\n",
      ["src/engine/audio.nupp"] = "--[[\nAudio helpers.\n]]\nfunction play(): nil end\n",
      ["src/engine/render.nupp"] = "--- Rendering helpers.\nfunction draw(): nil end\n",
      -- no engine/gpu module of its own, so that name documents as a namespace
      ["src/engine/gpu/vulkan.nupp"] = "--[[\nThe Vulkan backend.\n]]\n"
         .. "function submit(): nil end\n",
   })
   local output = capture(("cd '%s' && '%s' build"):format(dir, NUPP))
   assert(output == "", output)

   local home = readFile(dir .. "/site/index.html")
   assert(home:find("nuppdoc%-home%-hero"), home)
   assert(home:find("Build with Nupp", 1, true), home)
   assert(home:find("Typed LuaJIT programs", 1, true) < home:find(
      "A brief welcome.", 1, true), "hero content must follow the tagline")
   assert(home:find("A brief welcome.", 1, true) < home:find(
      'class="nuppdoc-hero-image"', 1, true), "hero content must remain beside the image")
   assert(home:find('class="nuppdoc-hero-image"', 1, true) < home:find(
      "Welcome to the project", 1, true), "home Markdown must follow the hero")
   assert(home:find("nuppdoc%-feature%-showcase"), home)
   assert(home:find("language%-nupp"), home)
   assert(home:find("Nupp Features", 1, true) < home:find(
      "nuppdoc%-feature%-showcase"), "feature heading must precede the showcase")
   assert(home:find("nuppdoc%-feature%-showcase") < home:find(
      "More details", 1, true), "features must follow the marked home introduction")
   assert(home:find('class="nuppdoc-logo" src="images/project.svg"',
      1, true), home)
   assert(home:find('src="images/project.svg"', 1, true), home)
   assert(readFile(dir .. "/site/images/project.svg"):find("Example", 1, true))
   assert(home:find('href="https://github.com/example/project"', 1, true), home)
   assert(home:find('href="llms.txt"', 1, true), home)
   assert(home:find('class="nuppdoc-search-button"', 1, true), home)
   assert(home:find('data-nuppdoc-search-index="assets/search-index.js"',
      1, true), home)

   local guide = readFile(dir .. "/site/guide/index.html")
   assert(guide:find('class="nuppdoc-logo" src="../images/project.svg"',
      1, true), guide)
   assert(guide:find('<span class="nuppdoc-brand-name">Example</span>',
      1, true), guide)
   assert(guide:find('class="nuppdoc%-breadcrumbs"'), guide)
   assert(guide:find('class="nuppdoc-breadcrumb-home"', 1, true), guide)
   assert(guide:find('aria-current="page">Guide', 1, true), guide)
   assert(guide:find('data-panel-toggle="sidebar"', 1, true), guide)
   assert(guide:find('data-panel-toggle="outline"', 1, true), guide)
   assert(guide:find('data-mobile-nav-toggle', 1, true), guide)
   assert(guide:find('aria-controls="nuppdoc-sidebar"', 1, true), guide)
   assert(guide:find('class="nuppdoc-page-nav"', 1, true), guide)
   assert(guide:find("Previous", 1, true), guide)
   assert(guide:find("Next", 1, true), guide)
   assert(guide:find("nuppdoc-token-keyword", 1, true),
      "Scintillua did not highlight Lua")
   assert(guide:find("nuppdoc-token-type", 1, true),
      "Scintillua did not highlight GLSL")
   assert(guide:find('class="nuppdoc-code-group" role="radiogroup"',
      1, true), "code tabs missing")
   assert(guide:find('class="nuppdoc-admonition nuppdoc-admonition-note"',
      1, true), "admonition missing")
   assert(guide:find('<p class="nuppdoc-admonition-title">Before you begin</p>',
      1, true), guide)
   assert(guide:find("Use <strong>Lunamark</strong> inside this callout.",
      1, true), guide)
   assert(guide:find('class="nuppdoc-code-tab"', 1, true),
      "code-tab labels missing")
   assert(guide:find('class="nuppdoc-code-block has-line-numbers"', 1, true), guide)
   assert(guide:find('<span class="nuppdoc-line-numbers" aria-hidden="true">'
      .. "<span>1</span><span>2</span></span>", 1, true), guide)
   -- an excerpt numbers from where it was cut, and still takes a caption
   assert(guide:find("<span>41</span></span>", 1, true), guide)
   assert(guide:find("<figcaption>Excerpt</figcaption>", 1, true), guide)
   -- a fence without the option is left alone
   assert(guide:find('<div class="nuppdoc-code-block" data-lang="glsl">', 1, true),
      guide)
   assert(guide:find(">Nupp</label>", 1, true), guide)
   assert(guide:find(">Generated Lua</label>", 1, true), guide)
   assert(guide:find("keyword-record", 1, true), guide)
   assert(guide:find("keyword-with", 1, true), guide)
   assert(guide:find('href="../modules/math/index.html#math.Point"', 1, true),
      "custom-page Nupp example did not link to the API reference")
   assert(guide:find('href="../reference/details/index.html"', 1, true),
      "configured Markdown page link was not rewritten to its public route")
   assert(guide:find('href="llms.txt"', 1, true), guide)
   assert(readFile(dir .. "/site/guide/llms.txt"):find("# Guide", 1, true))

   -- `<<< @path` fetches another file's bytes at build time rather than a page
   -- carrying a copy that can drift from it
   local details = readFile(dir .. "/site/reference/details/index.html")
   assert(details:find('<div class="nuppdoc-code-block" data-lang="abnf">', 1, true),
      details)
   assert(details:find('rule = &quot;literal&quot; / other', 1, true), details)
   assert(not details:find("<<<", 1, true),
      "embed directive was left in the rendered page")

   local module = readFile(dir .. "/site/modules/math/index.html")
   assert(module:find("Module contents", 1, true), module)
   -- Tealdoc-style category headings group the detailed declarations, and each
   -- declaration is one heading level beneath its group. The fragment still names the
   -- whole entry, so a link lands on the declaration heading.
   local typesAt = assert(module:find(
      '<section class="nuppdoc-api-group"><h2 id="types">Types', 1, true))
   local functionsAt = assert(module:find(
      '<section class="nuppdoc-api-group"><h2 id="functions">Functions', 1, true))
   local pointAt = assert(module:find(
      '<section class="nuppdoc-api-item" id="math.Point"><h3>', typesAt, true))
   local addAt = assert(module:find(
      '<section class="nuppdoc-api-item" id="math.add"><h3>', functionsAt, true))
   assert(typesAt < pointAt and pointAt < functionsAt and functionsAt < addAt, module)
   assert(not module:find('<section class="nuppdoc-api-item" id="math.add"><h2>',
      1, true), module)
   assert(module:find('href="../../modules/math/index.html#math.Point.x"',
      1, true), "record members in the complete signature must link to their docs")
   assert(module:find('<li class="nuppdoc-outline-section"><details open><summary>'
      .. '<a href="#types" title="Types">Types</a></summary><ol><li>'
      .. '<a href="#math.Point" title="Point">Point</a>', 1, true), module)
   assert(module:find('<li class="nuppdoc-outline-section"><details open><summary>'
      .. '<a href="#functions" title="Functions">Functions</a></summary><ol><li>'
      .. '<a href="#math.add" title="add">add</a>', 1, true), module)
   local moduleMarkdown = readFile(dir .. "/site/modules/math.md")
   local markdownTypesAt = assert(moduleMarkdown:find("\n## Types\n", 1, true))
   local markdownFunctionsAt = assert(moduleMarkdown:find(
      "\n## Functions\n", markdownTypesAt, true))
   assert(moduleMarkdown:find("\n### `Point`", markdownTypesAt, true)
      < markdownFunctionsAt, moduleMarkdown)
   assert(moduleMarkdown:find("\n### `add`", markdownFunctionsAt, true),
      moduleMarkdown)
   assert(not moduleMarkdown:find("\n## Records\n", 1, true), moduleMarkdown)
   assert(not moduleMarkdown:find("\n## Variables\n", 1, true), moduleMarkdown)
   assert(module:find("Functions", 1, true), module)
   assert(module:find("Types", 1, true), module)
   assert(module:find("nuppdoc%-kind%-badge"), module)
   assert(module:find("Previous", 1, true), module)

   -- a configured page whose path is a module's route is that module's
   -- overview: prose above the generated API rather than a second page beside it
   assert(module:find("<h1>Module: <code>math</code></h1>", 1, true), module)
   assert(module:find("Hand-written prose above the generated API.", 1, true),
      module)
   assert(module:find('<h2 id="where-to-start">Where to start', 1, true), module)
   -- it is ordinary page markdown, so both kinds of link still resolve
   assert(module:find('<a href="../../modules/math/index.html#math.add">'
      .. "<code>math.add</code></a>", 1, true), module)
   assert(module:find('<a href="../../guide/index.html">guide</a>', 1, true),
      module)
   -- the prose comes before the generated contents, and its headings are in the
   -- outline above them
   assert(module:find("Where to start", 1, true) < module:find("Module contents",
      1, true), "the overview must open the page")
   assert(module:find('<a href="#where-to-start" title="Where to start">',
      1, true), module)
   -- and there is one page at that route, not two
   assert(not io.open(dir .. "/site/modules/math/index.html/index.html"))
   local homePage = readFile(dir .. "/site/index.html")
   assert(not homePage:find(">Arithmetic</a>", 1, true),
      "the overview was also listed as a standalone page")
   assert(readFile(dir .. "/site/modules/math/llms.txt")
      :find("Hand-written prose above the generated API.", 1, true))
   local nestedModule = readFile(dir .. "/site/modules/engine/render/index.html")
   assert(nestedModule:find('class="nuppdoc-module-branch"', 1, true),
      nestedModule)
   assert(nestedModule:find('<code>render</code>', 1, true), nestedModule)
   assert(nestedModule:find('<details open><summary class="nuppdoc-module-branch-link">'
      .. '<a href="../../../modules/engine/index.html" aria-label="engine">'
      .. "<code>engine</code></a></summary>", 1, true), nestedModule)
   assert(not nestedModule:find("nuppdoc-module-overview", 1, true),
      "the module tree still renders an overview entry")
   local branchModule = readFile(dir .. "/site/modules/engine/index.html")
   assert(branchModule:find('<summary class="nuppdoc-module-branch-link">'
      .. '<a aria-current="page" href="../../modules/engine/index.html"',
      1, true), branchModule)

   -- a module's page lists the modules nested under it, so a namespace is
   -- somewhere a reader can arrive at rather than only pass through
   assert(branchModule:find('<h2 id="modules">Modules</h2>', 1, true), branchModule)
   assert(branchModule:find('<a href="../../modules/engine/audio/index.html">'
      .. "<code>engine.audio</code></a></td><td>Audio helpers.</td>",
      1, true), branchModule)
   assert(branchModule:find('<a href="../../modules/engine/render/index.html">',
      1, true), branchModule)
   -- engine.gpu has no module of its own, so it is a namespace: a page of its
   -- own, described by what it holds rather than by a blurb it has not got
   assert(branchModule:find('<a href="../../modules/engine/gpu/index.html">'
      .. "<code>engine.gpu</code></a></td><td>1 module</td>",
      1, true), branchModule)
   assert(branchModule:find('<a href="#modules" title="Modules">', 1, true),
      "the outline did not list the nested modules")
   assert(not readFile(dir .. "/site/modules/engine/audio/index.html")
      :find('<h2 id="modules">', 1, true),
      "a module with nothing nested under it still rendered a Modules table")

   local namespace = readFile(dir .. "/site/modules/engine/gpu/index.html")
   assert(namespace:find("<h1>Namespace: <code>engine.gpu</code></h1>", 1, true),
      namespace)
   assert(namespace:find("Nothing is required by this name itself", 1, true),
      namespace)
   assert(namespace:find('<a href="../../../modules/engine/gpu/vulkan/index.html">'
      .. "<code>engine.gpu.vulkan</code></a></td><td>The Vulkan backend.</td>",
      1, true), namespace)
   -- it holds no declarations, and nothing ever suggested it would
   assert(not namespace:find("No public declarations", 1, true), namespace)
   assert(not namespace:find("Module contents", 1, true), namespace)
   -- and it is a page this generator started writing, so no former URL points at
   -- it and it gets no redirect stub
   local stub = io.open(dir .. "/site/modules/engine/gpu.html")
   if stub then stub:close() end
   assert(not stub, "a namespace was given a legacy redirect")

   -- a constructor is grouped apart from the functions, and its kind is the
   -- word "function" on every row, so that column is left off
   assert(branchModule:find("<h3>Constructors</h3><table><thead><tr>"
      .. "<th>Constructor</th><th>Description</th>", 1, true), branchModule)
   assert(branchModule:find('<a href="#engine.newEngine"><code>newEngine</code></a>',
      1, true), branchModule)
   assert(branchModule:find("<h3>Functions</h3><table><thead><tr>"
      .. "<th>Function</th><th>Kind</th><th>Description</th>", 1, true),
      branchModule)
   assert(branchModule:find('<a href="#engine.boot"><code>boot</code></a>', 1, true),
      branchModule)

   -- a markdown link whose target names a module, a declaration, or a member is
   -- resolved to whatever documents it, so a reference is written as the name
   assert(branchModule:find('<a href="../../modules/engine/audio/index.html">audio</a>',
      1, true), branchModule)
   assert(branchModule:find('<a href="../../modules/engine/index.html#engine.Engine">'
      .. "<code>engine.Engine</code></a>", 1, true), branchModule)
   assert(branchModule:find('<a href="../../modules/engine/index.html#engine.Engine.running">'
      .. "<code>engine.Engine.running</code></a>", 1, true), branchModule)
   -- a name nothing documents still renders, rather than becoming an empty link
   assert(branchModule:find("never <code>nothing.at.all</code>", 1, true),
      branchModule)
   assert(guide:find('<a href="../modules/math/index.html#math.add">'
      .. "<code>math.add</code></a>", 1, true), guide)
   assert(guide:find('<a href="../modules/engine/index.html">the engine</a>',
      1, true), guide)
   -- a reference inside a code span is a page showing the syntax, not using it
   assert(guide:find("<code>[](math.add)</code>", 1, true), guide)

   -- a fence longer than the ones it holds keeps them, so a page can show a fenced
   -- block and an embed directive without either being acted on
   assert(guide:find("```nupp\nlocal x = 1\n```\n&lt;&lt;&lt; @docs/snippet.abnf",
      1, true), guide)
   assert(not guide:find("literal&quot; / other", 1, true),
      "an embed directive inside a fence was expanded")
   -- and everything after the fence is still on the page
   assert(guide:find('id="after-the-fence"', 1, true),
      "the four-backtick fence swallowed the rest of the page")

   assert(readFile(dir .. "/site/modules/math/llms.txt"):find(
      "# Module: `math`", 1, true))
   local engineMarkdown = readFile(dir .. "/site/modules/engine/llms.txt")
   assert(engineMarkdown:find("## Modules", 1, true), engineMarkdown)
   assert(engineMarkdown:find("| `engine.gpu` | 1 module |", 1, true),
      engineMarkdown)
   assert(readFile(dir .. "/site/modules/engine/gpu/llms.txt")
      :find("# Namespace: `engine.gpu`", 1, true))
   -- the same references in markdown: an anchor when the document holds what it
   -- names, and the bare name when it does not
   assert(engineMarkdown:find("[`engine.Engine`](#engine.Engine)", 1, true),
      engineMarkdown)
   assert(engineMarkdown:find("Sound comes out of audio.", 1, true), engineMarkdown)
   assert(readFile(dir .. "/site/llms.txt"):find("Complete documentation", 1, true))
   assert(readFile(dir .. "/site/llms-full.txt"):find("Guide", 1, true))
   local search = readFile(dir .. "/site/assets/search-index.js")
   assert(search:find("Guide › Checked workflows", 1, true), search)
   assert(search:find("Human%-readable setup instructions"), search)
   assert(search:find("API › add", 1, true), search)
   assert(search:find("API › Point.x", 1, true), search)
   local script = readFile(dir .. "/site/assets/site.js")
   assert(script:find("Search pages, headings, functions, and types.",
      1, true), script)
   assert(script:find('event.key.toLowerCase() === "k"', 1, true), script)
   assert(script:find('sidebar?.querySelector(\'a[aria-current="page"]\')',
      1, true), script)
   assert(script:find("sidebar.scrollTop +=", 1, true), script)
   local css = readFile(dir .. "/site/assets/style.css")
   assert(css:find("is%-mobile%-nav%-open"), css)
   assert(css:find("%-%-nuppdoc%-hero%-glow%-color"), css)
   assert(css:find("color%-mix%(in srgb,var%(%-%-nuppdoc%-hero%-glow%-color%)"), css)
   assert(css:find("nuppdoc%-code%-tab%-input:checked"), css)
   assert(css:find("nuppdoc%-admonition%-warning"), css)
   assert(css:find("@media print", 1, true), css)
   assert(css:find("%-%-example%-project%-accent:#315f58"), css)
   assert(css:find("clip%-path:circle%(50%% at 50%% 50%%%)"), css)
   assert(css:find("filter:drop%-shadow"), css)
   -- one mechanism clears the sticky header; two would stack into twice the gap
   assert(css:find(
      "scroll-margin-top:calc(var(--nuppdoc-header-height) + 1.4rem)",
      1, true), css)
   assert(not css:find("scroll-padding-top", 1, true), css)

   local legacy = readFile(dir .. "/site/modules/math.html")
   assert(legacy:find("math/index.html", 1, true), legacy)
   os.execute("rm -rf '" .. dir .. "'")
end

-- Markdown is lunamark's now. These are the cases the pattern-based renderer
-- it replaced got wrong, so they are the ones worth pinning.
function M.markdownIsRenderedByLunamark()
   local html = require("nupp.compiler.doc.html")
   local cases = {
      {"**a *nested* b**", "<strong>a <em>nested</em> b</strong>"},
      {"a \\*escaped\\* b", "a *escaped* b"},
      {"[l](http://x.com/a(b))", '<a href="http://x.com/a(b)">l</a>'},
      {"a * b * c * d", "a * b * c * d"},
      {"use `a * b` here", "<code>a * b</code>"},
   }
   for _, case in ipairs(cases) do
      local out = html.markdownHtml(case[1], {})
      assert(out:find(case[2], 1, true),
         ("%s\n  want: %s\n  got:  %s"):format(case[1], case[2], out))
   end
   -- Every block wraps the same way whether or not the source ended in a blank
   -- line; a table cell full of summaries depends on it.
   assert(html.markdownHtml("one\n\ntwo", {}):find("<p>two</p>", 1, true))
   -- A summary is a sentence, so the one paragraph around it goes.
   assert(html.inlineHtml("a **bold** one") == "a <strong>bold</strong> one")
end

-- Fenced regions are lifted out before lunamark sees them, which is what keeps
-- the fence options working: an info string is not something markdown parses.
function M.fencedBlocksKeepTheirOptions()
   local html = require("nupp.compiler.doc.html")
   local labeled = html.markdownHtml(
      "```lua [example.lua] :line-numbers=12\nprint(1)\n```", {})
   assert(labeled:find("nuppdoc-labeled-code", 1, true), labeled)
   assert(labeled:find("<figcaption>example.lua</figcaption>", 1, true), labeled)
   assert(labeled:find("has-line-numbers", 1, true), labeled)
   assert(labeled:find("<span>12</span>", 1, true), labeled)

   local group = html.markdownHtml(table.concat({
      "::: code-group", "", "```lua [one]", "print(1)", "```", "",
      "```sh [two]", "echo", "```", "", ":::", "", "after",
   }, "\n"), {})
   assert(group:find("nuppdoc-code-group", 1, true), group)
   assert(group:find(">one</label>", 1, true), group)
   assert(group:find(">two</label>", 1, true), group)
   -- and the prose on the far side of the block is still prose
   assert(group:find("<p>after</p>", 1, true), group)
end

-- Lunamark does not parse `:::` containers itself. The container is lifted out,
-- while its body goes through the same Lunamark parser as the surrounding page.
function M.admonitionsKeepLunamarkMarkdown()
   local html = require("nupp.compiler.doc.html")
   local out = html.markdownHtml(table.concat({
      "::: warning Check this <title>",
      "Use **strong text**, [a link](https://example.com), and a list:",
      "",
      "- first",
      "- second",
      ":::",
      "",
      "after",
   }, "\n"), {})
   assert(out:find('class="nuppdoc-admonition nuppdoc-admonition-warning"',
      1, true), out)
   assert(out:find('aria-label="Check this &lt;title&gt;"', 1, true), out)
   assert(out:find("<strong>strong text</strong>", 1, true), out)
   assert(out:find('<a href="https://example.com">a link</a>', 1, true), out)
   assert(out:find("<li>first</li>", 1, true), out)
   assert(out:find("<p>after</p>", 1, true), out)

   local default = html.markdownHtml("::: tip\nUseful.\n:::", {})
   assert(default:find(">Tip</p>", 1, true), default)

   local nested = html.markdownHtml(table.concat({
      "::: note", "Outside.", "", "::: tip", "Inside.", ":::", "",
      "```text", ":::", "```", ":::",
   }, "\n"), {})
   assert(nested:find("nuppdoc-admonition-note", 1, true), nested)
   assert(nested:find("nuppdoc-admonition-tip", 1, true), nested)
   assert(nested:find("nuppdoc-code-block", 1, true), nested)
   assert(nested:find(":::<", 1, true), nested)
end

-- The id is Nupp's slug rather than lunamark's, and each heading keeps the
-- anchor the stylesheet draws.
function M.headingsKeepTheirAnchors()
   local html = require("nupp.compiler.doc.html")
   local out = html.markdownHtml("# One `two`\n\nbody", {})
   assert(out:find('id="one-two"', 1, true), out)
   assert(out:find('class="nuppdoc-header-anchor"', 1, true), out)
   assert(out:find("<h2 ", 1, true), out) -- shifted by one by default
   assert(html.markdownHtml("# One", {}, 0):find("<h1 ", 1, true))
end

return M
