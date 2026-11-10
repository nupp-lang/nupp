-- Lua twin of catalog-records-affine-errors.nupp: the destructor calls Nupp
-- makes, on the error paths too, written out.
local closed = 0
local order = 0

local function destroy(self)
    closed = closed + 1
    order = order * 10 + self.id
end

local function risky(n)
    if n > 2 then
        error("boom")
    end
    return n
end

local function guarded(n)
    local f = {id = n}
    local ok, r = pcall(risky, n)
    if not ok then
        destroy(f)
        error(r, 0)
    end
    local result = r + f.id
    destroy(f)

    return result
end

local function nested(n)
    local outer = {id = 7}
    local ok, r = pcall(guarded, n)
    if not ok then
        destroy(outer)
        error(r, 0)
    end
    destroy(outer)

    return r
end

local ok1 = pcall(guarded, 1)
local ok2 = pcall(guarded, 5)
local ok3 = pcall(nested, 9)
local score = closed * 1000000 + order
if ok1 and not ok2 and not ok3 then
    score = score + 100000000
end
return score
