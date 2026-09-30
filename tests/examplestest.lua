-- Every Nupp example the documentation shows, checked as the program it claims to be.
--
-- A reader copies an example before reading the prose around it, so an example that
-- does not check is a bug a reader finds first. Two kinds of page carry them: the
-- guides under `docs/learn`, and the docblocks of the modules themselves, which
-- `nupp doc` renders into the API pages. Each fenced `nupp` block in either is parsed
-- and checked the way a file of its own would be.
--
-- Not every block is a program. One that shows a step of a sequence, a declaration
-- lifted out of its module, or syntax in isolation says so on its fence with
-- `:fragment`, and is skipped. One that shows what the checker refuses says so with
-- `:refused`, and is held to that: it has to report an error, or it has stopped
-- demonstrating what the prose around it says it does.
--
-- ```nupp:fragment
-- ```nupp:refused
local parser = require("nupp.compiler.syntax.parser")
local check = require("nupp.compiler.check")
local envMod = require("nupp.compiler.project.env")
local fs = require("nupp.compiler.fs")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
if not HERE:match("^/") then
   local pipe = assert(io.popen("pwd"))
   HERE = pipe:read("*l") .. "/" .. HERE
   pipe:close()
end
local ROOT = HERE:match("^(.*)/[^/]+$")

local M = {}

-- An example is a fragment of a program in one respect: it binds what it is about and
-- stops, so the two lints that ask a file to be a whole program are off, as they are
-- for the suite's own fixtures.
local LINTS = {["unused-binding"] = "off", ["discarded-result"] = "off"}

