-- One executable index from the public hot-reload promises to the tests that
-- enforce them. The runner executes every referenced case in its owning suite;
-- this suite keeps a documentation edit from relying on a renamed or removed
-- case without replacing its coverage.

local suites = {
   hotreloadtest = require("hotreloadtest"),
   runtimetest = require("runtimetest"),
}

local guarantees = {
   {
      claim = "watch mode is O0-only",
      cases = {{"runtimetest", "cliWatchRejectsOptimizedGeneration"}},
   },
   {
      claim = "poll commits compatible edits and preserves the last good generation",
      cases = {{"runtimetest", "cliWatchCommitsAndKeepsTheLastGoodGeneration"}},
   },
   {
      claim = "function identity, module state, and captured cells survive commit",
      cases = {{"hotreloadtest", "retainedFunctionUsesPatchedBodyAndCapturedCell"}},
   },
   {
      claim = "unloaded modules create no patch slots",
      cases = {{"hotreloadtest", "sessionSkipsUnloadedChangedModules"}},
   },
   {
      claim = "named functions and record and struct methods retain identity",
      cases = {
         {"hotreloadtest", "retainedFunctionUsesPatchedBodyAndCapturedCell"},
         {"hotreloadtest", "inlineRecordMethodKeepsItsPublicIdentity"},
         {"hotreloadtest", "structMethodDispatchesThroughAStableSlot"},
      },
   },
   {
      claim = "self recursion is generation-private and mutual recursion uses slots",
      cases = {
         {"hotreloadtest", "selfRecursionUsesNewPrivateImplementation"},
         {"hotreloadtest", "mutualRecursionUsesTheNewestPartnerSlot"},
      },
   },
   {
      claim = "type errors reject a candidate without replacing the old generation",
      cases = {
         {"hotreloadtest", "sessionRechecksLoadedModulesAfterDeclarationChanges"},
         {"runtimetest", "cliWatchCommitsAndKeepsTheLastGoodGeneration"},
      },
   },
   {
      claim = "patch staging is atomic and commit flushes stale JIT traces",
      cases = {
         {"hotreloadtest", "failedMultiFunctionStagePublishesNothing"},
         {"hotreloadtest", "commitFlushesJitAfterPublishing"},
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
      claim = "structural, C, capture, and affine changes name why restart is required",
      cases = {
         {"hotreloadtest", "sessionReportsStructuralChangesAsRestartRequired"},
         {"hotreloadtest", "sessionRejectsChangedCLayoutsBeforePatching"},
         {"hotreloadtest", "rejectedCaptureChangeLeavesOldGenerationRunning"},
         {"hotreloadtest", "sessionNamesTheAffineCaptureThatRequiresRestart"},
      },
   },
   {
      claim = "an active call finishes on the implementation it entered",
      cases = {{"hotreloadtest", "activeCallFinishesOnTheImplementationItEntered"}},
   },
   {
      claim = "ordinary generation contains no hot-reload machinery",
      cases = {{"hotreloadtest", "normalGenerationRemainsByteIdentical"}},
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
