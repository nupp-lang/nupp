local fixture = require("helpers.projectfixture")
local testAssert = fixture.testAssert
local project = fixture.project
local process = fixture.process
local buildPlatform = fixture.buildPlatform
local write = fixture.write
local tempProject = fixture.tempProject
local remove = fixture.remove

local hostSystem = require("helpers.projectfixture").hostSystem
local compiledRuntimeSources = require("helpers.projectfixture").compiledRuntimeSources

local M = {}

function M.binaryFixpointReadsThePlatformNamedHostOutput()
    local dir = tempProject({
        [
            "nupp.lua"
        ] = [[return {include = {"src"}, build = {targets = {dist = {
   kind = "binary", stub = "nupp", output = "out/app", entries = {"main"},
}}}, selfHost = {binary = "dist"}}]],
        ["src/main.nupp"] = "return 1\n",
    })
    local output = dir .. "/out/app.exe"
    local oldBuild, oldRun, oldHostKey = project.build, process.run, buildPlatform.hostKey
    project.build = function(_, opts)
        write(output, "same stamped bytes")
        opts.produced.artifact = output
        return 0
    end
    process.run = function(argv)
        testAssert.eq(argv[1], output .. ".stage1", "fixpoint executes the platform-named stage")
        write(output, "same stamped bytes")
        return 0
    end
    buildPlatform.hostKey = function()
        return "x86_64-pc-windows-msvc"
    end
    local ok, status = pcall(project.binaryFixpoint, dir, {result = {}})
    project.build, process.run, buildPlatform.hostKey = oldBuild, oldRun, oldHostKey
    remove(dir)
    assert(ok, status)
    testAssert.eq(status, 0, "the Windows executable suffix is shared with the build")
end

return M
