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
            kind = "bundle", dialect = "luajit", outDir = "out",
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
            interface = "nupp.time.spi.TimeProvider",
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
local selected: Codec = do
    local chosen: Codec?
    local tied = false
    for candidate in spi.load(Codec) do
        if chosen == nil or (candidate.priority ?? 0) > (chosen.priority ?? 0) then
            chosen = candidate
            tied = false
        elseif (candidate.priority ?? 0) == (chosen.priority ?? 0) then
            tied = true
        end
    end
    assert(not tied, "highest priority is tied")
    yield chosen ?? require("example.first")
end
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

local TARGET_PROFILES = {
    {dialect = "luajit", host = "native"},
    {dialect = "luajit", host = "browser", marker = "__nuppBrowser"},
}

function M.hostAndVmFallbacksRetainSpiOverrides()
    local instances = require("providerstate")
    local cases = {
        {
            module = "nupp.time",
            interface = "nupp.time.spi.TimeProvider",
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
            member = "scope",
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
            interface = "nupp.io.path.spi.PathProvider",
            native = "nupp.runtime.provider.nativepath",
            browser = "nupp.runtime.browser.path"
        },
        {
            module = "nupp.io.uri.provider",
            interface = "nupp.io.uri.spi.UriTextProvider",
            native = "nupp.runtime.provider.nativeuri",
            browser = "nupp.runtime.browser.uri"
        },
        {
            module = "nupp.runtime.uuid",
            interface = "nupp.runtime.uuid.spi.UuidProvider",
            native = "nupp.runtime.provider.nativeuuid",
            browser = "nupp.runtime.browser.crypto"
        },
        {
            module = "nupp.random",
            interface = "nupp.random.spi.CryptoProvider",
            native = "nupp.runtime.provider.nativecrypto",
            browser = "nupp.runtime.browser.crypto",
            member = "randomBytes"
        },
        {
            module = "nupp.suspension",
            interface = "nupp.suspension.spi.Provider",
            native = "nupp.runtime.provider.suspension",
            browser = "nupp.runtime.browser.suspension",
            member = "source"
        },
        {
            module = "nupp.text",
            interface = "nupp.text.spi.TextBufferProvider",
            native = "nupp.runtime.provider.nativebuffer",
            browser = "nupp.runtime.provider.tablebuffer",
            member = "new",
            exported = "newBuffer",
            vm = true
        },
        {
            module = "nupp.runtime.bitops",
            interface = "nupp.runtime.bitops.spi.BitopsProvider",
            native = "bit",
            browser = "nupp.runtime.provider.scalarbitops",
            vm = true
        },
        {
            module = "nupp.runtime.representation",
            interface = "nupp.runtime.representation.spi.CstorageProvider",
            native = "nupp.runtime.provider.nativestorage",
            browser = "nupp.runtime.provider.wasmstorage",
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
                    if case.module == "nupp.system" then
                        provider.platform, provider.architecture = "fixture", "fixture"
                        provider.pointerBits, provider.endianness = 32, "little"
                    elseif case.storage then
                        provider.representation = "native"
                        provider.layout, provider.reference = {}, function()
                        end
                        provider.integers, provider.structs, provider.host = {}, {referenceValued = true}, {}
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
                local label = profile.host .. "/" .. profile.dialect .. ": " .. case.module
                if case.storage then
                    assert(facade.storage == expected, label)
                elseif case.member then
                    local call = facade[case.exported or case.member]
                    assert(call == expected[case.member], label)
                    assert(call() == selectedName and call() == selectedName, label)
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

function M.moduleStagingDistinguishesTheHostFromTheVm()
    local surface = require("nupp.compiler.standardsurface")
    local expectations = {
        {"nupp.runtime.provider.nativebuffer", true, true},
        {"nupp.runtime.provider.nativestorage", true, true},
        {"bit", true, true},
        {"nupp.runtime.provider.wasmstorage", false, false},
        {"nupp.runtime.provider.nativetime", true, false},
        {"nupp.runtime.provider.workers", true, false},
        {"nupp.runtime.provider.nativeprocess", true, false},
        {"nupp.runtime.provider.nativecompression", true, false},
        {"nupp.runtime.browser.time", false, true},
        {"nupp.runtime.browser.workers", false, true},
        -- The compiler may carry the transport helper without selecting a browser
        -- provider.
        {"nupp.runtime.browser.memory", true, true},
    }
    for _, case in ipairs(expectations) do
        for index, profile in ipairs(TARGET_PROFILES) do
            assert(
                surface.supports(case[1], profile.dialect, profile.host) == case[index + 1],
                profile.host .. "/" .. profile.dialect .. ": " .. case[1]
            )
        end
    end
end

return M
