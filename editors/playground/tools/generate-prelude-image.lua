-- Generates the browser compiler's checked prelude graph as inert data.

local bundle, output, mode, dialect = ...
dialect = dialect or "luajit"
assert(dialect == "luajit", "invalid prelude dialect")
assert(
    bundle and output and (mode == "source" or mode == "image"),
    "usage: lua generate-prelude-image.lua BUNDLE OUTPUT source|image"
)

assert(loadfile(bundle))()
local roots
if mode == "image" then
    roots = require("nupp.compiler.preludeimage").new()
else
    local envMod = require("nupp.compiler.env")
    local env = envMod.new(".", {
        cache = false,
        memoryOnly = true,
        dialect = dialect,
        nativeCompilerServices = false,
        config = {_target = {dialect = dialect}},
        typeRoots = {},
    })
    roots = {
        annotationsByName = env.annotations.byname,
        featureEffects = env.featureEffects,
        globalTypeDefs = env.globalTypeDefs,
        globalTypes = env.globalTypes,
        globals = env.globals,
        preludeComptimeFunctions = env.preludeComptimeFunctions,
        preludeRuntime = env.preludeRuntime,
        stringLib = env.stringLib,
    }
end

-- The arenas `nupp.compiler.types` answers `==` out of, and the counters that
-- number what it interns next. A restored graph that is in no arena is equal to
-- nothing: the checker asks for `lit(string:#)` when it sees `select("#", ...)`
-- and builds a second literal under a key the image never filled, so the two
-- `'#'`s in one program are different objects. Every interned table therefore
-- goes out with the arena and key it was interned under, and the reader puts it
-- back there. See `nupp.compiler.preludecache`, which keeps the same contract
-- for the native compiler's own prelude cache.
local types = require("nupp.compiler.types")
local identity = types.identity()

