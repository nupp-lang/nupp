-- Reference Lua 5.5 twin of catalog-numeric-control.nupp: `continue` is
-- spelled as a goto to the end of the loop body.
local nested = 0
for i = 1, 5 do
    for j = 1, 5 do
        if j > i then
            break
        end
        nested = nested + j
    end
end
local skipped = 0
for i = 1, 10 do
    if i % 3 == 0 then
        goto continue
    end
    skipped = skipped + i
    ::continue::
end
local odd = 0
local k = 0
while k < 10 do
    k = k + 1
    if k % 2 == 0 then
        goto continue
    end
    odd = odd + k
    ::continue::
end
local doubled = 0
local n = 0
repeat
    local d = n * 2
    doubled = doubled + d
    n = n + 1
until d >= 8
local stopped = 0
while true do
    stopped = stopped + 3
    if stopped > 10 then
        break
    end
end
local same = 0
if 3 == 3.0 then
    same = same + 1
end
if 0.0 == -0.0 then
    same = same + 2
end
if 1 == 2 then
    same = same + 4
end
return (((nested * 100 + skipped) * 100 + odd) * 100 + doubled) * 1000 + stopped * 10 + same
