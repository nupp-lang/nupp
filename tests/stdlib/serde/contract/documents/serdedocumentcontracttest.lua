local call = require("helpers.serdecontract").call
local json = require("testjson")
local M = {}

function M.externalModelsRoundTripBothRepresentationsAndDocuments()
    local status, output = call({"run", "rich.nupp"})
    assert(status == 0, output)
end

function M.documentContextsKeepTypedSchemaAndMemberValues()
    local status, output = call({"run", "context.nupp"})
    assert(status == 0, output)
    status, output = call({"check", "--json", "negative/context-key.nupp"})
    local checked = json.decode(output)
    assert(status ~= 0 and #checked.diagnostics == 1, output)
    assert(checked.diagnostics[1].code == "NUPP2006", output)
end

function M.richDocumentsRetainSemanticValuesAcrossReadersAndProfiles()
    for _, file in ipairs({
        "documents.nupp",
        "model_document.nupp",
        "semantic_bridge.nupp",
        "scalars.lua",
        "document_scope.lua",
        "document_cache_scope.lua",
        "json_document_scope.lua",
        "selection.lua"
    }) do
        local status, output = call({"run", file})
        assert(status == 0, output)
    end
end

function M.nativePersistenceKeepsExactTreesAndRestoresStoresTransactionally()
    local status, output = call({"run", "native.nupp"})
    assert(status == 0, output)
    status, output = call({"run", "native_scope.lua"})
    assert(status == 0, output)
    status, output = call({"run", "native_owned.nupp"})
    assert(status == 0, output)
end

function M.typedViewsRetainBindingsAndSnapshotWithoutAliasing()
    local status, output = call({"run", "view.nupp"})
    assert(status == 0, output)
    status, output = call({"check", "--json", "negative/owning-view.nupp"})
    assert(status ~= 0 and output:find("Copyable", 1, true), output)
end

return M
