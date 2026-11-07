local fixture = require("helpers.projectfixture")
local testAssert = fixture.testAssert
local project = fixture.project
local deps = fixture.deps
local process = fixture.process
local nativeStage = fixture.nativeStage
local buildPlatform = fixture.buildPlatform
local json = fixture.json
local read = fixture.read
local exists = fixture.exists
local tempProject = fixture.tempProject
local remove = fixture.remove
local libraryName = fixture.libraryName
local executableName = fixture.executableName
local setEnvironment = fixture.setEnvironment

local M = {}

function M.uuidBinaryStagesItsHelperAndSelectedProvider()
    local dir = tempProject({
        [
            "nupp.lua"
        ] = [[return {include = {"src"}, build = {kind = "binary", stub = "nupp",
   outDir = "out", output = "out/app", entries = {"main"}}}]],
        [
            "src/main.nupp"
        ] = [[
local make = os.uuid
local first = os.uuid(4)
local second = make(4)
local third = make(7)
assert(#first == 36 and first:sub(15, 15) == "4")
assert(#second == 36 and second:sub(15, 15) == "4")
assert(#third == 36 and third:sub(15, 15) == "7")
print("uuid-sidecar-ok")
]],
    })
    testAssert.eq(project.build(dir), 0)
    local state = json.decode(read(dir .. "/out/.nupp-state.json"))
    for _, name in ipairs({
        "nupp.util.internal.uuid",
        "nupp.runtime.uuidprovider",
        "nupp.runtime.provider.nativeuuid"
    }) do
        assert(state.modules[name], "the UUID binary failed to stage " .. name)
    end
    assert(
        exists(dir .. "/out/lib/" .. (jit.os == "Windows" and deps.sharedLibraryName("nupp_native") or "nupp_native")),
        "UUID generation stages its native provider"
    )
    local library = os.getenv("NUPP_NATIVE_LIBRARY")
    setEnvironment("NUPP_NATIVE_LIBRARY", nil)
    local ok, code, text = pcall(process.capture, {executableName(dir .. "/out/app")})
    setEnvironment("NUPP_NATIVE_LIBRARY", library)
    assert(ok, code)
    testAssert.eq(code, 0, text)
    testAssert.eq(text:match("[^\r\n]+"), "uuid-sidecar-ok")
    remove(dir)
end

function M.standaloneBinaryLinksClocksAndTimersIntoItsOwnHost()
    local dir = tempProject({
        [
            "nupp.lua"
        ] = [[return {include = {"src"}, build = {kind = "binary",
   stub = "nupp", standalone = true, outDir = "out", output = "out/app",
   entries = {"main"}}}]],
        [
            "src/main.nupp"
        ] = [[
const ffi = require("ffi")
local started = os.monotonic()
assert(os.walltime() > 1000000000000)
coroutine.sleep(2)
assert(os.monotonic() - started >= 2)
assert(rawget(_G, "__nuppHost") == nil)
assert(rawget(_G, "__nuppNativeLibrary") == ffi.C)
print("static-clocks-ok")
]],
    })
    testAssert.eq(project.build(dir), 0)
    local output = executableName(dir .. "/out/app")
    assert(exists(output), "the standalone clock executable is emitted")
    for _, name in ipairs({
        "nupp_native",
        "nupp_native.dll",
        "nupp_native.dylib",
        "nupp_native.so",
        "libnupp_native.dylib",
        "libnupp_native.so"
    }) do
        assert(not exists(dir .. "/out/lib/" .. name), "the standalone clock build retains no Rust sidecar")
    end
    local library = os.getenv("NUPP_NATIVE_LIBRARY")
    setEnvironment("NUPP_NATIVE_LIBRARY", nil)
    local ok, code, text = pcall(process.capture, {output})
    setEnvironment("NUPP_NATIVE_LIBRARY", library)
    assert(ok, code)
    testAssert.eq(code, 0, text)
    testAssert.eq(text:match("[^\r\n]+"), "static-clocks-ok", "clocks and timers resolve from the executable")
    remove(dir)
end

function M.windowsStandaloneIntermediateHostHasAnExecutableSuffix()
    local dir = tempProject({
        [
            "nupp.lua"
        ] = [[return {include = {"src"}, build = {kind = "binary",
   stub = "nupp", standalone = true, outDir = "out", entries = {"main"}}}]],
        ["src/main.nupp"] = "return 1\n",
    })
    local oldHostKey, oldLinkHost = buildPlatform.hostKey, nativeStage.linkHost
    local linkedOutput
    buildPlatform.hostKey = function()
        return "x86_64-pc-windows-msvc"
    end
    nativeStage.linkHost = function(_, _, _, output)
        linkedOutput = output
        return nil, "stop after observing the intermediate host path"
    end
    local ok, status = pcall(project.build, dir)
    buildPlatform.hostKey, nativeStage.linkHost = oldHostKey, oldLinkHost
    remove(dir)
    assert(ok, status)
    testAssert.eq(status, 1)
    assert(
        linkedOutput and linkedOutput:match("standalone%-host%-binary%.exe$"),
        "the Windows linker output has no executable suffix: " .. tostring(linkedOutput)
    )
end

return M
