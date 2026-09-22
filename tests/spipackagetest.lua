local project = require("nupp.compiler.build.project")
local process = require("nupp.compiler.build.process")
local fs = require("nupp.compiler.fs")
local json = require("testjson")
local M = {}

local function assertEq(got, want, label)
    assert(got == want, (label or "mismatch") .. ": expected " .. tostring(want) .. ", got " .. tostring(got))
end

local function write(path, text)
    assert(fs.writeFile(path, text))
end

local function read(path)
    return assert(fs.readFile(path))
end

local function exists(path)
    return fs.exists(path)
end

local function tempProject(files)
    local dir = os.tmpname()
    os.remove(dir)
    assert(fs.mkdir(dir))
    for name, text in pairs(files) do
        write(fs.join(dir, name), text)
    end

    return dir
end

local function remove(dir)
    assert(require("nupp.io.files").remove(dir, true))
end

function M.namedManifestTargetsCarryTheSelectedHostAndVm()
    local source = [[
local text = require("nupp.text")
local time = require("nupp.time")
local representation = require("nupp.runtime.representation")
return {newBuffer = text.newBuffer, now = time.now, storage = representation.storage}
]]
    local dir = tempProject({
        [
            "nupp.lua"
        ] = [[return {include = {"src"}, build = {
            kind = "modules", entries = {"main"}, default = "browser",
            targets = {
                browser = {dialect = "luajit", host = "browser", outDir = "out/browser"},
                native = {dialect = "luajit", host = "native", outDir = "out/native"},
            }
        }}]],
        ["src/main.g.nupp"] = source,
    })
    local ok, why = pcall(function()
        -- An editor opens the manifest directly, without build's private _target.
        local environment = require("nupp.compiler.env").new(dir, {cache = false})
        local path = dir .. "/src/main.g.nupp"
        local parsed = require("nupp.compiler.parser").parse(source, path)
        assert(#parsed.errors == 0)
        local diagnostics = require("fragment").check(parsed, path, environment)
        for _, diagnostic in ipairs(diagnostics) do
            assert(diagnostic.severity ~= "error", diagnostic.code .. ": " .. diagnostic.msg)
        end
        assertEq(parsed.host, "browser", "the editor honors the named default target")
        assertEq(parsed.dialect, "luajit")
        assertEq(project.check(dir), 0, "the default browser target checks")
        for _, target in ipairs({
            {name = "browser", host = "browser", dialect = "luajit"},
            {name = "native", host = "native", dialect = "luajit"},
        }) do
            local options = target.name == "browser" and {} or {target = target.name}
            assertEq(project.build(dir, options), 0, target.name .. " target builds")
            local output = dir .. "/out/" .. target.name
            local facts = assert(loadfile(output .. "/nupp/runtime/target.lua"))()
            assertEq(facts.host, target.host, "generated host")
            assertEq(facts.dialect, target.dialect, "generated dialect")
            for _, name in ipairs({"nativebuffer", "nativestorage"}) do
                assertEq(
                    exists(output .. "/nupp/runtime/provider/" .. name .. ".lua"),
                    target.dialect == "luajit",
                    target.name .. " carries " .. name
                )
            end
            assert(
                not exists(output .. "/nupp/runtime/provider/wasmstorage.lua"),
                target.name .. " excludes retired storage"
            )
            assertEq(
                exists(output .. "/nupp/runtime/provider/nativetime.lua"),
                target.host == "native",
                target.name .. " carries native clocks"
            )
            assertEq(
                exists(output .. "/nupp/runtime/browser/time.lua"),
                target.host == "browser",
                target.name .. " carries browser clocks"
            )
        end
    end)
    remove(dir)
    assert(ok, why)
end

function M.fixedHostLibrariesRemainOrdinaryBundleImports()
    local dir = tempProject({
        [
            "nupp.lua"
        ] = [[return {include = {"src"}, build = {
            kind = "bundle", dialect = "luajit", outDir = "out",
            output = "out/app.lua", entries = {"main"}
        }}]],
        ["src/main.g.nupp"] = [[local re = require("re")
return re.match("aaa", "'a'+")]],
    })
    assertEq(project.build(dir), 0, "bundle with host LPeg")
    local output = read(dir .. "/out/app.lua")
    assert(not output:find('package.preload["lpeg"]', 1, true))
    assert(not output:find('package.preload["nupp.spi"]', 1, true))
    local status, value = process.capture({
        "luajit",
        "-e",
        "io.write(assert(loadfile(" .. string.format("%q", dir .. "/out/app.lua") .. "))())"
    })
    assertEq(status, 0, value)
    assertEq(value, "4")
    remove(dir)
end

function M.packagedGeneratorsAndSpiUseSeparateDependencyRoles()
    local rockspec = [[
rockspec_format = "3.0"
package = "providerrock"
version = "1.0-1"
source = { url = "file://provider.lua" }
description = { summary = "Generator and SPI fixture." }
dependencies = { "lua >= 5.1" }
build = {
   type = "builtin",
   modules = {
      ["provider.codegen"] = "codegen.lua",
      ["provider.codec"] = "codec.lua",
   },
   copy_directories = { "nupp" },
}
]]
    local dir = tempProject({
        [
            "nupp.lua"
        ] = [[
return {
   include = {"src"},
   dependencies = {
      provider = {kind = "luarocks", path = "vendor/provider",
         rockspec = "vendor/provider/providerrock-1.0-1.rockspec"},
   },
   generators = {
      api = {using = "provider/codegen", inputs = {"model/*.txt"},
         options = {prefix = "generated"}},
   },
   build = {outDir = "out", entries = {"main"}, dependencies = {"provider"}},
}
]],
        [
            "src/main.nupp"
        ] = [[
local generated = require("fixture.generated")
local contract = require("codec")
local spi = require("nupp.spi")
local codec = assert(spi.load(contract.Provider)())
return generated.value .. ":" .. codec.name
]],
        ["src/codec.nupp"] = [[
module codec
export interface Provider
    name: string
end
]],
        ["model/value.txt"] = "answer\n",
        ["vendor/provider/providerrock-1.0-1.rockspec"] = rockspec,
        [
            "vendor/provider/codegen.lua"
        ] = [[
return function(request)
   local value = request.read("model/value.txt"):match("%S+")
   request.write("fixture/generated.nupp", "return {value = "
      .. string.format("%q", request.options.prefix .. "-" .. value) .. "}\n")
end
]],
        [
            "vendor/provider/codec.lua"
        ] = [[
local fields = {name = "codec"}
local implementation = newproxy(true)
getmetatable(implementation).__index = fields
getmetatable(implementation).__newindex = fields
return implementation
]],
        [
            "vendor/provider/nupp/capabilities.json"
        ] = [[
{"schema":2,"capabilities":[
 {"kind":"generator","name":"codegen","api":1,"entry":"provider.codegen"}
]}
]],
        ["vendor/provider/nupp/spi.json"] = [[{"codec.Provider":["provider.codec"]}]],
        ["vendor/provider/nupp/provider/codec.d.nupp"] = [[
local codec: {name: string}
return codec
]],
    })
    local produced = {}
    assertEq(project.build(dir, {produced = produced}), 0, "a packaged generator and runtime implementation build")
    local found = false
    for _, provider in ipairs(produced.spi or {}) do
        if provider.interface == "codec.Provider" then
            assertEq(provider.implementation, "provider.codec")
            assertEq(provider.dependency, "provider")
            found = true
        end
    end
    assert(found, "build output describes checked SPI implementations")
    assert(
        exists(dir .. "/out/generated/api/fixture/generated.nupp"),
        "the generator publishes beneath its instance module root"
    )
    local state = json.decode(read(dir .. "/out/.nupp-state.json"))
    assertEq(state.dependencies["tool:provider"].usage, "tool", "generator discovery installs a host-tool record")
    assertEq(state.dependencies.provider.usage, "target", "runtime discovery keeps a distinct target record")
    assert(
        exists(dir .. "/out/nupp/spi/index/g.lua") or exists(dir .. "/out/nupp/spi/index.lua"),
        "the build compiles a deterministic SPI index"
    )

    local script = (
        "package.path=%q..package.path;io.write(require('main'));assert(type(require('provider.codec'))=='userdata')"
    ):format(dir .. "/out/?.lua;" .. dir .. "/.rocks/share/lua/5.1/?.lua;")
    local status, output = process.capture({"luajit", "-e", script})
    assertEq(status, 0, "the generated module and implementation load: " .. tostring(output))
    assertEq(output, "generated-answer:codec")

    assertEq(project.build(dir), 0, "unchanged generator output is reusable")
    write(dir .. "/model/value.txt", "changed\n")
    assertEq(project.build(dir), 0, "an input change reruns the generator")
    assert(
        read(dir .. "/out/generated/api/fixture/generated.nupp"):find("generated%-changed"),
        "the published output follows the changed input"
    )
    remove(dir)
end

function M.nativeBitopsNeedNoSpiResolution()
    local dir = tempProject({
        ["nupp.lua"] = 'return {include = {"src"}, build = {outDir = "out", entries = {"setup"}, dialect = "luajit"}}',
        ["src/setup.nupp"] = [[
module setup
export = require("consumer")
]],
        ["src/consumer.nupp"] = [[
module consumer
export function shift(value: int32): int32
    return value << 3
end
]],
    })
    assertEq(project.build(dir), 0, "native bitops build")
    local script = (
        [=[
package.path = %q .. package.path
local consumer = require("setup")
for value = 1, 1000 do assert(consumer.shift(value) == value * 8) end
assert(require("consumer") == consumer)
io.write("direct")
]=]
    ):format(dir .. "/out/?.lua;")
    local probe = dir .. "/verify.lua"
    write(probe, script)
    local status, output = process.capture({"luajit", probe})
    assertEq(status, 0, "native bit operation initialization: " .. tostring(output))
    assertEq(output, "direct")
    local code = read(dir .. "/out/consumer.lua")
    assert(code:find("value << 3", 1, true), code)
    assert(not code:find('require("nupp.runtime.bitops")', 1, true), code)
    assert(not code:find("spi.load", 1, true), code)
    assert(not exists(dir .. "/out/nupp/spi.lua"))
    remove(dir)
end

function M.nativeStructsBindFfiDirectly()
    local dir = tempProject({
        ["nupp.lua"] = 'return {include = {"src"}, build = {outDir = "out", entries = {"setup"}, dialect = "luajit"}}',
        ["src/setup.nupp"] = [[
module setup
export = require("consumer")
]],
        [
            "src/consumer.nupp"
        ] = [[
module consumer
local struct Point
    x: int32
    y: uint8
end
export function sum(value: integer): integer
    local point = new Point(value, 7)
    point.x += 1
    return point.x + point.y
end
]],
    })
    local diagnostics = {}
    assertEq(
        project.build(dir, {
            diagnostics = diagnostics
        }),
        0,
        "native struct build: " .. tostring(diagnostics[1] and diagnostics[1].msg)
    )
    local script = (
        [=[
package.path = %q .. package.path
local consumer = require("setup")
for index = 1, 1000 do assert(consumer.sum(index) == index + 8) end
io.write("direct")
]=]
    ):format(dir .. "/out/?.lua;")
    local probe = dir .. "/verify.lua"
    write(probe, script)
    local status, output = process.capture({"luajit", probe})
    assertEq(status, 0, "native struct initialization: " .. tostring(output))
    assertEq(output, "direct")
    local code = read(dir .. "/out/consumer.lua")
    assert(code:find('require("ffi")', 1, true), code)
    assert(not code:find('require("nupp.runtime.structvalue")', 1, true), code)
    assert(not exists(dir .. "/out/nupp/runtime/provider/nativestorage.lua"))
    assert(not exists(dir .. "/out/nupp/workers/native.lua"))
    assert(not exists(dir .. "/out/nupp/text/internal/buffer.lua"))
    remove(dir)
end

function M.targetDependencyCanSupplyAMacImplementation()
    local dir = tempProject({
        [
            "nupp.lua"
        ] = [[
return {
   include = {"src"},
   dependencies = {crypto = {kind = "luarocks", path = "vendor/crypto",
      rockspec = "vendor/crypto/acme-crypto-1.0-1.rockspec"}},
   build = {outDir = "out", entries = {"main"}, dependencies = {"crypto"}},
}
]],
        [
            "src/main.nupp"
        ] = [[
local mac = require("nupp.mac")
local rolling = mac.create("hmac-sha256", "key")
assert(rolling:digestSize() == 32)
rolling:update("The quick brown fox ")
rolling:update("jumps over the lazy dog")
return rolling:hexDigest()
]],
        [
            "vendor/crypto/acme-crypto-1.0-1.rockspec"
        ] = [[
rockspec_format = "3.0"
package = "acme-crypto"
version = "1.0-1"
source = {url = "file://provider.lua"}
description = {summary = "Target-selected incremental MAC implementation fixture."}
dependencies = {"lua >= 5.1"}
build = {type = "builtin", modules = {["acme.hmac_sha256"] = "provider.lua"},
   copy_directories = {"nupp"}}
]],
        ["vendor/crypto/nupp/spi.json"] = [[
{"nupp.mac.spi.Provider":["acme.hmac_sha256"]}
]],
        [
            "vendor/crypto/nupp/acme/hmac_sha256.d.nupp"
        ] = [[
local {type Provider} = require("nupp.mac.spi")
local provider: Provider
return provider
]],
        [
            "vendor/crypto/provider.lua"
        ] = [[
local ffi = require("ffi")
local expected = "f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8"
local raw = expected:gsub("..", function(byte) return string.char(tonumber(byte, 16)) end)
return {algorithms = {["hmac-sha256"] = {name = "hmac-sha256", digestSize = 32, create = function(_, key)
   assert(key == "key")
   local parts = {}
   return {
      update = function(_, bytes)
         local pointer, count = bytes:ref()
         parts[#parts + 1] = ffi.string(pointer, count)
      end,
      finish = function(_, destination)
         assert(table.concat(parts) == "The quick brown fox jumps over the lazy dog")
         local pointer = destination:ref()
         ffi.copy(pointer, raw, #raw)
      end,
      close = function() parts = {} end,
   }
end}}}
]],
    })
    assertEq(project.build(dir), 0, "a target dependency supplies an incremental MAC implementation")
    local script = (
        "package.path=%q..package.path;io.write(require('main'))"
    ):format(dir .. "/out/?.lua;" .. dir .. "/.rocks/share/lua/5.1/?.lua;")
    local status, output = process.capture({"luajit", "-e", script})
    assertEq(status, 0, "the dependency-backed MAC artifact loads: " .. tostring(output))
    assertEq(output, "f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8")
    remove(dir)
end

function M.advertisedImplementationsAndTheirImportsReceiveTheAotPolicy()
    local dir = tempProject({
        [
            "nupp.lua"
        ] = [[return {include = {"src"}, build = {
            kind = "modules", outDir = "out", entries = {"main"},
            sources = {"src/main.nupp"}, aot = "require"
        }}]],
        ["nupp/spi.json"] = [[{"api.Kernel":["implementation"]}]],
        ["src/api.nupp"] = [[module api
export interface Kernel
    @readonly apply: function(number): number
end
]],
        [
            "src/main.nupp"
        ] = [[local {type Kernel} = require("api")
local impl = assert(nupp.spi.load(Kernel)())
return impl.apply
]],
        ["src/implementation.nupp"] = [[local kernel = require("kernel")
return {apply = kernel.apply}
]],
        [
            "src/kernel.nupp"
        ] = [[module kernel
@aot
local function apply(value: number): number
    return value * 2 + 1
end
export = {apply = apply}
]],
    })
    assertEq(project.build(dir, {outDir = dir .. "/out"}), 0, "the implementation's AOT import builds")
    local script = (
        "package.path=%q..package.path;local apply=require('main');"
        .. "assert(_G.__nuppAotCompiled[apply], 'SPI reached an uncompiled function');"
        .. "io.write(apply(20))"
    ):format(dir .. "/out/?.lua;")
    local status, output = process.capture({"luajit", "-e", script})
    assertEq(status, 0, output)
    assertEq(output, "41")
    remove(dir)
end

local function checkDocumentedSpi(page)
    local files = {
        [
            "nupp.lua"
        ] = [[return {include = {"src"}, build = {
            kind = "bundle", dialect = "luajit", outDir = "out",
            output = "out/app.lua", entries = {"main"}
        }}]],
        [
            "src/main.nupp"
        ] = [[local codec = require("example.codec")
assert(codec.encode("hello") == "hello")
return codec.encode == require("example.fastcodec").encode and "provider" or "fallback"
]],
    }
    local moduleCount = 0
    -- A fence carries the file it is, as `json [nupp/spi.json]`, so the page can
    -- show other JSON without it becoming the descriptor this project builds.
    for language, caption, source in page:gmatch("```([%w]+)([^\r\n]*)\r?\n(.-)\r?\n```") do
        if language == "nupp" then
            local name = assert(source:match("^module ([%w.]+)"), "the guide example needs a module name")
            local suffix = name == "example.codec" and "/init.nupp" or ".nupp"
            files["src/" .. name:gsub("%.", "/") .. suffix] = source .. "\n"
            moduleCount = moduleCount + 1
        elseif language == "json" and caption:find("nupp/spi.json", 1, true) then
            files["nupp/spi.json"] = source .. "\n"
        end
    end
    assertEq(moduleCount, 4, "the guide's interface, implementations, and consumer")
    assert(files["nupp/spi.json"], "the guide includes a discovery descriptor")
    local dir = tempProject(files)
    for _, expected in ipairs({"provider", "fallback"}) do
        assertEq(project.build(dir), 0, "the documented SPI example builds")
        local status, output = process.capture({
            "luajit",
            "-e",
            "io.write(assert(loadfile(" .. string.format("%q", dir .. "/out/app.lua") .. "))())",
        })
        assertEq(status, 0, output)
        assertEq(output, expected, "the documented consumer chooses its implementation")
        write(dir .. "/nupp/spi.json", "{}\n")
    end
    remove(dir)
end

function M.documentedSpiModulesSelectAnImplementationAndFallBack()
    checkDocumentedSpi(read("docs/learn/projects/spi.md"))
end

function M.documentedSpiModulesAcceptWindowsLineEndings()
    local page = read("docs/learn/projects/spi.md"):gsub("\r\n", "\n"):gsub("\n", "\r\n")
    checkDocumentedSpi(page)
end

return M
