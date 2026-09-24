local fs = require("nupp.compiler.fs")
local incremental = require("nupp.compiler.incremental")
local navigation = require("nupp.tools.lsp.spi")
local M = {}

function M.metadataNavigationDoesNotLoadImplementations()
    local dir = os.tmpname()
    os.remove(dir)
    assert(fs.mkdir(dir))
    local files = {
        ["nupp.lua"] = 'return {include = {"."}}',
        ["contract.nupp"] = [[
module contract
export interface Provider
    @readonly value: function(): string
end
]],
        [
            "implementation.nupp"
        ] = [[
module implementation
export function value(): string return "result" end
error("navigation must not execute this module")
]],
        ["nupp/spi.json"] = [[{"contract.Provider":["implementation"]}]],
        [
            "consumer.nupp"
        ] = [[
module consumer
const contract = require("contract")
local spi = require("nupp.spi")
const provider = assert(spi.load(contract.Provider)())
export const result = provider.value()
]],
    }
    for name, source in pairs(files) do
        assert(fs.writeFile(fs.join(dir, name), source))
    end
    local success, failure = pcall(function()
        local graph = incremental.new(dir)
        local checked = graph.checkFile(fs.join(dir, "consumer.nupp"))
        for _, diagnostic in ipairs(checked.diags) do
            assert(diagnostic.severity ~= "error", diagnostic.msg)
        end
        local token
        for _, candidate in ipairs(checked.result.tokens) do
            if candidate.text == "value" then
                token = candidate
            end
        end
        assert(token and token.definition, "the call resolves to the canonical interface member")
        local locations = navigation.implementations(graph, nil, token)
        local implementation = false
        for _, location in ipairs(locations) do
            implementation = implementation or location.uri:find("/implementation.nupp", 1, true) ~= nil
        end
        assert(implementation, "SPI navigation locates the implementation export")
        assert(#locations == 1, "one advertised implementation")
    end)
    require("nupp.io.files").remove(dir, true)
    if not success then
        error(failure, 0)
    end
end

function M.facadeLoadSitesLocateAdvertisedImplementations()
    local dir = os.tmpname()
    os.remove(dir)
    assert(fs.mkdir(dir))
    local files = {
        ["nupp.lua"] = 'return {include = {"."}}',
        ["contract.nupp"] = [[module contract
export interface Provider @readonly value: function(): string end]],
        [
            "alias.nupp"
        ] = [[module alias
local {type Provider} = require("contract")
export type PublicProvider = Provider]],
        [
            "implementation.nupp"
        ] = [[module implementation
export function value(): string return "result" end
error("navigation must not execute this module")]],
        ["nupp/spi.json"] = [[{"alias.PublicProvider":["implementation"]}]],
        [
            "consumer.nupp"
        ] = [[module consumer
local spi = require("nupp.spi")
local {type Provider} = require("contract")
local provider = assert(spi.load(Provider)())
export const value = provider.value]],
    }
    for name, source in pairs(files) do
        assert(fs.writeFile(fs.join(dir, name), source))
    end
    local success, failure = pcall(function()
        local graph = incremental.new(dir)
        graph.checkFile(fs.join(dir, "consumer.nupp"))
        local locations = navigation.implementations(graph, {moduleName = "consumer", name = "value"})
        assert(#locations == 1, "the facade's typed load refers to the defining interface")
        assert(locations[1].uri:find("/implementation.nupp", 1, true), locations[1].uri)
    end)
    require("nupp.io.files").remove(dir, true)
    assert(success, failure)
end

return M
