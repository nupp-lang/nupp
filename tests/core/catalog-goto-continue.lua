-- Lua twin of catalog-goto-continue.nupp.
local odd = 0
for index = 1, 10 do
    if index % 2 == 0 then
        goto continue
    end
    odd = odd + index
    ::continue::
end

local words = 0
for _, word in ipairs({"a", "", "b", "", "c"}) do
    if word == "" then
        goto continue
    end
    words = words + 1
    ::continue::
end

local count = 0
local steps = 0
while count < 6 do
    count = count + 1
    if count == 3 then
        goto continue
    end
    steps = steps + 1
    ::continue::
end

return odd * 100 + words * 10 + steps
