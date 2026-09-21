return {
    include = {"src"},
    build = {
        targets = {
            app = {
                kind = "bundle",
                entries = {"main"},
                sources = {"src"},
                output = "dist/app.lua",
                outDir = "build/app",
                dialect = "luajit",
                host = "browser",

                aot = "require-wasm",
                aotFeatures = {minimum = "simd128"},
            },
        },
    },
}
