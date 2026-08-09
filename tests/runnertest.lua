-- The runner is itself a command-line program. Exercise a fresh copy so this
-- test can observe exactly what a person sees, without recursing into this
-- repository's own suite.
local test = require("assert")
local M = {}

local ROOT = debug.getinfo(1, "S").source:match("^@(.+)/tests/")
if not ROOT then
   local p = assert(io.popen("pwd"))
   ROOT = p:read("*l")
   p:close()
end

local function read(path)
   local f = assert(io.open(path, "rb"))
   local text = f:read("*a")
   f:close()
   return text
end

local function write(path, text)
   local f = assert(io.open(path, "wb"))
   f:write(text)
   f:close()
end

local function run(path, args)
   local pipe = assert(io.popen(("luajit %q %s 2>&1"):format(path, args or "")))
   local output = pipe:read("*a")
   pipe:close()
   return output
end

function M.hidesPassingOutputUnlessVerbose()
   local dir = os.tmpname()
   os.remove(dir)
   assert(os.execute("mkdir -p " .. string.format("%q", dir)) == 0)
   write(dir .. "/run.lua", read(ROOT .. "/tests/run.lua"))
   write(dir .. "/assert.lua", read(ROOT .. "/tests/assert.lua"))
   write(dir .. "/noisytest.lua", [[
local M = {}
function M.writesToBothStreams()
   io.stdout:write("ordinary output\n")
   io.stderr:write("diagnostic output\n")
end
return M
]])
   write(dir .. "/failuretest.lua", [[
local M = {}
function M.writesBeforeFailing()
   io.stdout:write("failing stdout\n")
   io.stderr:write("failing stderr\n")
   error("the intended failure")
end
return M
]])

   local plain = run(dir .. "/run.lua")
   test.equal(plain:find("ordinary output", 1, true), nil,
      "passing stdout stays hidden")
   test.equal(plain:find("diagnostic output", 1, true), nil,
      "passing stderr stays hidden")
   test.matches(plain, "Output from failuretest / writesBeforeFailing")
   test.matches(plain, "failing stdout")
   test.matches(plain, "failing stderr")

   local verbose = run(dir .. "/run.lua", "--verbose")
   test.matches(verbose, "ordinary output")
   test.matches(verbose, "diagnostic output")
   os.execute("rm -rf " .. string.format("%q", dir))
end

function M.runsNuppSuites()
   local output = run(ROOT .. "/tests/run.lua", "nupptest --json")
   test.matches(output, '"suite":"nupptest"')
   test.matches(output, '"name":"runsAsNupp"')
   test.matches(output, '"name":"requiresNuppProjectModules"')
end

return M
