local mmout = require("mmout")
local O = mmout.opaque
local M = {}

function M.main()
    local p, done = mmout.new()
    local log = {}
    local mt = {}
    mt.__lt = function(a, b) log[#log + 1] = "lt" .. a.v .. b.v return a.v < b.v end
    mt.__le = function(a, b) log[#log + 1] = "le" .. a.v .. b.v return a.v <= b.v end
    local one, two = setmetatable({v = 1}, mt), setmetatable({v = 2}, mt)
    p("lt", one < two, two < one, one < one)
    p("le", one <= two, two <= one, one <= one)
    p("gt swaps", one > two, two > one)
    p("ge swaps", one >= two, two >= one)
    p("log", table.concat(log, ","))
    log = {}
    local ltonly = {__lt = function(a, b) log[#log + 1] = "lt" .. a.v .. b.v return a.v < b.v end}
    local x, y = setmetatable({v = 1}, ltonly), setmetatable({v = 2}, ltonly)
    p("le falls back to not lt", x <= y, y <= x, x <= x, x >= y)
    p("fallback log", table.concat(log, ","))
    local coerce = {__lt = function() return "yes" end, __le = function() return false end}
    local c1, c2 = setmetatable({}, coerce), setmetatable({}, coerce)
    p("result is a boolean", c1 < c2, c1 <= c2, c1 > c2)
    local other = {__lt = function() return true end, __le = function() return true end}
    local d = setmetatable({}, other)
    p("different handlers", pcall(function() return c1 < d end))
    p("mixed types", pcall(function() return one < 1 end))
    p("mixed types reversed", pcall(function() return 1 < one end))
    p("plain tables", pcall(function() return {} < {} end))
    p("plain tables le", pcall(function() return {} <= {} end))
    p("number and string", pcall(function() return 1 < O("2") end))
    p("strings", "a" < "b", "b" <= "a", "abc" < "abd", "" < "a", "a\0b" < "a\0c")
    p("numbers", 1 < 2, 2 <= 2, 0/0 < 1, 0/0 <= 0/0, -0.0 <= 0.0)
    local shared = function(a, b) return a.v < b.v end
    local s1 = setmetatable({v = 3}, {__lt = shared})
    local s2 = setmetatable({v = 4}, {__lt = shared})
    p("shared handler, two metatables", s1 < s2, s2 < s1, s1 <= s2)
    local failing = {__lt = function() error("lt failed", 0) end}
    p("errors propagate", pcall(function() return setmetatable({}, failing) < setmetatable({}, failing) end))
    local sorted = {}
    local imt = {__lt = function(a, b) return a.k < b.k end}
    for i = 1, 30 do sorted[i] = setmetatable({k = (i * 7) % 31}, imt) end
    table.sort(sorted)
    local keys = {}
    for i = 1, #sorted do keys[i] = sorted[i].k end
    p("table.sort uses __lt", table.concat(keys, " "))
    local count = 0
    for i = 1, 30 do
        for j = 1, 30 do
            if sorted[i] < sorted[j] then count = count + 1 end
            if sorted[i] <= sorted[j] then count = count + 1000 end
        end
    end
    p("hot loop", count)
    return done()
end

return M
