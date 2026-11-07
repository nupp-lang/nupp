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

function M.crossTargetBuildUsesVerifiedLocalStubsAndWritesPosixArchives()
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
    testAssert.eq(project.build(dir, {platform = linux}), 0, "a verified cache hit needs no source directory artifact")
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

    local windowsOutput = dir .. "/build/default/x86_64-pc-windows-msvc/default.exe"
    os.remove(windowsOutput)
    records["aarch64-apple-darwin"] = nil
    write(catalogPath, json.encode({catalogRelease = "synthetic-2", hostAbi = 1, stubs = records}))
    local partial = {}
    local partialCode = project.build(dir, {platform = "all", produced = partial})
    os.getenv = getenv
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
    remove(dir)
end

function M.crossTargetBuildRefusesSidecarOnlyProvidersBeforeCargoRuns()
    local dir = tempProject({})
    local outputs, err = nativeStage.build(dir, "out", {["native.http"] = true}, "x86_64-pc-windows-msvc")
    testAssert.eq(outputs, nil, "a compiler-host HTTP sidecar is not staged")
    assert(err:find("sidecar-only native feature http", 1, true), err)
    remove(dir)
end

return M
