-- The CLI page, held to what the binary prints.
--
-- A page that shows help text is worth reading only if it is the help text.
-- Every block on it captioned with a `--help` invocation is compared to the
-- bytes that invocation writes, and every command in the grammar has to have
-- one, so a command added without a section fails here rather than going
-- undocumented.

local cli = require("nupp.tools.cli")

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

-- Every source block on the page captioned with a path, which is how the page
-- shows the example project and the files a section adds to it.
local function pageFiles()
   local file = assert(io.open(PAGE, "rb"))
   local markdown = file:read("*a"):gsub("\r\n?", "\n")
   file:close()
   local files, path, body = {}, nil, nil
   for line in (markdown .. "\n"):gmatch("([^\n]*)\n") do
      if path then
         if line == "```" then
            files[path] = table.concat(body, "\n") .. "\n"
            path, body = nil, nil
         else
            body[#body + 1] = line
         end
      else
         local lang, caption = line:match("^```(%a+) %[([%w_./-]+)%]$")
         if caption and lang ~= "text" then
            path, body = caption, {}
         end
      end
   end
   return files
end

-- The page says its `text` blocks are the bytes the command wrote, and that
-- every example runs in its example project. Each block below is run there and
-- compared. A block added to the page has to be put in one table or the other,
-- so a new example is either held to what the binary prints or says why not.
local REPLAYED = {
   ["nupp check --colour"] = {},
   ["nupp init --list"] = {},
   ["nupp fmt src/messy.nupp"] = {adds = {"src/messy.nupp"}},
   ["nupp fmt --check"] = {adds = {"src/messy.nupp"}},
   ["nupp clean --dry-run"] = {},
   ["nupp clean"] = {},
   ["nupp lints"] = {},
   ["nupp ownership-audit src/block.nupp"] = {adds = {"src/block.nupp"}},
   ["nupp explain NUPP2119"] = {},
   ["nupp completions bash"] = {},
   ["nupp task --list"] = {},
   ["nupp task --list app"] = {},
   ["nupp task greet"] = {},
   ["nupp run src/main.nupp"] = {},
   ["nupp lsp rename src/greet.nupp 2 16 hello"] = {},
   -- The page describes this file rather than showing it.
   ["nupp lsp actions src/scratch.nupp 4 5"] = {
      writes = {["src/scratch.nupp"] = table.concat({
         "local function sign(n: integer): string",
         "    if n > 0 then",
         "        return \"positive\"",
         "    else",
         "        if n < 0 then",
         "            return \"negative\"",
         "        end",
         "    end",
         "    return \"zero\"",
         "end",
         "",
         "return sign",
         "",
      }, "\n")},
   },
   ["nupp lsp symbols greet"] = {},
}

local ILLUSTRATIVE = {
   ["nupp init app greeter"] = "writes a project",
   ["nupp init lib string-tools"] = "writes a project",
   ["nupp aot bench/kernel-subset-spike/mandelbrot.nupp"] = "runs in Nupp's own repository",
   ["nupp aot --emit asm --function scale src/kernel.nupp"] = "prints machine code for one host",
   ["nupp bc greet.nupp"] = "numbers instructions after a prelude that changes with the runtime",
   ["nupp check"] = "runs against a variant of the project the section describes",
   ["nupp reference"] = "is abridged",
   ["nupp test elseiftest"] = "runs in Nupp's own repository",
   ["nupp import-c native/mini.h --lib mini -o src/mini.nupp"] = "needs a C header and a compiler",
}

-- On Windows the harness starts `bin/nupp` through bash, and a task's own `nupp`
-- is resolved by cmd.exe instead, which that harness does not provide.
if jit.os == "Windows" then
   REPLAYED["nupp task greet"] = nil
   ILLUSTRATIVE["nupp task greet"] = "starts `nupp` by name, which the Windows harness does not provide"
end

function M.everyCommandBlockIsWhatTheCommandPrintsInTheExampleProject()
   local files = pageFiles()
   local dir = os.tmpname()
   os.remove(dir)
   assert(os.execute("mkdir -p '" .. dir .. "/src' '" .. dir .. "/build'") == 0)
   local function write(path, text)
      local handle = assert(io.open(dir .. "/" .. path, "wb"))
      handle:write(text)
      handle:close()
   end
   for _, path in ipairs({"nupp.lua", "src/greet.nupp", "src/main.nupp"}) do
      write(path, assert(files[path], "the page shows no " .. path))
   end
   local bin = NUPP:match("^(.*)/nupp$")
   local stale = {}
   for _, block in ipairs(captionedBlocks()) do
      local command = block.command
      local replay = REPLAYED[command]
      if not isHelp(command) then
         assert(replay or ILLUSTRATIVE[command], ("docs/reference/cli.md shows `%s`; add it to REPLAYED, "
            .. "or to ILLUSTRATIVE with the reason it cannot be run"):format(command))
      end
      if replay then
         local added = {}
         for _, path in ipairs(replay.adds or {}) do
            write(path, assert(files[path], "the page shows no " .. path))
            added[#added + 1] = path
         end
         for path, text in pairs(replay.writes or {}) do
            write(path, text)
            added[#added + 1] = path
         end
         local pipe = assert(io.popen(("cd '%s' && PATH='%s':\"$PATH\" NO_COLOR= CLICOLOR_FORCE= %q%s 2>&1")
            :format(dir, bin, NUPP, (command:gsub("^nupp", "", 1)))))
         local printed = pipe:read("*a"):gsub("\n$", "")
         pipe:close()
         for _, path in ipairs(added) do
            os.remove(dir .. "/" .. path)
         end
         if printed ~= block.output then
            stale[#stale + 1] = ("`%s` printed:\n%s"):format(command, printed)
         end
      end
   end
   os.execute("rm -rf '" .. dir .. "'")
   assert(#stale == 0, "docs/reference/cli.md is stale:\n" .. table.concat(stale, "\n\n"))
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
