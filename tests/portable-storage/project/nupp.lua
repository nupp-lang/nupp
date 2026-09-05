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
                dialect = "lua51",
                backends = {"nupp.runtime.backend.browser"},
            }
        }
    },
}
