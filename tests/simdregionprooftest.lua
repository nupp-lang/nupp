local proof = require("tests.simd.regionproof")
local M = {}
local files = {["sample.nupp"] = [[local function fold()
    @simd
    for i = 1, 8 do end
    @simd
    for i = 1, 16 do end
end
]]}
local units = {units = {{source = "src/sample.neon.c", tier = "neon", detector = false}}}
local scalar = [[KS_API void ks_ab_fold_forced_scalar__neon(void) {
    for (int i = 0; i < 8; i++) consume(i);
}
]]
local vector = [[KS_API void ks_ab_fold__neon(void) {
    uint32_t sr0_base1 = UINT32_C(0);
    ks_exp_mask_f64x2 sr0_active2;
    sr0_base1 = sr0_base1 + UINT32_C(2);
    uint32_t sr1_base1 = UINT32_C(0);
    ks_exp_mask_f64x4 sr1_active2;
    sr1_base1 = sr1_base1 + UINT32_C(4);
}
]]
local function verify(text)
    return proof.verify(proof.inventory(files), units, "neon", function() return text end)
end
function M.recordsEveryAuthoredRegionAndItsArtifact()
    local got = verify(scalar .. vector)
    assert(got.regions == 2 and #got.functions == 1)
    assert(got.functions[1].symbol == "ks_ab_fold__neon")
    assert(got.functions[1].annotations[1] == 2 and got.functions[1].annotations[2] == 4)
end
function M.rejectsAScalarEntryWithAnUnrelatedVectorHelper()
    assert(not pcall(verify, scalar .. vector:gsub("uint32_t sr1_base1 = UINT32_C%(0%);", "")))
end
function M.rejectsMissingScalarTwinOrSharedVectorBody()
    assert(not pcall(verify, vector))
    assert(not pcall(verify, scalar:gsub("consume%(i%)", "ks_exp_helper(i)") .. vector))
end
function M.rejectsWrongGangProgressAndMissingTail()
    assert(not pcall(verify, scalar .. vector:gsub("sr1_base1 %+ UINT32_C%(4%)", "sr1_base1 + UINT32_C(1)")))
    assert(not pcall(verify, scalar .. vector:gsub("ks_exp_mask_f64x4 sr1_active2;", "")))
end
function M.rejectsAMissingTierArtifact()
    assert(not pcall(proof.verify, proof.inventory(files), units, "simd128", function() return scalar .. vector end))
end
return M
