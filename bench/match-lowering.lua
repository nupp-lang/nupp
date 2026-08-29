-- Whether a `match` expression is worth lowering through goto rather than a closure.
-- Run: luajit bench/match-lowering.lua
--
-- Nupp has no `match` yet. Dispatch over a tagged union is written as the if/elseif
-- chain in `nupp reference language`, which is a statement: it cannot appear where
-- a value is wanted. The obvious sugar is a match expression. Its obvious
-- desugaring, when the arms are statements, is an immediately-called closure:
--
--     total = total + (function() if s.kind == "circle" then return ... end ... end)()
--
-- The alternative is to hoist a temporary, emit the arms as statements, and jump to a
-- label shared by every arm:
--
--     local r do if s.kind == "circle" then r = ... goto d end ... ::d:: end
--     total = total + r
--
-- The question this has to settle first is whether LuaJIT already does it. Allocation
-- sinking removes an allocation that does not escape its trace, and a closure that is
-- called on the spot and dropped is exactly that shape -- so the goto lowering may be
-- buying back something the trace compiler already declined to spend. That is the same
-- question bench/scratch-reuse.lua and bench/ffi-hoisting.lua asked, and both times the
-- answer was that LuaJIT had it covered.
--
-- Four lowerings are generated from one description of the arms, so the only thing that
-- differs between them is the lowering:
--
--   closure        the naive expression desugaring: an IIFE capturing the scrutinee
--   goto           the same tests, but a hoisted temporary and a jump to one label
--   goto-hoisted   as goto, and the discriminant field is read once, not once per test
--   ifelse         the statement form a person writes today; the ceiling, not a rival,
--                  since it cannot be used where a value is wanted
--
-- Three axes decide whether any of it matters:
--
--   arms       4 and 16, because a chain is linear and a guard is not
--   stream     biased (one tag 95% of the time) and uniform, because a trace records
--              the arm it saw and a uniform stream denies it one to specialise on
--   jit        on and off, because in a trace the untaken arms do not exist at all
--
-- The guarded spec is the case the closure cannot lower well: two arms sharing a tag
-- and separated by a guard mean a flat desugaring tests the tag twice, where a lowering
-- free to jump tests it once and falls through to the second arm on guard failure.

-- Timing needs a quiet machine; allocation does not. NUPP_BENCH_MODE=alloc reports only
-- the byte counts and the agreement check, which a loaded machine cannot distort.
local MODE = os.getenv("NUPP_BENCH_MODE") or "full"
local ROUNDS = tonumber(os.getenv("NUPP_BENCH_ROUNDS")) or 7
local N = tonumber(os.getenv("NUPP_BENCH_N")) or 300000
local BIAS = 0.95

local sink = 0

----------------------------------------------------------------------------------------
-- The prototype: one description of the arms, four lowerings.
----------------------------------------------------------------------------------------

-- An arm is {tag = <string>, guard = <expr or nil>, body = <expr>}. Arms are tried in
-- order and the first whose tag matches and whose guard holds supplies the value.

