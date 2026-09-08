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

function M.fixedHostLibrariesRemainOrdinaryBundleImports()
    local dir = tempProject({
        [
            "nupp.lua"
        ] = [[return {include = {"src"}, build = {
            kind = "bundle", dialect = "lua51", outDir = "out",
            output = "out/app.lua", entries = {"main"}
        }}]],
        ["src/main.g.nupp"] = [[local re = require("re")
return re.match("aaa", "'a'+")]],
    })
    assertEq(project.build(dir), 0, "bundle with host LPeg")
    local output = read(dir .. "/out/app.lua")
    assert(not output:find('package.preload["lpeg"]', 1, true))
    assert(not output:find('package.preload["nupp.services"]', 1, true))
    local status, value = process.capture({
        "luajit",
        "-e",
        "io.write(assert(loadfile(" .. string.format("%q", dir .. "/out/app.lua") .. "))())"
    })
    assertEq(status, 0, value)
    assertEq(value, "4")
    remove(dir)
end

function M.packagedGeneratorsAndRuntimeServicesUseSeparateDependencyRoles()
    local rockspec = [[
rockspec_format = "3.0"
package = "providerrock"
version = "1.0-1"
source = { url = "file://provider.lua" }
description = { summary = "Generator and service provider fixture." }
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
local codec = contract.service:require("fixture")
return generated.value .. ":" .. codec.name
]],
        [
            "src/codec.nupp"
        ] = [[
module codec
const services = require("nupp.services")
export interface Provider
    name: string
end
export const service: services.Service<Provider> = services.define("nupp.codec", 1)
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
        ["vendor/provider/codec.lua"] = "return {codec = {name = 'codec'}}\n",
        [
            "vendor/provider/nupp/capabilities.json"
        ] = [[
{"schema":2,"capabilities":[
 {"kind":"generator","name":"codegen","api":1,"entry":"provider.codegen"},
 {"kind":"service","service":"nupp.codec","name":"fixture","api":1,
  "contract":"codec","export":"service",
  "entry":"provider.codec","member":"codec"}
]}
]],
        ["vendor/provider/nupp/provider/codec.d.nupp"] = [[
local codec: {name: string}
return {codec = codec}
]],
    })
    local produced = {}
    assertEq(project.build(dir, {produced = produced}), 0, "a packaged generator and runtime service build")
    local found = false
    for _, provider in ipairs(produced.services or {}) do
        if provider.service == "nupp.codec" then
            assertEq(provider.name, "fixture")
            assertEq(provider.api, 1)
            assertEq(provider.contract, "codec")
            assertEq(provider.export, "service")
            assertEq(provider.entry, "provider.codec")
            assertEq(provider.member, "codec")
            found = true
        end
    end
    assert(found, "build output describes its checked service catalog")
    assert(
        exists(dir .. "/out/generated/api/fixture/generated.nupp"),
        "the generator publishes beneath its instance module root"
    )
    local state = json.decode(read(dir .. "/out/.nupp-state.json"))
    assertEq(state.dependencies["tool:provider"].usage, "tool", "generator discovery installs a host-tool record")
    assertEq(state.dependencies.provider.usage, "target", "runtime discovery keeps a distinct target record")
    assert(
        exists(
            dir .. "/out/nupp/runtime/services/artifact/g.lua"
        ) or exists(dir .. "/out/nupp/runtime/services/artifact.lua"),
        "the build compiles a deterministic service registry"
    )

    local script = (
        "package.path=%q..package.path;io.write(require('main'))"
    ):format(dir .. "/out/?.lua;" .. dir .. "/.rocks/share/lua/5.1/?.lua;")
    local status, output = process.capture({"luajit", "-e", script})
    assertEq(status, 0, "the generated module and service load: " .. tostring(output))
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

