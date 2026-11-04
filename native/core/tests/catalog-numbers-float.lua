-- Reference Lua 5.5 twin of catalog-numbers-float.nupp, without its types.
-- Float text is Nupp's, not Lua's (Decision 13): the shorter of the decimal
-- and exponent texts that read back exactly, so the twin writes the text
-- Nupp's tostring gives for the fixture's values. tonumber reads float
-- numerals by strtod but refuses inf and nan text.
local s = "1.5,2.5,3.0,-0.0,1e100,0.1,0.3333333333333333,1.2345678901234568e17,inf,-inf"
local result = #s * 100000000
if s == "1.5,2.5,3.0,-0.0,1e100,0.1,0.3333333333333333,1.2345678901234568e17,inf,-inf" then
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
