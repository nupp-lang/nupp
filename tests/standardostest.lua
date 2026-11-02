local test = require("assert")
local providerstate = require("providerstate")
local M = {}

function M.preservesTheHostTableAndQueriesParallelismPerCall()
    local count, queries = 2, 0
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
        return "uuid4"
    end, function()
        return "uuid7"
    end
    local randombytes = function(count)
        return ("r"):rep(count)
    end
    local load = providerstate.instance(
        {["nupp.runtime.standardos"] = true},
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
            ["nupp.util.internal.uuid"] = {uuid4 = uuid4, uuid7 = uuid7},
            ["nupp.runtime.entropy"] = {randombytes = randombytes},
        },
        nil,
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
    test.eq(original.uuid4, uuid4)
    test.eq(original.uuid7, uuid7)
    test.eq(surface.randombytes, randombytes)
    test.eq(original.randombytes, randombytes)
    test.eq(original.randombytes(3), "rrr")
    test.eq(require("nupp.random").randombytes, nil)
    test.eq(original.clock(), 9)
end

function M.checkedInfoAndServicesUseThePrivateContract()
    local parser = require("nupp.compiler.syntax.parser")
    local checker = require("fragment")
    local gen = require("nupp.compiler.lua.gen")
    local root = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]")) .. "/.."
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

return M
