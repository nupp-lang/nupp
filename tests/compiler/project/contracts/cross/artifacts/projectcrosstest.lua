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

function M.crossTargetBuildUsesVerifiedLocalStubsAndWritesPosixArchives()
    withProject(function(context)
        local platforms, dir = context.platforms, context.dir
        local stubDir, records, catalogPath = context.stubDir, context.records, context.catalogPath
        local linux = platforms[1]
        local produced = {}
        local ok, code = pcall(project.build, dir, {platform = "all", produced = produced})
        assert(ok, code)
        testAssert.eq(code, 0, "all synthetic platforms stamp")
        testAssert.eq(#produced.platforms, 3, "one result per platform")
        testAssert.eq(
            produced.platforms[2].distributionReady,
            false,
            "an unsigned macOS output is not described as distributable"
        )
        assert(produced.platforms[2].notice:find("must be signed", 1, true), produced.platforms[2].notice)
        for _, platform in ipairs(platforms) do
            local suffix = platform == "x86_64-pc-windows-msvc" and ".exe" or ""
            local output = dir .. "/build/default/" .. platform .. "/default" .. suffix
            assert(exists(output), platform .. " raw binary exists")
            if platform ~= "x86_64-pc-windows-msvc" then
                local archive = read(output .. ".tar")
                testAssert.eq(archive:sub(101, 108), "0000755\0", platform .. " tar records executable mode")
            end
        end
        local linux = platforms[1]
        local linuxRecord = records[linux]
        local cached = dir
            .. "/.nupp/stubs/synthetic-1/1/"
            .. linux
            .. "/"
            .. linuxRecord.sha256
            .. "/"
            .. linuxRecord.artifact
        assert(exists(cached), "a verified stub is installed in the content-addressed cache")
        write(cached, "corrupt")
        testAssert.eq(
            project.build(dir, {
                platform = linux
            }),
            0,
            "a corrupt cache entry is replaced from the verified local source"
        )
        testAssert.eq(read(cached), syntheticStub(linux), "the repaired cache contains authenticated bytes")
        local hiddenStubDir = stubDir .. "-hidden"
        testAssert.eq(os.rename(stubDir, hiddenStubDir), true)
        testAssert.eq(
            project.build(dir, {
                platform = linux
            }),
            0,
            "a verified cache hit needs no source directory artifact"
        )
        testAssert.eq(os.rename(hiddenStubDir, stubDir), true)

        write(
            dir .. "/nupp.lua",
            [[return {build = {kind = "binary", stub = "nupp", entries = {"main"},
         platforms = {"x86_64-unknown-linux-gnu", "aarch64-apple-darwin",
         "x86_64-pc-windows-msvc"},
         platformOutputs = {['x86_64-unknown-linux-gnu'] = "custom/linux"}}}]]
        )
        local overridden = {}
        testAssert.eq(
            project.build(dir, {
                platform = linux,
                outDir = "alternate",
                produced = overridden
            }),
            0,
            "an output-directory override reroots a configured platform output"
        )
        testAssert.eq(
            overridden.artifact,
            dir .. "/alternate/default/x86_64-unknown-linux-gnu/default",
            "the reported platform artifact uses the override"
        )
        assert(exists(overridden.artifact), "the overridden platform artifact exists")
        assert(not exists(dir .. "/custom/linux"), "the manifest platform path was not written")
        write(
            dir .. "/nupp.lua",
            [[return {build = {kind = "binary", stub = "nupp", entries = {"main"},
         platforms = {"x86_64-unknown-linux-gnu", "aarch64-apple-darwin",
         "x86_64-pc-windows-msvc"}}}]]
        )

    end)
end

return M
