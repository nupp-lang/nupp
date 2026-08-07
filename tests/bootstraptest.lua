-- The repository must remain runnable when the ignored build tree is absent.
local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
if not HERE:match("^/") then
   local p = assert(io.popen("pwd"))
   HERE = p:read("*l") .. "/" .. HERE
   p:close()
end
local ROOT = HERE .. "/.."

local M = {}

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
      "run", "import-c", "lsp", "help",
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

return M
