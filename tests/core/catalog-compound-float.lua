-- Lua twin of catalog-compound-float.nupp: Lua has no compound assignment.
local stored = 0
local count = 0
for i = 1, 4 do
    stored = stored + i / 4
    count = count + 1
end
stored = stored + 0.25

return stored * 4 + count + 0.5
