-- Bridge the frozen checker's field specification to table.Array's layout API.
local _DYNAMIC_REQUIRES = "@requires-dynamically nupp.array"
local arrayModule = table.concat({"nupp", "array"}, ".")
local array = require(arrayModule)
local M = {}
local MAX_FIELD_ALIGNMENT = 8

local function facts(raw, element)
    if type(element) ~= "table" or element.kind ~= "struct" then
        error("nupp: SoA storage needs a struct with a supported storage layout", 3)
    end
    assert(
        type(raw) == "table" and type(raw.name) == "string" and type(raw.spec) == "string",
        "nupp: invalid VM array layout specification"
    )
    local members = assert(element.fields, "nupp: VM array storage descriptor has no fields")
    local fields = {}
    local ordinal = 0
    local consumed = 0
    for fieldName, ctype in raw.spec:gmatch("([^:,]+):([^,]+)") do
        ordinal = ordinal + 1
        local member = members[ordinal]
        if member == nil or member.name ~= fieldName then
            error("nupp: SoA layout of " .. raw.name .. " does not match its storage descriptor", 3)
        end
        local fieldType = assert(member.type, "nupp: VM array field has no storage type")
        local alignment = fieldType.alignment
        local size = fieldType.size
        if type(alignment) ~= "number" or alignment < 1 or alignment % 1 ~= 0 then
            error("nupp: SoA field " .. fieldName .. " has invalid storage alignment", 3)
        end
        if alignment > MAX_FIELD_ALIGNMENT then
            error("nupp: SoA field " .. fieldName .. " needs more than " .. MAX_FIELD_ALIGNMENT .. "-byte alignment", 3)
        end
        if type(size) ~= "number" or size <= 0 or size % 1 ~= 0 then
            error("nupp: SoA field " .. fieldName .. " has invalid storage width", 3)
        end
        fields[
            ordinal
        ] = {
            name = fieldName,
            ctype = ctype:sub(1, 1) == "$" and ctype:sub(2) or ctype,
            size = size,
            alignment = alignment,
            pointerType = fieldType
        }
        consumed = consumed + #fieldName + 1 + #ctype + (ordinal > 1 and 1 or 0)
    end
    if ordinal ~= #members or consumed ~= #raw.spec then
        error("nupp: SoA layout of " .. raw.name .. " does not match its storage descriptor", 3)
    end

    return {name = raw.name, fields = fields}
end

function M.layout(rawSpec, element)
    return array._layout(facts(rawSpec, element))
end

function M.allocate(element, count, rawSpec)
    -- Main's storage adapter checks count-dependent layout and overflow.
    return array._allocateColumns(element, count, facts(rawSpec, element))
end

return M
