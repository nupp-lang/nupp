local function use(value, key)
    return value[key]
end

local function call(value, first)
    return value:sub(first)
end

local text = "abcdef"
local meta = getmetatable(text)
local library = string
assert(meta == getmetatable("") and meta.__index == library)
assert(meta.__index == _G.string)
assert(call(text, 3) == "cdef")
local sub = use(text, "sub")
assert(sub(text, 2, 4) == "bcd")
assert(use(text, "missing-string-field") == nil)
local missing = pcall(function()
    return text:missingStringMethod()
end)
assert(not missing)
local replacement = function(value, first)
    assert(value == text and first == 2)
    return "replaced"
end
library.sub = replacement
assert(use(text, "sub") == replacement and call(text, 2) == "replaced")
assert(sub(text, 2, 4) == "bcd")
rawset(library, "sub", sub)
assert(call(text, 3) == "cdef")
local original = meta.__index
meta.__index = function(value, key)
    if key == "size" then
        return #value
    end
    return original[key]
end
collectgarbage("collect")
assert(use(text, "size") == 6 and call(text, 3) == "cdef")
meta.__index = original
assert(use(text, "size") == nil)
local ok = pcall(function()
    local attach = setmetatable
    return attach(text, {})
end)
assert(not ok)
meta.__metatable = "protected string metatable"
assert(getmetatable(text) == "protected string metatable")
meta.__metatable = nil
text = nil
meta = nil
collectgarbage("collect")
collectgarbage("collect")
local fresh = "uvwxyz"
local freshmeta = getmetatable(fresh)
assert(freshmeta.__index == library and call(fresh, 3) == "wxyz")
return 1
