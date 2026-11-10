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

-- Decodes the first value in a borrowed byte range and reports how many bytes it
-- took, so a caller can consume exactly one value from a larger stream. The
-- scratch buffer only references the range, and is cleared before returning.
local scratch = native.new()
function M.decodeprefix(pointer, length)
    if length == 0 then
        error("no binary value in an empty input", 2)
    end
    scratch:set(pointer, length)
    local ok, value = pcall(scratch.decode, scratch)
    local remaining = #scratch
    scratch:reset()
    if not ok then
        error(value, 2)
    end

    return value, length - remaining
end

return M
