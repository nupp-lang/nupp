local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local test = require("assert")
if not HERE:match("^/") then
   local pipe = assert(io.popen("pwd"))
   HERE = pipe:read("*l") .. "/" .. HERE
   pipe:close()
end
local ROOT = HERE .. "/.."

local M = {}

local function quote(value)
   return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function write(path, text)
   local file = assert(io.open(path, "wb"))
   file:write(text)
   file:close()
end

local function read(path)
   local file = assert(io.open(path, "rb"))
   local text = file:read("*a")
   file:close()
   return text
end

local function temporary()
   local path = os.tmpname()
   os.remove(path)
   assert(os.execute("mkdir -p " .. quote(path)) == 0)
   return path
end

-- A Windows drive-letter path (`C:/...`) and the MSYS spelling Git Bash's own
-- utilities normalize it to (`/c/...`) name the same real location; comparing them
-- literally would fail on a difference in spelling rather than in substance.
local function posixDrive(path)
   return (path:gsub("^([A-Za-z]):/", function(drive)
      return "/" .. drive:lower() .. "/"
   end))
end

function M.helperSeedsOnlyReusableWorktreeState()
   local parent = temporary()
   local origin, task, dirtyTask = parent .. "/origin", parent .. "/task",
      parent .. "/dirty-task"
   assert(os.execute(("mkdir -p %s/scripts %s/src %s/build/cache "
      .. "%s/build/nupp/compiler %s/build/lib %s/.rocks")
      :format(quote(origin), quote(origin), quote(origin), quote(origin),
         quote(origin), quote(origin))) == 0)
   assert(os.execute(("cp %s/scripts/worktree %s/scripts/worktree")
      :format(quote(ROOT), quote(origin))) == 0)
   assert(os.execute("chmod +x " .. quote(origin .. "/scripts/worktree")) == 0)
   write(origin .. "/src/main.nupp", "return true\n")
   write(origin .. "/build/cache/checks.buf", "compiler-cache\n")
   write(origin .. "/build/.nupp-test-times.json", '{"suites":{"slow":10}}\n')
   write(origin .. "/build/nupp/compiler/main.lua", "return true\n")
   write(origin .. "/build/nupp.lua", "return true\n")
   write(origin .. "/build/lib/native", "library\n")
   write(origin .. "/build/.nupp-state.json", "{}\n")
   write(origin .. "/.rocks/sentinel", "rocks\n")
   assert(os.execute(("git -C %s init -q && git -C %s config user.name Test "
      .. "&& git -C %s config user.email test@example.com && git -C %s add scripts src "
      .. "&& git -C %s commit -q -m initial")
      :format(quote(origin), quote(origin), quote(origin), quote(origin), quote(origin))) == 0)
   write(origin .. "/build/.nupp-complete", "complete\n")

   local command = ("%s/scripts/worktree cached-worktree %s HEAD >/dev/null")
      :format(quote(origin), quote(task))
   assert(os.execute(command) == 0, "worktree helper failed")
   assert(read(task .. "/.rocks/sentinel") == "rocks\n",
      "the dependency link did not reach the origin")
   assert(read(task .. "/build/cache/checks.buf") == "compiler-cache\n",
      "the incremental cache was not seeded")
   assert(read(task .. "/build/.nupp-test-times.json"):find('"slow":10', 1, true),
      "test timings were not seeded")
   assert(read(task .. "/build/nupp/compiler/main.lua") == "return true\n",
      "a current compiler was not seeded")
   assert(os.execute(("test ! %s/src/main.nupp -nt %s/build/.nupp-complete")
      :format(quote(task), quote(task))) == 0,
      "the copied completion stamp remained older than a fresh checkout")
   -- A current timestamp is not enough when the origin compiler was built from
   -- uncommitted source. Its incremental cache remains safe to seed, but its generated
   -- compiler must not be mistaken for output of the clean revision.
   write(origin .. "/src/main.nupp", "return false\n")
   write(origin .. "/build/.nupp-complete", "complete after dirty build\n")
   command = ("%s/scripts/worktree dirty-worktree %s HEAD >/dev/null")
      :format(quote(origin), quote(dirtyTask))
   assert(os.execute(command) == 0, "dirty-origin worktree helper failed")
   assert(read(dirtyTask .. "/build/cache/checks.buf") == "compiler-cache\n",
      "a dirty origin stopped the safe incremental cache seed")
   local dirtyCompiler = io.open(dirtyTask .. "/build/nupp/compiler/main.lua", "rb")
   assert(not dirtyCompiler,
      "generated compiler output from dirty source was copied into a clean worktree")

   os.execute(("git -C %s worktree remove --force %s >/dev/null 2>&1")
      :format(quote(origin), quote(task)))
   os.execute(("git -C %s worktree remove --force %s >/dev/null 2>&1")
      :format(quote(origin), quote(dirtyTask)))
   os.execute("rm -rf " .. quote(parent))
