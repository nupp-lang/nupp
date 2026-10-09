local core = require("nupp.serde.value")
local debug = require("nupp.serde.debug")
local identity = require("nupp.serde.identity")
local renderer = debug.renderer(2)
local weak = setmetatable({}, {__mode = "k"})
local calls = 0

local function binding(kind)
    local member = {name = "root"}
    local adapter = {
        describe = function()
            calls = calls + 1
            return {member = member, kind = kind or "string", nullable = false, children = {}}
        end,
        write = function(_, value, writer)
            writer:writeString(member, value)
        end,
    }
    weak[adapter] = true

    return setmetatable({adapter = adapter}, core.Bound)
end

local first = binding()
assert(renderer:render(first, "a") == '"a"')
assert(renderer:render(first, "b") == '"b"' and calls == 1)
local failed = binding("opaque")
for _ = 1, 2 do
    assert(not pcall(renderer.render, renderer, failed, "c"))
end
assert(calls == 2)
renderer:render(binding(), "d")
assert(renderer:cachedBindings() == 2)
renderer:render(first, "e")
assert(calls == 4, "least recently used extension was not evicted")
first, failed = nil, nil
renderer:clear()
collectgarbage("collect")
collectgarbage("collect")
assert(next(weak) == nil, "Debug cache retained cleared adapters")
local recursive
local member = {name = "root"}
recursive = setmetatable(
    {
        adapter = {
            describe = function()
                assert(not pcall(renderer.clear, renderer))
                renderer:render(recursive, "nested")
            end,
        }
    },
    core.Bound
)
for _ = 1, 2 do
    local ok, err = pcall(renderer.render, renderer, recursive, "outer")
    assert(not ok and tostring(err):find("recursive Debug extension initialization", 1, true))
end

local function borrow()
    local value = {}
    weak[value] = true
    assert(identity(value) == identity(value))
end

borrow()
collectgarbage("collect")
collectgarbage("collect")
assert(next(weak) == nil, "identity tracking retained a borrowed value")
print("Debug schema extensions cache failures, evict, clear, and retain no values")
