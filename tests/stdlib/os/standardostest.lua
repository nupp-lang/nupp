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
    local program = require("program")
    local environment = require("nupp.compiler.project.env")
    local env = environment.new(assert(environment.compilerRoot()))
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
    program.installSourceModules()
    local image = program.image(parsed, "systemservices")
    assert(program.names(image, "nupp.runtime.standardos"))
    assert(
        parsed.effects["runtime.system"]
        and parsed.effects["runtime.clocks"]
        and parsed.effects["runtime.uuid"]
        and parsed.effects["runtime.crypto"]
    )
    local loadImage = assert(rawget(_G, "__nupp_load_image"))
    local chunk = assert(loadImage(image))
    local platform, monotonic, wall, random, ordered, bytes = chunk()
    test.eq(platform, os.info().platform)
    test.eq(type(monotonic), "number")
    test.eq(type(wall), "number")
    test.eq(#random, 36)
    test.eq(#ordered, 36)
    test.eq(#bytes, 7)
    test.eq(os.randombytes, require("nupp.runtime.entropy").randombytes)
    test.eq(require("os"), os)
end

return M
