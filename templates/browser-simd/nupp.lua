local function target(entry, output, outDir, features)
    return {
        kind = "bundle",
        entries = {entry},
        sources = {"src/" .. entry .. ".nupp"},
        output = output,
        outDir = outDir,
        dialect = "lua51",
        dependencies = {"lunajson"},
        backends = {"nupp.runtime.backend.browser"},
        aot = features and "require-wasm" or "off",
        aotFeatures = features,
    }
end

return {
    include = {"src"},

    dependencies = {
        lunajson = {kind = "luarocks", version = "1.2.3-1", bundle = {"lunajson.lua", "lunajson/**.lua"},},
    },

    build = {
        outDir = "build",
        default = "app",
        targets = {
            app = target("scalar", "dist/app.lua", "build/app"),
            scalar = target("scalar", "dist/scalar.lua", "build/scalar", "scalar"),
            simd = target("simd", "dist/simd.lua", "build/simd", "simd128"),
        },
    },

    test = {build = "app", argv = {"node", "tests/build.test.mjs"},},

    tasks = {
        package = {description = "Build scalar and SIMD128 browser packages", argv = {"sh", "scripts/package.sh"},},
        serve = {
            description = "Serve the dual package on localhost:8787",
            argv = {"node", "scripts/serve.mjs", "dist/browser"},
        },
    },
}
