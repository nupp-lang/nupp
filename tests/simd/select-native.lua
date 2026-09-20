local runner = require("tests.simd.runner")

local function csv(text, numeric)
    local result = {}
    for value in text:gmatch("[^,]+") do
        result[#result + 1] = numeric and (tonumber(value) or value) or value
    end

    return result
end

local lanes = csv(assert(arg[7]), true)
if lanes[1] == "all" then
    lanes = {};
    for width = 2, 64 do
        lanes[#lanes + 1] = width
    end;
    lanes[#lanes + 1] = "preferred"
end
local algorithms = csv(assert(arg[6]));
if #algorithms == 1 and algorithms[1] == "none" then
    algorithms = {}
end
local selection = require(
    "tests.simd.native-inventory"
).selection{
    compilers = csv(assert(arg[2])),
    tiers = csv(assert(arg[3])),
    families = csv(assert(arg[4])),
    types = csv(assert(arg[5])),
    algorithms = algorithms,
    lanes = lanes,
}
runner.writeJson(assert(arg[1]) .. "/selection.json", selection)
