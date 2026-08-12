-- Why the closure lowering costs what bench/match-lowering.lua measures.
-- Run: luajit bench/match-lowering-probe.lua
--      luajit -jv bench/match-lowering-probe.lua   (to see trace behaviour)
--
-- Two questions the timing cannot answer on a shared machine, because neither answer
-- depends on how fast the machine is running:
--
--   1. What is the 96 bytes? A closure, or a closure and an upvalue box?
--   2. Does the closure keep the loop from tracing, or does it trace and allocate anyway?

local N = 200000

local function bytesPerOp(fn)
   fn(1000)
   collectgarbage("collect")
   collectgarbage("stop")
   local before = collectgarbage("count")
   local kept = fn(N)
   local after = collectgarbage("count")
   collectgarbage("restart")
   return (after - before) * 1024 / N, kept
end

-- 1. What the 96 bytes is made of.

-- Captures nothing: the arms read a global-ish table passed in, so no upvalue is needed.
local function noUpvalue(n)
   local total = 0
   for i = 1, n do
      total = total + (function() return 1 end)()
   end
   return total
end

-- Captures one loop local, which is the shape a match expression over a scrutinee has.
local function oneUpvalue(n)
   local total = 0
   for i = 1, n do
      local s = i
      total = total + (function() return s end)()
   end
   return total
end

-- Captures two, to see whether the cost scales per capture or per closure.
local function twoUpvalues(n)
   local total = 0
   for i = 1, n do
      local s, t = i, i + 1
      total = total + (function() return s + t end)()
   end
   return total
end

-- The goto lowering of the same thing.
local function gotoForm(n)
   local total = 0
   for i = 1, n do
      local s = i
      local r
      do
         r = s
         goto d
         ::d::
      end
      total = total + r
   end
   return total
end

print(jit.version)
print("\nWhat a closure costs per evaluation:\n")
print(" Shape                    bytes/op")
print(" ───────────────────────  ────────")
for _, case in ipairs({
   {"closure, 0 upvalues", noUpvalue},
   {"closure, 1 upvalue", oneUpvalue},
   {"closure, 2 upvalues", twoUpvalues},
   {"goto, no closure", gotoForm},
}) do
   local bytes = bytesPerOp(case[2])
   print((" %-23s  %8.2f"):format(case[1], bytes))
end

-- 2. Whether the closure loop traces at all. Under -jv a loop that compiles prints one
-- TRACE line and then stops printing; one that aborts prints an abort reason and, once
-- it has aborted enough times, is blacklisted and never retried.
print("\nRun again under -jv to see whether each loop compiles or aborts.")
print("Recording now:\n")
noUpvalue(N)
oneUpvalue(N)
twoUpvalues(N)
gotoForm(N)
