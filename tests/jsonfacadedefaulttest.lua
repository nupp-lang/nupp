-- Using JSON must not depend on AOT. `nupp.codec.json` resolves its provider
-- through the `data.json` service contract, whose default loader is Lunajson;
-- the AOT provider is a named catalog entry nothing selects.
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
    local output = runScript(string.format(
        [[
        local json = require("nupp.codec.json")
        -- The service resolves on first use rather than on require, so the
        -- provider is named only once something asks the codec for an answer.
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
    ))
    assert(output:find("done", 1, true), "the spawned check did not finish: " .. output)
    assert(not output:find("MISSING lunajson", 1, true), "ordinary JSON use did not resolve Lunajson: " .. output)
    assert(not output:find("LOADED ", 1, true), "ordinary JSON use loaded an AOT-only module: " .. output)
end

function M.theJsonProviderModuleIsLunajson()
    -- The same claim from inside this process, without moving anything: the
    -- module the facade holds is the Lunajson provider itself.
    local provider = require("nupp.codec.json.provider")
    local lunajson = require("nupp.runtime.provider.lunajson")
    assert(provider.decode == lunajson.decode, "the assembled JSON provider is not Lunajson")
    assert(provider.encode == lunajson.encode, "the assembled JSON provider is not Lunajson")
end

function M.nothingInTheTreeSelectsTheAotJsonProvider()
    -- The catalog registers `nupp.aot` so a host may ask for it. If anything
    -- shipped ever selects it by default, the default stops being Lunajson and
    -- the checks above stop meaning what they say.
    local output = runScript([[
        local contracts = require("nupp.runtime.services.contracts")
        print("selected " .. tostring(rawget(contracts.json, "selected")))
    ]])
    assert(output:find("selected nil", 1, true), "the data.json service arrives with a selection: " .. output)
end

return M
