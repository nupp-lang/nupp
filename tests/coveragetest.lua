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
    -- seven quick tests both runners execute, where `runnertest` spawns copies
    -- of the runner and ran them all under an instrumented compiler -- thirty
    -- seconds of the forty-seven this case cost, for coverage percentages
    -- nothing here asserts. (`pathtest` served until the VM runner began
    -- leaving it to LuaJIT, which made the run report coverage of nothing.)
    local command = (
        "cd %q && %q test --coverage --coverage-out %q coveragereporttest 2>&1"
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
    assert(report.summary.lines.covered > 0, "the run reached instrumented code")
    -- A module the suite loaded ran its top level, and its first statement is there.
    local first = nil
    for _, file in ipairs(report.files) do
        if file.path == "src/nupp/tools/coverage.nupp" then
            for _, site in ipairs(file.sites) do
                if site.kind == "statement" and (not first or site.line < first.line) then
                    first = site
                end
            end
        end
    end
    assert(first and first.count > 0, "a loaded module's top level is counted")
    local index = read(out .. "/index.html")
    test.matches(index, "<details")
    test.matches(index, "Missed arms")
    assert(#index < 1024 * 1024, "coverage index stays below one megabyte")
    assert(not index:find("Nupp source", 1, true), "coverage index does not embed source pages")
    assert(index:find("--bg:#0d1117", 1, true), "coverage report uses dark theme")
    assert(index:find(".nuppdoc-token-keyword", 1, true), "coverage CSS styles syntax")
    assert(
        index:find("href='files/src/nupp/tools/coverage.nupp/index.html'", 1, true),
        "coverage index links to a file page"
    )
    local filePage = read(out .. "/files/src/nupp/tools/coverage.nupp/index.html")
    test.matches(filePage, "Nupp source")
    assert(filePage:find("<nav class=breadcrumbs aria-label=Breadcrumb>", 1, true), "coverage pages have breadcrumbs")
    assert(
        filePage:find("href='../../../../../directories/src/index.html'>src</a>", 1, true),
        "coverage breadcrumbs link each parent layer"
    )
    assert(
        filePage:find("href='../../../../../directories/src/nupp/tools/index.html'>tools</a>", 1, true),
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
    local toolsPage = read(out .. "/directories/src/nupp/tools/index.html")
    assert(
        toolsPage:find("href='../../../../files/src/nupp/tools/coverage.nupp/index.html'", 1, true),
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
local FIXTURE = table.concat(
    {
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
    },
    "\n"
)

-- Where the fixture says it is. Nothing reads the file: it is checked from the text.
local function fixturePath()
    return "coverage-fixture/sample.nupp"
end

local checkEnv = nil
local moduleFixtures = 0

-- A fresh check of `path` as module `name`: each backend annotates the tree it
-- lowers, so neither is handed one the other has been over. The environment is
-- shared, so what the module imports is checked once.
local function checked(path, name, source)
    local isolated = source ~= nil
    local env
    if isolated then
        -- A renamed copy has its own checker facts and never consults a cached
        -- product for the real module at this same coverage source path.
        env = require("nupp.compiler.project.env").new(ROOT, {cache = false})
    else
        checkEnv = checkEnv or require("nupp.compiler.project.env").new(ROOT)
        env = checkEnv
        source = path == fixturePath() and FIXTURE or nil
    end
    local collected = {}
    local result = require("nupp.tools.cli.compile").check(path, env, {moduleName = name}, collected, source)
    assert(result, "the fixture checks: " .. tostring(collected[1] and (collected[1].msg or collected[1].message)))
    if isolated then
        test.equal(result.moduleName, name, "isolated checker module identity")
        test.equal(result.declaredModuleName, name, "the source header matches before facts are produced")
    end

    return result
end

-- The image of module `name` at `path`, instrumented when `covered` is true or
-- names a request of its own, and the manifests the request collected.
local function lowered(path, name, covered, source)
    local result = checked(path, name, source)
    local request = covered
    if covered == true then
        request = {
            path = function(candidate)
                return candidate == name and path or nil
            end,
            manifests = {},
        }
    end
    local image = require("nupp.compiler.vm.lower").emit(
        name,
        {},
        function(candidate)
            return candidate == name and path or nil
        end,
        function()
            return result.root
        end,
        nil,
        nil,
        require("nupp.compiler.targetlayout").hostKey(),
        request or nil
    )

    return image, request and request.manifests or nil
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
    assert(
        instrumented:find("nupp.runtime.coveragecounter", 1, true),
        "an instrumented image carries its counters"
    )
end

-- Counting the same run the same way is what makes one report hold for either
-- backend. The image only runs on the VM; the generated Lua runs on both.
local function countedRun(path, run)
    local outer = rawget(_G, "__nuppCoverage")
    local previous = outer and outer.hits[path] or nil
    if outer then
        outer.hits[path] = nil
    end
    local ok, result = pcall(run)
    local counters = rawget(_G, "__nuppCoverage")
    local hits = counters and counters.hits[path] or {}
    if outer then
        outer.hits[path] = previous
    end
    rawset(_G, "__nuppCoverage", outer)
    if not ok then
        error(result, 0)
    end

    return result, hits
end

local function vmImageCountsWhatItRuns()
    local path = fixturePath()
    local image, manifests = lowered(path, "sample", true)
    local _, vmHits = countedRun(path, function()
        return rawget(_G, "__nupp_load_image")(image)().run()
    end)
    local reached = 0
    for _, site in ipairs(manifests.sample.sites) do
        local keys = site.kind == "branch" and {site.id .. ":true", site.id .. ":false"} or {tostring(site.id)}
        for _, key in ipairs(keys) do
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

-- Loading a real module runs its top level, which the VM lowering opens with
-- statements of its own (the type witnesses' cells) before any the source wrote.
-- Those once reused the register the counts were loaded into, and every count of
-- the module's top level went into the witness table instead.
local function vmModuleLoadCountsItsTopLevel()
    local path = ROOT .. "/src/nupp/compiler/types/generics.nupp"
    local realName = "nupp.compiler.types.generics"
    local real = require(realName)
    local identifier, sourceType = real.normalize, real.Normalized
    local outer = rawget(_G, "__nuppCoverage")
    moduleFixtures = moduleFixtures + 1
    local name = "nupp.compiler.coveragefixture.generics" .. moduleFixtures
    local source = read(path)
    local declaration = "module " .. realName
    assert(source:sub(1, #declaration + 1) == declaration .. "\n", "the real module begins with its declared header")
    source = "module " .. name .. source:sub(#declaration + 1)
    local previousFixture = package.loaded[name]
    local vmHits, manifests

    local function compilerUnchanged()
        test.equal(package.loaded[realName], real, "coverage did not replace the real loaded compiler module")
        test.equal(require(realName), real)
        test.equal(real.normalize, identifier, "the real function identity survives")
        test.equal(real.Normalized, sourceType, "the real nominal declaration survives")
        test.equal(rawget(_G, "__nuppCoverage"), outer, "the outer counters are restored")
    end

    local ok, problem = pcall(function()
        -- Both checks see the rewritten header first. The physical path and
        -- line count stay unchanged, so all original coverage sites compare.
        local image
        image, manifests = lowered(path, name, true, source)
        _, vmHits = countedRun(path, function()
            return rawget(_G, "__nupp_load_image")(image)()
        end)
        compilerUnchanged()
    end)
    package.loaded[name] = previousFixture
    if not ok then
        error(problem, 0)
    end
    local sites = {}
    for _, site in ipairs(manifests[name].sites) do
        sites[tostring(site.id)] = true
    end
    local keys = 0
    for key in pairs(vmHits) do
        assert(sites[key:match("^(%d+)")], "the VM counted site " .. key .. ", which the lowering never numbered")
        keys = keys + 1
    end
    assert(keys > 50, "loading the module reached its top level")
end

if rawget(_G, "__nupp_load_image") then
    M.vmImageCountsWhatItRuns = vmImageCountsWhatItRuns
    M.vmModuleLoadCountsItsTopLevel = vmModuleLoadCountsItsTopLevel
end

return M
