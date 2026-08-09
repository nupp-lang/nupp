-- The report is deliberately static: exercise it as a user does, through the public
-- command, and inspect the artifacts rather than reaching into its implementation.
local test = require("assert")
local cjson = require("cjson")
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
    local detail = read(out .. "/files/src/nupp/gen.nupp.html")
    test.matches(detail, "Nupp source")
    test.matches(detail, "Generated Lua")
    assert(detail:find("--bg:#0d1117", 1, true), "coverage report uses dark theme")
    assert(detail:find(".nuppdoc-token-keyword", 1, true), "coverage CSS styles syntax")
    assert(detail:find("<a aria-current=page href='files/src/nupp/gen.nupp.html'", 1, true),
        "coverage tree marks the selected file")
    assert(detail:find(".tree a:hover", 1, true), "coverage tree has a hover state")
    assert(index:find("class=sort-indicator", 1, true), "sortable headings show an indicator")
    assert(index:find("aria-sort=none", 1, true), "sortable headings expose their state")
    test.matches(read(out .. "/lcov.info"), "SF:src/nupp/")
    assert(os.execute("rm -rf " .. string.format("%q", out)) == 0)
end

return M