end

-- The launcher builds the development provider by asking the toolchain driver
-- for it, and installs the file the driver named. It does not know where that
-- file came from or how it was cached: the driver keys that by the compiler
-- this machine has, and every worktree of a checkout shares one answer.
function M.launcherBuildsTheProviderThroughTheToolchainDriver()
   if jit.os == "Windows" then
      test.skip("the fake Darwin toolchain fixture requires a POSIX host")
   end
   local root = temporary()
   local fake = root .. "/fake-bin"
   assert(os.execute(("mkdir -p %s/bin %s/bootstrap %s/scripts %s/build/lib %s")
      :format(quote(root), quote(root), quote(root), quote(root), quote(fake))) == 0)
   assert(os.execute(("cp %s/bin/nupp %s/bin/nupp && chmod +x %s/bin/nupp")
      :format(quote(ROOT), quote(root), quote(root))) == 0)
   assert(os.execute(("cp %s/scripts/luajit.sh %s/scripts/luajit.sh")
      :format(quote(ROOT), quote(root))) == 0)
   write(root .. "/bootstrap/nupp.lua", "return true\n")
   -- A driver that records what it was asked for and answers with a file it
   -- made, which is the whole of the contract the launcher relies on.
   write(root .. "/scripts/toolchain", [[#!/bin/sh
case "${1:-}" in
   native|native-rust) printf '%s\n' "$*" >> "$NUPP_TEST_RECORD" ;;
esac
printf 'built\n' > "$NUPP_TEST_BUILT"
printf '%s\n' "$NUPP_TEST_BUILT"
]])
   assert(os.execute("chmod +x " .. quote(root .. "/scripts/toolchain")) == 0)
   write(fake .. "/uname", "#!/bin/sh\necho Darwin\n")
   write(fake .. "/luajit", [[#!/bin/sh
if [ "${1:-}" = -v ]; then echo 'LuaJIT 2.1.1784535650'; fi
exit 0
]])
   assert(os.execute("chmod +x " .. quote(fake) .. "/*") == 0)

   local record, built = root .. "/asked.txt", root .. "/provider.dylib"
   local environment = ("PATH=%s:$PATH NUPP_TEST_RECORD=%s NUPP_TEST_BUILT=%s ")
      :format(quote(fake), quote(record), quote(built))
   assert(os.execute(environment .. quote(root .. "/bin/nupp") .. " clean") == 0)
   local asked = read(record)
   assert(asked == "native\n"
      .. "native-rust base,files,http,net,process,tls,uri,uuid\n",
      "the launcher requested the wrong development providers: " .. asked)
   assert(read(root .. "/build/lib/libnupp_native_dev.dylib") == "built\n",
      "the launcher did not install the compatibility provider")
   assert(read(root .. "/build/lib/libnupp_native_v2_dev.dylib") == "built\n",
      "the launcher did not install the Rust provider")
   os.execute("rm -rf " .. quote(root))
end

return M
