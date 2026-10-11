-- Borrowed identity lookup. Keys are weak, values are numbers, and no caller
-- can recover an object from its identity. This retains no borrowed object.
local ids = setmetatable({}, {__mode = "k"})
local nextId = 0
return function(value)
    local kind = type(value)
    if kind ~= "table" and kind ~= "userdata" and kind ~= "cdata" then
        return nil
    end
    local id = ids[value]
    if id == nil then
        assert(nextId < 9007199254740991, "identity space exhausted")
        nextId = nextId + 1
        id = nextId
        ids[value] = id
    end

    return id
end
