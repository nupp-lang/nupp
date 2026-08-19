-- The CLI page, held to what the binary prints.
--
-- A page that shows help text is worth reading only if it is the help text.
-- Every block on it captioned with a `--help` invocation is compared to the
-- bytes that invocation writes, and every command in the grammar has to have
-- one, so a command added without a section fails here rather than going
-- undocumented.

local cli = require("nupp.compiler.cli")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
if not HERE:match("^/") then
   local p = assert(io.popen("pwd"))
   HERE = p:read("*l") .. "/" .. HERE
   p:close()
end
local NUPP = HERE .. "/../bin/nupp"
local PAGE = HERE .. "/../docs/reference/cli.md"

local M = {}

-- Every ```text block captioned with a command line, in page order. The caption
-- is the command, so a block says what produced it and can be reproduced.
local function captionedBlocks()
   local file = assert(io.open(PAGE, "rb"), "docs/reference/cli.md is missing")
   local markdown = file:read("*a"):gsub("\r\n?", "\n")
   file:close()
   local blocks, command, body = {}, nil, nil
   for line in (markdown .. "\n"):gmatch("([^\n]*)\n") do
      if command then
         if line == "```" then
            blocks[#blocks + 1] = {command = command,
               output = table.concat(body, "\n")}
            command, body = nil, nil
         else
            body[#body + 1] = line
         end
      else
         local caption = line:match("^```text %[(nupp[^%]]*)%]$")
         if caption then
            command, body = caption, {}
         end
      end
   end
   assert(not command, "a captioned block on the page is never closed")
   return blocks
end

-- Help is what the reader is promised, so it is compared and nothing else is:
-- a diagnostic carries a path, a duration or a byte count, and the page shows
-- those as the illustration they are.
local function isHelp(command)
   return command == "nupp help" or command:match("%-%-help$") ~= nil
end

local function capture(command)
   local pipe = assert(io.popen(
      ("%q%s 2>&1"):format(NUPP, command:gsub("^nupp", "", 1))))
   local out = pipe:read("*a")
   pipe:close()
   return (out:gsub("\n$", ""))
end

function M.everyHelpBlockIsWhatTheCommandPrints()
   local checked = 0
   for _, block in ipairs(captionedBlocks()) do
      if isHelp(block.command) then
         checked = checked + 1
         local printed = capture(block.command)
         if printed ~= block.output then
            error(("docs/reference/cli.md is stale for `%s`:\n%s")
               :format(block.command, printed), 2)
         end
      end
   end
   assert(checked > 20, "expected a help block for every command")
end

function M.everyCommandHasASection()
   local shown = {}
   for _, block in ipairs(captionedBlocks()) do
      shown[block.command] = true
   end
   for _, name in ipairs(cli.names()) do
      assert(shown["nupp " .. name .. " --help"],
         ("docs/reference/cli.md documents no `%s`; add a section carrying its "
            .. "`nupp %s --help` block"):format(name, name))
   end
   assert(shown["nupp help"], "the page shows the command list")
end

return M
