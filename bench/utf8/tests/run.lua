-- Holds all four validators to each other, then measures them interleaved.
--
-- The differential is exhaustive where exhaustive is cheap: every byte value
-- alone, every pair, every prefix of a well-formed sample, and random strings
-- drawn from the lead bytes that decide the hard cases.
local implementations = assert(loadfile("implementations.lua"))()

local function differential()
   local subjects = {}
   for _, name in ipairs(implementations.order) do subjects[#subjects + 1] = name end

   local function agree(value, what)
      local want = implementations.shipped(value)
      for _, name in ipairs(subjects) do
         local got = implementations[name](value)
         if got ~= want then
            error(("%s disagrees on %s (%q): got %s, want %s")
               :format(name, what, value, tostring(got), tostring(want)), 0)
         end
      end
   end

   for b = 0, 255 do agree(string.char(b), "one byte") end
   for a = 0, 255 do
      for b = 0, 255 do agree(string.char(a, b), "two bytes") end
   end
   local sample = "A caf\xc3\xa9 \xe2\x82\xac3 \xf0\x9f\x8d\xb0 \xe6\x97\xa5\xe6\x9c\xac ok"
   for i = 0, #sample do agree(sample:sub(1, i), "a prefix") end
   for i = 1, #sample do agree(sample:sub(i), "a suffix") end

   math.randomseed(31)
   local leads = {0xC2, 0xC3, 0xDF, 0xE0, 0xED, 0xE6, 0xEF, 0xF0, 0xF4, 0xF5, 0x80, 0xBF, 0x41}
   for _ = 1, 200000 do
      local t = {}
      for i = 1, math.random(0, 20) do
         t[i] = string.char(math.random() < 0.55 and leads[math.random(#leads)] or math.random(0, 255))
      end
      agree(table.concat(t), "a random string")
   end
   -- Everything above is shorter than a block, so the SIMD path has only ever
   -- run its scalar tail. These are the cases that reach the block loop: a
   -- corruption walked through every position of a multi-block string, and the
   -- boundaries themselves, where a scalar straddling byte 64 is the case the
   -- carry vector and the three-byte rewind exist for.
   local long = ("A caf\xc3\xa9 \xe2\x82\xac \xf0\x9f\x8d\xb0 \xe6\x97\xa5\xe6\x9c\xac ok. "):rep(40)
   agree(long, "a multi-block string")
   for at = 1, #long do
      for _, bad in ipairs({"\xff", "\x80", "\xc0", "\xf5", "\xed\xa0\x80"}) do
         agree(long:sub(1, at - 1) .. bad .. long:sub(at + #bad), "a corruption at " .. at)
      end
      agree(long:sub(1, at), "a truncation at " .. at)
   end
   -- A scalar deliberately placed across each of the first three block edges.
   for _, edge in ipairs({64, 128, 192}) do
      for _, scalar in ipairs({"\xc3\xa9", "\xe2\x82\xac", "\xf0\x9f\x8d\xb0"}) do
         for shift = 0, #scalar - 1 do
            local head = ("a"):rep(edge - shift)
            agree(head .. scalar .. ("b"):rep(80), "a scalar across " .. edge)
            agree(head .. scalar:sub(1, #scalar - 1) .. ("b"):rep(80), "a broken scalar across " .. edge)
         end
      end
   end
   print("differential: every byte, every pair, every prefix and suffix of a sample,")
   print("200000 random strings, and every corruption, truncation and block-edge")
   print("straddle of a multi-block string -- all four agree\n")
end

local function corpus(make) local l = {} for i = 1, 64 do l[i] = make(i) end return l end
local CASES = {
   {"short ascii (8-24 B)", corpus(function(i) return string.rep("ab", 4 + i % 9) end), 3000},
   {"short accented (~20 B)", corpus(function(i) return ("caf\xc3\xa9 na\xc3\xafve %d"):format(i) end), 3000},
   {"short CJK (~24 B)", corpus(function(i) return string.rep("\xe6\x97\xa5\xe6\x9c\xac\xe8\xaa\x9e", 2 + i % 3) end), 3000},
   {"json-ish 4 KiB", {string.rep('{"name":"value","n":12345},', 152)}, 8000},
   {"CJK 900 B", {string.rep("\xe6\x97\xa5\xe6\x9c\xac\xe8\xaa\x9e", 100)}, 8000},
   {"ascii 1 MiB", {string.rep("abcdefgh", 131072)}, 40},
}

local function time(f, list, rounds)
   for i = 1, #list do f(list[i]) end
   local best = math.huge
   for _ = 1, 7 do
      local t0 = os.clock()
      for _ = 1, rounds do for i = 1, #list do f(list[i]) end end
      local dt = os.clock() - t0
      if dt < best then best = dt end
   end
   local bytes = 0
   for i = 1, #list do bytes = bytes + #list[i] end
   return (bytes * rounds) / 1048576 / best
end

differential()
io.write(("%-24s"):format(""))
for _, name in ipairs(implementations.order) do io.write(("%20s"):format(implementations.titles[name])) end
print()
for _, case in ipairs(CASES) do
   local label, list, rounds = case[1], case[2], case[3]
   local rates = {}
   for _, name in ipairs(implementations.order) do
      rates[name] = time(implementations[name], list, rounds)
   end
   io.write(("%-24s"):format(label))
   for _, name in ipairs(implementations.order) do io.write(("%13.0f MB/s"):format(rates[name])) end
   print()
   io.write(("%-24s"):format("  against shipped"))
   for _, name in ipairs(implementations.order) do
      io.write(("%19.2fx"):format(rates[name] / rates.shipped))
   end
   print()
end