function M.portableBitopsResolveOnlyWhileRequiringTheFacade()
    local dir = tempProject({
        ["nupp.lua"] = 'return {include = {"src"}, build = {outDir = "out", entries = {"setup"}, dialect = "lua51"}}',
        [
            "src/setup.nupp"
        ] = [[
module setup
const contracts = require("nupp.runtime.services.contracts")
contracts.bitops:register("fixture", function(): contracts.BitopsProvider
    return contracts.bitops:require("nupp.scalar")
end)
contracts.bitops:select("fixture")
export = require("consumer")
]],
        ["src/consumer.nupp"] = [[
module consumer
export function shift(value: uint32): int32
    return value << 3
end
]],
    })
    assertEq(project.build(dir), 0, "portable bitops build")
    local script = (
        [=[
package.path = %q .. package.path
local contracts = require("nupp.runtime.services.contracts")
local count = 0
local lookup = contracts.bitops.lookup
contracts.bitops.lookup = function(self, name) count = count + 1; return lookup(self, name) end
local consumer = require("setup")
local initialized = count
assert(initialized > 0)
for value = 1, 1000 do assert(consumer.shift(value) == value * 8) end
assert(count == initialized, "hot calls performed SPI resolution")
assert(not pcall(function() contracts.bitops:select("nupp.scalar") end))
assert(require("consumer") == consumer)
io.write("direct")
]=]
    ):format(dir .. "/out/?.lua;")
    local probe = dir .. "/verify.lua"
    write(probe, script)
    local status, output = process.capture({"luajit", probe})
    assertEq(status, 0, "portable provider initialization: " .. tostring(output))
    assertEq(output, "direct")
    local code = read(dir .. "/out/consumer.lua")
    assert(code:find('require("nupp.runtime.bitops")', 1, true), code)
    assert(not code:find("_G.__nuppBitops", 1, true), code)
    assert(not code:find(":lookup(", 1, true), code)
    remove(dir)
end

function M.portableStructsBindTheirRepresentationOnce()
    local dir = tempProject({
        ["nupp.lua"] = 'return {include = {"src"}, build = {outDir = "out", entries = {"setup"}, dialect = "lua51"}}',
        [
            "src/setup.nupp"
        ] = [[
module setup
const contracts = require("nupp.runtime.services.contracts")
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
        "portable struct build: " .. tostring(diagnostics[1] and diagnostics[1].msg)
    )
    local script = (
        [=[
package.path = %q .. package.path
local contracts = require("nupp.runtime.services.contracts")
local count = 0
local lookup = contracts.cstorage.lookup
contracts.cstorage.lookup = function(self, name) count = count + 1; return lookup(self, name) end
local consumer = require("setup")
local initialized = count
assert(initialized > 0)
for index = 1, 1000 do assert(consumer.sum(index) == index + 8) end
assert(count == initialized, "constructors performed SPI resolution")
assert(not pcall(function() contracts.cstorage:select("nupp.wasm") end))
io.write("direct")
]=]
    ):format(dir .. "/out/?.lua;")
    local probe = dir .. "/verify.lua"
    write(probe, script)
    local status, output = process.capture({"luajit", probe})
    assertEq(status, 0, "portable struct initialization: " .. tostring(output))
    assertEq(output, "direct")
    local code = read(dir .. "/out/consumer.lua")
    assert(code:find('require("nupp.runtime.structvalue")', 1, true), code)
    assert(not code:find("_G.__nuppStructvalue", 1, true), code)
    assert(not exists(dir .. "/out/nupp/runtime/provider/nativestorage.lua"))
    assert(not exists(dir .. "/out/nupp/workers/native.lua"))
    assert(not exists(dir .. "/out/nupp/text/buffer/types.lua"))
    remove(dir)
end

function M.targetDependencyCanSupplyAMacService()
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
local contract = require("nupp.runtime.services.mac")
contract.service:select("acme")
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
description = {summary = "Target-selected incremental MAC service fixture."}
dependencies = {"lua >= 5.1"}
build = {type = "builtin", modules = {["acme.hmac_sha256"] = "provider.lua"},
   copy_directories = {"nupp"}}
]],
        [
            "vendor/crypto/nupp/capabilities.json"
        ] = [[
{"schema":2,"capabilities":[
 {"kind":"service","service":"nupp.mac","name":"acme","api":1,
  "contract":"nupp.runtime.services.mac","export":"service",
  "entry":"acme.hmac_sha256"}
]}
]],
        [
            "vendor/crypto/nupp/acme/hmac_sha256.d.nupp"
        ] = [[
local {type Provider} = require("nupp.runtime.services.mac")
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
    assertEq(project.build(dir), 0, "a target dependency supplies an incremental MAC service")
    local script = (
        "package.path=%q..package.path;io.write(require('main'))"
    ):format(dir .. "/out/?.lua;" .. dir .. "/.rocks/share/lua/5.1/?.lua;")
    local status, output = process.capture({"luajit", "-e", script})
    assertEq(status, 0, "the dependency-backed MAC artifact loads: " .. tostring(output))
    assertEq(output, "f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8")
    remove(dir)
end

return M
