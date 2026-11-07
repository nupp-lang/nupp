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

local withProject = require("helpers.crossproject").withProject
local M = {}

function M.crossTargetBuildKeepsIndependentPlatformsAndCleansOne()
    withProject(function(context)
        local platforms, dir = context.platforms, context.dir
        local stubDir, records, catalogPath = context.stubDir, context.records, context.catalogPath
        local linux = platforms[1]
        local windowsOutput = dir .. "/build/default/x86_64-pc-windows-msvc/default.exe"
        os.remove(windowsOutput)
        records["aarch64-apple-darwin"] = nil
        write(catalogPath, json.encode({catalogRelease = "synthetic-2", hostAbi = 1, stubs = records}))
        local partial = {}
        local partialCode = project.build(dir, {platform = "all", produced = partial})
        testAssert.eq(partialCode, 1, "one missing platform makes the aggregate fail")
        testAssert.eq(partial.platforms[1].status, "built", "the first platform still builds")
        testAssert.eq(partial.platforms[2].status, "failed", "the missing platform is reported")
        testAssert.eq(partial.platforms[3].status, "built", "later independent platforms still build")
        assert(exists(windowsOutput), "a platform after the failure was restamped")
        local removed = {}
        testAssert.eq(
            project.clean(dir, {
                target = "default",
                platform = "x86_64-pc-windows-msvc",
                removed = removed,
            }),
            0,
            "one platform can be cleaned"
        )
        testAssert.eq(
            removed[1],
            "build/default/x86_64-pc-windows-msvc/default.exe",
            "clean reports the selected platform output"
        )
        assert(not exists(windowsOutput), "the selected Windows output was removed")
        assert(exists(dir .. "/build/default/x86_64-unknown-linux-gnu/default"), "another platform output remains")
    end)
end

return M
