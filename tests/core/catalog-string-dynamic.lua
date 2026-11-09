-- No string namespace value, getmetatable or protected-call alias carries the
-- library for this dynamic read: the receiver alone requires its metatable.
local function use(value)
    return value:sub(2)
end

assert(use("abcd") == "bcd")
return 1
