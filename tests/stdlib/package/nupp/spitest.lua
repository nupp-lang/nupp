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
    assert(os.remove(dir, true))
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
local spi = package
local {type Codec} = require("example.api")
local next = spi.providers(Codec)
local first = assert(next())
local second = assert(next())
assert(next() == nil and next() == nil)
assert(first.encode("x") == "first:x")
assert(second.encode("x") == "second:x")
assert(spi.providers(Codec)() == first)
assert(package.providers(Codec)() == first)
assert(package.providers == spi.providers and package.select == spi.select)
local contracts: any = require("example.api")
assert(contracts.providers == nil and contracts.select == nil and contracts.load == nil)
local api = require("example.api")
assert(spi.providers(api.Codec)() == first)
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
local {providers} = package
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
local spi = package
local {type Codec} = require("example.api")
local provider: Codec = spi.providers(Codec)() ?? require("example.first")
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
        local generated = assert(fs.readFile(dir .. "/out/generated/package/nupp/index.nupp"))
        local expected = [[module package.nupp.index
local _DYNAMIC_REQUIRES = "@requires-dynamically z.second @requires-dynamically a.first @requires-dynamically z.first"
export = {
    ["a.Api"] = {"a.first"},
    ["z.Api"] = {"z.second", "z.first"},
}
]]
        assert(generated == expected, generated)
        local parsed = require("nupp.compiler.syntax.parser").parse(generated, "generated.nupp")
        require("nupp.compiler.compat").syntax(parsed, function(_, reason)
            error("the generated index must remain portable: " .. reason)
        end)
        assert(discovery.write(dir, "out", entries), "rewriting the same index failed")

        assert(fs.writeFile(dir .. "/blocked", "not a directory"))
        local wrote, problem = discovery.write(dir, "blocked/child", entries)
        assert(not wrote and problem ~= nil, "an index write failure was reported as success")
    end)
end

