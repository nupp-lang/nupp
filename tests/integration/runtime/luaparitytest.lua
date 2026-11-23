-- Lua 5.5 behaviors a plain chunk keeps on every runtime: a goto that ends an
-- outer loop's iteration, and table.pack and table.unpack.
local test = require("assert")
local M = {}

local function three()
    return 1, 2, 3
end

function M.aGotoEndsTheIterationOfTheLoopWhoseBodyItsLabelEnds()
    local seen = {}
    for row = 1, 3 do
        local column = 0
        while true do
            column = column + 1
            if column > row then
                goto nextrow
            end
            seen[#seen + 1] = row .. ":" .. column
        end
        ::nextrow::
    end
    test.eq(table.concat(seen, " "), "1:1 2:1 2:2 3:1 3:2 3:3")

    local kept = {}
    for _, word in ipairs({"a", "", "b"}) do
        for _, letter in ipairs({"x", "y"}) do
            if word == "" then
                goto continue
            end
            if letter == "y" then
                goto inner
            end
            kept[#kept + 1] = word .. letter
            ::inner::
        end
        ::continue::
    end
    test.eq(table.concat(kept, " "), "ax bx")
end

function M.tablePackCountsItsValuesNilsIncluded()
    local packed = table.pack(1, nil, 3)
    test.eq(packed.n, 3)
    test.eq(packed[1], 1)
    test.eq(packed[2], nil)
    test.eq(packed[3], 3)
    test.eq(table.pack().n, 0)
    test.eq(table.pack(three()).n, 3)
    test.eq(table.pack(0, three())[4], 3)

    local function packs(...)
        return table.pack(...)
    end

    test.eq(packs(nil, nil).n, 2)
    local pack = table.pack
    test.eq(type(pack), "function")
    test.eq(pack("a", "b").n, 2)
    test.eq(select(2, pcall(table.pack, 7)).n, 1)
end

function M.tableUnpackGivesItsRange()
    test.eq(select("#", table.unpack({1, 2, 3})), 3)
    test.eq(select("#", table.unpack({1, nil, 3}, 1, 3)), 3)
    local b, c = table.unpack({1, 2, 3}, 2)
    test.eq(b, 2)
    test.eq(c, 3)
    test.eq(select("#", table.unpack({1, 2, 3}, 3, 2)), 0)
    local packed = table.pack(three())
    test.eq(select(3, table.unpack(packed, 1, packed.n)), 3)
end

return M
