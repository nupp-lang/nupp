local system = os.info()
local random = require("nupp.runtime.standardmath").value
local uuid = os
local providerstate = require("helpers.providerstate")
local targetLayout = require("nupp.compiler.targetlayout")
local M = {}

function M.generatorNamespacePreservesTheHostRandomFunction()
    local host = {}
    for key, value in pairs(math) do
        host[key] = value
    end
    local calls = {}
    local failure = {}
    host.random = function(...)
        local count = select("#", ...)
        calls[#calls + 1] = {count = count, ...}
        if count > 0 and (...) == nil then
            error(failure)
        end

        return 0.25
    end
    local original = host.random
    local load = providerstate.instance({["nupp.runtime.standardmath"] = true}, nil, nil, {math = host})
    local namespace = load("nupp.runtime.standardmath")
    local moved = host.random
    assert(moved == original and type(moved) == "function")
    assert(namespace.value == host and host.Xoshiro128 == namespace.Xoshiro128)
    assert(moved() == 0.25 and moved(8) == 0.25 and moved(-4, 12) == 0.25)
    assert(calls[1].count == 0)
    assert(calls[2].count == 1 and calls[2][1] == 8)
    assert(calls[3].count == 2 and calls[3][1] == -4 and calls[3][2] == 12)
    local ok, reason = pcall(moved, nil)
    assert(not ok and reason == failure, "the host's validation error must survive")
end

function M.systemReportsExecutingAbiWithoutWorkers()
    assert(type(system.platform) == "string" and #system.platform > 0)
    assert(type(system.arch) == "string" and #system.arch > 0)
    -- The host's modeled target: every one is little-endian, and the i686 and
    -- wasm32 ones are the 32-bit targets.
    local key = assert(targetLayout.hostKey(), "the host is a modeled target")
    assert(system.pointerbits == ((key:match("^i686") or key:match("^wasm32")) and 32 or 64))
    assert(system.endianness == "little")
    local count = system.parallelism
    assert(type(count) == "number" and count >= 1 and count == math.floor(count))
end

function M.secureRandomBytesSizesAndValidation()
    for _, count in ipairs({0, 1, 32, 4096}) do
        assert(#os.randombytes(count) == count)
    end
    for _, count in ipairs({-1, 0.5, 1048577, math.huge, 0 / 0}) do
        assert(not pcall(os.randombytes, count))
    end
    assert(random.randombytes == nil and random.sha256 == nil and random.uuid4 == nil and random.hmacSha256 == nil)
end

function M.identifiersAreMembersOfTheOsNamespace()
    assert(uuid.uuid(4):match("^%x%x%x%x%x%x%x%x%-%x%x%x%x%-4%x%x%x%-[89ab]%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$"))
    assert(uuid.uuid(7):match("^%x%x%x%x%x%x%x%x%-%x%x%x%x%-7%x%x%x%-[89ab]%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$"))
    assert(uuid.uuid4 == nil and uuid.uuid7 == nil and uuid.v4 == nil, "the earlier spellings are gone")
end

function M.identifiersRejectMalformedProviderResults()
    local valid4 = "12345678-1234-4abc-8def-123456789abc"
    local valid7 = "12345678-1234-7abc-bdef-123456789abc"
    local values = {
        17,
        "12345678-1234-4ABC-8def-123456789abc",
        "1234567-81234-4abc-8def-123456789abc",
        "12345678-1234-4abc-7def-123456789abc",
    }
    for _, value in ipairs(values) do
        local load = providerstate.instance({["nupp.util.internal.uuid"] = true}, {
            ["nupp.runtime.uuidprovider"] = {
                uuid4 = function()
                    return value
                end,
                uuid7 = function()
                    return value
                end,
            },
        })
        local generated = load("nupp.util.internal.uuid")
        local ok4, problem4 = pcall(generated.uuid4)
        local ok7, problem7 = pcall(generated.uuid7)
        assert(not ok4 and tostring(problem4):find("invalid version 4 UUID", 1, true), tostring(problem4))
        assert(not ok7 and tostring(problem7):find("invalid version 7 UUID", 1, true), tostring(problem7))
    end

    local wrongVersion = providerstate.instance({["nupp.util.internal.uuid"] = true}, {
        ["nupp.runtime.uuidprovider"] = {
            uuid4 = function()
                return valid7
            end,
            uuid7 = function()
                return valid4
            end,
        },
    })("nupp.util.internal.uuid")
    local ok4, problem4 = pcall(wrongVersion.uuid4)
    local ok7, problem7 = pcall(wrongVersion.uuid7)
    assert(not ok4 and tostring(problem4):find("invalid version 4 UUID", 1, true), tostring(problem4))
    assert(not ok7 and tostring(problem7):find("invalid version 7 UUID", 1, true), tostring(problem7))

    local load = providerstate.instance({["nupp.util.internal.uuid"] = true}, {
        ["nupp.runtime.uuidprovider"] = {
            uuid4 = function()
                return valid4
            end,
            uuid7 = function()
                return valid7
            end,
        },
    })
    local generated = load("nupp.util.internal.uuid")
    assert(generated.uuid4() == valid4 and generated.uuid7() == valid7)
end

local TARGET_PROFILES = {{host = "native"}, {host = "browser", marker = "__nuppBrowser"},}

function M.hostAndVmBindingsSelectTheTargetImplementationOnce()
    local instances = require("helpers.providerstate")
    local cases = {
        {
            module = "nupp.time",
            binding = "nupp.runtime.bindings.clock",
            optional = true,
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
            native = "nupp.runtime.provider.workers",
            browser = "nupp.runtime.browser.workers",
            member = "runscheduler",
            exported = "__runScheduler",
            cache = "nupp.runtime.workersprovider"
        },
        {
            module = "nupp.runtime.system",
            binding = "nupp.runtime.bindings.system",
            native = "nupp.vm.systembinding",
            browser = "nupp.runtime.browser.system",
            member = "availableparallelism",
            exported = "availableParallelism"
        },
        {
            module = "nupp.io.path.provider",
            binding = "nupp.io.path.provider",
            native = "nupp.runtime.provider.nativepath",
            browser = "nupp.runtime.browser.path"
        },
        {
            module = "nupp.io.uri.provider",
            binding = "nupp.io.uri.provider",
            native = "nupp.runtime.provider.nativeuri",
            browser = "nupp.runtime.browser.uri"
        },
        {
            module = "io.internal.files",
            binding = "nupp.runtime.bindings.files",
            native = "nupp.runtime.provider.nativefiles",
            browser = "nupp.runtime.browser.files",
            member = "exists",
            -- The facade answers the provider through its own error shape rather
            -- than re-exporting it.
            wrapped = true
        },
        {
            module = "nupp.runtime.uuidprovider",
            binding = "nupp.runtime.uuidprovider",
            native = "nupp.runtime.provider.nativeuuid",
            browser = "nupp.runtime.browser.crypto"
        },
        {
            module = "nupp.runtime.entropy",
            binding = "nupp.runtime.bindings.entropy",
            native = "nupp.vm.cryptobinding",
            browser = "nupp.runtime.browser.crypto",
            member = "randombytes",
            exported = "randombytes"
        },
        {
            module = "nupp.suspension",
            binding = "nupp.runtime.bindings.suspension",
            native = "nupp.runtime.provider.suspension",
            browser = "nupp.runtime.browser.suspension",
            member = "source",
            cache = "nupp.suspension.selected",
            siblings = {"nupp.suspension.host"}
        },
        {
            module = "bytes._representation",
            native = "nupp.vm.storagebinding",
            -- No other storage ships: a LuaJIT VM takes native storage on either host.
            browser = "fixture.otherstorage",
            storage = true,
            vm = true
        },
    }
    for _, profile in ipairs(TARGET_PROFILES) do
        for _, case in ipairs(cases) do
            local loaded, preloads, providers = {}, {}, {}

            local function provide(name)
                local provider = {}
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
            -- Native worker binding requires an installed host bridge. Its
            -- presence must not execute it while loading the facade.
            preloads["nupp.workers.native"] = function()
                error("the fixture must not execute a host bridge")
            end
            local owned = {[case.module] = true}
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
            load = instances.instance(owned, {["nupp.runtime.target"] = profile}, preloads, globals)
            local expected = providers[selectedName]
            local facade = load(case.module)
            local label = profile.host .. ": " .. case.module
            if case.storage then
                assert(facade.storage == expected, label)
            elseif case.member then
                local call = facade[case.exported or case.member]
                assert(case.wrapped or call == expected[case.member], label)
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
            assert(loaded[case.native] == (usesNative and 1 or nil), label .. ": native fallback")
            assert(loaded[case.browser] == (not usesNative and 1 or nil), label .. ": browser fallback")
            if case.cache then
                assert(load(case.cache).provider == expected, label .. ": optional consumers chose another provider")
            end
        end
    end
end

function M.memoizedAppPathsAreRecreated()
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
        {"nupp.io.internal.nativebuffer", true, true},
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

return M
