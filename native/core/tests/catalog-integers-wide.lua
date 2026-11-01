-- Reference Lua 5.5 twin of catalog-integers-wide.nupp, without its types.
local x = 100000000 * 100000000
local y = x * 3 + 7
local wrapped = x * x
local z = (y + wrapped % 1000) % 1000003
local cmp = 0
if x > 5 then
    cmp = cmp + 1
end
if x == 10000000000000000.0 then
    cmp = cmp + 10
end
if x < 100000000000000000.0 then
    cmp = cmp + 100
end
if x - x == 0 then
    cmp = cmp + 1000
end
local t = {}
t[x] = 5
local again = 100000000 * 100000000
return z * 100000 + cmp * 10 + (t[again] or 0)
