local mmout = require("mmout")
local M = {}

function M.main()
    local p, done = mmout.new()
    local T = {__tostring = function(t) return "T(" .. t.v .. ")" end}
    local t = setmetatable({v = 1}, T)
    p("tostring", tostring(t))
    p("format %s", string.format("%s and %s", t, setmetatable({v = 2}, T)))
    p("non-string result", tostring(setmetatable({}, {__tostring = function() return 42 end})))
    p("errors propagate", pcall(tostring, setmetatable({}, {__tostring = function() error("ts failed", 0) end})))
    local mt = {}
    local late = setmetatable({}, mt)
    p("before", (tostring(late):gsub("0x%x+", "ADDR"):gsub(": [%x]+$", ": ADDR")))
    mt.__tostring = function() return "late" end
    p("after", tostring(late))
    local Base = {__tostring = function(self) return "base " .. self.n end}
    Base.__index = Base
    local Derived = setmetatable({}, {__index = Base})
    Derived.__index = Derived
    local inst = setmetatable({n = 3}, Derived)
    p("not inherited through __index", (tostring(inst):match("^table") ~= nil))
    Derived.__tostring = Base.__tostring
    p("copied down", tostring(inst))
    local count = 0
    local counted = setmetatable({}, {__tostring = function() count = count + 1 return "c" end})
    local parts = {}
    for i = 1, 50 do parts[i] = tostring(counted) end
    p("hot loop", table.concat(parts):len(), count)
    p("plain values", tostring(1), tostring(1.5), tostring(nil), tostring(true), tostring("s"))
    return done()
end

return M
