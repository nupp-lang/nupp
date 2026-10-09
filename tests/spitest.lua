local fs = require("nupp.compiler.fs")
local project = require("nupp.tools.build.project")
local process = require("nupp.compiler.process")
local discovery = require("nupp.tools.build.spi")
local M = {}

local function fixture(files, body)
    local dir = os.tmpname()
    os.remove(dir)
    assert(fs.mkdir(dir))
    for name, source in pairs(files) do
        assert(fs.writeFile(fs.join(dir, name), source))
    end
    local ok, why = pcall(body, dir)
    assert(require("nupp.io.files").remove(dir, true))
    assert(ok, why)
end

local function files(main, descriptor)
    return {
        [
            "nupp.lua"
        ] = [[return {include = {"src"}, build = {
            kind = "bundle", outDir = "out",
            output = "out/app.lua", entries = {"main"}
        }}]],
        ["nupp/spi.json"] = descriptor or [[{"example.api.Codec":["example.first","example.second"]}]],
        [
            "src/example/api.nupp"
        ] = [[module example.api
export interface Codec
    @readonly encode: function(value: string): string
end]],
        [
            "src/example/first.nupp"
        ] = [[module example.first
export function encode(value: string): string return "first:" .. value end]],
        [
            "src/example/second.nupp"
        ] = [[module example.second
export function encode(value: string): string return "second:" .. value end]],
        ["src/main.nupp"] = main,
    }
end

local function run(dir)
    local produced = {}
    assert(project.build(dir, {produced = produced}) == 0, "SPI fixture did not build")
    local status, output = process.capture({"luajit", dir .. "/out/app.lua"})
    assert(status == 0, output)

    -- Printed lines use CRLF on Windows; the provider results are the same.

    return produced, (output:gsub("\r\n", "\n"))
end

