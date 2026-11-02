-- Lua twin of catalog-numbers-random.nupp.

-- math.random draws as Lua 5.5's xoshiro256** does once seeded: integers in
-- a range, floats in [0, 1) and any integer for 0.
math.randomseed(42)
local score = 0
for _ = 1, 20 do
    score = (score * 31 + math.random(1, 100)) % 1000000007
end
for _ = 1, 5 do
    score = (score * 31 + math.random(6)) % 1000000007
end
local f = math.random()
if f >= 0 and f < 1 then
    score = score + 1
end
score = (score * 31 + math.floor(f * 1000000)) % 1000000007
score = (score * 31 + math.random(0) % 1000) % 1000000007
math.randomseed(7)
score = (score * 31 + math.random(-5, 5) + 5) % 1000000007
score = (score * 31 + math.random(math.mininteger, math.maxinteger) % 997) % 1000000007
score = (score * 31 + math.random(1, 1)) % 1000000007
local any = math.random(1, 3)
if any >= 1 and any <= 3 then
    score = score * 2
end
return score
