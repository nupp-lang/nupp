-- Differential tests over the four implementations.
--
-- The published vectors pin the algorithm; everything after them holds the four
-- against each other, which is what catches a padding or block-boundary
-- mistake that a handful of famous messages would sail past.
local implementations = require("implementations")

local failures = 0

local function check(name, ok, detail)
   if ok then
      io.write(("ok   %s\n"):format(name))
   else
      failures = failures + 1
      io.write(("FAIL %s: %s\n"):format(name, detail or ""))
   end
end

-- FIPS 180-4 and the two long-message examples that go with it.
local VECTORS = {
   {"", "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"},
   {"abc", "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"},
   {
      "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq",
      "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1",
   },
   {
      "abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmnhijklmno"
         .. "ijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu",
      "cf5b16a778af8380036ce59e7b0492370b249b11e8f07a51afac45037afee9d1",
   },
   {
      string.rep("a", 1000000),
      "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0",
   },
}

for _, name in ipairs(implementations.order) do
   local sha256 = implementations[name]
   local wrong = nil
   for index, vector in ipairs(VECTORS) do
      local answer = sha256(vector[1])
      if answer ~= vector[2] then
         wrong = ("vector %d: %s"):format(index, answer)
         break
      end
   end
   check(name .. " matches the published vectors", wrong == nil, wrong)
end

-- Every length from nothing to past two blocks, so the terminating bit lands in
-- each position it can, including the two that force a second padded block.
local function agreementOverLengths(alphabet, limit)
   local body = alphabet:rep(math.ceil(limit / #alphabet))
   for length = 0, limit do
      local subject = body:sub(1, length)
      local expected = implementations.c(subject)
      for _, name in ipairs(implementations.order) do
         local answer = implementations[name](subject)
         if answer ~= expected then
            return ("length %d: %s answered %s, C answered %s"):format(length, name, answer, expected)
         end
      end
   end
   return nil
end

check("every length to 200 agrees", agreementOverLengths("abcdefghij", 200) == nil,
   agreementOverLengths("abcdefghij", 200))

-- Bytes outside ASCII, and the zero byte, which a length-terminated C string
-- would stop at and a Lua string does not.
local everyByte = {}
for value = 0, 255 do
   everyByte[value + 1] = string.char(value)
end
everyByte = table.concat(everyByte)
local expected = implementations.c(everyByte)
local disagreed = nil
for _, name in ipairs(implementations.order) do
   if implementations[name](everyByte) ~= expected then
      disagreed = name
   end
end
check("all 256 byte values agree, embedded NUL included", disagreed == nil, disagreed)

-- Sizes either side of every boundary the implementations reason about: a whole
-- block, the 56-byte point where the length tally stops fitting, and the point
-- where a second padded block becomes necessary.
local boundaries = {55, 56, 57, 63, 64, 65, 119, 120, 127, 128, 129, 8191, 8192, 8193}
local boundaryProblem = nil
for _, length in ipairs(boundaries) do
   local subject = ("x"):rep(length)
   local answer = implementations.c(subject)
   for _, name in ipairs(implementations.order) do
      if implementations[name](subject) ~= answer then
         boundaryProblem = ("%s disagrees at %d bytes"):format(name, length)
      end
   end
end
check("block and padding boundaries agree", boundaryProblem == nil, boundaryProblem)

-- Calling twice must answer twice. The `@aot` entry reuses one scratch buffer
-- per call and one Lua state's registered closure table across calls, so a
-- digest leaking into the next one would show up here and nowhere else.
local first = implementations.aot("first")
local _ = implementations.aot(("y"):rep(500))
check("a call does not disturb the next", implementations.aot("first") == first)

if failures > 0 then
   io.write(("\n%d check(s) failed\n"):format(failures))
   os.exit(1)
end
io.write("\nall checks passed\n")

if arg[1] == "--bench" then
   table.remove(arg, 1)
   dofile("benchmark.lua")
end
