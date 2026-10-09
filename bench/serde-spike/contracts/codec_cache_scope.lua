local core = require("contract.value")
local json = require("contract.jsoncodec")
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
