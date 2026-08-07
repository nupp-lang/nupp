local doc = require("nupp.doc")

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
   assert(task.signature == "record Task<T is Value> is Named, Runnable where true",
      task.signature)
   assert(task.members[1].name == "__call" and task.members[1].isMetamethod)
   assert(task.members[2].name == "describe" and task.members[2].isFunction)
   assert(task.members[2].params[1].name == "prefix")
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
      "enum State 'Ready' '_Internal' end",
   }, "\n")
   local public = assert(doc.extract(source, "src/public.nupp", "public"))
   local publicRecord, publicEnum
   for _, item in ipairs(public.items) do
      if item.name == "Public" then publicRecord = item else publicEnum = item end
   end
   assert(#publicRecord.members == 1, "private record members leaked")
   assert(publicRecord.members[1].name == "visible")
   assert(#publicEnum.values == 1, "private enum members leaked")
   local complete = assert(doc.extract(source, "src/public.nupp", "public",
      {includePrivate = true}))
   local completeRecord, completeEnum
   for _, item in ipairs(complete.items) do
      if item.name == "Public" then completeRecord = item else completeEnum = item end
   end
   assert(#completeRecord.members == 3, "private record members were not included")
   assert(#completeEnum.values == 2, "private enum members were not included")
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
      "   point: Point",
      "end",
      "with box = openBox() do",
      "   inspect(box)",
      "end",
      "local function make(point: Point): Point",
      "   return point ?? Point{x = 1}",
      "end",
   }, "\n"), {Point = "#math.Point"})
   assert(html:find("nuppdoc-token-comment", 1, true))
   assert(html:find("nuppdoc-token-keyword", 1, true))
   assert(html:find("nuppdoc-token-function", 1, true))
   assert(html:find("nuppdoc-token-type", 1, true))
   assert(html:find("nuppdoc-token-number", 1, true))
   assert(html:find("nuppdoc-token-operator", 1, true))
   assert(html:find("keyword-record", 1, true), html)
   assert(html:find("keyword-with", 1, true), html)
   assert(html:find('href="#math.Point"', 1, true))
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
               heroImage = "images/project.svg",
               heroImageAlt = "Example project icon",
               heroActions = {
                  {text = "Get started", path = "guide", theme = "brand"},
               },
               features = {
                  {icon = "⚡", title = "Fast", details = "Parse-only docs."},
               }},
            {path = "guide", title = "Guide", source = "docs/guide.md"},
            {path = "reference/details", title = "Details",
               source = "docs/details.md"},
         },
      },
   }},
}
]],
      ["docs/index.md"] = "Welcome to the project.\n",
      ["docs/public/images/project.svg"] = "<svg><title>Example</title></svg>\n",
      ["docs/site.css"] = ":root{--example-project-accent:#315f58}\n",
      ["docs/guide.md"] = table.concat({
         "# Guide",
         "",
         "Human-readable setup instructions.",
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
      ["docs/details.md"] = "# Details\n\nA deeper reference.\n",
      ["src/math.nupp"] = SOURCE,
      ["src/engine/init.nupp"] = "--- Engine entry point.\nfunction boot(): nil end\n",
      ["src/engine/audio.nupp"] = "--- Audio helpers.\nfunction play(): nil end\n",
      ["src/engine/render.nupp"] = "--- Rendering helpers.\nfunction draw(): nil end\n",
   })
   local output = capture(("cd '%s' && '%s' build"):format(dir, NUPP))
   assert(output == "", output)

   local home = readFile(dir .. "/site/index.html")
   assert(home:find("nuppdoc%-home%-hero"), home)
   assert(home:find("Build with Nupp", 1, true), home)
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

   local module = readFile(dir .. "/site/modules/math/index.html")
   assert(module:find("Module contents", 1, true), module)
   -- the fragment names the whole entry, so a link lands on its heading
   assert(module:find('<section class="nuppdoc-api-item" id="math.add"><h2>', 1, true),
      module)
   assert(module:find("Functions", 1, true), module)
   assert(module:find("Types", 1, true), module)
   assert(module:find("nuppdoc%-kind%-badge"), module)
   assert(module:find("Previous", 1, true), module)
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
   assert(readFile(dir .. "/site/modules/math/llms.txt"):find(
      "# Module: `math`", 1, true))
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
   assert(css:find("@media print", 1, true), css)
   assert(css:find("%-%-example%-project%-accent:#315f58"), css)
   assert(css:find("clip%-path:circle%(50%% at 50%% 50%%%)"), css)
   assert(css:find("filter:drop%-shadow"), css)
   -- one mechanism clears the sticky header; two would stack into twice the gap
   assert(css:find("scroll%-margin%-top:calc%(var%(%-%-nuppdoc%-header%-height%)"), css)
   assert(not css:find("scroll-padding-top", 1, true), css)

   local legacy = readFile(dir .. "/site/modules/math.html")
   assert(legacy:find("math/index.html", 1, true), legacy)
   os.execute("rm -rf '" .. dir .. "'")
end

-- Markdown is lunamark's now. These are the cases the pattern-based renderer
-- it replaced got wrong, so they are the ones worth pinning.
function M.markdownIsRenderedByLunamark()
   local html = require("nupp.doc.html")
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
   local html = require("nupp.doc.html")
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

-- The id is Nupp's slug rather than lunamark's, and each heading keeps the
-- anchor the stylesheet draws.
function M.headingsKeepTheirAnchors()
   local html = require("nupp.doc.html")
   local out = html.markdownHtml("# One `two`\n\nbody", {})
   assert(out:find('id="one-two"', 1, true), out)
   assert(out:find('class="nuppdoc-header-anchor"', 1, true), out)
   assert(out:find("<h2 ", 1, true), out) -- shifted by one by default
   assert(html.markdownHtml("# One", {}, 0):find("<h1 ", 1, true))
end

return M
