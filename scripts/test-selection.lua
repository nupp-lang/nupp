-- Repository policy only. The CI classifier remains the source of surfaces.
local classifier = dofile(".github/scripts/classify-changes.lua")
local M = {}
function M.select(paths)
    if #paths == 0 then
        return {groups = {}}
    end
    local selection = classifier.classify(paths)
    local surfaces = selection.surfaces
    local prose = true
    for _, path in ipairs(paths) do
        prose = prose and (path:match("%.md$") ~= nil or path:match("%.css$") ~= nil)
    end
    if prose and not surfaces.unclassified and not surfaces.everything then
        return {groups = {}, inspect = true}
    end
    -- These surfaces select CI's broad fast and integration jobs. Locally one
    -- broad run covers their union, rather than repeating it per platform.
    for _, surface in ipairs({
        "everything",
        "unclassified",
        "compiler",
        "library",
        "native",
        "tests",
        "cli",
        "editors",
        "browser",
        "aot",
        "gpu",
        "packaging"
    }) do
        if surfaces[surface] then
            return {all = true, groups = {}, fixpoint = selection.jobs.fixpoint == true}
        end
    end
    local groups, suites = {}, {}
    if surfaces.docs then
        groups[#groups + 1] = "docs"
    end
    if surfaces.measurement then
        groups[#groups + 1] = "measurement"
        suites = {"benchtest", "benchprojectstest"}
    end
    -- An unhandled classifier surface must never turn into an empty green run.
    if surfaces.evals or #groups == 0 then
        return {all = true, groups = {}}
    end

    return {groups = groups, suites = suites}
end

if arg and arg[0] and arg[0]:match("test%-selection%.lua$") then
    local file = assert(io.open(assert(arg[1]), "rb"))
    local paths = {}
    for path in file:read("*a"):gmatch("([^%z]+)") do
        paths[#paths + 1] = path
    end
    file:close()
    local result = M.select(paths)
    if result.all then
        print("all")
    end
    for _, group in ipairs(result.groups) do
        print("group=" .. group)
    end
    for _, suite in ipairs(result.suites or {}) do
        print("suite=" .. suite)
    end
    if result.fixpoint then
        print("fixpoint")
    end
    if result.inspect then
        print("inspect")
    end
end
return M
