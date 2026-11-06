-- Lua twin of catalog-os-time.nupp.

-- Lua's clock and calendar on the core, as reference Lua 5.5 answers them:
-- os.clock and os.time by their shape and how two readings relate; os.date
-- of fixed times in UTC, every conversion Lua takes, and "*t"; os.time of a
-- table, normalized; os.difftime; and their errors. Each check is a bit of
-- the score.
local score = 0
local bit = 1

local function check(ok)
    if ok then
        score = score | bit
    end
    bit = bit << 1
end

local function ends(text, suffix)
    return type(text) == "string" and string.sub(text, -#suffix) == suffix
end

-- The clocks: a float that only grows, and whole seconds near each other.
local first = os.clock()
local spin = 0
for k = 1, 200000 do
    spin = spin + k % 7
end
local second = os.clock()
check(math.type(first) == "float" and first >= 0 and second >= first and spin > 0)
local now = os.time()
local later = os.time()
check(math.type(now) == "integer" and now > 1600000000 and later >= now and later - now <= 5)

-- Fixed times in UTC: the fields, a format and every conversion.
local epoch = os.date("!*t", 0)
check(epoch.year == 1970 and epoch.month == 1 and epoch.day == 1 and epoch.hour == 0)
check(epoch.min == 0 and epoch.sec == 0 and epoch.wday == 5 and epoch.yday == 1 and epoch.isdst == false)
check(os.date("!%Y-%m-%d %H:%M:%S", 86400 * 365 + 3661) == "1971-01-01 01:01:01")
check(os.date("!%c", 0) == "Thu Jan  1 00:00:00 1970" and os.date("!", 0) == "" and os.date("!%%", 0) == "%")
check(
    os.date(
        "!%x|%X|%p|%r|%D|%e|%F|%h|%j|%u|%w|%U|%W|%V|%G|%g|%C|%y|%I|%R|%T",
        0
    ) == "01/01/70|00:00:00|AM|12:00:00 AM|01/01/70| 1|1970-01-01|Jan|001|4|4|00|00|01|1970|70|19|70|12|00:00|00:00:00"
)
check(os.date("!%n|%t|%Ec|%EC|%Ex|%EX|%Ey|%EY", 0) == "\n|\t|Thu Jan  1 00:00:00 1970|19|01/01/70|00:00:00|70|1970")
check(os.date("!%Od|%Oe|%OH|%OI|%Om|%OM|%OS|%Ou|%OU|%OV|%Ow|%OW|%Oy", 0) == "01| 1|00|12|01|00|00|4|00|01|4|00|70")
check(os.date("!%a %A %b %B %d %H %m %M %S %Y", 1000000000) == "Sun Sunday Sep September 09 01 09 46 40 2001")
local stringTime = "86400"
check(os.date("!%d", stringTime) == "02" and type(os.date()) == "string" and #(os.date()) > 0)

-- Local time: os.time of os.date's fields is the time, and a table is
-- normalized in place.
local here = os.date("*t", now)
check(os.time(here) == now and type(here.isdst) == "boolean")
local spec = {year = 2020, month = 13, day = 32, hour = 25}
local made = os.time(spec)
check(math.type(made) == "integer" and spec.year == 2021 and spec.month == 2 and spec.day == 2 and spec.hour == 1)
check(spec.min == 0 and spec.sec == 0 and spec.yday == 33 and spec.wday == 3 and type(spec.isdst) == "boolean")
local noon = os.date("*t", os.time({year = 2001, month = 5, day = 6}))
check(noon.hour == 12 and noon.min == 0 and noon.day == 6)
local converted = {year = "2001", month = 5.0, day = 6}
check(os.time(converted) == os.time({year = 2001, month = 5, day = 6}))
check(
    os.time(
        {year = 2000, month = 1, day = 1, hour = 0}
    ) - os.time({year = 1999, month = 12, day = 31, hour = 0}) == 86400
)

-- os.difftime.
check(os.difftime(5, 2) == 3.0 and math.type(os.difftime(5, 2)) == "float" and os.difftime(0, 2) == -2.0)

-- Errors.
local missingOk, missingMessage = pcall(function()
    return os.time({})
end)
check(not missingOk and ends(missingMessage, ":75: field 'year' missing in date table"))
local wrongOk, wrongMessage = pcall(function()
    return os.time({year = 2000, month = "x", day = 1})
end)
check(not wrongOk and ends(wrongMessage, ":79: field 'month' is not an integer"))
local fractionOk, fractionMessage = pcall(function()
    return os.time({year = 2000, month = 1.5, day = 1})
end)
check(not fractionOk and ends(fractionMessage, ":83: field 'month' is not an integer"))
local boundOk, boundMessage = pcall(function()
    return os.time({year = 2000, month = 1, day = 1 << 40})
end)
check(not boundOk and ends(boundMessage, ":87: field 'day' is out-of-bound"))
local tableOk, tableMessage = pcall(function()
    return os.time(5)
end)
check(not tableOk and ends(tableMessage, ":91: bad argument #1 to 'time' (table expected, got number)"))
local optionOk, optionMessage = pcall(function()
    return (os.date)("%Q abc")
end)
check(not optionOk and ends(optionMessage, ":95: bad argument #1 to 'date' (invalid conversion specifier '%Q abc')"))
local endOk, endMessage = pcall(function()
    return (os.date)("abc%")
end)
check(not endOk and ends(endMessage, "bad argument #1 to 'date' (invalid conversion specifier '%')"))
local twoOk, twoMessage = pcall(function()
    return (os.date)("%Ez")
end)
check(not twoOk and ends(twoMessage, "bad argument #1 to 'date' (invalid conversion specifier '%Ez')"))
local integralOk, integralMessage = pcall(function()
    return os.date("!*t", 1.5)
end)
check(
    not integralOk and ends(integralMessage, ":107: bad argument #2 to 'date' (number has no integer representation)")
)
local farOk, farMessage = pcall(function()
    return os.date("!*t", 1 << 62)
end)
check(not farOk and ends(farMessage, ":113: date result cannot be represented in this installation"))
local noneOk, noneMessage = pcall(function()
    return (os.difftime)(1)
end)
check(not noneOk and ends(noneMessage, ":117: bad argument #2 to 'difftime' (number expected, got no value)"))
local nilOk, nilMessage = pcall(function()
    return (os.difftime)(1, nil)
end)
check(not nilOk and ends(nilMessage, ":121: bad argument #2 to 'difftime' (number expected, got nil)"))
return score
