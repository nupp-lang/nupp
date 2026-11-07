local fixture = require("helpers.bundlefixture")
local NUPP = fixture.NUPP
local packaging = fixture.packaging
local tempProject = fixture.tempProject
local readFile = fixture.readFile
local run = fixture.run
local COMPONENT_MANIFEST = fixture.COMPONENT_MANIFEST

local M = {}

function M.aComponentInstallsBeforeItsEntryRuns()
    local dir = tempProject({
        ["nupp.lua"] = COMPONENT_MANIFEST,
        [
            "src/app/main.nupp"
        ] = [[
local json = require("serde.json")
local {type Checksum, type CompressionFormat, hexencode} = require("bytes")
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

return M
