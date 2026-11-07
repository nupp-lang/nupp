local fixture = require("helpers.projectfixture")
local testAssert = fixture.testAssert
local project = fixture.project
local compilerEnv = fixture.compilerEnv
local write = fixture.write
local read = fixture.read
local exists = fixture.exists
local tempProject = fixture.tempProject
local remove = fixture.remove

local hostSystem = require("helpers.projectfixture").hostSystem
local compiledRuntimeSources = require("helpers.projectfixture").compiledRuntimeSources

local M = {}

-- A docs target with no outDir does not land in the manifest's default
-- directory; the generator has its own, and for markdown it is not even under
-- it. `nupp clean` removes what the task table names, so naming the wrong
-- place left the output behind and took an unrelated directory with it.
function M.aDocsTaskReportsWhereTheGeneratorWillWrite()
    local dir = tempProject({
        [
            "nupp.lua"
        ] = [[
return {
   include = {"src"},
   build = {targets = {
      site = {kind = "docs", sources = {"src"}},
      api = {kind = "docs", sources = {"src"}, format = "markdown"},
      chosen = {kind = "docs", sources = {"src"}, outDir = "elsewhere"},
   }},
}
]],
    })
    local site = assert(project.describeTasks(dir, "site"))
    testAssert.eq(site.outDir, "build/docs", "a site target defaults below build")
    local api = assert(project.describeTasks(dir, "api"))
    testAssert.eq(api.outDir, "docs/api.md", "a markdown target defaults to a file")
    local chosen = assert(project.describeTasks(dir, "chosen"))
    testAssert.eq(chosen.outDir, "elsewhere", "an explicit outDir still wins")
    remove(dir)
end

-- `all` and `includePrivate` include different things, and the task table
-- reported the first under the second's name while never mentioning the second.
function M.docsTaskReportsItsPrivacySetting()
    local dir = tempProject({
        [
            "nupp.lua"
        ] = [[
return {
   include = {"src"},
   build = {targets = {site = {
      kind = "docs", sources = {"src"}, includePrivate = true,
   }}},
}
]],
    })
    local task = assert(project.describeTasks(dir, "site"))
    testAssert.eq(task.includePrivate, true)
    testAssert.eq(task.all, nil, "there is one privacy setting")
    remove(dir)
end

function M.strictnessFollowsTheFileExtensionThroughTheProject()
    -- The extension decides, and it has to survive the whole path from the file on
    -- disk to the checker: a `.nupp` reports an unknown name, a `.lua` does not.
    local luaDir = tempProject({
        ["nupp.lua"] = [[
return {include = {"src"}, build = {entries = {"main"}}}
]],
        ["src/main.lua"] = "return unknown_project_value\n",
    })
    local strictDir = tempProject({
        ["nupp.lua"] = [[
return {include = {"src"}, build = {entries = {"main"}}}
]],
        ["src/main.nupp"] = "return unknown_project_value\n",
    })
    local errorPath = os.tmpname()
    local originalStderr = io.stderr
    io.stderr = assert(io.open(errorPath, "wb"))
    local plain = project.check(luaDir)
    local strict = project.check(strictDir)
    io.stderr:close()
    io.stderr = originalStderr
    os.remove(errorPath)
    testAssert.eq(plain, 0, ".lua permits unknown globals")
    testAssert.eq(strict, 1, ".nupp reports an unknown name")
    remove(luaDir)
    remove(strictDir)
end

function M.manifestBuildDiscoversModulesAndPreservesPaths()
    local dir = tempProject({
        [
            "nupp.lua"
        ] = [[
return {
   include = {"src"},
   build = {outDir = "out", entries = {"app.main"},
      resources = {"src/app/*.d.nupp",
         {source = "src/schema.nupp", output = "app/data/schema.nupp"}}},
}
]],
        ["src/app/main.nupp"] = "local lib = require('lib.util')\nreturn lib\n",
        ["src/lib/util.nupp"] = "return { answer = 42 }\n",
        ["src/app/data.d.nupp"] = "return { ok: boolean }\n",
        ["src/schema.nupp"] = "return { version = 1 }\n",
    })
    testAssert.eq(project.build(dir), 0)
    -- A library is its source, so its build writes nothing beside the record.
    assert(not exists(dir .. "/out/app/data.d.nupp"), "a library build copies no resources")
    assert(exists(dir .. "/out/.nupp-state.json"), "persistent state is written")
    assert(exists(dir .. "/out/.nupp-complete"), "the completion marker is published")
    assert(
        not exists(dir .. "/out/.nupp-complete.pending"),
        "the stamp it was written to is renamed into place rather than left beside it"
    )
    -- The launcher rebuilds whenever a source is newer than this marker, so the marker
    -- has to date from before the sources were read. Stamped when the build finished it
    -- covered every edit made while the build was running: an edit that landed too late
    -- to be compiled was also too old to ask for another build, and the tree stayed one
    -- edit behind until something unrelated happened to move.
    testAssert.eq(
        os.execute(("test ! '%s/out/.nupp-complete' -nt '%s/out/.nupp-state.json'"):format(dir, dir)),
        0,
        "the completion marker must not be newer than what the build wrote"
    )
    testAssert.eq(project.build(dir), 0, "warm build succeeds")
    write(dir .. "/out/.nupp-state.json", "not json")
    testAssert.eq(project.build(dir), 0, "corrupt state degrades to a cold build")
    remove(dir)
