local _DYNAMIC_REQUIRES = "@requires-dynamically nothing"
-- Private native storage for io.Buffer. Other hosts use the checked fallback.
local ok, native = pcall(require, table.concat({"string", "buffer"}, "."))
if not ok then
    return {}
end
local ffi = require("ffi")
local M = {new = native.new}
function M.finish(buffer)
    local text = buffer:tostring()
    buffer:free()
    return text
end

function M.base(buffer)
    local pointerSpec = "uint8_t *"
    return ffi.cast(pointerSpec, (buffer:ref()))
end

local function slowPut(buffer, ...)
    local simple = true
    for i = 1, select("#", ...) do
        local kind = type(select(i, ...))
        if kind ~= "string" and kind ~= "number" then
            simple = false;
            break
        end
    end
    if simple then
        buffer:put(...)
    else
        for i = 1, select("#", ...) do
            local value = select(i, ...)
            local kind = type(value)
            if kind == "string" or kind == "number" then
                buffer:put(value)
            elseif value.tostring then
                buffer:put(value:tostring())
            else
                local pointer, count = value:ref()
                buffer:putcdata(pointer, count)
            end
        end
    end

    return #buffer
end

local function simple(value)
    local kind = type(value)
    return kind == "string" or kind == "number"
end

-- Fixed argument reads keep the append path recordable by LuaJIT.
local function put(buffer, ...)
    local count = select("#", ...)
    local a, b, c, d, e, f, g, h = ...
    if count == 1 and simple(a) then
        buffer:put(a)
    elseif count == 2 and simple(a) and simple(b) then
        buffer:put(a, b)
    elseif count == 3 and simple(a) and simple(b) and simple(c) then
        buffer:put(a, b, c)
    elseif count == 4 and simple(a) and simple(b) and simple(c) and simple(d) then
        buffer:put(a, b, c, d)
    elseif count == 5 and simple(a) and simple(b) and simple(c) and simple(d) and simple(e) then
        buffer:put(a, b, c, d, e)
    elseif count == 6 and simple(a) and simple(b) and simple(c) and simple(d) and simple(e) and simple(f) then
        buffer:put(a, b, c, d, e, f)
    elseif count == 7
        and simple(a)
        and simple(b)
        and simple(c)
        and simple(d)
        and simple(e)
        and simple(f)
        and simple(g)
    then
        buffer:put(a, b, c, d, e, f, g)
    elseif count == 8
        and simple(a)
        and simple(b)
        and simple(c)
        and simple(d)
        and simple(e)
        and simple(f)
        and simple(g)
        and simple(h)
    then
        buffer:put(a, b, c, d, e, f, g, h)
    else
        return slowPut(buffer, ...)
    end

    return #buffer
end

M.put = put

function M.bind(state)
    local buffer = state._native
    return function(self, ...)
        if state._closed then
            error("nupp: io.Buffer is closed", 2)
        end
        state._length = put(buffer, ...)

        return self
    end
end

return M
