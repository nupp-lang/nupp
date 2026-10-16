local mmout = require("mmout")
local O = mmout.opaque
local M = {}

function M.main()
    local p, done = mmout.new()
    local mt = {}
    local t = setmetatable({}, mt)
    p("getmetatable", getmetatable(t) == mt, getmetatable({}), setmetatable(t, mt) == t)
    mt.__metatable = "locked"
    p("protected read", getmetatable(t))
    p("protected write", pcall(O(setmetatable), t, {}))
    p("protected clear", pcall(O(setmetatable), t, nil))
    mt.__metatable = nil
    -- LuaJIT's getmetatable answers a nil `__metatable` slot as nil, so only
    -- the write is compared once the field is cleared.
    p("unlocked", (pcall(O(setmetatable), t, nil)))
    local falsy = setmetatable({}, {__metatable = false})
    p("false still protects", getmetatable(falsy), (pcall(O(setmetatable), falsy, {})))
    p("cleared", getmetatable(t))
    p("string metatable", O(getmetatable("")).__index == string)
    p("bad metatable", (pcall(O(setmetatable), {}, 1)))
    p("bad target", (pcall(O(setmetatable), 1, {})))
    local shared = {__index = function() return "shared" end}
    local a, b = setmetatable({}, shared), setmetatable({}, shared)
    p("shared metatable", a.x, b.y, getmetatable(a) == getmetatable(b))
    local self = {}
    self.__index = self
    self.v = "self"
    local selfish = setmetatable({}, self)
    p("metatable is its own __index", selfish.v)
    local loop = {}
    loop.__index = setmetatable({}, loop)
    p("rawequal", rawequal(t, t), rawequal(t, {}), rawlen and rawlen({1, 2}) or #{1, 2})
    return done()
end

return M
