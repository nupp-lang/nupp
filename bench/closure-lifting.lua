-- What a closure inside a hot function costs, against the same code lifted out.
-- Run: luajit bench/closure-lifting.lua
--
-- The candidate: a `local function` declared inside another function is built on
-- every entry (`FNEW`) and its scope closed on every exit (`UCLO`). LuaJIT records
-- neither, so a trace that reaches one aborts, and the code runs interpreted
-- however hot it gets. Lifting it out and passing what it captured turns the
-- closure into an ordinary call to a constant.
--
-- Unlike bench/scratch-reuse.lua, the JIT cannot already be doing this: allocation
-- sinking removes allocations inside a trace, and here the problem is that there
-- is no trace. That is the whole difference between the two benchmarks, and the
-- reason one of them justifies a pass and the other retires one.
--
-- `analysis.queries(...).body(fn).calledOnly(definition)` is the question a pass
-- would ask: a nested function every mention of which is a direct call can be
-- lifted, and one handed somewhere as a value cannot.

local N = tonumber(os.getenv("N") or "3000000")
local DATA = {1, 2, 3, 4, 5, 6, 7, 8}

-- Built on every call, and never leaves.
local function withClosure(t, k)
   local function pick(x) return x + k end
   local total = 0
   for i = 1, #t do total = total + pick(t[i]) end
   return total
end

-- The same, lifted, with the captured value passed instead.
local function pick(x, k) return x + k end
local function lifted(t, k)
   local total = 0
   for i = 1, #t do total = total + pick(t[i], k) end
   return total
end

local aborts = 0
jit.attach(function(what) if what == "abort" then aborts = aborts + 1 end end, "trace")

local function measure(fn)
   fn(DATA, 1)
   local before = aborts
   local best = math.huge
   for _ = 1, 5 do
      local started = os.clock()
      local sink = 0
      for i = 1, N do sink = sink + fn(DATA, i) end
      local took = os.clock() - started
      if took < best then best = took end
      if sink == -1 then io.write("unreachable\n") end
   end
   return best, aborts - before
end

local closureTime, closureAborts = measure(withClosure)
local liftedTime, liftedAborts = measure(lifted)

io.write(("\n closure lifting, %d iterations, best of 5\n\n"):format(N))
io.write((" %-16s %10s %9s\n"):format("shape", "time", "aborts"))
io.write((" %s %s %s\n"):format(("─"):rep(16), ("─"):rep(10), ("─"):rep(9)))
io.write((" %-16s %9.4fs %9d\n"):format("closure inside", closureTime, closureAborts))
io.write((" %-16s %9.4fs %9d\n"):format("lifted out", liftedTime, liftedAborts))

io.write("\n")
if liftedTime < closureTime * 0.9 then
   io.write((" lifting is %.1fx faster here, and the abort column is why:\n"):format(
      closureTime / liftedTime))
   io.write(" the closure form never gets a trace to run on\n\n")
else
   io.write(" no material difference; the pass is not worth building on this shape\n\n")
end
