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
                fold:add(values[i])
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

-- An int32 and a uint32 are the same Lua number, so the witness alone decides
-- which way a 32-bit fold wraps.
function M.theElementWitnessDecidesHowAnIntegerReducerWraps()
    local array = require("nupp.mem.array")
    local signed = simd.reducer.wrappingSum(array.int32, 2147483647)
    local unsigned = simd.reducer.wrappingSum(array.uint32, 2147483647)
    signed:add(1)
    unsigned:add(1)
    test.equal(signed:value(), -2147483648, "int32 wraps to its minimum")
    test.equal(unsigned:value(), 2147483648, "uint32 keeps counting")
    local wide = simd.reducer.wrappingProduct(array.uint64, 4294967296ULL)
    wide:add(4294967296ULL)
    test.equal(wide:value(), 0ULL, "uint64 wraps modulo 2^64")
    local ok, problem = pcall(simd.reducer.orBits, array.float, 0)
    test.equal(ok, false, "a float witness names no integer reducer")
    assert(tostring(problem):find("array witness", 1, true), tostring(problem))
end

-- As ordinary Lua the species is one lane wide, a vector is that lane's
-- value and a mask a boolean: `false` contributes nothing, and an arg
-- extremum still counts it as a position.
function M.aBooleanMaskSkipsTheContributionAsOrdinaryLua()
    local array = require("nupp.mem.array")
    local total = simd.reducer.orderedSum(0.0)
    total:add(1.0, false)
    total:add(2.0, true)
    total:add(3.0)
    test.equal(total:value(), 5.0, "a false mask contributes nothing to a sum")
    local pairwise = simd.reducer.pairwiseSum(0.0)
    pairwise:add(1.0, false)
    test.equal(pairwise:value(), 0.0, "a false mask adds no leaf")
    local bits = simd.reducer.xorBits(array.uint32, 0)
    bits:add(7, false)
    bits:add(5, true)
    test.equal(bits:value(), 5, "a false mask skips an integer contribution")
    local every = simd.reducer.all()
    every:add(false, false)
    test.equal(every:value(), true, "a false mask leaves a predicate alone")
end

require("jit").off(M.pairwiseFinalizationCarriesOddLeavesToTheNextLevel, true)
return M
