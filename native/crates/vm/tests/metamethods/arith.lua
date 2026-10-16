local mmout = require("mmout")
local O = mmout.opaque
local M = {}

function M.main()
    local p, done = mmout.new()
    local V = {}
    local function vec(x) return setmetatable({x = x}, V) end
    local function name(v) return type(v) == "table" and ("v" .. tostring(v.x)) or tostring(v) end
    for _, op in ipairs({"add", "sub", "mul", "div", "mod", "pow"}) do
        V["__" .. op] = function(a, b) return op .. "(" .. name(a) .. "," .. name(b) .. ")" end
    end
    V.__unm = function(a, b) return "unm(" .. name(a) .. "," .. name(b) .. ")" end
    local a, b = vec(1), vec(2)
    p("table op table", a + b, a - b, a * b, a / b, a % b, a ^ b)
    p("table op number", a + 1, a - 1, a * 1, a / 1, a % 1, a ^ 1)
    p("number op table", 1 + a, 1 - a, 1 * a, 1 / a, 1 % a, 1 ^ a)
    p("string op table", O("s") + a, O("3") * a)
    p("unary minus", -a)
    local L, R = {__add = function() return "left" end}, {__add = function() return "right" end}
    p("left operand first", setmetatable({}, L) + setmetatable({}, R), setmetatable({}, R) + setmetatable({}, L))
    p("right operand when left has none", {} + setmetatable({}, R), 5 + setmetatable({}, R))
    p("numeric strings", O("10") + 1, O("3") * O("4"), O("2") ^ 3, 10 % O("3"), -O("2"), O("0x10") + 0)
    p("missing handler", pcall(function() return {} + 1 end))
    p("missing on both", pcall(function() return {} * {} end))
    p("bad string", pcall(function() return O("x") + 1 end))
    p("unary missing", pcall(function() return -{} end))
    p("nil operand", pcall(function() return O(nil) + 1 end))
    local counter = setmetatable({n = 0}, {__add = function(c, k) c.n = c.n + k return c end})
    local c = counter
    for i = 1, 100 do c = c + i end
    p("hot loop", c.n, c == counter)
    local Num = {}
    Num.__index = Num
    local function num(v) return setmetatable({v = v}, Num) end
    Num.__add = function(x, y) return num(x.v + y.v) end
    Num.__sub = function(x, y) return num(x.v - y.v) end
    Num.__mul = function(x, y) return num(x.v * (type(y) == "number" and y or y.v)) end
    Num.__unm = function(x) return num(-x.v) end
    Num.__eq = function(x, y) return x.v == y.v end
    local total = num(0)
    for i = 1, 50 do total = total + num(i) * 2 - num(1) end
    p("values", total.v, (-total).v, total == num(2500), total == num(1))
    local failing = {__mul = function() error("mul failed", 0) end}
    p("errors propagate", pcall(function() return setmetatable({}, failing) * 2 end))
    local multi = {__add = function() return 1, 2, 3 end}
    p("first result only", select("#", setmetatable({}, multi) + 1), (setmetatable({}, multi) + 1))
    p("no result is nil", setmetatable({}, {__sub = function() end}) - 1)
    return done()
end

return M
