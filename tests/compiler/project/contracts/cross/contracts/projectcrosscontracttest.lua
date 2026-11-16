local fixture = require("helpers.projectfixture")
local testAssert = fixture.testAssert
local project = fixture.project
local exists = fixture.exists

local cross = require("helpers.crossproject")
local M = {}

-- A binary is a VM program for the machine building it. A platform selected for
-- a build, the host's included, is refused before anything is built rather than
-- stamped from a stub, and an unconfigured one is refused as a target error.
function M.aBinaryForASelectedPlatformIsRefusedBeforeBuilding()
    cross.withProject(function(context)
        local dir = context.dir
        for _, platform in ipairs(context.platforms) do
            local diagnostics = {}
            testAssert.eq(
                project.build(dir, {platform = platform, diagnostics = diagnostics}),
                1,
                "a build for " .. platform .. " is refused"
            )
            assert(cross.refused(diagnostics), "the refusal names the VM program contract for " .. platform)
            assert(not exists(dir .. "/build/default/" .. platform), "nothing was written for " .. platform)
        end
        local diagnostics = {}
        testAssert.eq(
            project.build(dir, {platform = "riscv64gc-unknown-linux-gnu", diagnostics = diagnostics}),
            1,
            "an unconfigured platform is refused"
        )
        testAssert.eq(diagnostics[1] and diagnostics[1].code, "NUPP0003", "an unconfigured platform is a target error")
    end)
end

return M
