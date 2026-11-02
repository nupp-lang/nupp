-- Lua twin of catalog-numbers-power.nupp.

-- a ^ b is always a float, by C's pow; math's exp, log (with a base),
-- trigonometry and fmod come from C too, and fmod of integers is the
-- remainder of truncated division.
local score = 0
local function add(x)
    score = (score * 7 + math.floor(x * 1000000)) % 1000000007
end
add(2 ^ 10)
add(2 ^ 0.5)
add(10 ^ -2)
add(math.exp(1))
add(math.log(100))
add(math.log(8, 2))
add(math.log(1000, 10))
add(math.log(81, 3))
add(math.sin(1))
add(math.cos(1))
add(math.tan(0.5))
add(math.asin(0.5))
add(math.acos(0.5))
add(math.atan(1))
add(math.fmod(7.5, 2))
add(math.fmod(-7.5, 2))
local r1 = math.fmod(-7, 2)
local r2 = math.fmod(7, -2)
local r3 = math.fmod(math.mininteger, -1)
score = score * 10 + (r1 + 1) * 4 + (r2 - 1) * 2
if r3 == 0 and math.type(r1) == "integer" and math.type(2 ^ 2) == "float" then
    score = score + 1
end
return score
