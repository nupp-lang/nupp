local function typed(value)
    return value:sub(2)
end

local function dynamic(value)
    return value:sub(2)
end

local library = string
local meta = getmetatable("")
local original = library.sub
local originalindex = meta.__index
local held = ("abc").sub

local function typedalias(value)
    return value.sub
end

local heldtyped = typedalias("abc")
assert(heldtyped == held and heldtyped("abc", 2) == "bc")
assert(("abc"):sub(2) == "bc" and typed("abc") == "bc")
library.sub = function(value, first)
    assert(value == "abc" and first == 2)
    return "library"
end
assert(("abc"):sub(2) == "library")
assert(typed("abc") == "library" and dynamic("abc") == "library")
assert(held("abc", 2) == "bc")
local changed = library.sub

local function argument()
    library.sub = original
    return 2
end

assert(("abc"):sub(argument()) == "library")
assert(library.sub == original)
meta.__index = function(value, key)
    assert(type(value) == "string")
    if key == "sub" then
        return function(subject, first)
            assert(subject == "abc" and first == 2)
            return "index"
        end
    end

    return originalindex[key]
end
collectgarbage("collect")
assert(("abc"):sub(2) == "index")
assert(typed("abc") == "index" and dynamic("abc") == "index")
assert(typedalias("abc")("abc", 2) == "index")
meta.__index = originalindex
assert(typed("abc") == "bc" and changed("abc", 2) == "library")
local string = {
    sub = function()
        return "shadow"
    end
}
assert(string.sub() == "shadow" and ("abc").sub == held)
assert(typedalias("abc") == heldtyped)
local value = "abc"
assert(
    not pcall(function()
        value.sub = original
    end)
)
return 1
