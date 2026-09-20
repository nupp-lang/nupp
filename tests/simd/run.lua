-- A single generated corpus batch. Matrix orchestration chooses the compiler
-- and exact tier; Wasm packaging consumes these identical generated files.
local runner = require("tests.simd.runner")
local mode, family, output = assert(arg[1]), assert(arg[2]), assert(arg[3])
assert(mode == "native" or mode == "wasm", "mode must be native or wasm")
assert(family == "primitives" or family == "reducers", "unknown SIMD corpus")

local function list(value, numeric)
    if not value or value == "" then
        return nil
    end
    local values = {}
    for entry in value:gmatch("[^,]+") do
        values[#values + 1] = numeric and (tonumber(entry) or entry) or entry
    end

    return values
end

local options = {types = list(os.getenv("NUPP_SIMD_TYPES")), lanes = list(os.getenv("NUPP_SIMD_LANES"), true),}
local generated = require("tests.simd." .. family).generate(options)
if mode == "native" then
    local report = runner.native(generated, {directory = output})
    runner.writeJson(output .. "/matrix-result.json", report)
    print(family .. ": " .. report.cases .. " cases, " .. report.probes .. " native probes, tier " .. report.tier)
else
    runner.wasm(generated, {directory = output})
    print(output)
end
