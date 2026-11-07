local fixture = require("helpers.projectfixture")
local testAssert = fixture.testAssert
local project = fixture.project
local deps = fixture.deps
local process = fixture.process
local nativeStage = fixture.nativeStage
local buildPlatform = fixture.buildPlatform
local json = fixture.json
local read = fixture.read
local exists = fixture.exists
local tempProject = fixture.tempProject
local remove = fixture.remove
local libraryName = fixture.libraryName
local executableName = fixture.executableName
local setEnvironment = fixture.setEnvironment

local M = {}

function M.popenBinaryStagesItsStructuredImplementationAndProvider()
    local dir = tempProject({
        [
            "nupp.lua"
        ] = [[return {include = {"src"}, build = {kind = "binary", stub = "nupp",
   outDir = "out", output = "out/app", entries = {"main"}}}]],
        ["src/main.nupp"] = [[
local open = io.popen
local child = open({"fixture-child"})
]],
    })
    testAssert.eq(project.build(dir), 0)
    assert(exists(executableName(dir .. "/out/app")), "popen emits a binary with its provider directory")
    local state = json.decode(read(dir .. "/out/.nupp-state.json"))
    for _, name in ipairs({"io.internal.process", "nupp.runtime.provider.nativeprocess"}) do
        assert(state.modules[name], "popen failed to stage " .. name)
    end
    assert(
        exists(dir .. "/out/lib/" .. (jit.os == "Windows" and deps.sharedLibraryName("nupp_native") or "nupp_native")),
        "popen stages its native provider"
    )
    remove(dir)
end

return M
