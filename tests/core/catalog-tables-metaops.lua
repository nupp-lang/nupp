-- Lua twin of catalog-tables-metaops.nupp.

-- type(), and the metamethods of .., /, //, unary minus, tostring and calls,
-- each answering for a table that has one.
local P = {
    __concat = function(a, b)
        return "P" .. (a.x or 0) .. b
    end,
    __div = function(a, b)
        return (a.x or 0) * 100 + b
    end,
    __idiv = function(a, b)
        return (a.x or 0) * 1000 + b
    end,
    __unm = function(a)
        return 0 - (a.x or 0)
    end,
    __tostring = function(a)
        return "point" .. (a.x or 0)
    end,
    __call = function(self, n)
        return (self.x or 0) + n * 2
    end
}

local function helper(n)
    return n
end

local p = setmetatable({x = 7}, P)
local score = 0
if p .. "!" == "P7!" then
    score = score + 1
end
if p / 3 == 703 then
    score = score + 10
end
if p // 4 == 7004 then
    score = score + 100
end
if -p == -7 then
    score = score + 1000
end
if tostring(p) == "point7" then
    score = score + 10000
end
local callable = p
if callable(5) == 17 then
    score = score + 100000
end
if type(p) == "table" and type(1) == "number" and type("a") == "string" and type(nil) == "nil" then
    score = score + 1000000
end
if type(true) == "boolean" and type(helper) == "function" and type(1.5) == "number" then
    score = score + 10000000
end
return score + helper(0)