end

-- Advice about a program is not a reason to refuse to compile it. A note and a
-- warning are said and stepped over; only an error withholds the generated Lua
-- and fails the build.
function M.onlyAnErrorStopsAManifestBuild()
    local dir = tempProject({
        ["nupp.lua"] = [[
return {
   include = {"src"},
   build = {outDir = "out", entries = {"app.main"}},
}
]],
        [
            "src/app/main.nupp"
        ] = table.concat(
            {
                "local type Color = 'red' | 'green' | 'blue'",
                "local function name(c: Color): string",
                "    if c == 'red' then",
                "        return 'r'",
                "    end",
                "end",
                "return { name = name }",
            },
            "\n"
        ) .. "\n",
    })
    testAssert.eq(project.build(dir), 0, "a warning does not fail the build")
    assert(exists(dir .. "/out/.nupp-complete"), "a warning does not withhold the build")

    -- the same lint, turned up by the project, does stop it
    write(
        dir .. "/nupp.lua",
        [[
return {
   include = {"src"},
   lints = {["exhaustiveness"] = "error"},
   build = {outDir = "out", entries = {"app.main"}},
}
]]
    )
    remove(dir .. "/out")
    assert(project.build(dir) ~= 0, "raised to an error, it stops the build")
    assert(not exists(dir .. "/out/.nupp-complete"), "and the build is withheld")
    remove(dir)
end

function M.moduleBuildCacheUsesDependencyInterfaces()
    local depV1 = table.concat(
        {"local function answer(): number", "   return 1", "end", "return { answer = answer }",},
        "\n"
    )
    local dir = tempProject({
        ["nupp.lua"] = [[
return {
   include = {"src"},
   build = {outDir = "out", entries = {"main"}},
}
]],
        [
            "src/main.nupp"
        ] = table.concat({"local lib = require('lib')", "local value: number = lib.answer()", "return value",}, "\n"),
        ["src/lib.nupp"] = depV1,
    })

    local cold = {}
    testAssert.eq(project.build(dir, {stats = cold}), 0)
    local runtime = compiledRuntimeSources(dir, {"main", "lib"})
    testAssert.eq(cold.checkedModules, 2 + runtime, "cold build checks the project and runtime closure")

    local warm = {}
    testAssert.eq(project.build(dir, {stats = warm}), 0)
    testAssert.eq(warm.checkedModules, 0, "warm build checks no modules")
    testAssert.eq(warm.generatedModules, 0, "warm build generates no modules")
    testAssert.eq(warm.reusedModules, 2 + runtime, "warm build reuses the project and runtime closure")

    write(dir .. "/src/lib.nupp", depV1:gsub("return 1", "return 2"))
    local bodyEdit = {}
    testAssert.eq(project.build(dir, {stats = bodyEdit}), 0)
    testAssert.eq(bodyEdit.checkedModules, 1, "body edit checks only the changed dependency")
    testAssert.eq(
        bodyEdit.reusedModules,
        1 + runtime,
        "body edit reuses the dependent and runtime after interface cutoff"
    )

    write(
        dir .. "/src/lib.nupp",
        table.concat(
            {
                depV1:gsub("return 1", "return 2"),
                "-- Change the returned module interface without breaking consumers.",
            },
            "\n"
        )
            :gsub("return { answer = answer }", "return { answer = answer, label = 'answer' }")
    )
    local interfaceEdit = {}
    testAssert.eq(project.build(dir, {stats = interfaceEdit}), 0)
    testAssert.eq(interfaceEdit.checkedModules, 2, "interface edit rechecks the dependency and dependent")
    testAssert.eq(
        interfaceEdit.reusedModules,
        runtime,
        "changed interface invalidates the dependent but preserves the runtime"
    )
    remove(dir)
end

function M.moduleBuildCacheIncludesDeprecationMetadata()
    local lib = table.concat({"local M = {}", "function M.answer(): number", "   return 42", "end", "return M",}, "\n")
    local dir = tempProject({
        ["nupp.lua"] = [[
return {
   include = {"src"},
   build = {outDir = "out", entries = {"main"}},
}
]],
        ["src/main.nupp"] = table.concat({"local lib = require('lib')", "return lib.answer()",}, "\n"),
        ["src/lib.nupp"] = lib,
    })

    testAssert.eq(project.check(dir, {stats = {}, diagnostics = {}}), 0)
    write(
        dir .. "/src/lib.nupp",
        lib:gsub("function M.answer", '@deprecated(replacement = "lib.currentAnswer")\nfunction M.answer')
    )
    local stats, diagnostics = {}, {}
    testAssert.eq(project.check(dir, {stats = stats, diagnostics = diagnostics}), 0)
    testAssert.eq(stats.checkedModules, 2, "deprecation metadata invalidates the persistent dependent cache")
    local sawDeprecated = false
    for _, diagnostic in ipairs(diagnostics) do
        if diagnostic.code == "NUPP2513" then
            sawDeprecated = true
        end
    end
    assert(sawDeprecated, "the rebuilt dependent reports the deprecated API")

    remove(dir)
