-- The binary observation used by diff-directed test selection. Selection is
-- allowed to narrow only when this file can prove the graph came from the exact
-- project state and a complete run, so malformed data always has to look absent.

local test = require("assert")
local measurements = require("nupp.test")
local impact = require("nupp.compiler.testimpact.store")
local selection = require("nupp.compiler.testimpact.selection")
local binaryStore = require("nupp.compiler.build.store")

local M = {}

local function temporary(suffix)
    local path = os.tmpname() .. suffix
    os.remove(path)
    return path
end

local function stamps(overrides)
    local out = {
        project = "project:4fd0",
        revision = "0123456789abcdef",
        operatingSystem = "Linux",
        architecture = "x86_64",
        runtime = "LuaJIT 2.1",
        targetProfile = "native-debug",
        suiteCatalog = "catalog:32aa",
        stableIds = "suite-path-case-id/1",
    }
    for key, value in pairs(overrides or {}) do
        out[key] = value
    end

    return out
end

local function observation(order)
    local modules = {
        {name = "app.worker", path = "./src\\app/worker.nupp", dependencies = {"app.model", "app.model"},},
        {name = "app.model", path = "src/app/model.nupp", dependencies = {}},
    }
    local suites = {
        {
            path = "./tests\\workertest.lua",
            sliceSafe = true,
            uncertainty = {},
            roots = {{module = "app.worker", provenance = "suite-load"}},
            cases = {
                {
                    id = "second/case",
                    sliceSafe = false,
                    uncertainty = {"child-unattributed"},
                    roots = {{module = "app.worker", provenance = "child-build"}},
                },
                {
                    id = "first:case",
                    sliceSafe = true,
                    uncertainty = {},
                    roots = {
                        {module = "app.model", provenance = "require"},
                        {module = "app.model", provenance = "require"},
                    },
                },
            },
        },
    }
    if order == "reverse" then
        modules[1], modules[2] = modules[2], modules[1]
        suites[1].cases[1], suites[1].cases[2] = suites[1].cases[2], suites[1].cases[1]
    end

    return {
        stamps = stamps(),
        complete = true,
        successful = true,
        unfiltered = true,
        paths = {"generated/input.nupp", "generated/input.nupp"},
        modules = modules,
        suites = suites,
    }
end

local function read(path)
    local file = assert(io.open(path, "rb"))
    local bytes = file:read("*a")
    file:close()
    return bytes
end

function M.caseIdentityUsesTheNormalizedSuitePathAndBothLengths()
    local first = assert(impact.caseIdentity("./tests\\a/btest.lua", "c:d"))
    local second = assert(impact.caseIdentity("tests/a/btest.lua", "c:d"))
    test.equal(first, second)
    test.equal(first, "17:tests/a/btest.lua3:c:d")
    test.equal(assert(impact.caseIdentity("tests/nested/../a/btest.lua", "c:d")), first)
    test.equal(impact.caseIdentity("", "case"), nil)
    test.equal(impact.caseIdentity("../tests/a.lua", "case"), nil)
    test.equal(impact.caseIdentity("/tests/a.lua", "case"), nil)
    test.equal(impact.caseIdentity("tests/a.lua", ""), nil)
end

function M.roundTripKeepsInternedEdgesAndSafetyMetadata()
    local path = temporary("-impact.buf")
    local ok, problem = impact.publish(path, observation())
    test.equal(ok, true, problem)
    local graph = assert(impact.load(path, stamps()), "the graph did not round trip")
    test.equal(
        table.concat(graph.paths, ","),
        "generated/input.nupp,src/app/model.nupp,src/app/worker.nupp,tests/workertest.lua"
    )
    test.equal(table.concat(graph.modules, ","), "app.model,app.worker")
    test.equal(graph.modulePaths[1], 2)
    test.equal(graph.modulePaths[2], 3)
    test.equal(table.concat(graph.moduleDependencies[2], ","), "1")
    test.equal(graph.suites[1], 4)
    test.equal(graph.suiteSliceSafe[1], true)
    test.equal(graph.cases[1][2], "first:case")
    test.equal(graph.cases[2][2], "second/case")
    test.equal(graph.caseSliceSafe[1], true)
    test.equal(graph.caseSliceSafe[2], false)
    test.equal(graph.uncertainty[1], "child-unattributed")
    test.equal(graph.caseUncertainty[2][1], 1)
    test.equal(graph.provenance[1], "child-build")
    test.equal(graph.provenance[2], "require")
    test.equal(graph.provenance[3], "suite-load")
    test.equal(graph.suiteRoots[1][1][1], 2)
    test.equal(graph.suiteRoots[1][1][2], 3)
    test.equal(graph.caseRoots[1][1][1], 1)
    test.equal(graph.caseRoots[1][1][2], 2)
    os.remove(path)
end

function M.encodingIsDeterministicAcrossInputOrder()
    local first = temporary("-first.buf")
    local second = temporary("-second.buf")
    assert(impact.publish(first, observation()))
    assert(impact.publish(second, observation("reverse")))
    test.equal(read(first), read(second), "equivalent observations produced different bytes")
    os.remove(first)
    os.remove(second)
end

