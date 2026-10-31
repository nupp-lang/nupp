-- Match the JSON facade installed by tests/run.lua.
local native = require("serde.json")

local json = {
    NULL = native.NULL,
    EMPTY_ARRAY = native.EMPTY_ARRAY,
    EMPTY_OBJECT = native.EMPTY_OBJECT,
    arrayOf = native.arrayOf,
    asArray = native.asArray,
    asObject = native.asObject,
    isArray = native.isArray,
    encode = native.encodeValue,
    newWriter = native.newWriter,
}

-- The facade answers a reason now; the runner's callers want a raise.
function json.decode(text)
    local value, reason = native.decodeValue(text, native.NULL)
    if reason ~= nil then
        error(reason, 2)
    end

    return value
end

function json.pull(text, shape)
    local value, reason = native.pull(text, shape, native.NULL)
    if reason ~= nil then
        error(reason, 2)
    end

    return value
end

return json
