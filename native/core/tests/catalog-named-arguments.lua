-- Lua twin of catalog-named-arguments.nupp, as main emits its calls: the
-- positional list the checker bound the named arguments to, nil where a
-- parameter is skipped.
local Table = {}
Table.__index = Table

function Table.column(self, heading, align, paint, minimumwidth)
    local width = minimumwidth or #heading
    self.widths[#self.widths + 1] = width * 10 + (align == nil and 1 or 0) + (paint == nil and 2 or 0)
    return self
end

local function combine(a, b, c, d)
    return a + (b or 0) * 10 + (c or 0) * 100 + (d or 0) * 1000
end

local t = setmetatable({widths = {}}, Table)
t:column("level", nil, nil, 7):column("ab"):column("x", "left", nil, 4)

return combine(1, nil, 3) + combine(2, 5, nil, 9) * 1000
    + (t.widths[1] + t.widths[2] + t.widths[3]) * 100000000
