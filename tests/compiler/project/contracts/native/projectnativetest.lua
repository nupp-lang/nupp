local fixture = require("helpers.projectfixture")
local testAssert = fixture.testAssert
local process = fixture.process
local nativeStage = fixture.nativeStage
local fs = fixture.fs
local compilerEnv = fixture.compilerEnv
local tempProject = fixture.tempProject
local remove = fixture.remove

local hostSystem = require("helpers.projectfixture").hostSystem
local compiledRuntimeSources = require("helpers.projectfixture").compiledRuntimeSources

local M = {}

function M.subprocessPreservesEmptyArguments()
    local dir = tempProject({["argv.sh"] = [[printf '%s|%s|%s' "$#" "$1" "$2"]],})
    local status, output = process.capture({"sh", dir .. "/argv.sh", "", "tail"})
    remove(dir)
    testAssert.eq(status, 0, output)
    testAssert.eq(output, "2||tail", "an empty argv entry reaches the child process")
end

return M
