local mmout = require("mmout")
local O = mmout.opaque
local M = {}

function M.main()
    local p, done = mmout.new()
    local seen = {}
    local fn = setmetatable({present = "raw"}, {__index = function(t, k) seen[#seen + 1] = tostring(k) return "got " .. tostring(k) end})
    p("function handler", fn.missing, fn[1], fn.present, rawget(fn, "missing"), table.concat(seen, ","))
    local defaults = {color = "red", size = 3}
    local tb = setmetatable({size = 5}, {__index = defaults})
    p("table handler", tb.color, tb.size, tb.other, rawget(tb, "color"))
    local A = {a = "A"}
    local B = setmetatable({b = "B"}, {__index = A})
    local C = setmetatable({c = "C"}, {__index = B})
    local obj = setmetatable({}, {__index = C})
    p("chain", obj.a, obj.b, obj.c, obj.d)
    A.d = "late"
    p("chain sees a later write", obj.d)
    local Base = {}
    Base.__index = Base
    function Base.new(x) return setmetatable({x = x}, Base) end
    function Base:get() return self.x end
    function Base:kind() return "base" end
    local Derived = setmetatable({}, {__index = Base})
    Derived.__index = Derived
    function Derived.new(x) return setmetatable({x = x}, Derived) end
    function Derived:kind() return "derived" end
    local Leaf = setmetatable({}, {__index = Derived})
    Leaf.__index = Leaf
    function Leaf.new(x) return setmetatable({x = x}, Leaf) end
    local items = {Base.new(1), Derived.new(2), Leaf.new(3)}
    local parts = {}
    for _, item in ipairs(items) do parts[#parts + 1] = item:kind() .. item:get() end
    p("classes", table.concat(parts, " "))
    local sum = 0
    for _ = 1, 200 do for _, item in ipairs(items) do sum = sum + item:get() end end
    p("hot method calls", sum)
    function Base:kind() return "patched" end
    p("patched base", items[1]:kind(), items[2]:kind(), items[3]:kind())
    Derived.kind = nil
    p("removed override", items[2]:kind(), items[3]:kind())
    local mt = {}
    local swap = setmetatable({}, mt)
    p("handler added later: before", swap.k)
    mt.__index = function() return "now" end
    p("handler added later: after", swap.k)
    mt.__index = {k = "table now"}
    p("handler replaced", swap.k)
    setmetatable(swap, nil)
    p("metatable cleared", swap.k)
    local rejected = setmetatable({}, {__index = function(_, k) error("no field " .. k, 0) end})
    p("errors propagate", pcall(function() return rejected.thing end))
    p("index nil", pcall(function() return O(nil).y end))
    p("index number", pcall(function() return O(1).y end))
    local multi = setmetatable({}, {__index = function() return 1, 2 end})
    p("first result only", select("#", multi.x), multi.x)
    p("string methods", ("abc"):upper(), ("x"):rep(3), #("abc"):sub(2))
    O(string).shout = function(s) return s:upper() .. "!" end
    p("string method added", O("hey"):shout())
    O(string).shout = nil
    p("string index", type(("abc").len), pcall(function() return O("abc").nope end))
    local counted = 0
    local lazy = setmetatable({}, {__index = function(t, k) counted = counted + 1 rawset(t, k, k * 2) return k * 2 end})
    local total = 0
    for _ = 1, 3 do for i = 1, 10 do total = total + lazy[i] end end
    p("memoized", total, counted)
    local numkey = setmetatable({}, {__index = function(_, k) return type(k) end})
    p("key types", numkey[1], numkey[1.5], numkey.s, numkey[true], numkey[numkey])
    return done()
end

return M
