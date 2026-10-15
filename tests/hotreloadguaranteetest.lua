-- One executable index from the public hot-reload promises to the tests that
-- enforce them. The runner executes every referenced case in its owning suite;
-- this suite keeps a documentation edit from relying on a renamed or removed
-- case without replacing its coverage.

local suites = {
   cheadertest = require("cheadertest"),
   hotreloadtest = require("hotreloadtest"),
}

local guarantees = {
   {
      claim = "watch mode is O0-only",
      cases = {{"hotreloadtest", "cliWatchRejectsOptimizedGeneration"}},
   },
   {
      claim = "poll commits compatible edits and preserves the last good generation",
      cases = {
         {"hotreloadtest", "cliWatchCommitsAndKeepsTheLastGoodGeneration"},
         {"hotreloadtest", "cliWatchPatchesUnderARunningLoop"},
      },
   },
   {
      claim = "function identity, module state, and captured cells survive commit",
      cases = {{"hotreloadtest", "retainedFunctionUsesPatchedBodyAndCapturedCell"}},
   },
   {
      claim = "unloaded modules are not patched",
      cases = {{"hotreloadtest", "sessionSkipsUnloadedChangedModules"}},
   },
   {
      claim = "named and anonymous functions and record methods retain identity",
      cases = {
         {"hotreloadtest", "retainedFunctionUsesPatchedBodyAndCapturedCell"},
         {"hotreloadtest", "anonymousClosuresArePatchIdentities"},
         {"hotreloadtest", "inlineRecordMethodKeepsItsPublicIdentity"},
      },
   },
   {
      claim = "a changed body may add closures",
      cases = {{"hotreloadtest", "aChangedBodyMayAddAClosure"}},
   },
   {
      claim = "every call after a commit enters the newest body",
      cases = {
         {"hotreloadtest", "selfRecursionUsesNewPrivateImplementation"},
         {"hotreloadtest", "mutualRecursionUsesTheNewestPartnerSlot"},
      },
   },
   {
      claim = "type errors reject a candidate without replacing the old generation",
      cases = {
         {"hotreloadtest", "sessionRechecksLoadedModulesAfterDeclarationChanges"},
         {"hotreloadtest", "cliWatchCommitsAndKeepsTheLastGoodGeneration"},
      },
   },
   {
      claim = "a patch lands whole or not at all",
      cases = {
         {"hotreloadtest", "failedMultiFunctionStagePublishesNothing"},
         {"hotreloadtest", "theRuntimeRefusesWhatTheSessionMissed"},
      },
   },
   {
      claim = "loaded semantic dependencies are rechecked at their dependency boundary",
      cases = {
         {"hotreloadtest", "sessionRejectsSemanticSignatureChangesWithTheSameSpelling"},
         {"hotreloadtest", "sessionNamesTheImportedModuleWhoseInterfaceChanged"},
         {"hotreloadtest", "sessionIgnoresUnrelatedDeclarationChanges"},
      },
   },
   {
      claim = "direct and preprocessed header inputs are observed semantically",
      cases = {
         {"cheadertest", "headerProvenanceNamesTheDirectInput"},
         {"cheadertest", "preprocessorProvenanceIncludesNestedHeaders"},
         {"hotreloadtest", "sessionObservesHeaderSemanticsAndIgnoresComments"},
         {"hotreloadtest", "sessionTracksPreprocessedHeaderClosure"},
         {"hotreloadtest", "cliWatchObservesHeaderOnlyEdits"},
      },
   },
   {
      claim = "mapped native artifacts load exactly and require restart when replaced",
      cases = {
         {"hotreloadtest", "sessionPinsAndObservesMappedNativeArtifacts"},
         {"hotreloadtest", "cliWatchRequiresRestartForMappedNativeReplacement"},
      },
   },
   {
      claim = "unmapped native loader names are reported as unverified",
      cases = { {"hotreloadtest", "sessionReportsUnmappedNativeIdentityOnce"} },
   },
   {
      claim = "structural, C, capture, signature and layout changes name why restart is required",
      cases = {
         {"hotreloadtest", "sessionReportsStructuralChangesAsRestartRequired"},
         {"hotreloadtest", "sessionRejectsChangedCLayoutsBeforePatching"},
         {"hotreloadtest", "rejectedCaptureChangeLeavesOldGenerationRunning"},
         {"hotreloadtest", "sessionRefusesSignatureDeclarationAndLayoutChanges"},
      },
   },
   {
      claim = "keyed C dependencies ignore order and reject changed or newly used ABI",
      cases = {
         {"hotreloadtest", "sessionKeysCDeclarationsIndependentOfOrder"},
         {"hotreloadtest", "sessionKeysCFunctionsByDecodedLibraryAndSymbol"},
         {"hotreloadtest", "sessionRejectsChangedCLayoutsBeforePatching"},
         {"hotreloadtest", "sessionRejectsNewCUseMissingFromTheRunningModule"},
         {"hotreloadtest", "sessionKeepsRawFfiDeclarationsOnTheConservativeFallback"},
      },
   },
   {
      claim = "derive provider filesystem inputs are observed and invalidate consumers",
      cases = {
         {"hotreloadtest", "sessionTracksDeriveProviderFilesystemInputs"},
         {"hotreloadtest", "deriveProviderFilesystemInputsRequireLiteralPaths"},
         {"hotreloadtest", "deriveProviderFilesystemInputsStayInsideTheProject"},
      },
   },
   {
      claim = "an active call finishes on the implementation it entered",
      cases = {{"hotreloadtest", "activeCallFinishesOnTheImplementationItEntered"}},
   },
   {
      claim = "a body that only moved is no change",
      cases = {{"hotreloadtest", "movedLinesAreNoChange"}},
   },
}

local M = {}

function M.documentedGuaranteesNameExecutableCoverage()
   local seen = {}
   for _, guarantee in ipairs(guarantees) do
      assert(not seen[guarantee.claim], "duplicate hot-reload guarantee: " .. guarantee.claim)
      seen[guarantee.claim] = true
      assert(#guarantee.cases > 0, "uncovered hot-reload guarantee: " .. guarantee.claim)
      for _, case in ipairs(guarantee.cases) do
         local suite, name = case[1], case[2]
         assert(type(suites[suite]) == "table", "unknown hot-reload suite: " .. tostring(suite))
         assert(type(suites[suite][name]) == "function",
            guarantee.claim .. " names missing test " .. suite .. "." .. tostring(name))
      end
   end
end

return M
