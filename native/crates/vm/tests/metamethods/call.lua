local mmout = require("mmout")
local O = mmout.opaque
local M = {}

function M.main()
    local p, done = mmout.new()
    local callable = setmetatable({name = "c"}, {__call = function(self, a, b) return self.name, a, b end})
    p("arguments", callable(1, 2))
    p("no arguments", callable())
    p("results", select("#", callable(1)), select("#", callable(1, 2, 3)))
    p("pcall", pcall(callable, "x"))
    local Class = setmetatable({}, {__call = function(cls, v) return setmetatable({v = v}, cls) end})
    Class.__index = Class
    function Class:value() return self.v end
    local inst = Class(42)
    p("constructor idiom", inst:value(), getmetatable(inst) == Class)
    local varargs = setmetatable({}, {__call = function(_, ...) return select("#", ...), ... end})
    p("varargs", varargs(1, nil, 3))
    p("spread", varargs(unpack({4, 5})))
    local method = {obj = callable}
    p("as field", method.obj("f"))
    local total = 0
    local adder = setmetatable({}, {__call = function(_, x) return x + 1 end})
    for i = 1, 200 do total = total + adder(i) end
    p("hot loop", total)
    local function apply(f, ...) return f(...) end
    p("through a call", apply(adder, 9), apply(callable, "q"))
    p("not callable", pcall(function() return O({})() end))
    p("handler not callable", pcall(function() return setmetatable({}, {__call = rawget({k = 1}, "k")})() end))
    local mt = {}
    local late = setmetatable({}, mt)
    p("before", pcall(late))
    mt.__call = function() return "now" end
    p("after", late())
    local failing = setmetatable({}, {__call = function() error("call failed", 0) end})
    p("errors propagate", pcall(failing))
    local tail = setmetatable({}, {__call = function(_, n) return n end})
    local function viaTail(n) return tail(n) end
    p("tail call", viaTail(7))
    return done()
end

return M
