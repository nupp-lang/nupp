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
local NUPP = os.getenv("NUPP_TEST_BIN") or ROOT .. "/bin/nupp"

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

-- A copied runner loads compiled modules before it does anything, and it cannot
-- find them from a temporary directory. Naming the repository's build directory
-- is what lets the copy be the same program as the original.
local MODULES = ("NUPP_TEST_MODULES=%q "):format(ROOT .. "/build")

local function run(path, args)
   local quoted = "'" .. path:gsub("'", "'\\''") .. "'"
   local pipe = assert(io.popen((MODULES .. "luajit %s %s 2>&1"):format(quoted, args or "")))
   local output = pipe:read("*a")
   pipe:close()
   return output
end

-- The same, with standard error left where it was. Under `--json` the runner
-- puts its progress marks on standard error precisely so the document on
-- standard output stays a document; folding the two together turns it back into
-- something no decoder accepts.
local function runJson(path, args)
   local quoted = "'" .. path:gsub("'", "'\\''") .. "'"
   local pipe = assert(io.popen((MODULES .. "luajit %s %s 2>/dev/null"):format(quoted, args or "")))
   local output = pipe:read("*a")
   pipe:close()
   return output
end

local function runWorkerHost(args)
   local pipe = assert(io.popen(("cd %q && %q %s 2>&1")
      :format(ROOT, ROOT .. "/build/nupp-test", args)))
   local output = pipe:read("*a")
   pipe:close()
   return output
end

