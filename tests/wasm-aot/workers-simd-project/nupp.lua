local function target(output, outDir, features)
    return {
        kind = "bundle",
        entries = {"main"},
        sources = {"src"},
        output = output,
        outDir = outDir,
        dialect = "lua51",
        backends = {"nupp.runtime.backend.browser"},
        aot = "require-wasm",
        aotFeatures = features,
    }
end

return {
    include = {"src"},
    build = {
        outDir = "build",
        default = "scalar",
        targets = {
            scalar = target("dist/scalar.lua", "build/scalar", "scalar"),
            simd = target("dist/simd.lua", "build/simd", "simd128"),
        },
    },
}
