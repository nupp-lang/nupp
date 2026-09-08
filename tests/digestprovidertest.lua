local digest = require("nupp.digest")
local checksum = require("nupp.checksum")
local mac = require("nupp.mac")
local registry = require("nupp.service.registry")
local builtin = require("nupp.digest.internal.builtin")
local M = {}

local function installed(service, name, loader, body)
    local previous = registry[service]
    local entries = {}
    for key, value in pairs(previous or {}) do
        entries[key] = value
    end
    entries[name] = loader
    registry[service] = entries
    local ok, problem = pcall(body)
    registry[service] = previous
    assert(ok, problem)
end

function M.providerSelectionAndCleanup()
    local created, closed = 0, 0
    installed(
        "nupp.digest",
        "sha256",
        function()
            return {
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
                        end,
                    }
                end,
            }
        end,
        function()
            assert(digest.algorithm("sha256").digestSize == 32)
            assert(created == 0, "metadata must not allocate state")
            assert(
                digest.hexDigest("sha256", "abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
            )
            assert(created == 1 and closed == 1, "selected provider closes exactly once")
        end
    )
end

function M.providerFailureClosesAndDoesNotFallBack()
    local closed = 0
    installed(
        "nupp.digest",
        "sha256",
        function()
            return {
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
                        end,
                    }
                end,
            }
        end,
        function()
            local ok, problem = pcall(digest.hexDigest, "sha256", "abc")
            assert(not ok and tostring(problem):find("test provider failure", 1, true))
            assert(closed == 1, "failed finalization closes exactly once")
        end
    )
end

function M.invalidDescriptorsAndUnknownAlgorithms()
    for _, api in ipairs({digest, checksum, mac}) do
        assert(api.lookup("not-installed") == nil)
        assert(not pcall(api.create, "not-installed", "key"))
    end
    installed(
        "nupp.digest",
        "sha256",
        function()
            return {
                name = "sha256",
                digestSize = 31,
                create = function()
                    error("must not construct")
                end
            }
        end,
        function()
            local ok, problem = pcall(digest.algorithm, "sha256")
            assert(not ok and tostring(problem):find("wrong output size", 1, true))
        end
    )
    installed(
        "nupp.digest",
        "sha256",
        function()
            error("loader failure")
        end,
        function()
            local ok, problem = pcall(digest.algorithm, "sha256")
            assert(not ok and tostring(problem):find("loader failure", 1, true))
        end
    )
end

return M
