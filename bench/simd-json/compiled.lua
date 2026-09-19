-- Refuse timings unless the selected public codec reaches native builders.
local function upvalue(fn, wanted)
    for index = 1, 64 do
        local name, value = debug.getupvalue(fn, index)
        if not name then
            break
        end
        if name == wanted then
            return value
        end
    end
    error("compiled decoder proof cannot find " .. wanted)
end

local function prove(entry, providerMember, decoderName)
    local provider = upvalue(entry, "native")
    local decoder = upvalue(provider[providerMember], decoderName).decode
    local registry = assert(rawget(_G, "__nuppAotCompiled"), "no AOT replacement registry")
    local modules = assert(rawget(_G, "__nuppAotBuilderModules"), "no native builder registry")
    local seen, registered, native = {}, false, false

    local function visit(fn)
        if seen[fn] then
            return
        end
        seen[fn] = true
        registered = registered or registry[fn] ~= nil
        for index = 1, 64 do
            local name, value = debug.getupvalue(fn, index)
            if not name then
                break
            end
            if type(value) == "function" then
                visit(value)
            end
        end
    end

    visit(decoder)
    for _, builders in pairs(modules) do
        for _, fn in pairs(builders) do
            if seen[fn] and debug.getinfo(fn, "S").what == "C" then
                native = true
            end
        end
    end
    assert(registered and native, "the selected " .. providerMember .. " decoder is not a registered native builder")

    return true
end

return function()
    require("simd_json.setup")
    local codec = require("nupp.codec.json")
    local proof = {
        eager = prove(codec.decode, "decode", "eagerDecoder"),
        pull = prove(codec.pull, "pull", "pullDecoder"),
        serde = prove(codec.decode, "decodeSerde", "serdeDecoder"),
    }
    for _, kernel in ipairs({{"scanner", "classify"}, {"indexer", "index"}, {"parser", "parse"}}) do
        local entry = require("simd_json." .. kernel[1])[kernel[2]]
        assert(rawget(_G, "__nuppAotCompiled")[entry], kernel[1] .. " is not compiled")
        proof[kernel[1]] = true
    end

    return proof
end
