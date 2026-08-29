-- Ownership lowering benchmark: measures the runtime cost of the cleanup
-- regions automatic lexical destruction emits. Run: luajit bench/ownership.lua
--
-- The arms are hand-written compiler OUTPUT, the same approach reification.lua
-- takes. Nothing here needs an unimplemented feature:
--
--   ffi.gc          what a LuaJIT programmer writes today
--   drop         what an owned result + drop lowers to (a direct free call)
--   region (upvalue) naive lowering: fresh closure, owner in an upvalue
--   region (args)    cleanup lowering using xpcall's extra arguments and a
--                   per-execution slot table instead of a closure
--
-- Granularity matters more than any single number: total body work is held
-- constant while the work covered by one resource grows, so a cost that lives
-- only at the scope boundary amortizes down the table and a cost that slows
-- the body does not.
--
-- RESULT (LuaJIT 2.1, arm64): the xpcall boundary is ~free. What is not free
-- is a protected region that CAPTURES UPVALUES -- `NYI: bytecode FNEW` makes
-- the enclosing loop uncompilable, costing ~5x at every granularity. A region
-- that captures nothing and takes its state through xpcall's extra arguments
-- amortizes to 1.0x. See bench notes at the bottom.

local ffi = require("ffi")

ffi.cdef [[
void *malloc(size_t size);
void free(void *ptr);
]]

local C = ffi.C
local u8 = ffi.typeof("uint8_t *")

local SIZE = 128         -- bytes per allocation
local ROUNDS = 5

---------------------------------------------------------------------------
-- Body work. Identical in every arm so only the resource discipline differs.
---------------------------------------------------------------------------

local function body(p, i)
   local b = ffi.cast(u8, p)
   b[0] = i % 251
   return b[0]
end

---------------------------------------------------------------------------
-- Arms
---------------------------------------------------------------------------

local function armGc(n, work)
   local sum = 0
   for i = 1, n do
      local p = ffi.gc(C.malloc(SIZE), C.free)
      for w = 1, work do sum = sum + body(p, i + w) end
      -- no explicit release: the finalizer runs whenever the GC gets to it
   end
   return sum
end

local function armDrop(n, work)
   local sum = 0
   for i = 1, n do
      local p = C.malloc(SIZE)
      for w = 1, work do sum = sum + body(p, i + w) end
      C.free(p)
   end
   return sum
end

-- Naive cleanup lowering: the protected region is a fresh closure per
-- execution and the hidden owner slot is one of its upvalues.
local function armCleanupUpvalue(n, work)
   local sum = 0
   for i = 1, n do
      local slot = nil
      local ok, err = xpcall(function()
         slot = C.malloc(SIZE)
         for w = 1, work do sum = sum + body(slot, i + w) end
      end, tostring)
      if slot ~= nil then C.free(slot) end
      if not ok then error(err, 0) end
   end
   return sum
end

-- Cleanup lowering that hoists the region and passes state through xpcall's
-- extra arguments. The hidden owner still needs to survive an error, so it
-- lives in a per-execution slot table rather than an upvalue.
local function region(slot, i, work)
   slot[1] = C.malloc(SIZE)
   local sum = 0
   for w = 1, work do sum = sum + body(slot[1], i + w) end
   return sum
end

local function armCleanupArgs(n, work)
   local sum = 0
   for i = 1, n do
      local slot = {}
      local ok, got = xpcall(region, tostring, slot, i, work)
      if slot[1] ~= nil then C.free(slot[1]) end
      if not ok then error(got, 0) end
      sum = sum + got
   end
   return sum
end

---------------------------------------------------------------------------
-- Harness
---------------------------------------------------------------------------

local function measure(fn, n, work)
   fn(n, work)                          -- warmup: let traces compile
   collectgarbage("collect")
   collectgarbage("collect")
   local loop, drain = {}, {}
   for r = 1, ROUNDS do
      local t0 = os.clock()
      fn(n, work)
      loop[r] = os.clock() - t0
      local t1 = os.clock()
      collectgarbage("collect")         -- pay any deferred finalizer cost
      collectgarbage("collect")
      drain[r] = os.clock() - t1
   end
   table.sort(loop)
   table.sort(drain)
   local mid = math.ceil(ROUNDS / 2)
   return loop[mid], drain[mid]
end

