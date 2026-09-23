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

function M.completeRunPublishesAndDiffSelectsCasesConservatively()
    local directory = os.tmpname()
    os.remove(directory)
    assert(os.execute("mkdir -p " .. string.format("%q", directory .. "/src")) == 0)
    assert(os.execute("mkdir -p " .. string.format("%q", directory .. "/tests")) == 0)

    write(directory .. "/.gitignore", "build/\n")
    write(directory .. "/nupp.lua", 'return {include = {"src"}, build = {entries = {"main"}}}\n')
    write(directory .. "/tests/groups.lua", 'return {leaf = {"leafimpacttest"}, unrelated = {"unrelatedtest"}}\n')
    write(directory .. "/src/main.nupp", "return true\n")
    write(directory .. "/src/leaf.nupp", "return {value = 41}\n")
    write(directory .. "/src/other.nupp", "return {value = 1}\n")
    write(directory .. "/src/hookleaf.nupp", "return {value = 2}\n")
    write(
        directory .. "/tests/leafimpacttest.nupp",
        [[
local test = require("nupp.test")
local M = {}

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

function M.beforeAll(): nil
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

    local fullOutput, fullStatus, fullCommand = run(directory, "--jobs=1 --json", true)
    test.equal(fullStatus, 0, fullCommand .. " failed:\n" .. fullOutput)
    local full = json.decode(fullOutput)
    test.equal(full.total, 5)
    local cache = directory .. "/build/.nupp-test-impact.buf"
    test.assert(exists(cache), "a complete successful clean run did not publish " .. cache)
    test.assert(
        not exists(directory .. "/build/.nupp-test-impact-run/1-stale/fragment.buf"),
        "an abandoned impact fragment directory was not cleaned"
    )
    test.assert(#read(cache) > 0, "the published impact graph was empty")

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

    local shadowOutput, shadowStatus, shadowCommand = run(directory, "--diff --shadow --jobs=1 --json", true)
    test.equal(shadowStatus, 0, shadowCommand .. " failed:\n" .. shadowOutput)
    local shadow = json.decode(shadowOutput)
    test.equal(shadow.total, 5)
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

    local laneOutput, laneStatus, laneCommand = run(directory, "--diff --lane=shared --jobs=2 --json", true)
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
    test.equal(promoted.total, 2)
    test.assert(contains(promoted.selection.selectedSuites, "hookimpacttest"))
    test.equal(#promoted.selection.selectedCases, 0)
    test.assert(#promoted.selection.promotions > 0)

    assert(os.remove(cache))
    local fallbackOutput, fallbackStatus, fallbackCommand = run(directory, "--diff=HEAD --jobs=1 --json", true)
    test.equal(fallbackStatus, 0, fallbackCommand .. " failed:\n" .. fallbackOutput)
    local fallback = json.decode(fallbackOutput)
    test.equal(fallback.total, 5)
    test.equal(fallback.selection.complete, true)
    test.assert(reasonWithCode(fallback.selection.fallbacks, "graph-miss") ~= nil)
    test.equal(#fallback.selection.selectedSuites, 3)

    os.execute("rm -rf " .. string.format("%q", directory))
end

return M
