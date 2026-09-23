local impact = require("runner.impact")
local process = require("nupp.compiler.build.process")
local fs = require("nupp.compiler.fs")

local M = {}

local function equal(got, want, label)
    if got ~= want then
        error(("%s: want %s, got %s"):format(label, tostring(want), tostring(got)), 2)
    end
end

local function tempDirectory()
    local path = os.tmpname()
    os.remove(path)
    assert(fs.mkdir(path))
    return path
end

local function run(root, argv)
    local code, output = process.capture(argv, {cwd = root})
    assert(code == 0, table.concat(argv, " ") .. ": " .. output)
    return output
end

local function write(root, path, contents)
    assert(fs.writeFile(fs.join(root, path), contents))
end

local function repository()
    local root = tempDirectory()
    run(root, {"git", "init", "--quiet"})
    run(root, {"git", "config", "user.email", "impact@example.invalid"})
    run(root, {"git", "config", "user.name", "Impact Test"})
    write(root, "keep.txt", "base\n")
    write(root, "delete.txt", "delete\n")
    write(root, "rename.txt", "rename\n")
    run(root, {"git", "add", "."})
    run(root, {"git", "commit", "--quiet", "-m", "base"})

    return root
end

local function changeByPath(discovered, path)
    for _, change in ipairs(discovered.changes) do
        if change.path == path then
            return change
        end
    end
end

function M.workingDiffIncludesStagedUnstagedUntrackedDeletedAndRenamedPaths()
    local root = repository()
    write(root, "keep.txt", "unstaged\n")
    write(root, "staged.txt", "staged\n")
    run(root, {"git", "add", "staged.txt"})
    run(root, {"git", "rm", "--quiet", "delete.txt"})
    run(root, {"git", "mv", "rename.txt", "renamed.txt"})
    write(root, "untracked.txt", "untracked\n")

    local discovered = impact.discoverChanges({cwd = root})
    assert(discovered.available, discovered.reason)
    equal(discovered.base, discovered.head, "plain --diff uses HEAD as its base")
    equal(changeByPath(discovered, "keep.txt").status, "modified", "unstaged modification")
    equal(changeByPath(discovered, "staged.txt").status, "added", "staged addition")
    equal(changeByPath(discovered, "delete.txt").status, "deleted", "staged deletion")
    equal(changeByPath(discovered, "renamed.txt").oldPath, "rename.txt", "both rename paths")
    equal(changeByPath(discovered, "untracked.txt").sources[1], "untracked", "untracked source")
    local paths = {}
    for _, path in ipairs(discovered.paths) do
        paths[path] = true
    end
    assert(paths["keep.txt"] and paths["rename.txt"] and paths["renamed.txt"], "changed path index is complete")

    run(root, {"git", "status", "--short"})
    os.execute(("rm -rf %q"):format(root))
end

function M.explicitRefAddsCommittedChangesFromItsMergeBaseAndWorkingChanges()
    local root = repository()
    local base = run(root, {"git", "rev-parse", "HEAD"}):gsub("%s+$", "")
    write(root, "keep.txt", "committed\n")
    run(root, {"git", "add", "keep.txt"})
    run(root, {"git", "commit", "--quiet", "-m", "change"})
    write(root, "working.txt", "working\n")

    local discovered = impact.discoverChanges({cwd = root, ref = base})
    assert(discovered.available, discovered.reason)
    equal(discovered.base, base, "explicit ref resolves through merge-base")
    equal(changeByPath(discovered, "keep.txt").sources[1], "committed", "committed source")
    equal(changeByPath(discovered, "working.txt").sources[1], "untracked", "working source")

    os.execute(("rm -rf %q"):format(root))
end

function M.invalidRepositoryAndRefAreStructuredDiscoveryFailures()
    local outside = tempDirectory()
    local noRepository = impact.discoverChanges({cwd = outside})
    equal(noRepository.available, false, "outside a repository")
    equal(noRepository.code, "git-unavailable", "repository failure code")
    os.execute(("rm -rf %q"):format(outside))

    local root = repository()
    local invalidRef = impact.discoverChanges({cwd = root, ref = "not-a-ref"})
    equal(invalidRef.available, false, "invalid ref")
    equal(invalidRef.code, "invalid-ref", "ref failure code")
    os.execute(("rm -rf %q"):format(root))
end

