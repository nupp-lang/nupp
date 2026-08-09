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
local dir = arg[0]:match("^(.*)[/\\]") or "."
local buildDir = os.getenv("NUPP_COVERAGE_BUILD") or "build"
package.path = dir .. "/../" .. buildDir .. "/?.lua;" .. dir .. "/?.lua;"
   .. package.path
local test = require("assert")

-- Existing suites use Lua's familiar assert spelling.  Give those assertions
-- useful falsy diagnostics, while `require("assert")` exposes equal, matches,
-- raises and skip for new assertions that can say exactly what differed.
assert = test.assert

local asJson = false
local verbose = false
local only = nil
for _, argument in ipairs(arg) do
   if argument == "--json" then
      asJson = true
   elseif argument == "--verbose" then
      verbose = true
   elseif argument:sub(1, 1) ~= "-" then
      only = argument
   end
end

-- Tests often run a command specifically to make it print a diagnostic. Lua's
-- `io.output` cannot capture that command's inherited descriptors, so redirect
-- the descriptors themselves. The runner keeps duplicates for its own progress
-- marks, which must stay visible while a test owns the usual stdout and stderr.
local capture
local progressWrite
do
   local loaded, ffi = pcall(require, "ffi")
   if loaded and ffi.os ~= "Windows" then
      ffi.cdef[[
         int dup(int);
         int dup2(int, int);
         int open(const char *, int, int);
         int close(int);
         int fflush(void *);
         long write(int, const void *, unsigned long);
      ]]
      local C = ffi.C
      local create = ffi.os == "OSX" and 0x200 or 0x40
      local truncate = ffi.os == "OSX" and 0x400 or 0x200
      local statusFd = C.dup(asJson and 2 or 1)

      progressWrite = function(text)
         C.write(statusFd, text, #text)
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

      capture = function(run)
         local outPath, errPath = os.tmpname(), os.tmpname()
         flush()
         local savedOut, savedErr = C.dup(1), C.dup(2)
         local out = C.open(outPath, 1 + create + truncate, 384)
         local err = C.open(errPath, 1 + create + truncate, 384)
         assert(savedOut >= 0 and savedErr >= 0 and out >= 0 and err >= 0,
            "cannot capture test output")
         assert(C.dup2(out, 1) >= 0 and C.dup2(err, 2) >= 0,
            "cannot redirect test output")
         C.close(out); C.close(err)
         local ok, problem = pcall(run)
         flush()
         assert(C.dup2(savedOut, 1) >= 0 and C.dup2(savedErr, 2) >= 0,
            "cannot restore test output")
         C.close(savedOut); C.close(savedErr)
         return ok, problem, read(outPath), read(errPath)
      end
   else
      -- The runner remains useful on a LuaJIT without descriptor access, but a
      -- host that cannot redirect descriptors cannot hide child-process output.
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

local suites = {}
do
   local p = assert(io.popen("ls '" .. dir .. "'"), "cannot list test directory")
   for f in p:lines() do
      local name, extension = f:match("^(.*test)%.([^.]+)$")
      if name and (extension == "lua" or extension == "nupp")
         and (not only or name == only) then
         suites[#suites + 1] = {name = name, extension = extension}
      end
   end
   p:close()
end
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
local total, passed, failed, skipped = 0, 0, 0, 0
local started = now()
local progressWidth = 0

local function mark(symbol)
   progressWrite(symbol)
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
      mark(".")
   elseif test.isSkip(err) then
      skipped = skipped + 1
      record.status = "skipped"
      record.skip = {reason = tostring(test.skipReason(err) or "skipped")}
      mark("S")
   else
      failed = failed + 1
      local message, errFile, errLine = errorPosition(err)
      record.failure = {message = message, file = errFile, line = errLine}
      record.output = {stdout = stdout, stderr = stderr}
      mark("E")
   end
   if verbose then
      record.output = record.output or {stdout = stdout, stderr = stderr}
      showCaptured(record)
   end
   results[#results + 1] = record
end

for _, suiteInfo in ipairs(suites) do
   local suite, removeLoader = loadSuite(suiteInfo)
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
   local before = now()
   local ready, setupProblem, setupOut, setupErr = capture(function()
      local ok, problem = call(hooks.beforeAll)
      if not ok then error(problem, 0) end
   end)
   local setupElapsed = now() - before
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
         recordResult(suiteInfo.name, name, case, ok, err, stdout, stderr,
            now() - caseBefore)
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
end
local duration = now() - started

-- Coverage-generated modules share one small global counter table.  The runner owns
-- the process boundary, so it is the right place to turn that in-memory table into a
-- shard the parent `nupp coverage` command can merge after the test process exits.
local coverageFile = os.getenv("NUPP_COVERAGE_FILE")
local coverage = coverageFile and rawget(_G, "__nuppCoverage") or nil
if coverageFile and coverage then
   local json = require("cjson").new()
   json.encode_empty_table_as_object(false)
   json.encode_invalid_numbers(false)
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

if asJson then
   local json = require("cjson").new()
   json.encode_empty_table_as_object(false)
   json.encode_invalid_numbers(false)
   io.write(json.encode({ok = failed == 0, total = total, passed = passed,
      skipped = skipped, failed = failed, durationMs = duration,
      tests = results}) .. "\n")
else
   if failed > 0 then
      io.write("\nFailures:\n")
      for _, record in ipairs(results) do
         if record.status == "failed" then
            io.write(("\n  %s / %s\n      %s\n"):format(record.suite,
               record.name, record.failure.message))
            io.write(captured(record))
         end
      end
   end
   io.write(("\n%d tests, %d passed, %d skipped, %d failed (%.1fms)\n")
      :format(total, passed, skipped, failed, duration))
end
os.exit(failed == 0 and 0 or 1)
