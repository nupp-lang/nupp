local incremental = require("nupp.compiler.incremental")
local observation = require("nupp.compiler.testimpact.observe")
local projectfact = require("nupp.compiler.projectfact")
local selection = require("nupp.compiler.testimpact.selection")
local fs = require("nupp.compiler.fs")

local M = {}

local function assertList(got, want, label)
    assert(#got == #want, (label or "list") .. " length")
    for index, value in ipairs(want) do
        assert(got[index] == value, (label or "list") .. " item " .. index)
    end
end

local function temporaryProject()
    local root = os.tmpname()
    os.remove(root)
    assert(os.execute("mkdir -p '" .. root .. "/alpha' '" .. root .. "/beta'") == 0)

    local function write(path, text)
        local file = assert(io.open(root .. "/" .. path, "wb"))
        file:write(text)
        file:close()
    end

    return root, write
end

function M.semanticQueriesRetainDiamondAndAliasSourcePaths()
    local root, write = temporaryProject()
    write("alpha/leaf.nupp", "global type Shared = number\nreturn {}\n")
    write("beta/leaf.nupp", "global type Shared = string\nreturn {}\n")

    local inc = incremental.new(root)
    assertList(
        inc.projectDependencyPaths("projectEntries", "Shared"),
        {"alpha/leaf.nupp", "beta/leaf.nupp", projectfact.CATALOG_PATH},
        "diamond declaration paths"
    )
    assertList(
        inc.projectDependencyPaths("projectModuleBasenames", "leaf"),
        {"alpha/leaf.nupp", "beta/leaf.nupp", projectfact.CATALOG_PATH},
        "ambiguous module alias paths"
    )
    assertList(
        inc.projectDependencyPaths("projectModulePath", "alpha.leaf"),
        {"alpha/leaf.nupp", projectfact.CATALOG_PATH},
        "resolved module path"
    )
    assertList(
        inc.projectDependencyPaths("projectEntries", "Absent"),
        {projectfact.CATALOG_PATH},
        "negative declaration lookup"
    )
    assertList(
        inc.projectDependencyPaths("projectModulePath", "absent.module"),
        {projectfact.CATALOG_PATH},
        "negative module lookup"
    )

    os.execute("rm -rf '" .. root .. "'")
end

function M.positiveModuleResolutionAndGuaranteesKeepCatalogFact()
    local root, write = temporaryProject()
    assert(os.execute("mkdir -p '" .. root .. "/alpha/shared' '" .. root .. "/beta/shared'") == 0)
    write("alpha/shared/explicit.nupp", "module shared.explicit\nexport const value = 1\n")
    local inc = incremental.new(root, {config = {include = {"alpha", "beta"},},})
    local expected = {"alpha/shared/explicit.nupp", projectfact.CATALOG_PATH}
    assertList(inc.projectDependencyPaths("projectModulePath", "shared.explicit"), expected, "module resolution")
    assertList(
        inc.projectDependencyPaths("moduleCallGuarantees", "shared.explicit\0value"),
        expected,
        "module guarantee map"
    )
    assertList(
        inc.projectDependencyPaths("moduleCallGuarantee", "shared.explicit\0value\0shared.explicit.value\0pure"),
        expected,
        "one module guarantee"
    )

    local duplicate = root .. "/beta/shared/explicit.nupp"
    write("beta/shared/explicit.nupp", "module shared.explicit\nexport const value = 2\n")
    inc.diskChanged(duplicate, 1)
    local paths = inc.projectDependencyPaths("projectModulePath", "shared.explicit")
    assert(paths[2] == projectfact.CATALOG_PATH, "duplicate explicit module still invalidates the prior resolution")
    assert(#paths == 2, "one resolved provider remains concrete beside the catalog fact")

    os.execute("rm -rf '" .. root .. "'")
end

function M.positiveQueriesKeepCatalogFactWhenMatchingSourcesJoin()
    local root, write = temporaryProject()
    write("alpha/leaf.nupp", "global type Shared = number\nreturn {}\n")
    local inc = incremental.new(root)
    assertList(
        inc.projectDependencyPaths("projectEntries", "Shared"),
        {"alpha/leaf.nupp", projectfact.CATALOG_PATH},
        "positive declaration query"
    )
    assertList(
        inc.projectDependencyPaths("projectModuleBasenames", "leaf"),
        {"alpha/leaf.nupp", projectfact.CATALOG_PATH},
        "positive alias query"
    )

    local added = root .. "/beta/leaf.nupp"
    write("beta/leaf.nupp", "global type Shared = string\nreturn {}\n")
    inc.diskChanged(added, 1)
    assertList(
        inc.projectDependencyPaths("projectEntries", "Shared"),
        {"alpha/leaf.nupp", "beta/leaf.nupp", projectfact.CATALOG_PATH},
        "new matching declaration"
    )
    assertList(
        inc.projectDependencyPaths("projectModuleBasenames", "leaf"),
        {"alpha/leaf.nupp", "beta/leaf.nupp", projectfact.CATALOG_PATH},
        "new matching alias"
    )

    os.execute("rm -rf '" .. root .. "'")
end

function M.catalogFactTracksNewAndDeletedModules()
    local root, write = temporaryProject()
    local added = root .. "/future.nupp"
    local inc = incremental.new(root)
    assertList(
        inc.projectDependencyPaths("projectModulePath", "future"),
        {projectfact.CATALOG_PATH},
        "module starts absent"
    )

    write("future.nupp", "return { value = 1 }\n")
    inc.diskChanged(added, 1)
    assertList(
        inc.projectDependencyPaths("projectModulePath", "future"),
        {"future.nupp", projectfact.CATALOG_PATH},
        "new module source"
    )

    os.remove(added)
    inc.diskChanged(added, 3)
    assertList(
        inc.projectDependencyPaths("projectModulePath", "future"),
        {projectfact.CATALOG_PATH},
        "deleted module returns to catalog"
    )

    os.execute("rm -rf '" .. root .. "'")
end

local function owner(fragment, suite, caseId)
    for _, found in ipairs(fragment.owners) do
        if found.suite == suite and found.caseId == caseId then
            return found
        end
    end
    error("missing observation owner", 0)
end

local function rootEdge(found, name)
    for _, edge in ipairs(found.roots) do
        if edge.module == name then
            return edge
        end
    end
    error("missing observation root " .. name, 0)
end

local function dependencies(fragment, name)
    for _, record in ipairs(fragment.dependencies) do
        if record.module == name then
            return record.dependencies
        end
    end
    error("missing dependencies for " .. name, 0)
end

function M.buildObservationCarriesCatalogAliasesDiamondsAndGeneratedRuntime()
    local root = fs.absolute(".")
    local observed = observation.new({runId = "project-attribution", platform = "test", projectRoot = root,})
    observed.beginSuite("tests/projectimpactattributiontest.lua")
    observed.beginCase("build-graph")
    observed.recordBuildState(
        {
            modules = {
                app = {
                    sourcePath = "src/app.nupp",
                    dependencies = {"left", "right"},
                    runtimeModules = {"nupp.codec.base64"},
                    projectDependencies = {
                        {name = "projectModuleBasenames", key = "leaf", paths = {"src/left.nupp", "src/right.nupp"},},
                        {name = "projectEntries", key = "Absent", paths = {projectfact.CATALOG_PATH},},
                    },
                },
                left = {
                    sourcePath = "src/left.nupp",
                    dependencies = {"core"},
                    runtimeModules = {},
                    projectDependencies = {},
                },
                right = {
                    sourcePath = "src/right.nupp",
                    dependencies = {"core"},
                    runtimeModules = {},
                    projectDependencies = {},
                },
                core = {
                    sourcePath = "src/core.nupp",
                    dependencies = {},
                    runtimeModules = {},
                    projectDependencies = {},
                },
                [
                    "nupp.codec.base64"
                ] = {compilerRuntime = true, dependencies = {}, runtimeModules = {}, projectDependencies = {},},
            },
        },
        root
    )
    observed.finishCase()
    observed.finishSuite()

    local fragment = observed.fragment(true)
    local found = owner(fragment, "tests/projectimpactattributiontest.lua", "build-graph")
    assert(#found.uncertainty == 0, "catalog and positive semantic paths are fully attributed")
    assert(rootEdge(found, "nupp.codec.base64").path == "src/nupp/codec/base64.nupp")

    local app = dependencies(fragment, "app")
    local semanticPaths = {}
    local sawLeft, sawRight, sawRuntime = false, false, false
    for _, edge in ipairs(app) do
        if edge.module:match("^@project/") then
            semanticPaths[edge.path] = true
        elseif edge.module == "left" then
            sawLeft = true
        elseif edge.module == "right" then
            sawRight = true
        elseif edge.module == "nupp.codec.base64" then
            sawRuntime = true
        end
    end
    assert(semanticPaths["src/left.nupp"] and semanticPaths["src/right.nupp"], "alias paths remain distinct")
    assert(semanticPaths[projectfact.CATALOG_PATH], "negative lookup names the catalog fact")
    assert(sawLeft and sawRight and sawRuntime, "checked diamond and generated runtime edges remain")
    assert(dependencies(fragment, "left")[1].module == "core")
    assert(dependencies(fragment, "right")[1].module == "core")
end

local function catalogGraph()
    return {
        complete = true,
        base = "base",
        modules = {
            catalog = {paths = {projectfact.CATALOG_PATH}, dependencies = {},},
            app = {paths = {"src/app.nupp"}, dependencies = {"catalog"},},
        },
        suites = {["tests/exampletest.lua"] = {path = "tests/exampletest.lua", sliceSafe = true, unsafeCases = {},},},
        impacts = {app = {{suite = "tests/exampletest.lua", caseId = "observes-project",},},},
        uncertainSuites = {},
        uncertainCases = {},
    }
end

local function selectChange(status, path, oldPath)
    local paths = {path}
    if oldPath then
        paths[#paths + 1] = oldPath
    end
    table.sort(paths)

    return selection.select(catalogGraph(), {
        available = true,
        base = "base",
        head = "head",
        paths = paths,
        changes = {{status = status, path = path, oldPath = oldPath,},},
    })
end

function M.newAndDeletedSourcesReachCatalogDependents()
    local added = selectChange("added", "src/future.nupp")
    assert(#added.selectedSuites == 0 and #added.selectedCases == 1)
    assert(added.selectedCases[1].suite == "tests/exampletest.lua")
    assert(added.selectedCases[1].caseId == "observes-project")
    assert(#added.fallbacks == 0, "new source is explained by the catalog fact")

    local deleted = selectChange("deleted", "src/removed.nupp")
    assert(#deleted.selectedSuites == 0 and #deleted.selectedCases == 1)
    assert(deleted.selectedCases[1].caseId == "observes-project")
    assert(#deleted.fallbacks == 0, "deleted source is explained by the catalog fact")
end

function M.luaMembershipAndNestedManifestsReachCatalogDependents()
    for _, change in ipairs({
        {status = "added", path = "src/generated.lua"},
        {status = "deleted", path = "src/removed.lua"},
        {status = "renamed", path = "src/new-name.lua", oldPath = "src/old-name.lua"},
        {status = "modified", path = "examples/nested/nupp.lua"},
    }) do
        local selected = selectChange(change.status, change.path, change.oldPath)
        assert(#selected.selectedSuites == 0 and #selected.selectedCases == 1)
        assert(selected.selectedCases[1].caseId == "observes-project")
        assert(#selected.fallbacks == 0, change.status .. " " .. change.path .. " reaches the catalog")
    end

    assert(projectfact.affectsCatalog("examples/nested/nupp.lua", "modified"))
    assert(not projectfact.affectsCatalog("examples/nested/not-nupp.lua", "modified"))
    assert(not projectfact.affectsCatalog("src/existing.lua", "modified"))
end

function M.directDuplicateModulePathAndPriorResolutionSelectBothOwners()
    local graph = catalogGraph()
    graph.modules.newModule = {paths = {}, dependencies = {},}
    graph.impacts.newModule = {{suite = "tests/exampletest.lua", caseId = "observes-new-module",},}
    local selected = selection.select(
        graph,
        {
            available = true,
            base = "base",
            head = "head",
            paths = {"src/future.nupp"},
            changes = {{status = "added", path = "src/future.nupp",},},
        },
        {pathModules = {['src/future.nupp'] = {"newModule"},},}
    )

    assert(#selected.selectedSuites == 0 and #selected.selectedCases == 2)
    assert(selected.selectedCases[1].caseId == "observes-new-module")
    assert(selected.selectedCases[2].caseId == "observes-project")
    assert(#selected.fallbacks == 0, "direct path explanation does not suppress the catalog owner")
end

return M
