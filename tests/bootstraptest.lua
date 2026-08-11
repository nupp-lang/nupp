-- The repository must remain runnable when the ignored build tree is absent.
local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
if not HERE:match("^/") then
   local p = assert(io.popen("pwd"))
   HERE = p:read("*l") .. "/" .. HERE
   p:close()
end
local ROOT = HERE .. "/.."

local M = {}

local function readFile(path)
   local file = assert(io.open(path, "rb"))
   local source = file:read("*a")
   file:close()
   return source
end

-- A fresh checkout renders docs with the tracked compiler before any source has
-- rebuilt it. Keep both halves of an admonition in that bundle: without the
-- container renderer the markers become prose, and without the CSS the aside is
-- structurally correct but visually plain.
function M.trackedBootstrapCarriesAdmonitions()
   local source = readFile(ROOT .. "/bootstrap/nupp.lua")
   assert(source:find("ADMONITION_TITLES", 1, true),
      "tracked bootstrap lacks the admonition container renderer")
   assert(source:find(".nuppdoc-admonition{", 1, true),
      "tracked bootstrap lacks admonition styling")
end

function M.launcherFallsBackToTrackedBootstrap()
   local dir = os.tmpname()
   os.remove(dir)
   assert(os.execute("mkdir -p '" .. dir .. "/bin'") == 0)
   assert(os.execute(("cp '%s/bin/nupp' '%s/bin/nupp'"):format(ROOT, dir)) == 0)
   assert(os.execute(("cp -R '%s/bootstrap' '%s/bootstrap'"):format(ROOT, dir)) == 0)

   local p = assert(io.popen(("'%s/bin/nupp' --help 2>&1"):format(dir)))
   local out = p:read("*a")
   p:close()
   assert(out:find("Usage:\n  nupp", 1, true),
      "launcher did not start the tracked bootstrap compiler: " .. out)

   local commands = {
      "ast", "check", "fmt", "build", "clean", "tasks", "test", "doc", "fixpoint",
      "run", "import-c", "rock", "lsp", "help",
   }
   for _, command in ipairs(commands) do
      p = assert(io.popen(("'%s/bin/nupp' %s --help 2>&1")
         :format(dir, command)))
      out = p:read("*a")
      p:close()
      assert(out:find("Usage:", 1, true),
         "tracked bootstrap lacks help for " .. command .. ": " .. out)
   end

   os.execute("rm -rf '" .. dir .. "'")
end

-- Help output proves only that the tracked Lua loads. The bootstrap also has to
-- understand every language and resolver change used by the current compiler, or a
-- fresh checkout cannot produce its first build.
function M.trackedBootstrapBuildsCurrentCompiler()
   local dir = os.tmpname()
   os.remove(dir)
   assert(os.execute("mkdir -p '" .. dir .. "'") == 0)
   assert(os.execute(("cp '%s/nupp.lua' '%s/nupp.lua'"):format(ROOT, dir)) == 0)
   assert(os.execute(("cp -R '%s/src' '%s/src'"):format(ROOT, dir)) == 0)
   assert(os.execute(("cp -R '%s/bootstrap' '%s/bootstrap'"):format(ROOT, dir)) == 0)

   local p = assert(io.popen(("cd '%s' && luajit bootstrap/nupp.lua build 2>&1")
      :format(dir)))
   local out = p:read("*a")
   local ok = p:close()
   assert(ok, "tracked bootstrap cannot build the current compiler: " .. out)

   local stamp = io.open(dir .. "/build/.nupp-complete", "rb")
   assert(stamp, "tracked bootstrap reported success without completing the build")
   stamp:close()
   os.execute("rm -rf '" .. dir .. "'")
end

return M
