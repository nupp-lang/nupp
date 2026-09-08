local system = require("nupp.system")
local crypto = require("nupp.crypto")
local uuid = require("nupp.uuid")
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
        assert(#crypto.randomBytes(count) == count)
    end
    for _, count in ipairs({-1, 0.5, 1048577, math.huge, 0 / 0}) do
        assert(not pcall(crypto.randomBytes, count))
    end
    assert(crypto.sha256 == nil and crypto.uuid4 == nil and crypto.hmacSha256 == nil)
end

function M.identifiersHaveTheirOwnNamespace()
    assert(uuid.v4():match("^%x%x%x%x%x%x%x%x%-%x%x%x%x%-4%x%x%x%-[89ab]%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$"))
    assert(uuid.v7():match("^%x%x%x%x%x%x%x%x%-%x%x%x%x%-7%x%x%x%-[89ab]%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$"))
    assert(uuid.uuid4 == nil and uuid.uuid7 == nil)
end

return M
