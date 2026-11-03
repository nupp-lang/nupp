local test = require("assert")
local providerstate = require("helpers.providerstate")
local M = {}

function M.preservesTheHostTableAndQueriesParallelismPerCall()
    local count, queries = 2, 0
    local uuidLoads, calls4, calls7 = 0, 0, 0
    local valid4 = "12345678-1234-4123-8123-123456789abc"
    local valid7 = "12345678-1234-7123-8123-123456789abc"
    local original = {
        clock = function()
            return 9
        end
    }
    local monotonic, walltime = function()
        return 123.5
    end, function()
        return 1700000000123
    end
    local uuid4, uuid7 = function()
        calls4 = calls4 + 1
        return valid4
    end, function()
        calls7 = calls7 + 1
        return valid7
    end
    local randombytes = function(count)
        return ("r"):rep(count)
    end
    local load = providerstate.instance(
        {["nupp.runtime.standardos"] = true, ["nupp.util.internal.uuid"] = true},
        {
            ["nupp.runtime.system"] = {
                platform = "fixture",
                architecture = "fixture64",
                endianness = "little",
                pointerBits = 64,
                availableParallelism = function()
                    queries = queries + 1;
                    return count
                end,
            },
            ["nupp.runtime.clocks"] = {selected = {now = monotonic, walltime = walltime}},
            ["nupp.runtime.entropy"] = {randombytes = randombytes},
        },
        {
            ["nupp.runtime.uuidprovider"] = function()
                uuidLoads = uuidLoads + 1
                return {uuid4 = uuid4, uuid7 = uuid7}
            end,
        },
        {os = original}
    )
    local surface = load("nupp.runtime.standardos")
    test.eq(surface.value, original)
    test.eq(queries, 0)
    local first = original.info()
    test.eq(first.platform, "fixture")
    test.eq(first.arch, "fixture64")
    test.eq(first.endianness, "little")
    test.eq(first.pointerbits, 64)
    test.eq(first.parallelism, 2)
    count = 7
    test.eq(original.info().parallelism, 7)
    test.eq(first.parallelism, 2)
    test.eq(queries, 2)
    test.eq(original.monotonic, monotonic)
    test.eq(original.walltime, walltime)
    test.eq(uuidLoads, 0, "system and clock queries do not select a UUID provider")
    local random, ordered = original.uuid4, original.uuid7
    test.eq(random, surface.uuid4, "the public table and exported function share one callable")
    test.eq(ordered, surface.uuid7)
    test.eq(original.uuid4, random, "repeated public reads retain their callable identity")
    test.eq(original.uuid7, ordered)
    test.eq(random(), valid4)
    test.eq(original.uuid4(), valid4)
    test.eq(ordered(), valid7)
    test.eq(surface.uuid7(), valid7)
    test.eq(uuidLoads, 1, "both UUID versions retain the same selected provider")
    test.eq(calls4, 2, "each public version 4 call invokes its provider exactly once")
    test.eq(calls7, 2, "each public version 7 call invokes its provider exactly once")
    test.eq(surface.randombytes, randombytes)
    test.eq(original.randombytes, randombytes)
    test.eq(original.randombytes(3), "rrr")
    test.eq(require("math.random").randombytes, nil)
    test.eq(original.clock(), 9)
end

