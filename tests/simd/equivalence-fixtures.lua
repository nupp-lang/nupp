-- Test-only mutations of real schema-3 Wasm bridge manifests. The guest keeps
-- the canonical manifest, while the embedded host reads the mutated copy.
local M = {}

local source = debug.getinfo(1, "S").source:gsub("^@", ""):gsub("\\", "/")
local directory = assert(source:match("^(.*)/[^/]+$"))
local root = assert(directory:match("^(.*)/tests/simd$"))
local decode = assert(loadfile(root .. "/src/nupp/runtime/vendor/lunajson/decoder.lua"))()()
local encode = assert(loadfile(root .. "/src/nupp/runtime/vendor/lunajson/encoder.lua"))()()

local function read(path)
    local file, problem = io.open(path, "rb")
    assert(file, ("cannot read %s: %s"):format(path, tostring(problem)))
    local text = file:read("*a") or ""
    file:close()

    return text
end

local function entries(manifest)
    assert(
        type(manifest) == "table"
        and manifest.schemaVersion == 3
        and manifest.target == "wasm32-unknown-emscripten"
        and type(manifest.units) == "table",
        "equivalence mutation requires a real schema-3 Emscripten manifest"
    )
    local values = {}
    for _, unit in ipairs(manifest.units) do
        for _, entry in ipairs(unit.bridge and unit.bridge.entries or {}) do
            values[#values + 1] = {unit = unit, entry = entry}
        end
    end
    assert(#values > 0, "equivalence mutation found no independent Wasm entries")

    return values
end

local function endsWith(value, suffix)
    return value:sub(-#suffix) == suffix
end

local function lowered(name)
    return (name:gsub("%u", function(letter)
        return "_" .. letter:lower()
    end):gsub("_+", "_"))
end

local function executedEntries(manifest, probes)
    if type(probes) ~= "table" then
        return entries(manifest)
    end
    local values = {}
    for module, names in pairs(probes) do
        local matches = {}
        for _, unit in ipairs(manifest.units) do
            -- Generated C, or LLVM IR when the LLVM backend built the unit.
            local sourceName = (unit.source or ""):gsub("%.ll$", ".c")
            if endsWith(sourceName, "/" .. module .. ".simd128.c")
                or endsWith(sourceName, "/" .. module .. ".g.simd128.c")
                or sourceName == module .. ".simd128.c"
                or sourceName == module .. ".g.simd128.c"
            then
                matches[#matches + 1] = unit
            end
        end
        assert(#matches == 1, "equivalence mutation found no unique executed unit for " .. module)
        for _, name in ipairs(names) do
            local candidates = {}
            for _, entry in ipairs(matches[1].bridge and matches[1].bridge.entries or {}) do
                if endsWith(entry.symbol, "_" .. name) or endsWith(entry.symbol, "_" .. lowered(name)) then
                    candidates[#candidates + 1] = entry
                end
            end
            assert(
                #candidates == 1,
                "equivalence mutation found no unique executed entry for " .. module .. "." .. name
            )
            values[#values + 1] = {unit = matches[1], entry = candidates[1]}
        end
    end
    assert(#values > 0, "equivalence mutation found no executed Wasm entries")

    return values
end

function M.load(path)
    local ok, manifest = pcall(decode, read(path), 1, nil, true)
    assert(ok and type(manifest) == "table", path .. " is not valid JSON: " .. tostring(manifest))

    return manifest
end

function M.write(path, manifest)
    local file, problem = io.open(path, "wb")
    assert(file, ("cannot write %s: %s"):format(path, tostring(problem)))
    file:write(encode(manifest))
    file:write("\n")
    file:close()
end

function M.mutate(manifest, id, probes)
    local values = executedEntries(manifest, probes)
    if id == "wasm-stack-transport" then
        local selected = values[1]
        selected.entry.params[#selected.entry.params + 1] = {kind = "scalar", type = "i32"}
        if type(selected.entry.params[0]) == "number" then
            selected.entry.params[0] = selected.entry.params[0] + 1
        end

        return {unit = selected.unit.unit, symbol = selected.entry.symbol, expected = "bridge extent mismatch",}
    elseif id == "wasm-wide-transport" then
        for _, selected in ipairs(values) do
            for _, param in ipairs(selected.entry.params or {}) do
                if param.kind == "read_span" or param.kind == "write_span" then
                    if param.sourceType == "int64" or param.sourceType == "uint64" then
                        local signed = param.sourceType == "int64"
                        param.sourceType = signed and "int32" or "uint32"
                        param.type = signed and "i32" or "u32"

                        return {
                            unit = selected.unit.unit,
                            symbol = selected.entry.symbol,
                            expected = "Wasm scalar span layout mismatch",
                        }
                    end
                end
            end
        end
        error("equivalence mutation found no executed 64-bit scalar span", 0)
    end
    error("unknown equivalence fixture " .. tostring(id), 0)
end

return M
