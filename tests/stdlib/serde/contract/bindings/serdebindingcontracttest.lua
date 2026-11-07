local call = require("helpers.serdecontract").call
local json = require("testjson")
local M = {}

function M.codecExtensionsReuseOperationsWithBoundedRetention()
    local status, output = call({"run", "codec_extensions.nupp"})
    assert(status == 0, output)
    status, output = call({"run", "codec_cache_scope.lua"})
    assert(status == 0, output)
end

function M.typedStructureOperationsKeepConstructionAndSelectionChecked()
    local status, output = call({"run", "structure.nupp"})
    assert(status == 0, output)
end

function M.declarationAccessPreservesConstructorsDefaultsAndPrivateStorage()
    local status, output = call({"run", "access.nupp"})
    assert(status == 0, output)
end

function M.declarationBindingsRoundTripRecursiveRecordsAndExactCarriers()
    local status, output = call({"run", "declaration.nupp"})
    assert(status == 0, output)
end

function M.streamingMembersStayOutsideFiniteSerialization()
    local status, output = call({"run", "streaming.nupp"})
    assert(status == 0, output)
end

function M.indexedMappingsPreservePresenceFactoriesAndInspectableAccess()
    local status, output = call({"run", "indexed.nupp"})
    assert(status == 0, output)
end

function M.owningDecodeResultsAndAbortedConstructionKeepCleanup()
    local status, output = call({"run", "owned_decode.nupp"})
    assert(status == 0, output)
end

function M.syntaxRetainsNumbersAndValidatesSkippedValues()
    local status, output = call({"run", "jsonsyntax.lua"})
    assert(status == 0, output)
end

function M.directOutputAndStructuredFailuresPreserveTheirContracts()
    for _, file in ipairs({"buffer_output.nupp", "errors.nupp", "output_guards.nupp"}) do
        local status, output = call({"run", file})
        assert(status == 0, output)
    end
end

function M.ordinaryProgramsNeedNoMappingTablesOrPreparation()
    local status, output = call({"run", "ergonomics.nupp"})
    assert(status == 0, output)
end

function M.ordinaryBindingsUseDefaultJsonWithoutImplicitModelSelection()
    local status, output = call({"run", "default_json.nupp"})
    assert(status == 0, output)
end

function M.declarationMappingsWhitelistRenameAndValidateConstruction()
    local status, output = call({"run", "mapping.nupp"})
    assert(status == 0, output)
end

function M.debugKeepsItsOwnPolicyAndReleasesLazySchemaExtensions()
    local status, output = call({"run", "debug.nupp"})
    assert(status == 0, output)
    status, output = call({"run", "debug_scope.lua"})
    assert(status == 0, output)
end

function M.scopedReadersRejectRetentionAndIncorrectConsumption()
    local status, output = call({"run", "reader_scope.lua"})
    assert(status == 0, output)
    status, output = call({"check", "--json", "negative/reader-escape.nupp"})
    local checked = json.decode(output)
    assert(status ~= 0 and #checked.diagnostics == 1, output)
    assert(checked.diagnostics[1].code == "NUPP2603", output)
end

return M
