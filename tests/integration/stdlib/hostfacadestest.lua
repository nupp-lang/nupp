local system = os.info()
local random = require("math.random")
local uuid = os
local providerstate = require("helpers.providerstate")
local targetLayout = require("nupp.compiler.targetlayout")
local M = {}

function M.randomNamespaceForwardsTheHostCallExactly()
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
    local load = providerstate.instance({["math.random"] = true}, nil, nil, {math = host})
    local moved = load("math.random")
    assert(moved == host.random and moved == load("math.random"))
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
    assert(uuid.uuid4():match("^%x%x%x%x%x%x%x%x%-%x%x%x%x%-4%x%x%x%-[89ab]%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$"))
    assert(uuid.uuid7():match("^%x%x%x%x%x%x%x%x%-%x%x%x%x%-7%x%x%x%-[89ab]%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$"))
    assert(uuid.v4 == nil and uuid.v7 == nil, "the old nested spelling is gone")
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

return M
