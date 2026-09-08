local state = require("providerstate")
local builtin = require("nupp.digest.internal.builtin")
local M = {}

local function selected(kind, algorithms)
    local load, service = state.family(kind)
    service:register("fixture", function()
        return {algorithms = algorithms}
    end)
    service:select("fixture")

    return load, service
end

function M.providerSelectionAndCleanup()
    local created, closed, resolutions = 0, 0, 0
    local load, service = selected("digest", {
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
    local lookup = service.lookup
    service.lookup = function(self, name)
        resolutions = resolutions + 1
        return lookup(self, name)
    end
    local digest = load("nupp.digest")
    local initialized = resolutions
    assert(initialized > 0)
    assert(digest.algorithm("sha256").digestSize == 32 and created == 0)
    assert(digest.lookup("sha512") ~= nil, "unreplaced built-ins remain available")
    for _ = 1, 20 do
        assert(digest.hexDigest("sha256", "abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        assert(#digest.algorithms() == 4)
    end
    assert(created == 20 and closed == 20)
    assert(resolutions == initialized, "operations must not resolve providers")
    assert(load("nupp.digest") == digest)
    assert(not pcall(service.select, service, "nupp.builtin"))
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
    local load, service = state.family("digest")
    service:register("broken", function()
        error("loader failure")
    end)
    service:select("broken")
    local ok, problem = pcall(load, "nupp.digest")
    assert(not ok and tostring(problem):find("loader failure", 1, true))
end

function M.discoveryDoesNotSelectProviders()
    for _, kind in ipairs({"digest", "checksum", "mac"}) do
        local load, service = state.family(kind)
        service:register("unused", function()
            error("discovery must not select")
        end)
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
        local load, service = state.family(kind)
        local builtinProvider = service:require("nupp.builtin")
        service:register("fixture", function()
            return builtinProvider
        end)
        service:select("fixture")
        local resolutions = 0
        local lookup = service.lookup
        service.lookup = function(self, name)
            resolutions = resolutions + 1
            return lookup(self, name)
        end
        local api = load("nupp." .. kind)
        local initialized = resolutions
        assert(initialized > 0)
        for _ = 1, 20 do
            api.algorithms()
            if kind == "checksum" then
                assert(tonumber(api.value("crc32c", "123456789")) == 0xe3069283)
            else
                assert(#api.digest("hmac-sha256", "key", "payload") == 32)
            end
        end
        assert(resolutions == initialized, kind .. " operations resolved SPI")
    end
end

return M
