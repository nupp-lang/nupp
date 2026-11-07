local state = require("helpers.providerstate")
local builtin = require("nupp.digest.internal.builtin")
local checksumBuiltin = require("nupp.checksum.internal.builtin")
local checksumProvider = require("nupp.runtime.provider.checksum")
local M = {}

local function selected(kind, algorithms)
    return state.family(kind, {{algorithms = algorithms}})
end

function M.bytesRootDoesNotInitializeStorageOrAlgorithmFamilies()
    local preloads = {}
    for _, name in ipairs({
        "nupp.runtime.provider.checksum",
        "nupp.runtime.provider.digest",
        "nupp.runtime.provider.mac",
        "nupp.runtime.packages",
        "nupp.runtime.storage",
    }) do
        preloads[name] = function()
            error("hash root initialized " .. name)
        end
    end
    local load = state.instance(
        {
            ["bytes"] = true,
            ["nupp.util.internal.bitset"] = true,
            ["nupp.digest.checksum"] = true,
            ["nupp.digest.digest"] = true,
            ["nupp.digest.mac"] = true,
            ["nupp.digest.internal.context"] = true,
            ["nupp.digest.internal.contracts"] = true
        },
        nil,
        preloads
    )
    local hash = load("bytes")
    assert(hash.fnv1a64("hello") == "a430d84680aabd0b")
    assert(load("bytes") == hash)
end

function M.bytesContextNamesUseCanonicalKeysOnly()
    for _, kind in ipairs({"checksum", "digest", "mac"}) do
        local load = state.family(kind, {})
        local facade = load("bytes")[kind]
        local name = kind == "checksum" and "crc32" or kind == "digest" and "sha256" or "hmac-sha256"
        local algorithm = facade(name)
        local final = "create"
        local retired = kind == "checksum" and "newChecksum" or kind == "digest" and "newDigest" or "newMac"
        assert(type(algorithm[final]) == "function" and algorithm[retired] == nil)
        local context = kind == "mac" and algorithm[final](algorithm, "key") or algorithm[final](algorithm)
        assert(type(context.writespan) == "function" and context.writeSpan == nil)
        if kind ~= "checksum" then
            assert(algorithm.digestsize > 0 and algorithm.digestSize == nil)
            assert(context:digestsize() == algorithm.digestsize and context.digestSize == nil)
            assert(type(context.hexdigest) == "function" and context.hexDigest == nil)
        end
        context:close()
    end
end

function M.retiredStaticHelpersAndUnknownFamiliesAreRejected()
    local byteapi = require("bytes")
    for _, name in ipairs({"Digest", "Checksum", "Mac"}) do
        for _, helper in ipairs({"Algorithm", "create", "compute", "computehex"}) do
            assert(byteapi[name][helper] == nil, name .. "." .. helper .. " remains public")
        end
    end
    local ok, problem = pcall(byteapi.formats, "unknown")
    assert(not ok and tostring(problem):find("unknown bytes format kind unknown", 1, true))
end

