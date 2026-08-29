-- The report is deliberately static: exercise it as a user does, through the public
-- command, and inspect the artifacts rather than reaching into its implementation.
local test = require("assert")
local json = require("testjson")
local highlight = require("nupp.compiler.doc.highlight")
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
    local command = ("cd %q && %q coverage --out %q pathtest 2>&1")
        :format(ROOT, ROOT .. "/bin/nupp", out)
    local pipe = assert(io.popen(command))
    local output = pipe:read("*a")
    local closed, reason, status = pipe:close()
    assert(closed or (reason == "exit" and status == 0), output)
    test.matches(output, "coverage: lines")
    local report = json.decode(read(out .. "/coverage.json"))
    test.equal(report.version, 1)
    assert(#report.files > 0, "coverage report has source files")
    assert(report.summary.lines.total > 0, "coverage report has executable lines")
    local index = read(out .. "/index.html")
    test.matches(index, "<details")
    test.matches(index, "Missed arms")
    assert(#index < 1024 * 1024, "coverage index stays below one megabyte")
    assert(not index:find("Nupp source", 1, true), "coverage index does not embed source pages")
    assert(index:find("--bg:#0d1117", 1, true), "coverage report uses dark theme")
    assert(index:find(".nuppdoc-token-keyword", 1, true), "coverage CSS styles syntax")
    assert(index:find("href='files/src/nupp/compiler/gen.nupp/index.html'", 1, true),
        "coverage index links to a file page")
    local genPage = read(out .. "/files/src/nupp/compiler/gen.nupp/index.html")
    test.matches(genPage, "Nupp source")
    test.matches(genPage, "Generated Lua")
    assert(genPage:find("<nav class=breadcrumbs aria-label=Breadcrumb>", 1, true),
        "coverage pages have breadcrumbs")
    assert(genPage:find("href='../../../../../directories/src/index.html'>src</a>", 1, true),
        "coverage breadcrumbs link each parent layer")
    assert(genPage:find("href='../../../../../directories/src/nupp/compiler/index.html'>compiler</a>", 1, true),
        "coverage breadcrumbs link nested parent layers")
    assert(not index:find("location.hash", 1, true), "coverage navigation uses real pages")
    assert(index:find("<details open><summary><a href='directories/src/index.html'", 1, true),
        "coverage tree opens its first level")
    assert(index:find("<details open><summary><a href='directories/src/nupp/index.html'", 1, true),
        "coverage tree opens its second level")
    local compilerPage = read(out .. "/directories/src/nupp/compiler/index.html")
    assert(compilerPage:find("href='../../../../files/src/nupp/compiler/gen.nupp/index.html'", 1, true),
        "directory summaries link to file pages")
    local query = assert(io.popen(("cd %q && %q coverage --report-json --out %q")
        :format(ROOT, ROOT .. "/bin/nupp", out)))
    local queried = query:read("*a")
    local queryClosed, queryReason, queryStatus = query:close()
    assert(queryClosed or (queryReason == "exit" and queryStatus == 0), queried)
    local queriedReport = json.decode(queried)
    test.equal(queriedReport.version, 1)
    assert(#queriedReport.files > 0, "report JSON query has every file")
    assert(index:find(".tree a:hover", 1, true), "coverage tree has a hover state")
    assert(index:find("class=sort-indicator", 1, true), "sortable headings show an indicator")
    assert(index:find("aria-sort=none", 1, true), "sortable headings expose their state")
    assert(index:find("td>.status{margin-right:.45rem}", 1, true),
        "table status dots leave room before filenames")
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
-- prerequisite for an ordinary test run. The coverage command sets this for the
-- test process; the cheap syntax-highlighting assertion below still runs normally.
if os.getenv("NUPP_COVERAGE") == "1" then
    M.coverageReportRunsAndWritesBrowsableArtifacts =
        coverageReportRunsAndWritesBrowsableArtifacts
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

return M
