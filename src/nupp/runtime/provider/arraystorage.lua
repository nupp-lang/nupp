-- Managed arrays retain storage owners instead of native malloc pointers.
local _DYNAMIC_REQUIRES = "@requires-dynamically nupp.runtime.storage"
local storageModule = table.concat({"nupp", "runtime", "storage"}, ".")
local physical = require(storageModule)
local M = {}
local MAX_EXACT_INTEGER = 9007199254740991

local function countOf(count)
    assert(
        type(count) == "number" and count >= 0 and count % 1 == 0 and count <= MAX_EXACT_INTEGER,
        "nupp: array count must be a non-negative integer"
    )

    return count
end

function M.row(element, layout, columns, index)
    local value = element()
    for ordinal, field in ipairs(layout.fields) do
        value[field.name] = columns[ordinal][index]
    end

    return value
end

function M.copyelements(destination, source, count)
    countOf(count)
    if count == 0 then
        return
    end
    local descriptor = physical.descriptor(source)
    local element = descriptor.element or descriptor
    local width = physical.sizeOf(element)
    assert(width > 0 and count <= MAX_EXACT_INTEGER / width, "nupp: array copy byte size is too large")
    physical.copy(destination, source, count * width)
end

function M.packed(element, count)
    countOf(count)
    local width = physical.sizeOf(element)
    assert(width > 0 and count <= MAX_EXACT_INTEGER / width, "nupp: array byte size is too large")
    local pointer = physical.allocateArray(element, count)

    return {pointer = pointer, owner = pointer, count = count}
end

function M.columns(element, count, layout)
    countOf(count)
    -- Validate the same reflected layout without depending on native addresses.
    layout:forcount(count)
    local types = {}
    for _, field in ipairs(element.fields or {}) do
        types[field.name] = field.type
    end
    local columns = {}
    for ordinal, field in ipairs(layout.fields) do
        local descriptor = assert(types[field.name], "nupp: array column has no managed storage type")
        assert(physical.sizeOf(descriptor) == field.elementsize, "nupp: array column storage width differs")
        columns[ordinal] = physical.allocateArray(descriptor, count)
    end

    return {owner = columns, count = count, element = element, layout = layout, columns = columns}
end

function M.dispose(allocation)
    -- Dropping the final graph edge releases each managed owner through GC.
    allocation.owner = nil
    allocation.pointer = nil
    allocation.columns = nil
end

-- The native worker hook transfers malloc addresses. VM workers transport the
-- owner graph, so VM arrays never opt into that native pointer protocol.
function M.movable(value)
    return nil
end

function M.parts(value)
    return nil
end

function M.fromparts(pointer, count, tag, metatable)
    error("nupp: the VM cannot import a native array pointer", 2)
end

function M.freeparts(pointer)
    error("nupp: the VM cannot free a native array pointer", 2)
end

return M
