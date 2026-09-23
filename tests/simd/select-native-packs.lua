local runner = require("tests.simd.runner")

local function csv(text)
    local result = {}
    for value in text:gmatch("[^,]+") do
        result[#result + 1] = value
    end

    return result
end

local algorithms = csv(assert(arg[4]))
if #algorithms == 1 and algorithms[1] == "none" then
    algorithms = {}
end
runner.writeJson(assert(arg[1]) .. "/selection.json", {
    schemaVersion = 1,
    compilers = csv(assert(arg[2])),
    tiers = csv(assert(arg[3])),
    packs = {"species", "semantics"},
    algorithms = algorithms,
    buildModel = {
        harnessCommandsPerCompilerTier = 1,
        nativePackBuildsPerCompilerTier = 2,
        legacyCartesianBuildsPerCompilerTier = 20,
    },
})