local function listed(command)
   local pipe = assert(io.popen("cd '" .. ROOT .. "' && " .. command))
   local paths = {}
   for path in pipe:lines() do
      paths[#paths + 1] = path
   end
   pipe:close()
   table.sort(paths)
   return paths
end

-- The fenced `nupp` blocks among `lines`, each with the line its fence opened on and
-- the options written after the language. A closing fence is at least as long as the
-- opening one, the rule a page showing a fence inside a fence relies on.
local function fencedBlocks(lines)
   local blocks, open = {}, nil
   for number, line in ipairs(lines) do
      if open then
         local closer = line and line:match("^%s*(`+)%s*$")
         if line == false or (closer and #closer >= #open.fence) then
            if open.nupp then
               open.text = table.concat(open.body, "\n") .. "\n"
               blocks[#blocks + 1] = open
            end
            open = nil
         else
            open.body[#open.body + 1] = line
         end
      elseif line then
         -- Any fence is tracked, so a page showing a `nupp` fence inside a markdown
         -- one does not have the inner one read as an example of its own.
         local fence, info = line:match("^%s*(```+)(.*)$")
         if fence then
            local options = info:match("^nupp(.*)$")
            local nupp = options ~= nil and (options == "" or options:match("^[%s:%[]") ~= nil)
            open = {fence = fence, options = options or "", line = number, body = {}, nupp = nupp}
         end
      end
   end
   return blocks
end

local function fileLines(text)
   local lines = {}
   for line in (text .. "\n"):gmatch("([^\n]*)\n") do
      lines[#lines + 1] = line
   end
   return lines
end

-- A source file's comment text, line for line: a `---` or `--` line without its
-- marker, a `--[[ ]]` body as written, and `false` for a line of code, which ends any
-- fence a docblock left open.
local function commentLines(text)
   local lines, inBlock = {}, false
   for line in (text .. "\n"):gmatch("([^\n]*)\n") do
      if inBlock then
         local before = line:match("^(.-)%]%]")
         if before then
            lines[#lines + 1] = before
            inBlock = false
         else
            lines[#lines + 1] = line
         end
      else
         local opened = line:match("^%s*%-%-%[=*%[(.*)$")
         if opened then
            if opened:find("]]", 1, true) then
               lines[#lines + 1] = false
            else
               inBlock = true
               lines[#lines + 1] = opened
            end
         else
            local comment = line:match("^%s*%-%-%-? ?(.*)$")
            if comment ~= nil then
               lines[#lines + 1] = comment
            else
               lines[#lines + 1] = false
            end
         end
      end
   end
   return lines
end

-- What a block is checked as. A caption naming a file keeps that file's extension, so
-- a `.g.nupp` view is checked gradually and a `.d.nupp` as a declaration; anything
-- else is a strict file of its own, outside every source root.
local function exampleName(where, block)
   local caption = block.options:match("%[([^%]]+)%]")
   local file = caption and caption:match("^([%w%._/%-]+%.nupp)")
   local stem = ("/nupp-examples/" .. where):gsub("[^%w/%-_]", "_")
   if file then
      return stem .. "_" .. block.line .. "/" .. file:gsub("^.*/", "")
   end
   return stem .. "_" .. block.line .. ".nupp"
end

local function marked(block, marker)
   return block.options:find(":" .. marker, 1, true) ~= nil
end

local function errorsOf(env, name, text)
   local result = parser.parse(text, name)
   local diagnostics = #result.errors > 0 and result.errors or check.check(result, name, env, {lints = LINTS})
   local errors = {}
   for _, diagnostic in ipairs(diagnostics) do
      if (diagnostic.severity or "error") == "error" then
         errors[#errors + 1] = diagnostic
      end
   end
   return errors
end

-- Checks every block and returns one line per example that is wrong.
local function examine(env, where, blocks, problems, counts)
   for _, block in ipairs(blocks) do
      if not marked(block, "fragment") then
         counts.checked = counts.checked + 1
         local errors = errorsOf(env, exampleName(where, block), block.text)
         if marked(block, "refused") then
            if #errors == 0 then
               problems[#problems + 1] = ("%s:%d is marked :refused and checks clean"):format(where, block.line)
            end
         elseif #errors > 0 then
            local first = errors[1]
            problems[#problems + 1] = ("%s:%d: %s %s"):format(
               where, block.line + (first.line or 0), first.code or "?", tostring(first.msg):gsub("\n.*", ""))
         end
      end
   end
end

local ENV = nil
local function environment()
   ENV = ENV or envMod.new(ROOT)
   return ENV
end

function M.everyGuideExampleChecks()
   local problems, counts = {}, {checked = 0}
   for _, path in ipairs(listed("find docs/learn -name '*.md'")) do
      examine(environment(), path, fencedBlocks(fileLines(assert(fs.readFile(ROOT .. "/" .. path)))), problems, counts)
   end
   assert(counts.checked > 200, "the guides were reached: " .. counts.checked)
   assert(#problems == 0, #problems .. " guide examples do not check; fix them, or mark a block "
      .. ":fragment or :refused on its fence:\n  " .. table.concat(problems, "\n  "))
end

function M.everyModuleDocblockExampleChecks()
   local problems, counts = {}, {checked = 0}
   for _, path in ipairs(listed("find src/nupp -name '*.nupp'")) do
      examine(environment(), path, fencedBlocks(commentLines(assert(fs.readFile(ROOT .. "/" .. path)))), problems, counts)
   end
   assert(counts.checked > 100, "the module docblocks were reached: " .. counts.checked)
   assert(#problems == 0, #problems .. " docblock examples do not check; fix them, or mark a block "
      .. ":fragment or :refused on its fence:\n  " .. table.concat(problems, "\n  "))
end

-- The markers are read off the fence the way the documentation renderer reads its
-- own options, so a marked block still renders as the Nupp it is.
function M.aMarkedFenceStillRendersAsNupp()
   local blocks = fencedBlocks(fileLines("```nupp:fragment\nlocal x = 1\n```\n```nupp [a.nupp]:refused\nreturn 1\n```\n"))
   assert(#blocks == 2 and marked(blocks[1], "fragment") and marked(blocks[2], "refused"), "both markers are read")
   local html = require("nupp.tools.doc.html")
   local rendered = html.markdownHtml and html.markdownHtml("```nupp:fragment\nlocal x = 1\n```\n") or nil
   if rendered then
      assert(not rendered:find(":fragment", 1, true), "the marker is not shown: " .. rendered)
   end
end

return M
