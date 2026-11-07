local fixture = require("helpers.projectfixture")
local testAssert = fixture.testAssert
local project = fixture.project
local deps = fixture.deps
local process = fixture.process
local read = fixture.read
local exists = fixture.exists
local tempProject = fixture.tempProject
local remove = fixture.remove

local hostSystem = require("helpers.projectfixture").hostSystem
local compiledRuntimeSources = require("helpers.projectfixture").compiledRuntimeSources

local M = {}

function M.compileDependenciesOptInWithoutChangingOldTypeManifests()
    local legacyDir = tempProject({
        [
            "nupp.lua"
        ] = [[
return {dependencies = {types = {kind = "types", format = "luacats",
 source = {git = "https://example.invalid/types", rev = string.rep("a", 40)}}},
 build = {entries = {"main"}}}
]],
        ["main.nupp"] = "return true\n",
    })
    local legacy = assert(project.loadManifest(legacyDir))
    testAssert.eq(legacy.build.compileDependencies, nil, "omission preserves ambient type dependency compatibility")
    remove(legacyDir)

    local explicitDir = tempProject({
        [
            "nupp.lua"
        ] = [[
return {dependencies = {types = {kind = "types", format = "luacats",
 source = {git = "https://example.invalid/types", rev = string.rep("a", 40)}}},
 build = {entries = {"main"}, compileDependencies = {}}}
]],
        ["main.nupp"] = "return true\n",
    })
    local explicit = assert(project.loadManifest(explicitDir))
    testAssert.eq(
        #explicit.build.compileDependencies,
        0,
        "an explicit empty list opts out of ambient type dependencies"
    )
    remove(explicitDir)
end

function M.aFailingGeneratorReportsWhatItPrinted()
    local rockspec = [[
rockspec_format = "3.0"
package = "providerrock"
version = "1.0-1"
source = { url = "file://provider.lua" }
description = { summary = "Generator fixture." }
dependencies = { "lua >= 5.1" }
build = {
   type = "builtin",
   modules = { ["provider.codegen"] = "codegen.lua" },
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
      provider = {kind = "luarocks", path = "vendor/provider",
         rockspec = "vendor/provider/providerrock-1.0-1.rockspec"},
   },
   generators = {api = {using = "provider/codegen", inputs = {"model/*.txt"}}},
   build = {outDir = "out", entries = {"main"}},
}
]],
        ["src/main.nupp"] = "return true\n",
        ["model/value.txt"] = "answer\n",
        ["vendor/provider/providerrock-1.0-1.rockspec"] = rockspec,
        -- Leaves through the exit rather than the worker's own reply, so the
        -- only evidence is what it wrote before going.
        [
            "vendor/provider/codegen.lua"
        ] = [[
return function(request)
   io.stdout:write("codegen: model is on fire\n")
   io.stdout:flush()
   os.exit(3)
end
]],
        [
            "vendor/provider/nupp/capabilities.json"
        ] = [[
{"schema":2,"capabilities":[
 {"kind":"generator","name":"codegen","api":1,"entry":"provider.codegen"}
]}
]],
    })
    local errorPath = os.tmpname()
    local originalStderr = io.stderr
    io.stderr = assert(io.open(errorPath, "wb"))
    local code = project.build(dir)
    io.stderr:close()
    io.stderr = originalStderr
    local reported = read(errorPath) or ""
    os.remove(errorPath)
    testAssert.eq(code, 1, "a generator that dies fails the build")
    assert(
        reported:find("codegen: model is on fire", 1, true),
        "the worker's captured output is reported: " .. reported
    )
    assert(reported:find("generator api failed: worker failed", 1, true), reported)
    assert(not exists(dir .. "/out/generated/api.nupp-staged"), "the staging directory is removed")
    remove(dir)
end

function M.shellEntryPointsRefuseBoundedOptions()
    local ok, err = pcall(process.run, {"true"}, {timeoutMs = 1000})
    assert(
        not ok and tostring(err):find("captureIsolated", 1, true),
        "run refuses a timeout it cannot honor: " .. tostring(err)
    )
    ok, err = pcall(process.capture, {"true"}, {memoryMb = 64})
    assert(
        not ok and tostring(err):find("captureIsolated", 1, true),
        "capture refuses a memory ceiling it cannot honor: " .. tostring(err)
    )
    testAssert.eq(process.run({"true"}, {cwd = "."}), 0, "cwd is still honored")
end

function M.startedSessionsRefusePoliciesTheyCannotService()
    for _, options in ipairs({
        {timeoutMs = 1000},
        {
            pump = function()
            end
        },
        {
            cancelled = function()
                return false
            end
        },
    }) do
        local ok, err = pcall(process.startIsolated, {"true"}, options)
        assert(
            not ok and tostring(err):find("session caller", 1, true),
            "a started session must not silently ignore its policy: " .. tostring(err)
        )
    end
end

function M.generatorDeclarationsAreClosedAndPlainData()
    local unknown = tempProject({
        ["nupp.lua"] = [[
return {generators = {api = {using = "missing/codegen"}},
 build = {entries = {"main"}}}
]],
        ["main.nupp"] = "return true\n",
    })
    local _, unknownErr = project.loadManifest(unknown)
    assert(
        tostring(unknownErr):find("references unknown dependency missing", 1, true),
        "a generator must select a declared provider dependency: " .. tostring(unknownErr)
    )
    remove(unknown)

    local cyclic = tempProject({
        [
            "nupp.lua"
        ] = [[
local options = {}
options.self = options
return {
 dependencies = {provider = {kind = "luarocks", path = "provider"}},
 generators = {api = {using = "provider/codegen", options = options}},
 build = {entries = {"main"}},
}
]],
        ["main.nupp"] = "return true\n",
    })
    local _, cyclicErr = project.loadManifest(cyclic)
    assert(
        tostring(cyclicErr):find("must not contain cycles", 1, true),
        "generator options must be serializable plain data: " .. tostring(cyclicErr)
    )
    remove(cyclic)

    local compile = tempProject({
        ["nupp.lua"] = [[
return {build = {entries = {"main"}, compileDependencies = {"missing"}}}
]],
        ["main.nupp"] = "return true\n",
    })
    local _, compileErr = project.loadManifest(compile)
    assert(
        tostring(compileErr):find("references unknown dependency missing", 1, true),
        "compile dependencies are checked by name: " .. tostring(compileErr)
    )
    remove(compile)
end

function M.docsDoNotInstallUnrunGeneratorTools()
    local dir = tempProject({})
    local config = {
        dependencies = {provider = {kind = "luarocks", path = "not-present"},},
        generators = {api = {using = "provider/codegen"},},
    }
    local built, err = deps.build(dir, "out", config, {}, {kind = "docs", dependencies = {}})
    assert(built, "a docs dependency pass ignores unrun generators: " .. tostring(err))
    testAssert.eq(next(built), nil, "no generator tool is installed for docs")
    remove(dir)
end

return M
