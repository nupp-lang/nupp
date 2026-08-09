-- Every subset of the optimizer's passes has to agree on what a program does.
--
-- A pass is tested on its own, which is not the same as being tested. Two can
-- claim one node and the second one's rewrite can be dropped by the first one's
-- codegen branch, and each pass's own suite stays green because each pass, on
-- its own, is fine. That is not hypothetical: OPT-2 rewrites a generic `for`
-- into a numeric one through a different branch, and that branch did not emit
-- OPT-5's finish, so the accumulator came out empty. Fifty-four optimizer tests
-- passed with the bug in the tree.
--
-- The subsets come from `optimize.passes` rather than a list here, so a pass
-- added tomorrow is covered by this the day it lands.
--
-- Behaviour, not bytes: passes are supposed to change the output. What they may
-- not change is the answer. `nupp fixpoint` is the whole-program version of the
-- same idea, comparing the compiler built at -O0 against -O2; this is the
-- per-program one.
local parser = require("compiler.parser")
local optimize = require("compiler.optimize")
local gen = require("compiler.gen")
local check = require("fragment")
local envMod = require("compiler.env")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local env = envMod.new(HERE .. "/..")

-- Exhaustive while the subset count stays sane. Beyond that every pass alone and
-- every pair of passes, which is where interaction bugs live, plus all-on and
-- all-off. Announced rather than silent: a sweep that quietly stopped being
-- exhaustive would read like one that still was.
local EXHAUSTIVE_BUDGET = 256

local function assertEq(got, want, label)
   if got ~= want then
      error(("%s:\n  want: %s\n  got:  %s"):format(label or "mismatch",
         tostring(want), tostring(got)), 2)
   end
end

