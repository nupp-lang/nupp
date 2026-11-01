-- Match the JSON facade installed by tests/run.lua.
local native = require("serde.json")

local json = {
    NULL = native.NULL,
    EMPTY_ARRAY = native.EMPTY_ARRAY,
    EMPTY_OBJECT = native.EMPTY_OBJECT,
    arrayOf = native.arrayof,
    asArray = native.asarray,
    asObject = native.asobject,
    isArray = native.isarray,
    encode = native.encodevalue,
    newWriter = native.newwriter,
}

-- The facade answers a reason now; the runner's callers want a raise.
function json.decode(text)
    local value, reason = native.decodevalue(text, native.NULL)
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
