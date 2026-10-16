local mmout = require("mmout")
local O = mmout.opaque
local M = {}

-- Metamethods LuaJIT 2.1 does not consult on tables: `__gc` (ownership and
-- `with` are the close path in Nupp), `__close`, `__idiv`, the bitwise ones
-- and `__name`. Setting them changes nothing.
function M.main()
    local p, done = mmout.new()
    local collected = 0
    for _ = 1, 10 do
        setmetatable({}, {__gc = function() collected = collected + 1 end})
    end
    collectgarbage()
    collectgarbage()
    p("__gc", collected)
    local closed = 0
    do
        local t = setmetatable({}, O({__close = function() closed = closed + 1 end}))
        local _ = t
    end
    p("__close", closed)
    local named = setmetatable({}, O({__name = "Thing"}))
    p("__name", (tostring(named):match("^table: ") ~= nil))
    local bits = setmetatable({}, O({__band = function() return 1 end, __idiv = function() return 2 end}))
    p("bitwise and idiv fields are plain fields", type(O(getmetatable(bits)).__band), type(O(getmetatable(bits)).__idiv))
    return done()
end

return M
