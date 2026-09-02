-- The value boundary a browser worker lane copies across.
--
-- A lane is a separate Lua state, so what these assert is what a copy must
-- preserve and what it must refuse. The refusals are the native scheduler's
-- wording on purpose: they are the same rule about the same values, and the
-- corresponding native paths are covered by the worker suites.

local check = require("assert")
local codec = require("nupp.runtime.browser.workercodec")

local M = {}

local function packed(...)
   return {values = {...}, count = select("#", ...)}
end

local function roundTrip(...)
   return codec.decode(codec.encode(packed(...)))
end

local function rejects(value)
   return codec.unsendable(value, "argument 1", 0, {seen = {}})
end

function M.scalarsCrossUnchanged()
   local answer = roundTrip(nil, true, false, 0, -1, 1.5, "", "text")
   check.equal(answer.count, 8, "the pack keeps its length")
   check.equal(answer.values[1], nil, "a nil position is retained")
   check.equal(answer.values[2], true, "true crosses")
   check.equal(answer.values[3], false, "false crosses")
   check.equal(answer.values[4], 0, "zero crosses")
   check.equal(answer.values[5], -1, "a negative number crosses")
   check.equal(answer.values[6], 1.5, "a fraction crosses")
   check.equal(answer.values[7], "", "the empty string crosses")
   check.equal(answer.values[8], "text", "a string crosses")
end

function M.anEmptyPackCrosses()
   local answer = roundTrip()
   check.equal(answer.count, 0, "an empty result pack has no values")
end

function M.trailingNilPositionsAreRetained()
   local answer = roundTrip("only", nil, nil)
   check.equal(answer.count, 3, "trailing nils are part of the pack")
   check.equal(answer.values[1], "only", "the first value crosses")
end

function M.numbersRoundTripExactly()
   local values = {
      0.1, 1 / 3, 2 ^ 53, -2 ^ 53, 1e308, 5e-324, 2147483647, -2147483648,
   }
   for _, value in ipairs(values) do
      check.equal(roundTrip(value).values[1], value, "exact round trip for " .. tostring(value))
   end
   check.equal(roundTrip(math.huge).values[1], math.huge, "positive infinity crosses")
   check.equal(roundTrip(-math.huge).values[1], -math.huge, "negative infinity crosses")
   local nan = roundTrip(0 / 0).values[1]
   check.assert(nan ~= nan, "not-a-number crosses as not-a-number")
end

function M.arbitraryStringBytesSurvive()
   local bytes = {}
   for byte = 0, 255 do
      bytes[#bytes + 1] = string.char(byte)
   end
   local blob = table.concat(bytes)
   check.equal(roundTrip(blob).values[1], blob, "every byte value crosses")
   check.equal(roundTrip("a\0b").values[1], "a\0b", "an embedded zero crosses")
end

function M.tablesCrossAsIndependentCopies()
   local original = {1, 2, three = {deep = "value"}, [true] = "flag"}
   local answer = roundTrip(original).values[1]
   check.assert(answer ~= original, "the receiver gets its own table")
   check.equal(answer[1], 1, "an array position crosses")
   check.equal(answer[2], 2, "the next array position crosses")
   check.equal(answer.three.deep, "value", "a nested table crosses")
   check.equal(answer[true], "flag", "a boolean key crosses")
end

function M.aRepeatedTableIsRefusedRatherThanDuplicated()
   local shared = {name = "a"}
   check.equal(
      rejects({shared, shared}),
      "argument 1[2] repeats a table already present in the message",
      "decoding one identity twice would silently make two"
   )
end

function M.aCycleIsRefused()
   local looped = {}
   looped.self = looped
   check.matches(rejects(looped), "repeats a table already present", "a cycle is a repeat of its own root")
end

function M.deepNestingIsRefused()
   local root = {}
   local at = root
   for _ = 1, 40 do
      at.next = {}
      at = at.next
   end
   check.matches(rejects(root), "nests deeper than 32 tables", "the depth bound is named where it is reached")
end

function M.valuesNoCopyCouldReproduceAreRefused()
   check.equal(rejects(print), "argument 1 is a function", "a function cannot cross")
   check.equal(
      rejects({hook = print}),
      "argument 1[hook] is a function",
      "the message names the path rather than the argument"
   )
   check.equal(rejects(coroutine.create(print)), "argument 1 is a thread", "a thread cannot cross")
   check.equal(
      rejects(setmetatable({}, {__index = {}})),
      "argument 1 has a metatable",
      "only an exported record declaration is reproducible"
   )
   check.equal(
      rejects({[print] = 1}),
      "argument 1 has a function key",
      "a key outside the transferable scalars is refused"
   )
end

function M.nothingRefusedIsSaidOfATransferableValue()
   check.equal(rejects({1, "two", {nested = true}}), nil, "a plain tree of scalars crosses")
   check.equal(rejects(nil), nil, "nil crosses")
end

function M.malformedMessagesAreRefusedRatherThanDecoded()
   for _, bytes in ipairs({"", "3:", "1:S5:ab", "1:Q", "1:S1:ab"}) do
      check.raises(function()
         codec.decode(bytes)
      end, "worker message")
   end
end


-- A task scope reaches whichever provider is selected through the same three hidden
-- functions and holds a `fork` to that provider's own `Submitted`. The two
-- implementations deliberately differ over what may cross -- native moves an
-- engine-backed buffer, the browser refuses every ownership mode -- so each exports
-- its own contract, and neither keeps a private copy the task scope could not see.
function M.bothProvidersExportTheSubmissionContractAndTheScopeHooks()
   local here = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
   local function read(path)
      local file = assert(io.open(here .. "/../" .. path, "rb"))
      local text = file:read("*a")
      file:close()
      return text
   end
   for _, path in ipairs({
      "src/nupp/workers/init.nupp",
      "src/nupp/runtime/provider/browserworkers.g.nupp",
   }) do
      local source = read(path)
      check.assert(source:find("\ntype workers.Submittable = sendable function", 1, true),
         path .. " exports Submittable")
      check.assert(source:find("\ncomptime function workers.Submitted(F: type): typepack", 1, true),
         path .. " exports Submitted as a direct member")
      check.equal(source:find("local type Submittable", 1, true), nil,
         path .. " keeps no private Submittable")
      check.equal(source:find("local comptime function Submitted", 1, true), nil,
         path .. " keeps no private Submitted")
      for _, hook in ipairs({"__scope", "__settle", "__parallelism"}) do
         check.assert(source:find('rawset(workers, "' .. hook .. '"', 1, true),
            path .. " installs " .. hook)
      end
   end
end

return M
