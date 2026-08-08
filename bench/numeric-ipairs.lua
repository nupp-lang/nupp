-- OPT-2 numeric-ipairs: the generic iterator emitted at -O0 against the raw
-- numeric loop emitted at -O1 after a dense-entry, stable-shape proof.
-- Run: luajit bench/numeric-ipairs.lua
--
-- The optimized form uses the literal's proved length as its bound and direct
-- reads for the slots the dense-table proof says are present. Run with the JIT
-- enabled: an ahead-of-time rewrite only earns a default optimization slot if
-- it still helps after tracing.

local ROUNDS = 9

local function measure(fn, values, traversals)
   fn(values, traversals)
   local times, answer = {}, nil
   for round = 1, ROUNDS do
      local started = os.clock()
      answer = fn(values, traversals)
      times[round] = os.clock() - started
   end
   table.sort(times)
   return times[math.ceil(ROUNDS / 2)], answer
end

local function generic(values, traversals)
   local total = 0
   for traversal = 1, traversals do
      for _, value in ipairs(values) do total = total + value end
   end
   return total
end

local function numeric(values, traversals, limit)
   local total = 0
   for traversal = 1, traversals do
      local held = values
      for index = 1, limit do
         total = total + held[index]
      end
   end
   return total
end

local rows = {}
for _, size in ipairs({4, 32, 256}) do
   local values = {}
   for index = 1, size do values[index] = index end
   local traversals = math.floor(8000000 / size)
   local genericTime, genericAnswer = measure(generic, values, traversals)
   local numericTime, numericAnswer = measure(function(v, n)
      return numeric(v, n, size)
   end, values, traversals)
   assert(genericAnswer == numericAnswer, "the two traversals must agree")
   rows[#rows + 1] = {size = size, generic = genericTime, numeric = numericTime}
end

local rule = ("\226\148\128"):rep(1)
io.write(("\n numeric ipairs, median of %d, JIT on\n\n"):format(ROUNDS))
io.write((" %8s %10s %10s %8s\n"):format(
   "elements", "ipairs", "numeric", "faster"))
io.write((" %s %s %s %s\n"):format(
   rule:rep(8), rule:rep(10), rule:rep(10), rule:rep(8)))
for _, row in ipairs(rows) do
   io.write((" %8d %9.4fs %9.4fs %7.2fx\n"):format(
      row.size, row.generic, row.numeric, row.generic / row.numeric))
end
io.write("\n")