function M.providerSelectionAndCleanup()
    local created, closed = 0, 0
    local load, counts = selected("digest", {
        sha256 = {
            name = "sha256",
            digestsize = 32,
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
    local digest = load("bytes").digest
    assert(counts.resolutions == 0, "catalog loads on first use")
    load("bytes").formats("digest")
    local initialized = counts.resolutions
    assert(initialized == 1)
    assert(digest("sha256").digestsize == 32 and created == 0)
    assert(digest("sha512") ~= nil, "unreplaced built-ins remain available")
    for _ = 1, 20 do
        assert(digest("sha256"):computehex("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        assert(#load("bytes").formats("digest") == 4)
    end
    assert(created == 20 and closed == 20)
    assert(counts.resolutions == initialized, "operations must not reload implementations")
    assert(load("bytes").digest == digest)
end

function M.digestAndMacProviderFailuresCloseAndDoNotFallBack()
    for _, kind in ipairs({"digest", "mac"}) do
        for _, failure in ipairs({"update", "finish"}) do
            local closed = 0
            local name = kind == "digest" and "sha256" or "hmac-sha256"
            local load = selected(kind, {
                [name] = {
                    name = name,
                    digestsize = 32,
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
            local api = load("bytes")[kind]
            local ok, problem
            if kind == "digest" then
                ok, problem = pcall(api(name).computehex, api(name), "abc")
            else
                ok, problem = pcall(api(name).computehex, api(name), "key", "abc")
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
    local checksum = load("bytes").checksum
    local ok, problem = pcall(checksum("crc32c").compute, checksum("crc32c"), "abc")
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
        local checksum = load("bytes").checksum
        local ok, answer = pcall(checksum("custom").compute, checksum("custom"), "payload")
        assert(ok ~= failRead)
        assert(failRead and tostring(answer):find("test checksum read failure", 1, true) or answer == 42)
        assert(created == 1 and closed == 1, "one-shot checksum closes exactly once")
    end
end

function M.invalidDescriptorsFailAtFirstCatalogUse()
    for _, case in ipairs({
        {"digest", "sha256", "digestsize", 31},
        {"checksum", "crc32c", "width", 16},
        {"mac", "hmac-sha256", "digestsize", 31}
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
        local ok, problem = pcall(load("bytes").formats, case[1])
        assert(not ok and tostring(problem):find("wrong " .. case[3], 1, true), tostring(problem))
    end
end

function M.failedLoadFailsTheFacadeInitialization()
    local load = state.family("digest", {
        function()
            error("loader failure")
        end
    })
    local ok, problem = pcall(load("bytes").formats, "digest")
    assert(not ok and tostring(problem):find("loader failure", 1, true))
end

function M.digestAndMacCatalogsRetryFailedLoadsBeforePublishing()
    for _, kind in ipairs({"digest", "mac"}) do
        local attempts = 0
        local load, counts = state.family(kind, {
            function()
                attempts = attempts + 1
                if attempts == 1 then
                    error("temporary catalog failure", 0)
                end

                return {algorithms = {}}
            end
        })
        local byteapi = load("bytes")
        local api = byteapi[kind]
        local ok, problem = pcall(byteapi.formats, kind)
        assert(not ok and tostring(problem):find("temporary catalog failure", 1, true), tostring(problem))
        local names = byteapi.formats(kind)
        assert(#names > 0 and counts.resolutions == 2)
        for index = 2, #names do
            assert(names[index - 1] < names[index], "catalog names are sorted and unique")
        end
        assert(#byteapi.formats(kind) == #names and counts.resolutions == 2)
        local name = kind == "digest" and "sha256" or "hmac-sha256"
        assert(api(name).digestsize == 32)
    end
end

function M.targetBindingsRetainBuiltinsAndIndependentListings()
    for _, kind in ipairs({"digest", "checksum", "mac"}) do
        local load = state.family(kind)
        local api = load("bytes")[kind]
        assert(not pcall(api, "not-installed"))
        local factory = api
        assert(not pcall(factory, "not-installed", "key"))
        local names = load("bytes").formats(kind)
        assert(#names > 0)
        names[1] = "mutated"
        assert(load("bytes").formats(kind)[1] ~= "mutated", "listing must not expose retained storage")
    end
end

function M.builtinChecksumProviderRetainsCanonicalDescriptors()
    local expected = checksumBuiltin.names()
    assert(table.concat(expected, ",") == "adler32,crc32,crc32c,crc64-ecma,crc64nvme")
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
        local api = load("bytes")[kind]
        assert(counts.resolutions == 0, "catalog loads on first use")
        load("bytes").formats(kind)
        local initialized = counts.resolutions
        assert(initialized == 1)
        for _ = 1, 20 do
            load("bytes").formats(kind)
            if kind == "checksum" then
                assert(tonumber(api("crc32c"):compute("123456789")) == 0xe3069283)
            else
                assert(#api("hmac-sha256"):compute("key", "payload") == 32)
            end
        end
        assert(counts.resolutions == initialized, kind .. " operations reloaded the implementation")
    end
end

function M.builtinBindingsDoNotConsultUserDiscovery()
    for _, kind in ipairs({"digest", "checksum", "mac"}) do
        local load, counts = state.family(kind)
        local api = load("bytes")[kind]
        assert(#load("bytes").formats(kind) > 0)
        assert(load("bytes")[kind] == api)
        assert(counts.resolutions == 1, "builtin implementation initializes once")
    end
end

return M
