-- Impact selection is stateful across two invocations: a complete clean run
-- records the graph that a later dirty run queries. Keep that lifecycle in one
-- bounded temporary repository rather than making the Nupp checkout itself the
-- fixture.
local test = require("assert")
local json = require("testjson")
local M = {}

local ROOT = debug.getinfo(1, "S").source:match("^@(.+)/tests/")
if not ROOT then
    local process = assert(io.popen("pwd"))
    ROOT = process:read("*l")
    process:close()
end
ROOT = ROOT:gsub("\\", "/")
local NUPP = os.getenv("NUPP_TEST_BIN") or ROOT .. "/bin/nupp"
local EXIT = "@@nupp_test_impact_exit:"

local function write(path, contents)
    local file = assert(io.open(path, "wb"))
    file:write(contents)
    file:close()
end

local function read(path)
    local file = assert(io.open(path, "rb"))
    local contents = file:read("*a")
    file:close()

    return contents
end

local function exists(path)
    local file = io.open(path, "rb")
    if not file then
        return false
    end
    file:close()

    return true
end

local function lineCount(path)
    if not exists(path) then
        return 0
    end
    local _, count = read(path):gsub("\n", "")

    return count
end

local function run(directory, arguments, jsonOnly)
    local redirect = jsonOnly and "2>/dev/null" or "2>&1"
    local command = ("cd %q && NUPP_TEST_IMPACT_RECORD=1 %q test %s %s"):format(directory, NUPP, arguments, redirect)
    local process = assert(io.popen(("%s; printf '%s%%d@@\\n' $?"):format(command, EXIT)))
    local output = process:read("*a") or ""
    process:close()
    local status = tonumber(output:match(EXIT .. "(%d+)@@"))
    output = output:gsub(EXIT .. "%d+@@\n?", "")

    return output, status, command
end

local function shell(directory, command)
    local status = os.execute(("cd %q && %s"):format(directory, command))
    assert(status == 0, command .. " failed with " .. tostring(status))
end

local function contains(values, wanted)
    for _, value in ipairs(values or {}) do
        if value == wanted then
            return true
        end
    end

    return false
end

local function reasonWithCode(reasons, wanted)
    for _, reason in ipairs(reasons or {}) do
        if reason.code == wanted then
            return reason
        end
    end
end

local function plannedPieces(report, suite)
    local count = 0
    for _, shard in ipairs(report.shards or {}) do
        for _, spec in ipairs(shard.specs or {}) do
            local name = tostring(spec):match("^(.-)#") or spec
            if name == suite then
                count = count + 1
            end
        end
    end

    return count
end