function M.bundledRunnerWorksOutsideTheCompilerCheckout()
   local dir = os.tmpname()
   os.remove(dir)
   assert(os.execute("mkdir -p " .. string.format("%q", dir .. "/tests")) == 0)
   for _, name in ipairs({"alpha", "beta"}) do
      write(("%s/tests/%stest.lua"):format(dir, name), ([=[
local test = require("nupp.test")
local M = {}
function M.passes() test.equal(%q, %q) end
return M
]=]):format(name, name))
   end

   local command = ("cd %q && NUPP_TEST_BUILD=%q %q test-runner "
      .. "--jobs=2 --json 2>/dev/null"):format(dir, dir .. "/build", NUPP)
   local pipe = assert(io.popen(command))
   local output = pipe:read("*a")
   local ok = pipe:close()
   assert(ok, "the bundled runner failed outside its checkout: " .. output)
   local report = require("testjson").decode(output)
   test.equal(report.total, 2, "both external suites ran")
   test.equal(report.passed, 2, "both external suites passed")
   test.equal(#report.shards, 2, "the external run used both requested workers")
   local timings = read(dir .. "/build/.nupp-test-times.json")
   test.matches(timings, '"alphatest"', "external timing history is persisted")
   test.matches(timings, '"betatest"', "every external suite is timed")
   os.execute("rm -rf " .. string.format("%q", dir))
end

function M.workerHostDogfoodsNuppWorkersForOrdinarySuites()
   local ordinary = runWorkerHost("lexertest --timings=0")
   test.matches(ordinary, "1 suites across 1 Nupp workers")
   test.matches(ordinary, "17 tests, 17 passed")
   test.equal(ordinary:find(".................", 1, true), nil,
      "parallel progress is one mark per suite slice, not one per case")

   local isolated = runWorkerHost("processnativetest --timings=0")
   test.equal(isolated:find("Nupp workers", 1, true), nil,
      "the native process suite stays off the mechanism it tests")
   test.matches(isolated, "11 tests, 11 passed")
end

function M.namingSeveralSuitesRunsEveryOneOfThem()
   -- Each name used to overwrite the one before it, so `nupp test a b` ran only `b`
   -- and reported a count that looked like an answer. Summed from the single runs
   -- rather than written down, so this keeps meaning what it says as suites grow.
   local first = runWorkerHost("lexertest --timings=0")
   local second = runWorkerHost("uritest --timings=0")
   local both = runWorkerHost("lexertest uritest --timings=0")
   local a = tonumber(first:match("(%d+) tests,"))
   local b = tonumber(second:match("(%d+) tests,"))
   local together = tonumber(both:match("(%d+) tests,"))
   test.assert(a and b and together, "each run reports a count")
   test.equal(together, a + b, "naming two suites runs both of them")
end

function M.aNameMatchingNoSuiteIsAFailure()
   -- Discovering nothing and reporting it green is the shape of this that hurts:
   -- a typo in a suite name reads exactly like a suite that passed.
   local out = runWorkerHost("nosuchsuitetest --timings=0")
   test.matches(out, "no tests were discovered")
end

function M.workerHostColorsOnlyWhenAskedDownAPipe()
   local colored = runWorkerHost("lexertest --timings=0 --color=always")
   test.assert(colored:find("\27[", 1, true),
      "--color=always paints runner output")

   local plain = runWorkerHost("lexertest --timings=0 --no-color")
   test.equal(plain:find("\27[", 1, true), nil,
      "--no-color keeps redirected runner output plain")
end

function M.embeddedWorkersDoNotPassTheirProgressDescriptorToNestedRunners()
   local dir = os.tmpname()
   os.remove(dir)
   assert(os.execute("mkdir -p " .. string.format("%q", dir)) == 0)
   write(dir .. "/run.lua", read(ROOT .. "/tests/run.lua"))
   write(dir .. "/assert.lua", read(ROOT .. "/tests/assert.lua"))
   write(dir .. "/innertest.lua", [[
local M = {}
function M.passes() end
return M
]])
   write(dir .. "/outertest.lua", ([=[
local M = {}
function M.capturesNestedProgress()
   local pipe = assert(io.popen("luajit " .. %q .. " innertest --jobs=1 --no-color 2>&1"))
   local output = pipe:read("*a")
   pipe:close()
   assert(output:find(".\n\n1 tests", 1, true),
      "nested progress escaped its capture: " .. output)
end
return M
]=]):format(dir .. "/run.lua"))
   write(dir .. "/host.lua", ([=[
rawset(_G, "__NUPP_TEST_PROGRESS_FD", 9)
arg = {[0] = %q, "outertest", "--jobs=1", "--no-color"}
dofile(arg[0])
]=]):format(dir .. "/run.lua"))

   local output = dir .. "/output"
   local progress = dir .. "/progress"
   local status = os.execute((
      MODULES .. "NUPP_TEST_PROGRESS_FD=9 luajit %q 9>%q >%q 2>&1"
   ):format(dir .. "/host.lua", progress, output))
   local result = read(output)
   test.assert(status == 0,
      "the outer runner failed after launching its nested runner: " .. result)
   test.matches(result, "1 tests, 1 passed, 0 skipped, 0 failed")
   os.execute("rm -rf " .. string.format("%q", dir))
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

-- Where the time went, which is the report a person asking why the suite takes
-- as long as it does is looking for. A suite costs more than its cases: this one
-- sleeps in `beforeAll`, so a report that only added the cases up would say the
-- suite was free.
function M.reportsWhereTheTimeWent()
   local dir = os.tmpname()
   os.remove(dir)
   assert(os.execute("mkdir -p " .. string.format("%q", dir)) == 0)
   write(dir .. "/run.lua", read(ROOT .. "/tests/run.lua"))
   write(dir .. "/assert.lua", read(ROOT .. "/tests/assert.lua"))
   write(dir .. "/slowtest.lua", [[
local M = {}
local function spin(seconds)
   local until_ = os.clock() + seconds
   while os.clock() < until_ do end
end
function M.beforeAll() spin(0.05) end
function M.quick() end
function M.slow() spin(0.05) end
return M
]])

   local output = run(dir .. "/run.lua", "--jobs=1")
   test.matches(output, "slowest suites")
   test.matches(output, "slowest tests")
   test.matches(output, "slowtest%s+%d+ms")
   test.matches(output, "slowtest / slow")

   -- The same run as data, where the suite's own cost is separable from its
   -- cases' rather than only rendered.
   local json = require("testjson")
   local decoded = json.decode(runJson(dir .. "/run.lua", "--jobs=1 --json"))
   test.equal(#decoded.suites, 1, "one suite record")
   local record = decoded.suites[1]
   test.equal(record.suite, "slowtest")
   test.equal(record.tests, 2)
   test.equal(record.slowestCase, "slow")
   test.assert(record.hooksMs >= 25, "beforeAll is measured with the suite")
   test.assert(record.durationMs >= record.casesMs + record.hooksMs - 1,
      "the suite is at least what its cases and hooks cost")

   -- Asked for none, and the report is gone; the run still measured it.
   local quiet = run(dir .. "/run.lua", "--jobs=1 --timings=0")
   test.equal(quiet:find("slowest suites", 1, true), nil,
      "--timings=0 asks for no report")
   os.execute("rm -rf " .. string.format("%q", dir))
end

-- Slices are packed by what a case last cost, not by where it sits in the list.
-- One heavy case among cheap ones belongs on its own: the alternative is a slice
-- that carries it plus a share of the rest, which is the run's floor plus extra.
function M.slicesASuiteByWhatItsCasesCost()
   local dir = os.tmpname()
   os.remove(dir)
   assert(os.execute("mkdir -p " .. string.format("%q", dir .. "/tests")) == 0)
   assert(os.execute("mkdir -p " .. string.format("%q", dir .. "/build")) == 0)
   write(dir .. "/tests/run.lua", read(ROOT .. "/tests/run.lua"))
   write(dir .. "/tests/assert.lua", read(ROOT .. "/tests/assert.lua"))
   write(dir .. "/tests/slicedtest.lua", [[
local M = {}
function M.heavy() end
function M.alpha() end
function M.beta() end
function M.gamma() end
return M
]])
   write(dir .. "/build/.nupp-test-times.json", [[
{"suites":{"slicedtest":1030},
 "cases":{"slicedtest":{"heavy":1000,"alpha":10,"beta":10,"gamma":10}}}
]])

   local json = require("testjson")
   local first = json.decode(runJson(dir .. "/tests/run.lua",
      "--json --shard=slicedtest#0/2"))
   local second = json.decode(runJson(dir .. "/tests/run.lua",
      "--json --shard=slicedtest#1/2"))
   test.equal(#first.tests, 1, "the heavy case is a slice on its own")
   test.equal(first.tests[1].name, "heavy")
   test.equal(#second.tests, 3, "the cheap cases share the other slice")
   os.execute("rm -rf " .. string.format("%q", dir))
end

-- Who runs what is decided while the run is happening. Two workers pointed at one
-- queue divide it between them and neither runs a piece twice, which is what makes
-- an estimate that was wrong cost the difference rather than the whole imbalance.
function M.workersDivideAQueueBetweenThem()
   local dir = os.tmpname()
   os.remove(dir)
   assert(os.execute("mkdir -p " .. string.format("%q", dir .. "/tests")) == 0)
   assert(os.execute("mkdir -p " .. string.format("%q", dir .. "/queue")) == 0)
   write(dir .. "/tests/run.lua", read(ROOT .. "/tests/run.lua"))
   write(dir .. "/tests/assert.lua", read(ROOT .. "/tests/assert.lua"))
   for _, name in ipairs({"alpha", "beta", "gamma", "delta"}) do
      write(("%s/tests/%stest.lua"):format(dir, name),
         ("local M = {}\nfunction M.only%s() end\nreturn M\n"):format(name))
   end
   local order = {"alphatest", "betatest", "gammatest", "deltatest"}
   write(dir .. "/queue/order", table.concat(order, "\n") .. "\n")
   for index, spec in ipairs(order) do
      write(("%s/queue/piece-%d"):format(dir, index), spec .. "\n")
   end

   local json = require("testjson")
   local seen, ran = {}, 0
   for _ = 1, 2 do
      local report = json.decode(runJson(dir .. "/tests/run.lua",
         "--json --queue=" .. dir .. "/queue"))
      for _, spec in ipairs(report.claimed or {}) do
         test.equal(seen[spec], nil, spec .. " was claimed twice")
         seen[spec] = true
      end
      ran = ran + report.total
   end
   test.equal(ran, 4, "every piece ran exactly once")
   for _, spec in ipairs(order) do
      assert(seen[spec], spec .. " was never claimed")
   end
   os.execute("rm -rf " .. string.format("%q", dir))
end

function M.embeddedWorkersDiscoverFromTheParentCatalogWithoutPopen()
   local dir = os.tmpname()
   os.remove(dir)
   assert(os.execute("mkdir -p " .. string.format("%q", dir .. "/queue")) == 0)
   write(dir .. "/run.lua", read(ROOT .. "/tests/run.lua"))
   write(dir .. "/assert.lua", read(ROOT .. "/tests/assert.lua"))
   write(dir .. "/catalogtest.lua", [[
local M = {}
function M.passes() end
return M
]])
   write(dir .. "/queue/order", "catalogtest\n")
   write(dir .. "/queue/piece-1", "catalogtest\n")
   write(dir .. "/host.lua", ([=[
rawset(_G, "__NUPP_TEST_EMBEDDED", true)
rawset(_G, "__NUPP_TEST_SUITE_CATALOG", "catalogtest.lua")
io.popen = function() error("worker discovery called popen", 0) end
arg = {[0] = %q, "--json", "--queue=" .. %q, "--no-color"}
local report = dofile(arg[0])
io.write(report.total, "\n", report.tests[1].name, "\n")
]=]):format(dir .. "/run.lua", dir .. "/queue"))

   local output = run(dir .. "/host.lua")
   test.equal(output, ".\n1\npasses\n", "the catalogued suite ran")
   os.execute("rm -rf " .. string.format("%q", dir))
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
