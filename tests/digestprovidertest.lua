local state = require("providerstate")
local builtin = require("nupp.digest.internal.builtin")
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

function M.providerFailureClosesAndDoesNotFallBack()
    local closed = 0
    local load = selected("digest", {
        sha256 = {
            name = "sha256",
            digestSize = 32,
            create = function()
                return {
                    update = function()
                    end,
                    finish = function()
                        error("test provider failure")
                    end,
                    close = function()
                        closed = closed + 1
                    end
                }
            end
        }
    })
    local digest = load("nupp.digest")
    local ok, problem = pcall(digest.hexDigest, "sha256", "abc")
    assert(not ok and tostring(problem):find("test provider failure", 1, true))
    assert(closed == 1, "failed finalization closes exactly once")
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

local function catalog(name, priority)
    return {
        priority = priority,
        algorithms = {
            [name] = {
                name = name,
                digestSize = 1,
                create = function()
                    error("not used")
                end,
            }
        }
    }
end

function M.priorityWinsRegardlessOfDependencyOrder()
    for _, providers in ipairs({
        {catalog("low", 1), catalog("high", 5)},
        {catalog("high", 5), catalog("low", 1)},
        {catalog("negative", -1), catalog("default", nil)},
    }) do
        local load = state.family("digest", providers)
        local digest = load("nupp.digest")
        assert(digest.lookup(providers[1].priority == -1 and "default" or "high"))
        assert(digest.lookup("low") == nil and digest.lookup("negative") == nil)
    end
end

function M.lowerTiesCanBeSupersededButHighestTiesFail()
    local load = state.family("digest", {catalog("a", 0), catalog("b", 0), catalog("winner", 1)})
    assert(load("nupp.digest").lookup("winner"))
    for _, providers in ipairs({
        {catalog("a", 1), catalog("b", 1)},
        {catalog("a", nil), catalog("b", 0)},
        {catalog("high", 2), catalog("low", 0), catalog("alsoHigh", 2)},
    }) do
        local failed = state.family("digest", providers)
        local ok, problem = pcall(failed, "nupp.digest")
        assert(not ok and tostring(problem):find("highest priority", 1, true), tostring(problem))
    end
end

return M
