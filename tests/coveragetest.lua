-- The report is deliberately static: exercise it as a user does, through the public
-- command, and inspect the artifacts rather than reaching into its implementation.
local test = require("assert")
local json = require("testjson")
local highlight = require("nupp.tools.doc.highlight")
local M = {}

local ROOT = debug.getinfo(1, "S").source:match("^@(.+)/tests/")
if not ROOT then
    local p = assert(io.popen("pwd"))
    ROOT = p:read("*l")
    p:close()
end

local function read(path)
    local f = assert(io.open(path, "rb"))
    local text = f:read("*a")
    f:close()
    return text
end

local function coverageReportRunsAndWritesBrowsableArtifacts()
    local out = os.tmpname()
    os.remove(out)
    -- Any suite produces the same report: what is instrumented is the compiler,
    -- so every one of its files is in the artifacts whatever ran. This one is
    -- five tests of string handling, where `runnertest` spawns copies of the
    -- runner and ran them all under an instrumented compiler -- thirty seconds
    -- of the forty-seven this case cost, for coverage percentages nothing here
    -- asserts.
    local command = (
        "cd %q && %q test --coverage --coverage-out %q pathtest 2>&1"
    ):format(ROOT, ROOT .. "/bin/nupp", out)
    local pipe = assert(io.popen(command))
    local output = pipe:read("*a")
    local closed, reason, status = pipe:close()
    assert(closed or (reason == "exit" and status == 0), output)
    test.matches(output, "coverage: lines")
    local report = json.decode(read(out .. "/coverage.json"))
    test.equal(report.schemaVersion, 1)
    assert(#report.files > 0, "coverage report has source files")
    assert(report.summary.lines.total > 0, "coverage report has executable lines")
    local index = read(out .. "/index.html")
    test.matches(index, "<details")
    test.matches(index, "Missed arms")
    assert(#index < 1024 * 1024, "coverage index stays below one megabyte")
    assert(not index:find("Nupp source", 1, true), "coverage index does not embed source pages")
    assert(index:find("--bg:#0d1117", 1, true), "coverage report uses dark theme")
    assert(index:find(".nuppdoc-token-keyword", 1, true), "coverage CSS styles syntax")
    assert(
        index:find("href='files/src/nupp/compiler/lua/gen.nupp/index.html'", 1, true),
        "coverage index links to a file page"
    )
    local genPage = read(out .. "/files/src/nupp/compiler/lua/gen.nupp/index.html")
    test.matches(genPage, "Nupp source")
    test.matches(genPage, "Generated Lua")
    assert(genPage:find("<nav class=breadcrumbs aria-label=Breadcrumb>", 1, true), "coverage pages have breadcrumbs")
    assert(
        genPage:find("href='../../../../../../directories/src/index.html'>src</a>", 1, true),
        "coverage breadcrumbs link each parent layer"
    )
    assert(
        genPage:find("href='../../../../../../directories/src/nupp/compiler/index.html'>compiler</a>", 1, true),
        "coverage breadcrumbs link nested parent layers"
    )
    assert(not index:find("location.hash", 1, true), "coverage navigation uses real pages")
    assert(
        index:find("<details open><summary><a href='directories/src/index.html'", 1, true),
        "coverage tree opens its first level"
    )
    assert(
        index:find("<details open><summary><a href='directories/src/nupp/index.html'", 1, true),
        "coverage tree opens its second level"
    )
    local compilerPage = read(out .. "/directories/src/nupp/compiler/index.html")
    assert(
        compilerPage:find("href='../../../../files/src/nupp/compiler/lua/gen.nupp/index.html'", 1, true),
        "directory summaries link to file pages"
    )
    local query = assert(
        io.popen(("cd %q && %q test --coverage --report-json --coverage-out %q"):format(ROOT, ROOT .. "/bin/nupp", out))
    )
    local queried = query:read("*a")
    local queryClosed, queryReason, queryStatus = query:close()
    assert(queryClosed or (queryReason == "exit" and queryStatus == 0), queried)
    local queriedReport = json.decode(queried)
    test.equal(queriedReport.schemaVersion, 1)
    assert(#queriedReport.files > 0, "report JSON query has every file")
    assert(index:find(".tree a:hover", 1, true), "coverage tree has a hover state")
    assert(index:find("class=sort-indicator", 1, true), "sortable headings show an indicator")
    assert(index:find("aria-sort=none", 1, true), "sortable headings expose their state")
    assert(index:find("td>.status{margin-right:.45rem}", 1, true), "table status dots leave room before filenames")
    local tree = assert(index:match("<nav class=tree>(.-)</nav>"), "coverage tree")
    assert(not tree:find("class='status", 1, true), "file tree omits status circles")
    assert(tree:find("class='file partial'", 1, true), "file tree colors coverage state")
    assert(not tree:find("class=badge", 1, true), "file tree omits percentage badges")
    assert(index:find("class=sidebar-resizer role=separator", 1, true), "sidebar is resizable")
    assert(index:find("data-key=missedLines", 1, true), "missed lines are sortable")
    assert(index:find("data-key=functions", 1, true), "functions are sortable")
    assert(index:find("data-key=missedFunctions", 1, true), "missed functions are sortable")
    assert(index:find("data-key=missedArms", 1, true), "missed arms are sortable")
    test.matches(read(out .. "/lcov.info"), "SF:src/nupp/compiler/")
    assert(os.execute("rm -rf " .. string.format("%q", out)) == 0)
end

-- Building and reporting over an instrumented compiler is coverage work, not a
-- prerequisite for an ordinary test run. The coverage mode sets this for the
-- test process; the cheap syntax-highlighting assertion below still runs normally.
if os.getenv("NUPP_COVERAGE") == "1" then
    M.coverageReportRunsAndWritesBrowsableArtifacts = coverageReportRunsAndWritesBrowsableArtifacts
end

function M.highlightsLongCommentsAcrossSourceLines()
    highlight.configureScintillua(ROOT, {})
    local nupp = highlight.codeLines("--[[ outer\ninside\n]]\nlocal value = 1", "nupp")
    assert(nupp[1]:find("nuppdoc-token-comment", 1, true))
    assert(nupp[2]:find("nuppdoc-token-comment", 1, true))
    assert(nupp[3]:find("nuppdoc-token-comment", 1, true))
    local lua = highlight.codeLines("--[[ outer\ninside\n]]\nlocal value = 1", "lua")
    assert(lua[1]:find("nuppdoc-token-comment", 1, true))
    assert(lua[2]:find("nuppdoc-token-comment", 1, true))
    assert(lua[3]:find("nuppdoc-token-comment", 1, true))
end


-- The VM lowering instruments a module with the sites `nupp.compiler.coverage`
-- numbers, as the Lua generator does, so a report reads either backend's counters
-- against one manifest. These hold the two to the same numbering and the same
-- counts, and an uninstrumented image to exactly what it was.
local FIXTURE = table.concat({
    "module sample",
    "",
    "local record Counter",
    "    count: integer",
    "",
    "    function bump(self): nil",
    "        self.count = self.count + 1",
    "    end",
    "end",
    "",
    "local function classify(n: integer): string",
    "    if n < 0 then",
    "        return \"negative\"",
    "    elseif n == 0 then",
    "        return \"zero\"",
    "    end",
    "    local label = switch n do",
    "        case 1 -> \"one\"",
    "        case 2 -> \"two\"",
    "        else -> \"many\"",
    "    end",
    "    return label",
    "end",
    "",
    "local function find(items: {string}, wanted: string): integer?",
    "    for index, item in ipairs(items) do",
    "        if item == wanted then",
    "            return index",
    "        end",
    "    end",
    "    return nil",
    "end",
    "",
    "local function lookup(items: {string}, wanted: string): string",
    "    if position = find(items, wanted) then",
    "        return \"at \" .. position",
    "    end",
    "    return \"absent\"",
    "end",
    "",
    "export function run(): string",
    "    local counter = new Counter(count = 0)",
    "    local parts: {string} = {}",
    "    for n = -1, 3 do",
    "        counter:bump()",
    "        parts[#parts + 1] = classify(n)",
    "    end",
    "    local total = 0",
    "    repeat",
    "        total = total + 1",
    "    until total >= 3",
    "    while total > 0 do",
    "        total = total - 1",
    "    end",
    "    local twice = |x: integer| -> x * 2",
    "    parts[#parts + 1] = tostring(twice(counter.count))",
    "    parts[#parts + 1] = lookup({\"a\", \"b\"}, \"b\")",
    "    parts[#parts + 1] = lookup({\"a\"}, \"z\")",
    "    return table.concat(parts, \",\")",
    "end",
    "",
    "export function unused(): integer",
    "    return 1",
    "end",
    "",
}, "\n")

-- Where the fixture says it is. Nothing reads the file: it is checked from the text.
local function fixturePath()
    return "coverage-fixture/sample.nupp"
end

local checkEnv = nil

-- A fresh check of `path` as module `name`: each backend annotates the tree it
-- lowers, so neither is handed one the other has been over. The environment is
-- shared, so what the module imports is checked once.
local function checked(path, name)
    checkEnv = checkEnv or require("nupp.compiler.project.env").new(ROOT)
    local env = checkEnv
    local collected = {}
    local source = path == fixturePath() and FIXTURE or nil
    local result = require("nupp.tools.cli.compile").check(path, env, {moduleName = name}, collected, source)
    assert(result, "the fixture checks: " .. tostring(collected[1] and (collected[1].msg or collected[1].message)))

    return result
end

-- The image of module `name` at `path`, instrumented when `covered` is true or
-- names a request of its own, and the manifests the request collected.
local function lowered(path, name, covered)
    local result = checked(path, name)
    local request = covered
    if covered == true then
        request = {
            path = function(candidate)
                return candidate == name and path or nil
            end,
            manifests = {},
        }
    end
    local image = require("nupp.compiler.vm.lower").emit(name, {}, function(candidate)
        return candidate == name and path or nil
    end, function()
        return result.root
    end, nil, nil, require("nupp.compiler.targetlayout").hostKey(), request or nil)

    return image, request and request.manifests or nil
end

local function generated(path, name)
    local code, diagnostics, manifest = require("nupp.compiler.lua.gen").generate(checked(path, name), path, {path = path})
    test.equal(#diagnostics, 0)

    return code, manifest
end

local function sameSites(left, right, label)
    test.equal(#left, #right, label .. ": site count")
    for index, site in ipairs(left) do
        local other = right[index]
        for _, field in ipairs({"id", "kind", "line", "name", "endLine"}) do
            test.equal(site[field], other[field], ("%s: site %d %s"):format(label, index, field))
        end
    end
end

function M.vmLoweringNumbersTheSitesTheGeneratorNumbers()
    local path = fixturePath()
    local _, manifests = lowered(path, "sample", true)
    local _, manifest = generated(path, "sample")
    assert(#manifest.sites > 40, "the fixture has every kind of site")
    test.equal(manifests.sample.path, path)
    sameSites(manifests.sample.sites, manifest.sites, "fixture")
    -- And a module written for its own sake rather than for this test.
    local real = ROOT .. "/src/nupp/compiler/switchplan.nupp"
    local _, realManifests = lowered(real, "nupp.compiler.switchplan", true)
    local _, realManifest = generated(real, "nupp.compiler.switchplan")
    assert(#realManifest.sites > 100, "the module has sites to compare")
    sameSites(realManifests["nupp.compiler.switchplan"].sites, realManifest.sites, "nupp.compiler.switchplan")
end

function M.anUninstrumentedImageIsUnchanged()
    local path = fixturePath()
    local ordinary = lowered(path, "sample", nil)
    local declined = lowered(path, "sample", {
        path = function()
            return nil
        end,
        manifests = {},
    })
    test.equal(declined, ordinary, "a request instrumenting nothing changes nothing")
    assert(not ordinary:find("__nuppCoverage", 1, true), "an ordinary image has no probes")
    assert(not ordinary:find("nupp.runtime.coveragecounter", 1, true), "an ordinary image carries no counters")
    local instrumented = lowered(path, "sample", true)
    assert(instrumented:find("__nuppCoverage", 1, true), "an instrumented image probes")
    assert(instrumented:find("\nmodule nupp.runtime.coveragecounter ", 1, true), "an instrumented image carries its counters")
end

-- Counting the same run the same way is what makes one report hold for either
-- backend. The image only runs on the VM; the generated Lua runs on both.
local function countedRun(run)
    local outer = rawget(_G, "__nuppCoverage")
    local path = fixturePath()
    local previous = outer and outer.hits[path] or nil
    if outer then
        outer.hits[path] = nil
    end
    local result = run()
    local counters = rawget(_G, "__nuppCoverage")
    local hits = counters and counters.hits[path] or {}
    if outer then
        outer.hits[path] = previous
    else
        rawset(_G, "__nuppCoverage", nil)
    end

    return result, hits
end

local function vmImageCountsWhatTheGeneratedLuaCounts()
    local path = fixturePath()
    local image, manifests = lowered(path, "sample", true)
    local vmResult, vmHits = countedRun(function()
        return rawget(_G, "__nupp_load_image")(image)().run()
    end)
    local code = generated(path, "sample")
    -- The generated prelude installs the managed runtime, which a corpus image
    -- carries only when something names it.
    require("nupp.runtime.managed")
    local luaResult, luaHits = countedRun(function()
        return assert(loadstring(code, "@" .. path))().run()
    end)
    test.equal(vmResult, luaResult)
    local reached = 0
    for _, site in ipairs(manifests.sample.sites) do
        local keys = site.kind == "branch" and {site.id .. ":true", site.id .. ":false"} or {tostring(site.id)}
        for _, key in ipairs(keys) do
            test.equal(vmHits[key], luaHits[key], ("%s site %d (%s, line %d)"):format(key, site.id, site.kind, site.line))
            reached = reached + ((vmHits[key] or 0) > 0 and 1 or 0)
        end
    end
    assert(reached > 40, "the run reached the sites it was written to reach")
    for _, site in ipairs(manifests.sample.sites) do
        if site.name == "unused" then
            test.equal(vmHits[tostring(site.id)], nil, "an uncalled function is not counted")
        end
    end
end

if rawget(_G, "__nupp_load_image") then
    M.vmImageCountsWhatTheGeneratedLuaCounts = vmImageCountsWhatTheGeneratedLuaCounts
end

return M
