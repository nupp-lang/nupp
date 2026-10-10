local bridge = require("nupp.serde.internal.documentcodec")
local model = require("example.richmodel")
local json = require("nupp.serde.json")
bridge.clear()
local binding = model.binding(model.newModel())
local value = json.codec(model.policy(true)):decode(binding, '{"identifier":"cached","created":0}')
local document = bridge.fromBinding(binding, value)
local selections = 0
local wrapped = {
    accept = function(_, consumer, state)
        selections = selections + 1
        return binding:accept(consumer, state)
    end,
    discard = function(_, value)
        return binding:discard(value)
    end,
}
for _ = 1, 5 do
    assert(bridge.into(wrapped, document).id == "cached")
end
assert(selections == 1 and bridge.cachedBindings() == 1)
local decoder = bridge.decoder(wrapped)
bridge.clear()
assert(decoder:read(document).id == "cached")
local recursive, attempts
attempts = 0
recursive = {
    accept = function()
        attempts = attempts + 1
        bridge.decoder(recursive)
    end,
}
for _ = 1, 2 do
    local ok, problem = pcall(bridge.decoder, recursive)
    assert(not ok and tostring(problem):find("recursive", 1, true))
end
assert(attempts == 1)
bridge.clear()
local weak = setmetatable({}, {__mode = "k"})

local function populate()
    local temporary = model.binding(model.newModel())
    weak[temporary.adapter] = true
    bridge.decoder(temporary)
end

populate()
collectgarbage("collect")
assert(next(weak) ~= nil)
bridge.clear()
collectgarbage("collect")
collectgarbage("collect")
assert(next(weak) == nil)
for _ = 1, 270 do
    bridge.decoder(model.binding(model.newModel()))
    assert(bridge.cachedBindings() <= 256)
end
bridge.clear()

local attemptsToClear = 0
local clearing = {
    accept = function()
        attemptsToClear = attemptsToClear + 1
        bridge.clear()
    end
}
for _ = 1, 2 do
    local ok, problem = pcall(bridge.decoder, clearing)
    assert(not ok and tostring(problem):find("initializing", 1, true))
end
assert(attemptsToClear == 1)
bridge.clear()
local ready = bridge.decoder(binding)
local documents = require("nupp.serde.internal.document")
assert(not pcall(ready.read, ready, documents.null()))
assert(ready:read(document).id == "cached")
bridge.clear()