function M.providerErrorsAreNotTreatedAsAbsence()
    local sources = files(
        [[module main
local spi = package
local {type Codec} = require("example.api")
for candidate in spi.providers(Codec) do print(candidate.encode("x")) end]]
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
local spi = package
local {type Codec} = require("example.api")
local failure = require("failure")
local next = spi.providers(Codec)
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
    local load = require("helpers.providerstate").instance(
        {["nupp.runtime.packages"] = true},
        {["package.nupp.index"] = {["example.Api"] = {"fixture.broken", "fixture.fallback"}},},
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
    local next = load("nupp.runtime.packages").providers("example.Api")
    for _ = 1, 2 do
        local ok, problem = pcall(next)
        assert(not ok and problem == marker, "a provider failure changed identity")
    end
    assert(attempts == 2 and fallbackLoads == 0, "a caught failure advanced to the next provider")
end

function M.providerIndexInitializationErrorsCannotMasqueradeAsAbsence()
    local marker = setmetatable({}, {
        __tostring = function()
            return "module 'package.nupp.index' not found: initialization failed"
        end
    })
    local load = require("helpers.providerstate").instance({["nupp.runtime.packages"] = true}, nil, {
        ["package.nupp.index"] = function()
            error(marker, 0)
        end
    })
    local ok, problem = pcall(load, "nupp.runtime.packages")
    assert(not ok, "an index loader failure was treated as an absent index")
    assert(tostring(problem):find("cannot read provider index", 1, true), tostring(problem))
end

function M.optionalFallbackInitializationErrorsCannotMasqueradeAsAbsence()
    local cases = {
        {
            module = "nupp.runtime.timeprovider",
            binding = "nupp.runtime.bindings.clock",
            interface = "package.nupp.ClockProvider",
            fallback = "nupp.runtime.provider.nativetime",
        },
        {
            module = "nupp.runtime.workersprovider",
            binding = "nupp.runtime.bindings.workers",
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
            "helpers.providerstate"
        ).instance(
            {[case.module] = true, [case.binding] = true, ["nupp.runtime.optional"] = true},
            {
                ["nupp.runtime.target"] = {dialect = "luajit", host = "native"},
                ["package.nupp.index"] = {[case.interface] = {}},
            },
            preloads
        )
        local ok, problem = pcall(load, case.module)
        assert(not ok, case.module .. " treated an initializing fallback as absent")
        assert(problem == marker, case.module .. " replaced the fallback's failure identity")
    end
end

function M.optionalImplementationAbsenceDoesNotHideInitializationFailures()
    local marker = {}
    local load = require("helpers.providerstate").instance({["nupp.runtime.optional"] = true}, nil, {
        ["fixture.broken.optional"] = function()
            error(marker, 0)
        end,
    })
    local optional = load("nupp.runtime.optional")
    assert(optional.load("fixture.missing.optional") == nil)
    local ok, problem = pcall(optional.load, "fixture.broken.optional")
    assert(not ok and problem == marker, "initialization failures retain their original identity")
end

function M.optionalFilesystemInitializationErrorsCannotMasqueradeAsAbsence()
    local name = "spitest_optional_filesystem_failure"
    local marker = "module '" .. name .. "' not found: initialization failed"
    fixture({[name .. ".lua"] = ("error(%q, 0)"):format(marker)}, function(dir)
        local previousPath, previousModule = package.path, package.loaded[name]
        package.path = dir .. "/?.lua;" .. previousPath
        package.loaded[name] = nil
        local load = require("helpers.providerstate").instance({["nupp.runtime.optional"] = true})
        local ok, problem = pcall(function()
            return load("nupp.runtime.optional").load(name)
        end)
        package.path, package.loaded[name] = previousPath, previousModule
        assert(not ok, "an initializing filesystem module was treated as absent")
        assert(problem == marker, "the filesystem initialization failure was replaced")
    end)
end

function M.typeReexportsResolveToTheDefiningInterface()
    local sources = files(
        [[module main
local spi = package
local load = spi.providers
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
local spi = package
local api = require("example.api")
assert(assert(spi.providers(api.Codec)()).encode("x") == "first:x")
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
local spi = package
local {type Codec} = require("example.api")
for candidate in spi.providers(Codec) do print(candidate.encode("x")) end]]
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
local spi = package
local {type Codec} = require("example.api")
for candidate in spi.providers(Codec) do print(candidate.encode("x")) end]]
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
local spi = package
local {type Codec} = require("example.api")
local selected: Codec = spi.select(spi.providers(Codec)) ?? require("example.first")
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
    local spi = require("nupp.runtime.packages")
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
    for _, name in ipairs({
        "nupp.runtime.packages",
        "package.nupp.index",
        "spitest.low",
        "spitest.left",
        "spitest.right"
    }) do
        saved[name] = package.loaded[name]
    end
    package.loaded["nupp.runtime.packages"] = nil
    package.loaded["package.nupp.index"] = {["example.api.Codec"] = {"spitest.low", "spitest.left", "spitest.right"}}
    package.loaded["spitest.low"] = {priority = 1}
    package.loaded["spitest.left"] = {priority = 7}
    package.loaded["spitest.right"] = {priority = 7}
    local spi = require("nupp.runtime.packages")
    local ok, problem = pcall(spi.select, spi.providers("example.api.Codec"))
    for _, name in ipairs({
        "nupp.runtime.packages",
        "package.nupp.index",
        "spitest.low",
        "spitest.left",
        "spitest.right"
    }) do
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
                "module main\nlocal spi = package\n" .. declaration .. "\nlocal iterator = spi.providers(Codec)",
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
local spi = package
local {type Codec} = require("example.api")
export const before = "partial"
local provider = assert(spi.providers(Codec)())
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

function M.hostAndVmBindingsIgnoreAdvertisedOverrides()
    local instances = require("helpers.providerstate")
    local cases = {
        {
            module = "nupp.time",
            binding = "nupp.runtime.bindings.clock",
            optional = true,
            interface = "package.nupp.ClockProvider",
            native = "nupp.runtime.provider.nativetime",
            browser = "nupp.runtime.browser.time",
            member = "sleep",
            cache = "nupp.runtime.timeprovider",
            siblings = {"nupp.runtime.clocks"}
        },
        {
            module = "nupp.workers",
            binding = "nupp.runtime.bindings.workers",
            optional = true,
            interface = "nupp.workers.spi.Provider",
            native = "nupp.runtime.provider.workers",
            browser = "nupp.runtime.browser.workers",
            member = "runscheduler",
            exported = "__runScheduler",
            cache = "nupp.runtime.workersprovider"
        },
        {
            module = "nupp.runtime.system",
            binding = "nupp.runtime.bindings.system",
            interface = "package.nupp.SystemProvider",
            native = "nupp.runtime.provider.nativesystem",
            browser = "nupp.runtime.browser.system",
            member = "availableparallelism",
            exported = "availableParallelism"
        },
        {
            module = "nupp.io.path.provider",
            binding = "nupp.io.path.provider",
            interface = "io.spi.PathProvider",
            native = "nupp.runtime.provider.nativepath",
            browser = "nupp.runtime.browser.path"
        },
        {
            module = "nupp.io.uri.provider",
            binding = "nupp.io.uri.provider",
            interface = "io.spi.UriProvider",
            native = "nupp.runtime.provider.nativeuri",
            browser = "nupp.runtime.browser.uri"
        },
        {
            module = "nupp.runtime.bindings.files",
            binding = "nupp.runtime.bindings.files",
            interface = "io.internal.files.contracts.Provider",
            native = "nupp.runtime.provider.nativefiles",
            browser = "nupp.runtime.browser.files",
            member = "capabilities"
        },
        {
            module = "nupp.runtime.uuidprovider",
            binding = "nupp.runtime.uuidprovider",
            interface = "package.nupp.UuidProvider",
            native = "nupp.runtime.provider.nativeuuid",
            browser = "nupp.runtime.browser.crypto"
        },
        {
            module = "nupp.runtime.entropy",
            binding = "nupp.runtime.bindings.entropy",
            interface = "package.nupp.EntropyProvider",
            native = "nupp.runtime.provider.nativecrypto",
            browser = "nupp.runtime.browser.crypto",
            member = "randombytes",
            exported = "randombytes"
        },
        {
            module = "nupp.suspension",
            binding = "nupp.runtime.bindings.suspension",
            interface = "nupp.suspension.spi.Provider",
            native = "nupp.runtime.provider.suspension",
            browser = "nupp.runtime.browser.suspension",
            member = "source",
            cache = "nupp.suspension.selected",
            siblings = {"nupp.suspension.host"}
        },
        {
            module = "bytes._representation",
            interface = "package.nupp.CstorageProvider",
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
                        provider.openscope = function()
                            return name
                        end
                        provider.settle = function()
                            return name
                        end
                        provider.runscheduler = function()
                            return name
                        end
                        provider.definesendable = function()
                            return name
                        end
                        provider.describesendable = function()
                            return name
                        end
                    elseif case.module == "nupp.suspension" then
                        provider.install = function()
                            return name
                        end
                        provider.poll = function()
                            return name
                        end
                        provider.installdriver = function()
                            return name
                        end
                        provider.delegatedcanpark = function()
                            return name
                        end
                        provider.delegatedpark = function()
                            return name
                        end
                        provider.derive = function()
                            return name
                        end
                    elseif case.module == "nupp.runtime.system" then
                        provider.platform, provider.architecture = "fixture", "fixture"
                        provider.pointerbits, provider.endianness = 32, "little"
                    elseif case.storage then
                        provider.representation = "native"
                        provider.layout, provider.reference = {}, function()
                        end
                        provider.structs, provider.host = {referencevalued = true}, {}
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
                -- Native worker binding requires an installed host bridge. Its
                -- presence must not execute it while loading the facade.
                preloads["nupp.workers.native"] = function()
                    error("the fixture must not execute a host bridge")
                end
                local owned = {["nupp.runtime.packages"] = true, [case.module] = true}
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
                local usesNative = case.vm or profile.host == "native"
                local selectedName = usesNative and case.native or case.browser
                local load
                if case.binding then
                    preloads[case.binding] = function()
                        local implementation = load(selectedName)
                        return case.optional and {provider = implementation} or implementation
                    end
                end
                load = instances.instance(
                    owned,
                    {
                        ["nupp.runtime.target"] = profile,
                        [
                            "package.nupp.index"
                        ] = {[case.interface] = override and {"fixture.lower", "fixture.chosen"} or {}},
                    },
                    preloads,
                    globals
                )
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
                        assert(turnAvailable(), label .. ": an implementation without budgeting must be unbounded")
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
                                host[
                                    member
                                ] == expected[
                                    ({
                                        installDriver = "installdriver",
                                        delegatedCanPark = "delegatedcanpark",
                                        delegatedPark = "delegatedpark"
                                    })[member]
                                    or member
                                ],
                                label .. ": " .. member .. " came from another provider"
                            )
                        end
                        assert(facade.install == nil, label .. ": the host surface is next door")
                        assert(facade.poll == expected.poll, label .. ": poll stays beside source")
                    elseif case.module == "nupp.workers" then
                        local hooks = {
                            __scope = "openscope",
                            __settle = "settle",
                            __runScheduler = "runscheduler",
                            __defineSendable = "definesendable",
                            __sendable = "describesendable",
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
                assert(loaded[selectedName] == 1, label .. ": implementation initialized more than once")
                assert(
                    loaded["fixture.chosen"] == nil and loaded["fixture.lower"] == nil,
                    label .. ": builtin initialized an advertised override"
                )
                assert(loaded[case.native] == (usesNative and 1 or nil), label .. ": native fallback")
                assert(loaded[case.browser] == (not usesNative and 1 or nil), label .. ": browser fallback")
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
        apppath = function()
            resolved = resolved + 1
            return root
        end,
        createDirectory = function(path)
            assert(path == root)
            created = created + 1
            return true
        end,
    }
    local files = require("helpers.providerstate").load("files", provider)
    files.setappid("example", "application-path-test")

    assert(files.appdir("data") == root)
    assert(files.appdir("data") == root)
    assert(resolved == 1, "the platform root is resolved once")
    assert(created == 1, "a cached root is recreated if the caller removed it")
end

function M.suspensionProvidersPublishCompleteTurnBudgetsOrNone()
    local load = require("helpers.providerstate").instance(
        {['nupp.suspension'] = true, ['nupp.suspension.selected'] = true},
        {['nupp.runtime.target'] = {dialect = "luajit", host = "native"},},
        {
            ['nupp.runtime.bindings.suspension'] = function()
                return {
                    priority = 1,
                    installdriver = function()
                    end,
                    delegatedcanpark = function()
                    end,
                    delegatedpark = function()
                    end,
                    derive = function()
                    end,
                    turnavailable = function()
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
    local load = require("helpers.providerstate").instance(
        {['nupp.suspension'] = true, ['nupp.suspension.selected'] = true},
        {['nupp.runtime.target'] = {dialect = "luajit", host = "native"},},
        {
            ['nupp.runtime.bindings.suspension'] = function()
                return {
                    priority = 1,
                    installdriver = function()
                    end,
                    delegatedcanpark = function()
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
        tostring(problem):find("installdriver, delegatedcanpark, delegatedpark and derive", 1, true),
        tostring(problem)
    )
end

function M.moduleStagingDistinguishesTheHostFromTheVm()
    local surface = require("nupp.compiler.standardsurface")
    local expectations = {
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
        -- The codec the browser provider requires, carried like the transport.
        {"nupp.runtime.browser.hostwire", true, true},
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
    local instances = require("helpers.providerstate")
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

-- Builtin implementations are selected by target, so their initialization must
-- not inspect the user-package discovery index. The target matrix above checks
-- identity, one-time initialization, and ignored advertised overrides; package
-- priority and tie behavior remains covered by the user-package tests.
function M.packageSelectionAliasesInstallWithoutDiscoveryCalls()
    fixture(
        files(
            [[module main
local {select as choose, config, loaded} = package
assert(config == package.config and loaded == package.loaded)
local selectAgain = choose
local position = 0
local function next(): {priority: integer, value: string}?
    position = position + 1
    if position == 1 then return {priority = -2, value = "low"} end
    if position == 2 then return {priority = -1, value = "high"} end
    return nil
end
assert(assert(selectAgain(next)).value == "high")
print("ok")]],
            "{}"
        ),
        function(dir)
            local _, output = run(dir)
            assert(output == "ok\n", output)
        end
    )
end

function M.aLocalPackageLibraryKeepsItsOwnProviderContract()
    fixture(
        files(
            [[module main
local package: {
    providers: function(name: string): function(): string?,
    select: function(next: function(): string?): string?
} = {
    providers = function(name: string): function(): string?
        return function(): string? return name end
    end,
    select = function(next: function(): string?): string? return next() end
}
local providers = package.providers
local {select as choose} = package
assert(choose(providers("custom")) == "custom")
print("ok")]],
            "{}"
        ),
        function(dir)
            local _, output = run(dir)
            assert(output == "ok\n", output)
            local code = assert(fs.readFile(dir .. "/out/main.lua"))
            assert(
                not code:find('require("nupp.runtime.packages")', 1, true),
                "a local library must not install package discovery"
            )
        end
    )
end

function M.projectModulesDoNotReplaceBuiltinPackageMembers()
    local sources = files(
        [[module main
local {type Codec} = require("example.api")
local selected = assert(package.select(package.providers(Codec)))
assert(selected.encode("x") == "first:x")
print("ok")]],
        [[{"example.api.Codec":["example.first"]}]]
    )
    for _, name in ipairs({"providers", "select"}) do
        sources[
            "src/package/" .. name .. ".nupp"
        ] = "module package."
            .. name
            .. "\n"
            .. [[export const unrelated: string = "project module"
error("the builtin member must keep precedence")
]]
    end
    fixture(sources, function(dir)
        local _, output = run(dir)
        assert(output == "ok\n", output)
    end)
end

return M
