-- The open-binding prerequisite is a separate project. None of its models can
-- reach the compiler's reflection/derive tables or the existing serde schema.
local json = require("testjson")
local process = require("nupp.compiler.process")
local fs = require("nupp.compiler.fs")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local NUPP = fs.absolute(HERE .. "/../bin/nupp")
local PROJECT = fs.absolute(HERE .. "/../bench/serde-spike/contracts")
local M = {}

local function call(args)
    local argv = {NUPP}
    for _, arg in ipairs(args) do
        argv[#argv + 1] = arg
    end

    return process.capture(argv, {cwd = PROJECT})
end

function M.externalMembersEraseBehindACheckedBinding()
    local status, output = call({
        "check",
        "--json",
        "erasure.nupp",
        "src/contract/dispatch.nupp",
        "src/contract/render.nupp",
        "src/example/model.nupp",
        "src/example/other.nupp"
    })
    assert(status == 0, output)
    local checked = json.decode(output)
    assert(checked.ok and #checked.diagnostics == 0, output)
    status, output = call({"run", "erasure.nupp"})
    assert(status == 0, output)
end

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

function M.streamingMembersStayOutsideFiniteSerialization()
    local status, output = call({"run", "streaming.nupp"})
    assert(status == 0, output)
end

function M.indexedMappingsPreservePresenceFactoriesAndInspectableAccess()
    local status, output = call({"run", "indexed.nupp"})
    assert(status == 0, output)
end

function M.declarationBindingsCheckCarrierCapabilitiesBeforeReading()
    local status, output = call({"run", "declaration_capabilities.nupp"})
    assert(status == 0, output)
end

function M.reflectionGraphsCannotBeReplacedThroughCheckedViews()
    for _, name in ipairs({"reflection-mutation.nupp", "reflection-nested-mutation.nupp"}) do
        local status, output = call({"check", "--json", "negative/" .. name})
        assert(status ~= 0, output)
        local checked = json.decode(output)
        assert(not checked.ok and #checked.diagnostics > 0, output)
        for _, diagnostic in ipairs(checked.diagnostics) do
            assert(diagnostic.severity == "error", output)
        end
    end
end

function M.independentOpenApiPoliciesKeepTheirOwnUnionAndPropertyRules()
    local status, output = call({"run", "openapi.nupp"})
    assert(status == 0, output)
end

function M.owningDecodeResultsAndAbortedConstructionKeepCleanup()
    local status, output = call({"run", "owned_decode.nupp"})
    assert(status == 0, output)
end

function M.retainedDataAndCopyableBindingsRejectOwners()
    local status, output = call({
        "check",
        "--json",
        "negative/owning-copyable-binding.nupp",
        "negative/owning-context.nupp",
        "negative/owning-projection.nupp",
        "negative/owning-witness.nupp"
    })
    local checked = json.decode(output)
    assert(status ~= 0, output)
    -- Retaining an owner is refused at the Copyable bound; what an owner left
    -- unconsumed afterwards also says is not this contract's business.
    local refused = {}
    for _, diagnostic in ipairs(checked.diagnostics) do
        local expected = diagnostic.file:match("owning%-witness.nupp$") and "NUPP2001" or "NUPP2116"
        if diagnostic.code == expected then
            refused[diagnostic.file:match("([^/\\]+)$")] = true
        end
    end
    for _, name in ipairs({
        "owning-copyable-binding.nupp",
        "owning-context.nupp",
        "owning-projection.nupp",
        "owning-witness.nupp"
    }) do
        assert(refused[name], "missing refusal: " .. name .. "\n" .. output)
    end
end

function M.syntaxRetainsNumbersAndValidatesSkippedValues()
    local status, output = call({"run", "jsonsyntax.lua"})
    assert(status == 0, output)
end

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

function M.directOutputAndStructuredFailuresPreserveTheirContracts()
    for _, file in ipairs({"buffer_output.nupp", "errors.nupp", "output_guards.nupp"}) do
        local status, output = call({"run", file})
        assert(status == 0, output)
    end
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

function M.nativePersistenceKeepsExactTreesAndRestoresStoresTransactionally()
    local status, output = call({"run", "native.nupp"})
    assert(status == 0, output)
    status, output = call({"run", "native_scope.lua"})
    assert(status == 0, output)
    status, output = call({"run", "native_owned.nupp"})
    assert(status == 0, output)
end

function M.compiledRecipesMatchVisitorAndRespectRefusals()
    local native = PROJECT .. "/native-build"
    local status, output = process.capture({NUPP, "build", "--target", "compiled-contracts", "--json"}, {cwd = native})
    assert(status == 0, output)
    local built = json.decode(output)
    assert(built.ok, output)
    status, output = process.capture({"luajit", PROJECT .. "/compiled_scope.lua"}, {
        cwd = native,
        env = {
            LUA_PATH = native .. "/build/?.lua;" .. fs.absolute(HERE .. "/../build") .. "/?.lua;" .. package.path,
            LUA_CPATH = package.cpath
        }
    })
    assert(status == 0, output)
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

function M.bindingsAreInvariant()
    local expected = {
        ["widen.nupp"] = "NUPP2001",
        ["narrow.nupp"] = "NUPP2002",
    }
    local args = {"check", "--json"}
    for _, name in ipairs({"widen.nupp", "narrow.nupp"}) do
        args[#args + 1] = "negative/" .. name
    end
    local status, output = call(args)
    assert(status ~= 0, "negative contracts passed")
    local checked = json.decode(output)
    assert(checked.ok == false, output)
    local seen = {}
    for _, diagnostic in ipairs(checked.diagnostics) do
        local name = diagnostic.file:match("([^/\\]+)$")
        assert(expected[name] == diagnostic.code and diagnostic.severity == "error", output)
        assert(not seen[name], output)
        seen[name] = true
    end
    for name in pairs(expected) do
        assert(seen[name], "missing refusal: " .. name .. "\n" .. output)
    end
end

function M.typedViewsRetainBindingsAndSnapshotWithoutAliasing()
    local status, output = call({"run", "view.nupp"})
    assert(status == 0, output)
    status, output = call({"check", "--json", "negative/owning-view.nupp"})
    assert(status ~= 0 and output:find("Copyable", 1, true), output)
end

function M.portableSourceProfileRejectsUnsupportedRuntimeDependencies()
    local status, output = call({"check", "--compat", "lua51", "--json", "negative/portable-profile.nupp"})
    assert(status ~= 0, output)
    local checked = json.decode(output)
    local rejected = false
    for _, diagnostic in ipairs(checked.diagnostics) do
        rejected = rejected
            or diagnostic.code == "NUPP3015"
            and diagnostic.message:find('module "nupp.serde" violates compatibility', 1, true)
    end
    assert(rejected, output)
end

return M
