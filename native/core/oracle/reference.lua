-- Reference-side observation encoder. This is not part of the guest program.
assert(_VERSION == "Lua 5.5", "reference requires Lua 5.5")
assert(math.maxinteger == 9223372036854775807, "reference requires signed 64-bit integers")

local function scalar(value)
    local kind = type(value)
    if kind == "nil" then
        return "N;"
    end
    if kind == "boolean" then
        return value and "B1;" or "B0;"
    end
    if kind == "number" then
        assert(math.type(value) == "integer", "unsupported observation: float")
        return "I" .. string.format("%d", value) .. ";"
    end
    if kind == "string" then
        local bytes = {}
        for i = 1, #value do
            bytes[i] = string.format("%02x", string.byte(value, i))
        end
        return "S" .. #value .. ":" .. table.concat(bytes) .. ";"
    end
    error("unsupported observation type: " .. kind)
end

local ranks = {boolean = 1, number = 2, string = 3}
local active, nodes = {}, 0

local function encode(value, depth)
    nodes = nodes + 1
    assert(nodes <= 4096 and depth <= 16, "observation extent exceeded")
    if type(value) ~= "table" then
        return scalar(value)
    end
    assert(getmetatable(value) == nil, "unsupported observation: metatable")
    assert(not active[value], "unsupported observation: cycle")
    active[value] = true
    local keys = {}
    for key in next, value do
        assert(ranks[type(key)], "unsupported table key type")
        scalar(key)
        keys[#keys + 1] = key
    end
    table.sort(keys, function(a, b)
        local x, y = ranks[type(a)], ranks[type(b)]
        if x ~= y then
            return x < y
        end
        if x == 1 then
            return not a and b
        end

        return a < b
    end)
    local parts = {"T" .. #keys .. ":{"}
    for _, key in ipairs(keys) do
        parts[#parts + 1] = scalar(key)
        parts[#parts + 1] = encode(rawget(value, key), depth + 1)
    end
    parts[#parts + 1] = "}"
    active[value] = nil

    return table.concat(parts)
end

local chunk = assert(loadfile(assert(arg[1]), "t", {}))
local values = table.pack(chunk())
local parts = {"R" .. values.n .. ":"}
for i = 1, values.n do
    parts[#parts + 1] = encode(values[i], 0)
end
local bytes = table.concat(parts) .. "\n"
assert(#bytes <= 1048576, "observation byte extent exceeded")
local file = assert(io.open(assert(arg[2]), "wb"))
assert(file:write(bytes))
assert(file:close())
