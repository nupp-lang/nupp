-- The compiler reference, held to what the compiler actually does.
--
-- A reference is read as authoritative, so an example that stopped compiling is
-- worse than no example at all. Every one is built into a project and checked
-- strictly, every code it cites has to resolve, every lint has to appear, and
-- every rendering has to describe the same compiler-owned sections.

local reference = require("nupp.compiler.reference")
local explain = require("nupp.compiler.explain")
local lints = require("nupp.compiler.lints")
local trace = require("nupp.profile.trace")
local project = require("nupp.compiler.build.project")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
if not HERE:match("^/") then
   local p = assert(io.popen("pwd"))
   HERE = p:read("*l") .. "/" .. HERE
   p:close()
end
local NUPP = HERE .. "/../bin/nupp"

local M = {}

local function assertEq(got, want, label)
   if got ~= want then
      error(("%s:\n  want: %s\n  got:  %s"):format(label or "mismatch",
         tostring(want), tostring(got)), 2)
   end
end

--- Where a section's example belongs inside its project.
---
--- An example that declares a module has to be checked in the file that module
--- names, or the first thing reported is the name not matching -- which is a
--- fact about this harness rather than about the example. A dotted module names
--- directories the same way the compiler resolves it. Everything else is
--- `sample`, which declares nothing and so can be called anything.
local function examplePath(example)
   local declared = example:match("^%s*module%s+([%w_%.]+)")
   if not declared then return "sample.nupp" end

   return (declared:gsub("%.", "/")) .. ".nupp"
end

-- The section's example as a project of its own, companions and all.
local function tempProject(section)
   local dir = os.tmpname()
   os.remove(dir)
   assert(os.execute("mkdir -p '" .. dir .. "'") == 0)
   local manifest = assert(io.open(dir .. "/nupp.lua", "wb"))
   manifest:write('return {include = {"."}}\n')
   manifest:close()
   for name, source in pairs(section.context or {}) do
      local companion = assert(io.open(dir .. "/" .. name, "wb"))
      companion:write(source)
      companion:close()
   end
   local relative = examplePath(section.example)
   local parent = relative:match("^(.*)/[^/]+$")
   if parent then
      assert(os.execute("mkdir -p '" .. dir .. "/" .. parent .. "'") == 0)
   end
   local file = assert(io.open(dir .. "/" .. relative, "wb"))
   file:write(section.example)
   file:close()
   return dir, relative
end

--- Every diagnostic the compiler reports for one section's example.
local function diagnosticsFor(section)
   local dir, relative = tempProject(section)
   local diagnostics = {}
   project.check(dir, {
      strict = true,
      paths = {dir .. "/" .. relative},
      diagnostics = diagnostics,
   })
   os.execute("rm -rf '" .. dir .. "'")
   return diagnostics
end

function M.everyExampleChecksClean()
   local checked = 0
   for _, section in ipairs(reference.sections) do
      if section.example then
         checked = checked + 1
         local diagnostics = diagnosticsFor(section)
         if #diagnostics > 0 then
            local first = diagnostics[1]
            error(("the %q example reports %s: %s\n%s"):format(
               section.title, first.code or "?", first.message or "",
               section.example), 2)
         end
      end
   end
   assert(checked > 10, "expected the reference to carry examples")
end

-- A reference that cites a code nothing can explain sends its reader nowhere.
function M.everyCitedCodeResolves()
   for _, section in ipairs(reference.sections) do
      for _, code in ipairs(section.codes) do
         local entry = explain.lookup(code)
         assert(entry, ("the %q section cites %s, which nothing explains")
            :format(section.title, code))
      end
   end
end

-- The lint table is generated rather than written beside the lints, so a lint
-- added without touching the reference still appears in it.
function M.everyLintAppears()
   local markdown = reference.markdown()
   for _, lint in ipairs(lints.all) do
      assert(markdown:find(lint.name, 1, true),
         ("lint %s is missing from the reference"):format(lint.name))
      assert(markdown:find(lint.code, 1, true),
         ("code %s is missing from the reference"):format(lint.code))
   end
end

function M.theSkillCarriesLoadableFrontmatter()
   local skill = reference.skill()
   assertEq(skill:sub(1, 4), "---\n", "opens with frontmatter")
   assert(skill:find("\nname: nupp\n", 1, true), "names itself")
   assert(skill:find("description:", 1, true), "says when to load it")
   local closing = skill:find("\n---\n", 4, true)
   assert(closing, "closes its frontmatter")
   assert(skill:find("# Nupp reference", closing, true),
      "the document follows the frontmatter")
   assert(skill:find("## Language", closing, true), "groups language sections")
   assert(skill:find("## CLI", closing, true), "groups CLI workflows")
   assert(skill:find("### Improving test coverage", closing, true),
      "teaches the coverage workflow")
   assert(skill:find("nupp coverage --report-json", closing, true),
      "makes coverage data queryable by agents")
end

