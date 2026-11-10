-- Reference Lua 5.5 twin of catalog-numbers-text.nupp, without its types.
-- tonumber on text: decimal and hexadecimal integers with surrounding space,
-- text that is not a numeral, the int64 edges, and hexadecimal wrapping.
local total = 0

local function add(text, weight)
    local value = tonumber(text)
    if value == nil then
        total = total + weight * 7
    else
        total = total + value * weight
    end
end

add("42", 1)
add("  -17  ", 10)
add("0x10", 100)
add("0XfF", 1000)
add("12abc", 10000)
add("", 100000)
add("-", 1000000)
add("0x", 10000000)
if tonumber("9223372036854775807") == 9223372036854775807 then
    total = total + 3
end
if tonumber("-9223372036854775808") == -9223372036854775807 - 1 then
    total = total + 30
end
if tonumber("0xffffffffffffffff") == -1 then
    total = total + 300
end
return total + (tonumber(5) or 0)