function M.typedLazyIterationRetainsModuleIdentityAndBindsDirectFunctions()
    local sources = files(
        [[module main
local spi = require("nupp.spi")
local {type Codec} = require("example.api")
local next = spi.load(Codec)
local first = assert(next())
local second = assert(next())
assert(next() == nil and next() == nil)
assert(first.encode("x") == "first:x")
assert(second.encode("x") == "second:x")
assert(spi.load(Codec)() == first)
assert(nupp.spi.load(Codec)() == first)
local api = require("example.api")
assert(spi.load(api.Codec)() == first)
local encode = first.encode
for i = 1, 10 do assert(encode("x") == "first:x") end
print("ok")]]
    )
    fixture(sources, function(dir)
        local produced, output = run(dir)
        assert(output == "ok\n", output)
        assert(#produced.spi == 2)
        assert(produced.spi[1].interface == "example.api.Codec")
        local code = assert(fs.readFile(dir .. "/out/main.lua"))
        assert(code:find('"example.api.Codec"', 1, true), code)
    end)
end

function M.earlyTerminationDoesNotLoadLaterProviders()
    local sources = files(
        [[module main
local {load as providers} = require("nupp.spi")
local {type Codec as Interface} = require("example.api")
for candidate in providers(Interface) do
    assert(candidate.encode("x") == "first:x")
    break
end
print("ok")]]
    )
    sources["src/example/second.nupp"] = sources["src/example/second.nupp"] .. '\nerror("must stay unloaded")'
    fixture(sources, function(dir)
        local _, output = run(dir)
        assert(output == "ok\n", output)
    end)
end

function M.emptyDiscoveryUsesOrdinaryFallback()
    fixture(
        files(
            [[module main
local spi = require("nupp.spi")
local {type Codec} = require("example.api")
local provider: Codec = spi.load(Codec)() ?? require("example.first")
assert(provider.encode("x") == "first:x")
print("ok")]],
            "{}"
        ),
        function(dir)
            local _, output = run(dir)
            assert(output == "ok\n", output)
        end
    )
end

function M.discoveryUsesDeclaredDependencyOrderAndDeduplicates()
    fixture(
        {
            ["nupp/spi.json"] = [[{"example.api.Codec":["app.codec","app.codec"]}]],
            ["z/spi.json"] = [[{"example.api.Codec":["z.codec"]}]],
            ["a/spi.json"] = [[{"example.api.Codec":["a.codec"]}]],
            ["child/spi.json"] = [[{"example.api.Codec":["child.codec","app.codec"]}]],
            ["tool/spi.json"] = [[{"example.api.Codec":["tool.codec"]}]],
        },
        function(dir)
            local entries = assert(
                discovery.read(
                    dir,
                    {dependencies = {z = {dependencies = {"child"}}, a = {}, child = {}, tool = {},}},
                    {dependencies = {"z", "a", "child"}},
                    {
                        z = {typeRoot = dir .. "/z"},
                        a = {typeRoot = dir .. "/a"},
                        child = {typeRoot = dir .. "/child"},
                        tool = {typeRoot = dir .. "/tool"},
                    }
                )
            )
            local names = {}
            for _, entry in ipairs(entries) do
                names[#names + 1] = entry.implementation
            end
            assert(table.concat(names, ",") == "app.codec,z.codec,child.codec,a.codec")
        end
    )
end

function M.descriptorsRejectMalformedDocumentsShapesAndNames()
    local cases = {
        {"{", "must contain an interface-to-module object"},
        {"[]", "must contain an interface-to-module object"},
        {"null", "must contain an interface-to-module object"},
        {[[{"Codec":[]}]], "invalid qualified interface Codec"},
        {[[{"example.1Codec":[]}]], "invalid qualified interface example.1Codec"},
        {[[{"example.while.Codec":[]}]], "invalid qualified interface example.while.Codec"},
        {[[{"example.api.while":[]}]], "invalid qualified interface example.api.while"},
        {[[{"example.api.Codec":{}}]], "must list implementation modules"},
        {[[{"example.api.Codec":["example.1codec"]}]], "invalid implementation module"},
        {[[{"example.api.Codec":["example.end"]}]], "invalid implementation module"},
        {[[{"example.api.Codec":[null]}]], "invalid implementation module"},
    }
    for _, case in ipairs(cases) do
        fixture({["nupp/spi.json"] = case[1]}, function(dir)
            local entries, problem = discovery.read(dir, {dependencies = {}}, {dependencies = {}}, {})
            assert(entries == nil, "invalid SPI descriptor was accepted: " .. case[1])
            assert(tostring(problem):find(case[2], 1, true), tostring(problem))
        end)
    end
end

-- `nupp/spi.json` travels inside dependency type roots, so it crosses compiler
-- versions. A key starting with `$` is reserved for metadata and ignored, so
-- `$schema` or a later `$version` can be added without breaking an older
-- reader; any other key is still an interface name and still checked.
function M.descriptorsIgnoreDollarKeysAndStillRefuseOtherUnknownKeys()
    fixture(
        {
            [
                "nupp/spi.json"
            ] = [[{"$schema":"https://example.com/spi.json","$version":2,
            "example.api.Codec":["example.first"]}]]
        },
        function(dir)
            local entries, problem = discovery.read(dir, {dependencies = {}}, {dependencies = {}}, {})
            assert(entries, tostring(problem))
            assert(#entries == 1 and entries[1].implementation == "example.first", "a $ key became an entry")
        end
    )
    fixture({["nupp/spi.json"] = [[{"schema":"x","example.api.Codec":[]}]]}, function(dir)
        local entries, problem = discovery.read(dir, {dependencies = {}}, {dependencies = {}}, {})
        assert(entries == nil, "an unknown key without $ was accepted")
        assert(tostring(problem):find("invalid qualified interface schema", 1, true), tostring(problem))
    end)
end

function M.discoveryTerminatesDependencyCyclesWithoutChangingFirstOccurrenceOrder()
    fixture(
        {
            ["a/spi.json"] = [[{"example.api.Codec":["a.codec","shared.codec"]}]],
            ["b/spi.json"] = [[{"example.api.Codec":["b.codec","shared.codec"]}]],
        },
        function(dir)
            local entries = assert(
                discovery.read(
                    dir,
                    {dependencies = {a = {dependencies = {"b"}}, b = {dependencies = {"a"}},}},
                    {dependencies = {"a"}},
                    {a = {typeRoot = dir .. "/a"}, b = {typeRoot = dir .. "/b"},}
                )
            )
            local names = {}
            for _, entry in ipairs(entries) do
                names[#names + 1] = entry.implementation .. ":" .. entry.dependency
            end
            assert(table.concat(names, ",") == "a.codec:a,shared.codec:a,b.codec:b", table.concat(names, ","))
        end
    )
end

function M.generatedIndexesAreDeterministicAndReportWriteFailures()
    fixture({}, function(dir)
        local entries = {
            {interface = "z.Api", implementation = "z.second"},
            {interface = "a.Api", implementation = "a.first"},
            {interface = "z.Api", implementation = "z.first"},
        }
        assert(discovery.write(dir, "out", entries))
        local generated = assert(fs.readFile(dir .. "/out/generated/nupp/spi/index.g.nupp"))
        local expected = [[module nupp.spi.index
const _DYNAMIC_REQUIRES = "@requires-dynamically z.second @requires-dynamically a.first @requires-dynamically z.first"
export = {
    ["a.Api"] = {"a.first"},
    ["z.Api"] = {"z.second", "z.first"},
}
]]
        assert(generated == expected, generated)
        assert(discovery.write(dir, "out", entries), "rewriting the same index failed")

        assert(fs.writeFile(dir .. "/blocked", "not a directory"))
        local wrote, problem = discovery.write(dir, "blocked/child", entries)
        assert(not wrote and problem ~= nil, "an index write failure was reported as success")
    end)
end

function M.providerErrorsAreNotTreatedAsAbsence()
    local sources = files(
        [[module main
local spi = require("nupp.spi")
local {type Codec} = require("example.api")
for candidate in spi.load(Codec) do print(candidate.encode("x")) end]]
    )
    sources["src/example/second.nupp"] = sources["src/example/second.nupp"] .. '\nerror("broken provider")'
    fixture(sources, function(dir)
        assert(project.build(dir) == 0)
        local status, output = process.capture({"luajit", dir .. "/out/app.lua"})
        assert(status ~= 0 and output:find("broken provider", 1, true), output)
    end)
end

function M.providerErrorsKeepTheirOriginalIdentity()
    local sources = files(
        [[module main
local spi = require("nupp.spi")
local {type Codec} = require("example.api")
local failure = require("failure")
local next = spi.load(Codec)
local ok, problem = pcall(next)
assert(not ok and problem == failure.marker)
print("ok")]],
        [[{"example.api.Codec":["example.first"]}]]
    )
    sources["src/failure.nupp"] = [[module failure
export const marker = {}]]
    sources["src/example/first.nupp"] = sources["src/example/first.nupp"] .. '\nerror(require("failure").marker, 0)'
    fixture(sources, function(dir)
        local _, output = run(dir)
        assert(output == "ok\n", output)
    end)
end

function M.caughtProviderFailuresDoNotAdvanceToFallback()
    local marker = {}
    local attempts, fallbackLoads = 0, 0
    local load = require("providerstate").instance(
        {["nupp.spi"] = true},
        {["nupp.spi.index"] = {["example.Api"] = {"fixture.broken", "fixture.fallback"}},},
        {
            ["fixture.broken"] = function()
                attempts = attempts + 1
                error(marker, 0)
            end,
            ["fixture.fallback"] = function()
                fallbackLoads = fallbackLoads + 1
                return {}
            end,
        }
    )
    local next = load("nupp.spi").load("example.Api")
    for _ = 1, 2 do
        local ok, problem = pcall(next)
        assert(not ok and problem == marker, "a provider failure changed identity")
    end
    assert(attempts == 2 and fallbackLoads == 0, "a caught failure advanced to the next provider")
end

function M.providerIndexInitializationErrorsCannotMasqueradeAsAbsence()
    local marker = setmetatable({}, {
        __tostring = function()
            return "module 'nupp.spi.index' not found: initialization failed"
        end
    })
    local load = require("providerstate").instance({["nupp.spi"] = true}, nil, {
        ["nupp.spi.index"] = function()
            error(marker, 0)
        end
    })
    local ok, problem = pcall(load, "nupp.spi")
    assert(not ok, "an index loader failure was treated as an absent index")
    assert(tostring(problem):find("cannot read provider index", 1, true), tostring(problem))
end

function M.optionalFallbackInitializationErrorsCannotMasqueradeAsAbsence()
    local cases = {
        {
            module = "nupp.runtime.timeprovider",
            interface = "nupp.time.spi.Provider",
            fallback = "nupp.runtime.provider.nativetime",
        },
        {
            module = "nupp.runtime.workersprovider",
            interface = "nupp.workers.spi.Provider",
            fallback = "nupp.runtime.provider.workers",
            workers = true,
        },
    }
    for _, case in ipairs(cases) do
        local marker = setmetatable({}, {
            __tostring = function()
                return "module '" .. case.fallback .. "' not found: initialization failed"
            end
        })
        local preloads = {
            [case.fallback] = function()
                error(marker, 0)
            end
        }
        if case.workers then
            preloads["nupp.workers.native"] = function()
                return {}
            end
        end
        local load = require(
            "providerstate"
        ).instance(
            {["nupp.spi"] = true, [case.module] = true},
            {
                ["nupp.runtime.target"] = {dialect = "luajit", host = "native"},
                ["nupp.spi.index"] = {[case.interface] = {}},
            },
            preloads
        )
        local ok, problem = pcall(load, case.module)
        assert(not ok, case.module .. " treated an initializing fallback as absent")
        assert(problem == marker, case.module .. " replaced the fallback's failure identity")
    end
end

function M.typeReexportsResolveToTheDefiningInterface()
    local sources = files(
        [[module main
local spi = require("nupp.spi")
local load = spi.load
local {type PublicCodec} = require("example.alias")
assert(assert(load(PublicCodec)()).encode("x") == "first:x")
print("ok")]],
        [[{
            "example.alias.PublicCodec":["example.first"],
            "example.api.Codec":["example.first"]
        }]]
    )
    sources[
        "src/example/alias.nupp"
    ] = [[module example.alias
local {type Codec} = require("example.api")
export type PublicCodec = Codec]]
    fixture(sources, function(dir)
        local produced, output = run(dir)
        assert(output == "ok\n", output)
        assert(#produced.spi == 1, "canonical aliases must deduplicate one implementation")
        assert(produced.spi[1].interface == "example.api.Codec")
    end)
end

function M.returnedModuleTablesExportTheirInterfaces()
    local sources = files(
        [[module main
local spi = require("nupp.spi")
local api = require("example.api")
assert(assert(spi.load(api.Codec)()).encode("x") == "first:x")
print("ok")]]
    )
    sources[
        "src/example/api.nupp"
    ] = [[module example.api
local api = {}
interface api.Codec
    @readonly encode: function(value: string): string
end
export = api]]
    fixture(sources, function(dir)
        local _, output = run(dir)
        assert(output == "ok\n", output)
    end)
end

function M.invalidProvidersFailBuildWithoutExecutingThem()
    local sources = files(
        [[module main
local spi = require("nupp.spi")
local {type Codec} = require("example.api")
for candidate in spi.load(Codec) do print(candidate.encode("x")) end]]
    )
    sources[
        "src/example/second.nupp"
    ] = [[module example.second
export const encode = 42
error("provider bodies must not run during discovery")]]
    fixture(sources, function(dir)
        assert(project.build(dir) ~= 0, "a number cannot implement an encode function")
    end)
end

function M.descriptorChangesUpdateTheWarmBuild()
    fixture(
        files(
            [[module main
local spi = require("nupp.spi")
local {type Codec} = require("example.api")
for candidate in spi.load(Codec) do print(candidate.encode("x")) end]]
        ),
        function(dir)
            local _, first = run(dir)
            assert(first == "first:x\nsecond:x\n", first)
            assert(fs.writeFile(dir .. "/nupp/spi.json", [[{"example.api.Codec":["example.second"]}]]))
            local produced, second = run(dir)
            assert(second == "second:x\n", second)
            assert(#produced.spi == 1)
        end
    )
end

function M.selectionUsesOrdinaryModuleInitialization()
    local sources = files(
        [[module main
local spi = require("nupp.spi")
local {type Codec} = require("example.api")
local selected: Codec = spi.select(spi.load(Codec)) ?? require("example.first")
export const encode = selected.encode
assert(encode("x") == "second:x")
print("ok")]]
    )
    sources[
        "src/example/api.nupp"
    ] = [[module example.api
export interface Codec
    @readonly priority: integer?
    @readonly encode: function(value: string): string
end]]
    sources["src/example/second.nupp"] = sources["src/example/second.nupp"] .. "\nexport const priority: integer = 5"
    fixture(sources, function(dir)
        local _, output = run(dir)
        assert(output == "ok\n", output)
    end)
end

-- `select` over a plain iterator: the rule without discovery.
local function candidates(priorities)
    local position = 0
    return function()
        position = position + 1
        if position > #priorities then
            return nil
        end
        local priority = priorities[position]

        return {priority = priority or nil, position = position}
    end
end

function M.selectTakesTheUniqueHighestPriorityAndRefusesATieForIt()
    local spi = require("nupp.spi")
    assert(spi.select(candidates({})) == nil, "nothing advertised selects nothing")
    assert(spi.select(candidates({false})).position == 1, "a lone provider without a priority is chosen")
    assert(spi.select(candidates({5, 5, 10})).position == 3, "a higher priority supersedes a tie below it")
    assert(spi.select(candidates({10, 5, 5})).position == 1, "a tie below the highest does not matter")
    assert(spi.select(candidates({-1, false})).position == 2, "no priority counts as 0")
    for _, priorities in ipairs({{5, 5}, {5, 10, 10}, {false, 0}}) do
        local ok, problem = pcall(spi.select, candidates(priorities))
        assert(not ok, "a tie for the highest priority was settled")
        assert(tostring(problem):find("^nupp: multiple implementations have the highest priority"), tostring(problem))
    end
end

function M.selectNamesTheInterfaceAndTheModulesThatTied()
    local saved = {}
    for _, name in ipairs({"nupp.spi", "nupp.spi.index", "spitest.low", "spitest.left", "spitest.right"}) do
        saved[name] = package.loaded[name]
    end
    package.loaded["nupp.spi"] = nil
    package.loaded["nupp.spi.index"] = {["example.api.Codec"] = {"spitest.low", "spitest.left", "spitest.right"}}
    package.loaded["spitest.low"] = {priority = 1}
    package.loaded["spitest.left"] = {priority = 7}
    package.loaded["spitest.right"] = {priority = 7}
    local spi = require("nupp.spi")
    local ok, problem = pcall(spi.select, spi.load("example.api.Codec"))
    for _, name in ipairs({"nupp.spi", "nupp.spi.index", "spitest.low", "spitest.left", "spitest.right"}) do
        package.loaded[name] = saved[name]
    end
    assert(not ok, "the tie was settled")
    assert(
        tostring(problem):find("for example.api.Codec: spitest.left and spitest.right, at 7", 1, true),
        tostring(problem)
    )
end

function M.onlyExportedConcreteInterfacesCanBeLoaded()
    for _, declaration in ipairs({
        "local interface Codec @readonly encode: function(string): string end",
        "export record Codec @readonly encode: function(string): string end",
        "export interface Codec<T> @readonly encode: function(T): T end",
    }) do
        fixture(
            files(
                "module main\nlocal spi = require('nupp.spi')\n" .. declaration .. "\nlocal iterator = spi.load(Codec)",
                "{}"
            ),
            function(dir)
                assert(project.build(dir) ~= 0, declaration)
            end
        )
    end
end

function M.initializationFailureDoesNotPublishPartialFacadeExports()
    local sources = files(
        [[module main
local ok, problem = pcall(require, "consumer")
assert(not ok and tostring(problem):find("provider initialization failed", 1, true))
assert(type(package.loaded["consumer"]) ~= "table")
print("ok")]],
        [[{"example.api.Codec":["example.first"]}]]
    )
    sources[
        "src/consumer.nupp"
    ] = [[module consumer
local spi = require("nupp.spi")
local {type Codec} = require("example.api")
export const before = "partial"
local provider = assert(spi.load(Codec)())
export const encode = provider.encode]]
    sources[
        "src/example/first.nupp"
    ] = sources[
        "src/example/first.nupp"
    ]
        .. "\n"
        .. [[
assert(type(package.loaded["consumer"]) ~= "table", "partial facade was published")
error("provider initialization failed")]]
    fixture(sources, function(dir)
        local _, output = run(dir)
        assert(output == "ok\n", output)
    end)
end

local TARGET_PROFILES = {{host = "native"}, {host = "browser", marker = "__nuppBrowser"},}

function M.hostAndVmFallbacksRetainSpiOverrides()
    local instances = require("providerstate")
    local cases = {
        {
            module = "nupp.time",
            interface = "nupp.time.spi.Provider",
            native = "nupp.runtime.provider.nativetime",
            browser = "nupp.runtime.browser.time",
            member = "now",
            cache = "nupp.runtime.timeprovider"
        },
        {
            module = "nupp.workers",
            interface = "nupp.workers.spi.Provider",
            native = "nupp.runtime.provider.workers",
            browser = "nupp.runtime.browser.workers",
            member = "runScheduler",
            exported = "__runScheduler",
            cache = "nupp.runtime.workersprovider"
        },
        {
            module = "nupp.system",
            interface = "nupp.system.spi.Provider",
            native = "nupp.runtime.provider.nativesystem",
            browser = "nupp.runtime.browser.system",
            member = "availableParallelism"
        },
        {
            module = "nupp.io.path.provider",
            interface = "nupp.io.path.spi.Provider",
            native = "nupp.runtime.provider.nativepath",
            browser = "nupp.runtime.browser.path"
        },
        {
            module = "nupp.io.uri.provider",
            interface = "nupp.io.uri.spi.Provider",
            native = "nupp.runtime.provider.nativeuri",
            browser = "nupp.runtime.browser.uri"
        },
        {
            module = "nupp.io.files",
            interface = "nupp.io.files.spi.Provider",
            native = "nupp.runtime.provider.nativefiles",
            browser = "nupp.runtime.browser.files",
            member = "capabilities"
        },
        {
            module = "nupp.runtime.uuidprovider",
            interface = "nupp.util.spi.UuidProvider",
            native = "nupp.runtime.provider.nativeuuid",
            browser = "nupp.runtime.browser.crypto"
        },
        {
            module = "nupp.random",
            interface = "nupp.random.spi.Provider",
            native = "nupp.runtime.provider.nativecrypto",
            browser = "nupp.runtime.browser.crypto",
            member = "randomBytes"
        },
        {
            module = "nupp.suspension",
            interface = "nupp.suspension.spi.Provider",
            native = "nupp.runtime.provider.suspension",
            browser = "nupp.runtime.browser.suspension",
            member = "source",
            cache = "nupp.suspension.selected",
            siblings = {"nupp.suspension.host"}
        },
        {
            module = "nupp.text",
            interface = "nupp.text.spi.Provider",
            native = "nupp.runtime.provider.nativebuffer",
            browser = "nupp.runtime.provider.tablebuffer",
            member = "new",
            exported = "newBuffer",
            vm = true
        },
        {
            module = "nupp.mem.representation",
            interface = "nupp.mem.representation.spi.CstorageProvider",
            native = "nupp.runtime.provider.nativestorage",
            -- No other storage ships: a LuaJIT VM takes native storage on either host.
            browser = "fixture.otherstorage",
            storage = true,
            vm = true
        },
    }
    for _, profile in ipairs(TARGET_PROFILES) do
        for _, case in ipairs(cases) do
            for _, override in ipairs({false, true}) do
                local loaded, preloads, providers = {}, {}, {}

                local function provide(name, priority)
                    local provider = {priority = priority}
                    if case.member then
                        provider[case.member] = function()
                            return name
                        end
                    end
                    if case.module == "nupp.workers" then
                        provider.openScope = function()
                            return name
                        end
                        provider.settle = function()
                            return name
                        end
                        provider.runScheduler = function()
                            return name
                        end
                        provider.defineSendable = function()
                            return name
                        end
                        provider.describeSendable = function()
                            return name
                        end
                    elseif case.module == "nupp.suspension" then
                        provider.install = function()
                            return name
                        end
                        provider.poll = function()
                            return name
                        end
                        provider.installDriver = function()
                            return name
                        end
                        provider.delegatedCanPark = function()
                            return name
                        end
                        provider.delegatedPark = function()
                            return name
                        end
                        provider.derive = function()
                            return name
                        end
                    elseif case.module == "nupp.system" then
                        provider.platform, provider.architecture = "fixture", "fixture"
                        provider.pointerBits, provider.endianness = 32, "little"
                    elseif case.storage then
                        provider.representation = "native"
                        provider.layout, provider.reference = {}, function()
                        end
                        provider.structs, provider.host = {referenceValued = true}, {}
                    end
                    providers[name] = provider
                    preloads[name] = function()
                        loaded[name] = (loaded[name] or 0) + 1
                        return provider
                    end
                end

                provide(case.native)
                provide(case.browser)
                provide("fixture.lower", 1)
                provide("fixture.chosen", 2)
                -- Native workers require an installed host bridge before choosing
                -- their fallback, but discovery must still win when it is present.
                preloads["nupp.workers.native"] = function()
                    error("the fixture must not execute a host bridge")
                end
                local owned = {["nupp.spi"] = true, [case.module] = true}
                if case.cache then
                    owned[case.cache] = true
                end
                -- A facade whose siblings read the same selection has to own them too,
                -- or the sibling answers from whatever this process loaded first.
                for _, sibling in ipairs(case.siblings or {}) do
                    owned[sibling] = true
                end
                local globals = {}
                if profile.marker then
                    globals[profile.marker] = {}
                end
                local load = instances.instance(
                    owned,
                    {
                        ["nupp.runtime.target"] = profile,
                        [
                            "nupp.spi.index"
                        ] = {[case.interface] = override and {"fixture.lower", "fixture.chosen"} or {}},
                    },
                    preloads,
                    globals
                )
                local usesNative = case.vm or profile.host == "native"
                local selectedName = override and "fixture.chosen" or usesNative and case.native or case.browser
                local expected = providers[selectedName]
                local facade = load(case.module)
                local label = profile.host .. ": " .. case.module
                if case.storage then
                    assert(facade.storage == expected, label)
                elseif case.member then
                    local call = facade[case.exported or case.member]
                    assert(call == expected[case.member], label)
                    assert(call() == selectedName and call() == selectedName, label)
                    if case.module == "nupp.suspension" then
                        local host = load("nupp.suspension.host")
                        local turnAvailable = host.turnAvailable
                        local consumeTurn = host.consumeTurn
                        local deferTurn = host.deferTurn
                        assert(type(turnAvailable) == "function", label .. ": missing turn availability")
                        assert(type(consumeTurn) == "function", label .. ": missing turn consumption")
                        assert(type(deferTurn) == "function", label .. ": missing turn deferral")
                        assert(turnAvailable(), label .. ": an SPI override without budgeting must be unbounded")
                        consumeTurn()
                        assert(turnAvailable(), label .. ": an unbounded turn must stay available")
                        for _, member in ipairs({
                            "install",
                            "installDriver",
                            "delegatedCanPark",
                            "delegatedPark",
                            "derive"
                        }) do
                            assert(
                                host[member] == expected[member],
                                label .. ": " .. member .. " came from another provider"
                            )
                        end
                        assert(facade.install == nil, label .. ": the host surface is next door")
                        assert(facade.poll == expected.poll, label .. ": poll stays beside source")
                    elseif case.module == "nupp.workers" then
                        local hooks = {
                            __scope = "openScope",
                            __settle = "settle",
                            __runScheduler = "runScheduler",
                            __defineSendable = "defineSendable",
                            __sendable = "describeSendable",
                        }
                        for exported, provided in pairs(hooks) do
                            assert(
                                rawget(facade, exported) == expected[provided],
                                label .. ": " .. exported .. " came from another provider"
                            )
                        end
                    end
                else
                    assert(facade == expected, label)
                end
                assert(load(case.module) == facade, label .. ": facade identity changed")
                assert(loaded[selectedName] == 1, label .. ": provider initialized more than once")
                assert(loaded[case.native] == (not override and usesNative and 1 or nil), label .. ": native fallback")
                assert(
                    loaded[case.browser] == (not override and not usesNative and 1 or nil),
                    label .. ": browser fallback"
                )
                if case.cache then
                    assert(
                        load(case.cache).provider == expected,
                        label .. ": optional consumers chose another provider"
                    )
                end
            end
        end
    end
end

function M.memoizedApplicationPathsAreRecreated()
    local root = {}
    local resolved, created = 0, 0
    local provider = {
        applicationPath = function()
            resolved = resolved + 1
            return root
        end,
        createDirectory = function(path)
            assert(path == root)
            created = created + 1
            return true
        end,
    }
    local files = require("providerstate").load("files", provider)
    files.setApplicationIdentity("example", "application-path-test")

    assert(files.dataPath() == root)
    assert(files.dataPath() == root)
    assert(resolved == 1, "the platform root is resolved once")
    assert(created == 1, "a cached root is recreated if the caller removed it")
end

function M.suspensionProvidersPublishCompleteTurnBudgetsOrNone()
    local load = require("providerstate").instance(
        {['nupp.spi'] = true, ['nupp.suspension'] = true, ['nupp.suspension.selected'] = true},
        {
            ['nupp.runtime.target'] = {dialect = "luajit", host = "native"},
            ['nupp.spi.index'] = {['nupp.suspension.spi.Provider'] = {'fixture.suspension'},},
        },
        {
            ['fixture.suspension'] = function()
                return {
                    priority = 1,
                    installDriver = function()
                    end,
                    delegatedCanPark = function()
                    end,
                    delegatedPark = function()
                    end,
                    derive = function()
                    end,
                    turnAvailable = function()
                        return true
                    end,
                }
            end,
        }
    )
    local ok, problem = pcall(load, "nupp.suspension")
    assert(not ok, "a partial turn-budget extension was accepted")
    assert(tostring(problem):find("every turn-budget operation or none", 1, true), tostring(problem))
end

function M.suspensionProvidersPublishTheirDriverSeam()
    local load = require("providerstate").instance(
        {['nupp.spi'] = true, ['nupp.suspension'] = true, ['nupp.suspension.selected'] = true},
        {
            ['nupp.runtime.target'] = {dialect = "luajit", host = "native"},
            ['nupp.spi.index'] = {['nupp.suspension.spi.Provider'] = {'fixture.suspension'},},
        },
        {
            ['fixture.suspension'] = function()
                return {
                    priority = 1,
                    installDriver = function()
                    end,
                    delegatedCanPark = function()
                        return function()
                            return true
                        end
                    end,
                }
            end,
        }
    )
    local ok, problem = pcall(load, "nupp.suspension")
    assert(not ok, "an implementation without delegatedPark or derive was accepted")
    assert(
        tostring(problem):find("installDriver, delegatedCanPark, delegatedPark and derive", 1, true),
        tostring(problem)
    )
end

function M.moduleStagingDistinguishesTheHostFromTheVm()
    local surface = require("nupp.compiler.standardsurface")
    local expectations = {
        {"nupp.runtime.provider.nativebuffer", true, true},
        {"nupp.runtime.provider.nativestorage", true, true},
        {"bit", true, true},
        {"nupp.runtime.provider.nativetime", true, false},
        {"nupp.runtime.provider.workers", true, false},
        {"nupp.runtime.provider.nativeprocess", true, false},
        {"nupp.runtime.provider.nativecompression", true, false},
        {"nupp.runtime.browser.time", false, true},
        {"nupp.runtime.browser.workers", false, true},
        {"nupp.runtime.provider.nativehost", true, false},
        {"nupp.runtime.browser.host", false, true},
        -- The compiler may carry the transport helper without selecting a browser
        -- provider.
        {"nupp.runtime.browser.memory", true, true},
    }
    for _, case in ipairs(expectations) do
        for index, profile in ipairs(TARGET_PROFILES) do
            assert(surface.supports(case[1], profile.host) == case[index + 1], profile.host .. ": " .. case[1])
        end
    end
end

function M.browserMemoryIsTheActiveGuestTransport()
    local instances = require("providerstate")
    local name = "nupp.runtime.browser.memory"
    local guestMemory = {}
    local owned = {[name] = true}

    local guest = instances.instance(owned, {}, nil, {__nuppBrowser = {memory = guestMemory},})
    assert(guest(name) == guestMemory, "the active LuaJIT browser guest supplies its memory transport")

    for _, globals in ipairs({{__nuppBrowser = {}}, {}}) do
        local missing = instances.instance(owned, {}, nil, globals)
        local ok, problem = pcall(missing, name)
        assert(not ok and tostring(problem):find("memory transport is unavailable", 1, true), tostring(problem))
    end
end

-- Every facade that picks a provider applies the same rule through
-- `nupp.spi.select`: the unique highest priority wins, and a tie for it is
-- refused rather than settled by discovery order. When each facade carried its
-- own copy, loosening one copy's comparison let the later provider win a tie
-- silently and no suite noticed, so every facade is held to the rule here. The
-- table is the consumer inventory; a new facade that selects a provider
-- belongs in it.
local SELECTING_FACADES = {
    {"nupp.checksum", "nupp.checksum.spi.Provider"},
    {"nupp.codec.json.provider", "nupp.codec.json.spi.Provider"},
    {"nupp.compression", "nupp.compression.spi.Provider"},
    {"nupp.digest", "nupp.digest.spi.Provider"},
    {"nupp.gpu", "nupp.gpu.spi.Provider"},
    {"nupp.host", "nupp.host.spi.Provider"},
    {"nupp.io.files", "nupp.io.files.spi.Provider"},
    {"nupp.io.http", "nupp.io.http.spi.Provider"},
    {"nupp.io.net", "nupp.io.net.spi.Provider"},
    {"nupp.io.path.provider", "nupp.io.path.spi.Provider"},
    {"nupp.io.process", "nupp.io.process.spi.Provider"},
    {"nupp.io.tls", "nupp.io.tls.spi.Provider"},
    {"nupp.io.uri.provider", "nupp.io.uri.spi.Provider"},
    {"nupp.mac", "nupp.mac.spi.Provider"},
    {"nupp.random", "nupp.random.spi.Provider"},
    {"nupp.mem.representation", "nupp.mem.representation.spi.CstorageProvider"},
    {"nupp.runtime.timeprovider", "nupp.time.spi.Provider"},
    {"nupp.runtime.uuidprovider", "nupp.util.spi.UuidProvider"},
    {"nupp.runtime.workersprovider", "nupp.workers.spi.Provider"},
    {"nupp.suspension.selected", "nupp.suspension.spi.Provider"},
    {"nupp.system", "nupp.system.spi.Provider"},
    {"nupp.text", "nupp.text.spi.Provider"},
}

-- Loads `facade` afresh against a provider index holding `priorities`, one
-- fixture per entry, and puts every module table back afterwards so the rest
-- of the process never sees the fixtures.
local function loadWithProviders(facade, interface, priorities)
    local before = {}
    for name, value in pairs(package.loaded) do
        before[name] = value
    end
    local preloads = {}
    local names = {}
    for index, priority in ipairs(priorities) do
        local name = "spitest.fixture" .. index
        names[index] = name
        preloads[name] = package.preload[name]
        package.preload[name] = function()
            -- `false` stands for a provider that states no priority, which
            -- counts as 0.
            return setmetatable({priority = priority or nil}, {
                __index = function(_, member)
                    if member == "priority" then
                        return nil
                    end
                    return function()
                        error("fixture does not implement " .. tostring(member))
                    end
                end
            })
        end
    end
    package.loaded["nupp.spi"] = nil
    package.loaded[facade] = nil
    package.loaded["nupp.spi.index"] = {[interface] = names}
    local ok, problem = pcall(require, facade)
    for name in pairs(package.loaded) do
        if before[name] == nil then
            package.loaded[name] = nil
        end
    end
    for name, value in pairs(before) do
        package.loaded[name] = value
    end
    for name, previous in pairs(preloads) do
        package.preload[name] = previous
    end

    return ok, problem
end

function M.everySelectingFacadeRefusesATieForTheHighestPriority()
    for _, row in ipairs(SELECTING_FACADES) do
        local facade, interface = row[1], row[2]
        for _, priorities in ipairs({{5, 5}, {1, 5, 5}, {5, 1, 5}, {false, 0}}) do
            local ok, problem = loadWithProviders(facade, interface, priorities)
            assert(
                not ok and tostring(problem):find("multiple implementations have the highest priority", 1, true),
                facade .. " with priorities " .. table.concat(
                    (function()
                        local shown = {}
                        for index = 1, #priorities do
                            shown[index] = tostring(priorities[index])
                        end

                        return shown
                    end)(),
                    ","
                ) .. ": " .. (ok and "loaded" or tostring(problem))
            )
        end
    end
end

return M
