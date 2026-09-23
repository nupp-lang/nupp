local test = require("nupp.test")
local M = {}

local decode = assert(loadfile("src/nupp/runtime/vendor/lunajson/decoder.lua"))()()

local function json(path)
    local file = assert(io.open(path, "rb"))
    local value = decode(file:read("*a"))
    file:close()
    return value
end

local EXPECTED = {
    ["aarch64-pc-windows-msvc"] = "unsupported-native-toolchain",
    ["i686-pc-windows-msvc"] = "unsupported-native-toolchain",
    ["i686-unknown-linux-gnu"] = "not-executed",
}

local boundaries = json("tests/simd/runtime-boundaries.json")
local cases = test.cases(
    boundaries,
    function(boundary)
        return boundary.target:gsub("[^%w]", "_")
    end,
    function(boundary)
        test.equal(EXPECTED[boundary.target], boundary.status)
        test.assert(type(boundary.reason) == "string" and boundary.reason ~= "")
        test.assert(type(boundary.evidence) == "table" and #boundary.evidence > 0)
        test.fact("coverage.witness", {
            id = "runtime-boundary/" .. boundary.target .. "/" .. boundary.status,
            obligation = "simd.runtime-boundary",
            dimensions = {target = boundary.target, status = boundary.status},
        })
    end
)

for name, case in pairs(cases) do
    M[name] = case
end

function M.inventoryIsExact()
    test.equal(#boundaries, 3)
    for target in pairs(EXPECTED) do
        local found = false
        for _, boundary in ipairs(boundaries) do
            found = found or boundary.target == target
        end
        test.assert(found, "missing runtime boundary " .. target)
    end
end

return M
