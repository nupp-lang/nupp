local core = require("contract.value")
local json = require("contract.jsoncodec")

local function bind(adapter)
    return setmetatable({adapter = adapter}, core.Bound)
end

local member = {name = "amount"}
local description = {kind = "decimal", member = member, nullable = false, canRead = true, children = {}}
local adapter = {
    describe = function()
        return description
    end,
    read = function(_, reader)
        return reader:readDecimal(member)
    end,
    write = function(_, value, writer)
        writer:writeDecimal(member, value)
    end,
}
local binding = bind(adapter)
local factory = {
    policy = function()
        return {}
    end
}
for _, case in ipairs({
    {"0.001", "1e-3"},
    {"-0.001", "-1e-3"},
    {"0.000", "0e-3"},
    {"-0.00", "-0e-2"},
    {"1.00", "100e-2"},
    {"1e-2147483648", "1e-2147483648"},
    {"1e2147483647", "1e2147483647"},
}) do
    local value = json.decode(binding, case[1], factory)
    assert(json.encode(binding, value, factory) == case[2])
end
for _, bytes in ipairs({"1e-2147483649", "1e2147483648", "0.1e-2147483648"}) do
    assert(not pcall(json.decode, binding, bytes, factory))
end

-- A decoder owns the root reader token. Even an untyped adapter that keeps it
-- cannot use the view after success, a model error, or trailing-input failure.
for _, mode in ipairs({"success", "model-error", "trailing"}) do
    local retained
    local capturing = bind({
        describe = adapter.describe,
        write = adapter.write,
        read = function(_, reader)
            retained = reader
            if mode == "model-error" then
                error("model error", 0)
            end

            return adapter:read(reader)
        end,
    })
    local ok, problem = pcall(json.decode, capturing, mode == "trailing" and "1 2" or "1", factory)
    assert(ok == (mode == "success"), tostring(problem))
    local live, expired = pcall(retained.context, retained)
    assert(not live and tostring(expired):find("expired", 1, true), tostring(expired))
end
print("exact decimal normalization and root reader lifetimes passed")