-- Sorted, because the image is compared byte for byte and `pairs` is not an
-- order. Bucket first, then key, and the first pair a table is found under wins
-- when one table is interned twice.
local buckets = {}
for bucket in pairs(identity.arenas) do
    buckets[#buckets + 1] = bucket
end
table.sort(buckets)
local bucketKeys = {}
local internedAt = {}
for _, bucket in ipairs(buckets) do
    local keys = {}
    for key in pairs(identity.arenas[bucket]) do
        keys[#keys + 1] = key
    end
    table.sort(keys)
    bucketKeys[bucket] = keys
    for _, key in ipairs(keys) do
        local value = identity.arenas[bucket][key]
        if type(value) == "table" and internedAt[value] == nil then
            internedAt[value] = {bucket, key}
        end
    end
end

local ids = {}
local tables = {}
local pending = {}
local metatables = {}

local function scalar(value)
    local kind = type(value)
    return kind == "nil" or kind == "boolean" or kind == "number" or kind == "string"
end

local function tableKey(value)
    local parts = {}
    for name, member in pairs(value) do
        if scalar(name) and scalar(member) and member ~= nil then
            parts[#parts + 1] = tostring(name) .. "=" .. tostring(member)
        end
    end
    table.sort(parts)
    assert(#parts > 0, "prelude image has an anonymous table key")

    return table.concat(parts, "|")
end

local function entryKey(key)
    local kind = type(key)
    if kind == "string" then
        return "1:" .. key
    end
    if kind == "number" then
        return "2:" .. string.format("%+.17g", key)
    end
    if kind == "boolean" then
        return key and "3:1" or "3:0"
    end
    if kind == "table" then
        return "4:" .. tableKey(key)
    end
    error("prelude image cannot encode a " .. kind .. " table key", 0)
end

local function entries(value)
    local out = {}
    local seenOrder = {}
    for key, child in pairs(value) do
        if key ~= "trivia" then
            if key == "triviaCount" then
                child = 0
            end
            local order = entryKey(key)
            assert(not seenOrder[order], "prelude image has indistinguishable table keys")
            seenOrder[order] = true
            out[#out + 1] = {key = key, value = child, order = order}
        end
    end
    table.sort(out, function(left, right)
        return left.order < right.order
    end)

    return out
end

local function identify(value, path)
    if type(value) ~= "table" or ids[value] then
        return
    end
    local id = #tables + 1
    ids[value] = id
    tables[id] = value
    pending[#pending + 1] = value
    local metatable = getmetatable(value)
    if metatable ~= nil then
        metatables[id] = metatable
        identify(metatable, path .. " metatable")
    end
end

for _, name in ipairs({
    "annotationsByName",
    "featureEffects",
    "globalTypeDefs",
    "globalTypes",
    "globals",
    "preludeComptimeFunctions",
    "stringLib",
}) do
    identify(roots[name], name)
end

-- And from the arenas, not only from the roots. Checking the prelude interns
-- types that nothing in its seven roots reaches, and reachability is the wrong
-- question about them: an interned type is one the checker will later look for
-- by key, and a key that finds nothing becomes a second type built under it.
for _, bucket in ipairs(buckets) do
    for _, key in ipairs(bucketKeys[bucket]) do
        identify(identity.arenas[bucket][key], "arena " .. bucket .. " " .. key)
    end
end

local at = 1
while at <= #pending do
    local owner = pending[at]
    for _, entry in ipairs(entries(owner)) do
        identify(entry.key, "table " .. ids[owner] .. " key " .. entry.order)
        identify(entry.value, "table " .. ids[owner] .. " value " .. entry.order)
        local keyKind = type(entry.key)
        local valueKind = type(entry.value)
        assert(scalar(entry.key) or keyKind == "table", "prelude image cannot encode a " .. keyKind .. " key")
        assert(scalar(entry.value) or valueKind == "table", "prelude image cannot encode a " .. valueKind .. " value")
    end
    at = at + 1
end

-- Repeated strings dominate the graph: member names and interned type keys recur
-- in its declarations and arenas. A deterministic dictionary keeps their identity
-- while variable-width integers avoid decimal text for every count and reference.
local stringCounts = {}

local function countString(value)
    if type(value) == "string" then
        stringCounts[value] = (stringCounts[value] or 0) + 1
    end
end

for _, value in ipairs(tables) do
    for _, entry in ipairs(entries(value)) do
        countString(entry.key)
        countString(entry.value)
    end
    local where = internedAt[value]
    if where then
        countString(where[1])
        countString(where[2])
    end
end
for _, name in ipairs({
    "annotationsByName",
    "featureEffects",
    "globalTypeDefs",
    "globalTypes",
    "globals",
    "preludeComptimeFunctions",
    "stringLib",
    "preludeRuntime",
}) do
    countString(roots[name])
end
local dictionary = {}
for value, count in pairs(stringCounts) do
    if count > 1 then
        dictionary[#dictionary + 1] = value
    end
end
table.sort(dictionary, function(left, right)
    local a, b = stringCounts[left], stringCounts[right]
    return a == b and left < right or a > b
end)
local stringIds = {}
for index, value in ipairs(dictionary) do
    stringIds[value] = index
end

local file = assert(io.open(output, "wb"))
local MAX_INTEGER = 9007199254740991

local function writeInteger(value)
    assert(value >= 0 and value <= MAX_INTEGER and value % 1 == 0, "invalid prelude image integer")
    repeat
        local byte = value % 128
        value = math.floor(value / 128)
        assert(file:write(string.char(byte + (value > 0 and 128 or 0))))
    until value == 0
end

local function writeString(value)
    writeInteger(#value)
    assert(file:write(value))
end

local function writeValue(value)
    local kind = type(value)
    if kind == "nil" then
        assert(file:write("z"))
    elseif kind == "boolean" then
        assert(file:write(value and "t" or "f"))
    elseif kind == "string" then
        local id = stringIds[value]
        assert(file:write(id and "d" or "s"))
        if id then
            writeInteger(id)
        else
            writeString(value)
        end
    elseif kind == "table" then
        assert(file:write("r"))
        writeInteger(assert(ids[value]))
    elseif kind == "number" then
        if value % 1 == 0 and math.abs(value) <= MAX_INTEGER and not (value == 0 and 1 / value < 0) then
            assert(file:write(value < 0 and "j" or "i"))
            writeInteger(math.abs(value))
        else
            local encoded
            if value ~= value then
                encoded = "nan"
            elseif value == math.huge then
                encoded = "inf"
            elseif value == -math.huge then
                encoded = "-inf"
            else
                encoded = string.format("%.17g", value)
            end
            assert(file:write("n"))
            writeString(encoded)
        end
    else
        error("prelude image cannot encode " .. kind, 0)
    end
end

-- The interning header comes before the bodies, because the reader has to know
-- which tables are already live in its own arenas before it starts filling any
-- of them in: what is already there is left exactly as it stands.
local internedAs = {}
for id, value in ipairs(tables) do
    if internedAt[value] then
        internedAs[#internedAs + 1] = {id = id, where = internedAt[value]}
    end
end

assert(file:write("NUPP-PRELUDE-3\n"))
writeInteger(#tables)
writeInteger(#dictionary)
for _, value in ipairs(dictionary) do
    writeString(value)
end
writeInteger(#internedAs)
for _, entry in ipairs(internedAs) do
    writeInteger(entry.id)
    writeValue(entry.where[1])
    writeValue(entry.where[2])
end
writeInteger(identity.serial)
writeInteger(identity.capability)
writeInteger(identity.nominal)
for id, value in ipairs(tables) do
    local members = entries(value)
    writeInteger(#members)
    for _, entry in ipairs(members) do
        writeValue(entry.key)
        writeValue(entry.value)
    end
    writeInteger(metatables[id] and ids[metatables[id]] or 0)
end
for _, name in ipairs({
    "annotationsByName",
    "featureEffects",
    "globalTypeDefs",
    "globalTypes",
    "globals",
    "preludeComptimeFunctions",
    "stringLib",
}) do
    writeValue(roots[name])
end
writeValue(roots.preludeRuntime)
assert(file:close())

io.stderr:write(("wrote %s with %d tables\n"):format(output, #tables))
