local fixture = require("helpers.bundlefixture")
local NUPP = fixture.NUPP
local tempProject = fixture.tempProject
local run = fixture.run

local test = require("helpers.bundlefixture").test
local EXECUTABLE = require("helpers.bundlefixture").EXECUTABLE
local BUILT = require("helpers.bundlefixture").BUILT

local M = {}

-- An ordinary compiler-owned binary can use both facilities compiled into its
-- host and facilities carried only by its exact-feature provider. The host's
-- process namespace is deliberately partial in that case, so the sidecar must
-- remain the one selected provider for the whole native closure.
function M.aBinarySelectsOneProviderForItsMixedNativeClosure()
    local dir = tempProject({
        [
            "nupp.lua"
        ] = [[
return {include = {"src"}, build = {default = "app", targets = {app = {
   kind = "binary", stub = "nupp", entries = {"main"}, outDir = "build",
   nativeFeatures = {net = true, http = true},
}}}}
]],
        [
            "src/main.nupp"
        ] = [[
const http = require("io.http")

do local client = http.Client.create() ;
    print("mixed native provider")
end
]],
    })
    local built, builtOk = run(dir, "'" .. NUPP .. "' build")
    assert(builtOk, "the mixed native binary builds: " .. built)
    local executable = package.config:sub(1, 1) == "\\" and "build/app.exe" or "./build/app"
    local output, ranOk = run(dir, executable)
    assert(ranOk, "the mixed native binary runs: " .. output)
    assert(
        output == "mixed native provider\n",
        "one exact-feature provider serves the complete native closure: " .. output
    )
    os.execute("rm -rf '" .. dir .. "'")
end

return M