function M.completeRunPublishesAndDiffSelectsCasesConservatively()
    local directory = os.tmpname()
    os.remove(directory)
    assert(os.execute("mkdir -p " .. string.format("%q", directory .. "/src")) == 0)
    assert(os.execute("mkdir -p " .. string.format("%q", directory .. "/tests")) == 0)
    assert(os.execute("mkdir -p " .. string.format("%q", directory .. "/failing-project/src")) == 0)
    assert(os.execute("mkdir -p " .. string.format("%q", directory .. "/successful-project/src")) == 0)

    write(directory .. "/.gitignore", "build/\n")
    write(directory .. "/nupp.lua", 'return {include = {"src"}, build = {entries = {"main"}}}\n')
    write(directory .. "/tests/groups.lua", 'return {leaf = {"leafimpacttest"}, unrelated = {"unrelatedtest"}}\n')
    write(directory .. "/src/main.nupp", "return true\n")
    write(directory .. "/src/leaf.nupp", "return {value = 41}\n")
    write(directory .. "/src/other.nupp", "return {value = 1}\n")
    write(directory .. "/src/hookleaf.nupp", "return {value = 2}\n")
    write(directory .. "/src/planall.nupp", "return {value = 40}\n")
    write(directory .. "/src/planshared.nupp", "return {value = 2}\n")
    write(directory .. "/failing-project/nupp.lua", 'return {include = {"src"}, build = {entries = {"main"}}}\n')
    write(directory .. "/failing-project/src/main.g.nupp", 'return require("leaf")\n')
    write(directory .. "/failing-project/src/leaf.g.nupp", "local =\n")
    write(
        directory .. "/successful-project/nupp.lua",
        'return {include = {"src"}, build = {entries = {"nestedmain"}}}\n'
    )
    write(directory .. "/successful-project/src/nestedmain.nupp", "return true\n")
    write(directory .. "/src/parallel-a.nupp", "return {value = 'a'}\n")
    write(directory .. "/src/parallel-b.nupp", "return {value = 'b'}\n")
    write(directory .. "/process-impact-mode", "failing\n")
    write(
        directory .. "/src/nested.g.nupp",
        (
            [=[
local command = %q
if package.config:sub(1, 1) == "\\" then
    command = '"' .. command .. '"'
end
assert(os.execute(command) == 0)
return true
]=]
        ):format(("%q check src/main.nupp"):format(NUPP))
    )
    write(
        directory .. "/tests/leafimpacttest.nupp",
        [[
local test = require("nupp.test")
local M = {}

-- os.execute("lane marker") keeps this fixture on the fresh-process queue so
-- its exact-case selection proves that queue children inherit case metadata.
local discovery = assert(io.open("build/leaf-impact-discoveries", "ab"))
discovery:write("loaded\n")
discovery:close()

function M.usesLeaf(): nil
    local leaf = require("leaf")
    test.equal(leaf.value, 41)
end

function M.usesOther(): nil
    local other = require("other")
    test.equal(other.value, 1)
end

return M
]]
    )
    write(
        directory .. "/tests/hookimpacttest.nupp",
        [[
local test = require("nupp.test")
local M = {}

local discovery = assert(io.open("build/hook-impact-discoveries", "ab"))
discovery:write("loaded\n")
discovery:close()

function M.beforeAll(): nil
    local executions = assert(io.open("build/hook-impact-before-all", "ab"))
    executions:write("called\n")
    executions:close()
end

function M.usesHookLeaf(): nil
    local leaf = require("hookleaf")
    test.equal(leaf.value, 2)
end

function M.hookPeer(): nil
    test.equal(20 + 22, 42)
end

return M
]]
    )
    write(
        directory .. "/tests/hookpeerimpacttest.nupp",
        [[
local test = require("nupp.test")
local M = {}

function M.peer(): nil
    local leaf = require("hookleaf")
    test.equal(leaf.value, 2)
end

return M
]]
    )
    write(
        directory .. "/tests/shapeshifttest.nupp",
        [[
local test = require("nupp.test")
local M = {}

function M.first(): nil
    test.equal(20 + 22, 42)
end

function M.second(): nil
    test.equal(6 * 7, 42)
end

return M
]]
    )
    write(
        directory .. "/tests/planimpacttest.nupp",
        [[
local test = require("nupp.test")
local M = {}

local discovery = assert(io.open("build/plan-impact-discoveries", "ab"))
discovery:write("loaded\n")
discovery:close()

function M.alpha(): nil
    local all = require("planall")
    local shared = require("planshared")
    test.equal(all.value + shared.value, 42)
end

function M.beta(): nil
    local all = require("planall")
    local shared = require("planshared")
    test.equal(all.value + shared.value, 42)
end

function M.gamma(): nil
    local all = require("planall")
    test.equal(all.value + 2, 42)
end

function M.delta(): nil
    local all = require("planall")
    test.equal(all.value + 2, 42)
end

return M
]]
    )
    write(
        directory .. "/tests/planpeerimpacttest.nupp",
        [[
local test = require("nupp.test")
local M = {}

function M.peer(): nil
    local all = require("planall")
    local shared = require("planshared")
    test.equal(all.value + shared.value, 42)
end

return M
]]
    )
    write(
        directory .. "/tests/processimpacttest.lua",
        (
            [=[
local M = {}
local NUPP = %q

function M.argumentContainingNuppIsNotACompilerLaunch()
    assert(os.execute("mkdir -p build/path-containing-nupp") == 0)
end

function M.expectedCompilerFailureStillHasACompleteFragment()
    assert(os.execute(("%%q check missing-impact-file.nupp"):format(NUPP)) ~= 0)
end

function M.missingBuildRunAndAotRemainConservative()
    local mode = assert(io.open("process-impact-mode", "rb"))
    local value = mode:read("*l")
    mode:close()
    if value ~= "commands" then
        assert(os.execute(("%%q check missing-command-input.nupp"):format(NUPP)) ~= 0)
        return
    end
    for _, command in ipairs({"build", "run", "aot"}) do
        assert(os.execute(("%%q %%s missing-command-input.nupp"):format(NUPP, command)) ~= 0)
    end
end

function M.failingExistingImportRemainsConservativelyUncertain()
    local mode = assert(io.open("process-impact-mode", "rb"))
    local value = mode:read("*l")
    mode:close()
    if value == "missing" then
        assert(os.execute(("%%q check process-clean-missing.nupp"):format(NUPP)) ~= 0)
        return
    end
    assert(os.execute(("cd failing-project && %%q build"):format(NUPP)) ~= 0)
end

function M.nestedCompilerFragmentsMergeRecursively()
    assert(os.execute(("%%q run src/nested.g.nupp"):format(NUPP)) == 0)
end

return M
]=]
        ):format(NUPP)
    )
    write(
        directory .. "/tests/manifestimpacttest.lua",
        (
            [=[
local M = {}
local NUPP = %q

function M.successfulNestedBuildOwnsItsManifest()
    assert(os.execute(("cd successful-project && %%q build"):format(NUPP)) == 0)
end

return M
]=]
        ):format(NUPP)
    )
    for _, side in ipairs({"a", "b"}) do
        local other = side == "a" and "b" or "a"
        write(
            directory .. "/tests/parallelimpact" .. side .. "test.lua",
            (
                [=[
local M = {}
local NUPP = %q

function M.launchesDistinctCompilerChild()
    local marker = "build/parallel-impact-%s-ready"
    local other = "build/parallel-impact-%s-ready"
    local file = assert(io.open(marker, "wb"))
    file:write("ready\n")
    file:close()
    local deadline = os.time() + 30
    repeat
        local ready = io.open(other, "rb")
        if ready then
            ready:close()
            break
        end
    until os.time() >= deadline
    local ready = assert(io.open(other, "rb"), "parallel compiler barrier timed out")
    ready:close()
    assert(os.execute(("%%q check src/parallel-%s.nupp"):format(NUPP)) == 0)
end

return M
]=]
            ):format(NUPP, side, other, side)
        )
    end
    write(directory .. "/tests/unrelatedtest.lua", [[
return {passes = function() assert(true) end}
]])

    shell(directory, "git init -q")
    shell(directory, "git config user.name test-impact")
    shell(directory, "git config user.email test-impact@example.invalid")
    shell(directory, "git add .")
    shell(directory, "git commit -qm initial")

    assert(os.execute("mkdir -p " .. string.format("%q", directory .. "/build/.nupp-test-impact-run/1-stale")) == 0)
    write(directory .. "/build/.nupp-test-impact-run/1-stale/fragment.buf", "abandoned")

    local fullOutput, fullStatus, fullCommand = run(directory, "--jobs=2 --json", true)
    test.equal(fullStatus, 0, fullCommand .. " failed:\n" .. fullOutput)
    local full = json.decode(fullOutput)
    test.equal(full.total, 21)
    local cache = directory .. "/build/.nupp-test-impact.buf"
    test.assert(exists(cache), "a complete successful clean run did not publish " .. cache)
    test.assert(
        not exists(directory .. "/build/.nupp-test-impact-run/1-stale/fragment.buf"),
        "an abandoned impact fragment directory was not cleaned"
    )
    test.assert(#read(cache) > 0, "the published impact graph was empty")

    local function seedPlanTimings()
        write(
            directory .. "/build/.nupp-test-times.json",
            [[
{"suites":{"planimpacttest":4000,"planpeerimpacttest":100,"hookimpacttest":2000,"hookpeerimpacttest":100,"unrelatedtest":500},
 "cases":{"planimpacttest":{"alpha":1000,"beta":1000,"gamma":1000,"delta":1000},
          "planpeerimpacttest":{"peer":100},
          "hookimpacttest":{"usesHookLeaf":1000,"hookPeer":1000},
          "hookpeerimpacttest":{"peer":100},
          "unrelatedtest":{"passes":500}}}
]]
        )
    end

    seedPlanTimings()
    local partialDiscoveries = lineCount(directory .. "/build/plan-impact-discoveries")
    write(directory .. "/src/planshared.nupp", "return {value = 2, changed = true}\n")
    local partialOutput, partialStatus, partialCommand = run(
        directory,
        "planimpacttest planpeerimpacttest --diff --jobs=2 --json",
        true
    )
    test.equal(partialStatus, 0, partialCommand .. " failed:\n" .. partialOutput)
    local partial = json.decode(partialOutput)
    test.equal(partial.total, 3, partialOutput)
    test.assert(contains(partial.selection.selectedCases, "planimpacttest/alpha"))
    test.assert(contains(partial.selection.selectedCases, "planimpacttest/beta"))
    test.equal(plannedPieces(partial, "planimpacttest"), 2, partialOutput)
    test.equal(lineCount(directory .. "/build/plan-impact-discoveries") - partialDiscoveries, 2)
    shell(directory, "git checkout -q -- src/planshared.nupp")

    seedPlanTimings()
    write(directory .. "/src/planall.nupp", "return {value = 40, changed = true}\n")
    local wholeOutput, wholeStatus, wholeCommand = run(
        directory,
        "planimpacttest planpeerimpacttest --diff --jobs=2 --json",
        true
    )
    test.equal(wholeStatus, 0, wholeCommand .. " failed:\n" .. wholeOutput)
    local whole = json.decode(wholeOutput)
    test.equal(whole.total, 5, wholeOutput)
    test.assert(contains(whole.selection.selectedSuites, "planimpacttest"))
    test.equal(#whole.selection.selectedCases, 0)
    local wholePieces = plannedPieces(whole, "planimpacttest")
    test.assert(wholePieces > 1, "a complete safe case catalog did not coalesce and shard:\n" .. wholeOutput)
    local laneFilteredOutput, laneFilteredStatus, laneFilteredCommand = run(
        directory,
        "planimpacttest planpeerimpacttest --diff --lane=shell --jobs=2 --json",
        true
    )
    test.equal(laneFilteredStatus, 0, laneFilteredCommand .. " failed:\n" .. laneFilteredOutput)
    local laneFiltered = json.decode(laneFilteredOutput)
    test.equal(laneFiltered.total, 0, laneFilteredOutput)
    test.equal(laneFiltered.selection.emptyReason, "outside-requested-scope")
    shell(directory, "git checkout -q -- src/planall.nupp")

    seedPlanTimings()
    local statefulDiscoveries = lineCount(directory .. "/build/hook-impact-discoveries")
    local statefulHooks = lineCount(directory .. "/build/hook-impact-before-all")
    write(directory .. "/src/hookleaf.nupp", "return {value = 2, changed = true}\n")
    local statefulOutput, statefulStatus, statefulCommand = run(
        directory,
        "--diff --case=hookimpacttest/usesHookLeaf --case=hookpeerimpacttest/peer --jobs=2 --json",
        true
    )
    test.equal(statefulStatus, 0, statefulCommand .. " failed:\n" .. statefulOutput)
    local stateful = json.decode(statefulOutput)
    test.equal(stateful.total, 2, statefulOutput)
    test.assert(contains(stateful.selection.selectedCases, "hookimpacttest/usesHookLeaf"))
    test.equal(plannedPieces(stateful, "hookimpacttest"), 1, statefulOutput)
    test.equal(lineCount(directory .. "/build/hook-impact-discoveries") - statefulDiscoveries, 1)
    test.equal(lineCount(directory .. "/build/hook-impact-before-all") - statefulHooks, 1)
    shell(directory, "git checkout -q -- src/hookleaf.nupp")

    seedPlanTimings()
    local unsafeDiscoveries = lineCount(directory .. "/build/hook-impact-discoveries")
    local unsafeHooks = lineCount(directory .. "/build/hook-impact-before-all")
    write(directory .. "/src/hookleaf.nupp", "return {value = 2, changed = true}\n")
    local unsafeOutput, unsafeStatus, unsafeCommand = run(
        directory,
        "--diff --case=hookimpacttest/usesHookLeaf --case=hookimpacttest/hookPeer "
        .. "--case=hookpeerimpacttest/peer --jobs=2 --json",
        true
    )
    test.equal(unsafeStatus, 0, unsafeCommand .. " failed:\n" .. unsafeOutput)
    local unsafe = json.decode(unsafeOutput)
    test.equal(unsafe.total, 3, unsafeOutput)
    test.assert(contains(unsafe.selection.selectedSuites, "hookimpacttest"))
    test.equal(#unsafe.selection.selectedCases, 0)
    test.equal(plannedPieces(unsafe, "hookimpacttest"), 1, unsafeOutput)
    test.equal(lineCount(directory .. "/build/hook-impact-discoveries") - unsafeDiscoveries, 1)
    test.equal(lineCount(directory .. "/build/hook-impact-before-all") - unsafeHooks, 1)
    shell(directory, "git checkout -q -- src/hookleaf.nupp")

    seedPlanTimings()
    local guardDiscoveries = lineCount(directory .. "/build/hook-impact-discoveries")
    local guardHooks = lineCount(directory .. "/build/hook-impact-before-all")
    write(directory .. "/src/hookleaf.nupp", "return {value = 2, changed = true}\n")
    local guardOutput, guardStatus, guardCommand = run(
        directory,
        "--diff --case=hookimpacttest/usesHookLeaf --case=hookimpacttest/hookPeer "
        .. "--case=hookimpacttest/missing --case=hookpeerimpacttest/peer --jobs=2 --json",
        false
    )
    test.equal(guardStatus, 2, guardCommand .. " did not reject a missing selected ID:\n" .. guardOutput)
    test.matches(guardOutput, "no test case named hookimpacttest/missing")
    test.assert(
        not guardOutput:match("no test case named [^\n]*hookimpacttest/usesHookLeaf"),
        "the coalescing guard lost a valid worker acknowledgment:\n" .. guardOutput
    )
    test.equal(lineCount(directory .. "/build/hook-impact-discoveries") - guardDiscoveries, 1)
    test.equal(lineCount(directory .. "/build/hook-impact-before-all") - guardHooks, 0)
    shell(directory, "git checkout -q -- src/hookleaf.nupp")

    for _, side in ipairs({"a", "b"}) do
        local other = side == "a" and "b" or "a"
        write(directory .. "/src/parallel-" .. side .. ".nupp", "return {value = 'changed'}\n")
        local parallelListing, parallelStatus, parallelCommand = run(directory, "--diff --list-cases", false)
        test.equal(parallelStatus, 0, parallelCommand .. " failed:\n" .. parallelListing)
        test.matches(parallelListing, "parallelimpact" .. side .. "test/launchesDistinctCompilerChild")
        test.assert(
            not parallelListing:match("parallelimpact" .. other .. "test/launchesDistinctCompilerChild"),
            "parallel child fragments crossed owners:\n" .. parallelListing
        )
        shell(directory, "git checkout -q -- src/parallel-" .. side .. ".nupp")
    end

    write(directory .. "/missing-impact-file.nupp", "return true\n")
    local addedListing, addedStatus, addedCommand = run(directory, "--diff --list-cases", false)
    test.equal(addedStatus, 0, addedCommand .. " failed:\n" .. addedListing)
    test.matches(addedListing, "processimpacttest/expectedCompilerFailureStillHasACompleteFragment")
    assert(os.remove(directory .. "/missing-impact-file.nupp"))

    write(directory .. "/failing-project/src/leaf.g.nupp", "local function =\n")
    local failingListing, failingStatus, failingCommand = run(directory, "--diff --list-cases", false)
    test.equal(failingStatus, 0, failingCommand .. " failed:\n" .. failingListing)
    test.matches(failingListing, "processimpacttest/failingExistingImportRemainsConservativelyUncertain")
    shell(directory, "git checkout -q -- failing-project/src/leaf.g.nupp")
    write(directory .. "/process-impact-mode", "commands\n")
    shell(directory, "git add process-impact-mode")
    shell(directory, "git commit -qm exercise-noncheck-failures")
    local commandOutput, commandStatus, commandLine = run(directory, "--jobs=2 --json", true)
    test.equal(commandStatus, 0, commandLine .. " failed:\n" .. commandOutput)
    test.equal(json.decode(commandOutput).total, 21)
    write(directory .. "/nupp.lua", 'return {include = {"src"}, build = {entries = {"main"}, optimize = 1}}\n')
    local commandListing, commandListingStatus, commandListingLine = run(directory, "--diff --list-cases", false)
    test.equal(commandListingStatus, 0, commandListingLine .. " failed:\n" .. commandListing)
    test.matches(commandListing, "processimpacttest/missingBuildRunAndAotRemainConservative")
    shell(directory, "git checkout -q -- nupp.lua")
    write(directory .. "/process-impact-mode", "missing\n")
    shell(directory, "git add process-impact-mode")
    shell(directory, "git commit -qm stabilize-process-impact")
    local refreshedOutput, refreshedStatus, refreshedCommand = run(directory, "--jobs=2 --json", true)
    test.equal(refreshedStatus, 0, refreshedCommand .. " failed:\n" .. refreshedOutput)
    test.equal(json.decode(refreshedOutput).total, 21)

    write(
        directory .. "/successful-project/nupp.lua",
        'return {include = {"src"}, build = {entries = {"nestedmain"}, outDir = "nested-out"}}\n'
    )
    local manifestListing, manifestStatus, manifestCommand = run(directory, "--diff --list-cases", false)
    test.equal(manifestStatus, 0, manifestCommand .. " failed:\n" .. manifestListing)
    test.matches(manifestListing, "manifestimpacttest/successfulNestedBuildOwnsItsManifest")
    shell(directory, "git checkout -q -- successful-project/nupp.lua")

    write(
        directory .. "/tests/shapeshifttest.nupp",
        [[
local test = require("nupp.test")
local M = {}

function M.first(): nil
    test.equal(20 + 22, 42)
end

function M.second(): nil
    test.equal(6 * 7, 42)
end

function M.third(): nil
    test.equal(40 + 2, 42)
end

return M
]]
    )
    local staleCatalogOutput, staleCatalogStatus, staleCatalogCommand = run(
        directory,
        "--diff --case=shapeshifttest/first --case=shapeshifttest/second --jobs=2 --json",
        true
    )
    test.equal(staleCatalogStatus, 0, staleCatalogCommand .. " failed:\n" .. staleCatalogOutput)
    local staleCatalog = json.decode(staleCatalogOutput)
    test.equal(staleCatalog.total, 2, staleCatalogOutput)
    local staleCatalogIds = {}
    for _, record in ipairs(staleCatalog.tests) do
        staleCatalogIds[record.id] = true
    end
    test.assert(staleCatalogIds["shapeshifttest/first"])
    test.assert(staleCatalogIds["shapeshifttest/second"])
    test.assert(not staleCatalogIds["shapeshifttest/third"], staleCatalogOutput)
    test.assert(contains(staleCatalog.selection.selectedCases, "shapeshifttest/first"))
    test.assert(contains(staleCatalog.selection.selectedCases, "shapeshifttest/second"))
    test.assert(not contains(staleCatalog.selection.selectedSuites, "shapeshifttest"))
    shell(directory, "git checkout -q -- tests/shapeshifttest.nupp")

    write(
        directory .. "/tests/shapeshifttest.nupp",
        [[
local test = require("nupp.test")
local M = {}

local discovery = assert(io.open("build/shape-impact-discoveries", "ab"))
discovery:write("loaded\n")
discovery:close()

function M.beforeAll(): nil
    local executions = assert(io.open("build/shape-impact-before-all", "ab"))
    executions:write("called\n")
    executions:close()
end

function M.first(): nil
    test.equal(20 + 22, 42)
end

function M.second(): nil
    test.equal(6 * 7, 42)
end

return M
]]
    )
    local changedSuiteOutput, changedSuiteStatus, changedSuiteCommand = run(directory, "--diff --jobs=2 --json", true)
    test.equal(changedSuiteStatus, 0, changedSuiteCommand .. " failed:\n" .. changedSuiteOutput)
    local changedSuite = json.decode(changedSuiteOutput)
    test.equal(changedSuite.total, 2, changedSuiteOutput)
    test.assert(contains(changedSuite.selection.selectedSuites, "shapeshifttest"))
    test.assert(reasonWithCode(changedSuite.selection.reasons, "suite-source-changed") ~= nil)
    test.equal(lineCount(directory .. "/build/shape-impact-discoveries"), 1)
    test.equal(lineCount(directory .. "/build/shape-impact-before-all"), 1)
    shell(directory, "git checkout -q -- tests/shapeshifttest.nupp")

    local discoveryBefore = lineCount(directory .. "/build/leaf-impact-discoveries")
    local hookBefore = lineCount(directory .. "/build/hook-impact-before-all")
    local exactOutput, exactStatus, exactCommand = run(
        directory,
        "--case=leafimpacttest/usesLeaf --case=hookimpacttest/usesHookLeaf "
        .. "--case=hookimpacttest/hookPeer --jobs=3 --json",
        true
    )
    test.equal(exactStatus, 0, exactCommand .. " failed:\n" .. exactOutput)
    local exact = json.decode(exactOutput)
    test.equal(exact.total, 3)
    test.assert(#exact.shards >= 2, "the exact-case run did not enter the worker queues")
    test.equal(lineCount(directory .. "/build/leaf-impact-discoveries") - discoveryBefore, 1)
    test.equal(lineCount(directory .. "/build/hook-impact-before-all") - hookBefore, 1)
    local hookSuiteRuns = 0
    for _, suite in ipairs(exact.suites) do
        if suite.suite == "hookimpacttest" then
            hookSuiteRuns = hookSuiteRuns + 1
        end
    end
    test.equal(hookSuiteRuns, 1)

    local missingOutput, missingStatus, missingCommand = run(
        directory,
        "--case=leafimpacttest/usesLeaf --case=leafimpacttest/missing --jobs=2 --json",
        false
    )
    test.equal(missingStatus, 2, missingCommand .. " did not reject a missing case:\n" .. missingOutput)
    test.matches(missingOutput, "no test case named leafimpacttest/missing")
    test.assert(
        not missingOutput:match("no test case named [^\n]*leafimpacttest/usesLeaf"),
        "the parent lost a worker's selected-case acknowledgment:\n" .. missingOutput
    )

    write(directory .. "/src/leaf.nupp", "return {value = 41, changed = true}\n")
    local listing, listingStatus, listingCommand = run(directory, "--diff --list-cases --explain-selection", false)
    test.equal(listingStatus, 0, listingCommand .. " failed:\n" .. listing)
    test.matches(listing, "impact: 1 changed paths")
    test.matches(listing, "src/leaf%.nupp")
    test.matches(listing, "leafimpacttest/usesLeaf")
    test.assert(not listing:match("leafimpacttest/usesOther"), "case listing selected an unaffected case:\n" .. listing)
    test.assert(not listing:match("hookimpacttest/"), "case listing selected an unaffected suite:\n" .. listing)
    local suites, suitesStatus, suitesCommand = run(directory, "--diff --list-suites", false)
    test.equal(suitesStatus, 0, suitesCommand .. " failed:\n" .. suites)
    test.matches(suites, "leafimpacttest")
    test.assert(not suites:match("hookimpacttest"), "suite listing selected an unaffected suite:\n" .. suites)
    test.assert(not suites:match("unrelatedtest"), "suite listing selected an unrelated suite:\n" .. suites)

    local selectedOutput, selectedStatus, selectedCommand = run(directory, "--diff --jobs=1 --json", true)
    test.equal(selectedStatus, 0, selectedCommand .. " failed:\n" .. selectedOutput)
    local selected = json.decode(selectedOutput)
    test.equal(selected.total, 1)
    test.equal(selected.tests[1].id, "leafimpacttest/usesLeaf")
    test.equal(selected.selection.mode, "diff")
    test.equal(selected.selection.complete, false)
    test.assert(contains(selected.selection.changedPaths, "src/leaf.nupp"))
    test.assert(contains(selected.selection.selectedCases, "leafimpacttest/usesLeaf"))
    test.equal(#selected.selection.selectedSuites, 0)
    test.assert(#selected.selection.reasons > 0)
    test.equal(selected.selection.reasons[1].code, "module-impact")
    test.assert(type(selected.selection.queryMs) == "number")
    test.assert(type(selected.selection.selectedWorkMs) == "number")
    test.assert(type(selected.selection.requestedWorkMs) == "number")
    test.assert(type(selected.selection.predictedSavingsPercent) == "number")

    for _, expectation in ipairs({
        {lane = "shared", id = "planimpacttest/alpha"},
        {lane = "shell", id = "leafimpacttest/usesLeaf"},
    }) do
        local shadowLaneOutput, shadowLaneStatus, shadowLaneCommand = run(
            directory,
            (
                "--diff --shadow --lane=%s --case=leafimpacttest/usesLeaf "
            ):format(expectation.lane) .. "--case=planimpacttest/alpha --jobs=1 --json",
            true
        )
        test.equal(shadowLaneStatus, 0, shadowLaneCommand .. " failed:\n" .. shadowLaneOutput)
        local shadowLane = json.decode(shadowLaneOutput)
        test.equal(shadowLane.total, 1, shadowLaneOutput)
        test.equal(shadowLane.tests[1].id, expectation.id)
        for _, reason in ipairs(shadowLane.selection.reasons) do
            if expectation.lane == "shared" then
                test.assert(reason.suite ~= "leafimpacttest", shadowLaneOutput)
            end
        end
    end

    local mixedHookBefore = lineCount(directory .. "/build/hook-impact-before-all")
    local mixedDiscoveryBefore = lineCount(directory .. "/build/hook-impact-discoveries")
    seedPlanTimings()
    write(directory .. "/src/hookleaf.nupp", "return {value = 2, changed = true}\n")
    write(directory .. "/src/planshared.nupp", "return {value = 2, changed = true}\n")
    local mixedOutput, mixedStatus, mixedCommand = run(directory, "--diff --jobs=2 --json", true)
    test.equal(mixedStatus, 0, mixedCommand .. " failed:\n" .. mixedOutput)
    local mixed = json.decode(mixedOutput)
    test.equal(mixed.total, 7)
    local mixedIds = {}
    for _, record in ipairs(mixed.tests) do
        mixedIds[record.id] = true
    end
    test.assert(mixedIds["leafimpacttest/usesLeaf"])
    test.assert(not mixedIds["leafimpacttest/usesOther"])
    test.assert(mixedIds["hookimpacttest/usesHookLeaf"])
    test.assert(mixedIds["hookimpacttest/hookPeer"])
    test.assert(mixedIds["hookpeerimpacttest/peer"])
    test.assert(mixedIds["planimpacttest/alpha"])
    test.assert(mixedIds["planimpacttest/beta"])
    test.assert(not mixedIds["planimpacttest/gamma"])
    test.assert(not mixedIds["planimpacttest/delta"])
    test.assert(mixedIds["planpeerimpacttest/peer"])
    test.assert(contains(mixed.selection.selectedCases, "leafimpacttest/usesLeaf"))
    test.assert(contains(mixed.selection.selectedSuites, "hookimpacttest"))
    local shardedSuites = {}
    for _, suite in ipairs(mixed.suites) do
        if suite.shard ~= nil then
            shardedSuites[suite.suite] = true
        end
    end
    local schedulingEvidence = "\nsuites: " .. json.encode(mixed.suites) .. "\nshards: " .. json.encode(mixed.shards)
    test.assert(shardedSuites.leafimpacttest, "the exact-case suite bypassed the worker queue" .. schedulingEvidence)
    test.assert(
        shardedSuites.hookimpacttest,
        "the whole-suite promotion bypassed the worker queue" .. schedulingEvidence
    )
    test.assert(#mixed.shards >= 2, "mixed case and suite selection did not use parallel workers")
    test.equal(plannedPieces(mixed, "planimpacttest"), 2, mixedOutput)
    test.equal(plannedPieces(mixed, "hookimpacttest"), 1, mixedOutput)
    test.equal(lineCount(directory .. "/build/hook-impact-before-all") - mixedHookBefore, 1)
    test.equal(lineCount(directory .. "/build/hook-impact-discoveries") - mixedDiscoveryBefore, 1)

    seedPlanTimings()
    local lanePlanOutput, lanePlanStatus, lanePlanCommand = run(directory, "--diff --lane=shared --jobs=2 --json", true)
    test.equal(lanePlanStatus, 0, lanePlanCommand .. " failed:\n" .. lanePlanOutput)
    local lanePlan = json.decode(lanePlanOutput)
    test.equal(lanePlan.total, 6, lanePlanOutput)
    test.equal(lanePlan.selection.selectedWorkMs, 4200)
    test.equal(lanePlan.selection.requestedWorkMs, 6700)
    test.equal(lanePlan.selection.predictedSavingsMs, 2500)
    test.equal(plannedPieces(lanePlan, "planimpacttest"), 2, lanePlanOutput)
    test.equal(plannedPieces(lanePlan, "hookimpacttest"), 1, lanePlanOutput)
    for _, reason in ipairs(lanePlan.selection.reasons) do
        test.assert(reason.suite ~= "leafimpacttest", lanePlanOutput)
    end
    test.assert(not contains(lanePlan.selection.selectedCases, "leafimpacttest/usesLeaf"))
    test.assert(not contains(lanePlan.selection.selectedSuites, "leafimpacttest"))
    shell(directory, "git checkout -q -- src/hookleaf.nupp")
    shell(directory, "git checkout -q -- src/planshared.nupp")

    local shadowOutput, shadowStatus, shadowCommand = run(directory, "--diff --shadow --jobs=1 --json", true)
    test.equal(shadowStatus, 0, shadowCommand .. " failed:\n" .. shadowOutput)
    local shadow = json.decode(shadowOutput)
    test.equal(shadow.total, 21)
    test.equal(shadow.selection.shadow, true)
    test.assert(contains(shadow.selection.selectedCases, "leafimpacttest/usesLeaf"))

    local groupedOutput, groupedStatus, groupedCommand = run(directory, "--diff --group=leaf --jobs=2 --json", true)
    test.equal(groupedStatus, 0, groupedCommand .. " failed:\n" .. groupedOutput)
    local grouped = json.decode(groupedOutput)
    test.equal(grouped.total, 1)
    test.equal(grouped.tests[1].id, "leafimpacttest/usesLeaf")

    local excludedOutput, excludedStatus, excludedCommand = run(
        directory,
        "--diff --exclude=leafimpacttest --jobs=1 --json",
        true
    )
    test.equal(excludedStatus, 0, excludedCommand .. " failed:\n" .. excludedOutput)
    local excluded = json.decode(excludedOutput)
    test.equal(excluded.total, 0)
    test.equal(excluded.selection.fallbacks[#excluded.selection.fallbacks].code, "user-excluded")

    local excludedGroupOutput, excludedGroupStatus, excludedGroupCommand = run(
        directory,
        "--diff --exclude-group=leaf --jobs=1 --json",
        true
    )
    test.equal(excludedGroupStatus, 0, excludedGroupCommand .. " failed:\n" .. excludedGroupOutput)
    local excludedGroup = json.decode(excludedGroupOutput)
    test.equal(excludedGroup.total, 0)
    test.equal(excludedGroup.selection.fallbacks[#excludedGroup.selection.fallbacks].code, "user-excluded")

    local laneOutput, laneStatus, laneCommand = run(directory, "--diff --lane=shell --jobs=2 --json", true)
    test.equal(laneStatus, 0, laneCommand .. " failed:\n" .. laneOutput)
    local laneSelected = json.decode(laneOutput)
    test.equal(laneSelected.total, 1)

    local intersectedOutput, intersectedStatus, intersectedCommand = run(
        directory,
        "--diff unrelatedtest --jobs=1 --json",
        true
    )
    test.equal(intersectedStatus, 0, intersectedCommand .. " failed:\n" .. intersectedOutput)
    local intersected = json.decode(intersectedOutput)
    test.equal(intersected.total, 0)
    test.equal(intersected.selection.emptyReason, "outside-requested-scope")

    local caseOutput, caseStatus, caseCommand = run(
        directory,
        "--diff --case=leafimpacttest/usesOther --jobs=1 --json",
        true
    )
    test.equal(caseStatus, 0, caseCommand .. " failed:\n" .. caseOutput)
    local caseIntersection = json.decode(caseOutput)
    test.equal(caseIntersection.total, 0)
    test.equal(caseIntersection.selection.emptyReason, "outside-requested-scope")

    write(directory .. "/src/leaf.nupp", "return {value = 40}\n")
    local defectOutput, defectStatus, defectCommand = run(directory, "--diff --jobs=1 --json", true)
    test.equal(defectStatus, 1, defectCommand .. " did not expose the seeded leaf defect:\n" .. defectOutput)
    local defect = json.decode(defectOutput)
    test.equal(defect.total, 1)
    test.equal(defect.failed, 1)
    test.equal(defect.tests[1].id, "leafimpacttest/usesLeaf")

    shell(directory, "git checkout -q -- src/leaf.nupp")
    write(directory .. "/src/hookleaf.nupp", "return {value = 2, changed = true}\n")
    local promotedOutput, promotedStatus, promotedCommand = run(directory, "--diff --jobs=1 --json", true)
    test.equal(promotedStatus, 0, promotedCommand .. " failed:\n" .. promotedOutput)
    local promoted = json.decode(promotedOutput)
    test.equal(promoted.total, 3, promotedOutput)
    test.assert(contains(promoted.selection.selectedSuites, "hookimpacttest"))
    test.equal(#promoted.selection.selectedCases, 0)
    test.assert(#promoted.selection.promotions > 0)

    assert(os.remove(cache))
    local scopedFallbackOutput, scopedFallbackStatus, scopedFallbackCommand = run(
        directory,
        "--diff=HEAD --case=leafimpacttest/usesLeaf --jobs=1 --json",
        true
    )
    test.equal(scopedFallbackStatus, 0, scopedFallbackCommand .. " failed:\n" .. scopedFallbackOutput)
    local scopedFallback = json.decode(scopedFallbackOutput)
    test.equal(scopedFallback.total, 1, scopedFallbackOutput)
    test.equal(scopedFallback.tests[1].id, "leafimpacttest/usesLeaf")
    test.assert(contains(scopedFallback.selection.selectedCases, "leafimpacttest/usesLeaf"))
    test.assert(reasonWithCode(scopedFallback.selection.fallbacks, "graph-miss") ~= nil)

    local fallbackOutput, fallbackStatus, fallbackCommand = run(directory, "--diff=HEAD --jobs=1 --json", true)
    test.equal(fallbackStatus, 0, fallbackCommand .. " failed:\n" .. fallbackOutput)
    local fallback = json.decode(fallbackOutput)
    test.equal(fallback.total, 21)
    test.equal(fallback.selection.complete, true)
    test.assert(reasonWithCode(fallback.selection.fallbacks, "graph-miss") ~= nil)
    test.equal(#fallback.selection.selectedSuites, 11)

    os.execute("rm -rf " .. string.format("%q", directory))
end

return M
