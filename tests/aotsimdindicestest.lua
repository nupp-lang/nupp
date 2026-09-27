local simdindices = require("nupp.compiler.aot.simdindices")

local M = {}

local function iota(valueType, first, step)
    return {
        op = "simd_iota",
        args = {
            {op = "constant_i32", type = "i32", value = tostring(first)},
            {op = "constant_i32", type = "i32", value = tostring(step)},
        },
        type = valueType,
    }
end

function M.preferredProofUsesTheWidestTargetLaneCount()
    assert(simdindices.unique(iota("simd_vector_i32_preferred", 2147483632, 1)))
    assert(not simdindices.unique(iota("simd_vector_i32_preferred", 2147483633, 1)))
end

function M.rejectsMalformedIndexTypes()
    assert(not simdindices.unique(iota("simd_vector_i16_preferred", 1, 1)))
    assert(simdindices.matches("simd_vector_i32_fixed4", "simd_species_f64_fixed4"))
    assert(not simdindices.matches("simd_vector_i32_fixed4x", "simd_species_f64_fixed4x"))
    assert(not simdindices.matches("simd_vector_i32_fixed4", "simd_species_f128_fixed4"))
end

return M
