-- The nupp.bench surface, in three parts that fail independently.
--
-- The intrinsic: `keep` in statement position on a receiver statically known to be the
-- module nupp.bench returns is generated as a store against the module's own sink field
-- rather than called. A call there is exactly the cost the sink exists to avoid, so a
-- version of this that quietly went back to calling would measure the call.
--
-- The allocation account: what optimize.allocationSites reports is the compiler's
-- account of its own output, so a constructor a pass removed has to be absent from it.
-- This is the counter a record gates on; a wrong answer here is a false regression on
-- every case at once.
--
-- The comparison rules: which differences are gated, and which merely annotate. The two
-- that matter are that an optimization level keys a baseline -- `-O0` and `-O1` were
-- never comparable -- and that a compiler digest never does, because a compiler change
-- moving a counter is the regression this is for rather than a reason to stop looking.
local parser = require("nupp.compiler.parser")
local gen = require("nupp.compiler.gen")
local optimize = require("nupp.compiler.optimize")
local check = require("fragment")
local envMod = require("nupp.compiler.env")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local env = envMod.new(HERE .. "/..")

local function assertEq(got, want, label)
   if got ~= want then
      error(("%s:\n  want: %s\n  got:  %s"):format(label or "mismatch",
         tostring(want), tostring(got)), 2)
   end
end

local function assertTrue(cond, label)
   if not cond then error(label or "expected true", 2) end
end

local function compile(source, level)
   local parsed = parser.parse(source, "bench_test.g.nupp")
   assertEq(#parsed.errors, 0, "syntax errors")
   check.check(parsed, "bench_test.g.nupp", env)
   if level then
      optimize.run(parsed, {level = level, filename = "bench_test.g.nupp"})
   end
   local code = gen.generate(parsed, "bench_test")
   return code, parsed
end

local M = {}

function M.lowersKeepToAStoreRatherThanACall()
   local code = compile([[
local bench = require("nupp.bench")
local function body()
    bench.keep({1, 2})
end
]])
   assertTrue(code:find("__nuppSink", 1, true) ~= nil,
      "keep lowers against the module's sink field\n" .. code)
   -- The store is what makes the value escape its trace, so a surviving call would mean
   -- the sink is paying for a call as well as the store it needs.
   assertTrue(code:gmatch("bench%s*%.%s*keep%s*%(")() == nil,
      "no keep call survives\n" .. code)
end

function M.leavesAnOrdinaryKeepCallAlone()
   -- Not statement position: the result is bound, so there is nowhere to put a store and
   -- the ordinary call is the only correct lowering.
   local code = compile([[
local bench = require("nupp.bench")
local function body()
    local kept = bench.keep({1, 2})
    return kept
end
]])
   assertTrue(code:gmatch("keep%s*%(")() ~= nil,
      "a captured keep stays a call\n" .. code)
end

function M.leavesKeepOnAnUnrelatedReceiverAlone()
   local code = compile([[
local other = {keep = function(value) return value end}
local function body()
    other.keep(1)
end
]])
   assertTrue(code:find("__nuppSink", 1, true) == nil,
      "a receiver that is not the module is not the intrinsic\n" .. code)
end

function M.countsTheAllocationsTheTreeStillCarries()
   local _, parsed = compile([[
local function body()
    local point = {}
    local other = {1, 2}
    return point, other
end
]], 1)
   local sites = optimize.allocationSites(parsed)
   assertEq(#sites, 2, "two constructors stand in the emitted tree")
   for _, site in ipairs(sites) do
      assertEq(site.kind, "table", "both are table constructors")
      assertTrue(site.line > 0, "a site carries where it stands")
   end
end

function M.countsAClosureAsAnAllocation()
   local _, parsed = compile([[
local function body()
    return function() return 1 end
end
]], 1)
   local sites = optimize.allocationSites(parsed)
   local closures = 0
   for _, site in ipairs(sites) do
      if site.kind == "closure" then closures = closures + 1 end
   end
   assertTrue(closures >= 1, "a function value is an allocation")
end

function M.omitsAnAllocationAConstantFoldRemoved()
   -- The account is of the tree generation will emit, so a branch OPT-3 proved dead
   -- takes its constructor with it. Gating on a site the optimizer already removed would
   -- report a regression that does not exist.
   local _, parsed = compile([[
local function body()
    if false then
        local gone = {1, 2, 3}
        return gone
    end
    return nil
end
]], 1)
   local sites = optimize.allocationSites(parsed)
   assertEq(#sites, 0, "a folded-away constructor is not accounted for")
end

return M