function M.everyIdentityStampMustMatchExactly()
    local path = temporary("-impact.buf")
    assert(impact.publish(path, observation()))
    local fields = {
        "project",
        "revision",
        "operatingSystem",
        "architecture",
        "runtime",
        "targetProfile",
        "suiteCatalog",
        "stableIds",
    }
    for _, field in ipairs(fields) do
        test.equal(impact.load(path, stamps({[field] = "different"})), nil, field .. " mismatch was accepted")
    end
    -- `openValue` discards a different stamp in memory only; matching again reads
    -- the unchanged file.
    test.assert(impact.load(path, stamps()) ~= nil, "the exact identity no longer hits")
    os.remove(path)
end

function M.corruptTruncatedAndWrongVersionFilesAreMisses()
    local corrupt = temporary("-corrupt.buf")
    local file = assert(io.open(corrupt, "wb"))
    file:write("not a string.buffer value")
    file:close()
    test.equal(impact.load(corrupt, stamps()), nil)

    local full = temporary("-full.buf")
    assert(impact.publish(full, observation()))
    local bytes = read(full)
    local truncated = temporary("-truncated.buf")
    file = assert(io.open(truncated, "wb"))
    file:write(bytes:sub(1, math.floor(#bytes / 2)))
    file:close()
    test.equal(impact.load(truncated, stamps()), nil)

    local wrong = observation()
    local graph = assert(impact.canonical(wrong))
    graph.format = impact.FORMAT + 1
    local versionPath = temporary("-version.buf")
    local versioned = binaryStore.openValue(versionPath, assert(impact.cacheStamp(stamps())))
    versioned.set(graph)
    versioned.save()
    test.equal(impact.load(versionPath, stamps()), nil)

    os.remove(corrupt)
    os.remove(full)
    os.remove(truncated)
    os.remove(versionPath)
end

function M.incompleteFailedAndFilteredRunsDoNotReplaceTheGraph()
    local path = temporary("-impact.buf")
    assert(impact.publish(path, observation()))
    local original = read(path)
    for _, field in ipairs({"complete", "successful", "unfiltered"}) do
        local refused = observation()
        refused[field] = false
        local ok, problem = impact.publish(path, refused)
        test.equal(ok, false)
        test.assert(problem:find("complete, successful, unfiltered", 1, true) ~= nil)
        test.equal(read(path), original, field .. " run replaced the graph")
    end
    test.assert(impact.load(path, stamps()) ~= nil, "the authoritative graph was lost")
    os.remove(path)
end

function M.decodedButMalformedGraphsAreMisses()
    local path = temporary("-impact.buf")
    local graph = assert(impact.canonical(observation()))
    graph.moduleDependencies[1] = {#graph.modules + 1}
    local stored = binaryStore.openValue(path, assert(impact.cacheStamp(stamps())))
    stored.set(graph)
    stored.save()
    test.equal(impact.load(path, stamps()), nil)
    os.remove(path)
end

function M.largeGraphRoundTripHasInteractiveCacheCost()
    local path = temporary("-large-impact.buf")
    local modules, cases = {}, {}
    for index = 1, 10000 do
        local name = ("module.%05d"):format(index)
        modules[
            index
        ] = {
            name = name,
            path = ("src/module/%05d.nupp"):format(index),
            dependencies = index > 1 and {("module.%05d"):format(index - 1)} or {},
        }
        cases[
            index
        ] = {id = ("case-%05d"):format(index), sliceSafe = true, roots = {{module = name, provenance = "require"}},}
    end
    local large = {
        stamps = stamps(),
        complete = true,
        successful = true,
        unfiltered = true,
        paths = {},
        modules = modules,
        suites = {{path = "tests/largetest.lua", sliceSafe = true, cases = cases}},
    }

    local beforePublish = os.clock()
    assert(impact.publish(path, large))
    local publishMs = (os.clock() - beforePublish) * 1000
    local beforeLoad = os.clock()
    local graph = assert(impact.load(path, stamps()))
    local loadMs = (os.clock() - beforeLoad) * 1000
    test.equal(#graph.modules, 10000)
    test.equal(#graph.cases, 10000)
    local bytes = #read(path)
    measurements.metric("impact.cache.publish", publishMs, "ms")
    measurements.metric("impact.cache.load", loadMs, "ms")
    measurements.metric("impact.cache.size", bytes, "bytes")
    local querySamples = {}
    for sample = 1, 25 do
        local beforeQuery = os.clock()
        local loaded = assert(impact.load(path, stamps()))
        local selected = selection.select(loaded, {
            available = true,
            base = stamps().revision,
            head = "working",
            changes = {{status = "modified", path = "src/module/05000.nupp"}},
            paths = {"src/module/05000.nupp"},
        })
        test.equal(#selected.selectedCases, 5001)
        querySamples[sample] = (os.clock() - beforeQuery) * 1000
    end
    table.sort(querySamples)
    local queryP95 = querySamples[math.ceil(#querySamples * 0.95)]
    measurements.metric("impact.query.p95", queryP95, "ms")
    test.assert(publishMs < 5000, "publishing a 10,000-case graph took " .. tostring(publishMs) .. " ms")
    if os.getenv("NUPP_TEST_SUPERVISED_PIECE") ~= "1" then
        test.assert(loadMs < 100, "loading a 10,000-case graph took " .. tostring(loadMs) .. " ms")
        test.assert(queryP95 < 100, "10,000-case query p95 took " .. tostring(queryP95) .. " ms")
    end
    os.remove(path)
end

return M
