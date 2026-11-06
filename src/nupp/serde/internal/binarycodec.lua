local _DYNAMIC_REQUIRES = "@requires-dynamically nothing"
-- Private LuaJIT binary serialization. Public buffers do not serialize values.
-- Keep the established wire format and per-channel metatable dictionaries.
local moduleName = table.concat({"string", "buffer"}, ".")
local native = require(moduleName)
local M = {encode = native.encode, decode = native.decode}

function M.new(options)
    local codec = native.new(options)
    return {
        encode = function(_, value)
            codec:reset()
            codec:encode(value)
            return codec:get()
        end,
        decode = function(_, bytes)
            codec:set(bytes)
            local value = codec:decode()
            if #codec ~= 0 then
                error("trailing bytes after a binary value", 2)
            end

            return value
        end,
    }
end

return M