-- Probe: a fresh closure whose body mutates an enclosing local, but with NO
-- protected region. Separates the cost of the closure and its upvalues from
-- the cost of the xpcall boundary itself.
local function armClosureOnly(n, work)
   local sum = 0
   for i = 1, n do
      local slot = nil
      local fn = function()
         slot = C.malloc(SIZE)
         for w = 1, work do sum = sum + body(slot, i + w) end
      end
      fn()
      if slot ~= nil then C.free(slot) end
   end
   return sum
end

-- Probe: a protected region that touches no enclosing mutable state, so the
-- boundary cost is measured without any upvalue traffic.
local function bareRegion(i, work)
   local p = C.malloc(SIZE)
   local sum = 0
   for w = 1, work do sum = sum + body(p, i + w) end
   C.free(p)
   return sum
end

local function armXpcallOnly(n, work)
   local sum = 0
   for i = 1, n do
      local ok, got = xpcall(bareRegion, tostring, i, work)
      if not ok then error(got, 0) end
      sum = sum + got
   end
   return sum
end

local ARMS = {
   {name = "ffi.gc", fn = armGc},
   {name = "drop (direct free)", fn = armDrop},
   {name = "region (upvalue closure)", fn = armCleanupUpvalue},
   {name = "region (xpcall args)", fn = armCleanupArgs},
   {name = "probe: closure, no xpcall", fn = armClosureOnly},
   {name = "probe: xpcall, no upvalue", fn = armXpcallOnly},
}

-- Total body work is held constant while the work covered by ONE resource
-- grows. If cleanup only costs at the boundary its overhead should amortize
-- away down the table; if the protected region also slows the body, it will
-- not.
local TOTAL = 1600000
local GRAINS = {1, 16, 256, 4096}

print(("LuaJIT %s on %s/%s"):format(jit.version, jit.os, jit.arch))
print(("%d body units total per row, median of %d"):format(TOTAL, ROUNDS))
print("")
local header = (" %-28s"):format("arm")
for _, work in ipairs(GRAINS) do
   header = header .. ("%12s"):format(work .. " body/res")
end
print(header)
print((" %s"):format(("-"):rep(28 + 12 * #GRAINS)))

local grid = {}
for _, work in ipairs(GRAINS) do
   local n = math.max(1, math.floor(TOTAL / work))
   grid[work] = {n = n}
   for _, arm in ipairs(ARMS) do
      local loop, drain = measure(arm.fn, n, work)
      grid[work][arm.name] = loop + drain
   end
end

for _, arm in ipairs(ARMS) do
   local row = (" %-28s"):format(arm.name)
   for _, work in ipairs(GRAINS) do
      local base = grid[work]["drop (direct free)"]
      row = row .. ("%11.2fx"):format(grid[work][arm.name] / base)
   end
   print(row)
end
local counts = (" %-28s"):format("resources acquired")
for _, work in ipairs(GRAINS) do
   counts = counts .. ("%12d"):format(grid[work].n)
end
print((" %s"):format(("-"):rep(28 + 12 * #GRAINS)))
print(counts)
print(" (ratios vs drop, the direct-free path Owned<T> + drop emits)")

---------------------------------------------------------------------------
-- Backpressure: does the collector know how much C memory is outstanding?
---------------------------------------------------------------------------

local BLOCK = 64 * 1024
local BLOCKS = 4000

local freed = 0
local function countingFree(p)
   freed = freed + 1
   C.free(p)
end

local peak, luaHeapAtPeak = 0, 0
freed = 0
for i = 1, BLOCKS do
   local p = ffi.gc(C.malloc(BLOCK), countingFree)
   ffi.cast(u8, p)[0] = 1                    -- commit a page so it is real
   local outstanding = i - freed
   if outstanding > peak then
      peak = outstanding
      luaHeapAtPeak = collectgarbage("count") / 1024
   end
end
local leftAtEnd = BLOCKS - freed
collectgarbage("collect")
collectgarbage("collect")
local leftAfterCollect = BLOCKS - freed

print("")
print((" backpressure: %d x %d KB wrapped with ffi.gc"):format(BLOCKS, BLOCK / 1024))
print((" %s"):format(("-"):rep(68)))
print(("   peak outstanding        %6d blocks (%.0f MB of C memory)")
   :format(peak, peak * BLOCK / 1024 / 1024))
print(("   Lua heap at that peak   %6.1f MB")
   :format(luaHeapAtPeak))
print(("   still held at loop end  %6d blocks (%.0f MB)")
   :format(leftAtEnd, leftAtEnd * BLOCK / 1024 / 1024))
print(("   after two full collects %6d blocks"):format(leftAfterCollect))
