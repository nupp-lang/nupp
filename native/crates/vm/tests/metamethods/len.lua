-- reference: lua
local mmout = require("mmout")
local M = {}

-- `__len` on tables is Lua 5.2's (LuaJIT's 5.2 compatibility build); the VM
-- honors it without a flag.
function M.main()
    local p, done = mmout.new()
    local sized = setmetatable({1, 2, 3}, {__len = function(t) return 10 end})
    p("handler", #sized, rawlen and rawlen(sized) or 3)
    p("receives the operand", #setmetatable({}, {__len = function(t) return t end}) ~= nil)
    p("non-number result", #setmetatable({}, {__len = function() return "long" end}))
    p("strings ignore it", #"abc")
    local mt = {}
    local late = setmetatable({1}, mt)
    p("before", #late)
    mt.__len = function() return 99 end
    p("after", #late)
    local count = 0
    local counted = setmetatable({}, {__len = function() count = count + 1 return count end})
    local total = 0
    for _ = 1, 100 do total = total + #counted end
    p("hot loop", total, count)
    p("errors propagate", pcall(function() return #setmetatable({}, {__len = function() error("len failed", 0) end}) end))
    p("plain", #{1, 2, 3}, #{})
    local Base = {__len = function() return 7 end}
    Base.__index = Base
    local inst = setmetatable({}, setmetatable({}, {__index = Base}))
    p("not inherited through __index", #inst)
    return done()
end

return M
