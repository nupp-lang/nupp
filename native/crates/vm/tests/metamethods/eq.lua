local mmout = require("mmout")
local M = {}

function M.main()
    local p, done = mmout.new()
    local calls = 0
    local mt = {__eq = function(a, b) calls = calls + 1 return a.v == b.v end}
    local a, b, c = setmetatable({v = 1}, mt), setmetatable({v = 1}, mt), setmetatable({v = 2}, mt)
    p("same metatable", a == b, a ~= b, a == c, a ~= c, calls)
    p("identity skips the handler", a == a, a ~= a, rawequal(a, b), calls)
    local shared = function() calls = calls + 1 return true end
    local x, y = setmetatable({}, {__eq = shared}), setmetatable({}, {__eq = shared})
    p("shared handler, two metatables", x == y, x ~= y, calls)
    local z = setmetatable({}, {__eq = function() return true end})
    p("different handlers", x == z, z == x, x ~= z)
    local plain = {}
    p("one side only", x == plain, plain == x, x ~= plain)
    p("other types", a == 1, a == "v", a == nil, a == true, a == print, 1 == a)
    local truthy = {__eq = function() return 1 end}
    local falsy = {__eq = function() return nil end}
    p("result is a boolean", setmetatable({}, truthy) == setmetatable({}, truthy),
        setmetatable({}, falsy) == setmetatable({}, falsy), setmetatable({}, falsy) ~= setmetatable({}, falsy))
    local n = 0
    for _ = 1, 20 do
        if a == b then n = n + 1 end
        if a ~= c then n = n + 100 end
        if not (a == c) then n = n + 10000 end
    end
    p("in branches", n)
    local order = {}
    local logged = {__eq = function(l, r) order[#order + 1] = l.n .. r.n return false end}
    local l, r = setmetatable({n = "l"}, logged), setmetatable({n = "r"}, logged)
    local _ = l == r
    _ = r == l
    _ = l ~= r
    p("operand order", table.concat(order, ","))
    local late = {}
    local s1, s2 = setmetatable({}, late), setmetatable({}, late)
    p("added later: before", s1 == s2)
    late.__eq = function() return true end
    p("added later: after", s1 == s2)
    late.__eq = nil
    p("removed", s1 == s2)
    setmetatable(s1, mt)
    setmetatable(s2, mt)
    s1.v, s2.v = 5, 5
    p("metatable replaced", s1 == s2, s1 ~= s2)
    setmetatable(s1, nil)
    p("metatable cleared", s1 == s2, s2 == s1)
    local keys = {}
    keys[a] = "a"
    p("table keys stay raw", keys[b], keys[a])
    local failing = {__eq = function() error("eq failed", 0) end}
    p("errors propagate", pcall(function() return setmetatable({}, failing) == setmetatable({}, failing) end))
    local base = {__eq = function() return true end}
    base.__index = base
    local derived = setmetatable({}, base)
    local inst1, inst2 = setmetatable({}, derived), setmetatable({}, derived)
    p("not inherited through __index", inst1 == inst2)
    local counted = 0
    local cmt = {__eq = function(u, w) counted = counted + 1 return u.k == w.k end}
    local items = {}
    for i = 1, 50 do items[i] = setmetatable({k = i % 5}, cmt) end
    local matches = 0
    for i = 1, 50 do
        for j = 1, 50 do
            if items[i] == items[j] then matches = matches + 1 end
        end
    end
    p("hot loop", matches, counted)
    local function eqf(u, w) return u == w end
    local function nef(u, w) return u ~= w end
    p("through calls", eqf(a, b), nef(a, b), eqf(a, c), nef(a, c), eqf(1, 1), eqf("x", "x"), eqf({}, {}))
    return done()
end

return M
