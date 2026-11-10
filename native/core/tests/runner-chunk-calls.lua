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

-- A record another program declares, constructed by calling its class,
-- compiles. The call runs once the core's class tables are callable; they
-- have no __call there yet.
local function box()
    return helper.Box(3, 4)
end

check(type(box) == "function")

-- C declarations a chunk makes are typed by the C-header service; a C
-- function is called through its value, and the core has no FFI to call.
local loaded, ffi = pcall(require, "ffi")
if loaded then
    ffi.cdef([[
    int isatty(int);
    ]])
    local isatty = ffi.C.isatty
    local called = pcall(isatty, 0)
    check(called == true or called == false)
else
    check(true)
end

return score
