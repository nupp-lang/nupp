-- `kind = "bundle"`: a target that comes out as one Lua file.
--
-- The file is the deliverable on its own — it runs under a plain luajit with
-- nothing beside it — and it is also the payload a stub carries, so what is
-- asserted here is what docs/reference/distribution.md promises about payloads.
local HERE = require("helpers.paths").absoluteTests
local NUPP = HERE .. "/../bin/nupp"
local packaging = require("nupp.tools.build.package")

local function tempProject(files)
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p '" .. dir .. "'") == 0)
    for name, text in pairs(files) do
        local sub = name:match("^(.*)/[^/]+$")
        if sub then
            assert(os.execute("mkdir -p '" .. dir .. "/" .. sub .. "'") == 0)
        end
        local f = assert(io.open(dir .. "/" .. name, "wb"))
        f:write(text)
        f:close()
    end

    return dir
end

local function readFile(path)
    local f = io.open(path, "rb")
    if not f then
        return nil
    end
    local text = f:read("*a")
    f:close()

    return text
end

-- What the launcher writes about its own progress, which is not what these cases
-- are reading. Named exactly rather than matched by prefix: a diagnostic the
-- compiler wrote is also spelled `nupp: ...`, and several cases below are
-- checking for one.
local LAUNCHER_NOTICES = {
    "nupp: sources changed, building the compiler\n",
    "nupp: falling back to the stage-zero compiler\n",
    "nupp: the compiler did not build; running the last one that did\n",
}

-- What the program said, without what the launcher said about getting there.
--
-- These cases compare output exactly, and the launcher writes its own progress
-- to standard error -- "sources changed, building the compiler" -- whenever a
-- concurrent shard is mid-build and this tree looks unbuilt. That notice is
-- about the toolchain rather than about the program, and a case that failed on
-- it was reporting a race in the test runner as a fault in the bundle.
local function run(dir, argv)
    local outfile = os.tmpname()
    local status = os.execute(("cd '%s' && %s > '%s' 2>&1"):format(dir, argv, outfile))
    local out = readFile(outfile) or ""
    os.remove(outfile)
    -- A program that prints a newline on Windows writes a return with it, which
    -- is the C runtime doing what it is for rather than anything about the
    -- program. These cases compare what was printed, so they compare the line
    -- and not the platform's spelling of the end of one.
    out = out:gsub("\r\n", "\n")
    for _, notice in ipairs(LAUNCHER_NOTICES) do
        out = out:gsub(notice, "")
    end

    return out, status == 0
end

local RUST_HOST

local function rustHost()
    if RUST_HOST then
        return RUST_HOST
    end
    local root = HERE .. "/.."
    local output, ok = run(root, "'" .. root .. "/scripts/toolchain' host-rust workers")
    assert(ok, "the Rust host builds: " .. output)
    RUST_HOST = output:match("([^\n]+)\n?$")
    assert(RUST_HOST and readFile(RUST_HOST), "the Rust host path is reported: " .. output)

    return RUST_HOST
end

local function stampRustHost(dir, payload)
    local suffix = package.config:sub(1, 1) == "\\" and ".exe" or ""
    local output = dir .. "/build/app-rust" .. suffix
    local written, problem = packaging.stampFile(
        output,
        assert(readFile(rustHost())),
        assert(readFile(payload)),
        nil,
        0
    )
    assert(written, "the Rust host accepts the Nupp payload: " .. tostring(problem))

    return "./build/app-rust" .. suffix
end

local MANIFEST = [[
return {
   include = { "src" },
   build = {
      outDir = "build",
      default = "app",
      targets = {
         app = {
            kind = "bundle",
            entries = { "app.main" },
            resources = { "src/app/data/*.txt" },
         },
      },
   },
}
]]

local MAIN = [[
local greet = require("app.greet")
print(greet.hello("world"))

-- Absent when this runs from a build tree rather than a bundle, which is the
-- whole distinction being tested.
local loader = package.preload["nupp.embedded"]
if loader then
    print(tostring(loader()["/data/note.txt"]))
end
]]

local GREET = [[
local greet = {}

function greet.hello(who: string): string
    return "hello, " .. who
end

return greet
]]

local M = {}

local COMPONENT_MANIFEST = [[
return {
   include = {"src"},
   build = {
      kind = "component",
      outDir = "build",
      entries = {"app.main"},
      exports = {"game.answer"},
   },
}
]]

