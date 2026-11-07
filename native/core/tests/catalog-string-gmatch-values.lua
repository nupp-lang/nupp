local library = string
local make = library.gmatch
local direct = string.gmatch
assert(direct == make)
local each = make("a1 b22", "(%a)(%d+)")
local a, b = each()
assert(a == "a" and b == "1")
collectgarbage("collect")
a, b = each()
assert(a == "b" and b == "22")
assert(select("#", each()) == 0 and select("#", each()) == 0)
local positions = make("ab", "()(%a)")
local start, text = positions()
assert(start == 1 and text == "a")
start, text = positions()
assert(start == 2 and text == "b" and select("#", positions()) == 0)
local whole = make("a b", "%a+")
assert(whole() == "a" and whole() == "b" and select("#", whole()) == 0)
local empty = make("ab", "")
assert(empty() == "" and empty() == "" and empty() == "")
assert(select("#", empty()) == 0)
local many = make("abcdef", "(.)(.)(.)(.)(.)(.)")

local function six(...)
    local captured = {...}
    assert(select("#", ...) == 6 and captured[1] == "a" and captured[6] == "f")
end

six(many())
assert(select("#", many()) == 0)
local converted = make(123, "%d")
assert(converted() == "1" and converted() == "2" and converted() == "3")
local ok = pcall(function()
    return make(false, "%a")
end)
assert(not ok)
local broken = make("abc", "[")
assert(not pcall(broken))
local sum = 0
for position, char in ("abc"):gmatch("()(%a)") do
    sum = sum + position + #char
end
assert(sum == 9)
sum = 0
for char in string.gmatch("ab", ".") do
    sum = sum + #char
end
assert(sum == 2)
local dynamic = "ab"
sum = 0
for char in dynamic:gmatch(".") do
    sum = sum + #char
end
assert(sum == 2)
local meta = getmetatable("")
local originalindex = meta.__index
local original = library.gmatch
local held = dynamic.gmatch
library.gmatch = function(subject, pattern)
    assert(subject == "ab" and pattern == ".")
    return function()
        return "replacement"
    end
end
assert(("ab"):gmatch(".")() == "replacement")
assert(string.gmatch == library.gmatch and string.gmatch("ab", ".")() == "replacement")
assert(direct("ab", ".")() == "a")
assert(dynamic:gmatch(".")() == "replacement")
local retained = held("ab", ".")
assert(retained() == "a" and retained() == "b" and select("#", retained()) == 0)
library.gmatch = original
meta.__index = function(subject, key)
    if key == "gmatch" then
        return function(value, pattern)
            assert(value == "ab" and pattern == ".")
            return function()
                return "index"
            end
        end
    end

    return originalindex[key]
end
collectgarbage("collect")
assert(("ab"):gmatch(".")() == "index")
assert(dynamic:gmatch(".")() == "index")
meta.__index = originalindex
assert(("ab"):gmatch(".")() == "a")
return 1
