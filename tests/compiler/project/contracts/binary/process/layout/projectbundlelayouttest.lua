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

return M
