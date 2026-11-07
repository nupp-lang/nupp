local fixture = require("helpers.projectfixture")
local testAssert = fixture.testAssert
local project = fixture.project
local process = fixture.process
local buildPlatform = fixture.buildPlatform
local write = fixture.write
local tempProject = fixture.tempProject
local remove = fixture.remove

local M = {}

function M.sourceFixpointNamesTheStageZeroToItsWorkers()
    local dir = tempProject({
        [
            "nupp.lua"
        ] = [[return {include = {"src"}, build = {
   entries = {"main"}, outDir = "out"},
   selfHost = {bootstrap = "luajit find-stage0.lua"}}]],
        ["src/main.nupp"] = "return 1\n",
        [
            "stage0.lua"
        ] = [[
local input = assert(io.open(arg[0], "rb"))
local source = input:read("*a")
input:close()
if arg[0]:match("stage0%.lua$") then
   assert(os.getenv("NUPP_STAGE0") == arg[0], "workers need this stage-zero entry")
end
local output
for index = 1, #arg do
   if arg[index] == "--out-dir" or arg[index] == "--output" then output = arg[index + 1] end
end
assert(output)
os.execute('mkdir "' .. output .. '"')
local file = assert(io.open(output .. "/main.lua", "wb"))
file:write(source)
file:close()
]],
    })
    write(dir .. "/find-stage0.lua", ("print(%q)\n"):format(dir .. "/stage0.lua"))
    local ok, status = pcall(project.fixpoint, dir, {result = {}})
    remove(dir)
    assert(ok, status)
    testAssert.eq(status, 0, "each stage can launch workers through the selected compiler")
end

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
