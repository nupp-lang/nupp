-- Reference Lua 5.5 twin of catalog-strings-basic.nupp, without its types.
local s = "hello"
local t = tostring(42)
local f = ("%d-%s"):format(7, "x")
local parts = {}
parts[1] = s
parts[2] = t
parts[3] = f
local joined = table.concat(parts, ",")
local found = 0
for _ in joined:gmatch("l+") do
    found = found + 1
end
return #joined * 100 + found
