-- reference: lua
local mmout = require("mmout")
local O = mmout.opaque
local M = {}

-- `__pairs` is Lua 5.2's (LuaJIT's 5.2 compatibility build); the VM honors it
-- without a flag.
function M.main()
    local p, done = mmout.new()
    local backing = {"a", "b", "c"}
    local proxy = setmetatable({}, {__pairs = function(t)
        return function(_, k)
            local i = (k or 0) + 1
            if backing[O(i)] then return i, backing[O(i)] end
        end, t, nil
    end})
    local seen = {}
    for k, v in pairs(proxy) do seen[#seen + 1] = k .. "=" .. v end
    p("handler", table.concat(seen, ","))
    local args = {}
    local probe = setmetatable({}, {__pairs = function(t) args[#args + 1] = tostring(t == args.self) return next, {x = 1}, nil end})
    args.self = probe
    for k, v in pairs(probe) do p("next over another table", k, v) end
    p("handler arguments", table.concat(args, ","))
    local plain = setmetatable({k = "v"}, {})
    for k, v in pairs(plain) do p("no handler", k, v) end
    local mt = {}
    local late = setmetatable({z = 1}, mt)
    mt.__pairs = function() return function() end, nil, nil end
    local n = 0
    for _ in pairs(late) do n = n + 1 end
    p("added later", n)
    local triple = setmetatable({}, {__pairs = function() return function(s, c) if c < 3 then return c + 1, s end end, "s", 0 end})
    for k, v in pairs(triple) do p("state and control", k, v) end
    p("errors propagate", pcall(function() for _ in pairs(setmetatable({}, {__pairs = function() error("pairs failed", 0) end})) do end end))
    local counted = 0
    local cheap = setmetatable({}, {__pairs = function() counted = counted + 1 return function() end, nil, nil end})
    for _ = 1, 100 do for _ in pairs(cheap) do end end
    p("hot loop", counted)
    local listed = setmetatable({1, 2, 3}, {__pairs = function() return function() end end})
    local m = 0
    for _ in ipairs(listed) do m = m + 1 end
    p("ipairs stays raw", m)
    return done()
end

return M