function M.chaptersAreDiscoverableAndFocused()
   local catalogue = reference.catalog()
   assert(catalogue:find("language", 1, true), "lists the language chapter")
   assert(catalogue:find("cli", 1, true), "lists the CLI chapter")
   assert(catalogue:find("performance", 1, true),
      "lists the performance chapter")
   assert(catalogue:find("performance ", 1, true),
      "aligns the longest chapter name")
   local cli = assert(reference.chapter("cli"), "finds the CLI chapter")
   local performance = assert(reference.chapter("performance"),
      "finds the performance chapter")
   assert(reference.chapter("missing") == nil, "does not invent chapters")
   local markdown = reference.chapterMarkdown(cli)
   assert(markdown:find("# Nupp CLI reference", 1, true), "titles CLI output")
   assert(markdown:find("CLI commands", 1, true), "lists CLI commands")
   assert(markdown:find("Improving test coverage", 1, true),
      "keeps coverage guidance in the CLI chapter")
   local skill = reference.skill(cli)
   assert(skill:find("name: nupp-cli", 1, true), "names focused CLI skill")

   local performanceMarkdown = reference.chapterMarkdown(performance)
   assert(performanceMarkdown:find("# Nupp Performance reference", 1, true),
      "titles performance output")
   assert(performanceMarkdown:find("nupp lsp trace-check --json", 1, true),
      "puts deterministic inspection before profiling")
   assert(performanceMarkdown:find("nupp run --profile", 1, true),
      "teaches sampling")
   assert(performanceMarkdown:find("nupp run --jit-aborts", 1, true),
      "teaches abort collection")
   assert(performanceMarkdown:find("jit/loop-function-construction", 1, true),
      "takes static reasons from the shared catalog")
   for _, reason in ipairs(trace.records()) do
      if reason.explanation then
         assert(performanceMarkdown:find(reason.id, 1, true),
            "performance skill names " .. reason.id)
         assert(performanceMarkdown:find(reason.explanation, 1, true),
            "performance skill shares the explanation for " .. reason.id)
      end
   end
   local performanceSkill = reference.skill(performance)
   assert(performanceSkill:find("name: nupp-performance", 1, true),
      "names focused performance skill")
   assert(performanceSkill:find("performance regressions", 1, true),
      "describes the requests that load it")
end

function M.referenceCommandListsAndSelectsChapters()
   local pipe = assert(io.popen(('%q reference'):format(NUPP)))
   local catalogue = pipe:read("*a")
   pipe:close()
   assert(catalogue:find("Nupp reference chapters", 1, true),
      "bare command lists chapters")
   local cliPipe = assert(io.popen(('%q reference cli'):format(NUPP)))
   local cli = cliPipe:read("*a")
   cliPipe:close()
   assert(cli:find("# Nupp CLI reference", 1, true),
      "CLI chapter is selectable")
   local performancePipe = assert(io.popen(('%q reference performance'):format(NUPP)))
   local performance = performancePipe:read("*a")
   performancePipe:close()
   assert(performance:find("# Nupp Performance reference", 1, true),
      "performance chapter is selectable")
end


--- A reader who knows which construct they are asking about should not have to
--- load the chapter it lives in. The size is the whole point of the feature, so
--- it is what the test asserts.
function M.oneSectionIsSelectableAndFarSmallerThanItsChapter()
   local chapterPipe = assert(io.popen(('%q reference language'):format(NUPP)))
   local chapter = chapterPipe:read("*a")
   chapterPipe:close()
   local sectionPipe = assert(io.popen(('%q reference --section types'):format(NUPP)))
   local section = sectionPipe:read("*a")
   sectionPipe:close()
   assert(section:find("# Types", 1, true), "the section prints under its heading")
   assert(#section * 10 < #chapter,
      ("a section is a slice, not the chapter: %d vs %d bytes"):format(#section, #chapter))
end

--- Every diagnostic carries a `docs` pointer, and the anchor in it is what
--- identifies the section. Naming a section by the whole pointer has to work, or
--- the pointer is one a reader cannot follow.
function M.aDocsPointerNamesItsSection()
   local pipe = assert(io.popen(
      ('%q reference --section "docs/concepts/modules.md#modules"'):format(NUPP)))
   local out = pipe:read("*a")
   pipe:close()
   assert(out:find("# Modules", 1, true), "a docs pointer resolves: " .. out:sub(1, 120))
end

--- The loop a diagnostic half-closes: holding a code is enough to reach the prose.
function M.aCodeReachesTheSectionsExplainingIt()
   local reference = require("nupp.compiler.reference")
   local checked = 0
   for _, chapter in ipairs(reference.chapters) do
      for _, section in ipairs(chapter.sections) do
         for _, code in ipairs(section.codes) do
            local found = reference.sectionsFor(code)
            assert(#found > 0, code .. " is cited but reaches no section")
            checked = checked + 1
         end
      end
   end
   assert(checked > 0, "the reference cites codes")
   assert(#reference.sectionsFor("NUPP9999") == 0, "an uncited code reaches nothing")
end

--- Guessing is what the catalogue is meant to stop, so it has to name the slices.
function M.theCatalogueNamesEverySection()
   local reference = require("nupp.compiler.reference")
   local pipe = assert(io.popen(('%q reference'):format(NUPP)))
   local catalogue = pipe:read("*a")
   pipe:close()
   for _, chapter in ipairs(reference.chapters) do
      for _, section in ipairs(chapter.sections) do
         local slug = reference.slug(section.title)
         assert(catalogue:find(slug, 1, true),
            slug .. " is a slice the catalogue does not mention")
      end
   end
end


--- Two examples in this command's own help named sections that do not exist, and
--- nothing noticed until they were tried by hand. An example is a promise.
function M.everySectionExampleInTheHelpResolves()
   local pipe = assert(io.popen(('%q reference --help'):format(NUPP)))
   local help = pipe:read("*a")
   pipe:close()
   local checked = 0
   for name in help:gmatch("nupp reference %-%-section ([^%s]+)") do
      -- The usage line spells the argument `NAME`, which is the placeholder and
      -- not a section. Anything in capitals is one of those.
      if not name:match("^%u+$") then
      checked = checked + 1
      local run = assert(io.popen(
         ('%q reference --section %q >/dev/null 2>&1; echo $?'):format(NUPP, name)))
      local status = run:read("*a")
      run:close()
      assert(status:match("^0"), "the help offers --section " .. name .. ", which does not resolve")
      end
   end
   assert(checked > 0, "the help shows how to name a section")
end


return M
