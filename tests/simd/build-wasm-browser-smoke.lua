-- Build one representative SIMD kernel plus the runtime-sensitive counted
-- corpus for the real single-number browser guest.
local output = assert(arg[1], "output directory required")
local generated = require("tests.simd.primitives").generate({
    target = "wasm",
    types = {"int32"},
    lanes = {4},
    families = {"lanes"},
})
local counted = require("tests.simd.counted").generate()
for path, contents in pairs(counted.files) do
    assert(generated.files[path] == nil, "duplicate browser smoke source " .. path)
    generated.files[path] = contents
end
for module, names in pairs(counted.probes) do
    assert(generated.probes[module] == nil, "duplicate browser smoke probe " .. module)
    generated.probes[module] = names
end
for _, coverage in ipairs(counted.coverage) do
    generated.coverage[#generated.coverage + 1] = coverage
end
local primitiveEntry = generated.entry
generated.entry = "simd_browser_smoke"
generated.files[
    generated.entry .. ".nupp"
] = (
    [[
local primitive = require(%q)
local counted = require(%q)
local function run(): number
    return primitive.run() + counted.run()
end
return {run=run}
]]
):format(primitiveEntry, counted.entry)
require("tests.simd.runner").wasm(generated, {directory = output})