end

function M.warmBuildInvalidatesOnlyReadersOfAChangedProjectType()
    local model = table.concat({"global record ReflectedModel", "   name: string", "end", "return {}",}, "\n")
    local unrelated = table.concat({"global record UnrelatedModel", "   value: number", "end", "return {}",}, "\n")
    local dir = tempProject({
        ["nupp.lua"] = [[
return {
   include = {"src"},
   build = {outDir = "out", entries = {"main"}},
}
]],
        ["src/model.nupp"] = model,
        ["src/unrelated.nupp"] = unrelated,
        [
            "src/main.nupp"
        ] = table.concat(
            {
                "const SUMMARY = comptime do",
                "   local info = types.reflect(ReflectedModel)",
                "   return info.fields[1].name",
                "end",
                "return SUMMARY",
            },
            "\n"
        ),
    })

    local cold = {}
    testAssert.eq(project.build(dir, {stats = cold}), 0)
    local runtime = compiledRuntimeSources(dir, {"main", "model", "unrelated"})
    testAssert.eq(cold.checkedModules, 3 + runtime, "cold build checks every project module and runtime source")

    local warm = {}
    testAssert.eq(project.build(dir, {stats = warm}), 0)
    testAssert.eq(warm.checkedModules, 0, "unchanged project is warm")

    write(dir .. "/src/unrelated.nupp", unrelated:gsub("value: number", "value: string"))
    local unrelatedEdit = {}
    testAssert.eq(project.build(dir, {stats = unrelatedEdit}), 0)
    testAssert.eq(unrelatedEdit.checkedModules, 1, "unrelated export edit checks only its declaring module")
    testAssert.eq(unrelatedEdit.reusedModules, 2 + runtime, "the reflecting module and runtime remain reusable")

    write(dir .. "/src/model.nupp", model:gsub("name: string", "name: string\n   count: integer"))
    local reflectedEdit = {}
    testAssert.eq(project.build(dir, {stats = reflectedEdit}), 0)
    testAssert.eq(reflectedEdit.checkedModules, 2, "reflected field edit checks its declaration and reader")
    testAssert.eq(reflectedEdit.reusedModules, 1 + runtime, "unrelated module and runtime remain reusable")
    remove(dir)
end

function M.imageCompilationKeepsARecursiveEntryInItsPendingModule()
    local dir = tempProject({
        ["nupp.lua"] = 'return {include = {"src"}}\n',
        [
            "src/example/api.nupp"
        ] = [[
module example.api
local api = {}
interface api.Runnable
    run: function(self): integer
end
export = api
]],
        [
            "src/example/entry.nupp"
        ] = [[
module example.entry
local api = require("example.api")
local record Entry is api.Runnable
    function run(self): integer
        local root = require("example.root") as {ready: boolean}
        return root.ready and 0 or 1
    end
end
export = {commandType = Entry}
]],
        [
            "src/example/root.nupp"
        ] = [[
module example.root
local entry = require("example.entry")
export = {commandType = entry.commandType, ready = true}
]],
    })
    local env = compilerEnv.new(dir, {cache = false})
    local path = dir .. "/src/example/entry.nupp"
    local diagnostics = {}
    local image = require("nupp.tools.cli.compile").image(path, env, "example.entry", diagnostics)
    testAssert.eq(#diagnostics, 0, diagnostics[1] and diagnostics[1].msg)
    assert(type(image) == "string" and #image > 0, "the recursive entry compiles to its native image")
    assert(env.loaded["example.entry"] == env.loadedPaths[path], "the entry keeps one module record")
    assert(not env.loaded["example.entry"].inProgress, "the entry check completes")
    os.execute("rm -rf " .. string.format("%q", dir))
end

function M.manifestValidatesPrebuiltArtifacts()
    local host = require("nupp.compiler.targetlayout").hostKey()
    local valid = tempProject({
        [
            "nupp.lua"
        ] = (
            [=[
return {
   dependencies = {native = {kind = "c", linkage = "static", artifacts = {
      [%q] = {static = {path = "native.a", sha256 = %q, size = 8}},
   }}},
   build = {kind = "binary", stub = "nupp",
      entries = {"main"}, dependencies = {"native"}},
}
]=]
        ):format(host, ("0"):rep(64))
    })
    local config, err = project.loadManifest(valid)
    assert(config, err)
    remove(valid)
end

return M
