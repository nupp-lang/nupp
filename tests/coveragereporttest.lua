-- What the coverage report says about a run, from the two files a run leaves.
--
-- `nupp test --coverage` end to end is an instrumented build of the whole compiler
-- and a suite run under it; `coveragetest` does that once, under coverage, where
-- it is already paid for. This suite is about the report layer alone, so it
-- writes the state and shard a run would have left and asks what comes out --
-- which is what an editor reads, and has to keep saying the same thing.
local test = require("assert")
local json = require("testjson")
local coverage = require("nupp.compiler.coverage")

local M = {}

local function write(path, text)
    local handle = assert(io.open(path, "wb"))
    handle:write(text)
    handle:close()
end

local function tempdir()
    local base = os.tmpname()
    os.remove(base)
    assert(os.execute("mkdir -p " .. string.format("%q", base)) == 0)
    return base
end

-- One module with every kind of site: a named function spanning three lines, an
-- anonymous one, a statement, and a branch only ever taken one way.
local function run(hits)
    local dir = tempdir()
    local source = dir .. "/sample.nupp"
    write(source, "local function named()\n    return 1\nend\n\nlocal fn = function() end\n")
    write(dir .. "/state.json", json.encode({
        version = 4,
        modules = {
            ["sample"] = {
                output = dir .. "/sample.lua",
                coverage = {
                    path = source,
                    sites = {
                        {id = 1, kind = "function", line = 1, endLine = 3, name = "named"},
                        {id = 2, kind = "statement", line = 2},
                        {id = 3, kind = "branch", line = 2},
                        {id = 4, kind = "function", line = 5},
                    },
                },
            },
        },
        dependencies = {}, outputs = {}, targets = {},
    }))
    write(dir .. "/shard.json", json.encode({hits = {[source] = hits}}))
    local model = coverage.collect(dir .. "/state.json", dir .. "/shard.json")
    assert(os.execute("rm -rf " .. string.format("%q", dir)) == 0)
    test.equal(#model.files, 1)
    local sites = {}
    for _, site in ipairs(model.files[1].sites) do
        sites[site.id] = site
    end
    return model, sites
end

function M.functionSitesCarryTheirDeclaredNameAndSpan()
    local _, sites = run({["1"] = 3, ["2"] = 3})
    test.equal(sites[1].name, "named")
    test.equal(sites[1].line, 1)
    test.equal(sites[1].endLine, 3)
    test.equal(sites[1].count, 3)
end

-- An anonymous function still gets a site, and a report that invented a name for
-- it would be inventing the only thing a reader could use to find it again.
function M.anonymousFunctionSitesAreNamelessRatherThanGuessed()
    local _, sites = run({})
    test.equal(sites[4].name, nil)
    test.equal(sites[4].count, 0)
end

-- The distinction this whole change is for: a condition that ran a hundred times
-- and never once went the other way is not a covered branch, and a report that
-- only says "100" cannot tell anyone that.
function M.branchSitesCarryBothOutcomesSeparately()
    local _, sites = run({["1"] = 1, ["2"] = 100, ["3:true"] = 100, ["3:false"] = 0})
    test.equal(sites[3].kind, "branch")
    test.equal(sites[3].trueCount, 100)
    test.equal(sites[3].falseCount, 0)
end

function M.statementSitesCountWhatReachedThem()
    local _, sites = run({["2"] = 7})
    test.equal(sites[2].kind, "statement")
    test.equal(sites[2].count, 7)
end

-- Both halves of a branch count towards the denominator, so one taken arm is
-- half a branch rather than a whole one.
function M.oneTakenArmIsHalfOfItsBranch()
    local model = select(1, run({["3:true"] = 4}))
    test.equal(model.files[1].branches.total, 2)
    test.equal(model.files[1].branches.covered, 1)
end

function M.nonBranchSitesDoNotClaimOutcomeCounts()
    local _, sites = run({["2"] = 1})
    test.equal(sites[2].trueCount, nil)
    test.equal(sites[1].falseCount, nil)
end

return M