function M.checkedInfoAndServicesUseThePrivateContract()
    local parser = require("nupp.compiler.syntax.parser")
    local checker = require("helpers.fragment")
    local gen = require("nupp.compiler.lua.gen")
    local root = require("helpers.paths").tests .. "/.."
    local env = require("nupp.compiler.project.env").new(root)
    local source = [[
local function describe(value: os.Info): string return value.platform end
local facts: os.Info = os.info()
local monotonic: number = os.monotonic()
local wall: number = os.walltime()
local random: string = os.uuid4()
local ordered: string = os.uuid7()
local bytes: string = os.randombytes(7)
return describe(facts), monotonic, wall, random, ordered, bytes
]]
    local parsed = parser.parse(source, "system-services.nupp")
    test.eq(#parsed.errors, 0)
    local diagnostics = checker.check(parsed, "system-services.nupp", env)
    test.eq(#diagnostics, 0, diagnostics[1] and diagnostics[1].msg)
    local code, generated = gen.generate(parsed, "system-services.nupp")
    test.eq(#generated, 0)
    assert(code:find('require("nupp.runtime.standardos")', 1, true))
    assert(
        parsed.effects["runtime.system"]
        and parsed.effects["runtime.clocks"]
        and parsed.effects["runtime.uuid"]
        and parsed.effects["runtime.crypto"]
    )
    local platform, monotonic, wall, random, ordered, bytes = assert(loadstring(code))()
    test.eq(platform, os.info().platform)
    test.eq(type(monotonic), "number")
    test.eq(type(wall), "number")
    test.eq(#random, 36)
    test.eq(#ordered, 36)
    test.eq(#bytes, 7)
end

function M.clockInstallerDoesNotPackageUuidAtAnyOptimizationLevel()
    local parser = require("nupp.compiler.syntax.parser")
    local checker = require("helpers.fragment")
    local gen = require("nupp.compiler.lua.gen")
    local native = require("nupp.compiler.native")
    local optimize = require("nupp.compiler.lua.optimize")
    local root = require("helpers.paths").tests .. "/.."
    local path = root .. "/src/nupp/runtime/standardos.nupp"
    local file = assert(io.open(path, "rb"))
    local source = file:read("*a")
    file:close()
    for _, level in ipairs({0, 1, 2}) do
        local parsed = parser.parse(source, path)
        test.eq(#parsed.errors, 0)
        local env = require("nupp.compiler.project.env").new(root, {cache = false})
        local diagnostics = checker.check(parsed, path, env)
        test.eq(#diagnostics, 0, diagnostics[1] and diagnostics[1].msg)
        optimize.run(parsed, {level = level})
        local code, generated, _, emitted = gen.generate(parsed, path)
        test.eq(#generated, 0)
        local expanded = native.expand(emitted)
        assert(
            not expanded["runtime.uuid"] and not expanded["native.uuid"],
            "OS initialization selected unused UUID support"
        )
        for _, name in ipairs(gen.runtimeModules(code)) do
            assert(
                name ~= "nupp.util.internal.uuid"
                and name ~= "nupp.runtime.uuidprovider"
                and name ~= "nupp.runtime.provider.nativeuuid",
                "OS initialization packages unused UUID module " .. name
            )
        end
    end
end

function M.directAndAliasedUuidCallsCarryTheHelperAndProvider()
    local parser = require("nupp.compiler.syntax.parser")
    local checker = require("helpers.fragment")
    local gen = require("nupp.compiler.lua.gen")
    local native = require("nupp.compiler.native")
    local root = require("helpers.paths").tests .. "/.."
    local sources = {
        "print(os.uuid4())",
        "local make = os.uuid4\nprint(make())",
        "local system = os\nprint(system.uuid7())",
        "local system = require('os')\nprint(system.uuid4())",
        "module nupp.uuidfixture\nlocal system = require('nupp.runtime.standardos')\nprint(system.uuid7())",
        "module nupp.uuidfixture\nlocal system = require('nupp.runtime.standardos')\nlocal make = system.uuid4\nprint(make())",
    }
    for _, source in ipairs(sources) do
        local path = source:match("^module nupp%.uuidfixture") and root .. "/src/nupp/uuidfixture.nupp"
            or "uuid-features.nupp"
        local parsed = parser.parse(source, path)
        test.eq(#parsed.errors, 0, source)
        local env = require("nupp.compiler.project.env").new(root, {cache = false})
        local diagnostics = checker.check(parsed, path, env)
        test.eq(#diagnostics, 0, diagnostics[1] and diagnostics[1].msg)
        local _, generated, _, emitted = gen.generate(parsed, path)
        test.eq(#generated, 0)
        assert(emitted["runtime.uuid"], "the UUID read lost its explicit feature: " .. source)
        local modules = {}
        for effect in pairs(native.expand(emitted)) do
            local feature = native.feature(effect)
            if feature and feature.runtimeModule then
                modules[feature.runtimeModule] = true
            end
        end
        assert(modules["nupp.util.internal.uuid"], "the UUID feature omits its validating helper")
        assert(modules["nupp.runtime.uuidprovider"], "the UUID feature omits its selected provider")
    end
end

return M
