local fixture = require("helpers.projectfixture")
local testAssert = fixture.testAssert
local project = fixture.project
local tempProject = fixture.tempProject
local remove = fixture.remove

local M = {}

M.PLATFORMS = {"x86_64-unknown-linux-gnu", "aarch64-apple-darwin", "x86_64-pc-windows-msvc",}

--- What a binary build for a selected platform is refused with: a binary builds
--- for the machine building it.
M.REFUSAL = "a binary builds for the machine building it"

--- Runs `body` with a binary project configuring every platform in `PLATFORMS`.
function M.withProject(body)
    local dir = tempProject({
        [
            "nupp.lua"
        ] = [[return {build = {kind = "binary", stub = "nupp",
         entries = {"main"}, platforms = {"x86_64-unknown-linux-gnu",
         "aarch64-apple-darwin", "x86_64-pc-windows-msvc"}}}]],
        ["main.nupp"] = "return true\n",
    })
    testAssert.eq(
        project.check(dir, {
            platform = M.PLATFORMS[1]
        }),
        0,
        "checking a selected platform needs no stub or network"
    )
    local ok, problem = pcall(body, {platforms = M.PLATFORMS, dir = dir})
    remove(dir)
    assert(ok, problem)
end

--- Whether `diagnostics` holds the selected-platform refusal.
function M.refused(diagnostics)
    for _, diagnostic in ipairs(diagnostics) do
        if diagnostic.code == "NUPP0002" and tostring(diagnostic.msg):find(M.REFUSAL, 1, true) then
            return true
        end
    end

    return false
end

return M
