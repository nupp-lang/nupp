-- The report is deliberately static: exercise it as a user does, through the public
-- command, and inspect the artifacts rather than reaching into its implementation.
local test = require("assert")
local cjson = require("cjson")
local highlight = require("nupp.doc.highlight")
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

function M.coverageReportRunsAndWritesBrowsableArtifacts()
    local out = os.tmpname()
    os.remove(out)
    local command = ("cd %q && %q coverage --out %q runnertest 2>&1")
        :format(ROOT, ROOT .. "/bin/nupp", out)
    local pipe = assert(io.popen(command))
    local output = pipe:read("*a")
    local closed, reason, status = pipe:close()
    assert(closed or (reason == "exit" and status == 0), output)
    test.matches(output, "coverage: lines")
    local report = cjson.decode(read(out .. "/coverage.json"))
    test.equal(report.version, 1)
    assert(#report.files > 0, "coverage report has source files")
    assert(report.summary.lines.total > 0, "coverage report has executable lines")
    local index = read(out .. "/index.html")
    test.matches(index, "<details")
    test.matches(index, "Missed arms")
    test.matches(index, "Nupp source")
    test.matches(index, "Generated Lua")
    assert(index:find("--bg:#0d1117", 1, true), "coverage report uses dark theme")
    assert(index:find(".nuppdoc-token-keyword", 1, true), "coverage CSS styles syntax")
    assert(index:find("data-route='file/src/nupp/gen.nupp'", 1, true),
        "coverage report has a file route")
    assert(index:find("<nav class=breadcrumbs aria-label=Breadcrumb>", 1, true),
        "coverage pages have breadcrumbs")
    assert(index:find("<a data-route='dir/src' href='#dir/src'>src</a>", 1, true),
        "coverage breadcrumbs link each parent layer")
    assert(index:find("<a data-route='dir/src/nupp' href='#dir/src/nupp'>nupp</a>", 1, true),
        "coverage breadcrumbs link nested parent layers")
    assert(index:find("location.hash.slice(1)||'all'", 1, true), "coverage routes use URL hashes")
    assert(index:find("window.scrollTo(0,0)", 1, true), "coverage navigation resets scroll")
    assert(index:find("<details open><summary><a data-route='dir/src'", 1, true),
        "coverage tree opens its first level")
    assert(index:find("<details open><summary><a data-route='dir/src/nupp'", 1, true),
        "coverage tree opens its second level")
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
    test.matches(read(out .. "/lcov.info"), "SF:src/nupp/")
    assert(os.execute("rm -rf " .. string.format("%q", out)) == 0)
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
