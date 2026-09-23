-- Reducer execution now belongs to the compact native semantics fixture in
-- simdprimitivedifferentialtest. This suite keeps the generator boundary
-- explicit without compiling the same pack a second time.
local M = {}

function M.compactNativePackOwnsHorizontalMaskedAndLoopReducers()
    local generated = require("tests.simd.native-packs").semantics()
    local groups = {}
    for _, witness in ipairs(generated.coverage) do
        if witness.pack == "reducers" then
            groups[witness.family or witness.group or "horizontal"] = true
        end
    end
    assert(next(groups), "compact native pack has no reducer witnesses")
    local probes = 0
    for module, names in pairs(generated.probes) do
        if module:match("reducer") then
            probes = probes + #names
        end
    end
    assert(probes > 0, "compact native pack has no reducer probes")
end

return M
