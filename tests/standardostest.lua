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
            ["nupp.runtime.clocks"] = {selected = {now = monotonic, wallTime = walltime}},
            ["nupp.util.internal.uuid"] = {uuid4 = uuid4, uuid7 = uuid7},
        },
        nil,
        {os = original}
    )
    local surface = load("nupp.runtime.standardos")
    test.equal(surface.value, original)
    test.equal(queries, 0)
    local first = original.info()
    test.equal(first.platform, "fixture")
    test.equal(first.arch, "fixture64")
    test.equal(first.endianness, "little")
    test.equal(first.pointerbits, 64)
    test.equal(first.parallelism, 2)
    count = 7
    test.equal(original.info().parallelism, 7)
    test.equal(first.parallelism, 2)
    test.equal(queries, 2)
    test.equal(original.monotonic, monotonic)
    test.equal(original.walltime, walltime)
    test.equal(original.uuid4, uuid4)
    test.equal(original.uuid7, uuid7)
    test.equal(original.clock(), 9)
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
return describe(facts), monotonic, wall, random, ordered
]]
    local parsed = parser.parse(source, "system-services.nupp")
    test.equal(#parsed.errors, 0)
    local diagnostics = checker.check(parsed, "system-services.nupp", env)
    test.equal(#diagnostics, 0, diagnostics[1] and diagnostics[1].msg)
    local code, generated = gen.generate(parsed, "system-services.nupp")
    test.equal(#generated, 0)
    assert(code:find('require("nupp.runtime.standardos")', 1, true))
    assert(parsed.effects["runtime.system"] and parsed.effects["runtime.clocks"] and parsed.effects["runtime.uuid"])
    local platform, monotonic, wall, random, ordered = assert(loadstring(code))()
    test.equal(platform, os.info().platform)
    test.equal(type(monotonic), "number")
    test.equal(type(wall), "number")
    test.equal(#random, 36)
    test.equal(#ordered, 36)
end

return M
