local core = require("nupp.serde.value")
local json = require("nupp.serde.json")
local model = require("example.richmodel")

local codec = json.codec(model.policy(true), 2)
local weak = setmetatable({}, {__mode = "k"})

local function populate()
    local binding = model.binding(model.newModel())
    weak[binding.adapter] = true
    codec:decode(binding, '{"identifier":"temporary","created":0}')
end

populate()
collectgarbage("collect")
assert(next(weak) ~= nil, "the codec did not retain its warm adapter")
codec:clear()
collectgarbage("collect")
collectgarbage("collect")
assert(next(weak) == nil, "cleared codec state retained the adapter")

local binding = model.binding(model.newModel())
local source = binding.adapter
local calls = 0
local recursive
local adapter = {
    describe = function(_, direction)
        calls = calls + 1
        codec:decode(recursive, '{"identifier":"recursive","created":0}')
        return source:describe(direction)
    end,
    read = function(_, reader)
        return source:read(reader)
    end,
    write = function(_, value, writer)
        source:write(value, writer)
    end,
}
recursive = setmetatable({adapter = adapter}, core.Bound)
for _ = 1, 2 do
    local ok, problem = pcall(codec.decode, codec, recursive, '{}')
    assert(not ok and tostring(problem):find("recursive JSON extension initialization", 1, true))
end
assert(calls == 1, "recursive initialization was retried")
codec:clear()
print("codec caches release their adapters and refuse recursive initialization")

-- Reusing the binding executes its selected operations without re-entering the
-- generic consumer or probing the extension table on every value.
local extensions = require("nupp.serde.jsonextensions")
local scopeType = getmetatable(extensions.scope(model.policy(true), 2))
local resolve = scopeType.resolve
local resolutions, selections = 0, 0
scopeType.resolve = function(self, ...)
    resolutions = resolutions + 1
    return resolve(self, ...)
end
local tracked = {
    accept = function(_, consumer, state)
        selections = selections + 1
        return consumer:apply(binding.adapter, state)
    end,
}
local warm = json.codec(model.policy(true), 2)
for _ = 1, 10 do
    local value = warm:decode(tracked, '{"identifier":"warm","created":0}')
    assert(warm:encode(tracked, value) == '{"identifier":"warm","created":0}')
end
scopeType.resolve = resolve
assert(selections == 2 and resolutions == 2, "a warm operation repeated binding or extension selection")
warm:clear()

local nested = model.binding(model.newModel())
local active = false
local reentrant = setmetatable(
    {
        adapter = {
            describe = function(_, direction)
                return source:describe(direction)
            end,
            read = function(_, reader)
                if not active then
                    active = true
                    local value = warm:decode(nested, '{"identifier":"inner","created":0}')
                    assert(warm:encode(nested, value) == '{"identifier":"inner","created":0}')
                    active = false
                end

                return source:read(reader)
            end,
            write = function(_, value, writer)
                if not active then
                    active = true
                    local inner = warm:decode(nested, '{"identifier":"inner","created":0}')
                    assert(warm:encode(nested, inner) == '{"identifier":"inner","created":0}')
                    active = false
                end
                source:write(value, writer)
            end,
        }
    },
    core.Bound
)
local outer = warm:decode(reentrant, '{"identifier":"outer","created":0}')
assert(warm:encode(reentrant, outer) == '{"identifier":"outer","created":0}')
