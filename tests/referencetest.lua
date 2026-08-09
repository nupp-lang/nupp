-- The language reference, held to what the compiler actually does.
--
-- A reference is read as authoritative, so an example that stopped compiling is
-- worse than no example at all. Every one is built into a project and checked
-- strictly, every code it cites has to resolve, every lint has to appear, and
-- the committed docs/reference.md has to be what the binary would print.

local reference = require("nupp.reference")
local explain = require("nupp.explain")
local lints = require("nupp.lints")
local json = require("cjson").new()

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
if not HERE:match("^/") then
   local p = assert(io.popen("pwd"))
   HERE = p:read("*l") .. "/" .. HERE
   p:close()
end
local NUPP = HERE .. "/../bin/nupp"
local ROOT = HERE .. "/.."

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

-- The committed page is what the site renders and what the llms.txt beside it
-- carries. If it can drift from the binary, a reader has no way to tell which of
-- the two is lying to them.
function M.theCommittedPageIsCurrent()
   local file = assert(io.open(ROOT .. "/docs/reference.md", "rb"),
      "docs/reference.md is missing; run: nupp reference -o docs/reference.md")
   local committed = file:read("*a")
   file:close()
   assertEq(committed, reference.markdown() .. "\n",
      "docs/reference.md is stale; run: nupp reference -o docs/reference.md")
end

function M.theSkillCarriesLoadableFrontmatter()
   local skill = reference.skill()
   assertEq(skill:sub(1, 4), "---\n", "opens with frontmatter")
   assert(skill:find("\nname: nupp\n", 1, true), "names itself")
   assert(skill:find("description:", 1, true), "says when to load it")
   local closing = skill:find("\n---\n", 4, true)
   assert(closing, "closes its frontmatter")
   assert(skill:find("# Nupp language reference", closing, true),
      "the document follows the frontmatter")
   assert(skill:find("## Language", closing, true), "groups language sections")
   assert(skill:find("## Toolchain", closing, true), "groups tool workflows")
   assert(skill:find("### Improving test coverage", closing, true),
      "teaches the coverage workflow")
   assert(skill:find("nupp coverage --report-json", closing, true),
      "makes coverage data queryable by agents")
end

-- Around four thousand tokens is the claim the help text makes. Held loosely —
-- this is a ceiling that catches the reference growing into something nobody
-- can afford to paste, not a target to write to.
function M.theReferenceFitsInAPrompt()
   local markdown = reference.markdown()
   assert(#markdown < 60000,
      ("the reference has grown to %d bytes, past what it promises to be")
      :format(#markdown))
end

return M
