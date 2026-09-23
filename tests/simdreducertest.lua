-- Independent reducer contracts: a level-at-a-time tree, never the runtime's
-- online partial stack, decides the expected association.
local test = require("assert")
local mutation = require("tests.simd.equivalence-mutation")
local simd = require("nupp.simd")
local M = {}

local function tree(values, multiply)
    local level = {}
    for i, value in ipairs(values) do
        level[i] = value
    end
    while #level > 1 do
        local nextLevel = {}
        for i = 1, #level, 2 do
            local right = level[i + 1]
            nextLevel[#nextLevel + 1] = right == nil and level[i] or (multiply and level[i] * right or level[i] + right)
        end
        level = nextLevel
    end

    return level[1]
end

function M.pairwiseFinalizationCarriesOddLeavesToTheNextLevel()
    local cases = {
        {"sum", {1e16, 0, 0, 0, -1e16, 0, 1}},
        {"product", {1e308, 1, 1, 1, 1e308, 1, 1e-308}},
        {"dot", {1e16, 0, 0, 0, 0, 1, 1}},
    }
    for _, case in ipairs(cases) do
        local kind, values = case[1], case[2]
        local fold = kind == "product" and simd.reducer.pairwiseProduct(values[1])
            or kind == "dot" and simd.reducer.pairwiseDot(values[1])
            or simd.reducer.pairwiseSum(values[1])
        for i = 2, #values do
            if kind == "product" then
                fold:multiply(values[i])
            elseif kind == "dot" then
                fold:add(values[i], 1)
            else
                fold:add(values[i])
            end
        end
        local actual = fold:value()
        if kind == "sum" and mutation.active("pairwise-finalization") then
            actual = actual + 1
        end
        test.equal(
            actual,
            tree(values, kind == "product"),
            mutation.active("pairwise-finalization") and mutation.marker("pairwise-finalization", "wrong-result")
            or kind .. " adjacent-pair tree"
        )
    end
end

require("jit").off(M.pairwiseFinalizationCarriesOddLeavesToTheNextLevel, true)
return M
