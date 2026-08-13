-- Behavioural tests for nupp.data.bitset.
--
-- The set-algebra operations mark the population stale rather than tracking it
-- per word, and `wordCount` is an upper bound rather than the exact high-water
-- mark. Both are observable only through what they must not change, so most of
-- this compares against a naive set-of-positions oracle instead of asserting
-- particular internals.

local check = require("assert")
local bit = require("bit")
local bitset = require("nupp.bitsetimpl")

local FAR = bit.lshift(1, 20)

local M = {}

-- Lengths where a word boundary, an empty range, or a full word is in play.
local EDGES = {0, 1, 2, 7, 8, 15, 16, 17, 30, 31, 32, 33, 63, 64, 65, 95, 96, 97, 127, 128, 129}

-- A deterministic generator: the suite must answer the same every run, and
-- math.random is shared with whatever else the process did first.
local function seeded(seed)
   local state = seed
   return function(bound)
      state = (state * 1103515245 + 12345) % 2147483648
      return state % bound
   end
end

-- The oracle. A plain table of positions, which is the definition every
-- operation below is checked against.
local Oracle = {}
Oracle.__index = Oracle

local function oracle()
   return setmetatable({bits = {}}, Oracle)
end

function Oracle:set(index) self.bits[index] = true end
function Oracle:clear(index) self.bits[index] = nil end
function Oracle:get(index) return self.bits[index] == true end

function Oracle:setRange(low, high)
   for index = low, high do self.bits[index] = true end
end

function Oracle:count()
   local total = 0
   for _ in pairs(self.bits) do total = total + 1 end
   return total
end