local function codes()
   local out = {}
   for code in pairs(optimize.passes) do out[#out + 1] = code end
   table.sort(out)
   return out
end

-- One build under one set of disabled passes, run for its value.
local function build(src, disabled)
   local result = parser.parse(src, "perm.g.nupp")
   assertEq(#result.errors, 0, "syntax errors in test source\n" .. src)
   local diags = check.check(result, "perm.g.nupp", env)
   for _, diag in ipairs(diags or {}) do
      if diag.severity == "error" then
         error(("%s: %s\n%s"):format(diag.code, diag.msg, src), 2)
      end
   end
   optimize.run(result, {level = 1, disabled = disabled})
   local code, genDiags = gen.generate(result, "perm")
   assertEq(#genDiags, 0, "gen diagnostics\n" .. src)
   local chunk, err = loadstring(code, "@perm")
   if not chunk then
      return nil, "does not load: " .. tostring(err), code
   end
   local ok, value = pcall(chunk)
   if not ok then
      return nil, "raised: " .. tostring(value), code
   end
   return value, nil, code
end

-- The subsets to try, each a set of ENABLED codes.
local function subsets(all)
   local out = {}
   if 2 ^ #all <= EXHAUSTIVE_BUDGET then
      for mask = 0, 2 ^ #all - 1 do
         local on = {}
         for i, code in ipairs(all) do
            if math.floor(mask / 2 ^ (i - 1)) % 2 == 1 then on[#on + 1] = code end
         end
         out[#out + 1] = on
      end
      return out, "exhaustive"
   end
   out[#out + 1] = {}
   out[#out + 1] = all
   for i = 1, #all do
      out[#out + 1] = {all[i]}
      for j = i + 1, #all do out[#out + 1] = {all[i], all[j]} end
   end
   return out, "singles and pairs"
end

local function disabledFrom(all, on)
   local enabled, disabled = {}, {}
   for _, code in ipairs(on) do enabled[code] = true end
   for _, code in ipairs(all) do
      if not enabled[code] then disabled[code] = true end
   end
   return disabled
end

-- Builds `src` under every subset and requires one answer from all of them.
local function agrees(src, label)
   local all = codes()
   local combos, mode = subsets(all)
   local baseline, err = build(src, disabledFrom(all, {}))
   if err then
      error(("%s: with every pass off, the program %s\n%s")
         :format(label, err, src), 2)
   end
   for _, on in ipairs(combos) do
      local value, failure, code = build(src, disabledFrom(all, on))
      local named = #on == 0 and "(none)" or table.concat(on, "+")
      if failure then
         error(("%s [%s, %s]: %s\n---\n%s"):format(label, mode, named, failure,
            code), 2)
      end
      if value ~= baseline then
         error(("%s [%s, %s]: answered %s, but with every pass off it "
            .. "answered %s\n---\n%s"):format(label, mode, named,
            tostring(value), tostring(baseline), code), 2)
      end
   end
   return #combos
end

local M = {}

-- Every pass at once on one program, including the two that claim one loop.
function M.allPassesOnOneProgram()
   local tried = agrees([[
const sep = "," .. ""
local xs: {integer} = {1, 2, 3}
local counts = {}
counts.a = 1
counts.b = 2
local out = ""
for _, v in ipairs(xs) do
    out = out .. v .. sep
end
local folded = (2 + 3) * 4
return out .. "|" .. folded .. "|" .. counts.a .. counts.b
]], "all passes")
   assert(tried >= 2 ^ 5, "the sweep tried " .. tried .. " subsets")
end

-- The shape that was actually broken: OPT-2 rewrites the loop OPT-5 accumulates
-- round, and emits it from a branch of its own.
function M.aNumericIpairsLoopCarryingAnAccumulator()
   agrees([[
local xs: {integer} = {10, 20, 30}
local out = ""
for _, v in ipairs(xs) do
    out = out .. v .. ";"
end
return out
]], "ipairs loop with an accumulator")
end

function M.anAccumulatorInEachLoopKind()
   agrees([[
local a = ""
for i = 1, 3 do a = a .. i end
local b = ""
local n = 0
while n < 3 do n = n + 1 b = b .. n end
local c = ""
local m = 0
repeat m = m + 1 c = c .. m until m >= 3
return a .. "|" .. b .. "|" .. c
]], "accumulators in for, while and repeat")
end

function M.nestedLoopsEachWithTheirOwnAccumulator()
   agrees([[
local outer = ""
for i = 1, 3 do
    local inner = ""
    for j = 1, 2 do
        inner = inner .. j
    end
    outer = outer .. inner .. ":"
end
return outer
]], "nested accumulators")
end

function M.presizingBesideAConstantFold()
   agrees([[
const size = 2 * 2
local t = {}
t.a = size
t.b = size + 1
t.c = "x" .. "y"
return t.a .. "|" .. t.b .. "|" .. t.c
]], "presize and fold")
end

function M.repeatedCallsThroughOneImmutablePath()
   agrees([[
const lib = {inner = {twice = function(n: integer): number return n * 2 end}}
local total = 0
total = total + lib.inner.twice(1)
total = total + lib.inner.twice(2)
total = total + lib.inner.twice(3)
return total
]], "static callable binding")
end

function M.anAccumulatorReadAfterItsLoop()
   agrees([[
local out = ""
for i = 1, 4 do
    out = out .. i
end
local trailing = out .. "!" .. #out
return trailing
]], "the accumulator is a string again afterwards")
end

function M.aLoopThatNeverRuns()
   agrees([[
local out = ""
for i = 1, 0 do
    out = out .. i
end
return "[" .. out .. "]"
]], "zero iterations")
end

function M.everyPassIsInTheSweep()
   -- The guarantee this file is for: the subsets come from the registry, so a
   -- pass that lands without being added anywhere is still covered.
   local all = codes()
   assert(#all > 0, "the registry named no passes")
   for _, code in ipairs(all) do
      assert(optimize.passes[code].name, code .. " has no name")
   end
   local combos, mode = subsets(all)
   if mode == "exhaustive" then
      assertEq(#combos, 2 ^ #all, "every subset of " .. #all .. " passes")
   else
      assert(#combos >= #all, "at least every pass alone")
   end
end

return M
