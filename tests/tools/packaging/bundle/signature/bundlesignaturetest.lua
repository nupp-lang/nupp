local fixture = require("helpers.bundlefixture")
local packaging = fixture.packaging
local tempProject = fixture.tempProject
local readFile = fixture.readFile

local test = require("helpers.bundlefixture").test
local EXECUTABLE = require("helpers.bundlefixture").EXECUTABLE
local BUILT = require("helpers.bundlefixture").BUILT

local M = {}

function M.machOPackagingReplacesTheStubSignatureWithASignableLayout()
    local function little(value, width)
        local bytes = {}
        for index = 1, width do
            bytes[index] = string.char(value % 256)
            value = math.floor(value / 256)
        end

        return table.concat(bytes)
    end

    local header = "\207\250\237\254" .. little(
        0x0100000c,
        4
    ) .. little(0, 4) .. little(2, 4) .. little(2, 4) .. little(88, 4) .. little(0, 4) .. little(0, 4)
    local linkedit = little(
        0x19,
        4
    ) .. little(
        72,
        4
    ) .. "__LINKEDIT" .. (
        "\0"
    ):rep(
        6
    ) .. little(
        0x1000,
        8
    ) .. little(
        0x1000,
        8
    ) .. little(120, 8) .. little(8, 8) .. little(1, 4) .. little(1, 4) .. little(0, 4) .. little(0, 4)
    local signature = little(0x1d, 4) .. little(16, 4) .. little(120, 4) .. little(8, 4)
    local stub = header .. linkedit .. signature .. "SIGNHERE"
    local bytes = assert(packaging.stampBinary(stub, "return true\n", 0, true))
    assert(bytes:sub(-48, -41) == "NUPPLOAD", "the unsigned trailer ends the stamped file")
    assert(bytes:sub(17, 20) == little(1, 4), "the old signature load command is removed")
    assert(bytes:sub(21, 24) == little(72, 4), "the load-command byte count is updated")
    assert(
        bytes:sub(81, 88) == little(#bytes - 120, 8),
        "__LINKEDIT covers the payload and trailer for the next signer"
    )
end

return M
