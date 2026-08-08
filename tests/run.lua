-- Minimal dependency-free test runner: loads tests/*test.lua, runs every
-- function in the returned table, reports failures with their assert message.
--
-- With --json it reports the same run as one document: a record per test with
-- where it is defined, how long it took, and — when it failed — the message and
-- the file and line the error came from. Lines are 1-based, as everywhere else;
-- a Lua error carries no column, so none is invented.
local dir = arg[0]:match("^(.*)[/\\]") or "."
package.path = dir .. "/../build/?.lua;" .. dir .. "/?.lua;" .. package.path
local test = require("assert")

-- Existing suites use Lua's familiar assert spelling.  Give those assertions
-- useful falsy diagnostics, while `require("assert")` exposes equal, matches,
-- raises and skip for new assertions that can say exactly what differed.
assert = test.assert

local asJson = false
local only = nil
for _, argument in ipairs(arg) do
   if argument == "--json" then
      asJson = true
   elseif argument:sub(1, 1) ~= "-" then
      only = argument
   end
end

-- Wall clock, because most of what these tests spend time on is a subprocess,
-- which no measure of this process's own CPU time would ever see. The FFI is
-- guarded the same way nupp.ansi guards it: a build without it still runs the
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

local names = {}
do
   local p = assert(io.popen("ls '" .. dir .. "'"), "cannot list test directory")
   for f in p:lines() do
      local mod = f:match("^(.*test)%.lua$")
      if mod and (not only or mod == only) then names[#names + 1] = mod end
   end
   p:close()
end
table.sort(names)

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
local progress = asJson and io.stderr or io.stdout
local progressWidth = 0

local function mark(symbol)
   progress:write(symbol)
   progress:flush()
   progressWidth = progressWidth + 1
   if progressWidth == 80 then
      progress:write("\n")
      progressWidth = 0
   end
end

for _, mod in ipairs(names) do
   local suite = dofile(dir .. "/" .. mod .. ".lua")
   local cases = {}
   for name in pairs(suite) do cases[#cases + 1] = name end
   table.sort(cases)
   for _, name in ipairs(cases) do
      total = total + 1
      local file, line = definedAt(suite[name])
      local before = now()
      local ok, err = pcall(suite[name])
      local elapsed = now() - before
      local record = {suite = mod, name = name, file = file, line = line,
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
         mark("E")
      end
      results[#results + 1] = record
   end
end
local duration = now() - started

if progressWidth ~= 0 then progress:write("\n") end

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
         end
      end
   end
   io.write(("\n%d tests, %d passed, %d skipped, %d failed (%.1fms)\n")
      :format(total, passed, skipped, failed, duration))
end
os.exit(failed == 0 and 0 or 1)
