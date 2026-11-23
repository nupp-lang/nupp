-- Lua 5.5 behaviors a plain chunk keeps on every runtime: a goto that ends an
-- outer loop's iteration.
local test = require("assert")
local M = {}

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

return M