-- Arms sharing a tag are grouped so the tag is tested once for the run of them. This is
-- what a guard costs a flat lowering and what a lowering with a jump can decline to pay.
local function groupByTag(arms)
   local groups, byTag = {}, {}
   for _, arm in ipairs(arms) do
      local group = byTag[arm.tag]
      if not group then
         group = {tag = arm.tag}
         byTag[arm.tag] = group
         groups[#groups + 1] = group
      end
      group[#group + 1] = arm
   end
   return groups
end

-- The naive expression desugaring. Every arm is its own test, so a tag shared by two
-- arms is compared twice, and the closure captures the scrutinee as an upvalue.
local function lowerClosure(arms)
   local out = {"(function()"}
   for _, arm in ipairs(arms) do
      local test = ("s.kind == %q"):format(arm.tag)
      if arm.guard then test = test .. " and (" .. arm.guard .. ")" end
      out[#out + 1] = ("      if %s then return %s end"):format(test, arm.body)
   end
   out[#out + 1] = "      return 0"
   out[#out + 1] = "   end)()"
   return nil, table.concat(out, "\n")
end

-- The goto lowering. The result is a temporary declared before the dispatch, every arm
-- assigns it and jumps to the one label at the end, and arms sharing a tag sit inside a
-- single test with the guard falling through to the next of them.
local function lowerGoto(arms, hoistDiscriminant)
   local out = {"local r"}
   if hoistDiscriminant then out[#out + 1] = "      local k = s.kind" end
   local k = hoistDiscriminant and "k" or "s.kind"
   out[#out + 1] = "      do"
   for _, group in ipairs(groupByTag(arms)) do
      out[#out + 1] = ("         if %s == %q then"):format(k, group.tag)
      for _, arm in ipairs(group) do
         if arm.guard then
            out[#out + 1] = ("            if %s then r = %s goto d end"):format(arm.guard, arm.body)
         else
            out[#out + 1] = ("            r = %s goto d"):format(arm.body)
         end
      end
      out[#out + 1] = "         end"
   end
   out[#out + 1] = "         r = 0"
   out[#out + 1] = "         ::d::"
   out[#out + 1] = "      end"
   return table.concat(out, "\n"), "r"
end

-- The statement form written by hand today. Flat, like the closure, because elseif has
-- no way to share a test between two arms either.
local function lowerIfElse(arms)
   local out = {}
   for index, arm in ipairs(arms) do
      local test = ("s.kind == %q"):format(arm.tag)
      if arm.guard then test = test .. " and (" .. arm.guard .. ")" end
      out[#out + 1] = ("      %s %s then r = %s"):format(index == 1 and "local r if" or "elseif", test, arm.body)
   end
   out[#out + 1] = "      else r = 0 end"
   return table.concat(out, "\n"), "r"
end

local LOWERINGS = {
   {name = "closure", emit = lowerClosure},
   {name = "goto", emit = function(arms) return lowerGoto(arms, false) end},
   {name = "goto-hoisted", emit = function(arms) return lowerGoto(arms, true) end},
   {name = "ifelse", emit = lowerIfElse},
}

-- The match site is put in expression position, inside a loop, so a lowering that has to
-- allocate has to allocate once per iteration and one that does not, does not.
local function compile(arms, emit)
   local prelude, result = emit(arms)
   local source = ([[
return function(vs, n)
   local total = 0
   for i = 1, n do
      local s = vs[i]
      %s
      total = total + %s
   end
   return total
end
]]):format(prelude or "", result)
   local chunk = assert(loadstring(source), "generated source did not compile")
   return chunk(), source
end

----------------------------------------------------------------------------------------
-- The programs being dispatched over.
----------------------------------------------------------------------------------------

local function numberedTags(count)
   local tags = {}
   for index = 1, count do tags[index] = ("k%02d"):format(index) end
   return tags
end

local SPECS = {}

SPECS[#SPECS + 1] = {
   name = "4 arms",
   tags = {"circle", "square", "rect", "tri"},
   arms = {
      {tag = "circle", body = "3.14159 * s.a * s.a"},
      {tag = "square", body = "s.a * s.a"},
      {tag = "rect", body = "s.a * s.b"},
      {tag = "tri", body = "0.5 * s.a * s.b"},
   },
}

do
   local tags = numberedTags(16)
   local arms = {}
   for index, tag in ipairs(tags) do
      arms[index] = {tag = tag, body = ("s.a * %d + s.b"):format(index)}
   end
   SPECS[#SPECS + 1] = {name = "16 arms", tags = tags, arms = arms}
end

SPECS[#SPECS + 1] = {
   name = "4 arms, guards",
   tags = {"circle", "square", "rect", "tri"},
   arms = {
      {tag = "circle", guard = "s.a > 0.5", body = "s.a * 2"},
      {tag = "circle", body = "s.a"},
      {tag = "square", guard = "s.a > 0.5", body = "s.a * 3"},
      {tag = "square", body = "s.b"},
      {tag = "rect", body = "s.a + s.b"},
      {tag = "tri", body = "s.b * 0.5"},
   },
}

-- A deterministic stream, so every lowering sees the same tags in the same order and a
-- rerun answers the same. `biased` gives a trace one arm to specialise on; `uniform`
-- denies it one, which is the case a chain is supposed to lose.
local function stream(tags, count, biased)
   local seed = 0x2545F491
   local values = {}
   for index = 1, count do
      seed = (seed * 1103515245 + 12345) % 2147483648
      local pick
      if biased then
         pick = (seed / 2147483648) < BIAS and 1 or (seed % #tags) + 1
      else
         pick = (seed % #tags) + 1
      end
      values[index] = {kind = tags[pick], a = (seed % 1000) / 1000, b = (seed % 97) / 10}
   end
   return values
end

----------------------------------------------------------------------------------------
-- Measurement. Rounds are the outer loop so the lowerings interleave rather than each
-- taking a turn at whatever the machine was doing at the time.
----------------------------------------------------------------------------------------

local function median(times)
   table.sort(times)
   return times[math.ceil(#times / 2)]
end

-- Bytes allocated with the collector stopped, which counts what was created rather than
-- what survived. A closure the trace compiler failed to sink shows up here and nowhere
-- else.
local function allocated(fn, values)
   fn(values, 1000)
   collectgarbage("collect")
   collectgarbage("stop")
   local before = collectgarbage("count")
   sink = sink + fn(values, N)
   local after = collectgarbage("count")
   collectgarbage("restart")
   return (after - before) * 1024 / N
end

local function measure(variants, values)
   local results = {}
   for index = 1, #variants do
      variants[index].fn(values, 1000)
      results[index] = {bytes = allocated(variants[index].fn, values)}
   end
   if MODE == "alloc" then return results end

   local times = {}
   for index = 1, #variants do times[index] = {} end
   collectgarbage("collect")
   for _ = 1, ROUNDS do
      for index = 1, #variants do
         collectgarbage("collect")
         local started = os.clock()
         sink = sink + variants[index].fn(values, N)
         times[index][#times[index] + 1] = os.clock() - started
      end
   end
   -- The spread between the fastest and the median round. A benchmark sharing the
   -- machine says so here rather than in a footnote, and a wide spread means the ratios
   -- below are not worth reading.
   for index = 1, #variants do
      local sorted = times[index]
      table.sort(sorted)
      local mid = median(sorted)
      results[index].nanoseconds = mid / N * 1e9
      results[index].spread = (mid - sorted[1]) / sorted[1] * 100
   end
   return results
end

----------------------------------------------------------------------------------------

local function run(jitOn)
   if jitOn then jit.on() else jit.off() end
   jit.flush()
   print(("\n== JIT %s ==\n"):format(jitOn and "on" or "off"))

   for _, spec in ipairs(SPECS) do
      for _, biased in ipairs({true, false}) do
         local values = stream(spec.tags, N, biased)

         local variants, expected = {}, nil
         for _, lowering in ipairs(LOWERINGS) do
            local fn = compile(spec.arms, lowering.emit)
            local answer = fn(values, N)
            if expected == nil then
               expected = answer
            elseif math.abs(answer - expected) > 1e-6 then
               error(("%s disagrees on %s: %s vs %s"):format(lowering.name, spec.name, answer, expected))
            end
            variants[#variants + 1] = {name = lowering.name, fn = fn}
         end

         local results = measure(variants, values)

         print((" %s, %s stream"):format(spec.name, biased and "biased" or "uniform"))
         if MODE == "alloc" then
            print(" Lowering       bytes/op")
            print(" ─────────────  ────────")
            for index, variant in ipairs(variants) do
               print((" %-13s  %8.2f"):format(variant.name, results[index].bytes))
            end
         else
            local baseline = results[1].nanoseconds
            print(" Lowering        ns/op  bytes/op  vs closure  spread")
            print(" ─────────────  ──────  ────────  ──────────  ──────")
            for index, variant in ipairs(variants) do
               print((" %-13s  %6.2f  %8.2f  %9.2fx  %5.1f%%"):format(
                  variant.name, results[index].nanoseconds,
                  results[index].bytes, baseline / results[index].nanoseconds,
                  results[index].spread))
            end
         end
         print("")
      end
   end
end

print(("%s  N=%d  rounds=%d"):format(jit.version, N, ROUNDS))

-- One generated body, printed so what was measured can be read rather than trusted.
do
   local _, source = compile(SPECS[3].arms, lowerGoto)
   print("\ngoto lowering of the guarded spec:\n")
   print(source)
end

run(true)
run(false)

if sink == math.huge then print("unreachable") end
