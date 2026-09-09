-- Selection and timing persistence, exercised through a real runner in a
-- temporary project rather than against this repository's own suite: what these
-- cases assert is what the file on disk says after a run, and running them here
-- would mean rewriting the timings the rest of this run is packed from.
local test = require("assert")
local M = {}

local ROOT = debug.getinfo(1, "S").source:match("^@(.+)/tests/")
if not ROOT then
    local pwd = assert(io.popen("pwd"))
    ROOT = pwd:read("*l")
    pwd:close()
end
ROOT = ROOT:gsub("\\", "/")
local NUPP = os.getenv("NUPP_TEST_BIN") or ROOT .. "/bin/nupp"

local function read(path)
    local file = io.open(path, "rb")
    if not file then
        return nil
    end
    local text = file:read("*a")
    file:close()

    return text
end

local function write(path, text)
    local file = assert(io.open(path, "wb"))
    file:write(text)
    file:close()
end

local function shell(command)
    local pipe = assert(io.popen(command .. " 2>&1; printf '@@%d@@\n' $?"))
    local output = pipe:read("*a") or ""
    pipe:close()
    local status = tonumber(output:match("@@(%d+)@@"))

    return (output:gsub("@@%d+@@\n?", "")), status
end

--- A project with three suites of its own, and a group over two of them.
local function project()
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p " .. ("%q"):format(dir .. "/tests")) == 0)
    for _, name in ipairs({"alpha", "beta", "gamma"}) do
        write(
            ("%s/tests/%stest.lua"):format(dir, name),
            (
                [=[
local test = require("nupp.test")
local M = {}
function M.passes() test.equal(%q, %q) end
return M
]=]
            ):format(name, name)
        )
    end
    write(dir .. "/tests/groups.lua", 'return {pair = {"alphatest", "betatest"}, greek = {"*test"}}\n')

    return dir
end

local function runner(dir, args)
    return shell(("cd %q && NUPP_TEST_BUILD=%q %q test-runner --jobs=1 %s"):format(dir, dir .. "/build", NUPP, args))
end

local function suitesIn(dir)
    local recorded = read(dir .. "/build/.nupp-test-times.json") or ""
    local names = {}
    for name in recorded:gmatch('"(%a+test)"') do
        names[name] = true
    end

    return names, recorded
end

local function discard(dir)
    os.execute("rm -rf " .. ("%q"):format(dir))
end

-- The defect this case exists for: the file was written in place of what was
-- there, so a run that covered part of the selection threw away every other
-- suite's measured duration and the next full run packed its shards blind.
function M.aNarrowRunKeepsTheTimingsItDidNotMeasure()
    local dir = project()
    local everything, status = runner(dir, "--timings=0")
    test.equal(status, 0, "the whole project should run: " .. everything)
    local before = suitesIn(dir)
    for _, name in ipairs({"alphatest", "betatest", "gammatest"}) do
        test.assert(before[name], name .. " should have been timed by the whole run")
    end

    local narrow, narrowStatus = runner(dir, "alphatest --timings=0")
    test.equal(narrowStatus, 0, "the narrow run should succeed: " .. narrow)
    local after, recorded = suitesIn(dir)
    test.assert(after.alphatest, "the suite that ran should be timed")
    test.assert(after.betatest, "a suite the narrow run did not touch should keep its timing: " .. recorded)
    test.assert(after.gammatest, "every untouched suite should keep its timing: " .. recorded)
end

-- The other half of the same rule: an entry for a suite that no longer exists is
-- dropped, so the file tracks the tree rather than accumulating every suite
-- there has ever been.
function M.aRemovedSuiteLeavesTheRecord()
    local dir = project()
    runner(dir, "--timings=0")
    test.assert(suitesIn(dir).gammatest, "gammatest should be timed first")
    os.remove(dir .. "/tests/gammatest.lua")
    runner(dir, "--timings=0")
    local after, recorded = suitesIn(dir)
    test.assert(not after.gammatest, "a deleted suite should leave the record: " .. recorded)
    test.assert(after.alphatest, "the suites that remain should keep their timings")
    discard(dir)
end

function M.aGroupSelectsExactlyItsMembers()
    local dir = project()
    local listing, status = runner(dir, "--list-suites --group=pair")
    test.equal(status, 0, "listing a group should succeed: " .. listing)
    test.equal(listing, "alphatest\nbetatest\n")
    discard(dir)
end

function M.aGlobGroupTracksEverySuiteItMatches()
    local dir = project()
    local listing = runner(dir, "--list-suites --group=greek")
    test.equal(listing, "alphatest\nbetatest\ngammatest\n")
    discard(dir)
end

function M.excludingAGroupLeavesTheRest()
    local dir = project()
    local listing = runner(dir, "--list-suites --exclude-group=pair")
    test.equal(listing, "gammatest\n")
    local single = runner(dir, "--list-suites --exclude=betatest")
    test.equal(single, "alphatest\ngammatest\n")
    discard(dir)
end

-- A group that covers nothing and a group that does not exist are both refused
-- rather than run as an empty selection, because "the step passed" and "the step
-- ran no test" look identical in a log and only one of them is a result.
function M.anUnknownGroupIsRefused()
    local dir = project()
    local output, status = runner(dir, "--list-suites --group=nope")
    test.equal(status, 2, "an unknown group should be refused: " .. output)
    test.matches(output, "no test group named nope")
    test.matches(output, "greek", "the refusal should name the groups there are")
    discard(dir)
end

function M.aGroupMemberThatMatchesNothingIsRefused()
    local dir = project()
    write(dir .. "/tests/groups.lua", 'return {stale = {"deltatest"}}\n')
    local output, status = runner(dir, "--list-suites --group=stale")
    test.equal(status, 2, "a group naming a missing suite should be refused: " .. output)
    test.matches(output, "which matches no suite")
    discard(dir)
end

function M.anUnknownExclusionIsRefused()
    local dir = project()
    local output, status = runner(dir, "--list-suites --exclude=deltatest")
    test.equal(status, 2, "excluding a suite that does not exist should be refused: " .. output)
    test.matches(output, "no test suite named deltatest to exclude")
    discard(dir)
end

return M
