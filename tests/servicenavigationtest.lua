local fs = require("nupp.compiler.fs")
local incremental = require("nupp.compiler.incremental")
local navigation = require("nupp.compiler.lsp.services")
local M = {}

function M.catalogAndRegistrationNavigationDoesNotLoadProviders()
    local dir = os.tmpname()
    os.remove(dir)
    assert(fs.mkdir(dir))
    local files = {
        ["nupp.lua"] = 'return {include = {"."}}',
        [
            "contract.nupp"
        ] = [[
module contract
const services = require("nupp.services")
export interface Provider
    readonly value: function(): string
end
export const service: services.Service<Provider> = services.define("test.navigation", 1)
]],
        [
            "implementation.nupp"
        ] = [[
module implementation
export function value(): string return "result" end
error("navigation must not execute this module")
]],
        [
            "setup.nupp"
        ] = [[
module setup
const contract = require("contract")
contract.service:register("fixture", function(): contract.Provider
    return require("implementation")
end)
]],
        [
            "nupp/runtime/services/artifact.nupp"
        ] = [[
module nupp.runtime.services.artifact
export = {providers = {{service = "test.navigation", name = "fixture", api = 1,
    contract = "contract", export = "service", entry = "implementation"}}}
]],
        [
            "consumer.nupp"
        ] = [[
module consumer
const contract = require("contract")
const provider = contract.service:require("fixture")
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
        local implementation, registration = false, false
        for _, location in ipairs(locations) do
            implementation = implementation or location.uri:find("/implementation.nupp", 1, true) ~= nil
            registration = registration or location.uri:find("/setup.nupp", 1, true) ~= nil
        end
        assert(implementation, "catalog navigation locates the implementation export")
        assert(registration, "authored registration is navigable")
    end)
    require("nupp.io.files").remove(dir, true)
    if not success then
        error(failure, 0)
    end
end

function M.bundledFacadesNavigateToCanonicalContractsAndProviderExports()
    local dir = os.tmpname()
    os.remove(dir)
    assert(fs.mkdir(dir))
    assert(fs.writeFile(fs.join(dir, "nupp.lua"), 'return {include = {"."}}'))
    local success, failure = pcall(function()
        local graph = incremental.new(dir)
        local definition = navigation.definition(graph, "nupp.text.buffer", "new")
        assert(definition and definition.token, "the facade has a canonical declaration")
        local source = assert(fs.readFile(definition.filename))
        assert(source:sub(definition.token.offset, definition.token.offset + 2) == "new")
        local locations = navigation.implementations(graph, {moduleName = "nupp.text.buffer", name = "new"})
        assert(#locations == 2, "both buffer implementations are navigable")
        for _, location in ipairs(locations) do
            assert(location.uri:find("buffer.nupp", 1, true), location.uri)
        end
    end)
    require("nupp.io.files").remove(dir, true)
    if not success then
        error(failure, 0)
    end
end

return M
