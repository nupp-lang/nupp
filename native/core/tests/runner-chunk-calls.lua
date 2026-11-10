-- Calls the test runner's suites make that Lua allows and the checker
-- passes in a plain Lua chunk. Each check is a bit of the score.
local helper = require("nupp.core.catalogrunnerhelper")

local score, bit = 0, 1

local function check(ok)
    if ok then
        score = score | bit
    end
    bit = bit << 1
end

-- More arguments than a function's parameters: Lua drops the rest.
local function sum(a, b)
    return (a or 0) + (b or 0)
end

check(sum(1, 2, 3) == 3)
check(helper.double(4, "extra") == 8)

return score
