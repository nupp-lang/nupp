-- Reference Lua 5.5 twin of catalog-numbers-float.nupp, without its types.
-- Float text: tostring writes C's "%.15g", or "%.17g" when that loses the
-- value, with ".0" on integral values; tonumber reads float numerals by
-- strtod but refuses inf and nan text.
local zero = 0.0
local s = tostring(1.5) .. "," .. tostring(10 / 4) .. "," .. tostring(3.0) .. "," .. tostring(-zero)
s = s .. "," .. tostring(1e100) .. "," .. tostring(0.1) .. "," .. tostring(1 / 3)
s = s .. "," .. tostring(123456789012345678.0) .. "," .. tostring(1 / zero) .. "," .. tostring(-1 / zero)
local result = #s * 100000000
if s == "1.5,2.5,3.0,-0.0,1e+100,0.1,0.33333333333333331,1.2345678901234568e+17,inf,-inf" then
    result = result + 1
end
local total = 0.0
local missing = 0

local function read(text)
    local value = tonumber(text)
    if value == nil then
        missing = missing + 1
    else
        total = total + value
    end
end

read("1.5")
read(" 2.5e3 ")
read("0x1p4")
read(".5")
read("5.")
read("inf")
read("nan")
read("1e")
read("abc")
if tonumber("9223372036854775808") == 9223372036854775808.0 then
    result = result + 10
end
return result + math.floor(total * 2) * 100 + missing * 10000000