function M.algorithmFactoryReferencesCarryTheirSelectedProviders()
    local dir = tempProject({
        ["nupp.lua"] = MANIFEST:gsub('kind = "bundle"', 'kind = "modules"'),
        [
            "src/app/main.nupp"
        ] = [[
local {checksum, compress} = require("binary")
local catalog = require("binary")
local {digest, mac, formats} = catalog
assert(checksum("crc32"):compute("123456789") == 0xcbf43926ULL)
assert(digest("sha256"):computehex("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
assert(#mac("hmac-sha256"):computehex("key", "message") == 64)
local gzip = compress("gzip")
assert(gzip:decompress(gzip:compress("hello")) == "hello")
assert(table.concat(formats("compression"), ",") == "deflate-raw,gzip,zlib")
print("factories carried")
]],
    })
    local output, built = run(dir, "'" .. NUPP .. "' build")
    assert(built, output)
    for _, family in ipairs({"checksum", "digest", "mac", "nativecompression"}) do
        assert(readFile(dir .. "/build/nupp/runtime/provider/" .. family .. ".lua"), family .. " provider is staged")
    end
    local result, ran = run(dir, "LUA_PATH='./build/?.lua;;' luajit build/app/main.lua")
    assert(ran and result == "factories carried\n", result)
    os.execute("rm -rf '" .. dir .. "'")
end

function M.formatListingsDoNotNeedAlgorithmFactoryReferences()
    for _, host in ipairs({"native", "browser"}) do
        local manifest = MANIFEST:gsub('kind = "bundle"', 'kind = "modules"')
        if host == "browser" then
            manifest = manifest:gsub('kind = "modules",', 'kind = "modules", host = "browser",')
        end
        local compression = host == "native"
            and 'assert(table.concat(formats("compression"), ",") == "deflate-raw,gzip,zlib")'
            or 'assert(#formats("compression") == 0)'
        local dir = tempProject({
            ["nupp.lua"] = manifest,
            [
                "src/app/main.nupp"
            ] = [[
local {formats} = require("binary")
assert(table.concat(formats("digest"), ",") == "md5,sha1,sha256,sha512")
assert(table.concat(formats("checksum"), ",") == "adler32,crc32,crc32c,crc64-ecma,crc64nvme")
assert(table.concat(formats("mac"), ",") == "hmac-sha256")
]]
            .. compression
            .. '\nprint("catalogs carried")\n',
        })
        local output, built = run(dir, "'" .. NUPP .. "' build")
        assert(built, output)
        for _, family in ipairs({"checksum", "digest", "mac"}) do
            assert(readFile(dir .. "/build/nupp/runtime/provider/" .. family .. ".lua"), family .. " catalog is staged")
        end
        if host == "native" then
            local result, ran = run(dir, "LUA_PATH='./build/?.lua;;' luajit build/app/main.lua")
            assert(ran and result == "catalogs carried\n", result)
        else
            assert(readFile(dir .. "/build/nupp/runtime/browser/crc.lua"), "browser CRC backend is staged")
        end
        os.execute("rm -rf '" .. dir .. "'")
    end
end

function M.aComponentInstallsBeforeItsEntryRuns()
    local dir = tempProject({
        ["nupp.lua"] = COMPONENT_MANIFEST,
        [
            "src/app/main.nupp"
        ] = [[
local json = require("serde.json")
local {type Checksum, type CompressionFormat, hexencode} = require("binary")
local unusedCompression: CompressionFormat? = nil
assert(unusedCompression == nil)
assert(hexencode("Nu") == "4e75")
local unfinished: Checksum? = nil
assert(unfinished == nil)
assert(_G.component_started == nil)
debug.log.info("starting component")
_G.component_json = json.encodevalue({answer = 42})
_G.component_exact = json.encodevalue({value = json.numbertoken("18446744073709551615")})
_G.component_started = true
return true
]],
        [
            "src/game.nupp"
        ] = [[
local game = {}
function game.answer(value: integer): integer
   return value + 1
end
return game
]],
    })
    local out, ok = run(dir, "'" .. NUPP .. "' build")
    assert(ok, "the component target builds: " .. out)
    local artifact = readFile(dir .. "/build/component.nuppc")
    assert(
        not artifact:find('package.preload["nupp.runtime.provider.nativecompression"]', 1, true),
        "byte encoding and compression type imports do not stage the compression provider"
    )
    local marker = "-- NUPP-COMPONENT 1"
    assert(artifact and artifact:sub(1, #marker) == marker, "the component has a version marker")
    assert(
        artifact:find('package.preload["debug.log"]', 1, true),
        "the component carries standard-library modules reached by its source"
    )
    assert(
        artifact:find('package.preload["nupp.runtime.provider.lunajson"]', 1, true),
        "the component carries providers reached through service facades"
    )
    assert(
        artifact:find('package.preload["nupp.codec.json.number"]', 1, true),
        "the component carries the provider's numeric token validator"
    )

    local script = [[
_G.__nuppHost = {hostAbi = 1, hostFeatures = {}}
package.path, package.cpath = "", ""
local descriptor = assert(loadfile("build/component.nuppc"))()
assert(component_started == nil)
local component = descriptor.install()
assert(component_started == nil)
assert(component.exports["game.answer"](41) == 42)
assert(component_started == nil)
assert(component_json == nil)
component.start()
assert(component_started == true)
assert(component_json == '{"answer":42}')
assert(component_exact == '{"value":18446744073709551615}')
]]
    local scriptFile = assert(io.open(dir .. "/run.lua", "wb"))
    scriptFile:write(script)
    scriptFile:close()
    local ran, ranOk = run(dir, "luajit run.lua")
    assert(ranOk, "an installed component starts explicitly: " .. ran)
    os.execute("rm -rf '" .. dir .. "'")
end

function M.componentsShareOneRuntimeAndRejectNameCollisions()
    local dir = tempProject({
        ["build/one/main.lua"] = 'require("debug.log")\nreturn {call=function(n) return n + 1 end}\n',
        ["build/two/main.lua"] = 'require("debug.log")\nreturn {call=function(n) return n + 2 end}\n',
        ["build/three/main.lua"] = "return {call=function(n) return n + 3 end}\n",
        ["build/shared/debug/log.lua"] = "return {version=1}\n",
        ["build/changed/debug/log.lua"] = "return {version=2}\n",
    })

    local function artifact(entry, exported, shared)
        local path = dir .. "/build/" .. entry:gsub("%.", "/") .. ".lua"
        local modules = {[entry] = {output = path}}
        if shared then
            modules["debug.log"] = {output = dir .. "/build/" .. shared .. "/debug/log.lua", compilerRuntime = true}
        end
        local text = assert(
            packaging.bundleText(
                dir,
                {},
                {kind = "component", outDir = "build", entries = {entry}, exports = {exported},},
                nil,
                modules,
                false,
                nil,
                {},
                true
            )
        )

        return text
    end

    local one = assert(loadstring(artifact("one.main", "one.main.call", "shared")))()
    local two = assert(loadstring(artifact("two.main", "two.main.call", "shared")))()
    local collision = assert(loadstring(artifact("one.main", "one.main.other", "shared")))()
    local changed = assert(loadstring(artifact("three.main", "three.main.call", "changed")))()
    local savedHost, savedPublic = _G.__nuppHost, _G.__nuppComponentExports
    local savedShared = _G.__nuppComponentSharedModules
    local savedLogLoaded, savedLogPreload = package.loaded["debug.log"], package.preload["debug.log"]
    package.loaded["debug.log"], package.preload["debug.log"] = nil, nil
    _G.__nuppHost = {hostAbi = 1, hostFeatures = {}}
    local first = one.install()
    local second = two.install()
    assert(first.exports["one.main.call"](40) == 41)
    assert(second.exports["two.main.call"](40) == 42)
    local installed, problem = pcall(collision.install)
    assert(
        not installed and tostring(problem):find("component module collision: one.main", 1, true),
        "a colliding component is refused before replacing the first"
    )
    installed, problem = pcall(changed.install)
    assert(
        not installed and tostring(problem):find("component shared module collision: debug.log", 1, true),
        "components share only byte-identical compiler runtime modules"
    )
    assert(first.exports["one.main.call"](1) == 2, "the prior component remains installed")
    package.loaded["one.main"], package.loaded["two.main"] = nil, nil
    package.preload["one.main"], package.preload["two.main"] = nil, nil
    package.loaded["debug.log"], package.preload["debug.log"] = savedLogLoaded, savedLogPreload
    _G.__nuppHost, _G.__nuppComponentExports = savedHost, savedPublic
    _G.__nuppComponentSharedModules = savedShared
    os.execute("rm -rf '" .. dir .. "'")
end

function M.aBootstrapCompilerRetainsPublicRuntimeArtifacts()
    local dir = tempProject({
        ["build/nupp/tools/main.lua"] = 'return _G.__nuppCompilerModuleArtifacts["debug.log"].source',
        ["build/debug/log.lua"] = "return 17",
    })
    local target = {kind = "modules", outDir = "build", entries = {"nupp.tools.main"}}
    local modules = {
        ["nupp.tools.main"] = {output = dir .. "/build/nupp/tools/main.lua"},
        ["debug.log"] = {output = dir .. "/build/debug/log.lua"},
    }
    local text = assert(packaging.bundleText(dir, {}, target, nil, modules))
    local savedArtifacts = rawget(_G, "__nuppCompilerModuleArtifacts")
    local savedMain, savedMainLoaded = package.preload["nupp.tools.main"], package.loaded["nupp.tools.main"]
    local savedLog, savedLogLoaded = package.preload["debug.log"], package.loaded["debug.log"]
    package.loaded["nupp.tools.main"] = nil
    local ok, result = pcall(assert(loadstring(text)))
    package.preload["nupp.tools.main"], package.loaded["nupp.tools.main"] = savedMain, savedMainLoaded
    package.preload["debug.log"], package.loaded["debug.log"] = savedLog, savedLogLoaded
    rawset(_G, "__nuppCompilerModuleArtifacts", savedArtifacts)
    os.execute("rm -rf '" .. dir .. "'")
    assert(ok, result)
    assert(result == "return 17", "a bootstrap compiler can reuse its public runtime without a module directory")
end

function M.compilerHostPreambleMasksUniversalStubFeaturesBeforeUserCode()
    local dir = tempProject({
        [
            "build/main.lua"
        ] = [[
assert(rawget(_G, "__nuppHost") == nil)
local name = "lp" .. "eg"
local loaded = pcall(require, name)
return loaded
]],
    })
    local target = {kind = "binary", outDir = "build", entries = {"main"}}
    local modules = {main = {output = dir .. "/build/main.lua"}}
    local text = assert(packaging.bundleText(dir, {}, target, nil, modules, false, {}, {"workers"}))
    local again = assert(packaging.bundleText(dir, {}, target, nil, modules, false, {}, {"workers"}))
    assert(text == again, "the payload depends on selected features, not ambient stub state")

    -- The names are kept as a list rather than recovered from the saved table,
    -- because a module that was not preloaded saves as nil and `pairs` does not
    -- visit it. Restoring by iteration therefore left this test's stub opener
    -- installed for every later `require` of it.
    local stubbed = {"lpeg", "nupp.workers.native"}
    local savedPreloads, savedLoaded = {}, package.loaded.lpeg
    local savedPath, savedCpath = package.path, package.cpath
    for _, name in ipairs(stubbed) do
        savedPreloads[name] = package.preload[name]
        package.preload[name] = function()
            return name
        end
    end
    package.loaded.lpeg = nil
    package.path, package.cpath = "", ""
    _G.__nuppHost = {hostAbi = 1, hostFeatures = {lpeg = true, workers = true,}}
    local loaded = assert(loadstring(text))()
    assert(not loaded, "a computed require cannot observe an unselected universal feature")
    assert(package.preload["nupp.workers.native"], "selected worker opener remains visible")
    assert(package.preload.lpeg == nil, "unselected universal openers are removed")
    assert(_G.__nuppHost == nil, "the private handshake is gone before user code")
    package.loaded.lpeg = savedLoaded
    package.path, package.cpath = savedPath, savedCpath
    for _, name in ipairs(stubbed) do
        package.preload[name] = savedPreloads[name]
    end
    package.preload["nupp.embedded"] = nil
    os.execute("rm -rf '" .. dir .. "'")
end

-- An ordinary compiler-owned binary can use both facilities compiled into its
-- host and facilities carried only by its exact-feature provider. The host's
-- process namespace is deliberately partial in that case, so the sidecar must
-- remain the one selected provider for the whole native closure.
function M.aBinarySelectsOneProviderForItsMixedNativeClosure()
    local dir = tempProject({
        [
            "nupp.lua"
        ] = [[
return {include = {"src"}, build = {default = "app", targets = {app = {
   kind = "binary", stub = "nupp", entries = {"main"}, outDir = "build",
   nativeFeatures = {net = true, http = true},
}}}}
]],
        [
            "src/main.nupp"
        ] = [[
const http = require("io.http")

do local client = http.Client.create() ;
    print("mixed native provider")
end
]],
    })
    local built, builtOk = run(dir, "'" .. NUPP .. "' build")
    assert(builtOk, "the mixed native binary builds: " .. built)
    local executable = package.config:sub(1, 1) == "\\" and "build/app.exe" or "./build/app"
    local output, ranOk = run(dir, executable)
    assert(ranOk, "the mixed native binary runs: " .. output)
    assert(
        output == "mixed native provider\n",
        "one exact-feature provider serves the complete native closure: " .. output
    )
    os.execute("rm -rf '" .. dir .. "'")
end

function M.machOPackagingReplacesTheStubSignatureWithASignableLayout()
    local function little(value, width)
        local bytes = {}
        for index = 1, width do
            bytes[index] = string.char(value % 256)
            value = math.floor(value / 256)
        end

        return table.concat(bytes)
    end

    local header = "\207\250\237\254" .. little(
        0x0100000c,
        4
    ) .. little(0, 4) .. little(2, 4) .. little(2, 4) .. little(88, 4) .. little(0, 4) .. little(0, 4)
    local linkedit = little(
        0x19,
        4
    ) .. little(
        72,
        4
    ) .. "__LINKEDIT" .. (
        "\0"
    ):rep(
        6
    ) .. little(
        0x1000,
        8
    ) .. little(
        0x1000,
        8
    ) .. little(120, 8) .. little(8, 8) .. little(1, 4) .. little(1, 4) .. little(0, 4) .. little(0, 4)
    local signature = little(0x1d, 4) .. little(16, 4) .. little(120, 4) .. little(8, 4)
    local stub = header .. linkedit .. signature .. "SIGNHERE"
    local dir = tempProject({})
    local output = dir .. "/app"
    assert(packaging.stampFile(output, stub, "return true\n", "aarch64-apple-darwin"))
    local bytes = assert(readFile(output))
    assert(bytes:sub(-48, -41) == "NUPPLOAD", "the unsigned trailer ends the stamped file")
    assert(bytes:sub(17, 20) == little(1, 4), "the old signature load command is removed")
    assert(bytes:sub(21, 24) == little(72, 4), "the load-command byte count is updated")
    assert(
        bytes:sub(81, 88) == little(#bytes - 120, 8),
        "__LINKEDIT covers the payload and trailer for the next signer"
    )
    os.execute("rm -rf '" .. dir .. "'")
end

-- Precompiling is a change to the shape of a payload, and the two things it must
-- not change are what the payload does and what it is called. Code in a bundle
-- finds what travels beside the binary -- the native library, an AOT builder, the
-- compiler's staged declarations -- by reading the chunk name, and the host settles
-- that name from the executable it found itself in. A dump that kept its debug
-- information would answer with a name settled where it was built instead.
function M.aPayloadForThisMachineIsStrippedBytecodeTheHostStillNames()
    local source = "return debug.getinfo(1, 'S').source\n"
    local bytes, flags = packaging.payloadBytes(source, nil)
    assert(bytes, "a payload is produced for this machine")
    assert(flags == packaging.payloadFlagBytecode, "and its trailer says it carries bytecode")
    assert(bytes:sub(1, 3) == "\27LJ", "which is what it is")

    local chunk = assert(loadstring(bytes, "@/somewhere/nupp"))
    assert(chunk() == "@/somewhere/nupp", "the name comes from whoever loads it, as it does for a source payload")
end

-- A dump records the endianness and VM configuration it was written for and is
-- refused by one that does not match. A cross-stamped binary is run by a VM this
-- machine never sees, so it carries the bundle itself, which any of them can read.
function M.aPayloadForAnotherPlatformStaysSource()
    local platform = require("nupp.tools.build.platform")
    local elsewhere
    for _, key in ipairs(platform.keys()) do
        if key ~= platform.hostKey() then
            elsewhere = key
            break
        end
    end
    assert(elsewhere, "the platform list names somewhere this is not")

    local source = "return 1\n"
    local bytes, flags = packaging.payloadBytes(source, elsewhere)
    assert(bytes == source, "a cross-stamped payload is the bundle itself")
    assert(flags == 0, "and its trailer says so")
end

function M.aWorkerPayloadCarriesRuntimeModulesAndDispatchesItsEntry()
    local dir = tempProject({
        ["build/main.lua"] = "return 'main'\n",
        ["build/jobs/hash.lua"] = "return 'worker'\n",
        ["build/nupp/suspension.lua"] = "return {runtime = 'suspension'}\n",
        ["build/nupp/workers.lua"] = "return {runtime = 'workers'}\n",
    })
    local text, problem = packaging.bundleText(
        dir,
        {},
        {kind = "binary", outDir = "build", entries = {"main"},},
        nil,
        {main = {output = dir .. "/build/main.lua"}, ["jobs.hash"] = {output = dir .. "/build/jobs/hash.lua"},},
        true,
        {"nupp.suspension", "nupp.workers"}
    )
    assert(text, "the worker payload is assembled: " .. tostring(problem))
    assert(text:find('package.preload["nupp.suspension"]', 1, true), "the suspension runtime is carried")
    assert(text:find('package.preload["nupp.workers"]', 1, true), "the workers runtime is carried")
    assert(text:find('package.preload["main"]', 1, true), "the ordinary entry becomes selectable")
    assert(
        text:find('local __nuppEntry = rawget(_G, "__nuppWorkerEntry")', 1, true),
        "one dispatcher selects the worker or ordinary entry"
    )
    assert(
        text:find('local __nuppServed = require(__nuppEntry)', 1, true)
        and text:find('__nuppEntry == "nupp.workers"', 1, true)
        and text:find('rawget(__nuppServed, "__runScheduler")', 1, true)
        and text:find('then __nuppServe() end', 1, true),
        "a scheduler worker selects the compiler-owned scheduler loop"
    )
    -- Not through `require`. It is a C function, and a payload whose entry ran inside
    -- one could not suspend at all on a host whose every wait is a yield back to it.
    assert(
        text:find('local __nuppLoaded = package.preload["main"]("main")', 1, true)
        and text:find('return __nuppLoaded', 1, true),
        "the ordinary entry is called where the payload runs"
    )
    assert(not text:find('require(__nuppEntry or', 1, true), "the ordinary entry does not go through require")
    assert(
        text:find("if __nuppLoaded == nil then return end", 1, true),
        "an entry that returned nothing still returns nothing"
    )
    assert(
        not text:find("if __nuppEntry ~= nil then (require", 1, true),
        "a native worker payload installs nothing a lane has to install for itself"
    )
    os.execute("rm -rf '" .. dir .. "'")
end

function M.aStampedBinaryRunsStructuredTasksOnTheSharedScheduler()
    local dir = tempProject({
        ["shared-bytes.bin"] = "engine\0bytes\255",
        [
            "nupp.lua"
        ] = [[
return {include = {"src"}, build = {default = "app", targets = {app = {
   kind = "binary", stub = "nupp", entries = {"nupp.internal.workerapp"}, outDir = "build",
   payloadOutput = "build/app.payload.lua",
}}}}
]],
        ["nupp/spi.json"] = [[{"counter.spi.Counter":["counter.provider"]}]],
        [
            "src/counter/spi.nupp"
        ] = [[module counter.spi
export interface Counter
    @readonly next: function(): integer
end]],
        [
            "src/counter/provider.nupp"
        ] = [[module counter.provider
local count: integer = 0
export function next(): integer
    count = count + 1
    return count
end]],
        [
            "src/counter/init.nupp"
        ] = [[module counter
local spi = package
local {type Counter} = require("counter.spi")
local implementation = assert(spi.providers(Counter)())
export const next = implementation.next]],
        [
            "src/jobs.nupp"
        ] = [[
module jobs
local counter = require("counter")
export function nextCounter(): integer
    return counter.next()
end

export function square(value: integer): integer
    return value * value
end

export function pair(value: integer): (integer, string)
    return value * 2, "done"
end

local function failInsideWorker(): nil
    error("deliberate worker failure", 0)
end

export function fail(): nil
    failInsideWorker()
end

export record Box
    value: integer

    record Label
        text: string

        function size(self): integer
            return #self.text
        end
    end

    function doubled(self): integer
        return self.value * 2
    end
end

export function doubleBox(box: Box): integer
    return box:doubled()
end

export function bumpBox(box: Box): Box
    box.value = box.value + 1
    return box
end

export function labelSize(label: Box.Label): integer
    return label:size()
end

export function gradual(value: any): integer
    return 1
end

export function echo(value: string): string
    return value
end

export record Payload
    id: integer
    label: string
    ready: boolean
end

export function echoPayload(value: Payload): Payload
    return value
end

export function echoDynamic(value: any): any
    return value
end

export function attachmentMarkers(value: any): string
    return value.region:tostring()
        .. ":" .. tostring(value.markers.region.__nuppRegion)
        .. ":" .. tostring(value.markers.moved.__nuppMoved)
        .. ":" .. tostring(value.markers.escaped.__nuppAttachmentTable.nested)
end

export record Sparse
    id: integer
    ready: boolean
    note: string?
end

export function echoSparse(value: Sparse): Sparse
    return value
end

const sharedbytes = io.SharedBytes

export function firstByte(region: io.SharedBytes): integer
    return region:view(0, 1)[1]
end

const heap = table.Array

export function stamp(takes frame: affine(table.Array<uint8>, table.Array.destroy), value: integer): affine(table.Array<uint8>, heap.destroy)
    local writable = frame:write()
    writable[1] = value % 256
    own.drop(writable)

    return frame
end

export function total(takes values: affine(table.Array<int32>, table.Array.destroy)): integer
    local sum: integer = 0
    do
        local readable = values:read()
        for index = 1, #readable do
            sum = sum + readable[index]
        end
    end
    own.drop(values)

    return sum
end

const tasks = require("coroutine")

export function untilCancelled(): nil
    while true do tasks.checkpoint() end
end

export function nested(shards: integer): integer
    local squared: integer = 0
    do local scope = tasks.scope() ;
        squared = scope:work(|| -> shards * shards):await()
    end

    return squared
end
]],
        [
            "src/nupp/internal/workerapp.nupp"
        ] = [[
module nupp.internal.workerapp

const capture = require("capture")
const jobs = require("jobs")
const tasks = require("coroutine")
const sharedbytes = io.SharedBytes

-- Private service entry exercises the shared bootstrap before the public
-- channel API is exported.
const provider = require("nupp.runtime.workersprovider").provider as any
for _ = 1, 3 do
    local services = provider.openscope(nil, nil)
    assert(not services._scheduler.pooled)
    local task = services:worker(jobs.pair, 9)
    local value, label = task:await()
    assert(value == 18 and label == "done")
    services:close()
    assert(services._scheduler.dedicated == 0)
    assert(#services._scheduler.lanes == 0)
end

do
    local services = provider.openscope(nil, nil)
    local occupied: {any} = {}
    local lanes = math.max(1, math.min(os.info().parallelism, 64)) as integer
    for _ = 1, lanes do
        occupied[#occupied + 1] = services:spawn(jobs.untilCancelled)
    end
    local ok, problem = pcall(function(): nil
        assert(services:worker(jobs.square, 7):await() == 49)
        assert(#services._scheduler.lanes == lanes)
    end)
    for _, task in ipairs(occupied) do task:cancel() end
    services:close()
    assert(ok, tostring(problem))
    assert(services._scheduler.dedicated == 0)
end

do
    local services = provider.openscope(nil, nil)
    local failed = services:worker(jobs.fail)
    local ok, problem = pcall(failed.await, failed)
    assert(not ok and tostring(problem):find("deliberate worker failure", 1, true) ~= nil)
    services:close()
    assert(services._scheduler.dedicated == 0)
end

local counter = require("counter")
for index = 1, 100 do assert(counter.next() == index) end
do local scope = tasks.scope() ;
    local independent = scope:work(jobs.nextCounter)
    assert(independent:await() == 1, "the worker has the same SPI index and fresh provider state")
    assert(counter.next() == 101, "worker initialization does not mutate the caller's provider")
    const left = scope:work(6, jobs.square)
    const right = scope:work(7, jobs.square)
    const paired = scope:work(5, jobs.pair)
    const box = jobs.Box(value = 8)
    local dynamicBox = box as any
    dynamicBox.extra = "kept"
    const boxed = scope:work(box, jobs.doubleBox)
    const returnedBox = scope:work(box, jobs.bumpBox)
    const gradualBox = scope:work(box, jobs.gradual)
    const nested = scope:work(jobs.Box.Label(text = "worker"), jobs.labelSize)
    const text = scope:work("native string", jobs.echo)
    const payload = scope:work(jobs.Payload(id = 9, label = "schema", ready = true), jobs.echoPayload)
    local malformed = jobs.Payload(id = 10, label = "fallback", ready = false)
    local dynamicMalformed = malformed as any
    dynamicMalformed.id = "dynamic"
    const fallbackPayload = scope:work(malformed, jobs.echoPayload)
    const anyPayload = scope:work(jobs.Payload(id = 11, label = "any", ready = false), jobs.echoDynamic)
    local spare = jobs.Payload(id = 12, label = "extra", ready = true)
    local dynamicSpare = spare as any
    dynamicSpare.extra = "spare"
    const extraPayload = scope:work(spare, jobs.echoPayload)
    const region = sharedbytes.copy("region payload")
    const regionByte = scope:work(region:slice(7, 7), jobs.firstByte)
    const markerResult = scope:work({
        region = region:slice(0, 6),
        markers = {
            region = {__nuppRegion = 17},
            moved = {__nuppMoved = 99},
            escaped = {__nuppAttachmentTable = {nested = true}},
        },
    }, jobs.attachmentMarkers)
    const sparse = scope:work(jobs.Sparse(id = 13, ready = true), jobs.echoSparse)
    const noted = scope:work(jobs.Sparse(id = 14, ready = false, note = "held"), jobs.echoSparse)
    local doubled, label = paired:await()
    const leftValue = left:await()
    const restored = returnedBox:await()
    const restoredPayload = payload:await()
    const restoredFallback = fallbackPayload:await()
    const restoredAny = anyPayload:await()
    const restoredExtra = extraPayload:await()
    const restoredSparse = sparse:await()
    const restoredNoted = noted:await()
    print(
        leftValue,
        left:await(),
        right:await(),
        doubled,
        label,
        boxed:await(),
        restored:doubled(),
        restored is jobs.Box,
        (restored as any).extra,
        gradualBox:await(),
        nested:await(),
        text:await(),
        restoredPayload.id,
        restoredPayload.label,
        restoredPayload.ready,
        restoredPayload is jobs.Payload,
        (restoredFallback as any).id,
        restoredFallback is jobs.Payload,
        (restoredAny as any).id,
        restoredAny is jobs.Payload,
        (restoredExtra as any).extra,
        restoredExtra is jobs.Payload,
        restoredSparse.id,
        restoredSparse.note == nil,
        restoredSparse is jobs.Sparse,
        restoredNoted.note,
        regionByte:await(),
        markerResult:await(),
        region:slice(0, 6):tostring()
    )
end
print(capture.run(40))

local nestedOk, nestedProblem = pcall(function(): nil
    do local scope = tasks.scope() ;
        scope:work(4, jobs.nested):await()
    end
end)
print(not nestedOk, tostring(nestedProblem):find("another worker scope", 1, true) ~= nil)


local ok, problem = pcall(function(): nil
    do local scope = tasks.scope() ;
        scope:work(jobs.fail)
    end
end)
print(ok, tostring(problem):find("deliberate worker failure", 1, true) ~= nil)
assert(tostring(problem):find("stack traceback:", 1, true) ~= nil, tostring(problem))
assert(tostring(problem):find("nupp-worker", 1, true) ~= nil, tostring(problem))
if io.cli.args[1] == "check-stack" then
    assert(tostring(problem):find("failInsideWorker", 1, true) ~= nil, tostring(problem))
end

local copied, copyProblem = pcall(function(): nil
    do local scope = tasks.scope() ;
        scope:work(setmetatable({value = 1}, {}), jobs.gradual)
    end
end)
print(copied, tostring(copyProblem):find("has a metatable", 1, true) ~= nil)

const ffi = require("ffi")
const heap = table.Array

local frame = heap.alloc(ffi.typeof<uint8>(), 64)
do local scope = tasks.scope() ;
    frame = scope:work(frame, 200, jobs.stamp):await()
end
do
    local readable = frame:read()
    print(frame.count, readable[1])
end
own.drop(frame)

local counts = heap.alloc(ffi.typeof<int32>(), 5)
do
    local writable = counts:write()
    for index = 1, 5 do
        writable[index] = index * 3
    end
    own.drop(writable)
end
do local scope = tasks.scope() ;
    print(scope:work(counts, jobs.total):await())
end

local dynamicShared = sharedbytes as any
assert(dynamicShared.Builder == nil and dynamicShared.newBuilder == nil and dynamicShared.readFile == nil)
assert(dynamicShared.__regionParts == nil and dynamicShared.__regionFromParts == nil)
local loaded, readProblem = sharedbytes.readfile("shared-bytes.bin")
if loaded == nil then error(readProblem or "shared byte file failed") end
assert(loaded:len() == 13 and loaded:tostring() == "engine\0bytes\255")
local absent, missingReason = sharedbytes.readfile("missing-shared-bytes.bin")
assert(absent == nil and type(missingReason) == "string")

local builder = io.Buffer.create()
local lease = builder:reserve(3)
do local writer = lease:span() ;
    writer[1] = 104
    writer[2] = 105
    writer[3] = 33
end
lease:commit(2)
builder:put("!")
print(builder:freeze():tostring())

local type Accounted = {accounted: @nosuspend function(): integer}
local rawShared = require("nupp.mem.sharedbytes.native") as Accounted
collectgarbage("collect")
collectgarbage("collect")
local before = rawShared.accounted()
local grown: io.SharedBytes? = sharedbytes.copy(("y"):rep(65536))
print(rawShared.accounted() - before == 65536, grown ~= nil)
grown = nil
collectgarbage("collect")
collectgarbage("collect")
print(rawShared.accounted() == before)
]],
        [
            "src/capture.nupp"
        ] = [[
module capture

const jobs = require("jobs")
const tasks = require("coroutine")

export function run(base: integer): integer
    const box = jobs.Box(value = 21)
    do local scope = tasks.scope() ;
        const scalar = scope:work(2, |value: integer| -> base + value)
        const record = scope:work(|| -> box:doubled())
        return scalar:await() + record:await()
    end
end
]],
    })
    local built, builtOk = run(dir, "'" .. NUPP .. "' build")
    assert(builtOk, "the native worker binary builds: " .. built)
    local portablePayload = assert(readFile(dir .. "/build/app.payload.lua"))
    assert(portablePayload:sub(1, 3) ~= "\27LJ", "payloadOutput retains Lua source rather than current-host bytecode")
    assert(loadfile(dir .. "/build/app.payload.lua"), "the separately retained payload is a loadable Lua chunk")
    local executable = package.config:sub(1, 1) == "\\" and "build/app.exe" or "./build/app"
    local output, ranOk = run(dir, executable)
    assert(ranOk, "the native worker binary runs: " .. output)
    local expected = "36\t36\t49\t10\tdone\t16\t18\ttrue\tkept\t1\t6\tnative string\t9\tschema\ttrue\ttrue\tdynamic\ttrue\t11\ttrue\tspare\ttrue\t13\ttrue\ttrue\theld\t112\tregion:17:99:true\tregion\n84\ntrue\ttrue\nfalse\ttrue\nfalse\ttrue\n64\t200\n45\nhi!\ntrue\ttrue\ntrue\n"
    assert(output == expected, "results, records, captures, and failures cross structured cleanup: " .. output)
    local rustExecutable = stampRustHost(dir, dir .. "/build/app.payload.lua")
    local rustOutput, rustRanOk = run(dir, rustExecutable .. " check-stack")
    assert(rustRanOk, "the Rust worker host runs the Nupp payload: " .. rustOutput)
    assert(rustOutput == expected, "the Rust host preserves structured worker and shared-byte results: " .. rustOutput)
    os.execute("rm -rf '" .. dir .. "'")
end

-- 100 records per module, below the local-variable limit a module has.
local function recordModule(name, from, to)
    local lines = {"module " .. name, ""}
    for index = from, to do
        lines[#lines + 1] = ("export record R%d\n    v: integer\nend\n"):format(index)
    end
    lines[#lines + 1] = "const makers: {function(): any} = {"
    for index = from, to do
        lines[#lines + 1] = ("    function(): any return R%d(v = %d) end,"):format(index, index)
    end
    lines[#lines + 1] = "}\n"
    lines[
        #lines + 1
    ] = ("export function make(index: integer): any\n    return makers[index - %d]()\nend\n"):format(from - 1)

    return table.concat(lines, "\n")
end

-- A lane is one worker thread for the life of the process, so one task's
-- trouble must stay that task's: a record module that cannot load there, a
-- result carrying a record type past the channel's dictionary, and more
-- unrouted replies than a queue holds each used to end the lane, and every
-- later task sent to it failed.
function M.aTasksFailureLeavesItsLaneRunning()
    local dir = tempProject({
        [
            "nupp.lua"
        ] = [[
return {include = {"src"}, build = {default = "app", targets = {app = {
   kind = "binary", stub = "nupp", entries = {"main"}, outDir = "build",
   payloadOutput = "build/app.payload.lua",
}}}}
]],
        [
            "src/shapes.nupp"
        ] = [[
module shapes

export record Point
    x: integer
    y: integer
end

if rawget(_G, "__nuppWorkerIn") ~= nil then
    error("shapes cannot initialize on a worker lane", 0)
end
]],
        ["src/recs0.nupp"] = recordModule("recs0", 1, 100),
        ["src/recs1.nupp"] = recordModule("recs1", 101, 200),
        ["src/recs2.nupp"] = recordModule("recs2", 201, 300),
        [
            "src/points.nupp"
        ] = [[
module points

const shapes = require("shapes")

export function sum(point: shapes.Point): integer
    return point.x + point.y
end
]],
        [
            "src/jobs.nupp"
        ] = [[
module jobs

const recs0 = require("recs0")
const recs1 = require("recs1")
const recs2 = require("recs2")

export function double(value: integer): integer
    return value * 2
end

export function make(index: integer): any
    if index <= 100 then
        return recs0.make(index)
    elseif index <= 200 then
        return recs1.make(index)
    end
    return recs2.make(index)
end
]],
        [
            "src/main.nupp"
        ] = [[
const jobs = require("jobs")
const points = require("points")
const shapes = require("shapes")
const tasks = require("coroutine")

local function doubled(index: integer): nil
    do local lane = tasks.scope() ;
        assert(lane:work(index, jobs.double):await() == index * 2)
    end
end

local function wide(): boolean
    local ok = pcall(function(): nil
        do local scope = tasks.scope() ;
            for index = 1, 100 do
                scope:spawn(index, doubled)
            end
        end
    end)
    return ok
end

local loaded, loadProblem = pcall(function(): nil
    do local scope = tasks.scope() ;
        scope:work(shapes.Point(x = 1, y = 2), points.sum):await()
    end
end)
print(loaded, tostring(loadProblem):find("cannot initialize on a worker lane", 1, true) ~= nil, wide())

local made = 0
local madeProblem: any = nil
for index = 1, 300 do
    local ok, problem = pcall(function(): nil
        do local scope = tasks.scope() ;
            assert((scope:work(index, jobs.make):await() as any).v == index)
        end
    end)
    if ok then
        made = made + 1
    elseif madeProblem == nil then
        madeProblem = problem
    end
end
print(made, tostring(madeProblem):find("at most 256 record types", 1, true) ~= nil, wide())

-- More than every lane's inbox and outbox hold together, at the 64 lanes a
-- scheduler starts at most; the flood stops at the first refused spawn.
const total: integer = 64 * 2 * 1024 + 1
local spawned = 0
local _, flooded = pcall(function(): nil
    do local scope = tasks.scope() ;
        for index = 1, total do
            local spin = 0
            for _ = 1, 20000 do spin = spin + 1 end
            scope:work(index, jobs.double)
            spawned = index
        end
    end
end)
print(spawned > 1024, tostring(flooded):find("worker queue is full", 1, true) ~= nil, wide())
]],
    })
    local built, builtOk = run(dir, "'" .. NUPP .. "' build")
    assert(builtOk, "the lane-survival binary builds: " .. built)
    local expected = "false\ttrue\ttrue\n256\ttrue\ttrue\ntrue\ttrue\ttrue\n"
    local rustOutput, rustRanOk = run(dir, stampRustHost(dir, dir .. "/build/app.payload.lua"))
    assert(rustRanOk and rustOutput == expected, "a task's failure leaves its lane running: " .. rustOutput)
    os.execute("rm -rf '" .. dir .. "'")
end

function M.taskScopesOwnAndCancelWorkerTasks()
    local dir = tempProject({
        [
            "nupp.lua"
        ] = [[
return {include = {"src"}, build = {default = "app", targets = {app = {
   kind = "binary", stub = "nupp", entries = {"main"}, outDir = "build",
   payloadOutput = "build/app.payload.lua",
}}}}
]],
        [
            "src/jobs.nupp"
        ] = [[
module jobs

const tasks = require("coroutine")

export function cancellable(limit: integer): integer
    for index = 1, limit do
        tasks.checkpoint()
    end

    return limit
end

export function returnsAfterCancellation(): integer
    -- Spins until the cancellation has been requested, then returns anyway:
    -- this is the body that ignores its cancellation, and waiting for the
    -- request orders the return after it however loaded the machine is. A
    -- fixed wait raced the caller and lost on a busy runner.
    const stop = os.clock() + 5
    while os.clock() < stop and pcall(tasks.checkpoint) do end

    return 7
end
]],
        [
            "src/main.nupp"
        ] = [[
const jobs = require("jobs")
const suspension = require("coroutine.sus")
const suspensionHost = require("coroutine.sus.host")
const tasks = require("coroutine")

local runnable: {thread} = {}
local queued: {[thread]: boolean} = {}
local polls = 0
local shutdowns = 0
local function enqueue(task: thread): nil
    if queued[task] or coroutine.status(task) ~= "suspended" then
        return
    end
    queued[task] = true
    runnable[#runnable + 1] = task
end
local function runReady(): nil
    local pass = runnable
    runnable = {}
    for _, task in ipairs(pass) do
        queued[task] = nil
        -- A waker may run before the park that registered it yields, so a queued
        -- task can have moved on by the time its turn comes.
        if coroutine.status(task) == "suspended" then
            local ok, problem = coroutine.resume(task)
            if not ok then error(problem, 0) end
        end
    end
end
local handler = {
    park = function(_: any, waiting: suspensionHost.Waiting): nil
        const task = assert(coroutine.running())
        while not waiting:ready() do
            local woke = false
            waiting:onresume(function(): nil
                assert(not woke, "one wait registration woke the host twice")
                woke = true
                enqueue(task)
            end)
            if not waiting:ready() then coroutine.yield() end
        end
    end,
    canpark = function(): boolean return true end,
    shutdown = function(): nil
        shutdowns = shutdowns + 1
        while #runnable > 0 do runReady() end
    end,
}

const app = coroutine.create(function(): nil
do local handling = suspensionHost.install(handler) ;
do local scope = tasks.scope() ;
    const running = scope:work(1000000000, jobs.cancellable)
    while running:status() == "queued" do
        suspension.poll()
    end
    const requested = running:cancel("stop running")
    const ok, problem = pcall(function(): integer return running:await() end)
    print(requested, ok, tasks.iscancelled(problem),
        tostring(problem):find("stop running", 1, true) ~= nil)
end

do local scope = tasks.scope() ;
    const returning = scope:work(jobs.returnsAfterCancellation)
    while returning:status() == "queued" do suspension.poll() end
    const requested = returning:cancel("observe at return")
    const ok, problem = pcall(function(): integer return returning:await() end)
    print(requested, ok, tasks.iscancelled(problem),
        tostring(problem):find("observe at return", 1, true) ~= nil)
end

-- A fork is a worker child with the task scope's own handle: it counts against the
-- scope's limit until its lane answers, and its result pack comes back intact.
do local scope = tasks.scope(limit = 2) ;
    const forked = scope:work(3, jobs.cancellable)
    const sibling = scope:work(2, jobs.cancellable)
    print(forked:await() + sibling:await(), forked:status(), sibling:isdone())
end

pcall(function(): nil
do local scope = tasks.scope() ;
    for _ = 1, 64 do
        scope:work(1000000000, jobs.cancellable)
    end
    const queued = scope:work(1, jobs.cancellable)
    const wasQueued = queued:status() == "queued"
    const requested = queued:cancel("never start")
    const ok, problem = pcall(function(): integer return queued:await() end)
    print(wasQueued, requested, ok, tasks.iscancelled(problem))
    -- The block's own failure drains the family rather than cancelling it, and
    -- these children spin until told to stop, so say so before leaving.
    scope:cancel("finish queued cancellation test")
    error("finish queued cancellation test", 0)
end
end)

const deadlineOk, deadlineProblem = pcall(function(): nil
    do local scope = tasks.scope(timeoutms = 1) ;
        scope:work(1000000000, jobs.cancellable):await()
    end
end)
print(deadlineOk, tasks.iscancelled(deadlineProblem),
    tostring(deadlineProblem):find("deadline", 1, true) ~= nil,
    tostring(deadlineProblem))
end
print(polls > 0, shutdowns == 1)
end)
enqueue(app)
while coroutine.status(app) ~= "dead" or #runnable > 0 do
    polls = polls + 1
    suspension.poll()
    runReady()
end
]],
    })
    local built, builtOk = run(dir, "'" .. NUPP .. "' build")
    assert(builtOk, "the task-owned worker binary builds: " .. built)
    local executable = package.config:sub(1, 1) == "\\" and "build/app.exe" or "./build/app"
    local output, ranOk = run(dir, executable)
    assert(ranOk, "the task-owned worker binary runs: " .. output)
    -- Every field is exact but the last, which is the cancellation's own message.
    -- Two things can notice one deadline -- the scope that set it and the worker
    -- awaiting inside it -- and a deadline of a millisecond makes which gets
    -- there first a race. Both say the same thing about the same event, and the
    -- field before this one already asserts the message names the deadline.
    local head = "true\tfalse\ttrue\ttrue\ntrue\tfalse\ttrue\ttrue\n"
        .. "5\tdone\ttrue\n"
        .. "true\ttrue\tfalse\ttrue\nfalse\ttrue\ttrue\t"
    local tail = "\ntrue\ttrue\n"
    assert(
        output:sub(1, #head) == head
        and output:sub(-#tail) == tail
        and output:find("cancelled: its deadline passed", 1, true) ~= nil,
        "running, queued, and deadline cancellation share one task identity: " .. output
    )
    local rustExecutable = stampRustHost(dir, dir .. "/build/app.payload.lua")
    for _ = 1, 32 do
        local rustOutput, rustRanOk = run(dir, rustExecutable)
        assert(rustRanOk, "the Rust worker host runs task cancellation: " .. rustOutput)
        assert(
            rustOutput:sub(1, #head) == head
            and rustOutput:sub(-#tail) == tail
            and rustOutput:find("cancelled: its deadline passed", 1, true) ~= nil,
            "Rust-owned workers preserve queued, running, and deadline cancellation: " .. rustOutput
        )
    end
    os.execute("rm -rf '" .. dir .. "'")
end

-- A region's extent is two private fields, and a forged one used to reach the
-- native push beside a moved array: the push refused the region, and freed the
-- array twice. The transfer walk refuses it first, with the array still owned.
function M.aRegionWhoseExtentWasForgedIsRefusedBeforeItCrosses()
    local dir = tempProject({
        [
            "nupp.lua"
        ] = [[
return {include = {"src"}, build = {default = "app", targets = {app = {
   kind = "binary", stub = "nupp", entries = {"main"}, outDir = "build",
   payloadOutput = "build/app.payload.lua",
}}}}
]],
        [
            "src/jobs.nupp"
        ] = [[
module jobs

const heap = table.Array
const sharedbytes = io.SharedBytes

export function inspect(takes frame: affine(table.Array<uint8>, table.Array.destroy), region: io.SharedBytes): integer
    local count = frame.count
    own.drop(frame)
    return count + region:len()
end
]],
        [
            "src/main.nupp"
        ] = [[
const jobs = require("jobs")
const heap = table.Array
const sharedbytes = io.SharedBytes
const tasks = require("coroutine")

local region = sharedbytes.copy("abc")
rawset(region as any, "_length", 99)
local ok, problem = pcall(function(): nil
    local frame = heap.alloc(ffi.typeof<uint8>(), 64)
    do local scope = tasks.scope() ;
        scope:work(frame, region, jobs.inspect)
    end
end)
print(ok, tostring(problem):find("extent lies outside its storage", 1, true) ~= nil)
rawset(region as any, "_length", 3)
local frame = heap.alloc(ffi.typeof<uint8>(), 64)
do local scope = tasks.scope() ;
    print(scope:work(frame, region, jobs.inspect):await())
end
]],
    })
    local built, builtOk = run(dir, "'" .. NUPP .. "' build")
    assert(builtOk, "the forged-region binary builds: " .. built)
    local expected = "false\ttrue\n67\n"
    local rustOutput, rustRanOk = run(dir, stampRustHost(dir, dir .. "/build/app.payload.lua"))
    assert(rustRanOk and rustOutput == expected, "a forged region extent is refused before it crosses: " .. rustOutput)
    os.execute("rm -rf '" .. dir .. "'")
end

function M.bufferFreezeSelectsTheEngineAndFeedsReaders()
    local dir = tempProject({
        [
            "nupp.lua"
        ] = [[
return {include = {"src"}, build = {default = "app", targets = {app = {
   kind = "binary", stub = "nupp", entries = {"main"}, outDir = "build",
   payloadOutput = "build/app.payload.lua",
}}}}
]],
        [
            "src/main.nupp"
        ] = [[
local function freeze(takes buffer: io.Buffer): io.SharedBytes
    return buffer:freeze()
end
local function reader(): io.Reader
    local buffer = io.Buffer.create("skipabc\0def")
    buffer:skip(4)
    return io.Reader.of(freeze(buffer))
end
local input = reader()
local output = io.Buffer.create()
assert(input:readinto(output, 0, 7) == 7)
assert(output:tostring() == "abc\0def")
input:close()
local region = output:freeze()
print(region:tostring() == "abc\0def")
]],
    })
    local built, builtOk = run(dir, "'" .. NUPP .. "' build")
    assert(builtOk, "the byte I/O binary builds: " .. built)
    local output, ranOk = run(dir, stampRustHost(dir, dir .. "/build/app.payload.lua"))
    assert(ranOk and output == "true\n", "buffer freezing selects and uses engine storage: " .. output)
    os.execute("rm -rf '" .. dir .. "'")
end

-- The task-scopes guide's fork inside a spawned child, with more items than
-- slots, run for real. Every slot held by a child waiting on the worker task it
-- forked used to deadlock the scope ("a task cannot complete: no readiness
-- source"), because the fork waited for a slot only a sibling could free and
-- every sibling was doing the same. A child now lends its slot to the task it
-- starts. `taskstest` holds the same for coroutine children; this is the fork.
function M.aSpawnedChildForkingOnAFullScopeDoesNotDeadlock()
    local dir = tempProject({
        [
            "nupp.lua"
        ] = [[
return {include = {"src"}, build = {default = "app", targets = {app = {
   kind = "binary", stub = "nupp", entries = {"main"}, outDir = "build",
   payloadOutput = "build/app.payload.lua",
}}}}
]],
        [
            "src/jobs.nupp"
        ] = [[
module jobs

export function compress(name: string, path: string): integer
    return #name + #path
end
]],
        [
            "src/main.nupp"
        ] = [[
const jobs = require("jobs")
const tasks = require("coroutine")

local paths: {[string]: string} = {}
local expected: integer = 0
for index = 1, 9 do
    paths["item" .. index] = "path/" .. index
    expected = expected + #("item" .. index) + #("path/" .. index)
end
local total: integer = 0
do local scope = tasks.scope(2) ;
    for name, path in pairs(paths) do
        scope:spawn(function(): nil
            const size = scope:work(name, path, jobs.compress):await()
            total = total + size
        end)
    end
end
print(total == expected, total)
]],
    })
    local built, builtOk = run(dir, "'" .. NUPP .. "' build")
    assert(builtOk, "the forking binary builds: " .. built)
    local output, ranOk = run(dir, stampRustHost(dir, dir .. "/build/app.payload.lua"))
    assert(ranOk and output:match("^true\t%d+\n$"), "children forking on a full scope all answered: " .. output)
    os.execute("rm -rf '" .. dir .. "'")
end

-- A worker scope lists only what it may still owe something to. Settled tasks leave
-- it however long the scope lives, a handle still answers after its task has left,
-- and a result holding a moved allocation nothing consumed stays listed so close can
-- free it.
function M.aLongLivedScopeListsOnlyTheWorkerTasksItStillOwes()
    local dir = tempProject({
        [
            "nupp.lua"
        ] = [[
return {include = {"src"}, build = {default = "app", targets = {app = {
   kind = "binary", stub = "nupp", entries = {"nupp.internal.scopeobserver"}, outDir = "build",
   payloadOutput = "build/app.payload.lua",
}}}}
]],
        [
            "src/jobs.nupp"
        ] = [[
module jobs

const heap = table.Array

export function square(value: integer): integer
    return value * value
end

export function stamp(takes frame: affine(table.Array<uint8>, table.Array.destroy), value: integer): affine(table.Array<uint8>, heap.destroy)
    local writable = frame:write()
    writable[1] = value % 256
    own.drop(writable)

    return frame
end
]],
        [
            "src/nupp/internal/scopeobserver.nupp"
        ] = [[
module nupp.internal.scopeobserver

const ffi = require("ffi")
const heap = table.Array
const jobs = require("jobs")
const tasks = require("coroutine")

const lifecycle = rawget(require("nupp.tasks"), "__lifecycle") as function(borrows scope: tasks.Scope): {workers: integer}

local most: integer = 0
local repeated = false
do local scope = tasks.scope(4) ;
    const first = scope:work(3, jobs.square)
    for index = 1, 40 do
        scope:work(index, jobs.square)
        const counts = lifecycle(scope)
        if counts.workers > most then
            most = counts.workers
        end
    end
    repeated = first:await() == 9 and first:await() == 9
end
print(most <= 4, repeated)

local frame = heap.alloc(ffi.typeof<uint8>(), 64)
local owing: integer = -1
do local scope = tasks.scope(1) ;
    scope:work(frame, 7, jobs.stamp)
    for index = 1, 10 do
        scope:work(index, jobs.square)
    end
    scope:work(11, jobs.square):await()
    owing = lifecycle(scope).workers
end
print(owing)
]],
    })
    local built, builtOk = run(dir, "'" .. NUPP .. "' build")
    assert(builtOk, "the worker binary builds: " .. built)
    local output, ranOk = run(dir, stampRustHost(dir, dir .. "/build/app.payload.lua"))
    assert(
        ranOk and output == "true\ttrue\n1\n",
        "settled worker tasks left the scope and the unconsumed moved result stayed: " .. output
    )
    os.execute("rm -rf '" .. dir .. "'")
end

function M.nativeWorkersRequireACompatibleBinaryHost()
    local function rejected(kind, stub)
        local manifest = (
            [[
return {
   include = {"src"},
   build = {default = "app", targets = {app = {
      kind = %q, entries = {"main"}, stub = %s,
   }}},
}
]]
        ):format(kind, stub and string.format("%q", stub) or "nil")
        local dir = tempProject({
            ["nupp.lua"] = manifest,
            [
                "src/main.nupp"
            ] = 'module main\nlocal scope = coroutine.scope()\nscope:work(function(): integer return 42 end)\n',
        })
        local out, ok = run(dir, "'" .. NUPP .. "' build")
        os.execute("rm -rf '" .. dir .. "'")
        assert(
            not ok and out:find('native workers require a binary host with stub = "nupp"', 1, true),
            kind .. " with " .. tostring(stub) .. " is refused before runtime: " .. out
        )
    end

    rejected("binary", "third-party-host")
end

-- One tree, one deliverable, and every claim about it. That a bundle runs under
-- an interpreter that has never heard of nupp, that it carries its resources,
-- that a second build of the same tree produces the same bytes, that it carries
-- what the build compiled rather than what is lying around the output directory,
-- that it says what it could not carry, and that it needs nothing from the tree
-- it came from are six claims about one project -- and were five cases and six
-- builds of the same three files.
--
-- The phases below run in the order they are written and each says what it
-- changed, because two of them do change the tree: the identity phase throws the
-- output directory away so the second build is cold, and the unreachable-resource
-- phase rewrites the manifest. Every assertion names the project it is about, so
-- a failure says which directory to open as well as which claim broke.
function M.oneBundleTreeCarriesRunsRebuildsAndTravelsAlone()
    local dir = tempProject({
        ["nupp.lua"] = MANIFEST,
        ["src/app/main.nupp"] = MAIN,
        ["src/app/greet.nupp"] = GREET,
        ["src/app/data/note.txt"] = "carried along\n",
        ["src/app/data/second.txt"] = "and another\n",
    })
    local where = " (built in " .. dir .. ")"

    local out, ok = run(dir, "'" .. NUPP .. "' build")
    assert(ok, "the bundle target builds" .. where .. ": " .. out)
    local first = readFile(dir .. "/build/app.lua")
    assert(first, "the bundle was written to build/app.lua" .. where)

    -- One file, runnable by an interpreter that has never heard of nupp.
    local ran, ranOk = run(dir, "luajit build/app.lua")
    assert(ranOk, "the bundle runs on its own" .. where .. ": " .. ran)
    assert(
        ran:find("hello, world", 1, true),
        "its modules are reachable through package.preload" .. where .. ": " .. ran
    )
    assert(ran:find("carried along", 1, true), "and its resources came with it" .. where .. ": " .. ran)

    -- Taken now, run in the last phase with this project deleted out from under it.
    local elsewhere = os.tmpname()
    os.remove(elsewhere)
    assert(os.execute("mkdir -p '" .. elsewhere .. "'") == 0)
    assert(os.execute(("cp '%s/build/app.lua' '%s/alone.lua'"):format(dir, elsewhere)) == 0)

    -- Byte-identical across builds. The packaging fixpoint rests on this, and a
    -- bundle that embedded a timestamp or a hash order would fail it in a way that
    -- reproduces once a week. The output directory goes first, so nothing is
    -- reused: the ordering has to be decided by the bundler rather than by
    -- whatever order the last build left behind.
    os.execute("rm -rf '" .. dir .. "/build'")
    local rebuilt, rebuiltOk = run(dir, "'" .. NUPP .. "' build")
    assert(rebuiltOk, "the discarded output directory builds again" .. where .. ": " .. rebuilt)
    assert(first == readFile(dir .. "/build/app.lua"), "two cold builds produce the same bundle" .. where)

    -- The output directory is also where native dependencies build, and their
    -- trees are full of .lua that is examples, tests and scripts, some of which is
    -- not a valid preload module -- so a bundle carries what the build compiled,
    -- not what it finds. This one arrives after the fact, the way cargo's does.
    assert(os.execute("mkdir -p '" .. dir .. "/build/native/examples'") == 0)
    local intruder = assert(io.open(dir .. "/build/native/examples/tool.lua", "wb"))
    intruder:write("#!/usr/bin/env lua\nprint('not a module')\n")
    intruder:close()
    local beside, besideOk = run(dir, "'" .. NUPP .. "' build")
    assert(besideOk, "the build still succeeds beside a foreign tree" .. where .. ": " .. beside)
    local bundle = readFile(dir .. "/build/app.lua")
    assert(not bundle:find("not a module", 1, true), "somebody else's script is not preloaded as a module" .. where)
    local again, againOk = run(dir, "luajit build/app.lua")
    assert(againOk, "and the bundle still parses and runs" .. where .. ": " .. again)

    -- A resource staged beside the entry's directory rather than under it has no
    -- name a running program could ask for. It is left out and said out loud, so
    -- the manifest is rewritten here to ask for one that cannot be named, and the
    -- output directory goes again: this report is one a build makes from nothing
    -- rather than one an incremental build happened to keep.
    local reaching = MANIFEST:gsub('"src/app/data/%*%.txt"', '"src/app/data/*.txt", "extra/*.txt"')
    local rewritten = assert(io.open(dir .. "/nupp.lua", "wb"))
    rewritten:write(reaching)
    rewritten:close()
    assert(os.execute("mkdir -p '" .. dir .. "/extra'") == 0)
    local loose = assert(io.open(dir .. "/extra/loose.txt", "wb"))
    loose:write("not reachable\n")
    loose:close()
    os.execute("rm -rf '" .. dir .. "/build'")
    local reported, reportedOk = run(dir, "'" .. NUPP .. "' build")
    assert(reportedOk, "the build still succeeds with an unreachable resource" .. where .. ": " .. reported)
    assert(
        reported:find("could not be bundled", 1, true),
        "and says what it could not carry" .. where .. ": " .. reported
    )
    bundle = readFile(dir .. "/build/app.lua")
    assert(
        not bundle:find("not reachable", 1, true),
        "the unreachable resource is not embedded under a name nothing reads" .. where
    )
    assert(bundle:find("carried along", 1, true), "the reachable one still is" .. where)

    -- Nothing beside it. A bundle that still needed its build tree would be a
    -- bundle in name only, and the failure would be somebody else's, later.
    os.execute("rm -rf '" .. dir .. "'")
    local alone, aloneOk = run(elsewhere, "luajit alone.lua")
    assert(aloneOk, "the copy runs with its whole project deleted (copied to " .. elsewhere .. "): " .. alone)
    assert(
        alone:find("hello, world", 1, true) and alone:find("carried along", 1, true),
        "modules and resources both survived the move (copied to " .. elsewhere .. "): " .. alone
    )
    os.execute("rm -rf '" .. elsewhere .. "'")
end

function M.aCoroutineOnlyTaskBundleDoesNotAcquireWorkersOrTime()
    local dir = tempProject({
        [
            "nupp.lua"
        ] = [[
return {include = {"src"}, build = {default = "app", targets = {app = {
   kind = "bundle", entries = {"main"}, outDir = "build",
}}}}
]],
        [
            "src/main.nupp"
        ] = [[
const tasks = require("coroutine")
local answer = 0
do local scope = tasks.scope() ;
    answer = scope:spawn(function(): integer return 42 end):await()
end
print(answer)
]],
    })
    local out, ok = run(dir, "'" .. NUPP .. "' build")
    assert(ok, "the coroutine-only task bundle builds without a native host: " .. out)
    local ran, ranOk = run(dir, "luajit build/app.lua")
    assert(ranOk and ran == "42\n", "the standalone task bundle runs: " .. ran)
    os.execute("rm -rf '" .. dir .. "'")
end

-- A rock is a library the program needs and the bundle cannot leave behind: a
-- binary handed to somebody with no rock tree still has to run every command it
-- claims to have. What it carries is what the manifest named, under the name
-- `require` would have found it by in the tree it came from.
local ROCK_MANIFEST = [[
return {
   include = { "src" },
   dependencies = {
      tiny = {
         kind = "luarocks",
         rock = "tinyrock",
         path = "vendor/tinyrock",
         rockspec = "vendor/tinyrock/tinyrock-1.0-1.rockspec",
         bundle = { "tinyrock.lua" },
      },
   },
   build = {
      outDir = "build",
      default = "app",
      targets = {
         app = {
            kind = "bundle",
            entries = { "app.main" },
            dependencies = { "tiny" },
         },
      },
   },
}
]]

local ROCK_MAIN = [[
local tiny = require("tinyrock") as {answer: integer}
print("answer " .. tostring(tiny.answer))
]]

local TINY_ROCKSPEC = [[
package = "tinyrock"
version = "1.0-1"
source = { url = "file://tinyrock.lua" }
description = { summary = "A rock that ships with the project." }
dependencies = { "lua >= 5.1" }
build = { type = "builtin", modules = { tinyrock = "tinyrock.lua" } }
]]

function M.aBundleCarriesTheRockModulesItWasToldTo()
    local dir = tempProject({
        ["nupp.lua"] = ROCK_MANIFEST,
        ["src/app/main.nupp"] = ROCK_MAIN,
        ["vendor/tinyrock/tinyrock.lua"] = "return {answer = 42}\n",
        ["vendor/tinyrock/tinyrock-1.0-1.rockspec"] = TINY_ROCKSPEC,
    })
    local out, ok = run(dir, "'" .. NUPP .. "' build")
    assert(ok, "the bundle target builds: " .. out)

    -- With an empty search path, so nothing installed on this machine can
    -- answer the require: what runs is what the bundle brought.
    local ran, ranOk = run(dir, "LUA_PATH= LUA_CPATH= luajit build/app.lua")
    assert(ranOk, "the bundle runs with nothing on its path: " .. ran)
    assert(ran:find("answer 42", 1, true), "the rock's module came with it: " .. ran)
    os.execute("rm -rf '" .. dir .. "'")
end

-- The compiler's own stage-zero bundle goes through this same code. If the two
-- ever diverge, the bundle a release publishes is being produced by a path
-- nothing else tests. It is fetched rather than tracked, so this asks the
-- toolchain for it the way the launcher does.
function M.theStageZeroIsProducedByTheGeneralBundler()
    local root = HERE .. "/.."
    local handle = assert(io.popen(("'%s/scripts/toolchain' stage0 2>/dev/null"):format(root)))
    local named = handle:read("*a")
    local ok = handle:close()
    assert(ok, "no stage-zero compiler; run scripts/toolchain stage0")
    local stage0 = readFile((named:match("([^\n]+)%s*$")))
    assert(stage0, "the fetched stage zero is readable")
    assert(
        stage0:find('package.preload["nupp.embedded"]', 1, true),
        "it carries its resources the way every bundle does"
    )
    assert(
        stage0:find("package.preload[\"nupp.compiler\"]", 1, true),
        "and preloads its modules the way every bundle does"
    )
end

-- The standard library is this compiler's own Nupp, and it is carried as source
-- rather than described by a second declaration of itself. A project outside the
-- tree therefore types against exactly what was compiled into the binary it runs.
-- Before this it resolved to nothing, and gradual typing turned that into `any`
-- without a word — which then surfaced three steps later as an ownership error.
--
-- Four claims are made about that surface, and each of them used to stand up a
-- project of its own and pay again for compiling it: five checks and a run
-- across four temporary projects, of which the two checks about workers alone
-- cost more than every other bundle case in this file put together. The surface
-- is the fixture, so it is prepared once. One project holds a file per claim,
-- one strict check of the whole project answers all of them at once, and each
-- assertion names the file it is about, so a failure still says which claim
-- broke and which project to look in.
local STD_MANIFEST = 'return {include = {"."}}\n'

--- Whether the report says `code` about `file`.
---
--- Attributed rather than searched: one report now carries every file's
--- diagnostics, so "NUPP2001 is in there somewhere" would pass for the wrong
--- reason as easily as for the right one.
local function diagnosed(report, file, code)
    local prefix = "^" .. file:gsub("%p", "%%%0") .. ":%d+:%d+:"
    for line in report:gmatch("[^\n]+") do
        if line:match(prefix) and line:find(code, 1, true) then
            return true
        end
    end

    return false
end

function M.theStandardLibrarySurfaceIsTypedAndOwnedOutsideThisTree()
    local dir = tempProject({
        ["nupp.lua"] = STD_MANIFEST,
        ["input.txt"] = "hello\n",
        -- The library is typed, not `any`.
        ["typed.nupp"] = [[
local wrong: integer = io.open("x", "r")

return wrong
]],
        -- `types`' checked functions travel with it.
        [
            "format.nupp"
        ] = [[
local function format<F is string>(
    value: F,
    ...: unpackof types.formatarguments(F)
): string
    return string.format(value, ...)
end

print(format("%s=%d", "answer", 42))
]],
        -- Typed is not enough on its own: the ownership contract has to cross too,
        -- or an ordinary local cannot arrange automatic cleanup.
        ["acquire.nupp"] = [[
do
    local file = assert(io.open("input.txt", "r"))
    print(file:read("*a"))
end
]],
        ["leak.nupp"] = [[
local handle = assert(io.open("input.txt", "r"))

return 1
]],
        -- And the workers surface carries both halves.
        ["workerstyped.nupp"] = [[
local tasks = require("coroutine")
local wrong: integer = tasks.scope
return wrong
]],
        [
            "workersowned.nupp"
        ] = [[
local tasks = require("coroutine")
do local scope = tasks.scope() ;
    print(scope ~= nil)
end
return true
]],
    })
    local where = " (checked in " .. dir .. ")"
    local report = run(dir, "'" .. NUPP .. "' check")

    assert(diagnosed(report, "typed.nupp", "NUPP2001"), "the std surface is typed, not any" .. where .. ": " .. report)
    assert(
        not report:find("format.nupp", 1, true),
        "types checked functions are carried with the compiler" .. where .. ": " .. report
    )
    assert(
        diagnosed(report, "workerstyped.nupp", "NUPP2001"),
        "the workers surface is typed rather than gradual" .. where .. ": " .. report
    )
    -- An untouched ordinary owner is discharged by its lexical scope rather than
    -- diagnosed as forgotten, and a worker scope carries the same obligation.
    assert(
        not diagnosed(report, "leak.nupp", "NUPP2603"),
        "the ordinary owner receives automatic cleanup" .. where .. ": " .. report
    )
    assert(
        not diagnosed(report, "workersowned.nupp", "NUPP2603"),
        "a worker scope carries its automatic drain obligation" .. where .. ": " .. report
    )
    -- And each of the two checks clean rather than merely escaping that one code,
    -- which is what their own `check` exiting zero used to say before the files
    -- were checked together with the ones that are meant to fail.
    assert(
        not report:find("leak.nupp", 1, true),
        "an ordinary owner is diagnosed for nothing at all" .. where .. ": " .. report
    )
    assert(
        not report:find("workersowned.nupp", 1, true),
        "an owned worker scope is diagnosed for nothing at all" .. where .. ": " .. report
    )

    -- The private cleanup has to link and run, not only check.
    local acquired, acquiredOk = run(dir, "'" .. NUPP .. "' run acquire.nupp")
    assert(
        acquiredOk and acquired == "hello\n\n",
        "the standard-library private cleanup links and runs" .. where .. ": " .. acquired
    )
    os.execute("rm -rf '" .. dir .. "'")
end

function M.aStampedBinaryParksChannelWaitsWithoutBlockingSiblingTasks()
    local dir = tempProject({
        [
            "nupp.lua"
        ] = [[
return {include = {"src"}, build = {default = "app", targets = {app = {
    kind = "binary", stub = "nupp", entries = {"nupp.internal.channelapp"}, outDir = "build",
    payloadOutput = "build/app.payload.lua",
}}}}
]],
        [
            "src/nupp/internal/channelapp.nupp"
        ] = [[
module nupp.internal.channelapp
local channels = require("nupp.runtime.provider.channels") as any
local storage = require("nupp.runtime.provider.workers") as any
local tasks = require("coroutine")

-- Byte bounds can refuse before the message-count bound, and nil is data.
do
    local sender, receiver = channels.create({}, 2, 10)
    assert(sender:trysend("123") == "sent")
    local status, unsent = sender:trysend("456")
    assert(status == "full" and unsent == "456")
    local kind, value = receiver:tryreceive()
    assert(kind == "value" and value == "123")
    assert(sender:trysend(nil) == "sent")
    assert(sender:trysend(nil) == "sent")
    assert(sender:trysend(nil) == "full")
    local oversized = pcall(sender.trysend, sender, string.rep("x", 100))
    assert(not oversized)
    local forged = setmetatable({}, getmetatable(sender))
    assert(not pcall(sender.trysend, forged, 1))
    sender:close()
    kind, value = receiver:receive()
    assert(kind == "value" and value == nil)
    kind, value = receiver:receive()
    assert(kind == "value" and value == nil)
    assert(receiver:receive() == "closed")
    receiver:close()
end

-- A refused move returns a usable owner; acceptance transfers it exactly once.
do
    local sender, receiver = channels.create({}, 1, 128)
    assert(sender:trysend(nil) == "sent")
    local buffer = table.Array.alloc(ffi.typeof<uint8>(), 4)
    do local writing = buffer:write(); writing[1] = 23 end
    local raw: any = @unsafe own.release(buffer)
    local status, unsent = sender:trysend(raw)
    assert(status == "full" and raw.closed)
    assert(unsent:read():get(1) == 23)
    assert(receiver:receive() == "value")
    assert(sender:trysend(unsent) == "sent" and unsent.closed)
    local kind, arrived = receiver:receive()
    assert(kind == "value" and arrived:read():get(1) == 23)
    storage.channeldrop(arrived)
    local published = io.SharedBytes.copy("a\0b")
    assert(sender:trysend(published) == "sent")
    kind, arrived = receiver:receive()
    assert(kind == "value" and arrived:tostring() == "a\0b")
    assert(published:tostring() == "a\0b")
    local large = io.SharedBytes.copy(string.rep("x", 4096))
    assert(not pcall(sender.send, sender, large:slice(0, 1)))
    receiver:close()
    local refused = table.Array.alloc(ffi.typeof<uint8>(), 4)
    status, unsent = sender:trysend(@unsafe own.release(refused))
    assert(status == "closed" and unsent.count == 4)
    storage.channeldrop(unsent)
    sender:close()
end

local observed = 0
do local scope = tasks.scope(2, 1000) ;
    local sender, receiver = channels.create({}, 1, 64)
    scope:spawn(function(): nil
        for index = 1, 100 do sender:send(index) end
        sender:close()
    end)
    scope:spawn(function(): nil
        while true do
            local kind, value = receiver:receive()
            if kind == "closed" then break end
            observed += 1
            assert(value == observed)
        end
        receiver:close()
    end)
end
assert(observed == 100)

-- Cancellation removes a parked subscription without accepting its pending send.
for _, sending in ipairs({false, true}) do
    local sender, receiver = channels.create({}, 1, 64)
    if sending then sender:send(1) end
    local entered = false
    local began, started = channels.create({}, 1, 64)
    do local scope = tasks.scope(1, 1000) ;
        local child = scope:spawn(function(): nil
            entered = true
            began:send(true)
            if sending then sender:send(2) else receiver:receive() end
        end)
        assert(started:receive() == "value")
        assert(entered)
        child:cancel()
    end
    began:close()
    started:close()
    if sending then
        local kind, value = receiver:tryreceive()
        assert(kind == "value" and value == 1)
    end
    assert(receiver:tryreceive() == "empty")
    sender:close()
    receiver:close()
end
print("channels-ok")
]],
    })
    local built, builtOk = run(dir, "'" .. NUPP .. "' build")
    assert(builtOk, "the channel binary builds: " .. built)
    local output, ranOk = run(dir, stampRustHost(dir, dir .. "/build/app.payload.lua"))
    assert(ranOk and output == "channels-ok\n", "channel waits cooperate and cancel: " .. output)
    os.execute("rm -rf '" .. dir .. "'")
end

function M.aStampedDedicatedWorkerExchangesChannelsBeforeReturning()
    local dir = tempProject({
        [
            "nupp.lua"
        ] = [[
return {include = {"src"}, build = {default = "app", targets = {app = {
    kind = "binary", stub = "nupp", entries = {"nupp.internal.serviceapp"}, outDir = "build",
    payloadOutput = "build/app.payload.lua",
}}}}
]],
        [
            "src/nupp/internal/servicejobs.nupp"
        ] = [[
module nupp.internal.servicejobs
local {type Sender, type Receiver} = require("nupp.workers.internal.channeltypes")

export function service(takes incoming: Receiver<integer>, takes outgoing: Sender<integer>): integer
    local commands = incoming
    local events = outgoing
    local count: integer = 0
    while true do
        local kind, value = commands:receive()
        if kind == "closed" then return count end
        count += 1
        events:send(value * value)
    end
end

export function produce(takes outgoing: Sender<integer>): nil
    local events = outgoing
    local value: integer = 0
    while true do
        value += 1
        events:send(value)
    end
end

export function returnEndpoint(takes commands: Receiver<integer>): affine(Receiver<integer>)
    return commands
end
]],
        [
            "src/nupp/internal/serviceapp.nupp"
        ] = [[
module nupp.internal.serviceapp
local jobs = require("nupp.internal.servicejobs")
local channels = require("nupp.runtime.provider.channels") as any
local provider = require("nupp.runtime.workersprovider").provider as any
local native = require("nupp.workers.native") as any
local time = require("coroutine")
local ffi = require("ffi")
ffi.cdef("int usleep(unsigned int usec);")

-- The public API preserves both endpoint owners and the child's scope loan.
for _ = 1, 3 do
    local scope = coroutine.scope()
    local commands, requests = scope:channel<integer>(2, 64)
    local replies, events = scope:channel<integer>(1, 64)
    local child = scope:worker(requests, replies, jobs.service)
    for index = 1, 100 do
        commands:send(index)
        local kind, value = events:receive()
        assert(kind == "value" and value == index * index)
    end
    commands:close()
    events:close()
    assert(child:await() == 100)
    -- Let the thread end without polling: scope cleanup must still drive its join.
    ffi.C.usleep(2000)
end

do
    local scope = coroutine.scope()
    local sender, receiver = scope:channel<integer>(1, 64)
    local child = scope:spawn(function(): nil takes(sender)
        local output = sender
        output:send(17)
    end)
    local kind, value = receiver:receive()
    assert(kind == "value" and value == 17)
    child:await()
end

do
    local scope = coroutine.scope()
    local sender, receiver = scope:channel<affine(table.Array<uint8>, table.Array.destroy)>(1, 64)
    local first = table.Array.alloc(ffi.typeof<uint8>(), 4)
    sender:send(first)
    local second = table.Array.alloc(ffi.typeof<uint8>(), 4)
    local status, returned = sender:trysend(second)
    assert(status == "full")
    if status ~= "sent" then
        assert(returned.count == 4)
        own.drop(returned)
    end
    local kind, arrived = receiver:receive()
    if kind == "value" then
        assert(arrived.count == 4)
        own.drop(arrived)
    else
        error("the accepted array was lost")
    end
end

for _ = 1, 3 do
    local services = provider.openscope(nil, nil)
    local commands, requests = channels.create(services, 2, 64)
    local replies, events = channels.create(services, 1, 64)
    local child = services:worker(jobs.service, requests, replies)
    assert(not pcall(requests.tryreceive, requests))
    assert(not pcall(replies.trysend, replies, 1))
    for index = 1, 100 do
        commands:send(index)
        local kind, value = events:receive()
        assert(kind == "value" and value == index * index)
    end
    commands:close()
    events:close()
    assert(child:await() == 100)
    services:close()
    assert(services._scheduler.dedicated == 0)
    assert(#services._scheduler.lanes == 0)
end

-- A blocked event publisher cannot prevent cancellation or its control reply.
do
    local services = provider.openscope(nil, nil)
    local output, events = channels.create(services, 1, 64)
    local child = services:worker(jobs.produce, output)
    local deadline = os.monotonic() + 1000
    while native.endpointReady(events._state.handle, 0) ~= 0 do
        assert(os.monotonic() < deadline)
        time.sleep(1)
    end
    assert(child:cancel())
    assert(not pcall(child.await, child))
    local kind, value = events:receive()
    assert(kind == "value" and value == 1)
    assert(events:receive() == "closed")
    events:close()
    services:close()
    assert(services._scheduler.dedicated == 0)
end

-- Runtime checks back up the static scope and transfer restrictions.
do
    local services = provider.openscope(nil, nil)
    local sending, receiving = channels.create(services, 1, 64)
    sending:send("unread")
    services:close()
    assert(not pcall(receiving.tryreceive, receiving))
    assert(not pcall(sending.trysend, sending, 1))
    sending:close()
    receiving:close()
end

do
    local services = provider.openscope(nil, nil)
    local other = provider.openscope(nil, nil)
    local commands, requests = channels.create(other, 1, 64)
    local accepted, problem = pcall(services.worker, services, jobs.returnEndpoint, requests)
    assert(not accepted and tostring(problem):find("another scope", 1, true) ~= nil)
    assert(commands:trysend(1) == "closed")
    commands:close()
    other:close()
    services:close()
end

do
    local services = provider.openscope(nil, nil)
    local commands, requests = channels.create(services, 1, 64)
    local child = services:worker(jobs.returnEndpoint, requests)
    local accepted, problem = pcall(child.await, child)
    assert(not accepted and tostring(problem):find("channel endpoint", 1, true) ~= nil)
    assert(commands:trysend(1) == "closed")
    commands:close()
    services:close()
end
print("services-ok")
]],
    })
    local built, builtOk = run(dir, "'" .. NUPP .. "' build")
    assert(builtOk, "the service binary builds: " .. built)
    local output, ranOk = run(dir, stampRustHost(dir, dir .. "/build/app.payload.lua"))
    assert(ranOk and output == "services-ok\n", "dedicated channels move, communicate and settle: " .. output)
    os.execute("rm -rf '" .. dir .. "'")
end

return M
