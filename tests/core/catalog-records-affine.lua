-- Lua twin of catalog-records-affine.nupp: the destructor calls Nupp makes
-- at scope exit, written out (latest declared first).
local closed = 0
local order = 0

local function destroy(self)
    closed = closed + 1
    order = order * 10 + self.id
end

do
    local a = {id = 1}
    local b = {id = 2}
    destroy(b)
    destroy(a)
end

local function scoped(n)
    local f = {id = n}
    local result = f.id * 2
    destroy(f)
    return result
end

local doubled = scoped(3)
return closed * 10000 + order * 10 + doubled
