local _DYNAMIC_REQUIRES = "@requires-dynamically nothing"
-- Native representation work stays behind the checked Array and Span factories.
local ffiModule = table.concat({"f", "fi"})
local foreign = require(ffiModule)
foreign.cdef[[
void *malloc(size_t size);
void free(void *pointer);
void *memmove(void *destination, const void *source, size_t size);
]]
local M = {}
local limit = 9007199254740991
local nativeLimit = foreign.sizeof("size_t") == 4 and 4294967295 or limit

local function countOf(count)
    assert(
        type(count) == "number" and count >= 0 and count % 1 == 0 and count <= limit,
        "nupp: array count must be a non-negative integer"
    )

    return count
end

function M.row(element, layout, columns, index)
    local value = foreign.new(element)
    for ordinal, field in ipairs(layout.fields) do
        value[field.name] = columns[ordinal][index]
    end

    return value
end

function M.copyelements(destination, source, count)
    if count == 0 then
        return
    end
    local bytePointer = "const uint8_t *"
    local width = assert(tonumber(foreign.cast(bytePointer, source + 1) - foreign.cast(bytePointer, source)))
    assert(count <= nativeLimit / width, "nupp: array copy byte size is too large")
    foreign.C.memmove(destination, source, width * count)
end

function M.packed(element, count)
    countOf(count)
    local width = foreign.sizeof(element)
    assert(width > 0 and count <= nativeLimit / width, "nupp: array byte size is too large")
    local owner = foreign.C.malloc(math.max(1, width * count))
    assert(owner ~= nil, "nupp: array allocation failed")
    local pointerSpec = "$ *"

    return {pointer = foreign.cast(foreign.typeof(pointerSpec, element), owner), owner = owner, count = count}
end

function M.columns(element, count, layout)
    countOf(count)
    local instance = layout:forcount(count)
    local alignment = layout.alignment
    assert(instance.bytesize <= nativeLimit - alignment + 1, "nupp: aligned array byte size is too large")
    local owner = foreign.C.malloc(math.max(1, instance.bytesize + alignment - 1))
    assert(owner ~= nil, "nupp: array allocation failed")
    local addressType, bytePointer = "uintptr_t", "uint8_t *"
    local remainder = assert(tonumber(foreign.cast(addressType, owner) % alignment))
    local base = foreign.cast(bytePointer, owner) + (alignment - remainder) % alignment
    local columns = {}
    for ordinal, segment in ipairs(instance.segments) do
        columns[ordinal] = foreign.cast(segment.field.pointerType, base + segment.offset)
    end

    return {owner = owner, count = count, element = element, layout = layout, columns = columns}
end

function M.dispose(allocation)
    local owner = allocation.owner
    allocation.owner = nil
    allocation.pointer = nil
    allocation.columns = nil
    if owner ~= nil then
        foreign.C.free(owner)
    end
end

-- Worker tags preserve the existing scalar wire format. Managed and columnar
-- arrays are deliberately not movable through this packed-pointer protocol.
local tags, pointerTypes = {}, {}
for tag, element in ipairs({
    "uint8_t",
    "int8_t",
    "uint16_t",
    "int16_t",
    "uint32_t",
    "int32_t",
    "uint64_t",
    "int64_t",
    "float",
    "double"
}) do
    local pointerType = foreign.typeof(element .. " *")
    tags[tostring(pointerType)] = tag
    pointerTypes[tag] = pointerType
end
local boxSpec = "void *[1]"
local pointerBox = foreign.new(boxSpec)
local pointerSize = foreign.sizeof("void *")
function M.movable(value)
    if value.closed or value.storagekind ~= "packed" or not value.allocation or not value.allocation.owner then
        return nil
    end
    return tags[tostring(foreign.typeof(value.pointer))]
end

function M.parts(value)
    local tag = M.movable(value)
    if not tag then
        return nil
    end
    pointerBox[0] = value.pointer
    local bytes = foreign.string(pointerBox, pointerSize)
    value.allocation.owner = nil
    value.allocation.pointer = nil
    value.allocation = nil
    value.pointer = nil
    value.closed = true

    return bytes, value.count, tag
end

function M.fromparts(pointer, count, tag, metatable)
    local pointerType = pointerTypes[tag]
    if not pointerType or type(count) ~= "number" or count % 1 ~= 0 or count < 0 then
        return nil
    end
    local data = foreign.cast(pointerType, pointer)

    return setmetatable(
        {
            pointer = data,
            element = nil,
            descriptor = nil,
            columns = {},
            allocation = {owner = pointer, pointer = data, count = count},
            dispose = M.dispose,
            closed = false,
            count = count,
            storagekind = "packed",
            fingerprint = ""
        },
        metatable
    )
end

function M.freeparts(pointer)
    if type(pointer) == "string" then
        local boxType = "void * const *"
        pointer = foreign.cast(boxType, pointer)[0]
    end
    foreign.C.free(pointer)
end

return M
