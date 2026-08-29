-- Minimal test runner: loads tests/*test.lua and compiles tests/*test.nupp,
-- runs every function in the returned table, and reports failures with their
-- assert message. A suite may also define beforeAll, afterAll, beforeEach,
-- and afterEach lifecycle hooks.
--
-- With --json it reports the same run as one document: a record per test with
-- where it is defined, how long it took, and — when it failed — the message and
-- the file and line the error came from. Standard output and error from a test
-- are held back unless it fails or --verbose asks for them. Lines are 1-based,
-- as everywhere else; a Lua error carries no column, so none is invented.
-- The JSON codec is taken once, before any suite loads. A suite may legitimately
-- clear `package.loaded` to prove something loads lazily, and a suite that fails
-- part way through such a proof leaves it cleared. Acquiring the codec after the
-- run means one misbehaving suite turns the whole shard's report into "the shard
-- wrote no report", which loses every other suite's result and reads like an
-- infrastructure failure rather than the one test that broke.
local runnerPath = arg[0]
if package.config:sub(1, 1) == "\\" then
   runnerPath = runnerPath:gsub("^/([A-Za-z])(/)", function(drive, slash)
      return drive:upper() .. ":" .. slash
   end)
end
local dir = runnerPath:match("^(.*)[/\\]") or "."
local buildDir = os.getenv("NUPP_COVERAGE_BUILD") or "build"
package.path = dir .. "/../" .. buildDir .. "/?.lua;" .. dir .. "/?.lua;"
   .. package.path
-- A runner copied out of the repository -- which is how its own suite exercises
-- it as the program a person runs -- resolves the two paths above against
-- wherever it was copied to, so the compiled modules it loads before doing
-- anything are not on either of them. This names where they actually are.
local modulesRoot = os.getenv("NUPP_TEST_MODULES")
if modulesRoot and modulesRoot ~= "" then
   package.path = modulesRoot .. "/?.lua;" .. modulesRoot .. "/?/init.lua;" .. package.path
end

package.preload.testjson = package.preload.testjson or function()
   local native = require("nupp.data.json")

   local json = {
      NULL = native.NULL,
      EMPTY_ARRAY = native.EMPTY_ARRAY,
      EMPTY_OBJECT = native.EMPTY_OBJECT,
      arrayOf = native.arrayOf,
      asArray = native.asArray,
      asObject = native.asObject,
      isArray = native.isArray,
      encode = native.encode,
      serialize = native.serialize,
      writer = native.writer,
   }

   function json.decode(text)
      return native.decode(text, native.NULL)
   end

   function json.pull(text, shape)
      return native.pull(text, shape, native.NULL)
   end

   return json
end

local testJson = require("testjson")
local embedded = rawget(_G, "__NUPP_TEST_EMBEDDED") == true
local workerHost = rawget(_G, "__NUPP_TEST_WORKER_HOST") == true

-- The suites predate Windows support and deliberately exercise shell-facing
-- CLI behaviour with POSIX commands. On Windows the VM's `system` and `popen`
-- otherwise hand those commands to cmd.exe even though the runner itself was
-- launched by Git Bash. Keep one shell dialect for the tests, and keep native
-- paths for the Windows programs those commands start.
if package.config:sub(1, 1) == "\\" then
   local rawExecute, rawPopen, rawTmpname = os.execute, io.popen, os.tmpname
   -- Rejected empty as well as absent: an undefined workflow variable reaches a
   -- step as the empty string, which is true in Lua, so a bare `assert` let it
   -- through and every shelled-out command became `""` instead.
   local bash = os.getenv("NUPP_TEST_BASH")
   assert(bash and bash ~= "",
      "NUPP_TEST_BASH must name Git Bash on Windows")
   local nativeMarker = "__NUPP_WINDOWS_COMMAND__"
   _G.__NUPP_TEST_CMD_MARKER = nativeMarker
   _G.__NUPP_TEST_BASH = bash
   local cwdPipe = assert(rawPopen("cd"))
   local cwd = assert(cwdPipe:read("*l")):gsub("\\", "/")
   cwdPipe:close()

   -- `tmpnam` draws from a sequence that starts again in every process, so two
   -- shards running at once are handed the same name, make the same directory,
   -- and one writes the sample the other is about to compile. What is reported
   -- then belongs to neither of them: a parse error against source the test that
   -- failed never wrote.
   --
   -- Impossible while the whole suite ran in one process, which is what kept it
   -- hidden until the shards arrived. Salted with the shard the parent named and
   -- counted within the process, so no two names can meet.
   local shardSalt = (os.getenv("NUPP_CACHE_DIR") or ""):match("shard%-(%d+)") or "0"
   local handedOut = 0
   os.tmpname = function()
      handedOut = handedOut + 1

      return ("%s-%s-%d"):format((rawTmpname():gsub("\\", "/")), shardSalt, handedOut)
   end

   local function script(command)
      command = command:gsub("(%a):/", function(drive)
         return "/" .. drive:lower() .. "/"
      end)
      local path = os.tmpname() .. ".sh"
      local file = assert(io.open(path, "wb"))
      file:write(command, "\n")
      file:close()
      return path
   end

   local function invocation(path)
      -- cmd.exe strips the first pair of quotes from a command line that starts
      -- with a quoted executable. The outer pair preserves the executable and
      -- script as two quoted arguments.
      return ('""%s" "%s""'):format(bash:gsub('"', '\\"'),
         path:gsub('"', '\\"'))
   end

   os.execute = function(command)
      if type(command) ~= "string" then return rawExecute(command) end
      if command:sub(1, #nativeMarker) == nativeMarker then
         return rawExecute(command:sub(#nativeMarker + 1))
      end
      local caller = debug.getinfo(2, "S")
      local source = caller and caller.source:gsub("\\", "/") or ""
      if not source:find("/tests/", 1, true)
         and not source:match("^@?tests/") then
         return rawExecute(command)
      end
      local path = script(command)
      local result = rawExecute(invocation(path))
      os.remove(path)
      return result
   end

   io.popen = function(command, mode)
      if command:sub(1, #nativeMarker) == nativeMarker then
         return rawPopen(command:sub(#nativeMarker + 1), mode)
      end
      local caller = debug.getinfo(2, "S")
      local source = caller and caller.source:gsub("\\", "/") or ""
      if not source:find("/tests/", 1, true)
         and not source:match("^@?tests/") then
         return rawPopen(command, mode)
      end
      if command == "pwd" then
         local unread = true
         return {
            read = function()
               if not unread then return nil end
               unread = false
               return cwd
            end,
            lines = function()
               return function()
                  if not unread then return nil end
                  unread = false
                  return cwd
               end
            end,
            close = function() return true end,
         }
      end
      local path = script(command)
      local pipe = assert(rawPopen(invocation(path), mode))
      local proxy = {}
      function proxy:read(...) return pipe:read(...) end
      function proxy:lines(...) return pipe:lines(...) end
      function proxy:close()
         local result = {pipe:close()}
         os.remove(path)
         return unpack(result)
      end
      return proxy
   end
end

local test = require("assert")

-- Existing suites use Lua's familiar assert spelling.  Give those assertions
-- useful falsy diagnostics, while `require("assert")` exposes equal, matches,
-- raises and skip for new assertions that can say exactly what differed.
assert = test.assert

local asJson = false
local verbose = false
-- Suites named on the command line. A list rather than one name: `nupp test a b`
-- used to keep whichever came last and silently run something else, or nothing.
local only = nil
local chosen = {}
local chosenSet = nil
-- Suites this process is to run, when a parent has split them up. Empty means "decide
-- for yourself", which is what the run a person starts does.
local shard = {}
-- Where the work this process is to take from lives, when a parent handed out a
-- queue rather than a list. Empty means "decide for yourself" the same way an
-- empty shard does.
local queueDir = nil
local jobs = nil
local colorMode = "auto"
local colorSeen = false
local colorProblem = nil
-- How many rows the timing report shows, and whether it shows one at all. A run
-- always measures; this only decides how much of the measurement is printed.
-- `--timings` on its own means every suite and every test, which is what a
-- person asking where the time went wants.
local timingRows = 15
for _, argument in ipairs(arg) do
   if argument == "--json" then
      asJson = true
   elseif argument == "--verbose" then
      verbose = true
   elseif argument == "--color" then
      if colorSeen and colorMode ~= "always" then
         colorProblem = "color was both asked for and refused"
      end
      colorMode, colorSeen = "always", true
   elseif argument == "--no-color" then
      if colorSeen and colorMode ~= "never" then
         colorProblem = "color was both asked for and refused"
      end
      colorMode, colorSeen = "never", true
   elseif argument:match("^%-%-color=") then
      local wanted = argument:match("^%-%-color=(.*)$")
      if wanted ~= "always" and wanted ~= "never" and wanted ~= "auto" then
         colorProblem = "--color must be always, never, or auto"
      elseif colorSeen and colorMode ~= wanted then
         colorProblem = "color was both asked for and refused"
      else
         colorMode, colorSeen = wanted, true
      end
   elseif argument == "--timings" then
      timingRows = math.huge
   elseif argument:match("^%-%-timings=") then
      timingRows = tonumber(argument:match("^%-%-timings=(%d+)$")) or timingRows
   elseif argument:match("^%-%-jobs=") then
      jobs = tonumber(argument:match("^%-%-jobs=(%d+)$"))
   elseif argument:match("^%-%-queue=") then
      queueDir = argument:sub(#"--queue=" + 1)
   elseif argument:match("^%-%-shard=") then
      for name in argument:sub(#"--shard=" + 1):gmatch("[^,]+") do
         shard[#shard + 1] = name
      end
   elseif argument:sub(1, 1) ~= "-" then
      chosen[#chosen + 1] = argument
      only = #chosen == 1 and argument or nil
   end
end
if colorProblem then
   io.stderr:write("nupp: " .. colorProblem .. "\n")
   os.exit(2)
end
if #chosen > 0 then
   chosenSet = {}
   for _, name in ipairs(chosen) do
      chosenSet[name] = true
   end
end

-- Tests often run a command specifically to make it print a diagnostic. Lua's
-- `io.output` cannot capture that command's inherited descriptors, so redirect
-- the descriptors themselves. The runner keeps duplicates for its own progress
-- marks, which must stay visible while a test owns the usual stdout and stderr.
local capture
local progressWrite
local useColor = false
local silenceProcessOutput = function()
   return function() end
end
-- The descriptor the marks go to, for handing to a worker.
--
-- A worker cannot be told "your parent's standard output": `popen` has already
-- made that the pipe the report comes back on, and a mark written there lands in
-- the middle of the document. So the parent keeps a duplicate of its own stream
-- and lets the worker inherit it, which is a descriptor that still means the
-- terminal on the other side of the fork.
local progressFd = nil
local sharedProgressStream = false
do
   local loaded, ffi = pcall(require, "ffi")
   if loaded then
      if ffi.os == "Windows" then
         ffi.cdef[[
            int _dup(int);
            int _dup2(int, int);
            int _open(const char *, int, int);
            int _close(int);
            int fflush(void *);
            int _write(int, const void *, unsigned int);
            int _isatty(int);
            int _putenv_s(const char *, const char *);
         ]]
      else
         ffi.cdef[[
            int dup(int);
            int dup2(int, int);
            int open(const char *, int, int);
            int close(int);
            int fflush(void *);
            long write(int, const void *, unsigned long);
            int isatty(int);
            int unsetenv(const char *);
         ]]
      end
      local C = ffi.C
      local create = ffi.os == "Windows" and 0x0100
         or (ffi.os == "OSX" and 0x200 or 0x40)
      local truncate = ffi.os == "Windows" and 0x0200
         or (ffi.os == "OSX" and 0x400 or 0x200)
      local binary = ffi.os == "Windows" and 0x8000 or 0
      local dup = ffi.os == "Windows" and C._dup or C.dup
      local dup2 = ffi.os == "Windows" and C._dup2 or C.dup2
      local open = ffi.os == "Windows" and C._open or C.open
      local close = ffi.os == "Windows" and C._close or C.close
      local write = ffi.os == "Windows" and C._write or C.write
      local isatty = ffi.os == "Windows" and C._isatty or C.isatty
      silenceProcessOutput = function()
         local function flush()
            io.stdout:flush(); io.stderr:flush(); C.fflush(nil)
         end
         flush()
         local savedOut, savedErr = dup(1), dup(2)
         local null = open(ffi.os == "Windows" and "NUL" or "/dev/null",
            1 + binary, 384)
         assert(savedOut >= 0 and savedErr >= 0 and null >= 0,
            "cannot silence worker output")
         assert(dup2(null, 1) >= 0 and dup2(null, 2) >= 0,
            "cannot redirect worker output")
         close(null)

         return function()
            flush()
            assert(dup2(savedOut, 1) >= 0 and dup2(savedErr, 2) >= 0,
               "cannot restore worker output")
            close(savedOut); close(savedErr)
         end
      end
      -- Where a mark goes.
      --
      -- Ordinarily the runner's own stream: standard output, or standard error
      -- when the document is on standard output. A worker is told a descriptor
      -- instead, because its standard error is a file the parent keeps to ask why
      -- it died with, and a mark written there is a mark nobody sees. That is what
      -- made a sharded run silent: every worker was marking work off into its own
      -- file while the terminal waited for the first one to finish.
      local named = tonumber(rawget(_G, "__NUPP_TEST_PROGRESS_FD")
         or os.getenv("NUPP_TEST_PROGRESS_FD") or "")
      sharedProgressStream = named ~= nil
      local statusFd = named and dup(named) or dup(asJson and 2 or 1)
      progressFd = statusFd
      -- This descriptor is for one runner process, not an ambient destination
      -- for commands its tests launch. Keeping the variable would make a nested
      -- `nupp test` bypass that test's capture and write into this progress line.
      if named and os.getenv("NUPP_TEST_PROGRESS_FD") ~= nil then
         if ffi.os == "Windows" then
            pcall(C._putenv_s, "NUPP_TEST_PROGRESS_FD", "")
         else
            pcall(C.unsetenv, "NUPP_TEST_PROGRESS_FD")
         end
      end

      local terminal = false
      local detected, answer = pcall(isatty, statusFd)
      if detected then terminal = answer ~= 0 end
      local function requested(name)
         local value = os.getenv(name)
         return value ~= nil and value ~= "" and value ~= "0"
      end
      if colorMode == "always" then
         useColor = true
      elseif colorMode == "never" or requested("NO_COLOR") then
         useColor = false
      elseif requested("CLICOLOR_FORCE") then
         useColor = true
      else
         useColor = terminal and os.getenv("TERM") ~= "dumb"
      end

      progressWrite = function(text)
         write(statusFd, text, #text)
      end

      local function flush()
         io.stdout:flush(); io.stderr:flush(); C.fflush(nil)
      end

      local function read(path)
         local f = assert(io.open(path, "rb"), "cannot read captured test output")
         local text = f:read("*a")
         f:close()
         os.remove(path)
         return text
      end

      capture = embedded and function(run)
         -- File descriptors belong to the process, not to a Lua state. Redirecting
         -- them from several worker threads would make one test capture another's
         -- output and occasionally restore the wrong descriptor. Worker jobs keep
         -- Lua failures associated with their cases; suites that specifically test
         -- runner capture stay in the process-isolated lane below.
         local active = {stdout = {}, stderr = {}}
         rawset(_G, "__NUPP_TEST_CAPTURE", active)
         local originalPrint, originalWrite = print, io.write
         local originalStdout, originalStderr = io.stdout, io.stderr
         local fileOut, fileErr = assert(io.tmpfile()), assert(io.tmpfile())
         io.stdout, io.stderr = fileOut, fileErr
         print = function(...)
            local values = {}
            for index = 1, select("#", ...) do
               values[index] = tostring(select(index, ...))
            end
            active.stdout[#active.stdout + 1] = table.concat(values, "\t") .. "\n"
         end
         io.write = function(...)
            for index = 1, select("#", ...) do
               active.stdout[#active.stdout + 1] = tostring(select(index, ...))
            end
            return true
         end
         local ok, problem = pcall(run)
         fileOut:flush(); fileErr:flush()
         fileOut:seek("set", 0); fileErr:seek("set", 0)
         active.stdout[#active.stdout + 1] = fileOut:read("*a") or ""
         active.stderr[#active.stderr + 1] = fileErr:read("*a") or ""
         print, io.write = originalPrint, originalWrite
         io.stdout, io.stderr = originalStdout, originalStderr
         fileOut:close(); fileErr:close()
         rawset(_G, "__NUPP_TEST_CAPTURE", nil)
         return ok, problem, table.concat(active.stdout), table.concat(active.stderr)
      end or function(run)
         local outPath, errPath = os.tmpname(), os.tmpname()
         flush()
         local savedOut, savedErr = dup(1), dup(2)
         local out = open(outPath, 1 + create + truncate + binary, 384)
         local err = open(errPath, 1 + create + truncate + binary, 384)
         assert(savedOut >= 0 and savedErr >= 0 and out >= 0 and err >= 0,
            "cannot capture test output")
         assert(dup2(out, 1) >= 0 and dup2(err, 2) >= 0,
            "cannot redirect test output")
         close(out); close(err)
         local ok, problem = pcall(run)
         flush()
         assert(dup2(savedOut, 1) >= 0 and dup2(savedErr, 2) >= 0,
            "cannot restore test output")
         close(savedOut); close(savedErr)
         return ok, problem, read(outPath), read(errPath)
      end
   else
      -- The runner remains useful on a LuaJIT without descriptor access, but a
      -- host that cannot redirect descriptors cannot hide child-process output.
      local forced = os.getenv("CLICOLOR_FORCE")
      local refused = os.getenv("NO_COLOR")
      useColor = colorMode == "always" or (colorMode == "auto"
         and (refused == nil or refused == "" or refused == "0")
         and forced ~= nil and forced ~= "" and forced ~= "0")
      progressWrite = function(text)
         local stream = asJson and io.stderr or io.stdout
         stream:write(text); stream:flush()
      end
      capture = function(run)
         local ok, problem = pcall(run)
         return ok, problem, "", ""
      end
   end
end

local RESET = "\27[0m"
local function paint(code, text)
   return useColor and ("\27[" .. code .. "m" .. text .. RESET) or text
end
local function progressHeading(text) return paint("1;36", text) end

-- Wall clock, because most of what these tests spend time on is a subprocess,
-- which no measure of this process's own CPU time would ever see. The FFI is
-- guarded the same way nupp.compiler.ansi guards it: a build without it still runs the
-- tests, it just reports coarser times.
local now
do
   local ok, ffi = pcall(require, "ffi")
   if ok then
      -- tv_usec is a long on Linux and an int on the BSDs, and reading it at
      -- the wrong width is how a timer silently returns nonsense.
      local micros = ffi.os == "Linux" and "long" or "int"
      local declared = pcall(ffi.cdef, ([[
         struct nupp_timeval { long tv_sec; %s tv_usec; };
         int gettimeofday(struct nupp_timeval *, void *);
      ]]):format(micros))
      if declared then
         local tv = ffi.new("struct nupp_timeval[1]")
         local called = pcall(function() ffi.C.gettimeofday(tv, nil) end)
         if called then
            now = function()
               ffi.C.gettimeofday(tv, nil)
               return tonumber(tv[0].tv_sec) * 1000
                  + tonumber(tv[0].tv_usec) / 1000
            end
         end
      end
   end
   now = now or function() return os.clock() * 1000 end
end

-- A shard entry is a suite name, or `name#index/count` for one slice of a suite too
-- heavy to be left whole. A slice takes the cases whose position falls in it, which is
-- well defined because the case list is sorted before anything runs.
--
-- A list per suite rather than one entry, because packing is free to put two slices of
-- the same suite in one shard. Keyed singly, the second replaced the first and took its
-- cases with it: a run reported 1768 of 1790 tests and called itself green.
local wanted = nil
if #shard > 0 then
   wanted = {}
   for _, entry in ipairs(shard) do
      local name, index, count = entry:match("^(.-)#(%d+)/(%d+)$")
      name = name or entry
      local slices = wanted[name] or {}
      wanted[name] = slices
      slices[#slices + 1] = {
         index = tonumber(index) or 0,
         count = tonumber(count) or 1,
      }
   end
end

local suites = {}
-- Every suite there is, by name, whether or not this process was asked for it.
-- A process working from a queue does not know what it will run until it claims
-- it, so it cannot filter the listing the way one handed a list can.
local byName = {}
local suiteCatalog = {}
do
   local function found(f)
      local name, extension = f:match("^(.*test)%.([^.]+)$")
      if name and (extension == "lua" or extension == "nupp") then
         local info = {name = name, extension = extension}
         byName[name] = info
         suiteCatalog[#suiteCatalog + 1] = f
         if (not chosenSet or chosenSet[name]) and (not wanted or wanted[name])
            and not queueDir then
            suites[#suites + 1] = info
         end
      end
   end
   local inherited = rawget(_G, "__NUPP_TEST_SUITE_CATALOG")
   if type(inherited) == "string" then
      for f in inherited:gmatch("[^\n]+") do found(f) end
   else
      local p = assert(io.popen("ls '" .. dir .. "'"), "cannot list test directory")
      for f in p:lines() do found(f) end
      p:close()
   end
end
table.sort(suiteCatalog)
suiteCatalog = table.concat(suiteCatalog, "\n")
table.sort(suites, function(a, b)
   return a.name .. "." .. a.extension < b.name .. "." .. b.extension
end)

local function loadSuite(suite)
   local path = dir .. "/" .. suite.name .. "." .. suite.extension
   if suite.extension == "lua" then
      return dofile(path)
   end

   -- A Nupp suite is an ordinary module after compilation. Keep its runtime
   -- loader installed while its cases run so it may require project modules.
   local compile = require("nupp.compiler.cli.compile")
   -- The runner is invoked from the project root, just as `nupp test` runs
   -- its configured command. Keep this root normalized for module lookup.
   local env = require("nupp.compiler.env").new(".")
   local settings = compile.settings({})
   local code, compileErr = compile.module(path, env, settings)
   if not code then
      error("cannot compile Nupp test suite " .. path .. ": "
         .. tostring(compileErr), 0)
   end
   local removeLoader = require("nupp.compiler.runtime").install(env, function(modulePath, e)
      return compile.module(modulePath, e, settings)
   end)
   local chunk, loadErr = loadstring(code, "@" .. path)
   if not chunk then
      removeLoader()
      error("cannot load Nupp test suite " .. path .. ": " .. tostring(loadErr), 0)
   end
   local ok, loaded = pcall(chunk)
   if not ok then
      removeLoader()
      error(loaded, 0)
   end
   return loaded, removeLoader
end

--- Where a test function is written, which is stable and worth reporting even
--- when it passes.
local function definedAt(fn)
   local info = debug.getinfo(fn, "S")
   if not info then return nil, nil end
   return (info.source or ""):gsub("^@", ""), info.linedefined
end

--- Splits "tests/foo.lua:42: message" into its parts. A Lua error need not carry
--- a position at all, so the message is returned whole when it does not.
local function errorPosition(message)
   local file, line, rest = tostring(message):match("^(.-):(%d+): (.*)$")
   if not file then return tostring(message), nil, nil end
   return rest, file, tonumber(line)
end

local results = {}
-- One record per suite this process ran, so the report can say where the time
-- went at the granularity the shards are packed at. A suite is more than the sum
-- of its cases: loading it compiles a Nupp suite and runs a Lua one's top level,
-- and `beforeAll` can be the most expensive thing in the file. None of that
-- belongs to any single case, so measuring only cases loses it.
local suiteRecords = {}
local total, passed, failed, skipped = 0, 0, 0, 0
local started = now()
local progressWidth = 0

-- Whether this process is the only one marking on its stream.
--
-- A worker is not: it was handed a descriptor its siblings are also writing to,
-- so the column its own marks would be at is not the column the stream is at.
-- Counting anyway is what made a sharded run break its lines at 573, 35 and 510
-- characters -- each worker faithfully wrapping at its own eightieth mark, thirty
-- six of them, into one stream.
--
-- So a worker writes marks and nothing else, and the run that owns the stream
-- closes the line when the workers are done.
local ownsProgressStream = not sharedProgressStream

local function mark(symbol)
   local styled = symbol == "." and paint("32", symbol)
      or symbol == "S" and paint("1;33", symbol)
      or paint("1;31", symbol)
   progressWrite(styled)
   if not ownsProgressStream then
      return
   end
   progressWidth = progressWidth + 1
   if progressWidth == 80 then
      progressWrite("\n")
      progressWidth = 0
   end
end

local function captured(record)
   local output = record.output
   if not output or (output.stdout == "" and output.stderr == "") then return "" end
   local lines = {"\n  Output from " .. record.suite .. " / " .. record.name .. ":\n"}
   if output.stdout ~= "" then lines[#lines + 1] = "    stdout:\n" .. output.stdout end
   if output.stderr ~= "" then lines[#lines + 1] = "    stderr:\n" .. output.stderr end
   if lines[#lines]:sub(-1) ~= "\n" then lines[#lines + 1] = "\n" end
   return table.concat(lines)
end

local function showCaptured(record)
   local text = captured(record)
   if text == "" then return end
   local stream = asJson and io.stderr or io.stdout
   stream:write(text)
   stream:flush()
end

local HOOKS = {
   beforeAll = true, afterAll = true, beforeEach = true, afterEach = true,
}

local function call(fn)
   if fn == nil then return true end
   return pcall(fn)
end

-- afterEach gets a chance to clean up after a failed setup or test. If both
-- phases fail, keep the original failure as the headline and retain the
-- cleanup failure as the useful second half of the report.
local function runCase(hooks, fn)
   local ok, problem = call(hooks.beforeEach)
   if ok then
      ok, problem = call(fn)
   end
   local afterOk, afterProblem = call(hooks.afterEach)
   if not afterOk then
      if not ok then
         error(tostring(problem) .. "\n  afterEach failed: "
            .. tostring(afterProblem), 0)
      end
      error("afterEach failed: " .. tostring(afterProblem), 0)
   end
   if not ok then
      error(problem, 0)
   end
end

local function recordResult(suite, name, defined, ok, err, stdout, stderr, elapsed)
   total = total + 1
   local file, line = definedAt(defined)
   local record = {suite = suite, name = name, file = file, line = line,
      durationMs = elapsed, status = ok and "passed" or "failed"}
   if ok then
      passed = passed + 1
      if not queueDir then mark(".") end
   elseif test.isSkip(err) then
      skipped = skipped + 1
      record.status = "skipped"
      record.skip = {reason = tostring(test.skipReason(err) or "skipped")}
      if not queueDir then mark("S") end
   else
      failed = failed + 1
      local message, errFile, errLine = errorPosition(err)
      record.failure = {message = message, file = errFile, line = errLine}
      record.output = {stdout = stdout, stderr = stderr}
      if not queueDir then mark("E") end
   end
   if verbose then
      record.output = record.output or {stdout = stdout, stderr = stderr}
      showCaptured(record)
   end
   results[#results + 1] = record
end

-- Splitting the run across isolated lanes.
--
-- A hundred suites in one process took over four minutes while a whole build took
-- twelve seconds, so the wait was the suite rather than the compiler. Suites already
-- expect nothing of each other, so the split is only a matter of handing each lane a
-- list of names and adding up what comes back.
--
-- It stays serial for a single named suite, for `--jobs=1`, inside a shard, and while
-- coverage is collected -- the shards would race each other for the one counter file
-- that `NUPP_COVERAGE_FILE` names.
--- How many workers to make by default: one per processor.
---
--- It was two per processor, from a measurement on eight cores -- 71s at one per
--- core, 63s at two. That machine no longer stands for this one. On eighteen
--- cores, thirty-six workers means the longest test is competing with thirty-five
--- siblings for the machine it needs, and a run's slowest single test grew with
--- the worker count rather than staying put.
---
--- Trying to re-measure the crossover here did not settle it: fifteen consecutive
--- full runs drifted from 70s to 120s at settings that should not have differed,
--- so run order swamped the effect. One per core is the setting that does not
--- oversubscribe, and `--jobs=N` is there for a machine that wants otherwise.
local function defaultJobs()
   local handle = io.popen("getconf _NPROCESSORS_ONLN 2>/dev/null")
   local text = handle and handle:read("*l") or nil
   if handle then handle:close() end
   local found = tonumber(text or "")

   return found and found >= 1 and math.floor(found) or 4
end

--- What the last run measured, so this one can start the slow work first.
---
--- Suites are nothing like equal and nothing about a suite says in advance how long it
--- takes: `fmttest` is 282 lines and fifty seconds, `bootstraptest` is 83 lines and
--- sixteen. Source size is no guide, so the only honest estimate is what happened last
--- time. A first run with no record is evenly guessed and slow; every one after it is
--- packed from measurement.
local timingsPath = dir .. "/../" .. buildDir .. "/.nupp-test-times.json"

--- Where each shard's content-keyed store goes.
---
--- Under the build directory, so `nupp clean` removes it with everything else, and
--- keyed by nothing: the stores inside stamp and key their own entries, so a stale one
--- is a miss rather than a wrong answer.
local shardCacheRoot = dir .. "/../" .. buildDir .. "/.nupp-test-cache"

local recordedOnce = nil
local function recorded()
   if recordedOnce then
      return recordedOnce
   end
   recordedOnce = {suites = {}, cases = {}}
   local file = io.open(timingsPath, "rb")
   if not file then
      return recordedOnce
   end
   local text = file:read("*a")
   file:close()
   local ok, decoded = pcall(function()
      return testJson.decode(text)
   end)
   if ok and type(decoded) == "table" then
      if type(decoded.suites) == "table" then
         recordedOnce.suites = decoded.suites
      end
      if type(decoded.cases) == "table" then
         recordedOnce.cases = decoded.cases
      end
   end

   return recordedOnce
end

local function recordedTimings()
   return recorded().suites
end

--- What each case in a suite last cost, which is what a slice is packed from.
local function recordedCaseTimings(suite)
   local per = recorded().cases[suite]

   return type(per) == "table" and per or {}
end

--- Which slice each case of a suite belongs to.
---
--- Position was the rule -- case `n` went to slice `n % count` -- and position
--- says nothing about cost. `lsptest` ran cases from a tenth of a second to two
--- minutes, so every slice of it was a coin toss and the run's floor was
--- whichever one drew the worst. Longest-first into the emptiest slice is the
--- same makespan heuristic the shards themselves use, one level further down.
---
--- Both ends compute this from the same file: the parent, to know what a slice
--- will actually cost before it packs one, and the child, to know which cases
--- are its own. The file is rewritten once, after every child has finished, so
--- the two cannot disagree within a run.
---
--- An unmeasured case is guessed at the average of the measured ones, the same
--- way an unmeasured suite is, so a case added since the last run is not packed
--- as though it were free.
local function sliceAssignment(cases, costs, count)
   local known, counted = 0, 0
   for _, ms in pairs(costs) do
      known = known + (tonumber(ms) or 0)
      counted = counted + 1
   end
   local average = counted > 0 and known / counted or 1
   local order = {}
   for _, name in ipairs(cases) do
      order[#order + 1] = {name = name, cost = tonumber(costs[name]) or average}
   end
   table.sort(order, function(a, b)
      if a.cost ~= b.cost then
         return a.cost > b.cost
      end

      return a.name < b.name
   end)
   local filled, where = {}, {}
   for index = 0, count - 1 do
      filled[index] = 0
   end
   for _, item in ipairs(order) do
      local into = 0
      for index = 0, count - 1 do
         if filled[index] < filled[into] then
            into = index
         end
      end
      filled[into] = filled[into] + item.cost
      where[item.name] = into
   end

   return where, filled
end

--- What a suite costs a shard, from suite records rather than case records.
---
--- Cases alone under-report: loading is where a Nupp suite is compiled and a Lua
--- one runs its top level, and a `beforeAll` that builds a project belongs to no
--- case at all. Packing from case time alone therefore packs from a number that
--- can be a fraction of what the shard actually waits for.
---
--- Slices are added back up, except for loading, which is taken at its maximum
--- rather than summed. Each slice really does pay the load again, but recording
--- that would raise the suite's estimated cost, which asks for more slices, which
--- raises it again -- a run that slices further every time it is repeated. The
--- maximum is what one whole suite costs, which is the question packing asks.
local function rememberTimings(records, cases)
   local per = {}
   for _, record in ipairs(records) do
      local suite = tostring(record.suite)
      local entry = per[suite] or {work = 0, load = 0}
      per[suite] = entry
      entry.work = entry.work + (tonumber(record.casesMs) or 0)
         + (tonumber(record.hooksMs) or 0)
      entry.load = math.max(entry.load, tonumber(record.loadMs) or 0)
   end
   for suite, entry in pairs(per) do
      per[suite] = entry.work + entry.load
   end
   -- Every case, not only the expensive ones. What a slice is packed from is the
   -- shape of the whole suite, and a suite of two hundred cheap cases and one
   -- heavy one packs differently from a suite of one heavy case, which is a
   -- difference a list of only the heavy ones cannot express.
   local byCase = {}
   for _, record in ipairs(cases or {}) do
      local suite = tostring(record.suite)
      local into = byCase[suite] or {}
      byCase[suite] = into
      into[tostring(record.name)] = tonumber(record.durationMs) or 0
   end
   local json = testJson
   local encoded, text = pcall(json.encode, {suites = per, cases = byCase})
   if not encoded then
      return
   end
   local file = io.open(timingsPath, "wb")
   if file then
      file:write(text .. "\n")
      file:close()
   end
end

--- Orders the suites longest-first, slicing the ones too heavy to be left whole.
---
--- The order is all the plan is. Which worker runs which piece is decided while the
--- run is happening, by whoever is free -- see `takeWork`, which is where the reason
--- lives. Longest-first is what makes that come out well: the pieces that could still
--- unbalance the run are handed out while there is other work to hide behind them.
---
--- A suite costing more than a fair share is asked to run in slices, because one suite
--- longer than the share is on its own the floor however many workers there are: with
--- `selfFormatStable` whole, the best possible run was fifty seconds at any count.
local function planWork(list, shards, timings)
   local known, counted = 0, 0
   for _, ms in pairs(timings) do
      known = known + ms
      counted = counted + 1
   end
   -- An unmeasured suite is guessed at the average rather than zero, so a new one is
   -- not packed last behind everything.
   local average = counted > 0 and known / counted or 1

   local planned = 0
   local costs = {}
   for _, suite in ipairs(list) do
      local cost = tonumber(timings[suite.name]) or average
      costs[#costs + 1] = {name = suite.name, cost = cost}
      planned = planned + cost
   end

   local share = planned / shards
   local work = {}
   for _, item in ipairs(costs) do
      -- What the suite's cases last cost, which is what says whether slicing it
      -- would help and what each slice would come to. A suite whose weight is one
      -- case is not made lighter by being cut in four: three slices come back
      -- empty and the fourth is the floor it always was, so the pieces are capped
      -- at the number of cases there are to spread.
      local caseCosts = recordedCaseTimings(item.name)
      local names = {}
      for name in pairs(caseCosts) do
         names[#names + 1] = name
      end
      table.sort(names)
      -- Half a share rather than a whole one.
      --
      -- Slicing at the share leaves pieces exactly the size of a bin, and
      -- longest-first then puts one of them in a bin and adds whatever is left
      -- over on top: the run's floor was a shard holding a full-share slice plus
      -- four more suites. Halving the target gives the packer pieces it can fit
      -- around each other, and a slice costs only loading its suite again, which
      -- is milliseconds for all but a handful.
      local target = share / 2
      local pieces = 1
      if target > 0 and item.cost > target then
         pieces = math.ceil(item.cost / target)
         if #names > 0 then
            pieces = math.min(pieces, #names)
         end
      end
      if pieces > 1 then
         -- Evenly, when there is nothing measured to pack from. Otherwise from the
         -- assignment the child will make, so the plan costs a slice at what that
         -- slice is going to be rather than at the suite's average.
         local sliced, overhead = nil, 0
         if #names > 0 then
            local spread = 0
            for _, ms in pairs(caseCosts) do
               spread = spread + (tonumber(ms) or 0)
            end
            -- Whatever the suite cost beyond its cases is loading it, and every
            -- slice loads it again. Counted once per slice rather than divided
            -- between them, which is what actually happens.
            overhead = math.max(0, item.cost - spread)
            local _, filled = sliceAssignment(names, caseCosts, pieces)
            sliced = filled
         end
         for index = 0, pieces - 1 do
            work[#work + 1] = {cost = sliced and (sliced[index] + overhead)
               or item.cost / pieces,
               spec = ("%s#%d/%d"):format(item.name, index, pieces)}
         end
      else
         work[#work + 1] = {cost = item.cost, spec = item.name}
      end
   end
   table.sort(work, function(a, b)
      if a.cost ~= b.cost then
         return a.cost > b.cost
      end

      return a.spec < b.spec
   end)

   local order = {}
   for _, item in ipairs(work) do
      order[#order + 1] = item.spec
   end

   return order
end

-- A Nupp worker owns a Lua state, not the process around that state. Suites that
-- touch process-wide facilities therefore keep the subprocess isolation the
-- runner historically gave every suite. Everything else runs on nupp.workers.
-- Looking at the source as well as a short hard list makes the safe choice the
-- default when a new suite starts shelling out.
local PROCESS_ISOLATED = {
   -- These exercise worker hosting or runner descriptor behavior even when the
   -- operation is built as a source fixture rather than called by the Lua test.
   bundletest = true,
   comptimetest = true,
   -- Their compiler fixtures reach build commands through shared helpers, so the
   -- process call is not text in the suite for the source scan below to find.
   deriveacceptancetest = true,
   deriveprovidertest = true,
   derivetest = true,
   loggingtest = true,
   runtimereflectiontest = true,
   serdetest = true,
   typeleveltest = true,
   -- Imports cheadertest as a fixture; its top level asks the shell for an
   -- absolute checkout path on hosts where debug information is relative.
   hotreloadguaranteetest = true,
   projectlinktest = true,
   profiletest = true,
   runnertest = true,
   -- These execute generated ownership cleanups. Their providers are registered
   -- in process-global runtime tables, so a reused worker state is not their
   -- isolation boundary even though the cases themselves do not shell out.
   ioscalarstest = true,
   nativefoundationstest = true,
   soatest = true,
}

local processCalls = {
   "os.execute", "io.popen", 'require("nupp.io.process")',
   "require('nupp.io.process')", 'require("nupp.profile")',
   "require('nupp.profile')", 'require("nupp.workers")',
   "require('nupp.workers')",
}

local function processIsolated(suiteInfo)
   if not suiteInfo or PROCESS_ISOLATED[suiteInfo.name] then
      return suiteInfo ~= nil
   end
   local file = io.open(dir .. "/" .. suiteInfo.name .. "." .. suiteInfo.extension, "rb")
   if not file then
      return true
   end
   local source = file:read("*a") or ""
   file:close()
   for _, call in ipairs(processCalls) do
      if source:find(call, 1, true) then
         return true
      end
   end

   return false
end

local sharded = nil
if #shard == 0 and #suites > 0
   and ((workerHost and not processIsolated(only and byName[only]))
      or (#chosen ~= 1 and #suites > 1 and jobs ~= 1))
   and not os.getenv("NUPP_COVERAGE_FILE") then
   do
      local json = testJson
      local shareable, alone = {}, {}
      for _, suiteInfo in ipairs(suites) do
         local into = processIsolated(suiteInfo) and alone or shareable
         into[#into + 1] = suiteInfo
      end

      local children = 0
      local madeShardRoot = false
      -- Whether any worker wrote a mark, so this end knows whether there is a line
      -- to close. Out here rather than in `fanOut` because it is read after it.
      local marked = false
      local function beginPhase(text)
         if marked then
            progressWrite("\n")
            marked = false
         end
         progressWrite(progressHeading(text) .. "\n")
         progressWidth = 0
      end

      --- Starts one child per group and reads them all back.
      ---
      --- Every child is started before any is read, which is what makes them run
      --- at once: the pipes are open and the children are working while this
      --- blocks on whichever it reads first.
      ---
      --- `nupp.suspension`'s combinators would express the fan-out more directly,
      --- and do for a Nupp program, but reaching `nupp.io.process` from here means
      --- building a compiler environment first so its native provider resolves --
      --- more machinery in the parent than the parent is doing.
      ---
      --- `ownCache` gives each child a content-keyed store of its own. Every suite
      --- that runs `nupp` in a temporary project otherwise starts that project's
      --- store cold, and the most expensive thing in it -- what the compiler's own
      --- modules require, which decides what a stored answer is stamped with -- is
      --- the same answer for all of them. Per child rather than for the whole run
      --- because a store is written whole: children sharing one file would take
      --- turns discarding each other's entries. A suite running on its own has no
      --- one to share with and keeps the warm store this process was started with.
      local function fanOut(lanes, ownCache, isolated, suiteCount)
         if workerHost and ownCache and not isolated then
            local workers = require("nupp.workers")
            local job = require("job")
            local running = {}
            local scope = workers.scope()
            -- A worker state cannot redirect process-owned descriptors safely.
            -- Keep inherited output quiet for the threaded phase; ordinary Lua
            -- output is captured in its state, process-writing suites are in the
            -- isolated phase, and progress has its own saved descriptor.
            local restoreOutput = silenceProcessOutput()
            for _, lane in ipairs(lanes) do
               local index = children + 1
               children = index
               madeShardRoot = madeShardRoot
                  or os.execute("mkdir -p '" .. shardCacheRoot .. "'") ~= nil
               local cache = ("%s/shard-%d"):format(shardCacheRoot, index)
               running[#running + 1] = {
                  label = lane.label,
                  index = index,
                  startedAt = now() - started,
                  task = scope:spawn(job.run, lane.arg, cache, progressFd,
                     verbose, colorMode, suiteCatalog),
               }
            end

            if #running > 0 then
               beginPhase(("%d suites across %d Nupp workers")
                  :format(suiteCount or #shareable, #running))
               marked = true
            end

            local reports = {}
            for _, child in ipairs(running) do
               local ok, report = pcall(function() return child.task:await() end)
               if ok and type(report) == "table" then
                  report.shard = {index = child.index,
                     names = (report.claimed and #report.claimed > 0)
                        and report.claimed or {child.label},
                     startedAt = child.startedAt, collectedAt = now() - started}
                  reports[#reports + 1] = report
               else
                  reports[#reports + 1] = {names = {child.label},
                     failure = tostring(report)}
               end
            end
            scope:close()
            restoreOutput()

            return reports
         end

         local running = {}
         for _, lane in ipairs(lanes) do
            do
               local index = children + 1
               local label = lane.label
               children = index
               -- The store the children share a parent directory with is made by
               -- whoever writes into it, and nothing had yet. A redirect into a
               -- directory that is not there fails in the shell, before the child
               -- runs, so every one of them would have died saying nothing.
               madeShardRoot = madeShardRoot
                  or os.execute("mkdir -p '" .. shardCacheRoot .. "'") ~= nil
               -- Kept rather than inherited, so a child that dies can be asked
               -- why. One that wrote no report used to say only that, which is the
               -- least useful thing known about it: whether it was killed, ran out
               -- of memory, or wrote something that was not JSON all read the same.
               local errors = ("%s/shard-%d.err"):format(shardCacheRoot, index)
               local cache = ownCache
                  and ("NUPP_CACHE_DIR='%s/shard-%d' "):format(shardCacheRoot, index)
                  or ""
               -- The shell reports the wait status because this end cannot:
               -- LuaJIT's `close` on a pipe answers whether it closed, not what
               -- happened to what was on the other side, so a child that was killed
               -- and one that exited quietly are the same nil here. `$?` past 128 is
               -- the signal, which is the difference between a crash and an OOM kill.
               -- `9>&2` copies this process's standard error aside before `2>`
               -- sends the worker's to its file, so `3>&9` hands the worker a
               -- descriptor that still reaches the terminal. Two destinations, one
               -- for marks and one for whatever it says on the way down.
               -- Named rather than redirected: the worker inherits the
               -- descriptor across the fork and writes its marks straight to it,
               -- while its standard error still goes to the file this end keeps to
               -- ask a dead worker why. Without a descriptor to name -- a build
               -- with no FFI -- the worker marks into that file, which is where
               -- every mark used to go and why a sharded run said nothing at all
               -- until the first worker finished.
               local progress = progressFd
                  and ("NUPP_TEST_PROGRESS_FD=%d "):format(progressFd) or ""
               local command = ("{ %s%sluajit '%s' --json %s --color=%s%s; echo \"__status__:$?\" >&2; } 2>'%s'")
                  :format(cache, progress, arg[0], lane.arg,
                     colorMode, verbose and " --verbose" or "", errors)
               running[#running + 1] = {label = label, errors = errors,
                  index = index, startedAt = now() - started,
                  pipe = io.popen(command, "r")}
            end
         end

         -- Said before the first mark rather than left to be inferred from its
         -- absence. A worker marks a suite slice off when it finishes it, and the first
         -- one to finish anywhere can be half a minute in on a cold tree, which
         -- looks exactly like a run that has not started.
         if #running > 0 then
            beginPhase(("%d process-isolated suites across %d workers")
               :format(suiteCount or #lanes, #running))
         end

         if #running > 0 then
            marked = true
         end
         local reports = {}
         for _, child in ipairs(running) do
            if not child.pipe then
               reports[#reports + 1] = {failure = "the worker could not be started",
                  names = {child.label}}
            else
               local text = child.pipe:read("*a")
               local _, how, code = child.pipe:close()
               local decoded, report = pcall(json.decode, text or "")
               if decoded and type(report) == "table" then
                  -- What the parent knows and the child cannot: which shard this
                  -- was, when it was started, and when this end finished reading
                  -- it. The child's own `durationMs` is its wall clock, which is
                  -- the honest measure -- the pipes are read in order, so when the
                  -- parent noticed says more about read order than about the shard.
                  report.shard = {index = child.index,
                     names = (report.claimed and #report.claimed > 0)
                        and report.claimed or {child.label},
                     alone = isolated or nil,
                     startedAt = child.startedAt, collectedAt = now() - started}
                  reports[#reports + 1] = report
               else
                  -- Everything known about the death, in the failure itself. A
                  -- signal names how it was killed; the tail of its standard error
                  -- says what it managed to complain about first; the length of
                  -- what it wrote separates "nothing at all" from "not JSON".
                  local why = {}
                  if how then
                     why[#why + 1] = ("%s %s"):format(tostring(how), tostring(code))
                  end
                  why[#why + 1] = ("%d bytes on stdout"):format(#(text or ""))
                  local errored = io.open(child.errors, "rb")
                  if errored then
                     local said = errored:read("*a") or ""
                     errored:close()
                     local status = said:match("__status__:(%d+)")
                     if status then
                        local code = tonumber(status) or 0
                        why[#why + 1] = code > 128
                           and ("killed by signal %d"):format(code - 128)
                           or ("exit %d"):format(code)
                        said = said:gsub("__status__:%d+%s*$", "")
                     end
                     if #said > 0 then
                        why[#why + 1] = "stderr: " .. said:sub(-2000)
                     end
                  end
                  reports[#reports + 1] = {names = {child.label},
                     failure = "the worker wrote no report (" .. table.concat(why, "; ") .. ")"}
               end
            end
         end

         return reports
      end

      sharded = {results = {}, suites = {}, shards = {},
         total = 0, passed = 0, skipped = 0, failed = 0}

      local function absorb(reports)
         for _, report in ipairs(reports) do
            if report ~= nil and report.failure then
               -- A child that died says so as a failure of its own rather than
               -- quietly removing its suites from the count.
               sharded.total = sharded.total + 1
               sharded.failed = sharded.failed + 1
               sharded.results[#sharded.results + 1] = {
                  suite = table.concat(report.names, ","),
                  name = "<shard>",
                  status = "failed",
                  failure = {message = report.failure},
               }
            elseif report ~= nil then
               sharded.total = sharded.total + (report.total or 0)
               sharded.passed = sharded.passed + (report.passed or 0)
               sharded.skipped = sharded.skipped + (report.skipped or 0)
               sharded.failed = sharded.failed + (report.failed or 0)
               for _, record in ipairs(report.tests or {}) do
                  sharded.results[#sharded.results + 1] = record
               end
               for _, record in ipairs(report.suites or {}) do
                  record.shard = report.shard and report.shard.index or nil
                  record.alone = report.shard and report.shard.alone or nil
                  sharded.suites[#sharded.suites + 1] = record
               end
               if report.shard then
                  sharded.shards[#sharded.shards + 1] = {
                     index = report.shard.index,
                     specs = report.shard.names,
                     alone = report.shard.alone,
                     durationMs = tonumber(report.durationMs) or 0,
                     startedAt = report.shard.startedAt,
                     collectedAt = report.shard.collectedAt,
                     tests = report.total or 0,
                  }
               end
            end
         end
      end

      -- Run a dynamically-fed queue either in Nupp worker states or in process
      -- workers. The queue shape stays identical, so isolation does not give up
      -- load balancing or per-lane compiler caches.
      local function runQueue(list, isolated)
         if #list == 0 then return end
         local count = math.min(jobs or defaultJobs(), #list)
         local order = planWork(list, count, recordedTimings())
         local ticket = os.tmpname():match("[^/\\]+$") or tostring(#order)
         local queue = shardCacheRoot .. "/queue-" .. ticket
         os.execute("rm -rf '" .. queue .. "' && mkdir -p '" .. queue .. "'")
         local listing = assert(io.open(queue .. "/order", "wb"))
         listing:write(table.concat(order, "\n") .. "\n")
         listing:close()
         for index = 1, #order do
            local piece = assert(io.open(("%s/piece-%d"):format(queue, index), "wb"))
            piece:write(order[index], "\n")
            piece:close()
         end
         local lanes = {}
         for index = 1, math.min(count, #order) do
            lanes[#lanes + 1] = {arg = "--queue=" .. queue,
               label = (isolated and "process worker " or "Nupp worker ") .. index}
         end
         absorb(fanOut(lanes, true, isolated, #list))
         os.execute("rm -rf '" .. queue .. "'")

         -- Work nobody reported having run. A worker that dies holding a piece
         -- takes it with it, and silently doing less than requested is a failure.
         local ran = {}
         for _, entry in ipairs(sharded.shards) do
            for _, spec in ipairs(entry.specs or {}) do
               ran[spec] = true
            end
         end
         for _, spec in ipairs(order) do
            if not ran[spec] then
               sharded.total = sharded.total + 1
               sharded.failed = sharded.failed + 1
               sharded.results[#sharded.results + 1] = {
                  suite = (spec:match("^(.-)#") or spec),
                  name = "<unrun>",
                  status = "failed",
                  failure = {message = "no worker reported running " .. spec},
               }
            end
         end
      end

      runQueue(alone, true)
      runQueue(shareable, false)

      -- Workers mark completed cases without a newline because none can know
      -- whether another lane has a final mark. The parent closes it once both
      -- phases are collected.
      if marked then
         progressWrite("\n")
         progressWidth = 0
      end

      -- Back into the order a serial run would have reported, so the output does not
      -- depend on which shard happened to finish first.
      table.sort(sharded.results, function(a, b)
         if a.suite ~= b.suite then
            return tostring(a.suite) < tostring(b.suite)
         end

         return tostring(a.name) < tostring(b.name)
      end)
      suites = {}
   end
end

--- Runs one suite, or the cases of it that one slice was given.
---
--- A parameter rather than a lookup, because the cases a process runs are
--- decided in two different ways: a shard was handed a list of specs before it
--- started, and a worker takes one spec at a time off a queue while it runs.
local restoreLane = function() end

local function runSuite(suiteInfo, slices)
   -- Loading is measured with the suite rather than left out of it. A Nupp suite
   -- is compiled here, and a Lua one runs its top level here, so a suite can cost
   -- seconds before its first case starts.
   local loadBefore = now()
   local suite, removeLoader = loadSuite(suiteInfo)
   local loadElapsed = now() - loadBefore
   local hooks = {}
   local cases = {}
   for name, fn in pairs(suite) do
      if HOOKS[name] then
         hooks[name] = fn
      else
         cases[#cases + 1] = name
      end
   end
   table.sort(cases)
   local stateful = hooks.beforeAll or hooks.afterAll
      or hooks.beforeEach or hooks.afterEach
   -- One slice of the suite, when the parent decided it was too heavy to leave whole.
   -- A suite with lifecycle hooks is never sliced: `beforeAll` would run once per slice
   -- and any state its cases share would be split between processes, so the whole thing
   -- goes to slice zero and the other slices find nothing to do.
   local partial = false
   for _, slice in ipairs(slices or {}) do
      if slice.count > 1 then
         partial = true
      end
   end
   if partial then
      if stateful then
         -- Never sliced: `beforeAll` would run once per slice and whatever the cases
         -- share would be split between processes. Slice zero takes the whole suite and
         -- the others find nothing to do.
         local takesAll = false
         for _, slice in ipairs(slices) do
            if slice.index == 0 then
               takesAll = true
            end
         end
         if not takesAll then
            cases = {}
         end
      else
         -- Packing is by cost, and a shard may legitimately hold two slices of one
         -- suite, so each slice is asked for its own cases and the answers are
         -- unioned back into the sorted order the suite reports in.
         local costs = recordedCaseTimings(suiteInfo.name)
         local taken = {}
         for _, slice in ipairs(slices) do
            local where = sliceAssignment(cases, costs, slice.count)
            for _, name in ipairs(cases) do
               if where[name] == slice.index then
                  taken[name] = true
               end
            end
         end
         local mine = {}
         for _, name in ipairs(cases) do
            if taken[name] then
               mine[#mine + 1] = name
            end
         end
         cases = mine
      end
   end
   local before = now()
   local ready, setupProblem, setupOut, setupErr = capture(function()
      local ok, problem = call(hooks.beforeAll)
      if not ok then error(problem, 0) end
   end)
   local setupElapsed = now() - before
   local casesElapsed = 0
   local slowestCase, slowestCaseMs = nil, -1
   if not ready then
      recordResult(suiteInfo.name, "beforeAll", hooks.beforeAll, false,
         setupProblem, setupOut, setupErr, setupElapsed)
   else
      for _, name in ipairs(cases) do
         local case = suite[name]
         local caseBefore = now()
         local ok, err, stdout, stderr = capture(function()
            runCase(hooks, case)
         end)
         local caseElapsed = now() - caseBefore
         casesElapsed = casesElapsed + caseElapsed
         if caseElapsed > slowestCaseMs then
            slowestCase, slowestCaseMs = name, caseElapsed
         end
         recordResult(suiteInfo.name, name, case, ok, err, stdout, stderr,
            caseElapsed)
      end
   end
   local after = now()
   local afterOk, afterProblem, afterOut, afterErr = capture(function()
      local ok, problem = call(hooks.afterAll)
      if not ok then error(problem, 0) end
   end)
   local afterElapsed = now() - after
   if not afterOk then
      recordResult(suiteInfo.name, "afterAll", hooks.afterAll, false,
         afterProblem, afterOut, afterErr, afterElapsed)
   end
   if removeLoader then removeLoader() end
   suiteRecords[#suiteRecords + 1] = {
      suite = suiteInfo.name,
      durationMs = now() - loadBefore,
      loadMs = loadElapsed,
      hooksMs = setupElapsed + afterElapsed,
      casesMs = casesElapsed,
      tests = #cases,
      slowestCase = slowestCase,
      slowestCaseMs = slowestCase and slowestCaseMs or nil,
   }
end

-- A process lane now claims several suites from the dynamic queue. Restore the
-- shallow module and runtime-registration tables between them so a suite that
-- deliberately clears package.loaded cannot poison whichever suite it claims
-- next. Nupp lanes deliberately retain their warm compiler state; suites that
-- mutate these process-shaped tables are classified above instead.
local laneBaseline = nil
local missingGlobal = {}
if queueDir and not embedded then
   local function copyTable(value)
      local copied = {}
      for key, item in pairs(value) do copied[key] = item end
      return copied
   end
   local globals = {}
   for _, key in ipairs({"nupp", "__nuppCleanupRegistry",
      "__nuppManagedBrand", "__nuppManagedCells",
      "__nuppManagedPolicyCount"}) do
      globals[key] = _G[key] == nil and missingGlobal or _G[key]
   end
   laneBaseline = {globals = globals, loaded = copyTable(package.loaded),
      preload = copyTable(package.preload)}
end

restoreLane = function()
   if not laneBaseline then return end
   local function restore(value, baseline)
      for key in pairs(value) do
         if baseline[key] == nil then value[key] = nil end
      end
      for key, item in pairs(baseline) do value[key] = item end
   end
   restore(package.loaded, laneBaseline.loaded)
   restore(package.preload, laneBaseline.preload)
   for key, item in pairs(laneBaseline.globals) do
      _G[key] = item == missingGlobal and nil or item
   end
end

--- What this process took off the queue, so the parent can tell work that was
--- run from work whose worker died holding it.
local claimed = {}

--- Takes work until there is none left.
---
--- Packing the whole run in advance needs the cost of every suite known in
--- advance, and it is not: the record is what the last run measured under its
--- own load, and a run measures a suite two or three times slower when it lands
--- beside four heavy ones than when it lands beside nothing. Packed from that,
--- the busiest shard came out near twice the mean and the run waited on it.
---
--- So the parent orders the work longest-first and every worker takes the next
--- piece when it has finished the last. An estimate that was wrong then costs
--- the difference rather than the whole imbalance, and the makespan is the mean
--- plus one piece.
---
--- A claim is `os.rename`, which is atomic on both the filesystems this runs on
--- and needs no lock, no daemon and no subprocess: the parent writes one file
--- per piece and the worker that renames it first owns it. Losing the race
--- returns nil, which is the whole protocol.
local function takeWork()
   local file = io.open(queueDir .. "/order", "rb")
   if not file then return end
   local specs = {}
   for line in file:lines() do
      if line ~= "" then specs[#specs + 1] = line end
   end
   file:close()

   local cursor = 0
   while true do
      local took = nil
      for step = 1, #specs do
         local index = (cursor + step - 1) % #specs + 1
         local mine = ("%s/taken-%d"):format(queueDir, index)
         if os.rename(("%s/piece-%d"):format(queueDir, index), mine) then
            took, cursor = index, index
            break
         end
      end
      if not took then return end
      local spec = specs[took]
      claimed[#claimed + 1] = spec
      local name, index, count = spec:match("^(.-)#(%d+)/(%d+)$")
      name = name or spec
      local suiteInfo = byName[name]
      if suiteInfo then
         local beforeTotal, beforePassed = total, passed
         local beforeFailed = failed
         runSuite(suiteInfo, index and {{index = tonumber(index),
            count = tonumber(count)}} or nil)
         if total > beforeTotal then
            mark(failed > beforeFailed and "E"
               or passed == beforePassed and "S" or ".")
         end
      end
      restoreLane()
   end
end

if queueDir then
   takeWork()
else
   for _, suiteInfo in ipairs(suites) do
      runSuite(suiteInfo, wanted and wanted[suiteInfo.name] or nil)
   end
end
local duration = now() - started
if sharded then
   -- Added to what this process ran rather than replacing it: the exclusive
   -- suites were run here, after the shards, and are already in `results`.
   for _, record in ipairs(sharded.results) do
      results[#results + 1] = record
   end
   for _, record in ipairs(sharded.suites) do
      suiteRecords[#suiteRecords + 1] = record
   end
   total = total + sharded.total
   passed = passed + sharded.passed
   skipped = skipped + sharded.skipped
   failed = failed + sharded.failed
   table.sort(results, function(a, b)
      if a.suite ~= b.suite then
         return tostring(a.suite) < tostring(b.suite)
      end

      return tostring(a.name) < tostring(b.name)
   end)
end

-- Recorded by the parent after both lanes are collected, so the next run packs
-- from every suite rather than whichever queue one worker happened to claim.
-- Only a run that decided the whole selection has anything to say: a shard was
-- handed its share, and a single named suite says nothing about the rest.
if #shard == 0 and #chosen == 0 and not queueDir then
   rememberTimings(suiteRecords, results)
end

-- Coverage-generated modules share one small global counter table.  The runner owns
-- the process boundary, so it is the right place to turn that in-memory table into a
-- shard the parent `nupp coverage` command can merge after the test process exits.
local coverageFile = os.getenv("NUPP_COVERAGE_FILE")
local coverage = coverageFile and rawget(_G, "__nuppCoverage") or nil
if coverageFile and coverage then
   local json = testJson
   local merged = {}
   local previous = io.open(coverageFile, "rb")
   if previous then
      local text = previous:read("*a")
      previous:close()
      local ok, old = pcall(json.decode, text)
      if ok and type(old) == "table" and type(old.hits) == "table" then
         merged = old.hits
      end
   end
   for path, counters in pairs(coverage.hits) do
      local into = merged[path] or {}
      merged[path] = into
      for id, count in pairs(counters) do
         into[id] = (into[id] or 0) + count
      end
   end
   local f, coverageErr = io.open(coverageFile, "wb")
   if not f then
      io.stderr:write("nupp: cannot write coverage data: " .. tostring(coverageErr) .. "\n")
   else
      f:write(json.encode({hits = merged}) .. "\n")
      f:close()
   end
end

if progressWidth ~= 0 then progressWrite("\n") end

table.sort(suiteRecords, function(a, b)
   local left, right = tonumber(a.durationMs) or 0, tonumber(b.durationMs) or 0
   if left ~= right then return left > right end

   return tostring(a.suite) < tostring(b.suite)
end)

--- Where the run's time went, in the two units a person can act on.
---
--- Wall clock is what was waited for; work is what was spent, added up across the
--- shards. The distance between them is the parallelism actually achieved, and
--- the longest single shard is the floor no amount of extra shards moves -- which
--- is why the shard line reports the busiest one rather than only the average.
local function timingReport()
   local out = {}
   local function say(text) out[#out + 1] = text end
   -- Seconds once there are seconds to report, milliseconds while there are not.
   -- Most suites are under a second and a column of `0.0s` says nothing about
   -- which of them is a hundred times the others.
   local function seconds(ms)
      ms = tonumber(ms) or 0
      if ms < 1000 then return ("%.0fms"):format(ms) end

      return ("%.1fs"):format(ms / 1000)
   end

   local work = 0
   for _, record in ipairs(suiteRecords) do
      work = work + (tonumber(record.durationMs) or 0)
   end
   local headline = ("\n%s %s wall, %s of suite work"):format(
      paint("1;36", "Timing:"), seconds(duration), seconds(work))
   -- Process-isolated work runs first so retained Nupp worker states do not put
   -- memory pressure on it. Report the two phases in that same order.
   local shards, aloneShards = {}, {}
   for _, entry in ipairs(sharded and sharded.shards or {}) do
      local into = entry.alone and aloneShards or shards
      into[#into + 1] = entry
   end
   local function phase(label, entries)
      if #entries == 0 then return end
      local busiest, idlest, spent = 0, math.huge, 0
      for _, entry in ipairs(entries) do
         local ms = tonumber(entry.durationMs) or 0
         spent = spent + ms
         if ms > busiest then busiest = ms end
         if ms < idlest then idlest = ms end
      end
      headline = headline .. ("\n  %d %s: busiest %s, idlest %s, mean %s")
         :format(#entries, label, seconds(busiest), seconds(idlest),
            seconds(spent / #entries))
   end
   phase("process-isolated workers", aloneShards)
   phase("Nupp worker shards", shards)
   say(headline .. "\n")

   local shown = 0
   say("\n" .. paint("1;36", ("  %-27s %8s %8s %8s %8s %6s")
      :format("slowest suites", "wall", "load", "hooks", "cases", "tests")) .. "\n")
   for _, record in ipairs(suiteRecords) do
      if shown >= timingRows then
         say(("  %-27s (%d more)\n"):format("", #suiteRecords - shown))
         break
      end
      shown = shown + 1
      say(("  %-27s %8s %8s %8s %8s %6d\n"):format(
         tostring(record.suite):sub(1, 27), seconds(record.durationMs),
         seconds(record.loadMs), seconds(record.hooksMs),
         seconds(record.casesMs), tonumber(record.tests) or 0))
   end

   local slowest = {}
   for _, record in ipairs(results) do
      slowest[#slowest + 1] = record
   end
   table.sort(slowest, function(a, b)
      local left, right = tonumber(a.durationMs) or 0, tonumber(b.durationMs) or 0
      if left ~= right then return left > right end

      return tostring(a.suite) .. tostring(a.name)
         < tostring(b.suite) .. tostring(b.name)
   end)
   shown = 0
   say("\n" .. paint("1;36", ("  %-53s %8s")
      :format("slowest tests", "wall")) .. "\n")
   for _, record in ipairs(slowest) do
      if shown >= timingRows then
         say(("  %-53s (%d more)\n"):format("", #slowest - shown))
         break
      end
      shown = shown + 1
      local label = ("%s / %s"):format(tostring(record.suite), tostring(record.name))
      say(("  %-53s %8s\n"):format(label:sub(1, 53), seconds(record.durationMs)))
   end

   return table.concat(out)
end

local report = {ok = failed == 0, total = total, passed = passed,
   skipped = skipped, failed = failed, durationMs = duration,
   tests = results, suites = suiteRecords,
   shards = sharded and sharded.shards or {},
   claimed = #claimed > 0 and claimed or nil}

if embedded then
   return report
elseif asJson then
   local json = testJson
   io.write(json.encode({ok = report.ok, total = total, passed = passed,
      skipped = skipped, failed = failed, durationMs = duration,
      tests = json.asArray(results), suites = json.asArray(suiteRecords),
      shards = json.asArray(sharded and sharded.shards or {}),
      -- What this process took off a queue, which is how the parent tells work
      -- that ran from work whose worker died holding it. A run that was not
      -- handed a queue took nothing, and says nothing.
      claimed = #claimed > 0 and json.asArray(claimed) or nil}) .. "\n")
else
   if failed > 0 then
      io.write("\n" .. paint("1;31", "Failures:") .. "\n")
      for _, record in ipairs(results) do
         if record.status == "failed" then
            local label = ("%s / %s"):format(record.suite, record.name)
            io.write(("\n  %s\n      %s\n"):format(
               paint("1;31", label), record.failure.message))
            io.write(captured(record))
         end
      end
   end
   local summary = ("%d tests, %d passed, %d skipped, %d failed (%.1fms)")
      :format(total, passed, skipped, failed, duration)
   io.write("\n" .. paint(failed == 0 and "1;32" or "1;31", summary) .. "\n")
   if timingRows > 0 and #suiteRecords > 0 then
      io.write(timingReport())
   end
end
-- A run that discovered nothing is a broken run, not a passing one. Reported
-- only where the whole selection is known: a shard child is handed its share of
-- the work, and a slice of a suite that carries lifecycle hooks is legitimately
-- empty because slice zero took every case.
if #shard == 0 and not queueDir and total == 0 then
   io.stderr:write("nupp: no tests were discovered\n")
   os.exit(1)
end

os.exit(failed == 0 and 0 or 1)
