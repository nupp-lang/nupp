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

function M.standaloneBinaryLinksCDependencyIntoItsOwnHost()
    local dir = tempProject({
        [
            "nupp.lua"
        ] = [[
return {
   include = {"src"},
   dependencies = {tiny = {kind = "c", sources = {"native/tiny.c"},
      bindings = {header = "native/tiny.h"}}},
   build = {kind = "binary", stub = "nupp", standalone = true,
      outDir = "out", output = "out/app", entries = {"main"}, dependencies = {"tiny"}},
}
]],
        ["src/main.nupp"] = [[local tiny = require("tiny")
print(tiny.tiny_add(2, 3))
]],
        ["native/tiny.h"] = "int tiny_add(int a, int b);\n",
        ["native/tiny.c"] = "int tiny_add(int a, int b) { return a + b; }\n",
    })
    testAssert.eq(project.build(dir), 0)
    local output = executableName(dir .. "/out/app")
    assert(exists(output), "the standalone executable is emitted")
    assert(not exists(dir .. "/out/lib/" .. libraryName("tiny")), "the standalone build has no shared FFI sidecar")
    local code, text = process.capture({output})
    testAssert.eq(code, 0, text)
    testAssert.eq(text:match("[^\r\n]+"), "5", "the executable resolves FFI from its own symbols")
    remove(dir)
end

function M.recordPoolBundleOmitsPhysicalStorage()
    local dir = tempProject({
        [
            "nupp.lua"
        ] = [[return {include = {"src"}, build = {kind = "bundle",
   outDir = "out", output = "out/app.lua", entries = {"main"}, host = "browser"}}]],
        [
            "src/main.nupp"
        ] = [[
local record Item
    value: integer
end
local pool = table.Pool(Item, 2)
local item = pool:acquire()
item.value = 7
pool:release(item)
pool:reset()
assert(pool.capacity == 2 and pool:free() == 2)
]],
    })
    testAssert.eq(project.build(dir), 0)
    local payload = read(dir .. "/out/app.lua")
    for _, name in ipairs({"nupp.util.internal.structpool", "nupp.runtime.storage"}) do
        assert(
            not payload:find(('package.preload[%q]'):format(name), 1, true),
            "record pool unexpectedly packages " .. name
        )
    end
    remove(dir)
end

function M.byteIoBundleOmitsUnusedProcessAndClockProviders()
    local dir = tempProject({
        [
            "nupp.lua"
        ] = [[return {include = {"src"}, build = {kind = "bundle",
   outDir = "out", output = "out/app.lua", entries = {"main"}, host = "browser"}}]],
        [
            "src/main.nupp"
        ] = [[
local buffer = bytes.Buffer.create("portable bytes")
assert(buffer:tostring() == "portable bytes")
buffer:close()
]],
    })
    testAssert.eq(project.build(dir), 0)
    local payload = read(dir .. "/out/app.lua")
    for _, name in ipairs({
        "io.internal.process",
        "bytes.internal.sharedbytes",
        "nupp.runtime.provider.nativeprocess",
        "nupp.runtime.provider.nativetime",
        "nupp.io.path.pathtext"
    }) do
        assert(
            not payload:find(('package.preload[%q]'):format(name), 1, true),
            "byte I/O unexpectedly packages " .. name
        )
    end
    remove(dir)
end

function M.popenBinaryStagesItsStructuredImplementationAndProvider()
    local dir = tempProject({
        [
            "nupp.lua"
        ] = [[return {include = {"src"}, build = {kind = "binary", stub = "nupp",
   outDir = "out", output = "out/app", entries = {"main"}}}]],
        ["src/main.nupp"] = [[
local open = io.popen
local child = open({"fixture-child"})
]],
    })
    testAssert.eq(project.build(dir), 0)
    assert(exists(executableName(dir .. "/out/app")), "popen emits a binary with its provider directory")
    local state = json.decode(read(dir .. "/out/.nupp-state.json"))
    for _, name in ipairs({"io.internal.process", "nupp.runtime.provider.nativeprocess"}) do
        assert(state.modules[name], "popen failed to stage " .. name)
    end
    assert(
        exists(dir .. "/out/lib/" .. (jit.os == "Windows" and deps.sharedLibraryName("nupp_native") or "nupp_native")),
        "popen stages its native provider"
    )
    remove(dir)
end

function M.standaloneBinaryLinksRustFilesystemIntoItsOwnHost()
    local dir = tempProject({
        [
            "nupp.lua"
        ] = [[return {include = {"src"}, build = {kind = "binary",
   stub = "nupp", standalone = true, outDir = "out", output = "out/app",
   entries = {"main"}}}]],
        [
            "src/main.nupp"
        ] = [[
assert(os.stat("Cargo.toml") == "file")
local file = assert(io.open("Cargo.toml", "rb"))
local contents = assert(file:read("*a"))
assert(contents:find("[workspace]", 1, true))
print("rust-files-ok")
]],
    })
    testAssert.eq(project.build(dir), 0)
    local output = executableName(dir .. "/out/app")
    assert(exists(output), "the standalone filesystem executable is emitted")
    assert(not exists(dir .. "/out/lib/nupp_native"), "the standalone filesystem build retains no Rust sidecar")
    local code, text = process.capture({output})
    testAssert.eq(code, 0, text)
    testAssert.eq(
        text:match("[^\r\n]+"),
        "rust-files-ok",
        "the executable resolves Rust filesystem FFI from its own symbols"
    )
    remove(dir)
end

function M.standaloneBinaryPreservesDirectAndAliasedLuaPipes()
    local sources = {
        [[do
    local pipe = assert(io.popen("echo pipe-ok", "r"))
    assert(pipe:read("*l") == "pipe-ok")
end
]],
        [[local open = io.popen
do
    local pipe = assert(open("echo pipe-ok", "r"))
    assert(pipe:read("*l") == "pipe-ok")
end
]],
    }
    for index, source in ipairs(sources) do
        local dir = tempProject({
            [
                "nupp.lua"
            ] = [[return {include = {"src"}, build = {kind = "binary",
   stub = "nupp", standalone = true, outDir = "out", output = "out/app",
   entries = {"main"}}}]],
            ["src/main.nupp"] = source .. 'print("lua-pipe-ok")\n',
        })
        testAssert.eq(project.build(dir), 0, "standalone Lua pipe form " .. index)
        local output = executableName(dir .. "/out/app")
        assert(exists(output), "the standalone Lua pipe executable is emitted")
        for _, name in ipairs({
            "nupp_native",
            "nupp_native.dll",
            "nupp_native.dylib",
            "nupp_native.so",
            "libnupp_native.dylib",
            "libnupp_native.so"
        }) do
            assert(not exists(dir .. "/out/lib/" .. name), "the standalone Lua pipe retains no Rust sidecar")
        end
        local code, text = process.capture({output})
        testAssert.eq(code, 0, text)
        testAssert.eq(text:match("[^\r\n]+"), "lua-pipe-ok", "the Lua pipe reads and closes normally")
        remove(dir)
    end
end

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
