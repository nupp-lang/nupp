-- Using JSON must not depend on AOT. `nupp.codec.json` resolves its provider
-- during module initialization, with Lunajson as the explicit fallback.
--
-- What that claims is about a process that has done nothing else, so it is
-- asked of one: a spawned interpreter requires the facade, uses it, and prints
-- which modules came back with it. Doing this in-process would mean evicting
-- `package.loaded` entries other suites in the same worker are holding, and a
-- second copy of a provider is its own source of confusion.

local HERE = debug.getinfo(1, "S").source:match("^@(.*)/[^/]+$")
local NUPP = HERE .. "/../bin/nupp"

local M = {}

-- Every module that only the AOT JSON path pulls in.
local AOT_ONLY = {
    "nupp.codec.json.aot",
    "nupp.codec.json.internal.decode",
    "nupp.codec.json.internal.decoder.eager",
    "nupp.codec.json.internal.decoder.serde",
    "nupp.codec.json.internal.decoder.fused",
}

local function runScript(body)
    local path = os.tmpname() .. ".lua"
    local handle = assert(io.open(path, "w"))
    handle:write(body)
    handle:close()
    local pipe = assert(io.popen(string.format("%q run %q 2>&1", NUPP, path), "r"))
    local output = pipe:read("*a")
    pipe:close()
    os.remove(path)

    return output
end

function M.anOrdinaryJsonRequireLoadsLunajsonAndNoAotDecoder()
    local names = {}
    for _, name in ipairs(AOT_ONLY) do
        names[#names + 1] = string.format("%q", name)
    end
    local output = runScript(
        string.format(
            [[
        local json = require("nupp.codec.json")
        local value = json.decode('{"a":[1,2,3],"b":"x"}')
        assert(value.b == "x" and #value.a == 3, "the default provider decodes")
        assert(json.encode(json.asArray({1, 2})) == "[1,2]", "the default provider encodes")
        if package.loaded["nupp.runtime.provider.lunajson"] == nil then
            print("MISSING lunajson")
        end
        for _, name in ipairs({%s}) do
            if package.loaded[name] ~= nil then
                print("LOADED " .. name)
            end
        end
        print("done")
    ]],
            table.concat(names, ", ")
        )
    )
    assert(output:find("done", 1, true), "the spawned check did not finish: " .. output)
    assert(not output:find("MISSING lunajson", 1, true), "ordinary JSON use did not resolve Lunajson: " .. output)
    assert(not output:find("LOADED ", 1, true), "ordinary JSON use loaded an AOT-only module: " .. output)
end

function M.valueBuildingWithoutByteViewsDoesNotLoadStorage()
    local output = runScript(
        [[
        package.preload["nupp.mem.span"] = function()
            error("valuebuilder loaded spans before a byte view was requested")
        end
        local builder = require("nupp.codec.valuebuilder")
        assert(builder.length("hello") == 5)
        print("done")
    ]]
    )
    assert(output:find("done", 1, true), output)
end

function M.scalarFusedDecodingAndSpeciesWitnessesDoNotLoadStorage()
    local output = runScript(
        [[
        package.preload["nupp.mem.span"] = function() error("unexpected span import") end
        package.preload["nupp.runtime.storage"] = function() error("unexpected storage import") end
        local array, simd = require("nupp.mem.array"), require("nupp.simd")
        for _, name in ipairs({"uint8", "int8", "uint16", "int16", "uint32", "int32", "uint64", "int64", "float", "number"}) do
            assert(simd.species(array[name]) == nil)
        end
        local fused = require("nupp.codec.json.internal.decoder.fused")
        local value, status = fused.decodeEager('[1,"hello",true]', nil, {}, {})
        assert(status == 0 and value[1] == 1 and value[2] == "hello" and value[3] == true)
        print("done")
    ]]
    )
    assert(output:find("done", 1, true), output)
end

function M.theJsonProviderModuleIsLunajson()
    -- The same claim from inside this process, without moving anything: the
    -- module the facade holds is the Lunajson provider itself.
    local provider = require("nupp.codec.json.provider")
    local lunajson = require("nupp.runtime.provider.lunajson")
    assert(provider.decode == lunajson.decode, "the assembled JSON provider is not Lunajson")
    assert(provider.encode == lunajson.encode, "the assembled JSON provider is not Lunajson")
end

-- Run this same function under stock Lua 5.1 as well as the native suite: its
-- constant table historically coalesced literal -0.0 with positive zero.
function M.theVendoredDecoderPreservesBothZeroSigns()
    local decode = assert(loadfile(HERE .. "/../src/nupp/runtime/vendor/lunajson/decoder.lua"))()()
    for _, magnitude in ipairs({"0", "0e1", "0.0", "0.0e1", "0E-9", "0.000"}) do
        for _, sign in ipairs({"", "-"}) do
            local text = sign .. magnitude
            local reciprocal = sign == "-" and -math.huge or math.huge
            local value = decode(text)
            assert(value == 0 and 1 / value == reciprocal, "JSON zero sign changed: " .. text)
            local values = decode("[" .. text .. ",{" .. '\"zero\":' .. text .. "}]")
            assert(1 / values[1] == reciprocal, "array JSON zero sign changed: " .. text)
            assert(1 / values[2].zero == reciprocal, "object JSON zero sign changed: " .. text)
        end
    end
end

return M
