local fixture = require("helpers.projectfixture")
local testAssert = fixture.testAssert
local project = fixture.project
local deps = fixture.deps
local json = fixture.json
local write = fixture.write
local read = fixture.read
local exists = fixture.exists
local tempProject = fixture.tempProject
local remove = fixture.remove
local TINY_ROCKSPEC = fixture.TINY_ROCKSPEC
local tinyRockFiles = fixture.tinyRockFiles

local M = {}

function M.luarocksDependencyInstallsIntoTheProjectTree()
    local files = tinyRockFiles()
    files[
        "nupp.lua"
    ] = [[
return {
   include = {"src"},
   dependencies = {
      tiny = {kind = "luarocks", rock = "tinyrock", path = "vendor/tinyrock",
         rockspec = "vendor/tinyrock/tinyrock-1.0-1.rockspec"},
   },
   build = {outDir = "out", entries = {"main"}, dependencies = {"tiny"}},
}
]]
    local dir = tempProject(files)
    testAssert.eq(project.build(dir), 0)
    assert(exists(dir .. "/.rocks/share/lua/5.1/tinyrock.lua"), "the rock is installed into a tree the project owns")
    local state = json.decode(read(dir .. "/out/.nupp-state.json"))
    testAssert.eq(#state.dependencies.tiny.key, 32, "a rock's cache key is the build digest, not the trailer's SHA-256")
    -- And into the running process's search path: a build that installs a
    -- renderer is a build that may render with it a moment later.
    assert(
        package.path:find(dir .. "/.rocks/share/lua/5.1/?.lua", 1, true),
        "the tree is added to the search path this process is using"
    )

    -- A rock already in the tree at the version asked for is left alone, which
    -- is what keeps a warm build from reaching for the network.
    testAssert.eq(project.build(dir), 0, "an installed rock rebuilds")
    remove(dir)
end

function M.rockDependenciesCanBeOwnedByTheManifest()
    local files = tinyRockFiles()
    files[
        "vendor/tinyrock/tinyrock-1.0-1.rockspec"
    ] = TINY_ROCKSPEC:gsub(
        'dependencies = { "lua >= 5.1" }',
        'dependencies = { "lua >= 5.1", "dependency-nupp-does-not-install >= 1" }'
    )
    files[
        "nupp.lua"
    ] = [[
return {
   include = {"src"},
   dependencies = {
      tiny = {kind = "luarocks", rock = "tinyrock", path = "vendor/tinyrock",
         rockspec = "vendor/tinyrock/tinyrock-1.0-1.rockspec",
         rockDependencies = false},
   },
   build = {outDir = "out", entries = {"main"}, dependencies = {"tiny"}},
}
]]
    local dir = tempProject(files)
    testAssert.eq(project.build(dir), 0, "an explicitly owned rock dependency list is not resolved by LuaRocks")
    assert(
        exists(dir .. "/.rocks/share/lua/5.1/tinyrock.lua"),
        "disabling transitive resolution still installs the selected rock"
    )
    remove(dir)
end

-- A rock's `nupp` directory is copied into its versioned installation beside the
-- rockspec. It is not on Lua's runtime path; Nupp alone reads the declaration that
-- mirrors the module LuaRocks installed.
function M.installedRocksProvideTypedModuleDeclarations()
    local rockspec = [[
rockspec_format = "3.0"
package = "typedrock"
version = "1.0-1"
source = { url = "file://typedrock.lua" }
description = { summary = "A typed rock that ships with the project." }
dependencies = { "lua >= 5.1" }
build = {
   type = "builtin",
   modules = { typedrock = "typedrock.lua" },
   copy_directories = { "nupp" },
}
]]
    local dir = tempProject({
        [
            "nupp.lua"
        ] = [[
return {
   include = {"src"},
   dependencies = {
      typedrock = {kind = "luarocks", path = "vendor/typedrock",
         rockspec = "vendor/typedrock/typedrock-1.0-1.rockspec"},
   },
   build = {outDir = "out", entries = {"main"},
      dependencies = {"typedrock"}},
}
]],
        [
            "src/main.nupp"
        ] = [[
local typedrock = require("typedrock")
local answer: integer = typedrock.answer
print(answer)
]],
        ["vendor/typedrock/typedrock.lua"] = "return {answer = 42}\n",
        ["vendor/typedrock/nupp/typedrock.d.nupp"] = [[
local answer: integer
return {answer = answer}
]],
        ["vendor/typedrock/typedrock-1.0-1.rockspec"] = rockspec,
    })
    local first = {}
    testAssert.eq(
        project.build(dir, {
            checkOnly = true,
            stats = first
        }),
        0,
        "the installed declaration is a valid module surface"
    )
    local warm = {}
    testAssert.eq(project.build(dir, {checkOnly = true, stats = warm}), 0, "an unchanged rock declaration is warm")
    testAssert.eq(warm.reusedModules, 2, "the project module and external declaration are both reusable")

    write(dir .. "/vendor/typedrock/nupp/typedrock.d.nupp", [[
local answer: string
return {answer = answer}
]])
    local diagnostics = {}
    testAssert.eq(
        project.build(dir, {
            checkOnly = true,
            diagnostics = diagnostics
        }),
        1,
        "changing the installed declaration invalidates its consumer"
    )
    testAssert.eq(
        diagnostics[1] and diagnostics[1].code,
        "NUPP2001",
        "the rock's changed string surface rejects an integer binding"
    )
    assert(
        exists(dir .. "/.rocks/lib/luarocks/rocks-5.1/typedrock/1.0-1/" .. "nupp/typedrock.d.nupp"),
        "LuaRocks carried the Nupp declaration"
    )
    remove(dir)
end

function M.rockDependenciesAreRefusedUnlessTheyArePinned()
    local loose = tempProject({
        ["nupp.lua"] = [[
return {
   dependencies = {lunamark = {kind = "luarocks"}},
   build = {entries = {"main"}},
}
]],
    })
    local config, err = project.loadManifest(loose)
    testAssert.eq(config, nil, "a rock naming no version is refused")
    assert(err:find("must pin the rock", 1, true), err)
    remove(loose)

    local nested = tempProject({
        [
            "nupp.lua"
        ] = [[
return {
   dependencies = {
      native = {kind = "c", sources = {"native.c"}},
      lunamark = {kind = "luarocks", version = "0.6.0-1",
         dependencies = {"native"}},
   },
   build = {entries = {"main"}},
}
]],
    })
    config, err = project.loadManifest(nested)
    testAssert.eq(config, nil, "a rock does not declare what LuaRocks resolves")
    assert(err:find("LuaRocks resolves", 1, true), err)
    remove(nested)

    local wrongMode = tempProject({
        [
            "nupp.lua"
        ] = [[
return {
   dependencies = {lunamark = {kind = "luarocks", version = "0.6.0-1",
      rockDependencies = "no"}},
   build = {entries = {"main"}},
}
]],
    })
    config, err = project.loadManifest(wrongMode)
    testAssert.eq(config, nil, "the rock dependency policy is a boolean")
    assert(err:find("rockDependencies must be a boolean", 1, true), err)
    remove(wrongMode)
end

-- A version in the manifest and a version in the rockspec are two claims about
-- one rock, and a build that installed whichever it read last would be pinned
-- to neither.
function M.rockVersionMustAgreeWithItsRockspec()
    local files = tinyRockFiles()
    files[
        "nupp.lua"
    ] = [[
return {
   include = {"src"},
   dependencies = {
      tiny = {kind = "luarocks", rock = "tinyrock", version = "2.0-1",
         path = "vendor/tinyrock",
         rockspec = "vendor/tinyrock/tinyrock-1.0-1.rockspec"},
   },
   build = {outDir = "out", entries = {"main"}, dependencies = {"tiny"}},
}
]]
    local dir = tempProject(files)
    testAssert.eq(project.build(dir), 1, "a disagreeing version fails the build")
    assert(not exists(dir .. "/.rocks"), "and installs nothing")
    remove(dir)
end

-- A bundle carries modules, not files, so what a rock's files are called on the
-- way in is what `require` calls them on the way out.
function M.bundledRockModulesAreNamedTheWayRequireFindsThem()
    local dir = tempProject({
        [".rocks/share/lua/5.1/lunamark.lua"] = "return {}\n",
        [".rocks/share/lua/5.1/lunamark/util.lua"] = "return {}\n",
        [".rocks/share/lua/5.1/lunamark/writer/html.lua"] = "return {}\n",
        [".rocks/share/lua/5.1/cosmo/init.lua"] = "return {}\n",
        [".rocks/share/lua/5.1/unasked.lua"] = "return {}\n",
    })
    local config = {
        dependencies = {
            lunamark = {
                kind = "luarocks",
                version = "0.6.0-1",
                bundle = {"lunamark.lua", "lunamark/**.lua", "cosmo/init.lua"},
            },
        },
    }
    local carried = deps.rockModules(dir, config, {dependencies = {"lunamark"}})
    local names = {}
    for _, module in ipairs(carried) do
        names[#names + 1] = module.name
    end
    testAssert.eq(
        table.concat(names, " "),
        "cosmo lunamark lunamark.util lunamark.writer.html",
        "a directory module keeps its init, a nested one keeps its path"
    )

    testAssert.eq(
        deps.rockModules(dir, config, {
            dependencies = {}
        })[1],
        nil,
        "a target that asks for no rock carries none"
    )
    local unasked = {dependencies = {lunamark = {kind = "luarocks", version = "0.6.0-1"}},}
    testAssert.eq(
        deps.rockModules(dir, unasked, {
            dependencies = {"lunamark"}
        })[1],
        nil,
        "and a rock with no bundle globs is installed rather than carried"
    )
    remove(dir)
end

-- What a test command has to be told, since it is a fresh interpreter that has
-- never heard of the tree the build installed into.
function M.rockPathsNameTheTreesATargetDependsOn()
    local config = {
        dependencies = {
            tiny = {kind = "luarocks", version = "1.0-1", tree = "vendor/rocks"},
            native = {kind = "c", sources = {"native.c"}},
        },
    }
    local paths = deps.rockPaths("/project", config, {dependencies = {"tiny", "native"}})
    testAssert.eq(
        paths.path,
        "/project/vendor/rocks/share/lua/5.1/?.lua;" .. "/project/vendor/rocks/share/lua/5.1/?/init.lua",
        "the tree's Lua templates, in the order require reads them"
    )
    testAssert.eq(paths.cpath, "/project/vendor/rocks/lib/lua/5.1/" .. (jit.os == "Windows" and "?.dll" or "?.so"))
    testAssert.eq(
        paths.typeRoots[1],
        "/project/vendor/rocks/lib/luarocks/" .. "rocks-5.1/tiny/1.0-1/nupp",
        "the pinned rock version names its declaration root without installing it"
    )
    testAssert.eq(
        deps.rockPaths("/project", config, {
            dependencies = {"native"}
        }),
        nil,
        "a target with no rocks needs nothing added to its path"
    )
end

return M
