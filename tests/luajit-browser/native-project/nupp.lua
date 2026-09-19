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
                host = "browser",
                aot = "require",
                aotTarget = "i686-unknown-linux-gnu",
                aotFeatures = "baseline",
            }
        }
    },
}
