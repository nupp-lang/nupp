local mmout = require("mmout")
local O = mmout.opaque
local M = {}

function M.main()
    local p, done = mmout.new()
    local log = {}
    local store = {}
    local proxy = setmetatable({existing = 1}, {
        __newindex = function(t, k, v) log[#log + 1] = tostring(k) .. "=" .. tostring(v) rawset(store, k, v) end,
        __index = store,
    })
    proxy.a = 1
    proxy[2] = "two"
    proxy.existing = 5
    p("function handler", table.concat(log, ","), rawget(proxy, "a"), proxy.a, proxy[2], proxy.existing)
    proxy.a = 10
    p("absent from the table, so the handler again", table.concat(log, ","), store.a)
    local target = {}
    local redirect = setmetatable({}, {__newindex = target})
    redirect.x = 1
    redirect.y = 2
    p("table handler", rawget(redirect, "x"), target.x, target.y)
    local inner = {}
    local mid = setmetatable({}, {__newindex = inner})
    local outer = setmetatable({}, {__newindex = mid})
    outer.k = "v"
    p("chain", rawget(outer, "k"), rawget(mid, "k"), inner.k)
    local ro = setmetatable({}, {__newindex = function(_, k) error("read-only: " .. k, 0) end})
    p("errors propagate", pcall(function() ro.x = 1 end))
    rawset(ro, "x", 2)
    p("rawset bypasses", ro.x)
    local counter = 0
    local counting = setmetatable({}, {__newindex = function(t, k, v) counter = counter + 1 rawset(t, k, v) end})
    for i = 1, 100 do counting[i] = i end
    for i = 1, 100 do counting[i] = i * 2 end
    p("hot loop", counter, counting[100])
    local mt = {}
    local later = setmetatable({}, mt)
    later.a = 1
    mt.__newindex = function() end
    later.b = 2
    later.a = 3
    p("handler added later", later.a, rawget(later, "b"))
    local deleted = setmetatable({gone = 1}, {__newindex = function(t, k, v) rawset(t, k, "via handler") end})
    deleted.gone = nil
    deleted.gone = 2
    p("key removed then written", deleted.gone)
    p("assign to nil", pcall(function() O(nil).y = 1 end))
    local Class = {}
    Class.__index = Class
    Class.__newindex = function(t, k, v) rawset(t, k, type(v)) end
    local inst = setmetatable({}, Class)
    inst.n = 3
    inst.s = "x"
    p("class newindex", inst.n, inst.s)
    return done()
end

return M
