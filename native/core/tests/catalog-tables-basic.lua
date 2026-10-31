-- Reference Lua 5.5 twin of catalog-tables-basic.nupp, without its types.
local xs = {}
for i = 1, 1000 do
    xs[i] = i * 2
end
local total = 0
for i = 1, #xs do
    total = total + xs[i]
end
local sparse = {}
for i = 1, 50 do
    sparse[i * 1000] = i
end
local hashed = 0
for i = 1, 50 do
    hashed = hashed + sparse[i * 1000]
end
return (total * 10000 + #xs) * 10000 + hashed
