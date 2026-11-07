local fixture = require("helpers.templatefixture")
local testAssert = fixture.testAssert
local NUPP = fixture.NUPP
local shell = fixture.shell
local SCAFFOLD_STORE = fixture.SCAFFOLD_STORE
local scaffoldAndVerify = fixture.scaffoldAndVerify
local withDevelopmentRocks = fixture.withDevelopmentRocks

local M = {}

function M.theBrowserSimdTemplateChecksBuildsAndTests()
    -- Its default keeps the scalar kernel as Lua. The package task is what asks
    -- for scalar and SIMD128 AOT, so ordinary init/check/build/test remains a
    -- useful path on a machine that has not installed Emscripten yet.
    scaffoldAndVerify("browser-simd", "sample-browser-simd", nil, function(into)
        withDevelopmentRocks(into)
        local config = assert(loadfile(into .. "/nupp.lua"))()
        testAssert.eq(config.build.targets.scalar.aotFeatures.maximum, "scalar", "the fallback is scalar Wasm AOT")
        testAssert.eq(
            config.build.targets.simd.aotFeatures.minimum,
            "simd128",
            "the fast package requires Wasm SIMD128"
        )
        testAssert.eq(
            config.build.targets.simd.aotFeatures.maximum,
            nil,
            "and names no ceiling above the tier it requires"
        )

        local prefix = "NUPP_CACHE_DIR='"
            .. SCAFFOLD_STORE
            .. "' NUPP="
            .. NUPP
            .. " "
            .. NUPP
            .. " aot --triple wasm32-unknown-emscripten --features "
        local ok, out = shell(prefix .. "scalar '" .. into .. "/src/scalar.nupp'")
        assert(ok, "the scalar browser kernel is not admitted:\n" .. out)
        ok, out = shell(prefix .. "simd128 '" .. into .. "/src/vector_kernel.nupp'")
        assert(
            ok and out:find("explicit simd", 1, true),
            "the SIMD browser kernel did not use explicit vectors:\n" .. out
        )
    end)
end

return M
