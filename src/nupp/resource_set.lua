local ResourceSet = {}
ResourceSet.__index = ResourceSet

local function new(label)
    return setmetatable({label = label or "resource", entries = {}, closed = false}, ResourceSet)
end

function ResourceSet:adopt(value, cleanup)
    assert(not self.closed, "resource set is closed")
    assert(type(cleanup) == "function", "resource adoption needs a discharge witness")
    self.entries[#self.entries + 1] = {value = value, cleanup = cleanup}
    return value
end

function ResourceSet:remove(value)
    assert(not self.closed, "resource set is closed")
    for index = #self.entries, 1, -1 do
        local entry = self.entries[index]
        if entry.value == value then
            table.remove(self.entries, index)
            return entry.value
        end
    end
    error("resource is not registered in this set", 2)
end

function ResourceSet:close()
    if self.closed then
        return
    end
    self.closed = true
    local first, suppressed = nil, {}
    for index = #self.entries, 1, -1 do
        local entry = self.entries[index]
        local ok, reason = pcall(entry.cleanup, entry.value)
        if not ok then
            if first == nil then
                first = reason
            else
                suppressed[#suppressed + 1] = reason
            end
        end
    end
    self.entries = {}
    if first ~= nil then
        if #suppressed > 0 then
            error(tostring(first) .. " (suppressed " .. tostring(#suppressed) .. " cleanup failure(s))", 0)
        end
        error(first, 0)
    end
end

return {new = new, ResourceSet = ResourceSet}
