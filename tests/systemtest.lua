local system = require("nupp.system")
local random = require("nupp.random")
local uuid = require("nupp.util")
local providerstate = require("providerstate")
local ffi = require("ffi")
local M = {}

function M.systemReportsExecutingAbiWithoutWorkers()
    assert(type(system.platform) == "string" and #system.platform > 0)
    assert(type(system.architecture) == "string" and #system.architecture > 0)
    assert(system.pointerBits == ffi.sizeof("void *") * 8)
    assert(system.endianness == (ffi.abi("le") and "little" or "big"))
    local count = system.availableParallelism()
    assert(type(count) == "number" and count >= 1 and count == math.floor(count))
end

function M.secureRandomBytesSizesAndValidation()
    for _, count in ipairs({0, 1, 32, 4096}) do
        assert(#random.randomBytes(count) == count)
    end
    for _, count in ipairs({-1, 0.5, 1048577, math.huge, 0 / 0}) do
        assert(not pcall(random.randomBytes, count))
    end
    assert(random.sha256 == nil and random.uuid4 == nil and random.hmacSha256 == nil)
end

function M.identifiersAreMembersOfTheUtilNamespace()
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
            ["nupp.runtime.uuid"] = {
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
        ["nupp.runtime.uuid"] = {
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
        ["nupp.runtime.uuid"] = {
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