function Oracle:positions()
   local out = {}
   for index in pairs(self.bits) do out[#out + 1] = index end
   table.sort(out)
   return out
end

function Oracle:orWith(other)
   for index in pairs(other.bits) do self.bits[index] = true end
end

function Oracle:andWith(other)
   for index in pairs(self.bits) do
      if not other.bits[index] then self.bits[index] = nil end
   end
end

function Oracle:andNotWith(other)
   for index in pairs(other.bits) do self.bits[index] = nil end
end

function Oracle:xorWith(other)
   -- Not `self.bits[index] and nil or true`: that expression is always true,
   -- because `and nil` makes the whole thing fall through to the `or`.
   for index in pairs(other.bits) do
      if self.bits[index] then
         self.bits[index] = nil
      else
         self.bits[index] = true
      end
   end
end

-- Every enumeration route must agree with the oracle: the count, the walk, and
-- a word-at-a-time read reassembled by hand.
local function assertSame(set, want, label)
   local positions = want:positions()
   check.equal(set:count(), #positions, label .. ": count")

   local walked = {}
   local index = set:nextSetBit(0)
   while index >= 0 do
      walked[#walked + 1] = index
      index = set:nextSetBit(index + 1)
   end
   check.equal(#walked, #positions, label .. ": walk length")
   for at = 1, #positions do
      check.equal(walked[at], positions[at], label .. ": walk position " .. at)
   end

   for _, position in ipairs(positions) do
      check.assert(set:get(position), label .. ": get " .. position)
   end

   local fromWords = 0
   for word = 0, set:wordCount() - 1 do
      local bits = set:wordAt(word)
      for offset = 0, bitset.WORD_BITS - 1 do
         local mask = bit.lshift(1, offset)
         if bit.band(bits, mask) ~= 0 then
            fromWords = fromWords + 1
            check.assert(want:get(word * bitset.WORD_BITS + offset),
               label .. ": word " .. word .. " bit " .. offset .. " unexpected")
         end
      end
   end
   check.equal(fromWords, #positions, label .. ": words hold exactly the set bits")
end

function M.emptySet()
   local set = bitset.create()
   check.equal(set:count(), 0, "empty count")
   check.assert(set:isEmpty(), "empty isEmpty")
   check.equal(set:wordCount(), 0, "empty wordCount")
   check.equal(set:nextSetBit(0), -1, "empty walk")
   check.assert(not set:get(0), "empty get 0")
   check.assert(not set:get(FAR), "empty get far")
end

function M.setAndGetAcrossWordBoundaries()
   for _, position in ipairs(EDGES) do
      local set = bitset.create(8)
      local want = oracle()
      set:set(position)
      want:set(position)
      assertSame(set, want, "single bit " .. position)

      check.assert(not set:get(position + 1), "neighbour above " .. position)
      if position > 0 then
         check.assert(not set:get(position - 1), "neighbour below " .. position)
      end

      set:clear(position)
      want:clear(position)
      assertSame(set, want, "cleared " .. position)
      check.assert(set:isEmpty(), "empty after clear " .. position)
   end
end

function M.setIsIdempotent()
   local set = bitset.create()
   set:set(70)
   set:set(70)
   set:set(70)
   check.equal(set:count(), 1, "count counts distinct positions, not calls")
end

function M.growthPreservesContents()
   local set = bitset.create(1)
   local want = oracle()
   for _, position in ipairs({0, 5, 31, 32, 200, 1000, 4095}) do
      set:set(position)
      want:set(position)
      assertSame(set, want, "after growing to " .. position)
   end
end

function M.rangesCoverEveryShape()
   -- Inside one word, spanning two, spanning many, and the empty range.
   local shapes = {
      {0, 0}, {0, 31}, {1, 30}, {5, 5}, {31, 32}, {31, 33}, {32, 63},
      {0, 63}, {7, 120}, {64, 64}, {96, 200}, {10, 9},
   }
   for _, shape in ipairs(shapes) do
      local low, high = shape[1], shape[2]
      local label = ("range %d..%d"):format(low, high)

      local set = bitset.create(8)
      local want = oracle()
      set:setRange(low, high)
      want:setRange(low, high)
      assertSame(set, want, label)

      -- Over a set that already holds overlapping bits, so the count delta is
      -- exercised rather than a fresh popcount.
      local overlapping = bitset.create(8)
      local overlappingWant = oracle()
      for position = 0, 40, 3 do
         overlapping:set(position)
         overlappingWant:set(position)
      end
      overlapping:setRange(low, high)
      overlappingWant:setRange(low, high)
      assertSame(overlapping, overlappingWant, label .. " over existing bits")
   end
end

function M.rangeAfterStaleCount()
   -- setRange has an exact-delta path and a leave-it-stale path; the stale one
   -- is only reachable after set algebra.
   local set = bitset.create(64)
   local other = bitset.create(64)
   local want, otherWant = oracle(), oracle()
   for position = 0, 60, 2 do
      set:set(position)
      want:set(position)
   end
   for position = 0, 60, 3 do
      other:set(position)
      otherWant:set(position)
   end

   set:andWith(other)
   want:andWith(otherWant)
   set:setRange(70, 100)
   want:setRange(70, 100)
   assertSame(set, want, "range after a stale population")
end

function M.clearIsDefinedPastTheEnd()
   local set = bitset.create(64)
   set:set(5)
   set:clear(1000)
   set:clear(-1)
   check.equal(set:count(), 1, "clearing past the end changes nothing")
   check.assert(set:get(5), "the real bit survives")
end

function M.negativeWritesRaise()
   local set = bitset.create()
   check.raises(function() set:set(-1) end, "negative")
   check.raises(function() set:setRange(-1, 4) end, "below zero")
end

function M.clearAllKeepsCapacity()
   local set = bitset.create(8)
   set:set(4000)
   check.equal(set:count(), 1, "grew and set")
   set:clearAll()
   check.equal(set:count(), 0, "cleared")
   check.equal(set:wordCount(), 0, "bound reset")
   check.equal(set:nextSetBit(0), -1, "nothing to walk")

   -- Reusing it must not need another growth to reach the same position.
   set:set(4000)
   check.assert(set:get(4000), "reusable after clearAll")
end

function M.setOnlyReplacesEverything()
   local set = bitset.create()
   set:setRange(0, 100)
   set:setOnly(500)
   local want = oracle()
   want:set(500)
   assertSame(set, want, "setOnly")
end

function M.comparisonsMatchTheOracle()
   local left, right = bitset.create(64), bitset.create(64)
   local leftWant, rightWant = oracle(), oracle()
   for position = 0, 100, 2 do
      left:set(position)
      leftWant:set(position)
   end
   for position = 0, 100, 4 do
      right:set(position)
      rightWant:set(position)
   end

   check.assert(left:containsAll(right), "evens contain multiples of four")
   check.assert(not right:containsAll(left), "not the other way")
   check.assert(left:overlaps(right), "they overlap")
   check.assert(not left:disjoint(right), "so they are not disjoint")

   local odd = bitset.create(64)
   odd:set(1)
   check.assert(not left:overlaps(odd), "evens miss an odd bit")
   check.assert(left:disjoint(odd), "so they are disjoint")

   local empty = bitset.create()
   check.assert(left:containsAll(empty), "everything contains the empty set")
   check.assert(not left:overlaps(empty), "nothing overlaps the empty set")
   check.assert(empty:containsAll(empty), "the empty set contains itself")
   check.assert(empty:disjoint(empty), "and is disjoint from itself")
end

function M.containsAllAcrossDifferentCapacities()
   local wide = bitset.create(4096)
   local narrow = bitset.create(8)
   wide:set(3)
   narrow:set(3)
   check.assert(wide:containsAll(narrow), "capacity does not affect containment")
   check.assert(narrow:containsAll(wide), "in either direction")

   narrow:set(5000)
   check.assert(not wide:containsAll(narrow), "a bit beyond is not contained")
end

function M.copyFromIsIndependent()
   local source = bitset.create(64)
   local want = oracle()
   for position = 0, 200, 7 do
      source:set(position)
      want:set(position)
   end

   local target = bitset.create(4096)
   target:setRange(0, 3000)
   target:copyFrom(source)
   assertSame(target, want, "copied")

   -- Writing through one must not reach the other.
   target:set(1)
   check.assert(not source:get(1), "copy does not share storage")
   check.equal(source:count(), want:count(), "source untouched")

   local fromEmpty = bitset.create(64)
   fromEmpty:setRange(0, 100)
   fromEmpty:copyFrom(bitset.create())
   check.equal(fromEmpty:count(), 0, "copying an empty set empties the target")
   check.equal(fromEmpty:nextSetBit(0), -1, "and leaves nothing to walk")
end

function M.setAlgebraMatchesTheOracle()
   local operations = {"orWith", "andWith", "andNotWith", "xorWith"}
   for _, operation in ipairs(operations) do
      for _, width in ipairs({1, 32, 33, 200}) do
         local next = seeded(width * 7 + #operation)
         local left, right = bitset.create(8), bitset.create(8)
         local leftWant, rightWant = oracle(), oracle()

         for _ = 1, 40 do
            local position = next(width + 1)
            left:set(position)
            leftWant:set(position)
            local other = next(width + 1)
            right:set(other)
            rightWant:set(other)
         end

         local label = ("%s at width %d"):format(operation, width)
         left[operation](left, right)
         leftWant[operation](leftWant, rightWant)
         assertSame(left, leftWant, label)

         -- The right operand is read, never written.
         assertSame(right, rightWant, label .. ": operand untouched")
      end
   end
end

function M.setAlgebraWithEmptyOperands()
   local cases = {"orWith", "andWith", "andNotWith", "xorWith"}
   for _, operation in ipairs(cases) do
      local set = bitset.create(64)
      local want = oracle()
      for position = 0, 100, 5 do
         set:set(position)
         want:set(position)
      end

      set[operation](set, bitset.create())
      want[operation](want, oracle())
      assertSame(set, want, operation .. " with an empty operand")

      local empty = bitset.create()
      local emptyWant = oracle()
      empty[operation](empty, set)
      emptyWant[operation](emptyWant, want)
      assertSame(empty, emptyWant, "empty " .. operation .. " with an operand")
   end
end

function M.orGrowsToReachTheOperand()
   local small = bitset.create(1)
   local large = bitset.create(64)
   local want = oracle()
   large:set(5000)
   want:set(5000)
   small:orWith(large)
   assertSame(small, want, "union grew to reach the operand")
end

function M.randomOperationSequence()
   -- The interleaving is what shakes out the stale-population and used-bound
   -- bookkeeping: no single operation reaches every state.
   local next = seeded(20260813)
   local set = bitset.create(8)
   local want = oracle()

   for step = 1, 4000 do
      local choice = next(100)
      if choice < 30 then
         local position = next(300)
         set:set(position)
         want:set(position)
      elseif choice < 50 then
         local position = next(300)
         set:clear(position)
         want:clear(position)
      elseif choice < 60 then
         local low, high = next(200), next(200)
         set:setRange(low, high)
         want:setRange(low, high)
      elseif choice < 75 then
         local other, otherWant = bitset.create(8), oracle()
         for _ = 1, 10 do
            local position = next(300)
            other:set(position)
            otherWant:set(position)
         end
         local operation = ({"orWith", "andWith", "andNotWith", "xorWith"})[next(4) + 1]
         set[operation](set, other)
         want[operation](want, otherWant)
      elseif choice < 80 then
         set:clearAll()
         want = oracle()
      elseif choice < 90 then
         -- Reading the count resolves a stale population; the sequence must be
         -- the same whether or not anyone looked.
         check.equal(set:count(), want:count(), "count at step " .. step)
      else
         local position = next(300)
         check.equal(set:get(position), want:get(position),
            "get at step " .. step .. " position " .. position)
      end

      if step % 200 == 0 then
         assertSame(set, want, "random sequence at step " .. step)
      end
   end

   assertSame(set, want, "random sequence end state")
end

function M.walkIsStatelessAndNestable()
   local set = bitset.create(64)
   for _, position in ipairs({3, 40, 41, 300}) do set:set(position) end

   -- Two walks interleaved. A scan holding state on the set could not do this.
   local outer = set:nextSetBit(0)
   local pairsSeen = 0
   while outer >= 0 do
      local inner = set:nextSetBit(0)
      while inner >= 0 do
         pairsSeen = pairsSeen + 1
         inner = set:nextSetBit(inner + 1)
      end
      outer = set:nextSetBit(outer + 1)
   end
   check.equal(pairsSeen, 16, "4 by 4 interleaved walk")

   -- A walk resumed after a mutation still terminates and reports live bits.
   local index = set:nextSetBit(0)
   set:clear(40)
   index = set:nextSetBit(index + 1)
   check.equal(index, 41, "cleared bit is skipped")

   check.equal(set:nextSetBit(-5), 3, "a negative start reads as zero")
   check.equal(set:nextSetBit(301), -1, "past the last bit")
   check.equal(set:nextSetBit(FAR), -1, "far past the end")
end

function M.wordAtIsBoundedAndSigned()
   local set = bitset.create(64)
   check.equal(set:wordAt(0), 0, "unset word reads zero")
   check.equal(set:wordAt(-1), 0, "negative word index reads zero")
   check.equal(set:wordAt(FAR), 0, "word index past the end reads zero")

   set:set(bitset.WORD_BITS - 1)
   check.assert(set:wordAt(0) < 0, "the top bit of a word reads negative")

   set:set(bitset.WORD_BITS)
   check.equal(set:wordAt(1), 1, "the next word holds the next position")
end

function M.wordCountBoundsEverySetBit()
   -- The bound may exceed the exact high-water mark, but every set bit must sit
   -- below it, because that is what the word loops rely on.
   local set = bitset.create(8)
   set:setRange(0, 500)
   set:clear(500)
   for position = 400, 499 do set:clear(position) end

   local highest = -1
   local index = set:nextSetBit(0)
   while index >= 0 do
      highest = index
      index = set:nextSetBit(index + 1)
   end
   check.assert(set:wordCount() * bitset.WORD_BITS > highest,
      "every set bit is below the bound")
end

function M.positionsIntoMatchesTheWalk()
   local ffi = require("ffi")
   for _, bits in ipairs({1, 32, 33, 200, 4096}) do
      local set = bitset.create(8)
      local want = oracle()
      local step = math.max(1, math.floor(bits / 17))
      for position = 0, bits - 1, step do
         set:set(position)
         want:set(position)
      end

      local expected = want:positions()
      local target = ffi.new("int32_t[?]", math.max(1, #expected))
      local written, resume = set:positionsInto(target, #expected, 0)
      check.equal(written, #expected, "written at width " .. bits)
      check.equal(resume, -1, "exhausted at width " .. bits)
      for at = 1, #expected do
         check.equal(target[at - 1], expected[at],
            ("position %d at width %d"):format(at, bits))
      end
   end
end

function M.positionsIntoResumesWhenTargetFills()
   local ffi = require("ffi")
   local set = bitset.create(64)
   local want = oracle()
   for position = 0, 300, 3 do
      set:set(position)
      want:set(position)
   end
   local expected = want:positions()

   -- A target smaller than the population, drained in chunks. The chained calls
   -- have to produce exactly the walk's sequence with nothing lost or repeated.
   local target = ffi.new("int32_t[?]", 7)
   local collected, from = {}, 0
   while from >= 0 do
      local written, resume = set:positionsInto(target, 7, from)
      for at = 1, written do collected[#collected + 1] = target[at - 1] end
      check.assert(resume == -1 or written == 7,
         "a partial fill means the set was exhausted")
      from = resume
   end

   check.equal(#collected, #expected, "chunked total")
   for at = 1, #expected do
      check.equal(collected[at], expected[at], "chunked position " .. at)
   end
end

function M.positionsIntoEdges()
   local ffi = require("ffi")
   local target = ffi.new("int32_t[?]", 4)

   local empty = bitset.create(64)
   local written, resume = empty:positionsInto(target, 4, 0)
   check.equal(written, 0, "nothing written for an empty set")
   check.equal(resume, -1, "and it is exhausted")

   local set = bitset.create(64)
   set:set(5)
   set:set(100)

   written, resume = set:positionsInto(target, 0, 0)
   check.equal(written, 0, "a zero capacity writes nothing")
   check.equal(resume, 0, "and resumes where it started")

   written, resume = set:positionsInto(target, 4, 6)
   check.equal(written, 1, "a start past the first position skips it")
   check.equal(target[0], 100, "and finds the next")
   check.equal(resume, -1, "then is exhausted")

   written, resume = set:positionsInto(target, 4, 101)
   check.equal(written, 0, "a start past every position writes nothing")
   check.equal(resume, -1, "and is exhausted")

   written, resume = set:positionsInto(target, 4, -5)
   check.equal(written, 2, "a negative start reads as zero")
   check.equal(target[0], 5, "first position")

   written, resume = set:positionsInto(target, 4, FAR)
   check.equal(written, 0, "a start far past the end writes nothing")
   check.equal(resume, -1, "and is exhausted")

   check.raises(function() set:positionsInto(target, -1, 0) end, "capacity")
end

function M.positionsIntoAfterSetAlgebra()
   -- The used bound is an upper bound after intersection, so the extraction has
   -- to tolerate trailing zero words rather than trusting the bound is tight.
   local ffi = require("ffi")
   local set = bitset.create(4096)
   local other = bitset.create(4096)
   local want, otherWant = oracle(), oracle()
   for position = 0, 3000, 7 do
      set:set(position)
      want:set(position)
   end
   for position = 0, 500, 7 do
      other:set(position)
      otherWant:set(position)
   end

   set:andWith(other)
   want:andWith(otherWant)
   local expected = want:positions()

   local target = ffi.new("int32_t[?]", math.max(1, #expected))
   local written, resume = set:positionsInto(target, #expected, 0)
   check.equal(written, #expected, "written after intersection")
   check.equal(resume, -1, "exhausted after intersection")
   for at = 1, #expected do
      check.equal(target[at - 1], expected[at], "position " .. at)
   end
end

return M
