-- The compiler reference, held to what the compiler actually does.
--
-- A reference is read as authoritative, so an example that stopped compiling is
-- worse than no example at all. Every one is built into a project and checked
-- strictly, every code it cites has to resolve, every lint has to appear, and
-- every rendering has to describe the same compiler-owned sections.

local reference = require("nupp.compiler.reference")
local explain = require("nupp.compiler.explain")
local lints = require("nupp.compiler.lints")
local trace = require("nupp._trace")
local json = require("cjson").new()

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
   local file = assert(io.open(dir .. "/sample.nupp", "wb"))
   file:write(section.example)
   file:close()
   return dir
end

--- Every diagnostic the compiler reports for one section's example.
local function diagnosticsFor(section)
   local dir = tempProject(section)
   local pipe = assert(io.popen(("cd '%s' && '%s' check --strict --json sample.nupp 2>/dev/null")
      :format(dir, NUPP)))
   local out = pipe:read("*a")
   pipe:close()
   os.execute("rm -rf '" .. dir .. "'")
   local ok, decoded = pcall(json.decode, out)
   assert(ok, "check --json did not produce JSON: " .. out)
   return decoded.diagnostics or {}
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


return M
