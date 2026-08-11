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

   -- This case is about captured output, not the runner's own worker fan-out.
   -- Keep its copied runner in one process so the Windows test does not nest a
   -- second MSYS/native subprocess boundary inside the matrix's serial run.
   local plain = run(dir .. "/run.lua", "--jobs=1")
   test.equal(plain:find("ordinary output", 1, true), nil,
      "passing stdout stays hidden")
   test.equal(plain:find("diagnostic output", 1, true), nil,
      "passing stderr stays hidden")
   test.matches(plain, "Output from failuretest / writesBeforeFailing")
   test.matches(plain, "failing stdout")
   test.matches(plain, "failing stderr")

   local verbose = run(dir .. "/run.lua", "--jobs=1 --verbose")
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

function M.runsLifecycleHooksInOrder()
   local dir = os.tmpname()
   os.remove(dir)
   assert(os.execute("mkdir -p " .. string.format("%q", dir)) == 0)
   local trace = dir .. "/trace"
   write(dir .. "/run.lua", read(ROOT .. "/tests/run.lua"))
   write(dir .. "/assert.lua", read(ROOT .. "/tests/assert.lua"))
   write(dir .. "/lifecycletest.lua", ([[
local M = {}
local trace = %q
local function mark(name)
   local f = assert(io.open(trace, "ab"))
   f:write(name, "\n")
   f:close()
end
function M.beforeAll() mark("beforeAll") end
function M.beforeEach() mark("beforeEach") end
function M.alpha() mark("alpha") end
function M.beta() mark("beta") end
function M.afterEach() mark("afterEach") end
function M.afterAll() mark("afterAll") end
return M
]]):format(trace))

   local output = run(dir .. "/run.lua", "lifecycletest")
   test.matches(output, "2 tests, 2 passed, 0 skipped, 0 failed")
   test.equal(read(trace), table.concat({
      "beforeAll", "beforeEach", "alpha", "afterEach", "beforeEach", "beta",
      "afterEach", "afterAll", "",
   }, "\n"))
   os.execute("rm -rf " .. string.format("%q", dir))
end

function M.runsTeardownAfterFailures()
   local dir = os.tmpname()
   os.remove(dir)
   assert(os.execute("mkdir -p " .. string.format("%q", dir)) == 0)
   local trace = dir .. "/trace"
   write(dir .. "/run.lua", read(ROOT .. "/tests/run.lua"))
   write(dir .. "/assert.lua", read(ROOT .. "/tests/assert.lua"))
   write(dir .. "/cleanupfailtest.lua", ([[
local M = {}
local trace = %q
local function mark(name)
   local f = assert(io.open(trace, "ab"))
   f:write(name, "\n")
   f:close()
end
function M.beforeAll() mark("beforeAll") end
function M.beforeEach() mark("beforeEach") end
function M.fails() mark("test"); error("case failure") end
function M.afterEach() mark("afterEach"); error("cleanup failure") end
function M.afterAll() mark("afterAll") end
return M
]]):format(trace))

   local output = run(dir .. "/run.lua", "cleanupfailtest")
   test.matches(output, "case failure")
   test.matches(output, "afterEach failed: .-cleanup failure")
   test.equal(read(trace), "beforeAll\nbeforeEach\ntest\nafterEach\nafterAll\n")
   os.execute("rm -rf " .. string.format("%q", dir))
end

function M.runsTeardownAfterFailedSetup()
   local dir = os.tmpname()
   os.remove(dir)
   assert(os.execute("mkdir -p " .. string.format("%q", dir)) == 0)
   local trace = dir .. "/trace"
   write(dir .. "/run.lua", read(ROOT .. "/tests/run.lua"))
   write(dir .. "/assert.lua", read(ROOT .. "/tests/assert.lua"))
   write(dir .. "/setupcasefailtest.lua", ([[
local M = {}
local trace = %q
local function mark(name)
   local f = assert(io.open(trace, "ab"))
   f:write(name, "\n")
   f:close()
end
function M.beforeEach() mark("beforeEach"); error("case setup failure") end
function M.shouldNotRun() mark("test") end
function M.afterEach() mark("afterEach") end
function M.afterAll() mark("afterAll") end
return M
]]):format(trace))

   local output = run(dir .. "/run.lua", "setupcasefailtest")
   test.matches(output, "case setup failure")
   test.equal(read(trace), "beforeEach\nafterEach\nafterAll\n")
   os.execute("rm -rf " .. string.format("%q", dir))
end

function M.runsSuiteTeardownWhenSetupFails()
   local dir = os.tmpname()
   os.remove(dir)
   assert(os.execute("mkdir -p " .. string.format("%q", dir)) == 0)
   local trace = dir .. "/trace"
   write(dir .. "/run.lua", read(ROOT .. "/tests/run.lua"))
   write(dir .. "/assert.lua", read(ROOT .. "/tests/assert.lua"))
   write(dir .. "/setupfailtest.lua", ([[
local M = {}
local trace = %q
local function mark(name)
   local f = assert(io.open(trace, "ab"))
   f:write(name, "\n")
   f:close()
end
function M.beforeAll() mark("beforeAll"); error("setup failure") end
function M.shouldNotRun() mark("test") end
function M.afterAll() mark("afterAll") end
return M
]]):format(trace))

   local output = run(dir .. "/run.lua", "setupfailtest")
   test.matches(output, "setup failure")
   test.matches(output, "beforeAll")
   test.equal(read(trace), "beforeAll\nafterAll\n")
   os.execute("rm -rf " .. string.format("%q", dir))
end

return M
