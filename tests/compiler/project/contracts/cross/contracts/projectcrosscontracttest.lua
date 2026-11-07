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

function M.crossTargetBuildRefusesIncompatibleCatalogsAndPayloads()
    withProject(function(context)
        local platforms, dir = context.platforms, context.dir
        local stubDir, records, catalogPath = context.stubDir, context.records, context.catalogPath
        local linux = platforms[1]
        write(catalogPath, json.encode({catalogRelease = "synthetic-abi", hostAbi = 2, stubs = records}))
        testAssert.eq(
            project.build(dir, {
                platform = linux
            }),
            1,
            "a catalog for another host ABI is refused before stamping"
        )
        write(catalogPath, json.encode({catalogRelease = "synthetic-1", hostAbi = 1, stubs = records}))

        local wrongBytes = syntheticStub("aarch64-apple-darwin")
        local wrongArtifact = "wrong-linux-host"
        write(stubDir .. "/" .. wrongArtifact, wrongBytes)
        local originalLinux = records[linux]
        records[
            linux
        ] = {
            platform = linux,
            hostAbi = 1,
            artifact = wrongArtifact,
            sha256 = hash.sha256(wrongBytes),
            size = #wrongBytes,
            executableSuffix = "",
            hostFeatures = {},
            noticeArtifact = "notices-wrong.tar",
        }
        write(catalogPath, json.encode({catalogRelease = "synthetic-wrong", hostAbi = 1, stubs = records}))
        local wrongOk, wrongCode = pcall(project.build, dir, {platform = linux})
        assert(wrongOk, wrongCode)
        testAssert.eq(wrongCode, 1, "a digest-valid stub for the wrong architecture is refused")
        records[linux] = originalLinux
        write(catalogPath, json.encode({catalogRelease = "synthetic-1", hostAbi = 1, stubs = records}))

        write(dir .. "/main.nupp", 'local lpeg = require("lpeg")\nreturn lpeg\n')
        testAssert.eq(
            project.build(dir, {
                platform = linux
            }),
            1,
            "a payload feature absent from the selected stub is refused"
        )
        write(dir .. "/main.nupp", "return true\n")

    end)
end

return M
