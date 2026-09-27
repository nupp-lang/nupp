local state = require("providerstate")
local builtin = require("nupp.digest.internal.builtin")
local checksumBuiltin = require("nupp.checksum.internal.builtin")
local checksumProvider = require("nupp.runtime.provider.checksum")
local M = {}

local function selected(kind, algorithms)
    return state.family(kind, {{algorithms = algorithms}})
end

function M.providerSelectionAndCleanup()
    local created, closed = 0, 0
    local load, counts = selected("digest", {
        sha256 = {
            name = "sha256",
            digestSize = 32,
            create = function()
                created = created + 1
                local inner = builtin.lookup("sha256"):create()
                return {
                    update = function(_, bytes)
                        inner:update(bytes)
                    end,
                    finish = function(_, destination)
                        inner:finish(destination)
                    end,
                    close = function()
                        closed = closed + 1;
                        inner:close()
                    end
                }
            end
        }
    })
    local digest = load("nupp.digest")
    local initialized = counts.resolutions
    assert(initialized > 0)
    assert(digest.algorithm("sha256").digestSize == 32 and created == 0)
    assert(digest.lookup("sha512") ~= nil, "unreplaced built-ins remain available")
    for _ = 1, 20 do
        assert(digest.hexDigest("sha256", "abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        assert(#digest.algorithms() == 4)
    end
    assert(created == 20 and closed == 20)
    assert(counts.resolutions == initialized, "operations must not resolve providers")
    assert(load("nupp.digest") == digest)
end

function M.digestAndMacProviderFailuresCloseAndDoNotFallBack()
    for _, kind in ipairs({"digest", "mac"}) do
        for _, failure in ipairs({"update", "finish"}) do
            local closed = 0
            local name = kind == "digest" and "sha256" or "hmac-sha256"
            local load = selected(kind, {
                [name] = {
                    name = name,
                    digestSize = 32,
                    create = function()
                        return {
                            update = function()
                                if failure == "update" then
                                    error("test " .. kind .. " update failure")
                                end
                            end,
                            finish = function()
                                if failure == "finish" then
                                    error("test " .. kind .. " finish failure")
                                end
                            end,
                            close = function()
                                closed = closed + 1
                            end,
                        }
                    end,
                },
            })
            local api = load("nupp." .. kind)
            local ok, problem
            if kind == "digest" then
                ok, problem = pcall(api.hexDigest, name, "abc")
            else
                ok, problem = pcall(api.hexDigest, name, "key", "abc")
            end
            assert(not ok and tostring(problem):find("test " .. kind .. " " .. failure .. " failure", 1, true))
            assert(closed == 1, "failed " .. kind .. " " .. failure .. " closes exactly once")
        end
    end
end

function M.checksumProviderFailureClosesAndDoesNotFallBack()
    local closed = 0
    local load = selected("checksum", {
        crc32c = {
            name = "crc32c",
            width = 32,
            create = function()
                return {
                    update = function()
                        error("test checksum provider failure")
                    end,
                    value = function()
                        error("must not read failed state")
                    end,
                    close = function()
                        closed = closed + 1
                    end,
                }
            end,
        },
    })
    local checksum = load("nupp.checksum")
    local ok, problem = pcall(checksum.value, "crc32c", "abc")
    assert(not ok and tostring(problem):find("test checksum provider failure", 1, true))
    assert(closed == 1, "failed checksum update closes exactly once")
end

function M.checksumOneShotClosesSuccessfulAndFailedReads()
    for _, failRead in ipairs({false, true}) do
        local created, closed = 0, 0
        local load = selected("checksum", {
            custom = {
                name = "custom",
                width = 8,
                create = function()
                    created = created + 1
                    return {
                        update = function()
                        end,
                        value = function()
                            if failRead then
                                error("test checksum read failure")
                            end
                            return 42
                        end,
                        close = function()
                            closed = closed + 1
                        end,
                    }
                end,
            },
        })
        local checksum = load("nupp.checksum")
        local ok, answer = pcall(checksum.value, "custom", "payload")
        assert(ok ~= failRead)
        assert(failRead and tostring(answer):find("test checksum read failure", 1, true) or answer == 42)
        assert(created == 1 and closed == 1, "one-shot checksum closes exactly once")
    end
end

function M.invalidDescriptorsFailAtRequireTime()
    for _, case in ipairs({
        {"digest", "sha256", "digestSize", 31},
        {"checksum", "crc32c", "width", 16},
        {"mac", "hmac-sha256", "digestSize", 31}
    }) do
        local load = selected(case[1], {
            [case[2]] = {
                name = case[2],
                [case[3]] = case[4],
                create = function()
                    error("must not construct")
                end
            }
        })
        local ok, problem = pcall(load, "nupp." .. case[1])
        assert(not ok and tostring(problem):find("wrong " .. case[3], 1, true), tostring(problem))
    end
end

function M.failedLoadFailsTheFacadeInitialization()
    local load = state.family("digest", {
        function()
            error("loader failure")
        end
    })
    local ok, problem = pcall(load, "nupp.digest")
    assert(not ok and tostring(problem):find("loader failure", 1, true))
end

function M.emptyDiscoveryRetainsBuiltinsAndIndependentListings()
    for _, kind in ipairs({"digest", "checksum", "mac"}) do
        local load = state.family(kind)
        local api = load("nupp." .. kind)
        assert(api.lookup("not-installed") == nil)
        assert(not pcall(api.create, "not-installed", "key"))
        local names = api.algorithms()
        assert(#names > 0)
        names[1] = "mutated"
        assert(api.algorithms()[1] ~= "mutated", "listing must not expose retained storage")
    end
end

function M.builtinChecksumProviderRetainsCanonicalDescriptors()
    local expected = checksumBuiltin.names()
    assert(table.concat(expected, ",") == "adler32,crc32-ieee,crc32c,crc64-ecma")
    expected[1] = "changed"
    assert(checksumBuiltin.names()[1] == "adler32", "name lists must be independent")

    for _, name in ipairs(checksumBuiltin.names()) do
        local descriptor = assert(checksumProvider.algorithms[name])
        assert(descriptor == checksumBuiltin.lookup(name), name .. " descriptor identity changed")
        local first = descriptor:create()
        local second = descriptor:create()
        assert(first ~= second, name .. " factory reused state")
        first:close()
        second:close()
    end
end

function M.builtinDigestProviderRetainsCanonicalDescriptors()
    local expected = builtin.names()
    assert(table.concat(expected, ",") == "md5,sha1,sha256,sha512")
    expected[1] = "changed"
    assert(builtin.names()[1] == "md5", "name lists must be independent")

    for _, name in ipairs(builtin.names()) do
        local descriptor = assert(builtin.lookup(name))
        assert(descriptor.name == name)
        local first = descriptor:create()
        local second = descriptor:create()
        assert(first ~= second, name .. " factory reused state")
        first:close()
        second:close()
    end
end

function M.checksumAndMacRetainCatalogsDuringOperations()
    for _, kind in ipairs({"checksum", "mac"}) do
        local builtinProvider = require("nupp.runtime.provider." .. kind)
        local load, counts = state.family(kind, {builtinProvider})
        local api = load("nupp." .. kind)
        local initialized = counts.resolutions
        assert(initialized > 0)
        for _ = 1, 20 do
            api.algorithms()
            if kind == "checksum" then
                assert(tonumber(api.value("crc32c", "123456789")) == 0xe3069283)
            else
                assert(#api.digest("hmac-sha256", "key", "payload") == 32)
            end
        end
        assert(counts.resolutions == initialized, kind .. " operations resolved SPI")
    end
end

local function catalog(kind, name, priority)
    local descriptor = {
        name = name,
        create = function()
            error("not used")
        end,
    }
    descriptor[kind == "checksum" and "width" or "digestSize"] = 1

    return {priority = priority, algorithms = {[name] = descriptor}}
end

function M.priorityWinsRegardlessOfDependencyOrder()
    for _, kind in ipairs({"digest", "checksum", "mac"}) do
        for _, providers in ipairs({
            {catalog(kind, "low", 1), catalog(kind, "high", 5)},
            {catalog(kind, "high", 5), catalog(kind, "low", 1)},
            {catalog(kind, "negative", -1), catalog(kind, "default", nil)},
        }) do
            local load = state.family(kind, providers)
            local api = load("nupp." .. kind)
            assert(api.lookup(providers[1].priority == -1 and "default" or "high"))
            assert(api.lookup("low") == nil and api.lookup("negative") == nil)
        end
    end
end

function M.lowerTiesCanBeSupersededButHighestTiesFail()
    for _, kind in ipairs({"digest", "checksum", "mac"}) do
        local load = state.family(kind, {catalog(kind, "a", 0), catalog(kind, "b", 0), catalog(kind, "winner", 1),})
        assert(load("nupp." .. kind).lookup("winner"))
        for _, providers in ipairs({
            {catalog(kind, "a", 1), catalog(kind, "b", 1)},
            {catalog(kind, "a", nil), catalog(kind, "b", 0)},
            {catalog(kind, "high", 2), catalog(kind, "low", 0), catalog(kind, "alsoHigh", 2)},
        }) do
            local failed = state.family(kind, providers)
            local ok, problem = pcall(failed, "nupp." .. kind)
            assert(not ok and tostring(problem):find("highest priority", 1, true), tostring(problem))
        end
    end
end

return M
