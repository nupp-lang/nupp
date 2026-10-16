local mmout = require("mmout")
local O = mmout.opaque
local M = {}

function M.main()
    local p, done = mmout.new()
    local C = {}
    local function obj(n) return setmetatable({n = n}, C) end
    local function show(v) return type(v) == "table" and v.n or tostring(v) end
    C.__concat = function(a, b) return "[" .. show(a) .. "|" .. show(b) .. "]" end
    local a, b = obj("a"), obj("b")
    p("table .. table", a .. b)
    p("table .. string", a .. "s", "s" .. a)
    p("table .. number", a .. 1, 2 .. a)
    p("chain", "x" .. a .. "y", a .. "x" .. b, "p" .. "q" .. a)
    p("plain", "a" .. "b", 1 .. 2, 1.5 .. "", "x" .. 10)
    p("missing", pcall(function() return {} .. "x" end))
    p("missing right", pcall(function() return "x" .. {} end))
    p("boolean", pcall(function() return "x" .. O(true) end))
    p("nil", pcall(function() return O(nil) .. "x" end))
    local L, R = {__concat = function() return "left" end}, {__concat = function() return "right" end}
    p("left first", setmetatable({}, L) .. setmetatable({}, R), "s" .. setmetatable({}, R), setmetatable({}, L) .. 3)
    p("table.concat stays raw", (pcall(table.concat, {a, "x"})))
    local built = ""
    local acc = setmetatable({}, {__concat = function(x, y) return type(x) == "string" and x .. "+" or "+" .. y end})
    for _ = 1, 20 do built = built .. acc end
    p("hot loop", built)
    local failing = {__concat = function() error("concat failed", 0) end}
    p("errors propagate", pcall(function() return setmetatable({}, failing) .. "x" end))
    p("non-string result", O(setmetatable({}, {__concat = function() return 42 end}) .. "x") + 1)
    return done()
end

return M
