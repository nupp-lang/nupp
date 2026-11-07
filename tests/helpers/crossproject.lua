local fixture = require("helpers.projectfixture")
local testAssert = fixture.testAssert
local project = fixture.project
local hash = fixture.hash
local nativeStage = fixture.nativeStage
local json = fixture.json
local write = fixture.write
local read = fixture.read
local exists = fixture.exists
local tempProject = fixture.tempProject
local remove = fixture.remove
local syntheticStub = fixture.syntheticStub

local M = {}

function M.withProject(body)
    local platforms = {"x86_64-unknown-linux-gnu", "aarch64-apple-darwin", "x86_64-pc-windows-msvc",}
    local dir = tempProject({
        [
            "nupp.lua"
        ] = [[return {build = {kind = "binary", stub = "nupp",
         entries = {"main"}, platforms = {"x86_64-unknown-linux-gnu",
         "aarch64-apple-darwin", "x86_64-pc-windows-msvc"}}}]],
        ["main.nupp"] = "return true\n",
    })
    local stubDir = dir .. "/stubs"
    os.execute("mkdir -p '" .. stubDir .. "'")
    testAssert.eq(
        project.check(dir, {
            platform = platforms[1]
        }),
        0,
        "checking a selected platform needs no stub or network"
    )
    local records = {}
    for _, platform in ipairs(platforms) do
        local suffix = platform == "x86_64-pc-windows-msvc" and ".exe" or ""
        local artifact = "nupp-host-" .. platform .. suffix
        local bytes = syntheticStub(platform)
        write(stubDir .. "/" .. artifact, bytes)
        records[
            platform
        ] = {
            platform = platform,
            hostAbi = 1,
            artifact = artifact,
            sha256 = hash.sha256(bytes),
            size = #bytes,
            executableSuffix = suffix,
            hostFeatures = {},
            noticeArtifact = "notices-" .. platform .. ".tar",
        }
    end
    local catalogPath = dir .. "/catalog.json"
    write(catalogPath, json.encode({catalogRelease = "synthetic-1", hostAbi = 1, stubs = records}))
    local getenv = os.getenv
    os.getenv = function(name)
        if name == "NUPP_STUB_CATALOG" then
            return catalogPath
        end
        if name == "NUPP_STUB_DIR" then
            return stubDir
        end

        return getenv(name)
    end
    local ok, problem = pcall(body, {
        platforms = platforms,
        dir = dir,
        stubDir = stubDir,
        records = records,
        catalogPath = catalogPath,
    })
    os.getenv = getenv
    remove(dir)
    assert(ok, problem)
end

return M