local function graph()
    return {
        complete = true,
        base = "base",
        modules = {
            leaf = {paths = {"src/leaf.nupp"}, dependencies = {}},
            middle = {paths = {"src/middle.nupp"}, dependencies = {"leaf"}},
            top = {paths = {"src/top.nupp"}, dependencies = {"middle"}},
            cycleA = {paths = {"src/a.nupp"}, dependencies = {"cycleB"}},
            cycleB = {paths = {"src/b.nupp"}, dependencies = {"cycleA"}},
        },
        suites = {
            ["tests/safetest.lua"] = {path = "tests/safetest.lua", sliceSafe = true},
            ["tests/unsafetest.lua"] = {path = "tests/unsafetest.lua", sliceSafe = false},
        },
        impacts = {
            top = {{suite = "tests/safetest.lua", caseId = "through-top"}},
            middle = {{suite = "tests/unsafetest.lua", caseId = "through-middle"}},
            cycleB = {{suite = "tests/safetest.lua", caseId = "cycle"}},
        },
    }
end

local function discovered(changes)
    local paths = {}
    for _, change in ipairs(changes) do
        paths[#paths + 1] = change.oldPath or change.path
        if change.oldPath then
            paths[#paths + 1] = change.path
        end
    end

    return {available = true, base = "base", head = "head", changes = changes, paths = paths}
end

function M.selectionWalksReverseDependenciesAndPromotesUnsafeCases()
    local selected = impact.select(graph(), discovered({{status = "modified", path = "src/leaf.nupp"}}))
    equal(table.concat(selected.affectedModules, ","), "leaf,middle,top", "reverse dependency closure")
    equal(#selected.selectedCases, 1, "safe case count")
    equal(selected.selectedCases[1].caseId, "through-top", "safe case")
    equal(selected.selectedSuites[1], "tests/unsafetest.lua", "unsafe suite")
    equal(selected.promotions[1].code, "unsafe-case-promoted", "promotion code")
end

function M.selectionHandlesCyclesWithoutLosingCaseEdges()
    local selected = impact.select(graph(), discovered({{status = "modified", path = "src/a.nupp"}}))
    equal(table.concat(selected.affectedModules, ","), "cycleA,cycleB", "cycle closure")
    equal(selected.selectedCases[1].caseId, "cycle", "cycle case")
end

function M.selectionWalksDiamondsOnceAndKeepsEveryDetectingOwner()
    local diamond = graph()
    diamond.modules.left = {paths = {"src/left.nupp"}, dependencies = {"leaf"}}
    diamond.modules.right = {paths = {"src/right.nupp"}, dependencies = {"leaf"}}
    diamond.modules.join = {paths = {"src/join.nupp"}, dependencies = {"left", "right"}}
    diamond.impacts.join = {{suite = "tests/safetest.lua", caseId = "diamond"}}
    local selected = impact.select(diamond, discovered({{status = "modified", path = "src/leaf.nupp"}}))
    equal(selected.selectedCases[#selected.selectedCases].caseId, "through-top", "existing owner remains selected")
    local found = false
    for _, case in ipairs(selected.selectedCases) do
        found = found or case.caseId == "diamond"
    end
    assert(found, "diamond closure lost its detecting case")
end

function M.deletedAndGeneratedRuntimeModulesReachTheirConsumers()
    local generated = graph()
    generated.modules.runtime = {paths = {"src/nupp/runtime/provider.nupp"}, dependencies = {}}
    generated.modules.leaf.dependencies = {"runtime"}
    local selected = impact.select(
        generated,
        discovered({
            {status = "deleted", path = "src/nupp/runtime/provider.nupp"}
        })
    )
    equal(selected.affectedModules[1], "leaf", "runtime consumer is affected")
    local foundTop = false
    for _, moduleName in ipairs(selected.affectedModules) do
        foundTop = foundTop or moduleName == "top"
    end
    assert(foundTop, "generated runtime deletion did not reach transitive consumers")
end

function M.aliasPathsResolveToOneModuleIdentity()
    local aliased = graph()
    aliased.modules.leaf.paths = {"src/leaf.nupp", "src/leaf/init.nupp"}
    local selected = impact.select(aliased, discovered({{status = "modified", path = "src/leaf/init.nupp"}}))
    equal(selected.affectedModules[1], "leaf", "alias maps to the module")
    equal(selected.selectedCases[1].caseId, "through-top", "alias reaches its detecting case")
end

function M.changedSuiteIsSelectedDirectly()
    local selected = impact.select(graph(), discovered({{status = "modified", path = "tests/safetest.lua"}}))
    equal(selected.selectedSuites[1], "tests/safetest.lua", "direct suite")
    equal(#selected.fallbacks, 0, "no fallback")
end

function M.renameUsesBothBaseAndCurrentModuleIdentities()
    local renamedGraph = graph()
    renamedGraph.modules.leaf.paths = {"src/new-leaf.nupp"}
    renamedGraph.modules.leaf.basePaths = {"src/old-leaf.nupp"}
    local selected = impact.select(
        renamedGraph,
        discovered({
            {status = "renamed", oldPath = "src/old-leaf.nupp", path = "src/new-leaf.nupp"}
        })
    )
    equal(selected.selectedCases[1].caseId, "through-top", "renamed module reaches dependent case")
end

function M.currentModulePathIndexCanExplainANewOrMovedPath()
    local selected = impact.select(
        graph(),
        discovered({
            {status = "added", path = "src/current-leaf.nupp"}
        }),
        {
            pathModules = {["src\\current-leaf.nupp"] = {"leaf"}}
        }
    )
    equal(selected.completeScope, false, "current module identity prevents a broad fallback")
    equal(selected.selectedCases[1].caseId, "through-top", "current path reaches dependent case")
end

function M.unknownAndUnexplainedEmptySelectionsBroadenToTheCompleteScope()
    local unknown = impact.select(graph(), discovered({{status = "added", path = "mystery.file"}}))
    equal(unknown.completeScope, true, "unknown path broadens")
    equal(unknown.fallbacks[1].code, "unknown-path", "unknown fallback")
    equal(#unknown.selectedSuites, 2, "complete suite scope")

    local noWitness = graph()
    noWitness.impacts = {}
    local empty = impact.select(noWitness, discovered({{status = "modified", path = "src/leaf.nupp"}}))
    equal(empty.completeScope, true, "unexplained empty broadens")
    equal(empty.fallbacks[1].code, "unexplained-empty", "empty fallback")
end

function M.knownUnaffectingRuleMayExplainAnEmptySelection()
    local selected = impact.select(
        graph(),
        discovered({
            {status = "modified", path = "notes.txt"}
        }),
        {
            classifyPath = function()
                return {scope = "none", code = "prose-only", reason = "not consumed by tests"}
            end,
        }
    )
    equal(selected.completeScope, false, "known path does not broaden")
    equal(selected.emptyReason, "all-changes-known-unaffecting", "safe empty reason")
    equal(#selected.selectedSuites, 0, "no suites")
end

function M.missingIncompleteAndMismatchedGraphsAreStructuredFallbacks()
    local changes = discovered({{status = "modified", path = "src/leaf.nupp"}})
    local incompleteGraph = graph()
    incompleteGraph.complete = false
    equal(impact.select(incompleteGraph, changes).fallbacks[1].code, "graph-incomplete", "incomplete graph")
    local wrongBase = graph()
    wrongBase.base = "another"
    equal(impact.select(wrongBase, changes).fallbacks[1].code, "graph-base-mismatch", "base mismatch")
    local unavailable = impact.select(graph(), {
        available = false,
        code = "git-unavailable",
        reason = "not a work tree"
    })
    equal(unavailable.fallbacks[1].code, "git-unavailable", "diff failure")
end

function M.noChangesIsAProvenEmptySelection()
    local selected = impact.select(graph(), discovered({}))
    equal(selected.completeScope, false, "no changes")
    equal(selected.emptyReason, "no-changes", "empty reason")
end

function M.selectorConsumesTheInternedBinaryStoreGraphShape()
    local store = require("nupp.compiler.testimpact.store")
    local canonical = assert(
        store.canonical({
            stamps = {
                project = "project",
                revision = "base",
                operatingSystem = "os",
                architecture = "arch",
                runtime = "runtime",
                targetProfile = "profile",
                suiteCatalog = "catalog",
                stableIds = "ids",
            },
            paths = {},
            modules = {
                {name = "leaf", path = "src\\leaf.nupp", dependencies = {}},
                {name = "top", path = "src/top.nupp", dependencies = {"leaf"}},
            },
            suites = {
                {
                    path = "tests/storetest.lua",
                    sliceSafe = true,
                    cases = {
                        {id = "through-top", sliceSafe = true, roots = {{module = "top", provenance = "require"}},},
                    },
                },
            },
            complete = true,
            successful = true,
            unfiltered = true,
        })
    )
    local selected = impact.select(canonical, discovered({{status = "modified", path = "src/leaf.nupp"}}))
    equal(selected.completeScope, false, "canonical graph remains selective")
    equal(selected.selectedCases[1].suite, "tests/storetest.lua", "interned suite path")
    equal(selected.selectedCases[1].caseId, "through-top", "interned case id")
end

function M.pathsAreNormalizedBeforeTheyBecomeDiffIdentities()
    equal(impact.normalizePath("./src\\nupp//thing.nupp"), "src/nupp/thing.nupp", "normalized path")
end

return M
