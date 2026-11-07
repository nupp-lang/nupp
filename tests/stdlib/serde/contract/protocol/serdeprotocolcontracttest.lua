local call = require("helpers.serdecontract").call
local json = require("testjson")
local M = {}

function M.runtimeSmithyModelsKeepIdentitiesTraitsAndProtocolContexts()
    local status, output = call({"run", "smithy.nupp"})
    assert(status == 0, output)
end

function M.protocolRoutingReusesBindingsAcrossBodiesHeadersAndQueries()
    local status, output = call({"run", "routing.nupp"})
    assert(status == 0, output)
end

function M.loadedSmithyModelsShareTypedIndexedAndDocumentPolicies()
    local status, output = call({"run", "smithy_access.nupp"})
    assert(status == 0, output)
end

function M.transportBackpressureAndCancellationRetainOwnedBytesOnly()
    local status, output = call({"run", "transport_scope.lua"})
    assert(status == 0, output)
end

function M.independentOpenApiPoliciesKeepTheirOwnUnionAndPropertyRules()
    local status, output = call({"run", "openapi.nupp"})
    assert(status == 0, output)
end

function M.protocolFieldIdentitiesRetainNamespacesAndWireTypes()
    local status, output = call({"run", "protocolsyntax.nupp"})
    assert(status == 0, output)
    status, output = call({"run", "xmlassembly.nupp"})
    assert(status == 0, output)
end

function M.binaryCodecUsesSchemaDirectedNumbersTuplesAndOwnedUnknownFields()
    local status, output = call({"run", "binarynumbers.nupp"})
    assert(status == 0, output)
    status, output = call({"run", "binarycodec.nupp"})
    assert(status == 0, output)
end

function M.xmlCodecSharesSmithyRecordsAndDocumentsWithOwnedSubtrees()
    local status, output = call({"run", "xmlcodec.nupp"})
    assert(status == 0, output)
end

function M.protocolReadersCloseOnEveryExitAndCacheFailedSelections()
    local status, output = call({"run", "protocol_scope.lua"})
    assert(status == 0, output)
end

return M
