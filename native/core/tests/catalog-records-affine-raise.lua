-- Lua twin of catalog-records-affine-raise.nupp: the destructor calls Nupp
-- makes, on the error paths too, written out.
local closed = 0
local order = 0

local function destroy(self)
    closed = closed + 1
    order = order * 10 + self.id
end

local function raising(n)
    local f = {id = n}
    local ok, r = pcall(function()
        if n > 2 then
            error("too big", 3)
        end
        return f.id
    end)
    destroy(f)
    if not ok then
        error(r, 0)
    end
    return r
end

local function libraryraising(code)
    local g = {id = 4}
    local ok, r = pcall(function()
        return string.char(code) .. tostring(g.id)
    end)
    destroy(g)
    if not ok then
        error(r, 0)
    end
    return r
end

local ok1, e1 = pcall(raising, 1)
local ok2, e2 = pcall(raising, 5)
local ok3, e3 = pcall(libraryraising, 300)
local score = closed * 1000 + order
if ok1 and e1 == 1 and not ok2 and not ok3 then
    score = score + 10000
end
if string.find(tostring(e2), "too big") ~= nil and string.find(tostring(e3), "out of range") ~= nil then
    score = score + 20000
end
local function leaving()
    local f <close> = setmetatable({}, {__close = function()
        error("faulty", 0)
    end})
    return 1
end

local ok4, e4 = pcall(leaving)
if not ok4 and e4 == "faulty" then
    score = score + 40000
end

local function resuming()
    local f <close> = setmetatable({id = 6}, {__close = function(self)
        destroy(self)
    end})
    local inner = coroutine.wrap(function()
        if f.id > 0 then
            error("inside", 0)
        end
        return 0
    end)
    return inner()
end

local before = closed
local ok5, e5 = pcall(resuming)
if not ok5 and string.find(tostring(e5), "inside") ~= nil and closed == before + 1 then
    score = score + 80000
end
return score
